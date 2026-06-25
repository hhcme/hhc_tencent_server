# Phase 4：安全组 + 环境配置实施计划

> Phase 4 开始进入会修改远端环境和云网络边界的能力。所有写操作必须有能力探测、权限检查、预览、二次确认、操作日志和失败恢复说明。

**前置条件:** Phase 3 已完成，Dashboard、能力探测和文件管理器稳定。

## 1. 目标

1. 通过云 provider adapter 管理安全组查看和有限写操作。
2. 实现 systemd 服务查看、启动、停止、重启和日志查看。
3. 实现 Nginx 配置查看、测试、启用、回滚。
4. 实现防火墙规则查看和有限管理。
5. 实现 Cron 任务查看、添加、禁用、删除。
6. 实现环境变量文件管理和变更记录。
7. 建立远程变更审计日志和危险操作确认框架。

## 2. 非目标

- 不做 GitLab 部署。
- 不做私有包仓库。
- 不做跨云高级资源管理。
- 不尝试覆盖所有 Linux 发行版，只对已探测能力启用功能。
- 不在没有明确回滚路径时执行复杂配置改写。

## 3. 技术约束

- 安全组写操作必须基于 provider capability 和账号权限展示。
- systemd/Nginx/firewall/cron 都必须通过 adapter 或 capability model，不写死单一发行版。
- 修改配置前必须读取当前内容并保存本地变更记录。
- Nginx 配置保存后必须先执行测试命令，测试通过才 reload。
- 防火墙规则不能默认开放危险端口范围。
- 所有远程写操作必须有 timeout、stderr 捕获和操作日志。

## 4. 数据模型

新增表：

```sql
CREATE TABLE remote_change_logs (
    id TEXT PRIMARY KEY NOT NULL,
    server_id TEXT REFERENCES server_profiles(id) ON DELETE SET NULL,
    provider_id TEXT,
    target_type TEXT NOT NULL,
    target_id TEXT,
    action TEXT NOT NULL,
    before_snapshot TEXT,
    after_snapshot TEXT,
    status TEXT NOT NULL,
    message TEXT,
    created_at DATETIME NOT NULL
);

CREATE TABLE environment_profiles (
    id TEXT PRIMARY KEY NOT NULL,
    server_id TEXT NOT NULL REFERENCES server_profiles(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    file_path TEXT NOT NULL,
    last_loaded_at DATETIME,
    UNIQUE(server_id, file_path)
);
```

## 5. 模块设计

- `CloudSecurityGroupService`：云安全组读取、规则读取、规则 diff 和支持 provider 的单条写操作提交。
- `SystemdServiceManager`：服务列表、状态、start/stop/restart、journal 日志。
- `NginxConfigManager`：站点配置读取、编辑、测试、reload、回滚。
- `FirewallAdapter`：ufw/firewalld/iptables/nftables 能力探测和有限操作。
- `CronManager`：crontab 读取、编辑、禁用、恢复。
- `EnvironmentFileManager`：常见 `.env`、`/etc/default`、`/etc/sysconfig` 和 systemd drop-in env file 的受限发现、读取、备份保存。
- `RemoteChangeLogStore`：所有写操作审计。

## 6. UI 范围

- 工作台新增“安全组”页，仅云实例关联且账号有能力时启用。
- 工作台新增“服务”页：systemd 服务列表、状态、操作按钮、日志。
- 工作台新增“Nginx”页：配置文件列表、编辑、测试、reload、回滚。
- 工作台新增“防火墙”页：展示当前探测到的防火墙后端和规则。
- 工作台新增“Cron”页：任务列表、启用/禁用、编辑。
- 工作台新增“环境变量”页：常用 env 文件管理。
- 所有危险操作使用统一风险模型和确认入口，展示命令、目标、影响范围和恢复说明。

## 7. 实施任务

### Task 1：危险操作框架

- [x] 定义 `RemoteOperationRisk` 和确认模型：当前已覆盖远程文件删除/权限修改、systemd、Cron、Nginx、Environment 的风险级别、目标、命令预览、影响和恢复说明。
- [x] 所有写操作写入 `remote_change_logs`：当前 systemd、Cron、Nginx、Environment、Firewall 和腾讯云 Security Groups 写操作已记录 before/after/status/message。
- [x] 操作失败时保存 stderr 和上下文：当前 systemd、Cron、Nginx、Environment 和 Firewall 失败会记录 before snapshot 与错误 message。
- [x] UI 展示操作预览和风险说明：当前现有危险确认弹窗已使用统一风险文案，chmod 权限修改 sheet 已展示风险预览。

### Task 2：安全组

