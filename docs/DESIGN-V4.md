# DESIGN-V4 —— iOS 26 Liquid Glass 设计定版（0.2.3）

> 0.2.3 前置产出：先读 skill、出定版、再写码。依据的 skill：
> `local-swiftui-liquid-glass`（下称 LG）、`local-swiftui-design`（SD）、
> `local-impeccable`（IM）、`local-hallmark`（HA）。每条决定标注出处；
> 与方向冲突时以 skill 为准（简报口径与 skill 一致，无冲突项）。
> 本版只换设计语言，功能与 IA 一律不动（0.2.2 功能面原样）。

## 0. 总纲

- 本 App 是 **Operate 模式**界面（IM「Modes」：任务型界面里可扫描性、
  一致性与原生预期高于表达欲，野心体现在精度与克制）——Liquid Glass
  只做原生语言的精确落地，不做风格炫技。
- 玻璃只用于 **chrome 层**（LG「Workflow/Implement」：custom glass
  留给 functional controls 与 navigation surfaces，「not general
  content backgrounds」；「Common Mistakes」首条：Glass decorates
  static content → Keep it in the controls/navigation layer）。
- 每个元素要挣得自己的位置（SD Principle 5「System First, Don't
  Fill」）；单一强调色落在中性底上（SD Principle 6 anti-slop：
  Single warm accent color on neutral background——本 App 的强调色
  即已查证的腾讯蓝 #0052D9，只做微点与关键态，纪律不变）。

## 1. 底色去染色（内容层）

- pageBG 浅色由 #F7F8FA（蓝灰）改 **#FFFFFF 纯白**；fieldFill 由
  #F1F3F6 改 **#F2F2F2 中性灰**；深色 pageBG/surface/fieldFill 同步
  去蓝（#0B0B0D / #17181C / #232428）。
- 分组容器（odGroup）在纯白底上改靠 **0.5pt 发丝线描边**成面，
  不再靠底色对比（HA Floor 11「no card inside a card」的反面纪律：
  容器轻、边界细）。
- 抽屉保持实色 surface（LG：玻璃不做内容背景；抽屉是内容面）。
- 颜色只经令牌（HA Floor 1：every colour goes through a token）。

## 2. 底栏（玻璃悬浮、仅图标）

- 形态：**GlassEffect 悬浮胶囊**——单个 `.glassEffect(.regular,
  in: Capsule())` 作用于整条栏（LG：glassEffect 在布局修饰之后；
  单一形状不需要 GlassEffectContainer 拼多形，容器留给多玻璃形
  临近混合场景）。
- **只要图标、不要文字**：四格仅线条图标（SD P5：元素挣位置——
  图标＋VoiceOver 标签已足，视觉文字是赘余）；无障碍标签保留。
- 选中态：图标下/后的 **浅灰高亮胶囊（fieldFill）＋墨色图标＋
  4pt 主题色微点**（0.2.2 已定微点口径，承 §6 近单色纪律）；
  未选中：中灰线条。
- 层级与避让：栏以 overlay 悬浮于内容之上（玻璃的半透明才有
  意义）；**抽屉打开时隐藏**（沿 0.2.2 口径）；**键盘弹起时隐藏**
  （二选一取「隐藏」：输入舱自带完整操作面，栏隐藏避免与键盘
  争夺底沿——ContentView 监听键盘通知实现）。页面内容以
  safeAreaInset 预留下沿空间，不被栏遮挡。

## 3. 顶栏角钮（玻璃圆钮）

- 聊天页左右角钮改 `.buttonStyle(.glass)` 玻璃圆钮（LG「Improve」
  路径：Replace custom glass-like buttons with .buttonStyle(.glass)；
  本 App 下限即 iOS 26，无需 #available 回退——LG 审查清单的
  Availability 条款针对需兼容旧系统者，本 App 不适用，文档在此
  注明）。图标墨色线条（新建钮此前吃环境 tint 呈蓝色，本轮改墨）。
- 中间标题＋模型行是**内容性标题**，不做玻璃控件（LG「Status vs
  action」：只读状态不冒充控件）；模型行本身是真按钮（点开选择
  器），保持文字形态、墨/灰字阶，字阶按 §5 微调。

## 4. 发送舱（玻璃胶囊）

- 输入区整体改 **玻璃胶囊**：`.glassEffect(.regular, in:
  RoundedRectangle(cornerRadius: 28))` 包裹 ＋键/输入框/发送键
  一行；输入框自身底色与阴影撤掉（玻璃即容器）。
- ＋键：36pt 圆、墨色线条图标（透明底，融于玻璃）。
- 发送键：36pt 同径；可用态＝**primaryFill 实色＋白箭头**
  （关键动作的强调色落点）。不用玻璃染色：LG「Clear glass
  contrast」条款要求亮底上的玻璃控件保证可读——白底上 tint
  玻璃对比不足，实色填充即本 App 的对比处理，语义等同
  .glassProminent 的高强调定位（LG Button Styles）。
- 流式停止键同尺寸同位；待发附件条在胶囊上方、实色小件，不入玻璃。

## 5. 字阶与空状态

