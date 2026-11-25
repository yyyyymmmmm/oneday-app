# 伴生 1.0.7 部署记录（2026-11-11，用户新规：伴生自动修复自动部署）

为 OneDay 0.39.0 点子扩容＋0.40.0 目标分类流部署伴生侧，两批改动
均在 oneday_bridge.py 一个文件内（与运行中 1.0.6 逐文件 md5 比对，
其余镜像文件全部同哈希）：
- 点子生成段换代：素材七源装配（S 两段摘要／G 近况／K 任务实质／
  R 记忆摘录）、落卡三门（锚点门／动作门自检／硬门）、锚点级去重、
  账面新增 droppedReasons 四分计＋materialNotes 按源分记；p5 自测 21 项。
- 目标桥面：goal.category 枚举字段与校验、goal_task_links 端点与
  删目标级联、关联任务完成自动记事实条目；p6 自测 26 项。

部署：基线 1.0.6；回滚基线 /root/companion-107-deploy-20261111/
（1.0.6 的 compose、companion.env、两容器 inspect、运行容器内
oneday_bridge.py.106、本次 build.log/up.log 与 build-106 源码包
src.tgz）。回滚＝基线 compose+env 拷回 /www/dk_project/dk_app/
companion 后 docker compose up -d companion（镜像 1.0.6 仍在
服务器）。构建上下文 /root/build-107（build-106 副本仅替换
oneday_bridge.py，新文件 md5 77d4f182… 与本地工作树一致），
docker build --build-arg COMPANION_VERSION=1.0.7；生产 compose
镜像标签与 COMPANION_VERSION、companion.env [global]
COMPANION_VERSION 三处同步改 1.0.7。只重建伴生容器，Hermes
StartedAt 前后不变（2026-11-10T14:21:47Z），内存部署前 50.5%、
部署后 50.4%。

自测：部署前本地（TZ=Asia/Shanghai）全套跑通，只增不减：
overview 8／p2 34／p3 26／p4 19／p5 21／p6 26／write-gate 22／
ledger 60／device 桥 OK／device_sync OK／model-combos OK。
部署后在运行容器内对已上线模块本体复跑 p5 21/21、p6 26/26。

公网复验（App 同款单钥）：/api/companion/info 报 1.0.7、
hermesUp=true、五模块全 up、oneday degraded=false；台账
/ledger/summary 总 33 条、degraded=false、采集器心跳新鲜，
sessions 与 kanban 两源均 ok:true（与 1.0.6 一致）。

点子面冒烟（只读，未触发真生成轮）：GET /ideas/generation
账面可读，history 旧记录正常（droppedReasons/materialNotes 为
新字段，旧记录无此键属预期，自 2026-11-11 07:30 定时轮起的
新记录开始带）；GET /ideas 列表旧数据正常解析；GET /goals
回空表（生产尚无目标，category 面随 App 0.40.0 发出后启用）。
