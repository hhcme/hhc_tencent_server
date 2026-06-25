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
- 不实现多文件并发批量传输的高级队列；Phase 3 bootstrap 先支持串行单文件队列。

## 3. 技术约束

- Dashboard 采集必须后台执行，不能阻塞 SwiftUI 主线程。
- 指标命令必须有超时；解析失败时展示“能力不可用”而不是崩溃。
- 云监控指标必须标明来源：Cloud API。
- SSH 指标必须标明来源：SSH。
- 正式 SFTP、进度百分比、批量/并发传输和队列持久化未落地前，文件管理器只能宣称支持 bootstrap 排队单文件传输。
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
- [x] 缓存探测结果：Dashboard 刷新成功后写入 `dashboard_snapshots`，重新进入工作台会恢复最近快照。
- [ ] 支持手动重新探测。
- [ ] 测试 Ubuntu/Debian/CentOS/AlmaLinux 常见输出解析。

### Task 2：SSH 指标采集

- [x] 实现 CPU 核心数、内存、根磁盘、负载和网络基础采集。
- [x] 实现进程摘要采集。
- [x] Dashboard 基础采集命令配置超时。
- [x] 解析失败和单项命令失败返回结构化 warning。

### Task 3：云监控接入

- [x] 在腾讯云 adapter 中补基础云监控查询：已接入 Cloud Monitor `GetMonitorData` 的 CVM `CPUUsage`。
- [x] 将云监控指标与 SSH 指标分开展示：DashboardMetric 使用 `Cloud API` 来源标记，当前先聚合显示 Cloud CPU。
- [x] 无云账号或无关联实例时隐藏云指标入口；权限或凭据错误以 warning 降级。

### Task 4：Dashboard UI

- [x] 实现 Dashboard ViewModel 基础刷新。
- [x] 实现指标卡片、系统信息、刷新状态。
- [x] 实现错误和能力缺失基础提示。
- [x] 支持手动刷新和自动刷新开关。
- [x] 支持最近 Dashboard 快照持久化和工作台恢复。

### Task 5：SFTP 技术验证

- [ ] 验证 SwiftNIO SSH 是否能稳定接入 SFTP subsystem。
- [x] 评估成熟 SFTP 库或 libssh2 wrapper，并暂定以 OpenSSH/scp bootstrap 先交付单文件传输。
- [x] 验证目录列表、文件读取、上传、下载基础路径。
- [ ] 验证权限、断线恢复和正式传输队列。
- [x] 形成技术验证结论并写入设计文档。

结论：当前 macOS bootstrap 继续使用系统 OpenSSH 工具链。目录浏览和文本读写走 `ssh` 命令，单文件上传/下载走 `scp`，已在真实 Linux 服务器上验证远端 `sftp` 命令存在以及 scp 上传/下载往返可用。SwiftNIO SSH/libssh2 的正式 SFTP 封装留到进度百分比、批量/并发传输和队列持久化阶段替换，避免在核心流程尚未稳定时引入额外 native binding 风险。

### Task 6：文件管理器

- [x] 实现路径导航和只读目录列表 bootstrap。
- [x] 实现单文件上传、下载 bootstrap。
- [x] 实现当前传输取消和任务状态记录。
- [x] 实现串行单文件传输队列、pending 状态和待传队列清空。
- [x] 实现传输进度状态展示和完成/失败/取消历史持久化。
- [ ] 实现字节级实时进度、批量/并发传输和可恢复队列持久化。
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
- [x] 单文件上传/下载服务和 ViewModel 测试。
- [x] 当前传输取消 ViewModel 测试。
- [x] 串行传输队列和待传队列清空 ViewModel 测试。
- [x] 传输历史 SQLite 持久化、恢复和级联删除测试。
- [ ] 可选真实 SFTP 集成测试。

### Task 8：手动验收

- [x] 连接一台 Linux 服务器后 Dashboard 能展示基础指标。
- [ ] 无 `/proc` 或命令缺失时 UI 不崩溃。
- [ ] 已关联腾讯云实例时能展示云侧指标。当前已有 mock/contract 测试，真实云账号手动验收待补。
- [x] 文件列表能浏览目录。
- [x] 小文件上传、下载、重命名成功。
- [ ] 删除会二次确认并进入可恢复路径。
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
