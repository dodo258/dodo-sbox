# dodo258 节点管理

[![检查](https://github.com/dodo258/dodo-sbox/actions/workflows/check.yml/badge.svg)](https://github.com/dodo258/dodo-sbox/actions/workflows/check.yml) [![版本](https://img.shields.io/github/v/release/dodo258/dodo-sbox)](https://github.com/dodo258/dodo-sbox/releases/latest)

一个 Bash 脚本，一个 sing-box 服务。只部署 VLESS Reality、AnyTLS + TLS、Hysteria2；每个节点使用独立端口和凭据。

当前版本 `0.1.0`，首个公开测试版本，固定验证核心 `1.14.1`。已经在 Ubuntu 24.04 amd64 上完成与既有程序共存的实机测试；Linux arm64、其他系统版本仍需补充验证。已验证范围和剩余边界见 [测试记录](TEST_REPORT.md)。

## 使用

以 root 登录 Debian/Ubuntu 服务器后，下载发布包、校验 SHA256，再打开菜单：

```bash
work=$(mktemp -d) && cd "$work" && \
curl -fL --retry 2 -o dodo-sbox https://github.com/dodo258/dodo-sbox/releases/latest/download/dodo-sbox && \
curl -fL --retry 2 -o SHA256SUMS https://github.com/dodo258/dodo-sbox/releases/latest/download/SHA256SUMS && \
sha256sum -c SHA256SUMS && bash ./dodo-sbox
```

仅打开菜单不会部署节点。首次选择部署才安装缺失依赖、核心和独立服务；先阅读本页证书、防火墙和共存说明。

[查看 Ubuntu 服务器上的实际菜单](docs/menu-preview.txt)。主菜单展示当前服务、启用节点数、分流规则和续期状态；节点管理支持按序号选择节点。演示时测试节点已清理，因此显示“未部署”。

也可以从源码构建：

```sh
bash build.sh
```

将 `dist/dodo-sbox` 上传到 Debian/Ubuntu 服务器，以 root 运行：

```sh
bash ./dodo-sbox
```

选择“部署节点”，按提示填写协议、名称、连接地址、10000–50000 内的端口、Reality 握手域名或 TLS 证书域名。端口可回车随机，自动避开已有监听和本脚本记录的端口。

首次部署自动检测并安装必要依赖。之后运行 `dodo-sbox` 打开菜单。配置检查或服务启动失败时恢复原配置；进程中断留下的事务记录会在下次管理操作时恢复。

脚本不需要 Python，不修改系统 DNS、默认路由或原应用配置。安装使用独立目录和服务名；如果目标目录或命令属于其他应用，会拒绝覆盖。

## 原始节点链接

“节点管理”统一查看节点、原始链接和本地二维码：

- `vless://…`
- `anytls://…`
- `hysteria2://…`

二维码内容就是原始链接。不会上传到第三方转换服务，也不会生成、覆盖 Surge 或 Clash 的整份配置文件。可以把链接导入自己的外置配置。凭据重置、端口修改后需重新导入。

客户端必须支持所选协议；Surge 当前原生支持 AnyTLS、Hysteria2，不支持 VLESS Reality；Clash 需使用支持相应协议的 Mihomo 内核。分享链接不能为客户端添加它没有的协议能力。

## 免费证书与续期

使用 **Let's Encrypt** 和固定版本 `acme.sh`，不需要 Cloudflare API。

- 自动模式优先使用空闲的 TCP 80（HTTP-01）；80 被占用时尝试空闲 TCP 443（TLS-ALPN-01）。验证结束后释放端口。
- 若两个端口均被占用，选择“现有网站目录验证”。先核对验证文件实际可访问，再申请证书；不会停止 Nginx 或改写网站配置。
- 域名 A/AAAA 必须指向能完成验证的服务器，Cloudflare 应设为“仅 DNS”。多个地址都要可验证。
- 系统每天检查是否需要续期；只有证书满足续期条件才向 CA 续期。成功后检查域名、有效期和密钥匹配，切换证书并重启本脚本服务；失败保留原证书。重启可能短暂中断本脚本节点连接。
- 自动续期仍需保留域名解析及相应验证端口/网站目录。以后其他服务占用了验证端口，需要调整验证方式；不会替用户停掉该服务。
- 外部导入证书由原签发工具续期，新证书需再次导入。通配符证书不通过本脚本的 HTTP/TLS-ALPN 模式签发。

查看续期状态：

```sh
systemctl list-timers dodo-sbox-renew.timer
journalctl -u dodo-sbox-renew.service --no-pager
```

## 流媒体分流

默认不启用。添加平台规则后才对指定域名生效，其余流量仍由本机直连。

- **解锁 DNS**：填写解锁服务提供的 IP。普通公共 DNS 本身不提供地区解锁。
- **代理出口**：第一版支持 SOCKS5 出口，可带用户名和密码。只有选中平台的流量走该出口；出口需要支持 UDP 才能转发 QUIC。出口不可用时不会静默回落本机。
- 提供 Netflix、Disney+、YouTube 的基础域名组，也可完整查看、替换、自定义后缀；列表不是永远完整的解锁保证，需要按平台变化维护。
- 同一域名同时匹配 DNS 和代理规则时，代理规则优先。

**DNS 解锁边界：**客户端须把目标域名或 DNS 查询交给服务器。sing-box 1.14 的 `resolve` 不会把一个已经解析成 IP 的目标重新按 SNI 解析；ECH 或无法嗅探的流量同样不能保证域名规则命中。服务器不会改写用户的外置配置，也不会将“规则已保存”冒充“平台已解锁”。真实解锁地区还需要实际解锁 DNS/代理服务及客户端播放测试。

## BBR、防火墙与更新

首次节点部署可选择“内核支持时自动启用 BBR”或“保持现状”，默认共存模式保持现状。BBR 也可从主菜单单独设置；不换内核、不重启系统。系统 TCP BBR 与 Hysteria2 的用户态 QUIC 拥塞控制是两回事。

保留现有防火墙规则。若防火墙或云安全组拦截节点端口，需单独允许对应端口（Reality/AnyTLS 为 TCP，Hysteria2 为 UDP）。本脚本不会停防火墙或清空规则；“服务已监听”不等于“外部端口可达”。

脚本更新和核心更新分开，下载前后保留旧版本并验证校验值；核心只更新到当前脚本验证的版本。“检查并更新脚本”使用 [本仓库最新 Release](https://github.com/dodo258/dodo-sbox/releases/latest) 中命名为 `dodo-sbox` 的安装包，并验证 GitHub 提供的 SHA256 摘要。已经是相同发布包时不重复更新。也可使用指定本地/HTTPS 安装包加 SHA256 更新。

更新后的脚本需退出后重新运行。配置回滚和脚本回滚分别提供；首次部署前没有上一份配置可恢复。升级前建议备份 `/opt/dodo-sbox` 与 `/var/lib/dodo-sbox`，备份包含私钥和节点凭据，应只保存在受保护的位置。

## 目录与卸载

| 内容 | 路径 |
|---|---|
| 独立服务 | `dodo-sbox.service` |
| 管理脚本、核心、ACME | `/opt/dodo-sbox` |
| 节点状态、配置历史、证书 | `/var/lib/dodo-sbox` |
| 快捷命令 | `/usr/local/sbin/dodo-sbox` |
| 自动续期 | `dodo-sbox-renew.timer` |

卸载只删除本脚本的服务、目录、快捷命令和续期任务，保留共享系统依赖及其他应用。若本脚本修改过 BBR，只有当前值仍与脚本设置一致时才恢复原值。卸载前先导出所需节点资料。

## 验证与来源

详细实测记录见 `TEST_REPORT.md`。本地验证：

```sh
bash build.sh
bash -n dist/dodo-sbox
shellcheck -S warning -s bash dist/dodo-sbox
TEST_CORE=/absolute/path/to/sing-box TEST_OPENSSL=/absolute/path/to/openssl bash tests/local.sh
```

测试需要对应的 sing-box 二进制和 OpenSSL 3；Linux 集成测试只应在已授权、已备份的测试环境运行，需先阅读测试脚本。

本项目重新实现管理逻辑，参考 mack-a/v2ray-agent 的部署流程、233boy/sing-box 的节点操作、yonggekkk/sing-box-yg 的本地链接生成。协议实现来自 sing-box，证书来自 Let's Encrypt，ACME 客户端为 acme.sh。采用 AGPL-3.0，详见 `LICENSE`。

官方参考：

- https://sing-box.sagernet.org/configuration/
- https://github.com/acmesh-official/acme.sh
- https://letsencrypt.org/docs/challenge-types/
- https://manual.nssurge.com/policies/overview.html
