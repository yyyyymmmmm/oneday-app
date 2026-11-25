# 生成管线「API key 被拒」定性与修复（部署包 2.5.1，2026-11-25）

急修背景：2.5.0 应用后点子日轮已无 409，但终态失败于 `custom rejected your API key`；应用前 02:05／03:05 同型失败已存在。今早 07:30 定时轮前必须关账。

## 定性（全部实查，非推断）

**不是钥失效，是上游中转账户余额枯竭被误报成钥问题。**

- 生成管线链路：点子段 `oneday_seg_ideas_gen.py` 与动态段 `oneday_seg_feed.py` 共用同一 `_hermes_submit_run` 与 `GEN_MODEL`（段文件为同一模块命名空间拼装），模型由容器 env `ONEDAY_GEN_MODEL` 指定，原值 `claude-sonnet-4-6`，不带 provider 提交网关 run。
- 网关侧钥无恙：config 默认 provider `custom:ailey`（base_url `https://aikey.example.com/v1`，即自家 new-api），其钥 `ONEDAY_PROVIDER_AILEY_KEY` 与 `ONEDAY_PROVIDER_GATEWAY_KEY`、`NEWAPI_API_KEY` 实为同一把——自家 new-api 令牌 #67「hermes」（属主为站长账号）。该令牌 unlimited、站长账号余额约 $50,185 级（quota 25,092,461,130 单位），实时小请求（sonnet／deepseek 各一）均 200 并在 new-api logs 正常结算（log 46392–46394）。
- 真因：自家 new-api 内 `claude-sonnet-4-6` 走 **15 号通道 laogou8（api.laogou8.com 中转）**，该账户余额仅剩约 **$0.074**。生成请求提示词大（实测单轮 prompt 约 54k token），上游预扣需 **$0.44–0.55**，不足 → HTTP 403 `insufficient_user_quota`（原文：`Not enough quota to pre-consume for this request: $0.077572 remaining, $0.551370 required`，网关日志 2026-11-25 04:04:40／04:05:09 两轮；主线以 45k token 提示词同型复现，403 原文 remaining $0.074468／required $0.441540）。Hermes 把上游 403 统一包装成 `custom rejected your API key`，与钥有效性无关。
- 主对话不受影响之因：默认模型 deepseek-flash 走 **14 号通道 DeepSeek 官方（api.deepseek.com）**，余额健康；小请求预扣低，laogou8 残额也能过——所以只有生成管线的大提示词请求撞墙，02:05／03:05 先存失败同因。
- 与 2.5.0 scrub 无关（逐一排除）：生成管线所用钥在 `/opt/data/.env`（2026-11-12 落盘、0600），不在 scrub 删除／清值清单内（清单在 2.5.0 基线内）；且修复前实测该钥实时可用。scrub 未误清。

## 修法（部署包 2.5.1）

- 现行 compose `/www/dk_project/dk_app/hermes/docker-compose.yml` 第 81 行 `ONEDAY_GEN_MODEL=claude-sonnet-4-6` → **`deepseek-v4-pro`**（14 号 DeepSeek 官方通道；Ailey provider 模型表内有此模型）。点子＋动态共用同一 GEN_MODEL，一并恢复。
- 选型实测：deepseek-v4-pro 与 deepseek-flash 各以 45k token 提示词实测 HTTP 200；取 v4-pro（同通道更强档、成本仍低）。
- 基线：`/root/deploypkg-2.5.1-20261125/baseline/docker-compose.yml.pre-2.5.1`（sha256 `24552668769e102f31916290ff857d217d5993d02822c421704a53b1d077a5fc`）；现行目录另留 `docker-compose.yml.bak-2.5.1-genmodel`。
- 应用：`docker compose up -d --force-recreate hermes`（应用前内存 53%，红线 80%）；容器 env 回读 `ONEDAY_GEN_MODEL=deepseek-v4-pro`、health ok。
- 包面同步：manifest 升 2.5.1（变更注记在卷首）；verify.sh 新增探针 `genmodel-funded-route`（容器 env 须为 deepseek-v4-pro）。env.template 为空值占位、无值可改，不动。
- 回滚：compose 该行改回 `claude-sonnet-4-6`（或自基线恢复）＋重建 hermes 容器。

## 实证（关账门）

- 真实触发点子日轮（`hermes cron run 3df46e2d77cd`）：台账 job `job:ideas:1795551283` running → **completed**（seq 10198，delivery counts produced=5，seq 10199）。
- **data.json 点子 0 → 5 条**（全 pending）：「我可以整理 HeyGen Pro 续费退款的材料与跟进要点」「我可以备好 Ekko Studio 改密方案与回滚基线供你确认」「我可以按黑白通吃线列出《张世豪》第 2 章细纲」「我可以每天为 x-dun 整理选题简报（AI 工具教程与海外服务/VPS 方向）」「我可以整理西安通源天然气 IC 卡智能表的购气与报修清单」。
- 无 409、无 key 被拒：重启后网关日志 `rejected／Not enough quota` 命中 0；new-api logs 实证生成各轮经 14 号通道以 deepseek-v4-pro 结算（prompt 53,817／53,907／54,462 token 等多笔 type=2）。
- 动态生成段：与点子共用同一 GEN_MODEL／同一提交路径，点子轮已实证该路径；另以同型 45k token 请求对 deepseek-v4-pro 验通（HTTP 200）。未单独触发动态轮（避免在配图修复前多产无图帖）。
- 三读面未扰：动态 feedPosts 仍 29 条；health ok；内存全程约 53%。

## 遗留（需用户处理，主线转达）

- **laogou8（api.laogou8.com）账户需充值**：余额约 $0.074。该通道还承载 claude-sonnet-4-6／claude-haiku-4-5-20251001／gpt-5.6-terra 三个模型——凡经自家 new-api 调这三个模型的其它链路（如外部智能体经 laogou8 网关的钥）大请求同样会撞墙。充值后如要恢复 sonnet 生成路线，改 compose env 回 `claude-sonnet-4-6`＋重建容器即可（本记录回滚节）。
- 本次定性探针在 laogou8 残额上消耗约 $0.003（小请求实测），属诊断必要支出。
