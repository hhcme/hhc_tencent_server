# Phase 实施计划索引

本目录只维护中文实施计划。根目录 README 负责项目介绍和双语入口，`docs/` 下的架构、规格、设计稿说明和 Phase 计划默认使用中文维护。

## 阶段列表

1. [Phase 1：项目骨架 + 真实 SSH 最小闭环](2026-06-25-phase1-ssh-connection.md)
2. [Phase 2：云厂商基础层 + 简化命令面板](2026-06-25-phase2-cloud-command-panel.md)
3. [Phase 3：Dashboard + 文件管理器](2026-06-25-phase3-dashboard-file-manager.md)
4. [Phase 4：安全组 + 环境配置](2026-06-25-phase4-security-environment.md)
5. [Phase 5：GitLab 部署](2026-06-25-phase5-gitlab-deployment.md)
6. [Phase 6：私有包仓库](2026-06-25-phase6-private-registries.md)
7. [Phase 7：高级云资源管理](2026-06-25-phase7-advanced-cloud-resources.md)
8. [Phase 8：Windows 原生版技术验证](2026-06-25-phase8-windows-native.md)

## 阶段门禁

- 每个 Phase 开始前，必须确认上一 Phase 的完成标志都已经满足。
- 涉及凭据、远程命令、云资源写操作、文件删除、部署回滚的能力，必须先写清楚风险和确认流程。
- 不允许用模拟成功状态替代真实能力；尚未实现的功能只能展示为禁用或占位。
- 每个 Phase 必须包含测试计划和手动验收清单。
- 阶段边界需要更新时，先改设计文档和本目录实施计划，再开始写代码。
