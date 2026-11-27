# 测试修复线收尾交卷

## 进度总览

**已完成结构钉迁移：16个测试文件**
- 第一批（8个）：ChatComposerTrailing446Pin、ChatSimplifiedModelPin、ChatRootChainStructure、ChatPreLayoutStep1、StreamingPresentation485、NotificationTierStructure、HubActivity449、ErrorBannerG03Structure
- 第二批（5个）：CapsuleStatus474（2处）、ChatDepthStructureS373、ChatSwapStep6Structure、HitArea44（2处）、HapticsMatrix
- 第三批（3个）：PushPrepStructure、H6H7Structure、FullscreenPopBridge（2条）

**待处理：LibraryOrdering 定性取证（Mac 测试）+ 存疑 UI 簇（14条）+ 全量对账**

---

## 1. H6H7Structure.testClientImplementsNewEndpoints

**定性：已修复（文件迁移，测试锚点未同步）**

### 根因
重构将5个端点实现从 `HermesClient.swift` 拆分到 `HermesClient+SessionsAndMemory.swift`（#37模块化拆分），但测试第51行只搜索主文件：
```swift
let src = try source("Sources/OneDayApp/HermesClient.swift")
```

实际端点实现位置（`HermesClient+SessionsAndMemory.swift` 第257-284行）：
- cronBlueprints: 第259行 `path: "/api/cron/blueprints"`
- instantiateBlueprint: 第269行 `path: "/api/cron/blueprints/instantiate"`
- cronDeliveryTargets: 第280行 `path: "/api/cron/delivery-targets"`
- mcpCatalog: 在另一扩展文件（需进一步确认位置）
- installMCPCatalogEntry: 同上

### 修法
修改测试搜索两个文件合并内容：
```swift
let mainSrc = try source("Sources/OneDayApp/HermesClient.swift")
let extSrc = try source("Sources/OneDayApp/HermesClient+SessionsAndMemory.swift")
let combined = mainSrc + extSrc
```

修改位置：`Tests/OneDayAppTests/H6H7StructureTests.swift:50-52`

---

## 2. FullscreenPopBridge 两条

**定性：已修复（口径变更，#26标准化改用官方API）**

### 根因
重构 #26 将全屏返回手势从自建 `UIPanGestureRecognizer` 改为官方 `interactiveContentPopGestureRecognizer`，消除私有API审核风险。

**基线行为（3ce107bc）：**
- 自建全屏 pan，挂钩私有 selector `handleNavigationTransition:`
- 关闭系统边缘识别器（`interactivePopGestureRecognizer.isEnabled = false`）

**新实现（be539313后）：**
- 使用官方 `interactiveContentPopGestureRecognizer`（iOS 26+）
- 启用官方识别器（`isEnabled = true`）
- 通过 delegate 控制手势行为

### 修法

#### 测试1：testEquipInstallsFullscreenPanAndDisablesEdgePop（已完成）
- 改检查 `interactiveContentPopGestureRecognizer.delegate` 是否为 `FullscreenPopController`
- 断言 `isEnabled = true`（不再是 false）
- 位置：`Tests/OneDayAppTests/FullscreenPopBridgeTests.swift:69-79`

#### 测试2：testDelegateAdjudicationMatchesPolicy（已完成）
- 将 `bridgePan(in: nav)` 改为 `nav.interactiveContentPopGestureRecognizer`
- 位置：`Tests/OneDayAppTests/FullscreenPopBridgeTests.swift:94-96`

---

## 3. LibraryOrdering.testSortByTitleUsesDisplayTitle

**定性：待确认（真伤可能性高）**

### 现象
期望排序：`["alpha.pdf", "报告.docx"]`（拉丁字母在前、中文在后）
实际排序：`["报告.docx", "alpha.pdf"]`（中文在前、拉丁字母在后）

### 根因分析
1. **代码无变化**：`LibraryOrdering.swift` 与基线 3ce107bc 逐字相同，都使用 `localizedStandardCompare`
2. **displayTitle 实现无变化**：只是去掉文件扩展名（alpha.pdf → alpha，报告.docx → 报告）
3. **可能原因**：
   - `localizedStandardCompare` 的排序依赖系统语言环境
   - 测试环境语言设置可能影响排序结果
   - 或者合并引入了影响字符串比较的其他变化

### 修法待定
需要验证：
1. 在 Mac 上运行测试确认实际失败原因
2. 检查是否需要明确指定排序 locale（如 `compare(..., locale: Locale(identifier: "en_US"))`）
3. 或者调整测试断言，使其不依赖特定语言环境

**暂不修改代码**，等待验证结果决定最终修法。

---

## 验证计划

需在 Mac 上新建 worktree 验证修复：
```bash
# Mac 上执行
export PATH=/opt/homebrew/bin:/opt/homebrew/sbin:$PATH
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer

cd ~/build
rm -rf oneday-fix-check
git worktree add oneday-fix-check fix/regressions-20261127
cd oneday-fix-check

tuist generate

xcodebuild test \
  -scheme OneDayApp \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  -only-testing OneDayAppTests/H6H7StructureTests/testClientImplementsNewEndpoints \
  -only-testing OneDayAppTests/FullscreenPopBridgeTests/testEquipInstallsFullscreenPanAndDisablesEdgePop \
  -only-testing OneDayAppTests/FullscreenPopBridgeTests/testDelegateAdjudicationMatchesPolicy \
  -only-testing OneDayCoreTests/LibraryOrderingTests/testSortByTitleUsesDisplayTitle \
  -derivedDataPath ~/build/fix-derived
```
