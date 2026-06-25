# HHC Server Manager — 设计文档

> 统一的 macOS 原生服务器管理平台，类似宝塔面板，支持多云厂商多台服务器管理。

## 1. 项目概述

### 1.1 目标

构建一个 macOS 原生客户端应用，通过 SSH 连接远程服务器，提供统一的服务器管理能力。项目采用 **SSH-first + optional Cloud API enhancement**：SSH 是所有服务器管理能力的基础路径；当用户主动配置腾讯云、阿里云、华为云等云厂商 API 凭据后，启用实例发现、云资源状态、云监控、安全组和电源操作等增强能力。

### 1.2 核心功能

- **基础运维**：SSH 终端、文件管理器、服务器状态监控
- **云资源增强**：云实例发现、云资源元数据、云监控、安全组、开关机/重启
- **环境配置**：系统服务管理、Nginx、防火墙、定时任务、环境变量
- **GitLab 部署**：项目部署、自动部署（webhook）、回滚
- **私有包仓库**：npm 私有仓库（Verdaccio）、Flutter 私有 pub 仓库

### 1.3 设计边界

- **MVP 目标**：先打通“本地配置服务器 -> 安全保存凭据 -> 验证主机指纹 -> 真实 SSH 连接 -> 执行一个远程命令”的最小闭环。
- **云厂商支持方式**：默认支持手动 SSH 服务器；云厂商 API 作为可选增强层，通过 provider adapter 接入，不让 UI 为每家厂商分叉。
- **远程系统假设**：优先支持常见 Linux 发行版；systemd、firewalld、Nginx 目录结构等能力必须运行时探测，不能硬编码为所有服务器都可用。
- **Phase 1 不做的事**：完整交互式终端、SFTP 文件管理、Dashboard 实时监控、云厂商 API、部署系统、包仓库安装都后置。

### 1.4 技术栈

| 层级 | 技术选型 |
|------|---------|
| 语言 | Swift 6.1+ |
| UI 框架 | SwiftUI（为主），必要时混入 AppKit |
| SSH | SwiftNIO SSH 0.13.x（exec/shell channel）；SFTP 在 Phase 3 单独技术验证 |
| 云厂商 API | Provider Adapter（Tencent Cloud / Alibaba Cloud / Huawei Cloud，可选启用） |
| 数据持久化 | SQLite + GRDB 7.x（本地配置）+ macOS Keychain（敏感信息） |
| 最低系统版本 | macOS 14 (Sonoma) |

> SwiftNIO SSH 的新版本已进入 Swift 6.x 生态。为了避免依赖解析到需要更高 Swift 版本的包，项目应在 `Package.resolved` 中锁定版本，并在 CI 中固定 Xcode/Swift 工具链。
>
> 当前实现优先级是 macOS 原生版。Windows 原生版在 macOS 核心功能稳定后启动，推荐技术方向为 WinUI 3 + Windows App SDK + .NET/C#，详见 [Windows 原生客户端技术选型](2026-06-25-windows-native-client-strategy.md)。

## 2. 整体架构

### 2.1 应用结构

