#!/bin/bash

set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
SOURCE_DIR=$(cd -- "$SCRIPT_DIR/.." && pwd)
source "$SCRIPT_DIR/lib.sh"
lcw3_paths

PROFILE="evm-core"
SKIP_TOOLCHAINS=0
SKIP_OMARCHY=0
ENABLE_PLUGIN=1

usage() {
  cat <<'USAGE'
Usage: ./install [--profile evm-core|solana-core|hedera-core] [--skip-toolchains] [--skip-omarchy] [--no-enable-plugin]

Installs an additive, user-scoped Web3 workstation without elevated privileges or system package changes.
The optional coding-agent skill is not installed by this command.
USAGE
}

while (( $# > 0 )); do
  case "$1" in
  --profile)
    PROFILE=${2:-}
    shift 2
    ;;
  --skip-toolchains)
    SKIP_TOOLCHAINS=1
    shift
    ;;
  --skip-omarchy)
    SKIP_OMARCHY=1
    shift
    ;;
  --no-enable-plugin)
    ENABLE_PLUGIN=0
    shift
    ;;
  -h | --help)
    usage
    exit 0
    ;;
  *)
    lcw3_fail "unknown installer option: $1"
    ;;
  esac
done

case "$PROFILE" in
evm-core | solana-core | hedera-core) ;;
*) lcw3_fail "supported profiles: evm-core, solana-core, hedera-core" ;;
esac

for path_info in \
  "$LCW3_APP_ROOT:application root" \
  "$LCW3_PLUGIN_ROOT:plugin root" \
  "$LCW3_INSTALL_STATE:install state" \
  "$LCW3_SYSTEMD_ROOT:systemd root" \
  "$LCW3_BIN_HOME:command root" \
  "$LCW3_CACHE_HOME/limechain-web3:cache root" \
  "$LCW3_CONFIG_HOME/limechain-web3:configuration root"; do
  lcw3_assert_managed_path "${path_info%%:*}" "${path_info#*:}"
done

for command in jq python3 install cp; do
  command -v "$command" >/dev/null || lcw3_fail "required command is missing: $command"
done
[[ -x $SOURCE_DIR/scripts/safe-download.py ]] || lcw3_fail "safe downloader is missing"
[[ -x $SOURCE_DIR/scripts/safe-extract.py ]] || lcw3_fail "safe extractor is missing"

if (( SKIP_TOOLCHAINS )) && [[ ${LCW3_TESTING:-0} != 1 ]]; then
  lcw3_fail "--skip-toolchains is reserved for the isolated test suite"
fi

echo "Web3 Workstation $PROFILE manual setup"
echo "Owned scope: $LCW3_APP_ROOT, $LCW3_BIN_HOME/limechain-web3, $LCW3_CONFIG_HOME/limechain-web3,"
echo "             $(dirname -- "$LCW3_INSTALL_STATE"), marked user services, one bounded Omarchy menu block, and verified cache."
echo "Agent instructions: not installed (separate explicit opt-in only)."

if (( ! SKIP_OMARCHY )); then
  [[ $(uname -s) == "Linux" ]] || lcw3_fail "Omarchy installation requires Linux"
  if [[ $PROFILE != "hedera-core" ]]; then
    [[ $(uname -m) == "x86_64" ]] || lcw3_fail "the EVM and Solana profile lockfiles currently support x86_64 only"
  fi
  command -v omarchy >/dev/null || lcw3_fail "Omarchy CLI is not available"
  command -v pacman >/dev/null || lcw3_fail "pacman is not available"
  command -v systemctl >/dev/null || lcw3_fail "systemctl is not available"
  omarchy_package=$(pacman -Q omarchy 2>/dev/null || true)
  [[ $omarchy_package =~ [[:space:]]4\. ]] || lcw3_fail "Omarchy Quattro 4.x is required; found: ${omarchy_package:-none}"
  lcw3_export_omarchy_path
  lcw3_capture_active_user_units \
    limechain-web3-anvil.service \
    limechain-web3-surfpool.service
fi

source_real=$(lcw3_realpath "$SOURCE_DIR")
plugin_real=$(lcw3_realpath "$LCW3_PLUGIN_ROOT")
plugin_managed=false
if [[ $source_real != "$plugin_real" ]]; then
  if [[ ${LCW3_TESTING:-0} != 1 ]]; then
    lcw3_fail "run the installer from Omarchy's native plugin checkout: $LCW3_PLUGIN_ROOT/install"
  fi
  plugin_managed=true
