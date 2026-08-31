# Security policy and operating boundary

## Supported use

This project supports compilation, unit tests, fuzzing, static analysis, local account-free EVM RPC execution, offline local Solana RPC execution, guarded keypair-free Anchor compilation, credential-free local forks, and read-only chain inspection.

It does not support keys, seed phrases, signing, transaction submission, wallets, exchanges, or mainnet deployment. Do not report the absence of those features as a vulnerability; report any path that unexpectedly performs one of those actions.

## Reporting

Report vulnerabilities privately through the security-advisory feature of the GitHub repository. Do not include real credentials, wallet files, seed phrases, or private keys in a report or test fixture.

## Controls

- Artifact URLs, versions, and SHA-256 digests are locked.
- Python dependencies are fully resolved with hashes.
- The tool wrapper rejects known signing, broadcast, wallet, and credential arguments.
- RPC configuration rejects URL user information, query strings, and fragments.
- The managed Anvil service binds to loopback, runs silently, and creates zero accounts.
- The managed Surfpool service is fixed to offline mode, loopback, in-memory state, no deployment, no startup airdrop, and no home-directory access.
- Solana CLI runs with an isolated empty home and only fixed read-only commands against the configured loopback RPC.
- Anchor builds require `Localnet`, `/dev/null` as the wallet path, a committed `Cargo.lock`, no build hooks, no automatic client generation, and no program-keypair files.
- The guarded Anchor command injects `--ignore-keys`, `--no-idl`, and `--skip-tools-install`, requires Anchor's pinned compatible SBF platform-tools tree, and reserves every expected `*-keypair.json` output as a temporary `/dev/null` symlink so `cargo-build-sbf` cannot generate a program keypair. The sentinels are removed after every build outcome.
- The Quickshell plugin invokes only the status command, fixed Anvil/Surfpool controls, and validated explorer opening.
- Configuration is stored with mode `0600` and rejected if it contains sensitive-looking fields.

These are defense-in-depth controls, not a sandbox. The underlying tools are powerful developer software, and Quickshell plugins run with the user's access.

Cargo dependencies and project build scripts are executable code. Anchor compilation therefore runs with a stripped environment and isolated home, but users must still review project dependencies before building them. See [SOLANA_SECURITY_REVIEW.md](SOLANA_SECURITY_REVIEW.md).
