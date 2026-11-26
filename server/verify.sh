#!/usr/bin/env bash
# hermes-deploy verify.sh — 按 CAPABILITIES.md 能力注册表逐项探活（只读）
#
# 用法: 在部署机上运行: ./verify.sh [部署目录]
#   部署目录可选（默认 /srv/hermes），仅静态探针（规划路由 grep）用到。
#   写型探针（run 幂等重放等）本版一律不执行，只在输出里标注人工验收路径。
#
# 输出口径: [齐] 在位且行为/路由证据通过; [缺] 应有而未有; [规划中] 批次未到、当前缺失符合预期; [未验] 本轮条件不足未探
set -uo pipefail

DEPLOY_DIR="${1:-/srv/hermes}"
TARGET_IMAGE="nousresearch/hermes-agent:v0.23.0"
BASE="http://127.0.0.1:8642"

PASS=0; FAIL=0; PLANNED=0; UNKNOWN=0
ok()   { printf '[齐]     %s %s\n' "$1" "${2:-}"; PASS=$((PASS+1)); }
bad()  { printf '[缺]     %s %s\n' "$1" "${2:-}"; FAIL=$((FAIL+1)); }
plan() { printf '[规划中] %s %s\n' "$1" "${2:-}"; PLANNED=$((PLANNED+1)); }
unk()  { printf '[未验]   %s %s\n' "$1" "${2:-}"; UNKNOWN=$((UNKNOWN+1)); }

# 与 manifest.yaml 同步的期望哈希
declare -A WANT_SHA=(
  [api_server.py]=a493afb2dc3ab1121716ddd8dc41aec5fc72ab566b94cc6ea216895bcf7464c6
  [hermes_state_portability.py]=6a93ecc83a8b5f059978bd3f2db1d63ea8a2ec30a5790028c89ec90c5b2a1d0c
  [web_routers_sessions.py]=215cde6e95080f11a4d550cf6d85e6753c339fa096016befc0be7f1bf8c86be0
)
declare -A WANT_SHA_EXTRA=(
  [approval_projection.py]=fbebf958392225c46eb34dcc62a673949b0d68fc314537144f25902e56e2c7ff
  [grant_projection.py]=e1e29b3601f481a7792c2b71291053dd8dcd2d7da0df2773673e38273d0d41f2
  [api_server_runs.py]=79edb80b9a07f6d339609de1bad4b14d59104bd98817121a99bfd19dc7399d8a
  [crash_reports.py]=f74a7424e46bf02100a9e054882b7d1b8219e3a56859ec94482441ef5678f510
  [fileproc_gateway.py]=96654ddddebd33633c9c77c4a363545ea227b0cb1ef01e1d9c100af43ede914c
  [device_sync.py]=f2312d0caed820646a738c181b0e646c576ff22500b9c76d13f16960393bd838
  [device_gateway.py]=41ec82462c947408b2dc379b6b0e25ced9702db00d948bcdb127197588c7b06a
  [identity_gateway.py]=91ca959513e078db3dbfe2220262558b45f3a2ec8793c32f50789cf5a926578c
  [front_gateway.py]=857e88becb5e534130f0d47a7ad71a2814a244a54a42e1e9deaed8abed6df5bf
  [react_to_message_tool.py]=703164714fae87674635581a30671cb231a41926121bc6fdcf5af4432e35357e
  [self_reaction_pending.py]=972577870fb0cb0d60b4d5535324b4cba5f5f15c178760dcdc9b92f6c0ddf626
  [write_gate_gateway.py]=a0682135c7591193ed10eb340340d416a9c5de3350ada498d3077cdfb08ce58b
  [oneday_memory.py]=43dea21475b7bb24724c1787ff19f93403fba4666826b40e0828d3864a383d44
  [system_prompt.py]=7d558e89af41ee492ae85b681f9e7f4a347c728c58818c8ea76fbec776bcc05f
  [oneday_prompt.py]=bafc6c3ca7597f348b6eeec5b76153e9ad8e04dc02278695aff55f03ed766227
  [settings_registry.py]=0478458bdd5b9a2873471cbbcbb1e3efba7568fe3d01b6bda169c99b1cff78e5
  [settings_admin.py]=3057cbc2b1771d42dfd084e6ac9c5152e82be2f22c764b798d463fdf1d33f1cb
  [settings_admin_tool.py]=7d53eeae0816b8d3e751e2e6e96c2f79cb960536d112e2dba644a5a1c16f3815
  [oneday_semantic.py]=930265087b9a4ced35aacf83ca2c8f4bd1d29b6551fd692290c2b33e83c17bf1
  [skill_admission_gate.py]=e9c1ba18f93ecc1fac8056f68e75b7c98a51cdd447b3859b53f9b820037831c7
  [oneday_gateway.py]=82755461e014e89bf1ebd8d96cb68501d77edb747185d3cc3b04db4f1b17434b
  [overview_gateway.py]=0fabe764c8fe626462e7c76738518791c2e3c238cd919e21a5e39068d932bc5b
  [oneday_ledger_lib.py]=5ee8bc91d6c39ad9cc807e88d5add196ef04593bb760fa3d5739f562c04a6566
  [cron_projection.py]=0a3ef6684a29e6fccd1af4529aba22d34a65e63bdc702a7c0a8d42755f155ae6
  [api_server_oneday_routes.py]=bbe97478781282b69cc5c615d3a954b10dadeec3a94087b3b9a54586a78391ed
  [auth_tokens.py]=9291e5ca9495f8d676cc9076b368e1c7e383e4c49fb5902ff9c6bf1f9555c85a
  [push_tokens.py]=e01a5cdd1520f7a2af5d7b69c5bad4a341242f42452dd6e771693e76d68de8fe
  [push_sender.py]=ca47d28826126b9d2f848af0a063f43e963389df675208cd8aa50a4c025fc865
  [db_schema_guard.py]=040a19b476de75195e13600fdea9e11419f97c62a237d3e88af9d21bc842d05b
  [credential_vault.py]=ed95fcaf15a04abce54a68443e69d455ab3f9ba0cee3b42db4d292e2624e52f0
  [credential_vault_tool.py]=ea9f55ebda3e8802c20385c0be9541921c3f1d6e9fb024396d69c9d50d8b50eb
  [oneday_seg_automation.py]=b10453f970ffc3d1a61969462419b5162764d1f57154d6489ec705cbd861502d
  [oneday_seg_briefings.py]=f9fc273c9a0d142f57541ba1c2a5708ada333f976c1ab79a67c64236a3e77440
  [oneday_seg_cron.py]=1027673950195efdced445677ea57d009c988ac7b8e3a8cb5ef090a25e191de7
  [oneday_seg_delivery.py]=08bd159801f3b9a9ca9c2d747676117d726251ddddb8646e83527b4490ac0954
  [oneday_seg_feed.py]=b305c244437ff0e061c4a76a24a8be32e0da9831b9ebb7eaa55dd8d50956f39a
  [oneday_seg_filelibrary.py]=f6586b45029814471f3401f6514a9b740cedfa868ca08ef366e405eb1d82ae28
  [oneday_seg_goals.py]=59388a1ac78d82bc1a173d0f0b4c03d2fe95735c611079da81007f9f224aa29a
  [oneday_seg_goals_activity.py]=f5ee4f564b5182acc30f27f091ccf386f7e84e17d7a36801c7b77a3368e8efcb
  [oneday_seg_goals_facade.py]=f4237fe1b69c4febdab61db31ad6473fabdc449bde7b97181c23dd9f9a06f352
  [oneday_seg_ideas_gen.py]=7f2d33df2e80b0fa7ec4f761ad957c0892723bb8ca09781d0f2dd7bfbcfc148d
  [oneday_seg_ideas_pool.py]=762480db46114f18d8d468ee10d30233d3c585fa8e82f9049983eaa5633d3ad4
  [oneday_seg_ledger.py]=768bd29f4ff5d8c8e9408fbdc938241fa33d8cbb873551f090a100199fd5b801
  [oneday_seg_library_mcp.py]=29aaf48abbc66a13cc1aed43a8ba609ac88022b2ea82a576246cfdbbeadd3edd
  [oneday_seg_monitors.py]=fb33eb391c5382196398a02a2300a885ea9d957b0c41560f6092a528b3bc1a07
  [oneday_seg_sessions.py]=5fef89da32d675d079259f0345ed328484d3649349cca99b71eb6b5a4e57838d
  [oneday_seg_traces.py]=ebc6b07fde26e30a9827c32ca7755bd5b423938ba270f53ba9fa70d2acff0d9c
  [NotoSansSC-subset.ttf]=695c95a196eae0764aa5d4325aebaff38e5f22dfa9050e0e3930181b3a5ded6e
  [web_routers_profiles.py]=fda69d721249115ac7e8e41d699e15b8757838adb5ff18b2aa367de3e302c775
  [web_routers_ops.py]=ceac7c0dbfe627248c1aa5f9857c5a6fa21dd6ecde0f7a53390dbf6b84a45481
  [options_pending.py]=546f5f432ca4f6900b6b5577b4255ba02de3ab663fd2f78036fa07d11e45bc38
  [present_options_tool.py]=f8400d1cc3897a13eed2a7b16de72a7c46bbf392d506fc6c891e4247a9de785e
)
for k in "${!WANT_SHA_EXTRA[@]}"; do WANT_SHA[$k]="${WANT_SHA_EXTRA[$k]}"; done
declare -A CPATH=(
  [api_server.py]=/opt/hermes/gateway/platforms/api_server.py
  [approval_projection.py]=/opt/hermes/gateway/platforms/approval_projection.py
  [grant_projection.py]=/opt/hermes/gateway/platforms/grant_projection.py
  [hermes_state_portability.py]=/opt/hermes/hermes_state_portability.py
  [web_routers_sessions.py]=/opt/hermes/hermes_cli/web_routers/sessions.py
  [api_server_runs.py]=/opt/hermes/gateway/platforms/api_server_runs.py
  [crash_reports.py]=/opt/hermes/gateway/platforms/crash_reports.py
  [fileproc_gateway.py]=/opt/hermes/gateway/platforms/fileproc_gateway.py
  [device_sync.py]=/opt/hermes/gateway/platforms/device_sync.py
  [device_gateway.py]=/opt/hermes/gateway/platforms/device_gateway.py
  [identity_gateway.py]=/opt/hermes/gateway/platforms/identity_gateway.py
  [front_gateway.py]=/opt/hermes/gateway/platforms/front_gateway.py
  [react_to_message_tool.py]=/opt/hermes/tools/react_to_message_tool.py
  [self_reaction_pending.py]=/opt/hermes/gateway/platforms/self_reaction_pending.py
  [write_gate_gateway.py]=/opt/hermes/gateway/platforms/write_gate_gateway.py
  [oneday_memory.py]=/opt/hermes/gateway/platforms/oneday_memory.py
  [system_prompt.py]=/opt/hermes/agent/system_prompt.py
  [oneday_prompt.py]=/opt/hermes/agent/oneday_prompt.py
  [settings_registry.py]=/opt/hermes/gateway/platforms/settings_registry.py
  [settings_admin.py]=/opt/hermes/gateway/platforms/settings_admin.py
  [settings_admin_tool.py]=/opt/hermes/tools/settings_admin_tool.py
  [oneday_semantic.py]=/opt/hermes/gateway/platforms/oneday_semantic.py
  [skill_admission_gate.py]=/opt/hermes/tools/skill_admission_gate.py
  [oneday_gateway.py]=/opt/hermes/gateway/platforms/oneday_gateway.py
  [overview_gateway.py]=/opt/hermes/gateway/platforms/overview_gateway.py
  [oneday_ledger_lib.py]=/opt/hermes/gateway/platforms/oneday_ledger_lib.py
  [cron_projection.py]=/opt/hermes/gateway/platforms/cron_projection.py
  [api_server_oneday_routes.py]=/opt/hermes/gateway/platforms/api_server_oneday_routes.py
  [auth_tokens.py]=/opt/hermes/gateway/platforms/auth_tokens.py
  [push_tokens.py]=/opt/hermes/gateway/platforms/push_tokens.py
  [push_sender.py]=/opt/hermes/gateway/platforms/push_sender.py
  [db_schema_guard.py]=/opt/hermes/gateway/platforms/db_schema_guard.py
  [credential_vault.py]=/opt/hermes/gateway/platforms/credential_vault.py
  [credential_vault_tool.py]=/opt/hermes/tools/credential_vault_tool.py
  [oneday_seg_automation.py]=/opt/hermes/gateway/platforms/oneday_seg_automation.py
  [oneday_seg_briefings.py]=/opt/hermes/gateway/platforms/oneday_seg_briefings.py
  [oneday_seg_cron.py]=/opt/hermes/gateway/platforms/oneday_seg_cron.py
  [oneday_seg_delivery.py]=/opt/hermes/gateway/platforms/oneday_seg_delivery.py
  [oneday_seg_feed.py]=/opt/hermes/gateway/platforms/oneday_seg_feed.py
  [oneday_seg_filelibrary.py]=/opt/hermes/gateway/platforms/oneday_seg_filelibrary.py
  [oneday_seg_goals.py]=/opt/hermes/gateway/platforms/oneday_seg_goals.py
  [oneday_seg_goals_activity.py]=/opt/hermes/gateway/platforms/oneday_seg_goals_activity.py
  [oneday_seg_goals_facade.py]=/opt/hermes/gateway/platforms/oneday_seg_goals_facade.py
  [oneday_seg_ideas_gen.py]=/opt/hermes/gateway/platforms/oneday_seg_ideas_gen.py
  [oneday_seg_ideas_pool.py]=/opt/hermes/gateway/platforms/oneday_seg_ideas_pool.py
  [oneday_seg_ledger.py]=/opt/hermes/gateway/platforms/oneday_seg_ledger.py
  [oneday_seg_library_mcp.py]=/opt/hermes/gateway/platforms/oneday_seg_library_mcp.py
  [oneday_seg_monitors.py]=/opt/hermes/gateway/platforms/oneday_seg_monitors.py
  [oneday_seg_sessions.py]=/opt/hermes/gateway/platforms/oneday_seg_sessions.py
  [oneday_seg_traces.py]=/opt/hermes/gateway/platforms/oneday_seg_traces.py
  [NotoSansSC-subset.ttf]=/opt/hermes/gateway/platforms/assets/NotoSansSC-subset.ttf
  [web_routers_profiles.py]=/opt/hermes/hermes_cli/web_routers/profiles.py
  [web_routers_ops.py]=/opt/hermes/hermes_cli/web_routers/ops.py
  [options_pending.py]=/opt/hermes/gateway/platforms/options_pending.py
  [present_options_tool.py]=/opt/hermes/tools/present_options_tool.py
)

