# All mutation menu paths execute under with_lock.
node_add() {
    local self=$1 type name host port sni bbr=keep mode=none email='' webroot='' cert='' key='' candidate node id uuid private public short password pair tmp
    msg $'部署节点（任一步输入 0 返回）\n1. VLESS Reality\n2. AnyTLS + TLS\n3. Hysteria2'
    ask '协议' 1 || return 0
    case $REPLY in 1) type=vless;; 2) type=anytls;; 3) type=hysteria2;; *) err '请选择 1–3。'; return 1;; esac
    ask '节点名称' "$type" || return 0; name=$REPLY
    ask '客户端连接的服务器 IP 或域名（域名需 DNS only 灰云）' || return 0; host=$REPLY
    valid_host "$host" || { err '地址不合法。'; return 1; }
    ask '端口：10000–50000，回车随机' random || return 0; port=$REPLY
    if [[ $port != random ]]; then valid_port "$port" || { err '端口必须在 10000–50000。'; return 1; }; fi
    if [[ $type == vless ]]; then
        ask 'Reality 握手目标域名' www.microsoft.com || return 0; sni=$REPLY
    else
        ask '证书域名' "$host" || return 0; sni=$REPLY
        msg 'Lets Encrypt 免费证书：1.自动验证（使用空闲 80 或 443） 2.现有网站目录验证（网站保持运行） 3.导入已有证书'
        ask '证书方式' 1 || return 0
        case $REPLY in
          1) mode=auto;; 2) mode=webroot; ask '现有网站根目录绝对路径' || return 0; webroot=$REPLY;;
          3) mode=import
             ask '完整证书链绝对路径' || return 0; cert=$REPLY
             ask '私钥绝对路径' || return 0; key=$REPLY;;
          *) err '证书方式无效。'; return 1;;
        esac
        if [[ $mode != import ]]; then ask '证书联系邮箱（可留空）' || return 0; email=$REPLY; [[ -z $email || $email == *@*.* ]] || { err '邮箱格式不正确。'; return 1; }; fi
    fi
    valid_domain "$sni" || { err '域名不合法，请使用 ASCII/Punycode 域名。'; return 1; }
    if [[ ! -f $STATE ]]; then
        msg 'BBR：1.内核支持时自动启用（主机级 TCP 设置） 2.保持现状（与现有程序共存时选择）'
        ask 'BBR 设置' 2 || return 0
        case $REPLY in 1) bbr=enable;; 2) bbr=keep;; *) err '无效选项。'; return 1;; esac
    fi
    msg "部署：$name / $type / $host:$port / $sni"
    [[ $mode == none || $mode == import ]] || msg '自动申请使用 Lets Encrypt；继续表示同意该机构的服务条款。'
    yesno '开始安装缺失依赖、申请证书并部署' || return 0
    [[ -f $DODO_ROOT/.dodo-owned ]] || setup "$self" || return 1
    ensure_dependencies || return 1
    if [[ $port == random ]]; then port=$(choose_port) || return 1; else port_free "$port" || { err '端口被占用，原服务未改动。'; return 1; }; fi
    id=$(random_hex 8) || return 1
    if [[ $type == vless ]]; then
        local handshake_file
        handshake_file=$(mktemp) || return 1
        msg '检查 Reality 目标 TLS 1.3 握手…'
        timeout 12 openssl s_client -connect "$sni:443" -servername "$sni" -tls1_3 </dev/null > "$handshake_file" 2>&1
        local handshake_rc=$?
        if [[ $handshake_rc != 0 ]] || ! grep -q 'TLSv1.3' "$handshake_file"; then rm -f "$handshake_file"; err '目标 TLS 1.3 握手失败，请换域名。'; return 1; fi
        rm -f "$handshake_file"
        pair=$("$CORE" generate reality-keypair) || return 1
        private=$(printf '%s\n' "$pair" | awk '/PrivateKey:/{print $2}')
        public=$(printf '%s\n' "$pair" | awk '/PublicKey:/{print $2}')
        uuid=$("$CORE" generate uuid) && short=$(random_hex 8) || return 1
        node=$(jq -n --arg id "$id" --arg name "$name" --arg host "$host" --arg sni "$sni" --argjson port "$port" --arg uuid "$uuid" --arg private "$private" --arg public "$public" --arg short "$short" '{id:$id,name:$name,host:$host,sni:$sni,port:$port,type:"vless",enabled:true,uuid:$uuid,private_key:$private,public_key:$public,short_id:$short}') || return 1
    else
        if [[ $mode == import ]]; then
            cert_valid "$cert" "$key" "$sni" || { err '证书与域名/私钥不匹配，或一天内到期。'; return 1; }
            tmp=$(mktemp -d) || return 1
            cp "$cert" "$tmp/fullchain.pem" && cp "$key" "$tmp/key.pem" && activate_cert "$sni" "$tmp"
            local cert_rc=$?; rm -rf "$tmp"; [[ $cert_rc == 0 ]] || return 1
            msg '导入的外部证书需由原签发工具续期，再导入新证书。'
        else issue_certificate "$sni" "$mode" "$email" "$webroot" || return 1; fi
        password=$(random_hex 24) || return 1
        node=$(jq -n --arg id "$id" --arg name "$name" --arg host "$host" --arg sni "$sni" --arg type "$type" --argjson port "$port" --arg password "$password" --arg cert "$DATA/certs/$sni/active" '{id:$id,name:$name,host:$host,sni:$sni,port:$port,type:$type,enabled:true,password:$password,cert_dir:$cert}') || return 1
    fi
    if [[ $(sysctl -n net.ipv6.conf.all.disable_ipv6 2>/dev/null) == 1 ]]; then
        node=$(printf '%s' "$node" | jq '.listen="0.0.0.0"') || return 1
    fi
    candidate=$(new_candidate) || return 1
    tmp=$(mktemp) || return 1
    jq --argjson n "$node" '.nodes += [$n]' "$candidate" > "$tmp" && mv "$tmp" "$candidate" || return 1
    if apply_state "$candidate"; then
        rm -f "$candidate"
        if [[ $bbr == enable ]]; then
            if [[ $(sysctl -n net.ipv4.tcp_congestion_control) == bbr ]]; then msg 'BBR 已开启。'; else bbr_enable || msg '节点已部署；BBR 未启用，原因见上方。'; fi
        fi
        local transport=TCP
        [[ $type != hysteria2 ]] || transport=UDP
        msg "节点端口：${port}/${transport}；如仍无法连接，请在服务商控制台的云安全组允许 ${transport} ${port}。"
        printf '%s' "$node" | share_uri
        msg '完整信息和二维码：主菜单 → 节点管理。'
        return 0
    fi
    rm -f "$candidate"; return 1
}
export_node() {
    local id=$1 format=$2 node
    node=$(node_json "$STATE" "$id") || { err '节点不存在。'; return 1; }
    case $format in
      uri) printf '%s' "$node" | share_uri;;
      qr) printf '%s' "$node" | share_uri | tr -d '\n' | qrencode -t ANSIUTF8;;
      details)
        printf '%s' "$node" | jq 'del(.private_key,.password,.uuid,.short_id,.public_key)'
        if [[ $(printf '%s' "$node" | jq -r .type) != vless ]]; then openssl x509 -in "$(printf '%s' "$node" | jq -r .cert_dir)/fullchain.pem" -noout -subject -enddate; fi;;
      *) return 1;;
    esac
}
node_change() {
    local id=$1 action=$2 value=${3:-} candidate tmp type uuid node
    candidate=$(new_candidate) || return 1
    node=$(node_json "$candidate" "$id") || { rm -f "$candidate"; err '节点不存在。'; return 1; }
    tmp=$(mktemp) || return 1
    case $action in
      toggle)
        if [[ $(printf '%s' "$node" | jq -r .enabled) == false ]]; then
            port_free "$(printf '%s' "$node" | jq -r .port)" "$id" || { rm -f "$tmp" "$candidate"; err '端口被占用，无法启用。'; return 1; }
        fi
        jq --arg id "$id" '(.nodes[]|select(.id==$id)|.enabled) |= not' "$candidate" > "$tmp";;
      delete) jq --arg id "$id" '.nodes |= map(select(.id!=$id))' "$candidate" > "$tmp";;
      port)
        port_free "$value" "$id" || { rm -f "$tmp" "$candidate"; err '端口无效或被占用。'; return 1; }
        jq --arg id "$id" --argjson p "$value" '(.nodes[]|select(.id==$id)|.port)=$p' "$candidate" > "$tmp";;
      name) jq --arg id "$id" --arg name "$value" '(.nodes[]|select(.id==$id)|.name)=$name' "$candidate" > "$tmp";;
      rotate)
        type=$(printf '%s' "$node" | jq -r .type)
        if [[ $type == vless ]]; then
            uuid=$("$CORE" generate uuid) || return 1
            jq --arg id "$id" --arg v "$uuid" '(.nodes[]|select(.id==$id)|.uuid)=$v' "$candidate" > "$tmp"
        else
            value=$(random_hex 24) || return 1
            jq --arg id "$id" --arg v "$value" '(.nodes[]|select(.id==$id)|.password)=$v' "$candidate" > "$tmp"
        fi;;
      *) rm -f "$tmp" "$candidate"; return 1;;
    esac
    local rc=1
    if mv "$tmp" "$candidate" && apply_state "$candidate"; then rc=0; fi
    rm -f "$candidate" "$tmp"
    return "$rc"
}
node_menu() {
    [[ -f $STATE ]] || { msg '尚无节点。'; return 0; }
    local count index=0 id name type port status
    count=$(jq '.nodes|length' "$STATE") || return 1
    (( count > 0 )) || { msg '尚无节点，请先部署。'; return 0; }
    msg $'\n已部署节点：'
    while IFS=$'\t' read -r name type port status; do
        index=$((index+1))
        printf '  %s. %s | %s | 端口 %s | %s\n' "$index" "$name" "$type" "$port" "$status"
    done < <(jq -r '.nodes[]|[.name,.type,(.port|tostring),(if .enabled then "启用" else "停用" end)]|@tsv' "$STATE")
    ask '节点序号（也可输入完整 ID；0 返回）' || return 0
    id=$REPLY
    if [[ $REPLY =~ ^[1-9][0-9]{0,5}$ ]] && (( REPLY <= count )); then
        id=$(jq -r --argjson i "$((REPLY-1))" '.nodes[$i].id' "$STATE") || return 1
    fi
    node_json "$STATE" "$id" >/dev/null || { err '节点不存在。'; return 1; }
    msg $'1.详情 2.原始分享链接 3.二维码\n4.启用/停用 5.修改端口 6.重置凭据 7.修改名称 8.删除'
    ask '操作' 1 || return 0
    case $REPLY in
      1) export_node "$id" details;; 2) export_node "$id" uri;; 3) export_node "$id" qr;;
      4) with_lock node_change "$id" toggle;;
      5) ask '新端口' || return 0; with_lock node_change "$id" port "$REPLY";;
      6) yesno '旧凭据会失效，确认重置' && with_lock node_change "$id" rotate;;
      7) ask '新名称' || return 0; with_lock node_change "$id" name "$REPLY";;
      8) yesno '确认删除此节点' && with_lock node_change "$id" delete;;
      *) err '无效选项。';;
    esac
}
