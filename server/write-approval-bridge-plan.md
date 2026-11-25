# Hermes write-approval 启用＋HTTP 桥施工方案（OneDay 审核段数据源）

> 状态：**方案稿，未执行**。本文只做设计与步骤定义；启用闸门、部署桥、改 nginx 均属生产变更，须用户单独授权后另行施工。
> 产出时间：2026-11-09。对象：118.24.41.52 容器 `hermes`（nousresearch/hermes-agent **v0.23.0**，`gateway run`，HERMES_HOME＝容器内 `/opt/data`，宿主机 compose `./data` 卷）。
> 目标：启用 Hermes 本体 write-approval 写入闸门（记忆＋技能写入先暂存待批），并给 OneDay 枢纽页「审核记录」段补一条 HTTP 桥：pending 列表／详情（diff)／批准／驳回，对齐已定稿的审核卡形态（一卡一条：人话摘要＋来源＋diff 入口＋批准/驳回；一期只上待批卡，历史行等已决记录接口）。

## 0. 证据分级（先说清哪些是实读、哪些待施工复核）

| 结论 | 出处 | 级别 |
|---|---|---|
| 闸门开关在 active profile 的 `config.yaml`:`memory.write_approval`／`skills.write_approval`，默认 `false`；等价 CLI `hermes config set memory.write_approval true` 等 | Ekko 随仓文档 `~/workspace/ekko-studio/docs/hermes-write-gate.md`；上游 issue #28762 sweeper 证据（`hermes_cli/config.py` 定义 `skills.write_approval`) | 文档＋上游证据 |
| pending 记录落 `<HERMES_HOME>/pending/memory/*.json`、`<HERMES_HOME>/pending/skills/*.json`，字段含 id/subsystem/action/summary/origin/created_at/replay payload | 同上 Ekko 文档；Ekko 服务端 `normalizeRecord` 实读 | 文档＋代码实读（Ekko 侧） |
| approve＝重放 staged payload 后删记录；reject＝只删记录；命令面 `/memory pending|approve|reject`、`/skills pending|diff|approve|reject` | Ekko 文档；上游 `hermes_cli/cli_commands_mixin.py` 接线证据 | 文档＋上游证据 |
| 桥接可同机 exec Hermes 自己的 Python：`from tools import write_approval as wa`＋`from hermes_cli.write_approval_commands import handle_pending_subcommand`，以 `HERMES_HOME=<profile dir>` 调用 `wa.get_pending(wa.MEMORY/wa.SKILLS, id)` 与 `handle_pending_subcommand(subsystem, [action, id], memory_store=...)` | Ekko `packages/server/src/modules/hermes/services/write-gate/write-gate.ts`（PYTHON_HELPER 全文实读） | 代码实读 |
| 生产容器内两文件在位、`<HERMES_HOME>/pending` 目录不存在（从未启用）、HTTP 层（8642/9119）无 write-gate 接口 | 主线 2026-11-09 实查（见对话记录与 `phase3-hub-spec.md` §3.2) | 生产实查 |
| 本机 nginx 现状：`/v1/`→8642、`/health`→8642、`/`→9119(Dashboard)，**无 `/api/write-gate` 路由**；8642/9119 均只绑 127.0.0.1 | `~/workspace/hermes-deploy/hermes.example.com.conf`、`docker-compose.yml` 实读 | 配置实读 |

**待施工第一步复核项（本方案未直读 v0.23.0 镜像内源码）**:`tools/write_approval.py` 中 config 解析与 gate 决策函数的确切签名、`handle_pending_subcommand` 的参数与返回、memory 子系统 payload 的 action 枚举（skills 侧 action 枚举已由 Ekko helper 实读：`create/edit/patch/write_file/remove_file/delete`)、origin 字段的取值集合。施工时先在容器内只读打印这四个点，与本文假设对账不符则先改方案再动手。

## 1. 启用闸门：确切步骤与配置点

配置点只有一个：**active profile 的 `config.yaml`**（本机单默认 profile ⇒ 容器内 `/opt/data/config.yaml`，宿主机即 hermes-deploy 的 `./data/config.yaml`)。

```yaml
memory:
  write_approval: true
skills:
  write_approval: true
```

等价 CLI（容器内执行）：

```bash
hermes config set memory.write_approval true
hermes config set skills.write_approval true
```

施工步骤（授权后执行，本方案不执行）:

