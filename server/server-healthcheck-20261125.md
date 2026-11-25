# 服务端全面体检报告（2026-11-25 04:40–04:55，只读审计）

> 纪律：全程只读，未改任何配置、未重启、未删任何东西。高危项只记录＋置顶，未擅自处置。
> 服务器内存：核查前 51.7%、核查后 50.8%，全程远低于 80% 红线。
> 外部视角：公网可达性经用户 Mac（家庭网络、云外视角）实测，非本机自探。

## 结论先行

**总评：主体健康，无数据损坏、无正在发生的静默断供。** OneDay 数据结构完整、台账零坏行、今晨生成管线实跑通（点子 0→5、动态 29→34 均为今晨 04:14–04:19 真实轮次落盘）；9 个定时任务 8 个 last=ok；G1 失败露头两源代码在位、口径与事故面对账一致。**真正的风险集中在公网暴露面**：代理控制面与两个管理面板公网可达、SSH 开着密码登录且无 fail2ban。另有一件定时任务（目标进展日结提炼）仍挂 error、今晚 23:50 才迎来修复后首跑，且不在 07:45 回读覆盖内。

## 问题清单（按风险排序）

### 🔴 高

**H1. mihomo 代理控制面公网可达（9097/9098 实测 OPEN）**
- 证据：metacubexd 容器内实际运行 mihomo 本体（/usr/local/bin/mihomo -f /data/active.yaml）；active.yaml 实查 external-controller=0.0.0.0:9090、allow-lan=true、bind-address='*'；docker 映射 0.0.0.0:9097→8080、0.0.0.0:9098→9090；Mac 外部实测两端口均 OPEN。
- 缓解项：secret 字段已设置（值未读取），控制器需鉴权。
- 风险：控制面在公网接受 secret 爆破尝试；secret 强度未验。
- 建议处置：云防火墙把 9097/9098 收至白名单 IP，或改绑回环＋经隧道访问。归属：基础设施线（需用户点头动云防火墙）。

### 🟠 中高

**M1. SSH 22 公网开放＋密码登录开启＋无 fail2ban**
- 证据：ss 实查 sshd 监听 *:22，Mac 外部实测 OPEN；/etc/ssh/sshd_config 实查 PasswordAuthentication yes；fail2ban 服务不存在（systemctl 返回 unknown）。腾讯云主机安全（YJ-FIREWALL）链在位，部分兜底。
- 建议处置：确认密钥登录全覆盖后关密码登录，或至少装 fail2ban／云防火墙限源。归属：基础设施线。

**M2. 宝塔面板 16630 公网可达**
- 证据：BT-Panel 监听 *:16630，Mac 外部实测 OPEN。面板类是爆破高价值目标。
- 建议处置：确认已设安全入口＋强口令，最好云防火墙限源。归属：基础设施线。

### 🟡 中

**M3. 目标进展日结提炼（6f1d…4c03）仍处 error 态，修复后首跑未验**
- 证据：jobs.json 实查 last=error、lastRun 2026-11-24T23:50:42（HTTP 403 rate_limit，与 laogou8 余额根因同族，事故 6f1d2c_9df8e8ad6d0d 仍 detected、alerted_at=NULL）；该任务未钉模型/通道（model=None），与今晨已恢复并钉版（deepseek-flash＋custom:ailey）的日结/周体检不同。今晚 23:50 是生成切 DeepSeek 官方通道（2.5.1）后的第一次定时跑，能否自愈取决于它走的默认通道，**未实证**。
- 建议处置：主线今晚 23:50 后回读该轮结果；若再失败，比照另两件钉版。归属：服务端线。

**M4. allinssl 证书管理面 7979 公网可达**
- 证据：docker 映射 0.0.0.0:7979→8888，Mac 外部实测 OPEN。
- 建议处置：同 M2，限源或安全入口。归属：基础设施线。

**M5. cron_incidents 5 起 alerted_at 全部为 NULL，且 3 起是已删任务的陈旧 open 事故**
- 证据：executions.db 实查 incidents=5、alerted_at 全 NULL；其中 3 起为 2026-11-15 三个已不存在的任务（7343843862dd/a945522d7375/e57d82643791，auth/script 类），state 仍 detected 挂了 10 天；另 2 起为记忆任务族 11-24 夜 403 事故（1 起已 resolved、1 起 detected）。G1 的基线隔离使存量不回灌 overview（今晨 /v1/overview 实查 unreadNotifications=0、pendingApprovals=0，与「无新增未露头失败」一致），故不构成现行静默失败；但事故表无陈旧清理口径，长期会稀释信噪比。
- 建议处置：给 incidents 加陈旧事故归档/关闭口径（随 G1 后续包）。归属：服务端线。

### 🟢 中低／低