fi

app_parent=$(dirname -- "$LCW3_APP_ROOT")
install -d -m 0700 "$app_parent"
lcw3_assert_managed_path "$app_parent" "application parent"
if [[ -e $LCW3_APP_ROOT || -L $LCW3_APP_ROOT ]]; then
  [[ -d $LCW3_APP_ROOT && ! -L $LCW3_APP_ROOT ]] || lcw3_fail "application root collision: $LCW3_APP_ROOT"
  lcw3_require_owner_marker "$LCW3_APP_ROOT" "application-root"
fi

state_root=$(dirname -- "$LCW3_INSTALL_STATE")
if [[ -e $state_root || -L $state_root ]]; then
  [[ -d $state_root && ! -L $state_root ]] || lcw3_fail "state root collision: $state_root"
  lcw3_require_owner_marker "$state_root" "install-state"
  unknown_state=$(find "$state_root" -mindepth 1 -maxdepth 1 \
    ! -name install-state.json ! -name .limechain-web3-managed.json -print -quit)
  [[ -z $unknown_state ]] || lcw3_fail "state root contains unmanaged content: $unknown_state"
fi

config_root="$LCW3_CONFIG_HOME/limechain-web3"
config_file="$config_root/config.json"
if [[ -e $config_root || -L $config_root ]]; then
  [[ -d $config_root && ! -L $config_root ]] || lcw3_fail "configuration root collision: $config_root"
  lcw3_require_owner_marker "$config_root" "configuration"
  [[ -f $config_file && ! -L $config_file ]] || lcw3_fail "managed configuration is missing or not a regular file"
  unknown_config=$(find "$config_root" -mindepth 1 -maxdepth 1 \
    ! -name config.json ! -name .limechain-web3-managed.json -print -quit)
  [[ -z $unknown_config ]] || lcw3_fail "configuration root contains unmanaged content: $unknown_config"
fi

cli_link="$LCW3_BIN_HOME/limechain-web3"
if [[ -e $cli_link && ! -L $cli_link ]]; then
  lcw3_fail "refusing to replace an unmanaged command: $cli_link"
fi
if [[ -L $cli_link ]]; then
  current_target=$(lcw3_realpath "$cli_link")
  expected_target=$(lcw3_realpath "$LCW3_APP_ROOT/bin/limechain-web3")
  [[ $current_target == "$expected_target" ]] || lcw3_fail "refusing to replace a foreign symlink: $cli_link"
fi

for unit_name in limechain-web3-anvil.service limechain-web3-surfpool.service; do
  unit_target="$LCW3_SYSTEMD_ROOT/$unit_name"
  if [[ -e $unit_target || -L $unit_target ]]; then
    [[ -f $unit_target && ! -L $unit_target ]] || lcw3_fail "systemd unit collision: $unit_target"
    grep -qx '# Managed by limechain.web3; ownership-schema=1' "$unit_target" \
      || lcw3_fail "refusing to replace an unmanaged systemd unit: $unit_target"
  fi
done

existing_profiles='[]'
if [[ -f $LCW3_INSTALL_STATE ]]; then
  existing_profiles=$(jq -c 'if (.profiles | type) == "array" then .profiles elif .profile then [.profile] else [] end' "$LCW3_INSTALL_STATE")
fi
profiles=$(jq -cn --argjson existing "$existing_profiles" --arg profile "$PROFILE" \
  '$existing + [$profile] | map(select(. == "evm-core" or . == "solana-core" or . == "hedera-core")) | unique')

transaction=$(mktemp -d "$app_parent/.limechain-web3.transaction.XXXXXX")
chmod 0700 "$transaction"
staged_app="$transaction/application"
backup_app="$transaction/previous-application"
staged_state="$transaction/install-state.json"
backup_state="$transaction/previous-install-state.json"
staged_units="$transaction/systemd"
backup_units="$transaction/previous-systemd"
menu_backup="$transaction/previous-menu"
menu_existed=0
app_replaced=0
state_replaced=0
units_replaced=0
config_created=0
cli_created=0
cli_existed=0
state_root_created=0
plugin_created=0
commit_complete=0

