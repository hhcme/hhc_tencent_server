# 云厂商 API 增强层设计

> HHC Server Manager 的核心仍然是 SSH-first。云厂商 API 作为可选增强层，用来获取 SSH 无法稳定获得、或通过云平台更方便获得的资源信息和控制能力。

## 1. 背景

早期设计强调“不依赖云厂商 API”，这样可以保证项目对任意 Linux 服务器都可用。但主流云厂商都提供 ECS/CVM 实例查询、云监控、安全组、快照、开关机等 API。如果完全不用这些能力，会错过一些明显更好的体验：

- 自动发现账号下的服务器。
- 自动同步实例 ID、地域、可用区、公网 IP、内网 IP、规格和运行状态。
- 查看云监控指标，不只依赖服务器内部命令。
- 管理安全组端口，比手写 iptables/firewalld 更贴近云网络边界。
- 执行开机、关机、重启、快照等云资源操作。

因此项目方向调整为：

> **SSH-first + optional Cloud API enhancement**
>
> SSH 是所有服务器管理能力的基础路径；云 API 是用户显式配置凭据后启用的增强能力。

## 2. 设计原则

- **SSH 仍是核心**：没有云 API 凭据时，应用仍然可以管理手动添加的服务器。
- **云 API 可选**：用户不配置云账号，不影响 SSH、文件、部署、服务管理等基础功能。
- **统一 UI，不按厂商分叉**：UI 面向通用能力，例如“实例发现”“云监控”“安全组”，具体厂商差异由 adapter 吸收。
- **最小权限**：云 API 凭据只申请所需权限，优先 read-only；危险操作单独授权。
- **凭据安全**：云 API SecretId/SecretKey、AccessKey、Token 等都存入 macOS Keychain。
- **能力探测**：不同厂商和不同账号权限不一致，功能入口必须基于 capability 展示。
- **状态来源标注**：SSH 采集的是服务器内部状态，云 API 返回的是云资源状态，两者可能不一致，UI 要标明来源。

## 3. 适合云 API 的能力

| 能力 | 说明 | 优先级 |
|------|------|--------|
| 实例发现 | 从云账号导入 CVM/ECS 列表 | 高 |
| 实例元数据 | 实例 ID、地域、可用区、规格、镜像、计费类型 | 高 |
| 网络信息 | 公网 IP、内网 IP、VPC、子网、EIP | 高 |
| 实例状态 | running/stopped/stopping/starting/frozen 等 | 高 |
| 云监控 | CPU、网络、云盘等云平台指标 | 中 |
| 电源操作 | 开机、关机、重启 | 中，危险操作 |
| 安全组 | 查看规则、开放/关闭端口 | 中，危险操作 |
| 云盘和快照 | 云盘列表、快照创建/查看 | 后续 |
| 费用和到期 | 计费类型、到期/欠费/冻结状态 | 后续 |

## 4. 仍然应该走 SSH 的能力

| 能力 | 原因 |
|------|------|
| systemd 服务管理 | 操作系统内部状态，云 API 不通用 |
| Nginx 配置 | 文件和进程在服务器内部 |
| Cron | 用户级或系统级任务在服务器内部 |
| 环境变量 | 服务器内部配置 |
| 文件管理 | 需要 SFTP/SSH |
| GitLab 部署 | 依赖远程目录、git、脚本和运行时 |
| 进程列表 | 云监控不能替代 `ps`/`top` 级别细节 |
| 私有包仓库安装 | 需要服务器内部命令和文件写入 |

## 5. 架构

```text
UI
├── Server Management
│   ├── SSH Core
│   │   ├── SSHConnection
│   │   ├── CommandExecutor
│   │   ├── HostKeyTrustStore
│   │   └── SFTPClient (Phase 3)
│   └── Cloud Provider Layer
│       ├── CloudProviderRegistry
│       ├── CloudProviderAccountStore
│       ├── CloudInstanceSyncService
│       └── CloudMetricService
└── Provider Adapters
    ├── TencentCloudAdapter
    ├── AlibabaCloudAdapter
    ├── HuaweiCloudAdapter
    └── ManualSSHAdapter
```

`ManualSSHAdapter` 表示没有云账号来源的手动服务器。它不调用云 API，只让 UI 统一处理“云增强能力不可用”的状态。

## 6. Adapter 协议

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

能力枚举：

```swift
enum CloudCapability: String, Codable, CaseIterable {
    case instanceInventory
    case instanceMetadata
    case basicMetrics
    case powerControl
    case securityGroups
    case disks
    case snapshots
    case billingInfo
}
```

危险操作：

```swift
enum CloudInstanceAction: String, Codable, CaseIterable {
    case start
    case stop
    case reboot
    case createSnapshot
    case updateSecurityGroup
}
```

