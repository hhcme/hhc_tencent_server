# Phase 1：项目骨架 + 真实 SSH 最小闭环实施计划

> 本计划替换早期“模拟 SSH 连接”的版本。Phase 1 的交付标准是：应用可以安全保存一台服务器配置，验证主机指纹，使用密码或受支持的私钥真实连接远程服务器，并执行一条远程命令。

**设计文档:** `docs/superpowers/specs/2026-06-25-server-manager-design.md`

**本地设计快照:** `docs/assets/design/macos-mvp-v0.2/README.md`

**当前开发入口:** 先实现 macOS 原生 Phase 1。启动页采用“服务器列表优先”的结构；点击服务器后进入单服务器工作台；在工作台顶部通过服务器切换器切换当前操作对象。

---

## 1. 目标

Phase 1 完成后，项目应具备：

1. 一个可运行的 macOS 14+ SwiftUI 应用骨架。
2. 服务器配置 CRUD，持久化到 SQLite/GRDB。
3. SSH 凭据写入 macOS Keychain，不把密码或私钥明文写入 SQLite。
4. App Sandbox 所需 entitlements 配置完整。
5. 真实 SSH 连接闭环：TCP connect -> SSH handshake -> host key trust -> user auth -> exec command -> disconnect。
6. 启动服务器列表、添加服务器 sheet、单服务器工作台、服务器切换器、主机指纹确认 sheet、连接/断开按钮和命令 smoke test 输出。
7. 单元测试覆盖模型、Repository、Keychain wrapper、服务层状态机；可选真实 SSH 集成测试通过环境变量启用。

## 2. 非目标

Phase 1 不实现以下能力：

- 完整 PTY 终端。
- SFTP 文件管理器。
- Dashboard 监控图表。
- 云厂商 API 接入、实例发现、云监控和安全组管理。
- systemd/Nginx/firewall/Cron 管理。
- GitLab 部署、Webhook 服务、回滚。
- Verdaccio/unpub 一键安装。
- SSH agent、keyboard-interactive、多跳代理、端口转发。

这些能力要等真实 SSH 基础层稳定后再进入后续 Phase。

## 3. 技术约束

| 项 | 选择 |
|----|------|
| 项目类型 | Xcode macOS App project |
| 语言 | Swift 6.1+ |
| UI | SwiftUI + Observation |
| SSH | SwiftNIO SSH 0.13.x |
| DB | GRDB 7.x + SQLite |
| 凭据 | macOS Keychain |
| 最低系统 | macOS 14 |

依赖版本不要写成“从 0.9.0 起 Up to Next Major”。SwiftNIO SSH 不同小版本对应不同 Swift 最低版本，Phase 1 应选择当前工具链可编译的明确区间，例如：

```swift
.package(url: "https://github.com/apple/swift-nio-ssh.git", .upToNextMinor(from: "0.13.0")),
.package(url: "https://github.com/groue/GRDB.swift.git", from: "7.0.0")
```

同时提交 `Package.resolved`，避免后续开发机解析到不一致的版本。

## 4. 文件结构

使用标准 Xcode App project，不混用 Swift Package 的 `Sources/` 根目录。建议结构：

```text
HHCServerManager/
├── HHCServerManager.xcodeproj
├── HHCServerManager/
│   ├── App/
│   │   ├── HHCServerManagerApp.swift
│   │   └── AppState.swift
│   ├── Models/
│   │   ├── ServerProfile.swift
│   │   ├── TrustedHostKey.swift
│   │   └── CommandResult.swift
│   ├── Services/
│   │   ├── SSH/
│   │   │   ├── SSHClient.swift
│   │   │   ├── SSHConnection.swift
│   │   │   ├── SSHConnectionState.swift
│   │   │   ├── SSHError.swift
│   │   │   ├── HostKeyTrustStore.swift
│   │   │   └── NIOSSHAdapters.swift
│   │   ├── Storage/
│   │   │   ├── AppDatabase.swift
│   │   │   ├── ServerRepository.swift
│   │   │   └── KeychainService.swift
│   │   └── ServerManagementService.swift
│   ├── ViewModels/
│   │   ├── ServerBrowserViewModel.swift
│   │   ├── AddServerViewModel.swift
│   │   ├── ServerWorkspaceViewModel.swift
│   │   └── ServerSwitcherViewModel.swift
│   ├── Views/
│   │   ├── ContentView.swift
│   │   ├── ServerBrowser/
│   │   │   ├── ServerBrowserView.swift
│   │   │   ├── ServerRowView.swift
│   │   │   ├── ServerSummaryPanel.swift
│   │   │   └── EmptyServerListView.swift
│   │   ├── ServerWorkspace/
│   │   │   ├── ServerWorkspaceView.swift
│   │   │   ├── ServerWorkspaceSidebar.swift
│   │   │   ├── ServerOverviewView.swift
│   │   │   ├── SmokeTestOutputView.swift
│   │   │   └── ServerSwitcherPopover.swift
│   │   └── Sheets/
│   │       ├── AddServerSheet.swift
│   │       └── HostKeyTrustSheet.swift
│   └── Utilities/
│       └── Constants.swift
└── HHCServerManagerTests/
    ├── Models/
    ├── Services/
    └── Integration/
```

