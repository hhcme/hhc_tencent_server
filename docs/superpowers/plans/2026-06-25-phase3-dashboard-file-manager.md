# Phase 3：Dashboard + 文件管理器实施计划

> Phase 3 在真实 SSH 和命令面板基础上，提供服务器状态概览和文件管理。Dashboard 必须基于能力探测；文件管理器先用 OpenSSH 工具链完成可用 bootstrap，再逐步固化正式 SFTP 传输队列。

**前置条件:** Phase 2 已完成，云实例关联和简化命令面板稳定。

## 1. 目标

1. 建立服务器能力探测模型：Linux 发行版、内核、`/proc`、systemd、常用命令可用性。
2. 通过 SSH 采集基础指标：CPU、内存、磁盘、负载、网络、进程摘要。
3. 在云实例已关联时，聚合展示云监控指标和 SSH 内部指标。
4. 完成 SFTP 技术验证，并确定文件管理实现路径。
5. 实现文件浏览、上传、下载、重命名、权限查看和轻量编辑。
6. 文件删除优先走可恢复路径，不直接默认 `rm`。

## 2. 非目标

- 不实现安全组修改。
- 不实现 systemd/Nginx/firewall/cron 管理。
- 不实现部署系统。
- 不实现大型二进制文件编辑。
- 不实现 SwiftNIO/libssh2 正式 SFTP 断点续传队列；Phase 3 bootstrap 支持多选后的有限并发传输队列，并在 rsync 后加入 OpenSSH `sftp -b` resumable batch fallback。

## 3. 技术约束

- Dashboard 采集必须后台执行，不能阻塞 SwiftUI 主线程。
- 指标命令必须有超时；解析失败时展示“能力不可用”而不是崩溃。
- 云监控指标必须标明来源：Cloud API。
- SSH 指标必须标明来源：SSH。
- SwiftNIO/libssh2 正式 SFTP 和 native 级传输队列未落地前，文件管理器只能宣称支持 OpenSSH bootstrap 批量传输；当前队列支持有限并发，失败/取消/中断任务可从历史记录原地恢复，rsync 路径可提供运行中字节进度、部分文件保留和 append 校验续传，OpenSSH `sftp -b` fallback 在 rsync 不可用时首传使用 `put` / `get`，检测到 partial 时通过 `put -a` / `get -a` 尝试续传，scp 最终回退路径只保证开始/完成进度。
- 文件编辑保存必须先写临时文件，再原子替换或备份原文件。

## 4. 数据模型

新增表：

```sql
CREATE TABLE server_capabilities (
    server_id TEXT PRIMARY KEY REFERENCES server_profiles(id) ON DELETE CASCADE,
    os_name TEXT,
    os_version TEXT,
    kernel_version TEXT,
    has_proc INTEGER NOT NULL DEFAULT 0,
    has_systemd INTEGER NOT NULL DEFAULT 0,
    has_sftp INTEGER NOT NULL DEFAULT 0,
    detected_at DATETIME NOT NULL,
    raw_json TEXT
);

CREATE TABLE dashboard_snapshots (
    id TEXT PRIMARY KEY NOT NULL,
    server_id TEXT NOT NULL REFERENCES server_profiles(id) ON DELETE CASCADE,
    capabilities_json TEXT NOT NULL,
    metrics_json TEXT NOT NULL,
    warnings_json TEXT NOT NULL,
    captured_at DATETIME NOT NULL
);

CREATE TABLE file_transfer_jobs (
    id TEXT PRIMARY KEY NOT NULL,
    server_id TEXT NOT NULL REFERENCES server_profiles(id) ON DELETE CASCADE,
    direction TEXT NOT NULL,
    remote_path TEXT NOT NULL,
    local_path TEXT,
    status TEXT NOT NULL,
    bytes_total INTEGER,
    bytes_done INTEGER,
    created_at DATETIME NOT NULL,
    updated_at DATETIME NOT NULL
);
```

## 5. 模块设计