```
HHCServerManager/
├── App/                          # 应用入口
│   ├── HHCServerManagerApp.swift
│   └── AppState.swift            # 全局状态管理
├── Models/                       # 数据模型
│   ├── ServerProfile.swift
│   ├── DeployProject.swift
│   ├── DeployLog.swift
│   └── PackageService.swift
├── Services/                     # 核心服务层
│   ├── SSH/
│   │   ├── SSHManager.swift      # SSH 连接管理（actor）
│   │   ├── SSHConnection.swift   # 单个连接封装
│   │   ├── HostKeyTrustStore.swift # 主机指纹信任
│   │   └── CommandExecutor.swift # 远程命令执行
│   ├── Storage/
│   │   ├── AppDatabase.swift     # SQLite 数据库
│   │   └── KeychainService.swift # Keychain 封装
│   ├── Cloud/
│   │   ├── CloudProviderAdapter.swift   # 云厂商 adapter 协议
│   │   ├── CloudProviderRegistry.swift  # adapter 注册与能力发现
│   │   ├── CloudAccountStore.swift      # 云账号配置与凭据引用
│   │   ├── CloudInstanceSyncService.swift # 云实例同步
│   │   └── Providers/
│   │       ├── TencentCloudAdapter.swift
│   │       ├── AlibabaCloudAdapter.swift
│   │       └── HuaweiCloudAdapter.swift
│   ├── FileTransfer/
│   │   └── SFTPClient.swift      # Phase 3 技术验证后落地
│   └── Monitor/
│       └── ServerMonitor.swift   # 服务器状态采集
├── ViewModels/                   # 视图模型
│   ├── ServerBrowserViewModel.swift
│   ├── ServerWorkspaceViewModel.swift
│   ├── ServerSwitcherViewModel.swift
│   ├── TerminalViewModel.swift
│   ├── FileManagerViewModel.swift
│   ├── ServiceManagerViewModel.swift
│   ├── DeployerViewModel.swift
│   └── PackageManagerViewModel.swift
├── Views/                        # 视图层
│   ├── ServerBrowser/
│   │   ├── ServerBrowserView.swift
│   │   ├── ServerRowView.swift
│   │   └── ServerSummaryPanel.swift
│   ├── ServerWorkspace/
│   │   ├── ServerWorkspaceView.swift
│   │   ├── ServerWorkspaceSidebar.swift
│   │   ├── ServerOverviewView.swift
│   │   └── ServerSwitcherPopover.swift
│   ├── Sheets/
│   │   ├── AddServerSheet.swift
│   │   └── HostKeyTrustSheet.swift
│   ├── Dashboard/
│   │   ├── DashboardView.swift
│   │   ├── GaugeCard.swift
│   │   └── ProcessListView.swift
│   ├── Terminal/
│   │   └── TerminalView.swift
│   ├── FileManager/
│   │   ├── FileManagerView.swift
│   │   ├── FileListView.swift
│   │   └── FileEditorView.swift
│   ├── Services/
│   │   ├── ServiceManagerView.swift
│   │   ├── NginxConfigView.swift
│   │   ├── FirewallView.swift
│   │   └── CronView.swift
│   ├── Deployer/
│   │   ├── DeployerView.swift
│   │   ├── ProjectConfigView.swift
│   │   └── DeployLogView.swift
│   └── PackageManager/
│       ├── PackageManagerView.swift
│       ├── NpmRegistryView.swift
│       └── PubServerView.swift
└── Utilities/                    # 工具类
    ├── AnsiParser.swift          # ANSI 颜色解析
    ├── SystemInfoParser.swift    # 系统信息解析
    └── Constants.swift
```

### 2.2 导航结构

产品导航采用“两层模型”：

1. **Server Browser（启动服务器列表）**：应用启动后首先进入服务器列表，支持分组、搜索、筛选、选中摘要、Open/Connect/Delete 等操作。
2. **Server Workspace（单服务器工作台）**：点击 Open 后进入该服务器的专用工作台，工作台左侧是当前服务器的功能导航，顶部 toolbar 提供返回列表、服务器切换器和常用操作入口。

```
启动页：
┌──────────────────────────────────────────────────────┐
│ Toolbar: Search / Add / Cloud / More                 │
├───────────────┬──────────────────────────────────────┤
│ Source List   │ Server table + selected summary      │
│ All Servers   │ Open / Connect / Delete              │
│ Groups        │                                      │
│ Cloud/Manual  │                                      │
└───────────────┴──────────────────────────────────────┘

工作台：
┌──────────────────────────────────────────────────────┐
│ Toolbar: Servers / Current Server Switcher / Actions │
├───────────────┬──────────────────────────────────────┤
│ Server tools  │ Current server workspace             │
│ Overview      │ Overview / Terminal / Files / ...    │
│ Terminal      │                                      │
│ Files         │                                      │
└───────────────┴──────────────────────────────────────┘
```

