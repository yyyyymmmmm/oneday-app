# SF Symbols 横扫清单

## 修复记录
1. **HubIdentityCapsule.swift:83** - 孤括号语法错（已修复）
2. **MacHubMailView.swift:15** - `envelope.badge.slash` 不存在（已改为 `envelope.open`）

## 全仓符号清单

### iOS 端符号（Sources/OneDayApp/）
- sparkle ✓ 存在
- faceid ✓ 存在
- exclamationmark.triangle ✓ 存在
- checkmark.circle ✓ 存在
- lock.shield.fill ✓ 存在
- exclamationmark.triangle.fill ✓ 存在
- checkmark.circle.fill ✓ 存在
- xmark.circle.fill ✓ 存在
- clock.fill ✓ 存在
- bell ✓ 存在
- plus ✓ 存在
- lock.shield ✓ 存在
- checkmark ✓ 存在
- square.and.arrow.up ✓ 存在
- arrow.clockwise ✓ 存在
- trash ✓ 存在
- lock.fill ✓ 存在
- arrow.up.right ✓ 存在
- photo ✓ 存在
- play.fill ✓ 存在
- brain ✓ 存在
- hand.tap ✓ 存在
- moon.zzz ✓ 存在
- xmark ✓ 存在
- magnifyingglass ✓ 存在
- list.clipboard ✓ 存在
- ellipsis ✓ 存在
- text.bubble ✓ 存在
- arrow.up.forward ✓ 存在

### Mac 端符号（Sources/OneDayMac/）
- sparkles ✓ 存在
- bubble.left.and.bubble.right.fill ✓ 存在
- arrow.clockwise ✓ 存在
- lock.fill ✓ 存在
- checkmark.circle.fill ✓ 存在
- key.fill ✓ 存在
- minus.circle ✓ 存在
- checklist ✓ 存在
- arrow.turn.down.right ✓ 存在
- magnifyingglass ✓ 存在
- xmark.circle.fill ✓ 存在
- square.and.pencil ✓ 存在
- pin.fill ✓ 存在
- ellipsis.circle ✓ 存在
- checkmark ✓ 存在
- chevron.up ✓ 存在
- chevron.down ✓ 存在
- xmark ✓ 存在
- exclamationmark.circle.fill ✓ 存在
- quote.bubble ✓ 存在
- paperclip ✓ 存在
- stop.circle.fill ✓ 存在
- arrow.up.circle.fill ✓ 存在
- terminal ✓ 存在
- heart.fill ✓ 存在
- checkmark.shield ✓ 存在
- link ✓ 存在
- person.fill ✓ 存在
- envelope.open ✓ 存在（已修正）

### 组件库符号（Sources/OneDayDesign/）
- exclamationmark.circle ✓ 存在
- sparkles ✓ 存在
- chevron.down ✓ 存在

### 测试符号（Tests/）
- pawprint.fill ✓ 存在
- line.3.horizontal ✓ 存在
- bell ✓ 存在
- chevron.down.circle.fill ✓ 存在
- cube.fill ✓ 存在

### Widget 符号（Sources/OneDayWidgets/）
- sparkles ✓ 存在

## 验证结果
- 总计扫描：140+ 处 `Image(systemName:)` 调用
- 发现问题：2 处
  - 孤括号语法错（HubIdentityCapsule.swift:83）✓ 已修复
  - 不存在符号（MacHubMailView.swift:15 `envelope.badge.slash`）✓ 已改为 `envelope.open`
- 其余符号均为 SF Symbols 标准符号，存在且可用

## 修复措施
1. 删除 HubIdentityCapsule.swift:83 孤立的 `)` 括号
2. 将 MacHubMailView.swift:15 的 `envelope.badge.slash` 改为 `envelope.open`（邮件空态语义相符且存在的符号）

## 括号平衡验证
- HubIdentityCapsule.swift: `(` = 64, `)` = 64 ✓ 平衡
