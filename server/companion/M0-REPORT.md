# 伴生服务 M0 构建与本地验报告

> 范围：只构建与本地验。生产全程未动——服务器只做了只读拉取（五桥脚本、四份 compose 结构、基础镜像体积），开工时内存 53%（红线 80%）；未停/重启任何线上容器、未改线上 nginx、未写生产数据。拉回的 compose-hermes.yml 含生产密钥字面值，提取结构后已删除，不进本工程。

## 1. 交付物（~/workspace/hermes-deploy/companion/）

| 文件 | 内容 |
|---|---|
| Dockerfile | 基础镜像钉版 `nousresearch/hermes-agent:v0.23.0`，COPY 监督者/front/五模块/面板静态，ENTRYPOINT＝镜像 venv python 跑监督者（PID 1） |
| docker-compose.yml | 双容器成套文件（hermes 现行定义原样＋companion 新增＋可选网关 profile）；YAML 解析通过 |
| companion.env.example | 一份文件五段＋global 段：五把 scope 钥位、COMPANION_SERVICE_KEY 位、登录钥服务端副本位、面板密码哈希位、六个模块默认开关位；值全空/占位，零真实密钥（全文已反查） |
| supervisor/supervisor.py（400 行） | 标准库自研监督者：按段解析 companion.env 并只注入对应子进程（含 overview 跨段取 write-gate 钥、front 例外注入五钥作探针凭据）、期望状态落盘、崩溃 2 秒首重试＋指数退避（封顶 60 秒）、快速崩溃 ≥5 次标 crash-loop、控制通道 127.0.0.1:8651（启动生成 0600 口令文件）、SIGTERM 全员干净退出＋孤儿回收 |
| supervisor/modules.json | 六进程清单（五模块＋front）：脚本路径、端口、人话名、段名、跨段注入、front 的 include_global |
| front/front.py（1180 行） | 标准库 front：聚合 /api/companion/health（200/503）与 /info（恒 200、§5 形状逐字对齐）、面板静态托管、双方式登录（密码 scrypt 哈希验＋失败 5 次/5 分钟限速；密钥服务端调 8642 /v1/models 验真；会话 cookie HttpOnly/Secure/SameSite=Strict＋落盘 12 小时滑动过期；写操作 CSRF 头，退出登录单独豁免并注明理由）、自检三档（只读档真跑、探针档建会话→切模型→删探针全链、人工档固定明示）、连接管理全套 API（含云电脑规格增补的 POST /api/companion/connections 创建端点；写令牌走备份→只改一行→验活→不过自动回滚）、模块开关（经控制通道；关审批 API 层强制二次确认）、版本数据（只两行口径＋升级/回滚命令文本） |
| front/static/（index.html 9,537B＋app.css 11,287B＋app.js 31,437B） | 面板真页：浅色运维面（#F5F6F8 底、主题蓝 #0052D9、标尺间距）、双方式登录分段控件、五页全功能接 §4 契约 API、动效按批准样稿口径（切页淡入上滑/按压 .98/开关曲线/错峰）＋prefers-reduced-motion 降级；零外部资源（全文 grep `http` 命中 0）、零假数据（缺字段降级或不渲染） |
| modules/（五脚本，原样） | 与生产原件**逐字节一致**（拉回后 cmp 全等），md5：write_gate `85ad41dfb963a3e992a87a7bc7383e73`、overview `772f485fd2e49b785cc42088aa33762e`、box `96ac5d7956061874694eabd43dc15fcf`、oneday `d6d59d719ba8329c0e12ff87ecd7a02f`、device `6e46398832b0e2fe6b5186dd3a0d7d61` |
| tests/ | supervisor_selftest.py、front_selftest.py、run_local_stack.py、run_bridge_selftests.sh＋四份桥自测与两个假模块 |

## 2. 验证结果（合计 132 项自测全过、0 失败）

| 验项 | 验法 | 结果 |
|---|---|---|
| 监督者自测 | 真监督者进程＋假模块（tests/supervisor_selftest.py） | **12/12**：拉起、kill -9 自动拉回（新 pid、restarts≥1）、崩溃循环退避并标 crash-loop、期望状态落盘且重启监督者后保持、SIGTERM 退出码 0 且无孤儿 |
| front 自测 | 假 Hermes＋真 front 进程（tests/front_selftest.py） | **24/24**：双方式登录、cookie 属性、CSRF 拦截/放行、改密码后新旧对照、限速（5 次 401 后第 6 次 429）、info 形状与控制通道缺席时 unknown 降级、连接创建/VPS 凭据验活失败回滚/GitHub 凭据验活失败回滚且 .env 逐字还原、自检只读档＋探针档全链、关审批无确认 409、控制通道断时开关诚实 503、版本实际值取不到时 null、退出销会话 |
| 桥自测（overview） | 对镜像内模块副本跑其自带 selftest | **8/8** |
| 桥自测（device） | 先起模块副本再打其自带端到端 selftest（该自测的设计就是打活桥） | **11/11** |
| 桥自测（oneday p2/p3） | 对模块副本跑其自带 selftest | **34/34、25/25** |
| write-gate fail-closed | 无 Hermes 代码环境起模块副本实打 | /status 返回 supported=false、数据端点 409、错钥 401、进程不崩——环境不对只报不支持、不绕过；**真 Hermes 代码下的 pending/裁决全环留 M1 回归门** |
| 全栈本地演练 | 真监督者＋真五模块＋真 front＋假 Hermes（tests/run_local_stack.py） | **18/18**：五端口全活；聚合 info 五态正确（审批 degraded＝本地无 Hermes 代码、云电脑 degraded＝假厂商钥、其余 up）；经 front 关/开 device 模块全链通；kill -9 oneday 后监督者自动拉回；SIGTERM 后六个端口全关 |
| 面板托管 | front 实起后 curl | GET / 与 /companion/ 均 200 返回真页（9,537B）、/static/app.css 200；app.js 过 node --check |
| 镜像构建 | 本机新装 docker（vfs 驱动）后三次拉基础镜像 | **未成**：Docker Hub 两次（TLS 握手超时／token EOF）、DaoCloud 镜像一次（分层 EOF）——本机出站大文件传输被掐，与既往记录一致。Dockerfile 已静态复核（路径/入口与现行五桥在同镜像上的实证形态一致）；**镜像体积**：基础镜像 3.18 GB（服务器只读实测）＋本层约 0.55 MB（工程树 495,624 字节）→ 成品约 **3.18 GB**，实测值待 M1 在服务器 build 后回填（服务器已有基础镜像，build 为纯增量、不动线上容器） |