- [x] 扩展 CloudProviderAdapter 支持安全组读取：当前 provider capability 已包含 `securityGroups`，并接入 `CloudSecurityGroupService`。
- [x] 腾讯云安全组规则读取：当前通过 VPC `DescribeSecurityGroups` / `DescribeSecurityGroupPolicies` 读取账号地域下的安全组和规则。
- [x] 规则 diff 和预览：当前已支持本地生成安全组规则新增/删除 diff、before/after 计数、风险级别、命令预览和警告。
- [x] 有限写操作：腾讯云已支持新增/删除单条 ingress/egress 规则，并在执行前确认风险。
- [x] 权限不足时明确提示：安全组读取、规则读取和规则变更会把 provider 权限错误转换为包含所需读/写权限、provider 名称和原始错误信息的用户提示，并在规则变更失败时写入审计日志。
- [x] 实例精确安全组过滤：实例同步会持久化 provider 返回的安全组 ID，安全组页优先只展示当前服务器关联实例绑定的安全组；旧数据或 provider 未返回绑定关系时降级展示账号地域安全组列表。

### Task 3：systemd

- [x] 探测 systemd 可用性：`systemctl` 不存在时返回明确错误，Dashboard 也会探测 systemd capability。
- [x] 服务列表和状态解析：解析 unit、load、active、sub 和 description，并优先显示 active 服务。
- [x] start/stop/restart/reload 操作：限制为简单 `.service` unit 名，UI 操作前弹出确认。
- [x] journal 日志读取：支持读取选中 service 的最近 journal。
- [x] 非 systemd 系统隐藏或降级：当前以错误状态降级展示，不影响 SSH 其他功能。

### Task 4：Nginx

- [x] 探测 Nginx 安装和配置路径：当前通过 `command -v nginx` 和 `nginx -V` 解析 `--conf-path` / `--prefix`，并兼容 `/etc/nginx`、`/usr/local/nginx/conf`、`/opt/nginx/conf`、`/www/server/nginx/conf` 等路径。
- [x] 读取站点配置：当前支持配置文件列表、UTF-8 配置内容浏览和编辑，单文件限制 512 KiB。
- [x] 编辑前备份：保存时先创建远端 `.hhc-backup-*` 备份。
- [x] 保存后执行 `nginx -t`，并展示 stdout/stderr 合并结果。
- [x] 测试通过才 reload，失败自动恢复备份：保存后测试失败会恢复备份；reload 前也必须 `nginx -t` 通过。

### Task 5：防火墙

- [x] 探测 ufw/firewalld/iptables/nftables：当前探测 firewalld、ufw、nftables、iptables，并处理 firewalld 安装但未运行的状态。
- [x] 展示规则：当前展示后端状态和原始规则输出。
- [x] 支持有限新增/删除规则：当前支持经过校验的 IPv4 CIDR、TCP/UDP、单端口 allow/deny 规则，firewalld 支持 ingress，ufw/iptables 支持 ingress/egress，nftables 支持在已有 `inet` / `ip` filter input/output chain 上新增带 HHC comment 标记的规则，删除时只按该标记查找 handle 后删除，不创建 table/chain 或修改默认 policy。
- [x] 高风险规则二次确认：工作台会展示风险级别、目标、命令预览、影响和恢复说明，确认后才执行。

### Task 6：Cron 与环境变量

- [x] 读取用户 crontab。
- [x] 添加、禁用、删除任务：当前支持用户级 crontab 的添加、启用、禁用和删除，写入前创建远端备份。
- [x] `/etc/cron.d` 系统任务只读发现和解析：列表会展示来源文件与 run-as user，系统条目在 UI 中禁用修改/删除入口，避免误写系统计划任务。
- [x] 管理常用 `.env` 文件和 systemd env file：当前支持用户/应用目录 `.env` 和 `*.env`、`/etc/default`、`/etc/sysconfig`、systemd drop-in `.conf` 的受限发现、读取和编辑。
- [x] 保存前创建备份：当前保存环境变量文件前会创建远端 `.hhc-backup-*` 备份，并写入审计记录。

### Task 7：测试

