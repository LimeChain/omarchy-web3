from __future__ import annotations

import hashlib
import importlib.util
import io
import json
import stat
import sys
import tarfile
import tempfile
import unittest
import urllib.error
import zipfile
from email.message import Message
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def load_script(name: str):
    path = ROOT / "scripts" / name
    spec = importlib.util.spec_from_file_location(name.replace("-", "_"), path)
    assert spec and spec.loader
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


safe_download = load_script("safe-download.py")
safe_extract = load_script("safe-extract.py")
sanitize_archive = load_script("sanitize-upstream-archive.py")


class FakeResponse(io.BytesIO):
    def __init__(self, body: bytes, url: str, declared: int | None = None) -> None:
        super().__init__(body)
        self._url = url
        self.headers = Message()
        if declared is not None:
            self.headers["Content-Length"] = str(declared)

    def geturl(self) -> str:
        return self._url


class RedirectingOpener:
    def __init__(self, responses: list[object]) -> None:
        self.responses = responses

    def open(self, request, timeout):
        response = self.responses.pop(0)
        if isinstance(response, BaseException):
            raise response
        return response


def redirect(code: int, location: str) -> urllib.error.HTTPError:
    headers = Message()
    headers["Location"] = location
    return urllib.error.HTTPError("https://github.com/start", code, "redirect", headers, None)


class SafeDownloadTests(unittest.TestCase):
    def test_origin_policy_rejects_http_credentials_ports_and_foreign_hosts(self) -> None:
        allowed = {"github.com", "release-assets.githubusercontent.com"}
        rejected = (
            "http://github.com/a",
            "https://user@github.com/a",
            "https://github.com:8443/a",
            "https://evil.example/a",
            "https://github.com/a#fragment",
        )
        for value in rejected:
            with self.subTest(value=value), self.assertRaises(safe_download.DownloadError):
                safe_download.validate_url(value, allowed)

    def test_redirect_chain_validates_every_host(self) -> None:
        opener = RedirectingOpener(
            [
                redirect(302, "https://release-assets.githubusercontent.com/file"),
                FakeResponse(b"ok", "https://release-assets.githubusercontent.com/file", 2),
            ]
        )
        response = safe_download.open_with_policy(
            "https://github.com/start",
            {"github.com", "release-assets.githubusercontent.com"},
            timeout=1,
            opener=opener,
        )
        self.assertEqual(response.read(), b"ok")
        with self.assertRaises(safe_download.DownloadError):
            safe_download.open_with_policy(
                "https://github.com/start",
                {"github.com", "release-assets.githubusercontent.com"},
                timeout=1,
                opener=RedirectingOpener([redirect(302, "https://evil.example/file")]),
            )

    def test_stream_enforces_declared_actual_size_and_hash(self) -> None:
        body = b"reviewed bytes"
        digest = hashlib.sha256(body).hexdigest()
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "artifact"
            safe_download.stream_download(FakeResponse(body, "https://github.com/a", len(body)), output, len(body), digest)
            self.assertEqual(output.read_bytes(), body)
            for response, size, sha in (
                (FakeResponse(body, "https://github.com/a", len(body) + 1), len(body), digest),
                (FakeResponse(body + b"x", "https://github.com/a", None), len(body), digest),
                (FakeResponse(body, "https://github.com/a", len(body)), len(body), "0" * 64),
            ):
                output.unlink(missing_ok=True)
                with self.assertRaises(safe_download.DownloadError):
                    safe_download.stream_download(response, output, size, sha)
                self.assertFalse(output.exists())


