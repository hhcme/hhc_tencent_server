# HHC Server Manager / HHC 服务器管理器

[English](README.en.md) | [中文](README.zh-CN.md)

HHC Server Manager is an open-source macOS native server management client. It aims to provide a Baota-like desktop experience for managing Linux servers over SSH, without depending on any cloud vendor API.

HHC 服务器管理器是一个开源的 macOS 原生服务器管理客户端，目标是通过纯 SSH 提供类似宝塔面板的桌面端体验，不依赖腾讯云、阿里云、华为云等云厂商 API。

> Project status: design and Phase 1 planning. The first implementation milestone is a secure, real SSH connection MVP.
>
> 项目状态：设计与 Phase 1 规划阶段。第一个实现里程碑是安全、真实的 SSH 连接 MVP。

## Highlights / 亮点

- macOS native app planned with SwiftUI.
- Vendor-neutral server management through SSH.
- Credentials stored in macOS Keychain.
- Host key verification as a first-class security requirement.
- Bilingual documentation in English and Chinese.
- MIT licensed.

- 计划使用 SwiftUI 构建 macOS 原生应用。
- 通过 SSH 管理服务器，不绑定云厂商。
- SSH 密码、私钥等敏感信息存入 macOS Keychain。
- 把主机指纹验证作为基础安全能力。
- 中英文双语文档。
- 使用 MIT 开源协议。

## Documentation / 文档

- [Documentation index / 文档索引](docs/README.md)
- [Design document, Chinese / 设计文档中文](docs/superpowers/specs/2026-06-25-server-manager-design.md)
- [Design document, English](docs/en/2026-06-25-server-manager-design.md)
- [Phase 1 plan, Chinese / Phase 1 中文计划](docs/superpowers/plans/2026-06-25-phase1-ssh-connection.md)
- [Phase 1 plan, English](docs/en/2026-06-25-phase1-ssh-connection.md)

## Planned Roadmap / 规划路线

1. Phase 1: macOS app skeleton, server CRUD, Keychain integration, host key trust, real SSH command smoke test.
2. Phase 2: Dashboard and simplified command panel.
3. Phase 3: SFTP technical validation and file manager.
4. Phase 4: systemd, Nginx, firewall, cron, and environment management.
5. Phase 5: GitLab deployment workflows.
6. Phase 6: private npm and Dart/Flutter package registries.

## Contributing / 参与贡献

Contributions are welcome once implementation starts. Please read [CONTRIBUTING.md](CONTRIBUTING.md), [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md), and [SECURITY.md](SECURITY.md) before opening issues or pull requests.

项目进入实现阶段后欢迎贡献。提交 issue 或 pull request 前，请先阅读 [CONTRIBUTING.md](CONTRIBUTING.md)、[CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md) 和 [SECURITY.md](SECURITY.md)。

## License / 许可证

This project is released under the [MIT License](LICENSE).

本项目基于 [MIT License](LICENSE) 开源。
