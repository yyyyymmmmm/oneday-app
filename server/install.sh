#!/usr/bin/env bash
# hermes-deploy install.sh — 把部署包内的补丁幂等应用到目标 Hermes 部署目录
#
# 用法:
#   ./install.sh <部署目录>            部署目录 = 含 docker-compose.yml 与 patches/ 的目录
#   DRY_RUN=1 ./install.sh <部署目录>  只做检查与差异报告，不写文件、不重启
#
# 纪律（见 RULES.md）:
#   - 先校验目标 Hermes 版本，不符立即停，绝不硬敷
#   - 应用前备份 .bak-YYYYMMDD-deploypkg（同日已有备份不覆盖，保留最早一份）
#   - 补丁文件必须原地改写保 inode（单文件 bind mount 换 inode 会让运行容器钉旧文件、部署假绿）
#   - 新增模块文件（MODULES）: 部署目录缺失时新建（回滚=删除），存在时同补丁口径备份+原地改写；
#     其 compose 挂载行由本脚本幂等确保（改 compose 前同样留 .bak）
#   - 改后以「容器内回读哈希 + 端点健康」双验；任一步失败自动回滚并报错退出
#   - companion 已于包 2.0.0（断桥批五）整容器下线退役：本脚本不再探活它；
#     其 compose 定义/数据/镜像的处置与回滚见 bridge-teardown-rollout-20261125.md。
set -eo pipefail   # 不开 -u: 本机 bash 对空数组 "${arr[@]}" 在 -u 下会误报 unbound（批 2 装机实证，2026-11-22）

PKG_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPLOY_DIR="${1:-${DEPLOY_DIR:-}}"
TARGET_IMAGE="nousresearch/hermes-agent:v0.23.0"
TARGET_VERSION="0.23.0"
BAK_SUFFIX=".bak-$(date +%Y%m%d)-deploypkg"
DRY_RUN="${DRY_RUN:-0}"

