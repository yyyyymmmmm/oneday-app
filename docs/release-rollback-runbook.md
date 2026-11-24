# OneDay 发版分级放量与回装手册（第五批 #7）

## 1. 功能开关（Feature Flags）
- 客户端通过 `CapabilityModels.featureFlag(_:)` 统一读取服务端 `/capabilities` 下发的布尔开关（现已接入 `settings_registry`、`options_card`、`self_reactions`）。
- 原则：新特性默认由服务端开关门控，线上异常时先关远端开关止血，无需等待重新打包发版。

## 2. 上一版可回装路径
1. **保留构建产物**：每次发布归档对应的未签名/已签名 IPA（含版本号 `CFBundleShortVersionString` 与 `CFBundleVersion`）及对应 git tag/commit SHA。
2. **回装前数据兼容性**：SwiftData 本地库（`ChatThread`/`ChatEntry`）只做向后兼容的增量可选字段变更，禁止破坏性删列，确保回装上一版可直接冷启不闪退。
3. **快速回退操作**：
   - 如仅 UI/交互开关问题：关闭服务端对应 `feature_flag`，客户端下次拉取 `/capabilities` 即刻回落旧路径。
   - 如二进制崩溃/严重回归：从上一版归档 IPA 直接覆盖安装，或用上一版 git commit 重新打包（将 `CFBundleVersion` 递增 1 以便侧载/TestFlight 直接覆盖安装）。
