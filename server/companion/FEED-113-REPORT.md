# FEED-113 · 伴生 1.0.13 动态著帖收紧（配合 App §122）施工报告

日期：2026-11-11。触发：用户报「动态内容太长、翻半天不到头、图片有问题」；长度口径以用户随后发的 Muse 动态截图为准二次收紧（见下）。版本：伴生 1.0.12 → **1.0.13**，已按伴生自动部署授权上线。改动面：仅 `modules/oneday_bridge.py` 一个文件（feed 著帖环节）＋本地 Dockerfile/compose 版本位；存量帖不回改。

## 新口径定版（2026-11-11 用户以 Muse 动态截图为标准改严）

- **正文**：目标 **80–180 字、最多三句**（发生了什么＋为什么值得看＋来源锚点）。著帖提示词（`RESEARCH_COMPOSE_PROMPT`）已按此改写，原 300–800 字长文口径、及中途一版 150–300 字口径均作废。
- **落库截断**：正文超 **260 字**在落库前按句界截断（`_clamp_feed_body`，句界＝。！？；/换行；截断点落在 Markdown 链接内部时回退到链接之前；无句界硬截断）。
- **标题**：一行内、约 **30 字内**；提示词同步改 30 字；落库前超限按**词界**截断（`_clamp_feed_title`：取限内最后一个分隔符——空格/，、：；·—|/——处切断；词界过近（<10 字）会留残 stub 时改硬截断）。
- **选图过滤**（在 1.0.12 候选链与 HEAD 校验之后加一道形状门 `_image_shape_ok`，图片元数据在服务器侧读头判定）：(a) 高/宽 > 1.2 的长截图/疑似整页图弃用；(b) 能读到尺寸且宽 < 400px 的低清小图弃用；(c) 尺寸读不到（格式未知/网络失败）不因此弃图，保留 HEAD 既有口径。图池过滤空 → 无图发帖，不拿别的图凑。尺寸解析为零依赖手写头解析（`_parse_image_dimensions`：PNG/GIF/BMP/WebP 三变体/JPEG SOF 扫描；`_image_dimensions` 用 Range 流读至多 256KB 前缀）。

## 施工与回滚基线

- 部署前服务器内存实查：7725MB 总量、已用约 53%（红线 80% 内）；部署后约 51%。
- 回滚基线：服务器 `/root/companion-113-deploy-20261111/`（生产 docker-compose.yml、companion.env、两容器 inspect、部署前内存、1.0.12 版 `oneday_bridge.py.112`、build.log）。回滚＝基线 compose+env 拷回＋`docker compose up -d companion`（1.0.12 镜像保留在本机）。
- 构建：`/root/build-113`＝1.0.12 构建上下文副本仅替换 `oneday_bridge.py`，`diff -rq` 对 build-112 证明恰一文件不同；新文件 md5 `0ba744b922afb3a14de30ffa2d61ba7d`（与本地一致）；镜像 `oneday/companion:1.0.13`（sha256:b3aa3f34…）。生产 compose 第 3 行镜像、第 24 行与 companion.env 第 4 行 `COMPANION_VERSION` 均已置 1.0.13。

## 本地自测（全绿）

overview 8／p2 34／p3 29／p4 19／p5 21／**p6 45（基线 31＋新增 14）**／device OK／write-gate 22／device_sync OK／model-combos OK／ledger 60。p6 新增 §122 段断言：五种格式尺寸解析、未知字节 None、长截图弃、小图弃、正常 og 图保留、尺寸不可读保留、verify 级弃 tall 留 og、全坏图无图落帖、正文 260 句界截断且以「。」结尾、短正文不动、短标题不动、长标题词界截断、无分隔符长标题硬截断、verify 级标题截断。（device_sync 此前记录的 1 例 FAILED 本轮未复现，属日期相关既有项，与本包无关。调试中曾因测试样本标题实际仅 26 字未达 30 上限、2 条断言假红，换真长样本后转绿——系测试样本问题，非实现问题。）

## 上线验收

- 容器 `oneday-companion` 运行镜像 1.0.13，进程内 `COMPANION_VERSION=1.0.13`。
- /info 聚合（front `build_info()` 同源数据＋按 front 原探活口径复刻实测）：companionVersion=**1.0.13**、hermesUp=true、五模块全 up（writeGate `/status` 200 且 supported=true；overview `/overview` 200；box mcpSession up；oneday degraded=**false**；device ok）、supervisor 六进程全 running。
- 桥 /health（8646）：ok、degraded=false、台账 86 条、采集 lag 2.4 秒。
- Hermes 本体未动：StartedAt 部署前后同为 `2026-11-10T14:21:47.024396739Z`。
- 验收注记：front 探活钥走 `Authorization: Bearer`（非 X-Bridge-Key），且钥按 env 分段注入 front 进程；在容器外裸进程调 `build_info()` 会因缺钥把 writeGate/overview 误报 down——本次曾出现此测量假象，已按原口径复刻探活排除，面板真值以登录后 /info 为准。

## 未验（待观察，不要手动灌帖）

新帖形态（正文三句内/标题一行/图合格）等下一轮自然轮验证：2026-11-12 08:30 每日轮或简报变更触发轮。届时对尺：正文 ≤180 字目标（硬顶 260)、标题 ≤30 字、配图无长截图与小图、无图帖可接受。
