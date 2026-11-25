# FILE-115 · 伴生 1.0.15 表格转码端点（配合 App §125）施工报告

日期：2026-11-11。触发：用户报 OneDay 点开 .xlsx 直接进 QuickLook、21 列表被缩成极小一坨（file-open-flow-benchmark-20261111.md）；用户 13:15 拍板文件包主包＋表格转码二期一起做。版本：伴生 1.0.14 → **1.0.15**，已按伴生自动部署授权上线。改动面：仅 `modules/oneday_bridge.py` 一文件（新增转码端点）＋本地 Dockerfile/compose 版本位＋新增自测一面。

## 版本号顺延注（重要）

- 本包原拟 1.0.14，施工中实查生产已在 1.0.14（并行线先行部署，build-114 与 companion-114-deploy 基线在服务器），遂顺延 **1.0.15**，部署基线目录 `/root/companion-115-deploy-20261111/`、构建目录 `/root/build-115`。
- 源码对账：生产 build-114 的 `oneday_bridge.py` 与本地仓副本逐字一致；本包补丁对之为**纯增 330 行、零删改**（diff 实测），不存在覆盖并行线改动的风险。新文件 md5 `8541534a389a4ec5850303cfa4c2c9d2`（本地与服务器一致）。

## 端点口径（GET /files/spreadsheet?path=）

- 鉴权：走桥既有 Bearer 单钥 `_authed()`，无钥 401。
- 路径合规（照 Hermes files 下载同规）：根锁 /opt/data（SPREADSHEET_ROOT 可覆盖）；不存在 404；非文件/相对路径/越根 400；敏感 403（名单与 App SensitiveFilePolicy 逐项镜像：protectedNames＋.env 变体＋敏感扩展 pem/key/p12/keystore＋词元集＋credential/secret/token 子串兜底）；超 100MiB 413；旧版 .xls（OLE 魔数）与不可解析 422（App 侧 422 走 FileOpenFailure 转码专档）。
- 转码：零依赖 stdlib（zipfile＋XML；镜像内无表格库、不新引依赖）。**值口径**：公式取缓存值、无缓存值渲染空并计数进 notes 如实标注；合并单元格值只在左上格（格式本身如此存）；日期经 styles.xml 数字格式识别渲 ISO（内置日期格式 id 集＋自定义格式码启发式；Excel 序列 60 的虚构 1900-02-29 折叠至 1900-03-01，只读呈现妥协）；数字整数去尾 .0；布尔 TRUE/FALSE；共享字符串含富文本多段拼接。
- 限额：单 sheet 500 数据行截断（total_rows 报实数、truncated 明示，不静默）；sheet 上限 50（超限 notes 标注）。

## 本地自测（全绿）

- 新增 `oneday_bridge_spreadsheet_selftest.py` **20 测全过**：无钥 401、共享字符串/数字/公式缓存值/布尔/日期 ISO、CSV 引号转义、公式无缓存空值＋notes 计数、多表序、600 行截断（total_rows=600、csv 恰 501 行）、404/目录 400/相对 400/越根 400/敏感名 403（mytoken.xlsx 内容合法仍拒）/旧版 .xls 422/垃圾文件 422/缺参 400。已挂 `run_bridge_selftests.sh`。
- 全套回归绿：overview 8／p2 34／p3 29／p4 19／p5 21／p6 45／device OK／write-gate 22／device_sync OK／model-combos OK／ledger 60——基线只增不减（新增 spreadsheet 20）。

## 施工与回滚基线

- 部署前服务器内存实查：7725MB 总量、已用约 51%（红线 80% 内）；部署后约 51%。
- 回滚基线：`/root/companion-115-deploy-20261111/`（生产 docker-compose.yml、companion.env、两容器 inspect、部署前内存、1.0.14 版 `oneday_bridge.py.114`、build.log）。回滚＝基线 compose+env 拷回＋`docker compose up -d companion`（1.0.14 镜像保留在服务器）。
- 构建：`/root/build-115`＝build-114 副本仅替换 `oneday_bridge.py`，`diff -rq` 证明恰一文件不同；镜像 `oneday/companion:1.0.15`（sha256:cf20191f…）。生产 compose 第 3 行镜像、第 24 行与 companion.env 第 4 行 COMPANION_VERSION 均已置 1.0.15（构建上下文 Dockerfile 的 ARG 恒 1.0.5 系历版旧例，版本真值以 compose env＋env 文件＋镜像 tag 为准，与 1.0.13/1.0.14 同口径）。

## 上线验收

- 容器 `oneday-companion` 运行镜像 1.0.15，进程内 COMPANION_VERSION=1.0.15（容器 exec printenv 与监督者 /proc/1/environ 双证）。
- 桥 /health（8646）：ok、degraded=false、台账 90 条、采集 lag 16.2 秒；front（8650）200。
- **端点冒烟（容器内，钥自 companion.env 段内取、不外露）**：无钥 401／不存在 404／config.yaml 敏感 403；真实文件 `/opt/data/attachments/（仅供查看，不用于数据恢复）iCost_20261025103804.xlsx` 回 200——sheet「收支账单」total_rows=3893、truncated=true、csv 恰 501 行（表头＋500），首行 21 列表头完整，日期值（2025/05/31 14:06:00）、金额（-202 整数口径）、中文共享字符串均正确。公网路径（https://hermes.example.com/api/oneday-bridge/files/spreadsheet）无钥回 401，nginx 路由通。
- Hermes 本体未动：StartedAt 部署前后同为 `2026-11-10T14:21:47.024396739Z`。

## 未验（待 App 合并发版后真机验）

- App §125 中间页「查看表格」全链（多表切换/截断明示/公式无缓存注记）随 App 包合并定版后真机验；桥侧契约已由自测＋生产冒烟双证。
