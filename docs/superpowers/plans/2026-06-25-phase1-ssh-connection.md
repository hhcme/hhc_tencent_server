# Phase 1：项目骨架 + 真实 SSH 最小闭环实施计划

> 本计划替换早期“模拟 SSH 连接”的版本。Phase 1 的交付标准是：应用可以安全保存一台服务器配置，验证主机指纹，使用密码或受支持的私钥真实连接远程服务器，并执行一条远程命令。

**设计文档:** `docs/superpowers/specs/2026-06-25-server-manager-design.md`

**本地设计快照:** `docs/assets/design/macos-mvp-v0.2/README.md`

**当前开发入口:** 先实现 macOS 原生 Phase 1。启动页采用“服务器列表优先”的结构；点击服务器后进入单服务器工作台；在工作台顶部通过服务器切换器切换当前操作对象。

---

## 1. 目标

Phase 1 完成后，项目应具备：

1. 一个可运行的 macOS 14+ SwiftUI 应用骨架。
2. 服务器配置 CRUD，持久化到 SQLite。
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
| UI | SwiftUI + `ObservableObject` / `@Published` |
| SSH | macOS OpenSSH toolchain (`ssh`, `ssh-keyscan`, `ssh-keygen`, `sftp`, optional `rsync`) |
| DB | SQLite C API |
| 凭据 | macOS Keychain |
| 最低系统 | macOS 14 |

实现备注：早期计划建议 SwiftNIO SSH + GRDB。当前 Phase 1 已转向 OpenSSH 子进程后端和 SQLite C API，以便优先完成真实 SSH 闭环、SFTP/rsync 文件传输和系统工具兼容性。SwiftNIO SSH 或 libssh2 可作为后续替换评估，不再是 Phase 1 阻塞依赖。

如果后续重新引入 Swift Package 依赖，版本不要写成“从 0.9.0 起 Up to Next Major”。SwiftNIO SSH 不同小版本对应不同 Swift 最低版本，应选择当前工具链可编译的明确区间，例如：

```swift
.package(url: "https://github.com/apple/swift-nio-ssh.git", .upToNextMinor(from: "0.13.0")),
.package(url: "https://github.com/groue/GRDB.swift.git", from: "7.0.0")
```

同时提交 `Package.resolved`，避免后续开发机解析到不一致的版本。当前实现没有 Swift Package 依赖，因此没有 `Package.resolved`。

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
│   │   │   ├── OpenSSHClient.swift
│   │   │   └── HostKeyTrustStore.swift
│   │   ├── Storage/
│   │   │   ├── AppDatabase.swift
│   │   │   ├── ServerRepository.swift
│   │   │   └── KeychainService.swift
│   │   └── ServerManagementService.swift
│   ├── ViewModels/
│   │   ├── ServerBrowserViewModel.swift
│   │   ├── AddServerViewModel.swift
│   │   └── ServerWorkspaceViewModel.swift
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
- Keychain Sharing: 当前未启用；应用使用默认 Keychain item 访问，不使用共享 access group
- User Selected File Read/Write: 当前启用，用于选择/读取本地私钥等用户授权文件

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

SQLite migration 必须启用 foreign keys，并保证删除服务器时对应 host key 记录一并删除。

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

`SSHClientProtocol` 是 ViewModel 和业务层看到的接口。当前实现中的 OpenSSH 进程、临时私钥文件、askpass 脚本和 known_hosts 文件细节留在 `Services/SSH` 内部。

### 8.2 OpenSSHClient

`OpenSSHClient` 实现 `SSHClient` 协议：

```swift
protocol SSHClient: Sendable {
    func runSmokeTest(profile: ServerProfile) async throws -> CommandResult
    func execute(_ command: String, profile: ServerProfile) async throws -> CommandResult
    func trustHostKey(_ hostKeyInfo: HostKeyInfo, for profile: ServerProfile) throws
}
```