- **启动服务器列表**：面向多服务器浏览、搜索、分组和选择。
- **单服务器工作台**：面向当前服务器操作和浏览。
- **服务器切换器**：在工作台内切换当前服务器，不要求用户每次都返回启动列表。
- **多窗口**：后续可以支持同时打开多个服务器工作台，但 Phase 1 不要求。

## 3. SSH 连接层

### 3.1 连接模型

```
SSHManager（actor 或主线程隔离服务）
├── connections: [ServerID: SSHConnection]   # 连接池
├── connect(profile: ServerProfile) → SSHConnection
├── disconnect(serverId: ServerID)
└── reconnect(serverId: ServerID)

SSHConnection
├── bootstrapChannel: Channel               # TCP + NIOSSHHandler 所在 Channel
├── commandChannel: Channel?                # exec/shell 子 Channel
├── execute(command: String) → CommandResult
├── stream(command: String) → AsyncStream<String>
├── isConnected: Bool
└── lastActivity: Date
```

**并发约束**：
- `AppState` 与所有 SwiftUI 可观察状态运行在 `@MainActor`。
- `SSHManager` 使用 `actor` 或严格串行队列，避免同一服务器并发创建多个连接。
- NIO 的 `Channel`、`EventLoopGroup` 不直接暴露给 ViewModel；ViewModel 只拿到 `async throws` API 和状态流。

### 3.2 认证方式

| 方式 | 存储 | 说明 |
|------|------|------|
| SSH 密钥 | macOS Keychain | 推荐，优先 ED25519 / ECDSA；RSA 兼容性需实测 |
| 密码 | macOS Keychain | 备选，首次连接时输入 |

**密钥处理原则**：
- Keychain 保存的是私钥内容或加密后的凭据 blob，不保存裸文件路径作为唯一凭据。
- 如果用户选择引用本地私钥文件，必须保存 security-scoped bookmark，并在连接时重新获取访问权限。
- 支持 passphrase 的密钥时，passphrase 单独写入 Keychain 或按连接会话临时询问。

### 3.3 连接生命周期

1. 用户选择服务器 → 调用 `SSHManager.connect()`
2. 从 Keychain 获取认证凭据
3. 建立 TCP 连接并安装 `NIOSSHHandler`（超时 10 秒）
4. 通过 server authentication delegate 验证主机公钥指纹
5. 首次连接时提示用户确认并持久化 host key；后续连接必须比对
6. 认证成功后执行健康检查命令（`printf hhc-ssh-ok`）
7. 连接成功 → 加入连接池
8. 空闲检测：5 分钟无操作发送 keepalive 或执行轻量命令
9. 断线检测 → 自动重连；仅自动重试幂等操作

### 3.4 错误处理

| 错误类型 | 处理方式 |
|---------|---------|
| 连接超时 | 自动重试 3 次，间隔递增（1s/2s/4s） |
| 认证失败 | 提示用户检查密钥/密码，不自动重试 |
| 主机指纹变更 | 阻断连接，要求用户检查并重新建立信任记录 |
| 命令执行失败 | 返回 stderr 输出，由上层决定处理方式 |
| 网络中断 | 自动重连；未完成操作默认标记失败，只有声明为幂等的操作可重试 |
| 依赖能力缺失 | 展示“当前服务器不支持此功能”并给出检测结果 |

## 4. 云厂商 API 增强层

云厂商 API 不替代 SSH，而是补充 SSH 不擅长或无法稳定获得的信息。详细设计见 [云厂商 API 增强层设计](2026-06-25-cloud-provider-integration.md)。

### 4.1 能力范围