## 5. Entitlements

在 Signing & Capabilities 中配置：

- App Sandbox: Enabled
- Outgoing Connections (Client): Enabled
- Keychain Sharing: Enabled，access group 使用应用 bundle/team 对应值
- User Selected File Read Only: 如果支持从本地选择私钥文件，必须启用

Phase 1 推荐在用户选择私钥后立即读取私钥内容并写入 Keychain。这样连接时不依赖原文件路径，也减少 security-scoped bookmark 的复杂度。若产品上必须引用文件路径，则要保存 bookmark 并实现重新授权流程。

## 6. 数据模型

### 6.1 ServerProfile

```swift
enum SSHAuthType: String, Codable, CaseIterable {
    case password
    case privateKey
}

struct ServerProfile: Identifiable, Codable, Equatable, Hashable {
    var id: UUID
    var name: String
    var host: String
    var port: Int
    var username: String
    var authType: SSHAuthType
    var keychainRef: String
    var groupName: String?
    var createdAt: Date
    var updatedAt: Date
}
```

`keychainRef` 必须是非空逻辑引用，例如 `server_<uuid>`，由 `KeychainService` 拼接出具体 account key。不要把密码、私钥内容、私钥文件路径写进 `ServerProfile`。

### 6.2 TrustedHostKey

```swift
struct TrustedHostKey: Identifiable, Codable, Equatable, Hashable {
    var id: UUID
    var serverId: UUID
    var host: String
    var port: Int
    var algorithm: String
    var fingerprintSHA256: String
    var rawPublicKey: String?
    var trustedAt: Date
}
```

### 6.3 SQLite schema

```sql
CREATE TABLE server_profiles (
    id TEXT PRIMARY KEY NOT NULL,
    name TEXT NOT NULL,
    host TEXT NOT NULL,
    port INTEGER NOT NULL DEFAULT 22,
    username TEXT NOT NULL,
    auth_type TEXT NOT NULL,
    keychain_ref TEXT NOT NULL,
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
    trusted_at DATETIME NOT NULL,
    UNIQUE(server_id, algorithm, fingerprint_sha256)
);
```

GRDB migration 必须启用 foreign keys，并保证删除服务器时对应 host key 记录一并删除。

## 7. 凭据模型

UI 表单中的凭据只保存在内存里：

```swift
enum CredentialInput: Equatable {
    case password(String)
    case privateKey(data: Data, passphrase: String?)
}
```

Keychain 存储建议：

| Key | Value |
|-----|-------|
| `ssh_password_<keychainRef>` | UTF-8 password |
| `ssh_private_key_<keychainRef>` | private key bytes |
| `ssh_private_key_passphrase_<keychainRef>` | optional passphrase |

保存服务器时应由 `ServerManagementService` 统一编排：

1. 生成 `ServerProfile.id` 和 `keychainRef`。
2. 写入 Keychain。
3. 写入 SQLite。
4. 如果 SQLite 写入失败，删除刚写入的 Keychain 项。
5. 如果 Keychain 写入失败，不创建数据库记录。

删除服务器时顺序相反：

1. 断开 SSH 连接。
2. 删除数据库记录。
3. 删除 Keychain 项。
4. 若 Keychain 删除失败，记录本地日志并在下次启动做清理，不阻塞 UI。

## 8. SSH 架构

### 8.1 服务边界

