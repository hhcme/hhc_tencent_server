# HHC Server Manager / HHC 服务器管理器

[English](README.en.md) | [中文](README.zh-CN.md)

HHC Server Manager is an open-source macOS native server management client. It aims to provide a Baota-like desktop experience for managing Linux servers through SSH, with optional cloud provider API enhancements for instance discovery, cloud-side metrics, security groups, and power operations.

HHC 服务器管理器是一个开源的 macOS 原生服务器管理客户端，目标是以 SSH 为核心提供类似宝塔面板的桌面端体验，并在用户配置云厂商 API 凭据后启用实例发现、云监控、安全组和开关机等增强能力。

> Project status: early macOS implementation. The app can already store server profiles, keep credentials in Keychain, verify SSH host keys, run a real OpenSSH smoke test, and execute single remote commands from a simplified command panel.
>
> 项目状态：macOS 早期实现阶段。当前应用已经可以保存服务器配置、将凭据存入 Keychain、校验 SSH 主机指纹、执行真实 OpenSSH smoke test，并通过简化命令面板执行单条远程命令。

## Highlights / 亮点

- macOS native app built with SwiftUI.
- SSH-first server management with optional cloud API enhancement.
- Credentials stored in macOS Keychain.
- Host key verification as a first-class security requirement.
- Server browser, dedicated server workspace, real smoke test, and simplified command panel are underway.
- Bilingual README for the project introduction; detailed design and implementation documents are maintained in Chinese.
- MIT licensed.

- 使用 SwiftUI 构建 macOS 原生应用。
- SSH-first 服务器管理，云 API 作为可选增强能力。
- SSH 密码、私钥等敏感信息存入 macOS Keychain。
- 把主机指纹验证作为基础安全能力。
- 服务器列表、单服务器工作台、真实 smoke test 和简化命令面板已进入实现。
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
6. Phase 6: private npm and Dart/Flutter package registries.
7. Phase 7: additional cloud providers, snapshots, disks, billing, and advanced cloud resource management.
8. Phase 8: Windows native client technical validation with WinUI 3, Windows App SDK, and .NET.

## Contributing / 参与贡献

Contributions are welcome once implementation starts. Please read [CONTRIBUTING.md](CONTRIBUTING.md), [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md), and [SECURITY.md](SECURITY.md) before opening issues or pull requests.

项目进入实现阶段后欢迎贡献。提交 issue 或 pull request 前，请先阅读 [CONTRIBUTING.md](CONTRIBUTING.md)、[CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md) 和 [SECURITY.md](SECURITY.md)。

## License / 许可证

This project is released under the [MIT License](LICENSE).

本项目基于 [MIT License](LICENSE) 开源。