当前 Phase 1 是按命令启动 OpenSSH 进程的连接模型，不维护长期 SSH channel pool。并发防抖由 `ServerWorkspaceViewModel` 负责，避免重复点击创建重复 smoke test 或命令任务。

### 8.3 真实连接要求

SSH 后端必须做真实网络连接，禁止用 sleep 或固定状态模拟成功。

当前 OpenSSH 后端实现要点：

1. 使用 `ssh-keyscan` 读取 host key，并用 `ssh-keygen -l -f` 计算 SHA256 指纹。
2. 使用 `HostKeyTrustStore` 查询应用内 trust 记录。
3. 未知或变更的指纹由 ViewModel 进入等待用户确认/阻断状态。
4. 将已信任 host key 写入应用管理的 user-level known_hosts 文件。
5. 通过 Keychain 读取密码或私钥，并生成临时 askpass/identity 文件。
6. 使用 `/usr/bin/ssh` 执行 smoke test 或用户命令。
7. 收集 stdout、stderr、exit status。
8. 命令结束后清理临时文件；工作台断开连接时重置 UI 连接状态。

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

`AppState` 标记为 `@MainActor` 并使用 `ObservableObject`：

```swift
@MainActor
final class AppState: ObservableObject {
    @Published var selectedServerId: UUID?
    @Published var servers: [ServerProfile] = []
    @Published var connectionStates: [UUID: SSHConnectionState] = [:]
}
```

业务操作放到服务层：

- `ServerRepository`: 只负责 SQLite。
- `KeychainService`: 只负责 Keychain。
- `ServerManagementService`: 编排保存/更新/删除服务器和凭据。
- `OpenSSHClient`: 管理 host key 校验、认证上下文、命令执行和文件传输。

ViewModel 不直接写 Keychain，不直接管理 OpenSSH 进程细节。

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

- [x] 创建 Xcode macOS SwiftUI App：`HHCServerManager.xcodeproj` 和 app target 已存在。
- [x] 设置 bundle id、minimum deployment macOS 14：项目配置已可通过 `xcodebuild` 构建测试。
- [x] 配置 App Sandbox、Outgoing Connections、User Selected File Read/Write：`HHCServerManager.entitlements` 已启用 sandbox、network client 和用户选择文件读写。
- [x] 记录依赖技术转向：当前 Phase 1 不引入 SwiftNIO SSH/GRDB，使用 OpenSSH toolchain + SQLite C API；因此无 `Package.resolved`。
- [x] 建立目录结构：App、Models、Services、ViewModels、Views、Resources、Tests 已按 macOS app 组织。
- [x] 初始化 Git 仓库：本地仓库已连接 `origin/main` 并持续推送。

验收：

- [x] `xcodebuild`/`scripts/ci.sh` 能构建并运行 app-hosted test host。
- [x] target entitlements 中能看到 outgoing network 和 sandbox 配置。
- [x] 手工 `Cmd + R` 启动应用并观察首屏：已用 `xcodebuild ... ENABLE_DEBUG_DYLIB=NO build` 构建后通过 LaunchServices 启动，并用 CoreGraphics 窗口列表确认主窗口 `kCGWindowIsOnscreen = 1`。

### Task 2: 模型与数据库

- [x] 实现 `ServerProfile`、`TrustedHostKey`、`CommandResult`。
- [x] 实现 `AppDatabase` 和 SQLite C API migrations。
- [x] 实现 `ServerRepository`。
- [x] 实现 trusted host key 持久化，并通过 `HostKeyTrustStore` 封装信任评估。
- [x] 写单元测试覆盖 insert/update/delete/fetch/cascade delete。

验收：

- [x] 内存数据库测试通过。
- [x] 删除 server 后，对应 trusted host key 被删除。
- [x] `auth_type`、日期、UUID 编解码稳定。

### Task 3: KeychainService

