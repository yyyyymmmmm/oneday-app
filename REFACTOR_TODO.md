# OneDay iOS & 服务端工程重构总账（REFACTOR_TODO）

> 基线分支：`refactor/ios-ui-and-core-v2`（切自 `main` `3ce107bc`）
> 严格遵守独立审计 3 条硬裁定与 8 条前置条件（`audit-refactor-20261126.md`）。

## 一、审计硬红线（不可违背）

1. **严禁第二把主钥**：绝不引入 `VAULT_MASTER_KEY`；凭据库信封加密 v2 的 KEK 仅从 `API_SERVER_KEY` 派生，且保留 v1 双轨只读回退。
2. **暂缓 JWT 改铸**：`server/patches/auth_tokens.py` 维持 `odt1.` 铸造格式不变。
3. **保留中枢底层糊化**：`Sources/OneDayApp/ContentView.swift` 的 `HubUnderlayTreatment` 原样保留。
4. **零主线退化**：保留 `0.51.2+` `MessageVaultRequest` 密码卡链路、审批墓碑、气泡色板（`#E9EAEC` / `#2C2C2E`）、原生红线、Bitwarden 链接（`2.18.12`）与服务端 3 处凭据库修复。
5. **零僵尸件与空依赖**：不合入未接入业务流的 `oneday_db.py`、零引用依赖包或空壳 `_has_sqlite_vec()`。
6. **诚实验收**：未经 `xcodebuild` 真机/模拟器实跑绝不报绿，每次交付据实标注已跑检查与未跑项。

## 二、核心功能回归清单（每批合入前核对）

- [ ] 聊天收发、流式增量渲染与滚动贴底
- [ ] 表情表态、长按菜单与引用回复
- [ ] 结构化密码请求卡（`MessageVaultRequest`）授权 / 拒绝 / 墓碑态
- [ ] 附件预览（QuickLook）与图片查看器（Nuke + FloatingToastView）
- [ ] 云电脑（Simular Box）桌面状态读取、缩略预览、全屏接管与独立凭据 Sheet
- [ ] 密码库列表搜索、锁定解锁、强密码生成与全掩码展示
- [ ] 通知收件箱、中枢页模型切换与液态玻璃分段条
- [ ] 服务端凭据库信封 v2 / v1 双轨自测（Python 3.10+ + `cryptography`）

## 三、53 项改造进度追踪（49 项有效 + 4 项审计否决/缓办）

### Batch 1：UI 视觉、交互与体验精修（16 项）

- [x] `#1` 顶栏头像与胶囊分离（范式 B，`HubIdentityCapsule.swift`）— 已合 `main`
- [x] `#2` 密码添加/编辑页升级（`VaultEditView.swift`）— 已合 `main`
- [x] `#3` 云主机凭据脱敏回显 + liveURL 修复（`CloudComputerViews.swift`）— 已合 `main`
- [x] `#4` 当前服务器页对齐与居中危险按钮（`ServerDetailView.swift`）— 已合 `main`
- [x] `#5` 移除 Icons by Lordicon（`SettingsSupportViews.swift`）— 已合 `main`
- [x] `#6` Haptics 预热复用池（`Haptics.swift`）— 已合 `main`
- [x] `#7` 通知页大厂重构（`NotificationsView.swift`）— `54bfcb71`
- [x] `#8` 中枢页大厂重构（`AgentHubView.swift`）— `54bfcb71`
- [x] `#9` 深色强调色柔和对比度修复（`Palette.swift`）— `54bfcb71`
- [x] `#10` 点子分层符号与低饱和语义色底（`IdeasView.swift`；底栏五格 `TabBarSymbols.swift` 已无符号碰撞）— `54bfcb71`
- [x] `#11` 密码列表页搜索、图标徽章与锁定态解锁（`VaultListView.swift`）— `54bfcb71`
- [x] `#12` 聊天密码卡现代分层升级（`VaultRequestCard.swift`）— `54bfcb71`
- [x] `#13` 云主机详情页实时桌面预览卡 + 独立凭据 Sheet（`CloudComputerViews.swift`）— 本批
- [x] `#14` 全仓 List 边距与设置文案收口（`ToolsetsSettingsView` / `CrashReportsView` / `UsageDetailView` / `VoiceSettingsView` 统一 `settingsRowInsets` 与去工程味文案）
- [x] `#15` Haptics 全仓通道级防抖收敛（`Haptics.swift`）— 本批
- [~] `#16` ~~摘除 HubUnderlayTreatment~~（审计红线否决）

