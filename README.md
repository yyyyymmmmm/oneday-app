# OneDay

自托管 Hermes Agent 的全功能 iOS 客户端。用户在 App 内填入自己的
Hermes 服务器地址、面板账号与 API 密钥即可连接；聊天与状态走
服务端 API，管理功能分里程碑逐个点亮。

- 平台：原生 iOS（Swift 6 + SwiftUI，下限 iOS 26），Tuist 工程
- Bundle id：site.didichou.oneday
- 设计：礼记设计语言移植（纸墨为体、玻璃为用），主色腾讯蓝 #0052D9
- 服务端要求：Hermes v0.23.0（接口面按此版实测对接，见 docs/API-SURFACE.md）

## 构建

```sh
tuist generate   # 生成 OneDay.xcodeproj
```

用 Xcode 打开后选择 OneDayApp scheme 运行；单测在 OneDayCoreTests。

## 结构

- Sources/OneDayCore：纯逻辑（地址归一化、接口模型、SSE 解析、错误口径）
- Sources/OneDayDesign：设计令牌（蓝色令牌表、Mat/Elevation/Radius/Motion）与基础组件
- Sources/OneDayApp：界面与网络（连接页、总览、聊天、管理占位、设置）
- Tests/OneDayCoreTests：Core 单测

## 里程碑

- 里程碑 1（当前）：工程骨架＋连接登录（三步探活）＋状态总览＋聊天跑通
- 里程碑 2：管理面（模型与配置、记忆、技能、会话、定时、日志）逐个点亮

详见 docs/M1-NOTES.md。
