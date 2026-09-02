#!/usr/bin/env python3
"""Create a deterministic, link-free ZIP from one checksum-locked upstream tarball."""

from __future__ import annotations

import argparse
import hashlib
import os
import stat
import sys
import tarfile
import zipfile
from pathlib import Path, PurePosixPath
from typing import BinaryIO


CHUNK_SIZE = 1024 * 1024


class SanitizeError(RuntimeError):
    pass


def digest(path: Path) -> str:
    value = hashlib.sha256()
    with path.open("rb") as handle:
        while chunk := handle.read(CHUNK_SIZE):
            value.update(chunk)
    return value.hexdigest()


def normalize(name: str, strip_components: int) -> PurePosixPath | None:
    if not name or "\x00" in name or "\\" in name:
        raise SanitizeError(f"unsafe upstream member: {name!r}")
    parts = list(PurePosixPath(name).parts)
    while parts and parts[0] == ".":
        parts.pop(0)
    if not parts:
        return None
    if any(part in {"", ".", ".."} for part in parts):
        raise SanitizeError(f"unsafe upstream path: {name!r}")
    if parts[0] == "/" or len(parts) <= strip_components:
        return None
    return PurePosixPath(*parts[strip_components:])


def resolve_link(
    source_path: PurePosixPath,
    linkname: str,
    members: dict[PurePosixPath, tarfile.TarInfo],
) -> tarfile.TarInfo:
    current_path = source_path
    current_link = linkname
    visited = {source_path}
    for _ in range(16):
        if not current_link or "\x00" in current_link or "\\" in current_link:
            raise SanitizeError(f"unsafe symlink target for {source_path}")
        raw = PurePosixPath(current_link)
        if raw.is_absolute():
            raise SanitizeError(f"absolute symlink target for {source_path}")
        combined = list(current_path.parent.parts)
        for part in raw.parts:
            if part in {"", "."}:
                continue
            if part == "..":
                if not combined:
                    raise SanitizeError(f"symlink escapes archive root: {source_path}")
                combined.pop()
            else:
                combined.append(part)
        target_path = PurePosixPath(*combined)
        if target_path in visited:
            raise SanitizeError(f"symlink cycle at {source_path}")
        visited.add(target_path)
        target = members.get(target_path)
        if target is None:
            raise SanitizeError(f"symlink target is absent: {source_path} -> {target_path}")
        if target.isfile():
            return target
        if not target.issym():
            raise SanitizeError(f"symlink does not resolve to a regular file: {source_path}")
        current_path = target_path
        current_link = target.linkname
    raise SanitizeError(f"symlink chain is too deep: {source_path}")


def copy_stream(source: BinaryIO, target: BinaryIO, expected_size: int) -> None:
    remaining = expected_size
    while remaining:
        chunk = source.read(min(CHUNK_SIZE, remaining))
        if not chunk:
            raise SanitizeError("upstream member was truncated")
        target.write(chunk)
        remaining -= len(chunk)
    if source.read(1):
        raise SanitizeError("upstream member exceeded its declared size")


def sanitize(
    source_path: Path,
    output_path: Path,
    expected_size: int,
    expected_sha256: str,
    strip_components: int,
    drop_symlinks: set[PurePosixPath],
) -> None:
    if source_path.is_symlink() or not source_path.is_file():
        raise SanitizeError("upstream archive must be a regular file")
    if source_path.stat().st_size != expected_size or digest(source_path) != expected_sha256:
        raise SanitizeError("upstream archive differs from its reviewed size or SHA-256")
    if output_path.exists() or output_path.is_symlink():
        raise SanitizeError("refusing to replace an existing output")

    with tarfile.open(source_path, "r:*") as archive:
        by_source_path: dict[PurePosixPath, tarfile.TarInfo] = {}
        output: dict[PurePosixPath, tarfile.TarInfo] = {}
        dropped: set[PurePosixPath] = set()
        for member in archive.getmembers():
            source_name = normalize(member.name, 0)
            if source_name is None:
                continue
            if source_name in by_source_path:
                raise SanitizeError(f"duplicate upstream path: {source_name}")
            by_source_path[source_name] = member
            relative = normalize(member.name, strip_components)
            if relative is None or member.isdir():
                continue
            if relative in drop_symlinks:
                if not member.issym():
                    raise SanitizeError(f"declared dropped entry is not a symlink: {relative}")
                dropped.add(relative)
                continue
            if member.issym():
                raise SanitizeError(f"upstream symlink was not explicitly declared for omission: {relative}")
            if member.islnk() or not (member.isfile() or member.issym()):
                raise SanitizeError(f"upstream archive has an unsupported special entry: {member.name}")
            if relative in output:
                raise SanitizeError(f"duplicate sanitized path: {relative}")
            output[relative] = member

        if dropped != drop_symlinks:
            missing = sorted(str(path) for path in drop_symlinks - dropped)
            raise SanitizeError(f"declared dropped symlinks were absent: {missing}")

        try:
            with zipfile.ZipFile(
                output_path,
                "x",
                compression=zipfile.ZIP_DEFLATED,
                compresslevel=6,
                allowZip64=True,
            ) as result:
                # The upstream archive is checksum-locked, so its member order is a
                # reproducible input. Preserving it also keeps compressed-tar reads
                # sequential instead of repeatedly seeking through the stream.
                for relative, member in output.items():
                    resolved = member
                    source = archive.extractfile(resolved)
                    if source is None:
                        raise SanitizeError(f"could not read upstream member: {resolved.name}")
                    mode = stat.S_IMODE(resolved.mode)
                    info = zipfile.ZipInfo(relative.as_posix(), date_time=(1980, 1, 1, 0, 0, 0))
                    info.create_system = 3
                    info.compress_type = zipfile.ZIP_DEFLATED
                    info.external_attr = (stat.S_IFREG | (0o755 if mode & 0o111 else 0o644)) << 16
                    with source, result.open(info, "w", force_zip64=True) as target:
                        copy_stream(source, target, resolved.size)
        except BaseException:
            output_path.unlink(missing_ok=True)
            raise


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--source-size", required=True, type=int)
    parser.add_argument("--source-sha256", required=True)
    parser.add_argument("--strip-components", type=int, default=0)
    parser.add_argument(
        "--drop-symlink",
        action="append",
        default=[],
        help="exact stripped path of a known-unneeded upstream symlink to omit",
    )
    args = parser.parse_args()
    try:
        sanitize(
            args.source,
            args.output,
            args.source_size,
            args.source_sha256,
            args.strip_components,
            {PurePosixPath(value) for value in args.drop_symlink},
        )
    except (SanitizeError, OSError, tarfile.TarError, zipfile.BadZipFile) as exc:
        print(f"sanitize-upstream-archive: {exc}", file=sys.stderr)
        return 1
    print(f"{digest(args.output)}  {args.output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
