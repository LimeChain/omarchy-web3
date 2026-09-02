#!/bin/bash

set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
source "$SCRIPT_DIR/lib.sh"
lcw3_paths

plugin_root="$LCW3_PLUGIN_ROOT"
if [[ -d $plugin_root/.git ]] && command -v omarchy >/dev/null; then
  lcw3_export_omarchy_path
  lcw3_require_unlocked_session
  plugin_parent=$(dirname -- "$plugin_root")
  lcw3_assert_managed_path "$plugin_root" "plugin root"
  shell_config="$LCW3_CONFIG_HOME/omarchy/shell.json"
  lcw3_assert_user_regular_file_or_absent "$shell_config" "Omarchy shell configuration"
  transaction=$(mktemp -d "$plugin_parent/.limechain-web3.update.XXXXXX")
  chmod 0700 "$transaction"
  cleanup_update_snapshot() {
    local status=$?
    trap - EXIT INT TERM
    [[ ! -e $transaction ]] || python3 -c 'import shutil,sys; shutil.rmtree(sys.argv[1])' "$transaction"
    exit "$status"
  }
  trap cleanup_update_snapshot EXIT INT TERM
  lcw3_snapshot_user_tree "$plugin_root" "$transaction/plugin"
  shell_config_existed=0
  if [[ -f $shell_config ]]; then
    cp -p -- "$shell_config" "$transaction/shell.json"
    shell_config_existed=1
  fi
  complete=0
  rollback_update() {
    local status=$?
    trap - EXIT INT TERM
    if (( ! complete )); then
      if [[ -e $plugin_root || -L $plugin_root ]]; then
        mv "$plugin_root" "$transaction/failed-plugin"
      fi
      mv "$transaction/plugin" "$plugin_root"
      lcw3_restore_regular_file "$transaction/shell.json" "$shell_config" "$shell_config_existed"
      omarchy-shell shell reloadConfig >/dev/null 2>&1 || true
      omarchy-shell shell rescanPlugins >/dev/null 2>&1 || true
      command -v omarchy-restart-shell >/dev/null && omarchy-restart-shell >/dev/null 2>&1 || true
    fi
    [[ ! -e $transaction ]] || python3 -c 'import shutil,sys; shutil.rmtree(sys.argv[1])' "$transaction"
    exit "$status"
  }
  trap rollback_update EXIT INT TERM
  omarchy plugin update limechain.web3 --yes
  profile=evm-core
  if [[ -f $LCW3_INSTALL_STATE ]]; then
    profile=$(jq -r 'if (.profiles | type) == "array" and (.profiles | length) > 0 then .profiles[0] elif .profile then .profile else "evm-core" end' "$LCW3_INSTALL_STATE")
  fi
  # One transactional installer run refreshes every profile recorded in state.
  "$plugin_root/install" --profile "$profile" "$@"
  complete=1
  exit 0
fi

echo "limechain-web3: installed plugin is not a git checkout; reinstall from a tagged source checkout" >&2
exit 2
