# 伴生 1.0.23 部署报告：图片变体端点（§138 影音性能包）

- **版本**：1.0.22 → 1.0.23（镜像 oneday/companion:1.0.23，构建暂存 /root/build-1.0.23/，回滚点 /root/companion-123-deploy-20261111/）。
- **变更文件**：仅 `modules/oneday_bridge.py`（md5 `865928476cf56d03b9afcf0224f15a69`，本地仓库／构建暂存／在跑容器三方逐字一致）；另新增自测 `tests/oneday_bridge_rendition_selftest.py` 并登记进 `tests/run_bridge_selftests.sh`（自测文件不进镜像运行面）。
- **内容**：新增 `GET /media/rendition?path=&w=<360|1080|2048>&kind=<image|poster>`——Pillow 生成 JPEG 变体（EXIF 校正、长边 ≤w 永不放大、q80、pillow-heif 在位）、ffmpeg 首帧海报（10s 超时→502）；落盘缓存键＝sha256(路径＋mtime_ns＋size＋档位＋kind)[:32]；单飞＋全局并发 ≤2；内存 >85% 拒生成 503；路径纪律同 §125（根包含/敏感名 403/缺失 404/>100MiB 413/格式不支持 415）；响应 ETag＋immutable 缓存头、If-None-Match→304。二进制发送复用既有 `_send_bytes`（加可选 etag 参数）。
- **部署执行注记（如实）**：本包施工方（影音性能包分身）完成模块与自测后，部署已由主线侧按同一仓库树先行执行（容器 StartedAt 2026-11-11T09:33:45Z）；施工方未重复部署，改为全量回读验收（下列证据均为施工方亲验）。
- **验收证据**：
  - 自测：rendition 专测 22/22 PASS（生产容器同环境暂存副本：鉴权 401/逃逸 400/缺失 404/敏感 403/坏参 400/非图 415/ETag/immutable/长边 ≤360/不放大/缓存不重生成/304/海报 200/视频当图 415）。全套自测在干净环境（本机）复跑全绿——ledger 60/60、device_sync ALL PASS；容器内直跑时该两项红系端口与在跑生产模块相撞（ledger Part C 钉 8646）＋device_sync 已知跨日界 flaky，与本包无关。
  - 生产实拉（容器内 127.0.0.1:8646、桥钥取自进程 environ、未打印）：真图 /opt/data/screenshot_20261111_1709.png（68,026B）→ w=360 回 8,390B JPEG、w=1080 回 47,841B、w=2048 回 61,892B，均 200 image/jpeg；无钥 401；缓存目录 /opt/oneday-data/renditions/ 已落盘 3 键。
  - 红线：Hermes StartedAt 逐字不变（2026-11-10T14:21:47.024396739Z）；内存约 53%（4083/7725MB）；五模块在线。
  - 生产 /opt/data 浅层无 mp4/mov 样本，海报在生产实拉未验（自测已在同环境以 ffmpeg 生成样本验通），待 App 侧真机影音页验点覆盖。
- **回滚**：还原 /root/companion-123-deploy-20261111/ 的 compose 版本位至 1.0.22 并 `docker compose up -d` 只重建 companion；端点为纯新增，旧 App 不调用、无兼容面。
