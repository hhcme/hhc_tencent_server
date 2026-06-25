# HHC 服务器管理器

[English](README.en.md) | 中文

HHC 服务器管理器是一个开源的 macOS 原生服务器管理客户端。它的目标是以 SSH 为核心管理多台 Linux 服务器，提供类似宝塔面板的桌面端体验，并在用户主动配置云厂商 API 凭据后启用实例发现、云监控、安全组和开关机等增强能力。

当前仓库处于 macOS 早期实现阶段。应用已经可以保存服务器配置、将 SSH 和云凭据存入 Keychain、校验 SSH 主机指纹、执行真实 OpenSSH smoke test、执行单条远程命令，并在 SQLite 中持久化命令和云资源元数据。

## 为什么做这个项目

很多服务器管理工具要么依赖 Web 面板，要么依赖云厂商控制台，要么需要在服务器上安装重量级 agent。这个项目选择从 macOS 原生客户端出发，以通用 SSH 能力完成常见运维动作，同时用云 API 补足实例发现、云资源状态、云监控和安全组这类更适合由云平台提供的信息。

目标用户包括：

- 管理多台云服务器的个人开发者。
- 需要统一管理腾讯云、阿里云、华为云或自建服务器的小团队。
- 希望把服务器配置、部署、包仓库管理集中在本地客户端里的开发者。

## 功能

- 服务器列表、分组、搜索和连接状态。
- 密码和私钥认证。
- macOS Keychain 保存敏感凭据。
- SSH 主机指纹首次确认和后续校验。
- 真实 OpenSSH smoke test、简化单条命令面板和命令元数据历史。
- 云账号元数据和云凭据存储基础。
- 可选云账号接入：腾讯云、阿里云、华为云等通过 adapter 扩展。
- 云实例发现、云资源元数据、云监控、安全组和电源操作。
- 简化命令面板和服务器 Dashboard。
- SFTP 文件管理器。
- systemd、Nginx、防火墙、Cron、环境变量管理。
- GitLab 项目部署、日志和回滚。
- Verdaccio npm 私有仓库和 Dart/Flutter 私有 pub 仓库管理。

## 技术方向

| 层级 | 选型 |
|------|------|
| 语言 | Swift 6.1+ |
| UI | SwiftUI，必要时混入 AppKit |
| SSH | 当前 bootstrap：系统 OpenSSH adapter；目标核心：SwiftNIO SSH 0.13.x |
| 云 API | Provider adapter，可选启用 |
| 数据库 | 当前 bootstrap：SQLite C API；后续持久化层可迁移到 GRDB 7.x |
| 凭据 | macOS Keychain |
| 最低系统 | macOS 14 |

## 路线图

1. **Phase 1：项目骨架 + 真实 SSH 最小闭环**
   macOS App、服务器 CRUD、Keychain、主机指纹信任、真实 SSH 连接、`printf hhc-ssh-ok` smoke test。
2. **Phase 2：云厂商基础层 + 简化命令面板**
   云账号管理、Provider Adapter、腾讯云只读实例发现、命令历史。
3. **Phase 3：Dashboard + 文件管理器**
   聚合 SSH 指标和云监控指标；先完成 SFTP 技术验证，再实现目录浏览、上传、下载和在线编辑。
4. **Phase 4：安全组 + 环境配置**
   安全组查看/修改、systemd、Nginx、防火墙、Cron、环境变量管理。
5. **Phase 5：GitLab 部署**
   手动部署、部署日志、回滚和 webhook 自动部署。
6. **Phase 6：私有包仓库**
   Verdaccio 和 Dart/Flutter 私有仓库管理。
7. **Phase 7：高级云资源管理**
   更多云厂商、快照、云盘、计费状态和高级资源操作。
8. **Phase 8：Windows 原生版技术验证**
   WinUI 3、Windows App SDK、.NET、Windows Credential Manager、真实 SSH smoke test。

## 文档

- [文档索引](docs/README.md)
- [macOS MVP 本地设计快照](docs/assets/design/macos-mvp-v0.2/README.md)
- [macOS MVP 设计稿说明](docs/superpowers/specs/2026-06-25-macos-mvp-design.md)
- [设计文档](docs/superpowers/specs/2026-06-25-server-manager-design.md)
- [云厂商 API 增强层设计](docs/superpowers/specs/2026-06-25-cloud-provider-integration.md)
- [Windows 原生版技术选型](docs/superpowers/specs/2026-06-25-windows-native-client-strategy.md)
- [全部 Phase 实施计划](docs/superpowers/plans/README.md)

## 开发状态

macOS 应用已经进入实现阶段。Phase 1 基础已经落地，Phase 2 基础也已经启动：SwiftUI 应用结构、本地 SQLite 持久化、Keychain SSH/云凭据、主机指纹信任、基于 OpenSSH 的真实命令执行、命令元数据历史、云账号元数据、云实例关联、操作日志、单元测试和 GitHub Actions CI。命令输出默认只保留在本次会话中，不落库持久化。腾讯云 API 接入、Dashboard、SFTP、部署、私有包仓库和 Windows 原生版仍在后续 Phase。

## 参与贡献

欢迎后续参与设计讨论、实现、测试和文档改进。提交前请阅读：

- [贡献指南](CONTRIBUTING.md)
- [行为准则](CODE_OF_CONDUCT.md)
- [安全策略](SECURITY.md)

## 许可证

本项目使用 [MIT License](LICENSE) 开源。
