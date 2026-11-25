# 三方版本兼容与能力协商契约（#3 / #23）

状态：**已拍板（上架前基准口径）**  
适用三方：OneDay iOS App、Hermes API Server、Companion 伴生服务

## 1. 核心原则

1. **能力位协商优先，版本号只做底线兜底**：绝不要求 App、服务端、伴生三方同步发版。所有新功能一律通过 `GET /v1/capabilities` 的 `features` 布尔位声明，客户端未检测到对应能力位时自动隐藏入口或降级旧路径。
2. **向后兼容窗口（N-1 / N-2）**：服务端与伴生升级后，必须至少兼容前 **1~2 个**已发布的 App 正式版本；新增字段一律可选，禁止删除或变更既有字段语义。
3. **三态版本门禁**（客户端单源：`Sources/OneDayCore/ReleaseGatesAndHealth.swift` 中 `VersionCompatibilityGate`）：

| 状态 | 触发条件 | 客户端行为 |
| :--- | :--- | :--- |
| `compatible` | `appVersion >= recommendedAppVersion`（或未配置推荐线） | 正常运行，无打扰提示。 |
| `upgradeRecommended` | `minAppVersion <= appVersion < recommendedAppVersion` | 顶部/设置页展示可关闭的软提示，引导升级，不阻断使用。 |
| `incompatible` | `appVersion < minAppVersion` | 连接流硬拦截，明确提示最低要求版本号并引导升级（仅限破坏性协议变更或高危安全修复）。 |

## 2. 三方信息发布单点

- **Hermes API Server**：通过 `GET /v1/capabilities` 发布 `features`（功能级能力位，如 `settings_registry`、`options_card`、`self_reactions`、`push_tokens`）与 `endpoints`。
- **Companion 伴生服务**：通过伴生 info 接口发布 `minAppVersion`（底线版本）与 `recommendedAppVersion`（推荐版本），以及服务存活状态。
- **OneDay App**：连接阶段读取版本门禁并运行 `VersionCompatibilityGate.evaluate(_:)`，运行时按 `CapabilityNegotiation` 判定逐项能力可用性。
