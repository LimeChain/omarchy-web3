# Solana CLI and Anchor security review

Review date: 2026-08-31

## Reviewed binary artifacts

| Component | Version | Upstream artifact | SHA-256 |
|:--|:--|:--|:--|
| Agave / Solana CLI | `4.2.2` | `anza-xyz/agave` Linux x86-64 release tarball | `5fc8684f7430038105fde953d4308ed56addf627f658daa61709f345448247ee` |
| Anchor CLI | `1.1.2` | `otter-sec/anchor` Linux x86-64 release binary | `fdea9979629e9416e5f5e5622ff6c11b8c691d1e559581ece368e903c0c980c1` |
| SBF platform tools | `1.52` | `anza-xyz/platform-tools` Linux x86-64 release tarball | `8b3861e93daf085ec12b65c4fac374d9bec4587a3de16871da6b08ab0c1d907e` |
| Surfpool | `1.5.0` | `solana-foundation/surfpool` Linux x86-64 release tarball | `5b20a3b46e60c4f819af7b4da5c3ea211f76041710617841cc23247d15887ddc` |

The lockfile uses immutable versioned GitHub release URLs. GitHub's release-asset digests were compared with the committed hashes; the install path independently hashes the downloaded bytes before extraction and records a file manifest for the extracted tree.

## Key-handling findings

The upstream command surfaces are intentionally broader than this workstation:

- `solana-keygen` creates the default wallet under `~/.config/solana`; it is present inside the upstream Agave archive but is not linked into the workstation command environment.
- Solana `config`, `airdrop`, transfer, program deployment, stake, vote, and transaction commands can select keypairs or submit transactions; none are exposed.
- Anchor `init` and `new` call a create-or-read program-ID path that writes `target/deploy/*-keypair.json` when absent.
- Anchor `build` normally compares source program IDs with program-keypair files. The guarded build always uses `--ignore-keys`.
- `cargo-build-sbf` post-processing independently creates `target/deploy/<program>-keypair.json` when that path is absent. Before launch, the guard derives explicit cdylib program names from non-wildcard Cargo workspace members, requires their keypair paths to be absent, and reserves each path as a `/dev/null` symlink. Upstream sees an existing path and skips generation; the guard removes the sentinels in a `finally` path.
- Anchor `test` builds, starts a validator, deploys programs, and runs tests. Anchor `deploy`, `keys`, `account`, `migrate`, `idl`, and related commands cross the key/signing or remote-state boundary and are refused.
- Anchor lifecycle hooks execute arbitrary shell commands. Guarded builds reject `pre_build`, `post_build`, and their hyphenated aliases before launching Anchor.
- `toolchain.anchor_version` and `toolchain.solana_version` can trigger version-manager or installer behavior. Mismatched Anchor versions and any Solana override are rejected.
- Anchor `1.1.2` hardcodes `cargo build-sbf --tools-version v1.52`. The profile therefore pins that compatible upstream artifact and adds `--skip-tools-install`; a newer but unreviewed toolchain is not substituted.

## Exposed surface

| Goal | Allowed command | Boundary |
|:--|:--|:--|
| Version evidence | `limechain-web3 solana version` / `anchor version` | Verified binaries, isolated home |
| Local inspection | `solana slot`, `epoch`, `block-height`, `genesis-hash`, `transaction-count`, `cluster-version` | Fixed loopback RPC; no signer arguments |
| Sample creation | `anchor scaffold <new-directory>` | Bundled fixed public program ID; no keypair file |
| Program compile | `anchor build [directory]` | Localnet + `/dev/null` wallet and keypair outputs + locked dependencies + pinned SBF tools + no hooks/keys |

Everything else remains unavailable through the wrapper and the agent skill. The raw upstream binaries are developer tools, not sandboxes; filesystem permissions still apply to a user who deliberately bypasses the wrapper inside the application directory.
