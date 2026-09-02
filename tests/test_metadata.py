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
        self.assertIn('[root.cli, "surfpool", action]', qml)
        self.assertIn('[root.cli, "hedera", "open-latest"]', qml)
        self.assertIn('label: "Solana CLI"', qml)
        self.assertIn('label: "Anchor"', qml)
        self.assertIn('visible: !root.anvilActive && root.anvilAction === ""', qml)
        self.assertIn('visible: !root.surfpoolActive && root.surfpoolAction === ""', qml)
        self.assertIn('text: "REMOTE OBSERVER (OPTIONAL)"', qml)
        self.assertIn('text: "HEDERA OBSERVER"', qml)
        self.assertNotRegex(qml, r'enabled:\s*[!]?root\.anvilActive')
        self.assertNotRegex(qml, r'enabled:\s*[!]?root\.surfpoolActive')
        self.assertNotRegex(qml, r"command:\s*\[\s*\"surfpool\"")
        self.assertNotIn("private", qml.lower())

    def test_hedera_profile_has_no_binary_or_service_payload(self) -> None:
        lock = json.loads((ROOT / "toolchains" / "hedera-core.lock.json").read_text(encoding="utf-8"))
        self.assertEqual(lock["platform"], "any")
        self.assertEqual(lock["artifacts"], [])
        installer = (ROOT / "scripts" / "install.sh").read_text(encoding="utf-8")
        self.assertIn("evm-core | solana-core | hedera-core", installer)
        self.assertNotIn("limechain-web3-hedera.service", installer)

    def test_surfpool_service_is_offline_and_non_custodial(self) -> None:
        unit = (ROOT / "systemd" / "limechain-web3-surfpool.service").read_text(encoding="utf-8")
        self.assertIn("start --offline --host 127.0.0.1", unit)
        self.assertIn("--airdrop-keypair-path /dev/null --airdrop-amount 0", unit)
        self.assertIn("--ci --no-deploy", unit)
        self.assertIn("ProtectHome=tmpfs", unit)
        self.assertIn("IPAddressDeny=any", unit)
        self.assertIn("IPAddressAllow=localhost", unit)
        self.assertIn("KillSignal=SIGINT", unit)
        self.assertIn("TimeoutStopSec=5s", unit)

    def test_solana_artifact_and_guard_contract(self) -> None:
        lock = json.loads((ROOT / "toolchains" / "solana-core.lock.json").read_text(encoding="utf-8"))
        artifacts = {item["id"]: item for item in lock["artifacts"]}
        self.assertEqual(set(artifacts), {"surfpool", "agave", "anchor", "platform-tools"})
        self.assertEqual(artifacts["agave"]["bins"]["solana"], "bin/solana")
        self.assertEqual(artifacts["anchor"]["archive"], "raw")
        self.assertEqual(artifacts["platform-tools"]["version"], "1.52")
        cli = (ROOT / "bin" / "limechain-web3").read_text(encoding="utf-8")
        self.assertIn('"--ignore-keys"', cli)
        self.assertIn('"--skip-tools-install"', cli)
        self.assertIn('provider.get("wallet") != "/dev/null"', cli)
        self.assertIn('sentinel.symlink_to("/dev/null")', cli)

    def test_no_aur_or_unpinned_curl_pipe(self) -> None:
        installer = (ROOT / "scripts" / "install.sh").read_text(encoding="utf-8")
        self.assertNotRegex(installer, re.compile(r"(?m)^\s*yay\s"))
        self.assertNotRegex(installer, re.compile(r"curl[^\n|]*\|\s*(ba)?sh"))
        self.assertNotRegex(installer, re.compile(r"(?m)^\s*sudo\s"))

    def test_agent_skill_is_separate_explicit_opt_in(self) -> None:
        installer = (ROOT / "scripts" / "install.sh").read_text(encoding="utf-8")
        uninstaller = (ROOT / "scripts" / "uninstall.sh").read_text(encoding="utf-8")
        self.assertNotIn('lcw3_copy_tree "$SOURCE_DIR/skill', installer)
        self.assertNotIn('rm -rf "$LCW3_SKILL_ROOT"', uninstaller)
        self.assertTrue((ROOT / "install-agent-skill").is_file())
        self.assertTrue((ROOT / "uninstall-agent-skill").is_file())
        skill_installer = (ROOT / "scripts" / "install-agent-skill.sh").read_text(encoding="utf-8")
        self.assertIn('skill_root="$skill_home/.agents/skills/limechain-web3"', skill_installer)
        self.assertIn("managed-tree.py", skill_installer)

    def test_transaction_validates_lock_state_before_safe_shell_restart(self) -> None:
        installer = (ROOT / "scripts" / "install.sh").read_text(encoding="utf-8")
        self.assertIn("lcw3_require_unlocked_session", installer)
        self.assertIn("omarchy-restart-shell", installer)
        self.assertLess(installer.index("lcw3_require_unlocked_session"), installer.index("# Commit begins"))
        self.assertGreater(installer.rindex("omarchy-restart-shell"), installer.index("# Commit begins"))


if __name__ == "__main__":
    unittest.main()