### Batch 2：成熟库替换与原生动画交互（16 项）

- [x] `#17` `REFACTOR_TODO.md` 与回归护栏 — 本批
- [x] `#18` QR 扫码换原生 VisionKit `DataScannerViewController` — `59a8bfc3`
- [x] `#19` 滚动数字换原生 `.contentTransition(.numericText())` — `54bfcb71`
- [x] `#20` Keychain 换 `KeychainAccess 4.2.2` 并真切流 `KeychainStore.swift`（保留 `site.didichou.oneday` 无感继承老登录态）
- [x] `#21` 代码高亮换 `Highlightr 2.3.0` 并真切流 `MarkdownText.swift`（明/暗主题切换＋`CodeHighlight` 零吞字兜底）
- [x] `#22` SSE 换 `mattt/EventSource 1.6.0` 动态 `.framework` 并真切流 `HermesClient.swift`（`chatStream` + `runEvents`）与 `SSEParser.swift`
- [x] `#23` MCP 换官方 `modelcontextprotocol/swift-sdk 0.12.1` 并真切流 `BoxMCPClient.swift`（`MCP.Client` + `HTTPClientTransport`）
- [x] `#24` 性能监控换原生 `MetricKit`（`MetricKitDiagnostics.swift`）— `59a8bfc3`
- [x] `#25` 聊天输入框 Swift 6 收口（`ComposerFocusHandle` 标 `@MainActor`，保留 `UITextView` 规避中文拼音组合态撕裂）
- [x] `#26` 全屏返回回归 iOS 26 原生 `interactiveContentPopGestureRecognizer`（`FullscreenPopBridge.swift` 移除私有 selector 反射）
- [x] `#27` 侧滑抽屉移除空跑 `CADisplayLink`（`DrawerContainerView.swift` 改由 `UIViewPropertyAnimator` 与拖动回调直报进度）
- [x] `#28` 悬浮表态条收敛至原生 `UIMenu(options: .displayAsPalette)`（`ReactionFloatingBar.swift` 新增 `ReactionContextMenuBuilder`）
- [x] `#29` Markdown 渲染对齐 `swift-markdown 0.6.0` 并消除 `alignmentGuide` Swift 6 并发告警（`MarkdownText.swift`）
- [x] `#30` `StreamingText` 升级 `PhaseAnimator` + `StreamingFadeTextRenderer` — `59a8bfc3`
- [x] `#31` `TimelineView` 计时器切原生 `Text(style: .timer)` + 删 `ScrollViewTapDismiss` + `FloatingToastView` 收口 + `ImageViewerView` 原生 Zoom 扩展 + `SwipeReplyPanBridge` 动态横向滚动排除区
- [x] `#32` `DictationController` iOS 26 原生 `SpeechAnalyzer` + `SpeechTranscriber` 模块化收口（抽离 `DictationController+Pipeline.swift` 与 `SpeechAnalyzerCapability`）

### Batch 3：iOS 核心引擎、网络与大文件拆分（7 项）

- [x] `#33` 拆解 `ChatView.swift` 及超大视图（抽离 `ChatView+SendAndOutbox.swift` 与 `ChatView+OverlaysAndModifiers.swift`，完整保留 `MessageVaultRequest` 与 `HubUnderlayTreatment`）
- [x] `#34` 结构化 JSON `content_blocks`（`MessageBlockCodec` 落盘 `OneDayCore/MessageContentBlocks.swift`、`CloudComputerTarget` 补全 `Codable`，`ChatEntry.decodedContentBlocks` 双轨真切流 + `ChatThread.sortedEntries` 单调 `serverRowID` 排序）
- [x] `#35` `ChatNativeList.swift` 增加 `SizingMode`（默认 `.deterministicHeightLedger` 恪守 §329 防循环护栏，支持 `.adaptiveHostingSelfSizing` 原生 `.estimated` 模式）
- [x] `#36` `StreamRenderCoordinator.swift`（30fps 固定节拍 + 已闭合 Markdown 块冻结缓存）落盘 `OneDayCore` 并接入 `StreamingText.swift`（`CoordinatedStreamingView`）
- [x] `#37` 拆解 `HermesClient.swift` 为 4 个域文件（核心传输/流式 + `HermesClient+SessionsAndMemory.swift` + `HermesClient+AdminAndOps.swift` + `HermesClient+FilesAndKanban.swift`）
- [x] `#38` 本地存储收口 SSOT（新增 `AppPreferences.swift` 与 `LocalStoreCoordinator.swift`，`AppState.swift` 全部 `UserDefaults` 读写统一收口）
- [x] `#39` 设备桥按权限域插件化（新增 `DeviceCapabilityPlugin` 协议，拆出 `DeviceEventKitPlugin.swift` / `DeviceContactsAndFilesPlugin.swift` / `DeviceAlarmAndNotifyPlugin.swift`）

