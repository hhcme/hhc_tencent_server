# Phase 8：Windows 原生版技术验证实施计划

> Phase 8 启动 Windows 原生版，但第一目标不是功能全量追平 macOS，而是验证 WinUI 3 + Windows App SDK + .NET/C# 的原生客户端骨架和真实 SSH MVP。

**前置条件:** macOS 版核心能力稳定，领域模型、云 provider adapter 边界和安全策略已经沉淀。

**相关设计:** `docs/superpowers/specs/2026-06-25-windows-native-client-strategy.md`

## 1. 目标

1. 创建 Windows 原生项目骨架。
2. 验证 WinUI 3、Windows App SDK、.NET/C#、MVVM 的基础工程体验。
3. 实现 Windows 版服务器 CRUD。
4. 使用 Windows Credential Manager / DPAPI 保存 SSH 凭据。
5. 实现真实 SSH 连接、host key trust、`printf hhc-ssh-ok` smoke test。
6. 复用 macOS 版领域概念和接口命名，不强行共享 UI 代码。
7. 输出 Windows 后续追平计划。

## 2. 非目标

- 不追平 macOS 全部功能。
- 不实现 Dashboard、文件管理、部署、包仓库。
- 不做多云高级资源管理。
- 不做 Windows 服务端 agent。
- 不为了共享代码牺牲 Windows 原生 UI 和系统能力。

## 3. 技术约束

- UI 使用 WinUI 3。
- 平台能力走 Windows App SDK stable。
- 语言优先 C#。
- 数据库使用 SQLite。
- 凭据使用 Windows Credential Manager / DPAPI。
- SSH 先验证 SSH.NET；如 ED25519、host key verification、streaming output 受限，再评估 libssh2/native wrapper。
- 打包优先 MSIX，同时验证 unpackaged 开发体验。

## 4. 项目结构

```text
HHCServerManager.Windows/
├── HHCServerManager.Windows.slnx
├── src/
│   ├── HHCServerManager.Windows.App/
│   │   ├── App.xaml
│   │   └── MainWindow.xaml
│   ├── HHCServerManager.Windows.Application/
│   │   ├── Ports/
│   │   └── ServerManagement/
│   ├── HHCServerManager.Windows.Domain/
│   │   ├── Security/
│   │   ├── Servers/
│   │   └── Ssh/
│   └── HHCServerManager.Windows.Infrastructure/
│       ├── Credentials/
│       ├── Ssh/
│       └── Storage/
└── tests/
    └── HHCServerManager.Windows.Tests/
```

## 5. 数据模型

Windows 版 Phase 8 只需要复刻 Phase 1 核心表：

```sql
CREATE TABLE server_profiles (
    id TEXT PRIMARY KEY NOT NULL,
    name TEXT NOT NULL,
    host TEXT NOT NULL,
    port INTEGER NOT NULL DEFAULT 22,
    username TEXT NOT NULL,
    auth_type TEXT NOT NULL,
    credential_ref TEXT NOT NULL,
    group_name TEXT,
    created_at DATETIME NOT NULL,
    updated_at DATETIME NOT NULL
);

CREATE TABLE trusted_host_keys (
    id TEXT PRIMARY KEY NOT NULL,
    server_id TEXT NOT NULL REFERENCES server_profiles(id) ON DELETE CASCADE,
    host TEXT NOT NULL,
    port INTEGER NOT NULL,
    algorithm TEXT NOT NULL,
    fingerprint_sha256 TEXT NOT NULL,
    raw_public_key TEXT,
    trusted_at DATETIME NOT NULL
);
```

## 6. UI 范围

- 启动服务器列表。
- 添加服务器 dialog。
- 单服务器工作台 Overview。
- 服务器切换器。
- Host key trust dialog。
- Connect / Disconnect / Smoke Test。

Windows UI 要贴近 Fluent Design，而不是照搬 macOS 视觉。

## 7. 实施任务

### Task 1：技术验证

- [x] 验证当前 WinUI 3 + Windows App SDK stable 项目模板：已按 Windows App SDK 2.2.0 建立 WinUI 3 项目骨架；NuGet restore 可在 macOS 通过，完整 XAML 编译会调用 Windows `XamlCompiler.exe`，需在 Windows 环境补验。
- [x] 验证 .NET 版本：本地使用 .NET SDK 10.0.301 完成核心层编译和测试。
- [ ] 验证 MSIX 打包：保留 MSIX manifest 骨架，待 Windows/Visual Studio 环境完成 logo、证书和安装验证。
- [x] 验证 SQLite 方案：`Microsoft.Data.Sqlite` repository/store 测试通过。
- [x] 验证 Credential Manager / DPAPI 凭据保存边界：已实现 Win32 `CredWrite/CredRead/CredDelete` adapter，并通过非 Windows 平台保护测试；已加入 Windows-only 真实集成测试入口，真实 Windows 凭据读写待 Windows 主机补验。
- [x] 验证 SSH.NET 对密码、私钥、host key verification 的支持边界：已实现 SSH.NET adapter、host key 扫描和命令执行边界；已加入 Windows-only 真实 SSH smoke 测试入口，真实 SSH 登录、ED25519/passphrase 组合待 Windows 主机补验。

### Task 2：项目骨架

