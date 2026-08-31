# Omarchy Quattro validation report

Date: 2026-08-31

## Tested environment

- Omarchy package: `4.0.2-1`
- Architecture: `x86_64`
- Kernel: `7.1.9-arch1-2`
- Profiles: `evm-core`, `solana-core`
- Installation mode: user-scoped managed plugin on an existing Omarchy workstation

The workstation was rebooted after installation. Post-reboot validation confirmed that the Quattro shell, plugin IPC, agent skill, systemd unit, verified toolchain, and menu entry survived correctly.

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

The full-workstation regression pass also found that the first managed-plugin replacement stopped already-running Anvil and Surfpool units while Omarchy reloaded. The installer now snapshots both user units before any managed update and starts only those that were active after `daemon-reload`; an idempotent update leaves their existing PIDs untouched. A fake-systemd lifecycle regression test verifies that inactive services remain inactive while active services are restored.

The active Quattro plugin was then updated after the physical session was unlocked. `doctor --json`, Omarchy plugin validation, fixed Solana read-only queries, Surfpool control, and the guarded Anchor workflow all passed from the installed user-scoped paths.

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

## Remaining release validation

Before a public release, run the documented matrix on a clean VM made from the latest stable Omarchy ISO, repeat it with network access disabled after installation, and test update from a previous signed tag. This existing workstation validation does not claim those clean-ISO checks.
