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
- 所有云 API 请求必须限流、可取消、可审计；当前三家云 adapter 的 HTTP 出口已统一通过 `CloudProviderRequestRunner` 执行超时和 `CloudProviderRequestLimiter` 并发节流，等待中的请求取消时会从 limiter 队列移除，危险写操作通过 `remote_change_logs` 审计。

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
- 已新增 `AlibabaCloudAdapter` 和 `HuaweiCloudAdapter`，支持签名后的只读地域/项目发现、ECS 实例发现、分页和核心字段映射，并通过 fixture 测试覆盖请求签名与解析；阿里云已补 ECS `DescribeDisks` 云盘只读同步、`DescribeSnapshots` 快照只读同步、`AttachDisk` / `DetachDisk` 云盘挂载/卸载、CMS `DescribeMetricList` CPU 指标查询、`DescribeSecurityGroups` / `DescribeSecurityGroupAttribute` 安全组和规则只读同步，以及 `AuthorizeSecurityGroup` / `AuthorizeSecurityGroupEgress` / `RevokeSecurityGroup` / `RevokeSecurityGroupEgress` 单条规则新增/删除；华为云已补 ECS `os-start` / `os-stop` / `reboot` 实例启动/停止/重启、CES `metric-data` CPU 指标查询、ECS/EVS 派生计费状态同步、EVS `cloudvolumes/detail` 云盘只读同步、EVS `snapshots/detail` 快照只读同步、EVS `cloudsnapshots` 快照创建/删除、EVS `os-attach` / `os-detach` 云盘挂载/卸载、VPC `security-groups` / `security-group-rules` 安全组和规则同步，以及 VPC v3 `security-group-rules` 单条规则创建/删除。
- 已泛化 macOS 云导入入口，三家云账号可在同一流程中选择 provider、验证凭据、加载地域/项目、同步实例并导入 SSH profile。
- 已为腾讯云 CBS 接入快照创建/删除操作，云资源中心会按 `snapshotActions` capability 展示操作、执行风险确认、更新本地缓存，并写入 `remote_change_logs` 云端变更审计。
- 已为阿里云 ECS 接入快照创建/删除操作，云资源中心会按 `snapshotActions` capability 展示操作，`accomplished` 快照可删除，执行后更新本地缓存并写入 `remote_change_logs` 云端变更审计。
- 已为华为云 EVS 接入快照创建/删除操作，云资源中心会按 `snapshotActions` capability 展示操作，`available` 快照可删除，执行后更新本地缓存并写入 `remote_change_logs` 云端变更审计。
- 已为腾讯云 CBS 接入云盘挂载/卸载操作，云资源中心会按 `diskAttachmentActions` capability 展示操作；挂载仅允许 `UNATTACHED`/`DETACHED` 云盘，卸载仅允许 `ATTACHED` 云盘，执行后本地缓存进入 `ATTACHING`/`DETACHING` 并写入云端变更审计。
- 已为阿里云 ECS 接入云盘挂载/卸载操作，云资源中心会按 `diskAttachmentActions` capability 展示操作；挂载仅允许 `Available` 云盘，卸载仅允许 `In_use` 云盘，执行后本地缓存进入 `ATTACHING`/`DETACHING` 并写入云端变更审计。
- 已为华为云 EVS 接入云盘挂载/卸载操作，云资源中心会按 `diskAttachmentActions` capability 展示操作；挂载仅允许 `available` 云盘，卸载仅允许 `in-use` 云盘，执行后本地缓存进入 `ATTACHING`/`DETACHING` 并写入云端变更审计。
- 已为腾讯云 CVM 接入实例启动、停止、重启操作，云资源中心会按 `powerActions` capability 展示操作；启动仅允许 `STOPPED` 实例，停止/重启仅允许 `RUNNING` 实例，执行后本地缓存进入 `STARTING`/`STOPPING`/`REBOOTING` 并写入云端变更审计。
- 已为阿里云 ECS 接入实例启动、停止、重启操作，云资源中心会按 `powerActions` capability 展示操作；启动仅允许 `Stopped` 实例，停止/重启仅允许 `Running` 实例，执行后本地缓存进入 `STARTING`/`STOPPING`/`REBOOTING` 并写入云端变更审计。
- 已为华为云 ECS 接入实例启动、停止、重启操作，云资源中心会按 `powerActions` capability 展示操作；启动允许 `SHUTOFF` 实例，停止/重启允许 `ACTIVE` 实例，停止/重启默认使用 `SOFT`，执行后本地缓存进入 `STARTING`/`STOPPING`/`REBOOTING` 并写入云端变更审计。
- 已统一云资源操作状态门禁，服务层和云资源中心 UI 共用 provider-aware 策略，避免阿里云 `Available` / `In_use`、华为云 `ACTIVE` / `SHUTOFF` / `in-use` 等状态被腾讯云状态规则误禁用。
- 已为阿里云 ECS 接入安全组单条规则新增/删除操作，云资源中心会按 `securityGroupActions` capability 展示操作；规则参数复用统一预览模型，`443` 这类单端口会自动转为 `443/443`，执行后刷新规则快照并复用远程变更审计。
- 已为华为云 VPC 接入安全组单条规则创建/删除操作，云资源中心会按 `securityGroupActions` capability 展示操作；规则读取会保留 `providerRuleId`，删除时使用华为云 rule id 精确定位，执行后刷新规则快照并复用远程变更审计。
- 已将云资源中心危险操作的确认预览改为 provider-aware：腾讯云、阿里云、华为云分别展示对应 API/action 形态，避免跨云操作确认时误显示腾讯云命令名。
- 已为云资源中心加入运行时能力降级：当可选资源同步或危险云操作遇到权限不足、unauthorized/forbidden/denied 类 provider failure 或 adapter capability 缺失时，当前会话内对应 provider capability 会标记为 disabled，能力矩阵显示黄色警告，相关操作入口禁用并展示原因；非权限类 provider failure 不会误降级。
- 已为云资源中心危险操作加入成功后的 best-effort provider 刷新：快照操作后刷新快照，云盘挂载/卸载后刷新云盘，实例电源操作后刷新实例；刷新失败不会推翻已成功提交的写操作，会保留本地过渡态并提示刷新失败。
- 已为三家云 HTTP 请求统一加入共享并发节流器；默认最多 4 个云 API 请求同时进入 provider transport，测试可注入独立 limiter 覆盖并发上限，并覆盖等待中请求取消后不泄漏并发槽。

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
- [x] 实现 ECS `CreateSnapshot` / `DeleteSnapshot` 快照创建和删除操作。
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
- [x] 腾讯云实例安全组绑定 ID 同步，用于关联服务器的安全组精确过滤。
- [x] 阿里云云盘按 capability 补只读同步。
- [x] 阿里云快照按 capability 补只读同步。
- [x] 阿里云安全组按 capability 补只读同步。
- [x] 阿里云实例安全组绑定 ID 同步，用于关联服务器的安全组精确过滤。
- [x] 阿里云安全组单条规则新增/删除操作。
- [x] 华为云 EVS 云盘按 capability 补只读同步。
- [x] 华为云 EVS 快照按 capability 补只读同步。
- [x] 华为云安全组按 capability 补同类只读能力。
- [x] 华为云实例安全组绑定 ID 同步，用于关联服务器的安全组精确过滤。
- [x] 华为云安全组单条规则创建/删除操作。

