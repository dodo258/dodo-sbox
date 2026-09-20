# 更新记录

## 0.1.0 — 2026-09-20

首个公开测试版本。

- Bash 管理器，固定版本 sing-box 核心，单服务管理多个独立节点。
- VLESS Reality、AnyTLS、Hysteria2；端口范围 10000–50000。
- 原始协议链接、本地二维码、节点启停、改名、端口和凭据管理。
- Let's Encrypt 自动签发、每日续期检查；独立 ACME 目录，无 Cloudflare API。
- 指定平台的解锁 DNS 或 SOCKS5 出口，其他流量保持本机直连。
- 原子切换配置、启动失败回滚、脚本与核心分别更新、独立卸载。
- 主菜单展示服务、节点数量、分流和续期状态；节点支持按序号选择。
- GitHub Actions 检查 Shell、可复现发布包和真实 TLS 代理请求。

实测和未验证的环境见 [TEST_REPORT.md](TEST_REPORT.md)。