MEM_PCT=$(free | awk '/^Mem:/ {printf "%d", ($2 > 0) ? ($3 * 100 / $2) : 0}')
printf '内存使用率 %s%%（红线 80%%）\n' "$MEM_PCT"

# ---- 1. 版本 ----
IMG=$(docker inspect hermes --format '{{.Config.Image}}' 2>/dev/null || echo "")
if [ "$IMG" = "$TARGET_IMAGE" ]; then ok "hermes-version" "$IMG"; else bad "hermes-version" "实际: ${IMG:-无容器}"; fi

# ---- 2. 补丁容器内回读哈希 ----
for name in api_server.py hermes_state_portability.py web_routers_sessions.py approval_projection.py grant_projection.py api_server_runs.py crash_reports.py fileproc_gateway.py react_to_message_tool.py self_reaction_pending.py write_gate_gateway.py oneday_memory.py system_prompt.py oneday_prompt.py settings_registry.py settings_admin.py settings_admin_tool.py oneday_semantic.py skill_admission_gate.py web_routers_profiles.py web_routers_ops.py identity_gateway.py front_gateway.py oneday_ledger_lib.py cron_projection.py api_server_oneday_routes.py auth_tokens.py push_tokens.py push_sender.py db_schema_guard.py credential_vault.py credential_vault_tool.py; do
  got=$(docker exec hermes sha256sum "${CPATH[$name]}" 2>/dev/null | awk '{print $1}')
  if [ "$got" = "${WANT_SHA[$name]}" ]; then ok "patch-hash $name" "容器内回读一致"; else bad "patch-hash $name" "容器内: ${got:-读不到}"; fi
done

# ---- 3. 网关健康 ----
API_KEY=$(docker inspect hermes --format '{{range .Config.Env}}{{println .}}{{end}}' 2>/dev/null | sed -n 's/^API_SERVER_KEY=//p')
export API_KEY
HEALTH=$(curl -s --max-time 5 -H "Authorization: Bearer $API_KEY" "$BASE/v1/health" || true)
case "$HEALTH" in
  *'"status": "ok"'*'"version": "0.23.0"'*) ok "gateway-health" "8642 /v1/health ok, version 0.23.0" ;;
  *) bad "gateway-health" "应答: ${HEALTH:-无}" ;;
esac

# ---- 4/5. 补丁路由在位（GET 打写型路由: 405=在位, 404=不在位） ----
code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 -H "Authorization: Bearer $API_KEY" "$BASE/v1/enrollment/claim" || true)
if [ "$code" = "405" ]; then ok "enrollment-route" "POST /v1/enrollment/claim 已注册"; else bad "enrollment-route" "GET 应答 $code（期望 405）"; fi

code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 -H "Authorization: Bearer $API_KEY" "$BASE/v1/reactions/probe/1" || true)
if [ "$code" = "405" ]; then ok "reactions-write-route" "PUT/DELETE /v1/reactions/{sid}/{row} 已注册"; else bad "reactions-write-route" "GET 应答 $code（期望 405）"; fi

# ---- 6. reactions 历史投影（行为探针: 扫最近会话消息, 只统计不输出内容） ----
# 样本口径（1.6.0 修正）: 上限 60 会话、命中非空反应即早停、扫满 600 条即停;
# 消息下限 300 条——未命中且样本低于下限时明示「样本不足」, 与「样本充足仍无
# 反应」分开报。旧口径只扫 10 会话: 2026-11-23 实证 10 会话/40 条报未验、同日
# 60 会话/533 条命中非空反应（运维逐项核差异 1）, 小样本未验与能力缺失无法区分。
PROJ=$(python3 - <<'PY'
import json, os, urllib.request
key = os.environ.get("API_KEY", "")
SESSION_CAP = 60
MESSAGE_FLOOR = 300
MESSAGE_CAP = 600
def get(path):
    req = urllib.request.Request("http://127.0.0.1:8642" + path, headers={"Authorization": "Bearer " + key})
    with urllib.request.urlopen(req, timeout=8) as r:
        return json.load(r)
try:
    sessions = get("/api/sessions?limit=%d" % SESSION_CAP).get("data", [])
    tot = wk = ne = scanned = 0
    for s in sessions:
        d = get("/api/sessions/%s/messages" % s.get("id"))
        msgs = d if isinstance(d, list) else d.get("data", d.get("messages", []))
        scanned += 1
        tot += len(msgs)
        wk += sum(1 for m in msgs if isinstance(m, dict) and "reactions" in m)
        ne += sum(1 for m in msgs if isinstance(m, dict) and m.get("reactions"))
        if ne >= 1 or tot >= MESSAGE_CAP:
            break
    if ne >= 1:
        verdict = "found"
    elif tot < MESSAGE_FLOOR:
        verdict = "insufficient"
    else:
        verdict = "ample_empty"
    print("verdict=%s sessions=%d messages=%d reactions_key=%d reactions_nonempty=%d" % (verdict, scanned, tot, wk, ne))
except Exception as e:
    print("ERROR %s" % type(e).__name__)
PY
)
case "$PROJ" in
  ERROR*) unk "reactions-projection" "探针执行失败: $PROJ" ;;
  *verdict=found*) ok "reactions-projection" "$PROJ" ;;
  *verdict=insufficient*) unk "reactions-projection" "样本不足: 样本未达消息下限 300 条且无带反应消息, 无法行为确认（非能力缺失证据; $PROJ）" ;;
  *verdict=ample_empty*) unk "reactions-projection" "样本充足（>=300 条）仍无带反应消息, 无法行为确认（$PROJ）" ;;
  *) unk "reactions-projection" "探针输出无法判读: $PROJ" ;;
esac

# ---- 7. 写闸/总览（companion 监听 + 鉴权级） ----
# 断桥批二（包 1.10.0）起 8643 写闸桥已退役入关：8643 改验「无监听」
# （退役确认，网关面由 §18 write-gate 四探针接替）；8644/8646 批三起同口径。
code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 "http://127.0.0.1:8643/" || true)
case "$code" in 000|"") ok "companion-8643-retired" "8643 无监听（写闸桥已退役入关，包 1.10.0）" ;; *) bad "companion-8643-retired" "8643 仍应答: $code（退役未净）" ;; esac
# 断桥批三（包 1.19.0）起 8644/8646 两桥亦退役入关：改验「无监听」
# （网关面由第 24 节 oneday/overview 探针接替）。
for port in 8644 8646; do
  code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 "http://127.0.0.1:$port/" || true)
  case "$code" in 000|"") ok "companion-$port-retired" "$port 无监听（桥已退役入关，包 1.19.0）" ;; *) bad "companion-$port-retired" "$port 仍应答: $code（退役未净）" ;; esac
done
unk "companion-deep" "8648/8650/8651（identity/front/fileproc 宿主口）随 companion 于包 2.0.0 下线：identity/front 已由批四入关（包 2.3.0、第 28 节探针接替）；fileproc 已由网关 fileproc_gateway 在役（第 15 节）"

# ---- 8. Web 面 ----
code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 http://127.0.0.1:9119/ || true)
case "$code" in 200|302) ok "web-face" "9119 应答 $code" ;; *) bad "web-face" "应答: ${code:-无}" ;; esac
unk "reactions-projection-9119" "需 Dashboard 登录 cookie 流, 本探针未含"