- [x] 实现 password/private key/passphrase 的 save/read/delete：`KeychainService` 分账号保存密码、私钥、私钥口令，并在私钥口令为空时清理旧口令。
- [x] 支持自定义 service name，方便测试隔离：`KeychainService(serviceName:)` 支持测试专用 service name。
- [x] 所有 Keychain 操作返回明确错误类型：读取缺失项返回 `nil`，非预期 Security status 抛出 `KeychainError.unexpectedStatus`。
- [x] 写单元测试，使用测试专用 service name：`KeychainServiceTests` 每个测试使用 UUID service name 并在 tearDown 清理凭据。

验收：

- [x] 保存、读取、覆盖、删除 password 成功。
- [x] 保存、读取、删除 private key data 成功。
- [x] 保存、读取、清空、删除 private key passphrase 成功。
- [x] 删除不存在项不视为失败。
- [x] 测试结束清理 Keychain 项。

### Task 4: ServerManagementService

- [x] 定义 `CredentialInput`：位于 `ServerProfile.swift`，支持 password 和 private key/passphrase。
- [x] 实现 add/update/delete server 的编排：`ServerManagementService` 统一处理创建、更新、删除和凭据生命周期，测试覆盖 keep/replace credential、删除 DB/HostKey/Keychain，以及 `AppState` 删除选中服务器状态清理。
- [x] DB 写入失败时清理/回滚 Keychain：`ServerManagementServiceTests.testCreateServerRemovesNewCredentialWhenDatabaseWriteFails` 验证创建失败清理新凭据，`testUpdateServerRestoresOriginalCredentialWhenDatabaseWriteFails` 验证更新失败恢复旧凭据。
- [x] Keychain 写入失败时不落库：`ServerManagementServiceTests.testCreateServerDoesNotPersistProfileWhenKeychainWriteFails` 通过失败的 `ServerCredentialStore` 验证 repository 仍为空。
- [x] 写单元测试覆盖失败补偿：已覆盖 SQLite 写入失败后的 Keychain 清理，以及 Keychain 写入失败后的不落库行为。

验收：

- [x] 不会出现“有 DB 记录但没有凭据”的新建成功状态：Keychain 写入失败回归测试验证不会创建 server profile。
- [x] 不会因为 DB 失败留下孤儿 Keychain 凭据：固定 keychainRef 的回归测试验证失败后 `readPassword` 返回 nil。

### Task 5: HostKeyTrustStore

- [x] 实现 fingerprint 计算：`OpenSSHClient` 使用 `ssh-keyscan` + `ssh-keygen` 得到 SHA256 指纹。
- [x] 实现 trust 查询、保存、匹配、冲突错误：`HostKeyTrustEvaluation` 覆盖 trusted/unknown/changed。
- [x] 实现用户 trust/reject 流程：ViewModel 通过 `pendingHostKey`、`trustPendingHostKey`、`rejectPendingHostKey` 表达决策；未单独定义 `HostKeyTrustDecision` 枚举。
- [x] 为 OpenSSH 后端提供等待用户决策的接口：未知 host key 抛出 `SSHClientError.unknownHostKey`，ViewModel 暂停当前动作，用户 trust 后重试原动作。
- [x] 写单元测试覆盖首次信任、匹配、变更。

验收：

- [x] 首次未知指纹返回 awaiting trust。
- [x] 已信任指纹自动通过。
- [x] 指纹变更返回阻断错误。

### Task 6: 真实 SSHConnection

