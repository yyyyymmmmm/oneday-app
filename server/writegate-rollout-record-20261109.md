# write-gate 上线记录（2026-11-09）

授权：用户 2026-11-09 11:26 拍板「两个一起开，桥同日上线」（覆盖方案 §1 的分步建议，两键同日开）。
施工依据：`write-approval-bridge-plan.md`。目标机 118.24.41.52，hermes 容器（v0.23.0）未重启、定义未改。

## 施工前红线检查
- 内存：施工前 used 3311/7725 MB ≈ 43%；施工后 3416/7725 ≈ 44%。全程远低于 80%。
- 除 hermes 本体配置两键与新增 sidecar 外，其余业务容器未动。

## 源码复核（方案 §0 待核四点，容器内直读 v0.23.0）
- `handle_pending_subcommand(subsystem, args, *, memory_store=None, set_mode_fn=None) -> Optional[str]` — 与方案假设一致；gateway 自身即以 `memory_store=tools.memory_tool.load_on_disk_store()` 调用，桥照此办理（优于方案引 Ekko 的 MemoryStore 口径）。
- memory payload action 枚举：`add / replace / remove / patch / batch`；payload 字段 action/target(memory|user)/content/old_text/matched_entry/operations。
- skills action 枚举：`create / edit / patch / write_file / remove_file / delete / batch`；本体自带 `wa.skill_pending_diff(record)` 产 diff，桥直接复用。
- **origin 实测值域**：API 工具通道实测为 `assistant_tool`（源码 docstring 只写 foreground/background_review，实际取值域更宽）——OneDay 侧 origin 译表须按实测扩，不能只按二值做。
- record：id=8 位 hex、created_at=epoch 秒、summary 上游生成、payload 原样。
- 配置生效：`write_approval_enabled` 每次现读 load_config，改键后新进程即读到 True；运行中 gateway 经真实写入落 pending 实证生效，未重启 hermes。

## 基线与变更（回滚锚点）
| 项 | 变更前 | 变更后 |
|---|---|---|
| data/config.yaml md5 | a298d8a157a29038913714a7ace075d6 | c5b99d9a58acab6c7d136cd4d2de121c |
| config diff | — | 仅两行新增：memory 段与 skills 段各加 `write_approval: true`（1064/1230 行） |
| 备份 | data/config.yaml.bak-20261109-writegate（md5 同基线）；docker-compose.yml.bak-20261109-writegate；nginx conf 的 .bak-20261109-writegate | 基线清单：服务器项目目录 writegate-baseline-20261109/{skills,memories}-manifest.md5 |
| 新增 | — | sidecar 容器 write-gate-bridge（同镜像 v0.23.0，entrypoint 直跑桥脚本，127.0.0.1:8643，mem_limit 512m）；./write_gate_bridge.py（只读挂载）；./write-gate.env（0600，桥单独 Bearer 钥，值只存 credentials.txt 的 write_gate_key 与此 env 文件）；nginx 新增 location /api/write-gate/ → proxy_pass http://127.0.0.1:8643/;（带尾斜杠剥前缀） |

注意：本地 hermes-deploy 的 docker-compose.yml 副本已同步服务段（env_file 引用、不含钥值）；write-gate.env 未在本地留副本，迁移/重建时按 credentials.txt 的 write_gate_key 重新生成。

## 端到端验收证据（真链路：API 对话 → 本体闸门 staged → 桥审批 → 落盘/不落盘）
测试写入经 8642 API 真实对话触发（agent 自行调 memory/skill_manage 工具），4 条：
| 记录 | 子系统 | 裁决 | 结果证据 |
|---|---|---|---|
| cc026314（标记 …-A） | memory | approve | 桥回 success=true / "Approved 1 memory write(s)."；MEMORY.md 出现标记 A；此前 staged 阶段 MEMORY.md md5 保持基线 334f86bd… 未被直写 |
| ef156a52（writegate-test-skill） | skills | approve | success=true；data/skills/writegate-test-skill/SKILL.md 真实生成；桥 detail 的 review.diff 为本体 batch diff 渲染全文 |
| 83f57dfc（标记 …-B） | memory | reject | success=true；MEMORY.md 中 B 计数为 0（未落盘） |
| bae986b6（writegate-test-skill-b） | skills | reject | success=true；技能目录未出现 -b |

