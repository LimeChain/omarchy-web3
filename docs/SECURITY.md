# Security policy and operating boundary

## Supported use

This project supports compilation, unit tests, fuzzing, static analysis, local account-free EVM RPC execution, offline local Solana RPC execution, guarded keypair-free Anchor compilation, credential-free local forks, and read-only EVM, Solana, and Hedera inspection.

It does not support keys, seed phrases, signing, transaction submission, wallets, exchanges, or mainnet deployment. Do not report the absence of those features as a vulnerability; report any path that unexpectedly performs one of those actions.

## Reporting

Report vulnerabilities privately through the security-advisory feature of the GitHub repository. Do not include real credentials, wallet files, seed phrases, or private keys in a report or test fixture.

## Controls

- Artifact URLs, versions, exact byte sizes, redirect/final-origin allowlists, and SHA-256 digests are locked. Downloads are streamed with byte and free-disk limits into exclusive non-symlink temporary files.
- Archive preflight rejects absolute/traversal paths, duplicates, symlinks, hardlinks, devices, FIFOs, encrypted ZIP entries, unexpected top-level entries, excessive file counts, oversized files, and excessive uncompressed totals before writing a member. Extraction is manual and uses exclusive `O_NOFOLLOW` outputs.
- The two upstream archives that contain links (Node and SBF platform-tools) are transformed reproducibly into link-free derived archives. Any required internal platform-tool links are declared in the lock and materialized only after regular-file extraction; extracted links are never followed for chmod or binary installation.
- Python dependencies are fully resolved with hashes.
- The tool wrapper rejects known signing, broadcast, wallet, and credential arguments.
- RPC configuration rejects URL user information, query strings, and fragments.
- The managed Anvil service binds to loopback, runs silently, and creates zero accounts.
- The managed Surfpool service is fixed to offline mode, loopback, in-memory state, no deployment, no startup airdrop, and no home-directory access.
- Solana CLI runs with an isolated empty home and only fixed read-only commands against the configured loopback RPC.
- Anchor builds require `Localnet`, `/dev/null` as the wallet path, a committed `Cargo.lock`, no build hooks, no automatic client generation, and no program-keypair files.
- The guarded Anchor command injects `--ignore-keys`, `--no-idl`, and `--skip-tools-install`, requires Anchor's pinned compatible SBF platform-tools tree, and reserves every expected `*-keypair.json` output as a temporary `/dev/null` symlink so `cargo-build-sbf` cannot generate a program keypair. The sentinels are removed after every build outcome.
- The Quickshell plugin invokes only the status command, fixed Anvil/Surfpool controls, and validated explorer opening.
- The Hedera profile uses only fixed official Mirror Node and HashScan bases, GET requests, bounded responses, curated output fields, and validated identifiers; it installs no runtime and never invokes Solo.
- Configuration is stored with mode `0600` and rejected if it contains sensitive-looking fields.
- Application, configuration, state, cache, copied-plugin, service, and optional-skill ownership are explicit. Existing unmarked paths, foreign owners, symlink components, and unmanaged service files are refused.
- Installation builds the complete replacement under a private staging directory. The active app, state, services, CLI link, and menu are committed together and restored from local backups on failure.
- Coding-agent behavioral instructions are never installed by the marketplace or profile installer. Their fixed-path installer and uninstaller require a separate explicit command and an exact managed-tree manifest.

These are defense-in-depth controls, not a sandbox. The underlying tools are powerful developer software, and Quickshell plugins run with the user's access.

Cargo dependencies and project build scripts are executable code. Anchor compilation therefore runs with a stripped environment and isolated home, but users must still review project dependencies before building them. See [SOLANA_SECURITY_REVIEW.md](SOLANA_SECURITY_REVIEW.md) and [HEDERA_SECURITY_REVIEW.md](HEDERA_SECURITY_REVIEW.md).
