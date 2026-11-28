# OneDay × Hermes v0.23.0 原生客户端重构待办清单

> 对应 Google Sheets 原子级差异总表：[Hermes v0.23.0 vs OneDay 功能差异与重构方案总表](https://docs.google.com/spreadsheets/d/1tcyYjkbFVJTK0wvIfo26I00wEJaxOXVTcZ5Nflebtws/edit)
> 分支：`feat/cloud-connectors-hermes-v23`（基于 `main` `b5385916`）

## 零、审计与基线
- [x] 核对本机 `hermes-agent-v0.23.0-source.tar.gz` 全量模块树（`tools/`、`hermes_cli/`、`gateway/platforms/`、`acp_adapter/`、`agent/`）
- [x] 将 Google Sheets `Hermes功能差异总表` 扩充至 48 项原子级对比（含分身创建与管理、CLI/终端/后台进程、压缩/回溯/分支/队列/推理强度等）
- [x] 定位云电脑无法接管、连接器重复与搜索失效、分身与 CLI 管理缺失的精确源码根因

## 一、云电脑实时接管闭环（对标 Manus / OpenAI Operator）
- [x] `BoxBridgeClient.swift`：补齐 `box_view_token` MCP 调用，自动换取带鉴权票据的实时流 URL（兼容结构化 JSON / URL 文本并支持降级回退）
- [x] `BoxBridgeStore.swift`：新增 `liveStreamURL`、`refreshLiveStreamURL`、接管状态管理与 `handbackContextSummary`（交还前自动补抓最新画面与页面标题/URL，让 AI 知道用户操作了什么）
- [x] `ComputerFaceView.swift`：
  - [x] `LiveStreamWebView` 补齐 `WKUIDelegate`（站内承接 OAuth / `target="_blank"` 弹窗，解决登录卡死）与 `WKNavigationDelegate`（加载进度、错误提示 + 一键切免登直控兜底）
  - [x] `CloudComputerTakeoverSheet` 加上 `.interactiveDismissDisabled(true)` 防止下拉手势误关接管窗
  - [x] 修复 `directControlSurface` 缩放后点击坐标偏移问题并补齐放大后拖拽平移
  - [x] 增强直控工具栏：剪贴板一键粘贴（`UIPasteboard`）、右键模式开关与快捷键（`Ctrl+A`、`Ctrl+C`、`Ctrl+V`、`Enter`、`Tab`、`Esc`）
  - [x] 交还闭环：点击「交还给 AI」自动刷新最新状态与截图并把页面上下文交还给 `ChatView`
- [x] 使用 `xcrun swiftc -parse` 验证云电脑相关文件并提交 Git Commit

## 二、连接器页面重构与 MCP 生态收口（对标 Claude / ChatGPT / Apple HIG）
- [x] `ConnectorsView.swift`：
  - [x] 修复 `.searchable(text: $query)` 搜索框未生效的 bug（同时过滤本机权限、已接 MCP 服务与可安装 MCP 目录，无结果展示 `ContentUnavailableView.search`）
  - [x] 升级本机权限行与 MCP 服务行图标：严格采用 36×36 连续圆角 + `.hierarchical` SF Symbol 语义色块（零 Apple 原生 App 图标，合规对齐 Apple HIG 与 App Review 5.2.5）
  - [x] 暴露 `ConnectorsFacade` 已有的 MCP 目录（`loadCatalog` / `installCatalogEntry`），支持目录一键安装与环境变量表单（密钥类自动走 `SecureField`）
  - [x] 替换 `MCPServerDetailView` 占位视图：展示真实连接测试结果（`facade.testResults`）、工具数、来源、传输协议/端点元数据与启停开关
- [x] 使用 `xcrun swiftc -parse` 验证连接器相关文件并提交 Git Commit

## 三、Hermes v0.23.0 核心 P0 能力（分身管理 + CLI/斜杠命令与终端入口）
- [x] 新增 `ChatSlashCommandPalette.swift` 并接入 `ChatView` / `ChatBottomBarViews` 输入栏：
  - [x] 输入 `/` 弹出大厂级斜杠命令自动补全浮层（`/compress`、`/context`、`/rewind`、`/branch`、`/reasoning`、`/yolo`、`/learn`）
  - [x] 支持 `!` 前缀直通终端命令快捷识别与填入（对应 Hermes `bang_shell.py`）
- [x] 增强 `ProfilesView.swift`（分身创建、克隆、导入导出与卡片管理）：
  - [x] 升级为 36×36 合规 SF Symbol 语义色块、默认/使用中胶囊徽章与独立分身隔离说明
- [x] 增强 `BoxTerminalView.swift`：新增常用终端与进程诊断快捷胶囊栏（`pwd`、`ls -la`、`ps aux`、`git status`、`df -h`、`uname -a`）
- [x] 全量 `xcrun swiftc -parse` 校验 9 个修改与新增 Swift 文件（exit 0）
- [x] 提交并推送 `feat/cloud-connectors-hermes-v23` 分支，全部待办勾选收口
