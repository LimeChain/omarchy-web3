# MVP acceptance procedure

Run this matrix on a clean x86-64 VM installed from the latest stable Omarchy Quattro ISO. Record the ISO URL, SHA-256, Omarchy package version, Arch package inventory, and workstation commit in the test report.

## Clean install

1. Review and clone the tagged repository through `omarchy plugin add`.
2. Run `./install --profile evm-core` twice.
3. Confirm the second run changes no user-authored menu or shell configuration.
4. Run `limechain-web3 doctor --json`; every check must pass.
5. Confirm the bar widget loads and its panel opens.
6. Confirm no path exists at `~/.agents/skills/limechain-web3` unless the separate opt-in command was run.

## Marketplace security boundaries

1. Run the malicious archive/download unit suite and retain its output with the validation record.
2. Reproduce both derived link-free archives on Ubuntu 24.04; compare sizes and SHA-256 values with the locks and verify their GitHub attestations.
3. Create unmarked collisions at each application/config/state/cache/CLI/service destination in an isolated home and confirm install/uninstall refuses them without mutation.
4. Replace a parent component with a symlink and confirm the lifecycle refuses it.
5. Inject the post-app-commit test failure and confirm the old app, state, CLI link, menu bytes, unit bytes, and prior active/inactive service states are restored.
6. Modify and add a file to the optional agent skill. Confirm update/removal refuses it, then restore the exact manifest and confirm removal succeeds.
7. Make the official plugin update mutate the checkout and `shell.json`, then fail; confirm the old checkout and byte-identical shell configuration return.
8. Make the official plugin removal delete the native checkout and mutate `shell.json`, then fail during rescan; confirm the checkout, shell configuration, workstation files, menu, and prior service states all return.

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

## Solana CLI and Anchor

```bash
limechain-web3 surfpool start
limechain-web3 solana version
limechain-web3 solana slot
limechain-web3 solana epoch
limechain-web3 anchor scaffold /tmp/limechain-anchor-counter
limechain-web3 anchor build /tmp/limechain-anchor-counter
limechain-web3 anchor build /tmp/limechain-anchor-counter --offline
```

Confirm both Anchor builds produce the same program `.so`, no `*-keypair.json` exists before or after either build, the real home is absent from the child environment, and no Solana configuration or wallet file is opened. Add a build hook, remote provider, real wallet path, version override, or fake keypair filename one at a time and confirm each is refused before Anchor starts.

## Guard negative tests

Confirm each command is refused before tool execution:

```bash
limechain-web3 exec cast send 0x0000000000000000000000000000000000000000
limechain-web3 exec forge create src/Counter.sol:Counter
limechain-web3 exec forge script script/Deploy.s.sol --broadcast
limechain-web3 configure --name bad --chain-id 1 --rpc-url 'https://rpc.example/?key=secret'
limechain-web3 exec solana transfer recipient 1
limechain-web3 exec anchor test
```

## Lightweight Hedera observer

```bash
./install --profile hedera-core
limechain-web3 hedera status
limechain-web3 hedera latest-block
limechain-web3 hedera nodes --json
limechain-web3 hedera account 0.0.3 --json
limechain-web3 hedera network previewnet
limechain-web3 hedera network testnet
```

Confirm installation downloads no Hedera artifact and creates no service. Capture the panel on a small machine and verify Testnet is the default, switching shows a pending state, block and consensus-node data refresh, and the latest-block action opens the matching HashScan network. Confirm malformed account and transaction identifiers are refused before a request, redirects fail closed, output omits account key material and transfer lists, and no request uses POST.

Do not install or start Solo as part of this profile. A future optional Solo lab requires a separate acceptance matrix for resource limits, cleanup, isolation, and all signing material it creates.

## Update and uninstall

1. Update from the previous tagged release and confirm config, menu placement, and projects remain unchanged.
2. Run normal uninstall and confirm project-owned files and service state are removed while configuration/cache remain.
3. Reinstall, run purge uninstall, and confirm configuration/cache are removed.
4. Confirm unrelated Omarchy plugins, menu entries, agent skills, and shell layout remain unchanged after both paths.
5. Run the separate agent-skill opt-in/update/removal lifecycle before plugin removal; confirm base install/uninstall never creates or removes that tree.

Do not run destructive lifecycle tests on a user's daily machine; use a clean VM snapshot.
