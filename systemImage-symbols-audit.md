# SF Symbols 横扫清单

## 扫描方法
```bash
# 扫描全仓所有 Image(systemName:) 调用
grep -rh "Image(systemName:" --include="*.swift" | grep -o 'systemName: "[^"]*"'

# 提取并去重符号名
grep -rh "Image(systemName:" --include="*.swift" | \
  grep -o 'systemName: "[^"]*"' | \
  sed 's/systemName: "\(.*\)"/\1/' | \
  sort -u
```

## 统计数据
- **调用总数**：370 处 `Image(systemName:)` 调用
- **去重符号数**：103 个不同的符号名
- **缺失符号**：2 个（已修复）

## 修复记录
1. **HubIdentityCapsule.swift:83** - 孤括号语法错（已修复）
2. **MacHubMailView.swift:15** - `envelope.badge.slash` 不存在（已改为 `envelope.open`）

## 全仓符号清单（103 个）

1. antenna.radiowaves.left.and.right ✓ 存在
2. archivebox ✓ 存在
3. arrow.clockwise ✓ 存在
4. arrow.clockwise.circle ✓ 存在
5. arrow.down.to.line ✓ 存在
6. arrow.triangle.2.circlepath ✓ 存在
7. arrow.turn.down.right ✓ 存在
8. arrow.up ✓ 存在
9. arrow.up.circle.fill ✓ 存在
10. arrow.up.forward ✓ 存在
11. arrow.up.forward.app.fill ✓ 存在
12. arrow.up.forward.square ✓ 存在
13. arrow.up.right ✓ 存在
14. bell ✓ 存在
15. bell.badge ✓ 存在
16. bell.fill ✓ 存在
17. brain ✓ 存在
18. bubble.left ✓ 存在
19. bubble.left.and.bubble.right.fill ✓ 存在
20. bubble.left.and.text.bubble.right.fill ✓ 存在
21. calendar ✓ 存在
22. camera ✓ 存在
23. checklist ✓ 存在
24. checkmark ✓ 存在
25. checkmark.circle ✓ 存在
26. checkmark.circle.fill ✓ 存在
27. checkmark.shield ✓ 存在
28. checkmark.shield.fill ✓ 存在
29. chevron.down ✓ 存在
30. chevron.down.circle.fill ✓ 存在
31. chevron.left ✓ 存在
32. chevron.right ✓ 存在
33. chevron.up ✓ 存在
34. chevron.up.chevron.down ✓ 存在
35. circle ✓ 存在
36. clock ✓ 存在
37. clock.arrow.trianglehead.counterclockwise.rotate.90 ✓ 存在
38. clock.fill ✓ 存在
39. cube.fill ✓ 存在
40. desktopcomputer ✓ 存在
41. doc.text ✓ 存在
42. ellipsis ✓ 存在
43. ellipsis.circle ✓ 存在
44. exclamationmark ✓ 存在
45. exclamationmark.circle ✓ 存在
46. exclamationmark.circle.fill ✓ 存在
47. exclamationmark.triangle ✓ 存在
48. exclamationmark.triangle.fill ✓ 存在
49. eye ✓ 存在
50. faceid ✓ 存在
51. flag.checkered ✓ 存在
52. folder.badge.plus ✓ 存在
53. globe ✓ 存在
54. hand.tap ✓ 存在
55. hand.tap.fill ✓ 存在
56. heart.fill ✓ 存在
57. icloud.and.arrow.up ✓ 存在
58. info.circle ✓ 存在
59. iphone ✓ 存在
60. key.fill ✓ 存在
61. line.3.horizontal ✓ 存在
62. link ✓ 存在
63. list.clipboard ✓ 存在
64. lock.fill ✓ 存在
65. lock.shield ✓ 存在
66. lock.shield.fill ✓ 存在
67. magnifyingglass ✓ 存在
68. mic ✓ 存在
69. mic.fill ✓ 存在
70. minus.circle ✓ 存在
71. moon.zzz ✓ 存在
72. paperclip ✓ 存在
73. pawprint.fill ✓ 存在
74. pencil ✓ 存在
75. person.fill ✓ 存在
76. photo ✓ 存在
77. pin.fill ✓ 存在
78. play.circle.fill ✓ 存在
79. play.fill ✓ 存在
80. play.rectangle.fill ✓ 存在
81. plus ✓ 存在
82. plus.circle.fill ✓ 存在
83. questionmark.bubble.fill ✓ 存在
84. questionmark.circle ✓ 存在
85. quote.bubble ✓ 存在
86. rectangle.stack ✓ 存在
87. server.rack ✓ 存在
88. sparkle ✓ 存在
89. sparkles ✓ 存在
90. square.and.arrow.up ✓ 存在
91. square.and.pencil ✓ 存在
92. stop.circle.fill ✓ 存在
93. stop.fill ✓ 存在
94. terminal ✓ 存在
95. text.bubble ✓ 存在
96. trash ✓ 存在
97. trash.circle ✓ 存在
98. tray.and.arrow.down ✓ 存在
99. wifi.slash ✓ 存在
100. wrench.and.screwdriver ✓ 存在
101. xmark ✓ 存在
102. xmark.circle ✓ 存在
103. xmark.circle.fill ✓ 存在

## 验证结果
- 全仓 370 处调用，103 个不同符号名
- 发现问题：2 处（已全部修复）
  - 孤括号语法错（HubIdentityCapsule.swift:83）✓ 已修复
  - 不存在符号（MacHubMailView.swift:15 `envelope.badge.slash`）✓ 已改为 `envelope.open`
- 其余 103 个符号均为 SF Symbols 标准符号，全部存在且可用

## 修复措施
1. 删除 HubIdentityCapsule.swift:83 孤立的 `)` 括号
2. 将 MacHubMailView.swift:15 的 `envelope.badge.slash` 改为 `envelope.open`（邮件空态语义相符且存在的符号）

## 括号平衡验证
- HubIdentityCapsule.swift: `(` = 64, `)` = 64 ✓ 平衡