class SafeExtractTests(unittest.TestCase):
    def write_lock(
        self,
        root: Path,
        archive: str,
        size: int,
        materialized_symlinks: dict[str, str] | None = None,
        **limits: int,
    ) -> Path:
        archive_path = root / "archive.tar.gz"
        archive_digest = hashlib.sha256(archive_path.read_bytes()).hexdigest()
        lock = {
            "schema": 2,
            "artifacts": [
                {
                    "id": "tool",
                    "archive": archive,
                    "strip_components": 0,
                    "size": size,
                    "sha256": archive_digest,
                    "bins": {"tool": "bin/tool"},
                    "materialized_symlinks": materialized_symlinks or {},
                    "extraction": {
                        "max_entries": limits.get("max_entries", 3),
                        "max_unpacked_bytes": limits.get("max_unpacked_bytes", 32),
                        "max_file_bytes": limits.get("max_file_bytes", 16),
                        "allowed_top_level": ["bin"],
                    },
                }
            ],
        }
        path = root / "lock.json"
        path.write_text(json.dumps(lock), encoding="utf-8")
        return path

    def tar_with(self, root: Path, entries: list[tuple[str, bytes, str]]) -> Path:
        path = root / "archive.tar.gz"
        with tarfile.open(path, "w:gz") as archive:
            for name, body, kind in entries:
                item = tarfile.TarInfo(name)
                item.mode = 0o755
                if kind == "file":
                    item.size = len(body)
                    archive.addfile(item, io.BytesIO(body))
                elif kind == "symlink":
                    item.type = tarfile.SYMTYPE
                    item.linkname = body.decode()
                    archive.addfile(item)
                elif kind == "hardlink":
                    item.type = tarfile.LNKTYPE
                    item.linkname = body.decode()
                    archive.addfile(item)
                elif kind == "fifo":
                    item.type = tarfile.FIFOTYPE
                    archive.addfile(item)
        return path

    def test_valid_archive_is_manually_extracted_and_manifested(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            archive = self.tar_with(root, [("bin/tool", b"binary", "file")])
            lock = self.write_lock(root, "tar.gz", archive.stat().st_size)
            destination = root / "out"
            safe_extract.extract_locked(lock, "tool", archive, destination)
            self.assertEqual((destination / "bin/tool").read_bytes(), b"binary")
            self.assertTrue((destination / ".limechain-files.sha256").is_file())
            self.assertEqual(stat.S_IMODE((destination / "bin/tool").stat().st_mode), 0o755)
            safe_extract.verify_tree(lock, "tool", destination)
            (destination / "unmanaged").write_text("x", encoding="utf-8")
            with self.assertRaises(safe_extract.ExtractError):
                safe_extract.verify_tree(lock, "tool", destination)

    def test_declared_post_extraction_symlink_is_exactly_materialized(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            archive = self.tar_with(root, [("bin/tool", b"binary", "file")])
            lock = self.write_lock(
                root,
                "tar.gz",
                archive.stat().st_size,
                materialized_symlinks={"bin/tool-alias": "bin/tool"},
            )
            destination = root / "out"
            safe_extract.extract_locked(lock, "tool", archive, destination)
            alias = destination / "bin/tool-alias"
            self.assertTrue(alias.is_symlink())
            self.assertEqual(alias.readlink(), Path("tool"))
            safe_extract.verify_tree(lock, "tool", destination)
            alias.unlink()
            alias.symlink_to("../outside")
            with self.assertRaises(safe_extract.ExtractError):
                safe_extract.verify_tree(lock, "tool", destination)

    def test_rejects_traversal_links_special_entries_and_unexpected_paths(self) -> None:
        cases = (
            [("../escape", b"x", "file"), ("bin/tool", b"x", "file")],
            [("bin/tool", b"target", "symlink")],
            [("bin/tool", b"target", "hardlink")],
            [("bin/tool", b"", "fifo")],
            [("other/tool", b"x", "file"), ("bin/tool", b"x", "file")],
        )
        for entries in cases:
            with self.subTest(entries=entries), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                archive = self.tar_with(root, entries)
                lock = self.write_lock(root, "tar.gz", archive.stat().st_size)
                with self.assertRaises(safe_extract.ExtractError):
                    safe_extract.extract_locked(lock, "tool", archive, root / "out")
                self.assertFalse((root / "out").exists())

    def test_rejects_duplicate_and_bounded_archive_expansion(self) -> None:
        cases = (
            ([("bin/tool", b"a", "file"), ("bin/tool", b"b", "file")], {}),
            ([("bin/tool", b"0123456789", "file")], {"max_file_bytes": 4}),
            (
                [("bin/tool", b"1234", "file"), ("bin/other", b"5678", "file")],
                {"max_unpacked_bytes": 7},
            ),
            (
                [("bin/tool", b"a", "file"), ("bin/a", b"b", "file"), ("bin/b", b"c", "file")],
                {"max_entries": 2},
            ),
        )
        for entries, limits in cases:
            with self.subTest(entries=entries, limits=limits), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                archive = self.tar_with(root, entries)
                lock = self.write_lock(root, "tar.gz", archive.stat().st_size, **limits)
                with self.assertRaises(safe_extract.ExtractError):
                    safe_extract.extract_locked(lock, "tool", archive, root / "out")


class SanitizedArtifactTests(unittest.TestCase):
    def source_archive(self, root: Path, link_kind: bytes = tarfile.SYMTYPE) -> Path:
        path = root / "source.tar.gz"
        with tarfile.open(path, "w:gz") as archive:
            directory = tarfile.TarInfo("package")
            directory.type = tarfile.DIRTYPE
            archive.addfile(directory)
            binary = tarfile.TarInfo("package/bin/tool")
            binary.mode = 0o755
            binary.size = 6
            archive.addfile(binary, io.BytesIO(b"binary"))
            alias = tarfile.TarInfo("package/bin/alias")
            alias.type = link_kind
            alias.linkname = "tool"
            archive.addfile(alias)
        return path

    def test_transform_is_deterministic_regular_only_and_requires_exact_omission(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = self.source_archive(root)
            source_hash = hashlib.sha256(source.read_bytes()).hexdigest()
            outputs = [root / "one.zip", root / "two.zip"]
            for output in outputs:
                sanitize_archive.sanitize(
                    source,
                    output,
                    source.stat().st_size,
                    source_hash,
                    1,
                    {Path("bin/alias")},
                )
            self.assertEqual(outputs[0].read_bytes(), outputs[1].read_bytes())
            with zipfile.ZipFile(outputs[0]) as archive:
                self.assertEqual(archive.namelist(), ["bin/tool"])
                mode = archive.getinfo("bin/tool").external_attr >> 16
                self.assertEqual(stat.S_IFMT(mode), stat.S_IFREG)
            with self.assertRaises(sanitize_archive.SanitizeError):
                sanitize_archive.sanitize(
                    source,
                    root / "missing-omission.zip",
                    source.stat().st_size,
                    source_hash,
                    1,
                    set(),
                )

    def test_transform_rejects_hardlinks_and_wrong_source_hash(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = self.source_archive(root, tarfile.LNKTYPE)
            source_hash = hashlib.sha256(source.read_bytes()).hexdigest()
            with self.assertRaises(sanitize_archive.SanitizeError):
                sanitize_archive.sanitize(
                    source,
                    root / "hardlink.zip",
                    source.stat().st_size,
                    source_hash,
                    1,
                    {Path("bin/alias")},
                )
            with self.assertRaises(sanitize_archive.SanitizeError):
                sanitize_archive.sanitize(
                    source,
                    root / "wrong-hash.zip",
                    source.stat().st_size,
                    "0" * 64,
                    1,
                    set(),
                )


if __name__ == "__main__":
    unittest.main()
