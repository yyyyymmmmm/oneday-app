# 里程碑 2 接口摸排（2026-11-08 晚，Hermes v0.23.0 实测）

方法：POST /auth/password-login 拿会话 cookie 后逐个探路。基址 https://hermes.didichou.site（Dashboard :9119）。

## 已确认存在（登录后 200）
- GET /api/cron/jobs → 裸数组（当前 []）；定时任务管理走这里（CRUD 方法待里程碑 2 写操作时逐项验）
- GET /api/memory → {active, providers:[{name, description, available, configured, status, setup...}]}；记忆提供方管理面
- GET /api/logs → 200（日志）
- GET /api/files → {path, parent, entries:[{name, path, is_directory, size, mtime, mime_type}]}；数据目录 /opt/data 文件浏览
- GET /api/webhooks → 200
- GET /api/config、/api/sessions、/api/skills、/api/profiles（里程碑 1 已确认）

## 已确认不存在（404）
- /api/cron、/api/cron-jobs、/api/jobs、/api/scheduler
- /api/memories、/api/model、/api/models、/api/providers、/api/keys、/api/system、/api/plugins、/api/mcp、/api/channels

## 推论（待 M2 验）
- 模型与提供商：无独立端点，走 /api/config 的 model/providers 字段（读写同路）
- 密钥（KEYS 页）：不在 /api/keys；候选 /api/env 或 config 子路，M2 首日先探
- MCP/插件/渠道页：多半聚合自 config 或各自带前缀路径，进 M2 时抓 SPA 请求定案
