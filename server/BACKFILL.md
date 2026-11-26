# 部署包脱敏回填清单（BACKFILL）

仓内 `server/` 是分发口径的脱敏件：真域名、真部署路径在本仓以占位值登记。
**从本仓出包上任何真实 instance 之前，必须先在服务器暂存副本里逐件回填本清单，
回填后按暂存副本实物重算这几件的 sha256 并同步暂存副本的 manifest/install/verify
三处登记，才许跑 install.sh。** 未回填直接安装的后果逐件写明——seg_feed 一件是活雷：
新帖图片地址会全部指向不存在的域名。

回填值来源：现行 instance 线上实物（部署目录文件本身即真值），不在本仓写明真值。

| # | 文件 | 仓内占位 | 回填为什么 | 不回填的后果 |
|---|------|----------|------------|--------------|
| B-1 | `patches/oneday_seg_feed.py`（第 1429 行常量） | `https://hermes.example.com/feed-media/` | 现行 instance 的 feed-media 公网域名前缀 | **活雷**：新生成帖的图片地址全错、图全部打不开 |
| B-2 | `services/nginx-feed-media-shape.conf`（第 35 行 alias） | `/srv/hermes/data/oneday/media/feed/` | 现行 instance 部署目录下的真实 data 路径 | feed-media 静态服务 404，存量帖图也打不开 |
| B-3 | `device-mcp-config-patch.py`（第 54 行缺省部署目录） | `/srv/hermes` | 现行 instance 真实部署目录（调用时显式传参则不触发缺省） | 缺省调用时把 MCP 注册写到不存在的目录 |
| B-4 | `settings-admin-config-patch.py`（第 121 行缺省部署目录） | `/srv/hermes` | 同 B-3 | 缺省调用时配置补丁落错目录 |
| B-5 | `companion/backfill_idea_categories.py`（第 149 行缺省 HERMES_BASE_URL） | `https://hermes.example.com` | 现行 instance 真实域名（env `HERMES_BASE_URL` 有值则不触发缺省） | 缺省调用时回填脚本打到不存在的地址 |

登记口径：本仓三处登记（manifest.yaml / install.sh / verify.sh）的哈希一律按**仓内
脱敏实物**登记、自洽可验；暂存副本回填后哈希变化属预期，须在暂存副本内重算对平
（历史教训：登记停在实物值一侧、文件停在脱敏一侧时，install 会因哈希对不上直接卡住）。

关账状态（2026-11-26，部署包 2.11.0 收口）：五件清单补齐 ✅；仓内登记对平 ✅
（2.11.0 全表复算）；线上回填沿现行 instance 实物在役、本棒未动线上。
**硬条件：本清单五件未在暂存副本回填对平之前，不许从 main 出部署包上生产。**

补记（2026-11-26，部署包 2.16.0）：五件清单未变（仍 B-1～B-5）；2.12.0–2.16.0
各棒部署均按本清单口径先在暂存副本回填对平、再应用，仓内登记随各版全表复算
对平（2.16.0 时点：57 个带哈希登记点对仓库不一致 0）。硬条件不变。

补记（2026-11-26，部署包 2.18.1 并集定版，队列 157）：同日两线并发部署
（2.17.2 凭据请求结构化直出线与 2.18.0 插件 0.7.0 线同窗落同一实例，线上为
干净并集但仓内账面分叉）在此收口：三分支 fix/rd3-server-0512（d84a86a5）、
web-bar6（581ce9d5＋554d7162）、fix/seg-base-url-default（e808895f）自共同
基线 b85d3313 逐段合并为并集 2.18.1（分支 union/server-2181），冲突只落在
manifest／CAPABILITIES／verify 三件账面，均逐段对齐、无整文件覆盖；登记
顺延：CAPABILITIES 凭据件 #59 与棒 6 件 #60 并存，verify 凭据探针第 40 节、
棒 6 探针顺延第 41 节。此后只认 2.18.1 一套号：2.17.2 与 2.18.0 均为同日
中间态、不再单独出包。回填口径不变：B-1～B-5 五件仍按本清单在暂存副本
回填对平后才许整装；seg ideas_gen 的 HERMES_BASE_URL 缺省已由队列 156 在
仓内改回真域名（该件不在 B 清单内，系 2.11.0 换入占位缺省的根治件）。
