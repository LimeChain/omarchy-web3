#!/bin/bash

set -euo pipefail

lcw3_fail() {
  echo "limechain-web3: $*" >&2
  exit 1
}

lcw3_paths() {
  LCW3_HOME=${LCW3_HOME:-$HOME}
  LCW3_DATA_HOME=${LCW3_DATA_HOME:-$LCW3_HOME/.local/share}
  LCW3_CONFIG_HOME=${LCW3_CONFIG_HOME:-$LCW3_HOME/.config}
  LCW3_STATE_HOME=${LCW3_STATE_HOME:-$LCW3_HOME/.local/state}
  LCW3_CACHE_HOME=${LCW3_CACHE_HOME:-$LCW3_HOME/.cache}
  LCW3_BIN_HOME=${LCW3_BIN_HOME:-$LCW3_HOME/.local/bin}
  LCW3_APP_ROOT=${LCW3_APP_ROOT:-$LCW3_DATA_HOME/limechain-web3}
  LCW3_PLUGIN_ROOT=${LCW3_PLUGIN_ROOT:-$LCW3_CONFIG_HOME/omarchy/plugins/limechain.web3}
  LCW3_SKILL_ROOT=${LCW3_SKILL_ROOT:-$LCW3_HOME/.agents/skills/limechain-web3}
  LCW3_SYSTEMD_ROOT=${LCW3_SYSTEMD_ROOT:-$LCW3_CONFIG_HOME/systemd/user}
  LCW3_INSTALL_STATE=${LCW3_INSTALL_STATE:-$LCW3_STATE_HOME/limechain-web3/install-state.json}
  export LCW3_HOME LCW3_DATA_HOME LCW3_CONFIG_HOME LCW3_STATE_HOME LCW3_CACHE_HOME
  export LCW3_BIN_HOME LCW3_APP_ROOT LCW3_PLUGIN_ROOT LCW3_SKILL_ROOT LCW3_SYSTEMD_ROOT LCW3_INSTALL_STATE
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

lcw3_copy_tree() {
  local source=$1
  local target=$2
  mkdir -p "$target"
  cp -a "$source/." "$target/"
}
