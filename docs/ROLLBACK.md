# Update, uninstall, and rollback

## Update

`limechain-web3 update` asks Omarchy to fast-forward the Git-managed plugin, validates the new manifest, and reruns the idempotent installer. Omarchy refuses a plugin update it cannot fast-forward or validate.

## Uninstall

`limechain-web3 uninstall` stops the local service, removes the managed menu block and agent skill, asks Omarchy to remove the plugin, removes the verified environment, and leaves the configuration and download cache in place.

`limechain-web3 uninstall --purge` also removes `~/.config/limechain-web3` and `~/.cache/limechain-web3`.

The normal uninstall is recoverable by reinstalling the same tagged repository; the preserved cache avoids downloading unchanged verified artifacts. A purge is not recoverable unless the configuration was backed up separately.

## Emergency disable

If the shell plugin misbehaves:

```bash
omarchy plugin disable limechain.web3
```

This unloads the UI without changing the toolchain or project files.
