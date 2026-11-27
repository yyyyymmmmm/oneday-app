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

## 三、49 项改造进度追踪

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
- [ ] `#20` Keychain 换 `KeychainAccess`（需联网 `tuist install` 锁 `Package.resolved`）
- [ ] `#21` 代码高亮换 `Highlightr`（需联网 `tuist install`）
- [ ] `#22` SSE 换 `mattt/EventSource` 动态 `.framework` 并真切流 `HermesClient`
- [ ] `#23` MCP 换官方 `modelcontextprotocol/swift-sdk` 并真切流 `BoxMCPClient`
- [x] `#24` 性能监控换原生 `MetricKit`（`MetricKitDiagnostics.swift`）— `59a8bfc3`
- [ ] `#25` 聊天输入框回归原生 `TextField(axis: .vertical)`
- [ ] `#26` 顶栏与全屏返回回归原生交互返回
- [ ] `#27` 侧滑抽屉标准化 / 停掉空跑 `CADisplayLink`
- [ ] `#28` 悬浮表态条收敛到原生 `UIContextMenuInteraction`
- [ ] `#29` Markdown 与表格渲染对齐 `swift-markdown 0.6.0`
- [x] `#30` `StreamingText` 升级 `PhaseAnimator` + `StreamingFadeTextRenderer` — `59a8bfc3`
- [x] `#31` `TimelineView` 计时器切原生 `Text(style: .timer)` + 删 `ScrollViewTapDismiss` + `FloatingToastView` 收口 — `54bfcb71` / `59a8bfc3` / `4029264e`
- [ ] `#32` `DictationController` 切 iOS 26 原生 `SpeechAnalyzer`（已拍板：直接升级，归第 3 批执行）

### Batch 3：iOS 核心引擎、网络与大文件拆分（7 项）

- [ ] `#33` 拆解 `ChatView.swift` 及超大视图（保留 `MessageVaultRequest`）
- [ ] `#34` 结构化 JSON `content_blocks`（`MessageBlockCodec`）真切流
- [ ] `#35` 淘汰离屏算高台（`ChatNativeRowHeight` 改原生 Sizing）
- [ ] `#36` 合并 `Streaming*` 为 `StreamRenderCoordinator` 并真切流
- [ ] `#37` 拆解 `HermesClient.swift` 为域 API
- [ ] `#38` 本地存储收口 SSOT（`LocalStoreCoordinator` + `AppPreferences`）
- [ ] `#39` 设备桥插件化 + `ConnectorsView` Schema 驱动

### Batch 4：服务端解耦与工程门禁（10 项）

- [x] `#40` `credential_vault.py` 信封加密 v2 单主钥 + v1 双轨 — 已合 `main`
- [~] `#41` ~~引入第二把主钥 `VAULT_MASTER_KEY`~~（审计红线禁止）
- [~] `#42` ~~`auth_tokens.py` 换 JWT 铸造格式~~（审计缓办）
- [~] `#43` ~~`requirements-standard.txt` 零引用依赖与空壳 `sqlite-vec`~~（审计清退）
- [ ] `#44` 基于 `2.18.12+` 拆解 `api_server.py` / `device_gateway.py` / `oneday_seg_feed.py` 并全量登记 4 件套
- [ ] `#45` `oneday_db.py` 统一 SQLite WAL（已拍板：真接全四类 JSON/JSONL 存储并附迁移脚本，归第 4 批执行）
- [ ] `#46` `push_sender.py` 接 `aioapns` / 定时调度重构
- [ ] `#47` 服务端真加密测试全绿留档（Python 3.10+ + `cryptography`）
- [ ] `#48` 工程卫生（`Tuist/Package.resolved` 入库、Swift 6 并发告警清零）
- [x] `#49` 自动化 CI 门禁（`.github/workflows/ci.yml` + `ios-native.yml` 分支与 PR 触发）— 本批
