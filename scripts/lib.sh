#!/bin/bash

set -euo pipefail

lcw3_fail() {
  echo "limechain-web3: $*" >&2
  exit 1
}

lcw3_paths() {
  local actual_home=${HOME:?HOME is required}
  if [[ ${LCW3_TESTING:-0} == 1 ]]; then
    LCW3_HOME=${LCW3_HOME:-$actual_home}
  else
    [[ -z ${LCW3_HOME:-} || $LCW3_HOME == "$actual_home" ]] \
      || lcw3_fail "LCW3_HOME overrides are test-only"
    LCW3_HOME=$actual_home
  fi
  local default_data=${XDG_DATA_HOME:-$LCW3_HOME/.local/share}
  local default_config=${XDG_CONFIG_HOME:-$LCW3_HOME/.config}
  local default_state=${XDG_STATE_HOME:-$LCW3_HOME/.local/state}
  local default_cache=${XDG_CACHE_HOME:-$LCW3_HOME/.cache}
  if [[ ${LCW3_TESTING:-0} == 1 ]]; then
    LCW3_DATA_HOME=${LCW3_DATA_HOME:-$default_data}
    LCW3_CONFIG_HOME=${LCW3_CONFIG_HOME:-$default_config}
    LCW3_STATE_HOME=${LCW3_STATE_HOME:-$default_state}
    LCW3_CACHE_HOME=${LCW3_CACHE_HOME:-$default_cache}
    LCW3_BIN_HOME=${LCW3_BIN_HOME:-$LCW3_HOME/.local/bin}
    LCW3_APP_ROOT=${LCW3_APP_ROOT:-$LCW3_DATA_HOME/limechain-web3}
    LCW3_PLUGIN_ROOT=${LCW3_PLUGIN_ROOT:-$LCW3_CONFIG_HOME/omarchy/plugins/limechain.web3}
    LCW3_SYSTEMD_ROOT=${LCW3_SYSTEMD_ROOT:-$LCW3_CONFIG_HOME/systemd/user}
    LCW3_INSTALL_STATE=${LCW3_INSTALL_STATE:-$LCW3_STATE_HOME/limechain-web3/install-state.json}
    LCW3_MENU_FILE=${LCW3_MENU_FILE:-$LCW3_CONFIG_HOME/omarchy/extensions/omarchy-menu.jsonc}
  else
    for override in LCW3_DATA_HOME LCW3_CONFIG_HOME LCW3_STATE_HOME LCW3_CACHE_HOME LCW3_BIN_HOME \
      LCW3_APP_ROOT LCW3_PLUGIN_ROOT LCW3_SYSTEMD_ROOT LCW3_INSTALL_STATE LCW3_MENU_FILE; do
      [[ -z ${!override:-} ]] || lcw3_fail "$override overrides are test-only"
    done
    LCW3_DATA_HOME=$default_data
    LCW3_CONFIG_HOME=$default_config
    LCW3_STATE_HOME=$default_state
    LCW3_CACHE_HOME=$default_cache
    LCW3_BIN_HOME=$LCW3_HOME/.local/bin
    LCW3_APP_ROOT=$LCW3_DATA_HOME/limechain-web3
    LCW3_PLUGIN_ROOT=$LCW3_CONFIG_HOME/omarchy/plugins/limechain.web3
    LCW3_SYSTEMD_ROOT=$LCW3_CONFIG_HOME/systemd/user
    LCW3_INSTALL_STATE=$LCW3_STATE_HOME/limechain-web3/install-state.json
    LCW3_MENU_FILE=$LCW3_CONFIG_HOME/omarchy/extensions/omarchy-menu.jsonc
  fi
  export LCW3_HOME LCW3_DATA_HOME LCW3_CONFIG_HOME LCW3_STATE_HOME LCW3_CACHE_HOME
  export LCW3_BIN_HOME LCW3_APP_ROOT LCW3_PLUGIN_ROOT LCW3_SYSTEMD_ROOT LCW3_INSTALL_STATE LCW3_MENU_FILE
}

lcw3_assert_managed_path() {
  local target=$1
  local label=$2
  lcw3_assert_safe_path "$target" "$label"
  local helper=${LCW3_SECURITY_HELPER:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/managed-tree.py}
  python3 "$helper" check --target "$target" --boundary "$LCW3_HOME" --scope path
}

lcw3_write_owner_marker() {
  local root=$1
  local scope=$2
  install -d -m 0700 "$root"
  jq -cn --arg scope "$scope" --argjson uid "$UID" \
    '{schema:1,owner:"limechain.web3",scope:$scope,uid:$uid}' >"$root/.limechain-web3-managed.json"
  chmod 0600 "$root/.limechain-web3-managed.json"
}

lcw3_require_owner_marker() {
  local root=$1
  local scope=$2
  local marker="$root/.limechain-web3-managed.json"
  [[ -f $marker && ! -L $marker ]] || lcw3_fail "existing $scope is not marked as owned: $root"
  [[ $(stat -c %u "$marker" 2>/dev/null || stat -f %u "$marker") == "$UID" ]] \
    || lcw3_fail "$scope ownership marker belongs to another user: $marker"
  jq -e --arg scope "$scope" --argjson uid "$UID" \
    '.schema == 1 and .owner == "limechain.web3" and .scope == $scope and .uid == $uid' \
    "$marker" >/dev/null || lcw3_fail "invalid $scope ownership marker: $marker"
}

