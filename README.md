# HHC Server Manager / HHC 服务器管理器

[English](README.en.md) | [中文](README.zh-CN.md)

HHC Server Manager is an open-source macOS native server management client. It aims to provide a Baota-like desktop experience for managing Linux servers through SSH, with optional cloud provider API enhancements for instance discovery, cloud-side metrics, security groups, and power operations.

HHC 服务器管理器是一个开源的 macOS 原生服务器管理客户端，目标是以 SSH 为核心提供类似宝塔面板的桌面端体验，并在用户配置云厂商 API 凭据后启用实例发现、云监控、安全组和开关机等增强能力。

> Project status: active macOS implementation, with Windows native Phase 8 technical validation started. The macOS app can already store server profiles, keep SSH and cloud credentials in Keychain, verify SSH host keys, run real OpenSSH smoke tests, execute single remote commands, browse and edit remote files, queue rsync/sftp/scp-backed batch transfers with running byte progress, limited concurrency, and retryable interrupted transfers, show SSH and linked-cloud dashboard metrics, inspect and mutate selected cloud/security resources with runtime permission-based capability downgrade, manage systemd/Cron/Nginx/Firewall/Environment foundations, run GitLab-style deployment workflows, manage Verdaccio npm registry foundations with real isolated lifecycle validation, and persist command/cloud/deployment/registry/remote-change metadata in SQLite. The Windows tree now has a WinUI 3 / Windows App SDK / .NET solution skeleton plus tested domain, SQLite, Credential Manager boundary, host-key trust, SSH adapter, MVVM, DI, and connection-state foundations; full WinUI/MSIX/runtime validation still requires a Windows host.
>
> 项目状态：macOS 活跃实现阶段，Windows 原生版 Phase 8 技术验证已经启动。macOS 应用已经可以保存服务器配置、将 SSH 和云凭据存入 Keychain、校验 SSH 主机指纹、执行真实 OpenSSH smoke test、执行单条远程命令、浏览和编辑远程文件、通过 rsync/sftp/scp 排队批量传输文件并展示运行中字节进度、有限并发和中断重试、展示 SSH 与已关联云实例的 Dashboard 指标、查看并修改部分云资源和安全资源，并支持按运行时权限失败自动降级云能力，管理 systemd/Cron/Nginx/Firewall/Environment 基础能力，运行 GitLab 风格部署流程，管理 Verdaccio npm 私有仓库基础能力并完成隔离真实生命周期验证，并在 SQLite 中持久化命令、云资源、部署、仓库和远程变更元数据。Windows 目录已加入 WinUI 3 / Windows App SDK / .NET solution 骨架，并完成领域模型、SQLite、Credential Manager 边界、主机指纹信任、SSH adapter、MVVM、依赖注入和连接状态机基础测试；完整 WinUI/MSIX/runtime 验证仍需 Windows 主机。

## Highlights / 亮点

- macOS native app built with SwiftUI.
- SSH-first server management with optional cloud API enhancement.
- Credentials stored in macOS Keychain.
- Host key verification as a first-class security requirement.
- Server browser, dedicated server workspace, real smoke test, simplified command panel, and command metadata history are underway.
- Dashboard auto-refresh, SSH metrics, linked cloud metrics, security group inspection and confirmed single-rule changes, remote file browsing, lightweight text editing with Save As, permission changes, queued batch upload/download, systemd Services, Cron management, guarded Nginx config edit/test/reload, limited Firewall rule changes, guarded Environment file editing, GitLab-style deployments, and Verdaccio registry management are underway.
- Verdaccio has guarded real-server lifecycle coverage for isolated install, user creation, npm publish/install smoke, restart, config backup, and backup/restore; production deployment and proxy exposure still require environment-specific validation.
- Cloud account metadata and cloud credential storage foundation are in place.
- Cloud provider adapter protocol, capability registry, normalized errors, and timeout wrapper are in place.
- Tencent Cloud, Alibaba Cloud, and Huawei Cloud adapters now cover instance discovery, selected power/disk/snapshot/security-group operations, and linked dashboard metrics with mock-backed tests.
- Windows native Phase 8 has started with a WinUI 3 / Windows App SDK / .NET solution skeleton and tested core layers; Windows-host validation is still pending.
- Bilingual README for the project introduction; detailed design and implementation documents are maintained in Chinese.
- MIT licensed.

- 使用 SwiftUI 构建 macOS 原生应用。
- SSH-first 服务器管理，云 API 作为可选增强能力。
- SSH 密码、私钥等敏感信息存入 macOS Keychain。
- 把主机指纹验证作为基础安全能力。
- 服务器列表、单服务器工作台、真实 smoke test、简化命令面板和命令元数据历史已进入实现。
- Dashboard 自动刷新、SSH 指标、已关联云实例指标、安全组查看和经确认的单条规则变更、远程文件浏览、带另存为的轻量文本编辑、权限修改、带 rsync 字节进度和 partial 保留、OpenSSH `sftp -b` 普通 batch fallback、scp 最终回退的排队批量上传/下载、systemd Services、Cron 管理、受保护的 Nginx 配置编辑/测试/reload、有限防火墙规则变更、受保护的环境变量文件编辑、GitLab 风格部署和 Verdaccio 仓库管理已进入实现。
- Verdaccio 已有受保护的真实服务器生命周期覆盖：隔离安装、用户创建、npm publish/install smoke、重启、配置备份和备份/恢复；生产环境部署和 proxy 暴露仍需按目标环境单独验收。
- 云账号元数据和云凭据存储基础已经落地。
- 云厂商 adapter 协议、能力 registry、统一错误和超时包装已经落地。
- 腾讯云、阿里云和华为云 adapter 已覆盖实例发现、部分电源/云盘/快照/安全组操作，以及已关联实例 Dashboard 指标，并有 mock 测试覆盖。
- Windows 原生版 Phase 8 已启动，加入 WinUI 3 / Windows App SDK / .NET solution 骨架和已测试的核心层；Windows 主机验收仍待补齐。
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
