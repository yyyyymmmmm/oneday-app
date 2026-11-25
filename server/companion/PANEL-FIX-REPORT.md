# 伴生面板 CSS/JS 404 修复报告（2026-11-10 21:46–21:52 CST）

> 结论：**修复完成并已上线。** 根因即诊断定案（PANEL-RENDER-DIAGNOSIS.md）：`front/static/index.html` 相对引用 `app.css`/`app.js` 被浏览器解析为 `/companion/app.css`、`/companion/app.js`（404），真文件在 `/companion/static/` 下。改两处引用后公网按浏览器口径全 200、五桥带钥全 200、/health 200。五桥中断数秒级（<10 秒预期，见 §4）。唯一未在本轮完成的验收项：真浏览器截图实跑——本机无可用无头 Chromium（/opt/meta-chromium 被 Hatch WebGL 域策略门挡死、exit 13；无 playwright/puppeteer 二进制），需由主代理用其实时浏览器补拍一张登录页截图关账；其余证据链已等效闭合（见 §5）。

## 1. 改动点（最小面）

本地工程 `~/workspace/hermes-deploy/companion/`，同步到服务器构建区 `/www/dk_project/dk_app/companion-build/companion/`：

- `front/static/index.html` 两处：`href="app.css"` → `href="static/app.css"`；`src="app.js"` → `src="static/app.js"`。从 `/companion/` 解析为 `/companion/static/...`、从 `/` 解析为 `/static/...`，两入口都命中 front 现有静态路由。
- `tests/front_selftest.py` 新增断言（见 §2）。
- 版本号 1.0.0 → **1.0.1**：`Dockerfile` ARG、`docker-compose.yml` 镜像 tag 与 `COMPANION_VERSION` env（本地与服务器部署 compose 同步，服务器 compose 改前备份 `/root/m1-20261110/docker-compose.yml.bak-1.0.0`）。
- front.py、nginx **零改动**。

## 2. 自测

`tests/front_selftest.py` 新增 `check_page_assets()`：抓页面 HTML、正则提取 link/script 引用、用 `urljoin` 按浏览器口径相对页面 URL 解析、逐个断言 200 且 Content-Type 正确（css=text/css、js=javascript）。对 `/companion/` 与 `/` 两入口各一条。

本地实跑：**26 passed, 0 failed**（原 24 项全过＋新 2 项）。新断言对旧引用形态必然变红，正是防同类漏检复发的钉子。

## 3. 部署

- 开工内存：服务器 3862/7725MB ≈ 50%（红线 80% 未触）；Hermes 与其他容器全程未碰（事后验 `hermes Up 56 minutes`，为其自身此前批准的重启计时）。
- 服务器侧 `docker build -t oneday/companion:1.0.1` 成功（日志 `/root/m1-20261110/build-1.0.1.log`），新镜像 `ef44c88ec43f`。
- `docker compose up -d companion` 重建，新容器 StartedAt＝2026-11-10 21:48:26 CST，镜像 oneday/companion:1.0.1。

## 4. 中断量测

重建脚本内计时：自 `docker compose up -d` 发起至 front 在 8650 端口回 200 ＝ **2.19 秒**；整个重建 SSH 调用墙钟 5.8 秒，旧容器停机包含在该窗内——**五桥总中断数秒级（≲6 秒）**，小于事先告知的约 10 秒。Hermes 零中断。

## 5. 验收证据

- 公网浏览器口径：`GET https://hermes.example.com/companion/` ＝ 200，HTML 引用已为 `static/app.css`/`static/app.js`；解析后两资源均 **200**（css `text/css`、js `text/javascript`）。
- 公网实服内容核对：app.css 含 `.hidden{display:none!important}`（全页显隐所靠的那条规则）；app.js 含 showLogin/showApp 切换逻辑（8 处命中）。
- 五桥带各自服务钥本机直连各抽一端点：write-gate `/status` 200、overview `/notifications` 200、box `/box/status` 200（回厂商真状态 running、Box 名 main）、oneday `/health` 200、device `/health` 200。无钥时 8643/8644 回 401（鉴权在位、非故障）。
- 公网 `GET /health` ＝ 200。
- **未完成项（如实）**：真浏览器打开登录页的截图自查未做成——本机 Chromium 被运行环境策略门拦截、无其他无头浏览器二进制；已具备的等效证据如上（资源 200＋内容核对＋自测断言）。请主代理用实时浏览器补一张截图（预期：只显登录卡、品牌蓝块/分段控件样式生效、控制台无 404）后正式关账。

## 6. 回滚基线

- 旧镜像 `oneday/companion:1.0.0`（`c58a296f59b7`）原样保留在服务器镜像库；回滚＝部署 compose 两处版本号改回 1.0.0 后 `docker compose up -d companion`（备份 compose 在 `/root/m1-20261110/docker-compose.yml.bak-1.0.0`，旧 index.html 备份 `/root/m1-20261110/index.html.bak-1.0.0`）。本轮未动用。
