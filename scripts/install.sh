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
Usage: ./install [--profile evm-core|solana-core] [--skip-toolchains] [--skip-omarchy] [--no-enable-plugin]

Installs an additive, user-scoped Web3 workstation without elevated privileges or system package changes.
USAGE
}

replace_managed_plugin() {
  local parent staging backup
  parent=$(dirname -- "$LCW3_PLUGIN_ROOT")
  staging="$parent/.limechain.web3.staging.$$"
  backup="$parent/.limechain.web3.backup.$$"
  mkdir -p "$parent"
  rm -rf "$staging" "$backup"
  mkdir -p "$staging"
  install -m 0644 "$SOURCE_DIR/manifest.json" "$staging/manifest.json"
  lcw3_copy_tree "$SOURCE_DIR/plugin" "$staging/plugin"
  install -m 0644 /dev/null "$staging/.limechain-web3-managed"
  if [[ -e $LCW3_PLUGIN_ROOT || -L $LCW3_PLUGIN_ROOT ]]; then
    mv "$LCW3_PLUGIN_ROOT" "$backup"
    if ! mv "$staging" "$LCW3_PLUGIN_ROOT"; then
      mv "$backup" "$LCW3_PLUGIN_ROOT"
      lcw3_fail "could not atomically replace the managed plugin"
    fi
    rm -rf "$backup"
  else
    mv "$staging" "$LCW3_PLUGIN_ROOT"
  fi
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
evm-core | solana-core) ;;
*) lcw3_fail "supported profiles: evm-core, solana-core" ;;
esac

for path_info in \
  "$LCW3_APP_ROOT:application root" \
  "$LCW3_PLUGIN_ROOT:plugin root" \
  "$LCW3_SKILL_ROOT:skill root" \
  "$LCW3_INSTALL_STATE:install state"; do
  lcw3_assert_safe_path "${path_info%%:*}" "${path_info#*:}"
done

for command in jq python3 install cp cmp diff; do
  command -v "$command" >/dev/null || lcw3_fail "required command is missing: $command"
done

if (( ! SKIP_OMARCHY )); then
  [[ $(uname -s) == "Linux" ]] || lcw3_fail "Omarchy installation requires Linux"
  [[ $(uname -m) == "x86_64" ]] || lcw3_fail "the profile lockfiles currently support x86_64 only"
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

plugin_managed=false
plugin_changed=0
source_real=$(lcw3_realpath "$SOURCE_DIR")
plugin_real=$(lcw3_realpath "$LCW3_PLUGIN_ROOT")
if [[ ! -e $LCW3_PLUGIN_ROOT && ! -L $LCW3_PLUGIN_ROOT ]]; then
  plugin_managed=true
  plugin_changed=1
elif [[ $source_real != "$plugin_real" ]]; then
  [[ -f $LCW3_PLUGIN_ROOT/manifest.json ]] || lcw3_fail "existing plugin path has no manifest: $LCW3_PLUGIN_ROOT"
  installed_id=$(jq -r '.id // empty' "$LCW3_PLUGIN_ROOT/manifest.json")
  [[ $installed_id == "limechain.web3" ]] || lcw3_fail "plugin id collision at $LCW3_PLUGIN_ROOT"
  if [[ -f $LCW3_PLUGIN_ROOT/.limechain-web3-managed ]]; then
    plugin_managed=true
    if ! cmp -s "$SOURCE_DIR/manifest.json" "$LCW3_PLUGIN_ROOT/manifest.json" \
      || ! diff -qr "$SOURCE_DIR/plugin" "$LCW3_PLUGIN_ROOT/plugin" >/dev/null 2>&1; then
      plugin_changed=1
    fi
  fi
fi

if (( ! SKIP_OMARCHY && plugin_changed )); then
  lcw3_require_unlocked_session
fi

mkdir -p "$LCW3_APP_ROOT" "$LCW3_BIN_HOME" "$(dirname -- "$LCW3_INSTALL_STATE")"

install -m 0644 "$SOURCE_DIR/VERSION" "$LCW3_APP_ROOT/VERSION"
install -m 0644 "$SOURCE_DIR/LICENSE" "$LCW3_APP_ROOT/LICENSE"
install -m 0644 "$SOURCE_DIR/manifest.json" "$LCW3_APP_ROOT/manifest.json"
for directory in bin config docs plugin provenance samples sbom scripts skill systemd toolchains; do
  [[ -d $SOURCE_DIR/$directory ]] || continue
  lcw3_copy_tree "$SOURCE_DIR/$directory" "$LCW3_APP_ROOT/$directory"
done
install -m 0755 "$SOURCE_DIR/install" "$LCW3_APP_ROOT/install"
chmod 0755 "$LCW3_APP_ROOT/bin/limechain-web3" "$LCW3_APP_ROOT/scripts/"*.sh

