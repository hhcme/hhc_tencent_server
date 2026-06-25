# Changelog / 更新日志

All notable changes to this project will be documented in this file.

本文件记录项目的重要变更。

## Unreleased / 未发布

- Added MIT license.
- Added bilingual README files.
- Added contributing, security, and code of conduct documents.
- Added Chinese documentation index.
- Kept detailed design and implementation planning documents in Chinese while keeping README bilingual.
- Refined the project design and Phase 1 plan around real SSH behavior, host key trust, Keychain storage, and SwiftNIO SSH version constraints.
- Added SSH-first plus optional Cloud API enhancement direction.
- Added bilingual Cloud Provider API enhancement design.
- Updated roadmap to introduce cloud provider adapters after the real SSH MVP.
- Added bilingual Windows native client strategy with WinUI 3, Windows App SDK, and .NET/C# as the later-platform direction.
- Updated roadmap to keep macOS first and place Windows native validation in Phase 8.
- Added macOS MVP local design snapshots and bilingual design handoff notes.
- Revised the macOS design direction with a native v0.2 flow: server list first, dedicated server workspace, and toolbar-based server switching.
- Added repository-versioned PNG snapshots for the macOS MVP v0.2 design.
- Aligned the Phase 1 implementation plan and architecture documents with the local macOS v0.2 design flow.
- Added Chinese implementation plans for all roadmap phases from Phase 1 to Phase 8.
- Removed the internal English documentation mirror to avoid duplicated implementation planning drift.
- Started the macOS native app with a SwiftUI server browser, server workspace, SQLite persistence, Keychain credential storage, host-key trust flow, and real OpenSSH smoke-test adapter.
- Added the macOS unit test target covering repository, Keychain, server-management, form validation, and skipped-by-default SSH integration testing.
- Added password authentication support to the bootstrap OpenSSH adapter through a temporary askpass flow backed by Keychain credentials.
- Added workspace connection state, Connect/Disconnect controls, and ViewModel tests for success, failure, host-key trust, and disconnect flows.
- Added server editing with profile updates, credential preservation/replacement, edit UI entry points, and test coverage.
- Extracted host-key trust evaluation into `HostKeyTrustStore` and added tests for unknown, trusted, and changed host-key states.
- Added shared local and GitHub Actions macOS build-test automation.
- Added a simplified workspace command panel that executes single SSH commands and keeps per-session command history.
- Updated the README status to reflect the active macOS implementation.
- Added SQLite-backed command metadata history and operation logs without persisting command output.

- 添加 MIT 开源协议。
- 添加中英文 README。
- 添加贡献指南、安全策略和行为准则。
- 添加中文文档索引。
- 明确 README 保持中英文，详细设计和实施计划默认使用中文维护。
- 围绕真实 SSH 行为、主机指纹信任、Keychain 存储和 SwiftNIO SSH 版本约束修订项目设计与 Phase 1 计划。
- 添加 SSH-first + 云 API 可选增强的产品方向。
- 添加中英文《云厂商 API 增强层设计》。
- 更新路线图，在真实 SSH MVP 之后引入云厂商 adapter。
- 添加中英文《Windows 原生客户端技术选型》，明确后续平台方向为 WinUI 3、Windows App SDK 和 .NET/C#。
- 更新路线图，明确先做 macOS，Windows 原生版放到 Phase 8 技术验证。
- 添加 macOS MVP 本地设计快照和中英文设计交接说明。
- 修订 macOS 设计方向，新增更原生的 v0.2 流程：先展示服务器列表，再进入单服务器工作台，并通过工具栏切换服务器。
- 添加 macOS MVP v0.2 设计稿的仓库内 PNG 快照。
- 将 Phase 1 实施计划和架构文档校准到 macOS v0.2 本地设计流程。
- 补齐 Phase 1 到 Phase 8 的中文实施计划。
- 移除内部英文文档镜像，避免实施计划重复维护后漂移。
- 启动 macOS 原生应用实现，加入 SwiftUI 服务器列表、单服务器工作台、SQLite 持久化、Keychain 凭据存储、主机指纹信任流程和真实 OpenSSH smoke test 适配层。
- 添加 macOS 单元测试 target，覆盖 repository、Keychain、服务器管理、表单校验，以及默认跳过的真实 SSH 集成测试入口。
- 为 bootstrap OpenSSH 适配层加入 password 认证支持，通过临时 askpass 流程读取 Keychain 凭据。
- 添加工作台连接状态、Connect/Disconnect 控制，并补充 ViewModel 成功、失败、主机指纹信任和断开连接流程测试。
- 添加服务器编辑能力，支持配置更新、凭据保留/替换、编辑入口和测试覆盖。
- 抽出 `HostKeyTrustStore` 主机指纹信任判断，并补充未知、已信任和指纹变更阻断测试。
- 添加本地与 GitHub Actions 共用的 macOS 构建测试自动化。
- 添加工作台简化命令面板，支持执行单条 SSH 命令并保留本次会话命令历史。
- 更新 README 项目状态，使其反映当前 macOS 已进入实现阶段。
- 添加基于 SQLite 的命令元数据历史和操作日志，不持久化命令输出。