1. **基线备份**：备份 `data/config.yaml` 为 `config.yaml.bak-<日期>-writegate` 并记 md5（与历次口径一致，如 gateway 切换时的 bak)；确认 `data/pending/` 不存在并记录；记录 `memories/MEMORY.md`、`memories/USER.md` 与 skills 目录的现状快照（文件清单＋md5）作回滚对账面。
2. **分步开启（推荐）**：先只开 `skills.write_approval`（技能写入低频、体感影响小），观察数日后再开 `memory.write_approval`（高频、直接影响跨会话记忆连续性，见 §5）。两步不要同日叠加，出问题无法归因。
3. **生效方式**：据上游代码证据，config.yaml 走 mtime 键的缓存重载，改文件后可望在运行中生效；但不预设——改后立刻用一条验证写入实测（第 4 步），未落 pending 则走一次 gateway 进程重启（Dashboard `POST /api/gateway/restart?interrupt=true`，主线已有先例）再测。
4. **验证写入（每开一个子系统各做一次）**：在一次性测试会话里让 agent 记一条无害事实（记忆）／建一个一次性测试技能（技能），验收三点:①`pending/{memory,skills}/` 下出现 JSON 记录；②`MEMORY.md`/`USER.md`/skills 目录**未**被改动（快照对账）；③经容器内命令面 approve 一条 → 内容落盘且记录消失；reject 另一条 → 内容不落盘且记录消失。验收完清掉测试产物。
5. **与桥同日上线**：闸门开启而桥未通的窗口期，pending 只能靠进容器用命令面处理（见 §5 风险 3)。排期上桥的部署必须 ≤ 闸门开启日，理想顺序：桥先部署并以手工造的 pending 记录（验证写入产生）打通全链，再正式开闸门。

不需要改的：Hermes 镜像、compose 服务定义（桥是独立服务，见 §2)、New API 网关、OneDay 客户端的服务器地址与现有 API_SERVER_KEY 通道。

## 2. HTTP 桥形态选型

### 2.1 候选与裁决

| 形态 | 说明 | 裁决 |
|---|---|---|
| **A. 独立小服务（同镜像 sidecar 容器）** | 新起一个小容器，镜像与 hermes 同为 `nousresearch/hermes-agent:v0.23.0`，只读挂载同一 `./data` 卷中的必要部分＋以 `HERMES_HOME=/opt/data` 运行一个极小 HTTP 服务；list 直接读 pending JSON 文件，diff/approve/reject 在容器内 exec 本镜像的 Python 调 `tools.write_approval`／`handle_pending_subcommand`（Ekko 模式的容器内版本） | **推荐** |
| B. 宿主机守护进程＋`docker exec hermes python3 -c …` | 宿主机小服务逐请求 exec 进 hermes 容器跑 helper（Ekko 原版是同机直跑，此为跨容器变体） | 备选。少一个容器，但把 docker exec 权限交给一个 HTTP 服务，权限面更大；每次调用冷启 Python＋import，延迟秒级；hermes 容器重启/换名即断 |
| C. 往 hermes 容器里塞常驻进程 | 改 compose command/entrypoint 在主容器内多跑一个服务 | 否决。动正常业务容器的启动定义，违反既有运维口径（正常业务容器不动），且镜像升级即丢 |
| D. 复用现有网关转发（New API／Dashboard) | New API 是 LLM 代理、不承载任意 HTTP API;Dashboard 9119 无 write-gate 路由，补路由等于改上游代码 | 否决。无现成通道可"转发"——nginx 新增 location 指向桥服务才是这里的"转发"，属 A 的一部分 |
| E. 借道聊天发斜杠命令（`/memory pending` 文本） | 让 OneDay 发命令文本给 agent 读结果 | **明令否决**。主线已实证：API server 路径不分发斜杠命令，文本会被 agent 当任务执行（2026-11-09 /model 文本事故，72 次失控调用）；且把审批权交给模型会话本身，安全上不成立 |

### 2.2 推荐形态（A）细化

