# 伴生面板真页渲染异常诊断（2026-11-10 21:4x，只读诊断，未动生产）

## 一句话结论

**真 bug，非截图伪影**：面板页 `index.html` 用相对路径引用 `app.css`/`app.js`，而 front 只在 `/static/`、`/companion/static/` 前缀下发静态文件——浏览器按页面地址解析出的 `/companion/app.css`、`/companion/app.js` 在线上实测均为 **404**。CSS 与 JS 双双没加载：全页显隐只靠 CSS 类 `.hidden{display:none!important}`，样式一缺，登录区、密钥字段、登录后整壳五页全部按原始 DOM 上下堆叠裸排，即用户截图原貌。

## 证据

1. **源码对照**（`front/static/index.html`）：
   - L7 `<link rel="stylesheet" href="app.css">`、L188 `<script src="app.js"></script>`，均为相对引用，无 `<base>`。
   - 显隐机制：`#appView` 初始带 `class="app-shell hidden"`、`#keyField` 带 `hidden`，五页签靠 `.page{display:none}`/`.is-active` 切换——**全部依赖 app.css 的一条 `.hidden` 规则**（`app.css` L15：`.hidden{display:none!important}`）。HTML 里没有用 `hidden` 属性兜底。
   - `app.js` 的切换逻辑本身没问题：启动段（文件末尾）先查 `/api/companion/session`，未登录 `showLogin()`、已登录 `showApp()`；分段按钮切换 password/key 两字段。JS 没跑时这些都不发生，页面停在原始 DOM 状态。
2. **服务端路由**（`front/front.py` do_GET，约 L916–925）：只认 `/`、`/companion`、`/companion/`（发 index.html）与 `/static/*`、`/companion/static/*`（发静态文件），其余非 API 路径一律 404。页面从 `/companion/` 打开时相对引用解析为 `/companion/app.css`、`/companion/app.js`，正好落在 404 区；从 `/companion` 或 `/` 打开解析结果同样不命中静态前缀。
3. **线上实测**（2026-11-10 21:43 CST 前后，经公网）：
   - `GET /companion/app.css` → **404**；`GET /companion/app.js` → **404**。
   - `GET /companion/static/app.css` → **200**，内容完整（含 `.hidden` 规则）——文件在、服务能发，只是页面的引用路径指错了门。
4. **截图逐项吻合无 CSS 渲染**（用户 21:38 真机图）：品牌「知」无蓝底方块（CSS 里是 40px 蓝色圆角块）、正文通栏白底（CSS 应为 #F5F6F8 灰底＋白卡片描边阴影）、「Hermes 本体」是浏览器默认大标题（CSS 里 h2 只有 15px）、眼睛按钮成了输入框旁独立灰钮（CSS 里应绝对定位叠在输入框内）、导航页签是散排默认按钮（CSS 应为侧栏/横滚条）、总览停在静态占位「正在读取状态…」（JS 未运行、数据从未拉取）。
5. **伪影排除**：iOS 全页长截图只截已生成盒子的内容，`display:none` 元素不会出现在长截图里；且 404 是当下可从另一网络路径独立复现的实测，不是设备端偶发。故排除「全页截图把折叠区拍进来」的解释。

## 为什么此前没被发现

M0/M1 的面板验证全走 API 与登录端点（curl 级），M1 报告已自记遗留「面板五页未做浏览器逐页实跑」。front 自测的静态托管冒烟只验了 `GET /` 与 `/companion/` 返回 200，**没验页面引用到的资源按浏览器解析后的地址是否 200**——引用路径与服务前缀的错位就从这条缝漏过去了。

## 最小修法（建议，本轮未动手）

改 `front/static/index.html` 两处引用为带前缀的相对路径：

- `href="app.css"` → `href="static/app.css"`
- `src="app.js"` → `src="static/app.js"`

这样从 `/companion/` 打开解析为 `/companion/static/...`、从 `/` 打开解析为 `/static/...`，两种入口都命中 front 现有静态路由，front.py 与 nginx 均零改动。（备选：给 front.py 加 `/companion/app.css` 等别名路由，改动面更大，不推荐。）

配套补验（防再漏）：front 自测加一条断言——按浏览器解析口径取页面引用的 CSS/JS 地址（`/companion/app.css` 对应的修正后地址）必须 200 且 Content-Type 正确；发版验收加一次真浏览器打开未登录页只见登录卡的实跑。

## 部署方式

静态文件是 **打进镜像的**（Dockerfile `COPY front/ /opt/companion/front/`，compose 没有把 front 目录做卷挂载），所以改完源码后需要：在服务器侧重打伴生镜像并重建 companion 容器（`docker compose build companion` 后 `docker compose up -d companion`），**要重启 companion 一次**（其内五桥模块随之短暂中断，量级同 M1 两次重建的约 10 秒；Hermes 本体不碰）。front 的 `_static` 是每请求现读磁盘、无进程内缓存，但读的是镜像内文件，故不存在「只换文件不重启」的路径。
