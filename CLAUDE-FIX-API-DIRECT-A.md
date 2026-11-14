# 修复简报：API 直连第一包二轮（协调验收不通过项，逐条销）

工作区不变：`/home/hatch/workspace/oneday-worktrees/api-direct-a`，分支 `feat/api-direct-a`，在现有提交 `5b8fb68` 之上修。**分项小提交**（每组一个提交），最后 push。CI 已跑过一轮：run 43569538678 **编译红**（见 F1）。

行为基准＝伴生 `~/workspace/hermes-deploy/companion/modules/box_bridge.py` 的现行桥行为（状态合成、act、shell、files 各 handler），逐条对齐，不许凭猜。

## F1 编译红＋类型重造（CI 实证）

- `MCPModels.swift:95`：`AnyCodable` 声明 Sendable 却存 `Any`，编译错误。仓内已有正解：`Sources/OneDayCore/HermesAdminModels.swift` 的 `JSONValue`（Codable＋Sendable＋Equatable）。**删掉自造 AnyCodable，MCP 全层改用 JSONValue**（请求 params、structuredContent、arguments 组装都走它）。

## F2 协议致命伤：tools/call 参数形状错

- 现行把参数包成 `{"tool": {"name": ..., "arguments": ...}}`。MCP 规范形状是 params 顶层 `{"name": <工具名>, "arguments": {...}}`。改对，并用单测钉死信封形状。

## F3 握手不完整

- `initialize`：protocolVersion 改 `2025-03-26`（streamable HTTP 世代）；params 补 `"capabilities": {}`；initialize 成功后必须发 `notifications/initialized` 通知（JSON-RPC notification、无 id，服务端回 202 无体，容忍之）。

## F4 SSE 响应未实现（简报明文要求过）

- 请求头补 `Accept: application/json, text/event-stream`。
- 响应解析：Content-Type 为 `text/event-stream` 时，按 `data:` 行抽 JSON、按请求 id 匹配响应；纯 JSON 时直解。抽成 Core 纯函数并单测。

## F5 timeout 参数是摆设

- `callTool` 的 timeout 从未生效（URLSession 全局 60s 一刀切）。改为每次请求设 `URLRequest.timeoutInterval`（截图/状态 30–60、act/shell 90、shell base64 读 120，各调用点现行声明值即口径）。

## F6 凭据没人写（功能整体 inert，最严重）

- 全仓无人写 Keychain `box.mcp.key`：工厂永远 noKey。现行填钥匙落点＝`CloudComputerViews.swift` 的凭据表单 `submit()`（非 vps 分支走 `ConnectionPayloads.simularCredential(apiKey:)` → `ConnectionsStore.submitCredential`）。
- 在该流程里接上：当 connection.provider == `simular_box` 且提交验活成功（credentialPhase 到 verified）后，把用户刚填的 apiKey 写进 KeychainStore `box.mcp.key`，并调 `BoxMCPClientFactory.reset()` 让新凭据生效。服务端保管流（submitCredential 本体）一字不动。
- `box.mcp.url` 的 UserDefaults 覆盖无人写、产品面也没有地址输入（simular 表单只有钥匙）：删掉这个假覆盖，URL 用具名常量默认值。

## F7 status 保真（对齐 box_bridge.py get_status）

现行只剩 box_status 裸字段，桥合成的三件全丢：
- credits：另调 `billing` 工具——structured 里按 `credits_left`/`creditsLeft`/`credits`/`balance` 顺序取数；isError 或异常 → creditsNote＝厂商错误文本（截断 200 字），取不到数 → creditsNote 注明无数字。
- page：state == running 时调 `browser_snapshot`，解析 `Page: 标题 (url)` 行；失败/无行重试一次（间隔 0.9s）。
- lastKnownPage：客户端内缓存最近一次确认过的 page（来自 snapshot 或 navigate 结果），连同时间戳随状态返回；checkedAt＝本次查询时刻。

## F8 act 保真（对齐 post_act）

- 结果无图像块时补调一次 `screenshot` 取图（桥的 `extract or post_screenshot` 语义）。
- summary 取第一段文本的**第一行**（桥 first_line，上限 300 字），不是整段。

## F9 files 保真（对齐 clean_rel_path／get_files／_read_file_lines）

- 条目 JSON 键名错：DTO `WorkspaceFileEntry.CodingKeys` 要求 `is_directory`／`mime_type`，现行拼 `isDirectory`／`mimeType`，**list 每次解码必失败**。改回正确键名。
- 路径校验补齐（clean_rel_path 同款）：拒绝绝对路径、反斜杠、NUL、空段、`.`、`..` 段，违规抛人话错误，不许把 `..` 拼进绝对路径。
- 列表 500 条上限（桥 MAX_LIST_ENTRIES，超出截断）。
- 列表头 resolved 路径校验：解析出的目录必须等于 /workspace 或在其下（防符号链接逃逸），且 `/workspace/.` 归一。
- read_file：行被截断标记（` [line cut: N of M characters shown]`）出现时与二进制同样回退 shell base64（桥的无损原则）；总大小上限对齐桥 16MB 口径，超限给人话。

## F10 shell 保真（对齐 post_shell）

- 多文本块以 `\n` 拼接（现行只取第一块）。
- 本地输出上限 32768 字：超出截断并在输出内追加桥同款注记行 `[box-bridge: output truncated at 32768 characters]`（现在直连了，注记由 App 自己加，文案保持一致即可）；删掉「找桥注记字符串判 truncated」的死逻辑，truncated 由本地截断事实决定。
- ok 语义：exitCode 有值时 ok＝(exitCode == 0)，无值时 ok＝true（桥口径）。

## F11 缺件补齐

- **单测**（一轮只做了口头待办，必须落）：`Tests/OneDayCoreTests` 加 MCP 协议测试——请求信封编码（含 F2 的 params 形状断言）、JSON 响应解码、SSE data 行抽取与按 id 匹配、MCPContent text/image 解码、mcpTexts/mcpStructured/mcpErrorText 三态。目录文本解析若留在 App 层无测试宿主，把解析纯函数下沉 OneDayCore 后在 Core 测（这不算大搬家，是把可测纯逻辑放对层）。
- **DESIGN-V4 规格节**：补 §233（自编号，注明组版顺延），写清 A1 映射表、凭据接法、A3 退役与红线保留项。
- **仓库卫生**：`git rm` 掉已误提交的 `CLAUDE-TASK-API-DIRECT-A.md`；本简报与工作日志不进仓，工作日志改写到 `~/workspace/oneday-design-review/api-direct-a-worklog-20261114.md`（仓外）。

## 不许动

- 消费方公开 API 签名（status/screenshot/act/list/fileData/run）保持不变。
- `SessionClassification.aiCastSessionPrefix`、伴生 oneday_bridge.py（A3 已验收通过，二轮不许再碰）。
- 版本号。

完成后：分项提交、push、更新仓外工作日志（逐条对 F1–F11 销账＋实际 diff 文件清单）。不要自己跑 CI（协调方触发判读）。
