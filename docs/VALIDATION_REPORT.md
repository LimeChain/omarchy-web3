# Omarchy Quattro validation report

Initial run: 2026-08-31
Latest marketplace-hardening rerun: 2026-09-02

## Tested environment

- Omarchy package: `4.0.2-1`
- Architecture: `x86_64`
- Kernel: `7.1.9-arch1-2`
- Profiles: `evm-core`, `solana-core`, `hedera-core`
- Installation mode: user-scoped managed plugin on an existing Omarchy workstation

The workstation was rebooted after installation. Post-reboot validation confirmed that the Quattro shell, plugin IPC, then-installed agent skill, systemd unit, verified toolchain, and menu entry survived correctly. The agent skill in that historical build has since been removed from the marketplace lifecycle and made a separate explicit opt-in.

## Results

- Lockfiles, SPDX SBOM, metadata, shell syntax, 13 CLI/security unit tests, and isolated multi-profile install/reinstall/uninstall lifecycle: passed.
- Official `omarchy plugin validate`: passed.
- Live Quattro panel rendering and IPC refresh: passed at 3840×2160.
- Foundry build and two tests with 1,000 fuzz runs: passed.
- Slither analysis: one contract, 102 detectors, zero findings.
- Echidna property test: passed with at least 5,000 calls.
- Managed Anvil: loopback-only `127.0.0.1:8545`, chain ID `31337`, zero accounts, and no key or mnemonic output.
- systemd sandbox assessment: `1.2 OK`.
- Signing, private-key, transaction-submission, and deployment guard tests: refused as designed.
- Real uninstall/reinstall: passed; credential-free configuration and verified download cache were preserved.
- Final Anvil state: running and healthy for panel inspection.

## Solana Surfpool validation

- Pinned artifact: Surfpool `1.5.0`; downloaded release bytes matched SHA-256 `5b20a3b46e60c4f819af7b4da5c3ea211f76041710617841cc23247d15887ddc`.
- Managed runtime: healthy local Solana JSON-RPC on `127.0.0.1:8899` and WebSocket on `127.0.0.1:8900`.
- Process boundary: `--offline`, `--no-deploy`, in-memory state, zero startup airdrop, `/dev/null` keypair path, and no external established socket.
- systemd boundary: no capabilities, `NoNewPrivileges`, private user namespace, home hidden with `ProtectHome=tmpfs`, and IP filtering that denies every destination except localhost.
- systemd sandbox assessment: `1.2 OK`.
- Start, status, Reset, health recovery, Quattro IPC refresh, profile coexistence, and arbitrary Surfpool/MCP refusal: passed.
- Final Surfpool state: running so the new panel state can be inspected on the validation workstation.

## Solana CLI and Anchor validation

The guarded developer layer was validated on the same x86-64 Omarchy host from an isolated user-scoped prefix while the active Quattro session was locked. The installer correctly refused to replace or reload the active plugin during that lock state.

- Verified artifacts: Agave/Solana CLI `4.2.2`, Anchor CLI `1.1.2`, Anchor-compatible SBF platform-tools `1.52`, and Surfpool `1.5.0`; every extracted-tree manifest and tool check passed.
- Local CLI inspection: `version`, `slot`, `epoch`, `block-height`, `genesis-hash`, and `cluster-version` succeeded against offline Surfpool on `127.0.0.1:8899`.
- Runtime compatibility: Solana CLI `4.2.2` inspected Surfpool's Solana core `4.1.2` without a wallet or Solana config home.
- Guard negatives: arbitrary `solana transfer` and `anchor test` invocations were refused before upstream execution.
- Fresh sample: the bundled Anchor workspace compiled from its committed `Cargo.lock` with network access disabled after the isolated Cargo cache was populated.
- Reproducible output: repeated release builds produced `limechain_anchor_counter.so` SHA-256 `6433a5b3c237e44ba0f0a932dc0a107a886301e8590978639f618222edf46bcd`.
- Key boundary: the final guarded online/offline builds left no `*-keypair.json` path anywhere in either sample tree.

Live validation exposed two upstream behaviors that materially changed the guard design. Anchor `1.1.2` hardcodes SBF platform-tools `1.52`, so the initial newer `1.56` candidate was replaced with the compatible pinned artifact instead of overriding Anchor. More importantly, `cargo-build-sbf` generates a program keypair during post-processing even when Anchor receives `--ignore-keys`. The one keypair produced by the discovery run was immediately deleted from the temporary test workspace. The corrected wrapper now reserves every explicit cdylib program's expected keypair output as a temporary `/dev/null` symlink and removes the sentinel on every exit path. A fresh build then confirmed successful bytecode output with no generated keypair.

