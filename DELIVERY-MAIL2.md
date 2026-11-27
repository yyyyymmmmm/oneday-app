# 邮件面起草与发送批准链·交卷

## 端点查清结果

服务端 `server/patches/mail_gateway.py`（CAPABILITIES #66，包 2.18.7）**只实现了只读面**：

### 现有能力（已实现）
- 账号 CRUD：`POST /v1/mail/accounts`（创建）、`GET /v1/mail/accounts`（列表）、`PATCH /v1/mail/accounts/{id}`（更新）、`DELETE /v1/mail/accounts/{id}`（删除）
- 连接测试：`POST /v1/mail/test-connection`（IMAP + SMTP 双向测试）
- 消息同步：IMAP 轮询器自动同步、`GET /v1/mail/messages`（统一收件箱）、`GET /v1/mail/messages/{account_id}/{folder}/{uid}`（详情）
- 草稿模型：`POST /v1/mail/drafts`（创建草稿）、`GET /v1/mail/drafts`（列表），草稿表字段含 `to/subject/body_text/status/approval_ref/send_error`

### 缺失端点（本次停手原因）
**发送端点不存在**：
- 无 `POST /v1/mail/send` 或 `/v1/mail/drafts/{id}/send` 端点
- SMTP 客户端（`_default_smtp_factory` 与 `_test_smtp`）只在连接测试中调用 `login()`，从未调用 `sendmail()` 或任何发送方法
- 草稿表虽有 `approval_ref/send_error` 字段预留，但无任何代码写入这些字段、无状态机从 `draft` 转 `sent`
- 无发送执行器（类比同步的 `_exec_sync` vault executor）

### 诊断
mail_gateway.py 文档（L1–L7）明确：
> Bar 1 (queue 181, hub mail proposal): the server-side data source only -- account store, connection testing, polling IMAP sync into a local cache, unified-inbox queries and account CRUD. **No page, no AI tools**; those are later bars on top of this module.

**只读数据源已完整交付，发送能力属后续棒次、尚未实现。**

---

## 起草与批准链路（本次未实现）

按用户要求停手、不自造接口、不假面。若发送端点存在，计划实现三件：

1. **起草入口**（邮件详情面）：
   - 回复按钮（预填收件人 = 原发件人、主题 = "Re: {原主题}"、正文 = 引用原文）
   - 转发按钮（预填主题 = "Fwd: {原主题}"、正文 = 转发原文）
   - 调用 `POST /v1/mail/drafts` 创建本地草稿（`source: "reply"/"forward"`，`reply_to_message_id` 记原消息）

2. **批准链**（同聊天审批卡）：
   - 发送前调用待补的 `POST /v1/mail/drafts/{id}/send-approval`（拟案端点）创建批准卡
   - 批准卡进 `AgentHubStore.pendingApprovals`（与 `ApprovalCard` 同一数据源）
   - 用户批准后调用 `POST /v1/mail/drafts/{id}/send`（拟案端点）实际发送
   - 驳回则取消、草稿留 `status: "draft"`

3. **发送结果回写**：
   - 成功：草稿 `status: "sent"`，详情面显示「已发送」
   - 失败：草稿 `send_error` 记原因（同步口径），详情面显示失败原因

---

## 构建验证（未执行）

服务端缺发送端点，客户端实现无法验收，构建验证未执行。

若端点补全后需验证：
- SSH 进 Mac（`~/workspace/.nas/mac-via-tunnel`，非登录 shell 先 `export PATH=/opt/homebrew/bin:/opt/homebrew/sbin:$PATH; DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`）
- 新建 worktree `~/build/oneday-mail-check`，检出 `feat/mail-compose` 尖
- `tuist generate && xcodebuild build -scheme OneDayApp -configuration Release -destination generic/platform=iOS -derivedDataPath ~/build/mail-derived CODE_SIGNING_ALLOWED=NO`

---

## 结论

**停手交卷**：服务端只交付了只读邮件面（#66，包 2.18.7，2026-11-26 在役），发送能力属后续棒次、端点不存在。

客户端起草与批准链无法落地，不许自造接口、不许假面。待服务端补全发送端点后再接本分支继续实现。

---

**交卷人**：司礼监掌印大总管魏忠贤（奴才三狗）  
**交卷时间**：2026-11-27
