from __future__ import annotations

import json
import re
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


class MetadataTests(unittest.TestCase):
    def test_plugin_manifest_contract(self) -> None:
        manifest = json.loads((ROOT / "manifest.json").read_text(encoding="utf-8"))
        self.assertEqual(manifest["schemaVersion"], 1)
        self.assertEqual(manifest["id"], "limechain.web3")
        self.assertEqual(manifest["kinds"], ["bar-widget"])
        entry = ROOT / manifest["entryPoints"]["barWidget"]
        self.assertTrue(entry.is_file())
        self.assertFalse(any(path.is_symlink() for path in ROOT.rglob("*") if ".git" not in path.parts))

    def test_qml_uses_only_guarded_cli_actions(self) -> None:
        qml = (ROOT / "plugin" / "Web3Panel.qml").read_text(encoding="utf-8")
        self.assertNotRegex(qml, r"command:\s*\[\s*\"(curl|wget|cast|forge|anvil)\"")
        self.assertIn('[root.cli, "status", "--json"]', qml)
        self.assertIn('[root.cli, "anvil", action]', qml)
        self.assertNotIn("private", qml.lower())

    def test_no_aur_or_unpinned_curl_pipe(self) -> None:
        installer = (ROOT / "scripts" / "install.sh").read_text(encoding="utf-8")
        self.assertNotRegex(installer, re.compile(r"(?m)^\s*yay\s"))
        self.assertNotRegex(installer, re.compile(r"curl[^\n|]*\|\s*(ba)?sh"))
        self.assertNotRegex(installer, re.compile(r"(?m)^\s*sudo\s"))


if __name__ == "__main__":
    unittest.main()