# ---- 9. 规划中能力（当前缺失为期望内） ----
if [ -f "$DEPLOY_DIR/patches/web_routers_sessions.py" ] && grep -q 'sessions/{session_id}/rewind' "$DEPLOY_DIR/patches/web_routers_sessions.py"; then
  ok "rewind-route" "补丁内路由已在位（批 0 行为验收已通过）"
else
  plan "rewind-route" "批 0 未入包, 当前无此路由——符合规划预期"
fi
code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 -H "Authorization: Bearer $API_KEY" "$BASE/v1/approvals" || true)
if [ "$code" = "200" ]; then ok "approvals-endpoint" "GET /v1/approvals 应答 200（批 2 在役）"; else bad "approvals-endpoint" "GET /v1/approvals 应答 $code（期望 200）"; fi
if docker exec hermes test -f /opt/data/approvals/approval_ledger.jsonl 2>/dev/null; then ok "approvals-ledger" "待批账文件在位 /opt/data/approvals/approval_ledger.jsonl"; else unk "approvals-ledger" "待批账文件尚未生成（无待批事件落盘时为惰性创建）"; fi
plan "apns-push" "批 4b 未入包（令牌登记端点未定路径, 入包时补探针）"
code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 -H "Authorization: Bearer $API_KEY" "$BASE/v1/grants" || true)
if [ "$code" = "200" ]; then ok "grants-endpoint" "GET /v1/grants 应答 200（批 5 在役）"; else bad "grants-endpoint" "GET /v1/grants 应答 $code（期望 200）"; fi
GRANTS_CMP=$(python3 - <<'PY'
import json, os, urllib.request
key = os.environ.get("API_KEY", "")
def get(path):
    req = urllib.request.Request("http://127.0.0.1:8642" + path, headers={"Authorization": "Bearer " + key})
    with urllib.request.urlopen(req, timeout=8) as r:
        return json.load(r)
try:
    d = get("/v1/grants")
    print("exec=%s writegate=%s total=%d partial=%s" % (d.get("exec_count"), d.get("writegate_count"), len(d.get("grants", [])), d.get("partial")))
except Exception as e:
    print("ERROR %s" % type(e).__name__)
PY
)
TRUTH=$(docker exec hermes python3 -c "
import json
from hermes_cli.config import load_config_readonly
raw = load_config_readonly().get('command_allowlist') or []
try:
    rules = json.load(open('/opt/data/write-gate/rules.json')).get('rules', [])
except Exception:
    rules = []
print('exec=%d writegate=%d' % (len(set(raw)), len(rules)))
" 2>/dev/null || echo "ERROR")
case "$GRANTS_CMP" in
  ERROR*) bad "grants-reconcile" "清单探针执行失败: $GRANTS_CMP" ;;
  *)
    exp_exec=$(echo "$TRUTH" | sed -n 's/.*exec=\([0-9]*\).*/\1/p')
    exp_wg=$(echo "$TRUTH" | sed -n 's/.*writegate=\([0-9]*\).*/\1/p')
    got_exec=$(echo "$GRANTS_CMP" | sed -n 's/.*exec=\([0-9]*\).*/\1/p')
    got_wg=$(echo "$GRANTS_CMP" | sed -n 's/.*writegate=\([0-9]*\).*/\1/p')
    if [ -n "$exp_exec" ] && [ "$got_exec" = "$exp_exec" ] && [ "$got_wg" = "$exp_wg" ]; then
      ok "grants-reconcile" "清单与真源对账一致（$GRANTS_CMP vs 真源 $TRUTH）"
    else
      bad "grants-reconcile" "清单 $GRANTS_CMP 与真源 $TRUTH 不一致"
    fi ;;
esac
# ---- 9a2. grants 审计账本落盘（包 1.12.0, §439 细节复查 B8 改判）: 只读探针 ----
# 账本为惰性生成（首个 observed/revoked 事件才落盘）; 2026-11-24 应用线已以
# 测试 exec 授权走通立账->observed 落盘->revoke->revoked 落盘->回读清理全链,
# 本探针只读回验文件在位且末行字段完整, 不构造写型动作。
if docker exec hermes python3 -c "
import json
lines = [l for l in open('/opt/data/grants/grant_events.jsonl').read().splitlines() if l.strip()]
assert lines, 'empty'
o = json.loads(lines[-1])
assert o.get('v') == 1 and o.get('event') and o.get('grant_key') and o.get('source') and o.get('ts')
" 2>/dev/null; then ok "grants-ledger-landed" "授权审计账本已落盘且事件字段完整 /opt/data/grants/grant_events.jsonl（B8 全链实证 2026-11-24）"; else bad "grants-ledger-landed" "授权审计账本未落盘或末行字段不全（B8 改判后应已做实）"; fi

# ---- 9b. grants 审计 1 年自动清除（包 1.6.0）: 静态探针 ----
# 行为属时间驱动（事件满 1 年才清）, 活探针无法构造; 以容器内模块含 sweep
# 实现+留存常量为在位证据, 逻辑正确性以包内本地验证为准（verify-output-1.6.0）。
if docker exec hermes grep -q "EVENT_RETENTION_SECONDS" /opt/hermes/gateway/platforms/grant_projection.py 2>/dev/null \
   && docker exec hermes grep -q "def sweep" /opt/hermes/gateway/platforms/grant_projection.py 2>/dev/null; then
  ok "grants-audit-purge" "grant_projection 含审计 1 年自动清除 sweep（包 1.6.0）"
else
  bad "grants-audit-purge" "grant_projection 无自动清除实现（1.6.0 未应用或补丁未挂载）"
fi
# ---- 10. 工具集启停（批 34-S, 包 1.4.0）: 静态 grep + 路由探针 ----
if [ -f "$DEPLOY_DIR/patches/api_server.py" ] && grep -q 'toolsets/{name}' "$DEPLOY_DIR/patches/api_server.py"; then
  ok "toolset-toggle-route" "补丁内 PUT /v1/toolsets/{name} 路由已在位（批 34-S）"
else
  bad "toolset-toggle-route" "补丁内未找到 toolsets/{name} 路由（批 34-S 未入包/未应用）"
fi
code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 -H "Authorization: Bearer $API_KEY" "$BASE/v1/toolsets/video" || true)
if [ "$code" = "405" ]; then ok "toolset-toggle-method" "GET /v1/toolsets/{name} 应答 405（PUT 路由在位）"; else bad "toolset-toggle-method" "GET /v1/toolsets/{name} 应答 $code（期望 405）"; fi
unk "toolset-toggle-behavior" "写型探针（翻转一集 enabled→GET /v1/toolsets 回读对账→复原）默认不跑; 人工验收路径见 CAPABILITIES.md #13"

unk "run-idempotency" "写型探针（同键重放 POST /v1/runs）本版不执行; 人工验收路径见 CAPABILITIES.md #4"

# ---- 11. 消息级幂等 client_message_id（包 1.5.0, 总表 154）: 只读能力探针 ----
CMID=$(python3 - <<'PY'
import json, os, urllib.request
key = os.environ.get("API_KEY", "")
req = urllib.request.Request("http://127.0.0.1:8642/v1/capabilities", headers={"Authorization": "Bearer " + key})
try:
    with urllib.request.urlopen(req, timeout=8) as r:
        d = json.load(r)
    print("client_message_id=%s" % ((d.get("features", {}).get("runs_idempotency", {}) or {}).get("client_message_id")))
except Exception as e:
    print("ERROR %s" % type(e).__name__)
PY
)
case "$CMID" in
  ERROR*) unk "runs-client-message-id" "能力探针执行失败: $CMID" ;;
  *client_message_id=True) ok "runs-client-message-id" "GET /v1/capabilities runs_idempotency.client_message_id=true（包 1.5.0）" ;;
  *) bad "runs-client-message-id" "能力面未声明 client_message_id（$CMID; 期望 true——1.5.0 未应用或补丁未挂载）" ;;
esac
unk "runs-client-message-id-behavior" "写型探针（无头带 client_message_id 同体重复 POST→第二次 202 replayed 同 run_id; 同 id 异体→409）默认不跑; 人工验收路径见 CAPABILITIES.md #14"

# ---- 12. run 终态列表（包 1.7.0, 总表 162/163 缺口 G1/G3）: 只读行为探针 ----
RUNS_LIST=$(python3 - <<'PY'
import json, os, urllib.request
key = os.environ.get("API_KEY", "")
req = urllib.request.Request("http://127.0.0.1:8642/v1/runs?limit=5", headers={"Authorization": "Bearer " + key})
try:
    with urllib.request.urlopen(req, timeout=8) as r:
        d = json.load(r)
    rows = d.get("data")
    leak = any("output" in row for row in rows if isinstance(row, dict)) if isinstance(rows, list) else True
    print("rows=%s leak=%s" % (len(rows) if isinstance(rows, list) else "n/a", leak))
except Exception as e:
    print("ERROR %s" % type(e).__name__)
PY
)
case "$RUNS_LIST" in
  ERROR*) bad "runs-terminal-list" "探针执行失败: $RUNS_LIST" ;;
  *leak=True*) bad "runs-terminal-list" "列表投影泄漏 output 内容字段: $RUNS_LIST" ;;
  rows=*) ok "runs-terminal-list" "GET /v1/runs 应答 200 且投影无内容字段（$RUNS_LIST; 包 1.7.0）" ;;
  *) bad "runs-terminal-list" "应答无法判读: $RUNS_LIST" ;;
esac

# ---- 13. 崩溃上报端点（包 1.7.0, 总表 131）: GET 只读探针; POST 属写型不跑 ----
code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 -H "Authorization: Bearer $API_KEY" "$BASE/v1/diagnostics/crash-reports?limit=1" || true)
if [ "$code" = "200" ]; then ok "crash-reports-endpoint" "GET /v1/diagnostics/crash-reports 应答 200（包 1.7.0）"; else bad "crash-reports-endpoint" "GET 应答 $code（期望 200）"; fi
unk "crash-reports-ingest" "写型探针（POST 合成白名单记录→GET 回读→脱敏断言）默认不跑; 人工验收路径见 CAPABILITIES.md #17"

# ---- 14. companion 退役（包 2.0.0 起; 原 companion 版本探针, 包 1.7.0） ----
# 断桥批五（2.0.0）: companion 容器整下线、device 入关。容器在场即退役未净。
if docker inspect oneday-companion >/dev/null 2>&1; then bad "companion-retired" "oneday-companion 容器仍在（包 2.0.0 应已下线；末代在役版为 oneday/companion:1.0.77）"; else ok "companion-retired" "oneday-companion 容器不存在（断桥批五下线，包 2.0.0）"; fi
if docker exec hermes grep -q "approval_pending" /opt/hermes/gateway/platforms/overview_gateway.py 2>/dev/null \
   && docker exec hermes grep -q "run_failed" /opt/hermes/gateway/platforms/overview_gateway.py 2>/dev/null; then
  ok "overview-notification-kinds" "网关 overview 模块含 approval_pending（G2）与 run_failed（G1/G3）映射（静态探针; 活条目随真实待批/run 终态出现; 批三起改查网关模块，桥模块已退役）"