```swift
protocol SSHClientProtocol: Sendable {
    func connect(profile: ServerProfile, credential: CredentialInput) async throws
    func execute(_ command: String, timeout: Duration) async throws -> CommandResult
    func disconnect() async
}
```

`SSHClientProtocol` 是 ViewModel 和业务层看到的接口。SwiftNIO 的 `Channel`、`EventLoopGroup`、delegate 类型留在 `Services/SSH` 内部。

### 8.2 SSHManager

`SSHManager` 使用 `actor`：

```swift
actor SSHManager {
    func connection(for profile: ServerProfile) async -> SSHClientProtocol
    func connect(profile: ServerProfile, credential: CredentialInput) async throws
    func execute(serverId: UUID, command: String, timeout: Duration) async throws -> CommandResult
    func disconnect(serverId: UUID) async
    func disconnectAll() async
}
```

不要使用 `DispatchQueue.sync` + async barrier 混合管理连接池；它容易在并发点击时创建多个连接。

### 8.3 真实连接要求

`SSHConnection.connect` 必须做真实网络连接，禁止用 sleep 或固定状态模拟成功。

实现要点：

1. 使用 `ClientBootstrap` 建立 TCP 连接。
2. 安装 `NIOSSHHandler`。
3. 实现 `NIOSSHClientServerAuthenticationDelegate` 做主机公钥验证。
4. 实现 `NIOSSHClientUserAuthenticationDelegate` 做密码或私钥认证。
5. 认证成功后打开 session child channel。
6. 通过 `SSHChannelRequestEvent.ExecRequest` 执行 smoke test 命令。
7. 收集 stdout、stderr、exit status。
8. 关闭 child channel，不关闭底层 SSH 连接，除非用户断开。

Phase 1 smoke test 命令：

```sh
printf hhc-ssh-ok
```

验收条件：返回 `exitCode == 0` 且 stdout 包含 `hhc-ssh-ok`。

### 8.4 私钥支持边界

Phase 1 必须支持密码认证。私钥认证至少支持一种经过真实测试的 key 格式，并在 UI 中明确错误提示。

建议验收矩阵：

| 类型 | Phase 1 要求 |
|------|--------------|
| password | 必须支持 |
| unencrypted Ed25519 private key | 必须支持或在技术验证后改为 P0 阻塞项 |
| passphrase-protected OpenSSH private key | 可选；如果 SwiftNIO/SwiftCrypto 路径不支持，先标记为后续能力 |
| ssh-agent | 不做 |
| keyboard-interactive | 不做 |

如果私钥解析失败，错误文案要说明“当前版本不支持该私钥格式或加密方式”，而不是笼统显示认证失败。

## 9. 主机指纹信任流程

首次连接：

1. SSH server authentication delegate 收到主机公钥。
2. 计算 SHA256 指纹，格式类似 `SHA256:...`。
3. 查询 `trusted_host_keys`。
4. 未找到记录时，连接状态进入 `awaitingHostTrust`。
5. UI 弹出 `HostKeyTrustSheet`，展示 host、port、algorithm、fingerprint。
6. 用户确认后写入 `trusted_host_keys`，继续认证。
7. 用户拒绝则断开连接并返回错误。

后续连接：

1. 找到同 server/host/port 的指纹。
2. 完全匹配则继续。
3. 不匹配则进入 `hostKeyChanged` 错误状态。
4. 不允许静默覆盖；必须展示旧指纹和新指纹。

Phase 1 可以先不实现 known_hosts 导入，但数据模型要能支持后续扩展。

## 10. AppState 与 ViewModel

`AppState` 标记为 `@MainActor @Observable`：

```swift
@MainActor
@Observable
final class AppState {
    var selectedServerId: UUID?
    var servers: [ServerProfile] = []
    var connectionStates: [UUID: SSHConnectionState] = [:]
}
```

业务操作放到服务层：

- `ServerRepository`: 只负责 SQLite。
- `KeychainService`: 只负责 Keychain。
- `ServerManagementService`: 编排保存/更新/删除服务器和凭据。
- `SSHManager`: 管理连接池和 SSH 操作。

ViewModel 不直接写 Keychain，不直接打开 NIO channel。

## 11. UI 范围

Phase 1 UI 必须以仓库内设计快照为实现参考：`docs/assets/design/macos-mvp-v0.2/README.md`。

### 11.1 启动服务器列表

