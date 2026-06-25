# Phase 7：高级云资源管理实施计划

> Phase 7 在已有腾讯云基础层上扩展更多云厂商和高级云资源能力。重点是 provider adapter 的一致性、能力矩阵、只读优先和危险操作审计。

**前置条件:** Phase 6 已完成，macOS 版核心 SSH、云账号、部署和包仓库能力稳定。

## 1. 目标

1. 实现 Alibaba Cloud 和 Huawei Cloud adapter 的只读实例发现。
2. 扩展 Tencent Cloud adapter：云盘、快照、基础计费/到期状态。
3. 建立跨云资源搜索和高级过滤。
4. 支持云盘、快照、备份等高级资源查看。
5. 对快照创建、云盘挂载/卸载等危险操作建立能力和确认框架。
6. 接入云实例启动、停止、重启等电源操作的能力门禁、确认和审计。
7. 补齐 provider capability matrix 和兼容测试 harness。

## 2. 非目标

- 不做所有云厂商的全量 API 覆盖。
- 不做 Terraform 替代品。
- 不做自动成本优化决策，只展示信息和风险提示。
- 不做跨云迁移。
- 不做负载均衡、RDS、对象存储等非服务器核心资源的深度管理。

## 3. 技术约束

- 新厂商默认只读接入，写操作必须单独 capability 和权限档位。
- provider adapter 必须吸收字段差异，UI 面向统一资源模型。
- 计费和到期状态来自云 API，必须标注刷新时间和可能延迟。
- 快照、云盘挂载、删除等操作必须二次确认。
- 所有云 API 请求必须限流、可取消、可审计。

## 4. 数据模型

```sql
CREATE TABLE cloud_disks (
    id TEXT PRIMARY KEY NOT NULL,
    account_id TEXT NOT NULL REFERENCES cloud_provider_accounts(id) ON DELETE CASCADE,
    provider_id TEXT NOT NULL,
    region_id TEXT NOT NULL,
    disk_id TEXT NOT NULL,
    instance_id TEXT,
    name TEXT,
    disk_type TEXT,
    size_gb INTEGER,
    status TEXT,
    billing_type TEXT,
    expired_time DATETIME,
    raw_json TEXT,
    last_synced_at DATETIME,
    UNIQUE(account_id, region_id, disk_id)
);

CREATE TABLE cloud_snapshots (
    id TEXT PRIMARY KEY NOT NULL,
    account_id TEXT NOT NULL REFERENCES cloud_provider_accounts(id) ON DELETE CASCADE,
    provider_id TEXT NOT NULL,
    region_id TEXT NOT NULL,
    snapshot_id TEXT NOT NULL,
    disk_id TEXT,
    name TEXT,
    status TEXT,
    size_gb INTEGER,
    created_at_provider DATETIME,
    raw_json TEXT,
    last_synced_at DATETIME,
    UNIQUE(account_id, region_id, snapshot_id)
);

CREATE TABLE cloud_billing_states (
    id TEXT PRIMARY KEY NOT NULL,
    account_id TEXT NOT NULL REFERENCES cloud_provider_accounts(id) ON DELETE CASCADE,
    provider_id TEXT NOT NULL,
    resource_type TEXT NOT NULL,
    resource_id TEXT NOT NULL,
    billing_type TEXT,
    expire_at DATETIME,
    status TEXT,
    raw_json TEXT,
    last_synced_at DATETIME,
    UNIQUE(account_id, provider_id, resource_type, resource_id)
);
```

## 5. 模块设计

- `ProviderCapabilityMatrix`：展示每个厂商每项能力状态。
- `CloudResourceSearchService`：跨账号、跨地域、跨厂商搜索。
- `CloudDiskService`：云盘列表和状态同步。
- `CloudSnapshotService`：快照列表、创建和状态轮询。
- `CloudBillingService`：计费类型、到期、欠费/冻结状态。
- `ProviderAdapterTestHarness`：统一 fixture 和契约测试。

