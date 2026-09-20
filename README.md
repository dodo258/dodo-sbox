# dodo258 节点管理

[![检查](https://github.com/dodo258/dodo-sbox/actions/workflows/check.yml/badge.svg)](https://github.com/dodo258/dodo-sbox/actions/workflows/check.yml) [![版本](https://img.shields.io/github/v/release/dodo258/dodo-sbox)](https://github.com/dodo258/dodo-sbox/releases/latest)

简约的 **Shell 一键部署和管理脚本**，基于 sing-box，只保留 VLESS Reality、AnyTLS、Hysteria2。一个服务管理多个节点，每个节点使用独立端口和凭据。

## 一键安装

使用 **root** 登录 Debian / Ubuntu 服务器，复制下面整行命令运行：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/dodo258/dodo-sbox/main/install.sh)
```

没有 curl、但有 wget 时：

```bash
bash <(wget -qO- https://raw.githubusercontent.com/dodo258/dodo-sbox/main/install.sh)
```

进入菜单 → 输入 **1** 部署节点 → 选择协议 → 按提示填写。可回车使用默认值，输入 **0** 返回。脚本会下载并校验发布包，首次部署自动安装缺失依赖。

安装后，再次打开管理菜单只需：

```bash
dodo-sbox
```

[下载安装包](https://github.com/dodo258/dodo-sbox/releases/latest) · [查看菜单](docs/menu-preview.txt)

## 功能与特点

- **三种协议**：VLESS Reality、AnyTLS + TLS、Hysteria2。
- **Reality 双选项**：携程 `www.ctrip.com` / 西瓜视频 `www.ixigua.com`，部署前自动检查目标可用性。
- **节点管理**：按序号查看节点、启停、改名、改端口、重置凭据、删除；Reality 目标可直接切换，无需重建节点。
- **原始链接和二维码**：导出 `vless://`、`anytls://`、`hysteria2://`；二维码本地生成，方便配合自己的客户端配置使用。
- **免费证书**：部署时申请 Let's Encrypt，自动检查续期，无需 Cloudflare API。
- **证书管理**：首页菜单 **8** 查看域名、到期时间、续期任务状态，也可立即检查续期。
- **流媒体分流**：选定平台使用解锁 DNS 或 SOCKS5 出口，其他访问保持服务器本机出口；新增规则自动检查两种方式的域名重叠。
- **端口选择**：10000–50000，可指定或随机，避开已占用端口。
- **端口自动放行**：自动配置正在使用的 UFW / firewalld，按协议只开放节点需要的 TCP 或 UDP；改端口、停用、删除时同步清理脚本自己的规则。
- **更新与回滚**：一键更新脚本和已验证核心，可开启每日自动更新；核心启动失败恢复旧核心。
- **独立管理**：自动补齐依赖、BBR 设置、日志、重启、卸载；保留其他应用的配置和防火墙规则。

## 快捷管理

| 命令 | 功能 |
|---|---|
| `dodo-sbox` | 打开主菜单 |
| `dodo-sbox add` | 部署新节点 |
| `dodo-sbox nodes` | 节点管理、原始链接、二维码 |
| `dodo-sbox routing` | 流媒体分流 |
| `dodo-sbox certs` | 证书管理 |
| `dodo-sbox certs status` | 查看证书及续期状态 |
| `dodo-sbox renew` | 立即检查续期，未到续期时间不强制重签 |
| `dodo-sbox status` | 查看运行状态 |
| `dodo-sbox logs` | 查看最近日志 |
| `dodo-sbox restart` | 重启本脚本节点 |
| `dodo-sbox firewall` | 为已有节点补齐、重新同步端口规则 |
| `dodo-sbox update` | 更新脚本和已验证核心 |
| `dodo-sbox auto-update on` | 开启每日自动更新 |
| `dodo-sbox auto-update off` | 关闭每日自动更新 |
| `dodo-sbox auto-update status` | 查看自动更新状态 |
| `dodo-sbox uninstall` | 确认后卸载 |

## 自动更新怎么用

菜单 **5 → 开启每日自动更新**，或者运行 `dodo-sbox auto-update on`。默认关闭，开启后每天按服务器时间 **04:00–04:30** 检查；错过后会补做。

**协议实现随 sing-box 核心一起更新，无需分别更新三个协议。** 脚本先更新到本项目最新发布版，再升级到该版本验证过的核心。不会直接追随未经本项目验证的上游新版本。配置校验失败不替换核心，核心启动失败自动恢复旧核心；联合更新失败还会恢复本次替换前的管理脚本。

核心更新或证书续期成功后可能短暂重启本脚本节点。证书自动续期与脚本自动更新分别运行，关闭脚本自动更新不影响续期。

## 必要说明

- **系统**：Debian / Ubuntu、systemd、amd64 / arm64；已实测 Ubuntu 24.04 amd64，其他环境的验证范围见 [测试记录](TEST_REPORT.md)。
- **证书**：AnyTLS / Hysteria2 需域名解析到服务器；Cloudflare 设为“仅 DNS”。申请和续期需空闲 TCP 80 或 443；均被占用时可选择现有网站目录验证。导入的外部证书由原工具续期。
- **Reality**：无需拥有携程或西瓜视频域名，也无需为它们申请证书。目标可用性取决于服务器网络和对方网站，部署时会验证 TLS 1.3、HTTP/2 及证书；升级不会修改已有节点的目标域名。
- **端口**：本机 UFW / firewalld 自动放行节点端口，申请和续期证书时临时放行对应 TCP 80 / 443，结束后清理本次规则。不会关闭防火墙、修改默认策略或删除原有规则。若云厂商另设安全组，仍需在控制台放行；自定义 nftables / iptables 规则不自动接管，会明确提示。
- **分流**：普通公共 DNS 不等于地区解锁。DNS 分流需要客户端把目标域名或 DNS 查询交给服务器；已解析成 IP 的连接不能保证生效。实际解锁取决于服务提供方及平台。
- **BBR**：当前内核支持时可开启，不换内核、不重启；属于主机级设置，共存环境默认保持现状。
- **客户端**：需支持对应协议。原始链接用于导入你的外置配置，不生成整份 Surge / Clash 配置。

[详细说明](docs/ADVANCED.md) · [更新记录](CHANGELOG.md) · [问题反馈](https://github.com/dodo258/dodo-sbox/issues)

参考 [233boy/sing-box](https://github.com/233boy/sing-box)、[mack-a/v2ray-agent](https://github.com/mack-a/v2ray-agent)、[yonggekkk/sing-box-yg](https://github.com/yonggekkk/sing-box-yg) 的节点管理、证书生命周期和分流实现，具体取舍见 [源码对照记录](docs/SOURCE_REVIEW.md)。协议核心来自 [sing-box](https://github.com/SagerNet/sing-box)，证书签发使用 [acme.sh](https://github.com/acmesh-official/acme.sh) 与 Let's Encrypt。许可：[AGPL-3.0](LICENSE)。
