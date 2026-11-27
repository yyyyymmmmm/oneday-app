# SF Symbols 横扫清单

## 扫描方法
```bash
# 三路并查：Image(systemName:) + systemImage: + icon: 参数

# 路径1: Image(systemName:) 调用
grep -rh 'Image(systemName:' --include="*.swift" . | \
  grep -o 'systemName: "[^"]*"' | \
  sed 's/systemName: "\(.*\)"/\1/' | \
  sort -u

# 路径2: systemImage: 参数（Label、ContentUnavailableView 等）
grep -rh 'systemImage:' --include="*.swift" . | \
  grep -o 'systemImage: "[^"]*"' | \
  sed 's/systemImage: "\(.*\)"/\1/' | \
  sort -u

# 路径3: icon: 参数（navRow 等）
grep -rh 'icon:' --include="*.swift" . | \
  grep -o 'icon: "[^"]*"' | \
  sed 's/icon: "\(.*\)"/\1/' | \
  sort -u

# 三路合并去重
cat route1.txt route2.txt route3.txt | sort -u
```

## 统计数据
- **调用总数**：582 处（Image(systemName:) 284 + systemImage: 218 + icon: 80）
- **去重符号数**：186 个不同的符号名
- **缺失符号**：2 个（已修复）

## 修复记录
1. **HubIdentityCapsule.swift:83** - 孤括号语法错（已修复）
2. **MacHubMailView.swift:15** - `envelope.badge.slash` 不存在（已改为 `envelope.open`）

## 全仓符号清单（186 个）

