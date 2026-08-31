# LimeChain Web3 Workstation for Omarchy

An open-source, additive, reproducible EVM development and chain-inspection environment for Omarchy Quattro. It is deliberately not a wallet, signing surface, trading tool, or price ticker.

## MVP status

The `evm-core` implementation is under active development. Bitcoin and Solana profiles are explicitly outside the ten-day MVP.

## Install

Review the repository, then install it through Quattro's native plugin flow and run the pinned workstation installer:

```bash
omarchy plugin add https://github.com/limechain/omarchy-web3.git --enable --yes && ~/.config/omarchy/plugins/limechain.web3/install --profile evm-core
```

This is a single shell line without an unpinned `curl | bash`. The installer is user-scoped, invokes neither `sudo` nor `yay`, and can be run repeatedly.

After installation:

```bash
limechain-web3 doctor
limechain-web3 scaffold ~/Code/limechain-counter
cd ~/Code/limechain-counter
limechain-web3 exec forge build
limechain-web3 exec forge test
```

## How the panel works

The panel has two independent parts:

- **Local Anvil** is an account-free development chain on `http://127.0.0.1:8545` with chain ID `31337`. It works without internet access or a remote RPC. When stopped, the panel shows only **Start local Anvil**; while running, it shows only **Stop** and **Reset**.
- **Remote observer** is optional, read-only telemetry for a public chain or testnet. It is deliberately unconfigured by default so installation never chooses or contacts a third-party RPC service on the user's behalf.

Starting Anvil does not configure the remote observer. A fresh local chain starts at block 0; **Reset** returns it to a clean block-0 state. The panel never provides accounts, signing, or transaction submission.

Configure optional remote telemetry only with a credential-free public RPC URL:

```bash
limechain-web3 configure \
  --name Sepolia \
  --chain-id 11155111 \
  --rpc-url https://your-public-endpoint.example \
  --explorer-url https://sepolia.etherscan.io
```

URLs containing usernames, passwords, query parameters, or fragments are rejected.

## What is installed

- Verified Foundry (`forge`, `cast`, `anvil`, `chisel`), Node.js LTS, Bun, Solidity, Slither, Echidna, `solc-select`, and `uv` artifacts.
- A Quattro bar widget showing read-only block, fee, and RPC-health data.
- Fixed `systemd --user` controls for a loopback-only, silent Anvil service with zero accounts.
- An Omarchy menu section and a cross-agent skill under `~/.agents/skills/limechain-web3`.
- A dependency-free sample contract with unit, fuzz, Slither, and Echidna smoke-test paths.

The verified tools live under `~/.local/share/limechain-web3`; the installer does not replace an existing global Node, Bun, Foundry, Python, or Solidity setup. Use `limechain-web3 exec …` or `limechain-web3 shell`.

## Non-custodial boundary

The project does not implement wallet discovery, credential storage, key generation, seed handling, signing, transaction submission, exchange automation, or mainnet deployment. Guarded wrappers reject signing/broadcast commands and credential flags. Quickshell plugins remain unsandboxed user code, so the small plugin delegates all work to a fixed CLI surface.

See [SECURITY.md](docs/SECURITY.md), [THREAT_MODEL.md](docs/THREAT_MODEL.md), and [REPRODUCIBILITY.md](docs/REPRODUCIBILITY.md).

The latest real-host results and the corrected Quattro lockscreen reload race are documented in [VALIDATION_REPORT.md](docs/VALIDATION_REPORT.md).

## Lifecycle

```bash
limechain-web3 update
limechain-web3 uninstall
limechain-web3 uninstall --purge
```

Normal uninstall preserves the credential-free configuration and verified download cache. `--purge` removes them as well. See [ROLLBACK.md](docs/ROLLBACK.md).

## License

MIT. Third-party tools retain their upstream licenses; the SBOM records them as separate packages.
