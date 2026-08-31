# Keypair-free Anchor counter

This sample exists to validate the guarded Anchor compile path. It contains a
fixed public program address and no wallet, seed phrase, private key, or
program-keypair file.

```bash
limechain-web3 anchor build .
limechain-web3 anchor build . --offline
```

The wrapper always adds `--ignore-keys`, uses the pinned SBF platform tools,
points Anchor's required wallet field at `/dev/null`, and reserves the expected
program-keypair output as `/dev/null` while `cargo-build-sbf` runs. It does not expose
`anchor init`, `test`, `localnet`, `deploy`, `keys`, or transaction commands.
