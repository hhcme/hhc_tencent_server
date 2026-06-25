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
├── App/
│   ├── App.xaml
│   └── MainWindow.xaml
├── Presentation/
│   ├── Views/
│   ├── ViewModels/
│   └── Controls/
├── Application/
│   ├── ServerManagement/
│   ├── SSH/
│   └── Settings/
├── Domain/
│   ├── Servers/
│   ├── SSH/
│   └── Security/
├── Infrastructure/
│   ├── Storage/
│   ├── Credentials/
│   └── SSH/
└── Tests/
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

- [ ] 验证当前 WinUI 3 + Windows App SDK stable 项目模板。
- [ ] 验证 .NET 版本和 MSIX 打包。
- [ ] 验证 SQLite 方案。
- [ ] 验证 Credential Manager / DPAPI 凭据保存。
- [ ] 验证 SSH.NET 对密码、私钥、host key verification 的支持。

### Task 2：项目骨架

- [ ] 创建 solution 和项目结构。
- [ ] 建立 MVVM 基础。
- [ ] 建立依赖注入。
- [ ] 添加日志和错误处理基础。

### Task 3：存储和凭据

- [ ] 实现 server profile repository。
- [ ] 实现 trusted host key store。
- [ ] 实现 credential store。
- [ ] 删除服务器时清理 trusted host key 和凭据。

### Task 4：SSH MVP

- [ ] 实现连接状态机。
- [ ] 实现 host key 首次确认。
- [ ] 实现 host key mismatch 阻断。
- [ ] 实现密码认证。
- [ ] 验证私钥认证。
- [ ] 执行 `printf hhc-ssh-ok`。

### Task 5：Windows UI

- [ ] 服务器列表。
- [ ] 添加服务器 dialog。
- [ ] 单服务器工作台。
- [ ] 服务器切换器。
- [ ] Host key trust dialog。
- [ ] 错误提示和输出复制。

### Task 6：测试

- [ ] Domain model 测试。
- [ ] SQLite repository 测试。
- [ ] Credential store 测试。
- [ ] Host key trust 测试。
- [ ] SSH 状态机测试。
- [ ] 可选真实 SSH 集成测试。

### Task 7：手动验收

- [ ] Windows app 可启动。
- [ ] 添加服务器配置。
- [ ] 凭据不写入 SQLite。
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
