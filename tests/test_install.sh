#!/bin/bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
TEST_ROOT=$(mktemp -d)
trap 'rm -rf "$TEST_ROOT"' EXIT

export LCW3_HOME="$TEST_ROOT/home"
export LCW3_DATA_HOME="$TEST_ROOT/data"
export LCW3_CONFIG_HOME="$TEST_ROOT/config"
export LCW3_STATE_HOME="$TEST_ROOT/state"
export LCW3_CACHE_HOME="$TEST_ROOT/cache"
export LCW3_BIN_HOME="$TEST_ROOT/bin"
export LCW3_APP_ROOT="$TEST_ROOT/data/limechain-web3"
export LCW3_PLUGIN_ROOT="$TEST_ROOT/config/omarchy/plugins/limechain.web3"
export LCW3_SKILL_ROOT="$TEST_ROOT/home/.agents/skills/limechain-web3"
export LCW3_SYSTEMD_ROOT="$TEST_ROOT/config/systemd/user"
export LCW3_INSTALL_STATE="$TEST_ROOT/state/limechain-web3/install-state.json"
export LCW3_MENU_FILE="$TEST_ROOT/config/omarchy/extensions/omarchy-menu.jsonc"

mkdir -p "$LCW3_HOME"

fake_bin="$TEST_ROOT/fake-bin"
mkdir -p "$fake_bin"
printf '#!/bin/bash\nexit "${LCW3_TEST_LOCK_STATUS:-2}"\n' >"$fake_bin/omarchy-hyprland-session-locked"
chmod 0755 "$fake_bin/omarchy-hyprland-session-locked"
export HYPRLAND_INSTANCE_SIGNATURE=limechain-web3-test
if lock_error=$(LCW3_TEST_LOCK_STATUS=0 PATH="$fake_bin:$PATH" bash -c \
  'source "$1/scripts/lib.sh"; lcw3_require_unlocked_session' _ "$ROOT" 2>&1); then
  echo "locked-session guard unexpectedly allowed a plugin reload" >&2
  exit 1
fi
grep -q 'refusing to reload the plugin while the Omarchy session is locked' <<<"$lock_error"
LCW3_TEST_LOCK_STATUS=1 PATH="$fake_bin:$PATH" bash -c \
  'source "$1/scripts/lib.sh"; lcw3_require_unlocked_session' _ "$ROOT"

"$ROOT/install" --skip-toolchains --skip-omarchy
plugin_inode=$(python3 -c 'import os,sys; print(os.stat(sys.argv[1]).st_ino)' "$LCW3_PLUGIN_ROOT")
"$ROOT/install" --skip-toolchains --skip-omarchy
[[ $(python3 -c 'import os,sys; print(os.stat(sys.argv[1]).st_ino)' "$LCW3_PLUGIN_ROOT") == "$plugin_inode" ]]
"$ROOT/install" --profile solana-core --skip-toolchains --skip-omarchy
[[ $(python3 -c 'import os,sys; print(os.stat(sys.argv[1]).st_ino)' "$LCW3_PLUGIN_ROOT") == "$plugin_inode" ]]

[[ -L $LCW3_BIN_HOME/limechain-web3 ]]
[[ -f $LCW3_PLUGIN_ROOT/manifest.json ]]
[[ -f $LCW3_SKILL_ROOT/SKILL.md ]]
[[ -f $LCW3_SYSTEMD_ROOT/limechain-web3-anvil.service ]]
[[ -f $LCW3_SYSTEMD_ROOT/limechain-web3-surfpool.service ]]
grep -q 'crytic-compile' "$LCW3_APP_ROOT/scripts/install.sh"
[[ $(grep -c 'BEGIN limechain.web3' "$LCW3_MENU_FILE") == 1 ]]
jq -e '.schema == 2 and .profile == "solana-core" and .profiles == ["evm-core", "solana-core"]' "$LCW3_INSTALL_STATE" >/dev/null
grep -q 'Start Offline Surfpool' "$LCW3_MENU_FILE"

"$LCW3_BIN_HOME/limechain-web3" uninstall

[[ ! -e $LCW3_APP_ROOT ]]
[[ ! -e $LCW3_PLUGIN_ROOT ]]
[[ ! -e $LCW3_SKILL_ROOT ]]
[[ -f $LCW3_CONFIG_HOME/limechain-web3/config.json ]]
[[ ! -e $LCW3_BIN_HOME/limechain-web3 ]]
