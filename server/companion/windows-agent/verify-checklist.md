# Windows 代理装完验活手册（云电脑收口规格 §5）

对象：在目标 Windows 机器上跑完 `install-windows-agent.ps1` 之后。四级全过才算「通」；任何一级不过，如实记录卡在哪一级，不许跳级报通。

前置事实（先说清，不假装）：
- 桌面类工具（点按/截图/元素树）需要一个**已登录的交互会话**。云 VPS 的常态做法：RDP 登录后**断开而不注销**，或设置自动登录。会话注销了，代理进程还在，但桌面工具会没画面可用。
- 内部 auth-key 是这台电脑的钥匙：只许经内部路径回填到伴生连接记录（companion 状态文件），**不经 App、不经聊天、不进任何工单**。
- 本手册与安装件截至 2026-11-12 **未在真机实跑过**（无试点机）；命令参数以 Windows-MCP 官方 README 为据，实机如遇参数漂移，先以 `windows-mcp --help` / `windows-mcp serve --help` 的实机输出为准，并把差异回写本手册。

## L1 · 在：进程与端口

在目标机 PowerShell：
```powershell
Get-ScheduledTask -TaskName 'windows-mcp-server'        # 任务在
Get-NetTCPConnection -LocalPort 8000 -State Listen      # 端口在听
Get-Content "$env:USERPROFILE\.windows-mcp\server.error.log" -Tail 20   # 无致命错误
```

## L2 · 通：MCP 协议应答

自伴生所在网络（或同网机器）对端点发 initialize＋tools/list（把 `<IP>`、`<KEY>` 换成实值）：
```bash
curl -sk https://<IP>:8000/mcp -H "Authorization: Bearer <KEY>" \
  -H 'Content-Type: application/json' -H 'Accept: application/json, text/event-stream' \
  -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-03-26","capabilities":{},"clientInfo":{"name":"verify","version":"1"}}}'
```
判据：回 serverInfo；随后 tools/list 数得出工具清单（量级与 Windows-MCP 的 19 个工具相符，含 App / PowerShell / Screenshot / Snapshot）。错钥应回 401——顺手验掉。

## L3 · 被发现：Hermes 侧在列

1. 运维把端点＋内部钥回填伴生连接记录（secret 的 endpointUrl/token），伴生生成 pendingConfigEntry（条目名 `vps-<slug>`）。
2. 窗口期重启 Hermes 后：
   - `hermes mcp test <条目名>` 能列出工具；
   - `GET /api/mcp/servers` 里这台电脑与既有条目同列；
   - App 里这台电脑详情状态翻「已生效」（伴生 effective 随窗口动作更新）。

## L4 · 能干活：开浏览器＋回图

在 OneDay 里让智能体对这台电脑执行：
1. 用 App 工具打开 Edge，打开任意网页（如 example.com）；
2. 用 Screenshot 工具回一张图。
判据：图回得来、画面里是 Edge 与目标网页——到此才算「能开浏览器为通」，全链收口。

## 常见卡点

| 现象 | 多半原因 | 处理 |
|---|---|---|
| L1 端口不听 | 计划任务没触发/配置写坏 | 看 server.error.log；手动 `windows-mcp serve --transport streamable-http --host 0.0.0.0 --port 8000` 前台跑一次看报错 |
| L2 连不上 | 防火墙没放行/来源没放行 | 核对规则 `OneDay-Windows-Agent` 的来源范围与端口 |
| L2 回 401 | 钥不对 | 以 config.toml 里的 auth_key 为准重对（钥只在本机这一个地方） |
| L4 截图黑屏/无元素 | 交互会话已注销 | RDP 重新登录并保持会话（断开≠注销） |
| UAC 弹窗点不动 | Secure Desktop 隔离（引擎固有限制） | 人工在那台机器上点掉；属已知边界，不算故障 |

## 轮换内部钥与卸载

- 轮换：目标机重跑 `windows-mcp auth --transport streamable-http --host 0.0.0.0 --port 8000 --with-tls` → 新钥回填伴生记录 → 重启计划任务；旧钥即刻失效。
- 卸载：`windows-mcp uninstall`（摘计划任务）→ `uv tool uninstall windows-mcp` → 删 `%USERPROFILE%\.windows-mcp` → 删防火墙规则 `OneDay-Windows-Agent` → App 里对该电脑执行「断开」清服务端记录。
