# Wallet and hardware-wallet compatibility

Wallets remain outside this workstation. Use the configured normal browser and the vendors' official documentation:

- [MetaMask Support](https://support.metamask.io/)
- [Rabby Wallet](https://rabby.io/)
- [Ledger Support](https://support.ledger.com/)
- [Trezor Learn](https://trezor.io/learn)

Do not install wallet interfaces as Omarchy web-app wrappers for signing. Thin wrappers have known limitations with credential tooling, and an unsandboxed shell plugin is not an appropriate signing surface.

The workstation does not detect browser extensions or USB devices, alter udev rules, open wallet sessions, request signatures, or provide troubleshooting that requires exposing secrets.
