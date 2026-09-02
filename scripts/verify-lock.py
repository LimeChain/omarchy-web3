#!/usr/bin/env python3
"""Validate the workstation's reproducibility inputs."""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
from pathlib import Path
from urllib.parse import urlsplit


ROOT = Path(__file__).resolve().parents[1]
LOCKS = {
    "evm-core": ROOT / "toolchains" / "evm-core.lock.json",
    "solana-core": ROOT / "toolchains" / "solana-core.lock.json",
    "hedera-core": ROOT / "toolchains" / "hedera-core.lock.json",
}
PYTHON_LOCK = ROOT / "toolchains" / "python-requirements.lock"
SHA256 = re.compile(r"^[0-9a-f]{64}$")
TRUSTED_HOSTS = {"github.com", "nodejs.org"}
EXPECTED_ARTIFACTS = {
    "evm-core": {"foundry", "node", "bun", "echidna", "uv", "solc"},
    "solana-core": {"surfpool", "agave", "anchor", "platform-tools"},
    "hedera-core": set(),
}


def fail(message: str) -> None:
    raise ValueError(message)


def verify_lock(profile: str, path: Path, download: bool) -> None:
    lock = json.loads(path.read_text(encoding="utf-8"))
    if lock.get("schema") != 2 or lock.get("profile") != profile:
        fail(f"unexpected lockfile schema or profile: {path}")
    expected_platform = "any" if profile == "hedera-core" else "linux-x86_64"
    if lock.get("platform") != expected_platform:
        fail(f"lockfile must target {expected_platform}: {path}")

    ids: set[str] = set()
    commands: set[str] = set()
    for artifact in lock.get("artifacts", []):
        artifact_id = artifact.get("id", "")
        version = artifact.get("version", "")
        url = artifact.get("url", "")
        digest = artifact.get("sha256", "")
        size = artifact.get("size")
        redirect_hosts = artifact.get("redirect_hosts")
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
        if not isinstance(size, int) or size <= 0:
            fail(f"artifact has no positive locked byte size: {artifact_id}")
        if (
            not isinstance(redirect_hosts, list)
            or parsed.hostname not in redirect_hosts
            or not all(host in {"github.com", "release-assets.githubusercontent.com", "nodejs.org"} for host in redirect_hosts)
        ):
            fail(f"artifact has an invalid redirect-origin policy: {artifact_id}")
        archive = artifact.get("archive")
        if archive != "raw":
            extraction = artifact.get("extraction")
            if not isinstance(extraction, dict):
                fail(f"archive has no extraction policy: {artifact_id}")
            for field in ("max_entries", "max_unpacked_bytes", "max_file_bytes"):
                if not isinstance(extraction.get(field), int) or extraction[field] <= 0:
                    fail(f"archive has invalid {field}: {artifact_id}")
            allowed_top = extraction.get("allowed_top_level")
            if not isinstance(allowed_top, list) or not allowed_top:
                fail(f"archive has no allowed top-level entries: {artifact_id}")
        bins = artifact.get("bins", {})
        if not isinstance(bins, dict) or not bins:
            fail(f"artifact has no declared binaries: {artifact_id}")
        for command, relative in bins.items():
            if command in commands and not (artifact_id == "bun" and command == "bunx"):
                fail(f"duplicate command mapping: {command}")
            commands.add(command)
            if Path(relative).is_absolute() or ".." in Path(relative).parts:
                fail(f"unsafe binary path for {artifact_id}: {relative}")
        links = artifact.get("materialized_symlinks", {})
        if not isinstance(links, dict):
            fail(f"materialized_symlinks must be an object: {artifact_id}")
        for link, target in links.items():
            for value in (link, target):
                path_value = Path(value)
                if path_value.is_absolute() or ".." in path_value.parts or not path_value.parts:
                    fail(f"unsafe materialized symlink path for {artifact_id}: {value}")
        source_artifact = artifact.get("source_artifact")
        if source_artifact is not None:
            source_url = urlsplit(str(source_artifact.get("url", "")))
            if source_url.scheme != "https" or source_url.hostname not in TRUSTED_HOSTS:
                fail(f"derived artifact has an untrusted source: {artifact_id}")
            if not SHA256.fullmatch(str(source_artifact.get("sha256", ""))):
                fail(f"derived artifact has an invalid source SHA-256: {artifact_id}")
            if not isinstance(source_artifact.get("size"), int) or source_artifact["size"] <= 0:
                fail(f"derived artifact has an invalid source size: {artifact_id}")
            if source_artifact.get("transform") != "scripts/sanitize-upstream-archive.py":
                fail(f"derived artifact has an unexpected transform: {artifact_id}")
            omitted = source_artifact.get("omitted_symlinks")
            if not isinstance(omitted, list) or not omitted:
                fail(f"derived artifact has no explicit omitted-symlink set: {artifact_id}")
        if download:
            print(f"downloading {artifact_id} {version} for checksum verification", flush=True)
            import importlib.util
            import tempfile

            helper_path = ROOT / "scripts" / "safe-download.py"
            spec = importlib.util.spec_from_file_location("safe_download", helper_path)
            if spec is None or spec.loader is None:
                fail("safe downloader could not be loaded")
            helper = importlib.util.module_from_spec(spec)
            spec.loader.exec_module(helper)
            with tempfile.TemporaryDirectory() as directory:
                output = Path(directory) / artifact_id
                helper.download_locked(path, artifact_id, output)
                if output.stat().st_size != size or hashlib.sha256(output.read_bytes()).hexdigest() != digest:
                    fail(f"downloaded artifact differs from the reviewed lock: {artifact_id}")

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
