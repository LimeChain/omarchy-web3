#!/bin/bash

set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
source "$SCRIPT_DIR/lib.sh"
lcw3_paths

plugin_root="$LCW3_PLUGIN_ROOT"
if [[ -d $plugin_root/.git ]] && command -v omarchy >/dev/null; then
  lcw3_export_omarchy_path
  omarchy plugin update limechain.web3 --yes
  profile=evm-core
  if [[ -f $LCW3_INSTALL_STATE ]]; then
    profile=$(jq -r 'if (.profiles | type) == "array" and (.profiles | length) > 0 then .profiles[0] elif .profile then .profile else "evm-core" end' "$LCW3_INSTALL_STATE")
  fi
  # One transactional installer run refreshes every profile recorded in state.
  "$plugin_root/install" --profile "$profile" "$@"
  exit 0
fi

echo "limechain-web3: installed plugin is not a git checkout; reinstall from a tagged source checkout" >&2
exit 2