else
  bad "overview-notification-kinds" "网关 overview 模块缺新 kind 映射（包 1.19.0 未应用）"
fi
# ---- 14b. G1 任务侧失败两源（包 2.4.0）: 源在位（抓取函数+kind）＋条目形状（基线键） ----
if docker exec hermes grep -q "_fetch_cron_failures" /opt/hermes/gateway/platforms/overview_gateway.py 2>/dev/null \
   && docker exec hermes grep -q "cron_failed" /opt/hermes/gateway/platforms/overview_gateway.py 2>/dev/null \
   && docker exec hermes grep -q "_fetch_kanban_failures" /opt/hermes/gateway/platforms/overview_gateway.py 2>/dev/null \
   && docker exec hermes grep -q "kanban_failed" /opt/hermes/gateway/platforms/overview_gateway.py 2>/dev/null; then
  ok "overview-g1-sources" "网关 overview 模块含 G1 两源抓取函数与 cron_failed/kanban_failed 映射（静态探针; 活条目随真实 cron 事故/看板失败出现，包 2.4.0）"
else
  bad "overview-g1-sources" "网关 overview 模块缺 G1 失败两源（包 2.4.0 未应用）"
fi
if docker exec hermes grep -q "cron_since" /opt/hermes/gateway/platforms/overview_gateway.py 2>/dev/null \
   && docker exec hermes grep -q "kanban_since" /opt/hermes/gateway/platforms/overview_gateway.py 2>/dev/null \
   && docker exec hermes grep -q "_one_line_reason" /opt/hermes/gateway/platforms/overview_gateway.py 2>/dev/null; then
  ok "overview-g1-shape" "G1 条目形状机器在位：cron_since/kanban_since 基线键＋_one_line_reason 一行去敏投影（包 2.4.0; 行为证据见 g1-rollout-20261125.md 活验）"
else
  bad "overview-g1-shape" "网关 overview 模块缺 G1 基线键/去敏投影（包 2.4.0 未应用）"
fi

# ---- 15. 文件加工（G20 rendition + §125 spreadsheet, 包 1.9.0 网关 fileproc_gateway）: 路由+鉴权探针 ----
code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 "$BASE/v1/media/rendition?path=/opt/data/x.jpg&w=360&kind=image" || true)
if [ "$code" = "401" ]; then ok "rendition-route" "GET /v1/media/rendition 无钥应答 401（网关路由在位+鉴权生效; 行为证据见 CAPABILITIES.md #18）"; else bad "rendition-route" "无钥应答 $code（期望 401）"; fi
code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 "$BASE/api/fileproc-bridge/media/rendition?path=/opt/data/x.jpg&w=360&kind=image" || true)
if [ "$code" = "401" ]; then ok "rendition-shape-route" "保形口 GET /api/fileproc-bridge/media/rendition 无钥应答 401（已发货 App 路径在位）"; else bad "rendition-shape-route" "无钥应答 $code（期望 401）"; fi
code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 "$BASE/v1/files/spreadsheet?path=/opt/data/x.xlsx" || true)
if [ "$code" = "401" ]; then ok "spreadsheet-route" "GET /v1/files/spreadsheet 无钥应答 401（网关路由在位+鉴权生效）"; else bad "spreadsheet-route" "无钥应答 $code（期望 401）"; fi

# ---- 16. AI 自反应（包 1.8.0, 总表 202）: 能力位 + agent 反应投影（行为/只读） ----
# 静态级证据在第 2 节哈希回读（react_to_message_tool.py / self_reaction_pending.py /
# api_server_runs.py 三文件全合 = self-reactions-hashes）。
SRCAP=$(python3 - <<'PY'
import json, os, urllib.request
key = os.environ.get("API_KEY", "")
req = urllib.request.Request("http://127.0.0.1:8642/v1/capabilities", headers={"Authorization": "Bearer " + key})
try:
    with urllib.request.urlopen(req, timeout=8) as r:
        d = json.load(r)
    print("self_reactions=%s" % (d.get("features", {}) or {}).get("self_reactions"))
except Exception as e:
    print("ERROR %s" % type(e).__name__)
PY
)
case "$SRCAP" in
  ERROR*) unk "self-reactions-capability" "能力探针执行失败: $SRCAP" ;;
  *self_reactions=True) ok "self-reactions-capability" "GET /v1/capabilities features.self_reactions=true（包 1.8.0; 仅证代码在位, 产反应另受 display.agent_self_reactions 闸控）" ;;
  *) bad "self-reactions-capability" "能力面未声明 self_reactions（$SRCAP; 期望 true——1.8.0 未应用或补丁未挂载）" ;;
esac
SRPROJ=$(python3 - <<'PY'
import json, os, urllib.request
key = os.environ.get("API_KEY", "")
SESSION_CAP = 60
MESSAGE_FLOOR = 300
MESSAGE_CAP = 600
def get(path):
    req = urllib.request.Request("http://127.0.0.1:8642" + path, headers={"Authorization": "Bearer " + key})
    with urllib.request.urlopen(req, timeout=8) as r:
        return json.load(r)
try:
    sessions = get("/api/sessions?limit=%d" % SESSION_CAP).get("data", [])
    tot = agent_rx = scanned = 0
    for s in sessions:
        d = get("/api/sessions/%s/messages" % s.get("id"))
        msgs = d if isinstance(d, list) else d.get("data", d.get("messages", []))
        scanned += 1
        tot += len(msgs)
        for m in msgs:
            if isinstance(m, dict):
                for r in (m.get("reactions") or []):
                    if isinstance(r, dict) and r.get("author") == "agent":
                        agent_rx += 1
        if agent_rx >= 1 or tot >= MESSAGE_CAP:
            break
    if agent_rx >= 1:
        verdict = "found"
    elif tot < MESSAGE_FLOOR:
        verdict = "insufficient"
    else:
        verdict = "ample_empty"
    print("verdict=%s sessions=%d messages=%d agent_reactions=%d" % (verdict, scanned, tot, agent_rx))
except Exception as e:
    print("ERROR %s" % type(e).__name__)
PY
)
case "$SRPROJ" in
  ERROR*) unk "self-reactions-projection" "探针执行失败: $SRPROJ" ;;
  *verdict=found*) ok "self-reactions-projection" "$SRPROJ" ;;
  *verdict=insufficient*) unk "self-reactions-projection" "未触发: 样本未达消息下限 300 条且无 agent 反应（闸默认关/未翻闸时为预期; $SRPROJ）" ;;
  *verdict=ample_empty*) unk "self-reactions-projection" "未触发: 样本充足仍无 agent 反应（闸未开或尚无纯聊天轮贴反应; 非能力缺失证据; $SRPROJ）" ;;
  *) unk "self-reactions-projection" "探针输出无法判读: $SRPROJ" ;;
esac
unk "self-reactions-behavior" "写型探针（一次性会话: 纯聊天轮要求贴反应→触发用户消息行 agent 反应恰 1 且在盘内; 工具轮/失败轮→无 agent 反应; 正文无标记文本）默认不跑, 须 --with-mutating 人工执行; 路径见 CAPABILITIES.md #19"

# ---- 17. 断桥批一退役面（包 1.9.0）: channels 整退 + identity 改名写口关停 ----
code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 3 "http://127.0.0.1:8649/" || true)
if [ "$code" = "000" ]; then ok "channels-retired" "8649 无监听（channels 模块已整退）"; else bad "channels-retired" "8649 仍应答 $code（期望无监听; 观察窗内待命属未到摘除步, 见 bridge-batch1-rollout）"; fi
if docker exec hermes grep -q "NAME_WRITE_RETIRED_180" /opt/hermes/gateway/platforms/identity_gateway.py 2>/dev/null; then
  ok "identity-name-write-retired" "网关 identity 模块含写口关停标记（POST /identity/name 回 404, GET 读口与 MCP 本体在位；断桥批四起改查网关模块）"
else
  bad "identity-name-write-retired" "网关 identity 模块未见写口关停标记（断桥批四未应用或模块未挂载）"
fi

# ---- 18. 写闸网关入关（包 1.10.0, 断桥批二）: 只读探针; 写型默认不跑 ----
code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 -H "Authorization: Bearer $API_KEY" "$BASE/v1/write-gate/status" || true)
if [ "$code" = "200" ]; then ok "write-gate-status-endpoint" "GET /v1/write-gate/status 应答 200（包 1.10.0）"; else bad "write-gate-status-endpoint" "GET 应答 $code（期望 200）"; fi

code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 -H "Authorization: Bearer $API_KEY" "$BASE/v1/write-gate/rules" || true)
if [ "$code" = "200" ]; then ok "write-gate-rules-endpoint" "GET /v1/write-gate/rules 应答 200（包 1.10.0）"; else bad "write-gate-rules-endpoint" "GET 应答 $code（期望 200）"; fi

code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 -H "Authorization: Bearer $API_KEY" "$BASE/api/write-gate/status" || true)
if [ "$code" = "200" ]; then ok "write-gate-shape-endpoint" "GET /api/write-gate/status 保形口应答 200（包 1.10.0 迁移期）"; else bad "write-gate-shape-endpoint" "保形口应答 $code（期望 200）"; fi

code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 -H "Authorization: Bearer $API_KEY" "$BASE/v1/memories" || true)
if [ "$code" = "200" ]; then ok "memories-endpoint" "GET /v1/memories 应答 200（包 1.10.0）"; else bad "memories-endpoint" "GET 应答 $code（期望 200）"; fi

unk "write-gate-decide" "写型探针（待批产生→聚合可见→端点作答→原 run 续跑）默认不跑; 人工验收路径见 CAPABILITIES.md #20"
unk "memory-propose" "写型探针（提交→pending 在位→暂存文件存在）默认不跑; 人工验收路径见 CAPABILITIES.md #20"

# ---- 19. OneDay 记忆机制（包 1.11.0, §439）: 路由 + 能力位 + 种子/cron 在位 ----
# 静态级证据在第 2 节哈希回读（oneday_memory.py + api_server.py）。
code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 "$BASE/v1/memory/layers" || true)
if [ "$code" = "401" ]; then ok "memory-layers-route" "GET /v1/memory/layers 无钥 401（路由在位＋鉴权生效, §439）"; else bad "memory-layers-route" "无钥应答 $code（期望 401）"; fi

body=$(curl -s --max-time 5 -H "Authorization: Bearer $API_KEY" "$BASE/v1/memory/layers" || true)
case "$body" in *'"oneday_memory.layers"'*) ok "memory-layers-behavior" "带钥回层清单（object=oneday_memory.layers）" ;; *) bad "memory-layers-behavior" "带钥回读异常: ${body:0:80}" ;; esac