| 能力 | 来源 | 说明 |
|------|------|------|
| 实例发现 | Cloud API | 从腾讯云、阿里云、华为云账号导入服务器 |
| 云资源元数据 | Cloud API | 实例 ID、地域、可用区、规格、镜像、计费类型 |
| 网络信息 | Cloud API | 公网 IP、内网 IP、VPC、子网、EIP |
| 云监控 | Cloud API | 云平台 CPU、网络、云盘等指标 |
| 安全组 | Cloud API | 查看和修改云网络边界规则 |
| 电源操作 | Cloud API | 开机、关机、重启，必须二次确认 |
| 系统内部运维 | SSH | systemd、Nginx、Cron、文件、部署等仍走 SSH |

### 4.2 Adapter 模型

```swift
protocol CloudProviderAdapter: Sendable {
    var providerId: CloudProviderID { get }
    var displayName: String { get }
    var capabilities: Set<CloudCapability> { get }

    func validateCredentials(_ credential: CloudCredential) async throws
    func listRegions(account: CloudProviderAccount) async throws -> [CloudRegion]
    func listInstances(account: CloudProviderAccount, region: String) async throws -> [CloudInstance]
    func fetchMetrics(
        account: CloudProviderAccount,
        instance: CloudInstanceRef,
        query: CloudMetricQuery
    ) async throws -> [CloudMetricSeries]
    func performAction(
        _ action: CloudInstanceAction,
        account: CloudProviderAccount,
        instance: CloudInstanceRef
    ) async throws
}
```

首批 adapter 优先级：

1. Tencent Cloud：实例发现和云监控优先。
2. Alibaba Cloud：ECS 实例发现和 CloudMonitor。
3. Huawei Cloud：ECS 查询和 Cloud Eye。

### 4.3 云 API 凭据安全

- 云 API SecretId/SecretKey、AccessKey、Token 全部存入 macOS Keychain。
- SQLite 只保存 `keychain_ref`、厂商 ID、显示名称、启用状态等非密钥信息。
- 默认建议用户配置只读权限；开关机、安全组修改、快照等能力使用额外权限档位。
- 所有云 API 调用需要限流、错误归一化和本地审计日志。

## 5. 核心模块设计

### 5.1 Dashboard（服务器概览）

**数据采集方式**：基础系统指标通过 SSH 执行系统命令并解析输出；如果服务器关联了云实例，则并列采集云监控指标，用于对比“服务器内部状态”和“云平台资源状态”。

Dashboard 面向 Linux 服务器。进入 Dashboard 前先探测发行版、内核、是否存在 `/proc`、是否安装 `systemd`，并缓存探测结果。

| 指标 | 采集命令 | 刷新间隔 |
|------|---------|---------|
| CPU 使用率 | `/proc/stat` 差分；备选 `top -bn1 \| head -5` | 5 秒 |
| 内存使用 | `free -m` | 5 秒 |
| 磁盘使用 | `df -h` | 30 秒 |
| 网络流量 | `/proc/net/dev` 差分；备选 `ifstat` | 5 秒 |
| 系统信息 | `uname -a && uptime` | 60 秒 |
| 进程列表 | `ps aux --sort=-%cpu` | 10 秒 |

**UI 组件**：
- 仪表盘卡片（CPU/内存/磁盘/网络），带实时图表
- 云资源信息卡片（实例 ID、地域、规格、云状态、数据来源）
- 系统信息面板
- 进程 Top N 列表（可展开查看全部）

### 5.2 Terminal（终端）

**MVP 版本**（简化终端）：
- 输入框 + 输出区域
- 支持命令历史（上下箭头导航）
- ANSI 颜色渲染
- 输出支持滚动、搜索、复制
- 常用命令快捷按钮

**后期升级**（完整 PTY 终端）：
- 基于 PTY 的交互式终端
- 支持 `vim`、`top`、`htop` 等交互式程序
- 窗口大小自适应
- 多标签终端

### 5.3 FileManager（文件管理器）