- 应用启动后首先展示服务器列表，而不是直接进入某台服务器详情。
- 左侧 source list 展示 All Servers、Favorites、Recently Used、Groups、Cloud/Manual SSH 等分类。
- 主区域展示服务器表格或列表：名称、host、group、连接状态、云资源来源、最近使用时间。
- 选中服务器时展示底部或右侧摘要：名称、分组、host、连接状态和主要操作。
- `Open` 进入单服务器工作台；`Connect` 可以在列表页触发连接，但连接状态仍归属该服务器。
- 支持搜索、分组筛选、删除服务器并带确认弹窗。
- 连接状态点至少覆盖：disconnected / connecting / awaitingTrust / connected / failed。

### 11.2 单服务器工作台

- 打开服务器后进入专用工作台，不在启动页混合展示所有操作。
- 顶部 toolbar 包含返回服务器列表、当前服务器名称、服务器切换器、Run/Files/Logs/More 等入口。
- 左侧工作台导航只展示当前服务器的功能分类：Overview、Terminal、Files、Services、Processes、Logs、Configuration、Cloud。
- Phase 1 只实现 Overview 中的基础信息、连接状态、Connect / Disconnect、Smoke Test 和输出区域。
- Terminal、Files、Services、Processes、Logs、Configuration、Cloud 可以显示 disabled/coming later 状态，但不能宣称已完成。
- 服务器切换器弹窗展示可切换服务器列表、搜索框和当前服务器标记；切换后更新工作台上下文，不重新回到启动页。

### 11.3 添加服务器

字段：

- 名称
- Host
- Port
- Username
- Group
- Auth type: password / private key
- Password 或 private key picker
- Private key passphrase（可选）

行为：

- “保存”只保存配置和凭据。
- “测试并保存”先创建临时待保存记录，执行真实连接 smoke test；成功后保留记录，失败时回滚 DB 和 Keychain，除非用户选择“仍然保存”。
- 首次主机指纹需要弹窗确认，确认后的 trust 记录必须和待保存 server id 绑定。
- 表单校验 port 范围为 `1...65535`。
- Host 不能为空；保留域名、IPv4、IPv6 的输入空间，不做过度正则限制。

### 11.4 主机指纹确认

- 首次连接未知主机时以 sheet 形式展示 host、port、algorithm、SHA256 fingerprint。
- 用户点击 Trust 才写入 `trusted_host_keys` 并继续连接。
- 用户点击 Reject 必须断开连接，并将状态恢复到可理解的失败状态。
- 指纹变更时使用阻断式警告，不允许继续执行命令。

## 12. 实施任务

### Task 1: 初始化项目

- [ ] 创建 Xcode macOS SwiftUI App。
- [ ] 设置 bundle id、minimum deployment macOS 14。
- [ ] 配置 App Sandbox、Outgoing Connections、Keychain Sharing、User Selected File Read Only。
- [ ] 添加 SwiftNIO SSH 和 GRDB 依赖，并提交 `Package.resolved`。
- [ ] 建立目录结构。
- [ ] 初始化 Git 仓库。

验收：

- [ ] `Cmd + R` 能启动空应用。
- [ ] target entitlements 中能看到 outgoing network 和 keychain 配置。

### Task 2: 模型与数据库

- [ ] 实现 `ServerProfile`、`TrustedHostKey`、`CommandResult`。
- [ ] 实现 `AppDatabase` 和 GRDB migrations。
- [ ] 实现 `ServerRepository`。
- [ ] 实现 `TrustedHostKeyRepository` 或并入 `HostKeyTrustStore`。
- [ ] 写单元测试覆盖 insert/update/delete/fetch/cascade delete。

验收：

- [ ] 内存数据库测试通过。
- [ ] 删除 server 后，对应 trusted host key 被删除。
- [ ] `auth_type`、日期、UUID 编解码稳定。

### Task 3: KeychainService

- [ ] 实现 password/private key/passphrase 的 save/read/delete。
- [ ] 支持自定义 service name，方便测试隔离。
- [ ] 所有 Keychain 操作返回明确错误类型。
- [ ] 写单元测试，使用测试专用 service name。

验收：

- [ ] 保存、读取、覆盖、删除 password 成功。
- [ ] 保存、读取、删除 private key data 成功。
- [ ] 删除不存在项不视为失败。
- [ ] 测试结束清理 Keychain 项。