- `ServerCapabilityDetector`：探测远端系统能力并缓存结果。
- `SSHMetricCollector`：执行 SSH 命令并解析指标。
- `CloudMetricCollector`：复用 Phase 2 provider adapter 查询云监控。
- `DashboardService`：聚合指标并产出 UI state。
- `SFTPValidationHarness`：验证连接、目录列表、读写、权限、断线恢复。
- `RemoteFileTransferClient`：隔离 OpenSSH/scp bootstrap 与后续 SwiftNIO SSH/libssh2 SFTP 实现。
- `RemoteFileService`：文件列表、上传、下载、重命名、删除、编辑保存。
- `FileTransferQueue`：串行或有限并发传输队列。

## 6. UI 范围

- 工作台 Overview 页面升级为 Dashboard。
- 展示系统信息、CPU、内存、磁盘、负载、网络、进程摘要。
- 指标卡片必须显示数据来源和刷新时间。
- 文件管理页：路径栏、目录列表、排序、刷新、上传、下载、重命名、删除、权限信息。
- 文本文件编辑器：读取、编辑、保存、另存为。
- 传输任务小面板：进度、取消、失败原因。

## 7. 实施任务

### Task 1：能力探测

- [x] 实现 OS 和能力探测命令。
- [x] 缓存探测结果：Dashboard 刷新成功后写入 `server_capabilities` 独立缓存和 `dashboard_snapshots`，重新进入工作台会恢复最近快照。
- [x] 支持手动重新探测：手动刷新 Dashboard 会重新执行能力探测，并更新 `server_capabilities`。
- [x] 测试 Ubuntu/Debian/CentOS/AlmaLinux 常见输出解析。

### Task 2：SSH 指标采集

- [x] 实现 CPU 核心数、内存、根磁盘、负载和网络基础采集。
- [x] 实现进程摘要采集。
- [x] Dashboard 基础采集命令配置超时。
- [x] 解析失败和单项命令失败返回结构化 warning。

### Task 3：云监控接入

- [x] 在云厂商 adapter 中补基础云监控查询：已接入腾讯云 Cloud Monitor `GetMonitorData`、阿里云 CMS `DescribeMetricList` 和华为云 CES `metric-data`，覆盖云侧 CPU、内存、磁盘读写吞吐和网络入出吞吐。
- [x] 将云监控指标与 SSH 指标分开展示：DashboardMetric 使用 `Cloud API` 来源标记，当前聚合显示 Cloud CPU、Cloud Memory、Cloud Disk Read/Write 和 Cloud Network In/Out。
- [x] 无云账号或无关联实例时隐藏云指标入口；权限或凭据错误以 warning 降级。

### Task 4：Dashboard UI

- [x] 实现 Dashboard ViewModel 基础刷新。
- [x] 实现指标卡片、系统信息、刷新状态。
- [x] 实现错误和能力缺失基础提示。
- [x] 支持手动刷新和自动刷新开关。
- [x] 支持最近 Dashboard 快照持久化和工作台恢复。

### Task 5：SFTP 技术验证

- [ ] 验证 SwiftNIO SSH 是否能稳定接入 SFTP subsystem。
- [x] 评估成熟 SFTP 库或 libssh2 wrapper，并暂定以 OpenSSH/rsync/sftp/scp bootstrap 先交付有限并发队列传输。
- [x] 验证目录列表、文件读取、上传、下载基础路径。
- [ ] 验证权限、断线恢复和正式传输队列。
- [x] 形成技术验证结论并写入设计文档。

