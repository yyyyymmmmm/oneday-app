# oneday-console 抗升级检查单（可复用）

适用：Hermes 上游升级（换镜像版本／重建容器）前后，验证网页端插件 oneday-console 不被冲掉、全链仍通。本单由大活12 棒 6（2026-11-26）隔离副本演练实证后定版，后续每次升级照单逐项打勾。

原理一句话：插件不住镜像里——资产在数据卷 `data/plugins/oneday-console/`，启用登记在数据卷 `data/config.yaml` 的 `plugins.enabled`，镜像换版只换容器内文件、碰不到这两处；部署包再加双保险：install.sh 3f 每次部署幂等同步资产＋文本级确保启用登记，verify.sh 第 33 节常驻探针（哈希／启用／名册／资产路由）。

## 一、升级前

- [ ] 查服务器内存（118.24.41.52 超 80% 停手），确认现行 hermes 容器健康（`GET /health` 200）。
- [ ] 备份两份：部署目录整份（口径 `/root/pre-<版本>-deploy-backup-<日期>/`）＋数据卷内 `data/plugins/oneday-console/` 与 `data/config.yaml` 单独再拷一份。
- [ ] 记下当前值：镜像 tag、插件版本（`data/plugins/oneday-console/dashboard/manifest.json` 的 version）、三件资产 sha256（与部署包 manifest.yaml 登记值对平）。

## 二、升级动作

- [ ] 只换镜像／重建容器（`docker compose down` → 改 image tag → `up -d`），**不动数据卷、不删 data 目录**。
- [ ] 等容器健康：`GET /health` 200、dashboard 9119 可达。

## 三、升级后五项对账（逐项过，缺一不算完）

- [ ] **资产在位**：`data/plugins/oneday-console/dashboard/{manifest.json,dist/index.js,dist/style.css}` 三件在位，sha256 与部署包 manifest.yaml 登记逐字一致（不一致→跑 install.sh 整包部署，3f 会同步回）。
- [ ] **启用登记**：`data/config.yaml` 的 `plugins.enabled` 含 `oneday-console`（不在→install.sh 3f 文本级确保会自动补，改前有备份；或人工按同口径补行）。
- [ ] **名册在位**：dashboard 会话下 `GET /api/dashboard/plugins` 含 oneday-console 且 `source=user`（无会话的服务端核查走 web-login 等价链）。
- [ ] **资产路由**：`GET /dashboard-plugins/oneday-console/dist/index.js` 200，字节与包内一致。
- [ ] **真浏览器放行门**：打开 dashboard → OneDay 标签页在位且渲染 → 任选一面真数据走通（推荐诊断面「一键自检」六项全过：网关健康／能力／凭据链／名册／资产／定时任务）。

## 四、漂移处置（插件契约随上游演进时）

- 名册在位但标签不挂载：先对 manifest 结构与运行时注册法（`window.__HERMES_PLUGINS__`）是否被上游改动——插件产物与上游版本的对应关系记在部署包 manifest.yaml 的 web_plugins 注记里，漂移时按新结构改插件壳、逻辑核不动。
- dashboard 鉴权形态变化（会话/登录改版）：插件凭据流只依赖我方桥两端点（web-login／reveal），由桥的适配层吸收，插件面不直接依赖 dashboard 内部会话细节。
- 全链短期修不好：功能保底走路线 B（同域 `/oneday/` 独立 SPA 壳，页面逻辑与接口契约与插件版共用，只换壳），插件线单独修，不让功能面陪葬。

## 五、回滚

- [ ] 镜像 tag 改回升级前版本重建容器；插件目录与 config.yaml 用升级前备份还原；重跑第三节五项对账。

## 六、演练记录（棒 6，2026-11-26）

- 时间：2026-11-26 17:16–17:24 CST；全程日志在服务器 `/root/upgrade-drill-20261126.log`。
- 隔离副本：`/root/upgrade-drill-20261126`（生产部署目录整份复制；容器名改 hermes-drill、`network_mode: none`、mem_limit 1536m；全部检查经 `docker exec` 在副本内走 dashboard 登录链执行；演练毕已整目录删除）。
- 模拟方式：**换版变体未做成**——镜像站无 v0.24.0 tag（manifest unknown）、Docker Hub 直连超时，新版镜像拉不到；按拟案口径以「容器销毁＋重建（同 tag v0.23.0）」模拟升级（容器层全换、数据卷不动）。真实换版待网络可拉新版镜像时按本单第三节重跑 B 项即可，检查项不变。
- A 基线：副本启动后名册含 oneday-console（source=user）、资产路由 200、插件版本 0.6.1、资产 sha256 与数据卷文件一致、plugins.enabled 登记 1 行。
- B 升级模拟：`down` 销毁容器 → `up` 重建 → 名册／资产／版本／哈希**全不变**（插件住数据卷、容器重建零影响）✅。
- C 敌意用例 1（启用登记丢失）：删掉副本 config.yaml 的 `- oneday-console` 行并重启 → 名册变 absent、资产 404（consent 闸真实，失效形态与本单描述一致）；跑 install.sh 3f 段（自包内原文抽取、只指向副本）→ 登记自动补回、资产同步升至 0.7.0；重启后名册回 user、资产 200、index.js sha256 与包内 2.18.0 登记逐字一致 ✅。
- D 敌意用例 2（插件资产全删）：删掉整个 `data/plugins/oneday-console` → 跑 3f → 三件资产整套恢复（0.7.0）；重启后名册／资产正常 ✅。
- 生产实例未受影响：演练命令集只对 hermes-drill 操作，生产 hermes 健康在演练前后均 200。注：演练窗口内 17:20:08 生产容器有一次重启，经查为既有 prompt-refresh 看守 cron（每 10 分钟，`/root/prompt-refresh/watcher.log` 17:20:38 留痕「refreshed: gateway restarted after memory/config change」），与演练无关。
- 资源：演练期间宿主机内存峰值约 62%（4754/7725 MB），未触 80% 红线。
