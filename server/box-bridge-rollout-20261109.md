# 盒桥 box-bridge 上线记录（2026-11-09）

P2 浏览器打通·服务端先行。把 Simular Box 的浏览器/桌面能力做成 OneDay 可消费的 HTTP 接口（状态/画面/接管），独立 sidecar，与 hermes 容器、其 config、既有 compose 工程完全隔离。

## 部署形态

- 服务器 118.24.41.52，目录 `/www/dk_project/dk_app/box-bridge/`（独立 compose 工程）
  - `box_bridge.py`（原件存本目录同名文件，459+ 行，纯 stdlib HTTP 层 + 镜像内 mcp SDK 客户端）
  - `docker-compose.yml`：image `nousresearch/hermes-agent:v0.23.0`、container `box-bridge`、entrypoint 用镜像内 venv 的 python3 跑桥脚本（脚本只读挂载 `/opt/bridge/box_bridge.py`）、`mem_limit 256m`、restart unless-stopped
  - `box-bridge.env`（0600，服务器本地组装）：`MCP_BOX_API_KEY`（自 hermes data/.env 提取）+ `WRITE_GATE_KEY`（自 hermes write-gate.env 复用同一把桥钥匙）
- 端口：仅绑 `127.0.0.1:8645`
- 公网入口：nginx 站点 hermes.example.com 追加一段（备份 `hermes.example.com.conf.bak-20261109-boxbridge`，`nginx -t` 通过后 reload）：
  `location /api/box-bridge/` → `proxy_pass http://127.0.0.1:8645/box/`（剥前缀、透传 Authorization、read_timeout 120s）
- 桥内架构：专职事件循环线程持有一条**长活 MCP 官方 SDK 会话**直连厂商 `https://mcp.box.simular.ai/mcp`（不经 Hermes tool_call 间接层）；全部工具调用经锁串行；调用失败自动断开重连、重试一次（实测发生过 1 次厂商侧断连、自愈，日志 "Session termination failed: Server disconnected without sending a response." 后自动重建）
- fail-closed：`WRITE_GATE_KEY` 或 `MCP_BOX_API_KEY` 任一缺失拒启

## 契约（App 线对接以此为准）

基址：`https://hermes.example.com/api/box-bridge`，全部端点（除桥内 /health 不经公网）要求 `Authorization: Bearer <write-gate 桥钥匙>`（与 write-gate/overview 两桥同一把，App 已存的那把即可）。无/错 Bearer → 401（本机与公网均实测）。

### GET /status
```json
{
  "state": "running",                  // box_status 原生值：running / 睡眠等
  "name": "main",
  "boxId": "cb-b8486e59e25a",
  "image": "sbxdesk:v13",
  "latestImage": "sbxdesk:v13",
  "upgradeAvailable": false,
  "lastSavedAtMs": 1794149613120,
  "viewUrl": "https://box.simular.ai/box/cb-b8486e59e25a/live",
  "creditsLeft": null,                 // 见下方「额度口径」
  "creditsNote": "box plans are not enabled",
  "page": {"title": "Example Domain", "url": "https://example.com/"},  // 活读，可为 null，见「窗口语义」
  "lastKnownPage": {"title": "Example Domain", "url": "https://example.com/"},
  "lastKnownPageAt": "2026-11-09T08:17:38+00:00",
  "checkedAt": "<ISO8601>"
}
```
状态读**不唤醒** Box（纯 box_status＋billing＋快照活读）。

### GET /view-token
厂商实时视图通道（双通道之一）：
```json
{"view": {"token": "<442 字符>", "expires_at_ms": 1794215134000, "ws_url": "<32 字符>"},
 "viewUrl": "https://box.simular.ai/box/cb-b8486e59e25a/live"}
```
`view` 为 box_view_token 结果透传（parsed 优先）。令牌为短时效凭据，App 取后即用、勿落盘。

### POST /screenshot  body: {"maxEdge": 1024}（可选，默认 1024）
先 ensure_running（box 已睡眠时才 box_ensure 唤醒，状态缓存 20 秒）再截桌面图：
```json
{"mime": "image/jpeg", "width": 1024, "height": 640, "bytes": 58832,
 "imageBase64": "...", "capturedAt": "<ISO8601>"}
```

### POST /act  —— 一个动作下去一图回
导航：`{"action": "navigate", "url": "https://...（仅 http/https）", "front": true}`
→ `{ok, action, tool: "browser_navigate", page: {title,url}, summary, screenshot: {同截图结构}}`

