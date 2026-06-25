# Phase 2：云厂商基础层 + 简化命令面板实施计划

> Phase 2 的目标是在 Phase 1 真实 SSH MVP 之上，引入可选云厂商 API 增强层，并提供可复用的简化命令面板。云 API 不替代 SSH，只负责实例发现、云资源元数据和后续云能力的基础设施。

**前置条件:** Phase 1 已完成，服务器 CRUD、Keychain、主机指纹信任、真实 SSH command smoke test 均通过。

**相关设计:** `docs/superpowers/specs/2026-06-25-cloud-provider-integration.md`

## 1. 目标

1. 建立 `CloudProviderAdapter` 协议、provider registry 和 capability 模型。
2. 实现云账号配置、凭据写入 Keychain、凭据校验和账号启停。
3. 首批实现 Tencent Cloud 只读 adapter：地域查询、CVM 实例发现、基础实例元数据同步。
4. 支持云实例与 SSH server profile 的关联、导入和解除关联。
5. 在服务器列表中展示来源：手动 SSH / 腾讯云 / 后续云厂商。
6. 实现简化命令面板：输入命令、执行、展示 stdout/stderr/exit code、保存命令历史。
7. 建立云 API 错误归一化、限流、取消和本地操作日志基础。

## 2. 非目标

- 不实现阿里云、华为云的正式 adapter，只保留接口扩展点。
- 不做安全组修改、电源操作、快照、云盘和计费。
- 不做完整 PTY 终端。
- 不做 Dashboard 图表。
- 不让云账号成为使用应用的必要条件。

## 3. 技术约束

- 云 API 凭据必须存入 macOS Keychain，SQLite 只保存 `keychain_ref`。
- 默认权限建议为只读；写操作权限档位留到 Phase 4 以后。
- 所有云 API 请求必须有超时、取消和 provider 级限流。
- Tencent Cloud SDK 或签名客户端在实现前重新验证当前版本、Swift 兼容性和 macOS App Sandbox 行为。
- 命令面板只能复用 Phase 1 的 `SSHConnection.execute`，不引入 PTY。

## 4. 数据模型

新增表：

```sql
CREATE TABLE cloud_provider_accounts (
    id TEXT PRIMARY KEY NOT NULL,
    provider_id TEXT NOT NULL,
    display_name TEXT NOT NULL,
    keychain_ref TEXT NOT NULL,
    enabled INTEGER NOT NULL DEFAULT 1,
    created_at DATETIME NOT NULL,
    updated_at DATETIME NOT NULL
);

CREATE TABLE cloud_instance_links (
    id TEXT PRIMARY KEY NOT NULL,
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

CREATE TABLE command_history (
    id TEXT PRIMARY KEY NOT NULL,
    server_id TEXT NOT NULL REFERENCES server_profiles(id) ON DELETE CASCADE,
    command TEXT NOT NULL,
    exit_code INTEGER,
    duration_ms INTEGER,
    created_at DATETIME NOT NULL
);

CREATE TABLE operation_logs (
    id TEXT PRIMARY KEY NOT NULL,
    scope TEXT NOT NULL,
    action TEXT NOT NULL,
    target_id TEXT,
    status TEXT NOT NULL,
    message TEXT,
    created_at DATETIME NOT NULL
);
```

`raw_json` 只保存云实例兼容字段，不允许写入密钥、token 或完整请求头。

## 5. 模块设计

- `CloudProviderRegistry`：注册 adapter，按 provider id 查询能力。
- `CloudProviderAccountStore`：云账号 SQLite 元数据。
- `CloudCredentialStore`：云凭据 Keychain 读写。
- `CloudInstanceSyncService`：按账号和地域同步实例。
- `CloudInstanceLinkService`：云实例与 SSH server profile 关联。
- `CommandExecutionService`：复用 SSH 连接执行单条命令，记录历史和结果。

## 6. UI 范围

- 设置页新增“云账号”区域。
- 添加云账号 sheet：厂商、显示名、SecretId/SecretKey、默认地域。
- 云账号列表：启用状态、上次同步时间、能力状态、验证按钮、同步按钮。
- 服务器启动列表增加来源筛选：全部、手动 SSH、腾讯云。
- 云实例导入 flow：展示实例列表，选择实例后创建或关联 SSH server profile。
- 工作台新增简化命令面板：命令输入、执行按钮、输出区域、历史列表。

