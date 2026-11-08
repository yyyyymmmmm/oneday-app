# Hermes 接口面对接清单（服务端 v0.23.0）

基准部署：https://hermes.didichou.site（2026-11-08 实测）。
API Server（:8642）与 Dashboard（:9119）由 nginx 同域反代：
API 走 /v1/ 与 /health，Dashboard 走 / 与 /api/*。
鉴权分两个面：**Dashboard 会话 cookie** 管管理面，
**Bearer API 密钥** 管对话面（/v1/*）。App 两样都要存（Keychain）。

## 已实测接口（里程碑 1 已对接）

### GET /health — 健康（免鉴权）
- 200：`{"status": "ok", "platform": "hermes-agent", "version": "0.23.0"}`
- 用途：三步探活第一步；非 200 或 status≠ok 视为不通过。

### POST /auth/password-login — 面板登录（Dashboard）
- 请求：JSON `{"provider": "basic", "username": "…", "password": "…", "next": "/"}`
  - 缺 provider 字段返回 422（FastAPI 校验错误），四字段缺一不可。
- 成功：200 + Set-Cookie 会话（URLSession 共享 cookie 存储持有）。
- 失败口径：401/403/422 → 账号或密码不对。
- 会话过期后 /api/* 返回 401；App 用已存密码静默重登一次兜底。

### GET /api/status — 状态总览（免登录）
- 200 节选：`{"version": "0.23.0", "release_date": "2026.9.24",
  "config_version": 52, "gateway_running": true,
  "gateway_state": "running",
  "gateway_platforms": {"api_server": {"state": "connected",
  "error_code": null, "error_message": null, "updated_at": "…"}}}`
- 解码口径：字段全宽容（可选＋默认），小版本增减字段不许打死总览页。

### GET /api/config — 配置摘要（需会话）
- 200 节选：`{"model": "anthropic/claude-opus-4.6", "providers": {…},
  "toolsets": ["hermes-cli"], …}`
- 未登录：401 `{"error": "unauthenticated", "reason": "no_cookie",
  "login_url": "/login"}`
- 里程碑 1 只取 model / providers 键名 / toolsets 做总览摘要。

### GET /v1/models — 模型列表（Bearer）
- 200：`{"object": "list", "data": [{"id": "hermes-agent", …}]}`
- 用途：三步探活第三步（401/403 → 密钥被拒）；对话模型 id 取首项。

### POST /v1/chat/completions — 对话（Bearer，OpenAI 兼容）
- 请求：`{"model": "hermes-agent", "stream": true, "messages": [{role, content}…]}`
- 流式响应：SSE 逐行 `data: {…choices[0].delta.content…}`，
  以 `data: [DONE]` 结束；未发 [DONE] 收尾也按完成处理。
- 注意：后端未接模型时，回复是提示文本而非报错（HTTP 200），
  App 侧照常呈现，不做特殊分支。

## 已实测存在、里程碑 2 对接

| 接口 | 方法 | 鉴权 | 实测 | 用途 |
|---|---|---|---|---|
| /api/sessions | GET | 会话 | 200（sessions[]，含 id/source/session_key） | 会话管理 |
| /api/skills | GET | 会话 | 200 | 技能管理 |
| /api/profiles | GET | 会话 | 200 | 档案管理 |

## 待摸排（里程碑 2 开工先行）

- **定时任务**：/api/cron 返回 404，真实路径未知。候选：/api/jobs、
  /api/cron/jobs、/api/schedules。摸排法：登录 Dashboard 网页后
  看 Network 请求，或抓 Dashboard 前端 JS 包 grep "/api/"。
- **记忆管理**：路径未知，同上摸排（候选 /api/memory、/api/memories、
  配置内的 memory 段）。
- **配置写入**：/api/config 的 PUT/PATCH/POST 方法与字段口径
  （模型切换、提供商增删都在此面），需逐方法试探并留档。
- **模型管理**：Dashboard 侧 /api/models 返回 404；模型切换
  疑经配置写入完成，摸排后定。
- **技能开关**：/api/skills 的写方法（POST/PATCH）与参数。
- **会话操作**：/api/sessions 的 DELETE / 单条详情路径。
- **日志**：网关日志接口路径未知，同上摸排。
- **档案写操作**：/api/profiles 的增删改方法。

摸排纪律：只在自有服务器上试探；每个确认的接口补进本文件
（方法、路径、鉴权、请求/响应样本、失败口径）后再写 UI。
