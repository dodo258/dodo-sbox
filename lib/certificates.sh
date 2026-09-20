ensure_acme() {
    [[ -x $ACME ]] && return 0
    local tmp
    tmp=$(mktemp -d) || return 1
    if ! fetch https://codeload.github.com/acmesh-official/acme.sh/tar.gz/refs/tags/3.1.5 "$tmp/acme.tar.gz" ||
       [[ $(sha256 "$tmp/acme.tar.gz") != a5e5b61bf98464fd7bf9925951b97e9ed8c127e041d3b8e9703d2360cd6e19b6 ]] ||
       ! tar -xzf "$tmp/acme.tar.gz" -C "$tmp"; then rm -rf "$tmp"; err 'ACME 下载或校验失败。'; return 1; fi
    install -d -m 700 "$DODO_ROOT/acme" "$DODO_ROOT/acme-accounts" || return 1
    cp -R "$tmp/acme.sh-3.1.5/." "$DODO_ROOT/acme/" && chmod 700 "$ACME"
    local rc=$?
    rm -rf "$tmp"
    return "$rc"
}
cert_valid() {
    local cert=$1 key=$2 domain=$3 a b
    openssl x509 -in "$cert" -noout -checkend 86400 >/dev/null 2>&1 &&
        openssl verify -partial_chain -trusted "$cert" -verify_hostname "$domain" "$cert" >/dev/null 2>&1 || return 1
    a=$(openssl x509 -in "$cert" -pubkey -noout 2>/dev/null) || return 1
    b=$(openssl pkey -in "$key" -pubout 2>/dev/null) || return 1
    [[ -n $a && $a == "$b" ]]
}
activate_cert() {
    local domain=$1 source=$2 dir gen old='' active=0
    valid_domain "$domain" && cert_valid "$source/fullchain.pem" "$source/key.pem" "$domain" || { err '证书校验失败。'; return 1; }
    dir=$DATA/certs/$domain
    install -d -m 750 -o root -g dodo-sbox "$dir" || return 1
    if [[ -f $dir/active/fullchain.pem ]] && cmp -s "$source/fullchain.pem" "$dir/active/fullchain.pem"; then return 0; fi
    gen=$(mktemp -d "$dir/c.XXXXXXXX") || return 1
    chmod 750 "$gen" && chgrp dodo-sbox "$gen" &&
        install -m 640 -g dodo-sbox "$source/fullchain.pem" "$gen/fullchain.pem" &&
        install -m 640 -g dodo-sbox "$source/key.pem" "$gen/key.pem" || return 1
    [[ ! -L $dir/active ]] || old=$(readlink "$dir/active")
    ln -s "$gen" "$dir/.next" && mv -Tf "$dir/.next" "$dir/active" || return 1
    systemctl is-active --quiet "$SERVICE" && active=1
    if [[ ! -f $STATE ]] || { "$CORE" check -c "$DATA/current/config.json" && { [[ $active == 0 ]] || { systemctl restart "$SERVICE" && service_healthy "$STATE"; }; }; }; then return 0; fi
    if [[ -n $old ]]; then
        ln -s "$old" "$dir/.next" && mv -Tf "$dir/.next" "$dir/active"
        [[ $active == 0 ]] || systemctl restart "$SERVICE"
    else rm -f "$dir/active"; fi
    err '证书应用失败，已恢复原证书。'; return 1
}
acme_call() {
    local domain=$1; shift
    "$ACME" --home "$DODO_ROOT/acme" --config-home "$DODO_ROOT/acme-accounts/$domain" "$@"
}
copy_acme_cert() {
    local domain=$1 tmp rc=0
    tmp=$DODO_ROOT/acme-accounts/$domain/export
    install -d -m 700 "$tmp" || return 1
    acme_call "$domain" --install-cert -d "$domain" --ecc --key-file "$tmp/key.pem" --fullchain-file "$tmp/fullchain.pem" > "$DODO_ROOT/acme-accounts/$domain/install.log" 2>&1 &&
        activate_cert "$domain" "$tmp" || rc=1
    return "$rc"
}
issue_certificate() (
    local domain=$1 mode=$2 email=${3:-} webroot=${4:-} rc=0 probe
    valid_domain "$domain" || exit 1
    if [[ -f $DATA/certs/$domain/active/fullchain.pem ]] && cert_valid "$DATA/certs/$domain/active/fullchain.pem" "$DATA/certs/$domain/active/key.pem" "$domain"; then
        msg '复用有效证书。'; exit 0
    fi
    if [[ $mode == auto ]]; then
        if [[ -z $(ss -H -ltn 'sport = :80') ]]; then mode=http
        elif [[ -z $(ss -H -ltn 'sport = :443') ]]; then mode=alpn
        else err '80 和 443 已被占用，请选择现有网站目录验证。'; exit 1; fi
        msg "自动选择证书验证方式：$mode"
    fi
    if [[ $mode == alpn ]]; then
        [[ -z $(ss -H -ltn 'sport = :443') ]] || { err '443 端口被占用，原服务未改动。'; exit 1; }
    elif [[ $mode == http ]]; then
        [[ -z $(ss -H -ltn 'sport = :80') ]] || { err '80 端口已占用，请使用现有网站目录验证，不会停止已有服务。'; exit 1; }
    elif [[ $mode == webroot ]]; then
        [[ $webroot == /* && -d $webroot ]] || { err '网站目录必须是存在的绝对路径。'; exit 1; }
        probe=$(random_hex 16) || exit 1
        [[ -d $webroot/.well-known ]] || mkdir -m 755 "$webroot/.well-known" || exit 1
        [[ -d $webroot/.well-known/acme-challenge ]] || mkdir -m 755 "$webroot/.well-known/acme-challenge" || exit 1
        # Validation tokens are public; other web files are never changed.
        # Existing directory permissions remain unchanged.
        printf '%s' "$probe" > "$webroot/.well-known/acme-challenge/dodo-$probe" || exit 1
        chmod 644 "$webroot/.well-known/acme-challenge/dodo-$probe"
        local response
        response=$(curl -fsSL --connect-timeout 10 --max-time 20 "http://$domain/.well-known/acme-challenge/dodo-$probe") || rc=1
        rm -f "$webroot/.well-known/acme-challenge/dodo-$probe"
        [[ $rc == 0 && $response == "$probe" ]] || { err '验证文件外网访问检查失败。没有修改网站配置，请检查域名解析/网站目录。'; exit 1; }
    else err '未知证书验证方式。'; exit 1; fi
    ensure_acme || exit 1
    install -d -m 700 "$DODO_ROOT/acme-accounts/$domain" || exit 1
    if [[ $mode == http || $mode == alpn ]]; then
        command -v socat >/dev/null || DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=l apt-get install -y --no-install-recommends socat || exit 1
        local challenge=--standalone
        [[ $mode != alpn ]] || challenge=--alpn
        acme_call "$domain" --issue "$challenge" -d "$domain" --keylength ec-256 --server letsencrypt --accountemail "$email" > "$DODO_ROOT/acme-accounts/$domain/issue.log" 2>&1 || rc=$?
    else
        acme_call "$domain" --issue --webroot "$webroot" -d "$domain" --keylength ec-256 --server letsencrypt --accountemail "$email" > "$DODO_ROOT/acme-accounts/$domain/issue.log" 2>&1 || rc=$?
    fi
    if [[ $rc != 0 && $rc != 2 ]]; then err "证书申请失败。日志：$DODO_ROOT/acme-accounts/$domain/issue.log（分享前请检查敏感信息）。"; exit 1; fi
    copy_acme_cert "$domain" && install_renew_timer
)
install_renew_timer() {
    cat > /etc/systemd/system/dodo-sbox-renew.service <<UNIT
[Unit]
Description=dodo258 certificate renewal
[Service]
Type=oneshot
UMask=0077
ExecStart=/usr/local/sbin/dodo-sbox renew
UNIT
    cat > /etc/systemd/system/dodo-sbox-renew.timer <<'UNIT'
[Unit]
Description=dodo258 daily certificate check
[Timer]
OnCalendar=daily
RandomizedDelaySec=3600
Persistent=true
[Install]
WantedBy=timers.target
UNIT
    systemctl daemon-reload && systemctl enable --now dodo-sbox-renew.timer
}
renew_certificates() {
    owned_root || return 1
    [[ -f $STATE ]] || return 0
    local domain rc failures=0
    while IFS= read -r domain; do
        [[ -d $DODO_ROOT/acme-accounts/$domain ]] || continue
        rc=0
        acme_call "$domain" --renew -d "$domain" --ecc > "$DODO_ROOT/acme-accounts/$domain/renew.log" 2>&1 || rc=$?
        if [[ $rc == 0 || $rc == 2 ]]; then
            copy_acme_cert "$domain" || failures=$((failures+1))
        else err "证书续期失败：$domain；保留原证书。"; failures=$((failures+1)); fi
    done < <(jq -r '.nodes[]|select(.type!="vless")|.sni' "$STATE" | sort -u)
    [[ $failures == 0 ]]
}
