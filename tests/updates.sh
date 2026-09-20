#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "$0")/.."
source ./dodo-sbox.sh
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
DODO_ROOT=$work/root
DATA=$work/data
CORE=$DODO_ROOT/core/sing-box
mkdir -p "$DODO_ROOT/core" "$DATA/current"
touch "$DODO_ROOT/.dodo-owned" "$DATA/.dodo-owned"
printf '#!/usr/bin/env bash\necho "sing-box version 0.0.0"\n' > "$CORE"
chmod 755 "$CORE"
old_hash=$(sha256 "$CORE")
core_download() { cp "${TEST_CORE:?}" "$1" && chmod 755 "$1"; }
systemctl() { [[ $1 != is-active ]]; }
printf 'invalid config\n' > "$DATA/current/config.json"
if update_core; then echo 'FAIL invalid configuration accepted'; exit 1; fi
[[ $(sha256 "$CORE") == "$old_hash" ]]
echo 'PASS invalid configuration leaves original core intact'
printf '{"outbounds":[{"type":"direct","tag":"direct"}]}\n' > "$DATA/current/config.json"
systemctl() { return 0; }
service_healthy() { return 1; }
if update_core; then echo 'FAIL unhealthy core accepted'; exit 1; fi
[[ $(sha256 "$CORE") == "$old_hash" ]]
echo 'PASS unhealthy service restores old core'
systemctl() { [[ $1 != is-active ]]; }
update_core
[[ $(sha256 "$CORE") == "$(sha256 "$TEST_CORE")" ]]
echo 'PASS stopped service can update without being started'

printf 'original-manager\n' > "$DODO_ROOT/manager.sh"
update_latest() { printf 'update_core() { return 1; }\n' > "$DODO_ROOT/manager.sh"; }
if update_all; then echo 'FAIL failed combined update accepted'; exit 1; fi
[[ $(cat "$DODO_ROOT/manager.sh") == original-manager ]]
echo 'PASS combined update restores manager when new core update fails'
update_latest() { printf 'update_core() { return 0; }\n' > "$DODO_ROOT/manager.sh"; }
update_all
grep -q 'return 0' "$DODO_ROOT/manager.sh"
echo 'PASS combined update runs the new manager core updater'
