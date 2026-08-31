#!/usr/bin/env python3
"""Validate the workstation's reproducibility inputs."""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import shutil
import subprocess
import sys
import tempfile
import urllib.request
from pathlib import Path
from urllib.parse import urlsplit


ROOT = Path(__file__).resolve().parents[1]
LOCKS = {
    "evm-core": ROOT / "toolchains" / "evm-core.lock.json",
    "solana-core": ROOT / "toolchains" / "solana-core.lock.json",
}
PYTHON_LOCK = ROOT / "toolchains" / "python-requirements.lock"
SHA256 = re.compile(r"^[0-9a-f]{64}$")
TRUSTED_HOSTS = {"github.com", "nodejs.org"}
EXPECTED_ARTIFACTS = {
    "evm-core": {"foundry", "node", "bun", "echidna", "uv", "solc"},
    "solana-core": {"surfpool"},
}


def fail(message: str) -> None:
    raise ValueError(message)


def verify_lock(profile: str, path: Path, download: bool) -> None:
    lock = json.loads(path.read_text(encoding="utf-8"))
    if lock.get("schema") != 1 or lock.get("profile") != profile:
        fail(f"unexpected lockfile schema or profile: {path}")
    if lock.get("platform") != "linux-x86_64":
        fail(f"lockfile must target linux-x86_64: {path}")

    ids: set[str] = set()
    commands: set[str] = set()
    for artifact in lock.get("artifacts", []):
        artifact_id = artifact.get("id", "")
        version = artifact.get("version", "")
        url = artifact.get("url", "")
        digest = artifact.get("sha256", "")
        if not artifact_id or artifact_id in ids:
            fail(f"duplicate or empty artifact id: {artifact_id!r}")
        ids.add(artifact_id)
        parsed = urlsplit(url)
        if parsed.scheme != "https" or parsed.hostname not in TRUSTED_HOSTS:
            fail(f"untrusted artifact URL for {artifact_id}: {url}")
        if "latest" in parsed.path.lower() or str(version).lstrip("v") not in parsed.path:
            fail(f"artifact URL is not version-pinned for {artifact_id}")
        if not SHA256.fullmatch(str(digest)):
            fail(f"invalid SHA-256 for {artifact_id}")
        bins = artifact.get("bins", {})
        if not isinstance(bins, dict) or not bins:
            fail(f"artifact has no declared binaries: {artifact_id}")
        for command, relative in bins.items():
            if command in commands and not (artifact_id == "bun" and command == "bunx"):
                fail(f"duplicate command mapping: {command}")
            commands.add(command)
            if Path(relative).is_absolute() or ".." in Path(relative).parts:
                fail(f"unsafe binary path for {artifact_id}: {relative}")
        if download:
            print(f"downloading {artifact_id} {version} for checksum verification", flush=True)
            hasher = hashlib.sha256()
            if shutil.which("curl"):
                with tempfile.NamedTemporaryFile() as download_file:
                    subprocess.run(
                        [
                            "curl",
                            "--proto",
                            "=https",
                            "--tlsv1.2",
                            "--fail",
                            "--location",
                            "--retry",
                            "3",
                            "--connect-timeout",
                            "10",
                            "--max-time",
                            "300",
                            "--output",
                            download_file.name,
                            url,
                        ],
                        check=True,
                    )
                    download_file.seek(0)
                    while chunk := download_file.read(1024 * 1024):
                        hasher.update(chunk)
            else:
                with urllib.request.urlopen(url, timeout=30) as response:
                    while chunk := response.read(1024 * 1024):
                        hasher.update(chunk)
            if hasher.hexdigest() != digest:
                fail(f"downloaded checksum mismatch for {artifact_id}")

    required = EXPECTED_ARTIFACTS[profile]
    if ids != required:
        fail(f"artifact set differs from {profile} contract: {sorted(ids)}")
    if profile == "evm-core":
        python = lock.get("python", {})
        if python.get("packages") != {
            "crytic-compile": "0.4.2",
            "slither": "0.11.6",
            "solc-select": "1.2.0",
        }:
            fail("Python top-level versions differ from the reviewed set")
        if not PYTHON_LOCK.is_file():
            fail("Python requirements lock is missing")
        requirements = PYTHON_LOCK.read_text(encoding="utf-8")
        for requirement in ("crytic-compile==0.4.2", "slither-analyzer==0.11.6", "solc-select==1.2.0"):
            if requirement not in requirements:
                fail(f"Python lock is missing {requirement}")
        if "--hash=sha256:" not in requirements:
            fail("Python lock does not contain hashes")


def verify(download: bool) -> None:
    for profile, path in LOCKS.items():
        verify_lock(profile, path, download)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--download", action="store_true", help="download and hash every binary artifact")
    args = parser.parse_args()
    try:
        verify(args.download)
    except (ValueError, OSError, json.JSONDecodeError) as exc:
        print(f"verify-lock: {exc}", file=sys.stderr)
        return 1
    print("toolchain locks verified")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