- **部署单元**：compose 新增独立服务 `write-gate-bridge`（与 hermes 同文件或独立 compose 文件，互不改动对方定义），镜像钉 `v0.23.0` 与主容器同版（桥 import 的是内部模块，同版是对齐前提；Hermes 升级时桥必须同步升版并重跑自检，见 §5 风险 4)。
- **运行方式**：桥服务本体建议 Python 标准库 `http.server` 或已在镜像内的轻框架实现单个文件脚本（脚本随部署文件放 hermes-deploy 目录、只读挂进容器），不给镜像加依赖。工作分工照 Ekko:
  - list：直接读文件系统（pending 目录 JSON)，不起 Python 子进程，快且与上游"读不到的记录跳过"行为一致；
  - diff/approve/reject:exec 本容器 Python 跑一段固定的 helper（逻辑移植 Ekko PYTHON_HELPER：skills 用 `tools.skill_manager_tool._find_skill`＋difflib 生成 unified diff;memory 的 diff＝payload JSON 本身；approve/reject 走 `handle_pending_subcommand`，memory approve 前先 `MemoryStore().load_from_disk()`),HERMES_HOME 指向 profile 目录（默认 profile＝`/opt/data`)。
  - **串行化**:approve/reject 全局单队列（一把进程内锁即可），照 Ekko 按 profile 串行的做法，防并发重放同一记录。
  - **启动自检**（照 Ekko `isWriteGateSupported`):import `tools.write_approval` 与 `hermes_cli.write_approval_commands` 并确认两文件存在，失败则 `/status` 报 `supported:false`、写操作一律 409 fail-closed，不许带病上线。
- **端口与反代**：容器/宿主机只绑 `127.0.0.1:8643`（8642 的邻号，施工时以 `ss -ltnp` 实查未占用为准）。nginx 在 `hermes.example.com` 现有 server 块新增一段（置于 `location /` 之前）:

  ```nginx
  location /api/write-gate/ {
      proxy_pass http://127.0.0.1:8643;
      proxy_http_version 1.1;
      proxy_set_header Host $host;
      proxy_set_header X-Real-IP $remote_addr;
      proxy_set_header Authorization $http_authorization;
      proxy_read_timeout 60s;
  }
  ```

  对外只暴露这一个前缀；桥本身不开任何公网监听。
- **鉴权**：`Authorization: Bearer <WRITE_GATE_KEY>`，**给桥单独发一把密钥**（随机 32B hex，存桥容器环境变量＋OneDay 凭据同一保管通道；不写进本文与代码仓库）。不直接复用 API_SERVER_KEY 的理由：那把钥匙现在只值"聊天"，桥接通后它同时值"改 agent 长期记忆与技能"，单独一把可独立轮换、泄露时只吊销审批权。桥内做常量时间比较；无/错钥匙一律 401 且不区分原因。nginx 层不做第二重校验（避免两处口径漂移），但桥的访问日志只记方法/路径/状态码，**绝不记 payload 与 diff 内容**（含个人记忆数据）。

## 3. 接口契约（对齐 OneDay 审核卡）

Base:`https://hermes.example.com/api/write-gate`。全部响应 JSON;`subsystem` 只许 `memory|skills`;`id` 必须匹配 `^[A-Za-z0-9_-]{1,80}$`（Ekko 同款校验），不匹配 400。一期只支持默认 profile（OneDay 用的就是它），不开放 profile 参数。

| # | 方法与路径 | 入参 | 出参（关键字段） | 备注 |
|---|---|---|---|---|
| 1 | `GET /status` | — | `{supported:bool, gate:{memory:bool, skills:bool}, counts:{memory:int, skills:int}}` | gate 状态由桥读 config.yaml 两键得出；供 OneDay 渲染诚实状态卡三态：未启用／已启用但桥异常／正常（对齐枢纽页规格 #23) |
| 2 | `GET /pending` | — | `{records:[Record], counts:{memory, skills}, supported:bool}` | 按 created_at 升序（与 Ekko 一致，卡片先进先审） |
| 3 | `GET /pending/{subsystem}/{id}` | 路径参数 | `{record:Record, review:Review}` | 详情与 diff 一次返回（Ekko 是 `{diff, review}` 合并返回，本桥把 record 一并带上省一次往返） |
| 4 | `POST /pending/{subsystem}/{id}/approve` | 空 body | `{success:bool, output:string, decision:"approved"}` | 副作用：上游重放 payload 落盘＋删 pending 记录；桥追加已决日志（见下） |
| 5 | `POST /pending/{subsystem}/{id}/reject` | 空 body | `{success:bool, output:string, decision:"rejected"}` | 副作用：删 pending 记录、不落盘；同样记已决日志 |
| 6 | `GET /decisions?limit=50`（二期） | query limit≤200 | `{decisions:[{id, subsystem, action, summary, origin, created_at, decided_at, decision}]}` | 历史行数据源；**只含元数据、不含内容**。一期可不实现接口，但桥从上线第一天就必须写这份日志，否则历史永久丢失（上游 approve/reject 后记录即删，无处可查） |

**Record 结构**（源头是 pending JSON，桥只做规范化，不发明字段）:

