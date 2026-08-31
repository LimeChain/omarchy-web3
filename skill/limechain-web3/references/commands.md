# Guarded command reference

## Workstation

| Goal | Command |
|---|---|
| Verify installation | `limechain-web3 doctor --json` |
| Read status | `limechain-web3 status --json` |
| Enter verified shell | `limechain-web3 shell` |
| Create sample | `limechain-web3 scaffold ./counter` |
| Start local RPC | `limechain-web3 anvil start` |
| Stop local RPC | `limechain-web3 anvil stop` |
| Reset local RPC | `limechain-web3 anvil reset` |

## Verified tools

Use `limechain-web3 exec <tool> ...` for `forge`, `cast`, `node`, `npm`, `npx`, `bun`, `bunx`, `solc`, `solc-select`, `crytic-compile`, `slither`, and `echidna`.

The guard refuses:

- `cast send`, `cast publish`, `cast mktx`, and wallet commands.
- Transaction-submission, personal, and wallet JSON-RPC methods through `cast rpc`.
- `forge create` and any Forge invocation containing `--broadcast`.
- Credential flags including private-key, mnemonic, keystore, password, and AWS signer flags.
- Arbitrary Anvil arguments. Use the fixed `anvil` and `fork` subcommands instead.

## Credential-free chain configuration

```bash
limechain-web3 configure \
  --name Sepolia \
  --chain-id 11155111 \
  --rpc-url https://example-public-sepolia-rpc.invalid \
  --explorer-url https://sepolia.etherscan.io
```

The example RPC hostname is deliberately nonfunctional. Choose a public endpoint that does not put credentials in user information, a query string, or a fragment.
