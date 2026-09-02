# Reproducible link-free toolchain artifacts

Two reviewed upstream distributions contain archive symlink entries. The marketplace security review requires rejecting archive links before extraction, so Web3 Workstation publishes deterministic derived ZIPs containing ordinary files only. The source URL, byte size, SHA-256, exact omitted links, transform path, output size, and output SHA-256 are committed in the profile locks.

The transform:

1. requires the upstream file's exact byte size and SHA-256;
2. rejects absolute paths, traversal, backslashes, duplicates, hardlinks, devices, FIFOs, and any other special entry;
3. accepts only explicitly named symlinks for omission;
4. resolves no path outside the archive;
5. writes only regular ZIP entries with normalized `0644`/`0755` modes, a fixed timestamp, fixed Deflate level, Zip64, and checksum-locked upstream member order.

## Node.js 24.20.0

```bash
python3 scripts/sanitize-upstream-archive.py \
  --source node-v24.20.0-linux-x64.tar.xz \
  --output node-v24.20.0-linux-x64-link-free.zip \
  --source-size 31838904 \
  --source-sha256 2f2c0da162318f0de47665410c7c8c2ed3d36c8f3105de4bbc61176c70a7cbf2 \
  --strip-components 1 \
  --drop-symlink bin/corepack \
  --drop-symlink bin/npm \
  --drop-symlink bin/npx
```

The lock maps `npm`, `npx`, and `corepack` directly to the regular upstream JavaScript entry points instead of restoring the omitted archive links.

## Solana SBF platform-tools 1.52

```bash
python3 scripts/sanitize-upstream-archive.py \
  --source platform-tools-linux-x86_64.tar.bz2 \
  --output platform-tools-v1.52-linux-x86_64-link-free.zip \
  --source-size 519270959 \
  --source-sha256 8b3861e93daf085ec12b65c4fac374d9bec4587a3de16871da6b08ab0c1d907e \
  --drop-symlink llvm/lib/liblldb.so.20.1-rust-dev \
  --drop-symlink llvm/lib/python3.10/dist-packages/lldb/_lldb.cpython-310-x86_64-linux-gnu.so \
  --drop-symlink llvm/lib/python3.10/dist-packages/lldb/lldb-argdumper \
  --drop-symlink llvm/lib/liblldb.so \
  --drop-symlink llvm/bin/clang++ \
  --drop-symlink llvm/bin/clang-cpp \
  --drop-symlink llvm/bin/llvm-readelf \
  --drop-symlink llvm/bin/ld.lld \
  --drop-symlink llvm/bin/lld-link \
  --drop-symlink llvm/bin/clang-cl \
  --drop-symlink llvm/bin/clang \
  --drop-symlink llvm/bin/ld64.lld
```

Eight compiler/linker aliases required by SBF builds are declared in the Solana lock and materialized by `safe-extract.py` only after all ordinary files pass preflight and extraction. The four LLDB-only links are deliberately absent because this profile exposes compilation, not debugging. The materialized links are verified against an exact link manifest and are never followed by chmod or binary-discovery code.

## Independent reproduction

Run the command twice from separate empty directories and compare both SHA-256 values with the profile lock. Then run `python3 scripts/safe-extract.py` for the artifact; it must accept the derived ZIP and reject either original link-bearing upstream archive.
