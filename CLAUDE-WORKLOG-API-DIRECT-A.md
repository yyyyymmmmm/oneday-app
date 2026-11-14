# 工作日志：API 直连第一包（A1+A3）

## 查证：MCP 协议与现行参考实现

### MCP streamable HTTP 传输协议（已查证）

参考实现：`/home/hatch/workspace/hermes-deploy/companion/modules/box_bridge.py` 的 `BoxMCP` 类

**核心要素：**

1. **传输层**：HTTP POST 到 MCP 端点（如 `https://mcp.box.simular.ai/mcp`）
   - 使用 `mcp.client.streamable_http` SDK
   - Authorization: Bearer <API_KEY>
   - 响应可能是纯 JSON 或 `text/event-stream`（SSE）

2. **会话管理**：
   - 长驻会话：`ClientSession` 对象在专用线程上保持连接
   - 初始化：`session.initialize()` 完成握手
   - 会话 ID：MCP 协议使用 `Mcp-Session-Id` 头（SDK 内部管理）
   - 懒重连：会话死后下次调用时重建，**重连=新会话，浏览器窗口会重置**（box_bridge.py:14-16 明确记录）

3. **工具调用**：
   - 串行化：所有调用通过 `asyncio.Lock` 串行（box_bridge.py:108）
   - 调用方法：`session.call_tool(name, args)` 返回结果对象
   - 重试逻辑：失败时断开重连，最多重试 2 次（box_bridge.py:109-119）

4. **结果解析**：
   - `result.content` 数组，每项有 `type` 字段
   - `type="text"`：文本块，`.text` 属性
   - `type="image"`：图像块，`.data`（base64）、`.mime_type`/`.mimeType`
   - `result.is_error`：布尔标志
   - `result.structured_content` 或 `.structuredContent`：结构化数据（JSON）

5. **工具映射**（box_bridge.py 实际使用）：
   - `box_status` → GET /box/status（box_bridge.py:276）
   - `box_view_token` → GET /box/view-token（box_bridge.py:459）
   - `screenshot` → POST /box/screenshot（box_bridge.py:343，参数 max_edge）
   - `computer_act` → POST /box/act 桌面动作（box_bridge.py:390）
   - `browser_navigate` → POST /box/act navigate 动作（box_bridge.py:372）
   - `browser_snapshot` → 内部使用，解析页面信息（box_bridge.py:317）
   - `list_dir` → GET /box/files（box_bridge.py:538，路径参数）
   - `read_file` → GET /box/files/read（box_bridge.py:620，路径+offset+limit）
   - `shell` → POST /box/shell（box_bridge.py:425）
   - `box_ensure` → 内部使用，确保 Box 运行（box_bridge.py:134）

6. **关键行为特征**（box_bridge.py 验证过的）：
   - Box 状态缓存 20 秒（box_bridge.py:129）
   - 文件列表：`list_dir` 返回纯文本，格式为 `<path>:` 头行 + 每行 `name/` 或 `name  (N bytes)`（box_bridge.py:476-483）
   - 文件读取：`read_file` 带行号前缀 `%6d\t`，分页 2000 行，有 `[showing lines ...]` 尾行（box_bridge.py:602-653）
   - Shell：返回带 `[exit status N]` 尾行的文本（box_bridge.py:416）
   - 截图：从 content 数组中提取 `type="image"` 块（box_bridge.py:215-238）
   - 页面解析：从文本中匹配 `Page: <title> (<url>)` 正则（box_bridge.py:241-248）

### 与拟定实现的对齐

**一致项：**
- 会话长驻、串行调用、懒重连的架构完全对齐
- 工具名称与参数映射已核实（需逐项对照 box_bridge.py 实际调用）
- 响应解析：content 数组、is_error、structured_content 都已确认
- 重连语义：box_bridge.py 明确记录"重连=新会话、窗口重置可接受"，拟定实现需如实注释

