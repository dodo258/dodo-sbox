owned_root() {
    [[ -f $DODO_ROOT/.dodo-owned && -f $DATA/.dodo-owned ]] || { err '没有找到本脚本的安装标记。'; return 1; }
}
setup() {
    require_linux || return 1
    local path self=$1
    for path in "$DODO_ROOT" "$DATA"; do
        [[ ! -e $path || -f $path/.dodo-owned ]] || { err "$path 已存在且不属于本脚本。"; return 1; }
    done
    if [[ -e /etc/systemd/system/$SERVICE && ! -f $DODO_ROOT/.dodo-owned ]]; then err '服务名已被占用。'; return 1; fi
    if [[ -e /usr/local/sbin/dodo-sbox && ! -f $DODO_ROOT/.dodo-owned ]]; then err '快捷命令已被占用。'; return 1; fi
    ensure_dependencies || return 1
    if ! id dodo-sbox >/dev/null 2>&1; then
        useradd --system --no-create-home --home-dir "$DATA" --shell /usr/sbin/nologin dodo-sbox || return 1
    elif [[ ! -f $DODO_ROOT/.dodo-owned ]]; then err 'dodo-sbox 系统用户已存在，请先排查。'; return 1; fi
    install -d -m 755 "$DODO_ROOT" "$DODO_ROOT/core" || return 1
    install -d -m 750 -o root -g dodo-sbox "$DATA" "$DATA/generations" "$DATA/certs" || return 1
    touch "$DODO_ROOT/.dodo-owned" "$DATA/.dodo-owned" || return 1
    [[ -x $CORE ]] || core_download "$CORE" || return 1
    # Must be a bundled distribution, not the development loader.
    grep -q '^# DODO_SBOX_BUNDLE$' "$self" || { err '请先运行 bash build.sh，再使用 dist/dodo-sbox。'; return 1; }
    if [[ $(readlink -f "$self") != "$DODO_ROOT/manager.sh" ]]; then install -m 755 "$self" "$DODO_ROOT/manager.sh" || return 1; fi
    ln -sfn "$DODO_ROOT/manager.sh" /usr/local/sbin/dodo-sbox || return 1
    cat > "/etc/systemd/system/$SERVICE" <<UNIT
[Unit]
Description=dodo258 sing-box nodes
After=network-online.target
Wants=network-online.target
[Service]
User=dodo-sbox
Group=dodo-sbox
ExecStart=$CORE run -c $DATA/current/config.json
Restart=on-failure
RestartSec=3
UMask=0027
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
RestrictSUIDSGID=true
CapabilityBoundingSet=
LimitNOFILE=65536
[Install]
WantedBy=multi-user.target
UNIT
    systemctl daemon-reload || return 1
    msg '运行环境就绪。'
}
new_candidate() {
    local tmp
    tmp=$(mktemp) || return 1
    chmod 600 "$tmp"
    if [[ -f $STATE ]]; then cat "$STATE" > "$tmp"; else empty_state > "$tmp"; fi
    printf '%s\n' "$tmp"
}
service_healthy() {
    local candidate=$1 tries port kind output
    for ((tries=0; tries<15; tries++)); do
        if systemctl is-active --quiet "$SERVICE"; then
            local good=1
            while IFS=$'\t' read -r port kind; do
                [[ -n $port ]] || continue
                if [[ $kind == hysteria2 ]]; then output=$(ss -H -lun "sport = :$port"); else output=$(ss -H -ltn "sport = :$port"); fi
                [[ -n $output ]] || good=0
            done < <(jq -r '.nodes[]|select(.enabled)|[.port,.type]|@tsv' "$candidate")
            [[ $good == 1 ]] && return 0
        fi
        sleep 1
    done
    return 1
}
switch_generation() {
    local target=$1
    rm -f "$DATA/.current-next" || return 1
    ln -s "$target" "$DATA/.current-next" && mv -Tf "$DATA/.current-next" "$DATA/current"
}
recover_pending() {
    [[ -f $DATA/pending.json ]] || return 0
    local old active
    old=$(jq -er '.old // ""' "$DATA/pending.json") || return 1
    active=$(jq -r .active "$DATA/pending.json") || return 1
    if [[ -n $old ]]; then
        [[ $old == "$DATA/generations/"* && -f $old/state.json ]] || { err '回滚记录异常，需要人工检查。'; return 1; }
        switch_generation "$old" || return 1
        if [[ $active == 1 ]]; then systemctl restart "$SERVICE" && service_healthy "$STATE" || { err '恢复原配置后服务启动失败。'; return 1; }; else systemctl stop "$SERVICE" || return 1; fi
    else
        systemctl stop "$SERVICE" || return 1
        rm -f "$DATA/current"
    fi
    rm -f "$DATA/pending.json"
    msg '已恢复中断操作之前的配置。'
}
apply_state() (
    owned_root || exit 1
    local candidate=$1 gen old='' active=0 count switched=0
    validate_state "$candidate" || exit 1
    gen=$(mktemp -d "$DATA/generations/g.XXXXXXXX") || exit 1
    chmod 750 "$gen" && chgrp dodo-sbox "$gen" || exit 1
    if ! render_config "$candidate" > "$gen/config.json" || ! "$CORE" check -c "$gen/config.json"; then
        rm -rf "$gen"; err '核心校验失败，原节点未改动。'; exit 1
    fi
    install -m 600 "$candidate" "$gen/state.json" || exit 1
    chmod 640 "$gen/config.json" && chgrp dodo-sbox "$gen/config.json" || exit 1
    [[ ! -L $DATA/current ]] || old=$(readlink "$DATA/current")
    systemctl is-active --quiet "$SERVICE" && active=1
    jq -n --arg old "$old" --argjson active "$active" '{old:$old,active:$active}' > "$DATA/pending.json" || exit 1
    trap '[[ $switched == 0 ]] || recover_pending' EXIT
    trap 'exit 130' INT TERM HUP
    switched=1
    switch_generation "$gen" || exit 1
    count=$(jq '[.nodes[]|select(.enabled)]|length' "$candidate")
    if [[ $count == 0 ]]; then
        systemctl stop "$SERVICE" || exit 1
    else
        if ! systemctl restart "$SERVICE" || ! service_healthy "$candidate"; then err '新配置启动失败，恢复上一份配置。'; exit 1; fi
        systemctl enable "$SERVICE" >/dev/null || exit 1
    fi
    if [[ -n $old ]]; then ln -sfn "$old" "$DATA/previous" || exit 1; fi
    rm -f "$DATA/pending.json" || exit 1
    switched=0
    if [[ $count == 0 ]]; then msg '所有节点已停用。'; else msg '配置已应用，服务和监听正常；外部客户端连通仍需验证。'; fi
)
rollback_config() {
    owned_root || return 1
    [[ -f $DATA/previous/state.json ]] || { err '没有可回滚的配置。'; return 1; }
    apply_state "$DATA/previous/state.json"
}
update_core() {
    owned_root || return 1
    local tmp old_active=0
    if [[ $("$CORE" version | head -n 1) == "sing-box version $CORE_VERSION" ]]; then msg "已是本脚本验证的核心版本 $CORE_VERSION。"; return 0; fi
    tmp=$(mktemp "$DODO_ROOT/core/.candidate.XXXXXX") || return 1
    if ! core_download "$tmp" || ! "$tmp" check -c "$DATA/current/config.json"; then rm -f "$tmp"; return 1; fi
    systemctl is-active --quiet "$SERVICE" && old_active=1
    cp -p "$CORE" "$CORE.previous" && mv -f "$tmp" "$CORE" || return 1
    if [[ $old_active == 0 ]]; then msg '核心已更新；服务保持停止状态。'; return 0; fi
    if systemctl restart "$SERVICE" && service_healthy "$STATE"; then msg "核心已更新到 $CORE_VERSION。"; return 0; fi
    mv -f "$CORE.previous" "$CORE"
    systemctl restart "$SERVICE"
    err '新核心启动失败，已恢复原核心。'; return 1
}
update_script() {
    owned_root || return 1
    local source=$1 expected=$2 tmp
    [[ $expected =~ ^[a-f0-9]{64}$ ]] || { err '需要发布方提供的 SHA256。'; return 1; }
    tmp=$(mktemp "$DODO_ROOT/.manager.XXXXXX") || return 1
    case $source in https://*) fetch "$source" "$tmp" || { rm -f "$tmp"; return 1; };; /*) cp "$source" "$tmp" || return 1;; *) err '请输入 HTTPS 地址或本地绝对路径。'; rm -f "$tmp"; return 1;; esac
    if [[ $(sha256 "$tmp") != "$expected" ]] || ! bash -n "$tmp" || ! grep -q '^# DODO_SBOX_BUNDLE$' "$tmp"; then
        err '脚本校验失败，原脚本未改动。'; rm -f "$tmp"; return 1
    fi
    cp -p "$DODO_ROOT/manager.sh" "$DODO_ROOT/manager.previous.sh" && chmod 755 "$tmp" && mv -f "$tmp" "$DODO_ROOT/manager.sh" || return 1
    msg '脚本更新完成，请退出后重新运行 dodo-sbox。核心和节点配置未自动升级。'
}
bbr_status() {
    sysctl net.ipv4.tcp_congestion_control net.ipv4.tcp_available_congestion_control net.core.default_qdisc
}
bbr_enable() {
    owned_root || return 1
    local ctl=/etc/sysctl.d/90-dodo-sbox-bbr.conf
    [[ ! -e $ctl || -f $DATA/bbr-before.json ]] || { err "$ctl 已存在，不覆盖。"; return 1; }
    modprobe tcp_bbr 2>/dev/null || true
    sysctl -n net.ipv4.tcp_available_congestion_control | grep -qw bbr || { err '当前内核不支持 BBR，跳过；不会换内核或重启。'; return 1; }
    if [[ ! -f $DATA/bbr-before.json ]]; then
        jq -n --arg cc "$(sysctl -n net.ipv4.tcp_congestion_control)" --arg q "$(sysctl -n net.core.default_qdisc)" '{cc:$cc,qdisc:$q}' > "$DATA/bbr-before.json" || return 1
    fi
    printf 'net.core.default_qdisc = fq\nnet.ipv4.tcp_congestion_control = bbr\n' > "$ctl" || return 1
    sysctl -p "$ctl" && bbr_status
}
bbr_restore() {
    [[ -f $DATA/bbr-before.json ]] || return 0
    if [[ $(sysctl -n net.ipv4.tcp_congestion_control) == bbr && $(sysctl -n net.core.default_qdisc) == fq ]]; then
        sysctl -w "net.ipv4.tcp_congestion_control=$(jq -r .cc "$DATA/bbr-before.json")" "net.core.default_qdisc=$(jq -r .qdisc "$DATA/bbr-before.json")" || return 1
    else msg 'BBR 当前值已被其他操作修改，保留当前值。'; fi
    rm -f /etc/sysctl.d/90-dodo-sbox-bbr.conf "$DATA/bbr-before.json"
}
show_status() {
    if [[ -f $STATE ]]; then jq -r '.nodes[]|[.id,.name,.type,(.port|tostring),(if .enabled then "启用" else "停用" end)]|@tsv' "$STATE"; else msg '尚无节点。'; fi
    systemctl --no-pager --full status "$SERVICE" || true
    msg '防火墙/安全组提示：只需允许节点对应端口（Reality/AnyTLS TCP，Hysteria2 UDP）。本脚本不关闭或清空已有防火墙。'
}
uninstall() {
    owned_root || return 1
    msg "删除本脚本服务、续期任务、$DODO_ROOT、$DATA 和快捷命令；节点凭据与本脚本证书会删除。系统依赖、其他服务和防火墙保留。"
    yesno '已导出需要的节点资料，确认卸载' || return 0
    systemctl disable --now "$SERVICE" dodo-sbox-renew.timer 2>/dev/null || true
    if systemctl is-active --quiet "$SERVICE" || systemctl is-active --quiet dodo-sbox-renew.service; then err '服务仍在运行，停止卸载。'; return 1; fi
    bbr_restore || return 1
    rm -f "/etc/systemd/system/$SERVICE" /etc/systemd/system/dodo-sbox-renew.service /etc/systemd/system/dodo-sbox-renew.timer
    [[ $(readlink /usr/local/sbin/dodo-sbox) != "$DODO_ROOT/manager.sh" ]] || rm -f /usr/local/sbin/dodo-sbox
    rm -rf "$DODO_ROOT" "$DATA"
    userdel dodo-sbox || true
    systemctl daemon-reload
    msg '卸载完成。'
}
update_latest() {
    owned_root || return 1
    local tmp url digest
    tmp=$(mktemp) || return 1
    if ! fetch https://api.github.com/repos/dodo258/dodo-sbox/releases/latest "$tmp"; then rm -f "$tmp"; return 1; fi
    url=$(jq -r '.assets[]?|select(.name=="dodo-sbox")|.browser_download_url' "$tmp")
    digest=$(jq -r '.assets[]?|select(.name=="dodo-sbox")|.digest // empty' "$tmp")
    rm -f "$tmp"
    if [[ -z $url ]]; then msg '发布仓库暂时没有独立脚本安装包，保留当前版本。'; return 0; fi
    [[ $url == https://github.com/dodo258/dodo-sbox/releases/download/*/dodo-sbox && $digest == sha256:* ]] || { err '发布信息不符合预期。'; return 1; }
    if [[ $(sha256 "$DODO_ROOT/manager.sh") == "${digest#sha256:}" ]]; then msg '已是最新发布的脚本。'; return 0; fi
    update_script "$url" "${digest#sha256:}"
}