桌面动作（computer_act 语义）：action ∈ `click / double_click / right_click / triple_click / type / key / hotkey / scroll / drag / wait / launch_app / locate`
字段白名单：`element, x, y, to_x, to_y, text, key, keys, direction, amount, button, app, seconds, foreground, target{description,text?}, max_edge`
→ `{ok, action, tool: "computer_act", summary, screenshot: {...}}`（工具自带回图优先，否则补截一张）
坐标系：最近一张截图的像素（默认长边 1024 缩放，即 1024×640 空间）。
**`type_from_file` 明确拒绝**（涉及卡数据文件，不开放）。

错误映射：参数问题 400、Box 工具报错 502（带厂商错误文本）、MCP 会话不可用 503。

## 窗口语义（重要，实测得出）

- Chrome 窗口绑 MCP 会话：**盒桥会话的窗口 ≠ Hermes agent 会话的窗口**；桌面是共享单桌面（screenshot/computer_act 作用于共享桌面，厂商实时视图看到的也是这个桌面）。
- 厂商的浏览器自动化绑定在导航后会较快失效：实测导航后首次状态读能拿到 page，数秒至数分钟后 browser_snapshot 即报 "you have no Chrome window open"——但**桌面上的页面并未消失**（同期桌面截图仍是该页面）。即失效的是自动化附着，不是窗口本身。桥内对策：状态读对快照做 1 次重试（隔 0.9s）；仍落空时 page=null（诚实），同时以 `lastKnownPage/lastKnownPageAt` 给出本桥最近一次正向确认（导航回执或活读成功）的页面与时刻，App 应带时间标注展示，不得当作活读。
- 桥容器重启或 MCP 会话重建后窗口绑定重置，page 回 null、lastKnown 清空（进程内状态）；navigate 一次即恢复。
- Box 本体睡眠时：screenshot/act 会先唤醒（box_ensure）；status 不唤醒。

## 额度口径（如实）

`billing` 工具在本机当前计划下直接报错 "box plans are not enabled"，Box 工具面里没有 credits 余额来源（usage 工具是 token 用量，非 Box credits）。故 `creditsLeft` 恒为 `null` 并附 `creditsNote` 原文，不编造数字。将来计划开通后 billing 若给出数字字段，桥会自动填入 creditsLeft。

## 验收实查（2026-11-09，本机 8645 与公网 https 各一整套）