# 与 manifest.yaml 同步的补丁清单: 文件名|包内相对路径|容器内路径|期望 sha256
PATCHES=(
  "api_server.py|patches/api_server.py|/opt/hermes/gateway/platforms/api_server.py|a493afb2dc3ab1121716ddd8dc41aec5fc72ab566b94cc6ea216895bcf7464c6"
  "hermes_state_portability.py|patches/hermes_state_portability.py|/opt/hermes/hermes_state_portability.py|6a93ecc83a8b5f059978bd3f2db1d63ea8a2ec30a5790028c89ec90c5b2a1d0c"
  "web_routers_sessions.py|patches/web_routers_sessions.py|/opt/hermes/hermes_cli/web_routers/sessions.py|215cde6e95080f11a4d550cf6d85e6753c339fa096016befc0be7f1bf8c86be0"
)
# 新增模块（部署目录可缺失）: 同上格式
# 注: api_server_runs.py（1.5.0）是上游文件的全文件补丁，但部署目录初始无此文件，
# 故借本通道的首装新建+挂载确保机器落地；应用后与 PATCHES 同口径（原地改写/回滚删文件）。
# react_to_message_tool.py（1.8.0）同此口径（上游全文件补丁、部署目录初始无此文件）；
# self_reaction_pending.py（1.8.0）是包自有新模块。
# fileproc_gateway.py（1.9.0，断桥批一）是包自有新模块（自 companion fileproc 桥平移）。
# write_gate_gateway.py（1.10.0，断桥批二）是包自有新模块（自 companion write_gate 桥拆壳入关）。
# oneday_memory.py（1.11.0，§439）是包自有新模块（OneDay 分层记忆服务面）。
# system_prompt.py（1.12.0，§442）是上游装配文件的全文件补丁，部署目录初始无此文件，借本通道落地（api_server_runs 先例）；
# oneday_prompt.py（1.12.0，§442）是包自有新模块（第一层提示词正文＋identity.json 渲染）。
# settings_registry.py（1.13.0，§435 一期）是包自有新模块（设置注册表只读下发）。
# oneday_semantic.py（1.14.0，§445）是包自有新模块（记忆语义召回：本地嵌入＋混合排序）；
# 其运行时依赖 fastembed 与模型快照不随包走，由 3e 节装进 data 卷持久目录。
# skill_admission_gate.py（1.18.0，§444）是包自有新模块（技能准入硬闸，挂 tools 层）；
# skill_manager_tool.py（1.18.0，§444）是上游文件的全文件补丁（_guarded_write +13 行挂点，
# 上游基线 sha256 67df9575…），部署目录初始无此文件，借本通道落地（system_prompt.py 先例）。
# 回执运行时化（1.20.0）：api_server_runs.py（状态机＋判定器＋审计简化）、
# api_server.py（提醒改判＋委托转发 session_id）、oneday_prompt.py（Receipts
# 段改判）、react_to_message_tool.py（schema case (2) 改判）四件换哈希，
# 无新增模块；self_reaction_pending.py 不变。
# web_routers_profiles.py / web_routers_ops.py（1.23.0，中枢数据四件）是上游
# Dashboard 路由文件的全文件补丁（soul 回执 updatedAt / memory 回执
# builtin_files_updated_at），部署目录初始无此二文件，借 MODULES 通道落地
# （api_server_runs 先例）。
# device_sync.py / device_gateway.py（2.0.0，断桥批五·终局）是包自有新模块：
# 自 companion device 桥整搬入关——device_sync.py 为桥侧同步库逐字平移（与退役前
# 在役件同哈希 f2312d0c…，数据语义零漂移）；device_gateway.py 为桥引擎逐字保留
# ＋网关传输 shim，鉴权改单钥 API_SERVER_KEY（桥钥 DEVICE_BRIDGE_KEY 退役），
# 数据目录 DEVICE_DATA_DIR（默认 /opt/data/device）。companion 容器随本版下线。
# oneday_gateway.py / overview_gateway.py / oneday_ledger_lib.py /
# oneday_seg_*.py / NotoSansSC-subset.ttf（1.19.0，断桥批三）是包自有
# 新模块：自 companion oneday/overview 两桥拆壳入关（分段在容器内
# platforms/ 同目录，由 oneday_gateway.py 以 _load_segment
# 汇入同一命名空间）；字体是台账 PDF 渲染子集，随分段目录同置。
# identity_gateway.py / front_gateway.py（2.3.0，断桥批四）是包自有新模块：
# 自 companion identity 桥（8648）与 front 只读面（8650）拆壳入关——
# identity_gateway 为桥业务函数逐字平移＋dispatch 上下文适配（原件覆盖事故后
# 按登记接口重建，应用前已过函数级 AST 对账终验）；front_gateway 为
# connections/gateway-channels 只读两面（C-2 方案 b：凭据服务器侧录入、
# 公开视图零机密、渠道 key 零出模块）。api_server.py 相对 2.2.0 件 +126 行
# 纯增（identity 通配挂载＋保形口＋POST /mcp/identity＋front 只读两面＋
# features identity_gateway/front_readonly 两位）。companion 半边（1.0.78）
# 随 companion 2.0.0 整容器退役整体作废，本版只做网关半边。
# options_pending.py / present_options_tool.py（2.2.0，§441 选择框潜伏）
# 是包自有新模块：options_pending 为待挂选项存储＋校验单源＋attach
# 单事务 RMW 原语；present_options_tool 为 present_options 工具
# （registry-only、新工具集 options_card）。本版只潜伏：instance
# config 的 display.options_card 闸默认关、platform_toolsets.api_server
# 未加 options_card 工具集，工具不注册、行为零变化；翻闸属另一步。
MODULES=(
  "approval_projection.py|patches/approval_projection.py|/opt/hermes/gateway/platforms/approval_projection.py|fbebf958392225c46eb34dcc62a673949b0d68fc314537144f25902e56e2c7ff"
  "grant_projection.py|patches/grant_projection.py|/opt/hermes/gateway/platforms/grant_projection.py|e1e29b3601f481a7792c2b71291053dd8dcd2d7da0df2773673e38273d0d41f2"
  "api_server_runs.py|patches/api_server_runs.py|/opt/hermes/gateway/platforms/api_server_runs.py|79edb80b9a07f6d339609de1bad4b14d59104bd98817121a99bfd19dc7399d8a"
  "crash_reports.py|patches/crash_reports.py|/opt/hermes/gateway/platforms/crash_reports.py|f74a7424e46bf02100a9e054882b7d1b8219e3a56859ec94482441ef5678f510"
  "fileproc_gateway.py|patches/fileproc_gateway.py|/opt/hermes/gateway/platforms/fileproc_gateway.py|96654ddddebd33633c9c77c4a363545ea227b0cb1ef01e1d9c100af43ede914c"
  "device_sync.py|patches/device_sync.py|/opt/hermes/gateway/platforms/device_sync.py|f2312d0caed820646a738c181b0e646c576ff22500b9c76d13f16960393bd838"
  "device_gateway.py|patches/device_gateway.py|/opt/hermes/gateway/platforms/device_gateway.py|41ec82462c947408b2dc379b6b0e25ced9702db00d948bcdb127197588c7b06a"
  "identity_gateway.py|patches/identity_gateway.py|/opt/hermes/gateway/platforms/identity_gateway.py|91ca959513e078db3dbfe2220262558b45f3a2ec8793c32f50789cf5a926578c"
  "front_gateway.py|patches/front_gateway.py|/opt/hermes/gateway/platforms/front_gateway.py|857e88becb5e534130f0d47a7ad71a2814a244a54a42e1e9deaed8abed6df5bf"
  "react_to_message_tool.py|patches/react_to_message_tool.py|/opt/hermes/tools/react_to_message_tool.py|703164714fae87674635581a30671cb231a41926121bc6fdcf5af4432e35357e"
  "self_reaction_pending.py|patches/self_reaction_pending.py|/opt/hermes/gateway/platforms/self_reaction_pending.py|972577870fb0cb0d60b4d5535324b4cba5f5f15c178760dcdc9b92f6c0ddf626"
  "write_gate_gateway.py|patches/write_gate_gateway.py|/opt/hermes/gateway/platforms/write_gate_gateway.py|a0682135c7591193ed10eb340340d416a9c5de3350ada498d3077cdfb08ce58b"
  "oneday_memory.py|patches/oneday_memory.py|/opt/hermes/gateway/platforms/oneday_memory.py|43dea21475b7bb24724c1787ff19f93403fba4666826b40e0828d3864a383d44"
  "system_prompt.py|patches/system_prompt.py|/opt/hermes/agent/system_prompt.py|7d558e89af41ee492ae85b681f9e7f4a347c728c58818c8ea76fbec776bcc05f"
  "oneday_prompt.py|patches/oneday_prompt.py|/opt/hermes/agent/oneday_prompt.py|bafc6c3ca7597f348b6eeec5b76153e9ad8e04dc02278695aff55f03ed766227"
  "settings_registry.py|patches/settings_registry.py|/opt/hermes/gateway/platforms/settings_registry.py|0478458bdd5b9a2873471cbbcbb1e3efba7568fe3d01b6bda169c99b1cff78e5"
  "settings_admin.py|patches/settings_admin.py|/opt/hermes/gateway/platforms/settings_admin.py|3057cbc2b1771d42dfd084e6ac9c5152e82be2f22c764b798d463fdf1d33f1cb"
  "settings_admin_tool.py|patches/settings_admin_tool.py|/opt/hermes/tools/settings_admin_tool.py|7d53eeae0816b8d3e751e2e6e96c2f79cb960536d112e2dba644a5a1c16f3815"
  "oneday_semantic.py|patches/oneday_semantic.py|/opt/hermes/gateway/platforms/oneday_semantic.py|930265087b9a4ced35aacf83ca2c8f4bd1d29b6551fd692290c2b33e83c17bf1"
  "skill_admission_gate.py|patches/skill_admission_gate.py|/opt/hermes/tools/skill_admission_gate.py|e9c1ba18f93ecc1fac8056f68e75b7c98a51cdd447b3859b53f9b820037831c7"
  "skill_manager_tool.py|patches/skill_manager_tool.py|/opt/hermes/tools/skill_manager_tool.py|693b9a716fafad83b14c33ed971256b5f918e2eaccd70cc9c6d23297c9f29693"
  "oneday_gateway.py|patches/oneday_gateway.py|/opt/hermes/gateway/platforms/oneday_gateway.py|82755461e014e89bf1ebd8d96cb68501d77edb747185d3cc3b04db4f1b17434b"
  "overview_gateway.py|patches/overview_gateway.py|/opt/hermes/gateway/platforms/overview_gateway.py|0fabe764c8fe626462e7c76738518791c2e3c238cd919e21a5e39068d932bc5b"
  "oneday_ledger_lib.py|patches/oneday_ledger_lib.py|/opt/hermes/gateway/platforms/oneday_ledger_lib.py|5ee8bc91d6c39ad9cc807e88d5add196ef04593bb760fa3d5739f562c04a6566"
  "oneday_seg_automation.py|patches/oneday_seg_automation.py|/opt/hermes/gateway/platforms/oneday_seg_automation.py|b10453f970ffc3d1a61969462419b5162764d1f57154d6489ec705cbd861502d"
  "oneday_seg_briefings.py|patches/oneday_seg_briefings.py|/opt/hermes/gateway/platforms/oneday_seg_briefings.py|f9fc273c9a0d142f57541ba1c2a5708ada333f976c1ab79a67c64236a3e77440"
  "oneday_seg_cron.py|patches/oneday_seg_cron.py|/opt/hermes/gateway/platforms/oneday_seg_cron.py|1027673950195efdced445677ea57d009c988ac7b8e3a8cb5ef090a25e191de7"
  "oneday_seg_delivery.py|patches/oneday_seg_delivery.py|/opt/hermes/gateway/platforms/oneday_seg_delivery.py|08bd159801f3b9a9ca9c2d747676117d726251ddddb8646e83527b4490ac0954"
  "oneday_seg_feed.py|patches/oneday_seg_feed.py|/opt/hermes/gateway/platforms/oneday_seg_feed.py|b305c244437ff0e061c4a76a24a8be32e0da9831b9ebb7eaa55dd8d50956f39a"
  "oneday_seg_filelibrary.py|patches/oneday_seg_filelibrary.py|/opt/hermes/gateway/platforms/oneday_seg_filelibrary.py|f6586b45029814471f3401f6514a9b740cedfa868ca08ef366e405eb1d82ae28"
  "oneday_seg_goals.py|patches/oneday_seg_goals.py|/opt/hermes/gateway/platforms/oneday_seg_goals.py|59388a1ac78d82bc1a173d0f0b4c03d2fe95735c611079da81007f9f224aa29a"
  "oneday_seg_goals_activity.py|patches/oneday_seg_goals_activity.py|/opt/hermes/gateway/platforms/oneday_seg_goals_activity.py|f5ee4f564b5182acc30f27f091ccf386f7e84e17d7a36801c7b77a3368e8efcb"
  "oneday_seg_goals_facade.py|patches/oneday_seg_goals_facade.py|/opt/hermes/gateway/platforms/oneday_seg_goals_facade.py|f4237fe1b69c4febdab61db31ad6473fabdc449bde7b97181c23dd9f9a06f352"
  "oneday_seg_ideas_gen.py|patches/oneday_seg_ideas_gen.py|/opt/hermes/gateway/platforms/oneday_seg_ideas_gen.py|7f2d33df2e80b0fa7ec4f761ad957c0892723bb8ca09781d0f2dd7bfbcfc148d"
  "oneday_seg_ideas_pool.py|patches/oneday_seg_ideas_pool.py|/opt/hermes/gateway/platforms/oneday_seg_ideas_pool.py|762480db46114f18d8d468ee10d30233d3c585fa8e82f9049983eaa5633d3ad4"
  "oneday_seg_ledger.py|patches/oneday_seg_ledger.py|/opt/hermes/gateway/platforms/oneday_seg_ledger.py|768bd29f4ff5d8c8e9408fbdc938241fa33d8cbb873551f090a100199fd5b801"
  "oneday_seg_library_mcp.py|patches/oneday_seg_library_mcp.py|/opt/hermes/gateway/platforms/oneday_seg_library_mcp.py|29aaf48abbc66a13cc1aed43a8ba609ac88022b2ea82a576246cfdbbeadd3edd"
  "oneday_seg_monitors.py|patches/oneday_seg_monitors.py|/opt/hermes/gateway/platforms/oneday_seg_monitors.py|fb33eb391c5382196398a02a2300a885ea9d957b0c41560f6092a528b3bc1a07"
  "oneday_seg_sessions.py|patches/oneday_seg_sessions.py|/opt/hermes/gateway/platforms/oneday_seg_sessions.py|5fef89da32d675d079259f0345ed328484d3649349cca99b71eb6b5a4e57838d"
  "oneday_seg_traces.py|patches/oneday_seg_traces.py|/opt/hermes/gateway/platforms/oneday_seg_traces.py|ebc6b07fde26e30a9827c32ca7755bd5b423938ba270f53ba9fa70d2acff0d9c"
  "NotoSansSC-subset.ttf|patches/NotoSansSC-subset.ttf|/opt/hermes/gateway/platforms/assets/NotoSansSC-subset.ttf|695c95a196eae0764aa5d4325aebaff38e5f22dfa9050e0e3930181b3a5ded6e"
  "web_routers_profiles.py|patches/web_routers_profiles.py|/opt/hermes/hermes_cli/web_routers/profiles.py|fda69d721249115ac7e8e41d699e15b8757838adb5ff18b2aa367de3e302c775"
  "web_routers_ops.py|patches/web_routers_ops.py|/opt/hermes/hermes_cli/web_routers/ops.py|ceac7c0dbfe627248c1aa5f9857c5a6fa21dd6ecde0f7a53390dbf6b84a45481"
  "options_pending.py|patches/options_pending.py|/opt/hermes/gateway/platforms/options_pending.py|546f5f432ca4f6900b6b5577b4255ba02de3ab663fd2f78036fa07d11e45bc38"
  "present_options_tool.py|patches/present_options_tool.py|/opt/hermes/tools/present_options_tool.py|f8400d1cc3897a13eed2a7b16de72a7c46bbf392d506fc6c891e4247a9de785e"
  "cron_projection.py|patches/cron_projection.py|/opt/hermes/gateway/platforms/cron_projection.py|0a3ef6684a29e6fccd1af4529aba22d34a65e63bdc702a7c0a8d42755f155ae6"
  "api_server_oneday_routes.py|patches/api_server_oneday_routes.py|/opt/hermes/gateway/platforms/api_server_oneday_routes.py|bbe97478781282b69cc5c615d3a954b10dadeec3a94087b3b9a54586a78391ed"
  "auth_tokens.py|patches/auth_tokens.py|/opt/hermes/gateway/platforms/auth_tokens.py|9291e5ca9495f8d676cc9076b368e1c7e383e4c49fb5902ff9c6bf1f9555c85a"
  "push_tokens.py|patches/push_tokens.py|/opt/hermes/gateway/platforms/push_tokens.py|e01a5cdd1520f7a2af5d7b69c5bad4a341242f42452dd6e771693e76d68de8fe"
  "push_sender.py|patches/push_sender.py|/opt/hermes/gateway/platforms/push_sender.py|ca47d28826126b9d2f848af0a063f43e963389df675208cd8aa50a4c025fc865"
  "db_schema_guard.py|patches/db_schema_guard.py|/opt/hermes/gateway/platforms/db_schema_guard.py|040a19b476de75195e13600fdea9e11419f97c62a237d3e88af9d21bc842d05b"
  "credential_vault.py|patches/credential_vault.py|/opt/hermes/gateway/platforms/credential_vault.py|ed95fcaf15a04abce54a68443e69d455ab3f9ba0cee3b42db4d292e2624e52f0"
  "credential_vault_tool.py|patches/credential_vault_tool.py|/opt/hermes/tools/credential_vault_tool.py|ea9f55ebda3e8802c20385c0be9541921c3f1d6e9fb024396d69c9d50d8b50eb"
)
# 模块所需的 compose 挂载（hermes 服务 volumes 内，幂等确保）见 3b 节 specs

