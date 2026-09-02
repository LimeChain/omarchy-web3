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
| Start offline Solana RPC | `limechain-web3 surfpool start` |
| Stop offline Solana RPC | `limechain-web3 surfpool stop` |
| Reset offline Solana RPC | `limechain-web3 surfpool reset` |
| Read local Solana slot | `limechain-web3 solana slot` |
| Create safe Anchor sample | `limechain-web3 anchor scaffold ./anchor-counter` |
| Compile Anchor sample | `limechain-web3 anchor build ./anchor-counter` |
| Rebuild from cache | `limechain-web3 anchor build ./anchor-counter --offline` |
| Read Hedera status | `limechain-web3 hedera status` |
| Read latest Hedera block | `limechain-web3 hedera latest-block` |
| List Hedera consensus nodes | `limechain-web3 hedera nodes --json` |
| Inspect a Hedera account | `limechain-web3 hedera account 0.0.3 --json` |
| Inspect a Hedera transaction | `limechain-web3 hedera transaction '0.0.3@1750000000.000000001' --json` |
| Select official Hedera network | `limechain-web3 hedera network testnet` |

## Verified tools

Use `limechain-web3 exec <tool> ...` for `forge`, `cast`, `node`, `npm`, `npx`, `bun`, `bunx`, `solc`, `solc-select`, `crytic-compile`, `slither`, and `echidna`. Solana and Anchor use their dedicated fixed subcommands above.

The guard refuses:

- `cast send`, `cast publish`, `cast mktx`, and wallet commands.
- Transaction-submission, personal, and wallet JSON-RPC methods through `cast rpc`.
- `forge create` and any Forge invocation containing `--broadcast`.
- Credential flags including private-key, mnemonic, keystore, password, and AWS signer flags.
- Arbitrary Anvil arguments. Use the fixed `anvil` and `fork` subcommands instead.
- Arbitrary Surfpool commands, remote datasources, MCP, keypair, payer, and airdrop-keypair flags. Use the fixed `surfpool` subcommand instead.
- Arbitrary Solana CLI commands, including config, keygen, airdrop, transfer, program, stake, vote, and transaction operations.
- Anchor init/new/test/localnet/deploy/keys/account/migrate/IDL commands and builds that could load keys, run lifecycle hooks, change toolchains, or generate clients.
- Arbitrary Hedera endpoints, write requests, account creation/funding, transaction submission, and Solo startup. Hedera commands use fixed public Mirror Node endpoints and curated read-only output.

## Credential-free chain configuration

```bash
limechain-web3 configure \
  --name Sepolia \
  --chain-id 11155111 \
  --rpc-url https://example-public-sepolia-rpc.invalid \
  --explorer-url https://sepolia.etherscan.io
```

The example RPC hostname is deliberately nonfunctional. Choose a public endpoint that does not put credentials in user information, a query string, or a fragment.
