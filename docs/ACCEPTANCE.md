# MVP acceptance procedure

Run this matrix on a clean x86-64 VM installed from the latest stable Omarchy Quattro ISO. Record the ISO URL, SHA-256, Omarchy package version, Arch package inventory, and workstation commit in the test report.

## Clean install

1. Review and clone the tagged repository through `omarchy plugin add`.
2. Run `./install --profile evm-core` twice.
3. Confirm the second run changes no user-authored menu or shell configuration.
4. Run `limechain-web3 doctor --json`; every check must pass.
5. Confirm the bar widget loads and its panel opens.

## Toolchain smoke test

```bash
limechain-web3 scaffold /tmp/limechain-counter
cd /tmp/limechain-counter
limechain-web3 exec forge build
limechain-web3 exec forge test
limechain-web3 exec slither .
limechain-web3 exec echidna test/CounterEchidna.sol --contract CounterEchidna --config echidna.yaml
```

Run with network access disabled after installation to prove the bundled sample and compiler are self-contained.

## Local RPC

```bash
limechain-web3 anvil start
limechain-web3 status --json
limechain-web3 anvil reset
limechain-web3 anvil stop
```

Confirm the socket binds only to loopback, the RPC reports chain ID 31337, and service logs contain no accounts, private keys, or mnemonic.

## Offline Solana RPC

```bash
./install --profile solana-core
limechain-web3 surfpool start
limechain-web3 status --json
limechain-web3 surfpool reset
limechain-web3 surfpool stop
```

Confirm Surfpool reports healthy on `127.0.0.1:8899`, no non-loopback socket or established connection exists, the process arguments contain `--offline`, and the service cannot read the user's home directory. Confirm `limechain-web3 exec surfpool mcp` and a remote-network `surfpool start` invocation are refused before execution.

## Guard negative tests

Confirm each command is refused before tool execution:

```bash
limechain-web3 exec cast send 0x0000000000000000000000000000000000000000
limechain-web3 exec forge create src/Counter.sol:Counter
limechain-web3 exec forge script script/Deploy.s.sol --broadcast
limechain-web3 configure --name bad --chain-id 1 --rpc-url 'https://rpc.example/?key=secret'
```

## Update and uninstall

1. Update from the previous tagged release and confirm config, menu placement, and projects remain unchanged.
2. Run normal uninstall and confirm project-owned files and service state are removed while configuration/cache remain.
3. Reinstall, run purge uninstall, and confirm configuration/cache are removed.
4. Confirm unrelated Omarchy plugins, menu entries, agent skills, and shell layout remain unchanged after both paths.

Do not run destructive lifecycle tests on a user's daily machine; use a clean VM snapshot.