```json
{
  "id": "string",
  "subsystem": "memory | skills",
  "action": "string（上游原值，如 skills 的 create/edit/patch/write_file/remove_file/delete）",
  "summary": "string（上游生成的摘要，直接用作审核卡标题的人话摘要）",
  "origin": "string（上游原值，来源标识）",
  "created_at": "ISO8601（上游为 epoch 秒数值，桥转 ISO；上游缺失时以文件 mtime 兜底并标 created_at_approx:true）",
  "payload": { "…": "上游 replay payload 原样（列表可省略，详情必带）" }
}
```

**Review 结构**（与 Ekko `PendingWriteReview` 同构，OneDay 可直接按此渲染 diff 页）:

```json
{
  "subsystem": "memory | skills",
  "targetLabel": "string（skills=目标文件名如 SKILL.md；memory=\"memory\"）",
  "language": "string（diff 高亮语言，memory 为 json）",
  "current": "string（现行内容；memory 恒为空串）",
  "proposed": "string（拟写入内容；memory 为 payload 的 JSON 文本）",
  "diff": "string（unified diff；memory 时等于 payload JSON 文本，与 Ekko 行为一致）",
  "requestedOldString": "string?（patch 定位失败时回传原 old_string）",
  "notes": [{ "type": "patchOldStringMissing | currentReadFailed | deleteSkill | removeFile", "targetLabel": "?", "skillName": "?" }]
}
```

**审核卡字段映射**（OneDay 枢纽页规格 §3.2 已定）:

| 卡片元素 | 来源 |
|---|---|
| 人话摘要（卡标题） | `record.summary`（上游生成）；客户端按既有红线再过一层翻译/兜底（summary 为空时以 action＋targetLabel 拼兜底文案，不许直出 id/JSON) |
| 来源 | `record.origin` 经客户端 ServerLabels 同级映射表译成人话（如后台自检/对话中写入——确切映射表待 origin 枚举复核后定，见 §0) |
| 时间 | `record.created_at` 相对时间显示 |
| diff 入口 | 跳详情页拉接口 3 的 `review.diff`（skills 看 unified diff;memory 看 payload 条目） |
| 批准／驳回 | 接口 4/5;`success=false` 或 404（记录已被别处处理）时客户端刷新列表，不重试硬打 |

**错误契约**（照 Ekko controller 的状态码口径）:400＝subsystem/id 非法；401＝鉴权失败；404＝该 pending 不存在（已决/已删）；409＝闸门模块不受支持（自检失败）或目标状态冲突；500＝其余，body `{error:"…"}`。approve 的成功判定照 Ekko：处理前记录存在、处理后记录不存在，才算 `success:true`——防止上游静默失败被报成成功。

**已决日志**:桥在每次 approve/reject 后向 `data/write-gate/decisions.jsonl` 追加一行元数据（字段同接口 6，**不含 payload/diff/内容**）。文件在我们自己的 data 卷里，不进 pending 目录、不干扰上游。这是历史行（二期）唯一的数据来源，必须一期就写。

## 4. 回滚基线

回滚分两半，可独立执行；执行回滚前先冻结：通知 OneDay 侧审核段回落诚实状态卡（桥下线即自动呈现"通道未接通"，无需改 App）。

**A. 关闸门（恢复写入直落）**

1. **先清存量 pending**（关键顺序，错了会留悬案）：逐条处理 `pending/memory`、`pending/skills` 下所有记录——要的 approve 落盘、不要的 reject 删记录；把每条的 id/action/裁决记进施工记录。**绝不允许带着未决记录直接关闸门**：关闸门后新写入直落、旧记录永不自动重放，且日后重开闸门时它们会原样复活成"陈年待批"。
2. 两键改回 `false`（或整文件还原 `config.yaml.bak-<日期>-writegate` 并 md5 对账）；按 §1 第 3 步同法验证生效（发一条测试记忆，确认直落 `MEMORY.md` 且不产生 pending）。
3. 对账:§1 第 1 步的快照与现状 diff，列明闸门期所有**已批准落盘**的变更清单——这部分是真实生效的记忆/技能变更，回滚配置不会撤销它们；如需连内容一并还原，按清单逐条人工回退（这也是为什么已决日志与施工记录必须留档）。

**B. 撤桥（恢复无桥状态）**

1. nginx 删除 `/api/write-gate/` location 并 reload；`curl` 外网验该路径回到 404/9119 兜底行为。
2. 停并删除 `write-gate-bridge` 容器与 compose 中对应服务段；删除桥脚本文件与 WRITE_GATE_KEY 环境注入；宿主机 `ss -ltnp` 验 8643 无监听。
3. `data/write-gate/decisions.jsonl` 先拷贝归档到 hermes-deploy 目录留存，再决定是否删原文件（审计痕迹，不默认销毁）。
4. 终态核对：hermes 主容器定义、config、镜像与启用前基线一致（compose 文件 diff、config md5、容器 `docker ps` 状态），OneDay 其余功能（会话/模型锁等 8642/9119 通道）抽测一条聊天确认无恙。