- 顶栏标题 16pt semibold 不变；模型行 caption 不变（已合 SD 的
  系统字体＋好间距原则，不引入自定义字体）。
- 聊天空状态收敛：图标 26pt light 字重、三级灰；标题 callout
  semibold；说明 caption 次灰；顶部留白减半——空状态是内容，
  不做大块视觉锚点（SD P5；IM Operate 克制）。

## 6. 动效与无障碍

- 既有动效（0.2.2 §7 登记）全保留；玻璃栏的显隐沿用同一
  easeInOut 0.18 过渡。每个动效有 Reduce Motion 降级（HA
  Floor 7；LG 审查清单 Accessibility 条）。
- 玻璃在 Reduce Transparency 下由系统自动回退实色（系统行为，
  不另写代码；真机终审时用户可验）。

## 7. 验收清单（截图逐项对照）

1. 玻璃只出现在：底栏、顶栏角钮、发送舱——内容层无玻璃。
2. 底栏无文字、图标线条统一、选中浅灰胶囊＋微点。
3. 全页底色纯白系，无可感蓝灰（逐页看：聊天/总览/文件/设置/抽屉）。
4. 顶栏角钮玻璃圆钮＋墨色线条图标，无蓝色大图标。
5. 发送舱玻璃胶囊成形、两键 36pt 同径。
6. 聊天空状态轻量（本轮截图环仍是种子对话，空状态由代码审查
   与真机终审覆盖——如实登记）。

## 8. 0.2.4 修订：原生组件回归＋重叠架构（用户真机对照 Muse 定版）

0.2.3 的教训：自绘 glassEffect 胶囊「静态像、动态假」——没有
系统玻璃的折光、滚动穿透、键盘联动与系统弹簧，真机一眼假。
本版原则：**chrome 一律系统亲生组件，仿制代码删除，不在自
绘件上打补丁**；且布局改**重叠架构**——内容全幅铺满，玻璃
悬浮覆盖其上，内容从玻璃背后流过（对照 Muse 主页面）。

### 8.1 底栏＝原生 TabView

- SwiftUI 原生 `TabView(selection:)`，iOS 26 系统渲染
  Liquid Glass 底栏（材质、边缘高光、滚动/键盘行为全系统）。
- 无文字实现路径：tabItem 只放线条 SF 图标（系统 image-only
  条目形态），名称只进无障碍标签（accessibilityLabel）＋
  无障碍标识（tab.chat 等，供截图环定位）。
- 选中着色走系统通道：`.tint(Palette.primary)`——主题色从
  系统允许的入口进入。**取舍**：§2 的自绘「浅灰胶囊＋4pt
  微点」无系统挂钩，撤销；系统选中胶囊＋tint 图标替代之，
  冲突时系统优先。
- 层级/避让全服从系统默认：抽屉打开时底栏浮于其上（页内
  覆盖层管不到系统 chrome）、键盘弹起由系统处理。删除：
  自绘玻璃栏、键盘通知监听、frame 级 padding 预留、
  opacity 页切换与 odTabPage（含 0.2.2 登记的页签交叉淡化，
  由系统页签行为替代，登记口径在此更新）。

### 8.2 聊天页覆盖式布局

- 消息 ScrollView 全幅（顶到底），两组悬浮覆盖层：
  - 顶栏：左右系统玻璃角钮（`.buttonStyle(.glass)`＋
    `.buttonBorderShape(.circle)`，36pt 量级、墨色线条）
    ＋居中标题/模型行，浮在内容上，**无底色、无分界线**
    （撤 NavigationStack＋toolbar——栈内无 push 依赖，
    全仓核查在案）；内容可滚到角钮背后。
  - 底部悬浮层：回到底部钮＋错误/提示条＋发送舱，抬升到
    底栏上方（tabBarZone＝76）；其实测高度
    （onGeometryChange）驱动列表 contentMargins：顶 56、
    底＝悬浮层高＋间距——首尾消息能滚到玻璃上方不被永久
    遮挡。**不用 safeAreaInset 给发送舱留位**。
- 回到底部钮改系统 .glass 圆钮（撤实色底＋自绘阴影）。

### 8.3 发送舱＝单颗系统玻璃胶囊

- `GlassEffectContainer` 内一颗 Capsule 玻璃：胶囊本体与
  ＋键（glassEffect 圆、interactive）以同一
  `glassEffectUnion(id: "composer")` 融合——＋在胶囊内左、
  输入居中、发送在胶囊内右（对照 Muse 输入区形态）。
- 发送/停止键保持实色小圆（36pt，primaryFill＋白箭头）：
  系统玻璃语境内的对比通行做法，承 §4 的 LG 对比条款。

### 8.4 各页与抽屉

- 总览/文件/设置/状态页本就各自 NavigationStack＋系统
  列表：原生 TabView 下列表经系统安全区延伸到屏幕底、
  从底栏背后流过，无 App 侧截断（逐页核查：页内只有
  内容级 padding，无底栏预留件）。
- 抽屉：scrim 与面板仍为聊天页内覆盖层；底栏按系统层级
  浮于其上，面板底部留 tabBarZone 空位，服务器行不被
  玻璃栏遮挡（与 0.2.2「scrim 全覆盖」的差异是刻意的
  系统优先取舍）。