**功能列表**：
- 目录树浏览（基于 SFTP）
- 文件上传（本地 → 远程，支持拖拽）
- 文件下载（远程 → 本地，支持拖拽）
- 在线编辑文本文件（语法高亮）
- 新建文件/目录
- 删除文件/目录（二次确认）
- 重命名
- 修改权限（chmod）
- 修改所有者（chown）
- 文件搜索（`find` 或 `locate`）
- 文件大小/修改时间显示

**SFTP 操作封装**：
> SwiftNIO SSH 提供 SSH 协议和 session channel 能力，但不等价于高层 SFTP 客户端。Phase 3 开始前必须完成 SFTP 技术验证：选择成熟 SFTP 库、封装 libssh2，或基于 SSH subsystem 自研 SFTP 协议层。未验证前不要把文件管理器排进可交付范围。

```swift
protocol SFTPClientProtocol {
    func listDirectory(path: String) async throws -> [RemoteFile]
    func download(remotePath: String, localPath: String) async throws
    func upload(localPath: String, remotePath: String) async throws
    func delete(path: String) async throws
    func rename(from: String, to: String) async throws
    func chmod(path: String, mode: UInt32) async throws
    func mkdir(path: String) async throws
    func readFile(path: String) async throws -> Data
    func writeFile(path: String, data: Data) async throws
}
```

### 5.4 ServiceManager（环境配置）

**系统服务管理**：
- 能力探测：`command -v systemctl`，确认 systemd 可用
- 列出所有 systemd 服务：`systemctl list-units --type=service`
- 启动/停止/重启：`systemctl start/stop/restart <service>`
- 开机自启：`systemctl enable/disable <service>`
- 查看状态：`systemctl status <service>`
- 查看日志：`journalctl -u <service>`

**Nginx 管理**：
- 能力探测：`command -v nginx`，读取 `nginx -V` 和 `nginx -T`
- 配置路径探测：优先解析 `nginx -V` 的 `--conf-path` / `--prefix`，再兼容 `/etc/nginx`、`/usr/local/nginx/conf`、`/opt/nginx/conf` 等常见目录；不能假设所有服务器都使用 `/etc/nginx`
- 站点列表：优先基于探测到的配置目录枚举配置文件，后续可增强为解析 `nginx -T` include 图；`/etc/nginx/sites-enabled/` 仅作为 Debian/Ubuntu 约定路径
- 配置编辑：在线编辑配置文件
- 配置测试：`nginx -t`
- 重载配置：`nginx -s reload`
- SSL 证书：查看证书状态、路径
- 访问日志/错误日志查看

**防火墙管理**：
- 能力探测：`firewall-cmd` / `ufw` / `nft` / `iptables`
- 按探测结果进入对应适配器；不能假设所有服务器都使用 firewalld

**定时任务（Cron）**：
- 列出任务：`crontab -l`
- 添加任务：编辑 crontab
- 删除任务：从 crontab 中移除行
- 编辑任务：修改 crontab 行

**环境变量**：
- 系统级：`/etc/environment`、`/etc/profile.d/`
- 用户级：`~/.bashrc`、`~/.profile`、`~/.zshrc`
- 在线编辑 + 生效

### 5.5 Deployer（GitLab 部署）

**项目配置**：
```swift
struct DeployProject {
    let id: UUID
    let serverId: UUID
    let name: String              // 项目名称
    let repoUrl: String           // Git 仓库地址
    let branch: String            // 部署分支
    let remotePath: String        // 远程部署路径
    let deployScript: String      // 部署脚本（多行 shell 命令）
    let webhookSecret: String?    // Webhook 密钥
}
```

**部署流程**：
1. 首次部署：`git clone` → 记录当前 commit → 执行部署脚本
2. 更新部署：`git fetch` → 预检工作区状态 → `git reset --hard origin/<branch>` → 执行部署脚本
3. 回滚：从已记录的部署日志选择版本 → `git reset --hard <commit>` → 执行部署脚本
4. 所有 destructive git 操作必须在部署目录白名单内执行，并记录执行前 commit，避免误操作其他目录

