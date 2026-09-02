# Update, uninstall, and rollback

## Update

`limechain-web3 update` first requires an unlocked session, snapshots the current Git-managed plugin checkout and Omarchy `shell.json`, asks Omarchy to fast-forward the plugin, validates the new manifest, and reruns the installer. Before touching the active workstation, the installer downloads and verifies bounded artifacts, preflights archives, builds the replacement application, prepares state and service files, and validates the native plugin. If any later step fails, the prior checkout and exact shell configuration are restored before the plugin is rescanned.

The commit phase keeps local backups of the previous application, state, marked service units, CLI link state, menu, and Omarchy shell configuration. Any failure during commit, daemon reload, plugin rescan, or shell restart restores those backups and restarts services that were active before the attempt. The verified cache is outside the rollback set by design: a failed install may leave only size- and checksum-validated cache bytes.

## Uninstall

`limechain-web3 uninstall` preflights every target, stops only the two marked local services, removes the bounded menu block, asks Omarchy to remove its native plugin checkout, removes the owned application/state/command/service files, and leaves the owned configuration and download cache in place.

`limechain-web3 uninstall --purge` also removes `~/.config/limechain-web3` and `~/.cache/limechain-web3`.

The removal set is first moved into a private transaction directory. The native plugin checkout and exact Omarchy shell configuration are snapshotted before the official removal command. If any removal or rescan step fails—even after Omarchy deleted its Git checkout—the checkout, shell state, files, and menu are restored and previously active services are restarted. After Omarchy confirms removal, the private snapshots are deleted.

The normal uninstall is recoverable by reinstalling the same tagged repository; the preserved cache avoids downloading unchanged verified artifacts. A purge is not recoverable unless the configuration was backed up separately.

The optional coding-agent skill has an intentionally separate lifecycle. It is never installed or removed by marketplace/profile lifecycle commands. Run `uninstall-agent-skill` from the plugin checkout before uninstalling the workstation; it refuses removal when its exact managed manifest detects local edits or extra content.

## Emergency disable

If the shell plugin misbehaves:

```bash
omarchy plugin disable limechain.web3
```

This unloads the UI without changing the toolchain or project files.
