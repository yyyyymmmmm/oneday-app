# 中枢补件交付（UI2）

## 1. 邮箱面

- 查验结论：App 原先没有收件箱 API/Client；`compose_email` 仅调用系统邮件撰写面板，联系人邮箱只是通讯录字段，Gmail 连接器也不能作为收件箱。但仓库服务端 `mail_gateway.py` 已提供统一收件箱 `/v1/mail/messages`、单封详情 `/v1/mail/messages/{account_id}/{folder}/{uid}`，能力位为 `features.mail_gateway`（CAPABILITIES #66）。
- 本次新增只读邮件列表和详情读取 Client/View：列表显示发件人、主题、时间、摘要；点开后读取邮件头与正文。注册表输入改为 `mailDataSourceAvailable`，仅在 `/v1/capabilities` 真回读 `mail_gateway=true` 时长格，不再因恒 false 永久隐藏，也不在无能力部署上冒出空壳。
- 数据源：服务端 Mail Gateway 的同步缓存；邮件账户凭据仍由服务端 Credential Vault 管理，App 复用既有 Hermes Bearer 凭据，不新建凭据存储。App 当前只读；账户配置/维护使用服务端已有 API，本次未添加账户管理 UI。

## 2. 工作段与审核段

- 工作段现在固定呈现「当前活动」和「预定任务」两段。当前活动使用 `AppState.sharedLedgerStore()` 的服务端台账列表，沿用运行与日期流水、按天和会话聚合、条目详情与流水下钻；服务端列表出口已过滤 `activityExcluded` 及 `kind=job, origin=bridge_self` 的内部系统轮次，客户端不再重复过滤正常流水。预定任务沿用 `AppState.sharedCronStore()` / `CronStore.hubGroups`，其既有 `HubCron` 分组过滤 `is_system` 系统任务；空列表、加载态仍保留段头。
- 审核段现在固定呈现「当前待审批」和「审批记录」两段。待审批依据 `AgentHubStore.approvalState` 显示真队列及真实状态（读取中、无待批、未启用、通道不可用或失败）；记录仍由原 `grantsState`、`decisionHistory`、`resolvedLines`、`activityGroups` 真源合并倒序呈现。
- 云主机面未改动：仍是 `HubBrowserSection` → `ComputerFaceView`，包含桌面真实截图/接管以及文件、终端分段，没有退回占位卡。

## 3. 红线与凭据

- 仓库扫描确认指定禁用字符串已无命中；涉及既有文档/支持文案的仓库标识一并泛化处理。
- 未新增凭据存储，也未改动现有钥匙串/桥凭据路径。

## 4. 构建验证

- 已尝试：`xcodebuild build -scheme OneDay -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO`
- 结果：未能执行构建；当前 worktree 容器没有 `xcodebuild`（shell 返回 `xcodebuild: command not found`，退出码 127）。因此不能报告编译通过；需在安装 Xcode 的 macOS 环境重跑该命令。相关 XCTest 也未能在本环境执行。
- `git diff --check` 通过。
- 提交状态：未提交。Git 无法在 worktree 共用仓库元数据目录创建 `index.lock`（只读文件系统，退出码 128）；当前环境不能写入 `.git` 元数据。

---

已由司礼监在 wt-ui worktree 完成提交：110b96f8
