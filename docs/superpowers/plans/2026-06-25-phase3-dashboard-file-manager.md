# Phase 3：Dashboard + 文件管理器实施计划

> Phase 3 在真实 SSH 和命令面板基础上，提供服务器状态概览和文件管理。Dashboard 必须基于能力探测，文件管理器必须先完成 SFTP 技术验证再进入交付实现。

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
- 不实现多文件并发批量传输的高级队列。

## 3. 技术约束

- Dashboard 采集必须后台执行，不能阻塞 SwiftUI 主线程。
- 指标命令必须有超时；解析失败时展示“能力不可用”而不是崩溃。
- 云监控指标必须标明来源：Cloud API。
- SSH 指标必须标明来源：SSH。
- SFTP 未验证前，文件管理器不得宣称可交付。
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
    source TEXT NOT NULL,
    metric_name TEXT NOT NULL,
    metric_value REAL,
    unit TEXT,
    raw_json TEXT,
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
- [ ] 缓存探测结果。
- [ ] 支持手动重新探测。
- [ ] 测试 Ubuntu/Debian/CentOS/AlmaLinux 常见输出解析。

### Task 2：SSH 指标采集

- [ ] 实现 CPU、内存、磁盘、负载、网络采集。
- [x] 实现 CPU 核心数、内存、根磁盘、负载基础采集。
- [ ] 实现进程摘要采集。
- [x] Dashboard 基础采集命令配置超时。
- [ ] 解析失败返回结构化错误。

### Task 3：云监控接入

- [ ] 在腾讯云 adapter 中补基础云监控查询。
- [ ] 将云监控指标与 SSH 指标分开展示。
- [ ] 无云账号或无权限时隐藏云指标入口。

### Task 4：Dashboard UI

- [x] 实现 Dashboard ViewModel 基础刷新。
- [x] 实现指标卡片、系统信息、刷新状态。
- [ ] 实现错误和能力缺失提示。
- [ ] 支持手动刷新和自动刷新开关。

### Task 5：SFTP 技术验证

- [ ] 验证 SwiftNIO SSH 是否能稳定接入 SFTP subsystem。
- [ ] 评估成熟 SFTP 库或 libssh2 wrapper。
- [ ] 验证目录列表、文件读取、上传、下载、权限、断线恢复。
- [ ] 形成技术验证结论并写入设计文档。

### Task 6：文件管理器

- [x] 实现路径导航和只读目录列表 bootstrap。
- [ ] 实现上传、下载、取消和进度。
- [x] 实现重命名。
- [x] 实现权限查看基础展示。
- [x] 删除前二次确认，优先移动到远端应用回收目录。
- [ ] 文本文件编辑保存前创建备份。

### Task 7：测试

- [x] 指标解析单元测试。
- [x] 能力探测基础测试。
- [x] Dashboard ViewModel 测试。
- [x] RemoteFileService 目录列表解析测试。
- [x] 文件浏览 ViewModel 测试。
- [x] 文件重命名和可恢复删除测试。
- [ ] 可选真实 SFTP 集成测试。

### Task 8：手动验收

- [ ] 连接一台 Linux 服务器后 Dashboard 能展示基础指标。
- [ ] 无 `/proc` 或命令缺失时 UI 不崩溃。
- [ ] 已关联腾讯云实例时能展示云侧指标。
- [ ] 文件列表能浏览目录。
- [ ] 小文件上传、下载、重命名成功。
- [ ] 删除会二次确认并进入可恢复路径。
- [ ] 文本文件编辑保存成功，失败时不破坏原文件。

## 8. 完成标志

1. Dashboard 可稳定展示 SSH 指标。
2. 云监控指标在有云账号时可用，并正确标明来源。
3. SFTP 技术路径已验证并落地。
4. 文件管理器基本操作可用。
5. 所有高风险文件操作有确认和恢复策略。
6. 测试和手动验收通过。

## 9. 后续 Phase 边界

- Phase 4 才做 systemd/Nginx/firewall/cron 环境配置。
- Phase 5 才做部署流程。
- Phase 6 才做私有包仓库安装和管理。