body=$(curl -s --max-time 5 -H "Authorization: Bearer $API_KEY" "$BASE/v1/capabilities" || true)
case "$body" in *'"oneday_memory": true'*) ok "memory-capability-flag" "features.oneday_memory=true" ;; *) bad "memory-capability-flag" "capabilities 未见 oneday_memory 位" ;; esac

if docker exec hermes test -f /opt/data/memories/oneday/inbox/INBOX.md 2>/dev/null; then ok "memory-seed-tree" "种子分层子树在位（memories/oneday/inbox/INBOX.md）"; else bad "memory-seed-tree" "种子子树未铺（install 3c 未执行或被删）"; fi

if docker exec hermes grep -q "OneDay 记忆日结" /opt/data/cron/jobs.json 2>/dev/null; then ok "memory-cron-jobs" "cron/jobs.json 含 OneDay 记忆日结/周体检两条作业"; else bad "memory-cron-jobs" "cron 两条作业未合并（install 3c 未执行或 jobs.json 缺失）"; fi
if docker exec hermes grep -q "OneDay 目标进展日结提炼" /opt/data/cron/jobs.json 2>/dev/null; then ok "goals-cron-job" "cron/jobs.json 含目标进展日结提炼作业（G-2）"; else bad "goals-cron-job" "目标提炼作业未合并（install 3c 未执行或 jobs.json 缺失）"; fi

unk "memory-distill-behavior" "行为属时间驱动（日结首跑: journal 出现提炼回执且条目落层）, 活探针不构造; 人工验收路径见 memory-mechanism-rollout-20261124.md 与 CAPABILITIES.md #21"

# ---- 20. 第一层提示词（包 1.12.0, §442）: 身份真源 + 渲染 + 不落 data ----
# 静态级证据在第 2 节哈希回读（system_prompt.py + oneday_prompt.py）。
if docker exec hermes python3 -c "
import json
d = json.load(open('/opt/data/identity.json'))
assert all(isinstance(d.get(k), str) and d[k].strip() for k in ('agent_name', 'company_name', 'product_name'))
" 2>/dev/null; then ok "prompt-identity-file" "identity.json 在位且三值非空（身份真源, §442 P4）"; else bad "prompt-identity-file" "identity.json 缺失或三值未齐（第一层将回落上游装配）"; fi

if docker exec hermes python3 -c "
import sys
sys.path.insert(0, '/opt/hermes')
from agent.oneday_prompt import render_oneday_prompt
out = render_oneday_prompt()
assert out and 'Safety — The Red Lines' in out and '{{' not in out
" 2>/dev/null; then ok "prompt-render" "第一层提示词渲染成功（占位全填充、红线章在位）"; else bad "prompt-render" "第一层提示词渲染失败（identity 缺失或模块异常）"; fi

if docker exec hermes sh -c 'test -z "$(find /opt/data -iname "*system-prompt*" -o -iname "SYSTEM-PROMPT*" 2>/dev/null)"' 2>/dev/null; then ok "prompt-not-in-data" "data 区无系统提示词全文文件（全稿只随包代码走, §442 改判）"; else bad "prompt-not-in-data" "data 区出现系统提示词文件（违反 §442 落点改判）"; fi

unk "prompt-session-behavior" "新会话行为（自报家门与 identity.json 一致、全稿无可见入口）属会话级验证, 活探针不构造; 人工验收见应用线抽测记录（§442 阶段 C）"

# ---- 21. 设置注册表只读下发（包 1.13.0, DESIGN §435 一期）: 路由鉴权 + 种子对账 ----
# 静态级证据在第 2 节哈希回读（settings_registry.py + api_server.py）。
code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 "$BASE/v1/settings/registry" || true)
if [ "$code" = "401" ]; then ok "settings-registry-route" "GET /v1/settings/registry 无钥应答 401（网关路由在位+鉴权生效）"; else bad "settings-registry-route" "无钥应答 $code（期望 401）"; fi
SRSEED=$(DEPLOY_DIR="$DEPLOY_DIR" python3 - <<'PY'
import importlib.util, json, os, urllib.request
key = os.environ.get("API_KEY", "")
deploy = os.environ.get("DEPLOY_DIR", "")
try:
    spec = importlib.util.spec_from_file_location(
        "settings_registry_seed", os.path.join(deploy, "patches", "settings_registry.py"))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    seed = mod.seed_records()
    problems = mod.validate_records(seed)
    if problems:
        print("MISMATCH seed invalid: %s" % problems[:3])
        raise SystemExit
    seedmap = {r["key"]: r for r in seed}
    req = urllib.request.Request("http://127.0.0.1:8642/v1/settings/registry",
                                 headers={"Authorization": "Bearer " + key})
    with urllib.request.urlopen(req, timeout=8) as resp:
        payload = json.load(resp)
    got = {r["key"]: r for r in payload.get("records", []) if isinstance(r, dict)}
    meta_fields = ("type", "default", "surface", "owner", "writable_by", "capability")
    missing = [k for k in seedmap if k not in got]
    drift = [k for k in seedmap if k in got and
             any(got[k].get(f) != seedmap[k].get(f) for f in meta_fields)]
    extra = [k for k in got if k not in seedmap]
    if missing or drift:
        print("MISMATCH missing=%s drift=%s" % (missing[:5], drift[:5]))
    else:
        print("seed_ok records=%d extra=%d" % (len(got), len(extra)))
except SystemExit:
    pass
except Exception as e:
    print("ERROR %s" % type(e).__name__)
PY
)
case "$SRSEED" in
  ERROR*) unk "settings-registry-seed" "种子对账探针执行失败: $SRSEED" ;;
  seed_ok*) ok "settings-registry-seed" "带钥回读与包内种子逐条对账一致（$SRSEED; 种子元数据对已知键权威, overlay 仅许载 value/新记录）" ;;
  *) bad "settings-registry-seed" "回读与种子不一致: $SRSEED" ;;
esac

# ---- 22. 记忆语义检索（包 1.14.0, §445）: 后端状态 + hybrid 行为（只读） ----
# 静态级证据在第 2 节哈希回读（oneday_semantic.py + api_server.py）。
# status 经模块 CLI 在容器内跑: 索引后端必须是 fastembed 真后端、
# 512 维、且未落哈希降级, 否则能力声明不成立。
sem_status=$(docker exec hermes python3 /opt/hermes/gateway/platforms/oneday_semantic.py status 2>/dev/null || true)
case "$sem_status" in
  *'"backend": "fastembed"'*'"dim": 512'*)
    case "$sem_status" in
      *'"degraded": true'*) bad "memory-semantic-status" "语义后端已降级（哈希兜底）: ${sem_status:0:120}" ;;
      *) ok "memory-semantic-status" "语义后端 fastembed/512 维在位、未降级" ;;
    esac ;;
  *) bad "memory-semantic-status" "语义状态异常: ${sem_status:0:120}" ;;
esac

# hybrid 行为: 换说法问法（与忌口条目字面零重叠）须回 mode=hybrid 且
# 命中带 routes 分路信息; 首次调用含模型加载, 给足 60 秒。
body=$(curl -s --max-time 60 -H "Authorization: Bearer $API_KEY" "$BASE/v1/memory/search?q=%E5%AA%B3%E5%A6%87%E5%84%BF%E5%90%83%E9%A5%AD%E6%9C%89%E4%BB%80%E4%B9%88%E5%BF%8C%E5%8F%A3&mode=hybrid" || true)
case "$body" in
  *'"mode": "hybrid"'*'"routes"'*) ok "memory-hybrid-behavior" "mode=hybrid 回读命中且带 routes 分路（换说法问法）" ;;
  *) bad "memory-hybrid-behavior" "hybrid 回读异常: ${body:0:120}" ;;
esac

# ---- 23. 技能准入硬闸（包 1.18.0, §444）: 挂点在位 ----
# 静态级证据在第 2 节哈希回读（skill_admission_gate.py）；挂点本体
# skill_manager_tool.py 的容器内哈希由 install 第 5 节全量回读把关
# （693b9a71…），本节以挂点 grep 为在位证据。
if docker exec hermes grep -q "skill_admission_gate" /opt/hermes/tools/skill_manager_tool.py 2>/dev/null; then ok "skill-gate-hook" "skill_manager_tool.py 含准入闸挂点（§444）"; else bad "skill-gate-hook" "挂点缺失（skill_manager_tool 补丁未应用）"; fi
unk "skill-gate-behavior" "写型探针（一次性技能: 带凭据 create 应被拒且无目录残留、干净 create 应放行且账本落 admitted 行、改坏 patch 应被拒且旧版逐字节不变、skill_gate.json 豁免（approved_by=user）应放行且账本落 exempted 行，验毕删探针技能）默认不跑; 人工验收路径见 CAPABILITIES.md #28 与 skillgate-spec-20261124.md"