### Task 5：高级操作

- [x] 腾讯云创建快照操作。
- [x] 腾讯云删除快照操作。
- [x] 阿里云创建快照操作。
- [x] 阿里云删除快照操作。
- [x] 华为云创建快照操作。
- [x] 华为云删除快照操作。
- [x] 腾讯云云盘挂载/卸载操作。
- [x] 阿里云云盘挂载/卸载操作。
- [x] 华为云云盘挂载/卸载操作。
- [x] 腾讯云实例启动/停止/重启操作。
- [x] 阿里云实例启动/停止/重启操作。
- [x] 华为云实例启动/停止/重启操作。
- [x] 已接入的危险云操作写入变更审计日志。

### Task 6：云资源中心 UI

- [x] 资源搜索和过滤服务。
- [x] 高级资源详情页。
- [x] capability matrix 展示。
- [x] 三家云账号导入入口。
- [x] 三家云快照操作风险确认：确认弹窗包含 provider-aware API/action 预览。
- [x] 三家云云盘挂载/卸载风险确认：确认弹窗包含 provider-aware API/action 预览。
- [x] 三家云实例电源操作风险确认：确认弹窗包含 provider-aware API/action 预览。
- [x] 权限不足时运行时自动降级 provider capability，并在能力矩阵和资源详情操作区展示原因。
- [x] 危险云操作成功提交后按资源类型尽力刷新 provider 状态，刷新失败时保留提交成功结果并提示。

### Task 7：测试

- [x] Provider adapter 契约测试。
- [x] 三家云实例解析测试。
- [x] 云盘/快照/计费解析测试。
- [x] 跨云搜索测试。
- [x] 云 API 请求超时、并发节流和等待队列取消测试。
- [x] 腾讯云快照危险操作确认和审计测试。
- [x] 腾讯云云盘挂载/卸载请求、状态缓存和审计测试。
- [x] 腾讯云实例电源操作请求、状态缓存和审计测试。
- [x] 三家云危险操作风险确认文案测试，覆盖阿里云快照/云盘和华为云实例电源操作的 provider-aware 预览。
- [x] 危险云操作失败路径测试：覆盖快照创建、云盘挂载和实例电源操作失败时写入 failed 审计日志，且不污染本地快照、云盘和实例状态缓存。
- [x] 云资源中心运行时权限降级 ViewModel 测试，覆盖 permission denied 降级和非权限错误不降级。
- [x] 云资源中心本地筛选 ViewModel 测试，覆盖 account、region、kind、status、text filter 和过滤结果变化后的 selected resource 重置。
- [x] 云资源中心操作后刷新 ViewModel 测试，覆盖云盘挂载成功后从本地 `ATTACHING` 过渡态刷新为 provider 返回的 `ATTACHED` 状态。
- [x] 真实多云只读同步 opt-in 集成测试入口：`CloudIntegrationTests` 默认跳过，启用 `HHC_TEST_CLOUD_REAL=1` 和对应云厂商只读凭据后会验证 credential、region/project、实例、云盘、快照、计费同步和统一资源作用域。

### Task 8：手动验收

- [ ] 腾讯云、阿里云、华为云账号都可只读同步实例。当前已有受保护真实集成测试入口，等待真实只读账号凭据执行验收。
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
- [x] 权限不足时能力自动降级。当前已通过 ViewModel/contract 测试覆盖运行时降级，真实云账号权限档位验收仍需继续补齐。

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