### Task 4: ServerManagementService

- [ ] 定义 `CredentialInput`。
- [ ] 实现 add/update/delete server 的编排。
- [x] DB 写入失败时清理 Keychain：`ServerManagementServiceTests.testCreateServerRemovesNewCredentialWhenDatabaseWriteFails` 用固定 server UUID 和真实 SQLite 失败路径验证新写入凭据会被删除。
- [x] Keychain 写入失败时不落库：`ServerManagementServiceTests.testCreateServerDoesNotPersistProfileWhenKeychainWriteFails` 通过失败的 `ServerCredentialStore` 验证 repository 仍为空。
- [x] 写单元测试覆盖失败补偿：已覆盖 SQLite 写入失败后的 Keychain 清理，以及 Keychain 写入失败后的不落库行为。

验收：

- [x] 不会出现“有 DB 记录但没有凭据”的新建成功状态：Keychain 写入失败回归测试验证不会创建 server profile。
- [x] 不会因为 DB 失败留下孤儿 Keychain 凭据：固定 keychainRef 的回归测试验证失败后 `readPassword` 返回 nil。

### Task 5: HostKeyTrustStore

- [ ] 实现 fingerprint 计算。
- [ ] 实现 trust 查询、保存、匹配、冲突错误。
- [ ] 定义 `HostKeyTrustDecision`：trust / reject。
- [ ] 为 SSH delegate 提供 async 等待用户决策的接口。
- [ ] 写单元测试覆盖首次信任、匹配、变更。

验收：

- [ ] 首次未知指纹返回 awaiting trust。
- [ ] 已信任指纹自动通过。
- [ ] 指纹变更返回阻断错误。

### Task 6: 真实 SSHConnection

- [ ] 使用 SwiftNIO SSH 建立真实连接。
- [ ] 实现 server authentication delegate。
- [ ] 实现 user authentication delegate。
- [ ] 实现 password 认证。
- [ ] 实现至少一种私钥认证路径，或将私钥解析列为明确阻塞项并保留 UI disable。
- [ ] 实现 `execute(command:timeout:)`。
- [ ] 实现 disconnect 和 event loop graceful shutdown。
- [ ] 所有状态更新回到主线程可观察状态。

验收：

- [ ] 不能存在 sleep 后直接 connected 的代码。
- [ ] 认证失败时显示 authentication failed。
- [ ] 主机不可达时显示 connection failed/timeout。
- [ ] 执行 `printf hhc-ssh-ok` 返回正确 stdout 和 exit code。
- [ ] disconnect 后连接状态变为 disconnected。

### Task 7: AppState 与 ViewModels

- [ ] `AppState` 使用 `@MainActor @Observable`。
- [ ] `ServerBrowserViewModel` 加载、搜索、筛选、删除服务器。
- [ ] `AddServerViewModel` 做表单验证，不直接写 Keychain。
- [ ] `ServerWorkspaceViewModel` 处理当前服务器上下文、connect/disconnect/smoke test。
- [ ] `ServerSwitcherViewModel` 处理工作台内服务器切换。
- [ ] 所有异步操作有 loading/error 状态。

验收：

- [ ] UI 状态更新没有跨线程警告。
- [x] 连接中重复点击不会创建重复连接：`ServerWorkspaceViewModel.connect` 会在 connecting 或 smoke test 运行中忽略重复触发，并有 ViewModel 回归测试覆盖。
- [x] 删除当前选中服务器会清空 selection 并断开连接：`AppState` 测试覆盖删除选中服务器后清空 selection、移除连接状态、删除 DB 记录和 Keychain 凭据。
- [x] 在工作台内切换服务器不会复用上一台服务器的连接状态或 smoke test 输出：`ServerWorkspaceViewModel.configure(profile:initialState:)` 在服务器上下文变化时清理命令输出、历史、错误和文件等服务器绑定状态，并有回归测试覆盖。

### Task 8: SwiftUI 界面

- [ ] 主窗口采用 macOS 原生 split/toolbar 结构。
- [ ] 启动服务器列表页。
- [ ] 服务器摘要面板和 Open/Connect 操作。
- [ ] 单服务器工作台。
- [ ] 工作台顶部服务器切换器和 popover。
- [ ] 添加服务器 sheet。
- [ ] 主机指纹确认 sheet。
- [ ] Overview 中的连接控制和 smoke test 输出。
- [ ] 删除确认弹窗。