当前已落地底座：

- 已新增统一模型：`CloudDisk`、`CloudSnapshot`、`CloudBillingState`、`CloudUnifiedResource`、`CloudResourceSearchQuery`。
- 已新增 SQLite 表和 Repository 读写：`cloud_disks`、`cloud_snapshots`、`cloud_billing_states`。
- 已新增 `ProviderCapabilityMatrixBuilder` 和 `CloudResourceSearchService`。
- 已扩展 `CloudInstanceSyncService`，支持腾讯云云盘、快照、计费状态同步入库，并从本地库加载统一云资源。
- 已新增 macOS 云资源中心，支持按账号/地域同步、跨资源搜索过滤、能力矩阵展示和资源详情查看。
- 已新增 `AlibabaCloudAdapter` 和 `HuaweiCloudAdapter`，支持签名后的只读地域/项目发现、ECS 实例发现、分页和核心字段映射，并通过 fixture 测试覆盖请求签名与解析；阿里云已补 ECS `DescribeDisks` 云盘只读同步、`DescribeSnapshots` 快照只读同步、`DescribeSecurityGroups` / `DescribeSecurityGroupAttribute` 安全组和规则只读同步，华为云已补 EVS `cloudvolumes/detail` 云盘只读同步、EVS `snapshots/detail` 快照只读同步、VPC `security-groups` / `security-group-rules` 安全组和规则只读同步。
- 已泛化 macOS 云导入入口，三家云账号可在同一流程中选择 provider、验证凭据、加载地域/项目、同步实例并导入 SSH profile。
- 已为腾讯云 CBS 接入快照创建/删除操作，云资源中心会按 `snapshotActions` capability 展示操作、执行风险确认、更新本地缓存，并写入 `remote_change_logs` 云端变更审计。
- 已为腾讯云 CBS 接入云盘挂载/卸载操作，云资源中心会按 `diskAttachmentActions` capability 展示操作；挂载仅允许 `UNATTACHED`/`DETACHED` 云盘，卸载仅允许 `ATTACHED` 云盘，执行后本地缓存进入 `ATTACHING`/`DETACHING` 并写入云端变更审计。
- 已为腾讯云 CVM 接入实例启动、停止、重启操作，云资源中心会按 `powerActions` capability 展示操作；启动仅允许 `STOPPED` 实例，停止/重启仅允许 `RUNNING` 实例，执行后本地缓存进入 `STARTING`/`STOPPING`/`REBOOTING` 并写入云端变更审计。

## 6. UI 范围

- 云资源中心：账号、厂商、地域、状态、标签、搜索。
- 服务器工作台云资源页：实例、云盘、快照、计费状态。
- Provider capability matrix 页面。
- 云盘详情：挂载实例、容量、类型、状态。
- 快照列表：状态、创建时间、来源云盘。
- 危险操作确认：创建快照、删除快照、挂载/卸载云盘、启动/停止/重启实例。

## 7. 实施任务

### Task 1：Adapter 契约

- [x] 明确实例、云盘、快照、计费的统一模型。
- [x] 定义 capability matrix。
- [x] 添加 adapter fixture 测试规范。
- [x] 现有 adapter 输出统一错误类型。

### Task 2：Alibaba Cloud adapter

- [x] 验证当前 SDK 或签名方案。
- [x] 实现凭据校验。
- [x] 实现地域和 ECS 实例发现。
- [x] 解析公网 IP、私网 IP、规格、状态。
- [x] 实现 ECS `DescribeDisks` 云盘只读同步。
- [x] 实现 ECS `DescribeSnapshots` 快照只读同步。
- [x] 实现 ECS `DescribeSecurityGroups` / `DescribeSecurityGroupAttribute` 安全组和规则只读同步。
- [x] 添加 fixture 测试。

### Task 3：Huawei Cloud adapter

