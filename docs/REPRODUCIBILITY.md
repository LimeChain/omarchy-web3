# Reproducibility

For this MVP, reproducible means that a clean Omarchy Quattro 4.x installation resolves the same declared profile inputs and verifies the same artifact bytes before installation. EVM and Solana binary profiles currently target x86-64; the binary-free Hedera profile is architecture-neutral.

## Inputs

- `toolchains/evm-core.lock.json` pins upstream release URLs and SHA-256 digests.
- `toolchains/solana-core.lock.json` pins the reviewed Surfpool, Agave CLI, Anchor, and SBF platform-tools release URLs and SHA-256 digests.
- `toolchains/hedera-core.lock.json` explicitly records that the lightweight profile has no downloaded artifacts and supports any Omarchy architecture.
- `toolchains/python-requirements.lock` pins the complete Python dependency graph and hashes.
- `VERSION` identifies the workstation snapshot.
- `sbom/limechain-web3.spdx.json` records the application and toolchain packages.

The lock does not claim bit-for-bit reproducibility of Omarchy or Arch Linux itself. Omarchy is a rolling distribution, so CI records the tested ISO/release and package inventory separately.

## Verification

```bash
jq -e '.schema == 1 and .profile == "evm-core"' toolchains/evm-core.lock.json
jq -e '.schema == 1 and .profile == "solana-core"' toolchains/solana-core.lock.json
jq -e '.schema == 1 and .profile == "hedera-core" and .platform == "any" and (.artifacts | length == 0)' toolchains/hedera-core.lock.json
python3 scripts/verify-lock.py
python3 scripts/generate-sbom.py --check
```

The installer refuses a checksum mismatch and never falls back to an unverified package source.

The sample Anchor workspace commits its complete `Cargo.lock`. Its first build may fetch those locked crates into the workstation's isolated Cargo home; a subsequent `limechain-web3 anchor build . --offline` must succeed without fetching new dependencies. Anchor `1.1.2` selects platform-tools `1.52`; the wrapper requires that exact preinstalled tree and adds `--skip-tools-install`, so `cargo-build-sbf` cannot download a different toolchain.

## AUR policy

The MVP uses no AUR packages. Adding one later requires a pinned recipe revision, committed review notes, a clean isolated build, an SBOM update, and explicit maintainer approval.