结论：当前 macOS bootstrap 继续使用系统 OpenSSH 工具链。目录浏览和文本读写走 `ssh` 命令，文件上传/下载优先走 `rsync --partial --append-verify --progress` 以获得字节进度、部分文件保留和 append 校验续传；rsync 不可用或失败时先回退到 OpenSSH `sftp -b`，首传使用 `put` / `get`，检测到 partial 时使用 `put -a` / `get -a` batch；SFTP 仍失败时再回退 `scp`。工作台传输队列当前允许最多两个任务并发运行，超出的任务保持 pending。失败、取消和中断任务现在会以同一条历史任务原地恢复为 pending/running，保留已有进度上下文并在成功后覆盖为 succeeded，避免重试后留下重复历史。已在真实 Linux 服务器上验证远端 `sftp` 命令存在、SFTP 上传/下载往返、SFTP partial upload/download 续传以及 scp 上传/下载往返可用；2026-06-26 已重新用当前代码运行 SSH smoke、SFTP 往返和 SFTP partial 续传三项 opt-in 集成测试并通过。SwiftNIO SSH/libssh2 的正式 SFTP 封装仍留到 native 传输队列阶段替换，避免在核心流程尚未稳定时引入额外 native binding 风险。

### Task 6：文件管理器

- [x] 实现路径导航和只读目录列表 bootstrap。
- [x] 实现单文件上传、下载 bootstrap。
- [x] 实现当前传输取消和任务状态记录。
- [x] 实现有限并发传输队列、pending 状态和待传队列清空。
- [x] 实现多选批量上传和选中文件批量下载到目录，复用有限并发传输队列。
- [x] 实现传输进度状态展示和完成/失败/取消历史持久化。
- [x] 建立传输进度回调模型，运行中进度可更新 UI 并持久化到 `remote_file_transfers`。
- [x] 增加 rsync bootstrap 传输路径，支持字节进度解析、部分文件保留和 `--append-verify` 续传，失败时优先回退 OpenSSH `sftp -b`；首传使用 `put` / `get`，检测到 partial 时使用 `put -a` / `get -a`，最后回退 scp。
- [x] 实现 pending/running 任务持久化，重新进入工作台时将遗留未完成任务标记为 interrupted。
- [x] 实现 bootstrap 有限并发传输队列。
- [x] 实现失败、取消和中断传输任务的原地恢复入口；rsync 路径可利用 `--partial --append-verify` 保留的部分文件继续传输，恢复时复用原任务 ID、保留已有进度上下文并在成功后覆盖为 succeeded，SFTP fallback 检测到 partial 时通过 `put -a` / `get -a` 尝试续传，native 传输队列留到正式 SFTP 队列阶段。
- [x] 增加 native-ready 传输队列元数据：`remote_file_transfers` 持久化 backend、是否可续传、是否支持流式进度；OpenSSH 传输结果会标记 `rsync` / `OpenSSH SFTP` / `scp`，工作台传输列表展示 backend、resumable 和 streaming progress，为后续替换 libssh2/SwiftNIO SFTP 后端保留同一队列合同。
- [x] 增强传输队列按任务控制：工作台每条 pending/running 传输可单独取消；pending 任务取消后不会启动，running 任务取消只停止对应 Task，不影响其它运行中的传输，并继续持久化取消状态。
- [x] 增加传输队列暂停/恢复调度：暂停后 running 任务继续执行，但 pending 任务不会因并发槽释放而自动启动；恢复后继续按并发上限调度。
- [x] 增加批量恢复入口：工作台可一键恢复所有 failed/cancelled/interrupted 传输，已成功的历史任务不会重复入队。
- [ ] 实现正式 SFTP 和 native 级可恢复传输队列。
- [x] 实现重命名。
- [x] 实现权限查看基础展示。
- [x] 删除前二次确认，优先移动到远端应用回收目录。
- [x] 文本文件编辑保存前创建备份。
- [x] 实现另存为和权限修改。

### Task 7：测试