cli_link="$LCW3_BIN_HOME/limechain-web3"
if [[ -e $cli_link && ! -L $cli_link ]]; then
  lcw3_fail "refusing to replace an unmanaged command: $cli_link"
fi
if [[ -L $cli_link ]]; then
  current_target=$(lcw3_realpath "$cli_link")
  expected_target=$(lcw3_realpath "$LCW3_APP_ROOT/bin/limechain-web3")
  [[ $current_target == "$expected_target" ]] || lcw3_fail "refusing to replace a foreign symlink: $cli_link"
fi
ln -sfn "$LCW3_APP_ROOT/bin/limechain-web3" "$cli_link"

config_file="$LCW3_CONFIG_HOME/limechain-web3/config.json"
if [[ ! -e $config_file ]]; then
  install -d -m 0700 "$(dirname -- "$config_file")"
  install -m 0600 "$SOURCE_DIR/config/config.json" "$config_file"
else
  chmod 0600 "$config_file"
fi

if (( plugin_changed )); then
  replace_managed_plugin
fi

install -d -m 0755 "$LCW3_SKILL_ROOT"
lcw3_copy_tree "$SOURCE_DIR/skill/limechain-web3" "$LCW3_SKILL_ROOT"
install -m 0644 /dev/null "$LCW3_SKILL_ROOT/.limechain-web3-managed"

if (( ! SKIP_TOOLCHAINS )); then
  for command in curl sha256sum bsdtar; do
    command -v "$command" >/dev/null || lcw3_fail "toolchain installation requires: $command"
  done

  lock="$SOURCE_DIR/toolchains/$PROFILE.lock.json"
  cache_dir="$LCW3_CACHE_HOME/limechain-web3/downloads"
  toolchain_root="$LCW3_APP_ROOT/toolchains/installed"
  raw_bin="$LCW3_APP_ROOT/raw-bin"
  env_bin="$LCW3_APP_ROOT/env/bin"
  mkdir -p "$cache_dir" "$toolchain_root" "$raw_bin" "$env_bin"

  while IFS= read -r artifact; do
    id=$(jq -r '.id' <<<"$artifact")
    version=$(jq -r '.version' <<<"$artifact")
    url=$(jq -r '.url' <<<"$artifact")
    sha256=$(jq -r '.sha256' <<<"$artifact")
    archive=$(jq -r '.archive' <<<"$artifact")
    strip_components=$(jq -r '.strip_components // 0' <<<"$artifact")
    filename="${id}-${version}.${archive//./-}"
    download="$cache_dir/$filename"
    destination="$toolchain_root/$id/$version"
    marker="$destination/.limechain-verified"

    file_manifest="$destination/.limechain-files.sha256"
    verified_tree=0
    if [[ -f $marker && $(<"$marker") == "$sha256" && -f $file_manifest ]]; then
      if (cd -- "$destination" && sha256sum --check --quiet .limechain-files.sha256); then
        verified_tree=1
      fi
    fi

    if (( ! verified_tree )); then
      if [[ ! -f $download || $(lcw3_sha256 "$download") != "$sha256" ]]; then
        rm -f "$download"
        curl --proto '=https' --tlsv1.2 --fail --location --retry 3 \
          --connect-timeout 10 --max-time 300 --output "$download" "$url"
      fi
      actual=$(lcw3_sha256 "$download")
      [[ $actual == "$sha256" ]] || lcw3_fail "checksum mismatch for $id $version"

      staging="$toolchain_root/.${id}-${version}.tmp.$$"
      rm -rf "$staging"
      mkdir -p "$staging"
      case "$archive" in
      raw)
        install -m 0755 "$download" "$staging/$id"
        ;;
      tar.gz | tar.xz | tar.bz2 | zip)
        bsdtar -xf "$download" -C "$staging" --strip-components "$strip_components"
        ;;
      *)
        lcw3_fail "unsupported archive type for $id: $archive"
        ;;
      esac
      (
        cd -- "$staging"
        find . -type f ! -name '.limechain-files.sha256' ! -name '.limechain-verified' -print0 \
          | sort -z \
          | xargs -0 sha256sum >.limechain-files.sha256
      )
      rm -rf "$destination"
      mkdir -p "$(dirname -- "$destination")"
      mv "$staging" "$destination"
      printf '%s\n' "$sha256" >"$marker"
    fi

    while IFS=$'\t' read -r command relative; do
      [[ -n $command && -n $relative ]] || continue
      target="$destination/$relative"
      [[ -f $target ]] || lcw3_fail "locked binary missing after extraction: $target"
      chmod 0755 "$target"
      ln -sfn "$target" "$raw_bin/$command"
    done < <(jq -r '.bins | to_entries[] | [.key, .value] | @tsv' <<<"$artifact")
  done < <(jq -c '.artifacts[]' "$lock")

  if [[ $PROFILE == "evm-core" ]]; then
    python_venv="$LCW3_APP_ROOT/python"
    "$raw_bin/uv" venv --clear --python /usr/bin/python3 "$python_venv"
    "$raw_bin/uv" pip sync --python "$python_venv/bin/python" --require-hashes "$SOURCE_DIR/toolchains/python-requirements.lock"
    for command in crytic-compile slither solc-select; do
      [[ -x $python_venv/bin/$command ]] || lcw3_fail "Python tool did not install: $command"
      ln -sfn "$python_venv/bin/$command" "$raw_bin/$command"
    done
    [[ -x $python_venv/bin/solc ]] && ln -sfn "$python_venv/bin/solc" "$raw_bin/solc-select-solc"

    solc_version=$(jq -r '.artifacts[] | select(.id == "solc") | .version' "$lock")
    svm_dir="$LCW3_HOME/.svm/$solc_version"
    mkdir -p "$svm_dir"
    ln -sfn "$raw_bin/solc" "$svm_dir/solc-$solc_version"
  fi

  if [[ $PROFILE == "solana-core" ]]; then
    platform_tools_version=$(jq -r '.artifacts[] | select(.id == "platform-tools") | .version' "$lock")
    platform_tools_root="$toolchain_root/platform-tools/$platform_tools_version"
    solana_home="$LCW3_APP_ROOT/solana-home"
    install -d -m 0700 "$solana_home" "$solana_home/.cache" "$solana_home/.cache/solana"
    install -d -m 0700 "$solana_home/.cache/solana/v$platform_tools_version"
    ln -sfn "$platform_tools_root" "$solana_home/.cache/solana/v$platform_tools_version/platform-tools"
  fi

  while IFS= read -r command; do
    wrapper="$env_bin/$command"
    printf '#!/bin/bash\nexec %q exec %q "$@"\n' "$cli_link" "$command" >"$wrapper"
    chmod 0755 "$wrapper"
  done < <(
    jq -r '[.artifacts[].bins | keys[]] | unique[]' "$lock"
    if [[ $PROFILE == "evm-core" ]]; then
      printf '%s\n' crytic-compile slither solc-select
    fi
  )