**本地启动一条命令**：`python3 ~/workspace/hermes-deploy/companion/tests/run_local_stack.py`（全栈演练，18 项检查）；单件：`tests/supervisor_selftest.py`、`tests/front_selftest.py`、`tests/run_bridge_selftests.sh`。

## 3. 面板五页数据接通状态

| 页 | 接通情况 |
|---|---|
| 状态总览 | 数据全走 /info＋/modules＋/resources＋自检摘要，接口层已验（含 RSS、运行时长、重启计数、日志尾转发）；页面渲染待 M1 后浏览器实跑复核（本地仅源码＋托管层验） |
| 配置自检 | 只读档与探针档均真跑验过；人工档三项固定明示；结果落盘 companion-state |
| 连接管理 | 清单/创建/凭据/验活/断开全 API 已验，失败回滚路径实测；**成功路径的真实外部验活**（真 GitHub 令牌、真 Box 密钥、真 VPS 代理端点）本地无真凭据，未验，留窗口期 |
| 模块开关 | 经控制通道真开关 device 验过；关审批二次确认在 API（409）与页面（弹窗）双层 |
| 版本对齐 | 只两行已落；Hermes 实际版本取不到时如实显示「未能自动检测」（S8 降级路径已验） |

## 4. 与规格的偏差（3 处，均已在代码/ compose 注释中标明）

1. **companion.env 注入方式**：规格 §3.1 compose 写 env_file 平铺——实现改为整文件只读挂载＋监督者按段解析分发。理由：env_file 会把五段钥先平铺进监督者自身环境且同名键有覆盖风险，与 §2.3「按段注入、不给其他子进程」冲突时以后者为准。
2. **退出登录豁免 CSRF**：伪造退出只是滋扰不是越权，其余所有写操作仍强制 CSRF 头。
3. **VPS 云电脑的 config 条目**：凭据验活通过后只生成 pendingConfigEntry 记录、未真写 Hermes config.yaml——config 写面无损性本就是未实测项（云电脑规格未实测 #2），不在 M0 擅自落刀；GitHub/Simular 两条的 .env／companion.env 写面已按纪律全实做。

## 5. M1 切换前风险清单

1. **镜像未实 build**（见 §2）：M1 第一步在服务器 `docker build` 后先 `docker run` 冒烟再进切换流程；风险低（入口形态与现行五桥同镜像实证一致）但未经手就是未经手。
2. **S1 线上 nginx conf 全文未亲读**：M1 第一步按规格在服务器 diff 线上 conf 与 §1.3，出入以线上为准。
3. **S2 write-gate 代码级耦合**：伴生形态下（监督者注入 PYTHONPATH/HERMES_HOME）pending 列表/详情/裁决全环未验，M1 回归门必过项；本地只验到 fail-closed。
4. **S3 oneday 公网回环**：本地演练走 127.0.0.1 假 Hermes；生产 HERMES_BASE_URL 是公网域名，伴生与 hermes 同 compose 网络后的出网/DNS 路径未实测。
5. **S10 双挂载只读视角**：本地无 Docker 未验；M1 起容器时验，不可用按 §2.3 预案退化并登记。
6. **S9 内存总量**：五模块＋front 同容器稳态/峰值 RSS 未压测，1 GB 上限仍是估值，M1 切换后首日盯总览页 RSS 行。
7. **S6 面板会话安全走查**：登录代验＋会话落盘＋CSRF 的组合只过了功能验，未做专门安全评审；M1 前建议补一轮（重点：钥不进日志/错误回显——代码已按此写，属复核项）。
8. **S7 连接管理三项未证**：伴生内跑 `hermes mcp test` 的等价性、Notion 授权粘贴回退、GitHub 令牌是否必须重启 Hermes 才生效——页面文案已按保守口径（待重启生效）写，不承诺即时。
9. **面板未做浏览器实跑**：五页 JS 逻辑仅过语法检查与接口契约对照，M1 切换后须人工逐页点一遍（尤其登录双方式与开关弹窗）。
