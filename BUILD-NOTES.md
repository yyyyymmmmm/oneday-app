# 构建说明

## 改动完成

分支：`fix/search-flow-20261127`  
提交：`c28e4804` feat(search): 查找命中两档强调——对齐 iOS Messages 标准

### 改动文件
- `Sources/OneDayDesign/Palette.swift` (+15 行)：新增 findMatchCurrent/findMatchOther 两档颜色
- `Sources/OneDayApp/SelectableTextView.swift` (+11 行)：SelectableInlineText 增加 searchIsCurrentMatch 参数与两档逻辑
- `Sources/OneDayApp/MarkdownText.swift` (+12 行)：MarkdownText 增加 searchIsCurrentMatch 参数并传递给内部组件
- `Sources/OneDayApp/ChatView.swift` (+5 行)：调用 MarkdownText 时传入当前命中判断
- `DELIVERY-SEARCH.md` (新增)：交卷文档

### 修复内容
1. **新增两档颜色**：
   - 当前命中强背景：`Palette.findMatchCurrent` (#F9D84A / α0.55)
   - 其他命中弱背景：`Palette.findMatchOther` (#FBE38A / α0.20)

2. **打通参数链路**：
   - ChatView → MarkdownText → SelectableInlineText
   - 判断条件：`entry.id == findController.session.currentMatchID`

3. **覆盖范围**：
   - 散文段落、引用块、任务列表、代码块高亮

## 构建命令

SSH 连接不稳定，建议主线在 Mac 端直接构建：

```bash
cd ~/workspace/wt-search
export PATH=/opt/homebrew/bin:/opt/homebrew/sbin:$PATH
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
tuist install && tuist generate
xcodebuild build -scheme OneDayApp -configuration Release \
  -derivedDataPath ~/build/search-derived \
  CODE_SIGNING_ALLOWED=NO 2>&1 | tee build.log
```

## 验证清单

1. 点顶栏搜索钮，搜索栏滑入
2. 输入搜索词，计数显示（如 `3/12`）
3. **点上一个/下一个**：
   - 当前命中**强黄色**（饱和黄）
   - 其他命中**弱黄色**（淡黄）
   - 两档清晰可辨，不整行染色
4. 退出搜索，高亮清除

## 推送状态

- ✅ 已推送至 `origin/fix/search-flow-20261127`
- ⏳ 构建待 Mac 端执行（SSH 连接不稳定）
