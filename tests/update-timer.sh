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
