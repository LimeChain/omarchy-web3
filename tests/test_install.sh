#!/bin/bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
TEST_ROOT=$(mktemp -d)
trap 'rm -rf "$TEST_ROOT"' EXIT

export LCW3_HOME="$TEST_ROOT/home"
export LCW3_DATA_HOME="$LCW3_HOME/.local/share"
export LCW3_CONFIG_HOME="$LCW3_HOME/.config"
export LCW3_STATE_HOME="$LCW3_HOME/.local/state"
export LCW3_CACHE_HOME="$LCW3_HOME/.cache"
export LCW3_BIN_HOME="$LCW3_HOME/.local/bin"
export LCW3_APP_ROOT="$LCW3_DATA_HOME/limechain-web3"
export LCW3_PLUGIN_ROOT="$LCW3_CONFIG_HOME/omarchy/plugins/limechain.web3"
export LCW3_SYSTEMD_ROOT="$LCW3_CONFIG_HOME/systemd/user"
export LCW3_INSTALL_STATE="$LCW3_STATE_HOME/limechain-web3/install-state.json"
export LCW3_MENU_FILE="$LCW3_CONFIG_HOME/omarchy/extensions/omarchy-menu.jsonc"
export LCW3_TESTING=1

mkdir -p "$LCW3_HOME"

if env -i PATH="$PATH" HOME="$LCW3_HOME" LCW3_APP_ROOT="$LCW3_HOME/foreign-app" \
  bash -c 'source "$1/scripts/lib.sh"; lcw3_paths' _ "$ROOT" >/dev/null 2>&1; then
  echo "production lifecycle accepted a test-only destination override" >&2
  exit 1
fi

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

systemctl_log="$TEST_ROOT/systemctl.log"
cat >"$fake_bin/systemctl" <<'SYSTEMCTL'
#!/bin/bash
if [[ $1 == "--user" && $2 == "is-active" && $3 == "--quiet" ]]; then
  [[ $4 == "limechain-web3-anvil.service" ]]
elif [[ $1 == "--user" && $2 == "start" ]]; then
  printf '%s\n' "$3" >>"$LCW3_TEST_SYSTEMCTL_LOG"
else
  exit 2
fi
SYSTEMCTL
chmod 0755 "$fake_bin/systemctl"
LCW3_TEST_SYSTEMCTL_LOG="$systemctl_log" PATH="$fake_bin:$PATH" bash -c '
  source "$1/scripts/lib.sh"
  lcw3_capture_active_user_units limechain-web3-anvil.service limechain-web3-surfpool.service
  lcw3_restore_active_user_units
' _ "$ROOT"
[[ $(<"$systemctl_log") == "limechain-web3-anvil.service" ]]

mkdir -p "$LCW3_APP_ROOT"
printf '%s\n' foreign >"$LCW3_APP_ROOT/unmanaged"
if "$ROOT/install" --skip-toolchains --skip-omarchy >/dev/null 2>&1; then
  echo "installer overwrote an unmarked application collision" >&2
  exit 1
fi
[[ $(<"$LCW3_APP_ROOT/unmanaged") == foreign ]]
rm "$LCW3_APP_ROOT/unmanaged"
rmdir "$LCW3_APP_ROOT"

"$ROOT/install" --skip-toolchains --skip-omarchy
plugin_inode=$(python3 -c 'import os,sys; print(os.stat(sys.argv[1]).st_ino)' "$LCW3_PLUGIN_ROOT")
"$ROOT/install" --skip-toolchains --skip-omarchy
[[ $(python3 -c 'import os,sys; print(os.stat(sys.argv[1]).st_ino)' "$LCW3_PLUGIN_ROOT") == "$plugin_inode" ]]
"$ROOT/install" --profile solana-core --skip-toolchains --skip-omarchy
[[ $(python3 -c 'import os,sys; print(os.stat(sys.argv[1]).st_ino)' "$LCW3_PLUGIN_ROOT") == "$plugin_inode" ]]
"$ROOT/install" --profile hedera-core --skip-toolchains --skip-omarchy
[[ $(python3 -c 'import os,sys; print(os.stat(sys.argv[1]).st_ino)' "$LCW3_PLUGIN_ROOT") == "$plugin_inode" ]]

[[ -L $LCW3_BIN_HOME/limechain-web3 ]]
[[ -f $LCW3_PLUGIN_ROOT/manifest.json ]]
[[ ! -e $LCW3_HOME/.agents/skills/limechain-web3 ]]
[[ -f $LCW3_SYSTEMD_ROOT/limechain-web3-anvil.service ]]
[[ -f $LCW3_SYSTEMD_ROOT/limechain-web3-surfpool.service ]]
grep -q 'crytic-compile' "$LCW3_APP_ROOT/scripts/install.sh"
[[ $(grep -c 'BEGIN limechain.web3' "$LCW3_MENU_FILE") == 1 ]]
jq -e '.schema == 3 and .profile == "hedera-core" and .profiles == ["evm-core", "hedera-core", "solana-core"]' "$LCW3_INSTALL_STATE" >/dev/null
grep -q 'Start Offline Surfpool' "$LCW3_MENU_FILE"
grep -q 'Hedera Observer Status' "$LCW3_MENU_FILE"