**需补充：**
- list_dir 的文本解析：App 侧需实现与 box_bridge.py:530-596 同等的目录形状解析
- read_file 的行号前缀剥离与分页：需要对齐 box_bridge.py:606-653 的逻辑
- shell 的 exit status 尾行解析：已在 BoxShellModels 中定义，但桥侧逻辑在 box_bridge.py:434
- screenshot/act 的图像提取：需要对齐 extract_screenshot (box_bridge.py:215-238)

**凭据管理：**
- 现行口径：`BridgeCredential.read()` 从 Keychain 读 `api.key`（KeychainStore.swift:28-34）
- 拟定方案：Box MCP 需要**独立的盒子钥匙**（不同于 Hermes api.key）
- 新增 Keychain 键：`box.mcp.key`（用户在云电脑连接面填写，存 KeychainStore）
- MCP 地址：默认 `https://mcp.box.simular.ai/mcp`，可由用户覆盖（存 UserDefaults 或连接记录）

---

## A1 施工记录

### 1. 创建 MCP 客户端基础设施

**已完成：**
- `Sources/OneDayCore/MCPModels.swift`：MCP 协议模型（JSON-RPC 2.0 信封、结果解析、内容块）
- `Sources/OneDayApp/BoxMCPClient.swift`：MCP 客户端 actor（会话管理、工具调用、重试逻辑）
- `Sources/OneDayApp/BoxBridgeClient.swift`：改造为 MCP 直连（status/screenshot/act 三个公开 API 保持不变）
- `Sources/OneDayApp/BoxFilesClient.swift`：改造为 MCP 直连（list_dir/read_file 工具，解析纯文本目录列表）
- `Sources/OneDayApp/BoxShellClient.swift`：改造为 MCP 直连（shell 工具，解析 exit status 尾行）

**关键实现细节：**
- 会话管理：actor 隔离保证串行调用，懒重连（重连=新会话）
- 工具映射：box_status、screenshot、computer_act、browser_navigate、list_dir、read_file、shell
- 图像解析：PNG/JPEG 尺寸提取（对齐 box_bridge.py:192-212）
- 文件列表：纯文本解析 `<path>:\n` + `name/` 或 `name  (N bytes)`
- Shell 输出：剥离 `[exit status N]` 尾行

**凭据管理：**
- 新增 Keychain 键：`box.mcp.key`（盒子钥匙，独立于 Hermes api.key）
- MCP URL：UserDefaults `box.mcp.url`，默认 `https://mcp.box.simular.ai/mcp`
- 工厂模式：`BoxMCPClientFactory` 管理单例

**验证项（待 CI）：**
- grep 自证：App 代码中不再出现 `/api/box-bridge/status|screenshot|act|files|shell` 调用
- 三个客户端公开 API 签名不变（BoxBridgeStore/BoxFilesView/BoxTerminalView 无需改动）
- 单测：MCPModels 的编解码、工具结果解析（待补充）

---

## A3 施工记录（ai-sessions 退役）

### App 侧验证

**查证结果：**
```bash
grep -r "ai-sessions\|ai_sessions" --include="*.swift" Sources/
# 仅一处：Sources/OneDayCore/SessionClassification.swift 注释
```

**结论：**
- App 无 `/ai-sessions` 端点调用
- `SessionClassification.aiCastSessionPrefix = "oneday-ai-"` **保留**（红线，现行会话分类逻辑依赖此前缀）
- `/mcp-sessions` 门仍在铸此前缀，分类规则 R3b 依赖它

### 伴生侧退役

**退役范围（oneday_bridge.py）：**
1. **删除 REST 门**：`_dispatch_ai_sessions` 方法及其路由（行 10120-10141、10662-10663）
2. **删除自测文件**：`tests/oneday_bridge_ai_sessions_selftest.py`

**保留项（红线）：**
- `AI_SESSION_PREFIX = "oneday-ai-"`（常量，与 App 的 `aiCastSessionPrefix` 同步）
- `_create_ai_session_core` 等核心逻辑（`/mcp-sessions` 门仍在用）
- `_list_ai_sessions`（内部验证用，无外部路由）
- `SESSION_TOOLS`、`_session_tool_call`（`/mcp-sessions` 的 tools/call 实现）