The full-workstation regression pass also found that the first managed-plugin replacement stopped already-running Anvil and Surfpool units while Omarchy reloaded. The installer now snapshots both user units before any managed update and restores only those that were active after `daemon-reload`. A fake-systemd lifecycle regression test verifies that inactive services remain inactive while active services are restored.

The active Quattro plugin was then updated after the physical session was unlocked. `doctor --json`, Omarchy plugin validation, fixed Solana read-only queries, Surfpool control, and the guarded Anchor workflow all passed from the installed user-scoped paths.

## Hedera lightweight profile validation

Date: 2026-09-01

The `hedera-core` candidate was validated on the same Omarchy x86-64 host from an isolated temporary source tree and user-scoped install prefix. The active `v0.1.0` marketplace-review checkout was not modified.

- The complete local regression suite passed: lock/SBOM verification, 15 CLI and security tests, and multi-profile install/reinstall/uninstall lifecycle.
- The profile lock is architecture-neutral and contains zero artifacts. Isolated installation downloaded no Hedera binary, created no Hedera service, and passed official `omarchy plugin validate`.
- The guarded Python client reached the official Testnet and Previewnet Mirror Node endpoints using the host's system CA store.
- Live block, consensus-node, and account lookups passed. Testnet reported a current block, seven consensus nodes, and HAPI `0.76.1` during the run.
- Network switching returned to Testnet after validation. Invalid path-like account input was refused before any request.
- Curated account output omitted the upstream account-key object; transaction transfer lists are likewise not forwarded by the wrapper.
- No Solo, Docker, Kubernetes, account funding, signing, or transaction submission path was installed or started.

The active-panel pass was completed later the same day after the physical session was confirmed unlocked. The installer safely reloaded the plugin, preserved the inactive state of both local services, and the panel rendered fully at 3840×2160 with live Hedera Testnet block, seven-node, HAPI, and latency data. Direct plugin IPC refresh/status returned schema 3 and all three installed profiles.

The coexistence smoke test then started Anvil and Surfpool together while the Hedera observer remained healthy. Anvil block 0, Surfpool slot 0, and a live Hedera Testnet block were visible simultaneously. This pass exposed that Surfpool handles interactive `SIGINT` but did not exit on systemd's default `SIGTERM`, causing Reset to exceed the CLI's ten-second timeout. The unit now uses `KillSignal=SIGINT` with a five-second bounded stop; start/reset/stop was repeated after the correction, and both local services were returned to their original inactive state.

The first service draft used `MemoryDenyWriteExecute=true`. Live startup correctly revealed that Surfpool's Solana BPF loader needs executable-memory permission for `mprotect`; the service failed closed before opening an RPC socket. That single incompatible directive was removed while all network, home, privilege, namespace, and capability controls remained in place. A regression test retains the fixed offline and non-custodial service arguments.

## Incident and correction

An early installer revision rewrote unchanged plugin files and unconditionally requested a Quattro plugin rescan. When this happened while the screen was locked, Quickshell hit a lockscreen reload race and Hyprland displayed its crashed-lock failsafe.

The corrected installer now:

1. Compares plugin content and performs no write or rescan when it is unchanged.
2. Refuses a genuine plugin reload when the Omarchy session is locked or its lock state cannot be determined.
3. Replaces a changed managed plugin atomically when the session is confirmed unlocked.
4. Uses Omarchy's official shell restart after a genuine plugin change so Quattro does not retain a panel instance attached to the replaced directory.

Regression tests cover the locked-session refusal and unchanged-plugin inode preservation. On the live workstation, two corrected installer runs produced zero `limechain.web3` reload events.

## Panel UX correction

Live testing exposed that Quattro's shared `Button` component does not visually or behaviorally honor QML's standard `enabled` property. The first panel therefore left Start, Stop, and Reset looking actionable at the same time, even when Anvil was already active.