- [x] 使用 macOS OpenSSH 后端建立真实连接：当前 Phase1 采用 `/usr/bin/ssh`、`ssh-keyscan`、`ssh-keygen` 和用户级 known_hosts 文件，SwiftNIO SSH 方案保留为后续替换评估。
- [x] 实现 server authentication：连接前扫描 host key，写入/校验应用内 known_hosts，未知和变更指纹由 `HostKeyTrustStore` 阻断。
- [x] 实现 user authentication：认证参数由 `OpenSSHClient.makeAuthContext` 从 Keychain 生成，并为临时私钥和 askpass 脚本设置文件权限。
- [x] 实现 password 认证：通过 `SSH_ASKPASS` 注入 Keychain 密码，并禁用公钥回退。
- [x] 实现私钥认证路径：支持无口令私钥的 BatchMode 路径，以及带 passphrase 私钥的 askpass 路径，同时禁用密码/键盘交互回退。
- [x] 实现 `execute(command:)`：命令通过 OpenSSH 执行并返回 stdout、stderr、exit code、duration。
- [x] 实现 disconnect 和进程资源清理：当前连接模型为按命令进程执行，命令结束后清理临时私钥/askpass 文件；工作台 disconnect 将状态重置为 disconnected。
- [x] 所有状态更新回到主线程可观察状态：`ServerWorkspaceViewModel` 为 `@MainActor`，异步回调通过 `MainActor.run` 写入 `@Published` 状态。

验收：

- [x] 不能存在 sleep 后直接 connected 的代码：连接状态只在 `sshClient.runSmokeTest` 成功后进入 connected；生产代码中的 `Task.sleep` 仅用于轮询/延迟刷新，不用于模拟连接成功。
- [x] 认证失败时显示失败信息：OpenSSH stderr 会通过 `SSHClientError.processFailed` 进入 ViewModel 错误状态。
- [x] 主机不可达时显示 connection failed/timeout：OpenSSH 失败信息会进入 ViewModel 错误状态。
- [x] 执行 `printf hhc-ssh-ok` 返回正确 stdout 和 exit code：真实 SSH 集成测试已覆盖。
- [x] disconnect 后连接状态变为 disconnected。

### Task 7: AppState 与 ViewModels

- [x] `AppState` 使用 `@MainActor ObservableObject`，当前项目未采用 Observation 宏。
- [x] `ServerBrowserViewModel` 加载、搜索、筛选、删除服务器，并扩展云账号/云资源入口。
- [x] `AddServerViewModel` 做表单验证，不直接写 Keychain。
- [x] `ServerWorkspaceViewModel` 处理当前服务器上下文、connect/disconnect/smoke test。
- [x] 工作台内服务器切换由 `ContentView`、`AppState.selectedServerId` 和 `ServerWorkspaceViewModel.configure(profile:initialState:)` 共同处理，未拆独立 `ServerSwitcherViewModel`。
- [x] 所有核心异步操作有 loading/error 状态。

验收：

- [x] UI 状态更新没有跨线程警告：ViewModel/AppState 均在 `@MainActor` 上更新 `@Published` 状态。
- [x] 连接中重复点击不会创建重复连接：`ServerWorkspaceViewModel.connect` 会在 connecting 或 smoke test 运行中忽略重复触发，并有 ViewModel 回归测试覆盖。
- [x] 删除当前选中服务器会清空 selection 并断开连接：`AppState` 测试覆盖删除选中服务器后清空 selection、移除连接状态、删除 DB 记录和 Keychain 凭据。
- [x] 在工作台内切换服务器不会复用上一台服务器的连接状态或 smoke test 输出：`ServerWorkspaceViewModel.configure(profile:initialState:)` 在服务器上下文变化时清理命令输出、历史、错误和文件等服务器绑定状态，并有回归测试覆盖。

### Task 8: SwiftUI 界面

- [x] 主窗口采用 macOS 原生 split/toolbar 结构。
- [x] 启动服务器列表页。
- [x] 服务器摘要面板和 Open/Connect 操作。
- [x] 单服务器工作台。
- [x] 工作台顶部服务器切换器和 popover。
- [x] 添加服务器 sheet。
- [x] 主机指纹确认 sheet。
- [x] Overview 中的连接控制和 smoke test 输出。
- [x] 删除确认弹窗。

验收：

