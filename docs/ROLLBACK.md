# Update, uninstall, and rollback

## Update

`limechain-web3 update` asks Omarchy to fast-forward the Git-managed plugin, validates the new manifest, and reruns the installer. Before touching the active workstation, the installer downloads and verifies bounded artifacts, preflights archives, builds the replacement application, prepares state and service files, and validates the native plugin.

The commit phase keeps local backups of the previous application, state, marked service units, CLI link state, and menu. Any failure during commit, daemon reload, plugin rescan, or shell restart restores those backups and restarts services that were active before the attempt. The verified cache is outside the rollback set by design: a failed install may leave only size- and checksum-validated cache bytes.

## Uninstall

`limechain-web3 uninstall` preflights every target, stops only the two marked local services, removes the bounded menu block, asks Omarchy to remove its native plugin checkout, removes the owned application/state/command/service files, and leaves the owned configuration and download cache in place.

`limechain-web3 uninstall --purge` also removes `~/.config/limechain-web3` and `~/.cache/limechain-web3`.

The removal set is first moved into a private transaction directory. If a local removal step fails, files and the menu are restored and previously active services are restarted. After Omarchy confirms removal of its own checkout, the transaction is deleted.

The normal uninstall is recoverable by reinstalling the same tagged repository; the preserved cache avoids downloading unchanged verified artifacts. A purge is not recoverable unless the configuration was backed up separately.

The optional coding-agent skill has an intentionally separate lifecycle. It is never installed or removed by marketplace/profile lifecycle commands. Run `uninstall-agent-skill` from the plugin checkout before uninstalling the workstation; it refuses removal when its exact managed manifest detects local edits or extra content.

## Emergency disable

If the shell plugin misbehaves:

```bash
omarchy plugin disable limechain.web3
```

This unloads the UI without changing the toolchain or project files.
