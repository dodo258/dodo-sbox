# 详细说明

[返回使用说明](../README.md)

## 安装与备份位置

| 内容 | 路径 |
|---|---|
| 管理脚本、核心、ACME 客户端和账户 | `/opt/dodo-sbox` |
| 节点、配置历史、证书 | `/var/lib/dodo-sbox` |
| 快捷命令 | `/usr/local/sbin/dodo-sbox` |
| 节点服务 | `dodo-sbox.service` |
| 证书续期任务 | `dodo-sbox-renew.timer` |
| 可选每日更新任务 | `dodo-sbox-update.timer` |

备份前两项目录即可保留运行数据。备份包含私钥、节点密码和 ACME 账户信息，请保存在受保护的位置，不要提交到 GitHub 或公开分享。

配置通过 sing-box 检查后按版本目录切换；启动失败恢复上一份配置。进程中断留下的事务记录会在下次管理操作时尝试恢复。断电级恢复尚未全面验证。

## 证书签发和续期

自动验证优先使用空闲 TCP 80 的 HTTP-01；80 被占用时使用空闲 TCP 443 的 TLS-ALPN-01，验证后释放端口。两者都被占用时选择现有网站根目录，先验证文件可通过域名访问，再申请证书；不停止或改写现有网站。

所有 A / AAAA 地址都必须能完成 CA 验证。保持域名解析、验证端口或网站目录可用；如果其他服务后来占用了验证端口，需要调整验证方式。

每天检查续期条件；新证书先核对域名、有效期和私钥匹配，成功后切换并重启本脚本服务，失败保留原证书。外部导入的证书由原工具续期，需要重新导入。HTTP / TLS-ALPN 模式不签发通配符证书。

```bash
systemctl list-timers dodo-sbox-renew.timer
journalctl -u dodo-sbox-renew.service -n 50 --no-pager
```

## 更新策略

`dodo-sbox update` 先下载本仓库最新 Release 的完整管理脚本，验证 GitHub 提供的 SHA256，再由新脚本更新其验证过的核心版本。不是直接安装 sing-box 上游最新版本；新的核心需要本项目验证并发布后才会被自动更新采用。

核心在替换前验证现有配置；运行中的服务升级后检查服务状态和监听端口，失败恢复旧核心。联合更新失败也恢复本次替换前的管理脚本。此检查不能替代客户端连通性及流媒体播放测试。

自动更新默认关闭；开启后每日按服务器时间 04:00–04:30 检查，错过会补做，和手工节点管理共用互斥锁。网络失败保留现状，下一次定时检查重试。不会重写节点端口、凭据、外置客户端配置或平台规则。升级与证书续期重启可能短暂中断本脚本连接。

```bash
dodo-sbox update-script     # 只更新脚本
dodo-sbox update-core       # 只更新当前脚本验证的核心
dodo-sbox auto-update status
journalctl -u dodo-sbox-update.service -n 50 --no-pager
```

菜单提供上一份节点配置回滚和脚本回滚。仅回滚脚本不降低核心版本；核心更换失败时自动恢复的是本次替换前的核心。卸载同时移除本脚本的更新、续期任务和数据，保留共享依赖。

## 分流边界

提供 Netflix、Disney+、YouTube 的基础域名组，可以查看或修改后缀。列表需要随平台变化维护；匹配 DNS 和代理规则时，代理优先。SOCKS5 代理需要支持 UDP 才能转发 QUIC；不可用时不静默回落本机。

DNS 解锁要求客户端把目标域名或 DNS 查询交给服务器。sing-box 1.14 的 resolve 不会根据 SNI 把一个已解析的 IP 重新解析。ECH 或无法嗅探的流量也不能保证命中域名规则。普通公共 DNS 本身不能保证地区解锁。

## 源码与验证

脚本运行不需要 Python。开发时使用 Bash、jq、OpenSSL 3、ShellCheck 和对应平台的 sing-box 核心：

```bash
bash build.sh
shellcheck -S warning -s bash dist/dodo-sbox install.sh
TEST_CORE=/absolute/path/to/sing-box TEST_OPENSSL=/absolute/path/to/openssl bash tests/local.sh
TEST_CORE=/absolute/path/to/sing-box bash tests/updates.sh
```

`tests/bootstrap.sh` 和 `tests/update-timer.sh` 仅用于可丢弃的 Linux CI，后者会安装和卸载本脚本。不要在已有部署上直接运行。其他实机测试脚本同样需要事先阅读和备份。完整已验证范围见 [测试记录](../TEST_REPORT.md)。