log() { printf '[install] %s\n' "$*"; }
die() { printf '[install] ERROR: %s\n' "$*" >&2; exit 1; }
sha_of() { sha256sum "$1" | awk '{print $1}'; }
inode_of() { stat -c %i "$1" 2>/dev/null || stat -f %i "$1"; }

CHANGED_FILES=()
CREATED_FILES=()
COMPOSE_CHANGED=0
ROLLBACK_ARMED=0

rollback() {
  log "触发回滚：恢复 ${#CHANGED_FILES[@]} 个已改文件、删除 ${#CREATED_FILES[@]} 个新建文件"
  for f in "${CHANGED_FILES[@]}"; do
    local bak="$DEPLOY_DIR/patches/$f$BAK_SUFFIX"
    if [ -f "$bak" ]; then
      cat "$bak" > "$DEPLOY_DIR/patches/$f"
      log "已回滚 $f"
    else
      log "警告：$f 无备份可回滚"
    fi
  done
  for f in "${CREATED_FILES[@]}"; do
    rm -f "$DEPLOY_DIR/patches/$f"
    log "已删除新建文件 $f"
  done
  if [ "$COMPOSE_CHANGED" = "1" ]; then
    local cbak="$DEPLOY_DIR/docker-compose.yml$BAK_SUFFIX"
    if [ -f "$cbak" ]; then
      cat "$cbak" > "$DEPLOY_DIR/docker-compose.yml"
      log "已回滚 docker-compose.yml"
    fi
  fi
  docker restart hermes >/dev/null 2>&1 || true
  log "回滚完成（容器已重启），请人工复核后再重试"
}

on_error() {
  local rc=$?
  if [ "$ROLLBACK_ARMED" = "1" ]; then rollback; fi
  exit $rc
}
trap on_error ERR

# ---------- 1. 前置检查 ----------
[ -n "$DEPLOY_DIR" ] || die "用法: ./install.sh <部署目录>"
[ -f "$DEPLOY_DIR/docker-compose.yml" ] || die "部署目录缺少 docker-compose.yml: $DEPLOY_DIR"
[ -d "$DEPLOY_DIR/patches" ] || die "部署目录缺少 patches/: $DEPLOY_DIR"
command -v docker >/dev/null || die "未找到 docker"
command -v sha256sum >/dev/null || die "未找到 sha256sum"

# 内存红线：>=80% 立即停
MEM_PCT=$(free | awk '/^Mem:/ {printf "%d", ($2 > 0) ? ($3 * 100 / $2) : 0}')
[ "$MEM_PCT" -lt 80 ] || die "内存使用率 ${MEM_PCT}% >= 80%，按红线停手"
log "内存使用率 ${MEM_PCT}%（<80%，可继续）"

# 目标版本校验：compose 中 hermes 镜像必须等于包 target
grep -q "image: $TARGET_IMAGE" "$DEPLOY_DIR/docker-compose.yml" || die "compose 中 hermes 镜像不是 $TARGET_IMAGE，版本不符，停手（升级口径见 RULES.md）"
if docker inspect hermes >/dev/null 2>&1; then
  RUNNING_IMAGE=$(docker inspect hermes --format '{{.Config.Image}}')
  [ "$RUNNING_IMAGE" = "$TARGET_IMAGE" ] || die "运行中 hermes 容器镜像为 $RUNNING_IMAGE，与包 target $TARGET_IMAGE 不符，停手"
fi
log "目标版本校验通过：$TARGET_IMAGE"

# ---------- 2. 差异盘点（幂等核心） ----------
TO_APPLY=()
for entry in "${PATCHES[@]}"; do
  IFS='|' read -r name src_rel _cpath want_sha <<< "$entry"
  src="$PKG_DIR/$src_rel"
  dst="$DEPLOY_DIR/patches/$name"
  [ -f "$src" ] || die "包内缺文件: $src_rel"
  [ "$(sha_of "$src")" = "$want_sha" ] || die "包内文件哈希与 manifest 不符: $name（包已损坏或清单过期）"
  [ -f "$dst" ] || die "部署目录缺目标文件: patches/$name"
  if [ "$(sha_of "$dst")" = "$want_sha" ]; then
    log "已是目标状态，跳过: $name"
  else
    TO_APPLY+=("$entry")
    log "待应用: $name"
  fi
done

MODULES_TO_APPLY=()
MODULES_TO_CREATE=()
for entry in "${MODULES[@]}"; do
  IFS='|' read -r name src_rel _cpath want_sha <<< "$entry"
  src="$PKG_DIR/$src_rel"
  dst="$DEPLOY_DIR/patches/$name"
  [ -f "$src" ] || die "包内缺模块文件: $src_rel"
  [ "$(sha_of "$src")" = "$want_sha" ] || die "包内模块哈希与 manifest 不符: $name（包已损坏或清单过期）"
  if [ ! -f "$dst" ]; then
    MODULES_TO_CREATE+=("$entry")
    log "待新建模块: $name"
  elif [ "$(sha_of "$dst")" = "$want_sha" ]; then
    log "模块已是目标状态，跳过: $name"
  else
    MODULES_TO_APPLY+=("$entry")
    log "待应用模块: $name"
  fi
done

COMPOSE_NEEDS_MOUNT=0
grep -q "approval_projection.py" "$DEPLOY_DIR/docker-compose.yml" || COMPOSE_NEEDS_MOUNT=1
grep -q "grant_projection.py" "$DEPLOY_DIR/docker-compose.yml" || COMPOSE_NEEDS_MOUNT=1
grep -q "api_server_runs.py" "$DEPLOY_DIR/docker-compose.yml" || COMPOSE_NEEDS_MOUNT=1
grep -q "crash_reports.py" "$DEPLOY_DIR/docker-compose.yml" || COMPOSE_NEEDS_MOUNT=1
grep -q "fileproc_gateway.py" "$DEPLOY_DIR/docker-compose.yml" || COMPOSE_NEEDS_MOUNT=1
grep -q "device_sync.py" "$DEPLOY_DIR/docker-compose.yml" || COMPOSE_NEEDS_MOUNT=1
grep -q "device_gateway.py" "$DEPLOY_DIR/docker-compose.yml" || COMPOSE_NEEDS_MOUNT=1
grep -q "identity_gateway.py" "$DEPLOY_DIR/docker-compose.yml" || COMPOSE_NEEDS_MOUNT=1
grep -q "front_gateway.py" "$DEPLOY_DIR/docker-compose.yml" || COMPOSE_NEEDS_MOUNT=1
grep -q "react_to_message_tool.py" "$DEPLOY_DIR/docker-compose.yml" || COMPOSE_NEEDS_MOUNT=1
grep -q "self_reaction_pending.py" "$DEPLOY_DIR/docker-compose.yml" || COMPOSE_NEEDS_MOUNT=1
grep -q "write_gate_gateway.py" "$DEPLOY_DIR/docker-compose.yml" || COMPOSE_NEEDS_MOUNT=1
grep -q "oneday_memory.py" "$DEPLOY_DIR/docker-compose.yml" || COMPOSE_NEEDS_MOUNT=1
grep -q "system_prompt.py" "$DEPLOY_DIR/docker-compose.yml" || COMPOSE_NEEDS_MOUNT=1
grep -q "oneday_prompt.py" "$DEPLOY_DIR/docker-compose.yml" || COMPOSE_NEEDS_MOUNT=1
grep -q "settings_registry.py" "$DEPLOY_DIR/docker-compose.yml" || COMPOSE_NEEDS_MOUNT=1
grep -q "settings_admin.py" "$DEPLOY_DIR/docker-compose.yml" || COMPOSE_NEEDS_MOUNT=1
grep -q "settings_admin_tool.py" "$DEPLOY_DIR/docker-compose.yml" || COMPOSE_NEEDS_MOUNT=1
grep -q "oneday_semantic.py" "$DEPLOY_DIR/docker-compose.yml" || COMPOSE_NEEDS_MOUNT=1
grep -q "ONEDAY_SEM_CACHE" "$DEPLOY_DIR/docker-compose.yml" || COMPOSE_NEEDS_MOUNT=1
grep -q "skill_admission_gate.py" "$DEPLOY_DIR/docker-compose.yml" || COMPOSE_NEEDS_MOUNT=1
grep -q "skill_manager_tool.py" "$DEPLOY_DIR/docker-compose.yml" || COMPOSE_NEEDS_MOUNT=1
grep -q "oneday_gateway.py" "$DEPLOY_DIR/docker-compose.yml" || COMPOSE_NEEDS_MOUNT=1
grep -q "web_routers_profiles.py" "$DEPLOY_DIR/docker-compose.yml" || COMPOSE_NEEDS_MOUNT=1
grep -q "web_routers_ops.py" "$DEPLOY_DIR/docker-compose.yml" || COMPOSE_NEEDS_MOUNT=1
grep -q "options_pending.py" "$DEPLOY_DIR/docker-compose.yml" || COMPOSE_NEEDS_MOUNT=1
grep -q "present_options_tool.py" "$DEPLOY_DIR/docker-compose.yml" || COMPOSE_NEEDS_MOUNT=1
grep -q "cron_projection.py" "$DEPLOY_DIR/docker-compose.yml" || COMPOSE_NEEDS_MOUNT=1
grep -q "api_server_oneday_routes.py" "$DEPLOY_DIR/docker-compose.yml" || COMPOSE_NEEDS_MOUNT=1
grep -q "auth_tokens.py" "$DEPLOY_DIR/docker-compose.yml" || COMPOSE_NEEDS_MOUNT=1
grep -q "push_tokens.py" "$DEPLOY_DIR/docker-compose.yml" || COMPOSE_NEEDS_MOUNT=1
grep -q "push_sender.py" "$DEPLOY_DIR/docker-compose.yml" || COMPOSE_NEEDS_MOUNT=1
grep -q "db_schema_guard.py" "$DEPLOY_DIR/docker-compose.yml" || COMPOSE_NEEDS_MOUNT=1
grep -q "credential_vault.py" "$DEPLOY_DIR/docker-compose.yml" || COMPOSE_NEEDS_MOUNT=1
grep -q "credential_vault_tool.py" "$DEPLOY_DIR/docker-compose.yml" || COMPOSE_NEEDS_MOUNT=1
grep -q "overview_gateway.py" "$DEPLOY_DIR/docker-compose.yml" || COMPOSE_NEEDS_MOUNT=1
grep -q "oneday_seg_goals.py" "$DEPLOY_DIR/docker-compose.yml" || COMPOSE_NEEDS_MOUNT=1
grep -q "device-data" "$DEPLOY_DIR/docker-compose.yml" || COMPOSE_NEEDS_MOUNT=1
[ "$COMPOSE_NEEDS_MOUNT" = "0" ] || log "compose 待加模块挂载行"

