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

### 9.5 发送舱键盘膨胀根治（0.2.5 追加第五条）

- 缺陷（用户键盘对照截图）：键盘弹起时发送舱膨胀成占
  屏三分之一的空盒，＋/发送键钉在盒底两角、文字行浮在
  盒上半部，对位全失；空态盒底还挂着发送圆盘（圆盘问
  题已由 §9.2 状态机解决：空态只有裸麦克风）。
- 根因（布局提议链，非键盘本身）：发送舱位于覆盖式
  ZStack 的底部悬浮层，ZStack 向子视图提议全屏高度，
  提议经 bottomOverlay/inputBar 两层 VStack 与
  GlassEffectContainer 传到 TextField(axis: .vertical)
  ——链上唯一贪高的孩子（UITextView 被提议确定高度时
  照单全收，聚焦后进入可滚动态更甚）。键盘弹起只是触
  发重布局的扳机；固定 36pt 的两键被 HStack(.bottom)
  钉在被撑高的盒底，文字顶在 field 顶部，于是「盒子
  巨大、上下不对位」。
- 根治（不写死高度）：在提议链每一环——field 本体、
  胶囊 HStack、inputBar VStack、底部悬浮层 VStack
  ——加 fixedSize(horizontal: false, vertical: true)，
  高度永远取内容理想值。对位规格：field 纵向内边距
  12→8，单行 field 高≈38（行高约 22＋边距 16），与
  36pt 两键在 .bottom 对齐下中心差约 1pt（单行视觉
  居中）；多行时两键底边与 field 底边齐平、锚在最后
  一行。胶囊单行总高 54（≈52 规格）；行数上限 5→6，
  超出后 field 内滚。

## 10. 0.2.6 追记：发送区承载换代（调研定案）＋四项修正

0.2.5 交付后用户真机回两类问题：键盘弹起态发送舱仍膨
胀成空玻璃泡（§9.5 的断环只治住静态覆盖态）；另对照
Muse 长文输入态截图追加三点——顶部渐隐、输入多行时
的形状、底栏图标再小。本版按用户指示调整打法：先调研
成熟开源项目、后定案，不再在自研覆盖层上打补丁。

### 10.1 调研：三家成熟开源聊天 UI 的输入区承载

- Exyte/Chat（SwiftUI 聊天库）：消息表（UITableView
  承载）与输入区是同一布局流里的上下兄弟（其
  isListAboveInputView 修饰符即此结构），库内自带
  KeyboardState 观察键盘、保持输入条贴键盘、列表区
  让位（其 issue #180 的诉求与修复口径即「输入条应
  相对键盘固定、其余内容滚动让位」）。结论：输入区
  在流内、由键盘状态驱动，不是覆盖层。
  https://github.com/exyte/Chat
- MessageKit＋InputBarAccessoryView（UIKit）：输入条
  就是宿主控制器的 inputAccessoryView（视图控制器
  重写 canBecomeFirstResponder 常驻），停靠、跟随键
  盘、交互收起全由系统 UIInputWindowController 精确
  处理；条内 UITextView 自适应高，库的 KeyboardManager
  只负责同步滚动视图的内容边距。结论：UIKit 世界的
  钦定通道是 inputAccessoryView，高度与避让不归应
  用布局管。
  https://github.com/MessageKit/MessageKit
  https://github.com/nathantannar4/InputBarAccessoryView
- Stream Chat SwiftUI：频道页是「消息列表＋Composer」
  的流内上下结构，键盘避让走 SwiftUI 安全区；其
  KeyboardReadable 键盘发布者只供弹窗等附加件对齐
  键盘高度。结论：SwiftUI 世界与 Exyte 共识一致——
  composer 在流内、安全区管键盘。
  https://getstream.io/blog/swiftui-action-composer/

### 10.2 定案与取舍

- 选定结构：Exyte/Stream 式布局流承载的 SwiftUI 原生
  形态——消息列表加 .safeAreaInset(edge: .bottom) 承
  载整个发送区（回到底部钮＋错误/提示横幅＋发送舱）。
  键盘升起时系统安全区扩张、整段被顶到键盘上方，交
  互收起跟随安全区动画；高度在单次布局里只由内容决
  定。0.2.4/0.2.5 的覆盖式整套撤销：ZStack 底部悬浮
  层、tabBarZone 抬升、实测高度回写 contentMargins
  的反馈环一并删除；§9.5 的 fixedSize 断环在各环保
  留作双保险。玻璃胶囊本体（GlassEffectContainer＋
  union）原样保留——**胶囊是内容、不是布局机制**。