- [x] 命令解析 fixture 测试：已覆盖 systemd service 列表解析、unit 名校验、用户级 Cron 解析、`/etc/cron.d` 系统任务解析、系统 cron 只读保护和 crontab 写入内容、Nginx 配置列表解析和路径校验、Environment 文件列表解析和路径校验。
- [x] 风险确认模型测试：已覆盖 systemd、Cron、Nginx、Environment、远程文件权限修改的风险级别、命令预览、恢复说明和确认文案。
- [x] Nginx 配置测试/回滚逻辑测试：已覆盖配置保存、保存前备份、`nginx -t`、测试失败回滚、测试通过后 reload 和审计日志写入；已加入 `HHC_TEST_NGINX_REAL=1` 受保护真实集成入口，用于在 nginx 运行且存在安全 include 目录时验证临时 server block 写入、reload、HTTP smoke 和清理。
- [x] Firewall adapter 能力探测测试：已覆盖 firewalld、ufw、nftables、iptables 解析、firewalld 未运行状态、nftables 兼容 chain 选择、nftables add/delete 命令和无兼容 chain 拒绝。
- [x] Environment 文件读写测试：已覆盖受限文件发现、UTF-8 读取、保存前备份、ViewModel 状态流和审计日志写入；真实服务器已通过临时 `$HOME/hhc-phase4-env-*` 目录验证 `.env` 发现、保存、备份和审计。
- [x] 安全组测试：已覆盖 TencentCloudAdapter VPC 安全组/规则读取和单条写操作 API contract、CloudSecurityGroupService 账号/凭据/关联链路、ViewModel 加载/选择/写入刷新和审计状态流。
- [x] RemoteChangeLogStore 测试：已覆盖保存、倒序查询、按 server 过滤和 server 删除后的 SET NULL。

### Task 8：手动验收

- [x] 无云账号时安全组页不可用但 SSH 功能正常：ViewModel 测试覆盖未关联云实例时仅显示安全组不可用提示，并保持已连接 SSH 状态和命令结果不变。
- [ ] 腾讯云安全组可读取。当前 mock/contract 测试已通过，真实腾讯云账号手动验收待执行。
- [x] 新增安全组规则前显示预览和确认基础：当前安全组详情页可生成拟新增规则预览并展示风险，确认后执行腾讯云单条规则写入。
- [x] systemd 服务可以查看和重启。当前真实服务器只读查看已验收，并通过受控临时 oneshot unit 验证真实 restart 写操作、远端 marker 和 `remote_change_logs` 审计。
- [x] Nginx 配置测试失败时不 reload：当前 reload 流程会先执行 `nginx -t`，保存流程测试失败会自动恢复备份；真实服务器已完成只读配置路径和 `nginx -t` 验证，且已加入受保护的临时配置写入/reload 集成入口。当前测试服务器 nginx 服务未运行，真实配置写入/reload 仍待合适环境谨慎验收。
- [x] 防火墙后端探测：真实服务器已验证 firewalld 安装但未运行时可展示降级状态；规则写操作已有 mock/contract 测试覆盖，其中 nftables 仅写入已有兼容 chain 且只删除 HHC 标记规则，真实服务器写入仍需谨慎手动验收。
- [x] Cron 任务可禁用并恢复。当前真实服务器只读 crontab 已验收，并通过受控临时 cron entry 验证 add/disable/enable/delete、原 crontab 恢复和 `remote_change_logs` 审计；`/etc/cron.d` 系统任务只读发现已接入 contract 测试和受保护真实测试断言，真实系统条目是否存在取决于目标服务器。
- [x] Environment 文件保存可备份并审计。当前真实服务器已通过受控临时 `.env` 验证保存、`.hhc-backup-*` 备份、远端内容变更和 `remote_change_logs` 审计。
- [ ] 所有写操作可在操作日志中查到。当前 systemd、Cron、Nginx、Environment、Firewall 和腾讯云 Security Groups 写操作已写入 `remote_change_logs`；systemd/Cron/Environment 真实服务器写操作审计已验收，Nginx/Firewall 真实服务器写操作和真实云账号验收仍需继续补齐。

## 8. 完成标志

1. 云安全组读取、规则 diff/preview、实例精确安全组过滤和三家云单条规则写操作已可用；真实云账号写操作验收仍待继续补齐。
2. systemd、Nginx、防火墙、Cron、环境变量能力基于探测启用。当前 systemd、Nginx、Cron、Environment 已有工作台基础，Cron 支持用户级可写和 `/etc/cron.d` 只读展示，Firewall 已支持只读探测和受限规则写操作。
3. 所有远程写操作有确认和审计。当前 systemd、Cron、Nginx、Environment、Firewall 和腾讯云 Security Groups 已接入审计；现有危险确认已接入统一风险模型。
4. Nginx 等配置类操作有备份和回滚。当前 Nginx 已具备读取、编辑、保存前备份、保存后测试、失败回滚和 reload 前保护。
5. 测试和手动验收通过。

## 9. 后续 Phase 边界

- Phase 5 才做 GitLab 部署。
- Phase 6 才做包仓库安装。
- Phase 7 才扩展快照、云盘、计费和更多云厂商高级能力。