**Webhook 自动部署**：
- 在服务器上部署一个轻量 Python HTTP 服务（`webhook_server.py`，基于 `http.server` + `hmac`，无额外依赖）
- 监听指定端口（如 9000）的 GitLab push 事件
- 验证 GitLab `X-Gitlab-Token`（常量时间比较）；如后续增加自定义代理，再支持 HMAC-SHA256
- 触发对应项目的部署脚本
- 通过 systemd 管理 webhook 服务的生命周期

**部署日志**：
- 记录每次部署的完整输出
- 状态追踪：pending → running → success/failed
- 支持查看历史部署记录

### 5.6 PackageManager（私有包仓库）

#### npm 私有仓库（基于 Verdaccio）

**一键部署**：
1. 检查 Node.js 是否安装（`node -v`），未安装则按用户选择使用系统包管理器、NodeSource 或 nvm 安装受 Verdaccio 支持的版本
2. 安装明确版本的 Verdaccio，避免默认拉取 next/pre-release
3. 生成配置文件 `~/.config/verdaccio/config.yaml`（自定义端口、存储路径、上游 registry）
4. 创建 systemd 用户服务（`~/.config/systemd/user/verdaccio.service`）
5. 启用并启动服务
6. 配置 Nginx 反向代理（可选，用于 HTTPS 和域名绑定）

**管理功能**：
- 包列表浏览
- 包搜索
- 包发布（`npm publish --registry=<url>`）
- 用户管理（htpasswd）
- 上游 registry 配置
- 存储路径管理

#### Flutter 私有 pub 仓库（基于 `unpub`）

`unpub` 是 Dart 私有 pub 仓库候选方案，支持包发布、搜索、Web UI。进入 Phase 6 前需要重新验证维护状态、Dart SDK 兼容性和部署方式；也可评估 OnePub、自建 pub server 或私有 Git 依赖方案。

**一键部署**：
1. 安装 Dart SDK（如未安装，通过官方脚本安装）
2. `dart pub global activate unpub`
3. 配置 `unpub` 启动脚本（指定端口、存储路径）
4. 配置 systemd 服务实现开机自启
5. 配置 Nginx 反向代理（可选）

**管理功能**：
- 包列表浏览
- 包发布
- 版本管理
- 与 Flutter 项目集成（设置 `PUB_HOSTED_URL`）

## 6. 数据模型

### 6.1 SQLite 表结构