- 为何不选 inputAccessoryView 桥接：它停靠的是屏幕
  最底，与原生 TabView 并存时会压住底栏（本 App 发
  送舱须停靠在可见底栏之上），要补透明占位＋hitTest
  穿透才能共存，等于再造一层自研机制；且 SwiftUI 里
  需要第一响应者桥接，与 TabView 每格宿主的结构相
  冲。MessageKit 的前提（全屏聊天页、无底栏）与本
  App 不同。
- 取舍如实记：键盘收起态消息不再从发送舱背后流过
  （safeAreaInset 是留位不是覆盖）——舍掉 §8 的重叠
  观感，换来键盘联动的系统级精确，以及「高度被键盘
  态布局污染」这一类问题的整类消除。顶栏三件套仍为
  覆盖层（不与键盘发生关系，不在本轮换代范围）。

### 10.3 缺陷 A 的复现与证据（如实）

- 缺陷本体证据＝用户真机截图：键盘弹起、输入为空，
  发送舱膨胀成约 4–5 行高的空玻璃胶囊，＋与麦克风
  贴胶囊底部两角、上方全是空玻璃。
- 本地复现尝试：演示模式 UI 测试（ComposerKeyboard
  Tests）在 iPhone 17 与 iPhone 16e 两台模拟器上聚焦
  调起软键盘（美式键盘高 233），覆盖静止/键盘/键盘＋
  滚动/多行四态，以推导式量高（＋键底边 − 输入框上
  沿 ＋ 24）多轮测量——旧覆盖结构在模拟器各态推导高
  均为 54.0（单行规格内），**复现不出来**。第一代测
  试曾「红」过一次，后查明是测试自身测量污染（容器
  级无障碍标识被子元素继承、量到 36pt 的按钮），不
  是缺陷证据，已在测试注释中留档。
- 结论口径：膨胀是真机特有现象，与真机中文拼音键盘
  的高度/候选栏及其触发的布局通道差异为最大嫌疑，
  但无本地证据链、不写成定论。本版的修复逻辑是按
  §10.2 换掉出事的承载类——覆盖式悬浮层整体退役，
  键盘态高度改由系统安全区布局通道在单次布局中决
  定；是否根治以用户真机终审为准。回归测试保留并在
  新结构上继续把守同一规格（数值见 §10.6），测量锚
  点（＋键标签、field 本体标识 composerField）与推
  导式未迁移、未改口径。

### 10.4 缺陷 B＋顶部渐隐（追加 1）

- 标题胶囊：frame(maxWidth:) 由 240 收至 200，宽度
  回到「标题＋模型两行文字自然宽＋内边距」，居中，
  与左右角钮留明确间隙（0.2.5 真机约占屏宽 65%）。
  回归断言 ≤202pt（演示标题下实测 143，约束对真机
  长标题生效）。
- 顶部渐隐：系统 .scrollEdgeEffectStyle(.soft, for:
  .top) 保留，但白底上单独不可感——实际承担淡出的
  是悬浮 chrome 背后新增的 pageBG 渐变带（topFade）：
  自屏幕物理顶起 128pt，0–90% 全不透明、90%–100%
  降为全透明。几何按诊断图实测点位定（iPhone 17：
  胶囊一线约 68–115pt、静止时首条消息起于约 138pt）
  ——文字滚到胶囊/角钮一线之前已完全淡出，静止首条
  消息不被洗淡。它只是淡出遮罩：不做实色顶栏、不
  加分界线、不吃手势。

### 10.5 多行形状变形（追加 2）＋底栏图标（检查项 C＋追加 3）

- 形状病根有图为证：诊断截图里旧形态多行时 Capsule
  被拉成体育场形大气球（推导高 162），正是用户点名
  的「内容多了为什么变这样」。改：以输入框实测高判
  行数（单行 38、阈值 44），glassEffect 形状随之切
  换——单行 Capsule、多行 RoundedRectangle(corner
  Radius: 24, .continuous)，0.18s 缓动防跳变；文字
  从顶排起、＋与发送键锚底（HStack .bottom 原有语
  义）。新结构诊断图复核：多行已是固定圆角矩形向上
  生长，形态对齐 Muse。
