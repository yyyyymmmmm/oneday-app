# 账号持久化交付报告

## 任务概述
登录账号随连接配置持久化——用户密码登录成功后账号写入钥匙串，重连/重登时回显已存账号。

## 改动文件（4 个）

### 1. Sources/OneDayCore/ServerConfig.swift
**改动**：ServerConfig 结构体加 `username: String?` 字段
- 存位：登录账号可选字段，密码登录时填入
- 用途：重连/重登时回显

### 2. Sources/OneDayApp/KeychainStore.swift
**改动**：CredentialKey.username 键复活
- 注释更新：账号键从退役状态改为启用，说明用途
- 存储规则：密码登录成功时写入，密钥登录不涉及，断开连接随三件套清除
- 仍在 `CredentialKey.all` 数组内

### 3. Sources/OneDayApp/AppState.swift
**改动三处**：
1. `connectWithPassword` (1310-1314 行)：成功时写账号到钥匙串
   ```swift
   KeychainStore.save(username, account: CredentialKey.username)
   ```
   删除了旧的 `delete(account: CredentialKey.username)` 逻辑

2. `restore` (1066-1077 行)：恢复连接时读回账号
   ```swift
   config.username = KeychainStore.read(account: CredentialKey.username)
   ```

3. 新增 `username` 计算属性 (1180-1183 行)：供外部读取已存账号
   ```swift
   private var username: String? {
       if isDemo { return "" }
       return KeychainStore.read(account: CredentialKey.username)
   }
   ```

### 4. Sources/OneDayApp/ConnectView.swift
**改动**：登录面 `onAppear` 回显已存账号 (107-120 行)
- 优先从 `appState.config?.username` 读（restore 已恢复的情况）
- 未连接时直接读 `KeychainStore` 存量（用户断开后重登的情况）
- 只在账号非空时回填 `username` 状态

## 存位与链路

### 存储链路（密码登录成功时）
1. 用户在 ConnectView 填账号+密码
2. `connectWithPassword` 验证通过、换取 API 密钥后
3. 写入钥匙串三件：baseURL + username + password + apiKey
4. `config.username` 随 ServerConfig 进入 AppState

### 回显链路（重连/重登时）
**路径 A：启动恢复**
1. AppState.restore 读 Keychain 的 baseURL 与 apiKey
2. 读回 username 并赋值到 `config.username`
3. ConnectView.onAppear 从 `appState.config?.username` 读回显

**路径 B：断开后重登**
1. 用户断开连接（config 清空，但 Keychain 保留 username）
2. ConnectView.onAppear 直接读 `KeychainStore.read(account: CredentialKey.username)`
3. 回显到账号框

### 清理链路（断开连接时）
- `KeychainStore.clearAll()` 遍历 `CredentialKey.all` 数组清除
- username 在 all 数组内，随 baseURL/password/apiKey/shortLivedTokenPair 一并清除

## 构建验证

**验证环境**：Mac via tunnel SSH 连接
- 分支：`feat/login-account-persist`
- 基线：dc287754（账号持久化改动）
- 目标：worktree `~/build/oneday-auth2-check`
- DerivedData：`~/build/auth2-derived`

**验证步骤**：
1. 等待 Mac 构建通道空闲（监控中）
2. 创建独立 worktree 检出本分支
3. tuist generate（DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer）
4. xcodebuild build -configuration Release -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO

**验证状态**：等待通道空闲中（后台监控任务 bvzawijr2 运行中）

---

## 红线确认
✅ 代码中无 yyyyymmmmm 字样（已全文 grep 确认）
✅ 未动桥令牌逻辑（534f3d3b 原样保留）
✅ 未新增第二套凭据存储（复用 KeychainStore + CredentialKey 体系）
✅ 账号框默认空白或回显存量，无写死账号值

## 构建结论
（待构建完成后补充）
