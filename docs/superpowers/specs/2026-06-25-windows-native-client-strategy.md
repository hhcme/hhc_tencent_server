# Windows 原生客户端技术选型

> 当前开发优先级仍然是 macOS 原生版。Windows 原生版在 macOS 功能基本稳定后启动，目标是复用领域模型和协议层设计，但使用 Windows 原生 UI 与系统能力。

## 1. 结论

Windows 版本建议采用：

| 层级 | 推荐选型 |
|------|----------|
| UI | WinUI 3 |
| Platform SDK | Windows App SDK 2.2.0 stable |
| 语言 | C# |
| Runtime | .NET 10 LTS |
| 架构 | MVVM |
| 数据库 | SQLite |
| 凭据 | Windows Credential Manager / DPAPI |
| SSH | SSH.NET 起步；必要时评估 libssh2/native wrapper |
| 打包 | MSIX 优先，必要时支持 unpackaged |
| 分发 | GitHub Releases / winget / MSIX installer |

WinUI 3 是微软当前面向新 Windows 桌面应用推荐的现代原生 UI 框架，属于 Windows App SDK 的一部分。它适合新项目，而 WPF 更适合需要极高成熟度、复杂桌面控件生态或维护旧系统的场景。

## 2. 为什么选 WinUI 3

优点：

- 微软当前推荐的新 Windows 原生 UI 技术方向。
- Fluent Design 视觉体系更贴近 Windows 11。
- Windows App SDK 提供窗口、生命周期、通知、资源、部署等现代能力。
- 支持 C# 和 C++，本项目优先 C#。
- 可覆盖 Windows 10 1809+ 和 Windows 11。

风险：

- 相比 WPF，WinUI 3 的生态和部分桌面控件成熟度仍需要验证。
- XAML 设计器、第三方控件、复杂表格、终端控件可能不如 WPF 省心。
- 打包和 Windows App SDK runtime 分发需要提前设计。

因此策略是：**新 Windows 版选 WinUI 3，但核心业务不要绑死 UI 框架。**

## 3. 为什么不优先 WPF

WPF 的优势：

- 稳定、成熟、企业应用经验多。
- 第三方控件和复杂数据表格生态强。
- 文档和踩坑经验丰富。

不作为首选的原因：

- 新项目视觉和交互更难自然贴近 Windows 11。
- 未来平台方向不如 WinUI 3 清晰。
- 如果目标是“原生、现代、长期维护”，WinUI 3 更符合方向。

WPF 可以作为 Plan B：如果 WinUI 3 在终端组件、复杂表格、窗口行为或打包部署上阻塞明显，再评估 WPF。

## 4. 为什么用 C# 而不是 C++

本项目主要复杂度在：

- SSH 连接和命令执行。
- 云 API。
- SQLite 数据持久化。
- 凭据管理。
- 大量表单、列表、状态同步。
- 部署脚本和日志。

C# 在这些方面开发效率更高，异步模型、JSON、HTTP、SQLite、MVVM 生态更合适。C++/WinRT 只有在需要极致性能、底层系统集成、DirectX 或复杂 native interop 时才值得优先考虑。

## 5. Windows 架构建议

```text
HHCServerManager.Windows/
├── App/
│   ├── App.xaml
│   └── MainWindow.xaml
├── Presentation/
│   ├── Views/
│   ├── ViewModels/
│   └── Controls/
├── Application/
│   ├── ServerManagement/
│   ├── CloudProviders/
│   ├── Deployment/
│   └── Settings/
├── Domain/
│   ├── Servers/
│   ├── SSH/
│   ├── Cloud/
│   └── Security/
├── Infrastructure/
│   ├── Storage/
│   ├── Credentials/
│   ├── SSH/
│   ├── CloudProviders/
│   └── Logging/
└── Tests/
```

分层原则：

- `Domain` 保持平台无关。
- `Application` 编排用例，不直接依赖 WinUI。
- `Infrastructure` 封装 SQLite、Credential Manager、SSH、云 API。
- `Presentation` 才依赖 WinUI 3。
- macOS 和 Windows 尽量共享领域概念和接口命名，但不强行共享代码。

## 6. 与 macOS 版的对应关系

| 能力 | macOS | Windows |
|------|-------|---------|
| UI | SwiftUI | WinUI 3 |
| 语言 | Swift | C# |
| SSH | SwiftNIO SSH | SSH.NET / libssh2 wrapper |
| 本地数据库 | SQLite + GRDB | SQLite + EF Core 或 sqlite-net |
| 凭据 | macOS Keychain | Windows Credential Manager / DPAPI |
| 云 API | Provider Adapter | Provider Adapter |
| 打包 | `.app` / 后续签名 notarization | MSIX / winget |
| 自动更新 | 后续评估 | MSIX / winget / GitHub Releases |

## 7. 需要提前技术验证的点

Windows 版开工前，至少验证：

1. WinUI 3 的复杂列表、侧边栏、Tab、数据表格体验。
2. 终端控件方案：是否自研简化命令面板、集成 ConPTY、或引入成熟终端控件。
3. SSH.NET 对 ED25519、passphrase、host key verification、streaming output 的支持情况。
4. Credential Manager / DPAPI 的凭据读写和迁移策略。
5. MSIX 打包、自动更新和 Windows App SDK runtime 分发。
6. Windows 防火墙、代理、企业环境下的网络限制。
7. ARM64 Windows 支持。

## 8. 路线图位置

Windows 版本不进入当前 macOS MVP。当前已启动 Phase 8 技术验证，建议阶段：

- **Phase 1-6**：优先完成 macOS 原生版核心能力。
- **Phase 7**：补齐更多云厂商和高级云资源能力。
- **Phase 8**：启动 Windows 原生版技术验证和架构落地。

Phase 8 的第一目标不是功能全量追平，而是：

1. WinUI 3 应用骨架。
2. 服务器配置 CRUD。
3. Windows Credential Manager 凭据存储。
4. 真实 SSH 连接和 `printf hhc-ssh-ok` smoke test。
5. 连接后执行单条 SSH 命令。
6. 复用云 provider adapter 的领域模型。

当前仓库已加入 WinUI 3 / Windows App SDK 2.2.0 / .NET 10 solution 骨架，并完成可在 macOS 上验证的核心层测试，包括服务器 CRUD、host key trust、smoke test 状态机、取消和连接后的单条命令执行。WinUI XAML 编译、MSIX 打包、Credential Manager 真实读写和真实 SSH smoke test 仍需 Windows 主机补验。

## 9. 参考资料

- WinUI 3: https://learn.microsoft.com/en-us/windows/apps/winui/winui3/
- Windows App SDK: https://learn.microsoft.com/en-us/windows/apps/windows-app-sdk/
- Windows developer platform overview: https://learn.microsoft.com/en-us/windows/apps/get-started/
- Windows App SDK downloads: https://learn.microsoft.com/en-us/windows/apps/windows-app-sdk/downloads
- .NET downloads and support: https://dotnet.microsoft.com/en-us/download/dotnet