# 记忆资产待铺计数（§439）：种子/技能文件缺失数 + cron 作业未合并数（只数不写）
ASSETS_PENDING=0
if [ -d "$PKG_DIR/seed-memory" ]; then
  while IFS= read -r -d '' f; do
    rel="${f#$PKG_DIR/seed-memory/}"
    case "$rel" in
      README-SEED.md|config-memory-snippet.yaml) continue ;;
    esac
    [ -f "$DEPLOY_DIR/data/$rel" ] || ASSETS_PENDING=$((ASSETS_PENDING+1))
  done < <(find "$PKG_DIR/seed-memory" -type f -print0)
  cron_missing=0
  for frag in oneday-memory-jobs.json oneday-goals-jobs.json; do
    [ -f "$PKG_DIR/cron/$frag" ] || continue
    n=$(python3 - "$DEPLOY_DIR/data/cron/jobs.json" "$PKG_DIR/cron/$frag" << 'PYEOF'
import json, sys
try:
    raw = json.load(open(sys.argv[1]))
    have = {j.get("id") for j in (raw.get("jobs", []) if isinstance(raw, dict) else raw)}
except Exception:
    have = set()
want = {j.get("id") for j in json.load(open(sys.argv[2]))}
print(len(want - have))
PYEOF
)
    cron_missing=$((cron_missing + n))
  done
  ASSETS_PENDING=$((ASSETS_PENDING + cron_missing))
  [ "$ASSETS_PENDING" = "0" ] || log "记忆资产待铺: $ASSETS_PENDING 项（种子/技能/cron）"
fi

# 语义检索运行时状态（§445）：依赖与模型不在文件哈希口径内，单独探——
# 任一未就绪都不许走「无需应用」早退，否则 3e 永远达不到（1.14.0 首装实证）。
SEM_READY=0
docker exec -e PYTHONPATH=/opt/data/python-packages hermes python3 -c "import fastembed" >/dev/null 2>&1 && SEM_READY=1
SEM_MODEL_READY=0
docker exec hermes sh -c "ls /opt/data/cache/fastembed 2>/dev/null | grep -q ." >/dev/null 2>&1 && SEM_MODEL_READY=1
[ "$SEM_READY" = "1" ] || log "语义检索依赖未就绪（3e 待装）"
[ "$SEM_MODEL_READY" = "1" ] || log "语义模型快照未就绪（3e 待预取）"

if [ "${#TO_APPLY[@]}" = "0" ] && [ "${#MODULES_TO_APPLY[@]}" = "0" ] && \
   [ "${#MODULES_TO_CREATE[@]}" = "0" ] && [ "$COMPOSE_NEEDS_MOUNT" = "0" ] && \
   [ "$ASSETS_PENDING" = "0" ] && [ "$SEM_READY" = "1" ] && [ "$SEM_MODEL_READY" = "1" ]; then
  log "全部补丁与模块已是目标状态，无需应用、不重启（幂等）"
  exit 0
fi
if [ "$DRY_RUN" = "1" ]; then
  log "DRY_RUN：补丁 ${#TO_APPLY[@]} 个、模块更新 ${#MODULES_TO_APPLY[@]} 个、模块新建 ${#MODULES_TO_CREATE[@]} 个、compose 挂载变更 ${COMPOSE_NEEDS_MOUNT}、记忆资产待铺 ${ASSETS_PENDING} 项、语义依赖就绪 ${SEM_READY}、语义模型就绪 ${SEM_MODEL_READY}（未写、未重启）"
  exit 0
fi

# ---------- 3. 备份 + 原地改写 ----------
ROLLBACK_ARMED=1
apply_one() {
  local name="$1" src_rel="$2" want_sha="$3"
  local src="$PKG_DIR/$src_rel"
  local dst="$DEPLOY_DIR/patches/$name"
  local bak="$dst$BAK_SUFFIX"
  if [ ! -f "$bak" ]; then
    cp -a "$dst" "$bak"
    log "已备份: patches/$name$BAK_SUFFIX"
  else
    log "备份已存在（保留最早一份）: patches/$name$BAK_SUFFIX"
  fi
  local before_inode after_inode
  before_inode=$(inode_of "$dst")
  cat "$src" > "$dst"   # 原地截断改写，保 inode
  after_inode=$(inode_of "$dst")
  [ "$before_inode" = "$after_inode" ] || die "$name 应用后 inode 变化（$before_inode -> $after_inode），bind mount 可能钉旧文件"
  [ "$(sha_of "$dst")" = "$want_sha" ] || die "$name 应用后哈希不符"
  CHANGED_FILES+=("$name")
  log "已应用: $name"
}
for entry in "${TO_APPLY[@]}"; do
  IFS='|' read -r name src_rel _cpath want_sha <<< "$entry"
  apply_one "$name" "$src_rel" "$want_sha"
done
for entry in "${MODULES_TO_APPLY[@]}"; do
  IFS='|' read -r name src_rel _cpath want_sha <<< "$entry"
  apply_one "$name" "$src_rel" "$want_sha"
done
for entry in "${MODULES_TO_CREATE[@]}"; do
  IFS='|' read -r name src_rel _cpath want_sha <<< "$entry"
  cat "$PKG_DIR/$src_rel" > "$DEPLOY_DIR/patches/$name"
  [ "$(sha_of "$DEPLOY_DIR/patches/$name")" = "$want_sha" ] || die "模块 $name 新建后哈希不符"
  CREATED_FILES+=("$name")
  log "已新建模块: $name"
done

# ---------- 3b. compose 挂载确保 ----------
if [ "$COMPOSE_NEEDS_MOUNT" = "1" ]; then
  compose_file="$DEPLOY_DIR/docker-compose.yml"
  cbak="$compose_file$BAK_SUFFIX"
  if [ ! -f "$cbak" ]; then
    cp -a "$compose_file" "$cbak"
    log "已备份: docker-compose.yml$BAK_SUFFIX"
  fi
  COMPOSE_CHANGED=1
  python3 - "$compose_file" << 'PYEOF'