- /health：`{ok:true, service:"box-bridge", mcpSession:"up"}`
- 鉴权：无 Bearer 401、错 Bearer 401（本机＋公网各验）
- 状态：state=running、name=main、creditsLeft=null＋note；导航后 page={Example Domain, https://example.com/} 活读命中；lastKnown 字段与时间戳正常
- 导航（act）：200，page 标题 "Example Domain"，回图 image/jpeg 1024×640、58,835 字节（本机）/ 58,844 字节（公网）
- 截图端点：200，image/jpeg 1024×640、58,832 字节（本机）/ 58,724 字节（公网）
- 点击（act click 512,300 → computer_act）：200 ok，回新截图 1024×640
- view-token：200，view={token(442 字符), expires_at_ms, ws_url(32 字符)}（值不落记录）
- 内存：动手前 49.7% → 完工 53.4%（含同窗其他线活动；桥自身约 59MB / 上限 256MB）；全程未触 80% 红线
- 隔离：未碰 hermes 容器/config/其 compose 工程；nginx 仅追加自有段

探针残留已清：服务器 /tmp 下 box/sdk/mcp 探针脚本与含钥临时文件全部删除。

## 文件端点（2026-11-09 晚补，P8 遗留缺口实现）

按冻结契约 `~/workspace/oneday-design-review/box-files-contract-20261109.md` 给盒桥新增只读文件面，桥脚本 md5 `b37806d5…` → `6e2f093f…`（本地原件与服务器双验一致），仅重启 box-bridge 本体，未碰 hermes 与其它桥；服务器内存 48.7% → 51.7%（含探针唤醒 Box 与同窗活动），未触红线。

### 端点（挂 /box 下，鉴权同既有桥钥匙 Bearer）

- `GET /files?path=<相对路径>`：相对 `/workspace`，缺省=根。响应与 Hermes `GET /api/files` 同构：`{path, parent, root:"/workspace", locked_root:"/workspace", can_change_path:false, entries:[{name, path(相对), is_directory, size, mtime, mime_type}]}`；单目录上限 500 条，超出截断并带 `truncated: true`。
- `GET /files/read?path=<相对路径>`：返回文件原始字节，Content-Type 按扩展名猜测（客户端不依赖此头）。

### 厂商形状（探针实查，桥内归一化口径）

- `list_dir`：Box 休眠时也可读（读已保存文件系统状态，不唤醒）；返回纯文本——首行 `<绝对路径>:`，其后每行一条：目录为 `name/`、文件为 `name  (N bytes)`。桥据此解析 name/is_directory/size；`mime_type` 由扩展名猜测；**厂商不提供 mtime，条目一律 `mtime: null`**（客户端字段可空，不编造）。list_dir 入参可相对可绝对，桥统一传绝对路径；桥另外核对返回首行解析路径仍在 `/workspace` 内（防符号链接跳出）。
- `read_file`：是**带行号的文本视图**，不是原始字节——每行加 `%6d\t` 前缀、单次硬顶 2000 行（带 `[showing lines …]` 尾注）、超 2000 字符的行被截断（行尾带 ` [line cut: N of M characters shown]`）、空文件/读过尾返回 `<路径> has N lines; nothing at offset M`、二进制文件只回 `<路径> is a binary file of N bytes`。桥的归一化：分页（offset 步进 2000）拼行、剥行号前缀重组文本；遇 binary 标记或 line cut 标记（文本会被污染/截断的情形）改走 `shell` 的 `base64 -w 0` 取精确字节（上限 8MB，超限 502 人话）——**shell 调用会自动唤醒 Box**（与 screenshot/act 的 ensure 口径一致，属正常动作）；纯文本路径不唤醒。已知不可恢复项：原文末尾的换行符在行视图里不可见，重组文本会丢掉末尾换行（预览无碍，特此留痕）。

### 错误映射

- 路径越界（绝对路径、`..` 段、空段、`.` 段、反斜杠）在 MCP 调用前拦截 → 400；符号链接解析出工作区 → 400。
- 文件不存在：read → 404（与列表 404「未开通」口径分开，客户端报「已不存在」）；列表目录不存在 → 404。
- 读目录 → 400；厂商其它失败 → 502（带厂商错误文本）；未鉴权/错钥 → 401。

### 验收实查（本机 8645 与公网 https 各一整套，测试数据已清净）

- 列表对账：根（boxtest/、flows/ 两目录，字段逐项合契约）、子目录（7 个文件 size/mime 逐项对）、空目录（entries []）、505 文件目录截断（entries 500＋`truncated: true`）。
- 读取逐字对：54 字节多行中英文本 md5 `1e576f24…` 与原文一致；70 字节 PNG 走 shell 兜底 md5 `1798dfee…` 与原图一致；3000 行文件分页拼回 3000 行完整；两条超长行文件（3000/12000 字符）走 line cut 兜底 md5 均与原文一致；空文件 200 且 Content-Length 0；带尾换行文件重组为无尾换行（上述留痕项）。
- 越界：`../`、`..%2f`、`%2e%2e%2fetc`、`/etc`、`/workspace/flows`、`flows/../../etc`、`a//b`、`.`、read 无 path 参数 → 全 400。
- 鉴权：无钥/错钥对 /files 与 /files/read 各 401（本机＋公网）。
- 回归：/status 200（state=running）、/screenshot 200、/act(wait) 200 ok，均无异常。
- 测试残留已清：探针在 Box 内建的 `/workspace/boxtest/`（含 many/ 505 文件）整目录删除，根列表复验回到只有 `flows/`；服务器 /tmp 测试输出文件已删。注：探针的 shell 调用把 Box 从休眠唤醒为 running（正常动作，Box 自行再休眠）。

### 本节回滚

1. `cp /www/dk_project/dk_app/box-bridge/box_bridge.py.bak-20261109-filesapi /www/dk_project/dk_app/box-bridge/box_bridge.py`
2. `docker restart box-bridge`（脚本为只读挂载，重启即生效）。
两步后 /files 与 /files/read 回到 404（客户端如实显示「电脑文件尚未开通」），其余端点不受影响。

## 终端端点（2026-11-09 晚补，P9 遗留缺口实现）

按冻结契约 `~/workspace/oneday-design-review/box-shell-contract-20261109.md` 给盒桥新增 shell 执行面，桥脚本 md5 `6e2f093f…` → `e13fd316…`（本地原件与服务器双验一致），仅重启 box-bridge 本体，未碰 hermes 与其它桥；服务器内存 49.1% → 49.9%，未触红线。验收全程 Box 处于 running（探针与验收的 shell 调用属显式动作，唤醒口径与 screenshot/act 一致）。

### 端点（挂 /box 下，鉴权同既有桥钥匙 Bearer）

- `POST /shell`，body `{"command": "..."}` → `{"ok": bool, "output": str, "exitCode": int|null, "truncated": bool}`。命令由用户在 App 内逐条手输、桥**原样透传**厂商 `shell` 工具，不拼接不改写不过滤；执行域是 Box 沙箱，桥不转投任何宿主机 shell。先 `ensure_running`（同动作面口径），MCP 调用超时 90 秒，超时回 504 人话，其余厂商失败 502、MCP 不可用 503；空/纯空白/缺失/非字符串命令 → 400。

### 厂商形状（探针实查，桥内归一化口径）

- `shell` 为持久会话（cwd `/workspace` 起），结果恒为**单个 text block**：合并输出（stdout＋stderr 已由厂商合并）＋尾部 `[exit status N]` 行。归一化：剥掉 trailer 与其前一个分隔换行 → `output`；trailer 整数 → `exitCode`；trailer 缺失 → `exitCode: null`（客户端回落 `ok`，桥侧 `ok` 置 true 表示工具已执行）。**口径注记**：厂商线格式把输出尾部恰好一个换行并入分隔，桥归一化后的 output 相对命令原始输出至多差一个尾换行（`read_file` 行视图同病，已留痕）。
- **非零退出时厂商把结果标 `is_error: true`，但 text 里带完整输出与 trailer**——桥先认 trailer、认到即按正常结果归一化（exitCode 非 0、`ok: false`），只有 is_error 且无 trailer 才按厂商失败 502。若照普通工具那样先判 is_error 抛错，所有失败命令都会误报 502。
- 命令不存在的报错原文含厂商临时脚本路径（`/tmp/cocoonbox-shell/mcp-<hash>.sh: line 1: ...`），桥原样透传不修饰。
- 长输出：厂商先于桥截断——总量约 30K 字符处保留头尾、中段以一行 `[... N bytes omitted ...]` 明示省略字节数（实测 `seq 1 20000`：回 30,031 字符、接缝在第 2221 行、标记 `[... 78893 bytes omitted ...]`）。该标记是厂商输出原文的一部分，桥原样透传、客户端可见。桥自身上限 32,768 字符（超出截断＋`truncated: true`＋output 末尾附截断说明）因厂商先行截断在实测中未触发，其逻辑已由本地假 MCP 单元测试钉死（11 组用例全过：trailer 各形态/空输出/is_error 双形/截断/400 各例/命令逐字透传）。

### 验收实查（本机 8645 与公网 https 各一整套，20 项全 PASS，测试零残留）

- `uname -a`：本机＋公网均回 `exitCode 0`、output 与独立 MCP 探针在 Box 内实查逐字一致（`Linux main 6.8.0-142-generic #142-Ubuntu SMP PREEMPT_DYNAMIC Wed Sep  2 14:24:27 UTC 2026 x86_64 x86_64 x86_64 GNU/Linux`）。
- 失败命令：`ls /nonexistent-xyz` → exitCode 2＋厂商原文（本机＋公网）；`( exit 3 )` → exitCode 3（子壳退出，不伤持久会话）；`nonexistent-cmd-xyz` → exitCode 127＋`command not found` 原文；`printf 'abc'` → output 恰为 `abc`（尾换行口径实证）。
- 长输出：`seq 1 20000` → 200、exitCode 0、厂商省略标记在 output 内（见上节）。
- 鉴权/参数：无钥/错钥 401（本机＋公网各验）；空命令 400（本机三例＋公网一例）。
- 回归：/status（本机＋公网）、/screenshot、/files 均 200 无异常。
- 残留：探针/验收脚本（宿主机与容器内 /tmp）已删；验收命令全为只读（uname/printf/ls/seq），Box 内未落任何文件、未留进程。

### 本节回滚

1. `cp /www/dk_project/dk_app/box-bridge/box_bridge.py.bak-20261109-shellapi /www/dk_project/dk_app/box-bridge/box_bridge.py`
2. `docker restart box-bridge`（脚本为只读挂载，重启即生效）。
两步后 /shell 回到 404（客户端如实显示「电脑终端尚未开通」），其余端点不受影响。

## 回滚基线

1. `cd /www/dk_project/dk_app/box-bridge && docker compose down`（或 docker stop/rm box-bridge），删该目录；
2. nginx：删 hermes.example.com.conf 中 `# Box bridge` 段（或用备份 `.bak-20261109-boxbridge` 还原），`nginx -t && nginx -s reload`。
两步后全退，不影响 hermes 与其他两桥。
