# ADR: 短时票据认证方案定案（#1）

状态：**已拍板（按大厂移动端标准落地）**  
适用范围：OneDay iOS App ↔ Hermes API Server（`server/patches/api_server.py`）

## 1. 四个核心参数定案

| 决策项 | 最终口径 | 设计依据 |
| :--- | :--- | :--- |
| **Access Token 有效期** | **24 小时** | 个人自托管场景存在弱网与离线阅读，24 小时在体验与暴露面之间最均衡。 |
| **Refresh Token 有效期** | **30 天（活跃滑动续期，绝对上限 90 天）** | 正常使用无需重登，长期闲置自动失效。 |
| **轮换时机与防误杀** | **每次刷新即轮换（Refresh Token Rotation）+ 10 秒宽限窗口 + 复用检测** | 冷启动并发请求可能同时触发刷新，10 秒宽限窗口内允许旧 Refresh Token 命中同一批新票；超过宽限窗口若旧票被再次使用，立即作废该设备会话家族。 |
| **一期撤销方式** | **服务端设备会话表删记录（吊销 Refresh Token）+ Access Token 等自然过期** | 一期不引入 Redis 黑名单与实时推送强踢，靠 SQLite/JSON 会话表即可满足单设备踢下线与换机清理需求。 |

## 2. 接口契约（面向二期实施）

- `POST /v1/auth/exchange`：使用现有登录密钥（`API_SERVER_KEY`）或设备认领码换取 `{access_token, refresh_token, expires_in, session_id}`。
- `POST /v1/auth/refresh`：提交 `{refresh_token}`，按 Rotation + 10 秒宽限窗口返回新票对。
- `GET /v1/auth/sessions`：列出当前已登录设备会话（设备名、最近活跃时间、App 版本）。
- `POST /v1/auth/revoke`：按 `session_id` 或 `all_other_devices` 吊销对应 Refresh Token。

## 3. 兼容过渡策略

- 过渡期服务端同时接受传统 `API_SERVER_KEY` 与短时 `Bearer` Access Token；
- 通过 `/v1/capabilities` 广告 `features.short_lived_tokens = true`，旧版 App 无感知继续运行，新版 App 检测到能力位后自动升级为换票流。
