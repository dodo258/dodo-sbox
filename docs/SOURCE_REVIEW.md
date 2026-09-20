# 三个参考项目的源码对照与取舍

日期：2026-09-20。对照版本：dodo-sbox 0.4.0 → 0.5.0。

本次读取安装、配置生成、节点修改、服务管理、证书、更新、防火墙和分流等相关实现；没有执行第三方安装脚本，也没有把它们安装到共存测试服务器。以下是关键路径的对照，不代表完成三个项目所有分支的逐行审计。

## 固定源码版本

本次重新查询远端，以下提交与读取的本地快照一致。链接固定到提交，避免后续改动使结论失去依据。

| 项目 | 提交 | 重点阅读 |
|---|---|---|
| 233boy/sing-box | `2d78583b5aecccb0da0148a816bc1495a284509f` | `src/core.sh`、`download.sh`、`dns.sh`、`caddy.sh`、`systemd.sh` |
| mack-a/v2ray-agent | `5c5e2b72a394356fb1d53ed05785d407b8743758` | `install.sh` 中端口、DNS 预检、TLS 签发/续期、sing-box 更新、SOCKS5 与 DNS 分流、Reality 管理 |
| yonggekkk/sing-box-yg | `1efd60b1e1954a27b8e8be995200ca57012b1999` | `sb.sh` 中证书模式、配置生成、Reality 切换、域名分流、出口探测、更新和卸载 |

## 233boy：把节点修改复用到配置生成流程