import sys
path = sys.argv[1]
# (module filename, mount line, anchor substring) -- processed in order;
# a later spec may anchor on a line inserted by an earlier one.
specs = [
    ("approval_projection.py",
     "      - ./patches/approval_projection.py:/opt/hermes/gateway/platforms/approval_projection.py:ro",
     "./patches/api_server.py:/opt/hermes/gateway/platforms/api_server.py:ro"),
    ("grant_projection.py",
     "      - ./patches/grant_projection.py:/opt/hermes/gateway/platforms/grant_projection.py:ro",
     "./patches/approval_projection.py:/opt/hermes/gateway/platforms/approval_projection.py:ro"),
    ("api_server_runs.py",
     "      - ./patches/api_server_runs.py:/opt/hermes/gateway/platforms/api_server_runs.py:ro",
     "./patches/api_server.py:/opt/hermes/gateway/platforms/api_server.py:ro"),
    ("crash_reports.py",
     "      - ./patches/crash_reports.py:/opt/hermes/gateway/platforms/crash_reports.py:ro",
     "./patches/grant_projection.py:/opt/hermes/gateway/platforms/grant_projection.py:ro"),
    ("fileproc_gateway.py",
     "      - ./patches/fileproc_gateway.py:/opt/hermes/gateway/platforms/fileproc_gateway.py:ro",
     "./patches/crash_reports.py:/opt/hermes/gateway/platforms/crash_reports.py:ro"),
    ("device_sync.py",
     "      - ./patches/device_sync.py:/opt/hermes/gateway/platforms/device_sync.py:ro",
     "./patches/fileproc_gateway.py:/opt/hermes/gateway/platforms/fileproc_gateway.py:ro"),
    ("device_gateway.py",
     "      - ./patches/device_gateway.py:/opt/hermes/gateway/platforms/device_gateway.py:ro",
     "./patches/device_sync.py:/opt/hermes/gateway/platforms/device_sync.py:ro"),
    ("react_to_message_tool.py",
     "      - ./patches/react_to_message_tool.py:/opt/hermes/tools/react_to_message_tool.py:ro",
     "./patches/api_server.py:/opt/hermes/gateway/platforms/api_server.py:ro"),
    ("self_reaction_pending.py",
     "      - ./patches/self_reaction_pending.py:/opt/hermes/gateway/platforms/self_reaction_pending.py:ro",
     "./patches/crash_reports.py:/opt/hermes/gateway/platforms/crash_reports.py:ro"),
    ("write_gate_gateway.py",
     "      - ./patches/write_gate_gateway.py:/opt/hermes/gateway/platforms/write_gate_gateway.py:ro",
     "./patches/crash_reports.py:/opt/hermes/gateway/platforms/crash_reports.py:ro"),
    ("oneday_memory.py",
     "      - ./patches/oneday_memory.py:/opt/hermes/gateway/platforms/oneday_memory.py:ro",
     "./patches/write_gate_gateway.py:/opt/hermes/gateway/platforms/write_gate_gateway.py:ro"),
    ("system_prompt.py",
     "      - ./patches/system_prompt.py:/opt/hermes/agent/system_prompt.py:ro",
     "./patches/oneday_memory.py:/opt/hermes/gateway/platforms/oneday_memory.py:ro"),
    ("oneday_prompt.py",
     "      - ./patches/oneday_prompt.py:/opt/hermes/agent/oneday_prompt.py:ro",
     "./patches/system_prompt.py:/opt/hermes/agent/system_prompt.py:ro"),
    ("settings_registry.py",
     "      - ./patches/settings_registry.py:/opt/hermes/gateway/platforms/settings_registry.py:ro",
     "./patches/oneday_prompt.py:/opt/hermes/agent/oneday_prompt.py:ro"),
    ("settings_admin.py",
     "      - ./patches/settings_admin.py:/opt/hermes/gateway/platforms/settings_admin.py:ro",
     "./patches/settings_registry.py:/opt/hermes/gateway/platforms/settings_registry.py:ro"),
    ("settings_admin_tool.py",
     "      - ./patches/settings_admin_tool.py:/opt/hermes/tools/settings_admin_tool.py:ro",
     "./patches/settings_admin.py:/opt/hermes/gateway/platforms/settings_admin.py:ro"),
    ("oneday_semantic.py",
     "      - ./patches/oneday_semantic.py:/opt/hermes/gateway/platforms/oneday_semantic.py:ro",
     "./patches/settings_registry.py:/opt/hermes/gateway/platforms/settings_registry.py:ro"),
    ("skill_admission_gate.py",
     "      - ./patches/skill_admission_gate.py:/opt/hermes/tools/skill_admission_gate.py:ro",
     "./patches/oneday_semantic.py:/opt/hermes/gateway/platforms/oneday_semantic.py:ro"),
    ("skill_manager_tool.py",
     "      - ./patches/skill_manager_tool.py:/opt/hermes/tools/skill_manager_tool.py:ro",
     "./patches/skill_admission_gate.py:/opt/hermes/tools/skill_admission_gate.py:ro"),
    ("oneday_gateway.py",
     "      - ./patches/oneday_gateway.py:/opt/hermes/gateway/platforms/oneday_gateway.py:ro",
     "./patches/skill_manager_tool.py:/opt/hermes/tools/skill_manager_tool.py:ro"),
    ("overview_gateway.py",
     "      - ./patches/overview_gateway.py:/opt/hermes/gateway/platforms/overview_gateway.py:ro",
     "./patches/oneday_gateway.py:/opt/hermes/gateway/platforms/oneday_gateway.py:ro"),
    ("oneday_ledger_lib.py",
     "      - ./patches/oneday_ledger_lib.py:/opt/hermes/gateway/platforms/oneday_ledger_lib.py:ro",
     "./patches/overview_gateway.py:/opt/hermes/gateway/platforms/overview_gateway.py:ro"),
    ("cron_projection.py",
     "      - ./patches/cron_projection.py:/opt/hermes/gateway/platforms/cron_projection.py:ro",
     "./patches/oneday_ledger_lib.py:/opt/hermes/gateway/platforms/oneday_ledger_lib.py:ro"),
    ("oneday_seg_automation.py",
     "      - ./patches/oneday_seg_automation.py:/opt/hermes/gateway/platforms/oneday_seg_automation.py:ro",
     "./patches/oneday_ledger_lib.py:/opt/hermes/gateway/platforms/oneday_ledger_lib.py:ro"),
    ("oneday_seg_briefings.py",
     "      - ./patches/oneday_seg_briefings.py:/opt/hermes/gateway/platforms/oneday_seg_briefings.py:ro",
     "./patches/oneday_seg_automation.py:/opt/hermes/gateway/platforms/oneday_seg_automation.py:ro"),
    ("oneday_seg_cron.py",
     "      - ./patches/oneday_seg_cron.py:/opt/hermes/gateway/platforms/oneday_seg_cron.py:ro",
     "./patches/oneday_seg_briefings.py:/opt/hermes/gateway/platforms/oneday_seg_briefings.py:ro"),
    ("oneday_seg_delivery.py",
     "      - ./patches/oneday_seg_delivery.py:/opt/hermes/gateway/platforms/oneday_seg_delivery.py:ro",
     "./patches/oneday_seg_cron.py:/opt/hermes/gateway/platforms/oneday_seg_cron.py:ro"),
    ("oneday_seg_feed.py",
     "      - ./patches/oneday_seg_feed.py:/opt/hermes/gateway/platforms/oneday_seg_feed.py:ro",
     "./patches/oneday_seg_delivery.py:/opt/hermes/gateway/platforms/oneday_seg_delivery.py:ro"),
    ("oneday_seg_filelibrary.py",
     "      - ./patches/oneday_seg_filelibrary.py:/opt/hermes/gateway/platforms/oneday_seg_filelibrary.py:ro",
     "./patches/oneday_seg_feed.py:/opt/hermes/gateway/platforms/oneday_seg_feed.py:ro"),
    ("oneday_seg_goals.py",
     "      - ./patches/oneday_seg_goals.py:/opt/hermes/gateway/platforms/oneday_seg_goals.py:ro",
     "./patches/oneday_seg_filelibrary.py:/opt/hermes/gateway/platforms/oneday_seg_filelibrary.py:ro"),
    ("oneday_seg_goals_activity.py",
     "      - ./patches/oneday_seg_goals_activity.py:/opt/hermes/gateway/platforms/oneday_seg_goals_activity.py:ro",
     "./patches/oneday_seg_goals.py:/opt/hermes/gateway/platforms/oneday_seg_goals.py:ro"),
    ("oneday_seg_goals_facade.py",
     "      - ./patches/oneday_seg_goals_facade.py:/opt/hermes/gateway/platforms/oneday_seg_goals_facade.py:ro",
     "./patches/oneday_seg_goals_activity.py:/opt/hermes/gateway/platforms/oneday_seg_goals_activity.py:ro"),
    ("oneday_seg_ideas_gen.py",
     "      - ./patches/oneday_seg_ideas_gen.py:/opt/hermes/gateway/platforms/oneday_seg_ideas_gen.py:ro",
     "./patches/oneday_seg_goals_facade.py:/opt/hermes/gateway/platforms/oneday_seg_goals_facade.py:ro"),
    ("oneday_seg_ideas_pool.py",
     "      - ./patches/oneday_seg_ideas_pool.py:/opt/hermes/gateway/platforms/oneday_seg_ideas_pool.py:ro",
     "./patches/oneday_seg_ideas_gen.py:/opt/hermes/gateway/platforms/oneday_seg_ideas_gen.py:ro"),
    ("oneday_seg_ledger.py",
     "      - ./patches/oneday_seg_ledger.py:/opt/hermes/gateway/platforms/oneday_seg_ledger.py:ro",
     "./patches/oneday_seg_ideas_pool.py:/opt/hermes/gateway/platforms/oneday_seg_ideas_pool.py:ro"),
    ("oneday_seg_library_mcp.py",
     "      - ./patches/oneday_seg_library_mcp.py:/opt/hermes/gateway/platforms/oneday_seg_library_mcp.py:ro",
     "./patches/oneday_seg_ledger.py:/opt/hermes/gateway/platforms/oneday_seg_ledger.py:ro"),
    ("oneday_seg_monitors.py",
     "      - ./patches/oneday_seg_monitors.py:/opt/hermes/gateway/platforms/oneday_seg_monitors.py:ro",
     "./patches/oneday_seg_library_mcp.py:/opt/hermes/gateway/platforms/oneday_seg_library_mcp.py:ro"),
    ("oneday_seg_sessions.py",
     "      - ./patches/oneday_seg_sessions.py:/opt/hermes/gateway/platforms/oneday_seg_sessions.py:ro",
     "./patches/oneday_seg_monitors.py:/opt/hermes/gateway/platforms/oneday_seg_monitors.py:ro"),
    ("oneday_seg_traces.py",
     "      - ./patches/oneday_seg_traces.py:/opt/hermes/gateway/platforms/oneday_seg_traces.py:ro",
     "./patches/oneday_seg_sessions.py:/opt/hermes/gateway/platforms/oneday_seg_sessions.py:ro"),
    ("NotoSansSC-subset.ttf",
     "      - ./patches/NotoSansSC-subset.ttf:/opt/hermes/gateway/platforms/assets/NotoSansSC-subset.ttf:ro",
     "./patches/oneday_seg_traces.py:/opt/hermes/gateway/platforms/oneday_seg_traces.py:ro"),
    ("device-data-ro",
     "      - ./data/device:/opt/device-data:ro",
     "./patches/NotoSansSC-subset.ttf:/opt/hermes/gateway/platforms/assets/NotoSansSC-subset.ttf:ro"),
    ("web_routers_profiles.py",
     "      - ./patches/web_routers_profiles.py:/opt/hermes/hermes_cli/web_routers/profiles.py:ro",
     "./patches/web_routers_sessions.py:/opt/hermes/hermes_cli/web_routers/sessions.py:ro"),
    ("web_routers_ops.py",
     "      - ./patches/web_routers_ops.py:/opt/hermes/hermes_cli/web_routers/ops.py:ro",
     "./patches/web_routers_profiles.py:/opt/hermes/hermes_cli/web_routers/profiles.py:ro"),
    ("options_pending.py",
     "      - ./patches/options_pending.py:/opt/hermes/gateway/platforms/options_pending.py:ro",
     "./patches/api_server_runs.py:/opt/hermes/gateway/platforms/api_server_runs.py:ro"),
    ("present_options_tool.py",
     "      - ./patches/present_options_tool.py:/opt/hermes/tools/present_options_tool.py:ro",
     "./patches/options_pending.py:/opt/hermes/gateway/platforms/options_pending.py:ro"),
    ("api_server_oneday_routes.py",
     "      - ./patches/api_server_oneday_routes.py:/opt/hermes/gateway/platforms/api_server_oneday_routes.py:ro",
     "./patches/api_server.py:/opt/hermes/gateway/platforms/api_server.py:ro"),
    ("auth_tokens.py",
     "      - ./patches/auth_tokens.py:/opt/hermes/gateway/platforms/auth_tokens.py:ro",
     "./patches/api_server_oneday_routes.py:/opt/hermes/gateway/platforms/api_server_oneday_routes.py:ro"),
    ("push_tokens.py",
     "      - ./patches/push_tokens.py:/opt/hermes/gateway/platforms/push_tokens.py:ro",
     "./patches/auth_tokens.py:/opt/hermes/gateway/platforms/auth_tokens.py:ro"),
    ("push_sender.py",
     "      - ./patches/push_sender.py:/opt/hermes/gateway/platforms/push_sender.py:ro",
     "./patches/push_tokens.py:/opt/hermes/gateway/platforms/push_tokens.py:ro"),
    ("db_schema_guard.py",
     "      - ./patches/db_schema_guard.py:/opt/hermes/gateway/platforms/db_schema_guard.py:ro",
     "./patches/push_sender.py:/opt/hermes/gateway/platforms/push_sender.py:ro"),
    ("credential_vault.py",
     "      - ./patches/credential_vault.py:/opt/hermes/gateway/platforms/credential_vault.py:ro",
     "./patches/api_server_oneday_routes.py:/opt/hermes/gateway/platforms/api_server_oneday_routes.py:ro"),
    ("credential_vault_tool.py",
     "      - ./patches/credential_vault_tool.py:/opt/hermes/tools/credential_vault_tool.py:ro",
     "./patches/credential_vault.py:/opt/hermes/gateway/platforms/credential_vault.py:ro"),
    ("identity_gateway.py",
     "      - ./patches/identity_gateway.py:/opt/hermes/gateway/platforms/identity_gateway.py:ro",
     "./patches/present_options_tool.py:/opt/hermes/tools/present_options_tool.py:ro"),
    ("front_gateway.py",
     "      - ./patches/front_gateway.py:/opt/hermes/gateway/platforms/front_gateway.py:ro",
     "./patches/identity_gateway.py:/opt/hermes/gateway/platforms/identity_gateway.py:ro"),
]
lines = open(path).read().split("\n")
for fname, line, anchor in specs:
    if any(fname in ln for ln in lines):
        continue
    out = []
    inserted = False
    for ln in lines:
        out.append(ln)
        if not inserted and anchor in ln:
            out.append(line)
            inserted = True
    if not inserted:
        sys.exit("anchor mount line not found in compose for " + fname)
    lines = out