printf '%s\n' rollback-proof >"$LCW3_APP_ROOT/rollback-proof"
if LCW3_TEST_FAIL_AT=after-app-commit "$ROOT/install" --skip-toolchains --skip-omarchy >/dev/null 2>&1; then
  echo "injected transaction failure unexpectedly succeeded" >&2
  exit 1
fi
[[ $(<"$LCW3_APP_ROOT/rollback-proof") == rollback-proof ]]
[[ -L $LCW3_BIN_HOME/limechain-web3 ]]
jq -e '.schema == 3 and .profile == "hedera-core"' "$LCW3_INSTALL_STATE" >/dev/null

# Convert the isolated managed test copy into the shape of an Omarchy-native
# Git checkout, then prove that update and uninstall restore both the checkout
# and Omarchy's exact shell state when the official command fails after mutation.
python3 -c 'import shutil,sys; shutil.rmtree(sys.argv[1])' "$LCW3_PLUGIN_ROOT"
mkdir -p "$LCW3_PLUGIN_ROOT/.git" "$TEST_ROOT/fake-omarchy/shell"
printf '%s\n' original-plugin >"$LCW3_PLUGIN_ROOT/rollback-proof"
printf '%s\n' shell >"$TEST_ROOT/fake-omarchy/shell/shell.qml"
shell_config="$LCW3_CONFIG_HOME/omarchy/shell.json"
printf '%s\n' '{"version":1,"plugins":["limechain.web3"],"proof":"original"}' >"$shell_config"
cp "$shell_config" "$TEST_ROOT/original-shell.json"

cat >"$fake_bin/omarchy" <<'OMARCHY'
#!/bin/bash
set -euo pipefail
case "${1:-} ${2:-}" in
"plugin update")
  if [[ ${LCW3_TEST_UPDATE_SUCCEED:-0} == 1 ]]; then
    exit 0
  fi
  printf '%s\n' changed-plugin >"$LCW3_PLUGIN_ROOT/rollback-proof"
  printf '%s\n' '{"version":1,"proof":"changed-by-update"}' >"$LCW3_CONFIG_HOME/omarchy/shell.json"
  exit 41
  ;;
"plugin remove")
  printf '%s\n' '{"version":1,"proof":"changed-by-remove"}' >"$LCW3_CONFIG_HOME/omarchy/shell.json"
  python3 -c 'import shutil,sys; shutil.rmtree(sys.argv[1])' "$LCW3_PLUGIN_ROOT"
  [[ ${LCW3_TEST_REMOVE_FAIL:-0} == 0 ]] || exit 42
  ;;
*)
  exit 43
  ;;
esac
OMARCHY
cat >"$fake_bin/omarchy-shell" <<'OMARCHY_SHELL'
#!/bin/bash
exit 0
OMARCHY_SHELL
cat >"$fake_bin/omarchy-restart-shell" <<'OMARCHY_RESTART'
#!/bin/bash
exit 0
OMARCHY_RESTART
chmod 0755 "$fake_bin/omarchy" "$fake_bin/omarchy-shell" "$fake_bin/omarchy-restart-shell"

# Exercise the installed CLI in a production-shaped, isolated HOME. The
# update script resolves and exports its internal paths, but the child
# installer must receive none of those variables or its production guard will
# reject a legitimate update.
production_home="$TEST_ROOT/production-home"
production_app="$production_home/.local/share/limechain-web3"
production_plugin="$production_home/.config/omarchy/plugins/limechain.web3"
mkdir -p "$production_app/bin" "$production_app/scripts" "$production_home/.local/bin" "$production_plugin/.git"
install -m 0755 "$ROOT/bin/limechain-web3" "$production_app/bin/limechain-web3"
install -m 0755 "$ROOT/scripts/update.sh" "$production_app/scripts/update.sh"
install -m 0755 "$ROOT/scripts/managed-tree.py" "$production_app/scripts/managed-tree.py"
install -m 0644 "$ROOT/scripts/lib.sh" "$production_app/scripts/lib.sh"
ln -s "$production_app/bin/limechain-web3" "$production_home/.local/bin/limechain-web3"
cat >"$production_plugin/install" <<'PRODUCTION_INSTALL'
#!/bin/bash
set -euo pipefail
for override in LCW3_HOME LCW3_DATA_HOME LCW3_CONFIG_HOME LCW3_STATE_HOME LCW3_CACHE_HOME LCW3_BIN_HOME \
  LCW3_APP_ROOT LCW3_PLUGIN_ROOT LCW3_SYSTEMD_ROOT LCW3_INSTALL_STATE LCW3_MENU_FILE; do
  [[ -z ${!override:-} ]] || exit 91
