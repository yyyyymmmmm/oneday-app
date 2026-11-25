# RATE-LIMIT-134 部署报告（伴生 1.0.34，2026-11-12）

用户 02:56 真机被网页端登录 429 挡住。定因与修复如下。

## 定因
front.py 登录限速按连接 peer（`self.client_address[0]`）记账。公网流量全经
本机 nginx 反代，peer 恒为 127.0.0.1——所有来源共用一个失败桶。1.0.33
登录桥验收时故意连错 5 次烧满该桶，真用户随即被连坐锁死。LOGIN_FAILS
为进程内内存字典。

## 修法（front.py）
- 新增共用小函数 `Handler._client_ip()`：peer 为 127.0.0.1/::1 时取
  X-Real-IP 头作记账键（无头回落 peer）；peer 非本机时不信任转发头、
  用 peer 本身。
- `_login` 与 `_web_login` 两处记账同改用该函数，仍共用同一失败池
  （键 `{ip}:{method}` / `{ip}:password` 形态不变）。
- nginx 无需改动：生产 conf 的 `/companion/` 与 `/api/companion/` 两条
  location 早已带 `proxy_set_header X-Real-IP $remote_addr;`（部署时
  实读确认），故未动 conf、无 realip 备份产生。

## 自测
- front_selftest 新增 3 条断言：①本机 peer 带 X-Real-IP 连错 5 次→第 6 次
  429（桶跟头走）；②换一个 X-Real-IP 登录成功（不连坐）；③web-login 与
  _login 共用同一 per-IP 桶（已锁 IP 走 web-login 直接 429）。
  front 全套 38 passed, 0 failed（原 35＋新 3）。
- 桥全套自测：device_sync、rendition 两套 FAILED 与本次无关（不引用
  front、本机出站环境既存问题，1.0.29 期已登记）；其余全过。

## 部署与验收证据
- 动手前：生产容器 front.py md5 与本地同版（7780a7a4…）确认后才施工；
  内存 55%（<80%）。
- 镜像 oneday/companion:1.0.34（5bcaca2d1e73），构建目录
  /root/companion-134-build/；生产 compose 仅改镜像标签与
  COMPANION_VERSION 两处。
- 部署后：容器内 front.py md5 = 3bf027d8…（与新本地逐字一致）；
  COMPANION_VERSION 实读 1.0.34；五模块端口响应在位（8645/8646/8647
  health 200，8643/8644 为需鉴权的 401＝端点存活）；内存 55%；
  Hermes StartedAt 逐字不变（2026-11-10T14:21:47.024396739Z）。
- 进程重启即清内存限速账——**用户当前的锁已随部署解除，现在即可
  重新登录**。
- 公网回归（克制试探，未烧真桶）：/app/ 200、/companion/ 登录页 200、
  web-login 错密码 1 次 → 401（不是 429，计数正常）。

## 回滚点
/root/companion-134-deploy-20261112/：docker-compose.yml.1.0.33、
front.py.1.0.33、up.log。回滚＝compose 镜像标签与 COMPANION_VERSION
改回 1.0.33＋docker compose up -d companion。
