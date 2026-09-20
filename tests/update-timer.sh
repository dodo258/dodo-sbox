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