```sql
-- 服务器配置
CREATE TABLE server_profiles (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    host TEXT NOT NULL,
    port INTEGER NOT NULL DEFAULT 22,
    auth_type TEXT NOT NULL,          -- 'privateKey' | 'password'
    username TEXT NOT NULL,
    keychain_ref TEXT NOT NULL,       -- Keychain 中的凭据引用
    group_name TEXT,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP
);

-- 主机信任记录（用于支持同 host 多用户、多端口或后续 known_hosts 导入）
CREATE TABLE trusted_host_keys (
    id TEXT PRIMARY KEY,
    server_id TEXT NOT NULL REFERENCES server_profiles(id) ON DELETE CASCADE,
    host TEXT NOT NULL,
    port INTEGER NOT NULL,
    algorithm TEXT NOT NULL,
    fingerprint_sha256 TEXT NOT NULL,
    raw_public_key TEXT,
    trusted_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(server_id, algorithm, fingerprint_sha256)
);

-- 云厂商账号
CREATE TABLE cloud_provider_accounts (
    id TEXT PRIMARY KEY,
    provider_id TEXT NOT NULL,          -- 'tencent' | 'alibaba' | 'huawei' | 'manual'
    display_name TEXT NOT NULL,
    keychain_ref TEXT NOT NULL,
    enabled INTEGER NOT NULL DEFAULT 1,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP
);

-- 云实例与 SSH 服务器的关联
CREATE TABLE cloud_instance_links (
    id TEXT PRIMARY KEY,
    server_id TEXT REFERENCES server_profiles(id) ON DELETE SET NULL,
    account_id TEXT NOT NULL REFERENCES cloud_provider_accounts(id) ON DELETE CASCADE,
    provider_id TEXT NOT NULL,
    region_id TEXT NOT NULL,
    instance_id TEXT NOT NULL,
    display_name TEXT,
    public_ip TEXT,
    private_ip TEXT,
    status TEXT,
    instance_type TEXT,
    zone_id TEXT,
    vpc_id TEXT,
    raw_json TEXT,
    last_synced_at DATETIME,
    UNIQUE(account_id, region_id, instance_id)
);

-- 部署项目
CREATE TABLE deploy_projects (
    id TEXT PRIMARY KEY,
    server_id TEXT NOT NULL REFERENCES server_profiles(id),
    name TEXT NOT NULL,
    repo_url TEXT NOT NULL,
    branch TEXT DEFAULT 'main',
    remote_path TEXT NOT NULL,
    deploy_script TEXT NOT NULL,
    webhook_secret TEXT,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP
);

-- 部署日志
CREATE TABLE deploy_logs (
    id TEXT PRIMARY KEY,
    project_id TEXT NOT NULL REFERENCES deploy_projects(id),
    status TEXT NOT NULL,             -- 'pending' | 'running' | 'success' | 'failed'
    output TEXT,
    commit_hash TEXT,
    started_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    finished_at DATETIME
);

-- 包仓库服务
CREATE TABLE package_services (
    id TEXT PRIMARY KEY,
    server_id TEXT NOT NULL REFERENCES server_profiles(id),
    type TEXT NOT NULL,               -- 'npm' | 'flutter_pub'
    port INTEGER NOT NULL,
    status TEXT DEFAULT 'stopped',    -- 'running' | 'stopped'
    config_path TEXT,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP
);
```

### 6.2 Keychain 存储

| Key | Value | 说明 |
|-----|-------|------|
| `ssh_private_key_<keychain_ref>` | 私钥内容 | SSH 私钥 |
| `ssh_password_<keychain_ref>` | 密码字符串 | SSH 密码 |
| `ssh_private_key_passphrase_<keychain_ref>` | 密钥口令 | 可选，仅用户选择保存时写入 |
| `ssh_key_bookmark_<keychain_ref>` | security-scoped bookmark | 可选，引用本地私钥文件时使用 |
| `cloud_tencent_secret_id_<keychain_ref>` | SecretId | 腾讯云 API 凭据 |
| `cloud_tencent_secret_key_<keychain_ref>` | SecretKey | 腾讯云 API 凭据 |
| `cloud_alibaba_access_key_id_<keychain_ref>` | AccessKeyId | 阿里云 API 凭据 |
| `cloud_alibaba_access_key_secret_<keychain_ref>` | AccessKeySecret | 阿里云 API 凭据 |
| `cloud_huawei_access_key_id_<keychain_ref>` | AccessKeyId | 华为云 API 凭据 |
| `cloud_huawei_secret_access_key_<keychain_ref>` | SecretAccessKey | 华为云 API 凭据 |
| `webhook_secret_<project_id>` | 密钥字符串 | Webhook 密钥 |

## 7. 安全设计

### 7.1 凭据安全

- SSH 密钥/密码**仅**存储在 macOS Keychain，永不写入文件
- 云 API 凭据**仅**存储在 macOS Keychain，SQLite 只保存 `keychain_ref`
- SQLite 数据库可选加密（SQLCipher）
- 应用退出时断开所有 SSH 连接
- 应用启用 Sandbox 时必须配置 Outgoing Network Connections；如引用本地私钥文件，还需 User Selected File 权限和 security-scoped bookmark

### 7.2 操作安全