[`change()`](https://github.com/233boy/sing-box/blob/2d78583b5aecccb0da0148a816bc1495a284509f/src/core.sh#L398) 按修改类型分发，修改 SNI 等参数后复用节点生成路径；[`create()`](https://github.com/233boy/sing-box/blob/2d78583b5aecccb0da0148a816bc1495a284509f/src/core.sh#L316) 集中生成配置。它的价值是让参数修改、节点信息和分享链接围绕同一份配置工作。

**本次采纳**：已有 Reality 节点可在节点管理中切换携程／西瓜视频。只修改节点的 `sni`，再由同一配置生成器同步生成服务端握手目标和分享链接。端口、UUID、密钥和 short ID 保持不变。新目标预检失败不改配置，应用失败走原有回滚流程；客户端需要更新 SNI 或重新导入链接。

**已有能力保留**：单服务管理多个节点、节点参数与原始 URI 统一生成、随机端口避占用。我们继续用 `jq --arg` 传参和按节点 ID 修改，不依赖配置行号，也不先删除正在使用的配置。

[`download()`](https://github.com/233boy/sing-box/blob/2d78583b5aecccb0da0148a816bc1495a284509f/src/download.sh#L22) 展示了按组件、版本下载的组织方式。我们已有脚本与核心分别更新；继续保留固定验证版本、SHA256、候选配置校验和失败恢复，不增加任意测试版核心切换。

## mack-a：检查证书申请前提，并区分签发与部署

[`checkDNSIP()`](https://github.com/mack-a/v2ray-agent/blob/5c5e2b72a394356fb1d53ed05785d407b8743758/install.sh#L1549) 查询域名地址并与服务器出口对比；[`installTLS()`](https://github.com/mack-a/v2ray-agent/blob/5c5e2b72a394356fb1d53ed05785d407b8743758/install.sh#L2138) 和 [`renewalTLS()`](https://github.com/mack-a/v2ray-agent/blob/5c5e2b72a394356fb1d53ed05785d407b8743758/install.sh#L2411) 使用 ACME 签发及安装证书。值得借鉴的是把“CA 已签发”和“服务已经使用新证书”视为不同步骤。

**本次修复**：我们在对照这条链路时发现旧版证书迁移的缺口。旧证书无来源标记时，依靠 ACME 导出证书与当前证书一致来识别来源；若签发更新了导出文件，但启用新证书失败，下次会失去这种关联。现在先持久保存已验证的来源关联，再执行续期；应用失败保留当前证书，并允许下次重新尝试应用。

**已有能力保留**：Let’s Encrypt、独立 ACME 账户、持久导出目录、证书/域名/私钥校验、原子切换、失败恢复。我们读取证书本身的到期时间，由 ACME 判断续期条件；不使用文件修改时间推算有效期，不在续期时停止其他 Nginx 或代理服务。

[`allowPort()`](https://github.com/mack-a/v2ray-agent/blob/5c5e2b72a394356fb1d53ed05785d407b8743758/install.sh#L847) 按防火墙类型及传输协议放行。我们已有同类能力，并记录自己新增规则的归属；继续避免全局 reload、关闭防火墙或接管外部规则。

**后续候选，尚未实现**：申请证书前完整检查公开 A / AAAA 记录与多地址情况。不能简单要求“解析地址必须等于某个 IP 查询网站看到的出口”：多 IP、NAT、IPv6 和现有网站验证均可能不同。需要单独设计误报处理，再放进默认申请路径。

## 甬哥：分流通道要检查，规则覆盖范围要明确

[`sbymfl()`](https://github.com/yonggekkk/sing-box-yg/blob/1efd60b1e1954a27b8e8be995200ca57012b1999/sb.sh#L3424) 使用 SOCKS5 请求检查出口；[`changefl()`](https://github.com/yonggekkk/sing-box-yg/blob/1efd60b1e1954a27b8e8be995200ca57012b1999/sb.sh#L3533) 提示域名范围、重复规则与通道失效行为；[`changeym()`](https://github.com/yonggekkk/sing-box-yg/blob/1efd60b1e1954a27b8e8be995200ca57012b1999/sb.sh#L2554) 提供已有节点的 Reality 目标切换。

**本次采纳**：把分流冲突提示落实成保存前检查。一个规则使用 DNS 解锁、另一个规则使用代理出口时，同域名以及父子域名范围重叠都会被指出；例如 `example.com` 与 `video.example.com`。`notexample.com` 不算重叠；同方式规则使用同一个 DNS／出口，允许重叠。

升级保留旧规则及原有代理优先顺序，查看时提示重叠，用户可自行调整；修改其他不相关平台不会被旧冲突阻塞。普通流量仍默认使用本机出口，指定代理失败不静默回落。

**后续候选，尚未加入管理菜单**：一键检测指定 SOCKS5 出口的真实 HTTPS 请求，区分连接失败、认证失败、DNS 失败。出口可达不能等同流媒体地区已解锁；现有受控集成测试已验证路由行为，但不是面向用户的解锁诊断功能。

## 不适合本项目目标的实现

- [`sb.sh close()`](https://github.com/yonggekkk/sing-box-yg/blob/1efd60b1e1954a27b8e8be995200ca57012b1999/sb.sh#L177) 会关闭防火墙、清空规则并停止部分 Web 服务；不适合与原有程序共存。
- [`checkPortOpen()`](https://github.com/mack-a/v2ray-agent/blob/5c5e2b72a394356fb1d53ed05785d407b8743758/install.sh#L1582) 会控制 Nginx 和核心服务来探测端口；我们不将这种探测方式用于用户原有服务。
- 甬哥的部分节点修改通过固定行号替换 JSON；我们采用结构化状态和字段修改，避免配置布局改变后写错位置。
- 额外协议、Argo、WARP 自动安装、订阅网站、Telegram 推送、整份客户端配置输出、每日强制重启，都不是当前三协议轻量管理器的必要依赖。
- 不为使用旧 geosite 字段而降级核心；后续扩展规则集应适配当前已验证核心，并设计下载失败时保留旧规则的机制。

本轮独立实现以上流程改进，没有复制三个项目的源码片段。原作者和源码位置在此保留；项目继续以 AGPL-3.0 发布。

## 验证

- `tests/management.sh`：Reality 字段及 URI 一致性、端口凭据不变、失败不落盘、分流父子域名冲突及旧配置兼容。
- `tests/certificates-menu.sh`：模拟旧版 ACME 证书签发成功但应用失败，验证来源仍可识别且下次重试会执行。
- `tests/update-timer.sh`：隔离 Linux CI 中实际生成并切换配置目录，制造应用失败，验证旧配置恢复；停用节点保持停用。
- 原有协议、更新、端口归属、引导下载校验继续运行。本轮不对用户测试服务器执行部署、重启或防火墙变更；不重复向 CA 签发证书。