**L1. 台账 seq 10152/10153 各重复出现两次（序号不唯一）**
- 证据：ledger-events.jsonl 全量解析：1089 行、坏 JSON 0 行；逐行定位——行 1033/1034 是两条 status 结算行（job:morning 被打断轮次，即此前人工结算的两个 stale 样本）占用 10152/10153，行 1035/1036 的 collector/cursor 正常事件又被分配到同号。系人工结算写行时未与分配器计数对齐，分配器随后重发同号。内容无丢失、无损坏；仅按 seq 严格去重的消费方可能混淆。
- 建议处置：下次结算类写行先读分配器 nextSeq 对齐；存量不回改（append-only 纪律）。归属：服务端线。

**L2. errors.log 高频 ConnectionError（193 次，文件全期累计）**
- 证据：/opt/data/logs/errors.log 共 7825 行；错误类分布 ConnectionError 193、InternalServerError 47、OAuthNonInteractiveError 36、MCPError 22、ConnectError 12、URLError 8、Permission 类 13。gateway.log 全期 'rejected' 745 次、'409' 55 次——主体是 laogou8 余额 403 与点子 409 时代的存量痕迹，两根因今晨均已修复（2.5.0/2.5.1）；ConnectionError 家族提示上游连接抖动持续存在，量级不致命。
- 建议处置：观察项；若下次体检计数增速不降，再定性到具体上游。归属：服务端线。

**L3. 07:45 回读作业覆盖面两处过时**
- 证据：作业 oneday-morning-round-readback-20261125 在册、enabled、runonce 2026-11-25T07:45（本地 cron 实查）。但其基线数字已变：点子 0→5、动态 29→34（今晨验证轮已先行落盘，07:30 轮将在其上叠加）；且覆盖清单只含记忆日结/周体检，**不含仍处 error 的 4c03**（见 M3，其 23:50 首跑本来也晚于 07:45，属覆盖外事件，需主线另行回读）。
- 建议处置：07:45 结果按新基线解读；4c03 由主线今晚单独回读。归属：主线。

**L4. session_turn_leases 10 行全部过期未清**
- 证据：state.db 实查 10 行，max(expires_at) 已早于当前时刻，属租约残留；机制按过期即无效处理，无功能影响。
- 建议处置：随手清理项，攒到下个维护包。归属：服务端线。

**L5. 本机监听全接口但靠云防火墙兜底的两处（实测已拦截）**
- 证据：宿主机 MySQL（宝塔 /www/server/mysql）监听 [::]:3306、Xvfb :99 监听 *:6099，本机口径均为全接口；Mac 外部实测两端口均 closed/filtered，云安全组实际拦截生效。
- 建议处置：记录在案即可；若将来安全组放行清单变动，这两处会立即变裸奔，改绑回环更稳妥。归属：基础设施线。

**L6. 手动触发记忆周体检时出现一次 fire-claim 竞争副记录**
- 证据：executions 实查 4c02 在 02:23 completed 后 02:24 又有一条 failed（error='Fire claim ownership lost; stale result was discarded.'）；jobs.json last=ok 不受影响，机制自愈。
- 建议处置：无需处置，避免短时重复手动触发即可。归属：记录项。

## 四面逐项核查记录

### 一、数据完整性 —— 通过
- data.json（容器内 /opt/data/oneday/data.json，700KB，04:41 仍在更新）：顶层 16 键结构完整；goals 41、goalEntries 927、ideas 5、feedPosts 34（带图 6）、traces 80、aiSessions 6、kanbanBindings 2；posts/ideas 无重复 id、无空 id。带图仍为 6/34 系已知配图缺口（修复已在队列，非本次新发现）。
- ledger-events.jsonl：1089 行、坏行 0；kind 分布 baseline 988/cursor 26/collector 61/created 5/status 6 等；seq 空间 3–10205 稀疏系分配器与他面共享所致（间隔 2 占多数），非丢行证据；唯一异常为 L1 的两号重用。
- state.db（88MB）：messages 5247 与 messages_fts 5247 精确一致；sessions 1122、session_admissions 1303、worker_receipts 1546、state_meta 4425；无表级异常。体积列观察项。
- executions.db：executions 63（completed 56/failed 7）、cron_incidents 5——与 G1 2.4.0 落地口径（failed 7/incidents 5）逐一对上，无新增漂移。kanban.db 全表为空，与 G1 kanban_failed 源零产出一致（当前无看板任务）。

### 二、静默失败 —— 通过（存量已露头口径成立）
- 定时任务最近轮次：9 件中 8 件 last=ok；唯一 error 为 4c03（M3），且它在 incidents 表有据、非无声消失。
- G1 露头抽验：overview_gateway.py（gateway/platforms/）实查 cron_failed、kanban_failed 两源代码在位；/v1/overview 实查 hermesUp=true、unreadNotifications=0、pendingApprovals=0——今晨无新增失败样本可供实证新露头（2.4.0 落地时已双源活验，见 g1-rollout 记录），本项判「口径一致、无反证」。
- 生成管线：traces 近段全 ok；04:14 点子轮、04:19 动态/点子批次真实落盘（data.json 时间戳实查）；07:30 点子轮 next_run 正常排队。
- 日志反复错误模式：见 L2。