1. alarm ✓ 存在
2. antenna.radiowaves.left.and.right ✓ 存在
3. archivebox ✓ 存在
4. arrow.clockwise ✓ 存在
5. arrow.clockwise.circle ✓ 存在
6. arrow.down.right.and.arrow.up.left ✓ 存在
7. arrow.down.to.line ✓ 存在
8. arrow.right.to.line ✓ 存在
9. arrow.triangle.2.circlepath ✓ 存在
10. arrow.triangle.branch ✓ 存在
11. arrow.turn.down.right ✓ 存在
12. arrow.turn.up.left ✓ 存在
13. arrow.up ✓ 存在
14. arrow.up.circle.fill ✓ 存在
15. arrow.up.doc ✓ 存在
16. arrow.up.forward ✓ 存在
17. arrow.up.forward.app ✓ 存在
18. arrow.up.forward.app.fill ✓ 存在
19. arrow.up.forward.square ✓ 存在
20. arrow.up.left.and.arrow.down.right ✓ 存在
21. arrow.up.right ✓ 存在
22. arrowshape.turn.up.left ✓ 存在
23. arrowshape.turn.up.right ✓ 存在
24. bag ✓ 存在
25. bell ✓ 存在
26. bell.badge ✓ 存在
27. bell.fill ✓ 存在
28. bell.slash ✓ 存在
29. brain ✓ 存在
30. bubble.left ✓ 存在
31. bubble.left.and.bubble.right ✓ 存在
32. bubble.left.and.bubble.right.fill ✓ 存在
33. bubble.left.and.text.bubble.right ✓ 存在
34. bubble.left.and.text.bubble.right.fill ✓ 存在
35. cable.connector ✓ 存在
36. calendar ✓ 存在
37. camera ✓ 存在
38. camera.fill ✓ 存在
39. chart.bar ✓ 存在
40. checklist ✓ 存在
41. checkmark ✓ 存在
42. checkmark.circle ✓ 存在
43. checkmark.circle.fill ✓ 存在
44. checkmark.seal ✓ 存在
45. checkmark.shield ✓ 存在
46. checkmark.shield.fill ✓ 存在
47. chevron.down ✓ 存在
48. chevron.down.circle.fill ✓ 存在
49. chevron.left ✓ 存在
50. chevron.right ✓ 存在
51. chevron.up ✓ 存在
52. chevron.up.chevron.down ✓ 存在
53. circle ✓ 存在
54. clock ✓ 存在
55. clock.arrow.2.circlepath ✓ 存在
56. clock.arrow.circlepath ✓ 存在
57. clock.arrow.trianglehead.counterclockwise.rotate.90 ✓ 存在
58. clock.fill ✓ 存在
59. cpu ✓ 存在
60. cube.fill ✓ 存在
61. delete.left ✓ 存在
62. desktopcomputer ✓ 存在
63. doc ✓ 存在
64. doc.badge.gearshape ✓ 存在
65. doc.on.doc ✓ 存在
66. doc.questionmark ✓ 存在
67. doc.text ✓ 存在
68. doc.text.magnifyingglass ✓ 存在
69. ellipsis ✓ 存在
70. ellipsis.circle ✓ 存在
71. envelope.badge ✓ 存在
72. envelope.fill ✓ 存在
73. envelope.open ✓ 存在
74. escape ✓ 存在
75. exclamationmark ✓ 存在
76. exclamationmark.circle ✓ 存在
77. exclamationmark.circle.fill ✓ 存在
78. exclamationmark.triangle ✓ 存在
79. exclamationmark.triangle.fill ✓ 存在
80. eye ✓ 存在
81. eye.circle ✓ 存在
82. eye.slash ✓ 存在
83. face.smiling ✓ 存在
84. faceid ✓ 存在
85. flag.checkered ✓ 存在
86. folder ✓ 存在
87. folder.badge.plus ✓ 存在
88. folder.fill ✓ 存在
89. gearshape ✓ 存在
90. globe ✓ 存在
91. hammer ✓ 存在
92. hand.tap ✓ 存在
93. hand.tap.fill ✓ 存在
94. hand.thumbsdown ✓ 存在
95. hand.thumbsup ✓ 存在
96. heart.fill ✓ 存在
97. icloud.and.arrow.up ✓ 存在
98. info.circle ✓ 存在
99. iphone ✓ 存在
100. iphone.gen3 ✓ 存在
101. key ✓ 存在
102. key.fill ✓ 存在
103. key.slash ✓ 存在
104. keyboard ✓ 存在
105. lightbulb ✓ 存在
106. lightbulb.fill ✓ 存在
107. lightbulb.slash ✓ 存在
108. line.3.horizontal ✓ 存在
109. link ✓ 存在
110. link.badge.plus ✓ 存在
111. list.bullet ✓ 存在
112. list.clipboard ✓ 存在
113. lock.fill ✓ 存在
114. lock.shield ✓ 存在
115. lock.shield.fill ✓ 存在
116. magnifyingglass ✓ 存在
117. message ✓ 存在
118. message.fill ✓ 存在
119. mic ✓ 存在
120. mic.fill ✓ 存在
121. minus.circle ✓ 存在
122. moon.zzz ✓ 存在
123. music.note ✓ 存在
124. network ✓ 存在
125. newspaper ✓ 存在
126. paperclip ✓ 存在
127. paperplane ✓ 存在
128. pause.circle ✓ 存在
129. pawprint.fill ✓ 存在
130. pencil ✓ 存在
131. pencil.circle ✓ 存在
132. person.badge.key ✓ 存在
133. person.crop.circle ✓ 存在
134. person.fill ✓ 存在
135. photo ✓ 存在
136. photo.on.rectangle.angled ✓ 存在
137. pin.fill ✓ 存在
138. play.circle ✓ 存在
139. play.circle.fill ✓ 存在
140. play.fill ✓ 存在
141. play.rectangle.fill ✓ 存在
142. plus ✓ 存在
143. plus.circle ✓ 存在
144. plus.circle.fill ✓ 存在
145. point.3.connected.trianglepath.dotted ✓ 存在
146. puzzlepiece.extension ✓ 存在
147. qrcode ✓ 存在
148. qrcode.viewfinder ✓ 存在
149. questionmark.bubble.fill ✓ 存在
150. questionmark.circle ✓ 存在
151. questionmark.folder ✓ 存在
152. quote.bubble ✓ 存在
153. rectangle.stack ✓ 存在
154. repeat ✓ 存在
155. return ✓ 存在
156. server.rack ✓ 存在
157. shield ✓ 存在
158. shippingbox ✓ 存在
159. shuffle ✓ 存在
160. sparkle ✓ 存在
161. sparkles ✓ 存在
162. speaker.wave.2 ✓ 存在
163. square.and.arrow.down ✓ 存在
164. square.and.arrow.up ✓ 存在
165. square.and.pencil ✓ 存在
166. square.grid.3x3.fill ✓ 存在
167. square.stack.3d.up.fill ✓ 存在
168. square.stack.3d.up.slash ✓ 存在
169. stethoscope ✓ 存在
170. stop.circle.fill ✓ 存在
171. stop.fill ✓ 存在
172. sun.max ✓ 存在
173. target ✓ 存在
174. terminal ✓ 存在
175. text.bubble ✓ 存在
176. text.viewfinder ✓ 存在
177. trash ✓ 存在
178. trash.circle ✓ 存在
179. tray ✓ 存在
180. tray.and.arrow.down ✓ 存在
181. wand.and.stars ✓ 存在
182. wifi.slash ✓ 存在
183. wrench.and.screwdriver ✓ 存在
184. xmark ✓ 存在
185. xmark.circle ✓ 存在
186. xmark.circle.fill ✓ 存在

## 验证结果
- 全仓 582 处调用（Image(systemName:) 284 + systemImage: 218 + icon: 80），186 个不同符号名
- 发现问题：2 处（已全部修复）
  - 孤括号语法错（HubIdentityCapsule.swift:83）✓ 已修复
  - 不存在符号（MacHubMailView.swift:15 `envelope.badge.slash`）✓ 已改为 `envelope.open`
- 其余 186 个符号均为 SF Symbols 标准符号，全部存在且可用

## 修复措施
1. 删除 HubIdentityCapsule.swift:83 孤立的 `)` 括号
2. 将 MacHubMailView.swift:15 的 `envelope.badge.slash` 改为 `envelope.open`（邮件空态语义相符且存在的符号）

## 括号平衡验证
- HubIdentityCapsule.swift: `(` = 64, `)` = 64 ✓ 平衡