- 桥接口：GET /status = {supported:true, gate:{memory:true, skills:true}, counts 随流程 0→4→0}；GET /pending 摘要/来源完整；GET /pending/{sub}/{id} record+review 一次返回；无钥/错钥 401；非法 id 400；公网 https://hermes.example.com/api/write-gate/status 同验通过。
- 已决日志 data/write-gate/decisions.jsonl：4 行（2 approved + 2 rejected），仅元数据（id/subsystem/action/summary/origin/created_at/decided_at/decision），无 payload/内容。样本行结构：{"id":"cc026314","subsystem":"memory","action":"batch","origin":"assistant_tool","decision":"approved", ...}。此 4 行为验收审计痕迹，保留不删。
- 测试落盘清理：标记 A 条目已从 MEMORY.md 精确删除，MEMORY.md md5 回到基线 334f86bdfe8c30e5afe180bbcb2b034c（字节级一致，含无尾换行细节）；USER.md 未动（4d39d72f…）；测试技能目录已删。skills 内容文件与基线逐个 md5 一致；仅系统自有运行账本有正常 churn（新增 .curator_ledger.jsonl、.locks/ 两个空锁文件、.usage.json 计数更新），非技能内容变更，未回滚（删活锁文件风险更高）。
- 影响面观察：验收全程 5 轮 API 对话回复正常（含一条纯问答），普通聊天/工具链无异常；agent 回复已能自述「写入被暂存待审批」——即方案 §5 预告的行为变化已生效：此后记忆/技能写入先挂起、批前不生效。

## P7 记忆条目端点（2026-11-09 追加上线）

依据冻结契约 `~/workspace/oneday-design-review/memory-bridge-contract-20261109.md`（§2 端点/字段、§2.4 复验清单、§4 对账项）。write-gate 桥新增路由组，仅重启 write-gate-bridge 本体，hermes 本体与其余容器零接触；施工前内存 49.4%、施工后 48.7%，全程远离 80% 红线。

### 实现要点（同源同路实证）
- **读**：`GET /memories`、`GET /memories/{id}` 经 `tools.memory_tool.load_on_disk_store()` 解析（与裁决侧加载同一 store）。id＝`mem_`＋sha256(条目原文) 前 16 位、digest＝sha256 全量、updatedAt＝所在文件 mtime（文件级口径、契约 §2.2）；两条原文相同条目共享 id、操作命中第一条（与上游按原文匹配语义一致）。排序 memory 在前、user 在后、各按文件内序。
- **写（唯一发起面）**：`POST /memories/propose` → 校验（operation/target 400、memory 闸门未开 409「记忆写入审批未启用，暂时不能提交」、content 空 400、entryId 不存在 404、baseDigest 不符 409「这条记忆已经变了，请刷新后重新编辑」）→ 暂存走 **`tools.write_approval.stage_write` 本体内部**（与 memory 工具同一函数），`origin` 固定 `"oneday_app"`（上游 stage_write 的 origin 为自由字符串参数，无需自有映射表，契约 §4 对账项就此关闭）。payload 与工具同形：`{action: add|replace|remove, target, content, old_text}` 四键恒在（不适用者为 null）；update/delete 暂存前照工具 `_pin_matched_entries` 口径经 `store.resolve_entry()` 钉 `matched_entry`；summary 照上游 `_STORE_ACTIONS` 文案＋`f"{summary}: {detail[:120]}"` 拼法（如 `add to memory: <content 前 120 字>`）。暂存后以 `get_pending` 回读确认落盘才回 201 `{pendingId, operation, target}`。桥从不直写记忆文件。