### 8.5 验收加项（硬指标）

- 02-chat 截图必须看见消息文字在发送舱与底栏背后透出的
  模糊影：演示种子加长一轮问答保可滚长度，截图环在截
  02 前主动上滑一截制造滚动中段（静止底位时边距把末条
  顶到玻璃上方、天然无重叠）。

## 9. 0.2.5 追记：真机对照 Muse 的四处定点修正

0.2.4 交付后，用户拿真机逐项对照 Muse 点名四处。本版
只做视觉/布局定点改动，功能与 IA 不动。验收口径亦更新：
**截图环停用**（用户新规矩：他发的真机截图即验收材料，
我方不再主动截图），交付标准＝主构建 CI 绿＋单测全过，
观感由用户真机终审；§7/§8.5 的截图清单自此留档不用。

### 9.1 顶栏中心防撞（部分推翻 §3）

- 缺陷：§3 定「标题是内容性文字、不做玻璃控件」，0.2.4
  落地为裸文字悬浮——正文上滚直接从标题文字里穿过，字
  撞字（用户截图里错误消息的 request_id 糊在标题上）。
- 改法：标题＋模型行收进一颗紧凑玻璃胶囊
  （glassEffect .regular.interactive + Capsule，两行紧凑
  排：标题 16 semibold／模型 caption＋⌄），整颗可点开
  模型选择器。§3 的前提自此修正：该中心簇本就是控件
  （点开选择器），做玻璃控件不违 LG「Status vs action」
  ——纯状态不上玻璃，是控件的必须上。消息区另加系统
  scroll-edge 柔和渐隐（.scrollEdgeEffectStyle(.soft,
  for: .top)），内容滚向顶栏先淡出、不硬撞；顶部滚动
  边距随胶囊高度 56→64。左右角钮不动。

### 9.2 发送舱去嵌套＋右端状态机

- 缺陷：＋键自带 glassEffect 圆＋union 融合，成「胶囊里
  套圆圈」的嵌套；右端是不分状态常驻的灰实心圆盘。
- 改法（对照 Muse：胶囊内皆裸符号）：＋撤外圈改裸符号
  坐在胶囊玻璃里；右端改三态状态机——流式中＝停止键
  （36pt 主题填充盘、无描边，逻辑不变）、有内容＝发送
  箭头（36pt 小圆盘保留实色保对比，填充取主题档
  primaryFill：按 §9.4 口径腾讯蓝只留在内容强调位，本
  键即其一，故不取墨色盘，特此注明取舍）、空输入＝裸
  麦克风符号占位（无盘无边；语音未接，点按无动作，
  无障碍标签明示「尚未开放」）。

### 9.3 助手消息改浅灰泡（**推翻 DESIGN-V2 裸排决定**）

- 记录在案：DESIGN-V2 §3.5 曾定「助手回答裸排在底色
  上（学 ChatGPT/Claude 共识）」，0.2.5 经用户真机对
  照 Muse 后**正式推翻**——现行 Muse 的助手消息坐在
  浅灰圆角泡里，裸排在纯白底上无界、读感散（用户原问：
  「为什么 AI 发的是纯白的」）。V2 的该条决定作废，后
  续版本不得再以「裸排是共识」回滚本形态。
- 规格：新令牌 Palette.bubbleFill（浅 #F4F4F5／深
  #1E1F24）软填充、圆角 18（令牌 assistantBubble
  Corner）、内边距 14×10、左对齐，右侧 44pt 让位与用户
  泡同逻辑（宽度上限对齐）。泡内代码块用 fieldFill 再
  深一阶；流式半截、流式光标、等待三点一并入泡。用户
  泡保持现行主题浅染不变。

### 9.4 底栏图标瘦身＋tint 改墨（改 §8.1 的 tint 取舍）

- 缺陷：原生 TabView 的图标在真机上呈实心粗 glyph、选
  中染腾讯蓝。根因：SF Symbols 带 fill 变体的符号在
  选中态会被系统自动切换为 .fill 变体（双气泡、folder
  皆然），并非图标选错名；gearshape、表盘字形本身即
  实心剪影。
- 改法：四枚逐个定线条版并 .symbolVariant(.none) 锁死
  基础变体（.fill 全面禁用）——聊天 bubble.left.and.
  bubble.right（线条双泡）、总览 chart.line.uptrend.
  xyaxis（原 gauge.with.dots.needle.33percent 太粗，
  换细线条趋势图）、文件 folder（线条版）、设置
  slider.horizontal.3（gearshape 无更细同义符号，换
  偏好设置的标准线条字形）。底栏 .tint 由 Palette.
  primary 改 Palette.ink：选中呈「墨色线条图标＋系统
  浅灰选择胶囊」，与 Muse 一致。§8.1「选中着色走主
  题 primary」的取舍自此改墨；腾讯蓝只保留在发送键
  （§9.2）、链接等内容强调位，不再染底栏。各页强调色
  全部显式走 Palette 令牌（.tint 全仓仅此一处），改
  tint 无连带影响，已核查在案。
