#!/usr/bin/env bash
# Model firewalld's separate runtime/permanent stores without touching the host.
set -euo pipefail
cd -- "$(dirname -- "$0")/.."
source ./dodo-sbox.sh
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
DODO_ROOT=$work/root
DATA=$work/data
mkdir -p "$DODO_ROOT" "$DATA" "$work/rules"
touch "$DODO_ROOT/.dodo-owned" "$DATA/.dodo-owned"
firewall_detect() { printf 'firewalld\n'; }
firewall-cmd() {
    local zone='' scope=runtime arg action='' port=''
    for arg in "$@"; do
        case $arg in
          --get-active-zones) printf 'public\n  interfaces: eth0\n'; return 0;;
          --zone=*) zone=${arg#*=};; --permanent) scope=permanent;;
          --query-port=*) action=query; port=${arg#*=};;
          --add-port=*) action=add; port=${arg#*=};;
          --remove-port=*) action=remove; port=${arg#*=};;
          *) return 2;;
        esac
    done
    port=${port/\//-}
    case $action in
      query) if [[ -f $work/rules/$zone-$scope-$port ]]; then printf 'yes\n'; else printf 'no\n'; return 1; fi;;
      add) touch "$work/rules/$zone-$scope-$port";;
      remove) rm "$work/rules/$zone-$scope-$port";;
    esac
}
touch "$work/rules/public-permanent-23999-tcp"
printf '{"nodes":[{"port":23999,"type":"vless","enabled":true},{"port":24000,"type":"hysteria2","enabled":true}]}\n' > "$work/state"
firewall_sync "$work/state"
[[ ! -e $DATA/firewall/firewalld-public-permanent-23999-tcp ]]
[[ -f $DATA/firewall/firewalld-public-runtime-23999-tcp ]]
[[ -f $work/rules/public-runtime-24000-udp && -f $work/rules/public-permanent-24000-udp ]]
echo 'PASS firewalld keeps independent ownership of runtime and permanent rules'
firewall_sync "$work/state"
firewall_clear
[[ $(find "$work/rules" -type f | wc -l | tr -d ' ') == 1 ]]
[[ -f $work/rules/public-permanent-23999-tcp ]]
echo 'PASS cleanup retains pre-existing permanent permission'
firewall-cmd() {
    case $1 in --get-active-zones) printf 'public\n';; *) printf 'query failed\n'; return 254;; esac
}
if firewall_sync "$work/state"; then echo 'FAIL unknown firewall state accepted'; exit 1; fi
echo 'PASS query failures do not create permission records or mutate rules'
