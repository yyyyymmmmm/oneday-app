# 生成线写死模型修复＋伴生 1.0.38 部署报告（2026-11-12 夜）

## 结论先行

**已修复并上线。** 伴生桥写死的 `GEN_MODEL = "deepseek-flash"` 改为读环境变量 `ONEDAY_GEN_MODEL`（缺省回落 `claude-sonnet-4-6`），env 已显式落值 `claude-sonnet-4-6`；伴生升 **1.0.38** 部署完成。部署后手动触发动态＋点子各一轮：两轮都完整跑通生成管道、**零 billing 错误、非 failed**（均为 `empty` 终态——管道跑完但无新产出，见验收节说明）。今早 07:30 起点子/动态定时轮将走新模型，不再撞 DeepSeek 402。Hermes 全程未动、StartedAt 逐字未变。

## 一、改动（逐字 diff，全桥仅一行）

生产文件从运行中 1.0.37 容器抽出打补丁，diff 恰为一行（第 1832 行）：

```diff
-GEN_MODEL = "deepseek-flash"
+GEN_MODEL = os.environ.get("ONEDAY_GEN_MODEL", "claude-sonnet-4-6")
```

- 镜像内 Python 编译校验通过；在新镜像里直接执行该行实测：无 env → `claude-sonnet-4-6`；env 给值 → 听 env。
- 今后换生成模型只改 companion.env 一行＋重启伴生，不再动代码。
- 本地工作区副本已同步同一行改动（`companion/modules/oneday_bridge.py`），`companion.env.example` 已补 `ONEDAY_GEN_MODEL=claude-sonnet-4-6` 示例行。

## 二、部署（叠层法，未用过期 companion-build 目录）

- 构建：`FROM oneday/companion:1.0.37`＋COPY 补丁文件 → `oneday/companion:1.0.38`（sha256:2517e9e4…）。构建目录 `/root/genfix-1038`（含原文件 `oneday_bridge.orig.py` 与 Dockerfile 留底）。
- 配置三处编辑：
  - `docker-compose.yml`：image → 1.0.38、`COMPANION_VERSION=1.0.38`；
  - `companion.env`：第 4 行 `COMPANION_VERSION=1.0.38`；第 56 行（[oneday] 段内、HERMES_BASE_URL 之后）新增 `ONEDAY_GEN_MODEL=claude-sonnet-4-6`。
- `docker compose up -d` 重建容器，五桥（writeGate 8643／overview 8644／box 8645／oneday 8646／device 8647／front 8650）全部正常起服。

## 三、五层对齐验收（吸取 1.0.37 inode 事故教训，查到进程层）

| 层 | 实测 |
|---|---|
| 镜像 | 运行容器 image＝`oneday/companion:1.0.38` |
| compose | image 与 COMPANION_VERSION 均为 1.0.38 |
| companion.env（宿主机） | COMPANION_VERSION=1.0.38、ONEDAY_GEN_MODEL=claude-sonnet-4-6 |
| 进程 environ | supervisor(pid 1) COMPANION_VERSION=1.0.38；front(pid 18) COMPANION_VERSION=1.0.38；**oneday 桥(pid 14) environ 实有 `ONEDAY_GEN_MODEL=claude-sonnet-4-6`** |
| 接口层 | 两生成端点 POST 均回 202 且 history 落新条目（下节） |

注：companion.env 编辑用了 sed -i（inode 5387893→5388510），因编辑发生在容器重建**之前**、重建时 bind 按路径重新解析，且进程 environ 层已实证新值生效，无 16:18 式漏层。

## 四、数据层验收（手动触发回读 data.json history）

| 轮次 | 结果 | 说明 |
|---|---|---|
| 动态 feedGen（manual，第 19 条） | status=**empty**，produced=0，备注「候选全部被编辑环退稿」 | 管道完整走完 规划→选题→著帖→编辑环，终局是内容质量门退稿，**不是 failed、无 402**（昨日同触发死在第一步规划步） |
| 点子 ideasGen（manual，第 8 条） | status=**empty**，produced=0，error=None | 管道跑通、无任何错误；夜间无新素材可成卡 |

两轮终态均为 `empty` 而非 `ok`：该管道的状态词里 `empty`＝「跑完但零产出」，与 `failed`（步级报错）严格区分；验收标准「不许是 failed、无 billing 错误、produced 可为 0」满足。生成模型路径已实证复活——同一批触发在旧代码下必死于第一步 402。

## 五、红线核对

- Hermes StartedAt：部署前＝部署后＝`2026-11-10T14:21:47.024396739Z`，逐字未动；Hermes 未重启、网关配置未碰。
- 服务器内存：全程约 57%（4392/7725 MB），远低于 80% 红线。
- 正常业务容器未动；施工中误起的一个无钥匙试运行容器（funny_lehmann，桥全部 fail-closed 未起服）已删除。

## 六、回滚点

- 旧镜像保留：`oneday/companion:1.0.37`（sha256:8616161a…）。
- 配置备份（服务器 `/www/dk_project/dk_app/companion/`）：
  - `docker-compose.yml.bak-1.0.37-20261112`
  - `companion.env.bak-1.0.37-20261112`
- 回滚动作：恢复两备份 →`docker compose up -d` 即回 1.0.37 原状。
