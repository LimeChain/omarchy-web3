#!/usr/bin/env python3
"""Preflight and manually extract a locked archive without following links."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import shutil
import stat
import sys
import tarfile
import zipfile
from dataclasses import dataclass
from pathlib import Path, PurePosixPath
from typing import Any, BinaryIO, Iterator


CHUNK_SIZE = 1024 * 1024


class ExtractError(RuntimeError):
    pass


@dataclass(frozen=True)
class Member:
    source_name: str
    relative: PurePosixPath
    size: int
    mode: int
    is_dir: bool
    source: Any


def artifact_from_lock(lock_path: Path, artifact_id: str) -> dict[str, Any]:
    lock = json.loads(lock_path.read_text(encoding="utf-8"))
    matches = [item for item in lock.get("artifacts", []) if item.get("id") == artifact_id]
    if len(matches) != 1:
        raise ExtractError(f"artifact is not uniquely declared in lock: {artifact_id}")
    return matches[0]


def clean_member_name(name: str, strip_components: int) -> PurePosixPath | None:
    if not name or "\x00" in name or "\\" in name:
        raise ExtractError(f"unsafe archive member name: {name!r}")
    raw = PurePosixPath(name)
    if raw.is_absolute() or any(part in {"", ".", ".."} for part in raw.parts):
        raise ExtractError(f"unsafe archive member path: {name!r}")
    if len(raw.parts) <= strip_components:
        return None
    relative = PurePosixPath(*raw.parts[strip_components:])
    if not relative.parts:
        return None
    return relative


def tar_members(archive: tarfile.TarFile, strip_components: int) -> Iterator[Member]:
    for item in archive.getmembers():
        relative = clean_member_name(item.name, strip_components)
        if relative is None:
            if item.isdir():
                continue
            raise ExtractError(f"archive member disappears after component stripping: {item.name}")
        if not (item.isdir() or item.isfile()):
            raise ExtractError(f"archive contains a link or special entry: {item.name}")
        yield Member(item.name, relative, item.size, item.mode, item.isdir(), item)


def zip_members(archive: zipfile.ZipFile, strip_components: int) -> Iterator[Member]:
    for item in archive.infolist():
        relative = clean_member_name(item.filename.rstrip("/"), strip_components)
        is_dir = item.is_dir()
        if relative is None:
            if is_dir:
                continue
            raise ExtractError(f"archive member disappears after component stripping: {item.filename}")
        mode = (item.external_attr >> 16) & 0xFFFF
        kind = stat.S_IFMT(mode)
        if item.flag_bits & 0x1:
            raise ExtractError(f"archive contains an encrypted entry: {item.filename}")
        if kind not in {0, stat.S_IFREG, stat.S_IFDIR}:
            raise ExtractError(f"archive contains a link or special entry: {item.filename}")
        yield Member(item.filename, relative, item.file_size, mode or 0o644, is_dir, item)


def preflight(members: list[Member], artifact: dict[str, Any]) -> int:
    limits = artifact.get("extraction")
    if not isinstance(limits, dict):
        raise ExtractError("archive lock is missing extraction limits")
    max_entries = limits.get("max_entries")
    max_unpacked = limits.get("max_unpacked_bytes")
    max_file = limits.get("max_file_bytes")
    allowed_top = limits.get("allowed_top_level")
    if not all(isinstance(value, int) and value > 0 for value in (max_entries, max_unpacked, max_file)):
        raise ExtractError("archive extraction limits must be positive integers")
    if not isinstance(allowed_top, list) or not allowed_top or not all(
        isinstance(value, str) and value and "/" not in value and value not in {".", ".."}
        for value in allowed_top
    ):
        raise ExtractError("archive allowed_top_level policy is invalid")
    if len(members) > max_entries:
        raise ExtractError("archive exceeds the locked entry-count limit")
    total = 0
    seen: set[PurePosixPath] = set()
    allowed = set(allowed_top)
    for member in members:
        if member.relative in seen:
            raise ExtractError(f"archive contains a duplicate output path: {member.relative}")
        seen.add(member.relative)
        if member.relative.parts[0] not in allowed:
            raise ExtractError(f"archive contains an unexpected top-level entry: {member.relative}")
        if member.size < 0 or member.size > max_file:
            raise ExtractError(f"archive member exceeds the per-file limit: {member.relative}")
        total += member.size
        if total > max_unpacked:
            raise ExtractError("archive exceeds the locked uncompressed-byte limit")
    declared_links = artifact.get("materialized_symlinks", {})
    if not isinstance(declared_links, dict):
        raise ExtractError("materialized_symlinks must be an object")
    for relative in artifact.get("bins", {}).values():
        expected = PurePosixPath(relative)
        if expected not in seen and relative not in declared_links:
            raise ExtractError(f"locked binary is absent from archive: {relative}")
    return total


def safe_parent(destination: Path, relative: PurePosixPath) -> Path:
    current = destination
    for part in relative.parts[:-1]:
        current = current / part
        try:
            info = current.lstat()
        except FileNotFoundError:
            current.mkdir(mode=0o755)
            continue
        if not stat.S_ISDIR(info.st_mode) or stat.S_ISLNK(info.st_mode):
            raise ExtractError(f"non-directory extraction component: {current}")
    return current


def write_member(source: BinaryIO, target: Path, size: int, executable: bool) -> None:
    flags = os.O_WRONLY | os.O_CREAT | os.O_EXCL
    if hasattr(os, "O_NOFOLLOW"):
        flags |= os.O_NOFOLLOW
    descriptor = os.open(target, flags, 0o755 if executable else 0o644)
    remaining = size
    try:
        with os.fdopen(descriptor, "wb", closefd=True) as handle:
            while remaining:
                chunk = source.read(min(CHUNK_SIZE, remaining))
                if not chunk:
                    raise ExtractError(f"archive member was truncated: {target.name}")
                handle.write(chunk)
                remaining -= len(chunk)
            if source.read(1):
                raise ExtractError(f"archive member exceeded its declared size: {target.name}")
            handle.flush()
            os.fsync(handle.fileno())
    except BaseException:
        try:
            target.unlink()
        except FileNotFoundError:
            pass
        raise


def extract_members(
    archive: Any,
    members: list[Member],
    destination: Path,
    kind: str,
) -> None:
    directories = sorted((item for item in members if item.is_dir), key=lambda item: len(item.relative.parts))
    for member in directories:
        safe_parent(destination, member.relative)
        target = destination.joinpath(*member.relative.parts)
        try:
            target.mkdir(mode=0o755)
        except FileExistsError:
            info = target.lstat()
            if not stat.S_ISDIR(info.st_mode) or stat.S_ISLNK(info.st_mode):
                raise ExtractError(f"archive directory collides with another entry: {member.relative}")

    for member in (item for item in members if not item.is_dir):
        parent = safe_parent(destination, member.relative)
        target = parent / member.relative.name
        if target.exists() or target.is_symlink():
            raise ExtractError(f"archive output collision: {member.relative}")
        source = archive.extractfile(member.source) if kind == "tar" else archive.open(member.source, "r")
        if source is None:
            raise ExtractError(f"could not read archive member: {member.source_name}")
        with source:
            write_member(source, target, member.size, bool(member.mode & 0o111))


def safe_relative(value: str) -> PurePosixPath:
    if not value or "\x00" in value or "\\" in value:
        raise ExtractError(f"unsafe materialized path: {value!r}")
    path = PurePosixPath(value)
    if path.is_absolute() or any(part in {"", ".", ".."} for part in path.parts):
        raise ExtractError(f"unsafe materialized path: {value!r}")
    return path


def materialize_symlinks(destination: Path, artifact: dict[str, Any]) -> dict[str, str]:
    declared = artifact.get("materialized_symlinks", {})
    if not isinstance(declared, dict):
        raise ExtractError("materialized_symlinks must be an object")
    created: dict[str, str] = {}
    for link_value, target_value in sorted(declared.items()):
        if not isinstance(link_value, str) or not isinstance(target_value, str):
            raise ExtractError("materialized symlink paths must be strings")
        link_relative = safe_relative(link_value)
        target_relative = safe_relative(target_value)
        link = destination.joinpath(*link_relative.parts)
        target = destination.joinpath(*target_relative.parts)
        target_info = target.lstat()
        if not stat.S_ISREG(target_info.st_mode) or stat.S_ISLNK(target_info.st_mode):
            raise ExtractError(f"materialized symlink target is not a regular file: {target_relative}")
        safe_parent(destination, link_relative)
        if link.exists() or link.is_symlink():
            raise ExtractError(f"materialized symlink output collision: {link_relative}")
        relative_target = os.path.relpath(target, link.parent)
        link.symlink_to(relative_target)
        created[link_relative.as_posix()] = relative_target
    return created


def write_manifest(destination: Path, digest: str, links: dict[str, str]) -> None:
    lines: list[str] = []
    for path in sorted(destination.rglob("*")):
        info = path.lstat()
        if stat.S_ISLNK(info.st_mode):
            relative = path.relative_to(destination).as_posix()
            if links.get(relative) != os.readlink(path):
                raise ExtractError(f"tree contains an undeclared symlink: {path}")
            continue
        if not stat.S_ISREG(info.st_mode):
            continue
        hasher = hashlib.sha256()
        with path.open("rb") as handle:
            while chunk := handle.read(CHUNK_SIZE):
                hasher.update(chunk)
        lines.append(f"{hasher.hexdigest()}  {path.relative_to(destination).as_posix()}")
    (destination / ".limechain-files.sha256").write_text("\n".join(lines) + "\n", encoding="utf-8")
    (destination / ".limechain-links.json").write_text(
        json.dumps(links, sort_keys=True, separators=(",", ":")) + "\n", encoding="utf-8"
    )
    (destination / ".limechain-verified").write_text(digest + "\n", encoding="utf-8")


def verify_tree(lock_path: Path, artifact_id: str, destination: Path) -> None:
    artifact = artifact_from_lock(lock_path, artifact_id)
    if destination.is_symlink() or not destination.is_dir():
        raise ExtractError("verified toolchain destination is not a regular directory")
    marker = destination / ".limechain-verified"
    manifest = destination / ".limechain-files.sha256"
    links_file = destination / ".limechain-links.json"
    for metadata in (marker, manifest, links_file):
        info = metadata.lstat()
        if not stat.S_ISREG(info.st_mode) or stat.S_ISLNK(info.st_mode):
            raise ExtractError(f"invalid toolchain verification metadata: {metadata.name}")
    if marker.read_text(encoding="utf-8").strip() != artifact["sha256"]:
        raise ExtractError("toolchain marker differs from the artifact lock")
    try:
        links = json.loads(links_file.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        raise ExtractError("invalid materialized-symlink manifest") from exc
    expected_links = materialized_link_targets(destination, artifact)
    if links != expected_links:
        raise ExtractError("materialized-symlink manifest differs from the lock")
    declared_files: dict[str, str] = {}
    for line in manifest.read_text(encoding="utf-8").splitlines():
        digest, separator, relative = line.partition("  ")
        if not separator or len(digest) != 64 or relative in declared_files:
            raise ExtractError("invalid file-hash manifest")
        safe_relative(relative)
        declared_files[relative] = digest
    actual_files: set[str] = set()
    actual_links: dict[str, str] = {}
    for path in destination.rglob("*"):
        relative = path.relative_to(destination).as_posix()
        if relative in {".limechain-verified", ".limechain-files.sha256", ".limechain-links.json"}:
            continue
        info = path.lstat()
        if stat.S_ISLNK(info.st_mode):
            actual_links[relative] = os.readlink(path)
        elif stat.S_ISREG(info.st_mode):
            actual_files.add(relative)
        elif not stat.S_ISDIR(info.st_mode):
            raise ExtractError(f"toolchain tree contains a special file: {relative}")
    if actual_files != set(declared_files) or actual_links != expected_links:
        raise ExtractError("toolchain tree contains modified or unmanaged entries")
    for relative, expected_digest in declared_files.items():
        hasher = hashlib.sha256()
        with (destination / relative).open("rb") as handle:
            while chunk := handle.read(CHUNK_SIZE):
                hasher.update(chunk)
        if hasher.hexdigest() != expected_digest:
            raise ExtractError(f"toolchain file checksum mismatch: {relative}")


def materialized_link_targets(destination: Path, artifact: dict[str, Any]) -> dict[str, str]:
    values: dict[str, str] = {}
    declared = artifact.get("materialized_symlinks", {})
    if not isinstance(declared, dict):
        raise ExtractError("materialized_symlinks must be an object")
    for link_value, target_value in declared.items():
        link_relative = safe_relative(link_value)
        target_relative = safe_relative(target_value)
        link = destination.joinpath(*link_relative.parts)
        target = destination.joinpath(*target_relative.parts)
        values[link_relative.as_posix()] = os.path.relpath(target, link.parent)
    return values


def extract_locked(lock_path: Path, artifact_id: str, archive_path: Path, destination: Path) -> None:
    artifact = artifact_from_lock(lock_path, artifact_id)
    if archive_path.is_symlink() or not archive_path.is_file():
        raise ExtractError("locked archive is not a regular file")
    if archive_path.stat().st_size != artifact.get("size"):
        raise ExtractError("locked archive byte size changed before extraction")
    archive_digest = hashlib.sha256()
    with archive_path.open("rb") as handle:
        while chunk := handle.read(CHUNK_SIZE):
            archive_digest.update(chunk)
    if archive_digest.hexdigest() != artifact.get("sha256"):
        raise ExtractError("locked archive SHA-256 changed before extraction")
    if destination.exists() or destination.is_symlink():
        raise ExtractError("extraction destination must not already exist")
    destination.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    destination.mkdir(mode=0o700)
    try:
        archive_kind = artifact.get("archive")
        strip_components = artifact.get("strip_components", 0)
        if not isinstance(strip_components, int) or strip_components < 0:
            raise ExtractError("strip_components must be a non-negative integer")
        if archive_kind == "raw":
            if shutil.disk_usage(destination.parent).free < artifact["size"] + 16 * 1024 * 1024:
                raise ExtractError("insufficient free disk space for bounded raw-artifact installation")
            target_name = artifact_id
            allowed = set(artifact.get("bins", {}).values())
            if allowed != {target_name}:
                raise ExtractError("raw artifact must map to its locked artifact id")
            with archive_path.open("rb") as source:
                write_member(source, destination / target_name, artifact["size"], True)
        elif archive_kind in {"tar.gz", "tar.xz", "tar.bz2"}:
            with tarfile.open(archive_path, "r:*") as archive:
                members = list(tar_members(archive, strip_components))
                unpacked_size = preflight(members, artifact)
                if shutil.disk_usage(destination.parent).free < unpacked_size + 16 * 1024 * 1024:
                    raise ExtractError("insufficient free disk space for bounded archive extraction")
                extract_members(archive, members, destination, "tar")
        elif archive_kind == "zip":
            with zipfile.ZipFile(archive_path, "r") as archive:
                members = list(zip_members(archive, strip_components))
                unpacked_size = preflight(members, artifact)
                if shutil.disk_usage(destination.parent).free < unpacked_size + 16 * 1024 * 1024:
                    raise ExtractError("insufficient free disk space for bounded archive extraction")
                extract_members(archive, members, destination, "zip")
        else:
            raise ExtractError(f"unsupported locked archive type: {archive_kind}")

        links = materialize_symlinks(destination, artifact)
        for relative in artifact.get("bins", {}).values():
            target = destination / relative
            info = target.lstat()
            if stat.S_ISLNK(info.st_mode):
                if relative not in links:
                    raise ExtractError(f"locked binary is an undeclared symlink: {relative}")
            elif stat.S_ISREG(info.st_mode):
                target.chmod(0o755)
            else:
                raise ExtractError(f"locked binary is not a file: {relative}")
        write_manifest(destination, artifact["sha256"], links)
    except BaseException:
        shutil.rmtree(destination, ignore_errors=True)
        raise


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--lock", required=True, type=Path)
    parser.add_argument("--artifact", required=True)
    parser.add_argument("--archive", type=Path)
    parser.add_argument("--destination", required=True, type=Path)
    parser.add_argument("--verify-tree", action="store_true")
    args = parser.parse_args()
    try:
        if args.verify_tree:
            verify_tree(args.lock, args.artifact, args.destination)
        else:
            if args.archive is None:
                raise ExtractError("extraction requires --archive")
            extract_locked(args.lock, args.artifact, args.archive, args.destination)
    except (ExtractError, OSError, ValueError, json.JSONDecodeError, tarfile.TarError, zipfile.BadZipFile) as exc:
        print(f"safe-extract: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
