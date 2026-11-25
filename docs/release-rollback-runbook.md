# OneDay 发版分级放量与回退手册（#18）

## 1. 一级止血：远端功能开关（秒级回退，无需发版）
- 客户端通过 `CapabilityModels.featureFlag(_:)` / `CapabilityNegotiation` 统一读取服务端 `GET /v1/capabilities` 下发的布尔开关（现已接入 `settings_registry`、`options_card`、`self_reactions`、`push_tokens` 等）。
- 线上某新特性异常时，优先在服务端关闭对应特性开关，客户端下次刷新 `/v1/capabilities` 自动回落旧路径。

## 2. 二级回退：App 上一版可回装路径（10 分钟内恢复）
1. **发版前必须归档**：每次发版保留以下三件套，缺一不可：
   - 已签名 IPA（记录 `CFBundleShortVersionString` 与 `CFBundleVersion`）；
   - 对应 Git tag / commit SHA；
   - 对应 dSYM 符号表（供崩溃堆栈还原）。
2. **本地数据向后兼容红线**：SwiftData 模型（`ChatThread` / `ChatEntry`）只做增量可选字段变更，禁止破坏性删列或改类型，确保回装上一版可直接冷启不闪退。
3. **执行回装步骤**：
   - **TestFlight / 侧载回装**：基于上一版归档 tag 重新出包，将 `CFBundleVersion` 递增 1 后覆盖安装（保留用户本地数据，不需卸载）。
   - **App Store 线上止血**：在 App Store Connect 立即暂停分阶段发布（Pause Phased Release），随后提交基于上一版稳定 tag 递增 build 号的热修包走加急审核。

## 3. 服务端补丁回退
- 部署新版本 `server/patches/` 前，先备份原目录与 `/opt/data` 状态目录。
- 异常时切回上一版 `hermes-deploy-*.tar.gz` 并重启网关，执行 `server/verify.sh` 确认 `/health` 与 `/v1/capabilities` 返回 200。