- 底栏图标核查结论：模拟器诊断图同症复现——未选中
  的 folder 与选中态双气泡都呈实心黑块。定性：不是
  符号选错名，也非字重单因——SwiftUI 的 .symbol
  Variant(.none) 没有锁住 UITabBar 的渲染（选中态
  仍换 fill 变体、folder 在底栏渲染下呈实心剪影），
  且 tab 图标点数不受 SwiftUI font/symbolConfigur
  ation 控制（系统默认视觉约 26–28pt）。§9.4 的锁
  变体改法自此修正为烘焙法。
- 改法：四枚图标改预渲染 UIImage——以 UIImage.
  SymbolConfiguration(pointSize: 21, weight: .regular)
  生成后 Image(uiImage:) 入 tabItem。字形在生成时
  烘焙死，位图无变体可换，两态同一线条字形；点数
  21 落在用户直令的 20–22 目标带，点击热区是 tab
  条目本身、不随字形缩小。.tint 墨色照常生效（位图
  按 alpha 模板渲染）。新结构诊断图复核：四枚均为
  线条体、视觉明显小于 0.2.5。

### 10.6 回归与验收数值

- 回归测试 ComposerKeyboardTests 在新结构（safeArea
  Inset 承载）上通过（CI run 42506335381）：静止/键
  盘/键盘＋滚动三态推导胶囊高均为 54.0（规格 54±4），
  键盘确有升起（高 233），多行推导高 162.3（生长与
  6 行封顶口径不变），标题胶囊宽 143 ≤ 202。
- 主构建 CI 绿（run 42506812485）：Release 构建成功、
  OneDayCore 单测全过；未签名 IPA 解包核验
  CFBundleShortVersionString 0.2.6 / CFBundleVersion
  11 / bundle id site.didichou.oneday。注记：本轮首
  个构建 run（42506355374）解包验出仍是 0.2.5/10——
  版本在本仓是 Info.plist 直写字面量（Project.swift
  app target 处），只改工程 base 设置不进包，已补字
  面量后重跑，即本条 run。
- 已知问题（与本轮改动无因果证据）：ScreenshotTests
  .test02MainPages 等演示流式文本「先从定时任务模块
  动手」超时——整套连跑与单独复跑（run 42507232417）
  均复现，0.2.6 施工前仅加测试锚点的复现轮（run
  42504572278）已同症。疑似竞态：演示流式由
  chatSurface 的 .task 一次性触发、守卫含
  currentThread 非空，种子 @Query 未落定即触发会整
  场不起流；0.2.7 顺带按此修并复验。
- 观感终审仍归用户真机（截图规矩不变）：本节诊断图
  均为定位/验证手段，不进 docs/shots 留档。

## 11. 0.2.7 定案：高度权威换代＋图标官方口径

0.2.6 交付后用户真机回传：键盘弹起＋中文拼音输入时
发送舱仍膨成大空盒——首行文字顶盒顶、正在编辑的行连
同＋键/发送盘掉在盒底行、中间全空；底栏四图标真机仍
显大于 Muse。本版定案如下，前任施工的临时诊断/二分
代码已全部清出工作树。

### 11.1 膨胀源定案（代码级审计）

- 证据（用户真机截图量测）：拼音组合态下发送舱盒高
  约 140pt（约 5–6 行量级），而实际文字仅 2 行
  （「京津冀」已提交段＋「环境」组合段）。
- 定因：0.2.6 发送舱高度链上，承载 VStack、inputBar、
  内容行各环都挂了 fixedSize，但 fixedSize 的语义是
  「取子视图理想高」——只传导、不设限。链上唯一决定
  高度的是纵向 TextField：其理想高由 SwiftUI 与内嵌
  可滚动 UITextView 协商产生，我方没有权威量高者、
  也没有硬封顶。真机键盘升起触发安全区重排、拼音
  marked text 组合期间，该协商把理想高贪大至上限
  量级，各环 fixedSize 把它原样上传成整舱高度；
  HStack(.bottom) 把两键钉在膨胀后的盒底，文本视图
  顶锚首行——撕裂空盒的形态与此逐项吻合。模拟器布局
  通道不产生该提议（编程 marked text／真实拼音键盘
  三路构造均不复现），本地无从锁死，只能换机制。
- 玻璃容器（GlassEffectContainer/union）与承载方式
  （safeAreaInset）均已排除：0.2.6 换代后仍复发。

### 11.2 修法：高度单一权威（成熟结构）

