# 僵尸 run 结算记录（2026-11-25）

- 批准：用户 2026-11-25 04:50 亲口批准（「结算掉那条僵尸会话，解冻那个旁会话」）。
- 对象：run_136d1c78bc174c47a932940338eac263 ／ admission 413a9f1c364d486ea548c41d44630159（seq 1521，会话 oneday-side-2b577a29-3c26-4827-a0a2-52bc485d4984）。
- 定性依据：stop-button-server-rca-20261125.md（owner_epoch 78 ＜ 当时 runtime_epoch 82、同会话 worker_executions＝0、执行体随 03:08 部署重启死亡）。
- 基线：zombie-settle-baseline-20261125.txt（结算前全状态快照，结算前服务器内存约 50%、health ok）。

## 走的路径（网关自有正规路径，未改库、未重放）

`POST /v1/runs/{run_id}/resolve-unknown`（网关 api_server 既有端点，与 stop 同权限），请求体按端点契约恰为
`{"admission_id": "413a9f1c364d486ea548c41d44630159", "execution_generation": 1}`，
在容器内以网关自身 API 钥鉴权调用（钥未出容器、未落任何记录）。
内部链：`resolve_unknown_run` → `authority.resolve_unknown` → `resolve_unknown_session_input`，在 fenced 事务内 settle。

**回执（HTTP 200）**：
```json
{"run_id": "run_136d1c78bc174c47a932940338eac263", "admission_id": "413a9f1c364d486ea548c41d44630159",
 "sequence": 1521, "status": "terminal", "outcome": "interrupted", "authority_epoch": 78, "execution_generation": 1}
```

## 结算前后状态

| 面 | 结算前 | 结算后（回读实证） |
|---|---|---|
| session_admissions 行 | status=unknown、outcome=null、owner_epoch 78、generation 1 | **status=terminal、outcome=interrupted**（余字段不变） |
| 同会话 FIFO | 该 admission 独占队列头、非终态 1 条 | **非终态 0 条**（该会话仅此一条 admission，已终态）——队列已释放 |
| GET /v1/runs/{id} 投影 | status=unknown（非终态，App 永远等不到结束） | **status=cancelled（终态）**、output 空、pending_controls 空 |
| POST …/stop | 409 `unknown_execution`（150 次全同） | 409 `not_found`（已无可停的活跃 run；错误性质已变，非失联墙） |
| 网关 health | ok（0.23.0） | ok（0.23.0） |
| 三读面计数 | 目标 41／动态 34／点子 5／台账 1092 行 | **全不变**（41／34／5／1092） |

## 一处如实记录（非凑数、未手改）

runs_idempotency.db 中该 run 的 status_json 快照仍停在提交时的 `running`（updated_at 未变）。查实其机制：该快照只由**属主进程的活体状态机**（api_server_runs 的 `_set_run_status`→`update_status`）驱动更新，属主进程 pid 175 已死亡，本次走的 resolve-unknown 正规路径（与 Desktop/TUI 的 Discard 同路）不回写这份提交期快照。它只是原 POST 的防重放凭据记录，不参与 FIFO、不参与 GET 投影（投影直读 state.db admission，已终态）。**未对其做任何库级手改**——若要连这份快照也随 resolve 刷新，属网关代码改动，归 stop 修法包（RCA 修法 A）范围，不在本件。

## 回滚方法（如需）

本结算是控制面登记的终态化，不涉及执行重放，正常情况下无回滚必要。若必须回滚到结算前状态：凭基线文件 zombie-settle-baseline-20261125.txt，在维护窗口内将 state.db 该行 status 改回 `unknown`、outcome 改回 NULL 即可逐字恢复（payload、幂等行均未被本次操作触碰，无需恢复）。注意回滚会让该旁会话重新被这条失联 admission 堵住队列头。

## 边界

只处置这一条僵尸；未动任何其他 admission／run／会话状态；未往该会话发任何消息；stop 修法包（RCA 修法 A–D）不在本件范围，未实施。
