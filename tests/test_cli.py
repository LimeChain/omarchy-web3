from __future__ import annotations

import json
import importlib.machinery
import os
import shutil
import subprocess
import tempfile
import threading
import unittest
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
CLI = ROOT / "bin" / "limechain-web3"
CLI_MODULE = importlib.machinery.SourceFileLoader("limechain_web3_cli", str(CLI)).load_module()


class RpcHandler(BaseHTTPRequestHandler):
    def do_POST(self) -> None:  # noqa: N802
        length = int(self.headers.get("Content-Length", "0"))
        request = json.loads(self.rfile.read(length))
        results = {
            "eth_chainId": "0x7a69",
            "eth_blockNumber": "0x2a",
            "eth_gasPrice": "0x3b9aca00",
            "eth_getBlockByNumber": {"baseFeePerGas": "0x1dcd6500"},
            "getHealth": "ok",
            "getSlot": 77,
            "getVersion": {"solana-core": "1.18-test"},
            "getGenesisHash": "LCW3LocalGenesisHash",
        }
        body = json.dumps({"jsonrpc": "2.0", "id": request["id"], "result": results[request["method"]]}).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *_args: object) -> None:
        return


class CliTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = Path(tempfile.mkdtemp(prefix="limechain-web3-test-"))
        self.config = self.temp / "config.json"
        self.menu = self.temp / "omarchy-menu.jsonc"
        self.env = os.environ.copy()
        self.env.update(
            {
                "LCW3_HOME": str(self.temp),
                "LCW3_APP_ROOT": str(ROOT),
                "LCW3_CONFIG_FILE": str(self.config),
                "LCW3_MENU_FILE": str(self.menu),
                "LCW3_LOCK_FILE": str(ROOT / "toolchains" / "evm-core.lock.json"),
            }
        )
        shutil.copy(ROOT / "config" / "config.json", self.config)
        os.chmod(self.config, 0o600)

    def tearDown(self) -> None:
        shutil.rmtree(self.temp)

    def run_cli(self, *args: str) -> subprocess.CompletedProcess[str]:
        return subprocess.run([str(CLI), *args], env=self.env, capture_output=True, text=True, timeout=10)

    def test_signing_and_broadcast_are_refused(self) -> None:
        cast = self.run_cli("exec", "cast", "send", "0x0000000000000000000000000000000000000000")
        self.assertEqual(cast.returncode, 2)
        self.assertIn("sign or submit", cast.stderr)
        reordered = self.run_cli("exec", "cast", "--rpc-url", "http://127.0.0.1:8545", "send", "0x0")
        self.assertEqual(reordered.returncode, 2)
        self.assertIn("sign or submit", reordered.stderr)
        credential = self.run_cli("exec", "cast", "call", "0x0", "--private-key=0xdead")
        self.assertEqual(credential.returncode, 2)
        self.assertIn("credential", credential.stderr)
        forge = self.run_cli("exec", "forge", "script", "Deploy.s.sol", "--broadcast")
        self.assertEqual(forge.returncode, 2)
        self.assertIn("broadcast", forge.stderr)
        create = self.run_cli("exec", "forge", "--root", ".", "create", "src/Counter.sol:Counter")
        self.assertEqual(create.returncode, 2)
        self.assertIn("deployment", create.stderr)
        surfpool = self.run_cli("exec", "surfpool", "mcp")
        self.assertEqual(surfpool.returncode, 2)
        self.assertIn("arbitrary Surfpool commands are refused", surfpool.stderr)
        surfpool_remote = self.run_cli("exec", "surfpool", "start", "--network", "mainnet")
        self.assertEqual(surfpool_remote.returncode, 2)
        self.assertIn("fixed offline service", surfpool_remote.stderr)
        solana_transfer = self.run_cli("exec", "solana", "transfer", "recipient", "1")
        self.assertEqual(solana_transfer.returncode, 2)
        self.assertIn("arbitrary solana commands are refused", solana_transfer.stderr)
        anchor_test = self.run_cli("exec", "anchor", "test")
        self.assertEqual(anchor_test.returncode, 2)
        self.assertIn("arbitrary anchor commands are refused", anchor_test.stderr)

    def test_credential_bearing_rpc_url_is_refused(self) -> None:
        result = self.run_cli(
            "configure",
            "--name",
            "Unsafe",
            "--chain-id",
            "1",
            "--rpc-url",
            "https://rpc.example.org/v1?key=secret",
        )
        self.assertEqual(result.returncode, 2)
        self.assertIn("query strings", result.stderr)
        private = self.run_cli(
            "configure",
            "--name",
            "Private",
            "--chain-id",
            "1",
            "--rpc-url",
            "http://127.0.0.2:8545",
        )
        self.assertEqual(private.returncode, 2)
        self.assertIn("loopback", private.stderr)

    def test_menu_install_is_idempotent_and_removable(self) -> None:
        self.menu.write_text('{\n  // user content\n  "personal": {"label":"Personal"}\n}\n', encoding="utf-8")
        self.assertEqual(self.run_cli("internal", "install-menu").returncode, 0)
        self.assertEqual(self.run_cli("internal", "install-menu").returncode, 0)
        text = self.menu.read_text(encoding="utf-8")
        self.assertEqual(text.count("BEGIN limechain.web3"), 1)
        self.assertIn('"personal"', text)
        self.assertEqual(self.run_cli("internal", "remove-menu").returncode, 0)
        text = self.menu.read_text(encoding="utf-8")
        self.assertNotIn("limechain.web3", text)
        self.assertIn('"personal"', text)

    def test_local_rpc_status(self) -> None:
        server = ThreadingHTTPServer(("127.0.0.1", 0), RpcHandler)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        try:
            config = json.loads(self.config.read_text(encoding="utf-8"))
            config["local"]["rpc_url"] = f"http://127.0.0.1:{server.server_port}"
            self.config.write_text(json.dumps(config), encoding="utf-8")
            os.chmod(self.config, 0o600)
            result = self.run_cli("status", "--json")
        finally:
            server.shutdown()
            server.server_close()
        self.assertEqual(result.returncode, 0, result.stderr)
        report = json.loads(result.stdout)
        self.assertTrue(report["local"]["ok"])
        self.assertEqual(report["local"]["chain_id"], 31337)
        self.assertFalse(report["chain"]["configured"])
        self.assertEqual(report["local"]["block_height"], 42)
        self.assertEqual(report["local"]["gas_gwei"], 1.0)
        self.assertFalse(report["chain"]["ok"])
        self.assertFalse(report["solana"]["installed"])

    def test_solana_rpc_status(self) -> None:
        server = ThreadingHTTPServer(("127.0.0.1", 0), RpcHandler)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        try:
            config = json.loads(self.config.read_text(encoding="utf-8"))
            config["solana"]["local"]["rpc_url"] = f"http://127.0.0.1:{server.server_port}"
            self.config.write_text(json.dumps(config), encoding="utf-8")
            os.chmod(self.config, 0o600)
            self.env["LCW3_LOCK_FILE"] = str(ROOT / "toolchains" / "solana-core.lock.json")
            result = self.run_cli("status", "--json")
        finally:
            server.shutdown()
            server.server_close()
        self.assertEqual(result.returncode, 0, result.stderr)
        report = json.loads(result.stdout)
        self.assertEqual(report["schema"], 2)
        self.assertFalse(report["local"]["installed"])
        self.assertTrue(report["solana"]["installed"])
        self.assertTrue(report["solana"]["ok"])
        self.assertEqual(report["solana"]["slot"], 77)
        self.assertEqual(report["solana"]["version"], "1.18-test")
        self.assertEqual(report["solana"]["surfpool_version"], "1.5.0")
        self.assertEqual(report["solana"]["cli_version"], "4.2.2")
        self.assertEqual(report["solana"]["anchor_version"], "1.1.2")
        self.assertEqual(report["solana"]["mode"], "offline")

    def test_scaffold_refuses_overwrite(self) -> None:
        destination = self.temp / "counter"
        first = self.run_cli("scaffold", str(destination))
        self.assertEqual(first.returncode, 0, first.stderr)
        self.assertTrue((destination / "src" / "Counter.sol").is_file())
        second = self.run_cli("scaffold", str(destination))
        self.assertEqual(second.returncode, 2)
        self.assertIn("refusing to overwrite", second.stderr)

    def test_anchor_scaffold_and_preflight_are_keypair_free(self) -> None:
        destination = self.temp / "anchor-counter"
        result = self.run_cli("anchor", "scaffold", str(destination))
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue((destination / "Anchor.toml").is_file())
        self.assertTrue((destination / "Cargo.lock").is_file())
        self.assertFalse(any(destination.rglob("*-keypair.json")))
        self.assertEqual(CLI_MODULE.anchor_build_preflight(destination), ["limechain_anchor_counter"])

        with (destination / "Anchor.toml").open("a", encoding="utf-8") as stream:
            stream.write('\n[hooks]\npre_build = "echo unsafe"\n')
        with self.assertRaisesRegex(RuntimeError, "hooks are refused"):
            CLI_MODULE.anchor_build_preflight(destination)


if __name__ == "__main__":
    unittest.main()