### Batch 4：服务端解耦与工程门禁（10 项）

- [x] `#40` `credential_vault.py` 信封加密 v2 单主钥 + v1 双轨 — 已合 `main`
- [~] `#41` ~~引入第二把主钥 `VAULT_MASTER_KEY`~~（审计红线禁止）
- [~] `#42` ~~`auth_tokens.py` 换 JWT 铸造格式~~（审计缓办）
- [~] `#43` ~~`requirements-standard.txt` 零引用依赖与空壳 `sqlite-vec`~~（审计清退）
- [x] `#44` 基于 `2.18.12+` 拆解 `device_gateway.py`（→ `device_gateway_catalog.py`，900 行）、`oneday_seg_feed.py`（→ `oneday_feed_helpers.py`）、`api_server.py`（→ `api_server_helpers.py`）并全量登记 4 件套（`manifest.yaml` `2.18.13` / `install.sh` / `verify.sh` / `CAPABILITIES.md` `#72`）
- [x] `#45` `oneday_db.py` 统一 SQLite WAL 真接全四类 JSON/JSONL 存储（`front_gateway` / `credential_vault` / `auth_tokens` / `write_gate_gateway`，保留写穿镜像与无感自动迁移）＋ `server/migrate_json_to_sqlite.py` 幂等迁移脚本 ＋ `server/oneday_db_selftest.py`
- [x] `#46` `push_sender.py` 升级 `aioapns` 异步发送（无依赖时回退 `httpx[http2]` + `PyJWT`）与 `PushDispatchScheduler` 合并调度队列
- [x] `#47` 全量服务端 `py_compile`、`oneday_db_selftest`、`auth_tokens_selftest`、`push_tokens_selftest`、`push_sender_and_schema_guard_selftest` 通过；修复 `.github/workflows/ci.yml` 路径并在 Python 3.12 + `cryptography` 环境下运行 `server/credential_vault_selftest.py` 真加密自测
- [x] `#48` 工程卫生（`Tuist/Package.resolved` 锁定入库、`.gitignore` 排除构建与打包产物）
- [x] `#49` 自动化 CI 门禁（`.github/workflows/ci.yml` + `ios-native.yml` 分支与 PR 触发）— 本批

### Batch 5：全量视觉精修与架构收尾（4 项）

- [ ] `#50` 全局配色对比度与字号体检（`Palette.swift` 增补语义图标前景色 Token `tintSkyInk`/`tintGreenInk`/`tintLavenderInk`/`tintOrangeInk`；排查并修复可读文本误用 `inkMuted` 导致对比度偏低的区域，如 `FeedLinkPreviewCard` `domainLine` 等，同时保持现有 `VisualDirectionGateTests` 对比度断言零回归）
- [ ] `#51` 动态页（`FeedView.swift`）图标与卡片视觉统一（升级 `postRow` 图标容器为 36×36 连续圆角磁贴＋`.symbolRenderingMode(.hierarchical)`＋语义前景色对齐中枢/通知/点子页，补齐 `FeedSourceCardView`/`FeedLinkPreviewCard` `Palette.hairline` 描边）
- [ ] `#52` 通知页（`NotificationsView.swift`）分类筛选胶囊与左滑标已读增强（在全部/未读分段条下方新增横向分类胶囊 `全部 / 审批 / 监测 / 任务` 与触觉反馈，保留左滑「标已读」与减动态兼容）
- [ ] `#53` `ChatView.swift` 二次瘦身与 UIKit 桥体检（抽离顶部状态/查找栏/按钮簇与对话查找辅助至 `ChatView+HeaderAndActions.swift`，完成 `Sources/OneDayApp` 全部 11 处 `UIViewRepresentable` 桥接与计时器零泄漏审计）