# ---- 24. 断桥批三（包 1.19.0, #31/#32）: oneday/overview 入关 ----
B3_ROUNDS=$(docker exec hermes python3 -c 'import json; d=json.load(open("/opt/data/cron/jobs.json")); js=d.get("jobs") if isinstance(d, dict) else d; print(sum(1 for j in (js or []) if isinstance(j, dict) and str(j.get("name") or "").startswith("OneDay")))' 2>/dev/null || echo -1)
B3=$(B3_ROUNDS="$B3_ROUNDS" python3 - <<'PY'
import json, os, urllib.request
key = os.environ.get("API_KEY", "")
H = {"Authorization": "Bearer " + key}
def get(path, headers=None):
    req = urllib.request.Request("http://127.0.0.1:8642" + path,
                                 headers=headers or H)
    try:
        with urllib.request.urlopen(req, timeout=8) as r:
            return r.status, json.load(r)
    except urllib.error.HTTPError as e:
        return e.code, None
    except Exception:
        return 0, None
out = []
st, health = get("/api/oneday-bridge/health")
out.append("health=%s" % (
    "ok" if st == 200 and isinstance(health, dict)
    and health.get("degraded") is False else "bad"))
st, led = get("/api/oneday-bridge/ledger")
items = None
if st == 200 and isinstance(led, dict):
    items = (led.get("counts") or {}).get("total")
out.append("ledger=%s" % ("ok" if isinstance(items, int)
                          and items > 0 else "bad"))
rounds = int(os.environ.get("B3_ROUNDS", "-1"))
out.append("rounds=%d" % rounds)
st, _ = get("/api/oneday-bridge/internal/cron/ping", headers={})
out.append("ping-noauth=%s" % ("ok" if st == 401 else "bad"))
st, summ = get("/api/overview-bridge/overview")
out.append("summary=%s" % (
    "ok" if st == 200 and isinstance(summ, dict)
    and summ.get("hermesUp") is True else "bad"))
# library MCP: tools/list + tools/call vs REST deep equality (read-only)
def mcp(payload):
    req = urllib.request.Request(
        "http://127.0.0.1:8642/api/oneday-bridge/library-mcp", method="POST",
        data=json.dumps(payload).encode(),
        headers=dict(H, **{"Content-Type": "application/json"}))
    try:
        with urllib.request.urlopen(req, timeout=15) as r:
            return json.load(r)
    except Exception:
        return None
lst = mcp({"jsonrpc": "2.0", "id": 1, "method": "tools/list"})
names = []
try:
    names = [t.get("name") for t in lst["result"]["tools"]]
except Exception:
    pass
out.append("library-tools=%s" % ("ok" if names == ["library_list"]
                                 else "bad"))
call = mcp({"jsonrpc": "2.0", "id": 2, "method": "tools/call",
            "params": {"name": "library_list",
                       "arguments": {"limit": 500}}})
st, rest = get("/api/oneday-bridge/file-library")
deep = "bad"
try:
    mcp_view = json.loads(call["result"]["content"][0]["text"])
    mcp_items = mcp_view["items"]
    rest_items = rest["items"]
    keyf = lambda it: (str(it.get("path")), str(it.get("name")))
    if [keyf(i) for i in mcp_items] == [keyf(i) for i in rest_items]:
        deep = "ok"
except Exception:
    pass
out.append("library-deep=%s" % deep)
print(" ".join(out))
PY
)
case "$B3" in *health=ok*) ok "oneday-gateway-health" "网关 oneday 面 health 应答且 degraded=false（包 1.19.0）" ;; *) bad "oneday-gateway-health" "探针: $B3" ;; esac
case "$B3" in *ledger=ok*) ok "oneday-gateway-ledger" "网关台账 items 总数 > 0（只读探针; 与切换前基线对账见应用验收）" ;; *) bad "oneday-gateway-ledger" "探针: $B3" ;; esac
case "$B3" in *rounds=9*) ok "oneday-cron-rounds" "cron 登记表 OneDay 作业 9 条（系统轮 6＝原 4＋批三 #47 feed-evaluate/ideas-expire，另记忆日结/周体检/目标日结提炼 3）" ;; *) bad "oneday-cron-rounds" "探针: $B3（期望 rounds=9）" ;; esac
case "$B3" in *ping-noauth=ok*) ok "oneday-cron-ping-auth" "内部回调 ping 无钥 401（回调钥在位）" ;; *) bad "oneday-cron-ping-auth" "探针: $B3" ;; esac
case "$B3" in *summary=ok*) ok "overview-gateway-summary" "网关 overview summary 应答且 hermesUp=true（包 1.19.0）" ;; *) bad "overview-gateway-summary" "探针: $B3" ;; esac
case "$B3" in *library-tools=ok*) ok "library-mcp-tools" "网关 /library-mcp tools/list 恰 [library_list]（#26 读面入关不失）" ;; *) bad "library-mcp-tools" "探针: $B3" ;; esac
case "$B3" in *library-deep=ok*) ok "library-deep-equality" "library tools/call 与 GET /file-library 条目逐条深等（#26 复验）" ;; *) bad "library-deep-equality" "探针: $B3" ;; esac
unk "oneday-gateway-write-behavior" "写型探针（cron feed 轮手动回调落账、台账 PDF 导出、C-3 password 模式回退演练）默认不跑; 人工验收路径见 CAPABILITIES.md #31"
unk "overview-pipeline-filter" "流水线 run_* 完成通知来源侧过滤的行为证据需应用后自然轮观察（静态级已由 overview_gateway 哈希回读把关）; 人工验收路径见 CAPABILITIES.md #32"

# ---- 27. §441 选择框潜伏（包 2.2.0, #37）: 机器在位、闸默认关 ----
for name in options_pending.py present_options_tool.py; do
  got=$(docker exec hermes sha256sum "${CPATH[$name]}" 2>/dev/null | awk '{print $1}')
  if [ "$got" = "${WANT_SHA[$name]}" ]; then ok "patch-hash $name" "容器内回读一致"; else bad "patch-hash $name" "容器内: ${got:-读不到}"; fi
done
CAPS=$(curl -s --max-time 5 -H "Authorization: Bearer $API_KEY" "$BASE/v1/capabilities" || true)
case "$CAPS" in *'"options_card": true'*) ok "options-capability-flag" "features.options_card=true（补丁在位即声明，包 2.2.0）" ;; *) bad "options-capability-flag" "capabilities 未见 options_card 位" ;; esac
if grep -q "options_card" "$DEPLOY_DIR/data/config.yaml" 2>/dev/null; then unk "options-gate-state" "config.yaml 出现 options_card 字样（翻闸与否以实例为准，本探针不判读）"; else ok "options-gate-latent" "config.yaml 无 options_card 登记：display.options_card 闸未设（默认关）＋工具集未启用＝潜伏态（包 2.2.0）"; fi

printf '汇总: 齐 %d / 缺 %d / 规划中 %d / 未验 %d\n' "$PASS" "$FAIL" "$PLANNED" "$UNKNOWN"
[ "$FAIL" = "0" ]

# ---- 25. 中枢数据四件（包 1.23.0, #34）: 只读探针 ----
# Dashboard 两端点走会话令牌（容器 env 内读取，不出容器、不打印）。
HUBF=$(docker exec -i hermes python3 - <<'PY' 2>/dev/null || echo "soul=bad memory=bad"
import json, os, urllib.request
tok = os.environ.get("HERMES_DASHBOARD_SESSION_TOKEN", "")
H = {"Authorization": "Bearer " + tok}
def get(path):
    req = urllib.request.Request("http://127.0.0.1:9119" + path, headers=H)
    try:
        with urllib.request.urlopen(req, timeout=8) as r:
            return json.load(r)
    except Exception:
        return None
out = []
soul = get("/api/profiles/default/soul")
out.append("soul=%s" % ("ok" if isinstance(soul, dict)
    and isinstance(soul.get("updatedAt"), (int, float))
    and soul.get("updatedAt") > 0 else "bad"))
mem = get("/api/memory")
upd = mem.get("builtin_files_updated_at") if isinstance(mem, dict) else None
out.append("memory=%s" % ("ok" if isinstance(upd, dict)
    and isinstance(upd.get("memory"), (int, float)) else "bad"))
print(" ".join(out))
PY
)
case "$HUBF" in *soul=ok*) ok "soul-updated-at" "Dashboard soul 回执带 updatedAt（SOUL.md mtime，包 1.23.0）" ;; *) bad "soul-updated-at" "探针: $HUBF" ;; esac
case "$HUBF" in *memory=ok*) ok "memory-builtin-updated-at" "Dashboard /api/memory 带 builtin_files_updated_at.memory（包 1.23.0）" ;; *) bad "memory-builtin-updated-at" "探针: $HUBF" ;; esac
if docker exec hermes grep -q "op_count" /opt/hermes/gateway/platforms/write_gate_gateway.py 2>/dev/null && docker exec hermes grep -q "operations" /opt/hermes/gateway/platforms/write_gate_gateway.py 2>/dev/null; then ok "writegate-batch-fields" "write_gate_gateway 含 memory batch 结构化提取（包 1.23.0）"; else bad "writegate-batch-fields" "批量提取分支缺失"; fi
LEDGER_SUMMARY_N=$(docker exec hermes python3 -c 'import json,sys; sys.path.insert(0,"/opt/hermes/gateway/platforms"); import oneday_ledger_lib as L; from pathlib import Path; st=L.LedgerStore(Path("/opt/data/oneday/ledger-events.jsonl")); print(sum(1 for i in st.list_items() if i.get("summary")))' 2>/dev/null || echo -1)
if [ "$LEDGER_SUMMARY_N" -gt 0 ] 2>/dev/null; then ok "ledger-summary-settled" "台账已有 $LEDGER_SUMMARY_N 条带 summary 的结算条目（包 1.23.0）"; else unk "ledger-summary-settled" "台账暂无带 summary 条目（探针值 $LEDGER_SUMMARY_N；需 1.23.0 后首个终态结算后复验）"; fi

# ---- 26. 断桥批五（包 2.0.0, #35）: device 入关 + companion 终局退役 ----
for name in device_sync.py device_gateway.py; do
  got=$(docker exec hermes sha256sum "${CPATH[$name]}" 2>/dev/null | awk '{print $1}')
  if [ "$got" = "${WANT_SHA[$name]}" ]; then ok "patch-hash $name" "容器内回读一致"; else bad "patch-hash $name" "容器内: ${got:-读不到}"; fi
done
code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 3 "http://127.0.0.1:8647/" || true)
if [ "$code" = "000" ]; then ok "device-bridge-port-retired" "8647 无监听（device 桥已退役入关，包 2.0.0）"; else bad "device-bridge-port-retired" "8647 仍应答 $code（退役未净）"; fi
DBH=$(curl -s --max-time 5 "$BASE/api/device-bridge/health" || true)
case "$DBH" in *'"ok": true'*) ok "device-gateway-health" "8642 /api/device-bridge/health 免钥 ok（会话在位时 sessionOnline 随之）" ;; *) bad "device-gateway-health" "应答: ${DBH:-无}" ;; esac
DTOOLS=$(curl -s --max-time 8 -X POST -H "Authorization: Bearer $API_KEY" -H 'Content-Type: application/json' -d '{"jsonrpc":"2.0","id":1,"method":"tools/list","params":{}}' "$BASE/api/device-mcp" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(len(d["result"]["tools"]))' 2>/dev/null || echo -1)
if [ "$DTOOLS" = "53" ]; then ok "device-mcp-tools" "网关 /api/device-mcp tools/list = 53（与 2.0.0 应用基线在役桥注册表逐名对账一致）"; else bad "device-mcp-tools" "tools/list 计数: $DTOOLS（期望 53）"; fi
CAPS=$(curl -s --max-time 5 -H "Authorization: Bearer $API_KEY" "$BASE/v1/capabilities" || true)
case "$CAPS" in *'"device_bridge": true'*) ok "device-capability-flag" "features.device_bridge=true（包 2.0.0）" ;; *) bad "device-capability-flag" "capabilities 未见 device_bridge 位" ;; esac
if grep -A3 'device:' "$DEPLOY_DIR/data/config.yaml" 2>/dev/null | grep -q '127.0.0.1:8642/api/device-mcp'; then ok "device-mcp-config" "config.yaml mcp_servers.device 指向网关 8642（单钥）"; else bad "device-mcp-config" "config.yaml device 条目未指网关（device-mcp-config-patch.py 未应用）"; fi

# ---- 28. identity/front 网关入关（断桥批四, 包 2.3.0, #38/#39）: 只读探针; 写型默认不跑 ----
for name in identity_gateway.py front_gateway.py; do
  got=$(docker exec hermes sha256sum "${CPATH[$name]}" 2>/dev/null | awk '{print $1}')
  if [ "$got" = "${WANT_SHA[$name]}" ]; then ok "patch-hash $name" "容器内回读一致"; else bad "patch-hash $name" "容器内: ${got:-读不到}"; fi