- [x] 创建 solution 和项目结构。
- [x] 建立 MVVM 基础：`MainWindowViewModel` 管理服务器列表、选中服务器、添加/编辑/删除、连接状态、host key 待确认状态和 smoke test 输出。
- [x] 建立依赖注入：WinUI App 启动时通过 `Microsoft.Extensions.DependencyInjection` 组装 SQLite repository、Credential Manager、SSH.NET adapter 和应用服务。
- [x] 添加错误处理基础：ViewModel 统一记录 `ErrorMessage`、`StatusMessage` 和失败状态，WinUI 通过 InfoBar 展示。

### Task 3：存储和凭据

- [x] 实现 server profile repository。
- [x] 实现 trusted host key store。
- [x] 实现 credential store。
- [x] 删除服务器时清理 trusted host key 和凭据。
- [x] 编辑服务器：支持更新名称、host、port、username、group、认证类型和可选替换凭据；host/port 变化时清理旧 trusted host key，凭据替换失败会恢复旧凭据。

### Task 4：SSH MVP

- [x] 实现连接状态机：覆盖 disconnected、checking host key、awaiting trust、connected、running smoke test、failed。
- [x] 实现 host key 首次确认的应用层判断。
- [x] 实现 host key mismatch 阻断的应用层判断。
- [x] 实现密码认证 adapter。
- [x] 实现私钥认证 adapter；已提供 Windows-only 真实私钥/passphrase 测试入口，真实 Windows 主机上的私钥/passphrase 组合待验收。
- [x] 实现 `printf hhc-ssh-ok` smoke test 编排；已提供 Windows-only 真实服务器执行测试入口，真实执行待 Windows 主机验收。

### Task 5：Windows UI

- [x] 服务器列表骨架。
- [x] 服务器列表搜索和空状态：`MainWindowViewModel` 维护全量 `Servers` 和可见 `VisibleServers`，支持按 name/host/username/group 搜索；WinUI 搜索框绑定 `ServerSearchText`，列表为空时展示 Fluent `InfoBar` 空状态。
- [x] 添加服务器 dialog：支持密码和私钥认证服务器配置写入 repository 和 Credential Manager 边界；私钥/passphrase 不进入 SQLite。
- [x] 编辑服务器 dialog：支持保留现有凭据或替换密码/私钥，并复用同一套配置校验和 Credential Manager 边界。
- [x] 单服务器工作台骨架。
- [x] 服务器切换器入口骨架：左侧服务器列表选择即切换当前工作台上下文。
- [x] Host key trust dialog：连接遇到未知或变更指纹时弹出确认 dialog，工作台侧栏也展示 presented fingerprint，并提供 trust/reject 操作。
- [x] 错误提示和输出复制：错误通过 InfoBar 展示，命令输出区提供复制按钮。

### Task 6：测试

- [x] Domain model 测试。
- [x] SQLite repository 测试。
- [x] Credential store 平台边界测试。
- [x] SQLite 凭据隔离测试：使用真实临时 SQLite 文件验证密码、私钥内容和 passphrase 不会写入业务库。
- [x] Host key trust 测试。
- [x] SSH 状态机测试：覆盖首次 host key trust、确认后 smoke test、mismatch 阻断和 reject。
- [x] Windows 添加私钥服务器 ViewModel 测试：覆盖私钥/passphrase 进入 Credential Store、profile 记录为 `PrivateKey`、SQLite 不保存私钥材料、空私钥拒绝。
- [x] Windows 编辑服务器测试：覆盖 profile 更新、保留/替换凭据、认证类型切换必须提供新凭据、host/port 变化清理旧 trusted host key、ViewModel 替换当前选中服务器。
- [x] Windows 服务器列表搜索和空状态测试：`MainWindowViewModelFiltersServerListAndKeepsWorkspaceSelection` 覆盖 name/host/username/group 搜索、无结果空状态，以及搜索过滤不会清空当前工作台选择。
- [x] GitHub Actions Windows core tests：Windows runner 运行 `scripts/ci-windows-core.ps1`，覆盖不依赖 WinUI/XAML 编译器的核心层。
- [x] 可选真实 SSH 集成测试：`RealWindowsSshSmokeTestWhenEnvironmentIsConfigured` 默认跳过，Windows 主机设置 `HHC_WINDOWS_TEST_SSH_REAL=1` 和 SSH 环境变量后会覆盖 Credential Manager、SSH.NET host key scan、trust、`printf hhc-ssh-ok`、删除清理。

### Task 7：手动验收

- [ ] Windows app 可启动。
- [ ] 添加服务器配置。
- [ ] 凭据不写入 SQLite：核心自动测试已覆盖真实 SQLite 文件；仍待 Windows 主机确认 Credential Manager 实际读写路径。
- [ ] 首次连接弹出 host key trust dialog。
- [ ] 确认后连接成功。
- [ ] smoke test 返回 `hhc-ssh-ok`。
- [ ] 主机指纹变化会阻断连接。
- [ ] 删除服务器后凭据清理。
- [ ] MSIX 或开发包可安装运行。

## 8. 完成标志

1. Windows 原生 app 骨架可运行。
2. WinUI 3 / Windows App SDK / .NET 技术栈验证通过。
3. 服务器 CRUD、凭据、host key trust 和真实 SSH MVP 可用。
4. Windows 凭据存储安全边界清晰。
5. 输出 Windows 后续追平计划。
6. 测试和手动验收通过。

## 9. 后续边界

- Windows 后续功能追平应按 macOS 已稳定的模块顺序推进。
- 若 WinUI 3 在终端控件、复杂表格或打包上阻塞明显，再评估 WPF Plan B。
