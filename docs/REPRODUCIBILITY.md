# Reproducibility

For this MVP, reproducible means that a clean Omarchy Quattro 4.x installation resolves the same declared profile inputs and verifies the same artifact bytes before installation. EVM and Solana binary profiles currently target x86-64; the binary-free Hedera profile is architecture-neutral.

## Inputs

- `toolchains/evm-core.lock.json` pins release URLs, exact compressed sizes, redirect origins, SHA-256 digests, archive expansion limits, expected roots, and command mappings.
- `toolchains/solana-core.lock.json` applies the same contract to Surfpool, Agave CLI, Anchor, and SBF platform-tools.
- `toolchains/DERIVED_ARTIFACTS.md` records the reproducible transform for the two upstream archives that contain symlinks. GitHub Actions rebuilds the ordinary-file-only ZIPs from exact upstream bytes, checks the reviewed output size/hash, publishes provenance attestations, and creates the immutable `toolchains-v1` release.
- `toolchains/hedera-core.lock.json` explicitly records that the lightweight profile has no downloaded artifacts and supports any Omarchy architecture.
- `toolchains/python-requirements.lock` pins the complete Python dependency graph and hashes.
- `VERSION` identifies the workstation snapshot.
- `sbom/limechain-web3.spdx.json` records the application and toolchain packages.

The lock does not claim bit-for-bit reproducibility of Omarchy or Arch Linux itself. Omarchy is a rolling distribution, so CI records the tested ISO/release and package inventory separately.

## Verification

```bash
jq -e '.schema == 2 and .profile == "evm-core"' toolchains/evm-core.lock.json
jq -e '.schema == 2 and .profile == "solana-core"' toolchains/solana-core.lock.json
jq -e '.schema == 2 and .profile == "hedera-core" and .platform == "any" and (.artifacts | length == 0)' toolchains/hedera-core.lock.json
python3 scripts/verify-lock.py
python3 scripts/generate-sbom.py --check
```

`python3 scripts/verify-lock.py --download` runs the production bounded downloader against every release artifact. The installer refuses a size, origin, redirect, archive-policy, tree-manifest, or checksum mismatch and never falls back to another package source.

The sample Anchor workspace commits its complete `Cargo.lock`. Its first build may fetch those locked crates into the workstation's isolated Cargo home; a subsequent `limechain-web3 anchor build . --offline` must succeed without fetching new dependencies. Anchor `1.1.2` selects platform-tools `1.52`; the wrapper requires that exact preinstalled tree and adds `--skip-tools-install`, so `cargo-build-sbf` cannot download a different toolchain.

## AUR policy

The MVP uses no AUR packages. Adding one later requires a pinned recipe revision, committed review notes, a clean isolated build, an SBOM update, and explicit maintainer approval.
