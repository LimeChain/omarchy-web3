#!/usr/bin/env python3
"""Download one locked artifact with bounded I/O and an explicit origin policy."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import resource
import shutil
import ssl
import sys
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path
from typing import Any, BinaryIO


CHUNK_SIZE = 1024 * 1024
MAX_REDIRECTS = 3
REDIRECT_CODES = {301, 302, 303, 307, 308}


class DownloadError(RuntimeError):
    pass


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(
        self,
        req: urllib.request.Request,
        fp: BinaryIO,
        code: int,
        msg: str,
        headers: Any,
        newurl: str,
    ) -> None:
        return None


def validate_url(url: str, allowed_hosts: set[str]) -> str:
    try:
        parsed = urllib.parse.urlsplit(url)
        port = parsed.port
    except ValueError as exc:
        raise DownloadError("malformed artifact URL") from exc
    hostname = (parsed.hostname or "").lower()
    if parsed.scheme != "https" or hostname not in allowed_hosts:
        raise DownloadError(f"artifact URL violates the HTTPS origin policy: {hostname or 'missing host'}")
    if parsed.username or parsed.password or parsed.fragment or port not in {None, 443}:
        raise DownloadError("artifact URL contains forbidden authority or fragment data")
    return urllib.parse.urlunsplit(parsed)


def open_with_policy(
    url: str,
    allowed_hosts: set[str],
    *,
    timeout: float,
    opener: Any | None = None,
) -> Any:
    current = validate_url(url, allowed_hosts)
    active_opener = opener or urllib.request.build_opener(
        urllib.request.HTTPSHandler(context=ssl.create_default_context()), NoRedirect()
    )
    for redirects in range(MAX_REDIRECTS + 1):
        request = urllib.request.Request(
            current,
            method="GET",
            headers={"Accept": "application/octet-stream", "User-Agent": "limechain-web3-installer/1"},
        )
        try:
            response = active_opener.open(request, timeout=timeout)
        except urllib.error.HTTPError as exc:
            if exc.code not in REDIRECT_CODES:
                raise DownloadError(f"artifact server returned HTTP {exc.code}") from exc
            location = exc.headers.get("Location", "")
            exc.close()
            if not location:
                raise DownloadError("artifact redirect omitted Location")
            if redirects == MAX_REDIRECTS:
                raise DownloadError("artifact exceeded the redirect limit")
            current = validate_url(urllib.parse.urljoin(current, location), allowed_hosts)
            continue
        final_url = validate_url(response.geturl(), allowed_hosts)
        if final_url != current:
            response.close()
            raise DownloadError("HTTP client followed an unvalidated redirect")
        return response
    raise DownloadError("artifact exceeded the redirect limit")


def verify_existing(path: Path, expected_size: int, expected_sha256: str) -> bool:
    try:
        info = path.lstat()
    except FileNotFoundError:
        return False
    if (
        not path.is_file()
        or path.is_symlink()
        or info.st_nlink != 1
        or info.st_uid != os.getuid()
        or info.st_size != expected_size
    ):
        return False
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        while chunk := handle.read(CHUNK_SIZE):
            digest.update(chunk)
    return digest.hexdigest() == expected_sha256


def stream_download(
    response: Any,
    output: Path,
    expected_size: int,
    expected_sha256: str,
) -> None:
    length = response.headers.get("Content-Length")
    if length is not None:
        try:
            declared = int(length)
        except ValueError as exc:
            raise DownloadError("artifact returned an invalid Content-Length") from exc
        if declared != expected_size:
            raise DownloadError(
                f"artifact size differs from lock: expected {expected_size}, server declared {declared}"
            )

    free = shutil.disk_usage(output.parent).free
    if free < expected_size + 16 * 1024 * 1024:
        raise DownloadError("insufficient free disk space for the bounded artifact download")

    temp = output.parent / f".{output.name}.part.{os.getpid()}"
    flags = os.O_WRONLY | os.O_CREAT | os.O_EXCL
    if hasattr(os, "O_NOFOLLOW"):
        flags |= os.O_NOFOLLOW
    descriptor = os.open(temp, flags, 0o600)
    old_limit = resource.getrlimit(resource.RLIMIT_FSIZE)
    hard_limit = old_limit[1]
    effective_limit = expected_size if hard_limit == resource.RLIM_INFINITY else min(expected_size, hard_limit)
    digest = hashlib.sha256()
    written = 0
    try:
        resource.setrlimit(resource.RLIMIT_FSIZE, (effective_limit, hard_limit))
        with os.fdopen(descriptor, "wb", closefd=True) as handle:
            while chunk := response.read(CHUNK_SIZE):
                written += len(chunk)
                if written > expected_size:
                    raise DownloadError("artifact exceeded its locked byte limit")
                handle.write(chunk)
                digest.update(chunk)
            handle.flush()
            os.fsync(handle.fileno())
        if written != expected_size:
            raise DownloadError(f"artifact was truncated: expected {expected_size} bytes, received {written}")
        if digest.hexdigest() != expected_sha256:
            raise DownloadError("artifact SHA-256 differs from the reviewed lock")
        os.replace(temp, output)
    finally:
        resource.setrlimit(resource.RLIMIT_FSIZE, old_limit)
        try:
            temp.unlink()
        except FileNotFoundError:
            pass


def artifact_from_lock(lock_path: Path, artifact_id: str) -> dict[str, Any]:
    lock = json.loads(lock_path.read_text(encoding="utf-8"))
    matches = [item for item in lock.get("artifacts", []) if item.get("id") == artifact_id]
    if len(matches) != 1:
        raise DownloadError(f"artifact is not uniquely declared in lock: {artifact_id}")
    artifact = matches[0]
    required = {"url", "sha256", "size", "redirect_hosts"}
    if not required.issubset(artifact):
        raise DownloadError(f"artifact lock is missing bounded-download metadata: {artifact_id}")
    return artifact


def download_locked(lock_path: Path, artifact_id: str, output: Path, *, timeout: float = 30) -> None:
    artifact = artifact_from_lock(lock_path, artifact_id)
    expected_size = artifact["size"]
    expected_sha256 = artifact["sha256"]
    allowed_hosts = set(artifact["redirect_hosts"])
    if not isinstance(expected_size, int) or expected_size <= 0:
        raise DownloadError("locked artifact size must be a positive integer")
    if not isinstance(expected_sha256, str) or len(expected_sha256) != 64:
        raise DownloadError("locked artifact SHA-256 is invalid")
    if not allowed_hosts or not all(isinstance(host, str) and host for host in allowed_hosts):
        raise DownloadError("locked redirect host policy is invalid")

    output.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    if output.is_symlink():
        raise DownloadError("refusing a symlink artifact-cache target")
    if verify_existing(output, expected_size, expected_sha256):
        return
    if output.exists():
        output.unlink()

    response = open_with_policy(artifact["url"], allowed_hosts, timeout=timeout)
    try:
        stream_download(response, output, expected_size, expected_sha256)
    finally:
        response.close()


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--lock", required=True, type=Path)
    parser.add_argument("--artifact", required=True)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    try:
        download_locked(args.lock, args.artifact, args.output)
    except (DownloadError, OSError, ValueError, json.JSONDecodeError) as exc:
        print(f"safe-download: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
