#!/bin/bash

set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
skill_home=${HOME:?HOME is required}
if [[ ${LCW3_TESTING:-0} == 1 ]]; then
  skill_home=${LCW3_HOME:-$skill_home}
elif [[ -n ${LCW3_HOME:-} && $LCW3_HOME != "$HOME" ]]; then
  echo "uninstall-agent-skill: LCW3_HOME overrides are test-only" >&2
  exit 1
fi
skill_home=$(python3 -c 'import os,sys; print(os.path.abspath(sys.argv[1]))' "$skill_home")
skill_root="$skill_home/.agents/skills/limechain-web3"

python3 "$SCRIPT_DIR/managed-tree.py" remove \
  --target "$skill_root" \
  --boundary "$skill_home" \
  --scope agent-skill

echo "Optional agent skill removed."