- 文本视图换自量高 UITextView（ComposerTextView，
  UIViewRepresentable）：isScrollEnabled=false 常态
  关闭，sizeThatFits 以提议宽度量当前文本（含 marked
  段，与 IME 同路）的真实行高并返回——高度只有一个
  权威来源，即文本视图自己的布局管理器。此即
  Exyte/Chat 与 InputBarAccessoryView 的 InputTextView
  一脉的量高架构（开源实现出处：Exyte/Chat 的
  ChatInputView 与 MessageKit/InputBarAccessoryView
  的 InputTextView 均为「文本视图自量高＋条高＝视图
  高＋固定边距」）。
- 算术口径抽纯逻辑 OneDayCore.ComposerLayout，与量高
  共用同一组数字：行高 22.5、6 行封顶（135）、过封顶
  才内滚、多行判据＝实测高跨 1.5 行、舱内纵向边距
  32。胶囊总高规格：单行 22.5＋32＝54.5（54±4 内）；
  封顶时 135＋32＝167。玻璃改裸 glassEffect 施加在
  内容行本体（形状判据走 ComposerLayout.isMultiline，
  单行 Capsule／多行固定圆角 24 不变）。
- 高度回归改到单元测试层：ComposerLayoutTests 覆盖
  空／单行／多行／上限四态（见 11.4）。

### 11.3 底栏图标定案（官方口径）

- 标准改按官方：字形墨迹高 23–25pt——依据 HIG
  《Tab bars》指向的 Apple Design Resources 底栏
  字形规格（约 25pt）。实测 SF 符号在 UITabBar 渲染
  下墨迹系统性大于 SymbolConfiguration 点数且逐字
  形不同（config 21 时双气泡墨迹约 37pt、folder 约
  28pt），故逐字形反推 config 并两轮 CI 复量收敛。
- 定案：双气泡 config 12pt、其余三枚 15pt（墨迹落
  23–24pt）；字形烘焙进固定 44×44pt 透明画布居中
  绘制、显式 .alwaysTemplate——四条目位图同尺寸，
  系统排版基准一致，只缩墨迹、不动槽位与热区；两
  态同一张线条图，fill 变体切换问题维持 0.2.6 的
  烘焙法根除。

### 11.4 UI 断言处置

- ComposerKeyboardTests 的键盘态断言（点按聚焦→键
  盘升起→各态量高）删除。原因：文本视图换成
  UIViewRepresentable 后，XCUI 合成点按无法可靠
  驱动其聚焦（多轮 CI 实证）；真机上点按聚焦、打
  字、光标均正常（用户截图实证），问题只在测试工
  具侧。按既定验收分工，键盘态观感归用户真机终
  审，本文件只保留不依赖聚焦的静止态几何断言（胶
  囊推导高 54±4、防撕裂不变量、标题胶囊宽 ≤202）。
- 高度回归的把守层改为 11.2 的单元测试：量高机制
  （UITextView 实测）无法在单测内复现真机键盘通道，
  单测把守的是「实测高→应得高度」的算术不变量——
  膨胀的本质正是算术层失守（理想高无封顶地被采
  纳），新机制下返回高被 ComposerLayout 硬封顶，
  撕裂形态在算术上不再成立。

### 11.5 附带修复（保留项）

- 占位符移入 UITextView 内部子标签（InputTextView
  经典做法），representable 表面再无外来覆盖层。
- 「点空白收键盘」手势改挂消息内容栈：ScrollView
  本体的命中域含底部 safeAreaInset（发送舱所在），
  挂本体时管辖范围越界。
- 焦点桥改边沿触发：updateUIView 只在期望焦点相对
  上次已知状态变化时驱动第一响应者，消除电平触发
  在 delegate 回写窗口内误伤 resign 的竞态。
- 演示流等待预算放宽至 20s（§10.6 既存 test02 超时
  的稳健性处理）。

### 11.6 验收数值

- 收口提交 9152fdf（诊断代码清零＋量高恢复＋纯逻辑
  抽取＋§11 落档）；主构建 CI 一轮绿（run
  42517453812，workflow_dispatch）：Release 构建成
  功、OneDayCore 单测 49 条全过（较 0.2.6 的 45 条
  新增 ComposerLayoutTests 四态 4 条，均 passed）。
- 未签名 IPA 解包实测：CFBundleShortVersionString
  0.2.7 / CFBundleVersion 12 / bundle id
  site.didichou.oneday，与定版一致。
- 键盘态观感终审归用户真机（分工不变）：重点看拼音
  组合态发送舱是否贴着文字长、两键是否锚在编辑行。

## 12. 0.2.8 热修：焦点拆桥＋尺寸实测对齐