### 基线与备份（回滚锚点）
| 项 | 动手前 md5 | 备注 |
|---|---|---|
| write_gate_bridge.py | 58603b3eda34d452023b9fa505781c91 | 变更后 54032e5d724d40fd8c814c054b51d37e（本地原件与服务器双验一致） |
| data/write-gate/decisions.jsonl | 969fdb2c56d00b43e5048d61673cbaa9（4 行） | 验收后 8 行（新增 4 条 P7TEST 审计痕，沿首轮验收惯例保留不删） |
| data/memories/MEMORY.md | 334f86bdfe8c30e5afe180bbcb2b034c | 验收后逐字一致（同值） |
| data/memories/USER.md | 4d39d72f58a96cd7d093f87c47e6ccd3 | 全程未动 |

备份（服务器项目目录内）：`write_gate_bridge.py.bak-20261109-memapi`、`data/write-gate/decisions.jsonl.bak-20261109-memapi`、`data/memories/MEMORY.md.bak-20261109-memapi`、`data/memories/USER.md.bak-20261109-memapi`。

### 验收证据（契约 §2.4 全链，本机 8643＋公网 /api/write-gate 双验，38/38 PASS）
- 桩环境预演（本地 stub 同形模块）33/33 先行通过再上生产。
- 基线：/status gate{memory,skills}=true counts 0/0、/pending 空、/decisions 4 条；/memories 部署前 404。
- 401 双验：本机与公网各测无钥/错钥（GET /memories 与 POST propose）全 401。
- GET /memories 实测 2 条（memory：R1TEST 暗号条；user：数字条）；详情自算 sha256 与桥返回 id/digest 逐字对账一致；未知 id 404。
- propose 新建（P7TEST-20261109…）→ /pending 出现 pendingId `083a1a78`，origin=`oneday_app`、summary 与 payload 形状与工具暂存一致；暂存期间 MEMORY.md md5 不变（未直写实证）→ approve（回 "Approved 1 memory write(s)."）→ GET /memories 出现该条且 id 按 sha256 口径对账。
- propose 修改：错误 baseDigest 先验 409；正确 digest → pending `9a7d09a1` payload 为 replace＋matched_entry 已钉 → approve → 新 digest 在、旧 digest 消。
- propose 删除 → pending `47702ad3` → approve → 条目消失、列表回 2 条。
- propose 后 reject（`ea9727d7`）→ 条目未落盘、/decisions 有 decision=rejected 且 origin=oneday_app 记录。
- 回归：/status counts 回 0/0、/pending 回空、/decisions 总数＝基线 4＋验收 4；收尾两记忆文件 md5 与基线逐字一致、P7TEST 残留 0、pending 目录空。

### 回滚（仅本节端点）
①项目目录 `cp write_gate_bridge.py.bak-20261109-memapi write_gate_bridge.py`（原地覆盖保 inode）→ `docker compose restart write-gate-bridge`；②验 /memories 回 404、/status 与 /pending 正常；③如需连验收审计痕一并回退，再还原 decisions.jsonl 备份（注意：还原将抹掉回滚点之后所有裁决记录，先确认无真实裁决发生）；④记忆文件无需回滚（验收后已逐字回基线，如异常按对应 .bak 复原并 md5 对账）。

## 回滚一键步骤（复述方案 §4）
A. 关闸：①先经桥或命令面逐条清完 pending（approve/reject，不许带未决记录关闸）；②`hermes config set memory.write_approval false`＋`skills.write_approval false`，或整文件还原 config.yaml.bak-20261109-writegate 并 md5 对账回 a298d8a1…；③发一条测试记忆验直落 MEMORY.md 且不产生 pending。
B. 撤桥：①nginx 删 /api/write-gate/ location（或还原 conf 备份）→ nginx -t && reload，公网验该路径回 404/兜底；②项目目录 `docker compose stop write-gate-bridge && docker compose rm write-gate-bridge`，compose 删服务段（或还原 compose 备份），删 write_gate_bridge.py 与 write-gate.env，ss 验 8643 无监听；③decisions.jsonl 先归档再议删；④终态核对 hermes 容器、config md5 与一条普通聊天。
