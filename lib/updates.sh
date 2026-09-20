# Called under the same flock as node/configuration changes.
update_all() {
    owned_root || return 1
    local before after backup
    backup=$(mktemp "$DODO_ROOT/.update-before.XXXXXX") || return 1
    cp -p "$DODO_ROOT/manager.sh" "$backup" || return 1
    before=$(sha256 "$backup")
    if ! update_latest; then rm -f "$backup"; return 1; fi
    after=$(sha256 "$DODO_ROOT/manager.sh")
    # Load the new script's validated core version without reacquiring our lock.
    if bash -c 'source "$1" && update_core' bash "$DODO_ROOT/manager.sh"; then
        rm -f "$backup"
        msg '脚本和已验证核心已检查完成；协议实现随核心更新。'
        return 0
    fi
    if [[ $before != "$after" ]]; then
        mv -f "$backup" "$DODO_ROOT/manager.sh" || return 1
        err '核心更新失败，管理脚本已恢复为更新前版本。'
    else rm -f "$backup"; fi
    return 1
}
update_units_owned() {
    local unit
    for unit in dodo-sbox-update.service dodo-sbox-update.timer; do
        if [[ -e /etc/systemd/system/$unit ]] && ! grep -qx '# DODO_SBOX_AUTO_UPDATE' "/etc/systemd/system/$unit"; then
            err "自动更新服务名被其他配置占用：$unit"; return 1
        fi
        if [[ ! -e /etc/systemd/system/$unit ]] && systemctl cat "$unit" >/dev/null 2>&1; then
            err "自动更新服务名已存在：$unit"; return 1
        fi
    done
}
auto_update_on() {
    owned_root && update_units_owned || return 1
    cat > /etc/systemd/system/dodo-sbox-update.service <<'UNIT' || return 1
# DODO_SBOX_AUTO_UPDATE
[Unit]
Description=Update dodo-sbox and its validated sing-box core
Wants=network-online.target
After=network-online.target
[Service]
Type=oneshot
UMask=0077
ExecStart=/bin/bash /opt/dodo-sbox/manager.sh update
TimeoutStartSec=15min
UNIT
    cat > /etc/systemd/system/dodo-sbox-update.timer <<'UNIT' || return 1
# DODO_SBOX_AUTO_UPDATE
[Unit]
Description=Daily dodo-sbox update check
[Timer]
OnCalendar=*-*-* 04:00:00
RandomizedDelaySec=30min
Persistent=true
Unit=dodo-sbox-update.service
[Install]
WantedBy=timers.target
UNIT
    systemctl daemon-reload && systemctl enable --now dodo-sbox-update.timer || return 1
    msg '已开启每日自动更新（服务器时间 04:00–04:30，错过后会补做）。核心更新可能短暂中断本脚本节点。'
}
auto_update_off() {
    owned_root && update_units_owned || return 1
    systemctl disable --now dodo-sbox-update.timer 2>/dev/null || true
    # Do not interrupt an update already in progress.
    rm -f /etc/systemd/system/dodo-sbox-update.timer /etc/systemd/system/dodo-sbox-update.service
    systemctl daemon-reload || return 1
    msg '自动更新已关闭；若已有更新正在运行，会完成本次操作。证书续期不受影响。'
}
auto_update_status() {
    if systemctl is-enabled --quiet dodo-sbox-update.timer 2>/dev/null; then
        msg '自动更新：已开启'
        systemctl list-timers dodo-sbox-update.timer --no-pager
    else msg '自动更新：未开启（可手动运行 dodo-sbox update）'; fi
}
update_menu() {
    auto_update_status
    msg $'\n1.一键更新脚本和已验证核心\n2.仅更新脚本\n3.仅更新已验证核心\n4.开启每日自动更新\n5.关闭每日自动更新\n6.回滚配置\n7.回滚脚本\n0.返回'
    ask '请选择' || return 0
    case $REPLY in
      1) with_lock update_all;;
      2) with_lock update_latest;;
      3) with_lock update_core;;
      4) msg '每天自动下载安装本项目发布的脚本和对应核心；重启仅影响本脚本节点。'; yesno '开启自动更新' && with_lock auto_update_on;;
      5) with_lock auto_update_off;;
      6) yesno '恢复上一份配置（影响本脚本节点）' && with_lock rollback_config;;
      7) with_lock rollback_script;;
      *) err '无效选项。';;
    esac
}
restart_nodes() {
    owned_root || return 1
    [[ -f $STATE ]] || { err '请先部署节点。'; return 1; }
    if [[ $(jq '[.nodes[]|select(.enabled)]|length' "$STATE") == 0 ]]; then msg '没有启用的节点。'; return 0; fi
    "$CORE" check -c "$DATA/current/config.json" && systemctl restart "$SERVICE" && service_healthy "$STATE"
}