- [x] 验证当前 SDK 或签名方案。
- [x] 实现凭据校验。
- [x] 实现地域和 ECS 实例发现。
- [x] 解析网络、状态和规格。
- [x] 实现 EVS `cloudvolumes/detail` 云盘只读同步。
- [x] 实现 EVS `snapshots/detail` 快照只读同步。
- [x] 实现 VPC `security-groups` / `security-group-rules` 安全组和规则只读同步。
- [x] 统一华为云实例/云盘落库 region id，确保云资源中心按项目地域筛选可见。
- [x] 添加 fixture 测试。

### Task 4：高级资源

- [x] 腾讯云云盘同步。
- [x] 腾讯云快照同步。
- [x] 腾讯云基础计费/到期状态同步。
- [x] 阿里云云盘按 capability 补只读同步。
- [x] 阿里云快照按 capability 补只读同步。
- [x] 阿里云安全组按 capability 补只读同步。
- [x] 华为云 EVS 云盘按 capability 补只读同步。
- [x] 华为云 EVS 快照按 capability 补只读同步。
- [x] 华为云安全组按 capability 补同类只读能力。

### Task 5：高级操作

- [x] 腾讯云创建快照操作。
- [x] 腾讯云删除快照操作。
- [ ] 阿里云、华为云快照操作按 capability 补齐。
- [x] 腾讯云云盘挂载/卸载操作。
- [ ] 阿里云、华为云云盘挂载/卸载按 capability 补齐。
- [x] 腾讯云实例启动/停止/重启操作。
- [ ] 阿里云、华为云实例电源操作按 capability 补齐。
- [x] 已接入的危险云操作写入变更审计日志。

### Task 6：云资源中心 UI

- [x] 资源搜索和过滤服务。
- [x] 高级资源详情页。
- [x] capability matrix 展示。
- [x] 三家云账号导入入口。
- [x] 腾讯云快照操作风险确认。
- [x] 腾讯云云盘挂载/卸载风险确认。
- [x] 腾讯云实例电源操作风险确认。

### Task 7：测试

- [x] Provider adapter 契约测试。
- [x] 三家云实例解析测试。
- [x] 云盘/快照/计费解析测试。
- [x] 跨云搜索测试。
- [x] 腾讯云快照危险操作确认和审计测试。
- [x] 腾讯云云盘挂载/卸载请求、状态缓存和审计测试。
- [x] 腾讯云实例电源操作请求、状态缓存和审计测试。

### Task 8：手动验收

- [ ] 腾讯云、阿里云、华为云账号都可只读同步实例。
- [x] 云资源中心能跨厂商搜索。
- [x] 腾讯云云盘和快照信息可展示。
- [x] 阿里云云盘信息可同步并进入云资源中心统一资源列表。
- [x] 阿里云快照信息可同步并进入云资源中心统一资源列表。
- [x] 华为云云盘信息可同步并进入云资源中心统一资源列表。
- [x] 华为云快照信息可同步并进入云资源中心统一资源列表。
- [x] 计费/到期状态有来源和刷新时间。
- [ ] 真实腾讯云账号创建快照需要二次确认并写日志。
- [ ] 真实腾讯云账号云盘挂载/卸载需要二次确认并写日志。
- [ ] 真实腾讯云账号实例启动/停止/重启需要二次确认并写日志。
- [ ] 权限不足时能力自动降级。

## 8. 完成标志

1. 多云只读实例发现可用。
2. 云资源中心可跨云搜索。
3. 云盘、快照、计费状态基础能力可用。
4. 危险云操作有 capability、确认、日志和错误处理。
5. Adapter 契约测试覆盖核心字段。
6. 测试和手动验收通过。

## 9. 后续 Phase 边界

- Phase 8 才启动 Windows 原生版技术验证。
- 跨云迁移、负载均衡、数据库、对象存储等能力另行立项，不放入当前路线图。
