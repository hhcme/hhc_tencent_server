# Cloud Provider API Enhancement Layer

> HHC Server Manager remains SSH-first. Cloud provider APIs are optional enhancements for resource discovery, cloud-side metadata, monitoring, security groups, and power operations.

## 1. Background

The original design emphasized avoiding cloud vendor APIs so any Linux server could be managed through SSH. That remains important. However, major cloud vendors expose APIs for instance inventory, cloud monitoring, security groups, snapshots, and power actions. Ignoring those APIs would make the product less useful for cloud-hosted servers.

The adjusted direction is:

> **SSH-first + optional Cloud API enhancement**
>
> SSH is the universal management path. Cloud APIs become available only after the user explicitly configures provider credentials.

## 2. Principles

- **SSH remains core**: manual SSH servers work without any cloud account.
- **Cloud APIs are optional**: not configuring cloud credentials must not break SSH, files, deployment, or service management.
- **One UI, multiple adapters**: the UI targets generic capabilities such as inventory, metrics, security groups, and power control.
- **Least privilege**: prefer read-only credentials. Dangerous operations require extra permissions.
- **Secure credentials**: provider secrets live in macOS Keychain.
- **Capability-driven UI**: features appear only when the selected provider and account support them.
- **Source-aware state**: SSH state and cloud-resource state can differ, so the UI must show the data source.

## 3. Good Cloud API use cases

| Capability | Description | Priority |
|------------|-------------|----------|
| Instance inventory | Import CVM/ECS instances from cloud accounts | High |
| Metadata | Instance ID, region, zone, type, image, billing mode | High |
| Network info | public IP, private IP, VPC, subnet, EIP | High |
| Instance status | running, stopped, frozen, starting, stopping | High |
| Cloud metrics | CPU, network, cloud disk metrics | Medium |
| Power actions | start, stop, reboot | Medium, dangerous |
| Security groups | view and update ingress rules | Medium, dangerous |
| Disks and snapshots | list disks, create/view snapshots | Later |
| Billing and expiry | billing type, expiration, arrears/frozen state | Later |

## 4. SSH-owned capabilities

| Capability | Reason |
|------------|--------|
| systemd service management | OS-internal state |
| Nginx configuration | Files and process live on the server |
| Cron | User/system task files live on the server |
| Environment variables | OS-level configuration |
| File manager | Requires SSH/SFTP |
| GitLab deployment | Depends on remote directories, git, scripts, and runtimes |
| Process list | Cloud metrics cannot replace process-level detail |
| Private registry installation | Requires remote commands and file writes |

## 5. Architecture

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

`ManualSSHAdapter` represents manually added servers. It does not call provider APIs, but it lets the UI show cloud enhancement features as unavailable in a consistent way.

## 6. Adapter protocol

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

Capabilities:

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

Dangerous actions:

```swift
enum CloudInstanceAction: String, Codable, CaseIterable {
    case start
    case stop
    case reboot
    case createSnapshot
    case updateSecurityGroup
}
```

All `CloudInstanceAction` operations require confirmation and local audit logging.

## 7. Data model

```sql
CREATE TABLE cloud_provider_accounts (
    id TEXT PRIMARY KEY,
    provider_id TEXT NOT NULL,
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

`server_profiles` are SSH management targets. `cloud_instance_links` are cloud resources. A cloud instance may be linked to an SSH profile, or it may exist as an imported cloud resource waiting for SSH configuration.

Keychain suggestions:

| Key | Value |
|-----|-------|
| `cloud_tencent_secret_id_<keychain_ref>` | Tencent Cloud SecretId |
| `cloud_tencent_secret_key_<keychain_ref>` | Tencent Cloud SecretKey |
| `cloud_alibaba_access_key_id_<keychain_ref>` | Alibaba Cloud AccessKeyId |
| `cloud_alibaba_access_key_secret_<keychain_ref>` | Alibaba Cloud AccessKeySecret |
| `cloud_huawei_access_key_id_<keychain_ref>` | Huawei Cloud AccessKeyId |
| `cloud_huawei_secret_access_key_<keychain_ref>` | Huawei Cloud SecretAccessKey |

## 8. UI

Cloud Accounts settings:

- Add provider account.
- Choose provider.
- Enter and validate credentials.
- Select default regions.
- View enabled capabilities.
- Sync instances manually.

Server list enhancements:

- Group by manual SSH, Tencent Cloud, Alibaba Cloud, and Huawei Cloud.
- Show cloud instance status for imported resources.
- Show a "Configure SSH" entry for imported instances without SSH profiles.
- Show both cloud status and SSH status for linked instances.

Instance detail enhancements:

- Cloud metadata: instance ID, region, zone, type, network, billing.
- Data-source labels: Cloud API / SSH.
- Cloud metrics charts.
- Dangerous actions with confirmation: start, stop, reboot, security group updates.

## 9. Provider priority

1. **Tencent Cloud**: first adapter because of the repository focus. CVM `DescribeInstances` supports inventory, and Cloud Monitor `GetMonitorData` supports metrics.
2. **Alibaba Cloud**: ECS `DescribeInstances` and CloudMonitor cover inventory and monitoring.
3. **Huawei Cloud**: ECS details and Cloud Eye metrics cover the basic enhancement layer.

## 10. Permission strategy

Start with two permission levels:

### Read-only

Used for regions, instance inventory, basic metrics, and security group viewing.

### Operator

Used for power operations, security group updates, snapshot creation, and other destructive or billable actions.

The app should recommend read-only credentials by default. Dangerous operations should explain that extra permissions are required.

## 11. Phase updates

- **Phase 1**: no cloud API integration; complete the real SSH MVP.
- **Phase 2**: add provider models, cloud account settings, and read-only Tencent Cloud instance discovery.
- **Phase 3**: dashboard that can combine SSH metrics and cloud metrics, plus SFTP validation.
- **Phase 4**: security group management and server environment configuration.
- **Phase 5**: GitLab deployment.
- **Phase 6**: private package registries.
- **Phase 7**: more providers, snapshots, disks, billing, and advanced resource management.
- **Phase 8**: Windows native technical validation, reusing the cloud provider adapter domain model.

## 12. Reference APIs

- Tencent Cloud CVM `DescribeInstances`: https://www.tencentcloud.com/document/product/213/33258
- Tencent Cloud Monitor `GetMonitorData`: https://www.tencentcloud.com/document/product/248/33881
- Alibaba Cloud ECS `DescribeInstances`: https://www.alibabacloud.com/help/en/ecs/developer-reference/api-ecs-2014-05-26-describeinstances
- Alibaba Cloud CloudMonitor `DescribeMetricList`: https://api.alibabacloud.com/api/Cms/2019-01-01/DescribeMetricList
- Huawei Cloud ECS detail query: https://support.huaweicloud.com/intl/en-us/api-ecs/ecs_02_0104.html
- Huawei Cloud Eye metric data query: https://support.huaweicloud.com/intl/en-us/api-ces/ces_03_0033.html
