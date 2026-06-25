# macOS MVP 设计稿

仓库内设计快照：[macOS MVP v0.2 Design Snapshots](../../assets/design/macos-mvp-v0.2/README.md)

## 范围

这份设计稿用于在正式实现 macOS 客户端前确认产品信息架构、核心流程和界面密度。当前推荐使用仓库内 `macos-mvp-v0.2` 设计快照作为实现参考。

v0.2 的核心调整是：应用启动后首先展示服务器列表；点击服务器后进入该服务器的专用工作台；在工作台内通过顶部服务器切换器切换当前操作对象。

当前设计重点覆盖 Phase 1 到 Phase 2 会直接影响 UI 架构的内容：

- 服务器列表、分组、搜索和连接状态。
- 单服务器工作台和概览。
- SSH 凭据录入和保存前校验。
- 首次连接时的 SSH 主机指纹信任流程。
- 云厂商账号配置。
- 云实例发现，以及云实例与本地 SSH Profile 的关联。

## 设计快照

- `01-startup-server-list.png`：应用启动页，优先展示服务器列表、分组、搜索、筛选和选中服务器摘要。
- `02-server-workspace-overview.png`：点击服务器后进入的单服务器工作台，左侧是该服务器的操作分类，顶部提供返回列表和服务器切换入口。
- `03-server-switcher-popover.png`：在单服务器工作台内切换当前服务器的弹出层。
- `04-add-server-native-sheet.png`：更接近 macOS sheet 的添加服务器表单。
- `05-host-key-trust-native-sheet.png`：更接近 macOS sheet 的主机指纹确认流程。

## 本地图片

- [启动服务器列表](../../assets/design/macos-mvp-v0.2/01-startup-server-list.png)
- [单服务器工作台概览](../../assets/design/macos-mvp-v0.2/02-server-workspace-overview.png)
- [服务器切换弹窗](../../assets/design/macos-mvp-v0.2/03-server-switcher-popover.png)
- [添加服务器原生 Sheet](../../assets/design/macos-mvp-v0.2/04-add-server-native-sheet.png)
- [主机指纹确认原生 Sheet](../../assets/design/macos-mvp-v0.2/05-host-key-trust-native-sheet.png)

## 设计判断

- macOS 优先，不做营销页，第一屏就是可浏览和选择的服务器列表。
- 单台服务器的操作应进入专用工作台，不在启动页里直接塞满详情面板。
- 服务器切换应是工作台内的明确功能，而不是一直常驻展示全部服务器详情。
- SSH 是基础执行通道；云 API 是可选增强层，负责实例发现、云资源状态和平台侧能力。
- 主机指纹信任必须在凭据保存和正式连接前成为显式安全关卡。
- 云实例可以没有公网 IP，因此设计稿保留了私网 IP + jump host 的配置路径。
- 后续 Windows 原生版可以复用信息架构，但控件和平台能力应按 WinUI 3/Windows App SDK 重新实现。

## 评审重点

- 启动页是否符合“先浏览服务器列表，再进入服务器工作台”的产品心智。
- 单服务器工作台是否足够专注，避免和服务器总览页混在一起。
- 服务器切换器是否能自然替代常驻的全量服务器列表。
- 添加服务器流程是否足够短，同时没有跳过安全校验。
- 云厂商 API 功能是否以增强能力出现，而不是强制依赖。
- 实例导入流程是否能解释“发现云实例”和“创建 SSH 连接配置”是两件事。

## 后续迭代

- 将本地设计快照作为开源项目的稳定实现参考。
- 为终端、文件管理器、命令面板和部署流程补充更细的二级界面。
- 根据首版 SwiftUI 实现反馈，回写控件尺寸、状态和空态设计。