done
[[ ${1:-} == "--profile" && ${2:-} == "evm-core" ]]
touch "$HOME/update-env-clean"
PRODUCTION_INSTALL
chmod 0755 "$production_plugin/install"
env -i \
  HOME="$production_home" \
  PATH="$fake_bin:$PATH" \
  OMARCHY_PATH="$TEST_ROOT/fake-omarchy" \
  HYPRLAND_INSTANCE_SIGNATURE=limechain-web3-test \
  LCW3_TEST_LOCK_STATUS=1 \
  LCW3_TEST_UPDATE_SUCCEED=1 \
  "$production_home/.local/bin/limechain-web3" update
[[ -f $production_home/update-env-clean ]]

if LCW3_TEST_LOCK_STATUS=1 OMARCHY_PATH="$TEST_ROOT/fake-omarchy" PATH="$fake_bin:$PATH" \
  "$LCW3_BIN_HOME/limechain-web3" update >/dev/null 2>&1; then
  echo "failed native update unexpectedly succeeded" >&2
  exit 1
fi
[[ $(<"$LCW3_PLUGIN_ROOT/rollback-proof") == original-plugin ]]
cmp "$TEST_ROOT/original-shell.json" "$shell_config"

if LCW3_TEST_REMOVE_FAIL=1 OMARCHY_PATH="$TEST_ROOT/fake-omarchy" PATH="$fake_bin:$PATH" \
  "$LCW3_BIN_HOME/limechain-web3" uninstall >/dev/null 2>&1; then
  echo "partially destructive native uninstall unexpectedly succeeded" >&2
  exit 1
fi
[[ -f $LCW3_APP_ROOT/VERSION ]]
[[ $(<"$LCW3_PLUGIN_ROOT/rollback-proof") == original-plugin ]]
cmp "$TEST_ROOT/original-shell.json" "$shell_config"

OMARCHY_PATH="$TEST_ROOT/fake-omarchy" PATH="$fake_bin:$PATH" "$LCW3_BIN_HOME/limechain-web3" uninstall

[[ ! -e $LCW3_APP_ROOT ]]
[[ ! -e $LCW3_PLUGIN_ROOT ]]
[[ -f $LCW3_CONFIG_HOME/limechain-web3/config.json ]]
[[ ! -e $LCW3_BIN_HOME/limechain-web3 ]]

"$ROOT/install" --profile hedera-core --skip-toolchains --skip-omarchy
"$LCW3_BIN_HOME/limechain-web3" uninstall --purge
[[ ! -e $LCW3_APP_ROOT ]]
[[ ! -e $LCW3_PLUGIN_ROOT ]]
[[ ! -e $LCW3_CONFIG_HOME/limechain-web3 ]]
[[ ! -e $LCW3_CACHE_HOME/limechain-web3 ]]

"$ROOT/install-agent-skill"
skill_root="$LCW3_HOME/.agents/skills/limechain-web3"
[[ -f $skill_root/SKILL.md ]]
[[ -f $skill_root/.limechain-web3-managed.json ]]
if printf '\n# local edit\n' >>"$skill_root/SKILL.md" && "$ROOT/uninstall-agent-skill" >/dev/null 2>&1; then
  echo "agent-skill uninstall removed locally modified content" >&2
  exit 1
fi
sed -i.bak '$d' "$skill_root/SKILL.md"
sed -i.bak '$d' "$skill_root/SKILL.md"
rm "$skill_root/SKILL.md.bak"
"$ROOT/uninstall-agent-skill"
[[ ! -e $skill_root ]]

mkdir -p "$LCW3_HOME/.agents/skills/limechain-web3"
printf '%s\n' unmanaged >"$LCW3_HOME/.agents/skills/limechain-web3/SKILL.md"
if "$ROOT/install-agent-skill" >/dev/null 2>&1; then
  echo "agent-skill installer overwrote an unmanaged collision" >&2
  exit 1
fi

symlink_home="$TEST_ROOT/symlink-home"
mkdir -p "$symlink_home" "$TEST_ROOT/redirected-agents"
ln -s "$TEST_ROOT/redirected-agents" "$symlink_home/.agents"
if LCW3_HOME="$symlink_home" "$ROOT/install-agent-skill" >/dev/null 2>&1; then
  echo "agent-skill installer followed a symlink path component" >&2
  exit 1
fi
[[ -z $(find "$TEST_ROOT/redirected-agents" -mindepth 1 -print -quit) ]]
