menu_header() {
    local status='未部署' counts='0 / 0' renew='未配置' routing='未启用' color='' reset=''
    if [[ -t 1 && -z ${NO_COLOR:-} && ${TERM:-dumb} != dumb ]]; then color=$'\033[1;36m'; reset=$'\033[0m'; fi
    if [[ -f $DODO_ROOT/.dodo-owned ]]; then
        status='已安装，服务未运行'
        systemctl is-active --quiet "$SERVICE" && status='运行中'
    fi
    if [[ -f $STATE ]] && command -v jq >/dev/null; then
        counts=$(jq -r '"\([.nodes[]|select(.enabled)]|length) / \(.nodes|length)"' "$STATE")
        routing=$(jq -r 'if (.policies|length)==0 then "未启用" else "\(.policies|length) 条平台规则" end' "$STATE")
    fi
    systemctl is-active --quiet dodo-sbox-renew.timer && renew='每日自动检查'
    printf '\n%s━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━%s\n' "$color" "$reset"
    printf '  dodo258 节点管理  v%s\n' "$DODO_VERSION"
    printf '  VLESS Reality · AnyTLS · Hysteria2\n'
    printf '%s━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━%s\n' "$color" "$reset"
    printf '  服务：%s    节点：%s（启用 / 总数）\n' "$status" "$counts"
    printf '  分流：%s    证书续期：%s\n\n' "$routing" "$renew"
}
main_menu() {
    require_linux || return 1
    while :; do
        menu_header
        msg $'  1. 部署节点\n  2. 节点管理 · 原始链接 / 二维码\n  3. 流媒体分流 · 解锁 DNS / 代理出口\n  4. 运行状态与日志\n  5. 更新与回滚\n  6. BBR 与系统检测\n  7. 卸载\n\n  0. 退出\n'
        ask '请选择' || return 0
        case $REPLY in
          1) with_lock node_add "$DODO_SELF";;
          2) node_menu;;
          3) with_lock routing_menu;;
          4) show_status; yesno '查看最近 50 行日志（分享前请检查敏感信息）' && journalctl -u "$SERVICE" -n 50 --no-pager;;
          5)
            msg '1.检查并更新脚本 2.更新到本脚本验证的核心版本 3.回滚配置 4.回滚脚本 5.指定脚本包更新'
            ask '选择' 1 || continue
            case $REPLY in
              1) with_lock update_latest;;
              5)
                ask '发布包 HTTPS 地址或本地绝对路径' || continue; local source=$REPLY
                ask '发布包 SHA256' || continue
                with_lock update_script "$source" "$REPLY";;
              2) with_lock update_core;;
              3) yesno '恢复上一份配置（影响本脚本节点）' && with_lock rollback_config;;
              4) with_lock rollback_script;;
            esac;;
          6)
            bbr_status
            msg 'BBR 为主机级 TCP 设置。共存测试请保持现状。'
            yesno '当前内核支持时自动开启 BBR + FQ（不更换内核、不重启）' && with_lock bbr_enable;;
          7) with_lock uninstall; [[ -f $DODO_ROOT/.dodo-owned ]] || return 0;;
          *) err '无效选项。';;
        esac
    done
}
rollback_script() {
    owned_root && [[ -f $DODO_ROOT/manager.previous.sh ]] || return 1
    bash -n "$DODO_ROOT/manager.previous.sh" && install -m 755 "$DODO_ROOT/manager.previous.sh" "$DODO_ROOT/manager.sh" && msg '脚本已回滚，请重新运行。'
}
main() {
    umask 077
    case ${1:-menu} in
      menu) main_menu;;
      install) with_lock setup "$DODO_SELF";;
      renew) with_lock renew_certificates;;
      status) require_linux && show_status;;
      export) [[ $EUID == 0 ]] && export_node "${2:-}" "${3:-uri}";;
      render) command -v jq >/dev/null && render_config "$2";;
      version|--version) printf 'dodo-sbox %s / tested core %s\n' "$DODO_VERSION" "$CORE_VERSION";;
      help|--help) msg $'bash dodo-sbox [menu|install|status|renew|export NODE_ID uri|qr|details|version]\n离线验证：bash dodo-sbox render STATE.json\n首次使用：直接运行菜单选择部署。0 返回，Ctrl+C 取消。';;
      *) err '未知命令，请使用 help。'; return 1;;
    esac
}
