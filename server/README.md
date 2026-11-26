# hermes-deploy — Hermes + OneDay 服务端部署包

让任何部署者装出与现行 instance **功能一致**的 Hermes 服务端：上游镜像本体不改，OneDay 需要的全部服务端能力（配对认领、消息反应、写闸审批、总览等）都登记在本包里——补丁、服务定义、能力注册表、探针，一处不落。包的规矩见 [RULES.md](RULES.md)，完整部署指南见 [DEPLOYMENT-GUIDE.md](DEPLOYMENT-GUIDE.md)，脱敏回填清单见 [BACKFILL.md](BACKFILL.md)，能力清单见 [CAPABILITIES.md](CAPABILITIES.md)。

## 前置

- 一台 Linux 宿主机，装有 Docker 与 Docker Compose v2、`curl`、`sha256sum`、`python3`。
- 能拉取上游镜像 `nousresearch/hermes-agent:v0.23.0`（本包只对这个版本负责）。
- 一个部署目录（自选），布局为：`docker-compose.yml`、`patches/`、`data/`（Hermes 数据，首次启动自建）。
- 无需 companion 镜像：伴生容器已于包 2.0.0 整容器退役，写闸/总览等全部能力均为 Hermes 网关进程内模块，部署终局为单容器（见 DEPLOYMENT-GUIDE.md §1、§3）。
- 自己的凭据保险库：所有密钥只在部署时从保险库填入 env，**不要把真值写进任何会提交的文件**（键名全表见 `services/env.template`）。

## 一条命令安装

```bash
# 1) 把 services/hermes-compose.template.yml 放到部署目录、改名为 docker-compose.yml，按 env.template 备好凭据环境变量
# 2) 应用包内补丁并验收:
./install.sh /path/to/部署目录
```

install.sh 是幂等的：已是目标状态的文件自动跳过、不重启；应用前自动备份（`.bak-YYYYMMDD-deploypkg`）；补丁原地改写保 inode；改后自动重启 hermes 并逐端点健康检查（8642/9119＋8643 退役观察窗＋容器内回读哈希），任一步失败自动回滚并报错。第一次接触某个部署先 `DRY_RUN=1 ./install.sh <部署目录>` 看差异再真跑。

## 校验

```bash
./verify.sh /path/to/部署目录
```


## 升级与回滚口径

- **包升级**：拿到新版包后重跑 install.sh 即可（幂等＋备份＋双验）；版本号含义见 RULES.md §2。
- **Hermes 上游升级**：不要直接换镜像。先按 RULES.md §3 在包内完成 target 更新与补丁 rebase、探针全齐，再应用。
- **回滚**：install.sh 失败自动回滚；人工回滚＝把部署目录 `patches/*.bak-YYYYMMDD-deploypkg` 原地写回同名文件、重启 hermes、跑 verify.sh 复核。
- **补丁退役**：能力被上游合入后按 RULES.md §4 从包里移除，属正常演进。

## 目录结构

```
manifest.yaml                    包版本、目标 Hermes 版本、组件清单（路径/哈希/功能）
patches/                         补丁与网关模块现状正本（与现行 instance 哈希一致，全量清单与哈希见 manifest.yaml）
services/                        compose 模板（仅 hermes 单服务）与 env 键名模板
install.sh                       幂等安装（校验版本→备份→保 inode 应用→重启→健康检查→失败回滚）
verify.sh                        能力探针（只读）
CAPABILITIES.md                  能力注册表：功能 → 服务端依赖 → 探针 → 缺失时 OneDay 的表现
RULES.md                         先入包后应用等规矩
DEPLOYMENT-GUIDE.md              完整部署指南：架构/路由/凭据/验收清单/故障排查（§13 FAQ）
BACKFILL.md                      脱敏回填清单：从本仓出包上生产前必办的五件回填
```

注：本目录是部署包的脱敏分发副本，实例盘点、部署日记与验收输出等运维档案不随仓分发；根下 docker-compose.yml 为旧双容器形态副本，与现行版不一致、勿用，现行形态见 services/ 模板。