# Semantic-recall runtime wiring (1.14.0, section 445): the gateway
# imports fastembed from the persistent pip target on the data volume
# and caches the model inside the data volume; both env lines live in
# the hermes service environment list, anchored on its API_SERVER_KEY
# line (the bridge services use env_file and never match first).
if not any("ONEDAY_SEM_CACHE" in ln for ln in lines):
    env_lines = [
        "      - PYTHONPATH=/opt/data/python-packages",
        "      - ONEDAY_SEM_CACHE=/opt/data/cache/fastembed",
    ]
    out = []
    inserted = False
    for ln in lines:
        out.append(ln)
        if not inserted and "- API_SERVER_KEY=" in ln:
            out.extend(env_lines)
            inserted = True
    if not inserted:
        sys.exit("hermes environment anchor (API_SERVER_KEY) not found in compose")
    lines = out
# OneDay/Overview gateway wiring (1.19.0, batch 3): structural env
# for the in-gateway faces -- enable flags, the cron callback
# loopback base, the Dashboard loopback base for the C-3 channel,
# and the ledger state path inside the data volume. Runtime
# secrets (ONEDAY_GEN_MODEL / TAVILY_API_KEY / FIRECRAWL_API_KEY /
# ONEDAY_CRON_CALLBACK_KEY) are instance values: they are copied
# from the instance's companion.env [oneday] section at apply
# time (see CAPABILITIES #31), never baked into the package.
if not any("ONEDAY_GATEWAY_ENABLED" in ln for ln in lines):
    env_lines = [
        "      - ONEDAY_GATEWAY_ENABLED=1",
        "      - OVERVIEW_GATEWAY_ENABLED=1",
        "      - ONEDAY_CALLBACK_BASE=http://127.0.0.1:8642/api/oneday-bridge",
        "      - ONEDAY_DASH_BASE_URL=http://127.0.0.1:9119",
        "      - HERMES_DASH_BASE_URL=http://127.0.0.1:9119",
        "      - ONEDAY_LEDGER_STATE_PATH=/opt/data/oneday/ledger-state.json",
    ]
    out = []
    inserted = False
    for ln in lines:
        out.append(ln)
        if not inserted and "- API_SERVER_KEY=" in ln:
            out.extend(env_lines)
            inserted = True
    if not inserted:
        sys.exit("hermes environment anchor (API_SERVER_KEY) not found in compose")
    lines = out
# Device gateway wiring (2.0.0, batch 5): the device data home moved
# into the gateway's own data volume. Two idempotent fixups:
# (a) repoint every legacy /opt/device-data:ro mount line (whose
#     source was the retired bridge data dir) at ./data/device,
#     collapsing duplicates the insert-only era may have left;
# (b) pin DEVICE_DATA_DIR in the hermes environment so the module's
#     home is explicit rather than default-resolved.
_canonical_dd = "      - ./data/device:/opt/device-data:ro"
_seen_dd = False
_out = []
for ln in lines:
    if ":/opt/device-data:ro" in ln:
        if _seen_dd:
            continue
        _seen_dd = True
        _out.append(_canonical_dd)
    else:
        _out.append(ln)
lines = _out
if not any("DEVICE_DATA_DIR" in ln for ln in lines):
    out = []
    inserted = False
    for ln in lines:
        out.append(ln)
        if not inserted and "- API_SERVER_KEY=" in ln:
            out.append("      - DEVICE_DATA_DIR=/opt/data/device")
            inserted = True
    if not inserted:
        sys.exit("hermes environment anchor (API_SERVER_KEY) not found in compose")
    lines = out
open(path, "w").write("\n".join(lines))
PYEOF
  grep -q "approval_projection.py" "$compose_file" || die "compose mount line write failed"
  grep -q "grant_projection.py" "$compose_file" || die "compose grant_projection mount line write failed"
  grep -q "api_server_runs.py" "$compose_file" || die "compose api_server_runs mount line write failed"
  grep -q "crash_reports.py" "$compose_file" || die "compose crash_reports mount line write failed"
  grep -q "fileproc_gateway.py" "$compose_file" || die "compose fileproc_gateway mount line write failed"
  grep -q "device_sync.py" "$compose_file" || die "compose device_sync mount line write failed"
  grep -q "device_gateway.py" "$compose_file" || die "compose device_gateway mount line write failed"
  grep -q "identity_gateway.py" "$compose_file" || die "compose identity_gateway mount line write failed"
  grep -q "front_gateway.py" "$compose_file" || die "compose front_gateway mount line write failed"
  grep -q "DEVICE_DATA_DIR" "$compose_file" || die "compose DEVICE_DATA_DIR env write failed"
  grep -q "./data/device:/opt/device-data:ro" "$compose_file" || die "compose device-data repoint write failed"
  grep -q "react_to_message_tool.py" "$compose_file" || die "compose react_to_message_tool mount line write failed"
  grep -q "self_reaction_pending.py" "$compose_file" || die "compose self_reaction_pending mount line write failed"
  grep -q "write_gate_gateway.py" "$compose_file" || die "compose write_gate_gateway mount line write failed"
  grep -q "oneday_memory.py" "$compose_file" || die "compose oneday_memory mount line write failed"
  grep -q "system_prompt.py" "$compose_file" || die "compose system_prompt mount line write failed"
  grep -q "oneday_prompt.py" "$compose_file" || die "compose oneday_prompt mount line write failed"
  grep -q "settings_registry.py" "$compose_file" || die "compose settings_registry mount line write failed"
  grep -q "oneday_semantic.py" "$compose_file" || die "compose oneday_semantic mount line write failed"
  grep -q "ONEDAY_SEM_CACHE" "$compose_file" || die "compose ONEDAY_SEM_CACHE env write failed"
  grep -q "skill_admission_gate.py" "$compose_file" || die "compose skill_admission_gate mount line write failed"
  grep -q "skill_manager_tool.py" "$compose_file" || die "compose skill_manager_tool mount line write failed"
  grep -q "oneday_gateway.py" "$compose_file" || die "compose oneday_gateway mount line write failed"
  grep -q "overview_gateway.py" "$compose_file" || die "compose overview_gateway mount line write failed"
  grep -q "oneday_seg_goals.py" "$compose_file" || die "compose oneday segments mount line write failed"
  grep -q "device-data" "$compose_file" || die "compose device-data mount line write failed"
  grep -q "ONEDAY_GATEWAY_ENABLED" "$compose_file" || die "compose oneday gateway env write failed"
  grep -q "options_pending.py" "$compose_file" || die "compose options_pending mount line write failed"
  grep -q "present_options_tool.py" "$compose_file" || die "compose present_options_tool mount line write failed"
  log "compose 已加模块挂载行"
