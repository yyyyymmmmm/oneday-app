# 技能硬闸「存量 4 个」定清单（只读扫描，2026-11-25）

纪律声明：本清单全部来自只读扫描——未修复、未改任何技能文件、未重启、未碰凭据明文（凭据类命中只记规则 id＋文件:行号，命中原文不抄录）。服务器内存扫描前实查 4317/7725 MB ≈ 56%，未触 80% 红线。

## 工具与口径

- 闸本体：部署包 1.18.0（§444）模块 `skill_admission_gate.py`（生产容器 hermes 内 `/opt/hermes/tools/`，与包内钉值同件）。
- 扫描命令：模块自带 CLI `python3 skill_admission_gate.py check <skill_dir>`。已逐行核过源码：check 路径只调 `validate_tree()`——只读文件、Python 语法走内存 `compile()`、shell 走 `bash -n`，不写账本、不落盘，属纯只读模式。
- 闸的实际效力：技能经 skill_manager_tool 写入（create/edit/patch/write_file）时在落盘前整树校验，不过不落盘。**存量技能在下次被写入之前不受影响；一旦要改，先过闸。** 豁免只认 `HERMES_HOME/skill_gate.json` 中用户亲手登记（approved_by: "user")——实查生产**无 skill_gate.json**，即当前零豁免、闸默认开。

## 扫描范围与总结果

| 范围 | 棵数 | 结果 |
|---|---|---|
| 生产主树 `/opt/data/skills`（HERMES_HOME) | 69 | 65 过、**4 命中** |
| 插件树 `/opt/data/plugins/box/skills` | 1 | 过 |
| 待批暂存 `/opt/data/pending/skills` | 0（空目录） | — |
| 镜像内置树 `/opt/hermes/skills`（上游自带，参照组） | 44 | 42 过、2 命中（与生产 4 个中的 2 个同名同点，见下） |

合计实扫 114 棵：108 过、6 条命中记录，去重后即生产侧 **4 个**——与总表「技能硬闸存量 4 个待收编」正好对上，**所指查实**。

## 命中清单（逐个定性＋收编建议）

### 1. autonomous-ai-agents/hermes-agent — 凭据规则（示例值）
- 命中：`credentials` 检查——`references/native-mcp.md` 第 277、304 行各命中 `token_prefix_sk` 与 `bearer_token` 两条规则。
- 定性：两处都是文档里的 MCP 服务器配置**示例**（假域名 mycompany.com 的 YAML 样例，Authorization 头示例值），不是在用真凭据；但示例值形态与真令牌同形，闸无法分辨。镜像内置孪生件同点命中，问题随上游文档而来、非用户写入引入。
- 收编建议：把两处示例值改写成闸的占位符口径（如 `Bearer <your-token>` 或 `${COMPANY_API_TOKEN}` 式环境变量引用，`_PLACEHOLDER_RE` 放行形态），整树即过闸；不建议为文档示例登记用户豁免。

### 2. creative/baoyu-infographic — 引用规则（参数化占位路径，误报型）
- 命中：`references` 检查——SKILL.md 第 59、87、195、198 行的 `` `references/layouts/<layout>.md` `` 与 `` `references/styles/<style>.md` `` 被当作字面路径，不在树内。
- 定性：`references/layouts/`、`references/styles/` 两目录真实存在且文件齐全（bento-grid、comic-strip 等布局与风格文件都在）；命中的是「按选中项拼路径」的参数化写法，闸按字面判缺失，属写法与闸口径不合，非文件缺失。镜像内置孪生件同点命中。
- 收编建议：改 SKILL.md 措辞——把反引号内的 `<layout>`/`<style>` 占位路径改成不触发字面校验的表述（如正文说明「从 references/layouts/ 目录按布局名取同名 .md」，目录引用不带具体文件占位），或逐个写实文件名；改完即过闸。

### 3. productivity/maps — 引用规则（真悬空引用）
- 命中：`references` 检查——SKILL.md 第 22、38 行引用 `` `references/weather-open-meteo.md` ``，该技能**无 references/ 目录**，文件真缺失。
- 定性：四个里唯一一处真缺陷——正文两处把 Open-Meteo 天气配方外链到一个不存在的文件。配方内容现存于 `productivity/weather-forecast` 技能的 SKILL.md 内。
- 收编建议：二选一——①给 maps 补建 `references/weather-open-meteo.md`（从 weather-forecast 技能摘录 Open-Meteo 配方落盘）；②改 SKILL.md 两处引用为跨技能的正文表述（指向 weather-forecast 技能，不用反引号相对路径）。推荐①，引用与内容同树、后续写入不再卡闸。

### 4. productivity/weekly-review-planning — 引用规则（跨技能引用被按本树判）
- 命中：`references` 检查——SKILL.md 第 37 行以反引号相对路径写 `` `references/session-history-analysis.md` ``。
- 定性：目标文件真实存在，但在 **hermes-agent** 技能树内（`/opt/data/skills/autonomous-ai-agents/hermes-agent/references/session-history-analysis.md`）；原文语义本就是跨技能指引（「see hermes-agent → …」），只是路径用了反引号相对形态，被闸按本树引用判缺失。
- 收编建议：改第 37 行措辞为不带反引号相对路径的正文表述（如「见 hermes-agent 技能的 session-history-analysis 参考文件」），即过闸；不需动 hermes-agent 侧。

## 收编总口径（给后续施工）

- 4 个全是**内容侧小修**（改示例值形态 1 个、改引用措辞 2 个、补缺失文件或改引用 1 个），无一需要动闸本体、无一需要用户豁免登记。
- 施工通道：直接在技能文件上改（或经 skill_manager_tool 写入时闸自动验收——改后整树过闸即放行，天然闭环）。
- 施工后复验：对 4 棵重跑本清单同款 `check` 命令，全过即关账。
- 注意：镜像内置树 `/opt/hermes/skills` 的 2 个孪生命中不在收编范围（上游镜像件、升级即覆盖），生产只认 `/opt/data/skills` 一棵树。

## 附：本次未动的事项

- 未对任何技能做修复或豁免登记（等主线排施工）。
- 容器内扫描临时产物（/tmp/scan）已清。
