# 五桥凭据分权轮换记录（审计 F03/R8 服务器侧，2026-11-10）

用户 2026-11-10 15:13 拍板「必改两件＋五桥凭据分权一起修」后执行。
顺序纪律：App 0.32.1/62 IPA 出包（CI 42774943285）后才动服务器钥匙，
防现装 0.32.0 在过渡期断桥；轮换全程 0.32.0/0.32.1 靠 App 侧旧钥
回退（0.32.1 起）或原钥（0.32.0 存的是同一把旧钥——轮换后旧钥在
桥侧已退役，**0.32.0 的桥功能自轮换完成起失效，须装 0.32.1 并导入
钥匙组**；0.32.1 未导入前靠回退读到旧钥同样会被桥拒——导入即解）。

> 更正口径（同日复核）：0.32.1 的回退读的是用户 Keychain 里的旧共用
> 钥值；服务器轮换后该值已被各桥拒绝，故「未导入前照常」只成立于
> 轮换完成之前。轮换后唯一通道＝导入 bridge-keys.txt（一次粘贴）。

## 轮换内容

- 五桥各生成独立随机钥（openssl rand -hex 32，服务器内生成、从未
  经过聊天/日志），各桥 env 变量改名：OVERVIEW_BRIDGE_KEY /
  ONEDAY_BRIDGE_KEY / WRITE_GATE_BRIDGE_KEY / BOX_BRIDGE_KEY /
  DEVICE_BRIDGE_KEY；桥代码读各自变量、fail-closed 不变。
- 旧 WRITE_GATE_KEY 从五桥全部 env 退役（grep 五文件 0 残留）。
- 逐桥进行：备份代码＋env（*.bak-20261110-f03，共 10 份）→换钥→
  `docker compose up -d` 只重建该桥（env_file 变更必须重建、
  restart 不重读——P1 教训）→验 own 通/old 拒，再下一桥。
- Hermes 本体与其 API 钥未动（容器 Up 24h 连续）。

## 验收矩阵（服务器本机探针，30 格全对）

| 桥＼钥 | overview | oneday | writegate | box | device | 旧共用钥 |
|---|---|---|---|---|---|---|
| overview /overview | **200** | 401 | 401 | 401 | 401 | 401 |
| writegate /status | 401 | **200** | — 见注 | 401 | 401 | 401 |

注：矩阵脚本实测 writegate 行＝401/401/**200**/401/401/401，oneday 行
＝401/**200**/401/401/401/401，box 行＝401/401/401/**200**/401/401，
device 行＝401/401/401/401/**404**（鉴权通过后路径不存在）/401。
结论：每桥仅自己的钥可通，其余四把新钥＋旧钥全拒。MATRIX ALL PASS。

## 一处服务端例外（明示）

overview 桥的 pendingApprovals 需调 write-gate /status——分权后该
调用改用 write-gate 自己的钥作为**服务端服务凭据**（存
overview-bridge.env 的 WRITE_GATE_BRIDGE_KEY，仅服务器内、App 永不
持有）。轮换后实测 overview 待批数与 write-gate /status counts 一致
（均 0），失败时桥日志留痕、不再静默归零。

## 其余实测

- box 轮换时首探因 MCP 建连慢（>2 秒）误报 FAIL，复探 own 200 /
  old 401 / health mcpSession up——桥无恙，探针等待时长问题。
- oneday 数据零扰动：轮换后新钥读 /ideas 仍 3 张生成卡；
  /health degraded:false（F04 止血同日先行部署，见 DESIGN-V4 §60.1）。
- 内存：全程 51–52%，红线内。
- 钥匙组交付文件：~/workspace/your_files/bridge-keys.txt（0600，
  格式与 App BridgeKeyImport 解析器逐字对齐，本地按解析器规则复验
  5/5、0 未识别行）。服务器暂存 keys.env 已 shred。

## 追记 2026-11-10 16:2x：0.33.1 单钥入口上线（nginx，双模过渡中）

- 用户 16:08 定版后翻转：hermes.example.com 四条桥路由（write-gate/overview/box/oneday）加 auth_request——内部位置 /__bridge_auth 把客户端 Authorization 原样转 127.0.0.1:8642/v1/models 验（强制 GET、无 body），200 才放行；放行后 proxy_set_header Authorization 换成该桥服务钥字面值（从各容器 env 在服务器内脚本注入，未经任何聊天/文件明文；线上 conf 已 chmod 600）。
- 过渡双模：每桥带命名 fallback（@writegate_fallback 等，配置内有 [TRANSITION dual-mode] 醒目注释）——auth 未过时 error_page 401 403 接去 fallback 把客户端原 Authorization 直通＋rewrite 复刻前缀剥离（命名 location 不许 proxy_pass 带 URI，首版 nginx -t 就此报错、已按此法修好）。**撤销条件：用户装 0.33.1 并确认桥功能正常后，删四处 error_page 行与四个 fallback 块、nginx -t＋reload。**
- 备份：hermes.example.com.conf.bak-20261110-singlekey（0600，改前原版）；回滚＝覆盖回该备份＋nginx -t＋reload。
- 验矩阵（公网实测全绿）：四桥 ×（Hermes 登录钥 200／桥服务钥直通 200／随机错钥 401／无钥 401）；POST approve 探针两路均达桥逻辑层（不存在 id 回 404、非 401）；回归 /v1/models 200、/health 200、Dashboard / 200。施工期内存 51.6%（3988/7725MB），未触红线；未动 Hermes 本体、五桥 env、device-bridge（未公网注册、本轮不处理）。
- App 0.33.1 侧：七客户端统一读 api.key；bridge-keys.txt 自此无用，待用户装 0.33.1 确认后删除（App 已不读分项钥，留着也无害）。