cleanup_transaction() {
  local status=$?
  trap - EXIT INT TERM
  if (( ! commit_complete && app_replaced )); then
    if [[ -e $LCW3_APP_ROOT || -L $LCW3_APP_ROOT ]]; then
      python3 -c 'import shutil,sys; shutil.rmtree(sys.argv[1])' "$LCW3_APP_ROOT" 2>/dev/null || true
    fi
    [[ ! -e $backup_app ]] || mv "$backup_app" "$LCW3_APP_ROOT"
  fi
  if (( ! commit_complete && state_replaced )); then
    rm -f "$LCW3_INSTALL_STATE"
    [[ ! -e $backup_state ]] || mv "$backup_state" "$LCW3_INSTALL_STATE"
  fi
  if (( ! commit_complete && state_root_created )); then
    rm -f "$state_root/.limechain-web3-managed.json"
    rmdir "$state_root" 2>/dev/null || true
  fi
  if (( ! commit_complete && units_replaced )); then
    local unit
    for unit in limechain-web3-anvil.service limechain-web3-surfpool.service; do
      rm -f "$LCW3_SYSTEMD_ROOT/$unit"
      [[ ! -e $backup_units/$unit ]] || mv "$backup_units/$unit" "$LCW3_SYSTEMD_ROOT/$unit"
    done
  fi
  if (( ! commit_complete && cli_created )); then
    rm -f "$cli_link"
    if (( cli_existed )); then
      ln -s "$LCW3_APP_ROOT/bin/limechain-web3" "$cli_link"
    fi
  fi
  if (( ! commit_complete && config_created )); then
    python3 "$SCRIPT_DIR/managed-tree.py" remove \
      --target "$config_root" --boundary "$LCW3_HOME" --scope configuration 2>/dev/null || true
  fi
  if (( ! commit_complete && plugin_created )); then
    python3 "$SCRIPT_DIR/managed-tree.py" remove \
      --target "$LCW3_PLUGIN_ROOT" --boundary "$LCW3_HOME" --scope plugin-copy 2>/dev/null || true
  fi
  if (( ! commit_complete )); then
    if (( menu_existed )); then
      install -d -m 0700 "$(dirname -- "$LCW3_MENU_FILE")"
      cp -p "$menu_backup" "$LCW3_MENU_FILE"
    else
      rm -f "$LCW3_MENU_FILE"
    fi
    if (( ! SKIP_OMARCHY )); then
      systemctl --user daemon-reload >/dev/null 2>&1 || true
      lcw3_restore_active_user_units >/dev/null 2>&1 || true
    fi
  fi
  [[ ! -e $transaction ]] || python3 -c 'import shutil,sys; shutil.rmtree(sys.argv[1])' "$transaction"
  exit "$status"
}
trap cleanup_transaction EXIT INT TERM

mkdir -p "$staged_app"
install -m 0644 "$SOURCE_DIR/VERSION" "$staged_app/VERSION"
install -m 0644 "$SOURCE_DIR/LICENSE" "$staged_app/LICENSE"
install -m 0644 "$SOURCE_DIR/manifest.json" "$staged_app/manifest.json"
for directory in bin config docs plugin provenance samples sbom scripts systemd toolchains; do
  [[ -d $SOURCE_DIR/$directory ]] || continue
  lcw3_copy_tree "$SOURCE_DIR/$directory" "$staged_app/$directory"
done
install -m 0755 "$SOURCE_DIR/install" "$staged_app/install"
chmod 0755 "$staged_app/bin/limechain-web3" "$staged_app/scripts/"*.sh "$staged_app/scripts/"*.py

cache_root="$LCW3_CACHE_HOME/limechain-web3"
cache_dir="$cache_root/downloads"
if (( ! SKIP_TOOLCHAINS )); then
  if [[ -e $cache_root || -L $cache_root ]]; then
    [[ -d $cache_root && ! -L $cache_root ]] || lcw3_fail "cache root collision: $cache_root"
    lcw3_require_owner_marker "$cache_root" "download-cache"
    unknown_cache=$(find "$cache_root" -mindepth 1 -maxdepth 1 \
      ! -name downloads ! -name .limechain-web3-managed.json -print -quit)
    [[ -z $unknown_cache ]] || lcw3_fail "cache root contains unmanaged content: $unknown_cache"
  else
    lcw3_write_owner_marker "$cache_root" "download-cache"
  fi
  lcw3_assert_managed_path "$cache_dir" "download cache"
  if [[ -e $cache_dir || -L $cache_dir ]]; then
    [[ -d $cache_dir && ! -L $cache_dir ]] || lcw3_fail "download cache collision: $cache_dir"
  fi
  install -d -m 0700 "$cache_dir"