所有 `CloudInstanceAction` 都必须二次确认并写入本地操作日志。

## 7. 数据模型

```sql
CREATE TABLE cloud_provider_accounts (
    id TEXT PRIMARY KEY,
    provider_id TEXT NOT NULL,          -- tencent | alibaba | huawei | manual
    display_name TEXT NOT NULL,
    keychain_ref TEXT NOT NULL,
    enabled INTEGER NOT NULL DEFAULT 1,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP
);

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
```

说明：

- `server_profiles` 是 SSH 管理对象。
- `cloud_instance_links` 是云资源对象。
- 一个云实例可以关联一个 SSH server profile，也可以先作为“未配置 SSH”的云资源存在。
- `raw_json` 仅用于排查字段兼容性，不能存储密钥或敏感凭据。

Keychain 建议：

| Key | Value |
|-----|-------|
| `cloud_tencent_secret_id_<keychain_ref>` | Tencent Cloud SecretId |
| `cloud_tencent_secret_key_<keychain_ref>` | Tencent Cloud SecretKey |
| `cloud_alibaba_access_key_id_<keychain_ref>` | Alibaba Cloud AccessKeyId |
| `cloud_alibaba_access_key_secret_<keychain_ref>` | Alibaba Cloud AccessKeySecret |
| `cloud_huawei_access_key_id_<keychain_ref>` | Huawei Cloud AccessKeyId |
| `cloud_huawei_secret_access_key_<keychain_ref>` | Huawei Cloud SecretAccessKey |

## 8. UI 设计

新增 “Cloud Accounts / 云账号” 设置页：

- 添加云账号。
- 选择厂商。
- 输入凭据并验证。
- 选择默认地域。
- 查看已启用 capability。
- 手动同步实例。

服务器列表增强：

- 支持“手动 SSH”“腾讯云”“阿里云”“华为云”分组。
- 云导入服务器显示云实例状态。
- 未配置 SSH 的云实例可以显示“配置 SSH”入口。
- 已关联 SSH 的云实例同时显示云状态和 SSH 状态。

实例详情增强：

- 云资源信息区：实例 ID、地域、可用区、规格、网络、计费类型。
- 状态来源标识：Cloud API / SSH。
- 云监控图表：如 CPU、网络、云盘基础指标。
- 危险操作按钮：开机、关机、重启、安全组修改，均二次确认。

## 9. 厂商首批适配建议

### Tencent Cloud

优先级最高。原因：

- 项目名已经是 `hhc_tencent_server`。
- CVM `DescribeInstances` 可用于实例发现。
- Cloud Monitor `GetMonitorData` 可用于云监控。

### Alibaba Cloud

第二优先级。ECS `DescribeInstances` 和 CloudMonitor 能覆盖实例发现与监控。

### Huawei Cloud

第三优先级。ECS 查询和 Cloud Eye 监控能力可作为基础增强。

## 10. 权限策略

先定义两个权限档位：

### Read-only / 只读

用于：

- 列出地域。
- 查询实例。
- 查询基础监控。
- 查询安全组。

### Operator / 操作

用于：

- 开机。
- 关机。
- 重启。
- 修改安全组。
- 创建快照。

默认只建议用户配置 read-only 权限。进入危险操作前，UI 提示需要额外权限。

## 11. Phase 调整

- **Phase 1**：不接入云 API，只完成真实 SSH MVP。
- **Phase 2**：加入 Cloud Provider 基础模型、云账号管理、腾讯云只读实例发现。
- **Phase 3**：Dashboard 聚合 SSH 指标和云监控指标，同时推进 SFTP 技术验证。
- **Phase 4**：安全组管理和系统环境配置。
- **Phase 5**：GitLab 部署。
- **Phase 6**：私有包仓库。
- **Phase 7**：更多云厂商、快照、云盘、计费和高级资源管理。

## 12. 参考 API

- Tencent Cloud CVM `DescribeInstances`: https://www.tencentcloud.com/document/product/213/33258
- Tencent Cloud Monitor `GetMonitorData`: https://www.tencentcloud.com/document/product/248/33881
- Alibaba Cloud ECS `DescribeInstances`: https://www.alibabacloud.com/help/en/ecs/developer-reference/api-ecs-2014-05-26-describeinstances
- Alibaba Cloud CloudMonitor `DescribeMetricList`: https://api.alibabacloud.com/api/Cms/2019-01-01/DescribeMetricList
- Huawei Cloud ECS detail query: https://support.huaweicloud.com/intl/en-us/api-ecs/ecs_02_0104.html
- Huawei Cloud Eye metric data query: https://support.huaweicloud.com/intl/en-us/api-ces/ces_03_0033.html
