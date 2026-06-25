# HHC Server Manager / HHC 服务器管理器

[English](README.en.md) | [中文](README.zh-CN.md)

HHC Server Manager is an open-source macOS native server management client. It aims to provide a Baota-like desktop experience for managing Linux servers through SSH, with optional cloud provider API enhancements for instance discovery, cloud-side metrics, security groups, and power operations.

HHC 服务器管理器是一个开源的 macOS 原生服务器管理客户端，目标是以 SSH 为核心提供类似宝塔面板的桌面端体验，并在用户配置云厂商 API 凭据后启用实例发现、云监控、安全组和开关机等增强能力。

> Project status: design and Phase 1 planning. The first implementation milestone is a secure, real SSH connection MVP.
>
> 项目状态：设计与 Phase 1 规划阶段。第一个实现里程碑是安全、真实的 SSH 连接 MVP。

## Highlights / 亮点

- macOS native app planned with SwiftUI.
- SSH-first server management with optional cloud API enhancement.
- Credentials stored in macOS Keychain.
- Host key verification as a first-class security requirement.
- Bilingual documentation in English and Chinese.
- MIT licensed.

- 计划使用 SwiftUI 构建 macOS 原生应用。
- SSH-first 服务器管理，云 API 作为可选增强能力。
- SSH 密码、私钥等敏感信息存入 macOS Keychain。
- 把主机指纹验证作为基础安全能力。
- 中英文双语文档。
- 使用 MIT 开源协议。

## Documentation / 文档

- [Documentation index / 文档索引](docs/README.md)
- [macOS MVP Figma design / macOS MVP Figma 设计稿](https://www.figma.com/design/Wvukq4AG9kHbVYKdF64gBX)
- [macOS MVP design note, Chinese / macOS MVP 设计稿说明中文](docs/superpowers/specs/2026-06-25-macos-mvp-figma-design.md)
- [macOS MVP design note, English](docs/en/2026-06-25-macos-mvp-figma-design.md)
- [Design document, Chinese / 设计文档中文](docs/superpowers/specs/2026-06-25-server-manager-design.md)
- [Design document, English](docs/en/2026-06-25-server-manager-design.md)
- [Cloud Provider API enhancement, Chinese / 云厂商 API 增强层中文](docs/superpowers/specs/2026-06-25-cloud-provider-integration.md)
- [Cloud Provider API enhancement, English](docs/en/2026-06-25-cloud-provider-integration.md)
- [Windows native client strategy, Chinese / Windows 原生版技术选型中文](docs/superpowers/specs/2026-06-25-windows-native-client-strategy.md)
- [Windows native client strategy, English](docs/en/2026-06-25-windows-native-client-strategy.md)
- [Phase 1 plan, Chinese / Phase 1 中文计划](docs/superpowers/plans/2026-06-25-phase1-ssh-connection.md)
- [Phase 1 plan, English](docs/en/2026-06-25-phase1-ssh-connection.md)

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
