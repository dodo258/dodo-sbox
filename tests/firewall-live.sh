#!/usr/bin/env bash
# Run only in disposable CI, inside separate network AND mount namespaces.
set -Eeuo pipefail
trap 'echo "Firewall test failed at line $LINENO"; ufw show added || true; iptables-save || true' ERR
[[ ${GITHUB_ACTIONS:-} == true && $EUID == 0 ]]
[[ $(readlink /proc/self/ns/net) != "$(readlink /proc/1/ns/net)" ]]
[[ $(readlink /proc/self/ns/mnt) != "$(readlink /proc/1/ns/mnt)" ]]
cd -- "$(dirname -- "$0")/.."
source ./dodo-sbox.sh
work=$(mktemp -d)
mount --make-rprivate /
cp -a /etc/ufw "$work/etc-ufw"
cp /etc/default/ufw "$work/ufw-default"
mount --bind "$work/etc-ufw" /etc/ufw
mount --bind "$work/ufw-default" /etc/default/ufw
cleanup() {
    ufw --force disable >/dev/null || true
    umount /etc/ufw
    umount /etc/default/ufw
    rm -rf "$work"
}
trap cleanup EXIT
ufw --force reset >/dev/null
ufw default deny incoming >/dev/null
ufw allow 22222/tcp comment 'existing SSH' >/dev/null
ufw allow 23999/tcp comment 'existing application' >/dev/null
ufw --force enable >/dev/null
LC_ALL=C ufw show added > "$work/original.rules"
DODO_ROOT=$work/root
DATA=$work/data
STATE=$DATA/state.json
mkdir -p "$DODO_ROOT" "$DATA"
touch "$DODO_ROOT/.dodo-owned" "$DATA/.dodo-owned"
printf '{"nodes":[{"port":23999,"type":"anytls","enabled":true},{"port":24000,"type":"hysteria2","enabled":true}]}\n' > "$STATE"
firewall_sync "$STATE"
ufw show added | grep -q 'dodo-sbox-23999-tcp'
ufw show added | grep -q 'dodo-sbox-24000-udp'
iptables-save | grep -- '--dport 24000 ' | grep -q -- '-j ACCEPT'
ufw show added | grep -q 'existing application'
echo 'PASS real UFW TCP/UDP rules coexist with pre-existing allow on same port'
firewall_sync "$STATE"
[[ $(ufw show added | grep -c 'dodo-sbox-24000-udp') == 1 ]]
echo 'PASS repeated sync is idempotent'
firewall_sync "$STATE" 443
ufw show added | grep -q 'dodo-sbox-443-tcp'
firewall_sync "$STATE"
! ufw show added | grep -q 'dodo-sbox-443-tcp'
echo 'PASS temporary certificate port is removed while node ports remain'
mkdir -p "$DODO_ROOT/acme-accounts/example.com"
printf '443\n' > "$DODO_ROOT/acme-accounts/example.com/challenge-port"
acme_call() { return 1; }
if firewall_renew example.com; then echo 'FAIL expected ACME failure'; exit 1; fi
! ufw show added | grep -q 'dodo-sbox-443-tcp'
echo 'PASS failed certificate renewal also cleans temporary port'
jq '.nodes[0].port=24001|.nodes[1].enabled=false' "$STATE" > "$work/new-state"
firewall_sync "$work/new-state"
! ufw show added | grep -q 'dodo-sbox-23999-tcp'
! ufw show added | grep -q 'dodo-sbox-24000-udp'
ufw show added | grep -q 'dodo-sbox-24001-tcp'
ufw show added | grep -q 'existing application'
echo 'PASS change port and disable remove only owned rules'
firewall_clear
LC_ALL=C ufw show added > "$work/final.rules"
cmp "$work/original.rules" "$work/final.rules"
echo 'PASS cleanup preserves original rules exactly'
printf 'ufw\tglobal\tboth\t24002\ttcp\n' > "$DATA/firewall/ufw-global-both-24002-tcp"
firewall_clear
[[ ! -e /etc/ufw/applications.d/dodo-sbox-24002-tcp ]]
LC_ALL=C ufw show added > "$work/final.rules"
cmp "$work/original.rules" "$work/final.rules"
echo 'PASS interrupted profile creation can be cleaned without touching original rules'
printf 'foreign file\n' > /etc/ufw/applications.d/dodo-sbox-24003-tcp
if firewall_add ufw global both 24003 tcp; then echo 'FAIL foreign profile overwritten'; exit 1; fi
[[ $(cat /etc/ufw/applications.d/dodo-sbox-24003-tcp) == 'foreign file' ]]
[[ ! -e $DATA/firewall/ufw-global-both-24003-tcp ]]
rm /etc/ufw/applications.d/dodo-sbox-24003-tcp
echo 'PASS conflicting application file is preserved'
ufw --force disable >/dev/null
[[ $(firewall_detect) == none ]]
firewall_sync "$STATE"
[[ $(firewall_detect) == none ]]
echo 'PASS disabled UFW is never enabled by manager'
