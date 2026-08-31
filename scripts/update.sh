#!/bin/bash

set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
source "$SCRIPT_DIR/lib.sh"
lcw3_paths

plugin_root="$LCW3_PLUGIN_ROOT"
if [[ -d $plugin_root/.git ]] && command -v omarchy >/dev/null; then
  lcw3_export_omarchy_path
  omarchy plugin update limechain.web3 --yes
  exec "$plugin_root/install" --profile evm-core "$@"
fi

echo "limechain-web3: installed plugin is not a git checkout; reinstall from a tagged source checkout" >&2
exit 2