done
CAPS=$(curl -s --max-time 5 -H "Authorization: Bearer $API_KEY" "$BASE/v1/capabilities" || true)
case "$CAPS" in *'"identity_gateway": true'*'"front_readonly": true'*) ok "batch4-capability-flags" "capabilities features identity_gateway/front_readonly 均为 true" ;; *) bad "batch4-capability-flags" "capabilities 未见 identity_gateway/front_readonly 两位" ;; esac
code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 -H "Authorization: Bearer $API_KEY" "$BASE/v1/identity/name" || true)
case "$code" in 200) ok "identity-name-gateway" "GET /v1/identity/name 应答 200（soul 名读面入关）" ;; *) bad "identity-name-gateway" "应答: ${code:-无}" ;; esac
code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 -H "Authorization: Bearer $API_KEY" "$BASE/v1/identity/avatar" || true)
case "$code" in 200) ok "identity-avatar-gateway" "GET /v1/identity/avatar 应答 200（头像仓入关）" ;; *) bad "identity-avatar-gateway" "应答: ${code:-无}" ;; esac
code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 -H "Authorization: Bearer $API_KEY" "$BASE/api/identity-bridge/identity/avatar" || true)
case "$code" in 200) ok "identity-shape" "保形口 /api/identity-bridge/identity/avatar 应答 200（MCP 注册同前缀在位）" ;; *) bad "identity-shape" "应答: ${code:-无}" ;; esac
code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 -H "Authorization: Bearer $API_KEY" "$BASE/v1/front/connections" || true)
case "$code" in 200) ok "front-connections-gateway" "GET /v1/front/connections 应答 200（连接登记只读面入关）" ;; *) bad "front-connections-gateway" "应答: ${code:-无}" ;; esac
code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 -H "Authorization: Bearer $API_KEY" "$BASE/api/companion/connections" || true)
case "$code" in 200) ok "front-shape" "保形口 /api/companion/connections 应答 200" ;; *) bad "front-shape" "应答: ${code:-无}" ;; esac
code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 -H "Authorization: Bearer $API_KEY" "$BASE/v1/front/gateway-channels" || true)
case "$code" in 200) ok "front-gateway-channels" "GET /v1/front/gateway-channels 应答 200（渠道清单只读代理入关）" ;; 503) ok "front-gateway-channels" "应答 503（网关管理凭据未在服务端配置，诚实未配置态）" ;; *) bad "front-gateway-channels" "应答: ${code:-无}" ;; esac
unk "identity-mcp-deep" "identity MCP tools/call 写型（set_name/set_avatar）默认不跑; initialize/tools/list 于应用步人工冒烟"

# ---- 29. 服务端三件＋点子 409（包 2.5.0, #41/#42/#43）: 只读探针; 写型验收默认不跑 ----
CAPS=$(curl -s --max-time 5 -H "Authorization: Bearer $API_KEY" "$BASE/v1/capabilities" || true)
case "$CAPS" in *'"settings_admin": true'*) ok "settings-admin-flag" "capabilities features.settings_admin=true（§435 二期总闸已翻，包 2.5.0）" ;; *) bad "settings-admin-flag" "capabilities 未见 settings_admin 位或总闸未翻" ;; esac
case "$CAPS" in *'"settings_write"'*'"settings_events"'*'"settings_revoke"'*) ok "settings-admin-endpoints" "capabilities endpoints 含 settings_write/settings_events/settings_revoke 三行" ;; *) bad "settings-admin-endpoints" "capabilities endpoints 缺设置写面三行" ;; esac
EV=$(curl -s --max-time 5 -H "Authorization: Bearer $API_KEY" "$BASE/v1/settings/events?limit=5" || true)
case "$EV" in *'"object": "list"'*) ok "settings-events-route" "GET /v1/settings/events 应答审计列表形状" ;; *) bad "settings-events-route" "应答: ${EV:-无}" ;; esac
REG_N=$(curl -s --max-time 5 -H "Authorization: Bearer $API_KEY" "$BASE/v1/settings/registry" | python3 -c 'import json,sys; print(len(json.load(sys.stdin).get("records", [])))' 2>/dev/null || echo -1)
if [ "$REG_N" -ge 43 ] 2>/dev/null; then ok "settings-registry-count" "注册表 $REG_N 条（种子 43＋二期登记增量）"; else bad "settings-registry-count" "注册表条数: $REG_N（期望 ≥43）"; fi
if grep -q 'settings_admin' "$DEPLOY_DIR/data/config.yaml" 2>/dev/null && grep -A2 '^settings:' "$DEPLOY_DIR/data/config.yaml" 2>/dev/null | grep -q 'agent_admin: true'; then ok "settings-admin-config" "config.yaml 含 settings_admin 工具集行＋settings.agent_admin=true（settings-admin-config-patch.py 已应用）"; else bad "settings-admin-config" "config.yaml 缺工具集行或总闸未翻（settings-admin-config-patch.py 未应用）"; fi
DASHENV=$(docker exec hermes env 2>/dev/null | grep -c '^HERMES_DASH_USER=\|^HERMES_DASH_PASSWORD=' || true)
if [ "$DASHENV" = "0" ]; then ok "c3-dash-password-env-retired" "容器环境无 HERMES_DASH_USER/HERMES_DASH_PASSWORD（C-3 终局：内部通道只剩服务凭据，包 2.5.0）"; else bad "c3-dash-password-env-retired" "容器环境仍有 $DASHENV 行密码登录变量（C-3 未终局）"; fi
if docker exec hermes grep -q 'idem = f"ideas-sum-{int(_now())}"' /opt/hermes/gateway/platforms/oneday_seg_ideas_gen.py 2>/dev/null; then ok "ideas-digest-epoch-key" "点子摘要轮幂等键为轮次 epoch 形态（内容寻址键退役，包 2.5.0）"; else bad "ideas-digest-epoch-key" "摘要轮仍为内容寻址幂等键（409 毒化未除）"; fi
GENM=$(docker exec hermes env 2>/dev/null | grep '^ONEDAY_GEN_MODEL=' | cut -d= -f2)
if [ "$GENM" = "deepseek-v4-pro" ]; then ok "genmodel-funded-route" "生成管线 GEN_MODEL=deepseek-v4-pro（DeepSeek 官方通道，包 2.5.1）"; else bad "genmodel-funded-route" "ONEDAY_GEN_MODEL=$GENM（期望 deepseek-v4-pro；laogou8 通道余额枯竭，见 genkey-fix-20261125.md）"; fi
unk "settings-admin-write-deep" "设置写型验收（一次性测试键 register→set→delete→revoke 全程对账＋白名单外写入被拒）默认不跑; 应用步人工执行并记入 batch3plus-rollout-20261125.md"

# ---- 30. Credential Vault (2.7.0): read-only route/capability probes ----
code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 "$BASE/v1/vault/entries" || true)
if [ "$code" = "401" ]; then ok "vault-route-auth" "无钥 GET /v1/vault/entries → 401"; else bad "vault-route-auth" "应答 $code（期望 401）"; fi
code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 "$BASE/v1/vault/requests" || true)
if [ "$code" = "401" ]; then ok "vault-requests-route-auth" "无钥 GET /v1/vault/requests → 401"; else bad "vault-requests-route-auth" "应答 $code（期望 401）"; fi
CAPS=$(curl -s --max-time 5 -H "Authorization: Bearer $API_KEY" "$BASE/v1/capabilities" || true)
case "$CAPS" in *'"credential_vault": true'*) ok "vault-capability-flag" "features.credential_vault=true" ;; *) bad "vault-capability-flag" "capabilities 未见 credential_vault 位" ;; esac
unk "vault-behavior" "python3 credential_vault_selftest.py 在包内运行；真实 TLS/客户端安全卡联调、日志与备份审查仅部署验收时执行"

# ---- 31. 面板密码登录桥（包 2.8.0, #46）: 路由在位 + 鉴权口径（只读探针） ----
code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 -X POST "$BASE/api/companion/web-login" -H Content-Type:application/json -d '{"password":"verify-probe-wrong"}' || true)
if [ "$code" = "401" ]; then ok "web-login-route" "错密码 POST /api/companion/web-login → 401（路由在位、验密生效）"; else bad "web-login-route" "应答 $code（期望 401）"; fi
code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 -X POST "$BASE/api/env/reveal" -H Content-Type:application/json -d '{"key":"API_SERVER_KEY"}' || true)
if [ "$code" = "401" ]; then ok "env-reveal-route-auth" "无会话 POST /api/env/reveal → 401"; else bad "env-reveal-route-auth" "应答 $code（期望 401）"; fi
CAPS=$(curl -s --max-time 5 -H "Authorization: Bearer $API_KEY" "$BASE/v1/capabilities" || true)
case "$CAPS" in *'"panel_web_login": true'*) ok "web-login-capability-flag" "features.panel_web_login=true" ;; *) bad "web-login-capability-flag" "capabilities 未见 panel_web_login 位" ;; esac
unk "web-login-behavior" "python3 oneday_routes_selftest.py 在包内运行；真实登录全链（新密码→cookie→reveal→models）仅部署验收时执行"
# ---- 32. 2.7.1 线三件回填（包 2.8.0, #47）: 指纹守卫哈希已并入第 2 节回读; 余两件为配置/宿主面探针 ----
if grep -q '^platform_hints:' "$DEPLOY_DIR/data/config.yaml" 2>/dev/null && grep -q 'OneDay app, reached through the gateway' "$DEPLOY_DIR/data/config.yaml" 2>/dev/null; then ok "platform-hint-config" "config.yaml 含 platform_hints.api_server.replace（OneDay 渲染口径，platform-hint-config-patch.py 已应用，包 2.8.0 回填登记）"; else bad "platform-hint-config" "config.yaml 缺 platform_hints 覆盖（上游纯文本提示将压制加粗口径，platform-hint-config-patch.py 未应用）"; fi
if crontab -l 2>/dev/null | grep -q 'prompt-refresh-watcher'; then ok "prompt-refresh-watcher" "宿主 crontab 含 prompt-refresh-watcher 看守行（包 2.8.0 回填登记）"; else unk "prompt-refresh-watcher" "当前用户 crontab 未见 prompt-refresh-watcher 行（看守装在 root crontab 时不可见，人工核）"; fi

# ---- 33. 网页端插件地基（包 2.12.0, #52）: 资产哈希、名册(user 源)、资产路由、启用登记 ----
DASHB="http://127.0.0.1:9119"
PLUG_DIR="$DEPLOY_DIR/data/plugins/oneday-console/dashboard"
if [ -f "$PLUG_DIR/manifest.json" ]; then ok "webplug-manifest" "data/plugins/oneday-console/dashboard/manifest.json 在位（dashboard 官方插件 user 源）"; else bad "webplug-manifest" "插件 manifest 缺失（install 3f 未同步）"; fi
for pair in "manifest.json 0e130068eb5f9498a8c1295a27152ceb8eb7bfc36f68fa796d7205c73831bb3e" "dist/index.js e46bc263bcfadbcb54b180d16e380e4f4f824215ec40321e9eefc95d374218fb" "dist/style.css b7e8fcb88126c60d3c63ab60b1aa0d4ed1456aa6ea57e2182fdd8cd18ed1bbad"; do
  set -- $pair
  got=$(sha256sum "$PLUG_DIR/$1" 2>/dev/null | awk '{print $1}')
  if [ "$got" = "$2" ]; then ok "webplug-hash $1" "数据卷回读与包内登记一致"; else bad "webplug-hash $1" "数据卷: ${got:-读不到}（期望 $2）"; fi