fi

# ---------- 3b-2. 面板密码文件挂载确保（2.8.0，#46） ----------
# web-login 桥（api_server_oneday_routes）验面板密码读 password.json
# （scrypt 哈希；companion 时代的现行实物在部署目录同级 companion/
# companion-state/ 下）。源文件存在才给 hermes 服务加只读单文件挂载；
# 不存在的部署跳过——桥回退 PANEL_PASSWORD_HASH env，再无则回
# 「未配好」500，与旧 front 口径一致。单文件挂载下改密码必须原地
# 写回保 inode（front 的 write_text_inplace 同口径），容器免重启读新值。
PW_MOUNT_SRC="../companion/companion-state/password.json"
if [ -f "$DEPLOY_DIR/$PW_MOUNT_SRC" ]; then
  compose_file="$DEPLOY_DIR/docker-compose.yml"
  if ! grep -q "companion-state/password.json" "$compose_file"; then
    cbak="$compose_file$BAK_SUFFIX"
    if [ ! -f "$cbak" ]; then
      cp -a "$compose_file" "$cbak"
      log "已备份: docker-compose.yml$BAK_SUFFIX"
    fi
    COMPOSE_CHANGED=1
    python3 - "$compose_file" << 'PYEOF'
import sys
path = sys.argv[1]
line = "      - ../companion/companion-state/password.json:/opt/companion-state/password.json:ro"
anchor = "./patches/api_server_oneday_routes.py:/opt/hermes/gateway/platforms/api_server_oneday_routes.py:ro"
lines = open(path).read().split("\n")
if not any("companion-state/password.json" in ln for ln in lines):
    out = []
    inserted = False
    for ln in lines:
        out.append(ln)
        if not inserted and anchor in ln:
            out.append(line)
            inserted = True
    if not inserted:
        sys.exit("password.json mount anchor (api_server_oneday_routes) not found in compose")
    open(path, "w").write("\n".join(out))
PYEOF
    grep -q "companion-state/password.json" "$compose_file" || die "compose password.json mount line write failed"
    log "compose 已加面板密码文件挂载行"
  fi
  # 网关进程以 uid 10000 运行：密码文件必须归它可读（front 时代是
  # root 进程读 root 0600 文件；入关后不调属主必然 Permission
  # denied、桥恒回 401——2.8.0 首装实测教训）。属主对齐＋0600，
  # 内容与 inode 不动。
  chown 10000:10000 "$DEPLOY_DIR/$PW_MOUNT_SRC" 2>/dev/null || true
  chmod 600 "$DEPLOY_DIR/$PW_MOUNT_SRC" 2>/dev/null || true
fi

# ---------- 3c. OneDay 记忆资产（§439）：种子 + 技能 + cron 合并 ----------
# 口径：只补缺、永不覆盖——种子是新实例的起点，实例自己的记忆长出来后
# 种子无权顶替；cron 按 job id 幂等合并，既有作业（含用户自建）原样保留。
# 资产是 data/ 下的增量文件，不入补丁回滚范围：留置无害（机制靠 cron 与
# agent 程序驱动，删作业即停），清理步见 memory-mechanism-rollout。
if [ -d "$PKG_DIR/seed-memory" ]; then
  laid=0; skipped=0
  while IFS= read -r -d '' f; do
    rel="${f#$PKG_DIR/seed-memory/}"
    case "$rel" in
      README-SEED.md|config-memory-snippet.yaml) continue ;;
    esac
    dst="$DEPLOY_DIR/data/$rel"
    if [ -f "$dst" ]; then skipped=$((skipped+1)); continue; fi
    mkdir -p "$(dirname "$dst")"
    cp "$f" "$dst"
    laid=$((laid+1))
  done < <(find "$PKG_DIR/seed-memory" -type f -print0)
  log "记忆种子：新铺 $laid 个文件、已存在跳过 $skipped 个"
  mkdir -p "$DEPLOY_DIR/data/cron"
  added=0
  for frag in oneday-memory-jobs.json oneday-goals-jobs.json; do
    [ -f "$PKG_DIR/cron/$frag" ] || continue
    n=$(python3 - "$DEPLOY_DIR/data/cron/jobs.json" "$PKG_DIR/cron/$frag" << 'PYEOF'
import json, os, sys
dst_path, frag_path = sys.argv[1], sys.argv[2]
frag = json.load(open(frag_path))
if os.path.exists(dst_path):
    try:
        raw = json.load(open(dst_path))
    except Exception:
        sys.exit("cron/jobs.json 解析失败，未合并（先人工修复该文件）")
else:
    raw = {"jobs": []}
if isinstance(raw, dict):
    jobs = raw.get("jobs", [])
    wrap = True
else:
    jobs, raw, wrap = raw, {}, False
have = {j.get("id") for j in jobs if isinstance(j, dict)}
added = 0
for job in frag:
    if job.get("id") not in have:
        jobs.append(job)
        added += 1
if added:
    if wrap:
        raw["jobs"] = jobs
        out = raw
    else:
        out = jobs
    tmp = dst_path + ".tmp"
    with open(tmp, "w") as f:
        json.dump(out, f, ensure_ascii=False, indent=1)
        f.flush()
        os.fsync(f.fileno())
    os.replace(tmp, dst_path)
print(added)
PYEOF
) || die "cron 作业合并失败（$frag）"
    added=$((added + n))
  done
  log "cron 作业：新合并 $added 条（记忆＋目标，按 id 幂等）"
fi

# ---------- 3d. 身份真源（§442）：identity.json 只补缺 ----------
# 口径与记忆种子同：只补缺、永不覆盖——identity.json 是实例身份的真源，
# 装过之后归实例所有（App 身份面/运维改值），包内模板只是新实例的起点。
if [ -f "$PKG_DIR/assets/identity.json" ] && [ ! -f "$DEPLOY_DIR/data/identity.json" ]; then
  cp "$PKG_DIR/assets/identity.json" "$DEPLOY_DIR/data/identity.json"
  log "身份真源：已铺 identity.json 模板（空值待实例填写；三值未齐时第一层提示词不生效、装配回落上游）"
fi

# ---------- 3e. 语义检索依赖（§445）：fastembed 装入 data 卷 + 模型预取 ----------
# 口径：包本体只带代码；fastembed/onnxruntime 是运行时依赖，装进
# /opt/data/python-packages（data 卷持久、容器重建不丢），compose 的
# PYTHONPATH 指入（3b 已确保，本节在当前容器里以显式 PYTHONPATH 验）。
# 模型快照预取到 /opt/data/cache/fastembed（ONEDAY_SEM_CACHE）：安装期
# 联网一次，此后运行时零出境。幂等：可导入且模型在位时整段跳过。
# 容器 venv 无 pip：先以 ensurepip 自举（只落在容器临时层，够装机用）。
# 下载源：本机（腾讯云境内）实测 PyPI CDN 仅 20-85KB/s，安装期改走清华
# TUNA 镜像与 HF 镜像（仅安装期联网，运行时零出境口径不变）。
SEM_PKG_DIR=/opt/data/python-packages
SEM_CACHE_DIR=/opt/data/cache/fastembed
SEM_PIP_INDEX=https://pypi.tuna.tsinghua.edu.cn/simple
SEM_HF_ENDPOINT=https://hf-mirror.com
if docker exec -e PYTHONPATH=$SEM_PKG_DIR hermes python3 -c "import fastembed" >/dev/null 2>&1; then
  log "语义检索依赖已在位（fastembed 可导入），跳过安装"
else
  log "安装语义检索依赖 fastembed==0.9.1 到 $SEM_PKG_DIR"
  docker exec hermes python3 -m pip --version >/dev/null 2>&1 || \
    docker exec hermes python3 -m ensurepip >/dev/null 2>&1 || \
    die "ensurepip 自举 pip 失败，无法安装语义检索依赖"
  docker exec hermes python3 -m pip install --no-cache-dir \
    -i $SEM_PIP_INDEX \
    --target $SEM_PKG_DIR "fastembed==0.9.1" >/dev/null || \
    die "fastembed 安装失败（检查容器出网/镜像可达）"
  docker exec -e PYTHONPATH=$SEM_PKG_DIR hermes python3 -c "import fastembed" >/dev/null 2>&1 || \
    die "fastembed 安装后仍不可导入"
  log "语义检索依赖安装完成"
fi
if docker exec hermes sh -c "ls $SEM_CACHE_DIR 2>/dev/null | grep -q ." >/dev/null 2>&1; then
  log "语义模型快照已在位（$SEM_CACHE_DIR），跳过预取"