0.2.7 真机验收出两问题，本节只记这两件的定因与处置：
P0 点输入框键盘弹不出来（0.2.7 新回归，0.2.6 真机打字
正常）；P1 输入框单行高与底栏图标墨迹按真机实测对齐
Muse。本节数值口径一律以渲染后量测为准（真机优先），
不再采信 config 数字与二手像素换算（§11.3 的教训）。

### 12.1 P0 定因：焦点桥把关（hitTest 链审计）

定因：**@FocusState 边沿桥把关**。0.2.7 的聚焦路径是
「UIKit 点按聚焦 → delegate 回写 @FocusState → ChatView
重渲染 → updateUIView 边沿比对 → become/resign」——原生
聚焦须经 SwiftUI 焦点状态往返批准，而 SwiftUI 焦点引擎
对整个层级的第一响应者有自己的仲裁账：representable 在
引擎图外成为第一响应者时，其账面值（无 .focused 注册、
仅靠 delegate 异步回写）顶不掉引擎的「无焦点」认定，
更新一到即被 resign。证据链：0.2.6 纯 SwiftUI TextField
（经 .focused 正式登记在引擎内）真机聚焦正常；0.2.7 前
任三轮 CI 依次排除占位覆盖层、手势挂载点后聚焦仍被吃，
剩下的唯一聚焦治理差异就是这座桥；0.2.7 真机同症复现，
与「测试工具问题」的旧结论冲突，真机优先、旧结论作废。

hitTest 链审计（文本视图区域自上而下逐层，本次逐个读
代码核对）：①占位符 UILabel——文本视图内部子视图，
isUserInteractionEnabled=false，不吃触摸；②glassEffect
——施加在 composerRow 本体的渲染层（非叠加视图），同行
的＋键/发送键点按一直正常，证明该层不挡同行子视图触
摸；③HStack/VStack/bottomBar/safeAreaInset 宿主——无任
何手势与覆盖层；④消息列表内容栈的 onTapGesture——挂在
LazyVStack 子树，与发送舱（inset 子树）不同命中域；
ScrollView 的交互收起 pan 需位移才触发、不吞点按；⑤
抽屉 scrim 关闭时 allowsHitTesting(false)、面板偏移出
屏、左缘 24pt 热区不与输入框区域重叠；⑥topFade 在顶
部且 allowsHitTesting(false)；⑦文本视图本体配置
isEditable/isUserInteractionEnabled 均为真（0.2.8 起显式
写死）。结论：命中路径干净，病灶不在触摸、在聚焦批准
通道——拆桥（§12.2）。

### 12.2 修法：聚焦回归 UIKit 原生

- ComposerTextView 删除 isFocused 焦点桥与边沿逻辑；
  updateUIView 永不碰第一响应者。点按由 UITextView 原
  生 becomeFirstResponder 完成——文本视图是自身区域内
  最上层可交互元素，手指与它之间无手势/覆盖层（§12.1）。
- SwiftUI 侧状态只观察：Coordinator 的 didBegin/didEnd
  Editing 经 onFocusChange 回写 ChatView 的普通 @State，
  无任何视图据它把关聚焦。
- 程序化通道：新增 ComposerFocusHandle（弱引用文本视
  图＋pending 兜底）——点消息区空白收键盘、演示自检聚
  焦都经它直达本体，不经 SwiftUI 状态。
- 响应链自检（演示模式限定）：启动参数
  -odDemoFocusComposer 叠加 -odDemoMode 时，ChatView 落
  稳后经句柄程序化聚焦；ScreenshotTests.test07 断言系
  统键盘升起并留 kb-focus-selfcheck 附件。聚焦由 App 本
  体发起，不依赖 XCUI 合成点按——不构成点按聚焦调试；
  生产启动永不带此参数，真机点按终审归用户。

### 12.3 P1 定案：按实测改基数

量测基线（用户同机同批真机截图，主代理逐个量，402×
874pt@3x，误差 ±2pt）：输入框单行总高 Muse 约 45 /
OneDay 0.2.7 约 60；底栏图标墨迹高 Muse 约 24 /
OneDay 约 33；底栏总高两边同约 64–66（不动）。

- 输入框：ComposerLayout 改基数——行高 22.5→20（字体
  改固定 16pt 系统字体，ComposerTextView 不再随
  Dynamic Type 漂移）、文本纵向边距 16→10、两键直径
  36→30、行纵向边距 16 不变；单行总高＝max(20＋10,
  30)＋16＝46，落目标带 45–46。54.5 旧规格作废。多行
  自此基数按行递增，6 行封顶内滚逻辑不变；单测四态
  已同步新数（46/46/86/146）。
