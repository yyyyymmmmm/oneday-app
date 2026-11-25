# WEBLOGIN-133 部署报告（伴生 1.0.33，2026-11-12）

用户拍板：网页端登录改认用户自己那把密码（伴生面板密码），不再输 Hermes 部署密码。

## 改动
- front 新增 `POST /api/companion/web-login`：入参 {password}；每次现读
  companion-state/password.json、走与面板登录同一 scrypt 校验与同一限速池
  （5 次/300 秒/IP，第 6 次起 429）；验过后在服务器内网调
  `POST http://hermes:9119/auth/password-login`（容器网络名 hermes——伴生
  容器内 127.0.0.1:9119 不可达，实测 000；hermes:9119 实测 200），把 9119
  的 Set-Cookie 原样透传给浏览器，回 {ok:true}。错密码 401 通用文案；
  部署凭据未配 500；9119 异常 502。
- 部署凭据落点：生产 companion.env [front] 段新增两个变量（变量名
  HERMES_DASHBOARD_USER / HERMES_DASHBOARD_PASSWORD，值不记此报告），
  由凭据库程序化拷贝注入；模板 companion.env.example 已同步记名不记值。
  front 进程 environ 实读长度 5/20 与凭据库一致。
- 版本 1.0.32 → 1.0.33（Dockerfile ARG、本地与生产 compose 镜像标签＋
  COMPANION_VERSION、生产 env [global] COMPANION_VERSION 四处同改）。
- 网页端（oneday-web）：密码登录改单密码 → web-login → reveal 取钥；
  登录页删用户名字段，文案改「和伴生面板同一把」。已构建部署，
  线上 JS md5 与本地产物逐字一致（4aa20f7c…），旧哈希文件已清。
- 自测：tests/front_selftest.py 新增 FakeDashboard＋web-login 两项，
  全套 35 passed / 0 failed。

## 对齐与部署前检查
- 生产 front.py md5 与本地改前逐字一致（6189dc57…），确认同版才动手。
- 部署后：内存 55%（<80%）；Hermes StartedAt 逐字不变
  （2026-11-10T14:21:47.024396739Z）；伴生 /api/companion/health 200、
  五模块全 up；front 新 md5 7780a7a4…。

## 验收（临时密码全链，用户真实密码未动）
1. 生产 password.json 备份 sha256 = da54296f…（与部署前实读一致）。
2. 容器内用 front --set-password 设临时密码后，公网实测：
   web-login 临时密码 → 200 {ok:true}＋会话 Cookie 落罐；
   带 Cookie GET /api/sessions → 200 真数据；
   POST /api/env/reveal → 200，钥长度 64。
3. web-login 错密码 → 401；面板 /api/companion/login 错密码 → 401（回归）。
4. 连错 5 次 401，第 6 次用对密码 → 429（与面板同池同阈值）。
5. 测毕 password.json 原件恢复，sha256 回读 da54296f… 与备份逐字一致。
   真实密码成功路径由「同代码路径临时密码全链＋哈希原件字节级恢复」证明。
6. /app/ 公网 200；dist 对凭据库 4 项真实值程序化 grep → 0 命中。

## 回滚点
- /root/companion-133-deploy-20261112/：docker-compose.yml.1.0.32、
  companion.env.1.0.32、front.py.1.0.32、password.json.bak。
  回滚＝compose 镜像标签改回 1.0.32＋env 恢复＋docker compose up -d companion。
- 构建目录 /root/companion-133-build/。

## 遗留
- iOS App 密码登录仍走 9119 部署密码（本单未动 App，按简报口径留主线决策）。
- 限速桶按来源 IP 计：验收时本机出口 IP 的桶被打热 300 秒，用户手机
  出口 IP 不同、未受影响。