fi

toolchain_root="$staged_app/toolchains/installed"
raw_bin="$staged_app/raw-bin"
env_bin="$staged_app/env/bin"
mkdir -p "$toolchain_root" "$raw_bin" "$env_bin"

install_profile() {
  local profile=$1
  local lock="$SOURCE_DIR/toolchains/$profile.lock.json"
  [[ -f $lock ]] || lcw3_fail "profile lockfile is missing: $lock"
  while IFS= read -r artifact; do
    local id version sha256 archive filename download destination old_destination marker file_manifest verified_tree staging
    id=$(jq -r '.id' <<<"$artifact")
    version=$(jq -r '.version' <<<"$artifact")
    sha256=$(jq -r '.sha256' <<<"$artifact")
    archive=$(jq -r '.archive' <<<"$artifact")
    filename="${id}-${version}.${archive//./-}"
    download="$cache_dir/$filename"
    destination="$toolchain_root/$id/$version"
    old_destination="$LCW3_APP_ROOT/toolchains/installed/$id/$version"
    marker="$destination/.limechain-verified"
    file_manifest="$destination/.limechain-files.sha256"
    if [[ -e $old_destination || -L $old_destination ]]; then
      python3 "$SOURCE_DIR/scripts/managed-tree.py" check \
        --target "$old_destination" --boundary "$LCW3_APP_ROOT" --scope toolchain
      python3 "$SOURCE_DIR/scripts/safe-extract.py" \
        --lock "$lock" --artifact "$id" --destination "$old_destination" --verify-tree \
        || lcw3_fail "existing toolchain tree is modified or unmanaged: $old_destination"
      mkdir -p "$(dirname -- "$destination")"
      cp -a "$old_destination" "$destination"
    fi
    verified_tree=0
    if [[ -f $marker && ! -L $marker && $(<"$marker") == "$sha256" && -f $file_manifest && ! -L $file_manifest ]]; then
      if python3 "$SOURCE_DIR/scripts/safe-extract.py" \
        --lock "$lock" --artifact "$id" --destination "$destination" --verify-tree; then
        verified_tree=1
      fi
    fi
    if (( ! verified_tree )); then
      if [[ -e $destination || -L $destination ]]; then
        lcw3_fail "refusing to replace a modified or unmanaged toolchain tree: $destination"
      fi
      python3 "$SOURCE_DIR/scripts/safe-download.py" \
        --lock "$lock" --artifact "$id" --output "$download"
      staging="$toolchain_root/.${id}-${version}.staging.$$"
      [[ ! -e $staging && ! -L $staging ]] || lcw3_fail "toolchain staging collision: $staging"
      python3 "$SOURCE_DIR/scripts/safe-extract.py" \
        --lock "$lock" --artifact "$id" --archive "$download" --destination "$staging"
      mkdir -p "$(dirname -- "$destination")"
      mv "$staging" "$destination"
    fi

    while IFS=$'\t' read -r command relative; do
      [[ -n $command && -n $relative ]] || continue
      local target="$destination/$relative"
      [[ -f $target && ! -L $target ]] || lcw3_fail "locked binary is not a regular file: $target"
      ln -s "../toolchains/installed/$id/$version/$relative" "$raw_bin/$command"
    done < <(jq -r '.bins | to_entries[] | [.key, .value] | @tsv' <<<"$artifact")
  done < <(jq -c '.artifacts[]' "$lock")

  if [[ $profile == "evm-core" ]]; then
    local python_venv="$staged_app/python"
    "$raw_bin/uv" venv --clear --python /usr/bin/python3 "$python_venv"
    "$raw_bin/uv" pip sync --python "$python_venv/bin/python" --require-hashes "$SOURCE_DIR/toolchains/python-requirements.lock"
    local command
    for command in crytic-compile slither solc-select; do
      [[ -x $python_venv/bin/$command ]] || lcw3_fail "Python tool did not install: $command"
      printf '#!/bin/bash\nexec %q %q "$@"\n' \
        "$LCW3_APP_ROOT/python/bin/python" "$LCW3_APP_ROOT/python/bin/$command" >"$raw_bin/$command"
      chmod 0755 "$raw_bin/$command"
    done
  fi

  if [[ $profile == "solana-core" ]]; then
    local platform_tools_version platform_tools_root solana_home platform_link relative_platform_tools
    platform_tools_version=$(jq -r '.artifacts[] | select(.id == "platform-tools") | .version' "$lock")
    platform_tools_root="$toolchain_root/platform-tools/$platform_tools_version"
    solana_home="$staged_app/solana-home"
    install -d -m 0700 "$solana_home" "$solana_home/.cache" "$solana_home/.cache/solana"
    install -d -m 0700 "$solana_home/.cache/solana/v$platform_tools_version"
    platform_link="$solana_home/.cache/solana/v$platform_tools_version/platform-tools"
    if [[ -e $platform_link || -L $platform_link ]]; then
      [[ -L $platform_link ]] || lcw3_fail "Solana platform-tools cache link collision"
      rm "$platform_link"
    fi
    relative_platform_tools=$(python3 -c 'import os,sys; print(os.path.relpath(sys.argv[1], sys.argv[2]))' \
      "$platform_tools_root" "$(dirname -- "$platform_link")")
    ln -s "$relative_platform_tools" "$platform_link"
  fi

  while IFS= read -r command; do
    local wrapper="$env_bin/$command"
    printf '#!/bin/bash\nexec %q exec %q "$@"\n' "$LCW3_APP_ROOT/bin/limechain-web3" "$command" >"$wrapper"
    chmod 0755 "$wrapper"
  done < <(
    jq -r '[.artifacts[].bins | keys[]] | unique[]' "$lock"
    if [[ $profile == "evm-core" ]]; then
      printf '%s\n' crytic-compile slither solc-select
    fi
  )
}