## 5. 风险与对现有 Hermes 使用的影响面

**最大风险（行为面，不是技术面）：开闸门＝改变 Hermes 的记忆方式本身。** 具体影响：

1. **记忆不再即时生效（memory 子系统，高频）**：闸门语义按上游文档——前台交互 CLI 的记忆写入可走内联确认，但 **Gateway/Web UI/脚本/后台自检（background review）通道的记忆写入一律 staged**。本机 Hermes 的全部真实使用面（OneDay API、Dashboard、定时与后台自我改进）都在 staged 范围内。后果链：agent 在对话里"记住"的信息在用户批准前**不进** `MEMORY.md`/`USER.md`，后续会话读不到 → 用户体感"它答应记了却没记住"、跨会话连续性在审批间隔内断裂；依赖记忆的个性化（偏好、进行中的事）在批准前全部落空。
2. **技能写入永远 staged（skills 子系统）**：含前台通道在内一律待批（上游理由：技能变更太大不适合内联审）。agent 自创/改的技能在批准前不存在于技能目录，**同一会话后续轮次想调用刚写的技能会扑空**；后台自检产出的技能修订同样挂起，积压久了会出现"同一技能多条 pending 修订互相覆盖前提"的陈旧重放问题（approve 时 `old_string` 可能已不匹配现行文件——桥的 notes 里 `patchOldStringMissing` 就是为此设的，客户端必须把这类提示显性呈给审批人，不许静默按成功处理）。
3. **只进不出窗口**：闸门已开、桥未通/桥故障期间，写入只累积无处审（兜底只有进容器跑命令面）。这就是 §1 第 5 步要求桥与闸门同日上线的原因；桥的 `/status` 异常必须能在 OneDay 审核段显性呈现（诚实状态卡），不许假装无待批。
4. **积压与重复**：长期无人审批时 pending 会堆积；agent 不知道写入被挂起（它收到的是"已暂存"回执），后续可能重复发起同类写入，产生近似重复记录，审批人要逐条辨认。运营上需要一个清账节奏（建议：待批数进指挥中心/枢纽页状态行，有积压就提醒），否则闸门会在几周内退化成"没人看的收件箱"，最终被迫整批 reject——等于这段时间 agent 的学习成果全丢。
5. **版本耦合**：桥 import 的是上游**内部模块**（`tools.write_approval`、`hermes_cli.write_approval_commands.handle_pending_subcommand`)，非公开 API;Hermes 发版极快（钉版 v0.23.0 期间无事），**任何一次 hermes 镜像升级都必须把桥列为回归项**：先跑自检（import＋两文件在位），再用验证写入全链复测，过后才算升级完成。自检不过时桥 fail-closed 报 409，不会误批。
6. **权限升级**：桥的批准动作等价于"替 agent 改长期记忆与改技能（可执行指令集）"，是本机最高价值写通道之一。单钥匙＋仅 127.0.0.1＋nginx 单前缀暴露是底线；OneDay 侧这把钥匙与聊天 API_SERVER_KEY 分开保管、分开轮换。diff/详情里含用户记忆原文，只走既有 HTTPS，不进任何日志与第三方通道。
7. **不影响面（写清以免误虑）**：闸门只管 memory/skills 两个存储，**不管**普通文件编辑、终端命令、浏览器与 MCP 工具调用（那些是另一套 dangerous-command approval，与本方案无关，也不因开本闸门变安全）；会话、模型锁、定时任务等现有链路行为不变；config 两键改回 false 即完全恢复旧行为（存量 pending 的处理见 §4A，不在此列）。

## 6. 施工顺序建议（一页版）

1. 容器内只读复核 §0 待核四点 → 与本文对账。
2. 写桥（单文件脚本＋compose 服务段＋nginx location 草案），全部先落在部署文件层，**不动生产**。
3. 授权后：部署桥（不开闸门）→ 手工在 pending 目录放一条仿真记录（或用 CLI 造一条）→ curl 全链验 list/diff/approve/reject＋已决日志落行 → 撤仿真记录。
4. 备份基线 → 先开 skills 闸门 → 验证写入全链（§1 第 4 步）→ 观察数日 → 再开 memory 闸门 → 同样验证。
5. OneDay 审核段接真实数据（桥未就绪前保持诚实状态卡的既有施工不变）。
