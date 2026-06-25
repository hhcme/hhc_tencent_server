# HHC 服务器管理器

[English](README.en.md) | 中文

HHC 服务器管理器是一个开源的 macOS 原生服务器管理客户端。它的目标是以 SSH 为核心管理多台 Linux 服务器，提供类似宝塔面板的桌面端体验，并在用户主动配置云厂商 API 凭据后启用实例发现、云监控、安全组和开关机等增强能力。

当前仓库处于 macOS 活跃实现阶段，Windows 原生版 Phase 8 技术验证已经启动。macOS 应用已经可以保存服务器配置、将 SSH 和云凭据存入 Keychain、校验 SSH 主机指纹、执行真实 OpenSSH smoke test、执行单条远程命令、浏览和编辑远程文件、通过 rsync/sftp/scp 排队批量传输文件并展示运行中字节进度、有限并发和中断重试、展示 SSH 与已关联云实例的 Dashboard 指标、查看并修改部分云资源和安全资源，并支持按运行时权限失败自动降级云能力，管理 systemd/Cron/Nginx/Firewall/Environment 基础能力，运行 GitLab 风格部署流程，管理 Verdaccio npm 私有仓库基础能力并完成隔离真实生命周期验证，并在 SQLite 中持久化命令、云资源、部署、仓库和远程变更元数据。Windows 目录已加入 WinUI 3 / Windows App SDK / .NET solution 骨架，并完成领域模型、SQLite、Credential Manager 边界、主机指纹信任、SSH adapter、MVVM、依赖注入和连接状态机基础测试；完整 WinUI/MSIX/runtime 验证仍需 Windows 主机。

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
- 真实 OpenSSH smoke test、可取消的简化单条命令面板、命令元数据历史、stdout/stderr 分开展示和历史重跑。
- 云账号元数据和云凭据存储基础。
- 云厂商 adapter 协议、能力 registry、统一错误和超时包装。
- 腾讯云、阿里云和华为云 adapter，覆盖实例发现、部分电源/云盘/快照/安全组操作，以及已关联实例 Dashboard 指标，并有 mock 测试覆盖。
- 腾讯云安全组基础：通过 VPC API 读取安全组和规则，并在已关联账号/地域下支持经过确认的单条规则新增/删除和审计记录。
- 云导入 sheet：验证腾讯云账号、加载地域、同步 CVM 实例，并导入为 SSH profile。
- Dashboard 基础：通过 SSH 探测 OS/能力，并展示负载、内存、磁盘、CPU、网络、进程摘要和已关联云实例指标，支持手动刷新和自动刷新。
- 远程文件浏览基础：支持路径导航、目录列表、文件元信息展示、基于 OpenSSH/rsync/sftp/scp 的有限并发批量上传/下载、运行中字节进度、部分文件保留、当前传输取消、待传队列清空、失败/取消/中断任务重试、重命名、基于 chmod 的权限修改、可恢复移入回收目录，以及带保存前备份和另存为的轻量 UTF-8 文本编辑。
- Services 基础：支持 systemd 服务列表、状态展示、journal 日志读取，以及带确认的 start/stop/restart/reload 操作。
- Cron 基础：支持 crontab 读取、任务解析、添加/启用/禁用/删除流程，以及写入前远端备份。
- Nginx 基础：支持动态探测配置路径、受保护编辑、远端备份、执行 `nginx -t`、测试失败自动回滚、确认后 reload，并写入远程变更审计记录。
- 防火墙基础：支持探测 firewalld、ufw、nftables、iptables 后端、展示规则，并执行受限新增/删除规则。
- 环境变量文件基础：支持常见 `.env`、`/etc/default`、`/etc/sysconfig` 和 systemd drop-in 文件的受限发现与编辑，保存前创建远端备份，并写入审计记录。
- 可选云账号接入：腾讯云、阿里云、华为云等通过 adapter 扩展。
- 云实例发现、云资源元数据、云监控、安全组和电源操作。
- 简化命令面板和服务器 Dashboard。
- SFTP 文件管理器。
- systemd、Nginx、防火墙、Cron、环境变量管理。
- GitLab 风格部署：项目管理、命令预览、日志、回滚、本地 webhook listener 和运行中日志刷新。
- Verdaccio npm 私有仓库管理：preflight、安装、服务控制、用户、包列表、备份/恢复、Nginx proxy 和 npm smoke test，并提供 Dart/Flutter 外部 Hosted Pub Repository 配置辅助。
- Verdaccio 已有受保护的真实服务器生命周期覆盖：隔离安装、用户创建、npm publish/install smoke、重启、配置备份和备份/恢复；生产环境部署和 proxy 暴露仍需按目标环境单独验收。
- Windows 原生版 Phase 8 solution 骨架：WinUI 3、Windows App SDK、.NET、SQLite、Windows Credential Manager 边界、主机指纹信任和 SSH adapter 基础。

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
   先聚合 SSH 指标和已关联腾讯云 CVM 的 CPU 云监控指标；交付基于 SSH bootstrap 的目录浏览、轻量编辑、有限并发排队批量传输、rsync 字节进度、部分文件保留和更多云监控指标，再继续固化 SFTP 和可恢复传输流程。
4. **Phase 4：安全组 + 环境配置**
   安全组查看/修改、systemd、Nginx、防火墙、Cron、环境变量管理。
5. **Phase 5：GitLab 部署**
   手动部署、部署日志、回滚和 webhook 自动部署。
6. **Phase 6：私有包仓库**
   Verdaccio 管理，以及 Dart/Flutter 外部 Hosted Pub Repository 配置辅助；自托管 pub registry 安装在真实 publish/get 验收通过前只保留为研究项。
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

macOS 应用已经进入活跃实现阶段。Phase 1 到 Phase 6 的基础能力已经覆盖 SSH、可选云 API、Dashboard、文件管理、安全/环境工具、部署和私有仓库管理：SwiftUI 应用结构、本地 SQLite 持久化、Keychain SSH/云凭据、主机指纹信任、基于 OpenSSH 的真实命令执行与取消、可重跑的命令元数据历史、stdout/stderr 分开展示、云账号元数据、云实例关联、腾讯云/阿里云/华为云 adapter、已关联云实例 Dashboard 指标、远程目录浏览和编辑、带 rsync 字节进度和 partial 保留、OpenSSH `sftp -b` 普通 batch fallback、scp 最终回退和中断历史重试的有限并发批量传输、systemd/Cron/Nginx/Firewall/Environment 工作流、远程变更审计日志、GitLab 风格部署运行/日志/回滚/webhook listener、Verdaccio preflight/安装/服务/用户/包列表/备份/恢复/Nginx proxy/npm smoke 流程、单元测试、CI，以及真实服务器上的 SSH、传输、临时部署和隔离 Verdaccio 安装/发布/重启/备份/恢复 smoke 验证。Windows 原生版 Phase 8 已启动，加入 WinUI 3 / Windows App SDK / .NET solution 骨架和已测试核心层。命令输出默认只保留在本次会话中，不落库持久化。SwiftNIO/libssh2 SFTP 固化、真正断点续传、生产项目部署验收、真实多云写操作验收、生产 Verdaccio/proxy 验收和完整 Windows 主机验收仍在后续阶段。

## 参与贡献

欢迎后续参与设计讨论、实现、测试和文档改进。提交前请阅读：

- [贡献指南](CONTRIBUTING.md)
- [行为准则](CODE_OF_CONDUCT.md)
- [安全策略](SECURITY.md)

## 许可证

本项目使用 [MIT License](LICENSE) 开源。
