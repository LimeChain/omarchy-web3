#!/bin/bash

set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
source "$SCRIPT_DIR/lib.sh"
lcw3_paths

PURGE=0
while (( $# > 0 )); do
  case "$1" in
  --purge)
    PURGE=1
    shift
    ;;
  -h | --help)
    echo "Usage: limechain-web3 uninstall [--purge]"
    exit 0
    ;;
  *)
    lcw3_fail "unknown uninstall option: $1"
    ;;
  esac
done

config_root="$LCW3_CONFIG_HOME/limechain-web3"
cache_root="$LCW3_CACHE_HOME/limechain-web3"
state_root=$(dirname -- "$LCW3_INSTALL_STATE")
cli_link="$LCW3_BIN_HOME/limechain-web3"
menu_file=$LCW3_MENU_FILE
shell_config="$LCW3_CONFIG_HOME/omarchy/shell.json"

for path_info in \
  "$LCW3_APP_ROOT:application root" \
  "$LCW3_PLUGIN_ROOT:plugin root" \
  "$state_root:state root" \
  "$LCW3_SYSTEMD_ROOT:systemd root" \
  "$config_root:configuration root" \
  "$cache_root:cache root"; do
  lcw3_assert_managed_path "${path_info%%:*}" "${path_info#*:}"
done
lcw3_assert_safe_path "$cli_link" "command link"
lcw3_assert_managed_path "$(dirname -- "$cli_link")" "command root"
lcw3_assert_managed_path "$menu_file" "Omarchy menu file"
lcw3_assert_user_regular_file_or_absent "$shell_config" "Omarchy shell configuration"

[[ -d $LCW3_APP_ROOT && ! -L $LCW3_APP_ROOT ]] || lcw3_fail "managed application root is missing"
lcw3_require_owner_marker "$LCW3_APP_ROOT" "application-root"

if [[ -e $state_root || -L $state_root ]]; then
  [[ -d $state_root && ! -L $state_root ]] || lcw3_fail "state root collision: $state_root"
  lcw3_require_owner_marker "$state_root" "install-state"
  unknown_state=$(find "$state_root" -mindepth 1 -maxdepth 1 \
    ! -name install-state.json ! -name .limechain-web3-managed.json -print -quit)
  [[ -z $unknown_state ]] || lcw3_fail "state root contains unmanaged content: $unknown_state"
fi

if [[ -e $cli_link || -L $cli_link ]]; then
  [[ -L $cli_link ]] || lcw3_fail "command path is not the managed symlink: $cli_link"
  [[ $(lcw3_realpath "$cli_link") == $(lcw3_realpath "$LCW3_APP_ROOT/bin/limechain-web3") ]] \
    || lcw3_fail "command symlink no longer targets the managed application"
fi

for unit_name in limechain-web3-anvil.service limechain-web3-surfpool.service; do
  unit_target="$LCW3_SYSTEMD_ROOT/$unit_name"
  if [[ -e $unit_target || -L $unit_target ]]; then
    [[ -f $unit_target && ! -L $unit_target ]] || lcw3_fail "systemd unit collision: $unit_target"
    grep -qx '# Managed by limechain.web3; ownership-schema=1' "$unit_target" \
      || lcw3_fail "refusing to remove an unmanaged systemd unit: $unit_target"
  fi
done

plugin_kind=none
if [[ -e $LCW3_PLUGIN_ROOT || -L $LCW3_PLUGIN_ROOT ]]; then
  [[ -d $LCW3_PLUGIN_ROOT && ! -L $LCW3_PLUGIN_ROOT ]] || lcw3_fail "plugin root collision: $LCW3_PLUGIN_ROOT"
  if [[ -f $LCW3_PLUGIN_ROOT/.limechain-web3-managed.json ]]; then
    python3 "$SCRIPT_DIR/managed-tree.py" verify \
      --target "$LCW3_PLUGIN_ROOT" --boundary "$LCW3_HOME" --scope plugin-copy
    plugin_kind=managed-copy
  elif [[ -d $LCW3_PLUGIN_ROOT/.git ]]; then
    plugin_kind=omarchy-native
  else
    lcw3_fail "refusing to remove an unmarked plugin directory: $LCW3_PLUGIN_ROOT"
  fi
fi

if (( PURGE )); then
  if [[ -e $config_root || -L $config_root ]]; then
    [[ -d $config_root && ! -L $config_root ]] || lcw3_fail "configuration root collision: $config_root"
    lcw3_require_owner_marker "$config_root" "configuration"
    unknown_config=$(find "$config_root" -mindepth 1 -maxdepth 1 \
      ! -name config.json ! -name .limechain-web3-managed.json -print -quit)
    [[ -z $unknown_config ]] || lcw3_fail "configuration root contains unmanaged content: $unknown_config"
  fi
  if [[ -e $cache_root || -L $cache_root ]]; then
    [[ -d $cache_root && ! -L $cache_root ]] || lcw3_fail "cache root collision: $cache_root"
    lcw3_require_owner_marker "$cache_root" "download-cache"
    unknown_cache=$(find "$cache_root" -mindepth 1 -maxdepth 1 \
      ! -name downloads ! -name .limechain-web3-managed.json -print -quit)
    [[ -z $unknown_cache ]] || lcw3_fail "cache root contains unmanaged content: $unknown_cache"
  fi
fi