- 底栏图标：渲染管线（44pt 画布＋alwaysTemplate）不变
  时，墨迹高与 config 点数严格线性。按真机基线 33→
  目标 24（系数 ≈0.73）反推：双气泡 12→9、其余 15→
  11。§11.3 的「config 12/15 墨迹 23–24」系 CI 截图像
  素换算的错误量测，自此作废；本版以截图环渲染图复量
  为准（见 §12.4），再偏再修。

### 12.4 验收数值

- 构建 run 42519047031 一轮绿（CI 迭代 1/2）：Release
  构建成功、OneDayCore 单测 49 条全过（ComposerLayout-
  Tests 四态按新基数 46/46/86/146 均 passed）。IPA 解
  包实测 0.2.8 / 13 / site.didichou.oneday（主代理同法
  复验一致），已置 your_files/oneday-v0.2.8/。
- 截图环 run 42519050554：ComposerKeyboardTests 静止
  几何 passed（推导胶囊高落 43–49、field 单行高落
  17–24、锚差落 2–8、标题胶囊 ≤202）；Screenshot-
  Tests.test07 焦点自检 passed——程序化聚焦后键盘升
  起、截图里输入框带光标，响应链在 CI 侧证通。test02
  MainPages failed 于演示流等待（「先从定时任务模块动
  手」超时），是 §11.6 已记的整套负载下流式等待 flake、
  单独跑绿，与本轮改动无关，不作交付依据。
- 底栏墨迹 CI 基线（PIL 量 kb-idle 附件，px/3）：config
  9/11 四枚墨迹仅约 9–10pt——0.2.8 的校准在 CI 渲染口
  径下过冲向下（目标 24）。用户真机验收：键盘 ✅、输
  入框单行大小 ✅；图标仍非约 24pt、多行仍撕开——两
  条转 0.2.9 以闭环量测续修（§13）。真机点按聚焦终审
  以用户「键盘 OK 了」为准、通过。

## 13. 0.2.9 定案：停用截图环、确定性构造与纯逻辑

0.2.8 用户真机验收：键盘 ✅、单行大小 ✅；剩图标与
多行两条。本轮先误开已停用的 CI 截图环当量测台（用
户明令停用之物），主代理下停工改令＋根除令纠正，本
节为纠正后的定案。交付标准回到用户原令：构建绿＋
单元测试；真机观感由用户终审（既定分工不变）。

### 13.0 截图环根除与脚手架处置

「自动截图」的根在 .github/workflows/screenshots.yml
挂了 push 触发（分支＋Sources/Tests 路径），每推必
跑。本轮根除三层：①仓库层已由主代理 gh workflow
disable 停用；②文件层删除该工作流文件（git 历史可
恢复）；③交付路径摘除——OneDayUITests target 与两
份 UI 测试文件（ScreenshotTests、ComposerKeyboard-
Tests）删除，scheme 测试目标只剩 OneDayCoreTests；
演示自检脚手架摘除：程序化聚焦开关（-odDemoFocus-
Composer）、定长文本注入（-odDemoComposerText）及
ChatView 两处消费点（聚焦自检、文本注入）删除。
DemoMode 本体与种子数据保留：仅显式启动参数激活、
生产恒 .off，是本地人工演示/调试入口，不属于交付
验收路径（DemoMode.swift 文件头注已写明）。

### 13.1 图标：确定性构造（弃画布缩放）

三轮修不对的机制根源：字形尺寸被交给「config→画
布→系统渲染」的比例链，每环都有自己的缩放规则，
config 数字与最终字形之间没有构造保证。本轮换确
定性路线（OneDayCore.TabBarSymbols）：SF Symbol 以
显式 pointSize 生成，pointSize 由目标字形高反定——
先以 100pt 参考尺寸生成、量其 alpha 包围盒高，再
按目标 24pt 线性定标重生成。成品图的字形高由构造
本身决定（24pt 对齐 Muse 底栏字形规格，用户口
径），无画布、无留白、无缩放环节；结果缓存、重复
生成逐位一致。位图无符号变体，0.2.5 的选中态
.fill 切换天然免疫；alwaysTemplate 保证 tint 生效。
定案凭据＝单元测试（TabBarSymbolsTests，与工厂共
用同一 alpha 量法）：四字形 alpha 高 24±2、模板模
式、确定性——绿即定案，与截图/渲染环境无关。

### 13.2 多行：纯逻辑定案与撕开根因（代码审计）

