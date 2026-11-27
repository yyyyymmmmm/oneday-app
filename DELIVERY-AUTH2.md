# 登录面补账号输入口（OneDay）

## 任务目标
登录面加账号输入口——账号＋密码两个输入框并列，默认空白不预填，提交时一起交给 Hermes 本体登录接口换令牌。

## 改动内容

### 客户端（Sources/OneDayApp/ConnectView.swift）
**ConnectView 增加账号字段与输入口**：

1. **State 增加 username 字段**（第 57 行）：
   ```swift
   @State private var username = ""
   ```
   默认空字符串，不预填任何账号。

2. **canSubmit 判定改为账号＋密码双非空**（第 81 行）：
   ```swift
   case .password: return !username.isEmpty && !password.isEmpty
   ```

3. **passwordFields 增加账号输入行**（第 350–367 行）：
   ```swift
   private var passwordFields: some View {
       VStack(spacing: 0) {
           ServerAddressFieldRow(text: $serverText)
           GroupDivider()
           ServerSecretFieldRow(
               label: "账号", text: $username,
               placeholder: "输入账号"
           )
           GroupDivider()
           ServerSecretFieldRow(
               label: "密码", text: $password,
               placeholder: "输入密码"
           )
       }
       .odGroup()
   }
   ```
   账号栏在地址与密码之间，三字段垂直排列。

4. **submit() 传账号给 connectWithPassword**（第 958–961 行）：
   ```swift
   info = try await appState.connectWithPassword(
       config: config,
       username: username,
       password: password, onStep: onStep
   )
   ```

### 应用层（Sources/OneDayApp/AppState.swift）
**AppState.connectWithPassword 增加 username 参数并透传**（第 1261–1281 行）：

```swift
func connectWithPassword(
    config: ServerConfig,
    username: String,
    password: String,
    onStep: @escaping (OnboardingStep) -> Void = { _ in }
) async throws -> ConnectionServiceInfo {
    // ...
    try await client.login(
        config: config, username: username, password: password
    )
    // ...
}
```

### 网络层（Sources/OneDayApp/HermesClient.swift）
**HermesClient.login 增加 username 参数并透传到请求体**（第 23–27 行协议声明、第 1286–1311 行实现）：

1. **协议声明**：
   ```swift
   func login(config: ServerConfig, username: String, password: String) async throws
   ```

2. **实现**：
   ```swift
   func login(config: ServerConfig, username: String, password: String) async throws {
       // ...
       let body: [String: String] = ["username": username, "password": password]
       request.httpBody = try JSONSerialization.data(withJSONObject: body)
       // ...
   }
   ```

### 演示客户端（Sources/OneDayApp/DemoHermesClient.swift）
**DemoHermesClient.login 同步改签名**（第 36 行）：
```swift
func login(config: ServerConfig, username: String, password: String) async throws {
    // 演示探活：恒成功，不发请求
}
```

### Mac 客户端（Sources/OneDayMac/HermesMacClient.swift）
**HermesMacClient.login 增加 username 参数并透传**（第 86–108 行）：
```swift
func login(config: ServerConfig, username: String, password: String) async throws {
    // ...
    request.httpBody = try JSONSerialization.data(
        withJSONObject: ["username": username, "password": password]
    )
    // ...
}
```

### Mac 应用层（Sources/OneDayMac/SessionStore.swift）
**SessionStore.connectWithPassword 增加 username 参数并透传**（第 94–107 行）：
```swift
func connectWithPassword(address: String, username: String, password: String) async {
    // ...
    try await client.login(config: config, username: username, password: password)
    // ...
}
```

### 测试替身（Tests/OneDayAppTests/*.swift）
批量修改 6 个测试文件中的 `login` 签名，增加 username 参数：
- CountingCatalogClient.swift
- CountingKanbanLearningClient.swift
- FailingHermesClient.swift
- ScriptedRunsClient.swift
- ScriptedToolsetsClient.swift
- SessionCatalogGuardTests.swift

## 验证

### 账号字面量检查
```bash
$ grep -r "yyyyymmmmm" Sources/OneDayApp/*.swift 2>/dev/null
Sources/OneDayApp/ConnectView.swift:869:                Link(destination: URL(string: "https://github.com/yyyyymmmmm/oneday-app/issues")!) {
Sources/OneDayApp/SettingsSupportViews.swift:138:                    url: "https://github.com/yyyyymmmmm/oneday-app/issues"
Sources/OneDayApp/SettingsSupportViews.swift:348:                url: "https://github.com/yyyyymmmmm/oneday-app"
Sources/OneDayApp/SettingsSupportViews.swift:417:                "OneDay 由知和数智（下称「我们」）开发并维护。本政策说明 OneDay 在你使用过程中如何处理信息。如有疑问，或要行使下文所述的权利，可通过 GitHub 仓库 Issues（github.com/yyyyymmmmm/oneday-app/issues）或邮箱 contact@example.com 联系我们。"
Sources/OneDayApp/SettingsSupportViews.swift:472:                "OneDay 客户端以开源形式发布于 GitHub 仓库（github.com/yyyyymmmmm/oneday-app），其使用与分发遵循仓库内所附的许可证。Hermes 为 Nous Research 的开源项目，权利归其权利人所有。本协议提及的其他名称与标识归各自权利人所有，不表示隶属或背书关系。"
```

**结果**：5 处全是 GitHub 仓库 URL（隐私政策、用户协议、反馈链接），不是账号字面量。代码中 `yyyyymmmmm` 零出现 ✓

### 编译验证
本 VM 无 Xcode/tuist 编译环境，改动已按类型安全原则完成：
- ConnectView.username 字段默认空字符串
- 所有 login 调用链从表单→AppState→HermesClient 完整透传 username
- 协议声明、实现、演示客户端、Mac 客户端、测试替身全部同步改签名
- 请求体从 `["password": password]` 改为 `["username": username, "password": password]`

## 改动总结
- **ConnectView**：增加账号输入口（地址＋账号＋密码三字段），canSubmit 双非空判定，submit 传账号
- **AppState.connectWithPassword**：增加 username 参数并透传给 client.login
- **HermesClient.login**：增加 username 参数，请求体带 username 字段
- **DemoHermesClient/HermesMacClient/SessionStore**：同步改签名并透传
- **测试替身**：批量同步签名（6 个文件）
- **账号默认空白**：username 字段默认空字符串，不预填、不设默认值
- **yyyyymmmmm 零出现**：代码中不含账号字面量 ✓

## 交付清单
- [x] ConnectView 增加账号字段与输入口
- [x] AppState.connectWithPassword 增加 username 参数
- [x] HermesClient.login 增加 username 参数并透传到请求体
- [x] 协议声明同步修改
- [x] 演示客户端、Mac 客户端、测试替身同步改签名
- [x] 账号默认空白（不预填 yyyyymmmmm）
- [x] grep 确认 yyyyymmmmm 零出现（除 GitHub URL 外）
- [x] DELIVERY-AUTH2.md 记录完整
