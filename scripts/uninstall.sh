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

lcw3_assert_safe_path "$LCW3_APP_ROOT" "application root"
lcw3_assert_safe_path "$LCW3_PLUGIN_ROOT" "plugin root"
lcw3_assert_safe_path "$LCW3_SKILL_ROOT" "skill root"

if command -v systemctl >/dev/null; then
  systemctl --user stop limechain-web3-anvil.service >/dev/null 2>&1 || true
  rm -f "$LCW3_SYSTEMD_ROOT/limechain-web3-anvil.service"
  systemctl --user daemon-reload >/dev/null 2>&1 || true
fi

if [[ -x $LCW3_APP_ROOT/bin/limechain-web3 ]]; then
  "$LCW3_APP_ROOT/bin/limechain-web3" internal remove-menu || true
fi

cli_link="$LCW3_BIN_HOME/limechain-web3"
if [[ -L $cli_link && $(lcw3_realpath "$cli_link") == $(lcw3_realpath "$LCW3_APP_ROOT/bin/limechain-web3") ]]; then
  rm -f "$cli_link"
fi

if [[ -f $LCW3_SKILL_ROOT/.limechain-web3-managed ]]; then
  rm -rf "$LCW3_SKILL_ROOT"
fi

if [[ -f $LCW3_PLUGIN_ROOT/.limechain-web3-managed ]]; then
  rm -rf "$LCW3_PLUGIN_ROOT"
elif command -v omarchy >/dev/null && [[ -e $LCW3_PLUGIN_ROOT ]]; then
  lcw3_export_omarchy_path
  omarchy plugin remove limechain.web3 --yes || true
fi

rm -rf "$LCW3_APP_ROOT"
rm -f "$LCW3_INSTALL_STATE"

if (( PURGE )); then
  rm -rf "$LCW3_CONFIG_HOME/limechain-web3" "$LCW3_CACHE_HOME/limechain-web3"
  echo "Removed the workstation, cached downloads, and its credential-free configuration."
else
  echo "Removed the workstation. Configuration and verified download cache were preserved."
fi