- [x] 空状态清晰：`ServerBrowserViewModel.emptyState(for:links:)` 为首次启动无服务器、搜索无结果、手动来源为空和云来源为空提供明确标题、图标和描述；`AddServerViewModelTests.testServerBrowserEmptyStatesDescribeFirstRunSearchAndSourceFilters` 覆盖这些状态，`ServerBrowserView` 使用同一状态对象渲染 `ContentUnavailableView`。
- [x] 首屏是服务器列表，不是单服务器详情：`ContentView` 在没有 `selectedServer` 时显示 `ServerBrowserView`。
- [x] 点击 Open 后进入该服务器工作台：`ServerManagementServiceTests.testAppStateOpensClosesAndSwitchesWorkspaceSelection` 覆盖 `AppState.openWorkspace(for:)` 设置当前工作台服务器。
- [x] 工作台内可以通过服务器切换器切换服务器：`ServerManagementServiceTests.testAppStateOpensClosesAndSwitchesWorkspaceSelection` 覆盖从当前服务器切换到第二台服务器，并验证关闭工作台会清空选择。
- [x] 表单校验准确：`AddServerViewModelTests` 覆盖端口、主机、用户名、凭据等校验。
- [x] 首次连接出现指纹确认：ViewModel 测试覆盖 unknown host key -> `pendingHostKey`。
- [x] 指纹变更出现阻断警告：`HostKeyTrustStoreTests` 覆盖 changed 结果，OpenSSH 后端映射为阻断错误。
- [x] Smoke test 输出可复制：`CommandResultView` 提供 Copy 按钮，复制内容由 `CommandResult.clipboardText` 统一生成，包含命令、退出码、耗时、stdout 和 stderr；`ServerWorkspaceViewModelTests` 覆盖复制格式。

### Task 9: 测试

- [x] 模型测试：核心模型的编解码、风险模型和状态模型已通过 repository/service/view model 测试间接覆盖。
- [x] Repository 测试：`ServerRepositoryTests` 覆盖 server、trusted host key、command history、dashboard snapshot、transfer jobs 和级联删除。
- [x] Keychain 测试：`KeychainServiceTests` 覆盖 password、private key、cloud credential 和 webhook secret 的保存、覆盖、读取、删除。
- [x] ServerManagementService 补偿逻辑测试：`ServerManagementServiceTests` 覆盖服务器创建/更新/删除、凭据清理和云账号凭据生命周期。
- [x] AppState 入口和工作台切换测试：`ServerManagementServiceTests.testAppStateStartsWithEmptyServerListAndNoWorkspaceSelection` 覆盖首次启动空服务器列表和无选中工作台；`testAppStateOpensClosesAndSwitchesWorkspaceSelection` 覆盖添加服务器后列表可见、Open 进入工作台、工作台切换服务器和关闭工作台；`testAppStateReloadClearsWorkspaceSelectionWhenSelectedServerWasRemoved` 覆盖当前服务器被外部删除后 reload 清空工作台选择。
- [x] AppState 持久化重载测试：`ServerManagementServiceTests.testAppStateReloadsPersistedServerProfilesAfterDatabaseReopen` 使用临时 SQLite 文件创建服务器，重新打开数据库并创建新的 `AppState` 后验证服务器配置仍能恢复，凭据仍只从 Keychain 读取。
- [x] HostKeyTrustStore 测试：`HostKeyTrustStoreTests` 覆盖首次未知指纹、已信任匹配和指纹变化阻断。
- [x] SSH 状态机测试：`ServerWorkspaceViewModelTests` 覆盖连接成功、连接失败、未知 host key 等待/拒绝、重复连接防抖和断开连接状态。
- [x] 可选真实 SSH 集成测试：`SSHIntegrationTests.testRealPrivateKeySmokeTestWhenEnvironmentIsConfigured` 已使用真实腾讯云服务器验证 host key trust 和 `printf hhc-ssh-ok` smoke test；2026-06-26 已重新用当前代码验证通过。部署类真实集成测试需要额外设置 `HHC_TEST_DEPLOYMENT_REAL=1`，避免普通 CI 误改服务器。

真实 SSH 集成测试通过环境变量或本机测试配置文件启用：

