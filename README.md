# HHC Server Manager / HHC 服务器管理器

[English](README.en.md) | [中文](README.zh-CN.md)

HHC Server Manager is an open-source macOS native server management client. It aims to provide a Baota-like desktop experience for managing Linux servers through SSH, with optional cloud provider API enhancements for instance discovery, cloud-side metrics, security groups, and power operations.

HHC 服务器管理器是一个开源的 macOS 原生服务器管理客户端，目标是以 SSH 为核心提供类似宝塔面板的桌面端体验，并在用户配置云厂商 API 凭据后启用实例发现、云监控、安全组和开关机等增强能力。

> Project status: early macOS implementation. The app can already store server profiles, keep SSH and cloud credentials in Keychain, verify SSH host keys, run a real OpenSSH smoke test, execute single remote commands, browse remote files, queue rsync/scp-backed batch file transfers with running byte progress, show SSH dashboard metrics, load linked Tencent Cloud CVM CPU metrics, inspect Tencent Cloud security groups, apply confirmed single-rule Tencent Cloud security group changes, inspect and edit limited firewall rules, manage systemd/Cron/Nginx/Environment foundations, and persist command/cloud/remote-change metadata in SQLite.
>
> 项目状态：macOS 早期实现阶段。当前应用已经可以保存服务器配置、将 SSH 和云凭据存入 Keychain、校验 SSH 主机指纹、执行真实 OpenSSH smoke test、执行单条远程命令、浏览远程文件、通过 rsync/scp 排队批量传输文件并展示运行中字节进度、展示 SSH Dashboard 指标、加载已关联腾讯云 CVM 的 CPU 云监控指标，查看腾讯云安全组、执行经过确认的腾讯云安全组单条规则变更、查看并有限修改防火墙规则，管理 systemd/Cron/Nginx/Environment 基础能力，并在 SQLite 中持久化命令、云资源和远程变更元数据。

## Highlights / 亮点

- macOS native app built with SwiftUI.
- SSH-first server management with optional cloud API enhancement.
- Credentials stored in macOS Keychain.
- Host key verification as a first-class security requirement.
- Server browser, dedicated server workspace, real smoke test, simplified command panel, and command metadata history are underway.
- Dashboard auto-refresh, SSH metrics, linked Tencent Cloud CVM CPU metrics, Tencent Cloud security group inspection and confirmed single-rule changes, remote file browsing, lightweight text editing with Save As, permission changes, queued batch upload/download, systemd Services, Cron management, guarded Nginx config edit/test/reload, limited Firewall rule changes, and guarded Environment file editing are underway.
- Cloud account metadata and cloud credential storage foundation are in place.
- Cloud provider adapter protocol, capability registry, normalized errors, and timeout wrapper are in place.
- Tencent Cloud adapter now includes TC3 request signing plus Region, CVM instance query parsing, Cloud Monitor CPU metric query support, VPC security group/rule read support, and single-rule security group add/remove actions.
- Bilingual README for the project introduction; detailed design and implementation documents are maintained in Chinese.
- MIT licensed.

- 使用 SwiftUI 构建 macOS 原生应用。
- SSH-first 服务器管理，云 API 作为可选增强能力。
- SSH 密码、私钥等敏感信息存入 macOS Keychain。
- 把主机指纹验证作为基础安全能力。
- 服务器列表、单服务器工作台、真实 smoke test、简化命令面板和命令元数据历史已进入实现。
- Dashboard 自动刷新、SSH 指标、已关联腾讯云 CVM 的 CPU 云监控指标、腾讯云安全组查看和经确认的单条规则变更、远程文件浏览、带另存为的轻量文本编辑、权限修改、带 rsync 字节进度和 scp 回退的排队批量上传/下载、systemd Services、Cron 管理、受保护的 Nginx 配置编辑/测试/reload、有限防火墙规则变更和受保护的环境变量文件编辑已进入实现。
- 云账号元数据和云凭据存储基础已经落地。
- 云厂商 adapter 协议、能力 registry、统一错误和超时包装已经落地。
- 腾讯云 adapter 已包含 TC3 请求签名、地域查询、CVM 实例查询解析、云监控 CPU 指标查询、VPC 安全组/规则查询和单条安全组规则新增/删除。
- README 作为项目介绍保留中英文；详细设计和实施计划默认使用中文维护。
- 使用 MIT 开源协议。

## Documentation / 文档

- [Documentation index / 文档索引](docs/README.md)
- [macOS MVP design snapshots / macOS MVP 本地设计快照](docs/assets/design/macos-mvp-v0.2/README.md)
- [macOS MVP design note / macOS MVP 设计稿说明](docs/superpowers/specs/2026-06-25-macos-mvp-design.md)
- [Design document / 项目设计文档](docs/superpowers/specs/2026-06-25-server-manager-design.md)
- [Cloud Provider API enhancement / 云厂商 API 增强层设计](docs/superpowers/specs/2026-06-25-cloud-provider-integration.md)
- [Windows native client strategy / Windows 原生版技术选型](docs/superpowers/specs/2026-06-25-windows-native-client-strategy.md)
- [Phase implementation plans / 全部 Phase 实施计划](docs/superpowers/plans/README.md)

## Planned Roadmap / 规划路线

1. Phase 1: macOS app skeleton, server CRUD, Keychain integration, host key trust, real SSH command smoke test.
2. Phase 2: Cloud provider foundation, cloud account settings, Tencent Cloud read-only instance discovery, and simplified command panel.
3. Phase 3: Dashboard combining SSH metrics and cloud metrics, plus SFTP technical validation and file manager.
4. Phase 4: security group management, systemd, Nginx, firewall, cron, and environment management.
5. Phase 5: GitLab deployment workflows.
6. Phase 6: private npm registry management and Dart/Flutter external Hosted Pub Repository configuration assistance.
7. Phase 7: additional cloud providers, snapshots, disks, billing, and advanced cloud resource management.
8. Phase 8: Windows native client technical validation with WinUI 3, Windows App SDK, and .NET.

## Contributing / 参与贡献

Contributions are welcome once implementation starts. Please read [CONTRIBUTING.md](CONTRIBUTING.md), [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md), and [SECURITY.md](SECURITY.md) before opening issues or pull requests.

项目进入实现阶段后欢迎贡献。提交 issue 或 pull request 前，请先阅读 [CONTRIBUTING.md](CONTRIBUTING.md)、[CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md) 和 [SECURITY.md](SECURITY.md)。

## License / 许可证

This project is released under the [MIT License](LICENSE).

本项目基于 [MIT License](LICENSE) 开源。