app_parent=$(dirname -- "$LCW3_APP_ROOT")
transaction=$(mktemp -d "$app_parent/.limechain-web3.uninstall.XXXXXX")
chmod 0700 "$transaction"
mkdir -p "$transaction/systemd"
cleanup_uninstall_snapshot() {
  local status=$?
  trap - EXIT INT TERM
  [[ ! -e $transaction ]] || python3 -c 'import shutil,sys; shutil.rmtree(sys.argv[1])' "$transaction"
  exit "$status"
}
trap cleanup_uninstall_snapshot EXIT INT TERM
shell_config_existed=0
if [[ -f $shell_config ]]; then
  cp -p -- "$shell_config" "$transaction/shell.json"
  shell_config_existed=1
fi
if [[ $plugin_kind == omarchy-native ]]; then
  lcw3_snapshot_user_tree "$LCW3_PLUGIN_ROOT" "$transaction/native-plugin"
fi
menu_existed=0
if [[ -f $menu_file && ! -L $menu_file ]]; then
  menu_begin_count=$(grep -Fc '// BEGIN limechain.web3 (managed by limechain-web3)' "$menu_file" || true)
  menu_end_count=$(grep -Fc '// END limechain.web3' "$menu_file" || true)
  [[ $menu_begin_count == "$menu_end_count" && $menu_begin_count -le 1 ]] \
    || lcw3_fail "menu contains an ambiguous limechain.web3 managed block"
  cp -p "$menu_file" "$transaction/menu"
  menu_existed=1
elif [[ -e $menu_file || -L $menu_file ]]; then
  lcw3_fail "menu path is not a regular file: $menu_file"
fi

complete=0

rollback_uninstall() {
  local status=$?
  trap - EXIT INT TERM
  if (( ! complete )); then
    [[ ! -e $transaction/application ]] || mv "$transaction/application" "$LCW3_APP_ROOT"
    [[ ! -e $transaction/state ]] || mv "$transaction/state" "$state_root"
    [[ ! -e $transaction/cli ]] || mv "$transaction/cli" "$cli_link"
    [[ ! -e $transaction/plugin ]] || mv "$transaction/plugin" "$LCW3_PLUGIN_ROOT"
    if [[ $plugin_kind == omarchy-native && ! -e $LCW3_PLUGIN_ROOT && ! -L $LCW3_PLUGIN_ROOT ]]; then
      mv "$transaction/native-plugin" "$LCW3_PLUGIN_ROOT"
    fi
    [[ ! -e $transaction/config ]] || mv "$transaction/config" "$config_root"
    [[ ! -e $transaction/cache ]] || mv "$transaction/cache" "$cache_root"
    local unit
    for unit in limechain-web3-anvil.service limechain-web3-surfpool.service; do
      [[ ! -e $transaction/systemd/$unit ]] || mv "$transaction/systemd/$unit" "$LCW3_SYSTEMD_ROOT/$unit"
    done
    if (( menu_existed )); then
      install -d -m 0700 "$(dirname -- "$menu_file")"
      cp -p "$transaction/menu" "$menu_file"
    fi
    lcw3_restore_regular_file "$transaction/shell.json" "$shell_config" "$shell_config_existed"
    if command -v omarchy-shell >/dev/null; then
      omarchy-shell shell reloadConfig >/dev/null 2>&1 || true
      omarchy-shell shell rescanPlugins >/dev/null 2>&1 || true
    fi
    if command -v systemctl >/dev/null; then
      systemctl --user daemon-reload >/dev/null 2>&1 || true
      lcw3_restore_active_user_units >/dev/null 2>&1 || true
    fi
  fi
  [[ ! -e $transaction ]] || python3 -c 'import shutil,sys; shutil.rmtree(sys.argv[1])' "$transaction"
  exit "$status"
}
trap rollback_uninstall EXIT INT TERM

if command -v systemctl >/dev/null; then
  lcw3_capture_active_user_units limechain-web3-anvil.service limechain-web3-surfpool.service
  systemctl --user stop limechain-web3-anvil.service >/dev/null 2>&1 || true
  systemctl --user stop limechain-web3-surfpool.service >/dev/null 2>&1 || true
fi

"$LCW3_APP_ROOT/bin/limechain-web3" internal remove-menu

for unit_name in limechain-web3-anvil.service limechain-web3-surfpool.service; do
  [[ ! -e $LCW3_SYSTEMD_ROOT/$unit_name ]] || mv "$LCW3_SYSTEMD_ROOT/$unit_name" "$transaction/systemd/$unit_name"
done
[[ ! -e $cli_link && ! -L $cli_link ]] || mv "$cli_link" "$transaction/cli"
[[ ! -e $state_root ]] || mv "$state_root" "$transaction/state"
if [[ $plugin_kind == managed-copy ]]; then
  mv "$LCW3_PLUGIN_ROOT" "$transaction/plugin"
fi
if (( PURGE )); then
  [[ ! -e $config_root ]] || mv "$config_root" "$transaction/config"
  [[ ! -e $cache_root ]] || mv "$cache_root" "$transaction/cache"
fi
mv "$LCW3_APP_ROOT" "$transaction/application"

if [[ $plugin_kind == omarchy-native ]]; then
  command -v omarchy >/dev/null || lcw3_fail "Omarchy CLI is required to remove its native plugin checkout"
  lcw3_export_omarchy_path
  omarchy plugin remove limechain.web3 --yes
fi

if command -v systemctl >/dev/null; then
  systemctl --user daemon-reload >/dev/null 2>&1 || true
fi

complete=1
if (( PURGE )); then
  echo "Removed the workstation, its owned configuration, and verified download cache."
else
  echo "Removed the workstation. Its owned configuration and verified download cache were preserved."
fi
echo "A separately opted-in agent skill was not touched. Remove it explicitly with the plugin's uninstall-agent-skill command."