- 危险操作（删除文件、重启服务、修改系统配置）需二次确认
- 云 API 危险操作（关机、重启、安全组修改、快照创建）需二次确认并记录本地审计日志
- 所有远程操作记录到本地日志
- 文件删除优先走可恢复路径：探测 `trash`/`gio trash` 是否可用；不可用时移动到用户目录下的应用回收目录，直接 `rm` 必须二次确认

### 7.3 连接安全

- 强制 SSH 2 协议
- 首次连接验证主机指纹，后续连接对比指纹
- 支持 SSH 密钥 passphrase
- 主机指纹变更不允许静默覆盖；必须展示旧指纹、新指纹和风险说明

## 8. 开发阶段规划

### Phase 1：项目骨架 + 真实 SSH 最小闭环
- Xcode 项目初始化
- SwiftUI 应用框架（启动服务器列表 + 单服务器工作台 + toolbar 服务器切换器）
- SSH 连接层（真实连接、主机指纹确认、密码/密钥认证、执行单条命令）
- 服务器配置 CRUD + Keychain 集成
- 连接状态管理

### Phase 2：云厂商基础层 + 简化命令面板
- CloudProviderAdapter 协议和腾讯云只读 adapter
- 云账号配置、凭据写入 Keychain、权限校验
- 腾讯云 CVM 实例发现与 SSH profile 关联
- 简化命令面板（命令执行 + 输出展示）
- 命令历史

### Phase 3：Dashboard + 文件管理器
- 服务器状态采集与解析
- 云监控指标采集与 SSH 指标聚合展示
- Dashboard UI（仪表盘卡片、系统信息、进程列表、云资源信息）
- SFTP 文件操作封装
- 文件列表 UI（目录浏览、图标、排序）
- 文件上传/下载
- 在线文件编辑器
- 文件权限管理

### Phase 4：安全组 + 环境配置
- 云安全组查看与修改（需要额外权限和二次确认）
- 系统服务管理（systemd）
- Nginx 配置管理
- 防火墙规则管理
- 定时任务管理
- 环境变量管理

### Phase 5：GitLab 部署
- 部署项目配置
- 部署脚本执行
- 部署日志
- 回滚功能
- Webhook 自动部署

### Phase 6：私有包仓库
- Verdaccio 一键部署
- npm 包管理
- Dart/Flutter pub 私有仓库方案验证
- 验证通过后实现 pub 包管理

### Phase 7：高级云资源管理
- 阿里云、华为云 adapter
- 云盘、快照、备份、计费/到期状态
- 多云资源搜索与高级过滤

### Phase 8：Windows 原生版技术验证
- WinUI 3 + Windows App SDK + .NET/C# 技术验证
- Windows Credential Manager / DPAPI 凭据存储
- Windows 版真实 SSH MVP（服务器 CRUD、凭据、主机指纹、`printf hhc-ssh-ok`）
- 复用 macOS 版的领域模型和云 provider adapter 设计

## 9. 依赖库

| 库 | 用途 |
|----|------|
| SwiftNIO SSH 0.13.x | SSH 连接 |
| SwiftNIO | 异步网络框架 |
| GRDB 7.x | SQLite 数据库封装 |
| 云厂商 OpenAPI/SDK 或轻量签名客户端 | 可选云资源增强 |
| Splash 或 Highlightr | 代码语法高亮 |

## 10. 非功能需求

- **性能**：Dashboard 刷新不应阻塞 UI，所有 SSH 操作在后台线程执行
- **可靠性**：SSH 断线自动重连；只有幂等操作可自动重试，所有远程操作必须有超时处理
- **可扩展性**：模块化设计，新增云厂商通过 provider adapter 接入，不修改核心 UI
- **用户体验**：操作有 loading 状态、错误有明确提示、危险操作有确认弹窗
- **可测试性**：SSH、Keychain、数据库都通过协议注入；Phase 1 至少覆盖模型、Repository、Keychain wrapper、连接状态机和命令解析