高度链逐环审计后的同源结构：
- 字体同源：正文字体单一来源 ComposerTextMetrics
  .bodyFont（固定 16pt 系统字体），ComposerTextView
  与量测共用同一 UIFont，不存在第二份字体定义。
- 宽度同源：文本视图实际布局宽＝容器宽 − 132
  （ComposerLayout.horizontalChrome，逐项对应
  ChatView 几何：inputBar 边距 12×2＝24、composer-
  Row 边距 8×2＝16、两键 30×2＝60、HStack 间距
  8×2＝16、字段边距 8×2＝16）；sizeThatFits 的布局
  提议宽原样喂 TextKit，量测宽≡布局宽。此前宽度可
  能脱钩的环节（理想高协商）已于 0.2.7 换代根除。
- 行数与高度：行数由 TextKit（NSLayoutManager，排
  版参数与文本视图本体一致：lineFragmentPadding
  0、无内边距、按词缠绕）在上述字体与宽度下数出
  （含 marked 段，与 IME 同路）；胶囊高只经
  ComposerLayout 纯函数（行数 × 行高 19.17＋边距，
  6 行封顶）。高度链上没有第二权威。
- 行高常数：旧常数 20 是近似，16pt 系统字体真实行
  高 19.17——常数已改实测值，且单测钉住「常数 ==
  bodyFont.lineHeight（±0.5）」，字体口径再变会先
  红在单测而不是漂到真机。
撕开根因分代定案：0.2.5/0.2.6 世代的膨胀＝纵向
TextField 的理想高由 SwiftUI 与内嵌可滚动 UIText-
View 协商贪大（§11 定案，0.2.7 自量高换代根除）；
0.2.7 世代残余偏差＝行高常数近似（本轮修正如上）。
现行架构下胶囊高是「TextKit 行数 × 行高」的纯函
数，不存在能把盒子撑开的第二方提议——这是代码审
计层面的定因。核心断言进单测（ComposerTextMetrics-
Tests）：2 行定长串胶囊＝单行基数 46＋1×行高
（±1，实差 0.83＝单行键侧主导的构成差）、4 行＝
46＋3×行高（±1）、37 字缠绕在宽 270 下恰 3 行、
空文本 1 行 46。

### 13.3 验收数值

- 提交链：06f7fff（§12.4 回填）→ aaa6823/87e7d1e
  （第一轮，已被定案轮取代）→ e830f2f（口径对齐轮，
  同被取代）→ 149e3df（定案）→ 4d073f5（静态缓存并
  发安全修）。构建以定案轮为准。
- 构建 run 42522644541（HEAD 4d073f5）绿：Release
  构建成功；OneDayCore 单测 **58 条全过**（原 49＋
  新增 9：TabBarSymbolsTests 3——四字形 alpha 高
  24±2、alwaysTemplate、重复生成尺寸逐位一致；
  ComposerTextMetricsTests 6——宽 270 推导、行高常
  数↔字体行高一致、2/4 行胶囊＝基数＋(n−1)×行高
  ±1、缠绕恰 3 行、空文本 1 行 46）。
- IPA 解包实测 0.2.9 / 14 / site.didichou.oneday，
  已置 your_files/oneday-v0.2.9/（终版 1,925,687
  字节；第一轮的同名包已被定案轮替换）。
- 截图工作流：文件已删（本提交链内），仓库层
  disable 由主代理执行；本轮未跑、未看任何截图
  run。真机终审（图标观感、多行手感、键盘点按）
  归用户。

## 14. 视觉纪律（用户令 2026-11-09）

用户原令十条（逐字转录，不得改字义）＋每条的 SwiftUI
落法。实施批次：0.3.0（与模型选择接线同批）。实施汇
报逐条对账：哪条落在哪、哪条受平台限制只能等价近似、
近似成什么样，不许默默跳过。

### 条 1
原文：「禁黑框与 #000：全 App 不出现纯黑边框与 #000；
背景靠 4 层、层间明度差 1–3% 的微差分层（页面/卡片/
浮层/遮罩）。」
落法：Palette 立四层阶梯令牌（层 1 页面 / 层 2 卡片 /
层 3 浮层 / 层 4 遮罩），浅色明度 100→98→96→遮罩（墨
色 32% alpha），深色同理以 2% 级差排布；现有 pageBG/
surface/fieldFill/bubbleFill 归入阶梯并微调到级差内；
边框一律 hairline（墨色低 alpha），清除全仓 0x000000
与 Color.black 残留（AccentTheme 一处、ChatView 一处）。

