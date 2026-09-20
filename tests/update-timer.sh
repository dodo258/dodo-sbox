#!/usr/bin/env bash
# Only for disposable systemd-based Linux CI, not an existing customer installation.
set -euo pipefail
cd -- "$(dirname -- "$0")/.."
[[ ! -e /opt/dodo-sbox && ! -e /var/lib/dodo-sbox ]]
bash dist/dodo-sbox install
# A test-only unit condition prevents a scheduled check from downloading an older
# public release before this candidate has itself been released.
mkdir -p /run/systemd/system/dodo-sbox-update.service.d
printf '[Unit]\nConditionPathExists=/run/dodo-sbox-ci-allow-update\n' > /run/systemd/system/dodo-sbox-update.service.d/ci.conf
cleanup() {
    printf 'y\n' | bash /opt/dodo-sbox/manager.sh uninstall
    rm -f /run/systemd/system/dodo-sbox-update.service.d/ci.conf
    rmdir /run/systemd/system/dodo-sbox-update.service.d
    systemctl daemon-reload
}
trap cleanup EXIT
# Exercise certificate activation with real Linux ownership and symlink switching.
source ./dodo-sbox.sh
mkdir -m 700 "$DATA/cert-test"
openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:P-256 -nodes \
    -keyout "$DATA/cert-test/key.pem" -out "$DATA/cert-test/fullchain.pem" -days 2 \
    -subj /CN=test.example.com -addext subjectAltName=DNS:test.example.com >/dev/null 2>&1
activate_cert test.example.com "$DATA/cert-test" acme
[[ $(certificate_source test.example.com) == acme ]]
old_cert=$(readlink "$DATA/certs/test.example.com/active")
activate_cert test.example.com "$DATA/cert-test" acme
[[ $(readlink "$DATA/certs/test.example.com/active") == "$old_cert" ]]
activate_cert test.example.com "$DATA/cert-test" import
[[ $(certificate_source test.example.com) == import ]]
[[ $(readlink "$DATA/certs/test.example.com/active") != "$old_cert" ]]
[[ $(stat -c '%a' "$DATA/certs/test.example.com/active/renewal-source") == 600 ]]
echo 'PASS atomic certificate origin switching and repeated activation'
# Exercise the real configuration transaction with a stopped Reality node.
# The external target was separately tested; this gate focuses on local rollback.
(
    pair=$("$CORE" generate reality-keypair)
    private=$(printf '%s\n' "$pair" | awk '/PrivateKey:/{print $2}')
    public=$(printf '%s\n' "$pair" | awk '/PublicKey:/{print $2}')
    uuid=$("$CORE" generate uuid)
    jq -n --arg private "$private" --arg public "$public" --arg uuid "$uuid" \
      '{schema:1,policies:[],unlock_dns:null,egress:null,nodes:[{id:"1111111111111111",name:"test",type:"vless",enabled:false,host:"127.0.0.1",port:18101,sni:"www.ctrip.com",uuid:$uuid,private_key:$private,public_key:$public,short_id:"0123456789abcdef"}]}' > "$DATA/cert-test/state.json"
    apply_state "$DATA/cert-test/state.json"
    original=$(readlink "$DATA/current")
    reality_target_check() { return 0; }
    firewall_sync() { [[ $(jq -r '.nodes[0].sni' "$1") != www.ixigua.com ]]; }
    ! node_change 1111111111111111 reality www.ixigua.com
    [[ $(readlink "$DATA/current") == "$original" ]]
    [[ ! -e $DATA/pending.json ]]
    firewall_sync() { return 0; }
    node_change 1111111111111111 reality www.ixigua.com
    jq -e '.nodes[0].sni=="www.ixigua.com" and .nodes[0].enabled==false' "$STATE" >/dev/null
    ! systemctl is-active --quiet "$SERVICE"
)
echo 'PASS real Reality configuration transaction rolls back on failure and preserves stopped state'
bash /opt/dodo-sbox/manager.sh auto-update on
systemctl is-enabled --quiet dodo-sbox-update.timer
systemctl is-active --quiet dodo-sbox-update.timer
systemd-analyze verify /etc/systemd/system/dodo-sbox-update.service /etc/systemd/system/dodo-sbox-update.timer
bash /opt/dodo-sbox/manager.sh auto-update status
bash /opt/dodo-sbox/manager.sh auto-update off
! systemctl is-active --quiet dodo-sbox-update.timer
[[ ! -e /etc/systemd/system/dodo-sbox-update.service ]]
echo 'PASS real systemd timer enable, status and disable'
# Avoid network updates during this test, then check uninstall cleans the timer.
bash /opt/dodo-sbox/manager.sh auto-update on
cleanup
trap - EXIT
[[ ! -e /opt/dodo-sbox && ! -e /var/lib/dodo-sbox ]]
[[ ! -e /etc/systemd/system/dodo-sbox-update.timer ]]
echo 'PASS uninstall removes manager and update timer'