done
if grep -q -- '- oneday-console' "$DEPLOY_DIR/data/config.yaml" 2>/dev/null; then ok "webplug-enabled" "config.yaml plugins.enabled 含 oneday-console（user 源 consent 闸已放行）"; else bad "webplug-enabled" "config.yaml plugins.enabled 未见 oneday-console（插件不会挂载，install 3f 确保未生效）"; fi
REGPLUG=$(curl -s --max-time 5 "$DASHB/api/dashboard/plugins" | python3 -c 'import json,sys
try:
  d = json.load(sys.stdin)
  hit = [p for p in d if p.get("name") == "oneday-console"]
  print(hit[0].get("source", "") if hit else "absent")
except Exception:
  print("error")' 2>/dev/null || echo error)
if [ "$REGPLUG" = "user" ]; then ok "webplug-registry" "GET /api/dashboard/plugins 名册含 oneday-console（source=user）"; else bad "webplug-registry" "名册状态: $REGPLUG（期望 user；absent 查启用登记、error 查 dashboard 9119 可达）"; fi
code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 "$DASHB/dashboard-plugins/oneday-console/dist/index.js" || true)
if [ "$code" = "200" ]; then ok "webplug-asset" "GET /dashboard-plugins/oneday-console/dist/index.js → 200（资产路由在位）"; else bad "webplug-asset" "资产路由应答 $code（期望 200）"; fi
unk "webplug-browser" "真浏览器全链（登录 dashboard → OneDay 标签页渲染 → reveal 换钥 → 待批真数据上屏）属部署验收人工项；服务端等价链（web-login 200＋cookie 属性 Path=/ SameSite=Lax → reveal 200 钥长 64 → /v1/approvals 200）已于包 2.12.0 棒 0 实测留据；浏览器 Origin 闸已由包 2.12.1 修复并由第 34 节行为探针把关（等价链无 Origin、测不出此闸）"

# ---- 34. 网页端 CORS 来源（包 2.12.1, #52 修复）: compose 登记 + Origin 行为探针 ----
if grep -q 'API_SERVER_CORS_ORIGINS=https://hermes.didichou.site' "$DEPLOY_DIR/docker-compose.yml" 2>/dev/null; then ok "webcors-compose" "docker-compose.yml hermes environment 已登记本站来源（install 3g）"; else bad "webcors-compose" "compose 未见 API_SERVER_CORS_ORIGINS 本站登记（install 3g 未生效，浏览器内插件会被网关 CORS 闸空体 403）"; fi
code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 -X POST http://127.0.0.1:8642/api/env/reveal -H 'Origin: https://hermes.didichou.site' -H 'Content-Type: application/json' -d '{"key":"API_SERVER_KEY"}' || true)
if [ "$code" = "401" ]; then ok "webcors-site-origin" "本站 Origin POST /api/env/reveal（无会话）→ 401（已过 CORS 闸、由会话闸应答）"; else bad "webcors-site-origin" "本站 Origin reveal 应答 $code（期望 401；403＝CORS 白名单未生效，查容器 env 与网关重启）"; fi
code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 -X POST http://127.0.0.1:8642/api/env/reveal -H 'Origin: https://foreign.invalid' -H 'Content-Type: application/json' -d '{"key":"API_SERVER_KEY"}' || true)
if [ "$code" = "403" ]; then ok "webcors-foreign-origin" "外部 Origin POST /api/env/reveal → 403（CORS 闸对未登记来源保持拦截）"; else bad "webcors-foreign-origin" "外部 Origin reveal 应答 $code（期望 403；非 403＝白名单口径被放宽，须回滚核查）"; fi

# ---- 35. 网页端棒 1 功能面（包 2.13.0, #53）: 凭据请求主人模式 + 批准裁决面在位（只读探针；API_KEY 沿用文件头既有定义） ----
if [ -n "$API_KEY" ]; then
  code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 -H "Authorization: Bearer $API_KEY" "http://127.0.0.1:8642/v1/vault/requests?status=pending" || true)
  if [ "$code" = "200" ]; then ok "webvault-owner-list" "GET /v1/vault/requests（长钥主人模式）→ 200（棒 1 前长钥恒 404）"; else bad "webvault-owner-list" "vault requests 长钥列表应答 $code（期望 200；404＝主人模式未生效）"; fi
  code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 -H "Authorization: Bearer $API_KEY" "http://127.0.0.1:8642/v1/vault/entries" || true)
  if [ "$code" = "200" ]; then ok "webvault-entries" "GET /v1/vault/entries → 200（凭据库只读面数据源）"; else bad "webvault-entries" "vault entries 应答 $code（期望 200）"; fi
  code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 -H "Authorization: Bearer $API_KEY" "http://127.0.0.1:8642/v1/approvals" || true)
  if [ "$code" = "200" ]; then ok "webapprovals-list" "GET /v1/approvals → 200（批准面数据源；裁决写探针属部署验收人工项，不在只读 verify 内）"; else bad "webapprovals-list" "approvals 应答 $code（期望 200）"; fi
else
  unk "webvault-owner-list" "容器内读不到 API_SERVER_KEY，跳过（部署验收时人工核）"
fi
unk "webbar1-browser" "棒 1 真浏览器目视（批准卡按钮按 choices 渲染、裁决后回读、凭据请求表单提交清值）属部署验收人工项；服务端等价链由部署单实测留据"

# ---- 36. 网页端棒 2 内容三面（包 2.14.0, #54）: 动态/想法/目标数据源只读探针 ----
if [ -n "$API_KEY" ]; then
  code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 -H "Authorization: Bearer $API_KEY" "http://127.0.0.1:8642/v1/write-gate/activity?limit=1" || true)
  if [ "$code" = "200" ]; then ok "webactivity-list" "GET /v1/write-gate/activity → 200（动态·任务流水数据源）"; else bad "webactivity-list" "write-gate activity 应答 $code（期望 200）"; fi
  code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 -H "Authorization: Bearer $API_KEY" "http://127.0.0.1:8642/v1/oneday/feed?days=30" || true)
  if [ "$code" = "200" ]; then ok "webfeed-list" "GET /v1/oneday/feed?days=30 → 200（动态帖数据源）"; else bad "webfeed-list" "oneday feed 应答 $code（期望 200）"; fi
  code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 -H "Authorization: Bearer $API_KEY" "http://127.0.0.1:8642/v1/oneday/ideas" || true)
  if [ "$code" = "200" ]; then ok "webideas-list" "GET /v1/oneday/ideas → 200（想法面数据源）"; else bad "webideas-list" "oneday ideas 应答 $code（期望 200）"; fi
  code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 -H "Authorization: Bearer $API_KEY" "http://127.0.0.1:8642/v1/oneday/goals" || true)
  if [ "$code" = "200" ]; then ok "webgoals-list" "GET /v1/oneday/goals → 200（目标面数据源）"; else bad "webgoals-list" "oneday goals 应答 $code（期望 200）"; fi
else
  unk "webbar2-lists" "容器内读不到 API_SERVER_KEY，跳过（部署验收时人工核）"
fi
unk "webbar2-browser" "棒 2 真浏览器目视（三面真数据渲染、底部导航锚点跳转、网页端新建目标后 App 侧可见的双向对账）属部署验收人工项；服务端等价链由部署单实测留据"

# ---- 37. 网页端棒 3 枢纽面（包 2.15.0, #55）: 台账/审计/规矩/定时数据源只读探针 + /api/jobs 公网接线 ----
if [ -n "$API_KEY" ]; then
  code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 -H "Authorization: Bearer $API_KEY" "http://127.0.0.1:8642/v1/oneday/ledger/summary" || true)
  if [ "$code" = "200" ]; then ok "webledger-summary" "GET /v1/oneday/ledger/summary → 200（枢纽·工作台账摘要数据源）"; else bad "webledger-summary" "ledger summary 应答 $code（期望 200）"; fi
  code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 -H "Authorization: Bearer $API_KEY" "http://127.0.0.1:8642/v1/oneday/ledger" || true)
  if [ "$code" = "200" ]; then ok "webledger-list" "GET /v1/oneday/ledger → 200（台账条目数据源）"; else bad "webledger-list" "ledger 应答 $code（期望 200）"; fi
  code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 -H "Authorization: Bearer $API_KEY" "http://127.0.0.1:8642/v1/write-gate/status" || true)
  if [ "$code" = "200" ]; then ok "webgate-status" "GET /v1/write-gate/status → 200（审计面写闸状态）"; else bad "webgate-status" "write-gate status 应答 $code（期望 200）"; fi
  code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 -H "Authorization: Bearer $API_KEY" "http://127.0.0.1:8642/v1/write-gate/decisions?limit=1" || true)
  if [ "$code" = "200" ]; then ok "webgate-decisions" "GET /v1/write-gate/decisions → 200（决策记录数据源）"; else bad "webgate-decisions" "write-gate decisions 应答 $code（期望 200）"; fi
  code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 -H "Authorization: Bearer $API_KEY" "http://127.0.0.1:8642/v1/write-gate/rules" || true)
  if [ "$code" = "200" ]; then ok "webgate-rules" "GET /v1/write-gate/rules → 200（写闸规矩数据源）"; else bad "webgate-rules" "write-gate rules 应答 $code（期望 200）"; fi
  code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 -H "Authorization: Bearer $API_KEY" "http://127.0.0.1:8642/v1/grants" || true)
  if [ "$code" = "200" ]; then ok "webgrants-list" "GET /v1/grants → 200（授权管理面数据源）"; else bad "webgrants-list" "grants 应答 $code（期望 200）"; fi
  jobs_body=$(curl -s --max-time 8 -H "Authorization: Bearer $API_KEY" "https://hermes.didichou.site/api/jobs" || true)
  if printf '%s' "$jobs_body" | grep -q '"is_system"'; then ok "webjobs-public" "公网 GET /api/jobs（Bearer）→ 200 且含 is_system 投影（nginx = /api/jobs 精确接线已生效、未落 dashboard 9119）"; else bad "webjobs-public" "公网 /api/jobs 未见 is_system 投影（404/无投影＝nginx 精确 location 未应用，查 services/nginx-batch6-apijobs-shape.conf 应用状态）"; fi
else
  unk "webbar3-lists" "容器内读不到 API_SERVER_KEY，跳过（部署验收时人工核）"
fi
unk "webbar3-browser" "棒 3 真浏览器目视（枢纽台账计数与条目下钻、审计决策时间线、规矩逐条撤销后回读、定时任务系统标记）属部署验收人工项；服务端等价链由部署单实测留据"