验收：

- [ ] 空状态清晰。
- [ ] 首屏是服务器列表，不是单服务器详情。
- [ ] 点击 Open 后进入该服务器工作台。
- [ ] 工作台内可以通过服务器切换器切换服务器。
- [ ] 表单校验准确。
- [ ] 首次连接出现指纹确认。
- [ ] 指纹变更出现阻断警告。
- [ ] Smoke test 输出可复制。

### Task 9: 测试

- [x] 模型测试：核心模型的编解码、风险模型和状态模型已通过 repository/service/view model 测试间接覆盖。
- [x] Repository 测试：`ServerRepositoryTests` 覆盖 server、trusted host key、command history、dashboard snapshot、transfer jobs 和级联删除。
- [x] Keychain 测试：`KeychainServiceTests` 覆盖 password、private key、cloud credential 和 webhook secret 的保存、覆盖、读取、删除。
- [x] ServerManagementService 补偿逻辑测试：`ServerManagementServiceTests` 覆盖服务器创建/更新/删除、凭据清理和云账号凭据生命周期。
- [x] HostKeyTrustStore 测试：`HostKeyTrustStoreTests` 覆盖首次未知指纹、已信任匹配和指纹变化阻断。
- [x] SSH 状态机测试：`ServerWorkspaceViewModelTests` 覆盖连接成功、连接失败、未知 host key 等待/拒绝、重复连接防抖和断开连接状态。
- [ ] 可选真实 SSH 集成测试。

真实 SSH 集成测试通过环境变量启用：

```sh
HHC_TEST_SSH_HOST=127.0.0.1
HHC_TEST_SSH_PORT=22
HHC_TEST_SSH_USER=tester
HHC_TEST_SSH_PASSWORD=...
```

没有这些环境变量时跳过集成测试，不让 CI 失败。

### Task 10: 手动验收

- [ ] 首次启动为空列表。
- [ ] 添加密码认证服务器。
- [ ] 服务器出现在启动服务器列表中。
- [ ] 点击 Open 进入该服务器工作台。
- [ ] 工作台内服务器切换器能列出服务器并切换当前上下文。
- [ ] 首次连接展示主机指纹确认。
- [ ] 确认后连接成功。
- [ ] Smoke test 返回 `hhc-ssh-ok`。
- [ ] 断开连接成功。
- [ ] 重启应用后服务器配置仍在。
- [ ] 第二次连接不再询问相同主机指纹。
- [ ] 修改远端 host key 或模拟不同 fingerprint 时阻断连接。
- [ ] 删除服务器后 DB 记录、trusted host key、Keychain 凭据被清理。

## 13. 完成标志

Phase 1 只有在以下条件都满足时才算完成：

1. 应用可运行。
2. 服务器配置可持久化。
3. 凭据只在 Keychain。
4. 主机指纹首次确认、后续校验。
5. 至少密码认证能真实连接服务器。
6. `printf hhc-ssh-ok` 真实远程执行成功。
7. 断开连接释放 NIO channel 和 event loop。
8. 单元测试通过。
9. 手动验收清单通过。
10. UI 符合本地设计快照中的“服务器列表 -> 单服务器工作台 -> 服务器切换器”结构。

## 14. 后续 Phase 边界

- **Phase 2:** 云厂商基础层 + 简化命令面板。加入 CloudProviderAdapter、云账号设置、腾讯云只读实例发现；命令面板复用 Phase 1 的 `execute`，不要引入 PTY。
- **Phase 3:** Dashboard + SFTP 技术验证 + 文件管理器。Dashboard 聚合 SSH 指标和云监控指标；先证明 SFTP 库/协议方案可用。
- **Phase 4:** 安全组 + 环境配置。云安全组走 provider adapter，系统内部配置基于远端能力探测。
- **Phase 5:** GitLab 部署。先做手动部署日志，再做 webhook。
- **Phase 6:** 私有包仓库。Verdaccio/unpub 安装前做版本和系统依赖检测。
- **Phase 7:** 更多云厂商、高级云资源管理、快照、云盘和计费信息。
- **Phase 8:** Windows 原生版技术验证。WinUI 3 + Windows App SDK + .NET/C#，先复刻真实 SSH MVP。
