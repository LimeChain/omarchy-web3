# Omarchy Quattro validation report

Date: 2026-08-31

## Tested environment

- Omarchy package: `4.0.2-1`
- Architecture: `x86_64`
- Kernel: `7.1.9-arch1-2`
- Profile: `evm-core`
- Installation mode: user-scoped managed plugin on an existing Omarchy workstation

The workstation was rebooted after installation. Post-reboot validation confirmed that the Quattro shell, plugin IPC, agent skill, systemd unit, verified toolchain, and menu entry survived correctly.

## Results

- Lockfile, SPDX SBOM, metadata, shell syntax, eight CLI/security unit tests, and isolated install/reinstall/uninstall lifecycle: passed.
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