## 7. 实施任务

### Task 1：数据迁移

- [x] 添加 `command_history` 和 `operation_logs` 表，先支撑简化命令面板历史和审计基础。
- [x] 添加云账号和云实例关联表。
- [x] 为 provider/account/region/instance 建唯一约束。
- [x] 添加命令历史和操作日志 repository 单元测试。
- [x] 添加云账号和云实例关联 repository 单元测试。

### Task 2：云凭据存储

- [x] 扩展 KeychainService 支持云凭据命名空间。
- [x] 保存、读取、覆盖、删除 SecretId/SecretKey。
- [x] 云账号删除时清理 Keychain。
- [x] 测试 DB/Keychain 补偿逻辑。

### Task 3：Provider 基础设施

- [x] 定义 `CloudProviderID` 和 `CloudCapability`。
- [x] 定义 `CloudProviderAdapter`。
- [x] 实现 registry 和 adapter capability 查询。
- [x] 统一错误类型：认证失败、权限不足、限流、网络错误、provider 返回异常。
- [x] 添加请求超时和取消。

### Task 4：Tencent Cloud 只读 adapter

- [x] 验证当前 Tencent Cloud API/SDK 方案，采用 API 3.0 + TC3-HMAC-SHA256 直接签名请求。
- [x] 实现凭据校验入口，当前通过 Region 查询验证。
- [x] 实现地域列表。
- [x] 实现 CVM 实例列表和分页。
- [x] 归一化实例状态、IP、规格、地域、可用区、VPC。
- [x] 为 API 响应解析添加 fixture 测试，不提交真实凭据。

### Task 5：实例同步和关联

- [x] 实现手动同步服务入口。
- [x] 实现增量 upsert，并保留已有 SSH profile 关联。
- [x] 支持云实例创建 SSH profile。
- [x] 支持已有 SSH profile 关联云实例。
- [x] 解除关联时不删除 SSH profile，除非用户明确删除服务器。
- [x] 接入云账号设置和实例导入 UI 基础版。
- [ ] 使用真实腾讯云只读账号完成手动验收。

### Task 6：简化命令面板

- [x] 实现命令输入、执行状态、取消、输出展示。
- [x] 持久化 command、exit code、duration、created at 等命令元数据。
- [x] 明确 stdout/stderr 默认只保留在本次会话中，不写入 SQLite。
- [x] stdout/stderr 分开展示。
- [x] 保存命令历史，不保存包含疑似密钥的命令输出。
- [x] 支持重复执行历史命令。
- [x] 命令执行失败时展示 exit code 和 stderr。

### Task 7：测试

- [x] 云账号 repository 测试。
- [x] 云凭据 Keychain 测试。
- [x] Tencent Cloud response parser 测试。
- [x] 实例同步 upsert 测试。
- [x] 命令历史测试。
- [x] 命令面板 ViewModel 测试。
- [x] 云账号验证失败 ViewModel 测试：厂商凭据校验失败时不创建账号、不清空待修正密钥输入。

### Task 8：手动验收

- [ ] 添加腾讯云只读账号，凭据写入 Keychain。
- [ ] 使用真实腾讯云账号验证失败时不保存无效凭据。
- [ ] 同步 CVM 实例并在服务器列表看到云来源。
- [ ] 将云实例关联到 SSH profile。
- [ ] 手动 SSH 服务器在无云账号时仍可正常使用。
- [ ] 命令面板执行 `uname -a` 并展示 stdout、exit code。
- [ ] 命令历史可重复执行。

## 8. 完成标志

1. 云账号和云实例数据模型稳定。
2. 腾讯云只读实例发现可用。
3. 云凭据只在 Keychain。
4. 云实例可以导入或关联 SSH profile。
5. 简化命令面板基于真实 SSH execute 工作。
6. 单元测试和手动验收通过。

## 9. 后续 Phase 边界

- Phase 3 才做 Dashboard 图表、云监控指标聚合和 SFTP 文件管理。
- Phase 4 才做安全组写操作和系统环境配置。
- Phase 7 才扩展更多云厂商和高级云资源能力。
