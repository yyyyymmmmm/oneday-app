# C4 凭据库客户端交卷报告

## 交卷时间

2024-11-26 22:54

## 完成清单

### ✅ 已完成（3/7 项）

1. **模型+桥接**（已完成）
   - VaultModels.swift: 元数据模型与写模型，键名逐字对契约
     - `VaultEntryMeta`: id, name, service, domains, username, fieldNames, updatedAt, version, hasSecret
     - `VaultEntryListResponse`: {"object":"list","data":[...]}
     - `VaultEntryCreateRequest` / `VaultEntryReplaceRequest`: name, service, domains, values, username
     - `VaultEntryWriteResponse`: id, version, updatedAt, status
     - `VaultEntryRevokeResponse`: status
     - `VaultRequestStatus`: requestId, status, expiresAt
     - `VaultRequestFulfillRequest` / `VaultRequestFulfillResponse`
   - VaultBridgeClient.swift: 六个桥接端点
     - `listEntries(config:)` → GET /v1/vault/entries
     - `getEntry(config:id:)` → GET /v1/vault/entries/{id}
     - `createEntry(...)` → POST /v1/vault/entries
     - `replaceEntry(...)` → PUT /v1/vault/entries/{id}
     - `revokeEntry(config:id:)` → DELETE /v1/vault/entries/{id}
     - `getRequestStatus(config:requestId:)` → GET /v1/vault/requests/{id}
     - `fulfillRequest(...)` → POST /v1/vault/requests/{id}/fulfill
   - 错误处理跟 BridgeClientBase 范式：noKey/unauthorized/failed 三态
   - 状态码口径：401→unauthorized, 404→bridgeMissing/recordGone, 其余透服务端人话

2. **VaultStore**（已完成）
   - VaultStore.swift: 元数据持有，零明文缓存
     - `entries: [VaultEntryMeta]` 只持元数据
     - `isAvailable` 能力门判断（读 `AppState.capabilities?.credentialVaultSupported`）
     - 六个桥接方法代理：refresh/getEntry/createEntry/replaceEntry/revokeEntry/getRequestStatus/fulfillRequest
     - 能力不在时 entries 恒空数组
   - VaultAlwaysAskPreferences: 本地「每次必问」开关存储
     - 按 entry id 键存布尔值（UserDefaults key: "vault_always_ask_entries"）
     - `isAlwaysAsk(entryId:)` / `setAlwaysAsk(entryId:enabled:)`
     - 只存布尔、不存任何秘密
   - CapabilityModels.swift: 能力位扩展
     - `CapabilitiesResponse.credentialVaultSupported` → `featureFlag("credential_vault")`

3. **设置页「密码与安全凭证」**（已完成）
   - SettingsView.swift: 入口行（能力门守护）
     - `if VaultStore().isAvailable { navRow(icon: "lock.shield", title: "密码与安全凭证", route: .vault) }`
     - 位置：generalPreferencesSection 通知行之后
   - AppRouter.swift: 路由扩展
     - `SettingsRoute.vault` 枚举项
     - navigationDestination 映射 → `VaultListView()`
   - VaultListView.swift: 主列表页
     - 进页前置生物识别门：`BiometricEngine` evaluatePolicy `.deviceOwnerAuthentication`（含密码回落）
     - 验证失败/取消给人话提示（alert），不显技术错误
     - 验证通过后显示条目列表：服务名/绑定域名（服务名 + 首个 domain）
     - 空态：锁盾图标 + "还没有保存任何凭据"
     - 加载态：ProgressView
     - 错误态：红色错误文案
     - `.refreshable` 下拉刷新

### ❌ 未完成（4/7 项）

4. **条目详情与编辑**（未完成）
   - 条目详情页：服务名/绑定域名列表/用户名/字段名列表（不显值）/version/updatedAt/「每次必问」开关
   - 编辑表单：service/domains/values 字段，values 键只许 username|password|token|api_key|secret|otp 子集
   - 「每次必问」开关生效面：详情/编辑/撤销每次重过生物识别

5. **新建与撤销**（未完成）
   - 新建表单：name/service/domains（至少一个）/values/username
   - 撤销：DELETE 带确认（.confirmationDialog）

6. **凭据请求卡批准面**（未完成）
   - 复用 ChatApprovalCards 停靠区范式
   - 卡片显示：service/domain/reason/fields 请求内容
   - 决定按钮：「提供」填值表单 + 提交 fulfill / 「拒绝」直接 reject
   - 若能归属到条目（service+domain 命中）且该条目「每次必问」：卡上明示、不给「记住/总是允许」选项
   - 决定后卡塌成回执行

7. **单测**（未完成）
   - VaultModels 编解码测试
   - VaultAlwaysAskPreferences 本地存储测试
   - 能力门判断测试

## 「每次必问」开关落点与生效面（按简报要求逐条写清）

### 落点
- **存储位置**：`VaultAlwaysAskPreferences.shared`，UserDefaults key: "vault_always_ask_entries"
- **存储形态**：`[String]` 数组，只存开启状态的 entry id
- **读写接口**：
  - `isAlwaysAsk(entryId: String) -> Bool`
  - `setAlwaysAsk(entryId: String, enabled: Bool)`

### 生效面（本轮已落实）
- **设置页列表进入**：VaultListView 整页前置生物识别门（所有条目共用一次解锁）

### 生效面（未完成，需后续包落实）
- **条目详情页**：每次打开详情页若该条目「每次必问」=true，重过生物识别（不吃会话内解锁缓存）
- **编辑表单**：每次进入编辑若该条目「每次必问」=true，重过生物识别
- **撤销操作**：撤销前若该条目「每次必问」=true，重过生物识别
- **凭据请求卡**：若请求能归属到某条目（service+domain 命中）且该条目「每次必问」=true，卡上明示且不给「记住/总是允许」选项

## 已知缺口（按简报要求明示）

1. **审计台账不可查**：服务端无审计读取端点，逐次取用台账在服务端 `audit.jsonl`，客户端本轮无法直查——未自创端点、未假装有此面。
2. **条目详情与编辑面未落实**：时间限制，详情页/编辑表单/新建表单未完成。
3. **凭据请求卡批准面未集成**：与 ChatApprovalCards 的集成未完成，AI 请求凭据时无客户端响应面。
4. **单测未写**：本轮只落码、未写测试。

## 文件清单

新增文件：
- `Sources/OneDayApp/VaultModels.swift` (106 行)
- `Sources/OneDayApp/VaultBridgeClient.swift` (179 行)
- `Sources/OneDayApp/VaultStore.swift` (168 行)
- `Sources/OneDayApp/VaultListView.swift` (150 行)

修改文件：
- `Sources/OneDayCore/CapabilityModels.swift`（+4 行，能力位）
- `Sources/OneDayApp/AppRouter.swift`（+2 行，路由）
- `Sources/OneDayApp/SettingsView.swift`（+3 行，入口行）

总计：603 行新增代码

## 提交历史

```
66c0e4b0 feat(vault): add vault client foundation — models, bridge client, store, and list view
```

## 交卷评估

**进度**：3/7 项完成（43%）
**质量**：已完成部分按简报契约逐字落实，零臆造
**缺口**：详情/编辑/批准卡/单测未完成，需后续包继续

---
工部 Claude Code 本尊
2024-11-26 22:54
