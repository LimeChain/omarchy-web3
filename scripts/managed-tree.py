#!/usr/bin/env python3
"""Collision-safe lifecycle for a small, explicitly owned file tree."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import shutil
import stat
import sys
import tempfile
from pathlib import Path
from typing import Any


MARKER = ".limechain-web3-managed.json"


class ManagedTreeError(RuntimeError):
    pass


def normalized(path: Path) -> Path:
    if not path.is_absolute():
        raise ManagedTreeError(f"managed path must be absolute: {path}")
    return Path(os.path.normpath(path))


def assert_contained(path: Path, root: Path) -> tuple[Path, Path]:
    target = normalized(path)
    boundary = normalized(root)
    if target == boundary or boundary not in target.parents:
        raise ManagedTreeError(f"managed path escapes its declared boundary: {target}")
    return target, boundary


def check_existing_components(path: Path, root: Path, uid: int) -> None:
    target, boundary = assert_contained(path, root)
    for current in (boundary, *reversed(target.parents[: target.parents.index(boundary)]), target):
        try:
            info = current.lstat()
        except FileNotFoundError:
            continue
        if stat.S_ISLNK(info.st_mode):
            raise ManagedTreeError(f"managed path contains a symlink component: {current}")
        if info.st_uid != uid:
            raise ManagedTreeError(f"managed path component is not owned by uid {uid}: {current}")


def secure_mkdirs(path: Path, root: Path, uid: int) -> None:
    target, boundary = assert_contained(path, root)
    check_existing_components(target, boundary, uid)
    missing: list[Path] = []
    current = target
    while not current.exists():
        missing.append(current)
        current = current.parent
    for directory in reversed(missing):
        directory.mkdir(mode=0o700)
    check_existing_components(target, boundary, uid)


def hash_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        while chunk := handle.read(1024 * 1024):
            digest.update(chunk)
    return digest.hexdigest()


def inventory(root: Path, *, include_marker: bool = False) -> list[dict[str, Any]]:
    entries: list[dict[str, Any]] = []
    for path in sorted(root.rglob("*")):
        relative = path.relative_to(root).as_posix()
        if not include_marker and relative == MARKER:
            continue
        info = path.lstat()
        if stat.S_ISLNK(info.st_mode):
            raise ManagedTreeError(f"managed tree contains a symlink: {relative}")
        if stat.S_ISDIR(info.st_mode):
            entries.append({"path": relative, "type": "directory", "mode": stat.S_IMODE(info.st_mode)})
        elif stat.S_ISREG(info.st_mode):
            if info.st_nlink != 1:
                raise ManagedTreeError(f"managed tree contains a hard-linked file: {relative}")
            entries.append(
                {
                    "path": relative,
                    "type": "file",
                    "mode": stat.S_IMODE(info.st_mode),
                    "sha256": hash_file(path),
                    "size": info.st_size,
                }
            )
        else:
            raise ManagedTreeError(f"managed tree contains a special file: {relative}")
    return entries


def marker_payload(root: Path, scope: str, uid: int) -> dict[str, Any]:
    return {
        "schema": 1,
        "owner": "limechain.web3",
        "scope": scope,
        "uid": uid,
        "entries": inventory(root),
    }


def verify(root: Path, scope: str, uid: int) -> dict[str, Any]:
    check_existing_components(root, root.parent.parent.parent if scope == "agent-skill" else root.parent, uid)
    marker_path = root / MARKER
    if stat.S_IMODE(root.lstat().st_mode) != 0o700:
        raise ManagedTreeError(f"managed tree root has unsafe permissions: {root}")
    try:
        marker_info = marker_path.lstat()
    except FileNotFoundError as exc:
        raise ManagedTreeError(f"existing destination is not marked as managed: {root}") from exc
    if not stat.S_ISREG(marker_info.st_mode) or stat.S_ISLNK(marker_info.st_mode) or marker_info.st_uid != uid:
        raise ManagedTreeError(f"invalid ownership marker: {marker_path}")
    try:
        payload = json.loads(marker_path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise ManagedTreeError(f"invalid ownership marker: {marker_path}") from exc
    if (
        payload.get("schema") != 1
        or payload.get("owner") != "limechain.web3"
        or payload.get("scope") != scope
        or payload.get("uid") != uid
        or not isinstance(payload.get("entries"), list)
    ):
        raise ManagedTreeError(f"ownership marker does not match this managed scope: {root}")
    current = inventory(root)
    if current != payload["entries"]:
        raise ManagedTreeError(f"managed tree has modified or unmanaged content: {root}")
    return payload


def copy_source(source: Path, staging: Path, uid: int) -> None:
    if source.is_symlink() or not source.is_dir():
        raise ManagedTreeError(f"managed source must be a regular directory: {source}")
    for item in inventory(source):
        source_item = source / item["path"]
        target_item = staging / item["path"]
        if item["type"] == "directory":
            target_item.mkdir(mode=0o755)
        else:
            target_item.parent.mkdir(mode=0o755, parents=True, exist_ok=True)
            flags = os.O_WRONLY | os.O_CREAT | os.O_EXCL
            if hasattr(os, "O_NOFOLLOW"):
                flags |= os.O_NOFOLLOW
            descriptor = os.open(target_item, flags, item["mode"])
            with source_item.open("rb") as source_handle, os.fdopen(descriptor, "wb") as target_handle:
                shutil.copyfileobj(source_handle, target_handle, 1024 * 1024)
                target_handle.flush()
                os.fsync(target_handle.fileno())
            os.chmod(target_item, item["mode"])
    if any(path.lstat().st_uid != uid for path in (staging, *staging.rglob("*"))):
        raise ManagedTreeError("staged managed tree has unexpected ownership")


def install(source: Path, target: Path, boundary: Path, scope: str) -> None:
    uid = os.getuid()
    target, boundary = assert_contained(target, boundary)
    check_existing_components(target, boundary, uid)
    secure_mkdirs(target.parent, boundary, uid)
    if target.exists() or target.is_symlink():
        if target.is_symlink() or not target.is_dir():
            raise ManagedTreeError(f"managed destination collides with another file: {target}")
        existing = verify(target, scope, uid)
        if existing["entries"] == inventory(source):
            return

    staging = Path(tempfile.mkdtemp(prefix=f".{target.name}.staging.", dir=target.parent))
    backup = target.parent / f".{target.name}.backup.{os.getpid()}"
    if backup.exists() or backup.is_symlink():
        shutil.rmtree(staging)
        raise ManagedTreeError(f"transaction backup path already exists: {backup}")
    try:
        copy_source(source, staging, uid)
        payload = marker_payload(staging, scope, uid)
        marker = staging / MARKER
        descriptor = os.open(marker, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        with os.fdopen(descriptor, "w", encoding="utf-8") as handle:
            json.dump(payload, handle, sort_keys=True, separators=(",", ":"))
            handle.write("\n")
            handle.flush()
            os.fsync(handle.fileno())
        verify(staging, scope, uid)
        replaced = False
        if target.exists():
            target.rename(backup)
            replaced = True
        try:
            staging.rename(target)
        except BaseException:
            if replaced:
                backup.rename(target)
            raise
        if replaced:
            shutil.rmtree(backup)
    finally:
        if staging.exists():
            shutil.rmtree(staging)


def remove(target: Path, boundary: Path, scope: str) -> None:
    uid = os.getuid()
    target, boundary = assert_contained(target, boundary)
    check_existing_components(target, boundary, uid)
    if not target.exists() and not target.is_symlink():
        return
    if target.is_symlink() or not target.is_dir():
        raise ManagedTreeError(f"managed destination is not a regular directory: {target}")
    verify(target, scope, uid)
    trash = target.parent / f".{target.name}.remove.{os.getpid()}"
    if trash.exists() or trash.is_symlink():
        raise ManagedTreeError(f"transaction removal path already exists: {trash}")
    target.rename(trash)
    try:
        shutil.rmtree(trash)
    except BaseException:
        trash.rename(target)
        raise


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("action", choices=("check", "install", "remove", "verify"))
    parser.add_argument("--target", required=True, type=Path)
    parser.add_argument("--boundary", required=True, type=Path)
    parser.add_argument("--scope", required=True)
    parser.add_argument("--source", type=Path)
    args = parser.parse_args()
    try:
        if args.action == "check":
            check_existing_components(args.target, args.boundary, os.getuid())
        elif args.action == "install":
            if args.source is None:
                raise ManagedTreeError("install requires --source")
            install(args.source, args.target, args.boundary, args.scope)
        elif args.action == "remove":
            remove(args.target, args.boundary, args.scope)
        else:
            verify(args.target, args.scope, os.getuid())
    except (ManagedTreeError, OSError, ValueError, json.JSONDecodeError) as exc:
        print(f"managed-tree: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