lcw3_assert_safe_path() {
  local target=$1
  local label=$2
  [[ -n $target ]] || lcw3_fail "$label is empty"
  [[ $target == /* ]] || lcw3_fail "$label must be absolute: $target"
  [[ $target != "/" && $target != "$LCW3_HOME" ]] || lcw3_fail "unsafe $label: $target"
}

lcw3_sha256() {
  sha256sum "$1" | awk '{print $1}'
}

lcw3_realpath() {
  python3 -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$1"
}

lcw3_export_omarchy_path() {
  if [[ -z ${OMARCHY_PATH:-} ]]; then
    if [[ -f /usr/share/omarchy/shell/shell.qml ]]; then
      OMARCHY_PATH=/usr/share/omarchy
    elif [[ -f $LCW3_HOME/.local/share/omarchy/shell/shell.qml ]]; then
      OMARCHY_PATH=$LCW3_HOME/.local/share/omarchy
    else
      lcw3_fail "could not locate the Omarchy installation (OMARCHY_PATH is unset)"
    fi
  fi
  [[ -f $OMARCHY_PATH/shell/shell.qml ]] || lcw3_fail "invalid Omarchy path: $OMARCHY_PATH"
  export OMARCHY_PATH
}

lcw3_export_hyprland_instance() {
  if [[ -z ${HYPRLAND_INSTANCE_SIGNATURE:-} ]]; then
    local runtime_dir=${XDG_RUNTIME_DIR:-/run/user/$UID}
    local hypr_dir
    hypr_dir=$(find "$runtime_dir/hypr" -mindepth 1 -maxdepth 1 -type d -printf '%T@ %p\n' 2>/dev/null \
      | sort -n | tail -n 1 | cut -d' ' -f2-)
    [[ -n $hypr_dir ]] || lcw3_fail "could not locate the live Hyprland session"
    HYPRLAND_INSTANCE_SIGNATURE=${hypr_dir##*/}
  fi
  export HYPRLAND_INSTANCE_SIGNATURE
}

lcw3_require_unlocked_session() {
  command -v omarchy-hyprland-session-locked >/dev/null \
    || lcw3_fail "cannot verify the Omarchy lock state"
  lcw3_export_hyprland_instance
  local lock_status=0
  omarchy-hyprland-session-locked >/dev/null 2>&1 || lock_status=$?
  case $lock_status in
  0) lcw3_fail "refusing to reload the plugin while the Omarchy session is locked; unlock and retry" ;;
  1) return 0 ;;
  *) lcw3_fail "could not determine the Omarchy lock state; refusing a potentially unsafe plugin reload" ;;
  esac
}

LCW3_ACTIVE_USER_UNITS=()

lcw3_capture_active_user_units() {
  local unit
  LCW3_ACTIVE_USER_UNITS=()
  for unit in "$@"; do
    if systemctl --user is-active --quiet "$unit" 2>/dev/null; then
      LCW3_ACTIVE_USER_UNITS+=("$unit")
    fi
  done
}

lcw3_restore_active_user_units() {
  local unit
  for unit in "${LCW3_ACTIVE_USER_UNITS[@]}"; do
    systemctl --user start "$unit"
  done
}

lcw3_copy_tree() {
  local source=$1
  local target=$2
  mkdir -p "$target"
  cp -a "$source/." "$target/"
}

lcw3_assert_user_regular_file_or_absent() {
  local target=$1
  local label=$2
  lcw3_assert_managed_path "$target" "$label"
  if [[ -e $target || -L $target ]]; then
    [[ -f $target && ! -L $target ]] || lcw3_fail "$label is not a regular file: $target"
    [[ $(stat -c %u "$target" 2>/dev/null || stat -f %u "$target") == "$UID" ]] \
      || lcw3_fail "$label belongs to another user: $target"
  fi
}

lcw3_restore_regular_file() {
  local snapshot=$1
  local target=$2
  local existed=$3
  local parent
  parent=$(dirname -- "$target")
  if (( existed )); then
    install -d -m 0700 "$parent"
    local staged
    staged=$(mktemp "$parent/.limechain-web3.restore.XXXXXX")
    cp -p -- "$snapshot" "$staged"
    python3 -c 'import os,sys; os.replace(sys.argv[1], sys.argv[2])' "$staged" "$target"
  elif [[ -e $target || -L $target ]]; then
    [[ -f $target || -L $target ]] || lcw3_fail "refusing to remove unexpected rollback collision: $target"
    rm -f -- "$target"
  fi
}

lcw3_snapshot_user_tree() {
  local source=$1
  local destination=$2
  [[ -d $source && ! -L $source ]] || lcw3_fail "snapshot source is not a regular directory: $source"
  [[ ! -e $destination && ! -L $destination ]] || lcw3_fail "snapshot destination already exists: $destination"
  local foreign special
  foreign=$(find "$source" -xdev ! -user "$UID" -print -quit)
  [[ -z $foreign ]] || lcw3_fail "snapshot source contains foreign-owned content: $foreign"
  special=$(find "$source" -xdev -mindepth 1 ! -type d ! -type f ! -type l -print -quit)
  [[ -z $special ]] || lcw3_fail "snapshot source contains special content: $special"
  cp -a -- "$source" "$destination"
}