### 三、公网暴露 —— 有 H1/M1/M2/M4（见问题清单）
监听全表定性（Mac 外部实测为准）：
- 公网 OPEN 且属预期：22 SSH（见 M1）、80/443/888 nginx 站点面、3000 new-api（自有中转，令牌鉴权；管理台密码不轮换系用户 2026-11-14 亲裁，属已接受口径）、14850 OneNav（公开导航站，本性公开）、7000 frps（隧道服务端，本性公开，令牌鉴权）。
- 公网 OPEN 且建议收：9097/9098 mihomo 控制面（H1）、16630 宝塔（M2）、7979 allinssl（M4）。
- 仅回环（健康）：8642/9119 hermes 网关与 Dashboard、8095 vaultwarden、7890 metacubexd 代理口、8787 openmuse、3001 uptime-kuma、3307 epay-mysql 映射、7500 frps 控制台、2222 Mac 隧道 sshd、25 postfix。
- 本机全接口但外部实测拦截：3306、6099（L5）。
- 鉴权抽查：网关 /v1/overview 无钥请求被拒（gateway_auth_failed），API_SERVER_KEY 强制生效；9119 Dashboard 仅回环；mihomo secret 已设置。

### 四、定时任务健康 —— 8/9 健康，1 件待今晚首跑验证
jobs.json 与 executions.db 双源对账（hermes cron CLI 交叉查因隧道中断未成，jobs.json 即 CLI 同源）：
| 任务 | expr | 钉版 | last | 下轮 |
|---|---|---|---|---|
| 点子日轮 3df46e2d77cd | 30 7 * * * | 随生成配置（2.5.1 已切 deepseek-v4-pro） | ok（04:14 验证轮） | 今日 07:30 |
| 动态调研 A 44f110d3d796 | 30 8 * * * | — | ok（11-24 08:30） | 今日 08:30 |
| 动态调研 B 98b57c429e4a | 30 19 * * * | — | ok（11-24 19:30） | 今日 19:30 |
| 动态小时评估 375d6430e6bc | 5 * * * * | — | ok（今日 04:05） | 今日 05:05 |
| 点子到期清理 42da519d8dd6 | 15 3 * * * | — | ok（今日 03:15） | 明日 03:15 |
| 目标周报 6e815bb44097 | 0 8 * * 1 | — | ok（11-23 08:00） | 11-30 08:00 |
| 记忆日结 …4c01 | 40 23 * * * | deepseek-flash＋custom:ailey ✓ | ok | 今日 23:40（钉版后第一次定时实跑） |
| 记忆周体检 …4c02 | 30 10 * * 0 | deepseek-flash＋custom:ailey ✓ | ok | 11-29（周日）10:30 |
| 目标进展日结提炼 …4c03 | 50 23 * * * | 未钉 | **error**（11-24 23:50，403） | 今日 23:50（修复后首跑，见 M3） |
07:45 回读作业覆盖评估：见 L3（在册且 enabled；基线数字过时＋不覆盖 4c03）。

## 第 178 条 OB-I2 备查项 —— 结论：服务端可关账（零痕迹、零依赖），做不做属 App 产品线

- 备查内容（总表第 178 条原文＋2026-11-23 §391 注记＋openbot-hermes-deep-study-20261119.md:114 出处）：第 178 条本体（OB-U6 首启免费兜底、OB-I3 失败常驻）已随 0.50.99 发货并于 2026-11-24 随验收批关账；唯 **OB-I2 动作音效**被明确切出——「备查登记不落码」，等触感体系稳定后再议。OB-I2 指：参考 OpenBot 的 cuelume 操作音效（有主题、默认关、用户开启才响）给 OneDay 加一条与触感平行的音效通道，定性为低优先。
- 服务端痕迹实查：**零**。data.json 全文 grep sound/cue 无命中、meta 无相关键、config.yaml 无音效配置（唯一 sound 命中是注释里的终端 flash 说明）、§435 设置注册表目录（registry.json/settings_events.jsonl）grep sound 无命中、无相关 cron、无相关数据表。
- 结论：OB-I2 在服务端无任何已留痕迹、无需任何服务端施工或清理，**就服务端而言本项可直接关账**；其本体是纯 App 端功能备查（音效资源与开关都在客户端），将来是否立项由产品线（App 线）在触感体系稳定后决定，不占服务端队列。

## 未覆盖／口径说明
- 云安全组规则本体在腾讯云控制台侧，机内不可见；公网结论以 Mac 外部实测代偿，个别端口（80/443/888）未逐一外部复测（nginx 站点面素有公网服务事实）。
- mihomo secret、new-api 与宝塔口令的强度未验（只读纪律＋不读凭据值）；H1/M2 的风险定级含此不确定性。
- hermes cron CLI 交叉查因 SSH 隧道中途断开未完成；jobs.json 与 executions.db 两源已互证。
