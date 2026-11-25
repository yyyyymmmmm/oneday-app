# device-bridge 注册进 Hermes MCP · 执行记录（2026-11-10 20:52–20:58 CST）

授权：用户 2026-11-10 20:49 亲自批准（含重启 Hermes 一次）。执行前服务器内存 52.8%（红线 80% 内）。

## 做了什么

1. **备份**（服务器上，0600 区）：
   - `/opt/data/config.yaml.bak-20261110-device-mcp`（134,044 字节）
   - `/opt/data/.env.bak-20261110-device-mcp`
   - `hermes.example.com.conf.bak-20261110-devicemcp`（nginx）
   - 清理测试会话前另备：`/opt/data/state.db.bak-20261110-devicetest`（17,616,896 字节）
2. **.env**：给 Hermes 的 `/opt/data/.env` 追加 `DEVICE_BRIDGE_KEY` 一行，值在服务器内自 device-bridge 自己的 env 文件直读直写，未出服务器、未进任何工作区文件。
3. **config.yaml**：`mcp_servers` 下新增（照 github 条目同形，锚定其 Authorization 行后插入）：
   ```yaml
   device:
     url: https://hermes.example.com/api/device-mcp
     headers:
       Authorization: "Bearer ${DEVICE_BRIDGE_KEY}"
   ```
4. **nginx**：启用草案中的 MCP 门面路由 `location = /api/device-mcp` → `127.0.0.1:8647/mcp`（透传 Authorization、proxy_buffering off、read_timeout 120s），插在既有 `/api/device-bridge/` 块之后；`nginx -t` 通过后 reload。
   - 为什么走公网域名而不是容器直连本机端口：实测 hermes 容器内 `http://172.18.0.1:8647` 不通（桥只绑宿主机 127.0.0.1），而 `https://hermes.example.com/health` 回 200——公网路由是唯一现成可达路径，且正是预建草案的设计形态。
5. **重启 hermes 容器一次**：20:55:15 发起，容器约 20:55:25 拉起，健康检查在容器 Up 28 秒时已回 200——**总中断约 40 秒**。除 hermes 外未动任何容器。

## 验活证据

- `hermes mcp list`：device 与 notion、github 同列，enabled。
- `hermes mcp test device`：✓ Connected（1523ms），✓ Tools discovered: **10**——device_status、calendar_list_events、calendar_create_event、calendar_update_event、reminders_list、reminders_create、reminders_complete、contacts_search、health_daily_summary、home_status（与设计档工具面逐个对上）。
- 门面直调（经新 nginx 路由）：initialize 回 serverInfo=device-bridge；tools/call device_status 正常返回。
- **实调（重启后运行面）**：经网关发真会话问「我手机通讯录一共有多少人」，桥审计 `data/audit.jsonl` 实录两条（2026-11-10 20:57 CST）：`device_status` ok → `contacts_search` error `device_offline`。智能体答复如实：设备离线、没读到数据、不编数字，并提示打开 App 后再查。**断点已消除**：此前智能体根本没有设备工具（只能在服务器上找文件），现在工具在手、调用链真通。
- Dashboard `GET /api/mcp/servers` 未直读到：该面是 cookie 会话鉴权（basic 换 cookie 未被接受），未继续纠缠；以上 CLI＋审计实录为等效且更强的运行面证据。

## 当前状态与剩余一步

- 测试当时 `device_status` = **online: false**：手机上的 OneDay 设备会话未在线（心跳 >45 秒判离线）。**差最后一步：用户打开 OneDay（保持前台片刻）后，在对话里再问一次**，即可走 App 现读现回拿真数。
- 一个能力边界（智能体在测试答复里自己点明、属实）：通讯录工具只有 `contacts_search`（按名字关键词搜），没有「统计总数」接口。「一共有多少人」能否靠空关键词探全量，要等设备在线时实测 App 执行器行为；若只做关键词匹配，总人数问题需给 App 执行器补计数能力（产品侧决定，不在本轮）。
- 健康/家庭两工具已随门面注册，但 App 侧执行器仍受签名权益闸（目录里标「待签名权益」）——调用会如实回不可用，不假装能查。
- 测试会话 `mcp-devicetest-20261110`（1 会话＋8 消息）留在 state.db：直删被 state.db 的保护触发器拒绝（gateway runtime history 守卫），已回滚未删成，integrity ok；留待后续按正规路径批量清理，备份已备（见上）。

## 回滚法

还原三件备份＋再重启一次 hermes：
```bash
cp /opt/data/config.yaml.bak-20261110-device-mcp /opt/data/config.yaml
cp /opt/data/.env.bak-20261110-device-mcp /opt/data/.env
cp /www/server/panel/vhost/nginx/hermes.example.com.conf.bak-20261110-devicemcp \
   /www/server/panel/vhost/nginx/hermes.example.com.conf
/www/server/nginx/sbin/nginx -t && /www/server/nginx/sbin/nginx -s reload
docker restart hermes
```
（nginx 路由即使留着、config 里删掉 device 条目也即断链；全量还原为最稳。）