fi

mkdir -p "$LCW3_SYSTEMD_ROOT"
escaped_root=${LCW3_APP_ROOT//&/\\&}
case "$PROFILE" in
evm-core)
  unit_name="limechain-web3-anvil.service"
  ;;
solana-core)
  unit_name="limechain-web3-surfpool.service"
  ;;
esac
unit_source="$SOURCE_DIR/systemd/$unit_name"
unit_target="$LCW3_SYSTEMD_ROOT/$unit_name"
sed "s|@APP_ROOT@|$escaped_root|g" "$unit_source" >"$unit_target"
chmod 0644 "$unit_target"

existing_profiles='[]'
if [[ -f $LCW3_INSTALL_STATE ]]; then
  existing_profiles=$(jq -c 'if (.profiles | type) == "array" then .profiles elif .profile then [.profile] else [] end' "$LCW3_INSTALL_STATE")
fi
profiles=$(jq -cn --argjson existing "$existing_profiles" --arg profile "$PROFILE" '$existing + [$profile] | unique')
jq -n \
  --arg version "$(<"$SOURCE_DIR/VERSION")" \
  --arg source "$SOURCE_DIR" \
  --arg profile "$PROFILE" \
  --argjson profiles "$profiles" \
  --argjson plugin_managed "$plugin_managed" \
  '{schema:2,version:$version,source:$source,profile:$profile,profiles:$profiles,plugin_managed:$plugin_managed}' \
  >"$LCW3_INSTALL_STATE"
chmod 0600 "$LCW3_INSTALL_STATE"

"$cli_link" internal install-menu

if (( ! SKIP_OMARCHY )); then
  omarchy plugin validate "$LCW3_PLUGIN_ROOT"
  if (( plugin_changed )); then
    command -v omarchy-shell >/dev/null || lcw3_fail "omarchy-shell is not available"
    omarchy-shell shell rescanPlugins >/dev/null
  fi
  if (( ENABLE_PLUGIN )) && ! omarchy plugin list --json | jq -e 'any(.[]; .id == "limechain.web3" and .enabled == true)' >/dev/null; then
    omarchy plugin enable limechain.web3 --section right
  fi
  if (( plugin_changed )); then
    command -v omarchy-restart-shell >/dev/null || lcw3_fail "omarchy-restart-shell is not available"
    omarchy-restart-shell
  fi
  systemctl --user daemon-reload
  lcw3_restore_active_user_units
fi

echo "Web3 Workstation installed."
echo "Run: limechain-web3 doctor"
echo "Enter the verified environment with: limechain-web3 shell"
