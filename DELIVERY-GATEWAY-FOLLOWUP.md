# 网关页补三件交卷报告

## 一、任务清单与完成状态

**落了 1 件、缺了 2 件**

- ❌ 第1件：连接耗时数值行
- ❌ 第2件：切换网关操作
- ✅ 第3件：清除认证信息

---

## 二、逐件达标证据

### 第1件：连接耗时数值行（未落，缺字段）

**缺失原因**：`ServerStatus` 模型中没有延迟/连接耗时字段。

**核查过程**：
- 读取 `Sources/OneDayCore/HermesModels.swift:20-135` 中的 `ServerStatus` 结构体定义
- 模型包含字段：version, releaseDate, configVersion, gatewayRunning, gatewayState, platforms, latestConfigVersion, canUpdateHermes, overall, components, disk, memory
- **未找到**：latency、delay、responseTime、connectionTime 或任何表示连接耗时的字段

**红线遵守**：按简报红线规定「延迟值必须取现有网关状态模型里的真实字段；若模型里确实没有延迟字段，不许编假数据」，此件不落码。

**待定条件**：需服务端在 `GET /api/status` 回执中补充延迟字段（建议字段名 `latency` 或 `connection_latency_ms`，单位毫秒），客户端模型同步扩展后方可落地呈现。

---

### 第2件：切换网关操作（未落，缺机制）

**缺失原因**：全仓查无现成网关切换机制。

**核查过程**：
- 执行 `grep -r "切换网关|switchGateway|selectGateway|changeGateway" --include="*.swift"`，返回 `No files found`
- 查看 `Sources/OneDayApp/GatewayView.swift` 完整实现（1-372行），未见切换网关入口
- 查看 `Sources/OneDayCore/GatewayChannels.swift`（网关渠道模型），仅为展示用只读模型，不含切换逻辑

**现状判定**：当前 App 只支持单一网关配置（通过连接页配置 baseURL + apiKey），无多网关切换能力。

**待定条件**：需产��层面先定义网关切换需求（是否支持多网关配置保存、切换时是否需要重新鉴权等），再设计切换机制与数据层支持。

---

### 第3件：清除认证信息（已落）

**落点证据**：
- **文件**：`Sources/OneDayApp/GatewayView.swift`
- **新增 Section**：第 250-274 行，包含 Button(role: .destructive) + footer 说明文案
- **接入路径**：第 373 行调用 `appState.localStore.clearCredentials()`
- **真实清除路径**：`Sources/OneDayApp/LocalStoreCoordinator.swift:45-48`，调用 `KeychainStore.clearAll()`

**diff 摘要**：
```
+ Section {
+     Button(role: .destructive) { pendingAction = "clearAuth" }
+     // 按钮内容：垃圾桶图标 + "清除认证信息" + 红色文字
+ } footer: {
+     Text("将移除本地存储的 API 密钥和服务器地址...")
+ }

+ dialogTitle/dialogButton/dialogMessage 增加 "clearAuth" 分支
+ confirmationDialog role 判断加入 pendingAction == "clearAuth" 条件
+ perform() 函数第 349-353 行处理清除逻辑
```

**可核行为**：
- 按钮位置：列表底部独立 Section，在系统资源区之后
- 按钮样式：Button(role: .destructive)，系统自动应用红色 destructive 样式
- 无额外红色容器：符合简报要求「不许另加红色容器」
- 确认对话框：点击后弹出二次确认，role: .destructive
- 清除路径：`AppState.localStore.clearCredentials()` → `KeychainStore.clearAll()`（Sources/OneDayApp/LocalStoreCoordinator.swift:47）

---

## 三、总结

- **完成 1/3**：清除认证信息已按标准落地
- **阻塞 2/3**：连接耗时与切换网关均因数据层/机制缺失无法落地
- **零改动情况**：本交卷有逐条证据（第3件 diff + 落点行号 + 路径行号），不属于零改动交卷

**下一步建议**：
1. 服务端补充延迟字段后，第1件可快速落地（审计文档已提供完整方案，见 DELIVERY-GATEWAY.md 第四节）
2. 第2件需产品定义需求范围后再设计实现
