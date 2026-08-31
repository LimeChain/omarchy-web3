---
name: limechain-web3
description: Safely build, inspect, compile, test, fuzz, statically analyze, and run local EVM or offline Solana projects on an Omarchy LimeChain Web3 Workstation. Use this skill for Solidity, Foundry, Forge, Cast, Anvil, Slither, Echidna, Surfpool, read-only Solana CLI, guarded Anchor compilation, local RPC, contract scaffolding, local chains, or read-only chain inspection on Omarchy. Keep all work non-custodial: never handle keys or seed phrases, sign or submit transactions, broadcast deployments, or deploy to mainnet.
compatibility: Requires the `limechain-web3` command and an installed `evm-core` or `solana-core` profile.
---

# LimeChain Web3 Workstation

Use the verified workstation wrappers so the project remains reproducible and the non-custodial boundary stays visible.

## Start every task with a preflight

1. Run `limechain-web3 doctor --json`.
2. Stop if the lockfile, required tool, configuration-permission, or Omarchy checks fail. Explain the failed check; do not silently install an alternate tool.
3. Inspect the target project before changing it. Preserve its compiler version and existing test conventions when they are compatible with the verified toolchain.

Read [references/commands.md](references/commands.md) for the supported command surface and examples.

## Safety boundary

This workstation is for development, testing, fuzzing, static analysis, local simulation, and read-only chain inspection.

Refuse requests that require any of the following:

- Reading, generating, importing, exporting, copying, transforming, or storing private keys, seed phrases, mnemonics, keystores, wallet passwords, or signing devices.
- Looking through wallet folders, browser profiles, shell history, environment variables, clipboard history, password managers, or hardware-wallet state for credentials.
- Signing messages or transactions.
- Submitting transactions, invoking `cast send`, calling transaction-submission JSON-RPC methods, or broadcasting Forge scripts.
- Deploying to mainnet or automating a mainnet deployment.
- Embedding credentials in RPC URLs. URLs with user information, query parameters, or fragments are outside the supported boundary.

When refusing, state the exact boundary and offer a safe alternative such as a local account-free Anvil instance, a dependency-free unit test, a fuzz test, a dry simulation, or a read-only `cast call`.

These instructions guide agent behavior; they are not an operating-system sandbox. The Quickshell plugin is also unsandboxed, so do not ask it to access anything outside its fixed status and Anvil-control commands.

## Supported workflows

### Scaffold

Use `limechain-web3 scaffold <new-directory>`. Never scaffold over an existing path. The bundled Counter project has no external Solidity dependency.

### Compile and test

Run tools through the guard:

```bash
limechain-web3 exec forge build
limechain-web3 exec forge test
limechain-web3 exec forge test --fuzz-runs 1000
```

Do not add `--broadcast`, credential flags, or deployment commands.

### Static analysis and property testing

```bash
limechain-web3 exec slither .
limechain-web3 exec echidna test/CounterEchidna.sol --contract CounterEchidna --config echidna.yaml
```

Report findings; do not automatically weaken detectors or property thresholds just to make a run green.

### Local RPC

Use only fixed controls:

```bash
limechain-web3 anvil start
limechain-web3 status --json
limechain-web3 anvil stop
```

The managed service binds only to loopback and starts with zero accounts, so it emits no development keys.

### Offline Solana RPC

Use only the fixed Surfpool controls:

```bash
limechain-web3 surfpool start
limechain-web3 status --json
limechain-web3 surfpool reset
limechain-web3 surfpool stop
```

The service is pinned to offline mode, loopback, in-memory state, no deployments, no startup airdrop, and `/dev/null` instead of the default Solana keypair path. Do not run arbitrary `surfpool start` flags, enable a remote datasource, expose Surfpool MCP, or access Solana wallet/keypair files.

Use only the fixed read-only Solana queries:

```bash
limechain-web3 solana version
limechain-web3 solana slot
limechain-web3 solana epoch
limechain-web3 solana block-height
limechain-web3 solana genesis-hash
limechain-web3 solana transaction-count
limechain-web3 solana cluster-version
```

For Anchor, scaffold only into a new directory and compile only through the guarded command:

```bash
limechain-web3 anchor version
limechain-web3 anchor scaffold ./anchor-counter
limechain-web3 anchor build ./anchor-counter
limechain-web3 anchor build ./anchor-counter --offline
```

Do not invoke or emulate `anchor init`, `new`, `test`, `localnet`, `deploy`, `keys`, `account`, `migrate`, or `idl` commands. Do not bypass a refusal caused by a wallet path, build hook, automatic client generator, version override, missing `Cargo.lock`, or existing `*-keypair.json` file.

### Read-only local fork

Use `limechain-web3 fork --rpc-url <credential-free-public-url>` only when the user explicitly supplies or approves that public endpoint. The command must remain foreground-bound, loopback-only, silent, and account-free. Never convert a provider key into a URL or retrieve a provider credential from the environment.

### Read-only chain inspection

Permitted Cast operations include read-only calls such as `call`, `block`, `code`, `storage`, `logs`, and `chain-id`. Confirm the target chain before interpreting results. Prefer testnets unless the user explicitly asks to inspect mainnet state; inspecting state is allowed, deploying or submitting is not.

## Completion report

Conclude with:

- Files changed or created.
- Verified tool versions used.
- Compile, unit-test, fuzz, Slither, and Echidna results that were actually run.
- Whether local Anvil, Surfpool, or a local fork remains running.
- Any skipped check and the concrete reason it was skipped.

Do not claim a test or analysis passed unless its command completed successfully.