- [x] 指标解析单元测试。
- [x] 能力探测基础测试。
- [x] Dashboard ViewModel 测试。
- [x] Dashboard 自动刷新 ViewModel 测试。
- [x] Dashboard 快照 repository 持久化和 ViewModel 恢复测试。
- [x] RemoteFileService 目录列表解析测试。
- [x] 文件浏览 ViewModel 测试。
- [x] 文件重命名和可恢复删除测试。
- [x] 轻量文本读取、保存和备份测试。
- [x] 另存为和权限修改 ViewModel/Service 测试。
- [x] 单文件和批量上传/下载服务与 ViewModel 测试。
- [x] 当前传输取消 ViewModel 测试。
- [x] 有限并发传输队列、pending 溢出和待传队列清空 ViewModel 测试。
- [x] 失败/中断传输原地恢复 ViewModel 测试。
- [x] 传输历史 SQLite 持久化、恢复和级联删除测试。
- [x] 运行中传输进度回调、UI 状态更新和持久化测试。
- [x] 传输 backend / resumable / streaming progress 元数据持久化和恢复测试：`ServerRepositoryTests.testRemoteFileTransferJobsPersistOrderAndCascade` 覆盖 SQLite 字段，`ServerWorkspaceViewModelTests.testResumeRemoteFileTransferReusesFailedUploadJobHistory` 覆盖恢复任务成功后写回 native SFTP 能力，`testRemoteFileTransferProgressUpdatesRunningJobAndPersistence` 覆盖运行中流式进度能力持久化。
- [x] 按任务取消队列测试：`ServerWorkspaceViewModelTests.testCancelSinglePendingRemoteFileTransferDoesNotStartIt` 覆盖单个 pending 取消不启动且写入 cancelled，`testCancelSingleRunningRemoteFileTransferLeavesOtherRunning` 覆盖取消单个 running 不影响其它运行任务。
- [x] 队列暂停/恢复调度测试：`ServerWorkspaceViewModelTests.testPauseRemoteFileTransferQueueStopsPendingDispatchUntilResumed` 覆盖暂停期间并发槽释放后 pending 不启动，恢复后 pending 进入 running 并持久化。
- [x] 批量恢复测试：`ServerWorkspaceViewModelTests.testRetryAllRemoteFileTransfersOnlyQueuesRetryableJobs` 覆盖 failed upload 和 interrupted download 一键恢复，并确认 succeeded 历史不会重复执行。
- [x] rsync 进度输出解析和 `--append-verify` 参数测试。
- [x] 可选真实 SFTP 集成测试：`SSHIntegrationTests.testRealSFTPTransferRoundTripWhenEnvironmentIsConfigured` 会禁用 rsync 和 scp fallback，强制走 OpenSSH `sftp -b`，在远端 `/tmp/hhc-transfer-*` 完成首传上传、内容校验、下载和清理。
- [x] 可选真实 SFTP partial 续传集成测试：`SSHIntegrationTests.testRealSFTPResumePartialTransfersWhenEnvironmentIsConfigured` 会预置远端 partial upload 和本地 partial download，强制验证 `put -a` / `get -a` 可续传到完整内容。

### Task 8：手动验收

- [x] 连接一台 Linux 服务器后 Dashboard 能展示基础指标。
- [x] 无 `/proc` 或命令缺失时 UI 不崩溃：Dashboard 刷新会保留可用指标、把缺失命令记录为 warning，并通过 ViewModel 测试覆盖无 `/proc` 降级路径。
- [ ] 已关联腾讯云实例时能展示云侧指标。当前已有 mock/contract 测试，真实云账号手动验收待补。
- [x] 文件列表能浏览目录。
- [x] 小文件上传、下载、重命名成功。
- [x] 删除会二次确认并进入可恢复路径：工作台删除入口会弹出风险确认，确认后移动到远端 `~/.hhc-server-manager-trash/`，并已有 ViewModel/Service 测试覆盖。
- [x] 文本文件编辑保存成功，失败时不破坏原文件。

## 8. 完成标志

1. Dashboard 可稳定展示 SSH 指标。
2. 云监控指标在有云账号和已关联实例时可用，并正确标明来源。
3. SFTP 技术路径已验证并落地。
4. 文件管理器基本操作可用。
5. 所有高风险文件操作有确认和恢复策略。
6. 测试和手动验收通过。

## 9. 后续 Phase 边界

- Phase 4 才做 systemd/Nginx/firewall/cron 环境配置。
- Phase 5 才做部署流程。
- Phase 6 才做私有包仓库安装和管理。
