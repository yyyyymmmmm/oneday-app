# 施工单：API 直连第一包（A1 box 甩桥＋A3 ai-sessions 退役）

## 工作区（写死，不许动别处）

- App 仓库 worktree：`/home/hatch/workspace/oneday-worktrees/api-direct-a`，分支 `feat/api-direct-a`，基线 `39532cc`（rel-05039）。**只在此目录内改 App 代码**；严禁进入主 worktree `/home/hatch/workspace/oneday-app` 或任何其他 worktree。
- 伴生源码（无 git，部署源树）：`/home/hatch/workspace/hermes-deploy/companion`，仅 A3 允许动 `modules/oneday_bridge.py` 与 `tests/oneday_bridge_ai_sessions_selftest.py` 两处，其余文件不许碰。
- 本简报文件不要提交。

## 背景（先读）

- 盘点报告：`~/workspace/oneday-design-review/api-direct-inventory-20261114.md` 的 §3.1 A1、A3 两条与 §5 第 2、3 项。
- 口径：API 直连优先、桥只收敛不扩张；凭据体验定版＝用户只填服务方给的「地址＋密钥」，内部钥匙概念不许端给用户。

## 动手前先查（成熟做法）

先查 MCP 官方协议（streamable HTTP 传输：initialize 握手、Mcp-Session-Id、notifications/initialized、tools/call、结果 content 结构、JSON 与 SSE 两种响应）与现行参考实现——伴生 `modules/box_bridge.py` 的 `BoxMCP` 类就是同一目标（Simular Box MCP `https://mcp.box.simular.ai/mcp`，Bearer 盒子钥匙）的已验证客户端：会话长驻、调用串行、会话死后懒重连（重连后浏览器窗口重置是已记录的既定行为）。把查证结论写进工作日志（见交付）。

## 任务一（A1）：App 内建 MCP 客户端，box 全组甩桥

现状：App 经伴生 box 桥（8645）调 7 个端点：`/box/status`、`/box/view-token`、`/box/screenshot`、`/box/act`、`/box/files`、`/box/files/read`、`/box/shell`，客户端为 `BoxBridgeClient.swift`、`BoxFilesClient.swift`、`BoxShellClient.swift`，消费方 `BoxBridgeStore`、`BoxFilesView`、`BoxTerminalView`、`ComputerView`、`BrowserView`、`AgentHubStore`。

要做：

1. **新增 App 内 MCP 客户端**（Swift）：streamable HTTP＋JSON-RPC 2.0；完成 initialize 握手并保存 `Mcp-Session-Id`；会话对象长驻、工具调用串行化；会话失效懒重连（语义对齐 box_bridge.py：重连＝新会话、窗口重置可接受，但必须在代码注释与日志里如实呈现，不许假装无缝）。响应须兼容纯 JSON 与 `text/event-stream` 两种形态；解析 tools/call 结果的 content 数组（text／image／structuredContent）与 isError。
2. **工具映射**（以 box_bridge.py 的实际调用为准逐项核对工具名与入参，不许凭猜）：status→`box_status`、view-token→`box_view_token`、screenshot→桥所用截图工具、act→`computer_act`／`browser_navigate`、files 列表与读取→`list_dir`／`read_file`（含桥现行的纯文本目录形状解析，App 侧同等解析）、shell→桥所用 shell 工具。
3. **换传输不换脸**：三个 Box 客户端的公开 API 与 DTO 尽量保持签名不变，消费方（Store／View）零改或最小改；改完后 App 代码中不得再出现对上述 7 个桥端点的调用（grep 自证）。桥客户端基座（BridgeClientBase）若被这三个客户端共用，抽走后不许影响其他桥客户端。
4. **凭据与地址**：MCP 地址默认 `https://mcp.box.simular.ai/mcp`，可由用户在云电脑连接面填写的地址覆盖；盒子钥匙＝用户在 App 内自填——存取走仓内既有 `KeychainStore`（用户自有服务钥匙的既有存法），**不许**落 UserDefaults／明文文件／日志；现行「经单钥通道送服务端保管」的连接凭据流（ConnectionsStore／CompanionFrontClient）一字不动，Hermes 侧用盒子不受影响。若现行连接面已经把用户填的钥匙交到某个本地可复用位置，先查清再接，不许新造第二套凭据流；查无可复用位置时，在既有云电脑连接面的盒子条目上补本地 Keychain 保存（与提交服务端同一次填写），并在日志中说明接法。
5. **测试**：为可测的纯逻辑加单测——JSON-RPC 信封编解码、Session-Id 捕获、tools/call 结果解析（text／image／isError 三态）、list_dir 文本形状解析。放置位置按仓内既有分层（纯逻辑优先 OneDayCore，若 Box DTO 在 App 层则就近 App 层测试），不许为了测试大搬家。

## 任务二（A3）：ai-sessions 退役清理

1. **App 侧**：全仓 grep 证实 App 无 `/ai-sessions` 调用方（已知仅 `SessionClassification.swift` 注释与 `TraceEchoTests` 夹具字符串）。**红线**：`SessionClassification.aiCastSessionPrefix`（`oneday-ai-` 前缀）是现行会话分类逻辑、且 `/mcp-sessions` 门仍在铸此
...[truncated 2085 chars]