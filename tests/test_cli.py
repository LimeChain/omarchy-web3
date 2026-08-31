from __future__ import annotations

import json
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


class RpcHandler(BaseHTTPRequestHandler):
    def do_POST(self) -> None:  # noqa: N802
        length = int(self.headers.get("Content-Length", "0"))
        request = json.loads(self.rfile.read(length))
        results = {
            "eth_chainId": "0x7a69",
            "eth_blockNumber": "0x2a",
            "eth_gasPrice": "0x3b9aca00",
            "eth_getBlockByNumber": {"baseFeePerGas": "0x1dcd6500"},
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

    def test_scaffold_refuses_overwrite(self) -> None:
        destination = self.temp / "counter"
        first = self.run_cli("scaffold", str(destination))
        self.assertEqual(first.returncode, 0, first.stderr)
        self.assertTrue((destination / "src" / "Counter.sol").is_file())
        second = self.run_cli("scaffold", str(destination))
        self.assertEqual(second.returncode, 2)
        self.assertIn("refusing to overwrite", second.stderr)


if __name__ == "__main__":
    unittest.main()
