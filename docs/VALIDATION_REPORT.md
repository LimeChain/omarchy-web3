# Omarchy Quattro validation report

Date: 2026-08-31

## Tested environment

- Omarchy package: `4.0.2-1`
- Architecture: `x86_64`
- Kernel: `7.1.9-arch1-2`
- Profiles: `evm-core`, `solana-core` Surfpool preview
- Installation mode: user-scoped managed plugin on an existing Omarchy workstation

The workstation was rebooted after installation. Post-reboot validation confirmed that the Quattro shell, plugin IPC, agent skill, systemd unit, verified toolchain, and menu entry survived correctly.

## Results

- Lockfiles, SPDX SBOM, metadata, shell syntax, 11 CLI/security unit tests, and isolated multi-profile install/reinstall/uninstall lifecycle: passed.
- Official `omarchy plugin validate`: passed.
- Live Quattro panel rendering and IPC refresh: passed at 3840×2160.
- Foundry build and two tests with 1,000 fuzz runs: passed.
- Slither analysis: one contract, 102 detectors, zero findings.
- Echidna property test: passed with at least 5,000 calls.
- Managed Anvil: loopback-only `127.0.0.1:8545`, chain ID `31337`, zero accounts, and no key or mnemonic output.
- systemd sandbox assessment: `1.2 OK`.
- Signing, private-key, transaction-submission, and deployment guard tests: refused as designed.
- Real uninstall/reinstall: passed; credential-free configuration and verified download cache were preserved.
- Final Anvil state: stopped.

## Solana Surfpool preview validation

- Pinned artifact: Surfpool `1.5.0`; downloaded release bytes matched SHA-256 `5b20a3b46e60c4f819af7b4da5c3ea211f76041710617841cc23247d15887ddc`.
- Managed runtime: healthy local Solana JSON-RPC on `127.0.0.1:8899` and WebSocket on `127.0.0.1:8900`.
- Process boundary: `--offline`, `--no-deploy`, in-memory state, zero startup airdrop, `/dev/null` keypair path, and no external established socket.
- systemd boundary: no capabilities, `NoNewPrivileges`, private user namespace, home hidden with `ProtectHome=tmpfs`, and IP filtering that denies every destination except localhost.
- systemd sandbox assessment: `1.2 OK`.
- Start, status, Reset, health recovery, Quattro IPC refresh, profile coexistence, and arbitrary Surfpool/MCP refusal: passed.
- Final Surfpool state: running so the new panel state can be inspected on the validation workstation.

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
