# 修复简报三轮：API 直连第一包残余项（协调二轮验收实查，逐条销）

工作区/分支不变，在 `b54463b` 之上修，分项小提交后 push。二轮大部分已过，以下为实查未过/漏项（都附了证据，不许以「已改」自述代替 diff）：

## M1（致命）目录条目键名仍错——F9 第一条没落

`BoxFilesClient.parseDirectoryListing` 拼的条目仍是 `"isDirectory"`／`"mimeType"`（当前文件 239/259/265 行），而 `WorkspaceFileEntry.CodingKeys` 要求 `is_directory`／`mime_type`，`FilesListing` 解码每次必抛错、文件列表整体不可用。改成桥原样键名（name/path/is_directory/size/mtime/mime_type）。
补回归测试：`Tests/OneDayAppTests`（已有 @testable import OneDayApp 先例）加一条——喂一段厂商 list_dir 文本给 parseDirectoryListing，断言解码出条目数、isDirectory、size、mimeType 都对。

## M2（布尔参数会被写成数字）anyToJSONValue 判定顺序

`BoxMCPClient.anyToJSONValue` 的 switch 先判 Int/Double 后判 Bool：Darwin 上 Bool 经 NSNumber 桥接会先命中 Int，`["wait": true]`、`["front": true]` 会被发成 `1`。把 Bool 判定提到 Int/Double 之前。补一条 Core 或 App 测试钉住 bool 参数编码为 JSON true（可在 MCPProtocolTests 里测信封 arguments 的编码结果，前提是转换函数可测；不可测就把转换函数下沉/暴露为 internal 后测）。

## M3 initialize 的 SSE 响应未处理

`BoxMCPClient.initialize()` 直接对原始 data 解 MCPResponse；服务端若以 text/event-stream 回 initialize 就必失败。复用 callTool 同款逻辑：按 Content-Type 分流，SSE 时 parseSSEResponse(data:requestId:) 抽取后再解。

## M4 假覆盖仍在

`BoxMCPClientFactory` 仍读 UserDefaults `box.mcp.url`（无人写、产品面无此输入）。删掉，URL 用具名常量。

## M5 仓库卫生收尾

工作日志已外置到 `~/workspace/oneday-design-review/api-direct-a-worklog-20261114.md`（协调方已确认存在），把仓内 `CLAUDE-WORKLOG-API-DIRECT-A.md` 用 git rm 删除，本轮工作日志续写到仓外那份。

## M6（小）initialized 通知不许带 id

现行用 MCPRequest（恒带 id）发 `notifications/initialized`——那是请求不是通知。改用无 id 的通知信封编码（jsonrpc＋method，无 id 字段）。

不许动：其他已验收部分、公开 API 签名、伴生、版本号。完成后 push 并在仓外工作日志逐条销账 M1–M6。不要自己跑 CI。