```sh
HHC_TEST_SSH_HOST=127.0.0.1
HHC_TEST_SSH_PORT=22
HHC_TEST_SSH_USER=tester
HHC_TEST_SSH_PRIVATE_KEY=/path/to/private/key
HHC_TEST_SSH_PASSPHRASE=optional
```

没有这些环境变量或 `~/.hhc_tencent_server_test_env` 时跳过集成测试，不让 CI 失败。

### Task 10: 手动验收

- [x] 首次启动为空列表：`testAppStateStartsWithEmptyServerListAndNoWorkspaceSelection` 覆盖。
- [x] 添加密码认证服务器：`ServerManagementServiceTests.testCreateServerStoresProfileAndPasswordCredential` 覆盖密码认证 profile 持久化和密码写入 Keychain。
- [x] 服务器出现在启动服务器列表中：`testAppStateOpensClosesAndSwitchesWorkspaceSelection` 覆盖两台服务器 reload 后进入 `appState.servers`。
- [x] 点击 Open 进入该服务器工作台：`testAppStateOpensClosesAndSwitchesWorkspaceSelection` 覆盖。
- [x] 工作台内服务器切换器能列出服务器并切换当前上下文：`testAppStateOpensClosesAndSwitchesWorkspaceSelection` 覆盖工作台上下文切换；视觉 popover 仍建议随最终 UI 走查一起确认。
- [x] 首次连接展示主机指纹确认：`ServerWorkspaceViewModelTests.testUnknownHostKeyWaitsForTrustDecisionAndRejectDisconnects` 和 `HostKeyTrustStoreTests.testUnknownHostKeyRequiresTrustDecision` 覆盖 unknown host key 进入待确认状态。
- [x] 确认后连接成功：`ServerWorkspaceViewModelTests.testTrustPendingHostKeyResumesOriginalCommand` 覆盖确认 host key 后恢复原 smoke test；`testConnectSuccessUpdatesConnectionStateAndStoresResult` 覆盖连接成功状态。
- [x] Smoke test 返回 `hhc-ssh-ok`：`SSHIntegrationTests.testRealPrivateKeySmokeTestWhenEnvironmentIsConfigured` 已在真实服务器上验证 `printf hhc-ssh-ok`；无真实环境时默认跳过。
- [x] 断开连接成功：`ServerWorkspaceViewModelTests.testDisconnectClearsTransientErrorAndState` 覆盖断开后状态回到 disconnected 并清理瞬态错误。
- [x] 重启应用后服务器配置仍在：`testAppStateReloadsPersistedServerProfilesAfterDatabaseReopen` 覆盖文件数据库关闭/重开后的服务器配置恢复。
- [x] 第二次连接不再询问相同主机指纹：`HostKeyTrustStoreTests.testTrustedHostKeyMatchesAfterTrust` 覆盖 trust 后相同 host key 直接匹配。
- [x] 修改远端 host key 或模拟不同 fingerprint 时阻断连接：`HostKeyTrustStoreTests.testChangedHostKeyBlocksWhenAlgorithmMatchesButFingerprintDiffers` 覆盖同算法不同 fingerprint 的阻断结果。
- [x] 删除服务器后 DB 记录、trusted host key、Keychain 凭据被清理：`ServerManagementServiceTests.testDeleteServerRemovesProfileTrustedKeysAndCredentials` 和 `testAppStateDeletingSelectedServerClearsSelectionConnectionAndCredential` 覆盖级联清理和工作台状态清空。

## 13. 完成标志

Phase 1 只有在以下条件都满足时才算完成：

1. 应用可运行。
2. 服务器配置可持久化。
3. 凭据只在 Keychain。
4. 主机指纹首次确认、后续校验。
5. 至少密码认证能真实连接服务器。
6. `printf hhc-ssh-ok` 真实远程执行成功。
7. 断开连接会停止当前操作并清理 OpenSSH 进程上下文、临时私钥/askpass 文件和 UI 连接状态。
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
