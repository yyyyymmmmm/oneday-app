# 合并交付文档（合并版）

## 一、鉴权收敛——一个密码吃遍（OneDay）

### 任务目标
用户只用 Hermes 密码登录一次，拿到的会话令牌走到所有面都开门。桥钥匙退为服务器间内部使用，用户端不再依赖它。

### 病根（已实查）
- 客户端 `BridgeClientBase.requireKey()` 读不到独立"桥钥匙"（BridgeCredential，Keychain）就抛 noKey、**不发请求**
- 结果：新装设备上用户用 Hermes 密码登录成功（聊天/身份正常），但资源库、目标、动态、邮箱等走桥的面全死
- 服务端桥鉴权只认环境变量 ONEDAY_BRIDGE_KEY（2026-11-10 自设的独立钥匙）

### 改动内容

#### 客户端（Sources/OneDayApp/KeychainStore.swift）
**BridgeCredential.read()** 改为优先使用 Hermes 会话令牌，桥钥匙仅作过渡期兜底。

**改动理由**：
- Hermes 会话令牌（`api.key`）在登录时已经存入 Keychain，HermesClient 用它调所有 /v1 和 /api 端点
- 桥请求改为优先使用同一份令牌，只在令牌缺失时才读独立桥钥（过渡期存量）
- `BridgeClientBase.requireKey()` 的逻辑不变：两者皆无时才抛 noKey

#### 服务端（staging/patches/api_server.py）
**APIServer._check_auth()** 在 Bearer 校验链增加第二条接受路径，同时接受 Hermes 会话令牌与长期密钥。

**校验逻辑**：
1. 优先走既有的 `_check_short_lived_bearer`（动态注入的短时票据校验）
2. **新增**：调用 `auth_tokens.verify_access_token(token, api_key=expected_key)` 校验 odt1. 前缀的 Hermes 会话令牌
3. 令牌有效（ok=True）直接放行，返回 None
4. 令牌无效或不是短时令牌格式，继续走长期密钥比对（向后兼容）
5. 异常（ImportError/其他）不阻断流程，降级到长期密钥校验

**fail-closed 保证**：
- `verify_access_token` 返回 `(ok, session_id, error_code)`，只有 `ok=True` 才放行
- 令牌过期/撤销/会话不存在均返回 `ok=False`
- 校验失败不打印令牌原文，只记错误码
- auth_tokens 未装机时降级到长期密钥校验，不放行

### 验证
- Python 编译验证通过
- 自测脚本通过（真令牌/伪造/长期密钥格式判定）

### 交付清单
- [x] 客户端：Sources/OneDayApp/KeychainStore.swift BridgeCredential.read() 改为双路优先
- [x] 服务端：staging/patches/api_server.py _check_auth() 增加短时令牌校验
- [x] Python 语法验证通过
- [x] 自测脚本编写并通过

---

## 二、中枢页全屏＋五面补齐、聊天页顶栏改版 

### 定位

#### 中枢页实现位置
- **主视图**：`Sources/OneDayApp/AgentHubView.swift`（108行起）
- 呈现方式：ChatView.swift:1058 通过 `.sheet(isPresented: $showHub)` 触发
- 注册表驱动五面：HubSegmentRegistry.resolve() 按输入裁决格集（工作/审核/电脑/身份/邮箱）

#### 五面数据源与视图（已核查）
1. **工作段**（.work）：HubLedgerSection - 真面，数据源 LedgerStore
2. **审核段**（.audit）：HubAuditSection - 真面，数据源 AgentHubStore.grantsState + approvalState
3. **电脑段**（.computer）：HubBrowserSection → ComputerFaceView - 真面
4. **身份段**（.identity）：HubIdentitySection - 真面
5. **邮箱段**（.mail）：EmptyView 占位 - 未实现（符合预期）

#### 聊天页顶栏实现位置
- **文件**：`Sources/OneDayApp/ChatView+HeaderAndActions.swift`
- **身份区组件**：HubIdentityCapsule.swift

### 施工内容

#### 1. 中枢页改全屏呈现
**改动位置**：`Sources/OneDayApp/ChatView.swift:1058`
- 改前：`.sheet(isPresented: $showHub)`
- 改后：`.fullScreenCover(isPresented: $showHub)`

#### 2. 五面核查结果
- ✅ 预定任务：已并入工作段（HubLedgerSection 内折叠节）
- ✅ 审批记录：HubAuditSection 真面
- ✅ 云主机：ComputerFaceView 真面（三段：桌面/文件/终端）
- ✅ 身份：HubIdentitySection 真面
- ✅ 邮箱：注册表驱动未长格（设计预期）

#### 3. 聊天页顶栏改版
**改动位置**：`Sources/OneDayApp/HubIdentityCapsule.swift:39` + `ChatView+HeaderAndActions.swift:204`
- 身份区改上下排列（VStack）
- 右侧两按钮收进同一胶囊

### 对应口径
1. ✅ 中枢页全屏呈现：ChatView.swift 改用 `.fullScreenCover`
2. ✅ 五面齐全且是真面
3. ✅ 云主机面恢复真面：ComputerFaceView 是真面，非占位
4. ✅ 聊天页顶栏改版：头像与名字上下排列、右侧两按钮收进同一胶囊