if (( ! SKIP_TOOLCHAINS )); then
  while IFS= read -r installed_profile; do
    install_profile "$installed_profile"
  done < <(jq -r '.[]' <<<"$profiles")
fi

jq -cn --arg version "$(<"$SOURCE_DIR/VERSION")" --argjson uid "$UID" \
  '{schema:1,owner:"limechain.web3",scope:"application-root",uid:$uid,version:$version}' \
  >"$staged_app/.limechain-web3-managed.json"
chmod 0600 "$staged_app/.limechain-web3-managed.json"

mkdir -p "$staged_units" "$backup_units"
escaped_root=${LCW3_APP_ROOT//&/\\&}
if jq -e 'index("evm-core") != null' <<<"$profiles" >/dev/null; then
  sed "s|@APP_ROOT@|$escaped_root|g" "$SOURCE_DIR/systemd/limechain-web3-anvil.service" \
    >"$staged_units/limechain-web3-anvil.service"
fi
if jq -e 'index("solana-core") != null' <<<"$profiles" >/dev/null; then
  sed "s|@APP_ROOT@|$escaped_root|g" "$SOURCE_DIR/systemd/limechain-web3-surfpool.service" \
    >"$staged_units/limechain-web3-surfpool.service"
fi
chmod 0644 "$staged_units/"*.service 2>/dev/null || true

jq -n \
  --arg version "$(<"$SOURCE_DIR/VERSION")" \
  --arg source "$SOURCE_DIR" \
  --arg profile "$PROFILE" \
  --argjson profiles "$profiles" \
  --argjson plugin_managed "$plugin_managed" \
  '{schema:3,version:$version,source:$source,profile:$profile,profiles:$profiles,plugin_managed:$plugin_managed}' \
  >"$staged_state"
chmod 0600 "$staged_state"

menu_file=$LCW3_MENU_FILE
lcw3_assert_managed_path "$menu_file" "Omarchy menu file"
if [[ -f $menu_file && ! -L $menu_file ]]; then
  menu_begin_count=$(grep -Fc '// BEGIN limechain.web3 (managed by limechain-web3)' "$menu_file" || true)
  menu_end_count=$(grep -Fc '// END limechain.web3' "$menu_file" || true)
  [[ $menu_begin_count == "$menu_end_count" && $menu_begin_count -le 1 ]] \
    || lcw3_fail "menu contains an ambiguous limechain.web3 managed block"
  cp "$menu_file" "$menu_backup"
  menu_existed=1
elif [[ -e $menu_file || -L $menu_file ]]; then
  lcw3_fail "menu path is not a regular file: $menu_file"
fi

if (( ! SKIP_OMARCHY )); then
  omarchy plugin validate "$LCW3_PLUGIN_ROOT"
  lcw3_require_unlocked_session
  for active_unit in "${LCW3_ACTIVE_USER_UNITS[@]}"; do
    systemctl --user stop "$active_unit"
  done
fi

# Commit begins only after every download, extraction, tool install, and validation succeeded.
app_replaced=1
if [[ -e $LCW3_APP_ROOT ]]; then
  mv "$LCW3_APP_ROOT" "$backup_app"
fi
mv "$staged_app" "$LCW3_APP_ROOT"

if [[ ${LCW3_TESTING:-0} == 1 && ${LCW3_TEST_FAIL_AT:-} == after-app-commit ]]; then
  lcw3_fail "injected transaction failure after application commit"
fi

if [[ ! -e $state_root ]]; then
  lcw3_write_owner_marker "$state_root" "install-state"
  state_root_created=1
fi
if [[ -e $LCW3_INSTALL_STATE ]]; then
  mv "$LCW3_INSTALL_STATE" "$backup_state"
fi
mv "$staged_state" "$LCW3_INSTALL_STATE"
state_replaced=1

install -d -m 0700 "$LCW3_SYSTEMD_ROOT"
units_replaced=1
for unit_name in limechain-web3-anvil.service limechain-web3-surfpool.service; do
  unit_target="$LCW3_SYSTEMD_ROOT/$unit_name"
  [[ ! -e $unit_target ]] || mv "$unit_target" "$backup_units/$unit_name"
  [[ ! -e $staged_units/$unit_name ]] || mv "$staged_units/$unit_name" "$unit_target"
done

install -d -m 0700 "$LCW3_BIN_HOME"
if [[ -L $cli_link ]]; then
  cli_existed=1
  rm "$cli_link"
fi
ln -s "$LCW3_APP_ROOT/bin/limechain-web3" "$cli_link"
cli_created=1

if [[ ! -e $config_root ]]; then
  config_source="$transaction/configuration"
  mkdir -p "$config_source"
  install -m 0600 "$SOURCE_DIR/config/config.json" "$config_source/config.json"
  python3 "$SCRIPT_DIR/managed-tree.py" install \
    --source "$config_source" --target "$config_root" --boundary "$LCW3_HOME" --scope configuration
  config_created=1
fi

if [[ $plugin_managed == true ]]; then
  plugin_source="$transaction/plugin-source"
  mkdir -p "$plugin_source/plugin"
  install -m 0644 "$SOURCE_DIR/manifest.json" "$plugin_source/manifest.json"
  lcw3_copy_tree "$SOURCE_DIR/plugin" "$plugin_source/plugin"
  plugin_preexisted=0
  [[ ! -e $LCW3_PLUGIN_ROOT ]] || plugin_preexisted=1
  python3 "$SCRIPT_DIR/managed-tree.py" install \
    --source "$plugin_source" --target "$LCW3_PLUGIN_ROOT" --boundary "$LCW3_HOME" --scope plugin-copy
  if (( ! plugin_preexisted )); then
    plugin_created=1
  fi
fi

"$cli_link" internal install-menu

if (( ! SKIP_OMARCHY )); then
  systemctl --user daemon-reload
  if (( ENABLE_PLUGIN )) && ! omarchy plugin list --json | jq -e 'any(.[]; .id == "limechain.web3" and .enabled == true)' >/dev/null; then
    omarchy plugin enable limechain.web3 --section right
  fi
  command -v omarchy-shell >/dev/null || lcw3_fail "omarchy-shell is not available"
  command -v omarchy-restart-shell >/dev/null || lcw3_fail "omarchy-restart-shell is not available"
  omarchy-shell shell rescanPlugins >/dev/null
  omarchy-restart-shell
  lcw3_restore_active_user_units
fi

commit_complete=1

echo "Web3 Workstation installed."
echo "Run: limechain-web3 doctor"
echo "Enter the verified environment with: limechain-web3 shell"
echo "Optional agent instructions were not installed. Review and opt in separately with: $SOURCE_DIR/install-agent-skill"