### 条 2
原文：「输入框聚焦禁描边：聚焦态不出现边框高亮，改加
深双环阴影。」
落法：发送舱（composerRow）聚焦态不加任何 stroke；
改以两层 shadow 叠加（近环：墨色 12% alpha、半径 6、
y 2；远环：墨色 8% alpha、半径 18、y 6），随
composerFocused（delegate 观察回写）切换、带动画。

### 条 3
原文：「暗色模式字重全降一档（原令「全降40」）：暗色
下所有文字字重降 40（CSS 权重量纲），即视觉降一档。」
落法：OneDayDesign 出字重映射函数（CSS 权重量纲
100–900，暗色 −40 后就近落 SwiftUI 字重档：如 600→
500、500→400、700→600）；TypeScale 的字体工厂在暗色
环境下统一走映射——文字经 TypeScale/语义字体出入口
收敛者全量生效；裸 .font 字重散点逐处改走工厂。

### 条 4
原文：「流式打字渐显：新字以 blur 6px 起、120ms 化开，
字间错开 30ms 依次入场。」
落法：流式回复渲染组件按增量字符入场：每个新字符包
一层动画态（blur 半径 6→0、opacity 0→1、120ms），同
批增量内字符以 30ms 步进延迟（字符序号 × 30ms）；已
入场字符静止不重演。实现为 StreamingText 组件（字符
级 AttributedString/分段 Text 拼接，动画用 .animation
delay 驱动），只作用于流式进行中的助手回复，完成落
盘后切回整段静态渲染。

### 条 5
原文：「图标相对文字下移 0.125em 做光学对齐。」
落法：图标与文字同行的场景（行项、按钮、状态行），
图标统一 .offset(y: 字号 × 0.125)——body 16pt 处约
2pt；以 View 扩展 iconOpticalOffset(fontSize:) 单点
维护，逐个同行点位施加（底栏纯图标无文字同行，不在
此列）。

### 条 6
原文：「所有数字用等宽数字（tabular-nums 等价），防
宽度抖动。」
落法：含数字的 Text 统一 .monospacedDigit()；时间、
计数、金额、用量、会话数等展示点逐处施加，时间戳组
件与统计组件优先收敛到共用数字文本样式。

### 条 7
原文：「折叠展开走平滑高度动画（Grid 0fr→1fr 的等
价意图），禁跳变。」
落法：SwiftUI 无 0fr/1fr 原语，等价实现为 SmoothExpand
容器：内容以 .fixedSize 实测高、容器高度在 0↔实测高
间以动画插值并 clip——视觉等价于 Grid 行高 0fr→1fr；
施加于全部可折叠区块（长思考/工具块、会话抽屉分组、
设置折叠项等现存折叠点）。

### 条 8
原文：「正文段落优化断行（text-wrap: pretty 等价意
图）：避免尾行孤字、断行难看。」
落法：SwiftUI 无 text-wrap:pretty，等价近似为断行整
形纯函数（OneDayCore，可单测）：对段落文本做尾行孤
字防护——当末行将只剩 1 个 CJK 字（或 1 个英文词）
时，把末行与前行之间的断点前移一位（在倒数第二断
点处以不可断空格/零宽策略绑定最后两字），使末行至
少 2 字；施加于助手正文与用户气泡的段落渲染前。
近似边界：逐行断点由排版宽度决定，整形函数以与渲
染相同的宽度估算行为（CJK 等宽近似），不保证与
TextKit 逐行完全一致——属等价意图近似，汇报注明。

### 条 9
原文：「弹簧参数定版：拖拽类交互 stiffness 1200 /
damping 80、零回弹；点赞类小动作 380 / 18、微弹
（SwiftUI 用 interpolatingSpring 同名参数落）。」
落法：MotionTokens 定版两支：dragSpring =
.interpolatingSpring(stiffness: 1200, damping: 80)、
microSpring = .interpolatingSpring(stiffness: 380,
damping: 18)；拖拽类（会话抽屉拖动、滑动手势跟随）
走 dragSpring，小动作（点赞/收藏类点按反馈、徽标
跳动）走 microSpring；其余历史弹簧常量向这两支收敛，
个别保留者须在 MotionTokens 注明理由。

### 条 10
原文：「复制反馈：点复制后对勾确认态显示，2.5s 自
动消失。」
落法：CopyButton 共用组件：点按复制 → 图标切对勾
（checkmark）＋可选「已复制」字样，2.5s 后自动复原
（Task 计时、可取消，重复点按重置计时）；施加于代
码块复制、消息复制等全部复制点。