The corrected panel uses mutually exclusive visibility and explicit pending states: stopped shows only **Start local Anvil**; starting shows **Starting...**; active shows only **Stop** and **Reset**. It also separates the account-free local Anvil RPC from the optional remote observer, explains why no remote endpoint is configured by default, and provides a terminal-based setup guide. The live 3840x2160 panel was revalidated with Anvil active: service healthy, RPC healthy, chain ID `31337`, block `0`, and only Stop/Reset visible.

## Marketplace-hardening exact-commit rerun

The functional tree at commit `e0ee80b6df7a8c6e544b06c9768dc2674f83ef54` was rerun on 2026-09-02 on the x86-64 Omarchy `4.0.2-1` host with kernel `7.1.9-arch1-2`. This was an existing daily workstation, not a clean-ISO VM. A Btrfs migration snapshot was taken before replacing the experimental `0.2.0` managed copy with an Omarchy-native Git checkout. Destructive live uninstall/purge testing was intentionally not performed on the daily workstation; those paths ran only in the isolated temporary-HOME lifecycle suite.

- The native checkout passed `omarchy plugin validate`, remained clean at the exact commit, loaded as the enabled `limechain.web3` bar widget, and answered Quattro shell IPC.
- The profile installer completed for `evm-core`, `solana-core`, and `hedera-core`; a repeated EVM install preserved byte-identical Omarchy menu and shell configuration. The final state recorded all three profiles, with no optional agent skill installed.
- `doctor --json` passed all 44 installed-workstation checks, including every artifact tree manifest, pinned tool version, service unit, native plugin checkout, configuration permissions, and the intentionally absent optional skill.
- The same exact checkout passed 27 Python CLI/security/supply-chain tests plus the isolated install, repeat-install, update rollback, destructive-remove rollback, normal uninstall, purge uninstall, collision, symlink, and explicit agent-skill lifecycle suite directly on Arch/Omarchy.
- The EVM sample compiled with Solidity `0.8.36`; two Forge tests passed, including 256 fuzz cases. Slither analyzed one contract with 102 detectors and zero findings. Echidna passed the bounded-counter property after approximately 5,100 calls.
- Managed Anvil reported chain ID `31337` on `127.0.0.1:8545`, ran with `--accounts 0 --silent`, exposed no key or mnemonic markers in its journal, and passed start/reset/stop.
- Offline Surfpool served RPC/WebSocket only on `127.0.0.1:8899/8900`, used an in-memory database, `--no-deploy`, zero airdrop, and `/dev/null` as its fixed airdrop keypair path. It had zero external established connections and passed Solana version/slot/epoch plus start/reset/stop.
- Guarded Anchor online and offline builds produced the same program SHA-256, `6433a5b3c237e44ba0f0a932dc0a107a886301e8590978639f618222edf46bcd`, and left zero `*-keypair.json` files.
- The lightweight Hedera observer reached official Testnet and Previewnet Mirror Nodes, reported `mode: read-only`, returned live block/seven-node/account data, omitted upstream key and transfer fields, rejected malformed identifiers before a request, and returned to Testnet. It installed zero Hedera artifacts and zero services.
- Anvil, Surfpool, and the Hedera observer were healthy simultaneously. The only listeners were the declared loopback ports, and both managed services were returned to inactive state after testing.
- Nine live negative commands—Cast send/private-key, Forge create/broadcast, credential-bearing RPC configuration, Solana transfer, Anchor test, Surfpool MCP, and remote Surfpool start—were refused before upstream execution.

The rerun found and corrected three integration/UX defects before publication: `doctor` incorrectly treated the optional agent skill as required; production update leaked internally resolved `LCW3_*` paths into the child installer; and direct Hedera status omitted the explicit read-only mode present in the combined status schema. Regression coverage was added for all three. A stale crashed-lock marker also caused the installer to fail closed twice before commit; both attempts left no partial app, state, CLI, unit, menu, or transaction files, providing an additional live rollback observation.

Version `0.3.0` now has exact-commit live coverage on an existing Omarchy host for the marketplace-review hardening described in `MARKETPLACE_REVIEW.md`: separate explicit agent-skill lifecycle, bounded/origin-restricted downloads, malicious-archive preflight, link-free derived artifacts, ownership markers, collision checks, transactional install/update rollback, and fail-closed session handling.

## Remaining release validation

Before a public application release, run the documented matrix on a clean VM made from the latest stable Omarchy ISO, repeat it with network access disabled after installation, and test update from a previous signed tag. This existing workstation validation does not claim those clean-ISO checks.