else
  log "预取语义模型快照 BAAI/bge-small-zh-v1.5 到 $SEM_CACHE_DIR（一次性联网）"
  docker exec -e PYTHONPATH=$SEM_PKG_DIR -e ONEDAY_SEM_CACHE=$SEM_CACHE_DIR \
    -e HF_ENDPOINT=$SEM_HF_ENDPOINT \
    hermes python3 -c "
import os
from fastembed import TextEmbedding
m = TextEmbedding(model_name='BAAI/bge-small-zh-v1.5',
                  cache_dir=os.environ['ONEDAY_SEM_CACHE'])
list(m.embed(['预热']))
print('model prefetched')
" >/dev/null || die "语义模型预取失败（检查容器出网/HF 可达）"
  log "语义模型预取完成"
fi

# ---------- 3f. 网页端插件资产（大活12，包 2.12.0，#52）：oneday-console ----------
# 口径：插件住数据卷 plugins/ 目录（dashboard 官方插件机制 user 源），不在
# 镜像内、上游升级不冲掉；本节幂等整目录同步三件资产（包内为真源）。
# user 源插件须 config.yaml 的 plugins.enabled 含 oneday-console 才挂载
# （上游 consent 闸 #46435），本节以文本级编辑幂等确保（只动 plugins 段的
# enabled 列表、其余字节不变、改前在配置旁留时间戳备份）；配置缺失或锚点
# 不合时只告警不中断（插件是增量面，verify 第 33 节会探出未启用状态）。
if [ -d "$PKG_DIR/web-plugins/oneday-console" ]; then
  pdst="$DEPLOY_DIR/data/plugins/oneday-console/dashboard"
  mkdir -p "$pdst/dist"
  cp "$PKG_DIR/web-plugins/oneday-console/dashboard/manifest.json" "$pdst/manifest.json"
  cp "$PKG_DIR/web-plugins/oneday-console/dashboard/dist/index.js" "$pdst/dist/index.js"
  cp "$PKG_DIR/web-plugins/oneday-console/dashboard/dist/style.css" "$pdst/dist/style.css"
  chmod 644 "$pdst/manifest.json" "$pdst/dist/index.js" "$pdst/dist/style.css"
  log "网页端插件 oneday-console：资产已同步至 data/plugins/oneday-console"
  if [ -f "$DEPLOY_DIR/data/config.yaml" ]; then
    cp "$DEPLOY_DIR/data/config.yaml" "$DEPLOY_DIR/data/config.yaml.bak-webplug-$(date +%Y%m%d%H%M%S)"
    python3 - "$DEPLOY_DIR/data/config.yaml" <<'PYEOF' || log "警告：plugins.enabled 确保未完成（锚点不合），网页端插件暂不会挂载，人工核 config.yaml"
import sys
path = sys.argv[1]
lines = open(path, encoding="utf-8").read().split("\n")
pstart = next((i for i, ln in enumerate(lines) if ln.rstrip() == "plugins:"), None)
if pstart is None:
    sys.exit("no plugins block")
pend = len(lines)
for i in range(pstart + 1, len(lines)):
    ln = lines[i]
    if ln and not ln.startswith((" ", "#", "\t")) and ":" in ln:
        pend = i
        break
eidx = next((i for i in range(pstart + 1, pend) if lines[i].rstrip() == "  enabled:"), None)
if eidx is None:
    sys.exit("no plugins.enabled")
j = eidx + 1
items = []
while j < pend and lines[j].startswith("    - "):
    items.append(lines[j].strip()[2:].strip())
    j += 1
if "oneday-console" not in items:
    lines.insert(j, "    - oneday-console")
    open(path, "w", encoding="utf-8").write("\n".join(lines))
    print("plugins.enabled += oneday-console")
else:
    print("plugins.enabled already has oneday-console")
PYEOF
  else
    log "警告：data/config.yaml 不存在，跳过 plugins.enabled 确保（首启生成配置后重跑本节或人工启用）"
  fi
fi

# ---------- 3g. 网页端 CORS 来源确保（包 2.12.1，#52 修复） ----------
# 根因（2026-11-26 真浏览器复验实查）：网关上游 cors_middleware 对带
# Origin 的浏览器请求先查 API_SERVER_CORS_ORIGINS 白名单，未登记即回
# 空体 403（在 reveal/approvals 任何 handler 之前）；非浏览器客户端无
# Origin 故服务端等价链测不出。本节把本站 dashboard 来源以文本级编辑
# 幂等写入现行 compose 的 hermes environment（锚点 API_SERVER_KEY 行），
# 改前备份；reveal 自身两道闸（key 白名单＋dashboard 会话回验）不动，
# 外部 Origin 仍 403。锚点不合只告警不中断，verify 第 34 节会探出。
if [ -f "$DEPLOY_DIR/docker-compose.yml" ]; then
  if grep -q 'API_SERVER_CORS_ORIGINS=' "$DEPLOY_DIR/docker-compose.yml"; then
    log "网页端 CORS 来源：compose 已登记 API_SERVER_CORS_ORIGINS，跳过"
  else
    compose_file="$DEPLOY_DIR/docker-compose.yml"
    cbak="$compose_file.bak-$(date +%Y%m%d)-corsorigins"
    if [ ! -f "$cbak" ]; then
      cp -a "$compose_file" "$cbak"
      log "已备份: docker-compose.yml.bak-$(date +%Y%m%d)-corsorigins"
    fi
    if python3 - "$compose_file" <<'PYEOF'
import sys
path = sys.argv[1]
lines = open(path, encoding="utf-8").read().split("\n")
anchor = next((i for i, ln in enumerate(lines)
               if ln.strip().startswith("- API_SERVER_KEY=")), None)
if anchor is None:
    sys.exit("no API_SERVER_KEY env anchor")
indent = lines[anchor][:len(lines[anchor]) - len(lines[anchor].lstrip())]
lines.insert(anchor + 1, indent + "- API_SERVER_CORS_ORIGINS=https://hermes.didichou.site")
open(path, "w", encoding="utf-8").write("\n".join(lines))
print("API_SERVER_CORS_ORIGINS inserted after API_SERVER_KEY")
PYEOF
    then
      COMPOSE_CHANGED=1
      log "网页端 CORS 来源：已登记 https://hermes.didichou.site 至 compose environment"
    else
      log "警告：CORS 来源登记未完成（锚点不合），网页端插件在浏览器内仍会被网关 CORS 闸拦，人工核 docker-compose.yml"
    fi
  fi
fi

# ---------- 4. 重启 hermes ----------
log "重启 hermes 容器使挂载生效"
if docker compose version >/dev/null 2>&1; then
  (cd "$DEPLOY_DIR" && docker compose up -d --force-recreate hermes)
else
  docker restart hermes >/dev/null
fi

# ---------- 5. 健康检查（8642/9119/8643 + 容器内回读哈希） ----------
API_KEY=$(docker inspect hermes --format '{{range .Config.Env}}{{println .}}{{end}}' | sed -n 's/^API_SERVER_KEY=//p')
health_ok=0
for i in $(seq 1 30); do
  body=$(curl -s --max-time 5 -H "Authorization: Bearer $API_KEY" http://127.0.0.1:8642/v1/health || true)
  case "$body" in
    *'"status": "ok"'*"$TARGET_VERSION"*) health_ok=1; break ;;
  esac
  sleep 2
done
[ "$health_ok" = "1" ] || die "8642 /v1/health 60 秒内未恢复 ok/$TARGET_VERSION"
log "8642 /v1/health ok（version $TARGET_VERSION）"

code_9119=$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 http://127.0.0.1:9119/ || true)
case "$code_9119" in 200|302) log "9119 应答 $code_9119" ;; *) die "9119 应答异常: $code_9119" ;; esac

code_8643=$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 http://127.0.0.1:8643/ || true)
# 8643 口径（2026-11-24 随 1.14.0 修订）：断桥批二（1.10.0）后写闸桥已退役、
# 宿主 8643 无监听为正常终态（写闸面由网关 /v1/write-gate 承载、verify
# 第 18 节把关）；200|401＝观察窗内桥仍在位亦可。1.14.0 首装实证：旧口径
# 在 000 处误杀已实质完成的安装，故 000 改记注记放行，其余异常码仍停。
case "$code_8643" in
  200|401) log "8643 应答 $code_8643（桥观察窗在位）" ;;
  000) log "8643 无监听（写闸桥已退役，批二终态，正常）" ;;
  *) die "8643 应答异常: $code_8643" ;;
esac

for entry in "${PATCHES[@]}" "${MODULES[@]}"; do
  IFS='|' read -r name _src_rel cpath want_sha <<< "$entry"
  in_sha=$(docker exec hermes sha256sum "$cpath" | awk '{print $1}')
  [ "$in_sha" = "$want_sha" ] || die "容器内回读哈希不符: $name"
done
log "容器内回读哈希全对齐（补丁＋模块）"

# ---------- 5b. 语义检索冒烟（§445）：真后端建索引 ----------
# 以网关进程同一身份跑模块 CLI：reindex 输出即后端实况——必须是
# fastembed 真后端、非降级，否则本包的能力声明不成立，当场停。
sem_reindex=$(docker exec hermes python3 /opt/hermes/gateway/platforms/oneday_semantic.py reindex 2>/dev/null || true)
case "$sem_reindex" in
  *'"backend": "fastembed"'*'"degraded": false'*)
    log "语义索引构建 ok（fastembed 真后端）: ${sem_reindex:0:120}" ;;
  *) die "语义索引构建异常（后端非 fastembed 或已降级）: ${sem_reindex:0:200}" ;;
esac

ROLLBACK_ARMED=0
log "安装完成：应用 ${#CHANGED_FILES[@]} 个文件、新建 ${#CREATED_FILES[@]} 个模块，健康检查全过"
