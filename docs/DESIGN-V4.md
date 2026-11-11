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


## 15. 0.3.0 实施记录：视觉十条对账与模型接线

### 15.0 设计基线合并口径（2026-11-09 用户令）

界面设计基线新增 awesome-design-md 的 Claude 篇（原文
归档于 docs/reference/claude-DESIGN.md，589 行，本节
为其与本 App 既有口径的合并裁决）。优先级定版：

**用户视觉十条（§14）＋腾讯蓝主题定案 ＞ Claude 篇的
token 与组件语言 ＞ DESIGN-V4 既有其余条款。**

逐条裁决（冲突不许静默取舍，均列明）：

| Claude 篇 | 本 App 裁决 |
|---|---|
| 暖米色画布 #faf9f5 | **参考不采值**：其「暖底、四层暖表面」的分层思想与 §14 条 1 的四层阶梯同构、互相印证；但本 App 浅色底已定版纸白系（#FFFFFF 起阶梯），不换暖米——换底色属主题级变更、非本批授权 |
| 四层暖表面 | **采结构**：层数与「靠表面分层、不用描边堆层级」的组件语言与 §14 条 1 一致，作四层阶梯的旁证；具体色值走 §14 阶梯 |
| 墨色 #141413（非纯黑） | **相容采纳为旁证**：与 §14 禁 #000 同向；本 App 墨色令牌（ink 0x1A1A1E 等）已是非纯黑，不改值 |
| 珊瑚主色 #cc785c | **不采**：主题定案为腾讯蓝（#0052D9 系），优先级在其上；珊瑚仅作参考记录 |
| 衬线大标题（Copernicus/Tiempos slab-serif） | **不采**：App 标题体系（TypeScale 无衬线定版）优先；其「编辑式排版」的气质（标题克制、留白叙事）作参考 |
| 编辑式排版与组件行为（克制 CTA、内容先行） | **采行为**：与既有纪律（单强调色、玻璃只住功能层）同向，后续组件细化时按此校 |

动效图标基线同批定（细节走技能
~/workspace/custom-skills/animated-icons/SKILL.md）：
LORD Icon 走免费层＋署名（用户拍板不买 PRO）——设
置页「关于」已加 “Icons by Lordicon” 署名行（本批
先行落位，上架时商店描述同步）；变形类（状态切换）
走原生等价（本批：发送↔停止合一为 sendStopButton、
SF Symbol replace 过渡）；LORD 类（一次性反馈）待
System 家族图标资产选定后自托管 Lottie JSON 接入
（白名单：复制成功与 §14 条 10 合并、连接成功等），
尊重系统减少动态效果。白名单外位置一律静态。

### 15.1 视觉十条逐条对账（与 §14 对应）

1. **黑框/#000＋四层分层**：Palette 改四层阶梯（浅
   100/98.4/95.9/94.9、深 4.5/7.3/9.6/11.2，级差均
   1–3%）；层 4 遮罩为 Palette.scrim（墨色 alpha）——
   抽屉 scrim 自 Color.black 换入；AccentTheme 的
   0x000000 改 0x111114；Elevation 阴影色自 .black 改
   0x0A0A0C。落地后全仓 grep：0x000000/Color.black
   零残留（构建后自证）。
2. **聚焦禁描边**：发送舱聚焦态无任何 stroke 新增；
   composerRow 按 composerFocused 加深双环阴影（近
   环 .13α/r6/y2、远环 .10α/r18/y6；静止态淡影
   .05/.04），swap 动画过渡。
3. **暗色字重降一档**：两路覆盖——带权字体走
   TypeScale 的 (for: ColorScheme) 变体（display/
   title/label，映射表 OneDayCore.VisualWeight，单
   测把守）；未带权文字走 ContentView 根 fontWeight
   环境（暗色 .light）。UIKit 输入正文不在 SwiftUI
   环境内，不受影响（如实注记）。
4. **流式渐显**：新组件 StreamingText——词元化
   （CJK 逐字、拉丁按词）后以 TokenFlow 换行布局排
   布；新词元 blur 6→0＋opacity、120ms、同批增量
   序号×30ms 错峰；光标作末尾词元同流。落盘成品回
   MarkdownText 静态渲染。
5. **图标光学对齐**：iconOpticalOffset（0.125em≈
   body 处 2pt）修饰符入 OneDayDesign，施加于共用行
   组件 ContentRow 的图标位——全部经该组件的行项一
   致生效；散点图标后续新增同行点位须走此修饰（组
   件层纪律）。
6. **等宽数字**：tabularDigits()（monospacedDigit）
   入口＋ContentRow.trailing 读数位施加；Mono 字阶
   （monoFootnote 等）本就等宽、双保险。时间戳走
   ContentRow/状态组件同一出口。
7. **平滑高度展开**：SmoothExpand 组件（实测高
   0↔全高插值＋clipped，0fr→1fr 等价）入设计层并
   施加于发送舱附件条的出现/消失；全 App 后续折叠
   只许用它。
8. **断行 pretty**：等价近似——TextShaping 纯函数
   以 WORD JOINER 绑尾字形（末行 ≥2 字形、句末标
   点绑三），施加于 MarkdownText 段落与用户气泡。
   近似边界：不做行长均衡（balance）；绑定不估行
   宽，保证的是孤字情形结构性消除（函数文件头注
   已写明，单测把守）。
9. **弹簧定版**：MotionTokens.dragSpring
   （1200/80）/microSpring（380/18）定版；抽屉归位
   自 indicator 换 dragSpring；回到底部钮出入动画
   换 microSpring。其余 press/swap/entrance 等时基
   动画非弹簧类、保留（非拖拽非点按反馈，不在条
   9 两支口径内）。
10. **复制反馈**：CopyButton 共用组件（doc.on.doc
    →checkmark、Palette.success、2.5s Task 计时自
    隐、重复点按重置），施加于 MarkdownText 代码
    块右上。全 App 此前无任何复制点，本条同时补齐
    代码块复制能力本身。动效合并点（§15.0）：复制
    成功位列 LORD 白名单，后续以 Lottie 动效替换静
    态对勾时仍守本条 2.5s 自隐口径。

### 15.2 模型选择接线（研究口径见 ChatModels 文件头）

- 清单：OneDayCore.ChatModels 写死三项（deepseek-
  flash / deepseek-v4-pro / Qwen/Qwen3-30B-A3B-
  Instruct-2507-FP8），含展示名与说明；单测钉顺序、
  provider 口径与初始选择优先级。
- 选择：AppState.chatModel（UserDefaults 持久化），
  初始＝已存选择 > 服务端默认（须在清单内）> flash；
  selectChatModel 只写本地、不发请求。顶栏胶囊展示
  名改读 chatModel 展示名（名实一致）；选择器整表
  重写为三项本地点选。服务端默认管理（设置页
  setDefaultModel）与 ModelCatalog 原样保留、互不
  干扰。
- 请求：chatStream 请求体对清单内模型加
  "provider": "custom"（HermesClient 组包处按
  ChatModels.providerField 决定）。
- Qwen 冷启：超时沿用既有 600s（≥研究口径
  240s）；runStream 对 chatModel==coldStartID 且零
  增量失败时自动重试 1 次，重试期间等待行亮「模
  型唤醒中，冷启动约 1–3 分钟…」；已产出内容不重
  试（防重复）。
- 严禁项守纪：不发「/model xxx」文本；hermes-agent
  不进聊天候选（清单写死、providerField 对它返
  nil、顶栏不再展示它）。

### 15.3 验收数值

- 提交链：3332dc6（十条＋接线主体）→ 1479454（补
  规格两条）→ StreamingText init 编译修复 → §15.0
  与署名 → TextShaping 绑定点修复（HEAD）。
- 构建三轮：42523821783 编译失败一处（StreamingText
  缺无标签 init，已修）；42523997817 编译过、单测
  2 失败（TextShaping 的 WORD JOINER 插在尾部之前
  防不住末字孤立——实现错、测试期望对，改尾内逐对
  绑定后定案）；42524590858 终轮绿。
- 单测 **65 条全过**（58＋新增 7：VisualRulesTests
  4——字重降档映射、孤字绑定 2/3 字形、文档逐行；
  ChatModelsTests 3——三项清单钉死、provider 口
  径、初始选择优先级）。
- IPA 解包实测 0.3.0 / 15 / site.didichou.oneday，
  已置 your_files/oneday-v0.3.0/（1,958,748 字节）。
- 纯黑自证：全仓 grep 0x000000 / Color.black /
  UIColor.black ＝ 0 残留。
- 真机终审归用户：视觉十条观感（分层/聚焦影/暗色
  字重/流式渐显手感）、模型三项逐请求切换实效
  （Qwen 冷启唤醒链路尤其要真机验一遍——客户端规
  格已按研究口径实现，网关 303 既有缺陷在服务端
  侧、未修，归部署线）。

## 16. 0.3.1 定案：底栏图标改系统直渲＋原生栏止损条款

### 16.1 四轮不过的定因与本轮定法

底栏图标自 0.2.5 起四轮真机打回（线条化→预渲染
定标→HIG 口径→0.2.9 确定性构造）。0.2.9 的 alpha
包围盒定标在单测层无懈可击，真机仍被判「大小不
对」：同图双卡量测字形高已接近（OneDay 约 26 单位
vs Muse 约 22 单位，卡片缩放口径仅供参考），真
正的差在**描边**——Muse 是细线条 regular 字重，
OneDay 观感更粗、更「大坨」。定因：几何定标只管得
住字形框高，管不住两件事——①字重/描边的观感；
②预渲染位图进原生 TabView 后被当普通位图二次缩
放，构造层的精确数在渲染层被改写。

本轮先按简报定「SymbolConfiguration 定标
（22pt／.regular／.medium）」，施工中被用户改令
覆盖，定法改为**照搬礼记**（用户点名；礼记仓库
ContentView 实证在案）：礼记底栏大小天然对，靠的
不是任何定标，而是**纯原生结构让系统按默认度量
渲染**。OneDay 照此执行：

- **结构换礼记同款**：`TabView(selection:)`＋
  `Tab(value:)`＋`Label(标题, systemImage:)` 系
  统直渲。删除一切我方渲染介入：TabBarSymbols
  的烘焙路线（construct 定标、alphaBounds、预
  计算表）早已删尽，本轮连同配置定标一并作废，
  TabBarSymbols 只保留**符号名对数据**（单一事
  实源）。0.2.4 的「只要图标不要文字」同步作
  废：标题随 Label 进栏、由系统排布。
- **选中态学礼记**：未选线条体 ↔ 选中切官方
  .fill 成对变体——bubble.left.and.bubble.right
  ↔.fill、folder↔folder.fill；chart.line.
  uptrend.xyaxis 与 slider.horizontal.3 目录内
  无 .fill 对，选中同名。0.2.5 的「.fill 全面禁
  用」就此反转（当年禁 fill 是因为系统自动换变
  体不可控；现在由我方按选中态显式给名，可控）。
  选中时 `.symbolEffect(.bounce, value: 是否选
  中)` 弹一次，系统在 Reduce Motion 时自动抑
  制（礼记同款）。

### 16.2 tabBarMinimizeBehavior 评估：不采纳

礼记在用 `.tabBarMinimizeBehavior(.onScrollDown)`，
本轮评估后**不加**，理由记档：该行为是 TabView
全局行为、落点却是 OneDay 的主表面聊天页——消息
流与键盘联动、发送舱经底部安全区贴栏而坐，滚动
是对话本身而非浏览；栏的反复收起/展开会持续改
变底部插入几何，正是 0.2.6–0.2.8 三轮为发送舱稳
定性付出代价要守住的东西。礼记的表面是台账列表
（滚动即浏览），最小化免费；OneDay 聊天页不是。
其余三页的列表收益不足以 justify 全局行为对聊
天页的风险敞口。

### 16.3 单测口径

TabBarSymbolsTests 改写：只钉符号名对清单——四
条目（id／标题／未选／选中）全表、成对变体纪律
（凡两态不同名者必须是官方 .fill 后缀对）、按态
取名。alpha 量高断言与配置定标断言均已删除。交
付标准不变：构建绿＋单测，不碰截图（工作流已
删）。

### 16.4 止损条款（用户口径，本节为凭）

**这是原生底栏的最后一轮。** 若 0.3.1 真机仍判
不过，下一版直接**自绘底栏**（字形尺寸、字重、
选择胶囊全部自控），不再回原生栏调参。本轮遵
令未提前自绘。

### 16.5 验收数值

- 提交链：212835b（先行配置定标版，同日被改令覆
  盖、未交付）→ 本节定法提交（照搬礼记结构）。
  先行版构建 run 42525581650 已按令取消。
- 构建 run **42525828519 一轮绿**；单测 **65 条全
  过**（TabBarSymbolsTests 换代 3 条：名对全表／
  .fill 成对纪律／按态取名；总数与 0.3.0 持平）。
- IPA 解包实测 **0.3.1 / 16 / site.didichou.
  oneday**，已置 your_files/oneday-v0.3.1/
  （1,955,916 字节）。
- 真机终审归用户：底栏图标大小与描边（与 Muse
  并排）、选中 .fill 切换与 bounce 手感、标题进
  栏后的整体观感。若仍判不过，按 §16.4 止损条款
  下一版自绘底栏，不再回原生栏调参。

## 17. 0.3.2 礼记对齐包：令牌表、原生 List、动效纪律收编

用户 2026-11-09 点名 OneDay 全面参考礼记（设置页、AI
助手页、对话框、字体颜色、主色调与腾讯蓝强调、交互与
动画「都很好」）。参照研究全文见工作区
oneday-design-review/liqian-reference-20261109.md；本
节是实施对账。礼记的总纲一句话：**系统原生件＋语义令
牌单点＋纪律写进代码**。本版五块逐块销账如下。

### 17.1 令牌层礼记化（审查 #6 合并销账）

- 新增 `ThemeTokens` 主题令牌表（OneDayDesign/
  AccentTheme.swift）：每主题一行、浅/深各一套 Scheme
  （表面四层、scrim/hairline 基色＋alpha、文字三角色、
  强调三档＋onPrimary、反馈语义三色）。学礼记
  AppThemeTokens 的查表架构：`Palette` 只剩工厂——
  `token(_:)` 按当前主题行＋系统外观生成动态色，读
  AccentStore 即订阅、切主题自动重绘（沿 0.2.x 传播
  机制）。
- 本轮范围如实记：**腾讯蓝是唯一完整主题行**（结构令
  牌全套定值，数值即 0.3.0 的 §14 四层阶梯与三角色，
  零漂移）；深蓝/墨黑/紫/绿四款沿 0.2.1 既有行为，只
  换强调三档、结构令牌共用腾讯蓝行（`withAccent`
  派生）。将来整套换肤色温只需给该主题一行完整令
  牌，组件零改动——结构按可换主题建。
- 裸色清零（grep 证据，提交时点）：`Color(hex:`、
  `Color.black/white`、`0x000000`、`Color(uiColor:`、
  `.white/.black` 裸样式在 **OneDayDesign 之外 0 残
  留**。收编明细：ChatView 发送舱双环影的 0x0A0A0C
  ×2 → `Palette.shadowBase`（Elevation 同源同值一并
  收口）；发送键 `Color.white` 与主按钮 `.white` →
  `Palette.onPrimary`（新令牌，填充上文字色）；抽屉
  搜索框 `Color(uiColor: .secondarySystemBackground)`
  → `Palette.fieldFill`；外观页色点 `Color(hex:
  theme.swatch)` → 设计层 `theme.swatchColor`；外观
  页预览钮与文件页视频角标的 `.white` → onPrimary。

### 17.2 设置页骨架（原生 List）

- SettingsView 由 ScrollView＋VStack＋odGroup＋手绘
  分隔/箭头，整页改 **原生 `List(.insetGrouped)`＋
  Section＋共用行组件**（学礼记 MeView）：分组容器与
  披露箭头由系统唯一提供；行走本页共用组件 navRow
  （NavigationLink 直达路由）/infoRow/serverRow，
  行底 `.listRowBackground(Palette.surface)`、页底
  pageBG（scrollContentBackground 隐藏）。
- 内容组织一字不增删：服务器与连接／智能体／模型与
  密钥／网关／外观／关于六组与全部条目、摘要加载、
  深链消费、两处确认弹窗（断开/重启）原样保留。版
  本号行更新为 0.3.2。

### 17.3 输入栏与气泡（材质＋染色、度量收编）

- 发送舱材质改走 Mat 令牌入口：裸 `.glassEffect
  (.regular)` → `.odGlassSurface(.tinted, in:)`
  （学礼记 AdvisorView 输入栏 Mat.tinted＋主题染
  色：玻璃以品牌浅染 primaryTint 轻染）。
- 度量收编（审查 T-4 具名纪律）：气泡内边距 14/10
  → `bubblePaddingH/V`；气泡对侧让位 44 →
  `bubbleSideInset`；附件签圆角 10 → `codeCorner`；
  多行胶囊圆角 24 → 既有 `composerCorner`；流式词
  元间距 5 → `tokenFlowSpacing`；抽屉左缘热区 24 →
  `drawerEdgeZone`；抽屉宽 0.82/340 →
  `drawerWidthFraction/drawerMaxWidth`；底栏占位
  76 → `tabBarZone`。用户气泡染色（primaryTint）与
  助手侧 Markdown 无气泡形态不变（助手泡为 bubbleFill
  软填充，0.2.5 定版）。

### 17.4 文字令牌与对比表（审查 #4/I-1 销账）

- 暗色 inkMuted 提亮：令牌表暗行 0x7C7C82 →
  **0x8A8A90**。出厂常用色对对比表（相对亮度公式实
  算，全对 ≥4.5:1）：
  - 浅色：ink/pageBG 17.4、ink/bubbleFill 15.8；
    inkSecondary 8.8 / 8.0；inkMuted 5.1 / 4.6；
    白字/primaryFill（003CAB）9.4；primary/pageBG 6.5
  - 暗色：ink/pageBG 17.6、ink/bubbleFill 15.9；
    inkSecondary 8.9 / 8.0；inkMuted 5.7 / **5.2**
    （旧值 4.3 不达标，本版修复）；白字/primaryFill
    （0052D9）6.5；primary/pageBG 7.8
- 正文/弱文字全走语义令牌：本版清零的裸色点即证
  据（17.1）；系统色直用仅剩动态色工厂内部。

### 17.5 动效纪律（审查 #2/#3/#5/#7、M-1/M-3/M-4、E-1/E-2 合并销账）

- **MotionTokens 令牌册收编**：礼记四档 ↔ OneDay 对
  应成册（press/liquidSpring/pageCrossfade/entrance
  偶发档＋swap/streamIn 专用档＋dragSpring/
  microSpring 定版弹簧归档）。变更三处：旧 indicator
  档（spring 0.35/0.85，全仓零调用）退役 → **liquid
  Spring 取礼记定版值** interactiveSpring(0.34,
  0.72)；pageCrossfade 0.2 → **0.25**（礼记值，落点
  RootView 根切换与回滚底部）；流式入场 120ms 字面
  量 → 具名 **streamIn**。
- **press 取值分歧如实记**：礼记 press＝snappy 0.22，
  OneDay 保留自家 easeOut 0.15——审查 E-5 已把现行
  按压反馈确认为强项（按下即响应、只动 opacity/
  transform），档位对齐、取值按自家实测口径，不跟
  值。此为本版唯一「学结构不学数值」处。
- **弹簧语义落档（E-1）**：dragSpring ζ≈1.15（过阻
  尼零回弹）、microSpring ζ≈0.46（欠阻尼微弹）已补
  进令牌注释；速度交接的 SwiftUI 平台上限注记同
  入册（E-2）。退出快于进入口径成文入册头注（M-4：
  弹簧面共用弹簧、定时面退出 ≤进入 0.8、系统面不
  自改）。microSpring 的 calm 备选档（审查 #9 后
  半）本版未预备，留待真机手感反馈再定。
- **resolved() 全覆盖**：全仓 `.animation`/
  `withAnimation` 落点逐一过——StreamingText 词元入
  场、SmoothExpand、发送舱形状切换（0.18 字面量收
  编 swap，M-3）、发送舱聚焦影、回到底部钮出入、滚
  动回底、根切换、PressableButtonStyle 按压、连接页
  入场、抽屉开合，**无一绕行**；余下只有系统行为
  （sheet/符号 contentTransition）与 TimelineView
  状态指示（非动画落点，caret/等待点已各自读
  Reduce Motion）。SmoothExpand 补重量护栏（M-1）：
  内容实测高 >400pt 时高度瞬时到位、不做高度动
  画（原案的 crossfade 简化为瞬时，近似如实记）。
- **stagger 批级封顶（M-2/E-4）**：StreamingText 单
  批增量 >8 词元时步进压缩（总时长 ≤240ms）且退
  化为纯 opacity 无 blur；Reduce Motion 开启时新词
  元整段直显、不排队。
- **触感只挂结果事件**：Haptics 收编为 success/
  warning 两口（UINotificationFeedbackGenerator）。
  落点：发送完成（回复落地 .success）/发送失败
  （.warning，用户主动停止不给）、连接成功/失败
  （ConnectView）、复制成功（CopyButton 的
  .sensoryFeedback(.success)，设计层组件走 SwiftUI
  原生口）、网关重启与网关启停指令成功/失败、文件
  删除成功/失败。**撤销的旧触点**（0.2.2 口径作
  废）：抽屉吸附 light、删除会话 medium、发送起手
  light、文件删除确认 medium、网关确认 medium。
- **条 5/6 补落点（#5）**：tabularDigits 新增落
  点——总览指标格读数（＋numericText 过渡）、设置
  navRow 值位（＋numericText）、文件行副题（大小/
  日期）；iconOpticalOffset 新增落点——设置页全部
  行图标（rowIcon 统一施加）、抽屉新建会话行、文件
  行图标、连接页步骤图标（15pt 字号口径）。与礼记
  「等宽与 numericText 成对」的落点：指标格与设置
  值位两处成对施加。
- **CopyButton 热区（#7/I-2）**：命中区 28 → **44**
  （minTapTarget），视觉字形与 28pt 图标区不变。

### 17.6 剩余项（明说）

- 审查优先 #1（页面底暖化裁决）不在本包范围：四层
  阶梯维持 0.3.0 中性定版值，裁决待用户拍板后再动
  令牌表行值（架构已就位，届时只改一行）。
- 审查 #10 出厂门入档、E-7 两件小事（连接成功对勾
  Pop in、模型对勾 symbolEffect 过渡）、E-3 抽屉橡
  皮筋、Hallmark 63 中点连缀改写，未在本包范围，
  留待后续小版。
- 设置页改 List 后系统分隔线对齐线由系统决定（不
  再是 dividerInset 60 的自绘线）——礼记同款取舍，
  真机观感归用户终审。
- 真机终审点：设置页 List 观感与箭头、发送舱染色
  后的玻璃色温、暗色弱文字可读性、触感新落点体感。

### 17.7 验收数值

- 提交 f6dd3ae（五块一次落地）；构建 run
  **42526952431 一轮绿**；单测 **65 条全过**（本版
  改动全在 OneDayDesign/OneDayApp 两层，OneDayCore
  未动、测试数与 0.3.1 持平）。
- IPA 解包实测 **0.3.2 / 17 / site.didichou.oneday**，
  已置 your_files/oneday-v0.3.2/（1,954,636 字节）。
- 裸色 grep 自查（提交时点）：OneDayDesign 之外
  `Color(hex:`/`Color.black`/`Color.white`/
  `0x000000`/`Color(uiColor:`/裸 `.white` **0 残
  留**；动画字面量在 DesignTokens 令牌册之外 **0
  残留**；旧 `Haptics.light/medium`、旧
  `MotionTokens.indicator`、旧 `AccentTheme.values`
  引用 **0 残留**。
- 真机终审归用户：设置页 List 观感与系统箭头、发
  送舱染色玻璃的色温、暗色弱文字可读性、触感新落
  点体感、流式大批量补发时的退化表现。

## §18 0.3.3「去暖＋真机七条」（build 18）

本版三批并入：用户当场否决暖色的第 0 条（最高优先）、
0.3.1 真机六条（底栏/顶栏/锚底/光标/换行/上文下钮）、
设置页「太 low」五项与字重阶梯审计。逐条对账如下。

### 18.0 第 0 条·去暖（用户否决，长期口径）

- 用户原话：「不要暖色，暖色就是 AI 色，直接 pass。」
  审查备忘录优先第 1 条「页面底暖化」与 §15 暖面口径
  **就此作废、不得再捡**——本节即回滚口径的存档点。
- 浅色阶梯逐项对齐礼记 AppTheme.tencentBlue 令牌原值
  （~/workspace/liqian-app/Sources/LiqianDesign/Palette
  .swift，AppThemeTokens.tencentBlue）：pageBG
  0xF2F3F5（冷灰底）、surface 0xFFFFFF（纯白卡）、
  ink 0x1F2329、inkSecondary＝礼记 sub 0x5F6570、
  primaryTint 0xEAF1FE、hairlineBase 0x1F2329（礼记
  line 0xE3E6EB 的基色侧）；bubbleFill 0xECEEF1、
  fieldFill 0xF2F3F5 为同温冷灰派生。强调色 #0052D9
  不动。暗色阶梯本已全冷（0B0B0D/121214/17181B/
  1B1C1F，B≥G≥R），原样保留。
- 事故复盘：0.3.0/0.3.2 的浅色阶梯是 pageBG 纯白＋
  surface 0xFAFAFB——方向反转（卡比底暗）且只差一
  丝，观感即「暖象牙糊一片」；本版底卡明度差按礼记
  原值拉开（底 0xF2F3F5 ↔ 卡 0xFFFFFF）。
- grep 证据：Design＋App 全仓十六进制色值逐个验
  R/G/B 序——表面/结构色全部 B≥G≥R（冷/中性）；
  仅反馈语义色 warning（橙）/danger（红）为暖序，
  那是色相本身、非表面色温，不在去暖范围。

### 18.1 第 1 条·底栏随主题

ContentView 的 .tint 由 Palette.ink 改绑 Palette
.primary（学礼记 ContentView 的 .tint(Palette
.primary)）：选中字形与文字走强调色、随主题切换跟
随，未选保持系统灰。**覆盖 0.2.5「tint 改墨」旧定
版**（用户本轮以礼记双图对比当场改判）。0.3.2 令
牌表已接通此路，本版只改绑定。对账标准＝用户截
图：礼记选中项蓝字形＋蓝字，OneDay 此前灰胶囊＋
黑字形——改后选中着色走系统 tint 通道直达。

### 18.2 第 2 条·顶栏两钮同规格

新建 OneDayCore.HeaderButtonSpec：diameter 40、
glyphPointSize 20（字形/圆比 0.50）。校准出处：
用户提供的 Muse 截图 visual_grounding 量测——其
汉堡钮字形高/圆径 ≈0.48；本规格 0.50 落同一观感
带，单测钉住数值＋比值带 0.45–0.55。ChatView 左
右两钮（sidebar.left／square.and.pencil）同读此
令牌（此前各写 36/15、无令牌、字形显小）。

### 18.3 第 3 条·点输入框锚底

messageList 加两路触发共用 anchorToBottomAfter-
Keyboard：①onChange(of: composerFocused) 聚焦边
沿；②onReceive 键盘 willChangeFrame（聚焦中候选
栏收展等）。守卫＝弹起前 isNearBottom（此刻读到的
是键盘动画前的值）；等 300ms 键盘帧落定后复查再
滚。用户主动上滑不强拉，回到底部钮保留。

### 18.4 第 4/5 条·光标逃逸＋换行不对齐（几何归一）

定因方向（选定）：量测栈与视图排版栈几何此前各
写各的，且 iOS 26 的 UITextView 默认排版栈与量测
用的显式 TextKit-1 栈可能分家——行数对、光标错位。
收编：ComposerTextMetrics 立单一事实源（text-
ContainerInset .zero／lineFragmentPadding 0／
textOriginX 派生），量测容器改引常数；新增
makeTextView() 工厂以显式 TextKit-1 栈（Storage＋
LayoutManager＋Container）构造视图、applyGeometry
统一施加，ComposerTextView 改走工厂＋updateUIView
兜底重申；占位符原点改读 textOriginX/inset.top
（此前手写 constant 1）。新单测 ComposerGeometry-
Tests 5 条：常数与工厂、「规划」光标在第一行且 x
在原点后、三态光标在界内/在文字行带内、长句各行
usedRect.minX 全等 textOriginX、视图 fragment 数
== 量测 lineCount（同源断言）。
**剩余风险（如实）**：单测证明的是工厂配置下几何
同源；真机若再现，下一嫌疑是 IME 组合态（marked
text 期间的临时排版），归真机终审观察项。

### 18.5 第 6 条·发送舱上文下钮

composerRow 的 HStack 换自研 ComposerBarLayout
（Layout 协议、子视图序 [＋键，文本，右端状态
机]）：以窄宽/全宽各 sizeThatFits 一次量高——判
据恒走窄宽（isMultiline(narrow)）、总高走
ComposerLayout.capsuleHeight(narrow:full:)（签
名已改双参；多行＝全宽封顶高＋10＋4＋30＋16）。
摆位：单行与旧 HStack 逐项等价（总高 46 不变、
文本 x=行左+54/宽=行宽−108/底距 13、两键底对
齐）；多行文本全宽在上（x=行左+16、顶距 13）、
按钮行钉底（y=总高−8−30、文本底与钮行顶距 9＝
字段纵距 5＋行距 4，与公式分解对上）。形态经
Layout.Cache＋主队列异步回写 composerMultiline，
只驱动玻璃形状与 swap 动画；onMeasuredHeight 通
道撤销（视图不再反向驱动布局）。结构出处：Muse/
ChatGPT 本体（用户截图）、Exyte Chat 的 Message-
Composer、Stream Chat Composer 均为上文下钮。

### 18.6 设置页五项（学礼记 MeView 行口径）

数值出处：礼记 MeView.entryLabel（图标槽 24、
HStack spacingSM 12、minHeight＝LiqianMetrics
.minTapTarget 44、标题/副标题 VStack spacingXS
4）与 Palette.AppThemeTokens.tencentBlue（底/卡
值见 §18.0）；LiqianMetrics 出自 Palette.swift
（spacing 梯队 4/8/12/16/24/32）。
1. 底卡分离：见 §18.0（底 F2F3F5／卡 FFFFFF，
   礼记原值，不自创）。
2. 行图标分量：TypeScale.rowIcon＝20 semibold 粗
   实字形（槽宽仍 iconSlot 28——对齐线与
   dividerInset 60 的推导不破；礼记槽 24 与其自身
   版式成套，不整表搬）。落点：SettingsView
   .rowIcon 与 Design 的 ContentRow 图标。
3. 字重层级：TypeScale 行角色——rowTitle＝body
   semibold（唯一半粗位）、rowValue＝callout
   regular＋inkSecondary、rowSubtitle＝footnote
   regular＋inkMuted；navRow/infoRow/手写行标题
   （当前服务器/断开连接/重启网关/关于组两行）全
   部改走角色。
4. 行高与组距：OneDayMetrics.rowHeight 52→56
   （礼记行实效约 56 的口径）；SettingsView List
   加 .listSectionSpacing(spacingL 24)。
5. 连带变化（共用组件所在页面）：ContentRow 被
   连接页/总览等页共用——图标变粗实、标题变半
   粗、副标题转 inkMuted、行高 56 随之生效；
   rowHeight 亦被抽屉行与 Files 行引用，同幅变
   化，属预期的全 App 行口径统一。

### 18.7 字重阶梯审计（用户点破：正文粗则加粗无层级）

定版阶梯（OneDayCore.TextRoleWeights 数值账＋单
测钉住）：正文 400／行标题·胶囊标题·分区题·
Markdown 粗体·标题 600／bold 700 仅标题角色上限。
逐一查实（不猜）：
- TypeScale.body ＝ Font.body（regular）——未定
  成 semibold；
- MarkdownText 段落 .font(TypeScale.body)——基重
  regular；**真事故在行内**：AttributedString 的
  markdown 粗体直达系统 bold 700，越过标题的
  semibold 600，层级倒挂——已按 InlinePresent-
  ationIntent.stronglyEmphasized 重映射到
  TypeScale.markdownStrong（body semibold 600，
  与正文恰一档；.code 段不碰、斜体叠 .italic、
  标题内粗体与标题同重）；
- 根 fontWeight 环境（ContentView）：浅色
  .regular——未漏到浅色正文；暗色 .light 是 §14
  条 3 的定版降档，保留；
- StreamingText 词元 .font(TypeScale.body)——
  regular，无漂移；
- 用户气泡 .font(TypeScale.body)——regular。
grep 清点（.fontWeight(／weight: .semibold/.bold
全仓）：ChatView 内收编 2 处（空态标题手写
fontWeight→sectionTitle 角色；Markdown 粗体见
上）；合法登记：顶栏钮/回到底部/xmark/chevron/
checkmark 等图标字形 semibold、胶囊标题（已改
capsuleTitle 角色）、抽屉身份题 20 semibold、抽
屉会话行「当前会话 semibold」状态强调、发送↔
停止键 glyph bold、chevron.down bold 9pt 字形；
其余页面（总览指标题、列表小节题、各页 13pt
semibold 小按钮/标签）均为标题/标签位、非正文
角色，登记合法、本版不动。

### 18.8 验收（已回填）

- 构建 run 42529372497 一轮全绿（前两轮 42528610566
  ／42528906042 分别栽在测试改签漏网与几何断言容
  差，均测试侧问题、已逐一修正并留痕于提交史）；
  单测 76 条全过（65 基线＋几何 5＋顶栏规格 2＋字
  重阶梯 3＋布局宽度双模式 1）；解包实测
  0.3.3／18／site.didichou.oneday；IPA 在
  ~/workspace/your_files/oneday-v0.3.3/OneDay-0.3.3
  .ipa（1,973,934 字节）。
- 真机终审归用户：底栏选中蓝、顶栏两钮观感、点
  输入框锚底、光标三态、换行左齐、多行上文下钮、
  设置页冷灰底白卡与行层级、Markdown 粗体层级。

## §19 0.3.4「去染色＋变/不变表＋设置页 Muse 纪律＋换图标」（build 19）

### 19.1 主题变/不变表（长期规则，用户令入档）

用户原话：「输入框颜色不要跟着主题变。」通则查实
（官方文档出处）：
- TDesign 官方主题体系（tdesign.tencent.com 主题定
  制文档与 tdesign-common 设计令牌表）：--td-brand-
  color 的角色是品牌/主操作与选中态；背景是独立的
  中性令牌族（--td-bg-color-page／--td-bg-color-
  container #fff），输入组件的填充与边框走 bg/
  border 中性令牌、不走 brand。
- Material 3 官方 Color roles（m3.material.io/
  styles/color/roles；tone-based surfaces 博文）：
  surface／surface-container 五档出自 neutral 调色
  板；primary 只给 key components（FAB、filled
  button、选中指示、进度）；text field 容器用
  surface-container-highest（中性最高档）。
- Apple HIG·Color（developer.apple.com/design/
  human-interface-guidelines/color）：tint 只标记
  交互元素（链接、按钮、选中态）；背景用语义系统
  背景/fill（中性灰阶），不以强调色染表面。

**定版表（后续任何新表面先查此表再动手）：**
| 跟主题变（强调色只落交互与选中） | 不跟主题变（表面容器一律中性） |
|---|---|
| 主按钮/发送键填充 | 页面底 pageBG |
| 底栏与列表选中态（tint 通道） | 卡片面 surface |
| 链接 | **输入框填充与边框**（聚焦走双环中性阴影、不染蓝） |
| 开关、勾选标记 | 助手气泡 bubbleFill |
| 光标 caret | **用户气泡**（中性面、与卡面同族） |
| 状态强调点（连接成功点等） | 抽屉/弹层等容器面 |

### 19.2 本版执行（去染色两处）

- 发送舱：Mat.tinted 主题染色撤销（0.3.2 引入），
  回 odGlassSurface(.regular) 中性玻璃；聚焦双环
  阴影本就是中性 shadowBase、不动；caret 按变表
  跟主题——ComposerTextView 新增 caretColor 入参，
  ChatView 传 UIColor(Palette.primary)，主题切换
  时 updateUIView 同步。
- 用户气泡：Palette.primaryTint → Palette.surface
  （与卡面同族的中性面）；助手气泡 bubbleFill 本
  已中性。发送键 primaryFill 属「跟主题变」、保留。

### 19.3 换 App 图标（Brandkit 定版）

主版（蓝底白符号：轨道环＋节点＋地平线，#0052D9）
进 AppIcon.appiconset/icon-1024.png（1024×1024
替换）；裸标志 SVG 存 docs/reference/oneday-mark
.svg。素材源 ~/workspace/logo-skill-test/final-
icons/oneday/（Logo 技能横评定案，见记忆）。

### 19.4 设置页五条（Muse 纪律，推翻 0.3.3 礼记行口径）

用户拍板：OneDay 对标 Muse——礼记靠分量、Muse
靠细线＋正常字重＋留白。礼记对齐只保留结构/令牌/
原生 List 层，行样式以本节为准：
1. 行样式分域：SettingsView 本地行（navRow/
   infoRow/serverRow/断开/重启/关于 Link 行）标
   题改回 TypeScale.body（regular）、rowIcon 改
   细线 .system(size: 17, weight: .regular)；本
   页禁用 rowTitle/rowIcon（grep 本页 0 残留）。
   **其他页面判断**：ContentRow 系列表页（连接/
   总览/文件等）保留 rowTitle 半粗＋rowIcon——
   字重阶梯账（§18.7）里「行标题 semibold」是全
   App 列表的合法半粗位，Muse 纪律的推翻范围是
   用户点名的设置页一域，不外扩；TypeScale 注释
   已记分域。
2. 右侧值砍到单词/单数：技能＝计数（如「39」）、
   记忆＝提供方名、定时＝「X 个启用」、服务端
   会话＝总数；完整摘要（下次运行时间、启用数细
   目等）归各二级页；加载前统一占位「—」。
3. 关于组对齐线：infoRow 与两个 Link 行补
   iconSlot（28）透明占位——全页标题落同一条 x
   线；隐私说明移关于组 Section footer、不再占行。
4. 顶部身份头：List 首组加 identitySection——
   Hermes（headline）＋网关状态点，副行 host ·
   当前模型（footnote inkSecondary）；静态信息行
   不挂导航（详情入口在服务器组，避免双箭头同
   页）；模式借 aheze/Setting 的 profile header、
   只借模式不引库，导航结构与 SettingsRoute 不动。
5. 外观组单行：选「靠身份头改善节奏」不并组——
   理由：并组须把主题行塞进语义不相干的组，违
   0.2.1「参考 Muse 设置」的内容组织定案；身
   份头给页面加了开场节拍后，单行外观组是 iOS
   设置的常见形态（系统设置多有单行组），节奏问
   题已解，不编新功能凑数。

### 19.5 验收（已回填）

- 构建 run 42529732483 一轮全绿；单测 76 条全过
  （与 0.3.3 同数，本版无新增/删改单测面）；解包
  实测 0.3.4／19／site.didichou.oneday；IPA 在
  ~/workspace/your_files/oneday-v0.3.4/OneDay-0.3.4
  .ipa（1,998,607 字节）；图标源文件与定版素材
  md5 一致、Assets.car 已随包打出。
- 真机终审归用户：发送舱中性玻璃、用户气泡中性
  面、caret 蓝、设置页细线行与身份头、新图标。

## §20 0.3.5「图标补全＋回车重影定因＋点空白收键盘」（build 20）

### 20.1 回车重影定因（录屏实证）

录屏路径：单行打「测试」→ 回车插入换行 → 续打组合
输入，发送舱数帧内呈双层——旧单行胶囊盖在多行几何
上、再跳成圆角矩形才落定。定因两条合谋：

1. 形状是离散两态（Capsule ↔ RoundedRectangle 24），
   由 @State composerMultiline 驱动；该状态由
   ComposerBarLayout 在 sizeThatFits 内经主队列异步
   回写。布局本轮已按多行几何落位（Layout 内部
   metrics 同步算形态），形状隔一拍才换：滞后帧里
   Capsule 以新高（≈79）渲染＝半径≈39 的体育场形
   盖住多行内容，状态落定后跳成圆角矩形。
2. composerRow 上的 .animation(value: composerMul-
   tiline) 把这场迟到的形状切换又拉成时长动画，两
   段落定肉眼可辨。

修法（同帧化＋连续化）：

- 圆角半径改胶囊实测高的连续函数 ComposerLayout
  .cornerRadius(forCapsuleHeight:cap:)＝min(高/2,
  cap)：单行高 46→23 与 Capsule 几何等价，多行在
  cap＝composerCorner（24）饱和；实测高经 composer-
  Row 的 onGeometryChange 在布局周期内回写（连续
  量、非离散形态）。形状与高度同源同帧，无可滞后
  之物。
- 删除：@State composerMultiline、ComposerBarLayout
  的 onModeChange/Cache/主队列异步派发、composerRow
  的 .animation(value: composerMultiline)。
- 文本视图身份：ComposerBarLayout 子视图序恒定
  [＋键， 文本， 右端]、无条件分支包裹文本视图——
  UIViewRepresentable 全程同一 UITextView 实例，
  形态切换只改它的 frame；updateUIView 在 marked
  组合期间不回写 text（既有守卫），回车触发的切
  换不丢 marked 段与光标。代码层证据：形态/高度
  是文本的纯函数（无状态、无迟滞）——Composer-
  TextMetricsTests 的 testTypingSequenceModeIs-
  MonotonicAndPure（录屏同路径逐步量测：单调跨形
  态、重复量测逐次相等）与 ComposerLayoutTests
  的 testCornerRadiusIsContinuousAcrossModes（形
  态边界两侧半径差 <1pt）把守。

### 20.2 点空白不收键盘定因

收键盘手势（.onTapGesture）自 0.2.1 起挂消息内容
栈（LazyVStack）——挂点是对的（挂 ScrollView 本体
会吞发送舱点按，0.2.7 实证），但栈帧只裹住已有消
息：会话短时下半屏大片空白、气泡两侧窄于栈宽的区
域都落在栈外，点下去不命中。修法只补命中域：内容
栈帧 maxWidth .infinity、minHeight＝列表可视高
（onScrollGeometryChange 回写的 containerSize.
height）− 上下 contentMargins（64／spacingS），对
齐 .topLeading；手势类型、挂点、与行内既有交互
（链接、代码块复制钮）的仲裁关系一律不动，不误
收。滚动收键盘（scrollDismissesKeyboard .inter-
actively）保留——礼记三件套的「点消息区收」与
「滚动收」两件齐备（第三件附件栏收起钮归键盘附
件栏形态，本 App 发送舱在布局流内、不适用）。

### 20.3 图标补全（与礼记同构）

0.3.4 的 AppIcon.appiconset 只有两条错位条目
（iphone 1024x1024@1x＋ios-marketing），同安装路
径下礼记（19 张全尺寸显式清单）正常、OneDay 不显
示。按礼记结构补全套：自定版素材 oneday-appicon
-1024.png（1024×1024 RGB）以 Lanczos 缩放生成
19 张 Icon-App-*（iphone 20@2x/3x、29@1x/2x/3x、
40@2x/3x、60@2x/3x；ipad 20@1x/2x、29@1x/2x、
40@1x/2x、76@1x/2x、83.5@2x；ios-marketing
1024），Contents.json 与礼记逐字同构，旧 icon-
1024.png 削除。构建后解包验 Assets.car 在位（见
§20.4 回填）。

### 20.4 验收（已回填）

- 构建 run 42531079998 一轮全绿（含 Unit tests 步
  TEST SUCCEEDED）；单测 78 条全过（76＋新增 2：
  半径连续性、输入序列单调/纯函数）。解包实测
  0.3.5／20／site.didichou.oneday；IPA 在
  ~/workspace/your_files/oneday-v0.3.5/OneDay-0.3.5
  .ipa（2,074,559 字节）。
- 图标解包验：Assets.car 116,296 字节在位，内含
  Icon-App 全套 rendition（19 条目／15 个唯一文件
  名，与礼记 appiconset 同构）。
- 真机终审归用户：主屏图标显示、回车跨行无重影、
  点消息区空白收键盘。

## 21. 0.3.6：导航壳（立宪＋改令收敛）

### 21.1 前置：改令与调研版处置

本轮先行过一版「侧边栏调研规格 v2」（提交 bfe8358，
调研笔记 docs/reference/sidebar-research.md）：构建
run 42532017388 失败，两处编译错误——①drawerOverlay
在 @ViewBuilder 内写 if/else 赋值语句（构建器里 if 是
条件内容、装不下赋值），已抽成普通函数
drawerFollowedDrag；②UnevenRoundedRectangle 实参顺
序（声明序为 …bottomTrailing 在 topTrailing 之前），
已按声明序改正。随后用户在旁聊拍板改令：OneDay 整
体风格迁移 Muse 本体设计语言、0.3.6 以下列实测规
格为准——立宪（§22）＋(a) peek 侧边栏与带字名单先
行＋(b) 底栏后置。调研版与新规格不冲突的成果保留
（分组五段下沉 Core、置顶/重命名、List 承载、行单
行化、橡皮筋），被改令覆盖的形态按 §21.5 对账逐条
处置；调研笔记留作支撑材料、不再是施工规格。

### 21.2 立宪落点

- 「Muse 基线令牌表」＋「定义卡模板」＋本页定义
  卡立在 §22（新节），与旧条冲突逐条在 §21.5 标
  注、新表为准。
- 令牌层落点：ThemeTokens.Scheme 新增 chatSurface
  与 selectionFill 两字段（withAccent 派生原样带
  过）；浅色行按基线改值六处（见 AccentTheme 代码
  注）；TypeScale 新增 largeTitle/pageTitle/
  groupLabel 三档；OneDayMetrics 改 drawerWidth-
  Fraction 0.79、drawerCorner 28，新增 drawerInset
  20/navRowHeight 47/navGlyph 21/tabGlyph 22/
  drawerBarButton 52；ShadowSpec 加 x 偏移、
  Elevation 新增 drawer 档。

### 21.3 (a)(b) 逐项对账

(a) peek 侧边栏＋带字全局名单（先行）：
- 盖约 79%：drawerWidthFraction 0.82→0.79（上限
  340 大屏护栏保留，手机幅面不触发）；右侧约 21%
  底层在纱下透出。
- 遮罩白色半透纱：浅色行 scrimBase 改白、alpha
  0.55（Palette.scrim 唯一消费方就是抽屉）；暗色
  行暂留旧值归 0.3.8。
- 右缘约 30pt 柔影：Elevation.drawer（opacity
  0.12/radius 30/x 16）；右侧上下大圆角：
  drawerCorner 24→28（UnevenRoundedRectangle 连
  续圆角）。
- 栏内顶部只有智能体名字：drawerIdentity（名＋状
  态点＋状态词·模型小字）整块撤销，换 drawerAgent-
  Name＝「Hermes」TypeScale.largeTitle（28 bold）；
  drawerStatus 状态拉取随之删除（会话组拉取保留）。
- 分组＝13–14 灰标签＋左右留 20 发丝线：组标签换
  TypeScale.groupLabel（13 regular）＋Palette.ink-
  Secondary（基线 #6E6E73）；组间发丝线 drawer-
  Divider 左右 inset＝drawerInset 20；全部行标题
  x 线对齐 20（名单行外 12＋内 8、会话行外 12＋内
  8、组标签/名字/底条左右 20）。
- 导航行高约 47、只有图标＋标题：drawerNavRow
  minHeight＝navRowHeight 47，字形 navGlyph 21，
  标题 TypeScale.body（17 regular），无箭头无值；
  当前位（聊天）以 selectionFill 浅灰垫标示。
- 名单与底栏四格一一对应：drawerTabs＝TabBar-
  Symbols 四对（同符号源）× MainTab 四格，点按经
  onSelectTab 切格并关抽屉（ChatView 删除旧
  onOpenSettings 注入、改走此通道）。
- 底部浮动条：drawerBottomBar＝左圆钮（设置，
  slider.horizontal.3）＋中间搜索胶囊（高 52 与
  圆钮同高，fieldFill）＋右圆钮（新建会话，
  square.and.pencil），字形 18（17–20 带内）；圆
  钮 glyph 映射为施工选择（规格只定几何），如上
  在案。原顶部搜索胶囊、整行新建行、底部服务器
  行（状态点＋host＋箭头）三件撤销（定义卡删减
  清单）。
- 聊天主面底色随壳改 Palette.chatSurface
  （#FCFCFC）；面板底同令牌。
(b) 底栏（名单落地后动）：
- 悬浮大胶囊：原生 TabView 在 iOS 26 的系统悬浮
  胶囊即落点，不自绘栏体（0.2.3 自绘撤销在案、
  0.2.4 系统优先口径延续）；结构仍 Tab(value:)。
- 去文字标签：tabLabel 改 Image-only 系统条目
  （名称只进无障碍标签），回到 0.2.4 的条目形态。
- 字形 21–22：配置 OneDayMetrics.tabGlyph 22。
- 选中改浅灰小胶囊垫：.tint(Palette.primary)→
  .tint(Palette.ink)——按 0.2.5 本仓实证口径，
  tint 墨时系统选中呈「墨色线条字形＋系统浅灰选
  择胶囊」（#E3E3E5 系，色值由系统按 tint 派生、
  非自绘垫）；选中字形恒线条体、.fill 成对撤销、
  不变色不加粗不上蓝。
- 开合动效：抽屉开合仍走 MotionTokens.dragSpring
  ＋Reduce Motion 瞬时（既有机制未动）；IA 四格
  与数据逻辑零动（深链落点、pendingAgentRoute
  通道原样）。

### 21.4 会话标题人话化（补令并入本轮）

- 反例定因：ServerSession.title 在 display_name
  缺失时拼 "\(source) 会话"，服务端会话多由 API
  创建、display_name 为空，抽屉里整排同名
  「api_server 会话」。
- 落点（OneDayCore.SessionDisplay，单测把守）：
  hasHumanName（display_name 非空且非标识符形
  态）→ 用之；否则 humanTitle＝时间＋条数（今
  天/昨天/M月d日＋HH:mm＋「· N 条」，无时间退
  「服务端会话＋条数」）。首条消息/摘要标题由服
  务端以 display_name 承载，客户端不为标题另抓
  消息列表（拿不到就走时间＋条数，即本回落）。
- 数据先翻译：sourceLabel 把原始 source 标识译
  人话（api_server→「API 接口」、dashboard→
  「控制台」、cron→「定时任务」、未知→「服务
  端」），抽屉标题与副题永不出现原始标识；副题
  组合：人话标题时＝来源·条数·日期，回落标题时
  ＝来源（＋进行中）。原始实体名退到详情：设置
  的服务端会话详情照原样展示 source 等原始字段
  （现状即如此，本轮未动）。
- 本机会话标题本就源于首条消息（20 字截断），
  不在本项范围。

### 21.5 与旧口径冲突清单

推翻（新基线胜出）：
- 0.3.3「底栏 .tint(Palette.primary)、选中必须是
  蓝」→ 本轮撤销，选中浅灰垫＋墨字形。
- 0.3.1「底栏 Label 带字＋选中 fill 成对（照搬礼
  记）」→ 去标签、恒线条体。
- 0.3.3「表面阶梯逐项对齐礼记 tencentBlue 原值」
  → pageBG/inkSecondary/bubbleFill/fieldFill 改
  Muse 基线值（§22 表），礼记原值口径在设置类
  页自 0.3.4 起已先行作废、本轮扩及令牌行。
- §14 层 4「scrim 墨色推导」→ 浅色行改白色半透
  纱（暗色行暂留、归 0.3.8 一并对账）。
- 0.2.1 抽屉形态（82% 整幅盖＋顶部身份块＋底部
  服务器行）→ peek 79%＋只留名字＋名单＋底条。
- 调研版（bfe8358）会话行「选中 semibold＋
  fieldFill」→ 立宪选中口径：selectionFill 垫＋
  标题 regular 不变（§19「主题色不进列表选中」
  的不变侧保留，填充令牌由 fieldFill 换
  selectionFill 专令牌）。
保留（与基线不冲突）：
- §19 变/不变表的「不变」侧（页面底/卡面/输入框/
  双气泡恒中性）与「蓝只许功能位」同向，继续有
  效；primary #0052D9 不动（OneDay 功能蓝）。
- 分组五段＋置顶＋重命名＋List 承载＋橡皮筋（调
  研版成果）、MotionTokens 开合与 Reduce Motion
  降级、截图红线与构建＋单测交付口径。
延后（记录在案、本轮不动）：
- 字重阶梯全局冲突：宪法「只 regular/bold」与
  TypeScale 旧七档（semibold/medium 多处合法位，
  含 SectionLabel 13 medium、rowTitle semibold、
  §14 条 3 暗色降档）冲突——壳内已按宪法（三档
  新令牌＋壳面零 semibold），全局归 0.3.7 页面
  轮统一；ContentView 根 .fontWeight 暗色降档同
  归 0.3.8 对账。
- 新令牌暗色值（chatSurface 0x131316/
  selectionFill 0x2C2C2F）为暂定占位、暗色 scrim
  仍墨纱，0.3.8 暗色收口时整体定版。
- 设置页服务端会话列表的同名问题：本轮只修抽
  屉（侧栏轮）；设置列表归 0.3.7 页面轮（其定义
  卡由主聊汇总过目后施工）。

### 21.6 验收（已回填）

- 单测：85 条（82＋SessionDisplay 三测），run
  42533662765 的 Unit tests 步全绿（日志 distinct
  测试名 85、与源码计数对平）。
- 构建：run 42533662765 一轮全绿（Build＋Unit
  tests＋Package＋Upload）。过程两轮在案：
  42532017388 调研版编译失败（§21.1 两处错误）；
  42532939519 编译过、单测挂 humanTitle 两条断
  言——isDateInToday 锚真实系统时钟忽略注入 now，
  已改 startOfDay 日差判定（修复 e51a819）。
- 解包验：CFBundleShortVersionString 0.3.6／
  CFBundleVersion 21／site.didichou.oneday；
  Assets.car 116,296 字节在位（0.3.5 图标全套延
  续）；IPA 2,119,717 字节，存
  ~/workspace/your_files/oneday-v0.3.6/。
- 真机终审归用户：peek 79%＋白纱观感、名单四行
  与切格、底条搜索/圆钮、底栏去标签＋灰垫选中、
  服务端会话标题不再同名、面板圆角与右缘柔影。

## 22. 立宪：Muse 基线令牌表＋定义卡模板（0.3.6）

用户在旁聊以 6 张 Muse 本体截图实测立项：OneDay
整体风格迁移 Muse 本体设计语言。本节冻结基线；
与此前各节冲突处逐条在 §21.5 标注、新表为准。
后续版本（0.3.7 页面形态轮、0.3.8 暗色收口）按本
表执行，不再另行立规。

### 22.1 Muse 基线令牌表（冻值＋OneDay 落点）

表面：
- 设置类页：灰底 #F3F4F6＋白卡 → Palette.pageBG
  （浅色行改值）＋Palette.surface #FFFFFF。
- 导航/聊天面：近白 #FCFCFC → Palette.chatSurface
  （新令牌）；灰胶囊 #EEEFF1–#F2F2F4 →
  Palette.fieldFill #F2F2F4（带内）等。
- 选中垫：浅灰 #E3E3E5 系 → Palette.selectionFill
  （新令牌；底栏选中由系统按 tint=ink 派生同系
  灰，名单/会话行选中直接用此令牌）。
- 助手泡：冷灰 #E9EAEC、永不染色 →
  Palette.bubbleFill（浅色行改值）。
- 分层：一档明度差、无描边、无阴影（浮动件除
  外：抽屉柔影 Elevation.drawer、浮动控件
  Elevation.floating）。
墨三档：
- 标题近黑／正文黑 → Palette.ink #1F2329；
  次级 #6E6E73 → Palette.inkSecondary（浅色行改
  值）；更弱信息 Palette.inkMuted（仅元信息位）。
功能蓝：
- 只许功能位（发送键/主按钮/链接/开关/caret
  等 §19「变」侧）；OneDay 仍 #0052D9 →
  Palette.primary/primaryFill 不动。框架面、选
  中态、装饰位一律不许蓝。
字阶（全 HIG、字重只 regular/bold 两档）：
- 大标题 28–34 bold → TypeScale.largeTitle（28
  bold 先行）；页标题 17 bold →
  TypeScale.pageTitle；正文与行标题 17 regular
  （行距 22＝系统 body 自然行距）→ TypeScale.body；
  副标题 15 灰 → TypeScale.subhead＋次级色；分
  组标签 13–14 灰 → TypeScale.groupLabel（13
  regular）。
图标：
- 细线约 1.8pt、字形 20–22、全 App 同线宽 →
  SF Symbols 线条体恒定（.fill 禁用），字形尺寸
  走 navGlyph 21/tabGlyph 22/底条圆钮 18 等具名
  令牌；新表面不许另选粗细。

### 22.2 三条宪法

1. 框架无色、内容有色：导航壳、列表骨架、容器
   面恒中性；颜色只属于内容与功能位。
2. 蓝只许功能位：见 22.1 功能蓝；选中永远靠浅
   灰垫，不靠染色。
3. 形态可不同、只许公共组件拼：页面形态可以
   变，积木只能是令牌表与公共组件（Palette/
   TypeScale/OneDayMetrics/Elevation/公共行组
   件），不许页面私拼数值与色值。
附：暖色不进口（2026-11-09 既有红线，立宪重申）。

### 22.3 定义卡模板（每页产品定义卡·硬门）

每页开工前先产出定义卡（写进本设计档对应版本
节），按卡施工、按卡验收。固定六问：
1. 一页一事：这页只完成哪一件事（其余事赶去
   别页）。
2. 第一眼焦点：用户第一眼必须落在哪（唯一）。
3. 删减清单：本轮删掉什么（逐项列名，不许只
   加不减）。
4. 控件跟内容走：每个控件为何在此页此位（跟
   它服务的内容走，不跟惯例走）。
5. 按用户对象分组：分组按用户心里的对象分，
   不按数据来源/实现结构分。
6. 复杂性留幕后：哪些复杂性由系统吞掉、用户
   只看见结果。
验收红线（两条，卡内必须自检）：
- 展示不解释：能预览的页预览真实使用场景；不
  许把设计文档、令牌说明、实现注释放进 UI。
- 数据先翻译：服务端原始命名（实体名、枚举
  值、内部标识）不许上屏；先译成人话再呈现，
  原始名只退到详情/幕后。

### 22.4 侧边栏定义卡（0.3.6，按 22.3 先卡后工）

1. 一页一事：导航壳——切目的地（四格）、找并
   打开会话、新开会话，三件事即全部；管理动作
   （会话详情、服务器管理）不在本页，服务端会
   话行只是去详情的索引。
2. 第一眼焦点：智能体名字＋名单当前位；其余
   （分组、条数、时间）全部退后。
3. 删减清单：状态点＋状态词·模型小字、顶部搜
   索胶囊（下沉底条）、整行新建行（收成圆钮）、
   底部服务器行（状态点＋host＋箭头）、会话行
   元信息行、黑纱遮罩、82% 整幅盖法、服务端会
   话的原始同名标题。
4. 控件跟内容走：搜索只服务这份会话名单→沉
   到名单脚下的底条胶囊；新建是高频动作不是
   一行文字→右圆钮；设置是目的地不是状态→名
   单行＋左圆钮双入口同位。
5. 按用户对象分组：目的地（名单四行）／我的
   会话（置顶＋时间五段）／服务端会话（索引
   组）——按对象分；服务端会话在用户对象里仍
   是「会话」，同列一组、只以来源人话标签区分。
6. 复杂性留幕后：五段分组算法、置顶存储、手
   势仲裁与橡皮筋、服务端标题翻译，界面只呈现
   结果；点空白/scrim 关闭等既有壳行为不变。
红线自检：展示不解释——栏内无任何解释设计或
令牌的文案，空态只给一句去向；数据先翻译——
api_server 等原始命名零上屏（§21.4），原名只
在设置详情里出现。

### 22.5 图标变体令牌（0.3.7 补，用户真机纠正批）

来源：用户 2026-11-09 对 0.3.6 的真机逐像素剖析——
「骨架对了、语言错了」：基线令牌表（§22.1）只冻了
颜色/圆角，没冻字重与图标变体，页面层便各自沿用旧
组件的 semibold＋fill 默认。本节与 §22.6 补冻。

- 框架图标（底栏／抽屉名单／导航行／顶栏与抽屉圆
  钮）一律 outline 变体＋regular 字重：禁 .fill 变
  体、禁 semibold 字重。符号名走线条体本名（TabBar-
  Symbols 恒取 normal 一侧即此令的落点）。
- 实测依据：0.3.6 真机底栏对话图标墨迹密度 55%、
  文件夹 45%（实心砖），Muse 同位 13–21%（细线）。
  框架图标的观感目标就是这个密度带，靠 outline＋
  regular 达成，不逐图标调参。
- 豁免：内容缩略图（文件页 MediaCell 等内容面图
  标）与品牌图标（App 图标、主题色点）不受此限
  （宪法一「内容有色」）；状态符号（状态点是色点
  不是字形）不在此列。
- 字形尺寸带不变（§22.1：20–22，具名令牌 navGlyph
  21/tabGlyph 22/圆钮 18）；顶栏圆钮字形 20 走
  HeaderButtonSpec，字重自本节起改 regular（规格的
  直径/字号比不变）。

### 22.6 字重映射令牌（0.3.7 补，用户真机纠正批）

- 映射表（全 App 唯一口径，账本数值在 OneDayCore
  .TextRoleWeights，0.3.7 改版、单测钉住）：
  - 正文／导航行／会话标题／行标题／分区小标题＝
    regular（400）
  - semibold（600）只许两个位置：页标题与智能体
    名——且这两位自本节起直接落 bold 档实现（见
    下），600 在新代码里不再出现
  - bold（700）只许：大标题（largeTitle/display/
    title）、页标题（pageTitle/capsuleTitle）、
    Markdown 行内粗体（markdownStrong，与正文拉
    开恰一档、不越标题上限）
- 即：§22.1「字重只 regular/bold 两档」自本节起
  为可执行口径——TypeScale 全部角色只许 400/700
  两值，500（medium）退出账本（VisualWeight 的档
  位映射表是换算 machinery、保留，但不再有角色
  请求 500/600）。页面直写 semibold/medium 同罪，
  0.3.7 卡 17 逐处清零验收。
- 与卡 17 的关系：本节即卡 17 的施工/验收口径，
  两处不再分开处理（卡集第〇节原注同此）。

### 22.7 基线补遗（0.3.8 并入，用户 2026-11-09 旁聊拍板）

来源：~/workspace/oneday-design-review/baseline-supplement
-20261109.md（Muse 本体三屏补测＋形态总补）。补遗与
§22.1–22.6 冲突处以补遗为准（它是更晚的实测）；本节
是补遗的入档形态，0.3.8 起执行。

- 增量令 1 身份胶囊全局化（定性补「智能体即界面」）：
  一级页（聊天/总览/文件/状态）顶部统一悬浮身份锚点
  ——头像＋智能体名＋状态一枚胶囊（IdentityAnchor 组件
  全局唯一实现），切换页面时锚点位置与形态不动；页
  大标题退到锚点之下。二级页维持返回头、不挂锚点。
  聊天页的落点与 fixlist 第 30 条合并施工（胶囊只装
  身份三件、模型选择器另立小胶囊、会话名退次行）。
- 增量令 2 一种列表语法统治全应用：左图标列＋标题
  ＋灰副题＋右浅灰元信息，四件冻死在 OneDayCore
  .ListRowSpec（图标列 28／标题 17 regular／副题 13
  灰／元信息 13 等宽／单行高 56／两行会话行 57），组
  件落点＝OneDayDesign 的 ContentRow／UnifiedRow，各
  页只换图标与文案。发丝线与留白分段、几乎不用卡片
  框——卡片只留两类：身份与生成内容。
- 字体补测：内容标题 19–21pt semibold 是合法领地
  （§22.6 注补：账本 TextRoleWeights.contentTitle＝
  600，为 semibold 唯一合法角色；框架位——页标题/
  行/导航——仍只许 400/700 两档）；正文 16–17
  regular、行距约 20。
- 配色补测：链接蓝只许正文链接位；活动流圆盘色
  （Muse 石板灰蓝 #7D839B）、日历角标琥珀金
  #E6B036、内容卡矿物渐变均为「内容有色」侧的取值
  参考——OneDay 不新增框架色，圆盘类需要时走中性
  灰阶，不引石板蓝进框架令牌。
- 哲学两条：①数据先翻译连审计都不例外——日志/
  活动/任务记录上屏按「人话动作＋白话说明＋策略·
  相对时间」三行结构（OneDayCore.LogDisplay 解析），
  原始字段退脚注与详情；②信任做成一等页面——状态
  屏保持一级待遇（总览状态大卡直达、身份头完整）。
- 枢纽页形态参考（状态页）：居中大头像＋编辑徽章
  ＋28 bold 名＋五图标无文字分段胶囊（选中段
  #F0F1F3）；分段无文字的前提是图标语义自明，不
  自明的页不许学此形态。OneDay 状态页 0.3.8 落点：
  头像改白浮纸画法，分段形态不动（其三段有文字、
  语义不全靠图标）。

## §23 0.3.7 施工 NOTES（页面形态轮，逐卡销账）

施工基线：feat/ia-v3 @ bd4d191（0.3.6/21）→ 0.3.7/22。
规格源：~/workspace/oneday-design-review/cards-0.3.7.md
（19 卡；5 条待裁已于 2026-11-09 由用户拍板并写回卡
集，施工按已裁口径）。验收：CI run 42537745734 全绿
（构建＋OneDayCore 单测 96 个 0 失败，0.3.6 为 85，
新增 11＝ServerLabels 7＋IconTokens 2＋字重账本
改版净增 1＋SessionDisplay 改版净增 1）；IPA 解包
验：CFBundleShortVersionString 0.3.7／CFBundle-
Version 22／bundle id site.didichou.oneday／
Assets.car 在包（116,296 字节）；IPA 2,178,936
字节，落 ~/workspace/your_files/oneday-v0.3.7/。
构建两轮修正留痕：①DataBar 默认高误引不存在的
OneDayMetrics.barHeight 令牌（改字面量 6）；②
SessionDisplay 兜底用例数据缺 endedAt（会话按模
型定义属活跃、副题带「进行中」为正确行为，修测
试数据）。真机终审归用户，本节只记构建＋单测证据。

### 令牌层（施工序 1–2）

- §22.5 图标变体令牌、§22.6 字重映射令牌已补入
  §22（实测依据与豁免范围在条文内）。代码落点：
  OneDayCore.FrameworkIcon（weightGrade 400／禁
  fill／尺寸带 20–22，IconTokensTests 钉住，含
  TabBarSymbols 线条体名不带 .fill 的断言）。
- TextRoleWeights 账本改版（单测同步改）：rowTitle
  600→400、sectionTitle 600→400、capsuleTitle
  600→700、markdownStrong 600→700、heading
  600→700；新增断言「全账本只许 400/700」。
  TypeScale 同步：display/title→bold、headline→
  body.bold、label→footnote regular（与 groupLabel
  同档）、rowTitle→body、rowIcon→regular、
  sectionTitle→callout regular、display/title/
  label 的暗色降档入口改走 700/700/400；新增
  metricNumber（28 bold 摘要卡主读数）与
  monoTitle（title3 等宽 bold）。SectionLabel 随
  label 令牌自动 regular；CopyButton 字形
  medium→regular。§14 暗色降档机制本体不动
  （归 0.3.8 对账，卡 17 边界）。

### 逐卡销账（卡 1–19）

- 卡 1 连接页：品牌块改居中（全页唯一视觉重心）；
  底部说明小字整段删。表单卡/唯一主钮/探活条件
  渲染/SecureField 原样。
- 卡 2 总览：状态大卡置顶（状态行＝点＋人话状态
  词、正常字号；大数字＝今日 Token metricNumber；
  进度＝内存占用 %，新拉 systemStats；卡内次级
  指标＝活跃会话/定时两格深链保留）；IA 五段其
  余保留卡下（已裁 3，不砍）。纠正四条：①状态
  字号层级倒置已修（TypeScale.display 大字退出
  本页状态位）；②待处理改人话结论列表——恒渲
  染、无待处理明写「没有待处理」、日志原文整段
  退出本页（只留一条人话摘要行点去日志页）、
  平台异常按 error/failed 才红、其余 warning；
  ③platformRow 与待处理行的平台名/状态词走
  ServerLabels 翻译，host/版本行撤出（归服务器
  详情/状态屏系统段）；④底部留白改 tabBarZone
  76。chevron×4 与状态头箭头降 regular；指标数
  字 24 semibold 改 title 位 bold（随大卡化销账）。
- 卡 3 文件页：聚合机制说明整段删；空态文案现
  状各一句去向（实读合规，未动）；chevron 降
  regular。附则 FilePreviewView 不动（合格）。
  注：卡集原文卡 3 后半段起草时损坏（文件内字面
  truncated 标记），施工时按 FilesView 源码现状
  补记入卡集并已标注。
- 卡 4 状态屏：身份头居中＋头像位（64 圆面＋
  sparkles 字形），host 行撤下；定时段指路文案
  删；活动段会话行改 humanTitle/humanSubtitle；
  percentRow 主色蓝填充改共享 DataBar 中性口
  径；chevron 降 regular；状态句改走
  ServerLabels.gatewayState。
- 卡 5 外观页：假气泡预览组＋主题说明段整组
  删；新预览卡置顶＝真实聊天场景实时渲染（用
  户泡中性面/助手泡 bubbleFill/发送舱 fieldFill
  胶囊＋primaryFill 发送键/主按钮样例，文案为
  真实对话口吻）；主题卡独立成卡，勾字形降
  regular；全页只剩两卡。原「主按钮」假气泡的
  body medium 随整组删自然销账（卡 17 点名项）。
- 卡 6 当前服务器：摘要卡置顶（连接状态行＝点
  ＋连接正常/异常＋地址/账号/密钥行）；二期说
  明整段删；连接测试组保留（结果行随重测状态）。
- 卡 7 档案：摘要卡（当前档案名＋使用中）；页
  内说明段删；导航标题与设置页行标题「档案
  Profile」→「档案」。
- 卡 8 对话模型：当前值升摘要卡主读数
  （monoTitle）；底部说明删；组标题去括号注；
  网关别名说明段删（拦截仍在写入校验层）；候
  选空态改「服务端没有返回可切换的模型。」；
  提供商空态改「暂无提供商条目。」。
- 卡 9 密钥：摘要卡「已设置 X / 共 Y」；按服
  务端类别分组（ServerLabels 类别映射、未知回
  落「其他」、组内已设定在前）；组标题括号注
  删（原单组标题随分组形态消解）；行副题
  description 无中文不显示；chevron 降
  regular。附则 EnvVarDetailView 类别行值改译
  名；编辑器不动。
- 卡 10 用量：周期汇总升摘要卡（总 Token
  metricNumber 主位＋请求/会话/费用卡内次级
  行）；趋势条改中性口径（轨道 fieldFill、填充
  恒墨，与卡 4 DataBar 同口径——卡面原用
  RoundedRectangle 行内条、未换组件本体，只对
  齐着色，如实记）。
- 卡 11 网关：状态组升摘要卡（状态大字
  display＋点，发布日期次级位保留）；「配置版
  本」行删；平台行名/状态词走 ServerLabels；
  stateWord 改走翻译层。
- 卡 12 日志：底部「文件 agent.log · 共 N 行」
  注脚整行删，fileName 状态一并撤。
- 卡 13 记忆：摘要卡（当前提供方名＋内置文件
  总数）；内置行卖点副题删；提供方行英文
  description 不显示；chevron 降 regular。附
  则：MemoryProviderConfigView「切换为当前提
  供方」由组内行改组下 odPrimary 主按钮位。
- 卡 14 技能：摘要卡「已装 N 个 · 启用 M
  个」；按类别分组（译名组头）；行内 category
  mono 原文小字删；英文 description 不显示；
  chevron 降 regular。附则 SkillDetailView 保
  存钮 callout medium→regular，其余不动。
- 卡 15 定时：摘要卡「启用 X 个 · 下次运行
  今天/明天 HH:mm」（无下次只报启用数）；列
  表按状态两组「开着的/停着的」替「全部任
  务」；chevron×2 降 regular。附则
  CronJobDetailView：状态/计划/下次运行三行升
  摘要卡，原信息组余行改「详情」组（空则不渲
  染）；表单不动。
- 卡 16 服务端会话：摘要卡「共 N 条 · 进行中
  M 条」；组名改「全部会话」（计数只在卡）；
  行标题 humanTitle、副题 humanSubtitle（原
  subtitle() 拼 raw source 已删）；批量条
  「删除所选」medium→regular；chevron 降
  regular。附则（已裁 5）：详情页导航标题改
  contentTitle（首条用户消息摘要→display_
  name→未命名会话），元信息组加「原始标题」
  行（仅当与现标题不同时显示）。
- 卡 17 字重对齐：令牌层见上；页面直写点逐处
  清——总览 5、状态屏 1、文件 1、外观 1（＋假
  气泡 medium 随卡 5 删）、服务端会话 2、技能
  2、定时 2、记忆 1、密钥 1、设置主页外链箭头
  2（被动对齐）、聊天 6（顶栏两钮系卡 19、回
  到底部钮 1、横幅关闭 xmark 2、模型选择勾
  1）。全仓验收 grep：App/Design 源码内
  semibold/medium 字重直写归零，余三类豁免——
  ①DesignTokens 的 VisualWeight 500/600 档位
  映射表（换算 machinery，卡集第〇节与 §22.6
  均注明保留）；②注释中的历史叙述；③
  DemoHermesClient 占位缩略图内的文字绘制
  （演示内容图面，非 UI 文字，定性内容面豁免）。
  HeaderButtonSpec 注释同步改（规格只管几何、
  字重归 §22.5）。
- 卡 18 抽屉：五条逐条——①行距：服务端会话行
  由 minHeight 50＋纵向 padding 16（实高约 66）
  改总高 navRowHeight 47，本机会话行 44→47 统
  一；导航名单行原已 47（令牌在位）。②标题收
  紧：SessionDisplay 改版（见下），抽屉行标
  题/副题换新口径，旧 drawerServerSubtitle 删；
  ③空态：本机无会话且无搜索词时不渲染「暂无
  会话」行，改新建入口行（图标＋新建会话）；
  服务端组为空时整组（组头＋指路文案行）不渲
  染；④底左圆钮 glyph 由 TabBarSymbols.
  settings.normal（slider.horizontal.3）改独立
  gearshape，与名单设置行、底栏设置格三者不同
  图；⑤选中垫 #E3E3E5 未动，行文字本已
  regular/body 角色，账本改版后复核一致。
- 卡 19 聊天页：三条逐条——①顶栏两圆钮与身份
  胶囊去描边：圆钮撤 .glass 样式、胶囊撤
  glassEffect，同改无边白面（Palette.surface）
  ＋柔影（shadowBase 0.10/12/4）；回到底部钮
  同家族同改（玻璃圆钮一并收编，卡面未点名、
  同口径处理如实记）；两钮字形 semibold→
  regular（HeaderButtonSpec 几何不变）。②输
  入框撤 odGlassSurface 玻璃，改 Palette.
  fieldFill 中灰填充（composerShape 连续圆角
  函数不变），聚焦双环阴影保留、caret 仍
  primary。③底栏选中垫收窄：**无代码落点**——
  底栏为原生 TabView，垫宽由系统几何决定、代
  码不可控；本轮可动项只有字形侧（Image-only＋
  normal 线条符号＋tint 墨，0.3.6 已在位，字形
  无 weight 即 regular），如实记未改，不假报。

### SessionDisplay 收紧（已裁 5＋卡 18 完成标准）

- humanTitle 改属性式：人话 display_name 优先，
  否则「未命名会话」——0.3.6 的「时间＋条数当标
  题」落点正式作废；humanSubtitle(now:) 承载来
  源标签·时间·条数·进行中全部副信息。
- 新增 contentSummaryTitle（首条用户消息：取首
  个非空行、压平空白、剥行首 Markdown 标记、超
  24 字截断加…）与 contentTitle（摘要→
  display_name→未命名会话）。
- 同源落点：抽屉服务端行、服务端会话页、会话
  详情标题、总览最近会话行、状态屏活动行五处
  全部换新口径，原始 title/source 五处清零（详
  情页元信息组为唯一许可位）。
- ServerLabels（新 Core 文件）：平台名/平台状
  态/网关状态/类别四组翻译＋grouped 分组（组内
  保序、「其他」垫底）＋isChineseText；单测 7
  个把守（已知映射逐项、未知类别回落其他、未
  知状态回落未知、分组排序）。

### 与卡的偏差（如实记）

1. 卡 2 备选形态下「指标三格」只收编两格进大
   卡：今日 Token 已升大数字主位，第三格原位即
   是它，故卡内次级只剩活跃会话/定时两格——与
   「数字进卡不单列」本意一致，非漏做。
2. 卡 10 趋势条只对齐着色口径、未换 DataBar
   组件本体（行内条带数值列布局不同），已在卡
   10 销账行注明。
3. 卡 19 纠正 3（底栏垫收窄）无代码落点，已
   在卡 19 销账行如实记，未假报已改。
4. CronJobDetailView 摘要卡沿用行式三行（状态
   /计划/下次运行）而非大字读数——任务详情的
   「读数」是计划文本、非数字，行式即模板的摘
   要卡形态在本页的落点。

## §24 0.3.8 施工 NOTES（收口轮：33 条纠正＋基线补遗＋暗色/动效/删残）

施工基线：feat/ia-v3 @ ba58e5f（0.3.7/22）→ 0.3.8/23。
规格源：~/workspace/oneday-design-review/fixlist-0.3.8.md
（33 条＋用户四裁）与 baseline-supplement-20261109.md
（补遗，已并入 §22.7）。
验收：CI run 42542458853 全绿（构建＋OneDayCore 单测 112 个 0 失败；0.3.7 为 96，新增 16＝DisplayMapping 8＋RenderMeasure 6＋TabBarLayout 2，TabBarSymbols 改版净 0）。IPA 解包验：CFBundleShortVersionString 0.3.8／CFBundleVersion 23／bundle id site.didichou.oneday／Assets.car 在包（116,296 字节）；IPA 2,237,982 字节，落 ~/workspace/your_files/oneday-v0.3.8/。构建两轮留痕：首轮 run 42541961055 构建绿、单测 2 个断言失败（RenderMeasure 设置列紧致密度上限 0.50 被 network 0.532／server.rack 0.525 击穿）——复核认定紧致盒口径对紧凑字形失真（量的是字形内部填充率、非同列复杂度），断言改格口径＋防实心上限，第二轮全绿，详见 24.2 第 14 条。

### 24.1 量测方法（证据纪律，用户定）

验收不走真机终审，以量测自证为准、用户事后抽查。量
测全在构建产物层完成（无任何截图工作流、无 CI 截图
环——红线）：新增 RenderMeasureTests 进 OneDayCore-
Tests，在模拟器内离线渲染并逐像素取样，方法如下——
- 图标墨迹密度：UIImage(systemName:withConfigura-
  tion pointSize＋weight.regular) 渲染，取 cgImage 的
  alpha 通道，alpha>12 记墨；紧致包围盒＝墨像素最小
  包围盒，密度＝墨像素／盒面积；另附 44pt 方格口径
  密度（墨／44²）作对照。fixlist 的真机实测数（44.6%
  等）是整格像素口径、与紧致盒口径不可直接比数，本
  轮证据以「同口径对照」为准：同符号 outline 与 .fill
  变体的同法复量差、以及各框架位之间的密度带。
- 字形墨高：NSAttributedString 以目标 UIFont 绘制，
  alpha 包围盒高（pt，scale 换算）。
- ＋笔画宽：plus 字形紧致盒上 1/4 行只穿竖笔，取最
  长墨游程／scale。
- 色值：直接断言 ThemeTokens 令牌表 UInt32（出厂值
  即渲染值，Palette 工厂查表生成、无二次加工）。
- 几何：Core 纯函数（TabBarLayout.padWidth／Drawer-
  Geometry.bottomBarCenterFraction）单测钉死，视图层
  只引用令牌、不散写数值。
每项量测在测试里 print 一行 MEASURE…，CI 日志
（gh run view --log）可 grep 复核。

### 24.2 逐条销账（量测值均为 CI 日志 MEASURE 行，同口径复核法见 24.1）

| 条 | 做了什么 | 量测证据 | 偏差 |
|---|---|---|---|
| 1 | 底栏改自绘直渲：TabBarSymbols 清 .fill、FloatingTabBar 以 22pt regular 直渲 | 紧致密度：对话 0.305／趋势 0.350／文件夹 0.387／滑杆 0.392；44 格口径 0.080–0.120。对照同法：.fill 变体 0.723／0.872（格 0.219–0.289）——outline 化同口径降约 55% | fixlist 的 44.6%/49.0% 是真机整格像素口径，与紧致盒口径不可直接比数；以同口径对照（fill→outline）与格口径（≤0.120）作证 |
| 2 | 自绘底栏（用户裁决）：TabView 结构不动、原生栏 toolbarVisibility 隐藏，FloatingTabBar 白浮纸大胶囊 | 选中垫宽由 TabBarLayout.padWidth 构造：字形 26pt→垫 52pt（原生约 98pt＝栏宽 1/4）；单测钉死 | 无 |
| 3 | 抽屉开→底栏隐藏：ContentView 读 AppState.drawerPresented（ChatView.setDrawer 既有写点）＋发送舱 tabBarClearance 联动 | 状态链单测外由构造保证（同一 @Observable 状态驱动两处）；动效走 MotionTokens.swap＋Reduce Motion 出口 | 与 27 同件 |
| 4 | 设置页撤销系统大标题、自绘标题行 TypeScale.settingsTitle（30 bold，账本钉） | 墨高：旧形态 34 black 复量 30.0pt（清单 29.3、同量级）；新 30 bold＝26.3pt（目标约 25.7、断言带 23–28） | 无 |
| 5 | 行盒钉死：全节 listRowInsets 纵向 0＋行内容 minHeight 56（ListRowSpec 同值）；行题 17 regular（既有 body 口径、本轮账本补 navRowText 钉） | 行高构造＝56–57pt（目标约 57）；17 regular 墨高复量 15.7pt（清单两家同值 15.3、同量级） | 83pt 的成因（系统纵向 insets 叠加）以构造消除，未做 UI 渲染复量（量测层为字体/几何口径） |
| 6 | ModelDisplayNames 全局映射（Core）：聊天三项＋服务端别名，身份位兜底「服务端默认」；设置身份卡副题/对话模型值/状态页状态行三处改走映射，原始 id 只留对话模型详情 | 单测 8 断言钉映射表（含 Qwen 全名 id、deepseek-chat 别名、hermes-agent→nil） | 无 |
| 7 | 档案值 ServerLabels.profileName（default→「默认档案」）；记忆值：内置改报「N 个文件」（builtinFiles 计数）、外部接管报提供方名 | 单测钉 profileName 三态；记忆值口径在 loadSummaries 代码内 | 无 |
| 8 | 断开连接拆出服务器组、独立 Section | 结构改动（代码审查面）；红字红图标只在独立组内 | 无 |
| 9 | success 降饱和 #1E8E4F→#3F9163（暗 #45B878→#55A87B）；服务器行与网关行撤状态点，全页只留身份卡一处 | 令牌值单测断言（testTokenHexValues） | 无 |
| 10 | 设置页 List 补 contentMargins 底部 tabBarZone（76）；状态页底部留白同轮改 tabBarZone | 构造口径与总览同值（OneDayMetrics.tabBarZone） | 其余二级页（详情表单类）底部留白未逐页复量，归事后抽查 |
| 11 | 身份卡副题撤 host（只留模型显示名），URL 只留服务器行副题一处 | 代码面（第 6 条同改点） | 无 |
| 12 | 服务器行撤 StatusDot，右侧只剩系统箭头；navRow 的 dot 参数整删 | 代码面 | 无 |
| 13 | navigationTitle 撤销（空题＋inline），标题行贴 List 首行 | 构造：标题上方只剩 List 首节系统顶距（原约 130pt 的大标题区消失） | 未做 UI 渲染复量（同 5） |
| 14 | 设置列图标全走 rowIcon 的 17 regular 同档；量测复核同列一致性 | 14 枚密度：紧致 0.272–0.532、格口径 0.037–0.083、离散比 1.95（断言 ≤2.5／格 ≤0.10／紧致 ≤0.55）；**brain 0.366 居中（14 枚第 8 位）、非离群，清单的目测怀疑被量测推翻，未换形**；紧致最高是 network 0.532／server.rack 0.525（紧凑字形的内部填充率、格口径正常） | 未换任何图标（量测不支持换形）；断言口径首轮过严已按实测修正（见节首留痕） |
| 15 | 抽屉名单字形 21 无字重→18 regular（FrameworkIcon.drawerGlyphSize 令牌） | 18pt 紧致密度：0.310／0.363／0.399／0.396，离散比 1.29（0.3.7 目测口径 27.6 vs 19.6＝1.41）；格口径 0.055–0.082 | 紧致口径绝对值高于清单的 13–21%（其为整格口径）；统一性以离散比与同令牌构造作证 |
| 16 | 名单文字钉 17 regular（TypeScale.body＋账本 navRowText）、行距 minHeight 47（既有令牌、本轮销账确认） | 墨高同第 5 条（17 regular 15.7pt）；行高构造 47 | 无 |
| 17 | **关闭不施工（用户裁决：保留灰块）**：导航行/会话行选中整行 #E3E3E5 填充维持（selectionFill 令牌值单测断言 0xE3E3E5） | — | 推翻清单原案，依裁决 |
| 18 | 分组名「服务端会话」→「其他会话」；副题改序「时间·条数·进行中·来源」（来源退尾）；状态只在 isActive 真活跃时写；标题同源 SessionDisplay（详情页 contentTitle 内容摘要既有） | SessionDisplayTests 改序断言钉死（含已结束不挂「进行中」回归） | 抽屉列表载荷无消息正文，抽屉行标题走 humanTitle（contentTitle 的同源回落）；内容摘要只在已拉消息的详情页生效 |
| 19 | 全名单两行制：本地行补副题（LocalThreadSubtitle「时间·条数」）、服务端行同型，行高同 57（sessionRowHeight/ListRowSpec 钉） | LocalThreadSubtitle 单测钉格式 | 无 |
| 20 | 导航区补「选项卡」组标签（与会话组标签同形态） | 代码面 | 无 |
| 21 | 会话组间与服务端组前发丝线全撤（只留白＋组标题边距）；发丝线只留导航↔会话功能区界一处 | 代码面 | 无 |
| 22 | 删 tabBarZone 占位行（76）＋底条下边距改 DrawerGeometry 口径（面板内 4pt）＋面板/纱底色穿安全区 | 条中心比例纯函数单测：852 屏/安全区 34 → 0.925（Muse 实测 92.5%；旧 77.5%） | 无 |
| 23 | 底条横边距 20→12、件间距 12→8 | 搜索胶囊宽构造算术：393 屏 ≈166pt、402 屏 ≈174pt（清单旧约 150、Muse 约 173） | 无 |
| 24 | 齿轮 18 无字重→17 regular（drawerBarGlyphSize，与 15 同令牌族） | gearshape 17pt 紧致密度 0.396，与名单同带 | 无 |
| 25 | 底条圆钮＋搜索胶囊：fieldFill 灰填充→odFloatPaper（白浮纸） | 令牌值同 28（floatFill #FBFBFB 单测断言） | 无 |
| 26 | 用户气泡 surface 纯白→userBubbleFill 中性浅灰（新令牌） | 色值断言：浅 #F0F0F2／暗 #212126；底 #FCFCFC、助手泡 #E9EAEC 三者同家族拉开（明度序 F0F0F2＞E9EAEC） | 无 |
| 27 | 同 3 | 同 3 | 同件 |
| 28 | 新立白浮纸令牌 floatFill＋odFloatPaper 画法（近白＋发丝边 0.5＋paper 柔影），落点：输入框/身份胶囊/顶栏圆钮/回到底部钮/抽屉底条/自绘底栏/状态页头像 | 色值断言浅 #FBFBFB／暗 #1C1C1F；Elevation.paper 0.10/12/4 | 输入框聚焦仍走 §14 条 2 双环影（聚焦禁的是焦点描边；发丝边为浮件定位边，两口径不冲突） |
| 29 | 气泡正文显式角色 bubbleBody（17 regular）：用户 Text／MarkdownText 段落／StreamingText 三处同改 | 墨高：17 regular 15.7pt vs 19 semibold 对照 17.3pt（清单实测约 19 semibold 形态已退） | 无 |
| 30 | 按已批布局：IdentityAnchor（头像＋Hermes＋状态）＋右侧模型小胶囊＋会话名次行；顶栏让位 64→88、渐隐带 128→150 | 组件构造（状态词三态属实口径：未连接/唤醒中/生成中/在线） | 胶囊宽于 Muse 约 90pt 参考——已批布局含状态词，属方案内取舍 |
| 31 | 左钮 sidebar.left→line.3.horizontal（汉堡线），白浮纸圆钮 | 代码面 | 无 |
| 32 | ＋/麦克风 16→15 regular（composerGlyphSize 令牌） | plus 笔画复量 1.67pt（目标约 1.8）；注：16pt 同法亦 1.67（SF 笔画不随点数线性缩放，清单 2.5pt 为真机像素口径） | 无 |
| 33 | 备忘不施工：助手泡 #E9EAEC 未动（令牌值单测断言钉死防后版漂移） | bubbleFill 浅色断言 0xE9EAEC | — |

补遗落地（§22.7 对照）：身份锚点落聊天（第 30 条）／总览／文件三页＋状态页枢纽头改白浮纸（其身份头即锚点的大形态）；统一行：ListRowSpec 冻结＋UnifiedRow 组件新立，会话页行与记忆页两行已收编，定时/技能行因含 Toggle/三行运行信息属内容变体、规格同源（字号/列宽/行高同表）未并组件（如实记）；字体补测：contentTitle 600 入账本并注合法领地；审计三行：LogDisplay 解析＋日志页/状态页近期事件两处落点；配色补测：未引任何新框架色（圆盘位无落点需求、未动）；枢纽页分段：状态页分段含文字、语义不全靠图标，按补遗前提不学无文字形态、未动。

### 24.3 暗色审计（C 项）

- 令牌定值：0.3.6 遗留的暗色暂定值逐个转正（数值与
  依据在 AccentTheme.tencentBlue 文件头注）：四层微
  差（pageBG 0B0B0D／surface 121214／bubbleFill
  17181B／fieldFill 1B1C1F）＋chatSurface 131316＋
  selectionFill 2C2C2F 成立（§14 条 1 的 1–3% 微差）；
  暗色 scrim 定为墨纱 050506/0.50（抽屉压暗用，与
  浅色白纱分工不同）；新增 floatFill 暗 1C1C1F、
  userBubbleFill 暗 212126；success 暗随浅色同轮降
  饱和 45B878→55A87B。
- 字重降档（§14 条 3）：根环境 fontWeight 暗色降档
  通道沿用；TypeScale 的 (for:) 变体本轮补齐——
  headline/capsuleTitle/metricNumber/monoTitle 四个
  带权角色此前无降档变体、暗色漏降，本轮补上并切
  换关键调用点（IdentityAnchor 胶囊题走 capsule-
  Title(for:)）。
- §14 十条暗色相关逐项：条 1 禁黑框/#000——令牌表
  无 000000（inkBlack 主题 primaryFill 为 111114 近
  黑墨色，0.3.0 已改）；条 2 聚焦双环影——影基色
  shadowBase 0A0A0C 近黑非纯黑、双外观同值；条 3
  见上；条 4 流式 blur——与外观无关、MotionTokens
  同值；条 5 图标光学偏移——几何值同值；条 6 等宽
  数字——同值；条 7 折叠动画——同值；条 8 断行
  pretty——同值；条 9 弹簧两支——同值；条 10 复制
  对勾——同值。结论：暗色差异只应出现在令牌色与字
  重降档两处，本轮已收口，其余八条双外观同值即正
  确形态。

### 24.4 动效收口＋删残（D 项）

- 动效：全仓 grep 复核——.animation/withAnimation
  的曲线参数除 MotionTokens 定义处外，全部经
  MotionTokens.resolved 出口（symbolEffect 的系统
  过渡与 TimelineView 指示除外，属既有豁免口径）。
- 删残（grep 证据，删除前全仓引用计数为 0）：①
  Mat 三档＋odGlassButton/odGlassSurface（玻璃期令
  牌，发送舱去玻璃后零调用）；②ChatView 的 tabBar-
  Zone 本地副本（唯一用途抽屉占位已废）；③TabBar-
  Symbols 的 .fill 名对（chat/files，§22.5 清账）；
  ④SettingsView navRow 的 dot 参数（撤点后零调用）。


## §25 0.4.0 一期销账（原生化审计 §8 一期清单，2026-11-09）

版本 0.4.0／build 24，分支 feat/ia-v3。施工纪律：单写入者、每件
一批、CI 绿＋单测全绿才进下一批；无任何截图工作流新增/复活；
未动 Hermes 服务端、未发任何生产写请求。审计依据：
~/workspace/oneday-design-review/native-audit-0.4.0.md。

### 25.1 第 4 条·续聊打通（审计 §3.4）——批次 1，commit f030758，CI 42545910492，单测 115

- [x] ChatThread 加 serverSessionID（SwiftData 轻量迁移，可选字段默认 nil）
- [x] 四处入口统一改道聊天页：抽屉会话行（既有口径）／服务端会话页
  行／状态页最近会话＋总览服务端会话行／CronJob 运行记录行——点按置
  AppState.pendingChatSessionID，ContentView 切聊天格，ChatView 消费
- [x] 导入链：GET /api/sessions/{id}＋/messages → SessionHistoryImport
  过滤（只取 user/assistant 有正文者、保原序；新增 3 用例）→ 新线程
  （title=ServerSession.contentTitle、时间戳取服务端）；已关联线程按
  serverSessionID 直接切换、防重复导入
- [x] ServerSessionDetailView 降级为「会话信息」：聊天页会话名次行
  （仅已关联线程）→ sheet；元信息 LabeledContent＋消息平面记录；工具
  消息改摘要行＋DisclosureGroup（raw JSON 只在展开区 mono 小字，不
  裸奔）；删详情页消息渲染拷贝与 Palette.primaryTint 旧染色，用户泡
  旧染色 #E7F6F1 在现行渲染中不存在（已随气泡中性化退场）
- [ ] **R1 未验证（如实记）**：「续聊是否回写同一服务端会话」未验
  证——红线禁对生产 Hermes 发写请求；代码层维持现有无状态上下文
  重放发送链（本机线程后 20 条组 messages 发 /v1/chat/completions、
  不带服务端会话 id）。等用户点头后另行受控实测

### 25.2 底栏回原生（审计 §3.2）——批次 2，commit 8aadc85，CI 42546098013，单测 112

- [x] 删四处 .toolbarVisibility(.hidden, for: .tabBar)（grep 代码残留 0）
- [x] 删 FloatingTabBar 覆盖层与组件本体、TabBarLayout.swift；删自绘
  断言测试（TabBarLayoutTests 2＋底栏墨迹量测 1）；TabBarSymbols 保
  留作原生 Tab 的 Label 符号源
- [x] 抽屉底条让位走系统安全区：drawerBottomBar 改传实际 bottomInset
  （含原生底栏安全区高），接受原生玻璃坞系统层级、不为抽屉态隐藏底
  栏（报告推荐案，代码注释写明口径）
- [x] 删 ChatView tabBarClearance 手算；tabBarZone 四处引用逐处删除
  （OverviewView/StatusView/SettingsView/LogsView）＋令牌本体退役

### 25.3 删自定义背景与令牌降级·删背景部分（审计 §1.1/§1.3/§6.1 前置）——批次 3，commit c121d3c，CI 42546701428，单测 112

- [x] 删 ChatView topFade 渐隐带及顶栏 overlay 的 ZStack 背景层（只
  剩 headerBar 本体）；滚动边缘模糊回归 .scrollEdgeEffectStyle(.soft)
  单独承担（§6.1 正式修法的前置步）
- [x] 删根层 pageCrossfade 注入（OneDayApp RootView）与 ContentView
  暗色字重降档 hack；.tint(Palette.ink) 删除、tint 回系统默认
- [x] Palette 整表降级为系统语义色命名引用（pageBG=systemGrouped-
  Background 等）；气泡两色按 §1.1 改挂系统灰阶（助手泡 systemGray5、
  用户泡 systemGray6，新单测 testBubbleColorsUseSystemGrays 钉死）
- [x] AccentTheme/ThemeTokens 整套删除（AccentTheme.swift 删文件）；
  AppearanceView 最小改型：Form＋外观三档系统 Picker（跟随系统/浅
  色/深色，AppStorage appearanceMode＋根层 preferredColorScheme），
  设置行「主题」→「外观」；整页规格对齐归二期
- [x] Elevation 整表废止：4 处调用清零（odFloatPaper/状态页头像/附件
  牌去影），仅抽屉右缘保留一处内联系统近似档阴影（例外 E5）
- [x] 删 iconOpticalOffset（定义＋8 处调用，grep 代码残留 0）
- [ ] 存量保留（如实记）：MotionTokens 令牌本体与个别 resolved 调用
  （如 scrollToBottom）本期未动——一期第 3 件口径只含删背景部分，
  动效令牌收口归二期；顶栏胶囊/圆钮 glassEffect 换装归二期材质批
  （§6），本期只删背景、形态未动
- 备注：本批首轮 CI（42546510567）红——Palette 重写时 OneDayMetrics
  后半段成员被截断，已按 git 实值全量恢复后 amend 重跑绿；度量值以
  仓库实值为准（spacingL 24/XL 32/XXL 48 等），教训入账

### 25.4 字体与键值行（审计 §3.1）——批次 4，commit 69e41fd，CI 42546957193，单测 105（用例级对账：112−7）

- [x] TypeScale 整表废止：245 处引用按语义映射直用 Font.TextStyle
  （body/callout/footnote/caption/headline/title2/title/largeTitle/
  subheadline；mono 走 Font.system(语义档, design: .monospaced)；
  rowIcon 走 OneDayMetrics.rowIconGlyph 图标度量）；(for:) 暗色降档
  变体与 Font.Weight.od、TextRoleWeights、VisualWeight 账本一并退役
- [x] 验收 grep：框架层 TypeScale 代码残留 0；.weight( 覆写仅剩
  MarkdownText strongFont 1 处（内容层例外，审计注明）；Font.system
  (size:) 残留 46 处经逐点分类全为 SF Symbol 图标字形尺寸（框架图
  标字形口径，非文字写死），如实记边界
- [x] 摘要计数句降档：SkillsViews/CronViews/EnvVarsView 三处
  title(for:) 22 bold → .callout；GatewayView 状态词 display 28
  bold → .body 行
- [x] infoRow 八处实现全删、29 处调用统一 LabeledContent（mono 值走
  等宽 .callout；grep 代码残留 0）
- [x] 设置页自绘大标题 pageTitleSection 删除，回系统 navigationTitle
  （"设置"，整页 sheet 化归二期 R4）
- 测试增减对账：删除 7 个用例（TextRoleWeightsTests 4＋字重降档 1＋
  testTextRoleAdditions 1＋testTitleInkHeights 1），均为已废止令牌/
  账本的钉死用例；B3/B4 两轮 CI 日志用例名单 diff 验证不多不少

### 25.5 A 案胶囊合并（审计 §3.3）——批次 5，commit d69a7d7，CI 42547425816，单测 105

- [x] 聊天页右侧小模型胶囊撤除；IdentityAnchor 加可选 modelName 段
  （分隔线＋模型名＋chevron），一颗装身份＋状态＋模型；总览/文件页
  不传参、原样不受影响
- [x] ModelPickerSheet 退役；点整颗胶囊暂以 sheet 打开
  ModelSettingsView 现成路径（代码注释标明三期改开枢纽页）
- [x] 其余露头处置：#2 设置身份头模型副行撤；#4 状态页 statusLine
  撤模型后缀；#3 设置「对话模型」行改名「服务端默认模型」（行撤值
  归二期、本期只改名）；#5 ModelSettingsView 页名/组名同改＋页内语
  义明示一行；#6 会话详情模型行（批次 1 已落只读＋显示名映射）；
  #7 定时详情模型行改只读＋ModelDisplayNames 显示名映射

### 25.6 未尽项（归二/三期，不在本期口径内）

- R1 续聊回写验证（待用户点头受控实测，见 25.1）
- 二期：26 页逐页 List/Form 迁移、设置页 sheet 化与行撤值（R4 已
  裁）、顶栏收编系统通道＋glassEffect 材质批（§6）、AppearanceView
  整页规格、MotionTokens 收口、LabeledContent 行在卡片内的最终对齐
- 三期：智能体枢纽页本体（点胶囊打开；审核段数据源＝Hermes write-
  approval 启用＋HTTP 桥、浏览器段待后端接口，均已单列）

### 25.7 终批销账修正（解包验版抓到的假绿，2026-11-09）

- 终批首包（commit cdfcfb6，CI 42547777227 success，单测 105）解包
  验 Info.plist 时发现 CFBundleShortVersionString/CFBundleVersion
  仍为 0.3.8/23：终批只改了工程设置 MARKETING_VERSION/
  CURRENT_PROJECT_VERSION，而本工程版本字面量直写于 Project.swift
  的 infoPlist extendingDefault（注释早已写明「模板不展开工程设置、
  只写字面量才进包」，沿礼记 v4.4 实证口径）——该处漏改，CI 绿但
  产物版本号未变，属假绿，不予交付。
- 修复：Project.swift infoPlist 两字面量改 0.4.0/24（与工程设置对
  齐），独立 fix 提交重跑 CI；交付以重跑包解包验版＝0.4.0/24 为准
  （run 号与 IPA 字节数见交付回执）。教训并入：发版须同时改两处版
  本源，验收必解包验 plist、不认 CI 绿。

## §26 0.4.1 聊天页批次销账（消息长按四件，2026-11-09）

版本 0.4.1／build 25，分支 feat/ia-v3。用户 09:34 点名（样板＝
Muse 本体长按菜单截图：回复/复制/选择/分享），排期为一期后
聊天页批次、唯一写入者。范围只此一批：不碰二期逐页迁移；未动
Hermes 服务端、未发任何生产写请求；无截图工作流新增/复活。
发版三处版本源同改（Project.swift 工程设置＋infoPlist 字面量
＋设置页关于行硬编码字串），交付前解包验 Info.plist（§25.7
教训）。CI run 与单测数见本节末回填行。

### 26.1 入口与总口径

- [x] 每条已完成消息（用户/助手两侧）挂系统 `.contextMenu`
  长按菜单（MessageMenuModifier），四项全系统件、零自绘菜单；
  流式生成中的消息不是 ChatEntry、不经 bubble()，天然无菜单
- [x] 纯图片消息（正文空）不挂菜单：四项全是文本动作，空文本
  挂上只剩坏体验（引用摘要为空、复制/分享空串）
- [x] 菜单符号名收敛 OneDayCore `MessageActionSymbols` 一处，
  单测以 UIImage(systemName:) 逐个钉死存在性（写错名 CI 红）

### 26.2 回复（引用发送）

- [x] 点「回复」→ 发送舱上方引用条（SmoothExpand 平滑高度，
  与附件条同机制）：左细线＋「正在回复 Hermes／我的消息」
  ＋摘要一行截断＋✕ 取消；点完顺手聚焦发送舱
- [x] 引用是值快照（OneDayCore `MessageQuote`：role＋content），
  不持 SwiftData 对象；发送即消费清除、✕ 清除、切换线程经
  onChange 清除，不跨线程残留
- [x] 落盘：ChatEntry 新增 quoteRole/quoteContent 两可选字段
  （SwiftData 轻量迁移，与 serverSessionID 同先例）；正文存
  原文、只存两字段，摘要/拼装读时生成
- [x] 注入：现有无状态重放发送链不加 API 字段——组装上下文
  时经 `MessageQuote.outgoingContent` 把引用块
  （[引用 X 的消息]＋正文）拼进对应 user 消息 content；本轮
  新消息与历史回放同一函数，引用在后续轮次持续在场；带图
  发送的多模态 text 同走拼装，不丢引用
- [x] 注入防爆：引用正文超 1000 字符截断并明示「…（以下
  省略）」（纯函数＋单测），不静默截断、不撑爆每轮重放
- [x] 已发送消息顶部渲染引用块（quoteBlock）：小字、次级色、
  左细线＋称呼＋摘要（与引用条共用 summary 口径），只作回
  指不抢正文层级

### 26.3 复制

- [x] 整条消息纯文本进系统剪贴板；口径收敛：新增 OneDayDesign
  `Pasteboard.copy` 为全仓唯一剪贴板写入口，CopyButton 改走
  它，菜单「复制」共用——不许两套
- [x] 文本口径：用户消息原文；助手消息经 OneDayCore
  `MessagePlainText` 剥 Markdown 标记（围栏删界留代码原文、
  标题/引用前缀剥离、链接留文本＋URL、粗斜体/行内代码剥
  标记、分隔线删行；成对标记才剥、落单符号不误伤），纯
  函数＋单测把守

### 26.4 选择（选型定案）

- [x] **选纯文本 sheet 路线，不在气泡上直接划选。** 理由：
  ①气泡命中域上已有 contextMenu 长按——同处再叠
  .textSelection 的长按划选，手势仲裁由系统决定、两边都
  可能被对方吞（菜单唤不出或选区起不来），不可控；
  ②助手消息是 Markdown 复合排版（多 Text 块＋代码块），
  逐块选择跨不了块、选不完整条；③sheet 内整条纯文本以
  .textSelection(.enabled) 呈现，选择手柄与长按拷贝菜单
  全是系统行为、可跨段任意划选，确定性最高（本批无真机
  截图验收环，手感类风险按确定性优先原则裁）
- [x] sheet 形态：NavigationStack＋ScrollView 纯文本＋系统
  标题「选择文本」＋toolbar「完成」关闭，全系统件
- [x] 既有例外注记：助手消息的代码块内原本就有行内
  .textSelection 与 CopyButton（0.3.0 起），本批不动——
  代码块上长按走行内选择、气泡其余区域长按走菜单，两
  个命中域不重叠

### 26.5 分享

- [x] ShareLink 分享整条消息文本（与复制同一纯文本口径），
  系统分享单呈现，菜单内以 Label＋square.and.arrow.up 呈现

### 26.6 证据与回填（长按四件波次）

- 新增单测（MessageActionsTests）：引用称呼/摘要折叠/截断、
  注入拼装（无引用原样/有引用拼块/空正文只块/超长截断）、
  纯文本口径（标题粗斜体/围栏代码原文/链接图片/引用分隔
  线/落单符号不误伤）、菜单符号存在性
- 回填：commit f603a6d、CI run 42548996515（success）、
  单测 118（0.4.0 基线 105＋本批新增 13，日志聚合行实查）

### 26.7 追加波次：0.4.0 真机反馈八修（用户 10:06/10:07/10:09 三轮点名）

与长按四件同批交付（版本同为 0.4.1/25）。逐条销账：

- [x] **第 1 修【P0】键盘不弹**（commit 925244d，根因写
  在 commit 与发送舱注释）：diff 实证——0.3.8（键盘正
  常）→0.4.0 间焦点机器逐字未动（ComposerTextView.swift
  零 diff；ChatView 内 focusHandle 接线、点空白收键盘手
  势挂点、safeAreaInset 承载均未变；全 diff 无一行
  firstResponder/键盘代码改动）。唯一变量是环境层：批
  次 2 原生底栏由隐藏变可见＋自绘悬浮栏覆盖层撤销、批
  次 3 根层修饰删除与 topFade 删除（topFade 自身
  allowsHitTesting(false)，排除）。回归与底栏可见化同
  批出现：玻璃坞接管底部区域后，UIViewRepresentable
  文本视图的触摸/焦点环境改变、其自身触摸成单点故障。
  修法＝构造性双通道：整卡背景命中域加 onTapGesture 经
  既有 ComposerFocusHandle 聚焦（点卡面空隙必达），文
  本视图直触保留；点空白收键盘不变。恢复 0.2.8/0.3.8
  已验契约「点输入框必弹、点空白收」。**真机复验归用
  户终审**（本批验收口径＝构建＋单测＋用户真机，无截
  图环可代验键盘行为）
- [x] **第 2 修 抽屉单栏滚动**（commit 90c9b79）：drawer-
  Panel 整栏改一个 ScrollView——名字/名单/会话组/底条
  同属一个 VStack 一栏到底；List 退役（行本为自控素
  行、无 swipeActions，listRow 三件套剥离）；内容不
  足一屏时 VStack 以 minHeight＝面板高撑满＋Spacer
  把底条推到栏底（结构上仍是同一滚动栏、非独立钉底
  分区），超一屏整栏连底条一起滚
- [x] **第 3 修 输入栏与底栏同材质**（commit 925244d）：
  撤白浮纸（floatFill＋发丝边＋双环手搓影），发送舱
  回 .glassEffect(.regular)——与原生底栏同为 iOS 26
  Liquid Glass 家族，同材质即同观感，不再自调灰阶对色
- [x] **第 4 修 底栏向 Muse 靠（全原生件）**（commit
  95ab47e）：①Label 字形 .symbolVariant(.none) 锁
  outline（符号表 selected≡normal 之外第二道锁，堵系
  统选中态自动换 .fill）；②根 .tint 系统蓝改 .primary
  单色——连带 Palette.primary* 全仓 7 处框架强调位
  （发送键/光标/主按钮等）单色化，与「框架无色」基线
  同向、在案可否决；③.tabBarMinimizeBehavior
  (.onScrollDown) 滚动收起（样板底坞收成一颗胶囊的原
  生行为）；标签展开态保留属原生形态、不处理
- [x] **第 5 修 身份胶囊挤压**（commit e726891）：根因＝
  旧胶囊内名字无 lineLimit、被顶栏 HStack 压缩时换行
  断字，模型名 lineLimit(1) 截断词中间。改 ViewThat-
  Fits 三档降级（全量→收状态词只留点→模型短名），名
  字任何档位 lineLimit(1)＋fixedSize＋layoutPriority
  最高、永不断行；模型短名走 ChatModels 写死映射
  （Flash/V4 Pro/Qwen3，整词缩短、清单外回全名不截
  断）＋单测；顶栏胶囊钮 layoutPriority(1)；胶囊宽随
  内容自适应（hug）
- [x] **第 6 修 气泡回中性灰**（commit e726891，口径
  10:25 收紧、f9cd0c4 落注释）：**字面值封存——助手
  泡 #E9EAEC、用户泡 #F0F0F2，不许再用 systemGray
  或任何「等价系统灰阶」替代。** 根因：一期把气泡
  改挂 systemGray5/6，系统灰自带蓝紫色调（#E5E5EA／
  #F2F2F7），与封存量测值漂移，真机判「发紫灰、深
  浅难分」。依据：#E9EAEC 是 §22 基线自 Muse 本体
  截图逐像素量得的中性灰（0.3.x 冻值同此），量测值
  优先于系统近似色。Palette 以字面常量直给（动态色
  写法同 scrim），暗色纯中性派生 #2E2E2E／#242424
  同禁系统灰；单测钉解析值＋近中性断言（浅暗两环
  境 |R−B|≤4/255：封存值自身 B−R＝3/255 为量测原
  貌、系统灰＝5/255 过不了，阈值取 4 分辨——首版
  误设 2/255 被 CI run 42550395904 抓红、已修正，
  数字以实测为准不许拍脑袋）＋深浅档差（Render-
  MeasureTests），改挂系统灰会直接红。正文字重部
  分由第 9 修细化（见 §26.9）
- [x] **第 7 修 输入栏形态对齐样板**（commit 925244d，
  与第 3 修同落点）：白色玻璃大圆角卡片（圆角连续函
  数封顶 24）、＋在卡内左下、发送圆形键在卡内右下、
  多行上文下钮——均沿既有 ComposerBarLayout 结构，本
  修只换表面材质口径；自量高＋硬封顶（例外 E1）不动
- [x] **第 8 修 抽屉开时底栏露面**（commit 90c9b79）：
  ChatView body 绑定 .toolbarVisibility(drawerOpen ?
  .hidden : .visible, for: .tabBar)——开即隐藏、关恢
  复；0.4.0 的「不为抽屉态隐藏底栏」推荐案就此作废
  （覆盖层出现时 tab bar 不露面＝Muse 本体与系统
  sheet 共同行为，用户 10:09 点名）；底栏隐藏后安全
  区底 inset 只剩 home indicator，抽屉底条落屏幕真
  底边，与第 2 修合并落地

### 26.8 交付记录（0.4.1 全批）

- commits（feat/ia-v3）：f603a6d（长按四件）／e726891
  （第 5/6 修）／90c9b79（第 2/8 修）／95ab47e（第 4
  修）／925244d（第 1/3/7 修）／7c4ad80（单测编译修
  ＋本节文档初稿）／f9cd0c4（第 9 修＋第 6 修收紧）／
  23f91f7（中性阈值修＋CI 段回填）／eda52c4（第 10
  修）／b20ca1b（SessionDisplayTests 期望同步＋§26.10
  补记）／本节回填提交（docs-only、IPA 不受影响）
- CI：run 42548996515（长按波次，success，单测 118）
  ／run 42550139236（八修波次，红——新单测一处编译
  错 getRed 独占访问，7c4ad80 修）／run 42550395904
  （红——119 测执行、1 失败：气泡中性断言阈值误设
  2/255、封存值自身即 3/255，阈值改 4/255 修，见
  §26.7 第 6 修注）／run 42551143894（八修＋九修
  定稿，success，单测 119）／run 42551812746（第
  10 修，红——SessionDisplayTests 三断言钉旧副题
  字符串，b20ca1b 同步）／**交付 run 42552399029
  （success，单测 119＝105 基线＋长按 13＋短名 1，
  气泡/副题两处为替换不增减）**
- IPA：2,199,166 字节（~/workspace/your_files/
  oneday-v0.4.1/oneday-unsigned.ipa，md5 与 CI 工
  件一致），解包 Info.plist＝0.4.1/25 核对**通过**
  （CFBundleIdentifier＝site.didichou.oneday）
- 未验证如实标注：键盘弹起、抽屉单栏手感、底栏收起与
  胶囊三档切换均为真机行为，本批无真机/截图验收环，
  全部归用户真机终审；R1（续聊回写同一服务端会话）
  仍未验证（维持无状态重放，未对生产发写请求）

### 26.9 第 9 修：消息正文字重收口（用户 10:22 追问，细化第 6 修）

依据苹果 HIG 字体规范表（用户查证钉死）：iOS 正文
Body＝17pt Regular、行高 22；Headline 与 Body 同为
17/22、只差 Semibold——沾 semibold 就显粗；苹果自
家「信息」App 的消息正文就是 Body Regular。施工口
径：聊天消息正文一律 Font.body（系统字体、regular、
默认 leading），禁 .headline/semibold/medium 充当
正文、禁 rounded 设计字体；strong 只对应内容本身
的 ** 加粗；标题从 body regular 基准派生。

- [x] MarkdownText 段落：.font(.body) 维持，手工
  .lineSpacing(5) 撤销——行高回系统默认 leading
- [x] MarkdownText 标题：一级 .title2（22 regular，
  HIG 表里 Body 之上唯一字重仍 regular 的放大语义
  样式，层级由字号承担）；二级以下回 .body 基准
  （层级由块间距承担）；旧 .headline（17 semibold）
  废止；标题内 strong 改与正文同规则（同字号 bold
  一档、只对应 **），「标题自带 semibold」旧注释
  口径同步废止
- [x] 引用块称呼（caption2 semibold）、引用条标题
  （caption semibold）：同守 regular 基准、撤销
- [x] grep 清点（消息渲染路径全量，commit f9cd0c4）：
  用户泡正文 .body ✓／流式正文 .body ✓／段落 .body
  ✓（均第 29 条既有口径、本修未动）；strong＝
  .body.weight(.bold) 仅 ** 触发 ✓；残留两处、均
  非正文文字——①代码块 .system(.footnote, design:
  .monospaced)：代码内容例外（等宽是代码语义、非
  rounded 设计字体），保留；②引用条 ✕ 的 SF
  Symbol 字形 .system(size:12, weight:.semibold)：
  图标笔画字重（框架字形口径、非文字），保留


### 26.10 第 10 修：侧边栏量测对齐（用户 10:30 逐像素采样，细化第 2/8 修）

目标值全部来自主代理对两张抽屉截图（Muse 本体 vs
OneDay）的逐像素采样，逐项销账：

- [x] 面板宽度：drawerWidthFraction 0.79 → 0.75
- [x] 贴顶贴边：面板底色改穿上下安全区（状态栏压面
  板之上）、四角归直角（0.3.6 右侧 28 大圆角 clip
  退役、drawerCorner 令牌留表作废注记）；底部不设
  硬边——会话栏底加系统 .scrollEdgeEffectStyle
  (.soft, for: .bottom) 渐隐收尾
- [x] 面板底色：Palette.chatSurface 回 §22 量测值
  #FCFCFC 字面直给（0.4.0 改挂 systemBackground 纯
  白 #FFFFFF 属漂移；暗色纯中性 #1E1E1E 派生）——
  面板与聊天表面同值复归
- [x] 右侧内容纱：下层 ultraThinMaterial 轻模糊＋
  上层 Palette.scrim 纱色 #F4F4F6 @ 0.66（旧白
  0.55 采样近乎无纱）；分离感靠纱不靠影
- [x] 阴影收窄：旧黑 12%/半径 30/x 16（约 40pt 宽
  软带）→ 黑 8%/半径 6/x 3（约 10pt 贴边窄影），
  加右缘 0.5pt 发丝线（字面 #E3E3E3、向外衰减到
  纱色由窄影承担）
- [x] 选中填充：Palette.selectionFill 撤销 system-
  Gray5 挂接（抽屉采样 #E6E5EB 紫灰，与第 6 修同
  病）→ 字面中性 #EEEFF1（暗色 #2E2E2E）；导航行
  与会话行同源同改；单测断言同步改钉字面值
- [x] 底条玻璃化：圆钮与搜索胶囊撤白浮纸（灰实
  填）→ .glassEffect(.regular) 近白玻璃＋发丝边
  ＋轻柔影（黑 6%/半径 8/y 2），随单栏滚到真底
  部、下方接滚动边缘柔效渐隐
- [x] 分组节奏：会话各组之间、本地组与「其他会
  话」组之间补发丝分隔线（drawerDivider 同式）——
  0.3.8 第 21 条纯留白分段就此推翻
- [x] 副题翻译：SessionDisplay.sourceLabel 的
  api_server 由「API 接口」改「其他应用」（未翻
  译原状态、违反数据先翻译红线，用户点名）；
  ServerLabels.platformName 同名词是平台管理面
  口径（命名服务端组件本身）、不在此列、未动
  （补记：副题字符串另有 SessionDisplayTests 三断
  言钉旧值，run 42551812746 抓红后同步更新——改
  字符串口径时测试期望同改，此为其职）

## §27 0.4.2 热修批销账（抽屉结构纠正＋聊天双缘柔效＋划到底抖动定因，2026-11-09）

版本 0.4.2／build 26，分支 feat/ia-v3。触发：用户已装
0.4.1 在用，10:54 真机标注两图（Muse 本体侧边栏圈
标 1/2＋Muse 聊天页圈上下缘）＋报一 bug（对话划到
底抖动）。范围只此三件：不碰二期逐页迁移；未动
Hermes 服务端；无截图工作流新增/复活。发版三处版本
源同改（Project.swift 工程设置＋infoPlist 字面量＋设
置页关于行字串），交付前解包验 Info.plist（§25.7）。
CI run 与单测数见本节末交付记录。

### 27.1 抽屉结构纠正：头尾钉住、中段滚动、两端渐隐

口径沿革如实记：0.4.1 第 2 修按用户 10:06「不分上
下几栏、一栏可滚」做成整栏单 ScrollView（头/名单/
底条一起滚）；10:54 用户对照 Muse 本体侧边栏标注
图把口径定清——**标 1（顶部智能体名区）不滚、标 2
（底部齿轮/搜索/新建行）不滚、中间名单区滚动，且
滚动内容在头尾两端朦胧渐隐**（标注图里最下方「旁
聊」一行半融在底条上方）。0.4.1 的整栏全滚读法就此
作废，以本节为准。

- [x] 结构改：名单 ScrollView 居中（drawerNavList
＋drawerList），drawerAgentName 经.safeAreaInset
(edge:.top) 钉顶、drawerBottomBar 经.safeArea-
Inset(edge:.bottom) 钉底——条即安全区的系统通道
（与聊天页发送舱同式，WWDC25-323），内容从头尾
两区下方滑过
- [x] 渐隐改：名单 ScrollView 上下两缘挂.scroll-
EdgeEffectStyle(.soft)——滑到头尾边界时内容朦胧
化开，不用实色渐变带假冒（0.4.0 删 topFade 的同
一纪律）；0.4.1 只有底缘一条柔效是整栏结构的产
物，本版两缘齐备、且柔效落在中段滚动区本体上
- [x] 头尾材质与面板同源：两区不设自有背景，透出
的即面板底色 #FCFCFC（§26.10 量测口径）；面板其
余量测不变——宽 75%、通顶贴边、#EEEFF1 选中、
纱（ultraThinMaterial＋#F4F4F6@0.66）＋贴边窄
影、开抽屉 toolbarVisibility 藏底栏（第 8 修）
- [x] 底条下边距改：safeAreaInset 结构下安全区已把
条抬到 home indicator 之上，下边距只留 4——旧
「安全区 inset＋4」公式（DrawerGeometry.bottom-
BarBottomPadding）是内容直达屏底结构的手算补
位，在此叠加即双重计算、条被抬高一截，本处用
法退役（纯函数本体与单测留档不删）；条落点与旧
口径一致（中心约屏高 92.5%）
- [x] 退役件：整栏 minHeight 撑满（GeometryReader
测高）＋Spacer 推底条整套删除；drawerOverlay/
drawerPanel/drawerBottomBar 的 bottomInset 参数
链随之撤销（安全区口径归系统，不再由 body 手传）

### 27.2 聊天页上下边缘：M3 双缘柔效提前落地

用户第二张标注图（Muse 聊天页）：顶部圆钮＋身份
胶囊是浮层、消息滚到其下方朦胧发虚；底部输入卡与
底栏是浮在内容之上的玻璃簇、消息从其下方流过渐
隐。本为二期 M3 卡（phase2-build-cards），本批提
前。审计 §6.1 同源（正式修法＝删自加背景＋顶栏收
系统通道让柔效接管＋底部补挂.soft）。

- [x] 顶缘：0.4.0 已落地（topFade 整层删除＋.scroll-
EdgeEffectStyle(.soft, for:.top)＋顶栏 overlay
只剩 headerBar 本体）——本批复核无回退、无实色
遮罩残留（全文件 grep 渐变/遮罩只剩删除注记）
- [x] 底缘：消息 ScrollView 补.scrollEdgeEffect-
Style(.soft, for:.bottom)——消息流向发送舱（底
部 safeAreaInset 玻璃簇）时朦胧化开、不再硬切到
发送舱上沿；发送舱维持布局流不回退 0.2.6 覆盖
结构（与样板「舱下流过」的差异已于审计 §6.1 明
记：本版以柔效补齐渐隐一职，不动承载）
- [x] 顶栏浮层与发送舱/底栏维持系统玻璃现状（0.4.1
发送舱已回.glassEffect 系统玻璃卡、底栏原生玻
璃坞），本批不改其形态

### 27.3 对话划到底抖动：定因与修法

定因（证据链，逐条对代码实查）：

1. **流式跟随滚动追逐移动靶（流式时主因）**：
runStream 每收到一个增量即写 streamingText（无
节流，SSE 增量每秒可达数十次）；其 onChange 在
isNearBottom 时调 scrollToBottom——而 scrollTo-
Bottom 是 withAnimation(easeInOut 0.25) 的动画滚
动，目标「bottom」锚点随流式行（StreamingText 逐
字入场）生长不断下移。每来一字就重启一条 0.25s
动画去追一个移动靶，动画永远落在靶后、又被下
一字打断重瞄——到底处呈脉冲式抖动。落盘瞬间流
式行换 Markdown 成品（测高不同）再叠一次条目数
变化的动画滚动。
2. **底部 inset 高度骑欠阻尼弹簧（手动划到底主
因）**：「回到底部」钮住在底部 safeAreaInset 的
bottomBar 里，它的显隐直接增减消息列表的底部
inset 高度、而列表底部锚点就骑在这个高度上。
该容器的高度变化动画用 microSpring——令牌册自
注 stiffness 380/damping 18、ζ≈0.46「欠阻尼、
微弹」，本是点按浮钮的出入档；拿它动画锚点所
骑的高度，过冲使锚点随弹簧越过终点再摆回，划
过显隐阈值一次就摆一轮。
3. **贴底判定单阈值逐帧翻转（放大器）**：isNear-
Bottom 是 <140 单阈值即时判定（onScrollGeometry-
Change 直写）。距底距离在 140 附近游走（橡皮
筋回弹、LazyVStack 测高修订）时判定逐帧翻转，
第 2 条的钮显隐与第 1 条的跟随滚动随之反复触发。
4. **次因（只记不治）**：.tabBarMinimizeBehavior
(.onScrollDown)（0.4.1 第 4 修，用户点名要）收
展切换会改变列表底部安全区，与第 2 条同向叠加；
LazyVStack＋MarkdownText 无固定高、长列表落底
时总高有小幅测高修订。两者都是平台行为面，本
版以「inset 与判定稳定」收敛其可见后果，不撤
功能、不假装根除。

修法（与定因逐条对应）：

- [x] 跟随滚动去动画：scrollToBottom 加 animated
参数——人发起的（回到底部钮、键盘锚底）保留动
画曲线；内容跟随（条目数变化、流式生长）一律
animated: false 一步贴合当前底部，移动靶问题消
解为「每次都精确落在当前底部」
- [x] 流式节流：新增 OneDayCore.StreamFollowGate
——每新增 ≥40 字才放行一次跟随贴底；流结束
（streamingText=nil）归零、最后一贴由条目数变
化事件承担；切换线程同步归零
- [x] 判定迟滞：新增 OneDayCore.BottomProximity
——进入 <96／退出 ≥176 双阈值、带内保持原态；
onScrollGeometryChange 改回写距底距离、经纯函
数更新 isNearBottom，阈值附近不再翻转
- [x] inset 高度去弹簧过冲：bottomBar 容器动画由
microSpring 改 swap（easeInOut 0.2、单调无过
冲）——钮出入观感仍在，高度只单调滑到终点，不
再带着列表底部锚点摆动
- [x] 构造断言：BottomFollowTests 8 例钉死——迟
滞两向带内保持/进入/退出边界/橡皮筋负距、节流
闸不足增量不放行/累计放行/reset 重整/新流短文
本从零计（Tests/OneDayCoreTests/BottomFollow-
Tests.swift）
- [] 真机复验归用户：流式中到底不脉冲、手动划
到底不摆、过阈值钮出入列表不弹跳（本批无真机
证据，遵例只报构造与单测）

### 27.4 交付记录（0.4.2）

- commit 0d2ea30（代码＋§27 本文）；本回填为
  docs-only 后随提交，IPA 不受影响
- CI run 42554058577 success（构建＋单测全绿）
- 单测 127（0.4.1 基线 119＋BottomFollowTests 新增
  8，日志聚合行实查；BottomFollowTests 套件 passed）
- IPA：your_files/oneday-v0.4.2/oneday-unsigned.ipa，
  2,199,020 字节，md5 与 CI 工件一致
  （7e4874ba798e4e833e0e311f2e7e6936）
- 解包验版：Payload/OneDayApp.app/Info.plist＝
  CFBundleShortVersionString 0.4.2／CFBundleVersion
  26／bundle id site.didichou.oneday ✓（三处版本源
  同改，§25.7 假绿教训已避开）
- 未验证（如实标注）：抽屉头尾渐隐手感、聊天底缘
  柔效观感、抖动三项真机表现（流式到底不脉冲/手动
  划到底不摆/钮出入不弹跳）均无自动证据，归用户
  真机终审；键盘弹起（0.4.1 遗留项）亦待其复验

## §28 0.4.3 热修批（朦胧感加强：bar 注册路线，2026-11-09）

用户 11:10 真机截图打回 0.4.2（底部透字、顶部
锐利）；11:12 追加令先调研再定路线。调研报告
oneday-design-review/progressive-blur-research
.md（WWDC25 219/284/323/356＋Adopting Liquid
Glass＋Grow 出货实测＋Linear 自述）定案后改道：
Material 打底方案撤销，改走「把 bar 注册进系
统」的约束内正道。本节为定稿销账。

### 28.1 定因（实锤版）

- [x] 挂载点无误：聊天列表 .scrollEdgeEffect-
  Style(.soft, for: .top／.bottom) 挂在 message-
  List 的 ScrollView 本体；抽屉名单同挂其
  ScrollView 本体。不是挂错视图。
- [x] 原因一（顶部·未注册）：scroll edge effect
  只服务**系统 bar 或注册过的自定义 bar**（官方
  文档《Adopting Liquid Glass》明文：custom bar
  须经 safeAreaBar／UIScrollEdgeElementCon-
  tainerInteraction 注册）。顶栏 headerBar 是
  chatSurface 上的 .overlay 悬浮层，从未注册；
  .contentMargins(.top, 88) 只挪内容静止位、不
  产生注册。系统眼里顶部没有 bar——文字以全锐
  度滑到胶囊下方被硬边切断，即截图顶部形态。
- [x] 原因二（底部·实锤：inset 即关效果）：出
  货应用 Grow 团队的 iOS 26 适配实测记录——
  .safeAreaInset(edge: .bottom) 的作用是**关掉**
  底部边缘模糊，系统认可的通道是 toolbar 的
  .bottomBar 或 safeAreaBar。0.4.2 的发送舱正
  挂在 safeAreaInset 里：**系统压根没给发送舱发
  柔效，.soft 等于没挂上**。再叠发送舱玻璃本
  体按设计「内部近乎透明、靠边缘 lensing 定义
  形状」（WWDC25-219），本身几乎不磨字——两
  者叠加即截图底部「字透过输入卡还基本能读」
  的完整解释。
- [x] 原因三（强度与底色，次因）：.soft 无强度
  参数、系统定性 "subtle blur and fade"
  （WWDC25-323）；本页底色 #FCFCFC＋气泡
  #E9EAEC 明度对比近零，带内衰减落在近白对近
  白上几乎不可感（0.2.5 换通道再现）。此条在
  注册后仍成立——它是公开 API 的上限，见 28.6。
- [x] 抽屉同查结论：**同类问题**。抽屉头尾同为
  未注册的 safeAreaInset，其 .soft 同理从未真
  正发放（0.4.2 的头尾渐隐实际未生效）；且注
  册后内容才会从头尾下方穿过、化开形态才成
  立。故同法处理（28.5），非「维持 .soft」。

### 28.2 路线裁决记录

- [x] Material 打底方案**撤销**：曾暂存四处垫
  （发送舱 .regularMaterial 同形垫＋顶栏三钮外
  扩 6pt 垫），全部未提交、已整段回退净。撤销
  理由：①调研 §3 排除「垫厚 Material」为样板
  机制（均匀模糊无渐进，中段半透明重影）；
  ②WWDC25-323 明言 bar 背后的自研背景/压暗层
  会**干扰**系统效果——注册路线下垫层有害无益。
- [x] 顶栏为何不走真 toolbar：会话名次行无
  toolbar 槽位（收编须把顶栏拆成两半、破坏第
  30 条一体构造），且本页 0.2.4 已撤销 Naviga-
  tionStack、重引入的抽屉/底栏交互面风险大；
  safeAreaBar 正是官方文档为「有内容从下方滚
  过的自定义 bar」点名的注册 API，整颗顶栏作
  为一个 bar 注册即拿到系统效果——「尽量收进
  系统通道」以此达成，取舍如实记档。

### 28.3 发送舱改挂 safeAreaBar（底部）

- [x] messageList：.safeAreaInset(edge: .bottom)
  → .safeAreaBar(edge: .bottom, spacing: 0)，
  内容仍是 bottomBar(proxy) 本体零改动（回到底
  部钮＋错误/提示条＋inputBar）；仍属安全区布
  局机制、**不是覆盖层**，0.2.6「布局流」定版
  不回退；.scrollEdgeEffectStyle(.soft, for:
  .bottom) 保留——注册后系统按发送舱高度发放。
- [x] 发送舱自量高＋硬封顶（ComposerLayout/
  ComposerTextMetrics 纯逻辑）未动；玻璃
  .glassEffect(.regular, in: composerShape) 未
  动；卡面点按聚焦层（0.4.1 第 1 修）未动。

### 28.4 键盘硬门复验（构造＋审计＋单测）

结论：**不回退**。safeAreaBar 与 safeAreaInset
同属安全区布局族，键盘在 SwiftUI 里就是以安
全区扩张的方式出现——条的升降通道未变。逐项
证据：
- [x] 构造：键盘跟随的驱动源是窗口安全区（键
  盘帧→安全区 inset），safeAreaBar 内容与
  safeAreaInset 内容同置于安全区内被其驱动；
  WWDC25-323 的 safeAreaBar 演示场景即滚动视
  图＋底部自定义 bar，与本页同构。
- [x] 代码审计（逐条核对键盘链，全部未依赖
  inset 修饰符本身）：①焦点句柄 composer-
  FocusHandle（0.2.8）与 ComposerTextView 本
  体未动，点文本视图直触聚焦通道不变；②卡面
  点按聚焦层（0.4.1 第 1 修）挂在 composerRow
  的 .background 上、与承载修饰符无关，未动；
  ③键盘锚底两路触发（composerFocused 边沿＋
  keyboardWillChangeFrameNotification 监听）
  未动，触发源是通知与状态、不读 inset；④
  .scrollDismissesKeyboard(.interactively) 挂
  ScrollView 本体，未动；⑤距底判定 onScroll-
  GeometryChange 读 contentSize/containerSize
  ——注册后键盘升起仍同步压缩 container（安全
  区构成变了成员、没变机制），BottomProximity
  迟滞逻辑未动；⑥内容栈撑满 minHeight 常数
  64 退役（见 28.7），不影响键盘链。
- [x] 单测：OneDayCore 全套（含 Composer 布局
  与 BottomFollowTests 8 例）随 CI 全绿（数字
  见 28.8 交付记录）。
- [] 真机复验归用户（如实标注，本批无真机证
  据）：点输入栏键盘必弹、舱随键盘升降不膨胀
  不留白、交互下滑收键盘跟随——与 0.4.1 遗留
  的键盘确认合并为同一验收项。

### 28.5 顶栏与抽屉注册

- [x] 顶栏：chatSurface 的 .overlay { headerBar }
  整层撤销；headerBar 改挂 messageList 的
  .safeAreaBar(edge: .top)（内容本体零改动：两
  圆钮＋身份胶囊＋会话名次行整颗注册）；.con-
  tentMargins(.top, 88) 随之删除——首屏位置改
  由安全区本体让出。.soft 顶缘保留，作用区自
  此＝顶栏高度。
- [x] 抽屉：drawerPanel 的 .safeAreaInset(edge:
  .top／.bottom) → .safeAreaBar（spacing: 0），
  头尾钉住结构、名单中段滚动、底条下边距 4pt
  校准、搜索 TextField 的键盘跟随（同走安全
  区）均不变；注册后名单内容从头尾下方穿过、
  两端 .soft 化开（用户 10:54 标注口径至此才
  有系统通道支撑）。

### 28.6 预期上限（如实声明）

注册只把系统效果**发满**，上限仍是官方 subtle
级：密排文字滚到发送舱上方会变糊变淡，但达不
到 Muse「整片溶掉」的厚度——差在渐进模糊
（variable blur）无公开 API、且作用区严格等
于 bar 高度（调研 §4.1/4.2）。完全对齐样板须
用户在调研 §4.3 三条放宽里点一条，本版未擅
自越线。

### 28.7 附带调整

- [x] 内容栈撑满 minHeight：- 64 - spacingS →
  - spacingS（顶栏注册后容器高已不含顶区，64
  近似常数退役；注释已同步改写）。
- [x] 相关注释全面对齐新结构（chatSurface 主面
  注、messageList 边距注、bottomBar／headerBar
  文档注、drawerPanel 结构注与底条边距注），
  历史沿革保留、现状表述不留旧词误导。

### 28.8 交付记录（0.4.3）

- 版本三处同改：Project.swift（MARKETING_
  VERSION 0.4.3／CURRENT_PROJECT_VERSION 27／
  Info.plist 字面量 CFBundleShortVersionString
  0.4.3／CFBundleVersion 27）＋SettingsView 关
  于区显示串 0.4.3（§25.7 假绿教训口径）
- 代码提交 ef2afcb（bar 注册路线）＋7728997
  （§28.9 图标锁）；本回填为 docs-only 后随提
  交，IPA 不受影响
- CI run 42556265029 success（构建＋单测全绿；
  注：本仓 workflow 仅 main 分支 push 自动触发，
  本次经 workflow_dispatch 以 feat/ia-v3 触发）
- 单测 127（与 0.4.2 同数：本批无新增用例，键
  盘链相关的 ComposerLayout／ComposerText-
  Metrics／BottomFollow 诸套件在内、全绿，日志
  聚合行 "Executed 127 tests, with 0 failures"
  实查）
- IPA：your_files/oneday-v0.4.3/oneday-
  unsigned.ipa，2,202,583 字节，md5 与 CI 工件
  一致（557cb876144fc912bc6e989268ffa3b3）
- 解包验版：Payload/OneDayApp.app/Info.plist＝
  CFBundleShortVersionString 0.4.3／CFBundle-
  Version 27／bundle id site.didichou.oneday ✓
- 未验证（如实标注）：顶/底化开强度、抽屉底
  条落点与搜索键盘跟随、聊天键盘四项（28.4）
  均无自动证据，归用户真机终审

### 28.9 底栏图标空心钉死（11:22 追加，并入本批）

用户点名：底部导航栏图标要空心不要实心，跟
Muse 一样；11:10 真机截图实证 0.4.1 的「图标
锁 outline」在真机没成立（选中态聊天格仍是实
心双气泡）。范围只限底部导航栏四格，抽屉内图
标本批不动。

- [x] 四格符号名逐个核对（OneDayCore.TabBar-
  Symbols，单一事实源）：聊天 bubble.left.and.
  bubble.right／总览 chart.line.uptrend.xyaxis
  ／文件 folder／设置 slider.horizontal.3——全
  是 outline 本体名、无一带 .fill；selected≡
  normal 四格全等。TabBarSymbolsTests 三组钉
  死（全表钉死／全表禁 .fill／两态同名）。**数
  据层无病**。
- [x] 0.4.1 为什么没生效（定因）：两道锁都挂
  在系统不读的层级。①符号表 selected≡normal
  只堵「应用主动报 fill 名」——系统给选中条目
  换图根本不需要应用报名：底栏宿主以基础符号
  名在其变体族内直接取 .fill 变体作选中图（该
  族内 bubble.left.and.bubble.right 的 .fill 变
  体实存于 SF Symbols）。②.symbolVariant
  (.none) 挂在 tabLabel 的 Label 字形子树里—
  —SwiftUI 的底栏条目不是由 Label 子树就地渲
  染的，而是由 TabView 宿主**以 TabView 层的
  环境**统一构建，子树里设的环境值到不了构建
  处。证据链：代码位置（ContentView tabLabel）
  ＋单测证明数据层已锁死仍出实心＋真机截图
  （选中格实心、无内部留白＝.fill 变体渲染本
  人）。0.4.1 销账把「构造上有锁」当成了「呈
  现已生效」，是构造自证代替真机口径的老问题
  在图标上的复发。
- [x] 本批修法：ContentView 的 TabView 根加
  .environment(\.symbolVariants, .none)——注
  入到宿主构建条目时真正读取的那一层，全格全
  状态不变体；tabLabel 内 .symbolVariant(.none)
  保留作第二道锁并已在注释里标明其单独无效；
  字重不另设、随系统 regular 直渲（与 §22.6 框
  架图标 regular 口径一致）；文件头与 tabLabel
  的 0.4.1 注释已加纠正标注、不改史。
- [] 真机复验归用户：四格在选中/未选两态均
  为空心细线（本批无真机证据）。

## §29 0.4.4 热修批（朦胧感放大 E11＋正文墨/字号，2026-11-09）

用户 11:31 真机验收 0.4.3 两条指令：①「上面朦胧
感有点了，方法是对的，继续搞大点，下面的也加上」
——此即 11:18 预留的放宽决定，批准调研 §4.3 第
一条豁免（masked 真模糊层），登记为新例外 E11；
②11:33 点名「字体还是黑，粗」——主代理同机双截
图量测（OneDay 正文笔芯 ≈14／覆盖 20.7%，Muse
笔芯 ≈38／覆盖 14.8%）＋查码定因后并入本批。

### 29.1 例外 E11 登记（真渐进模糊近似层）

> **【注销】E11 已于 0.7.1 正式注销（2026-11-09）**：
> 用户 16:07 真机验收 0.6.1 否决本方案（上下白边、
> 判「不成熟」）、16:15 点选批准 chrome 裁决全案。
> 裁决档 oneday-design-review/chrome-research-
> 20261109.md 定案：带体对平色背景的 backdrop 模
> 糊输出恒等于材质 tint——静止时「朦胧」物理上不
> 存在、只剩带硬边的灰片（量测 245 vs 画布 252，
> 裁决 §1.1）；且属 WWDC25-323 明文应删的 bar 后
> 自加背景层。本节以下登记内容自 0.7.1 起全部作
> 废、仅作历史留档：EdgeProgressiveBlur.swift 已
> 删除、四处边缘回到「已注册系统 bar＋scrollEdge-
> Effect(.soft)＋背景同源全出血」的官方结构，任
> 何形态的独立边缘带（模糊/实色/渐变/材质片）全
> 禁（设计标准 §6 修订同日入册）。

- [x] 出处与批准：调研 progressive-blur-
  research.md §4.3 第一条（放宽「禁假渐变带」
  的解释、允许 masked UIVisualEffectView 作滚
  动两缘独立模糊层）；用户 2026-11-09 11:31
  亲口批准（「继续搞大点，下面的也加上」）。
- [x] 边界：只用公开 API（UIVisualEffectView＋
  UIBlurEffect＋CAGradientLayer mask）；私有
  variableBlur 滤镜线（调研 §2.1/§4.3-3）不
  碰；假色带（纯颜色渐变冒充模糊）不许——本
  层是真 backdrop 模糊、mask 只衰减其 alpha。
- [x] 与既有例外表的关：E11 是「无系统等价物」
  的新条目——系统 .soft 的作用区与强度无公开
  旋钮（§28.6 已明示上限），本层补的是作用区
  长度，不是替代 bar 注册路线；bar 注册＋.soft
  全部保留、叠加生效。

### 29.2 组件（EdgeProgressiveBlur）

- [x] 新文件 Sources/OneDayApp/EdgeProgressive
  Blur.swift：UIViewRepresentable 承载 UIVisual-
  EffectView（.systemMaterial，明暗自适应），
  CAGradientLayer 作 layer.mask（黑 alpha 停点
  列、自带顶向带底插值），layoutSubviews 同步
  mask frame；半径恒定、alpha 渐变（调研 §2.3
  公开口径的固有上限：中段有半透明重影，与样
  板的差距收窄不消失，如实记）。
- [x] 命中全关：SwiftUI 侧每处 .allowsHitTest-
  ing(false)＋UIKit 侧 isUserInteractionEnabled
  = false，滚动/点按/长按菜单零干扰。

### 29.3 挂载与几何（四处，全部走 bar 的 background 溢出）

挂载点选型：不另起覆盖层——四层一律作已注册
safeAreaBar 内容的 .background 溢出绘制。理由：
①z 序确定（bar 是系统 chrome、整体在滚动内容
之上，其 background 在 bar 本体之下、本体保持
锐利）；②位置跟随 bar 的安全区通道（底带随键
盘升降与发送舱同轨，见 29.5）；③background 不
参与布局（bar 尺寸、发送舱自量高＋硬封顶链零
影响）。残余不确定性如实记：若系统对 safeArea-
Bar 内容的 background 溢出作裁剪，增益静默退化
回 0.4.3 的 .soft 状态（不破版），真机截图即判。

- [x] 聊天顶：headerBar 的 background（align-
  ment .top），带长 176pt、上探 offset −60（盖
  状态区）、延出顶栏下缘约 45pt；停点（带顶→
  带底）0:1／0.58:1／0.82:0.45／1:0。
- [x] 聊天底：bottomBar 的 background（align-
  ment .top），带长 216pt、自发送舱上缘上方
  56pt 渐入（offset −56）、穿舱体、向下延约
  96pt 与底栏坞衔接成一片；停点 0:0／0.14:
  0.5／0.27:1／1:1（到舱上缘满模糊、其后恒满）。
- [x] 抽屉顶：drawerAgentName 的 background，
  带长 150pt、上探 −56、向名单延出约 35pt；
  停点 0:1／0.60:1／0.85:0.45／1:0。
- [x] 抽屉底：drawerBottomBar 的 background
  （alignment .bottom），带长 124pt、自底条上
  方约 68pt 渐入；停点 0:0／0.35:0.5／0.55:1
  ／1:1。
- [x] 发送舱本体零改动：safeAreaBar 承载、自
  量高＋硬封顶、玻璃、卡面聚焦层全未动（结构
  口径同 §28.3）。

### 29.4 正文墨与字号（11:33 追加件）

- [x] 定因（主代理量测＋查码，本批复核无误）：
  字重无病——正文 .body regular、strong 只映
  射 ** 段；病在 Palette.ink = Color.primary
  （系统最黑、笔芯 ≈14）＋17pt 在炭灰对照下墨
  迹足迹偏大（覆盖 20.7% vs 样板 14.8%）。
- [x] 新墨：Palette.bodyInk 字面值 #262626 中
  性炭灰（对齐量测笔芯 38）；暗色暂定 #D9D9DE
  （未经量测、归真机抽查回填）。
- [x] 字号：17→16 regular，语义载体走 .callout
  （HIG 字体表 Callout＝16 regular／行高 21），
  守 DesignTokens「框架不用 Font.system(size:)
  写死」纪律；strong 随基准换 .callout.weight
  (.bold)（与 regular 恰差一档的口径不变）。
- [x] 落点四处（只限消息正文，框架文字不动）：
  ①用户泡 Text（ChatView.bubble）②助手泡
  MarkdownText（段落 font＋strong＋墨、二级以
  下标题基准随正文、代码块与一级标题只换墨）
  ③流式行 StreamingText（font＋墨）④引用块摘
  要（quoteBlock，只换墨——摘要是被引正文本
  身；说话人名是标签、仍 inkSecondary，层级靠
  字号＋左细线＋底垫）。发送舱输入文字、胶囊、
  标题、设置页等框架文字本批未动。
- [x] 量测口径（前后）：笔芯目标 ≈38（由 ≈14）、
  覆盖目标 ≈15%（由 20.7%）；本批无自动量测证
  据，真机复量归用户截图终审。

### 29.5 键盘硬门复核（§28.4 六条逐条）

结论：不回退。本批新增物只有 bar 的 background
层与正文字体/墨，均不进键盘链：
- [x] ①焦点句柄 composerFocusHandle／Composer-
  TextView 本体未动；②卡面点按聚焦层在 compo-
  serRow 的 .background 上——本批底带是 bottom-
  Bar 整体的 background、位于其后，命中自前向
  后仍先达聚焦层，且模糊层双侧断命中；③键盘
  锚底两路触发（composerFocused 边沿＋键盘帧
  通知）未动；④.scrollDismissesKeyboard 挂
  ScrollView 本体未动；⑤距底判定 onScrollGeo-
  metryChange 未动（background 不改 container-
  Size/contentSize）；⑥内容栈 minHeight 公式未
  动。发送舱自量高：background 按定义不参与尺
  寸协商，ComposerLayout/ComposerTextMetrics
  未动。底带随键盘的跟随由构造保证（与发送舱
  同挂一个 safeAreaBar 内容、同被安全区驱动）。
- [x] 单测随 CI 全绿（数字见 29.8）；真机复验
  归用户（与在册键盘确认合并）。

### 29.6 图标复核（0.4.3 注入是否到达宿主构建层）

结论：**已生效，不换注入点**，代码证据链：
- [x] 数据层：TabBarSymbols 四名全 outline 本
  体、selected≡normal，TabBarSymbolsTests 三
  组钉死（§28.9 在案，本批复查原文无漂移）。
- [x] 注入层：ContentView 的 .environment(\.
  symbolVariants, .none) 直接挂在 TabView 本
  体上——宿主构建条目时读的正是 TabView 自身
  的环境（0.4.1 挂 Label 子树读不到的定因即在
  此对照）；tabLabel 内 .symbolVariant(.none)
  为第二道叠加锁。修饰顺序与位置本批逐行复
  查无误。
- [x] 无竞争源：全仓 grep symbolVariant(s) 只
  ContentView 两处；tab 路径无 symbolRender-
  ingMode 覆写、无第二处环境注入。
- [x] 截图判读（如实）：11:31 截图里被指「偏
  实」的聊天/文件，恰是 outline 本体即闭合轮
  廓的两枚（双气泡＝两只气泡轮廓交叠、文件
  夹＝闭合轮廓），在坞内约 20pt＋聊天截图压
  缩下笔画密度天然读作偏实；同图的总览/设
  置为开放线条、呈空心。两枚恰有 .fill 变体
  存在，故截图本身不足以在「变体锁失效」与
  「轮廓本密」间定案——终审归用户下一张原
  图（放大看文件夹盖折线与气泡交叠留白），
  本批不空口断言已修好、也不无据换点。

### 29.7 抽屉复用结论

- [x] 已复用：同一组件、四处同构挂载（29.3），
  抽屉头尾钉住＋safeAreaBar 注册结构未动。

### 29.8 交付记录（0.4.4）

- 版本三处同改：Project.swift（MARKETING_
  VERSION 0.4.4／CURRENT_PROJECT_VERSION 28／
  Info.plist 字面量 CFBundleShortVersionString
  0.4.4／CFBundleVersion 28）＋SettingsView 关
  于区显示串 0.4.4（§25.7 假绿教训口径）
- 代码提交 0291fc4（E11 四缘模糊层＋正文墨/
  字号四处＋版本）；本回填为 docs-only 后随提
  交，IPA 不受影响
- CI run 42557645977 success（构建＋单测全绿；
  workflow_dispatch 以 feat/ia-v3 触发。同
  commit 另有一 run 42557741435 亦 success，
  系派发命令重入的重复触发，工件同源、取前者
  为交付口径）
- 单测 127（与 0.4.3 同数：本批无新增纯逻辑，
  模糊层参数与正文样式均为视图层字面量；日志
  聚合行 "Executed 127 tests, with 0 failures"
  实查）
- IPA：your_files/oneday-v0.4.4/oneday-
  unsigned.ipa，2,213,815 字节，md5 与 CI 工件
  一致（1d1e95fed49e5f15c29d909971a32f41）
- 解包验版：Payload/OneDayApp.app/Info.plist＝
  CFBundleShortVersionString 0.4.4／CFBundle-
  Version 28／bundle id site.didichou.oneday ✓
- 未验证（如实标注）：四缘化开强度与 bottom-
  Bar background 溢出是否被系统裁剪（29.3）、
  正文笔芯/覆盖复量、图标两格原图判读、聊天
  键盘四项——均无自动证据，归用户真机终审

## §30 0.4.5 批（抽屉推式换代＋底条贴边＋E11 底带收下延＋底栏图标换本体，2026-11-09）

起因三条（均为用户真机对 Muse 本体点名）：
①11:37 发 Muse 本体录屏——「侧边栏是推不是
盖」：整页（含底部导航坞）作一张卡被推向右、带大
圆角＋柔影、略带缩小，抽屉在下层；OneDay 0.4.4 前
是覆盖式（纱＋peek 面板盖上来）。②11:47 发侧边栏
全开截图——「下面和侧边栏的下面多了」：样板底条
贴屏底、名单在底条下方渐隐直达屏边、被推页卡四
角圆角通底。③11:49——底栏文件/聊天两格仍实心观
感，「没有办法可以换图标呀」：换路线，不再跟变体
锁死磕，直接换图标本体（30.7）。

### 30.1 录屏/截图量测（先量后动，方法与原数）

材料：录屏 720×1566@30fps（抽帧 fps=4 共 26 帧）
＋11:47 全开截图 1284×2778。方法：逐帧目检＋像
素行剖面扫描＋模板匹配（PIL/numpy 归一化相关，
无 cv2；模板取关闭态帧的汉堡钮与全开帧的抽屉新
建钮）。定版数：

| 项 | 实测 | 施工定值 |
|---|---|---|
| 推开量（页卡左缘/屏宽） | 视频 y=1100 行剖面：影带渐变止于 x≈567 → 78.8%；截图左缘 ≈1015/1284 → 79.0%（两源互证） | 0.79×屏宽，上限 400pt |
| 缩放 | 汉堡钮模板在 0.96 档命中（开启中途帧/全开帧相关 0.91/0.89）、钮纵向位移 ≈0（Δy≈+2px/1566）→ 顶锚缩放；旁证：卡底边升至屏高 ≈96%，与截图实测卡底缘 96–97% 互证 | 1→0.96、anchor 顶中 |
| 圆角 | 截图角弧弦差 ≈85px/1284 ≈ 0.066W → ≈28pt（428pt 宽机） | 28pt×progress、四角同式 |
| 左缘影 | 影带宽 ≈55px/720 ≈ 27pt、最深处贴缘（灰度 217 vs 面 250、约 13% 压暗）、向左衰减到无 | shadowBase 16%/radius 24/x −10、随 progress 插值 |
| 抽屉联动 | 两帧独立地标拟合：页卡缘 46.3% 时抽屉新建钮位移 −240px、40.0% 时 −284px → 抽屉偏移＝页卡位移−推开量（斜率 1.0） | 刚性联动：抽屉偏移恒＝页卡偏移−travel |

注：主代理粗量「页卡左缘约 82%」是把左缘外侧约
55px 影带计入的读数；表面缘以剖面突变点为准
（79%）。圆角右角在全开/中途恒在屏外、不可量，
按整卡圆角矩形同半径落实（追加③指令）。缩放锚
点系由「顶部地标纵向不动＋卡底上移」两证推定
（顶中锚与中锚＋上移补偿在像素上不可分，取顶锚
实现，两者视觉等价）。

### 30.2 结构换代销账

- 抽屉承载从 ChatView 提到壳层（ContentView 根）：
  ZStack｛抽屉面（底层）／应用表面页卡（TabView
  整表，上层）｝，单一 progress（页卡位移/推开量）
  驱动位移/缩放/圆角/柔影四件事；抽屉偏移＝页卡
  偏移−travel（刚性联动，30.1）。点露出页卡窄条
  关闭（开态命中层接管整卡点按与横拖）。
- 新文件 DrawerView.swift：抽屉本体（头尾
  safeAreaBar 钉住＋E11 两端模糊带＋名单/搜索/底
  条）自 ChatView 原样搬迁、口径不改（承载性改动
  只三处：底条下边距手算、底带延长、右缘收尾撤
  销，见 30.5/30.8）；自带 @Query 与 modelContext，
  置顶/重命名/删除直操作 SwiftData。
- 跨视图通道走 AppState（先例 pendingChatSession-
  ID）：ChatView 回写 activeThreadID；DrawerView
  写 drawerThreadSelection（点行/新建）与 drawer-
  DeletedThreadID（删当前线程），ChatView 消费清
  零；服务端会话行沿用 pendingChatSessionID 改道
  链（ContentView 切聊天格＋ChatView 导入续聊，
  0.4.0 §3.4 不变）。ChatView 的 onOpenServer-
  Session／onSelectTab 两注入闭包随之撤销。
- ChatView 瘦身：删覆盖层/面板/手势/setDrawer 全
  套与抽屉状态六件（约 710 行）；body 回归 chat-
  Surface 本体；汉堡钮改写语义状态 drawerPresented、
  壳层 onChange 执行开合。
- 打开必先收键盘：壳层 setDrawer(true) 先走系统
  第一响应者通道收键盘，再启动画（旧承载在覆盖
  层内由结构保证、现显式化）。
- 动画：既有 MotionTokens.dragSpring（条 9 定版、
  stiffness 1200/damping 80、零回弹）驱动 progress，
  与录屏约 0.35s 级减速吸附同档；跟手/吸附/橡皮
  筋（DrawerGeometry.rubberBand）制式与旧抽屉逐
  式一致，宽度参数由面板宽换推开量。

### 30.3 保成果核对（对着 0.4.2–0.4.4 逐项）

- 抽屉头尾钉住＋名单中段滚＋两端化开：结构与带
  参（顶带 150/−56、drawerTop 停点）逐点不变；
  底带仅按下条延长。
- 点会话关抽屉＋续聊改道：链路不变（30.2 通道化
  后：本地行→drawerThreadSelection、服务端行→
  pendingChatSessionID，两路都先关抽屉）。
- 聊天页 safeAreaBar 顶/底注册、E11 顶带、发送舱
  自量高链、键盘安全区通道：未动；底带仅改带长
  与停点（30.6）。
- 0.4.1 第 8 修「开抽屉藏底栏」**撤销**：推式下
  坞随页卡同走、不存在「抽屉开着底栏露面」的问
  题，toolbarVisibility 绑定拆除（口径变化入
  30.8）。

### 30.4 手势仲裁清单（逐个核对）

- 左缘热区（24pt，OneDayMetrics.drawerEdgeZone）
  右滑开：挂页卡 overlay、仅合态存在、显隐只认
  drawerOpen（拖拽中不摘，防手势中途失效——旧覆
  盖层同制式）；轴向门 |横|>|纵| 才接管，纵滚不
  抢；热区内点按由热区持有（0.2.2 沿革不变），
  其余区域「点空白收键盘」不受影响。
- 开态命中层（整卡）：点按关、横拖跟手关（轴向
  门同上）；开态下卡内控件/列表/坞不可达是预期
  行为（被推开的页卡只是预览，样板同理）。
- 抽屉面拖拽：挂 DrawerView 本体，与名单纵滚以
  轴向门仲裁（旧面板同口径）；名单行点按/长按菜
  单、搜索框输入、底条按钮点按均不经平移手势，
  不受影响。
- 各页内部横向交互（页面内横滑/长按菜单等）：壳
  层平移手势只存在于左缘热区与开态命中层，页面
  内部区域不挂壳层手势，不抢。
- 聊天页既有手势（消息长按菜单、点空白收键盘、
  列表竖滚、交互收键盘 .interactively）：挂点与
  类型全未动；壳层手势与之的关系只有上面两条。

### 30.5 追加①：抽屉底条几何（先量后改）

- 样板（11:47 截图实测）：底条行底缘 ≈96.1%
  （2670/2778），其下是名单尾行渐隐直达屏边
  （100%），无死白条。
- OneDay 现行（0.4.3 后构造推算）：safeAreaBar
  钉底＋下边距 4 → 底缘＝屏高−34−4，即 95.5%
  （852pt 屏）/95.9%（926pt 屏）；与样板差 ≤5pt
  ——边缘位置本就同量级，真差距在条下：34–38pt
  纯面板色死带（名单帧止于安全区）vs 样板的内
  容渐隐到边。
- 改法（落点逐点不变、只补条下）：名单 Scroll-
  View .ignoresSafeArea(edges:.bottom) 直达屏底；
  安全区不再代抬底条，下边距改回手算 Drawer-
  Geometry.bottomBarBottomPadding（窗口底 inset
  ＋4，壳层 GeometryReader 给 inset）——底条底缘
  仍 95.5–96%、与样板同量级；E11 抽屉底带随之
  延长（124＋inset＋4、带底到屏边），停点按绝对
  锚重算（带顶 43pt 半/68pt 满，与 0.4.4 逐点同
  形），名单在底条下方、home indicator 区里被满
  模糊盖住渐隐到屏边——死白条消除。

### 30.6 追加②：聊天页底部簇核查（E11 底带下延）

- 核查（构造复核）：0.4.4 聊天底带固定 216pt、
  作发送区 background(alignment:.top)＋offset
  −56 → 带底＝发送区底缘＋（160−发送区高）；单
  行发送区高约 62pt 时下延 ≈98pt，且停点 0.27
  后恒满 alpha——该段越过发送区底缘、盖住坞身
  并垂进坞下方 home indicator 区，在坞的悬浮间
  隙里显成独立一坨磨砂带。**结论：属实，收掉。**
- 改法：带长改动态＝56＋发送区实测高（bottomBar
  onGeometryChange 回写 composerBarHeight），带
  底恰与发送区底缘齐平；停点按绝对锚重算（30pt
  半/58pt 满，与 0.4.4 定版逐点同形）——坞上方
  渐入段分毫不变、坞下方零残留。与 30.5 抽屉底
  带延长不矛盾：抽屉是整幅底层、带下有名单内容
  衬底；聊天页坞下方是悬浮间隙、无内容可衬。

### 30.7 追加③：底栏图标换本体（密度量测定选）

路线：0.4.1/0.4.3 两轮锁变体未过真机，本批直接
换符号本体＋量测为闸。方法：候选符号在模拟器内
离线渲染（RenderMeasureTests 同基础设施，diag
分支两轮 CI 实测，run 42559132273/42559600765），
24pt regular（底栏渲染尺寸），三口径并报：紧致
（墨/紧致包围盒）、格（墨/44pt 格）、画布（墨/
符号画布含设计内边距）。

口径辨析（如实记）：历史「Muse 同位 13–21%」
是真机截图的整格像素口径——§24.1 早已明记它与
渲染紧致口径不可直接比数、证据以同口径对照为准。
本批复核：画布口径下 message/bubble.left/chart
.xyaxis.line 落在 0.20–0.21（带缘），但文件/设
置两格没有任何候选能在任一渲染口径落进 13–21%
（线条画法的 slider 画布口径也有 0.266）——该带
是截图像素阈值下的产物，渲染口径复现不了。故
定选依 §24.1 既定法：同口径相对比较＋本体结构
（是否闭合轮廓），不拿截口径的带硬套渲染数。

| 格 | 候选 | 紧致 | 格 | 画布 | 处置 |
|---|---|---|---|---|---|
| 聊天 | bubble.left.and.bubble.right（旧） | 0.301 | 0.141 | 0.228 | 换 |
| 聊天 | **message** | 0.270 | 0.088 | 0.206 | **选** |
| 聊天 | bubble.left | 0.285 | 0.093 | 0.203 | 备 |
| 聊天 | ellipsis.message | 0.322 | 0.104 | 0.245 | 弃 |
| 聊天 | text.bubble | 0.378 | 0.124 | 0.270 | 弃 |
| 文件 | folder（旧） | 0.367 | 0.110 | 0.260 | 换（闭合轮廓出局） |
| 文件 | **tray** | 0.383 | 0.109 | 0.266 | **选** |
| 文件 | doc | 0.378 | 0.099 | 0.257 | 备（闭合页轮廓＋语义只偏文档） |
| 文件 | doc.text | 0.446 | 0.117 | 0.303 | 弃 |
| 文件 | archivebox | 0.418 | 0.111 | 0.289 | 弃 |
| 总览 | chart.line.uptrend.xyaxis（旧） | 0.341 | 0.097 | 0.236 | 换 |
| 总览 | **chart.xyaxis.line** | 0.292 | 0.083 | 0.202 | **选（三口径皆最轻）** |
| 设置 | **slider.horizontal.3**（留） | 0.392 | 0.096 | 0.268 | **留** |
| 设置 | gearshape | 0.377 | 0.125 | 0.288 | 弃 |

逐格理由：聊天 message 三口径中紧致/格双最轻、
旧双泡格口径 0.141 是全表最重——用户点名的实
心感在数上成立。文件 tray 是开口托盘线条（无闭
合轮廓、无填充面，与 folder 的结构性区别在此）；
紧致口径 tray 微高于 folder（0.383 vs 0.367——
紧致量的是字形在自身矮盒内的填充率、托盘生来
占得满），格口径（同槽位实际墨覆盖）0.109 vs
0.110 持平，即换形不增墨；doc 格口径虽最轻，
本体仍是闭合页轮廓（与 folder 同家族）且语义
不含影音，列备选。总览换带轴折线、三口径皆轻
于旧。设置 slider 留（指令明示可留；格口径
0.096 属轻档，gearshape 两口径更重）。
量测闸落码：RenderMeasureTests.testTabBar-
SymbolInk（24pt 复量＋格 ≤0.12/紧致 ≤0.42 上
限带，.fill 件 0.72+ 在带外）＋TabBarSymbols-
Tests 全表钉死；抽屉名单同符号源、18pt 既有
0.05–0.45 闸继续把守。变体锁保留作第二道防线，
本批成败只认本体＋密度数，真机观感归用户终审。

### 30.8 口径变化清单（本批有意改的旧口径）

1. 0.4.1 第 8 修（开抽屉藏底栏）撤销，理由见 30.3。
2. 抽屉可达范围：旧版仅聊天格（覆盖层在 ChatView
   内）→新版全格可达（壳层左缘热区；推式壳层的
   应有之义，样板同理）。
3. 覆盖式纱（scrim＋ultraThinMaterial）退役：推
   式无纱，分离靠页卡圆角/缩放/柔影。
4. 面板右缘发丝线＋贴边窄影（0.4.1 第 10 修）撤
   销：推式下面板与页卡贴合，再描一线是双重描边。
5. OneDayMetrics.drawerWidthFraction/drawerMax-
   Width 令牌闲置（留档不删，同 DrawerGeometry
   纯函数退役先例）；DrawerGeometry.bottomBar-
   BottomPadding 反向复活（见 30.5）。

### 30.9 交付记录（0.4.5）

- 版本三处同改：Project.swift（MARKETING_
  VERSION 0.4.5／CURRENT_PROJECT_VERSION 29／
  Info.plist 字面量 CFBundleShortVersionString
  0.4.5／CFBundleVersion 29）＋SettingsView 关
  于区显示串 0.4.5（§25.7 假绿教训口径）
- 代码提交 c3cfa17（壳层推式＋DrawerView＋
  E11 两带改动态带长＋图标换本体＋量测闸＋版
  本）；§30 本节为 docs-only 后随提交，IPA 不
  受影响
- CI run 42560158099 success（构建＋单测全绿；
  workflow_dispatch 以 feat/ia-v3 触发）
- 单测 128（0.4.4 的 127＋新增 testTabBarSymbolInk
  1 条；日志聚合行实查）
- IPA：your_files/oneday-v0.4.5/oneday-
  unsigned.ipa，2,198,269 字节，md5 与 CI 工件一致
- 解包验版：Payload/OneDayApp.app/Info.plist＝
  CFBundleShortVersionString 0.4.5／CFBundle-
  Version 29／bundle id site.didichou.oneday ✓
- 图标密度诊断两轮在 diag/tab-icons 分支完成
  （run 42559132273/42559600765），分支验完即删
- 未验证（如实标注）：推式手感/圆角/缩放/影的
  真机观感、抽屉底条贴边与渐隐到边、聊天坞下
  无残带、图标四格观感、抽屉打开收键盘、从其
  他格开抽屉选线程切格——均无自动证据，归用
  户真机终审

## §31 0.5.0 批（合并列车：phase2-split＋phase3-hub 合回＋胶囊入口接线＋审批桥钥匙字段，2026-11-09）

### 31.1 合并一：feat/phase2-split → feat/ia-v3

- 前置核查：分叉点 ef2afcb（0.4.3）之后主线改动面 14 文件，
  **未含 SettingsDetailViews.swift 本体**（主线只动过 Settings-
  View.swift，是另一个文件）——前提成立，未触发「先停下说明
  差异」条款
- merge --no-ff，commit c7a4068，**零冲突**（ort 策略；merge-
  tree 预演先行同为干净）
- 内容：SettingsDetailViews.swift（1641 行）删除，9 文件新建
  （ServerDetail/Profiles/ModelSettings/EnvVars/EnvVarDetail/
  EnvVarEditor/UsageDetail/Gateway/Logs），+1665/−1641，纯搬移
- 中间验收：推送后 CI run 42560749096 success；单测 128——即
  0.4.5 主线自身基线（phase2 分支的 127 是对 0.4.3 旧基线所
  测、其本身零新增测试），合入零漂移

### 31.2 合并二：feat/phase3-hub → 合并结果

- merge --no-ff，commit d1eabdf，**零冲突**（预演同为干净；
  任务预留的「冲突只许出现在工程/测试清单面」未触发，
  ChatView/ContentView/DrawerView 逻辑区零触碰）
- 内容：20 文件 +4117 纯追加——枢纽页本体与四段视图、
  WriteGateClient、AgentHubStore；Core 四模型文件；Hub 四组
  测试；docs/PHASE3-HUB.md；既有文件仅 HermesClient/
  DemoHermesClient/KeychainStore 三处同职责追加

### 31.3 入口接线（主线侧，commit 819f9a8）

- ChatView sheet 呈现内容：NavigationStack{ModelSettingsView
  ＋关闭钮} → **AgentHubView()**（视图自带 NavigationStack、
  ✕ 玻璃圆钮与 drag indicator，不再外包）
- 状态变量 showModelSettings 正名 showHub（声明/绑定/动作
  三处，grep 零残留）
- 身份胶囊 accessibilityLabel 尾段改「打开智能体枢纽页」
- ModelSettingsView 仍有正当入口：设置页 .models 路由＋枢纽
  页模型区参考行，未成孤儿

### 31.4 发版 0.5.0 / build 30（版本源五处）

- Project.swift 四字面量：MARKETING_VERSION 0.5.0／CURRENT_
  PROJECT_VERSION 30／CFBundleShortVersionString 0.5.0／
  CFBundleVersion 30
- **第五源补改（commit 109dd00）**：SettingsView 关于区显示
  串 Text("0.4.5") 是 §30.9 在案的版本源，首轮检索被 head
  截断漏检、发版 CI 已起跑后经 §30.9 记录回查发现——补改后
  旧 run 42561394655 主动取消、以新顶端重跑。此为本批唯一
  偏离点，已当场闭环；教训同 §25.7：版本源以文档在案清单
  为准，不靠临时 grep 全量

### 31.5 追加件：设置页「审批桥钥匙」粘贴一次字段（用户 12:25 拍板，commit 59c1e99）

- 入口：设置页「服务器与连接」组新行（key 图标＋标题＋状态
  词＋chevron，路由 SettingsRoute.writeGateKey），行值只显
  「已设置／未设置」；详情页 WriteGateKeySettingsView
- 交互：未设置＝SecureField 粘贴＋保存（清洗后为空禁用）；
  已设置＝只显「已设置」＋更换＋移除（移除走 confirmation-
  Dialog）；**永不回显钥匙原文**，草稿保存/移除后即清空；
  钥匙值不进代码/仓库/日志
- 读写同键自证：写入/回读/删除与 WriteGateClient 读取共用
  唯一通道 KeychainStore（service site.didichou.oneday）＋
  唯一常量 CredentialKey.writeGateKey＝"writegate.key"，
  grep 全量五处引用同源（WriteGateClient.swift:58 读、
  WriteGateKeySettingsView save/delete/read、SettingsView
  状态回读）；状态一律由保存/移除后的真实回读派生
- 状态纯判定下沉 OneDayCore（WriteGateKeyStatus：resolve/
  sanitizedForStorage），新增 5 单测覆盖未设置（nil/空/纯
  空白）/已设置/移除后回未设置/清洗规则
- 桥侧行为不变：钥匙未粘贴前 WriteGateClient 读不到，审核
  段保持「通道未接通」诚实态（本批未自创任何发放通道）

### 31.6 交付记录（0.5.0 最终包）

- 代码顶端 59c1e99（feat/ia-v3，已推送）；本节为 docs-only
  后随提交，IPA 不受影响
- CI：合并一验收 run 42560749096 success／基础包 run
  42561449602 success（单测 164）／最终包 run 42562070030
  success（workflow_dispatch 以 feat/ia-v3 触发）
- 单测 169（128 主线基线＋36 枢纽页＋5 钥匙状态），全过
- IPA：your_files/oneday-v0.5.0/oneday-unsigned.ipa，
  2,633,563 字节，md5 b993d1d4a84e80ede2be55ddea0824de
- 解包验版：Payload/OneDayApp.app/Info.plist＝CFBundleShort-
  VersionString 0.5.0／CFBundleVersion 30／bundle id
  site.didichou.oneday ✓；二进制 strings 冒烟：AgentHubView/
  WriteGateKeySettingsView/EnvVarDetailView 类型名均在包内
- 未验证（如实标注）：枢纽页五段真机观感与胶囊点开路径、
  活动行点按续聊回落、审核段与生产桥的真实 pending 联调
  （待用户粘贴钥匙＋一条真实待批）、钥匙字段真机粘贴流、
  soul 真回执 fixture——均无自动证据，归用户真机终审

## §32 0.5.1 批（B 案照改两项：流式发布合并节流＋思考折叠单元，2026-11-09）

来源：B 案拆解清单（craft-teardown-checklist.md）照改仅两
条——1.1 流式发布合并节流、4.5 思考折叠单元；冲突 5 条
（4.1/4.2/4.3/4.6/5.1）一条未碰。代码顶端 a8eb43a。

### 32.1 第 1 项：流式发布合并节流（清单 1.1）

- 现状坐实（改前）：ChatView.runStream 每个 SSE 增量
  `accumulated += delta; streamingText = accumulated` 直
  接写 @State 发布、下游零节流；StreamingText 逐增量整
  串重分词＋逐词元视图重排。增量每秒数十次到达时，发布
  频率＝增量频率
- 对方背书：Enchanted 以 Throttler（100ms）合并发布、
  源码注释明言逐条更新 UI 会冻住界面；Fullmoon 每 4
  token 发布、注释带「逐 token 更新约损 15% 生成速度」
  实测账。两家独立同指，OneDay 补此层
- 实现：OneDayCore 新增纯逻辑 `StreamPublishGate`
  （StreamPublishGate.swift）——增量先攒缓冲，满足任一
  条件才发布全文快照：①本轮首个非空增量立即发布（首
  字延迟不被窗口吞）；②距上次发布 ≥ 时间窗；③待发布
  累计 ≥ 字符阈值。收尾/取消 flush 精确发布残余（无
  残余不发），空增量永不发布。时刻由调用方注入单调时
  钟（ProcessInfo.systemUptime），闸不自读时钟
- 参数实测取值：**时间窗 80ms**（简报 50–100ms 带内、
  略紧于 Enchanted 的 100ms，保 StreamingText 词元渐
  显的密度感）；**字符阈值 64 字**（先到为准；中文约
  64 字、英文约 16 token 一簇）；视图侧 ticker **40ms**
  巡查 collectDue（半窗粒度），低速流尾巴增量到期即
  发、不等下一个增量
- 与 StreamFollowGate 分工（互不替代）：发布闸管「何
  时把全文快照写进 @State」（发布频率），FollowGate
  管「已发布全文每新增 ≥40 字放行一次贴底滚动」（滚
  动频率）；串联关系——onChange(of: streamingText) 的
  跟随判定自此只在发布点触发，判定口径未变
- 精确性：落盘与重试判定一律走闸的 fullText（已发布
  ＋待发布拼接），节流只影响呈现频率、永不丢字；冷启
  重试条件由 accumulated.isEmpty 改判两闸 hasContent
  皆空（思考已到亦算已产出，不重发防重复）
- 单测：StreamPublishGateTests 9 例（首增量立即/窗口
  合并/阈值抢先/collectDue 尾巴/flush 精确幂等/取消
  flush 保半截/空增量不发布/fullText 精确拼接/reset）

### 32.2 第 2 项前置核查：Hermes reasoning 到达形态（证据链）

只读查 NousResearch/hermes-agent 源码（GitHub），且专
门对**生产同版 v0.23.0**（tag df17742，我方部署版本）
逐行坐实，非只看 main：

- `gateway/platforms/api_server_openai_routes.py`
  @v0.23.0：流式写出段（L1180–1183）——agent 的
  reasoning 回调增量被打上 `__reasoning__` 标记、在
  SSE 写出时构造成独立帧 `_chunk({"reasoning_
  content": delta[1]})`，源码注释原文：「DeepSeek-
  style delta.reasoning_content (#99552), the field
  Open WebUI, opencode and the Vercel AI SDK render
  as a thinking block」
- 同文件 L837–843 `_on_reasoning`：接的是 agent 的
  `reasoning_callback` 结构化增量，注释明言不用
  「lossy 500-char reasoning.available progress
  preview」；L1050–1053 非流式孪生：整段落在
  `message.reasoning_content`
- `gateway/platforms/api_server.py` @v0.23.0 L54：
  /v1/capabilities 静态旗标 `reasoning_streaming:
  True`——该能力在网关侧默认宣称开启
- `evals/providers/reasoning_shapes.py`：回调语义钉
  死——reasoning_callback 收字符串片段、
  `"".join(callbacks) == expected`，即逐片增量、拼
  接为全文；上游入站字段为 reasoning／reasoning_
  content（agent/transports/types.py 归一为
  NormalizedResponse.reasoning）
- **结论：形态明确——独立字段 `choices[0].delta.
  reasoning_content`（字符串增量），非 <think> 内
  联、非不下发。** OneDay 改前 SSEParser 只解
  delta.content，思考增量被解码静默丢弃。是否真有
  思考帧取决于上游模型（如 deepseek-v4-pro 思考模
  式）；不产思考的模型不发此帧，客户端缺席即无单
  元，天然兼容

### 32.3 第 2 项施工：reasoning 捕获＋折叠单元

- 通道：ChatStreamChunk.Delta 增解 reasoning_content
  → SSEParser 新事件 .reasoning（同帧与正文并存时正
  文优先、思考让位——网关/DeepSeek 均分帧下发、并存
  不发生，让位保正文永不丢字）；HermesClient.
  chatStream 元素类型 String → OneDayCore.
  ChatStreamEvent（.content/.reasoning 双通道），
  DemoHermesClient 同步（只产正文）
- 呈现：新视图 ReasoningBlock（ReasoningBlock.swift）
  ——流式期恒展开：标题「思考中 · Ns」（TimelineView
  0.5s 现算）＋思考原文纯 Text 次级色＋左竖线（hair-
  line）；落盘后默认折叠：标题「已思考 · 约 Ns」，
  系统 Button 点按展开/收起。标题与展开口径走
  OneDayCore.ReasoningPresentation 纯函数（单测 4
  例）；色用 Palette.inkSecondary/inkMuted 字面口径、
  图标 brain（既有图标词汇），左界与气泡正文对齐
  （bubblePaddingH）；思考文本不走 Markdown 解析
  （草稿文本、半截语法风险，与流式纯文本口径同科）
- 计时与落盘：reasoningSeconds＝首个思考增量→首个
  正文增量（未产正文则到流结束）的实测秒数（0.1 精
  度）；ChatEntry 新增 reasoning/reasoningSeconds
  两可选字段（SwiftData 轻量迁移，与 quote 两字段先
  例同型），思考只展示、不回灌请求上下文；正文为
  空的思考-only 异常回复维持旧口径不落盘
- 单测：SSEParserTests 增 4 例（思考行/思考＋空正
  文同帧/同帧并存正文优先/空思考忽略）＋Reasoning-
  PresentationTests 4 例，总数见 32.4

### 32.4 发版 0.5.1 / build 31

- 版本源五处全仓 grep 同改：Project.swift 工程设置
  MARKETING_VERSION 0.5.1／CURRENT_PROJECT_VERSION
  31＋plist 字面量 CFBundleShortVersionString 0.5.1／
  CFBundleVersion 31＋SettingsView 关于区显示串 0.5.1
  （0.5.0 第五源教训，本批先行全量核对无漏）
- 代码顶端 d9b3a87（feat/ia-v3，已推送）：a8eb43a 本
  批主体＋d9b3a87 一行修复（ReasoningBlock 漏 import
  OneDayDesign，首轮 CI 42564426267 因此报错、已闭
  环）；本节为 docs-only 后随提交，IPA 不受影响
- CI：终验 run 42564625905 success（workflow_dispatch
  以 feat/ia-v3 触发）
- 单测 **186 全过**（169 基线＋17 新增：发布闸 9／解
  析 4／呈现判定 4），CI 日志 Executed 186 tests,
  with 0 failures 实查
- IPA：your_files/oneday-v0.5.1/oneday-unsigned.ipa，
  2,667,302 字节，md5 ac67532e0dedd5302c080dc137796046
- 解包验版：Payload/OneDayApp.app/Info.plist＝CFBundle-
  ShortVersionString 0.5.1／CFBundleVersion 31／bundle
  id site.didichou.oneday ✓；二进制 strings 冒烟：
  ReasoningBlock/StreamPublishGate 类型名均在包内
- 红线自查：未做任何截图；0.4.5 推式几何与 Drawer-
  View 零改动（git diff 文件面可证）；未引入任何三
  方库；清单冲突 5 条（4.1 MarkdownUI／4.2 气泡材质
  与助手无泡／4.3 写死 14pt＋semibold／4.6 Splash
  高亮／5.1 逐更新触感）一条未碰
- 未验证（如实标注，归用户真机终审）：流式合并发布
  的实际顺滑度与 StreamingText 渐显观感、思考折叠单
  元真机形态（须用 deepseek-v4-pro 发一条会产思考的
  消息验：思考期展开＋计时、正文到后落盘折叠＋秒
  数）、思考-only 回复不落盘口径的真机表现

## §33 0.7.0 批（旁聊三档全学＋状态行通道口径修正，2026-11-09）

规格＝oneday-design-review/sidechat-research-20261109.md §6 三档草案（用户 15:42 拍板全学）。基线令牌沿 0.6.1 的 OpenMuse 值，本批不做视觉精修（设计线定稿另行照图施工）。

- D1 主线钦定：本地 ChatThread 钦定（标题恒「主聊」）＋服务端以 App 指定 id（`oneday-main-<uuid>` 本地生成持久化）＋title 建线承载（POST /api/sessions，GET 查存→404 才建、服务端改派 id 以回执改存）；冷启落点次序＝抽屉选线程＞待续聊＞主线。抽屉「主线」区置顶单行，无长按菜单（不可归档/删/改名，UI 层约束）。判定纯函数 MainThreadDesignation（Core）＋单测。
- D2 回告入线：总览桥通知经 ReportCardPolicy（Core 纯函数：非主线恒空、主线取未读前 3）在主线消息流末尾呈现为卡——点身跳活动格、点叉走桥 markRead。红线 D4 守住：卡是纯 View，不入 SwiftData、不进发送上下文（上下文只由 sortedEntries 组装）、绝不往 Hermes 会话写任何消息；旁聊页不渲染。
- D3 分区＋标识＋契约：抽屉＝主线区/旁聊区（时间分组沿 SidebarGrouping、行带「旁聊」胶囊标识、聊天页标题行同标识）/其他会话/已归档区/契约文案「旁聊各自独立上下文，记忆与任务全线共享。」。标题管线（M3）＝本地服务端行：改名覆盖表＞SessionTitleResolver 派生；本地行：主线恒「主聊」、旁聊走 send() 首句派生。
- M1 轻保活：草稿文本（切线程存/恢复、发送后空串即删）与滚动锚（atBottom 或首个可见条目 id，切入延迟恢复、best-effort）在 SideChatStore 落 UserDefaults；不做全量挂载，附件不入保活。
- M2 本地归档：归档集合（`local:<uuid>`/`server:<id>` 命名空间键）本地持久化；归档从一切名单隐藏（搜索不捞）、「已归档（N）」区可展开恢复（本地行恢复并打开/可删，服务端行只恢复、服务端本体不动）。服务端名单拉取量 6→20、可见仍前 6。
- M4 分流动作（超越位）：长按消息第五项「在旁聊里接着问」（符号 arrow.triangle.branch 入 MessageActionSymbols）——新建旁聊、以该消息为引用种子（pendingForkQuote 穿过切换清理转入 pendingQuote，引用条文案分流），原线程上下文不带过去。
- 未证实项处置：已建会话改 title 未证实 → 按档内预案走本地覆盖表（commitRenameServerSession 只写 SideChatStore.titleOverrides，不对服务端发改名请求）；建会话回执形态宽容解码 CreatedSession（{session:{…}} 与裸对象两形态，单测把守）。
- 不学项守界：无云端线程、无分支式 /side、无自动命名（标题只有钦定/改名/首句派生三路）。
- 状态行通道口径修正（追加件，用户 16:05 真机截图坐实）：0.6.1 状态只读桥快照——桥 401/抖动即报「联系不上」，与同机刚收到聊天回复自相矛盾。本批改双输入纯函数 OverviewStatusLine.resolve(snapshot:hermesChannelUp:)：「联系不上」只认 Hermes API 通道探活（OverviewBridgeStore 每轮直探 /health，与桥取数独立）；桥挂只降级桥数据（待审批不显示、角标归 0），通道在即「在线」；探活未知退回桥 hermesUp 口径。桥鉴权失败（OverviewBridgeError.noKey/.unauthorized 类型化）回写 AppState.overviewBridgeAuthFailed：设置页「审批桥钥匙」行值位露「桥未连接」、钥匙页加说明行；网络类失败不点旗。单测钉死：桥空快照＋通道正常→「在线」、通道假＋桥称在线→「联系不上」等 8 例。
- 发版 0.7.0 / build 34（版本源五处：Project.swift 四字面量＋SettingsView 关于串）。

## §34 0.8.0 批（P1 聊天富内容，2026-11-09）

规格＝oneday-design-review/full-build-program-20261109.md P1 包（用户 15:23 硬验收项：照片能打开、工具卡片式、文件能打开，不只是雏形）。视觉沿《设计标准》§5.5/§5.7 与 0.6.1 基线令牌，精修归设计线定稿。

- 载荷冻结（先行一步，只读收割）：经 App 同款管理面只读接口全扫现存 20 条会话 160 条消息——tool_calls 30 条/tool 行 31 条；图片消息 1 条（combo-smoke-pro-1109）；文件消息零样本。脱敏 fixture 冻进 Tests/OneDayCoreTests/RichContentFixtures.swift（browser 会话全量＋combo 节选），渲染逻辑全部对 fixture 写单测。未在生产新跑任何 agent 任务造样本（需另行授权）。
- 图片落盘形态坐实：user 正文嵌 "[Image attached at: /opt/data/…/x.png]" 标记；本体经既有 GET /api/files/download 取回实测 200＋PNG 魔数＋字节数与目录清单对账（10,472）。AttachedImageRef（Core）剥标记出路径；ChatEntry.remoteImagePathsData 落盘路径列；缩略经文件通道取回（ServerImageCache 进程内缓存），点开 ImageFullScreenView（UIScrollView 双指缩放/双击/下滑关，系统手势本体）。
- 工具卡管线（Core ToolCards.swift 全纯函数）：SessionMessage 扩解 tool_calls/tool_call_id/tool_name/tool_call_labels；ToolCardBuilder 以 tool_call_id 配对 assistant 调用与 tool 行——真实名优先信 tool 行（间接层行也带真实名，实查坐实），无行时解 tool_call 参数取内层名；ToolCardClassifier 分类（浏览器/电脑/搜索/文件/终端/记忆/技能/视觉/任务/其他）＋中文标题映射（memory/skill_manage 按 operations.action 分）＋参数摘要；ToolResultUnwrap 剥 <untrusted_tool_result>（含免责声明段）并按 result/output/analysis/tools/message 分型，失败只认 exit_code 非 0／success=false。
- 呈现（RichContentViews.swift）：ToolCardView 按 §5.7 骨架（36×36 圆角 9 图标盒按类取 pastel、标题 15/500、失败 chip、结果超 280 字折叠、终端类等宽）；浏览器导航卡另出地址行（结果首行 "Page: 题（URL）" 解析）。ChatEntry.toolCardData 落盘卡 payload，role 恒 "tool"；发送上下文组装先滤角色（只 user/assistant）再取尾 20——卡永不进重放。
- 文件牌（无真样本、按实查路径形态施工，验收标待真样本）：FileRefDetector 从助手正文探测 /opt/data/… 绝对路径＋已知扩展名（URL 路径段、裸文件名、图片标记路径排除）；FileChip 按 §5.5 文件牌原式（sky 底、圆角 16）；点开图片扩展名进图片查看器、其余经 fileData 取回落临时目录走系统 QuickLook，失败走 notice 人话提示。
- 流式工具卡（防御式，未经生产实测）：ChatStreamChunk 解 delta.tool_calls 分片、ToolCallStreamAccumulator 按 index 累积拼装、HermesClient 以 .toolCall 整卡事件下发；ChatView 流中入列呈现（isLive「进行中」）、收尾按毫秒错开 createdAt 落盘在助手正文之前。服务端不下发此分片时恒为空、零影响——待真样本验收。
- 顺带修复（实查出的接线缺口）：HermesClient.chatStream 此前手工拼 role/content 两字段，多模态消息的 image_url parts 在出门前被丢弃——0.6.1 起模型层已落地的发图能力实际从未发出。本批改按 ChatMessage 的 Codable 形态序列化消息体，parts 随请求出门；纯文本形态与旧拼法逐字等价。
- 历史导入改 richItems：工具卡与图片路径随消息落盘呈现；标题仍走旧 importableEntries 口径。滚动锚/轻保活按 entry id 工作、对卡条目无感。
- 发版 0.8.0 / build 36（版本源五处：Project.swift 四字面量＋SettingsView 关于串）。

## §35 0.9.0 批（P2 浏览器 App 侧接线，2026-11-09）

规格＝full-build-program §4.3 打通路径（用户 15:23 硬验收项：浏览器页面可以看到内容、可以接管）；服务端契约＝box-bridge-rollout-20261109.md（盒桥已上线，本批不改服务器）。视觉按《设计标准》§5.7/§7-P2 与 0.6.1 基线令牌：整屏预览 aspect 1.6、圆角 12、接管态顶条 ink 底白字。

- 状态改源：浏览器状态面从 9119 /api/tools/computer-use/status（本机桌面自动化、恒未就绪的错位源）改读盒桥 GET /status。AgentHubStore 的 browserState/loadBrowserIfNeeded/reloadBrowser 整组退役，BrowserHubState 随之删除（ComputerUseStatus 本体保留供设置详情如实标注本机状态）。桥未连接（无钥匙/401）落 BoxBridgeHubState.bridgeUnavailable 露「桥未连接」并回写 AppState.overviewBridgeAuthFailed 旗（同一把钥匙、0.7.0 口径），不许显示成电脑离线。
- 契约模型（Core BoxBridgeModels.swift 全纯逻辑＋单测）：BoxBridgeStatus 按 rollout 形状解码——creditsLeft 当前计划恒 null、只解码不编造（有值才显示额度行）；页面呈现三态 BoxPagePresentation（活读／最后确认＋时刻／无），活读落空只许退 lastKnownPage 且副行带「最后确认于 HH:mm」，不许冒充实时；状态词只对实测原生值给译名（running/hibernated），其余「未运行」。
- 看页面：BrowserFaceView（枢纽浏览器段与应用格「浏览器」页共用一面）呈现盒桥 POST /screenshot 的真实 JPEG（1024×640），点开复用 0.8.0 ImageFullScreenView 全屏查看；轮询＝面可见时 10 秒一轮（状态＋运行中截图），面消失 .task 自动取消（退后台即停）；休眠不自动唤醒（省额度），露「唤醒并查看」手动钮；截图失败且有旧图时明示「显示的是上一张」。
- 能接管：接管态顶条（ink 底白字「接管中 · 智能体已暂停」＋交还钮）——单桌面无锁原语，互斥是产品层约定（施工图 §4.3③）：接管中停自动轮询、不抢图；任务派发层的真暂停随 P3 任务桥联动，本面先立呈现与通道。动作走 POST /act 一动作一回图：点按画面（SpatialTapGesture 取点→BoxCoordinateMapper 换算到截图像素系，letterbox 黑边点按落空不误译）、地址栏前往（BoxAddressText 规范化：裸域名补 https）、输入文字、回车/退格/Esc 三键（键名 Enter/Backspace/Escape 为透传给 computer_act 的通行写法，厂商键名表未冻结——待真机验收校准）。动作失败桥错误原样落行内提示、旧图保留不变黑。
- 客户端：BoxBridgeClient 仿 OverviewBridgeClient（Bearer 只读 Keychain writeGateKey、零新增粘贴；状态 20 秒超时、截图/接管 100 秒——唤醒＋回图慢，nginx 上限 120 秒之内）。BoxBridgeStore 自持于面内（枢纽段与应用页各自实例、只在所属面可见时轮询）。
- 入口：应用格「工具」组新增「浏览器」行（AppsPage.browser），枢纽段 HubBrowserSection 改为直挂共用面；HermesClient.computerUseStatus 端点保留不删（设置详情源）。
- 发版 0.9.0 / build 37（版本源五处：Project.swift 四字面量＋SettingsView 关于串）。

## §36 0.10.0 批（P3 任务：kanban 薄适配，2026-11-09）

规格＝kanban-spike-20261109.md 定案（混合路线：任务执行面直接用 Hermes 自带 kanban 插件、App 只做薄适配；自建任务桥销账）＋full-build-program P3 节。本批只做客户端＋fixture 单测：不碰生产 Hermes 任何写接口，实桥只读联调亦不做；**专属板开通与 review/needs_input 全链真验列为待授权的独立验收轮**。

- 适配层：HermesClientProtocol 增 11 个 kanban 方法，走既有 9119 会话 cookie 通道（performAdmin 的 401 重登同样适用），全部请求带 ?board=oneday 指名专属板（独立 db、与用户 default 板物理隔离）。端点与请求体逐条对 OpenAPI 实查（CreateTaskBody/UpdateTaskBody/CommentBody/ReclaimBody/TerminateRunBody）；响应体未定型，Core KanbanModels 全走 JSONValue 宽容提取（键名多拼写兜底、时间纪元秒/ISO 双认），形状漂移只落空降级不硬崩。启动探针 GET /workflow 校验列集合，缺核心列（ready/running/blocked/review/done）判枚举漂移→只读（KanbanProbe，形状未认出不判漂移）。
- 板未开通态：加载先查 GET /boards 清单，无 oneday 直接落「任务板未开通」ContentUnavailableView（清单取不到时直取板快照、404 才落此态），绝不给假数据；建板属生产写操作、不在本包，另行授权后由服务端线处理（POST /boards {slug:"oneday"}）。
- 任务面转正：活动格枢纽新增「任务」段（HubSegment.tasks，活动模式三段＝活动/任务/审核）。列表按呈现态分组（组序：等你回答→待审批→进行中→失败→已阻塞→排队中→已排期→待整理→已完成），任务卡＝标题＋状态 chip＋最近摘要（latest_summary 优先、result 兜底）＋失败原文行（failed 态）。状态译名逐条照 spike 冻结表：blocked＋needs_input＝等你回答、blocked＋transient＋last_failure_error＝失败、余 blocked＝已阻塞（原因/原文进详情）。
- 详情与证据：KanbanTaskDetailView——头部（状态/执行档案/创建·开始·完成时刻/连续失败数）、说明、结果、最近摘要、证据段（KanbanTaskDetail.evidenceItems：result 置顶＋runs 新→旧＋events 新→旧上限 50＋附件名）、评论段（作者 oneday 译「我」）。待答问题取 block_reason 优先、其次执行方最近一条非人工评论（spike 缺口补法 4），取不到落通用文案不编问题。
- 控制动作（KanbanControlPlan 纯映射＋单测钉死）：新建＝建卡（assignee=default、idempotency_key 由 App 生成）→POST /dispatch 催派→回板确认新卡出现，未确认不关表单；停止＝有 current_run_id 走 POST /runs/{id}/terminate、无则 POST /tasks/{id}/reclaim（无「暂停」——kanban 无此动词，动作集与文案全程无暂停）；继续/重试/打回＝PATCH {status:"ready"}；批准（review 列）＝PATCH {status:"done"}（人从 review 直接 complete 免证据强制，spike 对照 4c）；取消＝运行中先 terminate/reclaim 再 DELETE、排队直接 DELETE（confirmationDialog 确认）；答题＝POST comments（author="oneday"）＋PATCH ready（worker 再派发时上下文注入最近 30 条 comments）。全部动作走 KanbanStore.perform 的回读确认：回板＋回详情后呈现态达预期才算完成（取消＝已消失、停止＝不再运行、批准＝已完成、答题＝已离开等答态），未确认/失败把人话留在卡内 notes，不弹模态、不乐观移除（AgentHubStore.decide 同口径）。
- 接管互斥（施工图 §4.3 客户端半边）：AppState.boxTakeoverActive 由 BrowserFaceView 在接管开关变化时回写（onAppear 只置真不清零，防另一实例冲掉）；KanbanActionPolicy.gate 只闸派发类动作（新建/继续/重试/答题/打回——效果是让 worker 动起来的），停止/取消/批准为收束动作照常可用；被闸动作明示 KanbanContract.takeoverReason。服务端真联动（派发层真暂停）待生产验收轮。
- 演示态：DemoHermesClient 补 kanban 全套样本（板已开通＋运行/待审批/等答/已完成四态任务、详情带评论/事件/运行样本），写方法静默成功口径不变；KanbanStore.createTask 在演示态跳过回板确认（样本不落状态，与既有演示口径一致）。
- 单测：新增 KanbanModelsTests 20 个（257→277）——板快照三形解码＋游标、译名全表、失败翻译、分组序、板清单两形、探针三态、详情问题提取两路、证据拼装序、派发回执、控制计划逐条、动作集（含「无暂停」红线）、接管闸门只闸派发类、只读全闸、创建回执包裹形。
- 发版 0.10.0 / build 38（版本源五处：Project.swift 四字面量＋SettingsView 关于串）。

## §37 0.11.0 批（P4 目标＋P5 点子转正：oneday-bridge 客户端，2026-11-09）

规格＝full-build-program P4/P5 节＋服务端冻结契约（oneday-bridge-rollout-20261109.md，桥已上线验收 36 项全过）。本批只做客户端：基址 https://hermes.didichou.site/api/oneday-bridge（挂当前服务器根、随用户改址走），Bearer 复用 write-gate 钥匙（Keychain 既有字段、零新增粘贴）。

- Core（OneDayBridgeModels）：DTO 按实测样本逐字落形（goal 全形 {id,title,note,milestones:[{id,title,done}],createdAt,updatedAt}、时间 epoch 秒 float；note/detail 缺失或 null 按空串收、里程碑缺失按空表收）；纯派生全收口在此——GoalProgress（x/y 计数＋fraction，0/0 不冒充完成）、GoalPatchPlan（勾选 toggle 与编辑 update 两路组装：PATCH 全量替换、已有里程碑 id 原样带回对齐勾选、新条不带 id 由服务端生成、空标题行先剔除）、请求体收口 make（POST goals/ideas 的可选字段空即不落键）、IdeaTaskPlan（转任务标题/正文组装：详情＋关联目标行＋来源行，目标名解析不到不编名）、IdeaConversionMarks（已转标记本地编解码：排序去重容脏）。
- 客户端（OneDayBridgeClient）：错误口径与总览桥同分法——noKey/401＝桥未连接（钥匙问题）、集合端点 404＝桥未开通（bridgeMissing）、条目端点 404＝记录已不在（recordGone）；失败响应统一 {"error": 人话} 优先透服务端原文（标题为空/目标不存在无法关联等，客户端不猜固定文案）。契约细化对齐：删目标后点子 goalId 由服务端置 null（回读自愈、客户端不留悬空 chip）；POST /ideas 非 null goalId 必须指向现存目标（新建 picker 只列现存目标、提交时服务端再校验）；列表按 createdAt 升序原样呈现不重排。
- 目标格转正（GoalsView/GoalsStore）：列表卡＝标题＋备注一行＋进度条（DataBar 高 4 变体）＋「x/y 里程碑」，无里程碑不画条；详情/编辑＝草稿全量编辑（标题/备注/里程碑 CheckRow 勾选·增删——设计标准 §7 P4 锚：19 方框、勾选 ink 底白勾），保存一次 PATCH 全量替换→回读逐项对账（标题/备注/每条里程碑 id·标题·done）才算成功，未确认人话留行内（KanbanStore 同口径）；新建 POST→回读确认出现才关表单；删除走 confirmationDialog 破坏性确认→回读确认消失才关页（recordGone 按已达目的处理）。桥未连接/未开通态 ContentUnavailableView 如实露（与任务板未开通同形态），零假数据。
- 点子格转正（IdeasView/IdeasStore）：列表卡＝标题＋详情＋关联目标 chip（同批目标列表解析得到才显示）＋创建时间＋动作钮组；新建（标题/详情/可挂目标 picker）；删除走确认（注明不影响已转任务）；**一键转任务**经 P3 KanbanStore 适配层（先探板：未开通如实提示不往下走→IdeaTaskPlan 组装→createTask 建卡催派回板确认），确认成功才落「已转任务」本地标记（UserDefaults，冻结合约无此字段、不硬塞服务端），点子保留在列。
- 占位退役：PhaseTwoPlaceholderViews.swift 删除（点子/目标两占位自 0.6.0 立版至此转正），ContentView 两格改挂真视图。
- 单测：新增 OneDayBridgeModelsTests 12 个（277→289）——实测样本解码两形＋缺字段兜底、进度计数/比例/文案、toggle 全量带 id、update 新条省 id 键＋空行剔除、新建请求可选字段落键口径、转任务计划三形、已转标记往返。
- 发版 0.11.0 / build 39（版本源五处：Project.swift 四字面量＋SettingsView 关于串）。实桥联调归真机首开自验＋后续验收轮（本批不碰服务器）。

## §38 0.12.0 批（P6 监测：客户端先行，2026-11-09）

规格＝full-build-program P6 节＋契约档 monitor-bridge-contract-20261109.md（客户端先行冻结）。**数据源定案＝缺口契约**：实查 Hermes OpenAPI 无 monitor 路由、CronJob 无指纹/快照/结果字段（cron 只能当调度底座，派生不出有变化/无变化/检查失败三分与前后差异）；oneday-bridge 现有路由表只有 /goals、/ideas、/health（服务端原件对账）。故本批只做客户端、**不部署任何服务端件**：桥扩展 /monitors 后本面即转真数据；扩展前集合 404 如实露「监测数据源未开通」。

- Core（MonitorBridgeModels）：DTO 按契约形状落形（monitor 全形 {id,name,target,scheduleText,cronJobId,enabled,lastCheckedAt,lastResult,lastError,unreadChanges,latestChangeSummary,latestChangeAt,createdAt,updatedAt}、change {id,monitorId,detectedAt,summary,before,after,read}、时间 epoch 秒 float；可选字段缺失容缺收、enabled 缺失默认 true）；纯派生全收口——MonitorPresentation（状态分类：已暂停优先→还没检查过→三分 changed/unchanged/failed→三分之外 unknown 不许猜；状态人话单点；未读总数＝服务端计数之和）、MonitorOrdering（未读降序→最近变化降序→创建升序）、MonitorChangeOrdering（检出倒序）、MonitorChangeDetail.rows（摘要＋before/after 有才成行、空串按没存、皆无 hasOriginalText=false 页面明说没保存原文）、markingRead 副本。频率只吃服务端 scheduleText 显示串，客户端不解析 cron 语法（phase3「schedule 全量样本待收」在案口径）。
- 客户端（OneDayBridgeClient 增监测三法）：GET /monitors、GET /monitors/{id}/changes（集合 404＝bridgeMissing）、POST /monitors/{id}/changes/{changeId}/read（{ok:true}）；错误口径与 goals/ideas 完全同分法（noKey/401 钥匙问题、404 分流、{"error": 人话} 透传）。
- 监测面转正（MonitorsStore＋HubMonitorSection＋MonitorDetailViews）：落位＝活动格枢纽分段新增「监测」段（HubSegment.monitors，eye 符号；活动格四段），不双挂应用格。MonitorsStore 状态四分：loading／notConnected（钥匙）／sourceNotOpened（集合 404，标题逐字「监测数据源未开通」）／failed／ready，就绪后刷新失败保持旧数据；标记已读＝POST→本地即时翻已读→回读 /monitors 对账未读数（服务端计数为权威），失败不假装已读。监测卡（设计标准 §7 P6 锚：卡骨架＋状态点＋最近变化行）：状态点五态双通道（色＋文字：有变化蓝/无变化绿/检查失败红/未检查·已暂停·未识别灰）、名称、target、频率·上次检查时刻＋结果、失败原因行（danger）、最近变化行、未读数 badge（0 不显示）、已暂停整卡降调；段头汇总「N 条变化未读」。详情：本体信息（盯什么/频率/状态/最近检查/失败原因）＋变化记录列表（摘要＋时刻＋未读点）；差异页＝摘要＋变化前/后原文块（textSelection，有才显示）＋无原文明说行，打开即标记已读。
- 契约档同时钉死桥实现包口（下包）：POST /monitors（建监测＋指纹基线）、POST /monitors/{id}/check（立即检查落三分＋命中发 overview 通知）、pause/resume（转 cron）、DELETE；检查执行体在桥内（cron 到点触发桥检查逻辑，不另起 worker）。
- 单测：新增 MonitorBridgeModelsTests 14 个（289→303）——契约全形解码两形＋容缺兜底、状态分类（三分映射/已暂停优先/未检查/未识别不猜）、未读聚合、列表排序、变化倒序、差异行组装（有原文/空串按没存）、markingRead 副本。
- 发版 0.12.0 / build 40（版本源五处：Project.swift 四字面量＋SettingsView 关于串）。未验项：桥 /monitors 未上线，列表/详情/已读全链待桥扩展包部署后真机联调；无钥公网探测 /monitors 与 /goals 同为 401（鉴权先于路由，仅证桥活着）。

## §39 0.12.1 批（P6 监测控制接线：桥上线后客户端补控制动作，2026-11-09）

前置：服务端 oneday-bridge /monitors 全套已上线（rollout 记录 oneday-bridge-rollout-20261109.md 监测节：888 行脚本，POST 建监测建基线、check 已暂停回 409、pause/resume、DELETE 连 changes 删、调度在桥内）。本批只补客户端控制动作，不碰服务器；契约 §2.4 的包口至此全数对上。0.12.0 的五态/三分/已读口径原样不动。

- Core（MonitorBridgeModels 增）：MonitorFrequency 三档（manual/hourly/daily → intervalSeconds nil/3600/86400、scheduleText 客户端组人话「手动检查/每小时检查/每天检查」、label 短名）；BridgeMonitorCreateRequest{ name, target, scheduleText?, cron?, intervalSeconds? }（make 工厂收口：去首尾空白、频率档展开；cron 高级档本包不出 UI——字段留口恒 nil 不落键，两者都不给 interval/cron 时桥判手动型）；MonitorCreateValidation.problem（与桥端 400 对齐：名称空/链接空/非 http(s) 三条人话，先拦不发必失败请求，服务端人话仍透传不双轨）。
- 客户端（OneDayBridgeClient 增五法）：POST /monitors（201 全形，集合口径 404＝未开通）、POST /monitors/{id}/check（200 全形；409 走 checkStatus 默认支透传 {"error": 人话}）、POST pause/resume（200 全形）、DELETE /monitors/{id}（{ok:true}，连 changes 删）。回执本体只作参考，成功与否一律以回读为准。
- 控制口径（MonitorsStore，与 GoalsStore 同纪律）：新建＝POST→回读列表确认新 id 出现才算成，未出现留 createError「已提交但还没确认出现」；立即检查＝POST→回读对账（该监测还在且 lastCheckedAt 严格晚于动作前），409 已暂停人话原样落 notes 行内；暂停/恢复＝POST→回读确认 enabled 已翻转；删除＝DELETE→回读确认消失（recordGone 同口径视为已达），成功后清该监测变化缓存防孤儿。actingIDs 只禁用当前条、notes 行内不弹模态、失败原因原文呈现，不许乐观假成功。
- 呈现：新建入口两处（空态 ContentUnavailableView 动作钮＋列表顶「新建监测」行），表单 MonitorCreateView（照 GoalCreateView 骨架：SectionLabel/FieldRow/odGroup＋分段 Picker 三档＋档位说明——手动档只在点检查时跑/自动档先抓基线不算变化；校验问题与 createError 走 InlineError，创建钮校验不过禁用）；行内控制＝卡长按 contextMenu（立即检查/暂停·恢复/删除），删除走段级 confirmationDialog（明示变化记录一并删）；详情页新增控制区（立即检查带进行中转圈/暂停·恢复＋note 行）与删除区（确认后成功即 dismiss）。监测卡增 note 行与动作中转圈（替 chevron）。五态/三分/已读逻辑零改动。
- 单测：MonitorBridgeModelsTests 增 7 个（303→310）——频率档映射（三档 interval/scheduleText/label 件数）、手动档请求体不落 intervalSeconds 与 cron 键、每小时/每天档落间隔与人话串、表单校验三拒一纳（空名/空链接/非 http(s) 拒、http(s) 与带空白纳）。写链真机端到端以桥已上线为准、客户端以 fixture＋回读逻辑验收（本地不发生产写请求）。
- 发版 0.12.1 / build 41（版本源五处：Project.swift 四字面量＋SettingsView 关于串）。

## §40 0.13.0 批（P7 记忆条目桥：客户端先行，2026-11-09）

实查定案（契约档 oneday-design-review/memory-bridge-contract-20261109.md）：读写双缺口。读——Hermes OpenAPI 记忆面只有 GET /api/memory 状态（provider＋文件计数），无条目路由；条目在服务端 memories/MEMORY.md 与 USER.md 内、无逐条时间戳。写——write-gate 桥 POST 只有裁决两条（approve/reject），pending 只能由 Hermes 自己的 memory 工具暂存，外部客户端无任何发起面；oneday-bridge 不共享 /opt/data 卷承接不了；/api/files/read 考虑后否决（根范围未证、条目身份客户端无从诚实生成、与暂存 old_text 匹配语义须读写同源）。契约把新路由组挂 write-gate 桥（独享数据卷、已 import tools.write_approval、裁决同源）：GET /memories（桥经 load_on_disk_store 解析）、GET /memories/{id}、POST /memories/propose（按 memory 工具同形暂存、origin 固定 oneday_app）；审批衔接全复用已上线现成面（/status、/pending、/decisions、裁决 POST）。本批只做客户端，服务端路由组另包部署； App 无任何绕过审批的直写路径（红线）。

- 契约要点：条目 id 内容寻址（mem_＋sha256(原文) 前 16 位十六进制）、digest 全量 sha256、updatedAt 为文件级 mtime（同文件条目相同，呈现按文件时刻口径不包装成逐条时间）；title/summary 由桥生成（首非空行截 60/压平截 120），列表不带全文；propose 三形 create/update/delete 对应 gate payload add/replace/remove，update/delete 带 baseDigest、桥校验闸门未开 409/条目已变 409/条目不在 404；相同原文条目共享 id（与上游按原文匹配语义一致）。
- Core（新增 MemoryBridgeModels）：MemoryTarget（memory/user/unknown 宽容映射＋人话 长期记忆/用户档案/未注明来源＋分组序）、MemoryDigest（CryptoKit sha256 十六进制＋entryID，与桥同算法、客户端只用于回读验落盘与待批匹配）、BridgeMemoryEntry/Detail/两 Response（宽容解码）、BridgeMemoryProposeRequest（create 不落 entryId/baseDigest 键、update/delete 带 digest；工厂三式）＋Response、WriteGateDecisionRecord/DecisionsResponse（已决记录 DTO，decided_at ISO/epoch 双容）、MemoryEntryPresentation（标题兜底 标题→摘要→（无标题）；分组来源序组内不重排；搜索过滤 标题/摘要/来源人话包含匹配）、MemoryProposal＋Status 五态（pending/landed/approvedUnconfirmed/rejected/unresolved）＋Resolution 落定判定（还在待批→pending；驳回→rejected；批准→回读验落盘：create 看新 digest 出现、update 看新出旧消、delete 看旧消；无裁决记录→unresolved 不猜）、MemoryPendingMatching（appOrigin=oneday_app；payload old_text/matched_entry 算 targetedDigest，只认 replace/remove，patch 片段不贴标）、MemoryProposalValidation（空正文拦、update 未改动拦）。
- 客户端（新增 MemoryBridgeClient）：基址 /api/write-gate＋writeGateKey 同钥；entries/entry/propose/decisions 四法；错误沿 WriteGateError（集合 404＝bridgeMissing 未开通、条目 404＝recordGone、propose 409 透服务端人话、401 unauthorized、无钥 noKey 不发请求）。
- 状态面（新增 MemoriesStore，与 MonitorsStore 同纪律）：LoadState 五态（loading/notConnected/sourceNotOpened/failed/ready，已就绪后刷新失败不翻态）；load＝条目回读＋refreshApprovals 尽力链（/status 闸门态、/pending 认领 origin=oneday_app 的记录——本会话提案跟踪＋遗留 externalPending＋逐条 detail 算 targetedDigest 给条目贴待批标、/decisions 对账落定：离开待批的提案按 Resolution 更新状态与行内 note）；propose 三动作（校验→闸门明确关先拦→POST→追加提案→刷新标记；成功只代表已暂存，本地零乐观落定）；详情缓存按需拉全文。
- 呈现（新增 MemoryEntriesViews＋MemoryView 顶部接入）：条目段与状态面同页双数据源互不冒充，加载由 MemoryView 的 task/refreshable 并行驱动。段头「记忆条目」＋新建钮（闸门关禁用）；状态卡逐字「记忆条目尚未开通」/「数据桥未连接」＋重新检查；就绪态＝闸门关提示行＋待批区（提案行 操作·来源＋状态 chip＋note、遗留待批行 displaySummary＋「上次打开时提交的」；统一提示裁决在活动页审批区、本区不设裁决钮）＋搜索框（客户端过滤）＋按来源分组卡（行＝标题＋文件时刻 small＋待批 chip，§7 P7 锚）；空态「暂无记忆条目」。详情页：来源/更新时间 LabeledContent＋文件时刻口径说明、全文（可选文本）、待批提示、编辑/遗忘钮组（有待批或闸门关禁用；遗忘走 confirmationDialog 明示先待批后生效、提交成功 dismiss）。编辑器 sheet：新建分段选目标（长期记忆/用户档案）、编辑目标只读明示不能改；TextEditor 全量编辑＋校验问题行内＋提交钮「提交待审批」＋去向说明，成功才关表单。
- 单测：新增 MemoryBridgeModelsTests 21 个（310→331）——sha256 已知向量（"abc"/空串）＋中文稳定性、条目/详情/已决解码（含缺字段宽容与未知 target）、标题兜底三档、分组序与组内稳定、搜索四命中一空、propose 编码形（create 省略键/update/delete 带 digest）、gate action 映射、校验三拦一纳、payload 匹配（replace old_text/matched_entry/add 与 patch 不贴标）、落定矩阵七例（待批/驳回/新建落定与未确认/修改新旧同在未确认与落定/删除落定/无裁决与未知裁决值未确认）。
- 发版 0.13.0 / build 42（版本源五处：Project.swift 四字面量＋SettingsView 关于串）。未验项：契约三端点服务端未部署、无从联调（本包未碰生产任何接口，连只读 GET 亦未发——定案证据全部来自 OpenAPI 与桥源码一手实查）；files/read 未做联调（否决理由见契约 §1.4，不依赖它）；桥上线后须按契约 §2.4 全链复验（发起→活动格待批卡→批准→回读落盘、驳回→文件不变），且 sha256 口径与 origin 写入方式须在桥实现时各对账一次（契约 §4）。
- 销账（0.13.0 批回填）：顶端提交 8dad79a（main 线，基线 5d6383d 之上）；CI 42604093819 success（构建＋OneDayCore 全测绿，Test Suite 'All tests' passed）；单测 331（310 基线＋21）；IPA 4,074,240 字节、md5 30122bb193dcc399329e0ce2d3ea30cf、解包验 Info.plist＝0.13.0/42、bundle site.didichou.oneday，落 ~/workspace/your_files/oneday-v0.13.0/。

## §41 0.14.0 批（P8 文件屏升级，2026-11-09）

实查定案（OpenAPI docs/hermes-0.23.0-openapi.json 组件 schema＋0.2.1 生产实查）：/api/files 组根被 locked_root 锁死在服务端数据目录 /opt/data（can_change_path=false），列表/读/下载/删除 0.2.x 已接且真通；上传 POST /api/files/upload 是 JSON {path, data_url, overwrite 默认 true}（ManagedFileUpload，非 multipart）、建夹 POST /api/files/mkdir {path}（ManagedDirectoryCreate），无改名/移动端点（不做，注明）；/api/fs/* 是另一套 profile/session 作用域面（含 write-text 裸写），不接。写动作安全面核查：upload/mkdir/delete 同在 9119 管理会话鉴权之后、同受 locked_root 约束，与已上线的删除同一安全面；write-gate 审批只管 memory/skills（P7 已证），文件面无审批门路属服务端既定形态——本批接 upload＋mkdir，全部回读列表对账落定，不新增裸写通道。Box 源缺口：盒桥现只有 status/view-token/screenshot/act 四端点、无文件面（rollout 实查），MCP 侧有 list_dir/read_file 但桥未透出——契约冻结于 oneday-design-review/box-files-contract-20261109.md（GET /files、GET /files/read 挂盒桥、响应与 /api/files 列表同构、路径相对 /workspace、只读无写口、越界 400），客户端按契约建好、404 如实露「电脑文件尚未开通」，桥实现归 P9 或独立小包。

- Core（新增 FileBrowserLogic）：排序（目录优先＋name 升序/modified 与 size 降序、同键名称兜底）、段内搜索过滤（名称不分大小写、空查询原样）、面包屑（绝对版逐级展开＋相对版供 Box 段）、joinPath、文件夹名校验（非空/无分隔/非 ./..）、MIME 推断（扩展名映射、未知 octet-stream）、makeDataURL、上传上限 25MB 原始字节（data_url 膨胀计入说明）、图标盒 pastel 轮换序号（目录 3/图片 0/音频 1/视频 2/文本 1/未分类名称字节和 %4 稳定）。
- 客户端：HermesClientProtocol 增 uploadFile（sendJSON POST、超时 180 秒、回执不解码）与 makeDirectory；DemoHermesClient 同名 no-op（与 deleteFile 先例一致，演示静态样本不回显）。新增 BoxFilesClient：基址 /api/box-bridge＋桥钥匙同源，list/fileData 两法，错误四分（noKey/unauthorized＝桥未连接、列表 404＝notAvailable 未开通、读取 404＝文件已不存在人话、其余 failed 人话）。
- 文件格四段：影音（原网格，搜索联动过滤）、交付物（原聚合＋uploads 产出根标「App 上传」＋段内搜索＋上传钮，落点 /opt/data/uploads 缺失时先建夹再传）、浏览（新目录浏览器：状态驱动路径＋面包屑点跳、排序菜单三键、段内搜索、行＝类型图标盒 pastel 轮换＋名＋大小/时间 meta（§7 P8 锚 LinkRow 式）、目录下钻、文件点开预览、上下文菜单下载/删除、新建文件夹 alert、上传到当前目录；删除/建夹/上传一律回读对账：删除看条目消失、建夹看条目出现、上传看同名条目 size 与本地字节一致，对不上如实报「未确认」）、电脑（Box 段：相对路径面包屑＋同款行，状态四分——未开通逐字露「电脑文件尚未开通」、桥未连接、失败人话、就绪列表；点开走字节预览）。
- 预览深化（与 P1 共用组件、不另造）：FilePreviewView 重作——图片页内显示＋点开全屏 ImageFullScreenView（remotePath 源、与聊天同查看器）；其余类型下载落临时文件走 QuickLookPreview 原生预览（PDF 原生阅读，§7 锚；视频/音频 QuickLook 原生播放，撤自绘 AVPlayer 与内联文本渲染）；工具栏下载/分享保留。Box 文件预览 DataFilePreviewView 同路：图片走 ImageFullScreenView 的 data 源、其余走 QuickLookPreview。
- 上传流（FileUploadControl，交付物/浏览共用）：fileImporter 选件→security-scoped 读字节→25MB 上限先拦→（交付物段）确保 uploads 目录→同名预检（现拉目标目录）→同名确认框（覆盖/取消）→POST upload→回读对账才报成功；全程结果以 notice 人话呈现，不乐观假成功。
- 单测：新增 FileBrowserLogicTests 14 个（331→345）——排序三键（含目录优先与 nil size 垫底）、过滤大小写与空查询、面包屑根/嵌套/越界兜底、相对面包屑、joinPath 双形、文件夹名校验六例、MIME 推断、data URL 前缀＋base64 回环、上传上限边界、tintIndex 类别与未分类稳定性。
- 发版 0.14.0 / build 43（版本源五处：Project.swift 四字面量＋SettingsView 关于串）。未验项：upload/mkdir 未对生产联调（本包未向生产发任何写请求；请求形状据 OpenAPI 组件 schema、落定逻辑以回读对账兜底，真机首传即端到端自验——含上传回执形态、mkdir 已存在目录的服务端行为、upload path 须绝对路径的口径，均以服务端 locked_root 既有绝对路径惯例为准、若首传回读对不上界面会如实报未确认）；Box 段桥未部署、整段未开通为定案预期；改名/移动服务端无端点未做。
- 销账（0.14.0 批回填）：顶端提交 710b36c（main 线，基线 d3f32a8 之上；首提交 66aeee5 的 FilesView 因单次写入截断致 CI 42606769843 失败、be0f553 补齐后半后又因测试辅助 String.init 歧义挂测试步，710b36c 修毕）；CI 42607773218 success（构建＋OneDayCore 全测绿，Test Suite 'All tests' passed）；单测 345（331 基线＋14）；IPA 4,222,678 字节、md5 ba79d287ae708d95d688a2e6cd842381、解包验 Info.plist＝0.14.0/43、bundle site.didichou.oneday，落 ~/workspace/your_files/oneday-v0.14.0/。

## §42 0.15.0 批（P9 智能体电脑屏，2026-11-09）

施工图 P9 四面：Box 状态面（运行/休眠/镜像/额度真数据）、终端命令面（shell 工具代理）、电脑文件面（list_dir/read_file 经桥）、桌面截图面（复用 P2 截图链）；桌面实时流不做原生实现（MCP 工具面无原生流协议，P2 已定案），以厂商 WebView 实时视图＋截图刷新双轨代之。桥侧现状实查：box-bridge 仍只有 status/view-token/screenshot/act 四端点；文件面契约已于 P8 冻结（box-files-contract-20261109.md，桥实现由服务端线并行施工中）；终端面无端点——本批冻结 box-shell-contract-20261109.md（POST /shell {command} 原样透传 MCP shell 工具、{ok, output, exitCode, truncated} 回形、exitCode 第一口径、空命令 400、404 未开通、执行域只在 Box 沙箱内不落宿主机），客户端按契约建好、404 如实露「电脑终端尚未开通」，桥实现归独立服务端小包。本机无钥探 /files 与 /status 同为 401（鉴权先于路由），桥文件面是否已上线本机不可判——客户端 404 未开通/200 真读两态 P8 已就绪，本批不改此口径（未验项）。

- IA 转正：应用格原「浏览器」行升级为「电脑」行（desktopcomputer 图标牌＋副题「云电脑桌面、文件与终端」），AppsPage.browser 改名 computer；落点 ComputerView＝状态头＋分段（桌面/文件/终端）。枢纽活动格浏览器段不变（仍是共用桌面面）。
- 单一事实源（合并/去重）：ComputerView 持有一份 BoxBridgeStore 并注入桌面段——BrowserFaceView 新增 store 注入＋managesLoop/showsStatusCard 两开关，电脑面内关掉其自带轮询与状态卡，状态只在电脑面状态头呈现一处；BrowserView（应用格旧「浏览器」页包装）随之退役删除。文件段＝BoxFilesView 从 FilesView.swift 抽出为独立文件（连同 DataFilePreviewView），文件格电脑段与电脑面文件段共用同一组件、同一四态口径；FileBrowserRow 去 private 为两段共用行。轮询由电脑面统一驱动：状态 10 秒一轮；截图只在桌面段在场且运行中顺带刷新（休眠不自动唤醒、文件/终端段不取图）。接管旗清零责任收归电脑面 onDisappear（接管中离面不许把派发互斥永久挂住）。
- 状态头（§7 P9 锚：桌面卡放大版口径）：状态点＋状态行＋页面标题/副行（活读/最后确认三态不改）＋明细行（名称、镜像、最后保存、额度）。Core 新增派生并全 App 单一口径：imageLine（镜像原文；可更新且目标不同才带「可更新到」后缀）、creditsLine（有真数字给「剩余额度 X」、恒缺时给厂商 creditsNote 原文、不翻译不编造、皆无整行不出——浏览器面状态卡同步改用此派生，原内联拼凑退役）、lastSavedAt（毫秒戳转 Date）＋BoxTimeText.dateTime（MM-dd HH:mm）。
- 桌面段：即 BrowserFaceView 本体（截图整屏预览＋回合制接管＋接管顶条），零另造；休眠空态「唤醒并查看」沿用。
- 实时视图（通道 A）：状态头「实时视图」钮以状态回的 viewUrl 直开 WKWebView sheet（薄包装 VendorWebView，只装载不注入不读内容），页首注明厂商画面与登录可能；连续操作归此面、回合制接管归桌面段，分工写在注文里。
- 唤醒口径：状态读永不唤醒（桥口径不变）；唤醒只走两处手动钮（状态头「唤醒并查看」＝切桌面段＋走截图通道唤醒＋回刷状态；桌面段休眠空态同名钮，P2 既有）。
- 终端段（BoxTerminalView＋BoxShellClient，契约见上）：命令逐条手输、执行才发；历史仅当次会话内存态（离面即弃、不落盘）；每条交换＝codeFill 圆角 14 面（设计标准 §7 P9 锚）＋$ 命令行＋输出原文等宽直出（失败 danger 色＋退出码行、截断明示行）；四态分开（未连接/未开通/就绪/条内失败人话）。Core 新增 BoxShellModels：请求单键编码、回执容缺解码、succeeded 纯函数（exitCode 优先、缺失回落 ok、皆缺不判成功）、outputText（空输出「（无输出）」）、BoxShellCommandText.normalize（只去首尾空白、本体一字不改、空串拦下不发）。
- 单测：新增 18 个（345→363）——BoxBridgeTests +9（imageLine 四例、creditsLine 三例、lastSavedAt 两例）、BoxShellTests 9（全形解码、exitCode 盖 ok、回落 ok、无信号不判成功、空输出占位、缺 output 容缺、截断旗、请求编码单键、命令规范化）。
- 发版 0.15.0 / build 44（版本源五处：Project.swift 四字面量＋SettingsView 关于串）。未验项：桥文件面与终端面均未在本包联调（文件面桥实现并行施工中、上线后文件段自动转真读；终端面待桥小包部署后真机发 uname -a 自验）；实时视图 WebView 内厂商登录态未实测（用户 Google 账号在 WebView 内登录一次为厂商口径）；截图/接管链为 P2 已验链路、本批未重跑生产动作。
- 销账（0.15.0 批回填）：顶端提交 347f7dc（main 线，基线 6d23fa3 之上，一轮绿）；CI 42609292739 success（构建＋OneDayCore 全测绿，Executed 363 tests, 0 failures）；单测 363（345 基线＋18，只增不减）；IPA 4,313,891 字节、md5 51a301f00c33998b324d7bf8d5a0a328、解包验 Info.plist＝0.15.0/44、bundle site.didichou.oneday，落 ~/workspace/your_files/oneday-v0.15.0/。契约档两份在 ~/workspace/oneday-design-review/：box-files-contract-20261109.md（P8 冻结）、box-shell-contract-20261109.md（本批冻结）。

## §43 0.16.0 批（P10 管理面补齐：全功能施工图收官包，2026-11-09）

施工图 P10 五面：技能商店（hub 搜索/预览/安装/卸载＋启停联动）、档案创建/删除/导入导出、会话搜索（/api/sessions/search）、审批已决历史（桥 decisions 端点＋审核段历史行）、MCP 连接管理（servers 列表/启停/测试，Box 行如实显示插件来源）。数据源逐面实查定案：五面端点全在 9119 OpenAPI 在册、无缺面，本包无新桥、无新契约档。只读联调证据（2026-11-09，服务器内存 49%）：/api/mcp/servers 生产实样 {"servers":[…]}，box 行 source=plugin、plugin=box（插件来源有真字段）；/api/sessions/search?q=蓝鲸 生产实样真命中 R1 会话 api-10bbb01cdf42b4a5（results 元素 title/snippet/role/preview/started_at epoch 浮点/message_count 齐）；/api/skills/hub/sources 与 /search 在 30 秒、120 秒两档均无响应（HTTP 000、空体）——服务端抓外部注册表出网受阻，判「端点在册、当前部署不可用」，DTO 做多形宽容、界面如实露慢/失败，不拿空结果冒充没货。能力盘第 27 行的 /timeline、/export 与第 28 行的 /api/mcp/catalog 不在 P10 内容行内，本包不扩。

- 技能商店（新文件 SkillHubViews.swift；技能页顶部常驻入口行）：搜索提交触发（回车/按钮），来源 chips 走 GET /sources（拉不到整组不显示、不编造来源清单）；结果行点入详情——预览 GET /preview（content/skill_md/readme/markdown 四键容缺取全文走 MarkdownText，files 收字符串数组或 {path|name} 对象），内容与文件皆空明说「预览没有返回内容」；安装/卸载 POST 后回读 skills() 名集对账（HubSkill.installedName＝identifier 末段）：出现才标已装、消失才算卸掉，未落定明示「已提交，后台处理中，请稍后在技能列表确认」不假成功；启停联动＝装后即进技能页既有 toggle 链（同一 skills() 数据源、同一回读口径）。hub 三读客户端超时放宽到 120 秒（getJSON/sendJSON 加 timeout 参数），等服务端自己失败也不假装商店为空。商店目录描述是内容不是界面装饰：与技能页「英文不上屏」口径不同，照原文呈现供用户判断装不装。
- 档案补齐（ProfilesView）：顶部新建/导入两钮（.odSecondary，各开一个 Form sheet）；新建＝名称＋复制来源 Picker（clone_from 可选），同名在表单内先拦，POST 后回读列表、名字出现才关表单＋报已建，未出现给未确认提示；行 contextMenu＝切换（非当前）/导出/删除（删除仅非当前且非默认档案，确认框后 DELETE＋回读确认消失）；导出 POST 后以 ProfileExportResult 多键（path/output/archive/file）收服务器路径、展示可选中文本并说明导回路径，没回路径如实说没回、不编造下载链接；导入定案＝服务器路径形态（archive 字段语义无实样证据：导出产物同机导回是真用例，表单明示此口径；手机本地文件无已定义上行通道，不猜 base64、不假装能传文件）。
- 会话搜索（ServerSessionsView）：.searchable（navigationBarDrawer 常驻）＋.task(id: searchText) 防抖 450ms 调 GET /api/sessions/search（limit 30）；搜索态整页切换（「选择」工具钮与批量条隐藏），命中行＝displayTitle（title→preview→「未命名会话」三级回落）＋snippet 带角色（roleLabel 只译 user/assistant，其余不加前缀）＋副行（来源译名与 ServerSession.sourceLabel 同表/模型显示名/开始时间/消息数），点行同正表走 pendingChatSessionID 续聊；空结果与搜索失败分开呈（EmptyState/InlineError）。
- 审批已决历史（HubApprovalSection＋AgentHubStore＋WriteGateClient）：桥 GET /decisions 是自上线就有的现成面（P7 已用它做落定判定），WriteGateClientProtocol 补 decisions(config:limit:)（真实实现复用桥 get()；DemoWriteGateClient 裁决即落账＋预置一条合成已决）；store 在 loadApproval 置 .ready 后 best-effort 拉 50 条（try?、失败保留旧值、不拖垮审批态），裁决成功与 recordGone 后顺手刷新（决刚落账时拉最准）；审核段 ready 态改双 Section「待审批」（原卡片）＋「已决历史」（类别徽章＋结论 chip＋摘要＋来源＋相对时间，结论色与 Core isApproved/isRejected 同判定、不另立词表），待批与历史皆空才走原空态；段头注释同步改 0.16.0 口径。生产 decisions.jsonl 已有 8 条（基线 4＋P7 验收 4），施工图「历史里查到已决记录」的数据源已在服务端侧备好。
- MCP 连接（新文件 MCPViews.swift＋AgentRoute.mcp＋设置「智能体」组新行）：GET /api/mcp/servers 列表——名＋来源 chip（originLabel：插件预置 · {plugin}/手动配置）＋端点行（url 优先、否则 command，等宽单行中段省略）＋transport 译名行（远程连接/本地进程）；DTO 按实样钉字段，args/env/tools 不建模（配置与凭据类不上屏）；启停 PUT …/enabled 沿技能开关先例（乐观更新＋失败回滚＋作废旧测试结论）；测试 POST …/test 结果行内呈现，MCPTestResult.succeeded 只认显式信号（ok 真值或 status∈{ok,success,succeeded,connected,healthy}），皆缺不判成功、不假绿，工具数收 tool_count 或 tools 数组长。本页不做新增/删除：POST/DELETE 形状含完整服务器配置（命令/环境变量等凭据类字段），不在手机裸录、留电脑端。设置行值位只放总数（与技能行同口径），loadSummaries 同步拉取；agentDestination 穷举补 .mcp 一处（已 grep 确认仅此一处 switch）。
- Core 新增 ManagementModels.swift：HubSkill（identifier 末段＝installedName、sourceLabel 首段回落）、HubSearchResponse（results/skills/items 三键＋裸数组四形）、HubSource/HubSourcesResponse、HubPreview（四键容缺＋files 双形）、MCPServerItem/MCPServersResponse、MCPTestResult、SessionSearchHit/SessionSearchResponse、ProfileExportResult、WriteGateDecisionRecord 展示派生（decisionLabel/originText 走既有 WriteGateLabels 译表）。HermesClientProtocol 新增 13 法（hub 5＋档案 4＋会话搜索 1＋MCP 3），真实与 Demo 双实现（Demo 的 MCP 样本照生产实样给 box 插件行＋一条 stdio 手动配置行；hub 搜索/会话搜索在演示数据内按词过滤）。
- 单测：新增 11 个（363→374，ManagementModelsTests）——hub 响应三形解码＋installedName/sourceLabel、sources 双形、preview 四键与 files 双形、MCP 生产实样逐字解码、MCP 测试回执四态（显式 ok/状态词判成、皆缺不判成、工具数双键）、会话搜索生产实样逐字＋displayTitle 三级回落＋role 只译两值、导出回执四键与皆缺为 nil、已决标签派生与 decisions 响应原样解码（decided_at ISO 带 +00:00）。
- 发版 0.16.0 / build 45（版本源五处：Project.swift 四字面量＋SettingsView 关于串，全仓 grep 验无旧版残留、历史注释除外）。未验项：全部写动作（hub 安装/卸载、档案建/删/导/入、MCP 启停/测试）未对生产发请求（纪律：只读 GET 联调），真机首用即端到端自验——施工图验收动作中「搜索命中已知会话」已由联调在服务端侧实证、「历史查已决记录」数据源已备好，其余（真装技能并启停、建测试档案切换后删除）归真机首用；hub 响应形状无实样（端点超时）、profiles import 的 archive 语义、profiles export 回执形状、MCP test 回执形状均按多形宽容实现，待真机首用回填实样后收紧。
- 销账（0.16.0 批回填）：顶端提交 beca9b6（main 线，基线 bffbcef 之上；首轮 CI 42612876523 红——ManagementModelsTests 两处 #"…"# 原始字符串被 JSON 内的 "# 提前截断，改双 # 定界后二轮绿，过程留痕）；CI 42613501820 success（构建＋OneDayCore 全测绿，Executed 374 tests, 0 failures）；单测 374（363 基线＋11，只增不减）；IPA 4,610,343 字节、md5 8f66484dc4a14284ec4f4fb51fd72009、解包验 Info.plist＝0.16.0/45、bundle site.didichou.oneday，落 ~/workspace/your_files/oneday-v0.16.0/。至此全功能施工图 P1–P10 十包全部交付收官。

## §44 0.17.0 批（真机五修：chrome 三病＋侧边栏重做＋四格化，2026-11-09）

来源：用户 2026-11-09 19:51 真机五点名（白块/侧边栏丑/伸缩不稳/去底栏收缩/底栏去活动格）＋19:58 圈注图＋20:01 纠正定准（「底部导航栏下面被盖住一点」）＋Muse 本体侧边栏样板图与暗色对照三图。修法准绳＝全网调研报告 ~/workspace/research_notes/ios26-tabbar-topbar-issues-20261109-1203/report.md（Q1/Q2/Q4/Q6＋§6.4/§6.6，带源）；纪律沿例：不做截图验收、终审归用户真机对照其本人截图。

- 一、底栏落位（本包第一优先）：定因＝TabView 被 DrawerShell 页卡变换整体承载（顶锚 scaleEffect＋offset＋clipShape＋页卡阴影），系统按「容器在屏幕原位」算出的底栏浮动位置被变换层带偏——标签压进 home indicator 区、坞下沿出画（调研 Q1/Q4；0.6.1 已坐实「外层包裹扰动 TabView 安全区」只拆了 GeometryReader 一层，本批拆到底）。修法：DrawerShell 重构为**根级 TabView＋覆盖式抽屉**——TabView 回归根级安放、壳层不给它加任何 modifier；抽屉改自左滑入盖在静止内容之上（调研结构 A），分离感由新设整屏蒙层（DrawerMotion.scrimOpacity，峰值 0.32、随 progress 线性、两端钳制）＋抽屉右缘柔影（§3.4 定值 radius 10、x 改正向落抽屉外侧）承担。**取舍如实记**：推式视觉退役——调研结论是系统 tab bar 正确落位与「整页（含 bar）被变换」不可兼得，按简报「底栏落位正确＋抽屉可用优先」取覆盖形态；抽屉既有行为逐项保留零回退：主线钦定行保护、长按四件（置顶/重命名/归档/删除）、点行换会话并关抽屉、点服务端行续聊、左缘热区跟手开、开态蒙层/抽屉面跟手关、S2 方向锁定、S6 吸附、S5 预挂载/迟卸载、S7 弹簧桥接、开抽屉先收键盘——位移三件纯逻辑（DrawerMotion.followedOffset/settleOpens/isDirectionLocked）零改动、旧单测全过为证。附带删 .tabBarMinimizeBehavior(.onScrollDown) 改 .never 写死（0.4.1 commit 95ab47e 为学 Muse 加的滚动收起，用户下令去掉；调研 Q2 证实最小化只剩左下角单图标胶囊是其设计结果、非 bug）。底栏本体不加任何自定义背景/容器背景，全仓核查无 UITabBarAppearance/toolbarBackground 残留。
- 二、顶栏＋状态栏朦胧感：病根＝身份胶囊是白浮纸（odFloatPaper：实填充＋发丝边、无 backdrop 采样），带内除胶囊外的区域全透明、内容原样透出与胶囊文字相叠（调研 §6.0 第 1/3 种「透」）。注册面核对结果：消息 ScrollView 本人的 .scrollEdgeEffectStyle(.soft, for: .top/.bottom) 与顶/底双 .safeAreaBar 注册自 0.4.3 已在位、本批未动——缺的触发条件正是承载层（变换容器破坏安全区链与效果采样，一并由第一项治掉）。本批落点：胶囊本体换 .glassEffect(.regular)（调研 §6.1：浮件首选档、自带 backdrop 模糊＋明度调整；.clear 档为「让内容透出」而设计、聊天页禁用；.thickMaterial 回退未启用——胶囊文字短、regular 已含可读性调整，若真机仍透，回退路已定：胶囊换 thick 档或顶缘改 .hard，一行级改动）；发送舱本已 .glassEffect(.regular)＋safeAreaBar 注册、不动；顶缘风格维持 .soft 双缘（取舍：.soft 就是用户要的朦胧渐隐本身，.hard 是近不透明锐带、会把玻璃感换成实带，故不预先启用、只作回退）；其余三格（点子/目标/应用）为 NavigationStack＋系统 bar、边缘效果由系统自管、无自定义背景干扰（全仓 grep 证），无需注册动作；自制渐变带/实色补丁/假模糊层核查零残留（E11 已于 0.7.1 注销）；渐进模糊私有 API 未碰（调研定案：无公开 API、系统 scroll edge effect 即官方替代）。
- 三、侧边栏照 Muse 样板重做（DrawerView，功能零回退）：居中病根定因＝名单 VStack 默认居中对齐、无全宽帧的组标题被居中——改左对齐栈＋组标题补全宽左对齐帧（x 线恒 drawerInset 20）；智能体名由 .largeTitle regular 回 0.3.6 立宪的 28 bold（.title＋bold，样板同形态）；会话行两行制（57pt）收敛为**单行制**（47pt 导航行档）：标题＋旁聊标识＋行尾小字时间（弱色 footnote），条数/来源下行（完整副题 LocalThreadSubtitle.text/humanSubtitle 在 Core 与服务端会话页等其他面照旧）；服务端行抽共用 drawerServerSessionLabel（可见行与归档行同型）并补选中浅灰垫（新派生 activeServerSessionID＝当前线程的 serverSessionID，此前只有本地行有当前位呈现）；选中垫形态（selectionFill 圆角整行垫、标题不变色不加粗）、组间发丝线、头尾实色固定条、底条三件套（齿轮圆钮＋搜索胶囊＋新聊圆钮、贴底 safeAreaBar）全保留；四分区数据源（主线/旁聊/其他会话/已归档）、长按四件、搜索行为、缘拖开关零改动。
- 四、抽屉伸缩稳定性：抖源复查定因（结构层）——旧结构下同一变换层（页卡）同时承载 TabView 安全区传递、命中层与手势写入，drawerOffset 每帧写入牵动整卡合成层重排＋安全区重算，慢拖时即表现为帧抖与回跳感（0.7.1 的 S1–S8 只治了位移逻辑层、承载层未动，故真机手感仍不过）。新结构下跟手写入只动两个叶节点属性（抽屉 offset、蒙层 opacity），TabView 子树零参与重算，「状态只落在壳层」（S2）的隔离此时才真正成立；手势仲裁与弹簧参数**未再凭手感调**（S2/S6/S7 原样）。本项定性为结构定因、非真机自证——慢拖跟手/无回跳/无帧跳变的终审归用户真机（见未验项）。
- 五、底栏四格＋胶囊开枢纽：MainTab 删 .activity（聊天/点子/目标/应用），TabBarSymbols.all 钉四格（activity 符号对与 overview/files/settings 同例作数据保留）；ChatView 删 onOpenActivity 切格注入，改 @State showHub——身份胶囊身份域与回告卡点按双入口开 AgentHubView(mode: .activity) sheet（自带导航栈、下滑关），承载与原 ActivityView 逐字一致（同一四段＋onApprovalChanged 刷新总览桥），ActivityView.swift 随活动格删除；全仓改道核查：跳活动格的深链仅上述两处、已全改道，总览页/应用格无跳活动入口，铃铛通知 sheet 原样保留；面向用户文案四处「活动页」改「枢纽（聊天页点顶部胶囊打开）」（IdeasStore 1 处＋MemoryEntriesViews 3 处）。
- Core 与单测：DrawerMotion 新增 scrimOpacity/scrimMaxOpacity（0.32）——+1 测（线性/钳制/全程单调）；SessionDisplay 时间段抽共用 sessionDayTimeText（humanSubtitle 与 LocalThreadSubtitle.text 输出逐字不变、既有单测全过为证），新增 ServerSession.listTimeText 与 LocalThreadSubtitle.timeText 供单行行尾时间——+1 测（与副题首段逐字一致、无开始时间为 nil、三档日期）；TabBarSymbolsTests 钉死期望随四格化更新（同测改期望、计数不变）。单测 374→376，只增不减。
- 发版 0.17.0 / build 46（版本源五处：Project.swift 四字面量＋SettingsView 关于串，全仓 grep 验无旧版残留、历史注释除外）。
- 未验项（真机终审，按纪律如实标注，本包不自证）：①底栏落位——对照用户暗色三图验「坞完整浮置、下方留空、标签不压 home indicator 区」；②顶带/状态栏朦胧感——对照 19:58 圈注图验「内容滚过胶囊与状态栏带时模糊渐隐、不再原样透字」（含状态栏带）；③抽屉慢拖手感——跟手/无回跳/无帧跳变。三项任一不过，按已定回退路逐项收（②的回退：胶囊 thick 档/顶缘 .hard；①③的回退：壳层承载再隔离）。
- 过程留痕：首轮 CI 42616389772 构建已过、单测仅 TabBarSymbolsTests.testTabSymbolPairsArePinned 一处红（五格钉死期望未随四格化更新——施工时漏看该测试文件），改期望后二轮绿；无其他红项。
- 销账（0.17.0 批回填）：顶端提交 5e3dbe9（main 线，基线 96d9c5b 之上，代码提交 2b85f32＋测试修复 5e3dbe9、本节为其后 docs 提交）；CI 42617407872 success（构建＋OneDayCore 全测绿，Executed 376 tests, 0 failures）；单测 376（374 基线＋2，只增不减）；IPA 4,613,030 字节、md5 16fb960d85004a33b84775a9a83be8b1、解包验 Info.plist＝0.17.0/46、bundle site.didichou.oneday，落 ~/workspace/your_files/oneday-v0.17.0/。

## §45 0.18.0 批（A 期内部修订：AI 标题直达＋全部对话管理页＋抽屉四类分区＋kanban 问题原文，2026-11-09）

来源：旁聊全对齐立项档 ~/workspace/oneday-design-review/sidechat-program-20261109.md 的 A 期（差距表、A.3 管理面验收项 A3-V、专题二 AI 命名方案序①）。前提实查（施工首步、带登录态只读）：GET /api/sessions?limit=100 生产真样本 28 条——title 字段在行内、title_source 分布 llm 26 / null 2（null 者即 Qwen 冒烟会话与一条空会话，与专题二「Qwen 标题升级被拒」定案吻合）、archived=only 总数 0、pinned 0 条；0.6.1「接口没有 title 字段」就此更正为客户端误判（当时只解码恒 null 的 display_name）。本批施工期对生产零写请求（纪律）：PATCH/DELETE/prune 只做客户端实现＋fixture 单测，真机首用自验。

- 一、AI 标题直达（专题二方案序①，纯客户端）：Core ServerSession 新增四字段解码——serverTitle（"title"）/titleSource（"title_source"）/isArchived（"archived"）/isPinned（"pinned"）。**标题管线改序**——改前：本地改名覆盖（抽屉）＞本地派生（SessionTitleResolver 拉首条消息摘要）＞display_name＞「未命名会话」，服务端标题从未进客户端；改后（ServerSession.resolvedTitle，全 App 唯一管线）：服务端标题（title_source＝user 手动改名＞llm＞derived 占位，同存 title 字段按来源分级）＞本地派生（contentTitle：首条消息摘要＞display_name 人话名）＞「未命名会话」。消费面全改同源：抽屉行（SessionTitleResolver.title(for:) 改走 resolvedTitle、ensureTitles 只给无服务端标题者拉消息）、管理页行、会话详情页标题（ServerSessionsViews.detailTitle 改 resolvedTitle、「原始标题」元信息改显 cleanedServerTitle）、枢纽活动行与总览（经解析器自动同源）。Qwen 无 llm 标题的回落链按立项档钉死：derived 占位（若有）→本地派生→未命名，**不拿原文首句冒充 AI 名**（派生在呈现上仍是派生层）。真实样本脱敏 fixture 入 SessionDisplayTests（llm「确认链路正常」/user＋pinned/archived/null-Qwen 四行形状逐字钉死）。
- 二、全部对话管理页（A.3，新文件 AllConversationsView.swift＋AllConversationsStore）：抽屉底部「管理全部对话」行（divider＋rectangle.stack＋chevron）→ ContentView .fullScreenCover 呈现（自带 NavigationStack＋「完成」关闭）。分段＝主线／站内／外部／已归档：主线段只摆钦定行（分页拉不到时 GET 单条兜底、无菜单钦定保护、点按打开）；站内段＝archived=exclude 全量减主线（pinned 稳定置顶）；外部段 EmptyState「通道未开通」如实空态；已归档段＝archived=only 全量。数据分页拉全（limit 100/offset 递增、不足一页或达 total 停、上限 10 页防无界）。顶部服务端搜索＝.searchable 复用 GET /api/sessions/search（与 0.16.0 同端点同命中行呈现：SessionSearchHit 轻量行 displayTitle＋snippet、点按打开——不另建第二套搜索实现；应用格旧会话页的搜索面原样保留、本批未动其搜索代码，命中行不另拼四件、四件在分段全量行上）。行长按四件与抽屉共用同一组件 ServerSessionRow（新文件 ServerSessionActions.swift）：顺序固定**重命名／置顶（取消置顶）／归档（恢复）／删除**，改名走组件内 alert、删除走二次确认、进行中禁菜单、失败弹人话原因。多选批量：List 编辑态勾选（编辑态行走原生勾选、常态行走共用组件），站内＝归档＋删除、已归档＝恢复＋删除（删除整批二次确认），逐条经动作层执行、未落定逐条计数汇总呈现。清理区（站内段底部）：prune 两段式——先 dry_run 取将删条数（客户端多键宽容提取 SessionPruneReceipt，取不到数不许进确认、更不许真跑）、确认弹窗明示条数后才真跑、回执条数入结果条并重拉对账。写动作执行层 ServerSessionActions 四法（rename/setPinned/setArchived/delete）：全部经 AppState.performAdmin 走真端点（PATCH /api/sessions/{id} 只带非 nil 字段/DELETE），**回读对账才算落定**（改名对 title、置顶/归档对位值、删除对 GET 应取不到）；并发守卫 expected_revision/generation 不带——施工纪律禁对生产发写探针实测其语义，落定判据只用回读（立项档 O-4 就此定案）。恢复落定后顺手清存量本地归档键。
- 三、存量迁移（一次性，Core 纯逻辑 SessionMigration＋管理页首开执行）：plan＝本地改名覆盖表逐条（id 升序、空白标题不入计划）在前＋本地归档键只收 "server:" 前缀逐条在后；逐项经动作层 PATCH 回写＋回读对账；fold 折叠——成功项从本地退役（setTitleOverride(nil)/unarchive），失败项逐项留痕（「会话 id＋动作名＋人话原因」在管理页各段顶部「存量迁移未完成」区呈现、本地值保留、下次开页再试），不许静默吞。迁移逻辑 fixture 单测钉死（规划序/跳空标题/空计划/折叠留痕/全清五测）。Demo 侧写动作走进程内写回存（DemoSessionWriteStore，进程重启复位），演示态四件可全程点验。
- 四、抽屉四类分区（A-2，DrawerView）：分区改 主线／站内／已归档——原「其他会话」（服务端会话）并入站内（本地旁聊线程时间分组在前、服务端行随后）；「外部」区无 worker 数据整区不显示（本版恒不显示）；已归档区改读服务端本体（loadDrawerData 两路拉取：archived=exclude 20＋archived=only 50，与管理页同源；存量本地键命中者迁移前继续按本地口径藏入归档区、去重合并）。抽屉服务端行改用共用组件 ServerSessionRow（四件全真端点，取代 0.7.0 的本地改名覆盖＋本地隐藏归档＋无删除的旧菜单；归档区行点按＝恢复走 PATCH＋对账）；本地线程长按菜单序对齐为 重命名／置顶／归档／删除。契约文案按类分列：站内「站内旁聊各自独立上下文，记忆与任务全线共享。」＋外部「外部旁聊由分身代你出面、独立档案执行，只向主线汇报，拿不准的会回主线问你。」（立项档 A 期文案表口径）。命名全仓统一「主线」：SideChatStore.mainTitle「主聊」→「主线」（主线线程标题有进页自愈回写、存量自动对齐），残留旧称注释清零（全仓 grep「主聊」仅剩退役注一处）。0.17.0 侧边栏视觉形态（左对齐栈/单行行/浅灰选中垫）零回退；搜索态服务端行不再混入本地搜索结果（服务端搜索归管理页，抽屉搜索回归本地过滤——A.3 抽屉定位口径）。
- 五、kanban 问题原文小修（原 0.16.1 并入）：P3 验收实查定案——task 对象无 block_reason 字段，问题原文在任务详情 events 里 blocked 事件的 payload.reason（及 runs[].summary）。Core：KanbanEvent 新增 payloadReason/payloadKind（解 payload 子字典、顶层 reason 兜底）；KanbanTaskDetail 新增 latestBlockedEventReason/latestBlockedRunSummary/blockDetailText，pendingQuestion 改源（blocked 事件 payload.reason＞blocked run summary＞非人工评论）；task.blockReason 保留宽容解码但加退役注、不再作问题来源。App：KanbanTaskDetailView 元信息行与「等你回答」段改用 detail.blockDetailText/pendingQuestion，详情已到仍取不到如实显「问题原文未取到」、不拿任务标题冒充。fixture 用 P3 验收实案形状钉死（任务 t_e62a9001、blocked 事件 payload={reason:"你的幸运数字是多少？", kind:"needs_input"}、blocked run summary 同文、task 无 block_reason），断言问题原文逐字命中；另钉「有 events 时忽略 task.block_reason」「无事件回落 run summary」两例。Demo 的 demo-ask 任务同步改实案形状（事件 payload＋run summary 同文）。
- Core 与单测：新增 SessionMigration.swift（迁移规划/折叠纯逻辑）、ManagementModels 补 SessionPruneReceipt（prune 回执多键宽容取数、可嵌一层 result、全落空 nil 不编数）。单测 376→387（+11，只增不减）：SessionDisplayTests +3（管线优先序、Qwen 回落链、真实样本四行 fixture 解码）、SessionMigrationTests +5、KanbanModelsTests +2（净增，另改 1 例 fixture 为实案形状）、ManagementModelsTests +1（prune 取数）。
- 发版 0.18.0 / build 47（版本源五处：Project.swift 四字面量＋SettingsView 关于串，全仓 grep 验无旧版残留、历史注释除外）。
- 过程留痕：首轮 CI 42621032578 构建红——AllConversationsView 五处对不上真实 API（Palette.canvas 令牌不存在应为 pageBG、搜索命中型是 SessionSearchHit 而非 ServerSession、pruneSessions 回 Int? 且天数 Double、本地归档退役签名 unarchive(serverSessionID:)），逐处按真实签名对齐后二轮绿；无其他红项。
- 未验项（如实标注）：①服务端四件写动作（改名/置顶/归档/删除）、批量、prune 真跑、存量迁移——**均未对生产发任何写请求**（施工纪律），待真机首用自验（迁移在管理页首开时自动执行、失败留痕可见）；②PATCH 回执形状、prune 回执键名均未实测，回执不依赖（改名等只认回读、prune 条数多键宽容取不到即如实显未回）；③抽屉新分区与管理页视觉终审归用户真机。
- 销账（0.18.0 批回填）：顶端提交 2fa2edc（main 线，基线 3940acc 之上，代码提交 69e7a9c＋API 对齐修复 2fa2edc、本节为其后 docs 提交）；CI 42621459909 success（构建＋OneDayCore 全测绿，Executed 387 tests, 0 failures）；单测 387（376 基线＋11，只增不减）；IPA 4,801,995 字节、md5 d01a65cd9a16eea7af9929a8d25e52e6、解包验 Info.plist＝0.18.0/47、bundle site.didichou.oneday，落 ~/workspace/your_files/oneday-v0.18.0/。

## §46 0.19.0 批（真机五条·二轮：点空白收键盘/抽屉导航化/底条贴底/状态点改绿/标签删除，2026-11-09）

来源：用户 2026-11-09 22:26 装 0.18.0 后发两图点名五条——Muse 本体侧边栏样板图（名字头→「选项卡」组：主要聊天/动态/点子/目标/资源库→「空间」「频道」组→底条齿轮＋搜索胶囊＋编辑圆钮贴底）与 OneDay 抽屉现状图（名单全列＋底条下一大坨死白＋无 home indicator 可见）。纪律沿例：施工期对生产零写请求、不做截图验收、终审归用户真机。

- 一、点空白收键盘（ChatView）：现行已有机制是 0.2.1 起的「内容栈 onTapGesture→composerFocusHandle.dismiss()」＋0.3.5 的帧撑满——真机复发定因＝**只撑帧、没给命中形状**：LazyVStack 的命中测试只认子视图实形，消息行之间的纵向空隙、空状态之外的空白不在任何子视图内，帧再大也点不中。本批给内容栈补 `.contentShape(Rectangle())`，既有手势的辖区才真正等于撑满帧。冲突核对：手势类型与挂点不变（仍只挂内容栈、不挂 ScrollView 本体——发送舱不在辖区内的 0.2.7 口径不动）；子视图（气泡/按钮/链接/图片/长按菜单）仍先命中自己、既有仲裁关系不动；`.scrollDismissesKeyboard(.interactively)`（ScrollView 上、管滚动拖动收起与流式跟随）原样未动。范围核对：点子/目标页的输入都在表单/sheet 内（无「全屏列表＋常驻输入舱」形态），非同病、本批不动——聊天页是唯一落点。
- 二、抽屉照 Muse 重构（DrawerView 整文件重写，964→约 370 行）：结构＝名字头（现行 identityName「Hermes」保留、28 bold）→「选项卡」组五导航行（主线聊天/枢纽/点子/目标/应用：图标与底栏同源 TabBarSymbols 不另立符号表、单行 47pt 导航行档、选中浅灰垫、点行即达并关抽屉；枢纽行＝先切聊天格再经 AppState.hubOpenRequested 请求通道置位、ChatView onChange 消费开枢纽 sheet——枢纽本体不另立第二份承载）→发丝线→「管理全部对话」一行（点按进管理页、不聚焦搜索）。**被删清单**：主线区与主线行、站内区与全部本地/服务端会话行、今天时间分组、已归档区（本地＋服务端）、行尾时间、「旁聊」角标（sideChatTag）、「主线/站内/今天/已归档」分区字、契约文案两行、搜索本地过滤（drawerQuery TextField）、抽屉重命名 alert 与本地线程长按四件、开抽屉两路数据拉取（onChange/onAppear＋loadDrawerData）、DrawerView 的 @Query threads 与服务端行状态两组。接线退役边界：SideChatStore 数据本体、SidebarGrouping 等 Core 纯逻辑、AllConversationsStore、ServerSessionRow 共用组件**全部不动**——管理页数据源与功能全量可用如旧，退役的只有抽屉这一处消费接线。底条搜索胶囊改按钮：点它关抽屉进管理页并聚焦其搜索（AllConversationsView 新增 focusSearchOnAppear 入参＋.searchable 的 isPresented 绑定、ContentView 呈现由 Bool 改 ManageAllRoute 带参），不留假搜索。沿革注记：0.6.1 曾以「与底栏重复」删过同类导航组，本轮用户对着 Muse 样板亲口改令（导航留、名单删），新令覆盖旧裁决、已在 DrawerView 文件头留据。
- 三、抽屉底条贴底（DrawerView＋ContentView）：双计定因——底条下边距是 0.4.5 的手算口径 DrawerGeometry.bottomBarBottomPadding＝壳层量测的窗口底 inset＋4（≈38pt），其前提是推式时代「名单 ScrollView ignoresSafeArea(.bottom) 后 safeAreaBar 代抬消失」；0.17.0 覆盖承载下本条是系统注册 bar（与顶条同结构、无人给顶条手算过、从无此病），bar 内容本就停在安全区线（home indicator 之上），再叠手算＝indicator 段算两遍，真机呈底条下死白一大坨。本批拆手算：下边距改固定 4pt（与注册 bar 时代 0.4.2–0.4.4 落点一致），ContentView 壳层的底 inset 量测与 DrawerView 的 bottomSafeInset 入参一并退役；抽屉面底色 chatSurface 全出血一贯到底缘不变。DrawerGeometry 量测纯函数本体保留作口径档案（DisplayMappingTests 继续把守，本批未删任何旧测）。
- 四、状态点改绿（Core＋OverviewBridgeStore＋ChatView）：定因＝**词与点两源分叉**：状态词走 OverviewStatusLine.resolve 的通道口径（桥挂＋通道在→「在线」），旧点色 overviewStatusColor 却只认桥快照（snapshot 缺失或 hermesUp 假即落 inkMuted 灰）——未粘总览桥钥匙/桥 401 时正是词报「在线」点落灰。本批把判定收敛：Core OverviewStatusLine 内部改单一 classify（offline/pending/online），resolve（词）与新增 tone（语气三态 online/attention/offline）同源派生；胶囊点色改读 OverviewBridgeStore.statusTone：online→Palette.success（系统绿语义）、attention→Palette.warning、offline→inkMuted，其余状态口径不动。其他出现处核查结论（同步一致）：设置页身份头/GatewayView/OverviewView/StatusView 的状态点均走 Palette.stateColor(gateway_state)，其值域 running/stopped 中 running 本已映射 success 绿、无灰点病，不动；CronViews/ServerDetailView 直传 success/danger，不动。
- 五、主线/旁聊标签删除：抽屉侧随名单退役全数消失（分区字＋角标，见二）；聊天页侧删标题行次行的「旁聊」小标识（ChatView sideChatTag 本体＋挂载＋isCurrentSideThread 一并删；isCurrentMainThread 保留供回告卡判定、注释同步改口径）。全仓核查：Text("旁聊")/sideChatTag 零残留；「在旁聊里接着问」等是分流动作菜单文案、非身份标签，不在删除面；**管理全部对话页内分段（主线/站内/外部/已归档）是管理功能、按简报保留不动**。
- Core 与单测：OverviewStatusLine 加 Tone/classify（resolve 行为逐字不变、既有 8 例词用例全过为证）；单测 387→392（+5，只增不减）：OverviewBridgeTests 新增 tone 五例，与词用例逐条对位（桥挂通道在→online、通道假→offline、冷启未知→offline、待审批→attention、桥报 up→online）。名单退役未引起任何旧测删改：抽屉名单的 Core 纯逻辑（SidebarGrouping/DrawerGeometry/分组与量测）本体与单测保留、仅 App 层消费退役；DisplayMappingTests 的 bottomBarBottomPadding 断言（34→38）继续成立（函数未动）。
- 发版 0.19.0 / build 48（版本源五处：Project.swift 四字面量＋SettingsView 关于串，全仓 grep 验旧版字面量仅剩历史注释）。
- 未验项（真机终审，如实标注）：①底条落位——对照样板图验「底条贴底缘、indicator 之上、无死白带」；若拆手算后仍有残段，下一查点已定：壳层 ZStack 分支的 .ignoresSafeArea() 全域忽略与 safeAreaBar 的相互作用；②抽屉新形态观感与导航行手感（点行即达/枢纽行开 sheet/搜索胶囊进管理页且键盘弹起聚焦）；③点空白收键盘的真机命中（尤其消息间空隙与空状态周围）；④胶囊「在线」绿点（桥未连接状态下亦应绿）；⑤0.17.0/0.18.0 遗留终审（顶带朦胧、管理页四件真动作）仍归用户真机一并验。
- 销账（0.19.0 批回填）：顶端提交 89b74d4（main 线，基线 ce98290 之上，一轮绿、本节为其后 docs 提交）；CI 42636446499 success（构建＋OneDayCore 全测绿，Executed 392 tests, 0 failures）；单测 392（387 基线＋5，只增不减）；IPA 4,730,982 字节、md5 ba1ea77ca748f69384883c23feda21e1、解包验 Info.plist＝0.19.0/48、bundle site.didichou.oneday，落 ~/workspace/your_files/oneday-v0.19.0/OneDay-0.19.0.ipa。

### §46 补记：22:45 口径纠正返工（覆盖上文第二、五条，2026-11-09）

用户 22:45 亲口澄清：**正经旁聊必须留在抽屉**，要撤的只是「其他的对话」——Hermes 内部 worker/kanban/验收测试会话与微信/TG 等外部平台通道进来的会话；他自己在 App 里开的旁聊（如「你好」）要留。上文第二条的「名单整段退役」与第五条的抽屉侧全删、第二条内的「搜索跳管理页聚焦」均按本节作废重写；第一/三/四条与第五条的聊天页侧（标题行「旁聊」角标删除）不变。

- 返工后抽屉结构：名字头→「选项卡」导航组（不变）→发丝线→「管理全部对话」一行（不变）→发丝线→**「旁聊」区**：单个分区头＋平铺行（@Query updatedAt 倒序即呈现序），撤「站内」分区字、撤「今天」等分组字、撤每行「旁聊」角标、撤旧「主线」分区头与主线行；行型沿 0.17.0 单行制（标题＋行尾时间＋当前位浅灰垫），点行经 drawerThreadSelection 进会话续聊；长按四件恢复（重命名/置顶/归档/删除，与 0.18.0 本地行同序；置顶只落 isPinned 数据、抽屉呈现恒时间序）。底条搜索改回本地过滤旁聊区（标题＋条目内容，与 0.18.0 抽屉搜索同口径，搜索态只显命中行）；管理页呈现回滚为 0.18.0 的 Bool 形（ManageAllRoute 与 AllConversationsView 的 focusSearchOnAppear/searchPresented 接线全数回滚、该文件对 0.18.0 零 diff）。
- 过滤落法（字段实查在前）：旁聊区名单本体收敛为**本地线程**——决定性事实：ChatThread.serverSessionID 注释与数据双证「本机发起的会话为 nil」，即用户在 App 里新建的旁聊恒为本地线程、根本不产生服务端行；服务端会话整类不单独成行即无误伤。本地线程若关联了服务端会话（从管理页点开导入者），其来源再过 Core 纯函数 **DrawerSideChatFilter.threadListed** 一道（SessionDisplay.swift，+3 单测）：主线/本地归档先撤；linkedSource 为 kanban 或任何非用户通道来源（用户通道集合＝{api_server, api, dashboard, web}，平台源 whatsapp/telegram/feishu/cron 等在其外）撤；无关联或来源未拉到（服务端不可达）恒放行、不藏本人旁聊。服务端侧只拉一路 archived=exclude 会话取 id→source 映射（limit 100），不作名单数据源。
- 28 条服务端会话分类清单（2026-11-09 22:47 只读实查生产 state.db，字段：source/created_source/user_id/origin_json.platform；按 last_activity 倒序；「撤」＝不进抽屉、管理页仍全量可见）：
  1. api-592647b9ae21ec54「友好问候」api_server/31 条——**主线**（活动最新、消息数最多，与钦定主线特征吻合；客户端以钦定 mainServerSessionID 排除、不依赖此推断）→ 不入旁聊区，由导航组「主线聊天」行覆盖。
  2. local-ad7a71d6…「P3TEST review-reject 链验收任务（人工动词） #3」kanban → 撤（source=kanban）。
  3. local-780be318…「P3TEST needs_input 链验收任务 #2」kanban → 撤。
  4. local-9748b88a…「P3TEST needs_input 链验收任务」kanban → 撤。
  5. local-d230d92e…「P3TEST review-reject 链验收任务（人工动词） #2」kanban → 撤。
  6. local-3b4c5706…「P3TEST review-reject 链验收任务（人工动词）」kanban → 撤。
  7. local-c9f402d9…「P3TEST review-approve 链验收任务（人工动词）」kanban → 撤。
  8. local-df0c090c…「P3TEST review-approve 链验收任务 #2」kanban → 撤。
  9. local-e6f6248f…「P3TEST review-approve 链验收任务」kanban → 撤。
  10. api-340bdc44179f0a35「确认链路正常」api_server → 撤（R1 联调会话，0.16.0 会话搜索实证样本）。
  11. combo-smoke-pro-1109 api_server → 撤（模型组合冒烟会话）。
  12. local-1439bc1d…「SPIKE 测试任务（验后删除）」kanban → 撤。
  13. audit-browser-20261109 api_server → 撤（浏览器能力审计联调）。
  14. api-fb632d629e5f76cb「回答 1+1 等于几」api_server → 撤（联调探针）。
  15. api-d7d8b6c7be6afef1「创建 writegate-test-skill-b 技能」api_server → 撤（write-gate 联调）。
  16. api-039936dcfa7844c1「创建 writegate-test-skill 测试技能」api_server → 撤（联调）。
  17. api-aad0ed449e6269d5「添加联调标记到长期记忆」api_server → 撤（联调）。
  18. api-4d1e4d3ff5771ee5「调用 memory 工具写入联调标记」api_server → 撤（联调）。
  19. api-d61e0d8baf68f0a4「介绍自己及背后模型名称」api_server → 撤出抽屉（**元数据与本人会话同构、不可逐条分**，靠兜底信号：无本地线程关联；管理页仍在，用户点开一次即建立关联回归）。
  20. api-4ee003672dbabb7a「你说啥」api_server → 撤出抽屉（同 19，兜底信号）。
  21. api-10bbb01cdf42b4a5「记住暗号蓝鲸42」api_server → 撤（R1 实测联调）。
  22. api-3a6ba0f997d640a5「环境」api_server → 撤出抽屉（同 19，兜底信号）。
  23. api-c960803d32202327「默认正常」api_server → 撤（模型联调）。
  24. api-8e575fab3b3f0565「覆盖测试」api_server → 撤（测试）。
  25. api-f8c59afaec6a5121「一句话介绍西安特色」api_server → 撤出抽屉（同 19，兜底信号）。
  26. api-5f8ad71499cfeda4「一句话自我介绍及模型名」api_server → 撤出抽屉（同 19，兜底信号）。
  27. api-836bf68b0af289e2「Run system info command in box shell」api_server → 撤（Box 联调）。
  28. api-25f140a6575bf25c（无标题、1 条、created_source=null）api_server → 撤（空壳残缺会话）。
  汇总：kanban 9 条字段可分全撤；api_server 19 条＝主线 1（旁聊区外）＋联调/测试/冒烟可识别 13 撤＋同构不可分靠兜底 5 撤。**留**：本地线程全体（不在此 28 条内，如「你好」）——即旁聊区名单本体；平台来源现存为零（Hermes 启用通道数零），规则已按 source 非用户通道预置。
- 返工销账：代码提交 e33dcc6（基线 aba20bc 之上）；CI 42638839390 success（一轮绿，Executed 395 tests, 0 failures）；单测 395（返工前 392＋过滤 3，只增不减）；IPA 已覆盖同路径：4,770,991 字节、md5 c5d0f3169dd4c7927129625965c97ebd、解包验 Info.plist＝0.19.0/48、bundle site.didichou.oneday（**同版本重发，以此包为准，上文销账的 89b74d4 包作废**）。真机终审追加一项：旁聊区只见本人旁聊（「你好」在列、P3TEST/Kanban 类不见）、搜索过滤生效。

---

## §47 0.20.0/49「对标 Muse 三轮」（用户 2026-11-09 23:32 七条＋23:36 思考硬规格＋23:42 切后台定性纠正；基线 e77049b、单测 395 只增不减）

### 47.0 出处与推算口径
本轮尺寸/字号/色值的出处＝用户给的七张 Muse 真机图（抽屉 3、设置 2、资源库 2）＋两张 OneDay 本机截图（发送失败/思考铺屏）。图宽 1320px 对 440pt 逻辑宽、比例 0.333pt/px；锚点：状态栏高约 54pt、底栏坞高、图中已知系统件（状态栏字、home indicator 区）。推算值逐项登记于 47.2/47.6/47.7；拿不准处按量级带落值并在代码注里标明，真机终审时以图复核。

### 47.1 第一条·抽屉底条朦胧（覆盖 0.6.1 定式，brief 明确授权）
- 旧定式：底条走 safeAreaBar 实色注册（Palette.surface 打底），0.6.1 文件头注「不许再挂任何自绘渐变带/模糊层（E11 已注销）」——本条由用户 23:32 新令覆盖该注，E11 注销口径不变（禁的是私有 variableBlur，本条用的是系统 Material 与 glassEffect，均系统件）。
- 落法：DrawerView 根改 ZStack(alignment:.bottom)：名单 ScrollView 忽略底安全区（内容可滚到条下）、其上垫一条 ultraThinMaterial 矩形霜层（高 96、LinearGradient mask 上透下实、只承视觉不承命中）、底条本体留在安全区内（落点仍 indicator 线上方 4pt，与 0.19.0 贴底口径一致）。名单底部补 84pt 避让，末行不停在玻璃下。.scrollEdgeEffectStyle(.soft, for:.bottom) 保留。底条三件本体原已是 .glassEffect(.regular) 真玻璃（0.4.1），本轮不动。
- 顶条维持实色注册不变（brief 只改底条）。
- 自查口径：长名单滚到底，底条后可见被霜层糊住的内容影（真机终审项 T1）。

### 47.2 第二条·抽屉字阶对齐（推算表）
| 元素 | 图中量级（px→pt） | 落值 | 旧值 |
|---|---|---|---|
| 名字头 | 字形 cap 高约 102px→34pt、bold | 34 bold | 28 bold（.title） |
| 导航行题 | 约 60px→20pt、半粗 | 20 semibold | .body 17 |
| 导航行图标 | 约 80px→27pt | 27（槽 30） | 19（槽 22） |
| 导航选中垫行高 | 约 160px→53pt | 行高统一 58（drawerRowHeight） | 47 |
| 旁聊行距 | 约 175px→58pt | 58（同 drawerRowHeight） | 47 |
| 旁聊行题 | 约 60px→20pt、常规 | 20 regular | .body 17 |
| 旁聊行尾时间 | 约 45px→15pt | 15 | .footnote 13 |
| 分区头 | 约 46px→15pt 灰 | 15 medium、inkMuted | .subheadline |
| 底条搜索占位 | 约 54px→18pt | 18 | .body 17 |
| 底条圆钮 | 约 170px→57pt 直径 | 52 不动（登记差 5pt：与搜索胶囊同高联动、0.3.6 实测封存值，改钮必动胶囊高与底栏对齐线，本轮不冒险、终审时用户点名再动） | 52 |
新令牌 OneDayMetrics.drawerRowHeight=58。管理行与导航行同档（27/20 半粗/58、chevron 14）。

### 47.3 第三条·旁聊标题 AI 生成（定因＋修法）
- 现状定因（代码实查）：本地线程 title 只在两处被写——导入时刻快照（SessionHistoryImport.threadTitle，ChatView 约 2190 行）与首条消息发送时的首消息前 20 字派生（ChatView.sendMessage，title==「新会话」分支）；此后服务端会话标题（title 字段、title_source=llm）刷新永不回流。且 ChatThread 此前无手改标记，纵使回流也无从分辨手改名与派生名。断环＝「服务端标题→本地线程显示」整段缺失，抽屉只读本地 title 即永远停在派生值。
- 协议边界（如实）：发送链是无状态重放（/v1/chat/completions 不带会话 id），App 内新建旁聊永不建/链服务端会话（只有主线有钦定服务端会话，见 ensureMainThread）——纯本地线程没有服务端标题可回流，本条只能覆盖已关联线程（主线与导入续聊的线程）；纯本地线程保留派生标题＝v1 缺口，不冒充已解。
- 修法：①ChatThread 加 titleIsManual（默认 false 轻量迁移），抽屉 commitRenameThread 置位（全 App 唯一的本地改名写入点；管理页改名走服务端 ServerSessionActions 通道、不写本地 title）；②DrawerView.loadDrawerData 在既有 source 映射同批保留全量 [id: ServerSession]（drawerServerSessions）；③新 Core 纯函数 DrawerThreadTitle.resolve（手改＞服务端 cleanedServerTitle＞本地），抽屉行/搜索过滤/beginRename 预填统一走 drawerDisplayTitle。列表出现（onAppear 预取）与开抽屉（drawerPresented onChange）都会重拉映射，服务端标题刷新在下次开抽屉即跟上。
- 单测：DrawerThreadTitleTests 5 条（手改不覆盖/服务端压派生/无服务端回落/空白回落/去空白）。

### 47.4 第四条·思考折叠硬规格＋发送失败分型与切后台恢复（23:36＋23:42 两条追加合并销账）
**思考（硬规格五点）**：
1. 有界容器：正文区限高 Core ReasoningPresentation.maxBodyHeight=240pt。锚点口径：iPhone 视高约 730–870pt，三分之一约 243–290，取 240 保守落带内；测试钉 240 且 ≤730/3。区内系统 ScrollView 独立滚动；流式期 defaultScrollAnchor(.bottom) 跟随最新一行＋顶部 18pt 渐变罩（chatSurface 色渐隐、只承视觉）；落盘展开 .top 锚从头读。容器仍在消息列表行内（左竖线＋bubblePaddingH 左界与旧形态同），不溢出行外——图 8BB51F25 里「正文透到输入舱/底栏之下」是无界 Text 在行内无限增高所致，限高后行高有界、该形态消除。
2. 相位默认态（Core ReasoningPhase＋defaultExpanded，单测钉死）：streaming（纯思考期）默认展开；contentStarted（正文/工具卡起流）默认收起；finished（本轮结束与一切落盘条目）默认收起为一行「已思考 · 约 Ns」＋chevron。
3. **历史载入同规**：落盘条目（ChatView 条目行 ReasoningBlock isStreaming=false）相位恒 finished→默认收起，由 defaultExpanded(.finished)==false 单测钉死（用户最刺眼一条）。代码实查附记：0.19.0 落盘路径本已默认折叠，截图里的满屏展开实为流式行在正文起流后仍以 isStreaming=true 恒展开（旧 showsText＝isStreaming||expanded、正文开始不改相位）＋无界生长两因叠加；本轮双修。
4. 两态可点：标题恒为 Button（旧流式期标题非按钮、点不动已改），用户覆盖（userOverride）优先于相位默认、本视图生命周期内保持；动画 .default（与工具卡折叠同口径：头行 Button＋系统动画、无自绘曲线——同构结论：是）。
5. 排版沿旧：footnote 小一号＋Palette.inkSecondary 次级色＋纯 Text 不进 Markdown（草稿文本口径）；流式打字 blur 渐显纪律在正文泡侧、本单元不承载（§14 条 4 落点不变）。

**发送失败分型（23:35 截图一）与切后台杀流（23:42 定性纠正）——同源合并说明**：两条是同一个横幅、两个触发器。横幅文案出自 HermesError.unreachable，旧 HermesClient.mapNetworkError 把 .networkConnectionLost/.notConnectedToInternet 一律塞进「网络不可用＋检查地址是否正确、服务器是否在线」——触发器 A（前台 Wi-Fi/代理路径瞬断）与触发器 B（生成中切后台、系统挂起进程掐断流连接，用户原话「我切换了一下显示有问题了，显示无网络」）在错误层同形、旧文案一律甩锅地址与服务器，与顶栏胶囊走 overview-bridge 轮询得出的「在线」当面打架。
- 代码定因（B）：sendTask 是 ChatView 的裸 Task（约 2293 行建、2506 行清），ChatView 此前不观察 scenePhase——切后台无人记账、回前台无人对账；流一断即走普通失败收尾：横幅报错＋半截回复按正常条目落盘＋failed 触感，回复以错误态收场。
- 分型（Core 单测把守）：HermesError.fromURLError 分型表——瞬断档（timedOut/networkConnectionLost/notConnectedToInternet/cannotConnectToHost/dataNotAllowed/internationalRoamingOff）→新 case .transientNetwork（文案「网络好像断了一下，这条没发出去。等网络稳一点，再发一次试试。」——不提地址）；地址档仅 cannotFindHost/dnsLookupFailed 留 unreachable；其余归 unreachable「网络错误」。HermesClient.mapNetworkError 收敛为只调 Core 分型。isTransient 只认 transientNetwork。
- 再分一层（Core StreamFailure.kind＋wasBackgrounded）：瞬断∧本轮经历后台＝.lifecycleInterrupted；瞬断∧全程前台＝.transient；其余＝.fatal。
- 前台瞬断修法：runStream 的既有重试闸泛化——未产出任何内容（正文/思考两闸皆空）＋未重试过时，瞬断自动重试一次（等 1200ms 再连）；Qwen 冷启重试并入同闸、口径不变（模型限定＋亮唤醒提示）；已产出不重试防重复。
- 切后台修法（对账恢复，reconcileInterruptedStream）：ChatView 新增 scenePhase 观察——离开 .active 且 sendTask 在飞时记 backgroundedDuringStream（runStream 入口按轮归零）。中断轮收尾：不设 errorMessage、不给失败触感，半截内容照旧落盘（进程若被系统回收，回复不凭空消失），记 pendingRecovery（线程 id＋原上下文＋半截条目 ids，仅内存）。回前台（scenePhase→.active 或中断时已在前台的竞态自触发）执行对账：①client.health 探活（只读）——探不通才是真连不上，此时才报真错且注明环节为恢复探活、文案走分型口径；②线程有关联服务端会话（serverSessionID 非 nil）时拉 sessionMessages，取最后一条用户消息之后、本地没有的助手正文补齐（删半截→落完整版，notice「已重新连接，回复已补齐。」＋.success）；③无关联/服务端无此回复——发送链是无状态重放、服务端那次 run 的产物无 id 可按址取回（如实记：Hermes /v1 completions 的生成随请求连接走，客户端断开后不保证落进任何可寻址会话），删半截后以原上下文自动重发一次（用户消息已落盘、重发不新增消息，notice「已重新连接，正在继续生成…」）。发送未达阶段（刚发出未建流）被杀同走此路：本地消息在、上下文完整，对账重发即补齐，不静默丢失。
- 服务端会话历史对本地线程标题的覆盖面同 47.3 协议边界：主线与导入线程可走②，纯本地旁聊走③。

### 47.5 第五条·聊天页撤会话名
撤除清单（ChatView 顶栏区）：①胶囊之下的「会话名次行」整行——已关联线程的 Button(thread.title＋info.circle→会话信息 sheet）与未关联的 Text(线程标题）两分支全撤；②showSessionInfo @State；③其 sheet 承载（ServerSessionDetailView 弹层）。头部只剩身份胶囊行（头像＋名＋状态点＋模型小胶囊）与左右圆钮。会话名只在抽屉旁聊区与管理页出现；会话详情入口经管理页 ServerSessionRow 承接（不失联核查：AllConversationsView 行→ServerSessionDetailView 路径原在）。

### 47.6 第六条·设置页照 Muse 重排
- 形态：呈现改根级 sheet（ContentView .sheet 消费 AppState.settingsSheetRequested，抽屉齿轮置位；0.6.0 pendingAppsPage/AppsPage 通道整体退役）。页内沿原生 List insetGrouped＋navigationTitle 大标题，右上 toolbar 圆形 X（onClose）照图四的左大标题＋圆 X 形态；图五的居中标题变体是 Muse 在另一层级的状态，本页取图五左大标题档登记。
- 规格落值：底 Palette.settingsBG（新令牌，浅 #F2F2F7/暗 #0D1214 派生；图中约 #F2F2F4，差在采样噪声内且与系统分组底同源）；组距 settingsSectionSpacing=28；行 minHeight settingsRowHeight=60；行题 20 regular（双行卡题 20 semibold）；行图标 24 regular Palette.ink（图中约 26–28 黑线形，取 24 保 iconSlot 28 对齐线不漂）；值位沿旧 callout/mono 口径退后；身份卡＝题 20 半粗＋状态点＋副行 host 15 灰（补图中账户卡双行形态，模型副行仍禁——0.4.0 A 案不变）。
- **偏离原生登记**：①卡圆角保留系统 insetGrouped 原生档（iOS 26 约 20–24），图中约 25——差 1–5pt，不为此自绘卡面（全面原生令优先）；②组距 28 与行高 60 是字面覆写系统默认（图为准，理由即图）；③「管理」组三页走 sheet 而非栈内 push（三页各自带 NavigationStack，套栈必乱）。
- 功能映射表（旧位置→新位置，零丢失自查）：
| 条目 | 旧位置 | 新位置 |
|---|---|---|
| 身份头（Hermes＋状态点） | 设置首组 | 设置首组（＋host 副行） |
| 总览 | 应用格内页 | **设置「管理」组**（sheet） |
| 电脑 | 应用格内页 | **设置「管理」组**（sheet） |
| 服务器文件（托管根浏览） | 应用格·文件页「浏览」段 | **设置「管理」组**（sheet） |
| 当前服务器→详情 | 服务器与连接组第 1 行 | 同组（下移至外观之后） |
| 档案 | 服务器与连接组 | 同组 |
| 审批桥钥匙（write-gate） | 服务器与连接组 | 同组（值位口径不变：状态词/桥未连接） |
| 记忆/技能/定时任务/服务端会话/MCP | 智能体组 | 同组同序 |
| 服务端默认模型/密钥/用量 | 模型与密钥组 | 同组 |
| 网关状态/重启网关/日志 | 网关组 | 同组（重启确认弹窗不变） |
| 外观 | 外观组 | 同组 |
| 服务端版本/Hermes 开源项目/Lordicon 署名/隐私组脚注 | 关于组 | 同组 |
| OneDay 版本 | 关于组 LabeledContent 行 | **页脚居中小灰字行「OneDay v0.20.0」**（版本源第五处随之移位） |
| 断开连接 | 独立组（红字红图标） | 独立组（**去图标、红字 20**，照图「Log out」行；确认弹窗与 disconnect() 不变） |
| 深链消费（pendingSettingsRoute/pendingAgentRoute） | onAppear/onChange | 不变（栈 path 机制原样） |

### 47.7 第七条·底栏应用格换文件（交付物库）
- 换代：MainTab.apps→.files（TabBarSymbols.all 第四位改 files 对，TabBarSymbolsTests 同步钉）；抽屉导航行「应用」→「文件」；AppsView/AppsPage/AppState.pendingAppsPage 删除。
- 文件页（DeliverablesView）：顶部身份区＝左圆钮（line.3.horizontal 开抽屉，经 appState.drawerPresented）＋中央 IdentityAnchor 胶囊＋右圆钮（搜索开关，展开 FileSearchField＋FileUploadControl 行、P8 功能不丢）；大分段 [文件｜影音内容] 自制（登记偏离：系统 segmented 约 28 高/13 字，图中约 63 高/22 半粗——落值槽高 60/段字 20 半粗/选中段白面＋轻影，动画只用 .default）；文件行＝FileIconBox（32，共享组件原尺寸；图中约 37，差 5pt 登记、与浏览器行共用不单独放大）＋标题 20＋类型小字 15 灰（Core DeliverableFileType：扩展名大写，单测 2 条）＋行尾 ⋮ Menu（预览/分享两件）；点行进 FilePreviewView（navigationDestination(item:)）；长按菜单保留下载/删除（删除带确认、回读对账沿 P8）。影音段＝三列网格 spacing 2＋MediaCell（视频播放角标原组件自带），点开同走 FilePreviewView。
- **数据来源与交付物定义核对**：沿 P8 产出聚合（见 DeliverablesView 文件头）：/api/files 锁 /opt/data、只扫十个产出根＋根散文件（deny list 剔系统文件）、mtime 倒序、路径去重、≤3 层/600 条上限——这是 Hermes 现有面上唯一的「会话/任务产出」信号（消息附件无文件清单 API、会话工作区无独立产出面）。**为何符合定义**：聚合根全部是智能体干活写出的目录（生成文档/图片/视频/音频/截图/定时任务产出/App 上传），服务端配置与人格文件被 deny list 挡在根散文件之外、各产出根内不含系统文件——进本页的即「做出来的东西」，非服务器全量文件（全量浏览在设置「服务器文件」，两面分工明确）。**v1 缺口（如实）**：①产出与会话无关联字段，来源只标到产出目录级（Deliverable.source 数据层保留、行上按图不显示来源）；②聊天内用户附件是本地 imageData、不入服务端产出面；③cache/scratch「临时产出」与 image_cache/audio_cache 亦在聚合内（P8 口径沿用），可能含中间件——终审若嫌杂，二期按根收紧。
- 应用格功能迁移表（逐项可达自查）：
| 原应用格入口 | 新家 | 可达路径 |
|---|---|---|
| 总览 OverviewView | 设置「管理」组 | 抽屉齿轮→设置→管理→总览（sheet）；其 onOpenAgent/onOpenSettings 深链改道本页栈 path、onOpenChatSession 改道关设置＋pendingChatSessionID |
| 文件（四段页） | 拆解 | 交付物/影音→底栏文件格；浏览→设置「管理」服务器文件；电脑段→电脑页（其文件段本就共用 BoxFilesView） |
| 电脑 ComputerView | 设置「管理」组 | 设置→管理→电脑（sheet） |
| 设置 SettingsView | 根级 sheet | 抽屉齿轮直达（不再经格） |
| 当前服务器行（AppsView 首页行） | 设置身份卡副行＋服务器组当前服务器行 | 同信息两处在设置内 |
| 技能商店（SkillsView 内） | 设置智能体组→技能 | 原即经设置可达，路径不变 |
| 档案 ProfilesView | 设置服务器与连接组→档案 | 不变 |
| MCP | 设置智能体组→MCP 连接 | 不变 |
| 监测 | 枢纽 HubMonitorSection | 聊天页胶囊→枢纽（原即不在应用格） |
| 会话管理 | 抽屉「管理全部对话」 | 不变 |
| OverviewView/ComputerView 的「应用」返回钮 | 文案改「返回」 | 两页现只经设置 sheet 打开，onBackToApps 接 sheet 关闭 |

### 47.8 版本与测试
- 版本源五处同改 0.20.0/49：Project.swift 四字面量（MARKETING_VERSION/CURRENT_PROJECT_VERSION/CFBundleShortVersionString/CFBundleVersion）＋SettingsView.versionFooter 字面「OneDay v0.20.0」（第五处随 47.6 移位），全仓 grep 验。
- 单测：395 基线＋新增（DrawerThreadTitle 5、HermesError 5、StreamRecovery 3、Reasoning 相位/限高 2、DeliverableFileType 2）＝412 口径，只增不减；TabBarSymbolsTests 全表钉随第四格换代更新（apps→files，条数不变）。
- 施工期对生产零写请求（全程只读代码与本地仓库）。

### 47.9 真机终审项
T1 抽屉长名单滚到底：底条后有被霜住的内容影、名单末行不被压；T2 抽屉字阶与 Muse 图并置复核（名字/行题/行距）；底条圆钮 52 与图中约 57 的差是否要点名再动；T3 已关联旁聊（主线/导入线程）标题跟随服务端 AI 名、纯本地旁聊保持派生名（缺口预期内）；T4 思考三态：流式限高区内滚动跟随、正文起流自动收起、打开旧会话思考全收起、展开态限高内读；思考区内滚动与消息列表滚动的手势分配；T5 聊天页头部只剩胶囊行；T6 设置页与图四五并置（底色/卡距/行题/红字行/页脚版本行）、管理组三页 sheet 开合与深链改道；T7 文件页分段/行 ⋮/影音网格与图六七并置、预览与分享真动作；T8 切后台恢复：生成中切走再回——无「无网络」横幅、回复或被补齐或自动续生成；前台 Wi-Fi 瞬断时未产出自动重试一次、横幅新文案不提地址。
- 交付实录：功能提交 b1c9b75＋测试编译修复 65eada9（首轮 CI 42649039602 构建过、测试目标因 HermesErrorTests for-loop 类型标注写法编译失败，改先声明数组后复跑）；CI 42649862975 success，Executed 412 tests, 0 failures（395 基线＋17 新增，与 47.8 预估一致）；IPA 4,790,678 字节、md5 991267ade0a54ad8e71600c263409974、主代理独立解包验 Info.plist＝0.20.0/49、bundle site.didichou.oneday，落 ~/workspace/your_files/oneday-v0.20.0/OneDay-0.20.0.ipa。

## §48 0.21.0/50「旁聊建真会话·标题根治」（用户 2026-11-10 00:07 点选；基线 41f4247、单测 412 只增不减）

### 48.1 立项与技术定案
- §47.3 缺口收口：App 内旁聊（ChatThread）此前走无状态重放、永不建服务端会话——服务端两段式 AI 标题（derived→llm）无从回流、DrawerThreadTitle 管线只覆盖主线/导入线程。本包把旁聊升为真服务端会话，标题、历史归属、切后台恢复一并根治。
- **关键事实更正（探索期实查代码）**：仓库里从来没有 require_model_lock、也没有会话 chat 发送端点——主线现状＝钦定一条服务端会话记录（ensureMainServerSession）＋发送仍走无状态全量重放。故简报「走与主线同一条已验通的建会话路径」的落地形态定案如下（复用主线的通道与纪律、发送机制取研究档实测链）：①建会话复用主线同通道（AppState.performAdmin＋HermesClient 的 /api/sessions POST、服务端改派 id 以回执为准），body 按研究档实测链加 model＋require_model_lock:true（主线建线不带此二键，差异见 48.3 表）；②会话模式发送＝既有 chatStream 加可选 sessionID 参数→请求头 X-Hermes-Session-Id＋payload 只发本轮新消息（研究档两轮记忆探针实测：第二轮只发新问题、答出首轮数字——服务端持上下文成立）；不用 /api/sessions/{id}/chat/stream（OpenAPI 无此路径、事件 schema 未验、且只收纯文本装不下图片 parts）。主线默认 sessionID=nil、请求形态逐字不变（简报第七项「只复用不重构」）。
- **施工纪律执行**：全程对生产零写请求——未在生产建任何会话、未发任何写请求；链接状态机全部 fixture/mock 验（Core 纯函数单测），真链接只发生在用户装机后自己的发送动作里。

### 48.2 链接状态机（OneDayCore.SideChatLink，新增文件）
- 相位：未链接（serverSessionID 空＋失败计数 0）→链接中（瞬时相，单次发送内的建会话请求在飞、ChatView 任务内持有不落盘）→已链接（serverSessionID 非空，派生时压过历史失败计数）；链接失败→失败留痕相（linkFailed(attempts)），仍按未链接计划发送、下次发送再试。相位由持久字段纯派生（phase/phase(afterAttemptSuccess:)/phase(afterAttemptFailure:)），转移函数有单测钉。
- ChatThread 新增三字段（均带默认值、SwiftData 轻量迁移，同 titleIsManual 先例）：linkFailureCount、linkLastError（失败留痕）、linkedModel（链接时落锁的模型；导入线程为 nil）。
- 发送定形在 ChatView.prepareSendShape（send 起手、流开始前）：计划由 SideChatLink.sendPlan 定（主线恒 legacyReplay；已链接旁聊 .session；未链接 .linkAndSeed），载荷取形由 SideChatLink.payload 定。链接窗口内用户按停止：不进流、不记失败留痕、按停止语义静默收尾。

### 48.3 与主线路径的复用/差异表
| 环节 | 主线（不动） | 旁聊（本包） |
|---|---|---|
| 建会话通道 | performAdmin（401 静默重登）＋POST /api/sessions | 同一通道、同一客户端家族（新增 createLinkedServerSession） |
| 建会话 body | {id: oneday-main-<uuid>, title: 主线} | {id: oneday-side-<uuid>, model: 建时胶囊, require_model_lock: true}，**不带 title**（占住标题位会挡两段式 AI 标题自生） |
| id 落点 | SideChatStore.mainServerSessionID＋确认为准 | ChatThread.serverSessionID（回执 id 为准，同口径）；linkedModel=建时胶囊、失败计数清零 |
| 发送 | /v1/chat/completions 全量重放、无会话头（**本包零改动**） | 已链接：同端点＋X-Hermes-Session-Id 头、payload 仅本轮新消息（引用拼装/图片 parts 在全量上下文尾条备好后取尾条）；种子轮：全量载荷＋会话头 |
| 模型锁 | 钦定会话无确认锁（现状） | 建时 require_model_lock 落确认锁；胶囊改选且 linkedModel≠胶囊时发送前 best-effort POST /api/sessions/{id}/model 推一次（成功才更新 linkedModel、失败旧锁继续生效不挡发送）；导入线程 linkedModel=nil 永不代推（SideChatLink.needsModelRelock 钉） |
| 失败回退 | 建线失败静默、下次进页重试 | 建会话失败不挡消息：回退无状态重放整份发出＋linkFailureCount/linkLastError 留痕、下次发送再试；用户主动停止不算失败 |
| 恢复 | serverSessionID 在→补齐分支 | 同一分支（路线判定收敛 Core StreamRecovery.route，见 48.5） |
| 删除 | 主线不在抽屉删除面内 | 抽屉删本地线程→关联会话 PATCH archived:true（见 48.6） |

### 48.4 存量懒链接与种子轮载荷形态
- 存量未链接线程下一次发送自动懒链接（与新建旁聊首发同一条 .linkAndSeed 路）：先建会话，成功后本轮为**种子轮**——载荷＝既有全量重放成品（最近 20 条 user/assistant、引用经 MessageQuote.outgoingContent 拼装、本轮带图时尾条为多模态 parts），另加 X-Hermes-Session-Id 头；落 id 后下一轮起转会话模式（仅新消息）。纯本地从未发送过的线程不动作（链接只由发送触发、无后台主动建会话）。
- **种子轮未决风险（如实记，零写纪律下不可实证）**：服务端对「会话头＋全量 messages」的落库粒度（整段存入 vs 只存末轮）未验——模型当轮必见全上下文（载荷自带），落 id 后会话自种子轮起累积；本地 entries 恒为显示真源，抽屉/历史呈现不依赖该结论。用户真机首轮使用后可在管理页核对该会话 message_count 是否异常膨胀，若整段重复落库则下一包改「种子轮只发尾条＋历史由本地承担」口径。

### 48.5 恢复路径升级
- 路线判定从 ChatView 内联条件收敛为 Core 纯函数 StreamRecovery.route(linkedSessionID:)（completeFromServer/resendLocal，两分支单测钉），判定口径与 0.20.0 内联条件逐字等价：已链接先拉服务端历史补齐、拉不到本轮回复仍落重发兜底。
- 旁聊链接后自动升补齐分支（此前本地旁聊恒无 id、只能重发）；PendingStreamRecovery 新增 sessionID——已链接线程落重发兜底时按中断轮原形态续发（原载荷＋会话头），不退回无状态另起炉灶。导入线程的 R1 未验注就此结案改写（续聊回合按实测链回写同一会话）。

### 48.6 删除语义
- 本地线程删除点全仓唯一＝DrawerView.deleteThread（核查结论：AllConversationsView 不持有本地线程、管理面删的是服务端会话本体，口径不变）。删前快照 serverSessionID，本地删除先行，关联会话随后 PATCH archived:true（尽力而为）：成功顺手销留痕账；失败不阻塞本地删除、会话 id 落 SideChatStore.failedArchiveSessionIDs 留痕账（该会话在管理页未归档段仍可见、可手动归档收尾；clearFailedSessionArchive 供对账销账）。

### 48.7 标题刷新触发点（全集）
服务端 llm 标题在首轮回复后数秒升级，触发点四路：①开抽屉（drawerPresented onChange，0.18.0 既有）；②壳层预挂载 onAppear（0.7.1 既有）；③**App 回前台**（0.21.0 新增 DrawerView scenePhase onChange→loadDrawerData——此前注释自称含回前台、实则无此触发，本版坐实）；④**已链接旁聊一轮完整落地**（0.21.0 新增：ChatView runStream 收尾顶 AppState.drawerRefreshTick，即时一次＋6 秒延迟一次兜 llm 升级时延；抽屉未挂载时由①②兜底）。解析口径不变：手改名（titleIsManual）＞服务端标题＞本地派生（DrawerThreadTitle，0.20.0 管线零改动、仅文件头补 0.21.0 闭环注）。

### 48.8 版本与测试
- 版本源五处同改 0.21.0/50：Project.swift 四字面量＋SettingsView.versionFooter「OneDay v0.21.0」，全仓 grep 验（余下 0.20.0 字样均为历史注释）。
- 单测 412＋19＝431：新增 SideChatLinkTests 17（相位派生 6＋id 格式 1、发送计划 3、载荷取形 3、模型重锁 1、验收组合「链接状态→标题解析」三态 3——未链接恒派生/已链接＋llm 到手取 AI 名/手改名恒手改名）＋StreamRecoveryTests 恢复路线 2（已链接补齐/未链接重发）。演示客户端 createLinkedServerSession 恒抛错（演示走失败留痕＋重放回退、会话头永不进演示请求）。

### 48.9 真机终审项
U1 新建旁聊聊两轮：抽屉里该旁聊名从首消息派生名变为服务端 AI 名（发送完成回抽屉或等数秒）；U2 旧线程（0.21.0 前建的本地旁聊）续聊一轮后标题同样跟上（懒链接生效）；U3 已链接旁聊生成中切后台再回：走补齐路径（notice「回复已补齐」或自动续生成）、不整轮重发；U4 已链接旁聊里换胶囊模型再发：回复模型随新选（重锁生效、无报错横幅）；U5 抽屉删一条已链接旁聊：管理页已归档段出现该会话；U6 新建旁聊首轮带图发送：图片照常发出（种子轮多模态不回归）；U7 管理页核对新旁聊会话的 message_count（48.4 种子轮落库粒度观察项）。
- 交付实录：功能提交 c36d3cb；CI 42653353346 success，Executed 431 tests, 0 failures（412 基线＋19 新增，与 48.8 预估一致）；IPA 4,813,686 字节、md5 f193ecb6cc4b8b3248238169aedd86f9、解包验 Info.plist＝0.21.0/50、bundle site.didichou.oneday，落 ~/workspace/your_files/oneday-v0.21.0/OneDay-0.21.0.ipa。
## §49 0.22.0/51「视觉审计收官·对图对齐」（用户 2026-11-10 00:09 冷开点名＋00:25 审计 36 条 P0/P1 选包＋00:29 抽屉并排图追加＋00:30 设置图实测规格追加；基线 0157e1f、单测 431 只增不减；规格总源＝visual-direction-audit-20261110.md＋native-ios-design 技能）

### 49.1 冷开首屏压字（审计 C1，用户实机图）
- 定因（代码层）：顶栏/发送舱以 safeAreaBar 注册，其顶 inset 在首帧布局后才落定；ScrollView 初始 contentOffset 按未落定 inset（≈0）算出，首行贴画框顶缘、右上角让铃铛钮盖住。此后长线程靠条目数变化的贴底跟随（isNearBottom 默认 true）顺带按已落定 inset 重钳 offset、病被掩盖；短线程内容不可滚动且无等效再钳事件，压字定格。内容栈 minHeight 的 listViewportHeight 首帧为 0 同属首帧未落定一环（只管高度不管 offset）。
- 修法（ChatView messageList）：新增 `.task(id: currentThreadID)`——无存量滚动锚的线程（SideChatStore.scrollAnchor 为 nil、恢复链不接管者）出现 80ms 后、用户未上翻（isNearBottom）时无动画 scrollToBottom 一次，以已落定 inset 重钳 offset。短线程首行落顶栏下方、长线程仍开底部、流式跟随零回归（跟随链未动）。

### 49.2 底栏纯图标化（审计 T1，用户亲点对标 Muse）
- 实现：ContentView.tabLabel 加系统 `.labelStyle(.iconOnly)`＋显式 `.accessibilityLabel(pair.title)`——公开 LabelStyle、非自绘借道，与原生令相容；标题文本仍留在 Label 内，VoiceOver 名实双保险（构造核查：四格无障碍名＝聊天/点子/目标/文件，与原文字标签同名）。tint 维持.primary 定案：选中段深浅由系统按 tint 派生、无官方单独调浅开关；去标签后段内只剩字形、观感随之变浅，改灰 tint 会连字形一起变灰、与 Muse 黑细字形反向，故不动。
- 知情登记：HIG tab-bars（apple-design-skill 内置页）推荐带标签，本项为用户以 Muse 为参照的知情产品选择。
- 字形选形（探针实测，24pt 紧致密度 regular→light）：message .270→.222、lightbulb .340→.288、checklist .296→.272、tray .383→.329——符号全不换、字重统一降 light 一档（字体直接钉在 Label 的图上随图进宿主构建，与 0.4.3「子树环境到不了构建处」是两回事；底栏呈现终由系统介导，落档以真机终审 V3 并排为准）。审计密度带 0.10–0.24 系 17–18pt 小字形口径（FrameworkIcon.inkDensityTarget 注已补），24/27pt 下任何 outline 候选 regular 都在带外（.27–.41），操作口径改「同尺寸 light 档读数」；量测闸回填 testTabBarSymbolInk（24 light，格口径 ≤0.12/紧致 ≤0.42 两闸不变、实测 0.063–0.093/0.222–0.329）。

### 49.3 文件页去污（审计 F1 四层准入）
- 第 0 层产出根十→七：cache/scratch（临时产出）、image_cache、audio_cache（下载缓存）退出交付物面（设置「管理」服务器文件仍可达）。
- 第 1 层形态拦截（全来源，Core DeliverableAdmission）：隐藏文件全拒；内部后缀.db/.db-wal/.db-shm/.sqlite/.sqlite3/.etag/.lock/.pid/.tmp 拒；内部主干 {state, gateway_state, channel_directory, models_dev_cache, kanban, sessions, auth, config} 拒（主干＝去扩展名后全等匹配，kanban-guide.md 类正名不误伤）。
- 第 2 层根散白名单：扩展名集＝办公（pdf/doc/docx/xls/xlsx/ppt/pptx/pages/numbers/key）＋文本（md/txt/rtf/html/htm/csv）＋包（zip/7z/tar/gz/epub）＋媒体（png/jpg/jpeg/gif/webp/heic/mp4/mov/m4v/mp3/wav/m4a/aac）；json 不在集内（gateway_state.json 双保险被拒）。
- 第 3 层旧 deny 名单（.env/config.yaml/auth.json/SOUL/USER/AGENTS/MEMORY/IDENTITY.md）保留作第二道——.md 在白名单内，人格文件靠它挡回；产出根内不查白名单（来源本身即策展信号）、只过形态拦截。
- 拒收样本单测钉死：用户 00:12 实机 9 名（kanban.db-shm/state.db-shm/state.db-wal/gateway_state.json/kanban.db-wal/channel_directory.json/state.db/models_dev_cache.etag/models_dev_cache.json）＋形态变体与白名单进出两侧。
- 类型图标 v2（审计 F2，Core DeliverableIconStyle 表驱动，FileIconBox 36pt/圆角 9/白字形）：docx/doc＝W 白字 #2B579A、ppt/pptx＝P #C43E1C、xls/xlsx/csv＝X #217346、pdf＝doc.richtext.fill #D92D20、md/txt/rtf＝doc.text.fill #5B6B7A、html＝safari.fill #1473C8、压缩包＝archivebox.fill #6E777D、图片＝photo.fill #2E7D4F、视频＝film.fill #6A4FD0、音频＝waveform #C77400、目录＝folder.fill、未知＝doc.fill #949B9F（非文字用途）。旧 pastel 类别轮换退役出文件行（FileBrowserLogic.tintIndex 本体与旧测保留）。如实记：图片在文件段列表不出现——影音段 MediaCell 已是真缩略图面，图标盒图片字形仅作回落口径。
- ⋮ 命中域（审计 F4）：32→44pt（字形 18 不变、行高 64 可容纳）。

### 49.4 身份同源（审计 F3/H2）
- IdentityAnchor 新增 avatarImage 注入位（默认 nil 回落 sparkles 占位）：资产在 App bundle、OneDayDesign 无资源目录，注入是审计给的两条路之一。消费面三处同源：聊天页胶囊（既有）＋文件页＋总览页（本版注入同一 SangouPartner 资产、28pt 圆形裁切）。

### 49.5 抽屉三件（审计 G1/D2＋用户 00:29 并排图）
- 弱灰换档：旁聊行时间戳与分区头 inkMuted（#949B9F，实算 2.75:1）→inkSecondary（4.84:1）；本包只动抽屉这两处，inkMuted 就此只留非文字用途，其余面归 0.23.0。
- 名字头：34 不动（0.20.0 推算锚只定字号）、字重 bold→semibold 降一档——参考图「三狗」同为大标题而笔画克制，SF bold 拉丁字面近黑体级为压人来源；取舍在此登记。
- 节奏复量（像素实测，用户并排图 1206×2622）：OneDay 行距 120px/58pt；线前留白 OD 管理位 8＋12=20pt 为名单唯一双线孤岛 vs 参考图同位约 12pt 同档——撤管理行自带顶距 12、线前留白归一 8pt。线→旁聊头 OD ≈12pt vs 参考 ≈24pt（OD 更紧、非病）、头→首行两边同为 0.52–0.54 行距——余皆已核不动。
- 导航图标（27pt 紧致密度 regular→light）：message .267→.217、list.bullet .352→.290、lightbulb .328→.283、checklist .300→.266、管理行 rectangle.stack .353→.294——字重统一降 light、符号不换。两个否决记录：目标位参考图的方框勾形 checkmark.square 实测 .412（light .338）为全部候选最浓，与「细线感」目标反向、否决，checklist 同为框勾线家族且密度低一档；枢纽 list.bullet 无更轻的同义候选（rectangle.stack .353 同档），细线感由字重达成。FrameworkIcon.drawerGlyphSize 18→27 追认现行；量测闸回填 testDrawerSymbolInk（27 light、旧闸 0.05–0.45 继续有效）。
- 诚实边界：抽屉下半空是用户旁聊只有两条的真实状态、非版式问题，不拿假内容填；「空间/频道」是 Muse 产品概念，OneDay 无对应物，不硬造。

### 49.6 设置页对图对齐（用户 00:30 实测规格，原审计 S2/S4 提前）
- 大标题：navigationTitle 显式加.navigationBarTitleDisplayMode(.large)——sheet 内 automatic 档在小高呈现时可能被压成行内小字，显式钉死与大标题版参考图（34 bold 左对齐＋X 右上导航层）同形态。
- 行题字重：20 semibold 两处（身份卡题「Hermes」、当前服务器题）→regular，全页行题统一 20 regular 单一字重（重启网关与两条外链行题由.body 17 同步归队）；强调只靠位置不靠加粗（参考图账户题即 regular）。
- 行尾值位整件撤除：参考图导航行只有题＋chevron。撤除清单——档案名、记忆/技能/定时/会话/MCP 五计数、默认模型名、「环境变量」描述词、今日 Token 读数、agent.log、外观档名（值各自进详情页：档案页/各模块页/模型页/用量页/日志页/外观页内勾选）；连带退役：7 个摘要管理请求（打开设置请求面回到 status 1 个）、ValueStyle 值位组件与等宽 numericText 读数。状态两行走新 statusNavRow 降为题下副行 15 inkSecondary：审批桥钥匙（已设置/未设置/桥未连接——0.7.0「桥连不上要一眼看到」定案保住）、网关状态（运行中/已停止/异常）。
- 小字清查：本页下限 15——关于组脚注 13 footnote＋inkMuted→15＋inkSecondary、消息行 13→15、外链字形 13→15、管理行 chevron 14→15、版本行颜色 inkMuted→inkSecondary（15 不变）。
- 行图标：24→28 regular（参考图约 28–30 细线字形；槽 iconSlot 28 不变、对齐线不漂）；量测名单换现行 17 件、闸按 28pt 重新校准（FrameworkIcon.settingsGlyphSize 17→28 追认现行）。
- 分区头：本地 settingsHeader 15 regular inkSecondary 无大写化（参考「你的账户」≈15 灰）；共享 SectionLabel（footnote 13）是全 App 旧档、归 0.23.0 角色表统一，本包不动它。
- 行距已核：settingsRowHeight 60 vs 参考 pitch 约 62，差 2 在量测噪声内，不动。

### 49.7 不动项与顺延
- §14 十条、MotionTokens、0.21.0 SideChatLink 状态机与发送链、设置页 0.20.0 形态骨架（sheet＋分组卡）零改动。
- 顺延 0.23.0：字阶全面回文本样式（审计 G2 十角色表）、其余面 inkMuted 文字清查、图标三源统一（G3 余项）、设置卡圆角（S3，1–3pt 不自绘定案）、抽屉底条圆钮 52 vs 约 57（D3 终审对图再定）。

### 49.8 版本与测试
- 版本源五处同改 0.22.0/51：Project.swift 四字面量＋SettingsView.versionFooter「OneDay v0.22.0」，全仓 grep 验。
- 单测 431＋10＝441：DeliverableAdmissionTests 6（9 污染名拒收/形态变体/隐藏文件/根白名单进出/根内免白名单）＋DeliverableIconStyleTests 4（办公三色/媒体回落/目录与未知/大小写与复合后缀）。两轮施工：第一轮 442 测（含临时探针 1）红在 testSettingsSymbolInk 两条闸——28pt 下 cable.connector 紧致密度实测 0.631（紧致盒仅 9pt 宽、读数被窄盒放大，其格口径 0.092 反为全列最疏；旧闸按 17pt 校准），按实测全集（0.252–0.631）重新校准：防实心闸 0.55→0.68（仍低于 .fill 件 0.72 量级）、离散闸 2.5→3.0 并点名该件形态离群，设置列格口径闸 0.10→0.32（实测最大 0.229）；第二轮定版删除探针、回填底栏/抽屉 light 口径断言后 441 全绿。

### 49.9 真机终审项
V1 冷开短会话（1–2 条消息）：首条气泡完整位于顶栏下方、右上角不被铃铛钮盖；V2 冷开长会话仍开在底部、流式跟随不回归；V3 底栏四格纯图标观感（段深浅/字形粗细对 Muse 并排）＋VoiceOver 抽查四格读名（聊天/点子/目标/文件）；V4 文件页首屏应全是真交付物（db/wal/state/cache 类零出现）、docx/xlsx/pptx/pdf 图标可辨识、⋮ 好点；V5 文件页/总览页头像与聊天页胶囊同一张；V6 抽屉名字头观感、导航图标粗细对参考图并排、时间戳/分区头可读性；V7 设置页：大标题形态、行题不再有粗细两档、导航行无右值小字、状态两行副行在位、行图标大小、分区头 15 灰。
- 交付实录：第一轮提交 611b85e（CI 42656901969，442 测 2 失败——即上条设置列闸校准问题，构建本身通过）；定版提交 2ded189；CI 42658735147 success，Executed 441 tests, 0 failures（431 基线＋10 新增，与 49.8 一致）；IPA 4,830,694 字节、md5 a1109e0a4654de3cd85ef447debc4f60、解包验 Info.plist＝0.22.0/51、bundle site.didichou.oneday，落 ~/workspace/your_files/oneday-v0.22.0/OneDay-0.22.0.ipa。施工期生产零写请求；未自截真机图。

## §50 0.23.0/52「整机视觉定向收口」（视觉审计 36 条剩余项整包；基线 2f6f515、单测 441 只增不减；规格总源＝visual-direction-audit-20261110.md＋native-ios-design＋SwiftUI-Agent-Skill 两技能；证据分级：【官方】HIG/SDK 事实【实算】WCAG 公式与渲染量测【定版】用户既往拍板【启发】审计建议）

### 50.1 字阶角色化（审计 G2＋D1/S1/F/I1/M1/H1）
- 新建双层：Core `TypeRole`（十角色的样式名/默认 pt/字重档对账面，单测钉）＋Design `FontRoles.swift`（Font 扩展落 SwiftUI 形态）。十角色：screenName＝largeTitle.semibold（34；审计原表 bold、0.22.0 用户定版 semibold 覆盖，【定版】）／rowTitleL＝title3（20）／rowTitleLSemi＝title3.semibold（20）／rowTitle＝headline（17）／bodyText＝body（17）／rowSubtitle＝subheadline（15）／meta＝subheadline（15）／metaMonospaced＝subheadline 等宽变体／sectionLabel＝subheadline.medium（15）／captionText＝footnote（13）／badgeOnly＝caption（12，仅徽标）。
- 五面＋管理页逐面落：抽屉（名→screenName、旁聊题→rowTitleL、时间→meta、分区头→sectionLabel、导航/管理题→rowTitleLSemi、搜索字 18→bodyText【启发：审计 D1 许 body 或 searchText 角色，取 body 不新开角色】）；设置（行题→rowTitleL、副行→rowSubtitle、版本脚→meta、host→metaMonospaced、分区头→sectionLabel、身份卡题→rowTitleL 与全页单字重口径不变）；文件（分段→rowTitleLSemi、行题→rowTitleL、类型小字→rowSubtitle）；聊天（思考正文/头行→captionText、引用块名签 caption2→caption【G6】）；总览（会话行升内容行档：题 .body→rowTitle、副 .footnote→meta；其余 .body/.footnote/.subheadline 等值改名 bodyText/captionText/rowSubtitle；平台错误说明 caption→captionText【H3】）；管理页（会话行题→rowTitle、副→meta、全页 footnote 说明→captionText）。
- 共享组件同批：SectionLabel footnote 13 regular→sectionLabel 角色（15 medium，全 App 分区头统一【S4】；设置本地头字重 regular→medium 归一登记）；ContentRow/UnifiedRow 题 .body→rowTitle（与组件自注「行内唯一半粗位」对齐）、副题 footnote 13→rowSubtitle（15）、尾元 footnote 等宽→metaMonospaced（15）；ListRowSpec.subtitleSize/metaSize 13→15 随角色改值（DisplayMappingTests 断言随规格改值、非删测）。
- 映射不了逐项登记（保留值＋理由）：总览大数字 .title（28）/指标值 .title2（22）＝展示数、非行文，角色表无展示档，保留语义样式（本就随 Dynamic Type）；总览微标签 .caption（今日 Token/内存占用/指标名）＝与大数字成对的微标签、非阅读说明，保留；总览空态行 .callout（16）＝无等值角色（body 17/callout 16 差 1），保留；引用块说话人名签 .caption（12）＝微标签同组登记；聊天正文 .callout（16，0.4.4 §29 定版基准）不动；工具卡小字 .caption 为审计自评「基本自洽」面，保留。

### 50.2 灰度收敛（审计 G1＋C4）
- inkMuted（#949B9F，实算 2.75:1【实算】）退出一切文字位：全仓逐处分类（Text 前景＝文字位、Image/Shape/状态点＝非文字位），文字位 59 处换 inkSecondary（4.84:1），含共享组件 ContentRow/UnifiedRow 副题与尾元、管理页全部状态/说明行、抽屉空态提示、枢纽各段的时间/说明、日志元信息等；两处三元色（EnvVars 未设置态、StatusView 停用态下次时间）随之塌缩为 inkSecondary 单值。Palette inkMuted 注记改「只许非文字用途」。
- 清零证据（交付 grep 口径）：`grep -rn "Palette.inkMuted" Sources` 余 58 处，逐类为——chevron/箭头/搜索/清除等字形前景、StatusDot 与 stateColor/decisionColor/tone 等状态色返回值、quote 竖线/TypingDots 等 Shape 填充、双色符号次色、EmptyState 装饰图标、目标删除线色（装饰线）、已读点填充。无一处落在 Text 前景上。
- C4 落点：新增 Palette.inkSecondaryOnFill（浅 #5F666B＝在 #EEEEF0 上 5.04:1【实算，公式自证复算 5.035】；暗派生 #9AA3A8＝在暗泡 #272E33 上 5.36:1）。全仓实查填充面上的次级文字仅一处真落点——ServerRemoteImage 失败标签（inkSecondary 字落 bubbleFill 背景，4.29:1）已换新角色；quoteBlock 经代码核查位于气泡背景之外（VStack 内、气泡填充只包正文块），不属 C4 面、维持 inkSecondary（在页面底 4.84:1 达标）。

### 50.3 图标令牌单源化（审计 G3）
- 单源＝Core FrameworkIcon：新增 tabGlyphSize 22／navGlyphSize 21／rowGlyphSize 20／fileGlyphSize 17 四角色（值与旧源逐项同值）；连既有 drawerGlyphSize 27／drawerBarGlyphSize 17／settingsGlyphSize 28／composerGlyphSize 15 共八角色成全表。OneDayMetrics.navGlyph/tabGlyph/rowIconGlyph 改引用单源（别名保留、数值退役）；ListRowSpec 字号字段改挂 TypeRole（见 50.1）；HeaderButtonSpec（直径 40/字形 20/比 0.50）为几何规格、非字形令牌第三源，维持原位并在此对账（字形 20 在 glyphSizeRange 带内）。
- 消费点回填：抽屉导航/管理字形字面 27→FrameworkIcon.drawerGlyphSize（light 定版不变）；设置 rowIcon 字面 28→FrameworkIcon.settingsGlyphSize；FileIconBox 单字 17→FrameworkIcon.fileGlyphSize。字重分位维持 0.22.0 定版（底栏/抽屉 light、设置 regular），本表只管尺寸。

### 50.4 顶栏圆钮玻璃化（审计 T2）
- 聊天页左右圆钮（汉堡/铃铛）白浮纸 odFloatPaper→.glassEffect(.regular, in: Circle())，与同排身份胶囊同族；文件页 headerCircleButton 同步同改。视觉盘恒 HeaderButtonSpec.diameter 40 不变；chrome 定案不动（safeAreaBar 注册路径、私有 variableBlur 零碰、E11 不复活）。回到底部圆钮维持白浮纸（非顶栏件、0.3.8 浮件统一画法的现行件，只补命中域，见 50.5）。

### 50.5 命中域补齐（审计 C2/C3＋全 App 逐面审计）
- 补齐（视觉尺寸全不变、两层帧外扩，CopyButton 既有款式）：思考头行 minHeight 44【C2】；工具卡「展开结果」钮 minHeight 44【C2 同批】；引用条 ✕ 28→44【C3】；回告卡 ✕ 24→44；错误/提示条 ✕（无帧）→44；顶栏圆钮 40→44（聊天左右＋文件页两钮）；回到底部钮 34→44；附件移除钮 17→44（offset 补偿 13.5 保字形中心同位）；抽屉底条搜索清除钮→44（胶囊高 52 容纳）；目标页两处 minus.circle 行内删除钮→44；枢纽编辑钮 36→44、图片查看器 ✕ 36→44；总览状态卡头行 minHeight 44。
- 登记豁免（不达 44 但不动，逐项理由）：发送舱两键 30＝ComposerLayout 定版几何（胶囊总高 46 用户定版，扩键即推翻发送舱定版）；枢纽页头两枚 36 玻璃钮＝.buttonStyle(.glass) 系统件＋L1 样板定版，系统件命中由系统样式管理；审批段 bordered/borderedProminent 钮＝系统控件尺寸；主按钮高 42＝OneDayMetrics.primaryButtonHeight 的 OpenMuse 定版值（差 2）；搜索字段内清除钮（FileSearchField/LogsView/MemoryEntriesViews 三处）＝行内清除字形、受字段行高所限，外扩会侵占相邻控件命中，随系统文本框清除钮惯例登记；系统件全体（List 行/toolbar/tabBar/contextMenu/系统 segmented 以外的系统控件）由系统保证。

### 50.6 小字与 Light 清零（审计 G6）
- 9pt：胶囊 chevron 两处（ChatView 模型 Menu＋Components 身份锚）→.caption2.weight(.bold) 字形角色（默认 11 视觉当量、随 Dynamic Type）。
- 11pt：引用块说话人名签（文字）caption2→caption（见 50.1 登记）；工具卡链接字形 11 字面量删除（随行文走 caption 档）；工具卡「进行中」caption2→badgeOnly、「失败」徽标 caption2→badgeOnly.weight(.medium)；目标勾选勾字形 11→12。
- Light 字重（文字位）：聊天空态图标 26 light→regular【审计 G6 明列】。图标字形 light 定版不动（底栏/抽屉，0.22.0 探针定版）；Components EmptyState 装饰图标 34 light 为字形位、审计未列，保留。
- 残留口径：全仓 .system(size: 9/10/11) 余 FilesView 面包屑 chevron 10 与 BoxFilesView 同件——皆分隔字形、非文字，登记保留。

### 50.7 三设置检查（代码层＋单测闸，零截图）
- 新闸 VisualDirectionGateTests（+6 测）：①TypeRole 十角色样式名/默认 pt/字重逐项对账；②Dynamic Type 真缩放——ImageRenderer 离线渲染五角色文字于 .large 与 AX3 两档、断言高度增长 >20%（固定号字体在此现形）；③对比度实算——Palette 色经 EnvironmentValues（浅/暗两色貌）resolve 后以 Core WCAGContrast 复算：ink/inkSecondary 对 pageBG、inkSecondaryOnFill 对 bubbleFill，浅暗共五对 ≥4.5；inkMuted 对 pageBG <4.5 危险钉；④WCAG 公式自证对审计原值（4.84/2.75/5.04 复算命中——5.04 为第二轮以 CI 实测 5.035 校准施工估值 5.2 后的定版）；⑤TransparencyFallback 裁决两分支；⑥图标单源对账（OneDayMetrics 三别名＝FrameworkIcon 同值＋八角色定版值）。
- 减透明落点：系统玻璃（glassEffect）由系统回退【官方】；自制霜层（抽屉底条 Material＋渐变 mask）的淡出段不受系统回退管辖——DrawerView 经 TransparencyFallback 裁决加实色分支（Reduce Transparency 时整幅 Palette.surface、无 mask）；其余自制材质面全仓 grep 仅此一处（scrim 为带 alpha 的纯色纱、非材质面，不入列）。
- 暗色＋增对比：颜色全走 Palette 动态色（浅/暗成对），对比闸已含暗色对；Increase Contrast 下系统色与玻璃由系统加深【官方】，自有令牌无单独分支、登记为系统托管。

### 50.8 不动项与顺延
- §14 十条、MotionTokens、SideChatLink 与发送链、ComposerLayout 发送舱几何、0.22.0 全部定版落值（底栏/抽屉字形 light、设置行高 60/图标 28、抽屉槽 30/行高 58）零改动。
- 审计在册未纳入本包任务单：D3 行垫圆角 14、D5 底条玻璃去描边、G5 分组面宽层差、S3 设置卡圆角、F5 文件页迁 List、M2 留痕区 errorSurface 底、C5 聊天空态文案——均为 P2、留待后续包或用户点名。
- 版本源五处同改 0.23.0/52：Project.swift 四字面量＋SettingsView.versionFooter「OneDay v0.23.0」，全仓 grep 验。
- 单测 441＋6＝447（预估，实测以 CI 为准）：新增 VisualDirectionGateTests 6 测；既有断言改值 1 处（DisplayMappingTests ListRowSpec.subtitleSize 13→15，随 I1 规格改值、非删测）。

### 50.9 真机终审项（W 系列）
W1 大字号（设置→辅助功能→更大字体拉满）：抽屉/设置/文件/管理页/总览五行随之放大、不断行溢出（0.22.0 前三面纹丝不动为旧病）；W2 默认字号下五面与 0.22.0 并排观感不变（名字头/行题/副行同大同粗细）；W3 暗色模式五面过一遍：次级文字不发虚、思考/引用小字可读；W4 减透明开：抽屉底条变实色面、名单末行不透字叠读，关后霜层恢复；W5 聊天页顶栏两圆钮与胶囊同为玻璃质感（不再一纸一玻）、文件页两圆钮同；W6 命中手感抽查：思考头行、引用条 ✕、回告卡 ✕、附件移除钮、顶栏圆钮——都应一按中；W7 总览/管理页会话行与抽屉同物同尺感（题略粗、副行 15）；W8 设置页分区头与抽屉分区头同大同粗（15 medium 统一后）。
- 交付实录：首轮提交 56f8de0（CI 42662291054，447 测 1 失败＝公式自证期望值 5.2 系施工估值、实测 5.035，按 0.22.0 惯例第二轮校准 a235992 改断言 5.04±0.05 并同步改正 Palette/§50 口径，达标结论不变）；口径补正 da2dbb3 为定版提交，CI 42664068485 success，Executed 447 tests, 0 failures（441 基线＋6 新增，与 50.7/50.8 一致）；IPA 4,854,701 字节、md5 ae1905f7802b74528bd85ac5f6b221a3、解包验 Info.plist＝0.23.0/52、bundle site.didichou.oneday，落 ~/workspace/your_files/oneday-v0.23.0/OneDay-0.23.0.ipa。施工期生产零写请求；未自截真机图；§14 十条/MotionTokens/发送链零改动。

## §51 0.24.0/53「原生极简整改」（口径变更源＝用户 2026-11-10 当日指令：以苹果 HIG 为唯一依据、用原生极简主义重排、不许乱加粗——覆盖 0.22/0.23 的 Muse 量测口径；基线 6ab1883、单测 447 只增不减；证据分级：【官方】HIG/SDK 事实【实算】像素量测/WCAG/渲染量测【定版】用户既往拍板【惯例】系统列表惯例带）

### 51.0 根因审计（先查后改，四面 font 声明与角色表全量对账）
- 设置行题实测 21–23 之谜：代码层声明与角色表一致——行题恒 `.rowTitleL`＝title3 20 regular（SettingsView navRow/statusNavRow/manageRow/serverRow/身份卡五处同源，无放大声明）。本轮以 PIL 对用户设置截图逐元素复量（阈值 160、2.74px/pt、CJK 墨迹比以同图已知的 title3 行校准 ≈0.96em）：纯中文行题墨迹高 19.3pt＝20.0pt 声明值，分毫未被偷放大；混排拉丁行（MCP 连接，阈值 200）墨迹 21.9pt——「21–23」读数出自混排行与宽阈量测口径。观感「又大又粗」的真实构成：①20pt 本身比 HIG 列表行 Body 17 大一档（0.22.0 照 Muse 图量测定版，非 HIG 口径）；②图标字形 28 大于行题本身、且混实心符号（desktopcomputer 整屏实心、brain 密实、双泡宽字形压字），整行墨量被图标主导；③行高 60 的行盒放大整行尺度感（本轮未动，见 51.6）。
- 视图层私自覆盖角色表清单（四面＋共享件）：①DeliverablesView 分段标签直用 rowTitleLSemi（角色本身即 Semi，非视图私设，但属点名整改位）；②SettingsView rowIcon 字面量 28（0.22.0 追认值，本轮随令牌改）；③DrawerView 名单字形字面量 light（0.22.0 定版，本轮随令改）；④其余四面文字位全部经角色，无第三套字号。
- 设置标题形态与身份卡横切：配置审计无误——navigationTitle＋.navigationBarTitleDisplayMode(.large) 均落在栈内 List 上【SDK 事实】、呈现链 ContentView sheet→SettingsView 自有 NavigationStack、无嵌套栈、无第二呈现点（代码事实）。用户截图实测：标题为居中 ≈17 semibold 行内形态、身份卡「Hermes」墨迹高仅余 12.0pt（被横切近半）——与「大标题折叠后内容滑入栏区＋硬边切断」的形态一致；机制在「拍摄时已滚动折叠」与「sheet 承载下栏形态未按 .large 落地」两说之间不可单凭截图判死（分级：形态【实算】、机制【推断】）。本轮按构造兜底处理（见 51.4），不赌启发式。
- 文件页分段/空态实测基线：分段字墨迹 19.0pt（≈20 semibold）；空态题精量 16.8pt＝.headline 17（早前一版 31.4 读数系裁图误含图标行，本轮以行带分析纠正）；抽屉导航墨迹 19.3（≈20 semibold）、旁聊题 19.3、时间戳 14.6（≈15）、分区头 15.0（15 medium）；Muse 参考同法量测：导航 17.5（≈18 regular）、分段 15.3–17.2（≈17 regular）、名 24.1（≈25–27）。

### 51.1 字重清仓
- 角色层：semibold 角色 3（screenName/rowTitleLSemi/rowTitle-Headline）＋medium 角色 1（sectionLabel）→改后 bold 仅 screenName 一处（Title1，身份名/大标题配额【指令】），semibold/medium 角色归零；rowTitleLSemi 退役、rowTitle 由 .headline 改 .body——ContentRow/UnifiedRow/会话行/管理行全部行题随角色归 regular（消费点不逐个改、随表改档）。
- 字面量层（grep `weight(.semibold|.bold)` 及 `.weight` 变体，Sources 全量）：改前 31 处→改后 30 处（净 −1＝FontRoles 定义：rowTitleLSemi 退役、screenName semibold→bold 仍计 1）。改后 30 处逐类：角色定义 1（screenName bold，配额内）；字形位 8（胶囊/引用 chevron、引用条 ✕、发送键箭头、枢纽铅笔/勾/chevron——皆 Image 符号非文字）；内容排版 4（MarkdownText strong/标题 3、终端等宽强调 1——正文内容排版、不属 UI  chrome）；Hub 子页状态标签类 17（Browser 3/Goals 1/HubApproval 3/HubTask 2/RichContent 1/HubMonitor 2/MemoryEntries 1/SkillHub 4——caption/footnote 级状态小字与子页小标题，非四面、非点名类别，登记残留待后续包或用户点名）。
- `.font(.headline)` 直用 8→8，全为登记保留的系统 Headline 语义位：主按钮标签（PrimaryButtonBody）、身份名 ×2（IdentityAnchor、ChatView 身份头）、BrowserView 枢纽状态行、HubApproval/Kanban 详情/Computer 标题、EmptyState 题（文件页已迁 CUV、他页面包级标题语义保留）。列表行题的 headline 消费经 rowTitle 角色改档后归零。

### 51.2 字号落档（HIG Typography 文本样式为据）
| 元素 | 改前 | 本轮落值 | 依据 |
|---|---|---|---|
| 抽屉名字头 screenName | largeTitle 34 semibold | Title1 28 bold | 【官方】HIG Title 1；bold 配额＝身份名 |
| 设置行题/抽屉旁聊题/交付物行题 rowTitleL | title3 20 regular | Body 17 regular | 【官方】HIG Body＝列表正文行档 |
| 内容行题 rowTitle（ContentRow/UnifiedRow/会话行） | headline 17 semibold | Body 17 regular | 【指令】列表行题一律 regular |
| 抽屉导航行/管理行 | title3 20 semibold（rowTitleLSemi） | Body 17 regular（改用 bodyText） | 【官方】HIG Body；Muse 量测 ≈18 regular 旁证【实算】 |
| 文件页分段标签 | title3 20 semibold | Body 17 regular | 【官方】；选/未选只靠填充＋墨色（原形态已然） |
| 时间戳 meta/metaMonospaced | subheadline 15 | Footnote 13 regular | 【官方】HIG Footnote |
| 分区头 sectionLabel（全 App） | subheadline 15 medium | Footnote 13 regular＋secondary | 【官方】苹果设置分区头同款形态 |
| 行副题 rowSubtitle | subheadline 15 regular | 不变 | 【官方】HIG Subheadline |
| 聊天正文 .callout 等 | — | 不动（§29/§14 定版） | 【定版】 |
- TypeRole 表九角色（rowTitleLSemi 删）；VisualDirectionGateTests 角色对账断言同步改值（非删测）；DT 缩放闸五角色续跑（screenName/.title 同随 DT）。

### 51.3 图标规范
- 尺寸/字重：FrameworkIcon.drawerGlyphSize 27→21、settingsGlyphSize 28→21（同值、落 glyphSizeRange 20–22 带），字重两面均 regular（抽屉 light 分位退役；底栏 24 light 是 0.22.0 探针定版、不在本轮范围，保留并注记）。槽宽：OneDayMetrics.iconSlot 28→30（ListRowSpec.iconSlotWidth 同步 30、dividerInset 60→62＝20＋30＋12 推导同步）；图→字间距两面同为 HStack spacingSM＝12【惯例：HIG 无明文数字，此为系统列表惯例带】；设置 rowIcon 字形改槽内居中，与抽屉（槽 30 居中）同几何——两面图→字视觉间距自此一致。
- 换符号（设置页，全线性非 fill）：电脑 desktopcomputer→display（空屏线性；旧为整屏实心）；记忆 brain→memorychip（线性芯片、疏；语义由「脑」转「存储芯片」，取舍在此登记）；服务端会话 bubble.left.and.text.bubble.right→bubble.left（双泡宽字形 28pt 时自然宽溢出 28 槽压字【实算：截图图标与行题重叠】，单泡自然宽恒小于 30 槽、构造上不重叠；与「服务端默认模型」的 text.bubble 同族不同形、不混淆）；档案 rectangle.stack.person.crop→archivebox（去人像剪影填充）；外观 circle.lefthalf.filled→sun.max（去半实心；明暗双态语义弱化为亮度语义，取舍登记）。
- 保留登记（非 .fill 变体、符号设计本身形态）：key（无线性变体、剪影即其设计）、chart.bar（条形即其设计）、puzzlepiece.extension/network/folder/doc.text/text.bubble/cable.connector/chart.xyaxis.line/server.rack/arrow.clockwise（皆线性 outline 本体）。
- 量测闸：RenderMeasureTests 设置列名单同步换五件；抽屉名单字重改 regular。闸值先沿用（设置格口径 ≤0.32/紧致 ≤0.68/离散 ≤3.0；抽屉紧致 0.05–0.45），以 CI MEASURE 分布复核、需校准时按 0.22.0 惯例第二轮如实记录。

### 51.4 设置页形态
- 标题：navigationTitle＋.large 配置经审计无误（51.0），保留系统大标题路径不动。
- 身份卡防切（构造兜底两件）：①身份节专用行盒 identityRowInsets 顶距 0→10，首节恒在栏区之下留呼吸位；②List 加 .scrollEdgeEffectStyle(.soft, for: .top)——内容滑入栏下时渐隐、不再被硬边切成半截（iOS 26 官方 scrollEdgeEffect 口径，沿本仓 chrome 定案）。Hermes 题与 host 副行随之完整可见（终审 X5 真机判）。
- 身份卡「Hermes」题随 rowTitleL 改 17 regular：身份名 bold 配额只给抽屉名字头，本卡是列表行、从行题口径（登记）。

### 51.5 文件页空态
- DeliverablesView 三处空态（暂无交付物/没有匹配的文件/暂无影音交付）自绘 EmptyState→系统 ContentUnavailableView（图标/标题/副题全走系统默认形态与排版）；「读取失败」是错误态非空态、保留 EmptyState（登记）。EmptyState 组件本体他页（23 处消费）不动。

### 51.6 不动项与登记残留
- §14 十条/MotionTokens/SideChatLink 与发送链/ComposerLayout 几何零改动；设置行高 60、抽屉行高 58 未动（不在本轮落档表内——字号与图标已降档，行盒尺度终审后如仍显大、下一轮再议，不自创数值）；底栏字形 24 light 定版保留；Hub 子页 caption 级 semibold 状态标签 17 处登记残留（51.1）；系统 Section 自带头（各二级页）为系统形态、不入角色表管辖。
- 版本源五处同改 0.24.0/53：Project.swift 四字面量＋SettingsView.versionFooter「OneDay v0.24.0」，全仓 grep 验（Hermes 服务端版本字面量同名不同物、不动）。

### 51.7 真机终审项（X 系列）
X1 设置页行题与苹果设置并排：同为 17 regular 观感、行图标细线同列、无实心件；X2 抽屉：名字头 28 bold 不压人、导航行 17 regular、旁聊题 17＋时间戳 13 灰、分区头 13 灰；X3 文件页分段：两段字同大同粗、选中只靠白面浮起；X4 文件页空态为系统 ContentUnavailableView 形态（图标/题/副题系统排版）；X5 设置页静止态：大标题左对齐在位、身份卡 Hermes 与地址行完整无切；轻滚设置页：内容滑入栏下为渐隐、无半截字硬切；X6 服务端会话行图标不再压字、记忆/电脑/档案/外观四行新图标可辨识；X7 大字号拉满：五面随 DT 放大不断行（Body/Footnote/Title1 皆文本样式）；X8 管理页/总览会话行题为 regular 17（rowTitle 改档连带面）。
- 交付实录：单轮定版——功能提交 7286dfc，CI 42741249148 success，Executed 447 tests, 0 failures（与基线 447 持平：本轮为断言改值型整改——角色表/令牌值/ListRowSpec 三处断言随规格改值、无删测、无新增）。量测闸一次过、无校准轮：21pt regular 设置列紧致密度 0.230（sun.max）–0.645（cable.connector，7pt 窄盒离群、格口径 0.055 反为最疏，沿 0.22.0 点名口径）、格口径全列 ≤0.126（闸 0.32）、离散比 2.80（闸 3.0）；新换五件 memorychip 0.378/bubble.left 0.291/display 0.317/archivebox 0.427/sun.max 0.230 全部落带内；抽屉名单 21 regular 紧致 0.276–0.381（闸 0.05–0.45）。IPA 4,858,061 字节、md5 7ce27562c7ee852f57b1e081d9f73743、独立解包验 Info.plist＝0.24.0/53、bundle site.didichou.oneday，落 ~/workspace/your_files/oneday-v0.24.0/OneDay-0.24.0.ipa。施工期生产零写请求；未自截真机图；§14 十条/MotionTokens/SideChatLink 与发送链零改动。

## §52 0.25.0/54「交互与动效专包」（依据：Emil 技能包六件【emil-design-eng 动效四问＋频率表/review-animations/improve-animations/gestures/choreograph/apple-design】＋native-ios-design＋§14 十条＋MotionTokens 现值；方法：全量审计→逐项裁决→按裁决修；证据分级：【官方】HIG/SDK 事实【技能】Emil 条文【定版】用户既往拍板/令牌册【实查】代码审计事实）

### 52.0 审计方法与总则
- 全 App 十面（聊天/抽屉/文件/设置/点子/目标/总览/枢纽/管理页/底栏）逐元素过四问（该不该动/目的/曲线/时长）＋频率分级（高频＝逐日数十次级：零装饰动画；中频：仅功能性短动画；低频/稀有：可有入场）。高频面结论先行：发送/切页/键盘/打字/滚动跟随全部零装饰（既有口径、全数合规维持）。
- 铁律执行：§14 十条与 MotionTokens 九支数值零改动；冲突只登记待拍板（52.5）；手势驱动动画全数可打断（抽屉逐帧重定向/原生滚动/动画值驱动）；能用系统内置动效（TabView/sheet/NavigationStack/List 高亮/系统控件）的不自制——全仓转场审计结论：无自制页面转场（RootTabView 系统 TabView、设置 sheet、枢纽/管理 push 全系统），无可删项。

### 52.1 审计总表（面·元素·频率·裁决·改前→改后；「合规不动」只列要害行）
| 面·元素 | 频率 | 裁决 | 改前→改后 |
|---|---|---|---|
| 抽屉·拖动开合＋蒙层 | 中 | 合规不动 | DrawerShell 非桥接 1:1 直写零弹簧延迟【技能：直接操纵】、桥接走 drawerSpring 逐帧重定向保速衔接（速度连续、非自静止起步）、方向锁/橡皮筋/800pt/s fling＋30% 动量投影、scrim 同源 progress 派生（同曲线同步的构造等价）——全链已是全仓动效标杆 |
| 抽屉·导航行/管理行按压 | 中 | 修 | .plain 无反馈→.odPressable（touch-down 0.92） |
| 抽屉·底条搜索清除钮 | 低 | 修 | 无 buttonStyle→补 .odPressable（旁聊行/圆钮本已 odPressable） |
| 聊天·发送舱右端 mic↔圆盘键 | 低频边沿（空↔首字/发送↔流式） | 修 | 两视图硬切→Core ComposerTrailingState 三态收敛（单测把守、流式优先）＋同槽 ZStack opacity 交叉淡化（swap＋resolved）；发送↔停止仍走圆盘内 symbolEffect 形变（既有） |
| 聊天·错误/提示条进出 | 低 | 修 | 无过渡（高度硬跳）→条 .transition(.opacity)＋容器补 errorMessage/notice 两条 swap 动画值（与 isNearBottom 同口径、高度单调）；两 ✕ 钮补 .odPressable |
| 聊天·回到底部钮入场 | 中 | 修（小） | transition scale 起点 0.85→0.9【技能：入场缩放 ≥0.9、不自虚空出现】；高度驱动仍为容器 swap（单调） |
| 聊天·流式上屏/打字点/光标 | 高 | 合规不动 | §14 条 4/条 10 定版（blur 6px/120ms/错峰 30ms、符号形变）；数值零碰 |
| 聊天·思考块展开/收起 | 中 | 修 | 点按 withAnimation(.default)＋相位自动收展无动画，两路不一致→容器级 .animation(resolved(swap), value: expanded) 统一两路；chevron 上下硬切→contentTransition symbolEffect 形变 |
| 聊天·工具卡展开结果 | 中 | 修 | 无动画硬切（卡高跳变）→withAnimation(resolved(swap))；钮补 .odPressable |
| 聊天·列表行/通知/胶囊/引用条 ✕ 等 6 钮 | 中 | 修 | .plain→.odPressable（ChatView 内扫荡，见 52.2） |
| 文件·搜索开关/分段切换 | 中 | 修 | withAnimation(.default) 裸动画→swap（搜索）/liquidSpring（分段，令牌册明定选择指示器滑移归此档）＋resolved 出口（本面原无 reduceMotion 环境、本轮补） |
| 文件·分段钮/顶栏圆钮/影音格 | 中 | 修 | .plain→.odPressable |
| 设置·全部行（navRow 助手一处） | 中 | 修 | .plain→.odPressable（一处修全页行）；页内 inline 小钮（眼睛/清除）系统 .bordered 保留 |
| 管理页·编辑模式切换 | 低 | 修 | 裸 withAnimation{}（隐式 .default）→resolved(swap)＋补 reduceMotion 环境 |
| 全面·行/图标钮按压（枢纽/总览/目标/点子/服务器各面等 25 文件） | 中 | 修 | .buttonStyle(.plain) 全量→.odPressable，OneDayApp 内 .plain 归零（grep 证据）；唯一豁免见 52.2 |
| 组件·主/次按钮按压 | 中 | 修 | isPressed 透明硬跳→补 .animation(resolved(press), value: isPressed)（按下即响应、touch-down 触发）；Secondary 为读环境拆 Body 视图（同 Primary 款式） |
| 底栏·切页 | 高 | 合规不动 | 系统 TabView 原生、无自制转场、无装饰动画 |
| 转场·sheet/push/QuickLook/分享/图片查看 | 中 | 合规不动 | 全系统呈现；自制仅图片查看器关闭钮（系统 close 同款）与 ConnectView entrance（令牌册圈定稀有首跑面、§14 条 4 豁免面） |
| 状态·加载/空态/刷新 | 中高 | 合规不动 | ProgressView 系统转轮、ContentUnavailableView 系统空态、.refreshable 系统下拉——零自制装饰；总览/用量 numericText 为系统内容过渡（数字滚动属系统件、非装饰缩放） |
| 数字/符号形变族 | 中 | 合规不动 | Overview numericText、身份胶囊 chevron、发送键箭头、复制钮（§14 条 10）全走系统 contentTransition/symbolEffect |

### 52.2 按压反馈扫荡口径
- 范围：Sources/OneDayApp 全部 .buttonStyle(.plain)（改前 50 处）＋无样式钮 3（错误/提示条 ✕×2、抽屉搜索清除）＋ReasoningBlock 头行（.plain→odPressable 随扫荡）。改后 OneDayApp 内 .plain＝0。
- 唯一豁免（注册例外）：OneDayDesign/Components.swift 的 CopyButton 保留 .plain——它有自有反馈语言（复制成功符号形变＋触感，§14 条 10 定版面，0.2.5 已审），odPressable 的 0.92 缩放与之叠加反成双重反馈；登记为有据例外、非漏改。
- 安全核查：被扫荡位逐文件抽查上下文——皆普通行/图标钮；List 整行钮的 .plain 本就绕过系统行高亮（原无反馈）、odPressable 只加 label 级缩放透明、不与 swipeActions/编辑模式冲突；系统控件（.bordered/.glass/Picker/Menu label）不在扫荡内。

### 52.3 令牌收编（.default/裸动画清点）
- withAnimation(.default) 改前 3 处（文件页 ×2、思考块 ×1）→全数收编令牌＋resolved；裸 withAnimation{} 改前 1 处（管理页）→收编。改后全仓 withAnimation(.default)＝0、裸 withAnimation{}＝0（grep 证据，注释提及不计）。
- 余留 .animation(.default) 1 处＝SmoothExpand 护栏注释内的历史口径文字（非代码）；SmoothExpand 本体走 swap＋resolved＋>400pt 瞬时护栏（§14 条 7 定版等价实现），不动。

### 52.4 Reduce Motion 覆盖（逐面登记）
- 出口：全仓动画经 MotionTokens.resolved（Reduce Motion→nil 瞬时）或系统组件自管（TabView/sheet/List/ProgressView/玻璃由系统回退【官方】）；本轮给 DeliverablesView、AllConversationsView 两面补齐 reduceMotion 环境（原缺失、且各有 withAnimation 站点）。
- 代码闸：MotionGateTests 新增断言——九支令牌 resolved(true) 恒 nil、resolved(false) 恒非 nil（＋ComposerTrailingState 三态判定 3 测），共 +4 测，基线 447→451（预估、实测以 CI 为准）。
- 大位移面回退：抽屉（resolved(drawerSpring)→瞬时开合，位移仍由手势本身驱动、无自动大位移）、思考/工具卡高度（swap→瞬时）、回到底部钮（swap→瞬时显隐）、发送舱右端（swap→硬切）——全数经 resolved 出口自动回退，无独立分支代码。

### 52.5 待拍板清单（本包不动、附理由）
1. §14 条 9 落法文字与 0.7.1 chrome 裁决的口径差：条 9 定版「拖拽弹簧 1200/80、点赞弹簧 380/18」——1200/80 现为 dragSpring 令牌（值在册），但抽屉拖拽自 0.7.1 起实际走 drawerSpring（0.34·0.86，MotionTokens 注释有档：1200/80 刚度过高、跟手发木而换）。建议：修 §14 落法注记为「抽屉归 drawerSpring、dragSpring 留他用」，数值两边都不动；本包未改 §14 文字、未改令牌。
2. 非桥接拖拽松手的起步速度：SwiftUI 弹簧无 initial velocity 参数【SDK 事实】——抽屉非桥接路径松手后归位弹簧自静止起步（去向已由 settleOpens 以松手速度＋动量投影判定，桥接路径走 velocity 重定向保速）。属平台上限；根治需 UIKit 手势桥，代价与「全面原生」纪律相冲，不建议动，登记备查。
3. entrance 0.45 与 Emil「UI 动画 ≤300ms」上限的形式冲突：令牌册已将 entrance 圈定为「全屏级罕见转换」（现仅 ConnectView 首跑面消费），Emil 频率表对稀有面亦放行入场动画——审计裁合规、登记为已知的有据例外，不改值。
4. SmoothExpand 高度动画与 §14 条 7（Grid 0fr→1fr）：现实现为高度直算＋swap 的定版等价（§50 前已多轮定版），非本包新冲突，settled 不重议、仅在此对账。
5. CopyButton .plain 注册例外（52.2）：若用户要求全仓零例外，可改为 odPressable 并去掉其一重反馈，但将动 §14 条 10 的复制反馈定版面——待拍板。

### 52.6 不动项
- §14 十条、MotionTokens 九支数值、DrawerShell/DrawerMotion 全链、StreamingText/TypingDots/StreamingCaret、SmoothExpand、发送链与 SideChatLink、ComposerLayout 几何、TabView/sheet/导航形态——零改动。
- 版本源五处同改 0.25.0/54：Project.swift 四字面量＋SettingsView.versionFooter「OneDay v0.25.0」，全仓 grep 验。

### 52.7 真机终审项（Y 系列）
Y1 按压手感抽查：抽屉导航行/管理行、设置任意行、枢纽行、总览卡——按下即回落（不等抬手）、松手回弹，无「点了没反应」感；Y2 发送舱右端：空输入麦克风→打出首字淡化成发送箭头、发送后圆盘内变停止键、流结束回落，全程无硬跳；Y3 错误/提示条：断网发送触发错误条——淡入＋底栏平滑长高，点 ✕ 淡出收起；Y4 回到底部钮：上滑后淡入带轻放（0.9 起）出现、点按回底；Y5 思考块：正文起流时自动收起为平滑滑动（不再突然消失）、点标题行重展、chevron 翻转有形变感；Y6 工具卡长结果展开/收起平滑长高收回；Y7 文件页：搜索框开关顺滑、分段切换白面滑移；Y8 管理页「选择」进出编辑模式顺滑；Y9 减弱动态效果开：Y2–Y8 全部变瞬时切换（无滑动无缩放）、抽屉拖动仍 1:1 跟手、松手瞬时到位；Y10 主按钮（连接/保存）：按压透明柔和过渡、不硬闪。
- 交付实录：功能提交 d0804c3，CI 42743391015 success，Executed 451 tests, 0 failures（447 基线＋MotionGateTests 4 新增、零删测零改值）；IPA 4,870,215 字节、md5 dbaa7ebf4620fa19270a2ad05cd86c23、独立解包验 Info.plist＝0.25.0/54、bundle site.didichou.oneday，落 ~/workspace/your_files/oneday-v0.25.0/OneDay-0.25.0.ipa。施工期生产零写请求；未自截真机图；§14 十条/MotionTokens 九支数值零改动（冲突五项登记 52.5 待拍板）。

## 53. 外观页专包（0.26.0/55）

用户 2026-11-10 10:28 令：外观页对标 Muse 外观页截图（88771D9E），由「只剩模式三档」的 0.4.0 占位结构重做为四件套，全部真功能真持久化。机制定案（施工前）：主题＝Palette 级变体单一真源（Core ChatThemes 注册表），Palette 六个主题角色改计算型令牌、求值时现读 UserDefaults；RootView 与 ChatView 观察 chatTheme/avatarSize 两键触发重渲。色值全表经 WCAGContrast 同式脚本校准后落码，闸进单测。

### 53.1 四件套落值表

| 件 | 落法 | 落值 |
|---|---|---|
| 实时预览 | List 首节白卡（行盒 12）内迷你聊天框：头像＋名签胶囊、用户泡×2（148×44/108×30）、助手条泡（188×30）、灰卡块（205×58），空白形状无假文字 | 框圆角 containerCorner 23、内距 spacingM 16、描边＝当前主题强调色（预览明暗档）50% 1.5pt；框内 .environment(\.colorScheme, 预览档) 局部演示：预览档＝模式显式选浅/暗按所选、跟随系统按当前系统；页底走 Palette.pageBG 按演示档解析、助手泡走 Palette.bubbleFill；用户泡/描边走主题表显式取档色（traits 解析在局部环境内不可靠的位以显式色兜底） |
| 聊天主题 | 横滑色板（ScrollView 横排、行盒 左 20/右 0、格距 14）＋44pt 圆（命中域 48） | 默认「三狗」以头像图为样、余 7 款以气泡色（预览明暗档）填充；选中＝Palette.primary 描边环 2.5pt＋泡字色对勾 13 bold；点按经 MotionTokens.resolved(swap) 写 AppStorage(chatTheme)，即时全 App 生效 |
| 虚拟形象大小 | 原生 Menu 行（Menu 内嵌 Picker＝系统菜单勾选形态）：头像图槽 iconSlot 30＋题 rowTitleL＋当前档名 inkSecondary＋chevron.up.chevron.down | 档位：小 24/中 28/大 34（胶囊，中档＝现行 28 锚）；空态 48/56/68（胶囊×2）；作用面见 53.4 |
| 模式 | 三行自定义勾选行（图标槽宽占位对齐、题 rowTitleL、行高 settingsRowHeight 60、选中行尾 Palette.primary 对勾 .body semibold） | 写既有键 appearanceMode，RootView preferredColorScheme 链与 AppearanceMode 枚举零改动；老用户已选值不重置（键名 0.4.0 沿用、不改名不迁移） |
| 页面规范 | List(.insetGrouped)＋settingsBG＋组距 settingsSectionSpacing 28＋行盒（横 20/纵 0，与设置首页 settingsRowInsets 同值复刻）＋分区头 sectionLabel(Footnote 13)/inkSecondary/.textCase(nil)（settingsHeader 同口径复刻）＋新行全 .odPressable、裸动画 0、.plain 0 | 标题 .inline「外观」（推送页系统惯例，设置首页 .large 大标题不动） |

### 53.2 主题色值全表（浅泡/浅泡字/暗泡/暗泡字/浅强调/暗强调/浅弱面/暗弱面＋实算对比）

对比以 WCAGContrast 同式实算：泡字列＝泡字对同档气泡、强调列＝强调对页底（浅 #FCFCFC/暗 #101619）。全款四项 ≥4.74，闸由 ChatThemeTests 钉（≥4.5）。

| 主题 | 气泡浅 | 泡字浅 | 气泡暗 | 泡字暗 | 强调浅 | 强调深 | 弱面浅 | 弱面暗 | 泡字对比 浅/暗 | 强调对比 浅/暗 |
|---|---|---|---|---|---|---|---|---|---|---|
| 三狗 sangou（默认） | C8E7FF | 11191C | 1473C8 | FFFFFF | 1473C8 | 5EB1EF | EDF7FD | 16242E | 13.84/4.87 | 4.74/7.83 |
| 浅蓝 iceBlue | D9EEFC | 14324E | 1D5FA8 | FFFFFF | 1F6FC4 | 7FB8F0 | EAF5FD | 152736 | 11.02/6.45 | 4.96/8.70 |
| 曜黑 obsidian | 23272B | FFFFFF | 2C3138 | FFFFFF | 23272B | C9D1D9 | ECEEF0 | 1E2429 | 15.04/13.10 | 14.66/11.82 |
| 米灰 greige | E7DED2 | 46392A | 6B5B45 | FFF7EA | 84643F | C9A87C | F4EEE5 | 262019 | 8.40/6.16 | 5.28/8.15 |
| 天蓝 skyBlue | A9D6F8 | 103A5E | 1663AC | FFFFFF | 0B74BC | 6FB3EE | E3F1FD | 132636 | 7.64/6.15 | 4.83/8.13 |
| 浅紫 lavender | DCD2F5 | 3B2A63 | 5E4FA3 | FFFFFF | 6440C8 | A78BFA | F0EEFA | 221F31 | 8.59/6.72 | 6.58/6.71 |
| 粉 pink | FBD3E4 | 6E2147 | 9E3565 | FFFFFF | BC3A78 | F28BBD | FDEDF4 | 2C1A22 | 7.88/6.66 | 5.10/8.00 |
| 蜜桃 peach | FBE0C3 | 65350F | 9E5A1C | FFFFFF | AC5A12 | F5A95C | FDF0DF | 2B2113 | 8.00/5.34 | 4.84/9.31 |

默认行映射钉：三狗行气泡/强调/弱面三组与 0.25.0 前 Palette 旧值逐字相同（ChatThemeTests.testDefaultThemeMatchesLegacyPalette 钉），切回默认即回原貌。**全表唯一旧值修正**：暗档泡字——旧呈现为 bodyInk 暗档反演墨 #EDF1F3、对暗泡 #1473C8 实算 4.28 压线（且 onPrimary 暗档同值骑 primaryPale 暗档同病），本版泡字暗档改纯白 #FFFFFF（4.87），onPrimary 随泡字行同改；浅档零变化。

### 53.3 强调位应用清单（跟/不跟）

跟主题走（经 Palette 主题化令牌，默认值＝三狗行时呈现与旧版逐字相同）：
- Palette.primary（→主题强调行）：全 App 自绘强调唯一源——链接与消息内链接、选中态与勾选、未读/计数角标填充、光标 caret、开关与进度类强调，实查 24 处/17 文件。
- Palette.primaryFill（→强调行，与 primary 同值别名化）：令牌主题化；实查当前无视图直接消费（仅 DesignTokens 注释提及），保留别名防未来位漂移。
- Palette.primaryPale（→主题气泡行）：主按钮面、发送钮圆盘等浅填充面（4 处）——其令牌本义即「与用户泡同源的主填充蓝」，本版把同源关系落成字面同值。
- Palette.primaryTint（→主题弱面行）：强调语境弱填充——图标盒/附件牌/身份位底（5 处）。
- Palette.userBubbleFill＋新增 userBubbleText（→气泡行＋泡字行）：聊天页用户气泡底与正文字（本版将气泡正文字由 bodyInk 改走 userBubbleText，助手侧 bodyInk 不动）。
- Palette.onPrimary（→泡字行）：骑 primaryPale 的两面——发送钮箭头、主按钮字（3 处）。

明确不跟（及理由）：
- 界面底色与文字基线（pageBG/surface/settingsBG/chatSurface/bubbleFill 助手泡/ink/bodyInk/inkSecondary/inkSecondaryOnFill/inkMuted/hairline/selectionFill/scrim）：冷中性基线，简报明令不许动——主题只染气泡与强调，界面不许被染花。
- pastel 点缀家族（tintSky/tintGreen/tintLavender/tintOrange）：内容类别色（文件类型/监控分类的语义区分），与聊天主题无关；注：其中 tintSky/tintLavender/tintOrange 的色值与三款主题的弱面行巧合相同——那是 OpenMuse 原色板同源之故，令牌本体独立、不随主题变。
- success/warning/danger：语义状态色，跨主题恒义。
- 根 .tint(.primary)（系统 label 色）：0.5.2 定版，系统控件着色不涉 Palette.primary。
- codeFill/代码面、文件类型真色块（0.22.0 定版 W/P/X/PDF 品牌色）：内容本色，不染。

### 53.4 形象大小作用面与同源顺带登记

- 聊天胶囊头像（ChatView capsuleRow 硬编码 28→avatarTier.capsulePointSize）：ViewThatFits 双档（showName true/false）皆只换头像边长；名字 .headline＋fixedSize＋胶囊 hug 宽随内容、状态/模型段 fixedSize——头像 24↔34 只改胶囊总宽 ±10、不触发档位切换条件变化之外的截断（构造论证；真机终判 Z3）。
- 聊天空态形象（currentThread==nil 分支）：SF 符号 bubble.left.and.bubble.right 26pt 退役→SangouPartner 头像按 emptyStatePointSize（48/56/68）圆裁＋hairline 描边；两行字（§5 口径）原样保留。此项使空态视觉重量大于 §5「小图标」旧口径——系用户本令点名的作用面，覆盖关系在此登记。
- **同源顺带（简报两命名面之外）**：IdentityAnchor（总览/文件页顶栏锚，Components.swift）头像与 sparkles 占位边长 28→同档 capsulePointSize——0.22.0 F3 已定版「同一头像三面同源、并排即露馅」，只改聊天胶囊必再造双源，故同轮同档处理，在此明示登记。
- 不在辖区：枢纽页 110 大头像（品牌呈现面）、连接页吉祥物、抽屉名字头——不动。

### 53.5 偏离与差异登记

1. 分区头：参考图约 15pt 灰 vs 本页 Footnote 13＋inkSecondary——守 0.24.0 角色表定版，不为单页破例（简报已预登记）。
2. 预览名签：参考图为头像下缘重叠的白色小胶囊（底带浅描边环）——本页以 VStack 负间距 -5 复刻重叠形态，字 caption2 semibold；像素级对位归 Z1 真机判。
3. 主题切换的跨页即时性：聊天页与根层有显式观察（必即时）；其余页面（总览/文件/枢纽等）的强调色在其下一次重渲/出现时刷新——SwiftUI 树重渲语义内，无独立广播机制，不冒充全树瞬时。
4. primaryTint 暗档：旧为蓝 22% 透明叠底的随底等效色，本版取主题暗泡实色——默认主题下暗档呈现与旧版有可感差异（更实），系主题化必然，登记备查。
5. §14 十条/MotionTokens 九支数值零改动（本包唯一动效＝主题/模式写入点经 resolved(swap) 出口）；版本源五处同改 0.26.0/55＋grep 验；施工期生产零写请求；未自截真机图。

### 53.6 真机终审项（Z 系列）

Z1 外观页全貌对图（参考 88771D9E）：四组分区序与命名、预览框形态（头像＋名签重叠、泡位、卡块、主题色描边）、色板横滑与选中环＋勾、形象行菜单形态、模式三行行尾勾——逐项与参考图并排判。
Z2 预览实时性：依次改主题/形象档/模式三组，预览的气泡色、头像大小、明暗须逐项当场变；模式选「深色」时全 App 变暗之外，预览框演示档与之同向。
Z3 形象三档回归：大档 34 时聊天胶囊名字不断行不截断、状态词与模型短名正常；小档 24 时胶囊不塌；空态头像随档 48/56/68；总览/文件页顶栏锚头像同档跟随（同源顺带验收）。
Z4 主题真生效：任选一非默认主题（如粉/曜黑）→返回聊天页：用户气泡底与字色、发送钮与主按钮面、链接与选中色当场换色；切回「三狗」与 0.25.0 观感逐面一致（默认行零漂移验收）。
Z5 深色模式下全主题抽查：暗档气泡字可读（尤其三狗暗泡白字）、色板填充切暗档色、预览框暗档演示正常。
Z6 持久化：杀进程重开，三组选择保持；模式为跟随系统时改系统明暗，App 与预览同向跟随。
Z7 减弱动态效果开：主题/模式切换变瞬时、无残余动画。
Z8 形象行 Menu：点开为系统菜单、三档带勾在当前档、选手感与系统设置一致。

- 交付实录：功能提交 3b8b423，CI 42745926878 success，Executed 459 tests, 0 failures（451 基线＋ChatThemeTests 8 新增、零删测零改值）；IPA 4,926,466 字节、md5 bb58277b09ba7851ae75b428869181af、独立解包验 Info.plist＝0.26.0/55、bundle site.didichou.oneday，落 ~/workspace/your_files/oneday-v0.26.0/OneDay-0.26.0.ipa。

## 54. 主线/旁聊串话热修（0.27.0/56）

根因（诊断档 oneday-design-review/main-sidechat-bleed-diagnosis-20261110.md＋step1-session-probe-20261110.md 双判死）：Hermes api_server 对无会话头对话按开头派生合并落库＋前缀去重续写；主线恒无头重放、旁聊建会话打 Dashboard 面必 405 被静默吞——主线与同开头旁聊在服务端实为同一条会话（合并桶 api-592647b9ae21ec54 39 条、api-e8c923beeaebed9c 150 条，均已导出留底、冻结不删洗）。用户 2026-11-10 10:55 批准五步序（含生产写操作授权）。

### 54.1 服务端契约实证（源码＋活探针，不凭记忆）

- 建会话端点只在网关面 8642（api_server.py 路由表）；Dashboard 9119 的 sessions 路由只有 GET——405 的根。
- 带会话发送契约（api_server_openai_routes.py:899 起）：POST /v1/chat/completions＋X-Hermes-Session-Id 头＋Bearer；带头时历史以 state.db 为准、body 只取最后一条 user 消息；无头则按指纹派生（合并桶机制本体）。/api/sessions/{id}/chat/stream 是另一套类型化事件协议，本包不采用（沿用现有 SSE 通道）。
- 种子唯一官方口子：Dashboard POST /api/sessions/import（sessions 字典带 messages 全量导入；model/model_config 为透传列可随导入落锁）；走 mutation 围栏：request_id 每发新铸＋expected_revision＝锚点 runtime_revision（新锚 0）。活探针：import 两条消息 200 落库（revision 1）、回读 message_count=2；重复导入同锚 expected_revision=0 回 409 revision_conflict（围栏按设计工作）。
- Dashboard PATCH（改名/归档/置顶）无围栏必 409 client_upgrade_required（活探针判死）——0.18.0 以来管理页写动作与删除归档联动在生产从未真正落定，本包顺带修复：updateServerSession 内先 GET 取 runtime_revision、带围栏发、409 重读重试一次、落定仍靠调用方 GET 回读（O-4 口径不变）。围栏 PATCH 活探针：200、operation=sidebar、归档落值回读验。

### 54.2 五件施工落值

1. 送达改路：nginx hermes.didichou.site 新增 location = /api/sessions（POST 经 error_page 418 内部转 @gateway_session_create→8642、其余方法原样回 9119；改前备份 hermes.didichou.site.conf.bak-20261110-oneday027、nginx -t 过后 reload、动前内存 51%）；客户端 createServerSession/createLinkedServerSession 改带 App 既有 /v1 Bearer（sendJSONDecoding 加 bearer 形参），请求体组装收进 Core 纯函数（createSessionBody/linkedCreateSessionBody，单测把守形态）。不放宽其他 /api/*。
2. 主线转真会话：ensureMainServerSession（失败全静默）退役→ensureMainLink：未链（SideChatStore 新增 mainServerSeeded、与 mainServerConfirmed 由 markMainLinked 一并置真）时走共用 performLink；失败原因原文落 mainLinkLastError 持久化，设置页「服务器与连接」新增主线会话状态行（statusInfoRow：已链接显 id、未链接显错误原文）。主线发送自此与旁聊同口径走 sendPlan（钦定 id＋双位代入）。
3. 旁聊下线无头回退：SideChatSendPlan.legacyReplay 整类删除；sendPlan 改判 (serverSessionID, serverSeeded)：无绑定/绑合并桶/自有未种子→linkAndSeed，其余→session。链接共用 performLink 三路：不存在→无种子网关建、有种子 import 落行＋全量（围栏 0）；存在空行＋有种子→import 补种（围栏取 GET 的 runtime_revision）；存在有消息→认链。种子快照取本轮条目落盘前（防本轮消息在服务端落两份）；链接失败抛错→send() 删本轮条目、输入原样退回发送舱、错误横幅明示原因（旁聊失败计数/原因落线程既有字段）；用户链接窗口内停止抛 CancellationError 静默收尾（旧口径）。存量两条旁聊下次发送自动懒链接：绑桶者解绑覆盖为自有新 id（桶本体零动作）、各自本地条目成种。恢复链（reconcile）重发分支同步改判：旧待恢复账 sessionID 为 nil 时，已链接改带头只发尾条、未链接不硬发（留待下次发送一并种子）。
4. 硬化两处：①currentThread 删除 ?? threads.first 静默回落→Core CurrentThreadResolution 精确解析（失配 nil/空态）；ensureThread 三路（useExisting/createFresh/mismatch），mismatch 置可见错误、整轮不发、输入退回。②删除联动加闸：Core mayArchiveOnDelete 只认 oneday- 前缀（DrawerView 接线）；管理页对两条合并桶的归档/删除加二次确认并写明牵连主线历史（Core mergeBucketWarning 单一文案；ServerSessionRow 归档/删除＋AllConversationsView 批量归档/删除四入口全覆盖，恢复方向不拦）。ChatThread 新增 serverSeeded（续聊导入线程落盘置真、自有会话链接收尾置真）。
5. 收尾与生产验收：探针三条（oneday-probe-20261110、oneday-probe-20261110-main、oneday-probe-import-20261110）＋验收两条（oneday-verify-20261110、oneday-verify-seed-20261110）已全部 PATCH archived=true 落定（网关面）；两条合并桶本体未动。

### 54.3 公网端到端复验证据（与 App 完全同形）

- 公网 POST https://hermes.didichou.site/api/sessions（Bearer＋旁聊形态 payload）→ 201，会话 oneday-verify-20261110 落库（Dashboard 回读：model=deepseek-flash、model_config 含锁）。
- import 种子（Dashboard cookie 通道）→ 200 imported=1；回读 message_count=2、model/锁随导入落；随后以 App 发送形态（/v1/chat/completions＋X-Hermes-Session-Id＋仅尾条）发问「我第一句问的是什么」，模型答「你的第一句是：验收种子问」——种子上下文真续上；该会话 message_count 2→4（本轮 user＋assistant 追加进同一会话）。
- VM 本机出站链路当日多次连接重置（login 一发被断）——系本机透明拦截老毛病，服务端行为以服务器本机复测＋公网 201 双证为准，不归因服务端。

### 54.4 已知残留（登记待拍板，本包未动）

1. 会话内模型重锁端点 POST /api/sessions/{id}/model 只在网关面，公网现行路由（本包按简报只加 POST /api/sessions 精确一条）下达不到——已链接旁聊胶囊改选后的重锁仍为尽力而为、失败下轮再试（发送本体的逐请求 model＋provider 不受影响）。如需根治，另批一条 nginx 精确路由（POST /api/sessions/oneday-*/model 同式）即可。
2. performLink「存在空行＋有种子」分支的 import-into-existing-anchor 语义未单独活验（生产首跑走的都是新锚路径）：该分支 payload 含全量种子＋锁，即使服务端按整行替换语义处理落值亦正确；若回 409/400 则链接如实报错、不产生无头发送。
3. 绑合并桶的导入线程若本地条目本身即合并历史（经管理页续聊导入形成），解绑重链后种子内容仍含混杂——本地 entries 为真源口径下无客户端侧可行的再分割手段，登记备查。

### 54.5 AA 系列真机终审项（验法逐项写明）

- AA1 主线种子对账：装 0.27.0 后打开聊天页一次（触发主线链接预热）→设置页「主线会话」行应显「已链接 · oneday-main-…」；再到管理页（全部对话→主线段）看主线行 message_count——应与手机本地主线中 user＋assistant 正文条数一致（工具卡不计入种子、图片消息正文为空者不计）。不一致即报数回查。
- AA2 旁聊分家：两条存量旁聊各发一条（如问一个只有本聊提过的问题）→回复不得引用另一条/主线的内容；管理页站内段应出现两条 oneday-side- 新会话，计数各为（该旁聊本地既往条数＋2）。
- AA3 新旁聊首发：新建旁聊发一条→管理页即时出现对应 oneday-side- 会话且只有本聊内容；回主线发一条，主线计数只增本轮 2 条。
- AA4 断网可见失败：开飞行模式在任一未链接过的旁聊/主线发送→应弹「会话链接失败，本条未发送：…」横幅、输入退回发送舱、条目不落盘；关飞行模式重发应成功。旧版此情形会静默发进合并桶。
- AA5 删除闸：删一条绑 api- 的导入线程（或任一非 oneday- 绑定线程）→只删本地，管理页对应服务端会话仍在未归档段；删一条 oneday-side- 旁聊→其服务端会话转入已归档段。
- AA6 合并桶确认：管理页对「友好问候」（api-592647…）点归档或删除→先弹带「混存着主线与旁聊的历史」说明的二次确认；取消后桶与主线记录无任何变化。
- AA7 设置页状态：链接失败场景下（可用 AA4 的飞行模式在聊天页触发一次主线链接失败后）设置页「主线会话」行显「未链接 · <错误原文>」；恢复网络打开聊天页链接成功后该行转「已链接」。
- AA8 主线历史连续性：装机链接后在主线问一件只有主线旧对话里提过的事（如某个旧决定），模型应答得上（种子上下文生效）；在「你好」旁聊里问同一件事，应答不上或明确无关（分家生效）。

- 交付实录：功能提交 b7ebffc＋修复提交 1621c41（ServerSession.runtimeRevision 默认值，CI 首跑 42749072689 因此编译错、修复后重跑）；CI 42749644784 success，Executed 475 tests, 0 failures（459 基线＋SessionLinkHotfixTests 15＋SideChatLinkTests 改判净增 1，零删测）；IPA 4,948,355 字节、md5 6658834ff07419e1fd2a29ed02393fd3、独立解包验 Info.plist＝0.27.0/56、bundle site.didichou.oneday，落 ~/workspace/your_files/oneday-v0.27.0/OneDay-0.27.0.ipa。§14/MotionTokens/0.26.0 外观成果零改动；未自截真机图。

## 55. 连接器目录页（0.28.0/57）

### 55.1 实查证据表（2026-11-10，只读；查前服务器内存 51%，红线 80%）

| 面 | 查法 | 结果 | 证据档位 |
| --- | --- | --- | --- |
| config.yaml `mcp_servers:` | 容器内 grep | 整段是注释模板（行 1698 起），手动配置的 MCP 服务器＝0 条 | 配置层实查 |
| GET /api/mcp/servers | Dashboard 登录握手实测 200（容器内直连 9119） | 在册仅 1 条：box（transport http、url https://mcp.box.simular.ai/mcp、enabled=true、source=plugin、plugin=box） | 端点实活 |
| /opt/data/plugins | 目录实查 | box、pairing——box 官方插件已装，与上行互证 | 配置层实查 |
| channel_directory.json | 文件实查 | platforms＝{}，消息平台连接 0 条 | 配置层实查 |
| 四桥（write-gate 8643/overview 8644/box-bridge 8645/oneday-bridge 8646） | 既有部署事实 | OneDay 自身内部设施——按简报不列作用户连接器 | 不列示 |

结论：Hermes 现行真实「已连接」只有 Simular Box 一条（经官方插件预置的 MCP 连接）。目录页的已连接段只此一条，不凑数。

### 55.2 落值

1. Core 新文件 ConnectorCatalog.swift 单一真源：证据档位三级（liveVerified 端点实活／configuredOnly 仅配置未验活·预留档／none 无证据）；已连接条目 ConnectedConnector 构造口唯一——由 MCPServerItem 构成、evidence 恒 liveVerified，不给无证据的已连接留构造路径；状态文案单一映射（已连接 · 已启用／已连接 · 已停用）；搜索纯函数（名称＋分类＋说明＋状态，归一化大小写与首尾空白）；availableEntries 占名扣除（已连接占名的服务不再出现在可连接目录，防两边口径打架）；knownServers 展示映射只收实查在册者（box→Simular Box，云电脑说明）；未知服务端名回退原名＋来源口径说明，不编造产品名。
2. ConnectorsView 取代 MCPViews：List(.insetGrouped)＋settingsBG＋系统 searchable（常驻）＋已连接/可连接分段（默认已连接）；行题 rowTitleL、分区头 sectionLabel、行高 settingsRowHeight、行盒横向 20——与设置首页/外观页同规格。搜索时跨两段出结果（已连接段＋分类段），空结果有空态。已连接行＝瓷砖＋显示名＋状态点与状态字＋chevron；详情 sheet 列全状态（状态/证据档位/来源/传输/地址）并保留真实操作（启停 PUT 乐观更新＋失败回滚、测试 POST 回执口径沿旧页，不新造语义）。可连接行尾只有「未接入」状态字——全页无任何形似连接的假按钮；详情 sheet 只有状态/分类/接入路径/接入说明。
3. 图标：无品牌授权素材——彩色圆角瓷砖＋白色字形近似（Gmail「M」红、Google 日历「31」蓝、Drive「D」绿、Sheets「S」深绿、Notion「N」黑、GitHub「G」深灰、Spotify「♪」绿、Instagram「IG」品红、Simular Box「B」灰蓝），登记为近似处理，不拿错品牌图标冒充。
4. 设置入口：智能体组行题「MCP 连接」改「连接器」，目的地换 ConnectorsView（路由 .mcp 不动）；HermesClient 端点错误标签「MCP 连接」是接口名、保留。

### 55.3 目录名单全表

已连接（端点实活，1 条）：
| 条目 | 显示 | 状态 | 证据 |
| --- | --- | --- | --- |
| box | Simular Box（云电脑） | 已连接 · 已启用 | 端点实活（§55.1） |

可连接（静态目录，全部未接入，8 条）：
| id | 名称 | 分类 | 接入路径摘要 |
| --- | --- | --- | --- |
| gmail | Gmail | 效率提升 | 需服务器端配置 MCP＋Google OAuth（自备 Cloud 凭据） |
| google-calendar | Google 日历 | 效率提升 | 同上 |
| google-drive | Google 云端硬盘 | 办公协作 | 同上 |
| google-sheets | Google 表格 | 办公协作 | 同上 |
| notion | Notion | 办公协作 | 官方远程 MCP，服务器端添加＋一次授权 |
| github | GitHub | 开发工具 | 官方远程 MCP，服务器端添加＋授权 |
| spotify | Spotify | 生活 | 无官方 MCP，需开发者凭据＋社区服务器 |
| instagram | Instagram | 生活 | 官方暂无 MCP 路径 |

### 55.4 可低成本接通清单（供用户拍板，本包未接通、未动服务器配置）

1. **Notion**：官方远程 MCP（mcp.notion.com）现成；Hermes config.yaml 模板注释里就有该示例。接通动作＝服务器 config 加一条 url 型 MCP＋在授权页完成一次 Notion OAuth。成本最低。
2. **GitHub**：官方远程 MCP 现成；接通动作＝服务器 config 加一条＋GitHub OAuth 或访问令牌。次低。
其余六家：Google 系四家需自建 Google Cloud OAuth 凭据（中等成本）；Spotify 需开发者应用＋社区服务器（中高）；Instagram 无官方路径（不建议）。

### 55.5 BB 系列真机终审项

- BB1 已连接真实性：设置→智能体→「连接器」打开，默认落在「已连接」段——应只有 Simular Box 一条，状态点绿＋「已连接 · 已启用」。与服务器实际配置对得上即过。
- BB2 详情与证据：点 Simular Box 行→详情应列「证据档位：服务端实时读取」「来源：插件预置 · box」「传输方式：远程连接」与地址 mcp.box.simular.ai；「测试连接」点后应回成功＋工具数（box 工具实数以回执为准）。
- BB3 启停真生效：在详情里关掉「启用」→回列表状态变「已连接 · 已停用」、状态点灰；再打开恢复。关掉期间到电脑页/聊天里验 Box 工具不可用（服务端真停），不是只变个字。
- BB4 无假按钮：切到「可连接」段——八家行尾应只有「未接入」三字，没有任何蓝色「连接」按钮；逐个点开详情，只有状态与接入说明、没有可点的连接动作。
- BB5 搜索真过滤：搜「邮件」只出 Gmail；搜「开发」只出 GitHub；搜「Simular」出已连接的 Box；搜乱码出空态文案。
- BB6 读取失败不冒充：飞行模式下下拉刷新已连接段——应报错＋重试，不拿上次数据装实时（列表可能保留旧行属缓存呈现，但须有失败提示；若无提示即报回查）。
- BB7 分类与行规格：可连接段分组序为 效率提升（2）/办公协作（3）/开发工具（1）/生活（2）；行题 17 regular、瓷砖 40、行高与设置首页一致，无粗体泛滥。

- 交付实录：功能提交 c18a3f3＋修复提交 4d9aee2（ConnectedConnector 去 Equatable——MCPServerItem 非 Equatable 合成失败，CI 首跑 42751527952 因此编译错、修复后重跑）；CI 42751655037 success，Executed 485 tests, 0 failures（475 基线＋ConnectorCatalogTests 10 测，零删测）；IPA 5,033,330 字节、md5 c1a65db10958a2fac2bc7d2d792b9c5f、独立解包验 Info.plist＝0.28.0/57、bundle site.didichou.oneday，落 ~/workspace/your_files/oneday-v0.28.0/OneDay-0.28.0.ipa。§14/MotionTokens/0.26.0 外观/0.27.0 会话链零改动；施工期除只读查外生产零写；未自截真机图。

## 56. 连接器目录补本机服务组＋主线不进旁聊集（0.29.0/58）

用户 2026-11-10 12:30 点名（连接器目录「已连接」只数 MCP 在册一条，自家本机线没名分）、12:31 两令同下：①目录补「本机服务」组；②设计修正——主线不得出现在任何「旁聊」名义的列表里（对标 Muse：主线有自己独立入口，旁聊列表纯旁聊）。基线 183ff45（0.28.0/57、485 测）。

### 56.1 本机服务组（名册/探活证据/状态口径）

Core 新 `LocalServices.swift` 单一真源：名册四条（序＝呈现序）、探活结局→状态映射、状态文案、搜索纯函数。瓷砖续 0.28.0 彩色字母/字形瓷砖语言（H/记/标/览，非品牌图标）。

| 条 | 探活路径（既有客户端，与功能页同源） | 证据与读数口径 |
| --- | --- | --- |
| Hermes 服务 | GET /health（HermesClient.health，连接页探活一） | 200 且 status=ok 判正常；读数取回执 version（如「版本 0.23.0」），无版本不出 |
| 记忆与技能 | GET /api/write-gate/status（WriteGateClient.gateStatus，枢纽/记忆页同源） | 200 判正常；详情另列闸门模块/记忆闸门/技能闸门原值；计数为尽力读数——记忆条数走记忆页的 MemoryBridgeClient.entries、技能数走技能页的 HermesClient.skills，任一取不到就不出该数、不编造 |
| 目标与点子 | GET /api/oneday-bridge/goals（OneDayBridgeClient.goals，目标页同源） | **本桥无专用健康端点**，取最轻只读端点探活；读数＝目标数＋点子数（ideas 尽力而为） |
| 总览数据 | GET /api/overview-bridge/overview（OverviewBridgeClient.overview，总览页同源） | **本桥无专用健康端点**，取快照端点探活；待批数 >0 时作读数；详情显快照 generatedAt 原值 |

- 状态四档：正常（本次探活成功，绿点）／异常（本次探活失败，红点，详情显错误原文＋最近探活时间）／未配置（灰点，专指审批桥钥匙未设置——三桥共用同一把 Keychain 钥匙，各桥既有客户端在无钥匙时根本不发请求、以 noKey 结局回，映射到此档；判定与 WriteGateKeyStatus 同一把钥匙同一读法，App 层不另立第二套）／读取中（首帧小转圈，不拿灰点冒充已探）。
- 无缓存口径：状态只存视图 @State（本页生命周期），进页 .task 整批探活、下拉刷新整批重探；重进页必从读取中起，不存在跨页缓存的绿色。
- 详情 sheet：说明＋状态＋证据来源＋最近探活＋功能入口——记忆/技能/服务器详情/审批桥钥匙走既有 pending 路由（SettingsView 消费落位）；目标/点子经新增 AppState.mainTabSwitchRequest（ContentView 消费：关设置＋切底栏格，与 settingsSheetRequested 同式）；总览经 SettingsView 注入闭包回管理组 manageSheet 开总览（承载不另立第二份）。
- 电脑口径：Simular Box 是 MCP 在册连接，留在「已连接」组原位，本组不重复列（组脚注与详情均有说明）；box-bridge（8645）是电脑页内部设施，同 0.28.0 口径不列。
- 搜索：本机四条进搜索（名称＋说明＋状态词，Core 纯函数），命中恒列第一组（分组序：本机服务→已连接→可连接）。
- 页面规范续 0.24.0/0.28.0：行题 rowTitleL、分区头 sectionLabel、行高 settingsRowHeight、瓷砖 40。

### 56.2 主线排除审计（逐面；口径＝用户 12:31 令）

收敛点：Core `SideChatClassifier.isMain` 双信号单一函数族——本地线程版（钦定 id 命中 ∨ 关联会话为主线会话）与服务端会话版（钦定 id 命中 ∨ `oneday-main-` 生成前缀）；存量 zone() 两函数保留给非名单面（当前线程归类等），名单面一律改走 isMain。

| 面 | 改前：主线在不在（代码证据） | 改后 |
| --- | --- | --- |
| 抽屉「旁聊」区 | **判定在、单信号有缺口**：sideThreads 经 DrawerSideChatFilter.threadListed(isMainThread: thread.id == mainThreadID) 剔除，钦定 id 命中时不在；但钦定丢失/指向他条时，绑着主线会话的真主线线程无第二信号可剔，会以旁聊行出现（本地库不可远程核、是否已在用户机上发生未判死——串话诊断档未判死项 #3 同源） | 行源改走 isMain(localThreadID:linkedServerSessionID:mainThreadID:mainServerSessionID:) 双信号 |
| 抽屉底条搜索 | 与旁聊区同一行源（drawerSearchList 与 drawerSideSection 同吃 sideThreads，filteredThreads 只按词收窄）——同上缺口 | 随行源同改、自动同口径，无独立改动 |
| 管理页·主线段 | 主线行只在此段（mainRow、钦定保护、无菜单）——按设计保留（简报明示可保留） | 未动 |
| 管理页·站内段 | 等值过滤 `$0.id != mainSessionID`：钦定已回存时不在；钦定未回存（nil）时过滤恒真，主线会话会以普通行混入 | 改走 isMain(serverSessionID:mainServerSessionID:) 双信号 |
| 管理页·已归档段 | 同站内等值过滤 | 同改 |
| 管理页·外部段 | 无数据源（externalContent 只有静态 EmptyState「通道未开通」）——本就不在 | 未动（只报证据） |
| 管理页·搜索结果 | 服务端全量搜索（/api/sessions/search）可命中主线会话行——属「全部对话」全页搜索、非旁聊名义分段，主线在管理页的家是主线段本身 | 不在本次口径内，未动（仅登记） |
| 总览页「最近会话」 | 服务端名单含全部会话、本地回退 localThreads.prefix(3) 未过滤——该面名义为「最近会话」、不复用旁聊数据源 | 不在口径内，未动（仅登记） |
| 抽屉导航组「主线聊天」行 | 主线唯一 sanctioned 入口 | 形态未动（简报明令） |

单测钉死（MainlineExclusionTests 9 测）：钦定命中、绑主线会话的非钦定线程、前缀兜底三路判主线；无关联/绑 oneday-side-/绑 api- 桶的线程判非主线；旁聊集组装主线两形态全剔且集非空；服务端版钦定/前缀判主线、side/api/probe 判非主线。

### 56.3 CC 系列真机终审项

- CC1 本机组齐全与落定：设置→连接器，进页第一组「本机服务」四条齐（Hermes 服务/记忆与技能/目标与点子/总览数据），首帧读取中、随后逐条变「正常」绿点；组脚注有 Box 不重复列的说明，已连接段里 Box 仍在原位。
- CC2 状态与计数对账：四条的读数与功能页逐个对（技能数＝技能页「已装 N 个」、记忆数＝记忆页条数、目标/点子数＝两页条数）；任一功能页打不开时对应条不许显正常。
- CC3 飞行模式异常：开飞行模式进连接器页或下拉刷新——四条应转「异常」红点、不显绿；点开详情有错误原文与最近探活时间；关飞行模式下拉刷新恢复正常。
- CC4 未配置一档：在「审批桥钥匙」页清除钥匙后进连接器页——三条桥显「未配置」灰点（不是异常红点）、Hermes 服务不受影响仍正常；桥条详情有成因说明与「审批桥钥匙」入口；补设钥匙后下拉刷新转正常。
- CC5 入口跳转：记忆与技能详情点「记忆」/「技能」落对应页；目标与点子详情点「目标」关设置并切到底栏目标格、「点子」同理；总览数据详情点「总览」打开总览；Hermes 服务详情点「服务器详情」达服务器详情页。
- CC6 搜索覆盖：搜「审批」只出记忆与技能；搜「总览」出总览数据；飞行模式下搜「异常」出异常条目；本机命中恒排在已连接/可连接之前；搜乱码出空态。
- CC7 主线不进旁聊：抽屉「旁聊」区与底条搜索里找主线对话——不出现（重点验历史上以「你好」开头的形态）；主线只从导航组「主线聊天」行进入；管理全部对话：主线只在「主线」段，「站内」「已归档」段无主线行；旁聊条目仍在、名单没被误杀空。
- CC8 详情证据：四条详情的「证据来源」与实际探活端点一致（目标与点子、总览数据两条应注明无专用健康端点、取最轻只读端点）。

- 交付实录：功能提交 9a1a80c；CI 42757396350 success，Executed 506 tests, 0 failures（485 基线＋LocalServicesTests 12 测＋MainlineExclusionTests 9 测，零删测）；IPA 5,101,724 字节、md5 09c895681111e06ce16494d59b223f8d、独立解包验 Info.plist＝0.29.0/58、bundle site.didichou.oneday，落 ~/workspace/your_files/oneday-v0.29.0/OneDay-0.29.0.ipa。版本五处同改＋grep 验（注：设置页页脚在基线滞留 v0.26.0——0.27.0/0.28.0 两包漏改页脚，本包一并归正为 v0.29.0）。§14/MotionTokens/0.26.0 外观/0.27.0 会话链/0.28.0 目录既有条目状态语义零改动；探活全只读 GET、生产零写；未自截真机图。

## 57. 会话页签恢复语义＋聊天时间系统（0.30.0/59）

用户 2026-11-10 12:56 录屏讲解 Muse 模型并点名两件：①主要聊天是与旁聊平级的单独入口、底部「会话」页签不与主线同步——不管在旁聊还是主聊，点页签跳回的都是上次停留的对话；②对话页没有时间显示不科学，按微信/QQ 等大厂规划做（今天/昨天/星期/日期分档）。

### 57.1 现行偏差审计（改前实查）

| 面 | 改前行为 | 偏差 |
|---|---|---|
| 冷启落点 | ChatView `.onAppear`：`currentThreadID == nil` 即 `mainID ?? threads.first`——恒落主线（0.7.0 D1 口径） | 与 Muse 模型反：冷启应恢复上次线程 |
| 上次线程记忆 | 无。`currentThreadID` 只是 ChatView 的 `@State`、不落盘；SideChatStore 无此键 | 进程重启即丢，恢复无从谈起 |
| 页签切换（进程内） | 靠 @State 存活＋onAppear 的 nil 守卫「碰巧」保持——非设计保证，视图重建即被上一行恒落主线吞掉 | 语义靠运气 |
| 抽屉「主线聊天」行 | 动作只有 `onClose＋onSelectTab(.chat)`——不切线程：在旁聊里点它，落回的还是那条旁聊 | 与页签语义互串：标着主线的入口不去主线、页签被迫兼任回主线 |
| 聊天时间 | 消息流零时间呈现（条目 createdAt 只用于排序） | 用户点名不科学 |
| 设置 sheet「回聊天」动作 | 只切页签（onRequestChat）——非主线入口 | 无偏差：新模型下同走落点解析回上次对话，未改 |

### 57.2 落值一：页签与主线解绑

- Core 新增 `ChatLandingResolution.landing(currentID:lastThreadID:existingIDs:mainThreadID:)` 四态：`.keep`（进程内当前线程仍在，页签切回保持）／`.restore`（恢复上次）／`.main`（无记录或记录失效回钦定主线）／`.none`（三者均不在名单，调用方沿旧兜底落第一条/空态）。当前 id 已失效（指向已删线程）不粘死、继续向下解析。
- 持久化：`SideChatStore.lastThreadID`（键 `sideChats.lastThreadID`，与主线钦定同仓 UserDefaults，不另造第二套状态；演示模式纯内存同既有口径）。**唯一写入点**＝ChatView `body` 的 `onChange(of: currentThreadID)` 回调——切线程/新建/续聊导入/删当前线程全部经此一处；置空即清记录，下次按记录失效回主线。
- ChatView `.onAppear` 落点改走解析（抽屉选线程仍最优先、待续聊会话仍先行拦截，两条显式改道不变）；0.7.0「冷启永远先落主线」注释原地标注作废。
- 抽屉「主线聊天」行：动作加经 `drawerThreadSelection` 直切钦定主线（ChatView 消费切换并经唯一写入点落盘为上次线程），成**唯一显式回主线入口**；钦定未落定时退化为只切页签、落点解析以主线兜底。
- 未动：0.27.0 会话链接/种子/发送链、0.29.0 `SideChatClassifier.isMain` 双信号、删线程的 `drawerDeletedThreadID` 通道语义（置空后落点由解析接管）。

### 57.3 落值二：聊天时间系统（Core ChatTimeline）

- 落点（锚点走查）：会话首条前恒挂一条；其后与**上一条已挂分隔条的消息**间隔 > 300 秒再挂，恰 300 秒不挂。口径来源（2026-11-10 查证）：微信官方帮助中心《WeChat訊息是如何顯示時間？》「當天的訊息會以每5分鐘為一個跨度地顯示時間」；腾讯云 IM 官方文档《聊天IM的时间戳显示规则》「与最后一次显示时间戳的时间间隔大于5分钟时则再追加」。**与「只看相邻两条间隔」的差别如实记**：4 分钟一条连发时相邻口径全程只有首条，跨度口径约每 5 分钟再挂一条——从官方文档口径取跨度。
- 文案五档（本地时区、日历注入）：今天 HH:mm／昨天 HH:mm／日差 2...6 星期X HH:mm／本年 M月d日 HH:mm／跨年 yyyy年M月d日 HH:mm。相对优先：昨天跨月仍「昨天」、跨年但日差 ≤6 仍走星期档、跨年日差 1 仍「昨天」；未来条目（时钟漂移）只给时刻不编造相对日。
- 渲染：ChatView 消息流逐行前置（微信式素字）——居中、`.meta`（Footnote 13）角色、Palette.inkSecondary、无气泡无底色块；行距沿 LazyVStack spacingL、分隔与所属消息间距 spacingS。
- 条目口径：只对会话条目（user/assistant，即 toolCard 为 nil 者）走查——**工具卡条目不单独占分隔、也不重置锚点**（以所属回合的会话条目时间为准）；思考是 assistant 条目内字段、随其消息回合走；流式行与流内工具卡是当前回合的呈现层尾巴、不另起分隔（本回合分隔由其 user 条目承担）。
- 顺带核查·只登记未改：①抽屉旁聊行/管理页副题走 Core `LocalThreadSubtitle`/`sessionDayTimeText`（今天/昨天/M月d日 三档、无星期档、今天带「今天」前缀）——名单行紧凑口径，与聊天分隔条五档不一，本包未动；②文件页时间走 `AdminFormat.short`（恒 M月d日 HH:mm）——同登记。后续若要全 App 时间口径统一，另包处理。

### 57.4 DD 系列真机终审项

- DD1 页签恢复：在某条旁聊里聊两轮 → 切到文件/目标页签 → 点回会话页签，仍在那条旁聊、位置与内容不动。
- DD2 冷启恢复：停在旁聊里杀进程重开——直接落回那条旁聊（不是主线）。
- DD3 主线入口：停在旁聊 → 开抽屉点「主线聊天」——切到主线本体；之后点页签切走再切回，仍是主线（主线此时即上次线程）。
- DD4 记录失效：删掉当前停留的旁聊后冷启——回主线，不报错不空白死锁。
- DD5 时间分隔·跨度：连发数条间隔 <5 分钟——只有首条上方一条时间；停 6 分钟再发——新消息上方再挂一条；连发中每隔约 5 分钟周期出现一条（跨度口径）。
- DD6 时间文案：翻历史——今天只时刻、昨天带「昨天」、一周内带星期、更早带月日、去年带年月日，各档抽查一条与微信同口径对照。
- DD7 工具/思考回合：带工具卡的一轮——工具卡前后不单独出分隔条，分隔只挂在回合的会话消息上。
- DD8 分隔样式：居中素字、灰、无底色块，与气泡间距自然；暗色模式下同样可读。

### 57.5 交付实录

- 功能提交 7dadd70；CI 42759538188 success，Executed 528 tests, 0 failures（506 基线＋ChatLandingTests 9 测＋ChatTimelineTests 13 测，零删测零改值）。
- IPA：5,107,798 字节、md5 9e3bbd4a578b0943807b863367ba2ffd、独立解包验 Info.plist＝0.30.0/59、bundle site.didichou.oneday，落 ~/workspace/your_files/oneday-v0.30.0/OneDay-0.30.0.ipa。
- 版本五处同改＋grep 验：Project.swift 的 MARKETING_VERSION／CURRENT_PROJECT_VERSION／CFBundleShortVersionString／CFBundleVersion 四处＋SettingsView 页脚「OneDay v0.30.0」一处（本包未漏页脚）。
- §14/MotionTokens/外观定版零改动；0.27.0 会话链与 0.29.0 主线分类器语义未动；施工期生产零写；未自截真机图。

## §58 0.31.0 生成通道迁 /v1/runs（任务制：断线不取消、对账落定、真停止）

用户令（2026-11-10 13:26–13:28）：「大厂 AI 中途退出不会暂停/取消生成，咱们为什么返回/退出就取消＋网络错误一堆」→「直接看 Hermes 怎么做的，分析本质、然后针对修」。本质报告：~/workspace/oneday-design-review/hermes-generation-lifecycle-analysis-20261110.md。

### 58.1 本质结论（先行销账）

1. **断线并不真取消生成**：现 chat completions 通道下客户端断开，Hermes 的 interrupt 在本部署的 gateway runner 生命周期里落空——双探针实测断开后模型照常跑满并完整落库。用户痛点全在呈现层：流断被映射为网络错误横幅、没人回头对账。
2. **结构正解是 Hermes 自带 /v1/runs 任务制**：提交返 run_id、生成与连接分家、events 可按 seq 重挂、status 可轮询、stop 真取消（admission interrupt）、Idempotency-Key durable 重放。GET /v1/runs/{completion_id} 记的是流命运（断开即恒 cancelled、真完成不回改）——**禁用作完成信号**；完成与否的唯一 oracle 是会话 transcript。
3. **落库分段增量**：user 行轮次开始即落、工具行每批 flush、终答生成即 flush；但 assistant 文本轮末才整条可见——对账须按「等段出现」设计，段锚点＝transcript 最后一条 user 行之后。

### 58.2 阶段 A 探针证据（2026-11-10，公网真实路径，探针会话 oneday-probe-runbind/runfree-20261110，事后已归档复验）

- **会话绑定成立**：POST /v1/runs body 带 session_id；锁定会话内两轮 run 完成且第二轮准确复述第一轮暗号——历史以 state.db 为准，body 无需自带历史。
- **模型语义与现通道一致**：逐请求 model 成立（自由会话 v4-pro 完成）；对 flash 锁定会话发 v4-pro 亦被接受并以 v4-pro 完成（源码核实：runs 面只有请求内 route/provider 歧义检查，无会话锁拦截，与 chat completions 现行口径相同——锁仍靠客户端纪律＋会话改模端点，不回退）；provider=custom 被接受并真路由（Qwen run 到达上游后因渠道 13 停用回 503 业务错误，非 runs 面拒绝）。
- **事件形态实测**：message.delta 增量正文、tool.started/tool.completed（带 tool_call_id 与 ≤500 字 preview）、run.completed 终态带 output/usage。**思考直播缺失（唯一受管损项）**：reasoning.available 只是 500 字有损预览且生产 admission 路径未接线（探针 events 里没有）；但 transcript 的 reasoning_content 完整落盘且 Dashboard messages 接口带该字段——取舍：直播期无思考流、落定时从 transcript 全文回填（ReasoningPresentation 对 seconds=nil 只显示「已思考」不编秒数，现成口径）。流式呈现差别如实记：直播只有正文增量＋工具卡，思考盒在落定时出现。
- **幂等成立**：同 key 同体重提回同一 run_id 且 replayed:true；同 key 异体 409。
- **图片成立**：input 单元素消息数组（text＋image_url data: URL）被接受并正确识图。
- **真停止成立**：sleep 30 工具 run 在约 4 秒 stop→200 stopping→终态 cancelled；transcript 停增（+12 秒复查不长），工具行留 [Command interrupted]。
- **窗口限制如实记**：events 缓冲约 300 秒后被扫（已完成 run 的 events 回 404）；状态记录内存约 3600 秒；Idempotency-Key 保留 24 小时。重挂只作尽力，落定永远以「状态＋transcript」为准。
- 探针副作用一条：Run A 的 memory 工具经 write-gate 暂存待审批（pending 59ba48f2，仅 staged 未落库），留用户在审批面处理。

### 58.3 路线选择与施工（路线甲）

关键项全过→路线甲：发送通道整体迁 /v1/runs，chat completions 发送路径就此退役（chatStream 客户端方法保留供他用，本版聊天不再走）。路线乙（现通道对账化）未启用，留档备查。

- **状态机（Core RunTurnStateMachine，纯值类型）**：submitting→generating（受理）/failed（明确拒绝）/unknown（结果未知）；generating 流断→unknown→（前台）reconciling→（轮询活动）generating…；终态证据＋transcript 落定→finished/failed/cancelled。铁律落进转移表：断线/超时永不映射失败、落定后事件全忽略、预算耗尽停 unknown 不落失败。
- **持久账本（Core RunLedger＋App RunLedgerStore）**：提交前先落账（threadID/sessionID/runID/idempotencyKey/userEntryID/停止意图），杀进程可恢复；受理回执丢失用同 key 重演取回 run（服务端幂等保证不双跑，重演输入从本地用户条目重建、不另存载荷）。发送互斥：本线程有未落定账本时新消息不叠发（输入退回＋提示＋先对账）——服务端无 per-session 锁、段锚点靠单飞成立。
- **驱动（ChatView driveRun/followRunEvents/reconcileRun）**：提交（瞬断同 key 重试 ≤2、明确拒绝才真失败且消息留痕照实报）→events 订阅（增量过双 PublishGate、工具卡实时拼装、isWakingModel 沿用）→断线半截落盘＋进对账（状态轮询＋events 重挂＋transcript 段落定，10 分钟预算，耗尽给体面出口「生成仍在服务器进行中，稍后回来自动补齐」＋账本保留）。落定以 RunTranscriptSettle 整段替换半截（工具卡走 ToolCardBuilder、思考回填、failed_turn 行判失败不当答案、hidden 行排除）。
- **停止＝真取消**：发送舱停止键走 requestRunStop——提交窗口内取消本地提交任务（账本已记停止意图、下次对账执行真停）、其余发 runs stop 并由订阅/对账等终态落定，文案可诚实写「停止生成」。
- **合并删冗余**：0.20.0 的切后台记账（backgroundedDuringStream）＋内存待恢复账（PendingStreamRecovery）＋删半截以原上下文自动重发的恢复整类删除；Core StreamRecovery/StreamFailure 与其 6 测同删（职责被 RunTurn 吸收）；0.27.0 删除的无头重放不复活、本版亦无任何自动重发。恢复入口统一为 resumeRunIfNeeded（回前台＋进线程 .task 双触发，消费账本）。
- **客户端**：HermesClient 新增 submitRun（202 宽容、Idempotency-Key 头、provider 透传）/runStatus（404→nil）/runEvents（AsyncStream、每行过 Core RunEventParser、断流只结束不抛错——定性归状态机）/stopRun（200/404/409 均按受理）；SessionMessage 补 reasoning_content/reasoning/display_kind 三字段（transcript 回填与失败段判定靠它）；DemoHermesClient 同步实现四方法（演示走 output 合成落定）。
- **单测**：新增 RunTurnTests 40 测（状态机全转移/事件解析/DTO/输入编码/账本/段落定），删 StreamRecoveryTests 6 测，总数 528→563（净增、只增不减口径按总量守）。

### 58.4 EE 系列真机终审项

- EE1 杀进程见成品：发一条长回复，生成中途杀 App——重开进该对话，稍候（对账）应见完整回复落定，不报错、不出现重复用户消息。
- EE2 切后台两分钟：生成中切后台两分钟再回来——直播续上或直接见成品（附「已重新连接，回复已补齐。」提示），全程无网络错误横幅。
- EE3 真停止：发一条带长工具调用的请求，生成中点停止——提示「已停止生成。」；之后回服务端/管理页看该会话，transcript 不再增长（无睡醒续写）。
- EE4 弱网提交：飞行模式下发送——明确失败提示（照实报错）、消息以用户条目留痕、无假「已发送」；关飞行模式后手动重发正常。生成已受理后开飞行模式再关——不报错、回来自动对账补齐。
- EE5 思考回填：问一个需推理的问题，落定后思考盒出现（文案「已思考」、无秒数）；直播期间只有正文与工具卡、无思考盒属预期（58.2 取舍）。
- EE6 工具卡对账：带工具调用的一轮落定后，工具卡与管理页 transcript 一致（张数/成败），无直播半截卡残留。
- EE7 叠发守卫：上一轮未落定（切后台刚回来对账中）时发新消息——被拦下并提示「上一条还在生成中…」，旧轮落定后可正常发送。
- EE8 模型面回归：三候选（flash/v4-pro/Qwen）各发一轮可正常落定（Qwen 以渠道恢复为前提，渠道停用时应得服务端失败原文而非客户端网络错误）。

### 58.5 交付实录

- 功能提交 458f6a6＋测试修正两笔（72a9918 相位比较关联值、e940d3a 提交中流断归未知——均为测试对齐状态机转移表，实现未改）；CI 42768305956 success，Executed 563 tests, 0 failures（528 基线－StreamRecoveryTests 6＋RunTurnTests 40，净增 35）。
- IPA：5,164,319 字节、md5 ea044f360e00e75e41cb9c1c88879b9f、独立解包验 Info.plist＝0.31.0/60、bundle site.didichou.oneday，落 ~/workspace/your_files/oneday-v0.31.0/OneDay-0.31.0.ipa。
- 版本五处同改＋grep 验：Project.swift 四处（MARKETING_VERSION／CURRENT_PROJECT_VERSION／CFBundleShortVersionString／CFBundleVersion）＋SettingsView 页脚「OneDay v0.31.0」。
- 施工期生产零写（仅阶段 A 探针：两条 oneday-probe-run* 会话已归档复验；write-gate 待审批一条 staged 未落库，见 58.2）；未自截真机图；EE1–EE8 待真机终审。

## §59 0.32.0 三页工程 P1（点子生成管道＋点子页升级＋底栏 tint 修正）

用户 2026-11-10 14:19 逐条拍板（设计档 feed-ideas-goals-benchmark-design-20261110.md）：本包落 3A 点子每日晨间生成一轮、4A 采纳落点 kanban、8A 生成用 deepseek-flash、2A tint 随包改（案甲＋）。1A 五格与 7B/9B 属 P2/P3，本包不动。

### 59.1 桥（oneday-bridge，888→1509 行，生产已部署验收）

- **idea 五字段**：source（generated/manual）、evidence、evidenceRef、status（pending/adopted/dismissed/expired）、taskId、expiresAt（生成卡 createdAt+14 天、手记 null）。POST /ideas 接受 source；source=generated 且 evidence 空 → 400（无依据不落卡的硬门，API 与生成器共用同一校验口径）。新增 PATCH /ideas/{id}：只许改 status/taskId，流转 pending→adopted/dismissed（adopted/dismissed/expired 终态），taskId 落字即置 adopted，假 id 404、非法流转 400 人话。
- **过期口径定版**：调度 tick（20 秒）清扫落盘——pending 且 expiresAt 到期的生成卡置 expired 持久化，读时不计算，存储状态即唯一真源。
- **brief 实体**：GET/PUT /meta/brief（桥 meta 单字段，三页共用方向文本，横切 D）；PUT 上限 4000 字。
- **生成管道**：桥内调度（复用监测的 20 秒 tick 范式，非 Hermes cron——监测 rollout 已判 cron 无非 agent 触发通道、钥匙不进 prompt），每日 07:30（Asia/Shanghai）一轮，nextRunAt 持久化于 meta、重启不丢。素材只读拼装：brief＋目标（里程碑进度）＋监测近 7 天变化＋已忽略 30 天标题避让清单＋Dashboard cookie 登录（四字段契约，缺 provider 回 422）读近 7 天会话标题（排除归档/probe/生成会话自身）。生成走 Hermes POST /v1/runs（model=deepseek-flash、Idempotency-Key 按轮、优先无会话提交、网关要求会话时自动落 oneday-ideas-gen 专用会话重试），status 轮询至终态（600 秒上限；waiting_for_approval 滞留 60 秒即 stop 本轮——无头生成不等人审批）。产出严格折叠：JSON 数组逐卡校验（标题/正文/evidence 非空、标题不与存量重复、goalId 不认识则置 null、上限 3 张），不合格计数 dropped；失败/跑空只记账不落卡。账面 GET /ideas/generation（lastRunAt/nextRunAt/running/history 30 轮）＋ POST /ideas/generate 运维手动触发（生成中 409）。
- **首轮实录（生产，2026-11-10 下午手动触发）**：第一跑因登录缺 provider 回 422、且失败注记曾漏进素材正文被模型当事实凑出一张卡——两处已修（登录四字段；注记只进 round record 的 materialNote、永不进素材），凑数卡已删。第二跑 status=ok、produced=3/dropped=0：三卡依据各引真实会话编号（S5 复盘 150 条、S1 登录 422 排查、S11 P3TEST 验收批），字段全形、expiresAt=+14 天。下一轮已排 2026-11-11 07:30。
- **部署与回滚**：env 增 HERMES_API_KEY/HERMES_DASH_USER/HERMES_DASH_PASSWORD（自 credentials.txt 管道注入 env 文件、0600；`docker compose restart` 不重读 env_file、须 `up -d` 重建——本轮实证并记档）。备份 oneday_bridge.py.bak-20261110-ideasgen、data.json.bak-20261110-ideasgen（桥目录内）；回滚＝还原两备份＋up -d（旧脚本 _load 不认 meta 键、会保留未知键？——实测口径：旧 _load 只读四表、写入时 meta 丢失，生成账面随之清零，ideas 五字段被旧 _idea_view 吞掉但数据本体在盘上，升回新版即恢复呈现）。只重启 oneday-bridge 本体，其余容器与内存（52.6%）无扰动。
- **生成提示词资产**：IDEAS_GEN_PROMPT 常量（桥源码内，~/workspace/hermes-deploy/oneday_bridge.py 生成节首）——素材编号 S/G/M、evidence 必填、0–3 张、禁工具/禁外发类提议，改词即改该常量后重启桥。

### 59.2 App（点子页升级）

- **模型**：BridgeIdea 五字段宽容解码（旧载荷缺失按 manual/空依据/pending 収）；IdeaSource/IdeaStatus 枚举；BridgeIdeaPatchRequest（nil 不落键）；BridgeGenerationInfo/Run DTO；Core IdeaBoard 呈现口径（待阅排序＝生成在前手记在后各按时间倒序、已采纳近 30 天、空态二分 neverProduced/cleared、过期天数、任务状态派生文案）＋11 测。IdeaTaskPlan 任务正文增「依据：」行（有依据才带）。
- **真源迁移**：IdeasStore 退役本地 convertedIdeaIDs——isConverted 改读 idea.isAdopted（status=adopted ∨ taskId 落字）；转任务走 KanbanStore.createTaskReturningID（createTask 抽 impl、Bool 语义不变），确认落板后 PATCH 回写 taskId、回读核对才算完成，回写失败如实留 notes 不回滚任务。IdeaConversionMarks 类型与测试保留为存档（注释已标退役）。
- **页面**：描边卡改扁平行（List plain＋pageBG 行底）：34pt 来源瓷砖（S 会话/G 目标/M 监测/手记铅笔/生成灯泡，按 evidenceRef 首字母映射）→ 标题 Headline semibold 2 行 → 说明 Body inkSecondary 3 行 → 依据行（Footnote「依据 · …」，仅生成卡）→ 信息行（目标 chip＋相对时间＋过期倒数/任务状态）。分区 待阅/已采纳；待阅行左滑与长按菜单给「忽略」（PATCH dismissed、不弹确认），长按另有删除。详情页新立：全文＋依据组（带素材编号）＋信息组（来源/时间/过期/关联目标/状态）＋任务组（状态＋打开任务详情 sheet）＋动作组（转成任务/忽略/删除确认），删成回读确认才退页。空态二分：neverProduced＝「还没有点子。每天早上我会想一轮，你也可以点＋先记一个」；cleared＝「这一轮的点子都处理完了。明早会再想一轮…」。列表页脚明示节奏（「点子每天早上更新一轮 · 上次生成 …」，有账才带时刻）。手记新建 sheet 不动。run-now 钮不做（设计档定版：不假承诺立即生成）。
- **tint（2A/案甲＋）**：ContentView 根 .tint(.primary) 撤下、收进四格内容根各自一份——栏件由宿主按 TabView 本层环境构建（0.4.3 同理），根 tint 不再到达栏件、选中垫回系统默认中性浅灰（Muse 同位置同明度口径）；内容区强调色核查结论：全仓显式 .tint 仅根一处与 BrowserView/RichContentViews 两处 .white 覆写（不受影响），内容控件（链接/开关/Picker/按钮）此前全靠根 tint 继承——收进内容根后继承链一字不变；设置 sheet、全部对话、抽屉本就在 TabView 之外、此前此后都不吃这行。0.22.0「.primary 定案」注释已加 0.32.0 口径更新。

### 59.3 FF 系列真机终审项

- FF1 晨间卡真出现：明早 07:30 后打开点子页——待阅区应有 ≤3 张生成卡（或空态文案转「清完」侧），依据行可溯源到真实会话。
- FF2 采纳全链：对一张卡点「转成任务」——任务板（枢纽任务段）出现该卡；回点子页该卡进「已采纳」分区、行尾显任务状态；杀进程重开仍在（服务端真源）。
- FF3 忽略：左滑忽略一张卡——立即离场、刷新不回；详情页忽略同效。
- FF4 tint 并排：与 Muse 并排看底栏——选中格垫应为浅灰、与 Muse 同位置同明度；四格内容内的链接/开关强调色应仍为墨色（不回蓝）。
- FF5 详情全集：生成卡详情——依据全文、素材编号、过期日期、关联目标（有挂靠时）齐全；打开任务详情能落到对应任务。
- FF6 手记回归：＋新建手记点子——出现在待阅区手记段（生成卡之后）、无依据行、不过期文案。
- FF7 空态：把待阅全部忽略/采纳后——空态显「这一轮的点子都处理完了」而非「还没有点子」。

### 59.4 交付实录

- 功能提交 010f14a（10 文件，+1150/−161）；CI 42771107158 success，Executed 574 tests, 0 failures（563 基线＋11 新测：五字段全形解码/旧载荷默认/PATCH 编码/生成信息解码/待阅排序/已采纳 30 天窗/空态二分/过期天数/任务状态派生/任务正文带依据）。
- IPA：5,247,107 字节、md5 32cddbfaed5b11580aa74ecf6aa860bb、独立解包验 Info.plist＝0.32.0/61、bundle site.didichou.oneday，落 ~/workspace/your_files/oneday-v0.32.0/OneDay-0.32.0.ipa。
- 版本五处同改＋grep 验：Project.swift 四处（MARKETING_VERSION／CURRENT_PROJECT_VERSION／CFBundleShortVersionString／CFBundleVersion）＋SettingsView 页脚「OneDay v0.32.0」。
- 桥侧生产验收（59.1）：公网契约 13/13 PASS（401/空表/下一轮时刻/brief 往返并复原/临时卡全链 PATCH 流转与 400·404 门/generated 无 evidence 400）；本地桩测 31/32（唯一 FAIL 为断言本身写反、已单独核实请求体）；过期清扫本地验过；首轮真实生成 produced=3（卡 id 与依据见 59.1），下一轮 2026-11-11 07:30 已排。
- 施工期生产动作仅 oneday-bridge 本体（部署/env/重启/首轮触发/凑数卡删除各一次），内存峰值 52.6%，其余容器未动；未自截真机图；FF1–FF7 待真机终审。

## §60 0.32.1 旧思维审计整改（F04 止血＋F05 止血＋F03 App 侧）

缘起：2026-11-10 旧思维全面审计（oneday-design-review/legacy-thinking-audit-20261110.md）17 条发现，用户 15:13 拍板「必改两件（F04/F05）＋五桥凭据分权（F03/R8）一起修」。本版只做止血与 App 侧，F04 的迁 SQLite（R15）与 F05 的服务端目录（正道）均不在本轮。

### 60.1 F04 止血（桥侧，先于本版独立部署）

- oneday_bridge.py 的 `_load()` 解析失败路径重写：原文件改名隔离为 `data.json.corrupt-<时间戳>`（原件永不删除）；进程以内存空库＋只读降级启动——`_dispatch` 对一切非 GET 请求统一回 503（文案明示只读降级），`_save_locked()` 加硬闸（降级态 raise，内部/调度写路径同样不许把空库回写正式文件）；`/health` 附 `degraded` 标记与 `degradedReason`、`writesEnabled:false`。正常路径行为零变化。
- 验证：本地桩测 13/13（损坏启动：隔离文件存在且内容完好、正式文件未被重建、读端点 200、写端点 503；正常启动回归：种子可读、写落盘、无隔离文件）。生产部署：备份 `oneday_bridge.py.bak-20261110-f04`、`data.json.bak-20261110-f04`，只重启 oneday-bridge；公网实测 /health `degraded:false`、目标/点子读端点正常、今晨 3 张生成卡俱在、数据与备份逐项一致、无 corrupt 文件产生。

### 60.2 F05 止血（Qwen 下线呈现）

- 取舍：审计给「隐藏或明确置已停用」二选一——取**隐藏**（选择器结构改动最小：`ChatModels.items` 只剩 DeepSeek 两项；`initialSelection`/`selectChatModel` 的 contains 校验天然拒绝下线 id）。Qwen 进 `retiredItems`：不可选、不进选择器，仅保留显示名/短名映射（历史消息名牌与 ModelDisplayNames 翻译不许掉成原始 id 或「服务端默认」）。
- 冷启承诺整路拆除：`ChatModels.coldStartID` 删除；ChatView 的 `isWakingModel` 状态、等待行「模型唤醒中，冷启动约 1–3 分钟…」文案及全部置位/复位点删除——等待只剩打字点。
- 落回如实提示：已存选择恰是 Qwen 时，选择经 initialSelection 落回 deepseek-flash，AppState 派生一次性 `modelFallbackNotice`（文案在 Core `retiredFallbackNotice`），聊天页经现行 notice 条呈现一次；消费时落回值同步落盘、永不重现。
- **正道待办指针**：模型目录改服务端下发（id/展示名/状态位：可用/降级/停用＋不可用原因），App 只渲染、静态表降为离线兜底——排后续版本，本轮不做。

### 60.3 F03 App 侧（五桥凭据分权，R8）

- Core 新立 `BridgeKeyScope` 五值（overview 只读/oneday 业务写/writegate 审批写/box 执行/device 设备工具）＋`BridgeKeyImport` 解析器（格式每行 `scope: 钥匙`，半角/全角冒号、标签归一、说明行跳过、未识别行计数上报、同 scope 后行覆盖；与服务器侧 bridge-keys.txt 逐字对齐）。
- Keychain 分项存：`bridge.key.<scope>` 五键；`BridgeKeyStore.read(scope)` 分项优先、**未配置时临时回退旧共用钥 writeGateKey**（仅过渡：服务器轮换后旧钥在各桥 env 退役、回退值被桥拒绝而自然失效；**回退与 writeGateKey 键在轮换完成后下一版删除**，代码注释与本节双记）。七个客户端各改读自己 scope（Overview→overview、OneDay→oneday、WriteGate/Memory→writegate、Box 三客户端→box；device 尚无客户端、仅导入与状态位）。
- 设置页「桥钥匙」（原审批桥钥匙页改版）：钥匙组逐项状态（**只认分项本体**，不许拿回退冒充已分权）＋钥匙组导入（多行粘贴框一次填满五项、导入结果如实报写入项与未识别行数、草稿导入后即清）＋旧共用钥区（过渡，粘贴/更换/移除保留）。设置汇总行文案同步诚实化：已分权 N/5、已配置 N/5、旧钥匙（过渡）、未设置四档。未配置的功能面沿用各客户端 noKey 诚实态（连接器页/浏览器/云电脑文案已同步改指桥钥匙分项）。

### 60.4 GG 系列真机终审项

- GG1 Qwen 下线：模型选择器只剩 DeepSeek Flash / V4 Pro 两行，无 Qwen、无「冷启/唤醒」字样；发送等待只有打字点。若原选恰是 Qwen：首次进聊天页应见一次性提示「原选模型 Qwen3-30B 已停用，已自动切回 DeepSeek Flash」，重进不再出现。
- GG2 未导入前回归：不做任何导入，现装使用——总览/目标点子/审批/Box 各面照常工作（旧钥回退）。
- GG3 导入全链：设置·桥钥匙粘贴 bridge-keys.txt 整段导入——五项状态全变「已配置」，设置汇总行显「已分权 · 5/5」；各桥功能照常（此时走分项钥）。
- GG4 部分导入诚实态：只导入一两项时，逐项状态与汇总行如实报数（如「已配置 2/5」），未配项不许显已配置。

### 60.5 交付实录

- 功能提交 a7589ef（23 文件，+560/−112）；CI 42774943285 success，Executed 582 tests, 0 failures（574 基线＋8 新测，只增不减：ChatModels 改写 4 测＋新增下线名保留/落回提示 2 测、BridgeKeyImport 新立 6 测）。
- IPA：5,266,243 字节、md5 9e975e4cc1c7f61c3fe989b7f24c481c、独立解包验 Info.plist＝0.32.1/62、bundle site.didichou.oneday，落 ~/workspace/your_files/oneday-v0.32.1/OneDay-0.32.1.ipa。
- 版本五处同改＋grep 验：Project.swift 四处（MARKETING_VERSION 0.32.1／CURRENT_PROJECT_VERSION 62／CFBundleShortVersionString 0.32.1／CFBundleVersion 62）＋SettingsView 页脚「OneDay v0.32.1」。
- F04 桥止血同批独立交付（见 60.1）：本地桩测 13/13、生产已部署实测。五桥凭据分权服务器侧（R8 后半）于本 IPA 出包后执行，钥匙组文件 bridge-keys.txt 交付用户导入（GG3）；过渡期影响：装 0.32.1 前各桥照常（服务器尚未轮换）、装后未导入前靠旧钥回退照常、导入一次即完成分权。
- GG1–GG4 待真机终审（本版终审代号 GG，承 §59 的 FF 序）。

### 60.6 服务器侧轮换落账（R8 后半，同日执行）

- 执行序：本 IPA（0.32.1/62）出包后才动服务器钥匙。五桥逐桥轮换（备份 *.bak-20261110-f03 共 10 份、只重建该桥容器）：各桥独立随机钥＋各自 env 变量名（OVERVIEW_/ONEDAY_/WRITE_GATE_/BOX_/DEVICE_BRIDGE_KEY），旧 WRITE_GATE_KEY 从五桥 env 全数退役（0 残留）；验收矩阵 30 格全对（每桥仅己钥可通、余四新钥＋旧钥全 401）；Hermes 本体未动。全程记录见 ~/workspace/hermes-deploy/bridge-keys-rollout-20261110.md。
- 服务端例外一处：overview 内部调 write-gate /status 改用 write-gate 钥作服务凭据（仅服务器 env、App 不持有），待批数与源端 counts 实测一致。
- **过渡期真实影响（更正 60.3 的乐观口径）**：轮换完成后，旧共用钥已被各桥退役——现装 0.32.0 的桥功能即刻 401（聊天本体不受影响）；装 0.32.1 后、导入钥匙组之前，回退读到的旧钥同样被拒、桥面呈未连接诚实态；粘贴 bridge-keys.txt 导入一次即全恢复并完成分权。回退机制保留至下一版删除的口径不变（其价值在轮换前的窗口与单桥再轮换场景）。

## §61 0.33.0/63 三页工程 P2（目标补深：状态/进展/子目标/每周简报）

缘起：三页对标设计（oneday-design-review/feed-ideas-goals-benchmark-design-20261110.md §2）P2 期；用户拍板 5A 每周简报一封／7B 子目标一期做界面／9B 对话式创建。守审计新规矩（legacy-thinking-audit R 档）：目标数据以桥为唯一真源、不在 App 侧建副本账；新端点先在桥侧落契约再接 App。桥于本版开工前刚落 F04 只读降级闸与 F03 新钥（ONEDAY_BRIDGE_KEY），本节全部写路径在降级闸之后（降级态非 GET 一律 503、不动）。

### 61.1 桥契约（oneday-bridge P2 扩展，先于 App 落）

- goal 加四字段：`status`（active|completed 两态，学 Muse 无暂停；旧记录读作 active）、`completedAt`（桥在流转时落字、客户端永不自写；重开清空）、`parentId`（子目标恰好一层：父必须存在且为顶层、已有子目标者不得再成为子目标、自指拒绝，违者 400 人话）、`source`（manual|chat，默认 manual——9B 的桥侧面先行落字，见 61.4）。PATCH /goals 支持增量 status/parentId（与既有全量编辑体并存）；goal 视图另嵌 `latestEntry`（最新条目只读穿嵌入，供列表摘要免 N+1，不是第二份存储）。
- 进展条目集合 goalEntries：{id, goalId, body, source: user|agent, createdAt}，端点 GET/POST /goals/{id}/entries、DELETE /goals/{id}/entries/{eid}；append-only 不可编辑（纠错＝删单条或补新条）；正文空 400、上限 2000 字；目标不存在 404。
- 简报集合 briefings：{id, goalId, period（ISO 周，Asia/Shanghai）, title, body, createdAt}，端点 GET /goals/{id}/briefings（降序）；只由简报管道写、客户端永不改。
- monitor 加可选 `goalId`（建单校验存在、删目标置 null，与设计档 §2.4 定版一致）；删目标级联：子目标/条目/简报随删，点子与监测只解绑（goalId=null）。
- 进度百分比不设生成面：里程碑计数是事实、App 自 GoalProgress 派生，桥与模型都不许编造百分比。

### 61.2 每周简报管道（桥内调度）

- 节奏：桥内 20 秒 tick（与监测/点子生成同纪律），每周一 08:00（Asia/Shanghai）一轮；账面 GET /goals/briefings（lastRunAt/nextRunAt/history，保留 30 轮）；手动触发 POST /goals/briefings/generate（202/409，与点子生成同形）。
- 范围：仅 active 顶层目标（子目标是父目标档案的一部分、不单独成信）。素材只读拼装：近 7 天进展条目＋关联任务状态（由本目标点子采纳而生的 kanban 任务，经 Dashboard cookie 通道读任务板现值——与会话标题同一通道）＋挂靠监测近 7 天变化（monitor.goalId 归属）。**无素材的目标跳过并在账面记 skippedNoMaterial，绝不硬凑信**（与设计档原「无变化也出信」分歧点：从用户 5A 落地口径——无进展如实 0 封）。
- 生成：每目标一次 POST /v1/runs（deepseek-flash，Idempotency-Key＝goal-brief-<周期>-<目标 id>），产出严格解析 {"title","body"} 才落库；(goalId, period) 唯一、重跑幂等（already-exists 记账）；失败注记（如任务板读不到）只进账面 materialNote、永不进素材（P1 教训）；每轮上限 20 个目标。
- 部署实测：桥备份 oneday_bridge.py.bak-20261110-p2／data.json.bak-20261110-p2，只重启 oneday-bridge 本体（内存 51%）；本地自测 34/34（契约＋桩测整轮）；生产公网契约实测全过，手动一轮真产 1 封（临时目标＋一条进展，信体如实写「本周只有一条进展记录」、零编造），验后临时数据删净、生产回 0 目标/3 点子原状。施工中修一真 bug：简报 DTO 视图与账面视图同名 `_briefing_view` 互相遮蔽致 GET 简报列表 500，已改名分立并补回归测。

### 61.3 App 落点

- Core：BridgeGoal 宽容解码 P2 五件（旧载荷按 active/顶层/manual/无条目收）；BridgeGoalStatusPatchRequest（{status} 独立体）；BridgeGoalEntry/BridgeBriefing DTO 与请求体；`GoalBoard` 呈现口径纯函数（顶层过滤/子目标/状态分组/4 条折叠/摘要来源＝最新条目→备注→里程碑计数/里程碑全勾判据），单测钉死。
- 列表改扁平行（照 13:06 实测形态转译）：分组头（绿点圆底「进行中」/灰系「已完成」默认收起）→ 行＝22pt 方形勾选框（即完成开关，PATCH {status}＋回读确认 completedAt 落字）＋标题 title3 semibold＋进展摘要 2 行（.body 灰，源＝latestEntry）＋右端 ⋮ 菜单（编辑/标完成或重开/删除）；单组超 4 条折叠「显示另外N项」；底部常驻创建区（＋创建目标＋说明，点入仍走表单 sheet）。里程碑进度条退出列表行、移详情头部（设计档明示取舍）。
- 详情改呈现页（分区序定版）：①头部（标题＋状态 chip（完成带 completedAt 相对时间）＋所属目标回链＋备注＋里程碑进度条＋「里程碑已全部完成，可以标为完成了」事实提示——只提示、不自动完成）②简报（最新一封信卡：标题/正文 3 行/日期＋周期，点开 GoalBriefingsView 读全部信件全文，只读）③里程碑（CheckRow 就地勾选，走既有全量 PATCH＋逐项对账的 saveEdits，不新开写路）④进展（顶部记一条输入＋时间线倒序，来源标 你记的/智能体记的＋五档时间，长按删单条纠错；POST/DELETE 后回读确认）⑤子目标（子行勾选切状态＋点进子详情；底部新增一行，POST parentId＋回读确认；子目标详情无此区＝一层封顶明示，完成子目标不自动完成父目标）⑥状态与危险区（标为完成/重新打开、删除——确认文案同步级联口径）。编辑收进 GoalEditView 独立 sheet（原详情编辑器整段迁入，草稿全量口径一字不变）。
- GoalsStore：goals 仍是唯一目标状态面；详情面 entriesByGoal/briefingsByGoal 只做按需拉取与写后回读刷新（detailLoadedIDs 区分「未拉」与「拉过为空」），不建本地副本账；setStatus/addEntry/deleteEntry/toggleMilestone 全走回读确认、失败留 notes 人话。

### 61.4 9B 对话式创建：本版停下（实查判不可行）＋结构性替代方案

- 设计定版机制＝「由 Hermes 建目标」（设计档 §2.4：选类别＋一句话、智能体落桥）。实查证据（2026-11-10 15:4x 服务器一手）：Hermes config 的 mcp_servers 只有 notion、github 两条，**没有 oneday-bridge**；桥的写路径只认其 scope Bearer 钥，该钥只在桥 env 与用户 App Keychain 里，智能体侧无任何工具/技能持有它（skills 目录全文检索 8646/oneday-bridge/goals 仅命中 hub 索引缓存、非技能本体）；且桥端口绑宿主机回环、Hermes 容器另一网络命名空间。故智能体在对话里**没有任何能落桥建目标的路径**——9B 按简报纪律停下，不许自创土办法（解析聊天散文拼 POST 属土办法，不做）。
- 本版落的只有桥侧契约面：goal.source 已支持 chat 落字与校验（61.1），未来智能体写路径接通时契约零改动；App 创建入口保持表单（列表底创建区文案按真实机制写，不冒充对话式）。
- 结构性替代方案（待用户拍板）：给 oneday-bridge 加 MCP 门面（与 device-bridge 预建同形：/mcp 端点 goals_create 工具、独立 scope 钥、只许建目标＋记进展两件写事），随已排队的「Notion/GitHub 验活→重启 Hermes 一次收官」同一生产窗口注册进 Hermes config；接通后 App 目标页加「对话创建」入口＝开一条专用旁聊，用户说一句话、智能体调 goals_create(source=chat) 落桥、App 回读列表确认出现才报成。本版不预注册、不动 Hermes 配置。

### 61.5 HH 系列真机终审项

- HH1 列表形态：进行中组绿点头＋扁平行（勾选框/标题/进展摘要/⋮），与 Muse 目标图并排对形态；摘要显最新进展条目原文（无条目时显备注）。
- HH2 勾选即状态：点行首方框→目标进已完成组（组默认收起，展开可见、框已勾）；点已完成行框→回进行中组。全程杀进程重开状态不丢（桥真源）。
- HH3 详情呈现：打开详情是看不是改——头部进度条在、简报卡在（无简报时显节奏说明）、里程碑就地勾选即存（杀进程重开不丢）、编辑在右上角 sheet 里。
- HH4 进展时间线：记一条→时间线置顶出现（来源「你记的」＋时间）；长按删除→消失；杀进程重开与桥一致。
- HH5 子目标：详情底部加子目标→子行出现；勾子目标完成→父目标不自动完成（仍在进行中组）；进子目标详情无再加子目标的区（一层封顶）；删父目标→子目标一并消失。
- HH6 简报真信：等一个有进展的目标过周一 08:00（或由我方手动触发一轮）→详情简报卡出现当周信、点开全文可读；信里引用的进展/任务/监测与事实逐项对得上、无编造；无进展的目标不收到信。
- HH7 里程碑全勾提示：把某目标里程碑全勾→详情头部出现「可以标为完成了」；目标本身不自动完成，仍需手点。

### 61.6 交付实录

- 功能提交 dad684b（8 文件，+1752/−151）；CI 42778416940 success，Executed 595 tests, 0 failures（582 基线＋13 新测，只增不减：GoalDepthTests 解码 5＋请求体 4＋GoalBoard 4）。
- IPA：5,444,364 字节、md5 eb2b99231e8e20282a5d4a9d08f5f011、独立解包验 Info.plist＝0.33.0/63、bundle site.didichou.oneday，落 ~/workspace/your_files/oneday-v0.33.0/OneDay-0.33.0.ipa。
- 版本五处同改＋grep 验：Project.swift 四处（MARKETING_VERSION 0.33.0／CURRENT_PROJECT_VERSION 63／CFBundleShortVersionString 0.33.0／CFBundleVersion 63）＋SettingsView 页脚「OneDay v0.33.0」。
- 桥 P2 同批独立交付（见 61.1/61.2 与 rollout 附录 P2 节）：本地自测 34/34、生产已部署实测（手动一轮真产 1 封、验后删净、生产数据零残留）；下一轮自动简报 2026-11-16（周一）08:00（届时有 active 且有素材的目标才成信，生产当前 0 目标、如实 0 封）。
- 9B 对话式创建本版未落（见 61.4）：桥 source=chat 契约已备，App 入口保持表单；替代方案待用户拍板。
- HH1–HH7 待真机终审（本版终审代号 HH，承 §60 的 GG 序）。

## §62 0.33.1/64 凭据体验纠正（用户只持一把登录密钥）＋底栏通透/字形修正

### 62.1 用户定版口径（2026-11-10 16:08–16:11 三连纠正）

- 原话：「谁家的密钥这么多？不需要懂吗？能不能提高用户体验，就一个单独的 Hermes 登录密钥就行，其他不需要」「底部导航栏仍显实心」「人家的灯泡不是实心的」。
- 定版：**用户永远只持一把 Hermes 登录密钥**——分权（F03/R8）是对的、但那是服务器内部的事；产品级原则（大厂逻辑：一次登录、内部服务凭据用户不可见）。0.32.1 的 App 侧五分项钥＋粘贴导入整套作废退役。
- 落法：App 桥请求统一以聊天同一份登录密钥（api.key）作 Bearer；服务器 nginx 入口以 auth_request 向 Hermes 网关面验这把钥、通过后在服务器内部换成各桥自己的服务钥（桥钥只存服务器 env、轮换不再打扰用户）。服务器段见本版交付实录与 hermes-deploy/bridge-keys-rollout 追记；nginx 过渡双模（旧桥钥直通）在用户装 0.33.1 确认后撤除。

### 62.2 App 退役清单（本节代码面）

- 删除：`OneDayCore/BridgeKeyScope.swift`（BridgeKeyScope 五值＋BridgeKeyImport 解析器整件）；`OneDayApp/WriteGateKeySettingsView.swift`（「桥钥匙」设置页整件）；`Tests/BridgeKeyImportTests.swift`（6 测随解析器退役，由 62.3 新测等量接替、总数只增不减）。
- 设置页：删「桥钥匙」导航行＋汇总四档文案（已分权 N/5／已配置 N/5／旧钥匙（过渡）／未设置）＋状态回读（refreshWriteGateKeyStatus/bridgeKeyGroupStatusText/两枚 @State）；路由 `.writeGateKey` 自 SettingsRoute 退役；连接器目录 writeGate 服务的「桥钥匙」入口行删除；`navigationDestination` 对应分支删除。
- 取钥统一：七个桥客户端（WriteGate/Memory/Overview/OneDay/Box/BoxFiles/BoxShell）的 `bridgeKey` 一律改读 `BridgeCredential.read()`＝聊天同一份 api.key（WriteGateKeyStatus.sanitizedForStorage 清洗口径复用）；`BridgeKeyStore`（分项优先＋旧钥回退）整件删除；`CredentialKey.bridgeKey(_:)` 删除；`CredentialKey.writeGateKey` 键名保留作档案（无人读写、存量值不删、回滚 0.32.1 仍可用）。
- 启动清理：`OneDayApp.init` 调 `RetiredBridgeKeyCleanup.purge()`——按 OneDayCore `RetiredBridgeKeyAccounts` 清单删 Keychain 五条 bridge.key.*（只删本 App 写过的这组键；api.key/auth.*/server.baseURL/writegate.key 一概不动）；每次启动幂等执行。
- 保留：`WriteGateKeyStatus`（Core）整件保留——其 sanitizedForStorage 仍是凭据清洗的单一口径，枚举的桥钥匙状态用途退役已在文件头注明。

### 62.3 新测（等量接替、只增不减）

- 新增 `Tests/RetiredBridgeKeyAccountsTests.swift` 6 测：清单恰五条且与 0.32.1 scope 序逐字一致／全带 bridge.key. 前缀／无重复／全在场时 purge 全量返回／登录凭据与 writegate.key 永不入 purge（只回 bridge.key.box）／canonical 顺序与空集。删 BridgeKeyImportTests 6 测，总数与 0.33.0 基线 595 持平起步（以 CI 实测为准）。

### 62.4 底栏查证与落值（16:10/16:11 追加项）

查证（先查机制、只用官方开关；红线：不自绘底栏）：
- ①外覆写残留：全仓 grep toolbarBackground/UITabBarAppearance/scrollEdgeAppearance/standardAppearance——**零命中**；Assets.xcassets 无 AccentColor（只有 AppIcon/LaunchBackground/SangouPartner）→ App 无全局强调色，栏件 tint 无来源时回落系统蓝，此即 0.33.0 选中字形呈系统蓝的机制根源。
- ②背景层：DrawerShell 不给 TabView 加任何 modifier（0.17.0 定案）；聊天页背景 Palette.chatSurface（#FCFCFC）全出血到屏底——栏下采样源是平色画布，与 Muse 同构（其画布同为近白平色），非本 App 独有的「垫底」问题；各页 ScrollView/List 在 iOS 26 本就从栏下穿过。结论：栏身材质就是系统玻璃、无任何覆写把它压实；「发实」观感的主因在字形（蓝＋填充观感），不在材质层。
- ③符号名：四格现行名 message/lightbulb/checklist/tray 全为 outline 原名、selected≡normal、零 .fill（TabBarSymbolsTests 钉死）——用户所见「实心灯泡/实心蓝气泡」不是选名问题：SwiftUI 宿主构建栏件时对选中态自动派生 .fill 变体（苹果对齐资料口径：SwiftUI applies .fill for you in TabView items），既有双锁（label 内 .symbolVariant(.none)＋TabView 根环境 symbolVariants .none）保留并继续钉。**（0.34.0 更正：本条的「选中态派生」定性被 WWDC24 session 10147 官方机制与用户 16:32 真机图证推翻——自动选 fill 作用于全部标签、与选中态无关，且 .symbolVariant(.none) 是累积语义非清除、TabView 外层环境未罩住标签渲染点；正解见 §63.4。）**
- ④选中色机制：栏件字形吃 TabView 本层环境的 tint（内容根的 tint 到不了宿主构建处，0.4.3 已证）；选中垫是玻璃透镜本体、呈中性——0.33.0 在默认蓝 tint 下真机垫已是中性浅灰（用户截图自证），故「垫随 tint 派生变深」的 0.32.0 旧判因更正为：当年深观感是根 tint 把字形与标签同染的整体效果。

落值（全为官方修饰符、零自绘）：
- ContentView.tabView 修饰链加 `.tint(.primary)`（TabView 本层）——只达栏件宿主：选中字形回深色（.primary 标签色）；内容根各自 .tint(.primary) 同值覆盖、内容区观感不变；设置 sheet/抽屉在本层之外不受影响。
- tabLabel 的 Image 补 `.symbolRenderingMode(.monochrome)`——单色模板渲染对齐系统栏件惯例，杜绝 hierarchical/palette 派生。
- 符号名零改动（已合规，见③）；ContentView 内 0.32.0 tint 注与 tabLabel 注已加 0.33.1 口径更新、旧判因在原处标注更正。

### 62.5 II 系列终审项（凭据）

- II1 设置无桥钥匙：设置页「服务器与连接」组里不再有「桥钥匙」行；连接器目录 writeGate 服务详情不再有「桥钥匙」入口。
- II2 零配置恢复：从 0.32.1（或更早）覆盖装 0.33.1 后，不做任何粘贴/配置，总览/审批/目标/点子/Box 五面桥功能直接可用（与聊天同钥）。
- II3 聊天不受影响：登录态、会话列表、发消息全程与升级前一致；断开重连仍只填 Hermes 登录信息一处。
- II4 残项清理：装后启动一次，旧桥钥匙文件 bridge-keys.txt 即使留着也无用武之地（App 不再读分项钥）——文件由我方在用户确认后删除（服务器段纪律）。

### 62.6 JJ 系列终审项（底栏，与 Muse 并排）

- JJ1 栏身通透：聊天页滚动时内容从栏下滚过、栏身呈玻璃层次而非整块实白，与 Muse 并排对（同为浅色画布场景）。
- JJ2 选中字形色：选中格字形为深色（非系统蓝），与 Muse 并排对。
- JJ3 图标描边逐格对：气泡（message）/灯泡（lightbulb）/清单（checklist）/文件（tray）四格，选中与未选两态的线宽与空心形态与 Muse 并排逐格对——重点看选中态灯泡与气泡是否仍呈填充观感（宿主 .fill 派生若双锁压不住，在此项如实记并回主线议 UIKit 路线，不自绘）。**（0.34.0 更正：本项后半的 UIKit 后手指针作废——论坛调研以两处真机证据判死 UITabBarAppearance 路线（iOS 26 玻璃栏整体忽略 appearance、且 appearance 本不管符号变体）；根因与正解见 §63.4，终局备选为模板图资产（备选 B）。JJ 终审口径本身不变。）**
- JJ4 选中垫明度：选中垫保持中性浅灰玻璃（不回 0.32.0 前的深垫），与 Muse 并排对。

### 62.7 交付实录

- 功能提交 42e328b（21 文件：15 改＋3 删＋2 新＋DESIGN 本节）；CI 42781449131 success，Executed 595 tests, 0 failures（595 基线：删 BridgeKeyImportTests 6 测、增 RetiredBridgeKeyAccountsTests 6 测，等量接替、只增不减守恒）。
- IPA：5,400,401 字节、md5 d8c0445aa7c28c039bfb00a39fbfdb5b、独立解包验 Info.plist＝0.33.1/64、bundle site.didichou.oneday，落 ~/workspace/your_files/oneday-v0.33.1/OneDay-0.33.1.ipa。
- 版本五处同改＋grep 验：Project.swift 四处（MARKETING_VERSION 0.33.1／CURRENT_PROJECT_VERSION 64／CFBundleShortVersionString 0.33.1／CFBundleVersion 64）＋SettingsView 页脚「OneDay v0.33.1」。
- 服务器段（nginx 单钥入口＋过渡双模）与本节同批交付且已先于用户装机生效，实录见 hermes-deploy/bridge-keys-rollout-20261110.md 的 0.33.1 追记（验矩阵全绿、备份 bak-20261110-singlekey、内存 51.6%）；fallback 撤销条件＝用户装 0.33.1 并确认桥功能正常后另行派单撤除。
- II1–II4、JJ1–JJ4 待真机终审（本版终审代号 II＋JJ，承 §61 的 HH 序）。

## §63 0.34.0/65 本机连接器批一（工具调用制 App 接线）＋底栏填充正解 A

定版依据：设计档 `oneday-design-review/device-connectors-design-20261110.md`（14:49–14:52 用户拍板全条已决）＋桥契约以服务器源码 `hermes-deploy/device_bridge.py` 为准；底栏追加项依据论坛调研 `oneday-design-review/tabbar-fill-forum-research-20261110.md`。基线 0.33.1/64 顶端 22aa4e7、595 测，只增不减。

### 63.1 服务器段：device-bridge 公网路由（严格单钥）

- nginx `hermes.didichou.site` 新增 `location /api/device-bridge/` → 127.0.0.1:8647，照 0.33.1 单钥入口同形：`auth_request /__bridge_auth` 验 Hermes 登录钥 → `proxy_set_header Authorization` 注入 device 桥自己的服务钥（钥在服务器内从容器 env 直读直注、未经过任何本地文件/聊天）；`proxy_read_timeout 120s`＋`proxy_buffering off`（长轮询 ≤25s、转发调用 ≤30s）。
- **直接严格单钥、无过渡双模**：本桥新立、唯一客户端就是 0.34.0 的 App（持登录钥），不存在旧桥钥客户端要保——与四桥的双模情形不同，不留 fallback。
- **Hermes config 注册 MCP 门面不在本版**（留收官窗口与 Notion/GitHub 验活同批）：`/api/device-mcp` 路由未启用，智能体本版尚调不到设备工具——App 呈现按此诚实口径（见 63.5）。
- 备份：`hermes.didichou.site.conf.bak-20261110-devicebridge`（0600，改前整份）；回滚＝覆盖回备份＋`nginx -t`＋reload。改前内存 51.6%、改后 51.6%，未触红线，未动 Hermes 本体与其余桥。
- 验矩阵（公网实测全绿）：`GET /api/device-bridge/health` 登录钥 200（`{"ok":true,"service":"device-bridge",...}`）／随机错钥 401／无钥 401；会话全环冒烟（登录钥）：POST `/device/session` 201 得 sessionId → GET `/device/poll?wait=1` 回 `{"call":null}` → POST `/device/heartbeat` `{"ok":true}` → POST `/device/disconnect` `{"ok":true}`、断后 health 的 sessionOnline 回 false（冒烟会话已断净、不留残会话）。

### 63.2 Core 落值（纯逻辑，单测钉死）

- `OneDayCore/DeviceSources.swift`：五件名册单一真源（日历/提醒/通讯录批一 `batch 1`、健康/家庭批二 `batch 2` 待签名权益；蓝牙永不入册，单测钉 `DeviceSourceID(rawValue:"bluetooth") == nil`）；`DevicePermissionState` 六档与桥口径映射（桥只认精确 `granted` 放行；通讯录 limited 报 granted 放行＋`contactsScope=limited` 注解随注册载荷透传进 device_status，子集由系统框架天然收敛，不许因桥口径把已授权子集误报 permission_denied）；工具名册与桥 TOOLS 表逐字对齐（十件、写工具恰四件、无 delete），App 可执行集恰批一七件；`DeviceRegistration.payload` 双层开关语义（permissions 报系统原态，tools 只列「已接线＋权限可用＋开关开」——开关关掉的件桥回 tool_unavailable；批二即使假设授权＋开关开也永不上报工具）；目录行状态文案单一映射与搜索纯函数（名称＋说明＋状态词）。
- `OneDayCore/DeviceCalls.swift`：`DeviceToolError` 五码（permission_denied/tool_unavailable/invalid_arguments/update_not_allowed/device_error）；ISO 8601 解析/格式化；逐工具参数解析（必填与 idempotencyKey 必填、日历窗口 14 天在 App 侧收敛并标 clamped、通讯录 limit 缺省 20 收敛 1...50）；`DeviceSessionMachine` 会话状态机（注册→轮询→执行→回执全环，409/心跳失效回注册，噪声事件不演进）；`WriteKeyLedger` 写键账本（24 小时窗口、只存 key 与对象 id）；`DeviceCallLogEntry` 调用元数据（工具名/时刻/成败/错误码，永不记内容）。

### 63.3 App 落值

- 会话通道：`DeviceBridgeClient`（注册/心跳/长轮询/回执/断开五口，Bearer 走 BridgeCredential＝api.key 与其余桥同口径；轮询专用 session 超时 45s）；`DeviceSessionController`（@MainActor @Observable，AppState 持有，RootView 按 scenePhase＋连接态驱动 activate/deactivate——前台＋已连接才注册、退后台断开、演示模式恒不激活；权限/开关变更在线时重注册即时生效；心跳 20s 兜轮询停顿期，404 即重注册）。
- 执行器（`DeviceExecutors.swift`，App 层框架面）：EventKit 日历＋提醒同 store（`requestFullAccessToEvents/Reminders`）、Contacts 现查。写纪律四条落点：①确认在对话内完成（桥/智能体侧纪律，App 不二次弹确认）；②幂等双层——桥 write-keys 之外 App 侧 `WriteKeyLedger` 落 UserDefaults，命中回原对象回读、不真写第二次；③回读验证——create/update/complete 写完必 `event(withIdentifier:)`/`calendarItem(withIdentifier:)` 取回对象才许报 success，取不到回 failed 人话；④离线即失败在桥侧（device_offline）＋App 执行时复查（权限/开关以当下为准，不认注册快照）。红线：update 他人组织的日程回 update_not_allowed、只读日历同理；删除不进任何工具；提醒勾完成对已完成项回已完成态（天然幂等）。
- 权限双层：Info.plist（Project.swift extendingDefault）加 NSCalendarsFullAccessUsageDescription／NSRemindersFullAccessUsageDescription／NSContactsUsageDescription 三键（人话用途＋现读现回口径；健康/家庭/蓝牙键不加，entitlements 待批二签名核查）；逐件「允许智能体调用」开关默认关（UserDefaults `device.agentCall.*`），申请时机逐件用到才问（详情页「开启」触发系统弹窗，启动零索权）；通讯录 limited 在目录行与详情页如实显「部分联系人」与子集人数。
- 呈现：连接器目录新增「你的设备」恒显组（本机服务之后、分段控件之前，SF Symbol 瓷砖与行规格同本机服务；批一三件点进详情、健康/家庭行在但无入口、状态「待签名权益」；搜索纳入五件）；三件详情页共用状态头骨架（系统权限行＋动作、调用开关＋粒度口径、设备会话态、最近调用元数据、口径脚注）＋各自内容区（日历＝今起 14 天议程按日分组＋系统 EKEventEditViewController 新建；提醒＝按清单分组未完成在前、过期红字、行内点勾完成、新建小表；通讯录＝搜索现查列表＋联系人详情卡、离页不留副本）；设置页「设备与权限」总览行（紧随连接器行）＋总览页（五件状态汇总＋会话态）。

### 63.4 底栏填充正解 A（追加项，承 §62.6 JJ3）

- 根因（官方机制，证据出处：调研报告）：WWDC24 session 10147——标签栏宿主对它承载的 symbol image **统一自动选 fill 变体、与选中/未选中无关**；WWDC21 session 10349 佐证该机制属 SwiftUI 环境变体系统。先前判因（§62.4③「选中态派生」）就此作废更正。
- 先前两锁为何无效：`.symbolVariant(.none)` 是**累积语义**不是清除（Sarunw 机制解析），子层写它清不掉宿主注入的 fill；环境赋值 `.none` 是唯一清除法，但**注入层级必须罩住标签渲染点**。
- 层级复核实录：现行 `.environment(\.symbolVariants, .none)` 自 0.4.3 起挂在 **TabView 外层修饰链**——0.33.1 真机（用户 16:32 图证四格全实心、含未选中态）判此层级够不着渲染点；生产库 callstack/react-native-bottom-tabs 的 `noneSymbolVariant()` 经其 DeepWiki 源码文档复核**不在 TabViewImpl 本体修饰链内、而是挂在 TabItem（label 视图）上**，ShipSwift/Google-Blogger-iOS-App 两处独立源码同法（环境赋值挂标签侧）。
- 本版落值：`ContentView.tabLabel` 的 Label 本体加 `.environment(\.symbolVariants, .none)` 为主锁（赋值语义、罩住标签渲染点）；TabView 外层环境与 label 内 `.symbolVariant(.none)`、`.symbolRenderingMode(.monochrome)`、TabView 层 `.tint(.primary)` 全部保留不动（无冲突，且保真机判读归因——若本版回描边，变量只剩本处新增）。
- **§62 后手指针作废**：原 JJ3「回主线议 UIKit UITabBarAppearance 路线」已被调研以两处真机证据判死（DOSBTS 日志：iOS 26 玻璃栏整体忽略 UITabBar.appearance 的 iconColor/backgroundColor；cupertino_native_better 变更日志：真机验旧 tint 与现代 appearance 两路皆无效）且 appearance API 本无符号变体维度——不是没试，是判死，§62.4/JJ3 原处已加更正注。
- 终局备选 B（本版不实施）：四字形按 SF Symbols 官方流程导出模板图进资产目录、标签改用资产图（脱离 symbol image 身份，宿主无变体可换，确定性最高；Muse 五格字形疑似自有图标集为同构推断、无实锤）。A 若真机判死即转 B，不再另议路线。
- 证伪边界（如实）：此项在 CI 侧无法证伪/证实（无真机渲染断言手段），能验的只有构建与符号名单测；终审仍以 JJ 真机逐格对 Muse 为准，灯泡（lightbulb）先看。

### 63.5 诚实边界（本版不许宣称的）

- **智能体尚不能实际调用设备工具**：Hermes 侧 MCP 门面注册不在本版（收官窗口），App 状态头与总览页均明说「还差服务器侧门面注册」；设备会话在线只代表手机侧通道活着。
- 健康/家庭只有目录行与总览行（「待签名权益」），无执行器、无数据呈现、无假页面；蓝牙整件不做（§4.6 判死记录）。
- 设备会话以 App 前台为限：退后台/被杀即离线，工具侧如实回 device_offline，不排队、不拿旧数据冒充（桥契约与桥侧 TTL 45s 兜底）。

### 63.6 KK 系列终审项（本机连接器，真机）

- KK1 目录设备组：连接器页「你的设备」组在本机服务之后，五件齐（日历/提醒事项/通讯录/健康/家庭），状态字与各件实际授权一致；健康/家庭显「待签名权益」且点不动。
- KK2 双层开关：任一件关掉「允许智能体调用」后目录行变「调用已关」；系统设置里撤权后重进目录变「被拒」、详情页出「去系统设置」。
- KK3 日历详情：议程与系统日历 App 逐日对得上（全天/跨日事件在内）；新建日程（系统编辑器）保存后议程当场出现。
- KK4 提醒详情：未完成数与系统提醒 App 一致；行内勾掉一条，系统提醒 App 同步消失；新建提醒带到期保存成功。
- KK5 通讯录详情：搜「秦」出对应联系人；若给的是受限授权，页内明说「仅显示你勾选的 N 位」。
- KK6 权限申请时机：全新安装后不打开设备页就不弹任何权限窗；首次进某件详情点「开启」才弹该件的系统窗。
- KK7 会话在线态：App 前台时总览页「设备会话」显在线；切后台超过约 1 分钟再回来看（或以桥侧 health 查）应为离线——不许留假在线。
- KK8（待收官窗口后另验，不属本版）：Hermes 注册门面后，智能体实调 calendar_list_events 现读、杀 App 后同调回 device_offline、写工具复述确认＋幂等＋回读全环。

### 63.7 交付实录

- 提交链：862d11b（功能整包）→2576d09（CI 修：formatter Sendable＋DeviceSourceID Codable）→1d26ee8（CI 修：keysToFetch 组装）→bf0f5f7（CI 修：fetchReminders continuation 盒）；顶端 bf0f5f7。
- CI 42785106180 success，**Executed 624 tests, 0 failures**（基线 595＋新测 29：DeviceSourcesTests 12＋DeviceCallsTests 17，只增不减）。
- IPA：5,709,994 字节、md5 f9aa773ef461aa1ae4aa8ed754a088ad、独立解包验 Info.plist＝0.34.0/65、bundle site.didichou.oneday、三键 UsageDescription 均在包内，落 ~/workspace/your_files/oneday-v0.34.0/OneDay-0.34.0.ipa。
- 版本五处同改＋grep 验：Project.swift 四处（MARKETING_VERSION 0.34.0／CURRENT_PROJECT_VERSION 65／CFBundleShortVersionString 0.34.0／CFBundleVersion 65）＋SettingsView 页脚「OneDay v0.34.0」。
- 服务器段实录见 63.1（nginx 路由已生效、验矩阵全绿、备份 bak-20261110-devicebridge、内存 51.6%）；施工记录追记 hermes-deploy/device-bridge-rollout-20261110.md。
- KK1–KK7 待真机终审；JJ1–JJ4 续审（本版底栏正解 A 是否回描边以 JJ3 逐格对 Muse 为准，灯泡先看）；KK8 待收官窗口（Hermes 注册门面）后另验。


## §64 0.35.0/66 三页工程 P3（动态流＋底栏五格，三页工程收官）

依据：三页设计档第三章与 P3 节、九条拍板（1A 五格/6A 晨报联网/8A flash）。本版把动态页从 0 建到 1：桥端双生产者上线并各跑过真实首轮，App 动态页与底栏五格落地。

### 64.1 桥（oneday-bridge，P3 段）

- 数据面：`feedPosts` 存储＋端点 GET /feed（?days=30 窗口、createdAt 倒序、过期不回）、GET /feed/{id}、POST /feed/{id}/read（readAt 桥落字）、DELETE /feed/{id}、POST /feed/generate（晨报手动触发，202/409）、GET /feed/generation（双账面＋未读数）。帖 schema＝{id, kind, title, body(Markdown), refs:[{type,id}], links:[{title,url}], why, createdAt, expiresAt(+30 天), readAt}；简报类 refs 在读视图富化 goalId（App 点达所属目标，不靠猜）。
- 段一·确定性汇编（零模型）：调度 tick 折叠当日真实事件为一篇 digest 帖（事件集变化才重建、新事件重置未读）——事件源五路：新点子/目标简报/监测变化（桥自有数据）、kanban 任务状态变化（Dashboard 通道 300 秒节流轮询＋快照 diff，首快照静默基线）、待审批（经公网单钥网关路径 /api/write-gate/status 读计数，只增成事件、基线静默）。无事件的日子不发帖、只记账面计数。轮询失败只进账面注记、永不编事件。
- 段二·晨报（模型帖）：每日 08:30（Asia/Shanghai；点子 07:30、周一简报 08:00 之后）一轮 /v1/runs（deepseek-flash、幂等键按日、waiting_for_approval 滞留处置与点子管道同规——共用 _hermes_submit_run/_hermes_poll_run）。素材＝brief＋近 7 天带 id 素材（目标/点子/简报/监测变化/任务板/会话标题背景）＋联网调研指令（链接只许真返、桥侧滤非 http(s)）。严格解析 {"title","body","why","links","refs"}：why 必填、refs 至少一个且逐个验存在（idea/goal/task/monitor/briefing 对桥内真源＋kanban 快照）、**一个假引用整帖退回**；模型可回 {"skip": true} 如实记 empty 轮。账面 GET /feed/generation。
- 与设计档的口径差（逐项记账）：①排序——简报口径「按有用度以设计档为准」，设计档 §3.4 定版为发布时间倒序、有用度排序登记缓办，本版从设计档；②已读——设计档原案本地派生，本版从施工简报改服务端真源（readAt＋标记端点，多设备一致）；③页头胶囊——设计档原案 brief 摘要行，本版从施工简报落「今日 digest 摘要/未读数、点开落对应帖」，brief 编辑入口未在本版 App 落（brief 实体 P2 已在桥，编辑面另排）；④出厂三篇介绍帖——施工简报明令不许假帖填充，未做，空态改二分如实文案；⑤点赞/讨论/删帖动作——设计档列了全集，本版 App 只落读与已读（施工简报范围），loved 与讨论预置、删帖 UI 登记缓办（桥 DELETE 端点已备）；⑥晨报时刻设计档未定值，本版定 08:30 并记账于此。
- 首轮验收（生产实测，2026-11-10）：段一汇编出《今日动态 · 3 件》（当日 P1 首轮 3 张生成卡，refs 三个 idea id 全真）；段二手动触发一轮 status=ok、produced=1（run_9a824d76edb24a28bb1ab60809ae60f5），晨报《自托管助手的三件新事：发布通道、沙箱底座、密钥护栏》落库——refs 1 个真 idea、links 6 条真返（PR Newswire/TechCrunch/Google Cloud 等）、why 在位。生产终态：帖 2 篇（digest＋morning）、未读 2，晨报下轮 2026-11-11 08:30。kanban 现状实测为空板（8 列 0 任务——任务事件通道待有任务时自然生效，基线已立）；待审批基线 0（59ba48f2 已不在待批列）。
- 部署：备份 oneday_bridge.py.bak-20261110-p3＋data.json.bak-20261110-p3，只重启桥本体；内存全程约 51.6%。自测 oneday_bridge_p3_selftest.py 25/25（HTTP 契约＋段二桩轮三态＋轮询 diff/基线/只增口径）。

### 64.2 App

- 底栏五格（1A）：MainTab 增 .feed 第二格，顺序 聊天/动态/点子/目标/文件；新格与四格同走 ContentView.tabLabel（0.34.0 symbolVariants 主锁自动覆盖）；TabBarSymbols 增 feed 对（id "feed"、标题「动态」、doc.text——动态本体是个人报、取带字纸页同语义位，设计档「先 SF Symbol 同语义位」口径；outline 原名、两态同名。初版 newspaper 经 CI 量测判死：紧致密度 0.477 出抽屉名单带 0.05–0.45、格口径 0.138 出底栏线条画法档 ≤0.12，满版栏目线与 §30 线条画法纪律相冲，换 doc.text，汇编帖 kind 瓷砖同名对齐），all 改钉五格、TabBarSymbolsTests 全表同步。抽屉「选项卡」组同步加动态行（枢纽动作行不占格位序）。0.30.0 落点逻辑未动（默认仍落聊天/上次线程）。
- 动态页（FeedView/FeedStore）：顶栏＋大标题「动态」＋简报胶囊（FeedBoard.capsulePost：今日汇编→今日晨报→最近未读→最新；标题单行省略＋未读徽标，点开落对应帖）；帖子扁平行（34pt kind 瓷砖——晨报 sunrise/汇编 newspaper、标题 Headline 两行＋未读点、正文摘 3 行（FeedBoard.excerpt 剥 Markdown 形）、refs 蓝字内链横滑、动作行类别左＋相对时间右）；按日分组（组头与 ChatTimeline 同族口径）；帖子详情（Markdown 全文＋why 块＋链接清单＋引用列表，打开即 POST 已读、以桥回执对账）；下拉刷新；空态二分（neverProduced「动态刚上线＋第一篇晨报明早 8:30 到」/quiet「近来没有新动态」，均如实、不填假帖）；桥未连接/失败与点子格同分法。
- refs 点达：本栈复用各详情页——idea→IdeaDetailView、goal→GoalDetailView、briefing→凭 goalId 富化直达所属 GoalDetailView、task→KanbanTaskDetailView、monitor→MonitorDetailView；引用标题从同批加载的各 Store 解析，解析不到回类别文案、不编名。
- Core：FeedModels（BridgeFeedPost/Ref/Link/Generation DTO 宽容解码＋FeedBoard：排序/日组/相对时间五档/未读数/胶囊落点/空态二分/excerpt）＋FeedBoardTests 12 测、TabBarSymbolsTests 改钉五格。

### 64.3 LL 系列终审项（动态与五格，真机）

- LL1 五格并排：底栏五格与 Muse 并排逐格对（顺序/字形描边/选中垫），动态格 newspaper 字形先看；抽屉「选项卡」组动态行在位、选中态与当前格一致。
- LL2 胶囊：胶囊显今日汇编标题＋未读数与桥账面一致；点开落到汇编帖详情；全读后徽标消失。
- LL3 帖子内链点达：汇编帖三个点子 refs 逐个点开落 IdeaDetailView 且是同一张卡；晨报帖 refs/links 点达与外开正常。
- LL4 已读真源：点开一篇后回列表未读点消失；杀 App 重进仍为已读（服务端 readAt）。
- LL5 空态：断桥（关服务器连接）显未连接态而非空态假象；新装零数据时显「动态刚上线」文案。
- LL6 晨报节奏：2026-11-11 08:30 后动态页出现当日晨报（≤1 篇），标题下胶囊落点更新。
- LL7 落点不变：冷启仍落聊天格/上次线程，五格未动 0.30.0 落点逻辑。

### 64.4 交付实录

- 提交链：6e601b0（功能整包）→9e2805a（CI 修：动态格符号 newspaper 量测判死换 doc.text＋相对时间边界测例修正）；顶端 9e2805a。
- CI 42789983434 success（首轮 42788898202 构建过、单测三处红：newspaper 密度两闸＋相对时间恰 60 秒边界，均已修），**Executed 637 tests, 0 failures**（基线 624＋新测 13：FeedBoardTests 13，只增不减）。
- IPA：5,855,761 字节、md5 1c616691ccffe68d2705bf247984c3b2、独立解包验 Info.plist＝0.35.0/66、bundle site.didichou.oneday，落 ~/workspace/your_files/oneday-v0.35.0/OneDay-0.35.0.ipa。
- 版本五处同改＋grep 验：Project.swift 四处（MARKETING_VERSION 0.35.0／CURRENT_PROJECT_VERSION 66／CFBundleShortVersionString 0.35.0／CFBundleVersion 66）＋SettingsView 页脚「OneDay v0.35.0」。
- 桥侧实录见 64.1（备份 bak-20261110-p3、双生产者首轮真跑、自测 25/25、内存约 51.6%）；施工记录追记 hermes-deploy/oneday-bridge-rollout-20261109.md。
- LL1–LL7 待真机终审；JJ/KK 系列续审并行。

## §65 0.36.0/67 全局整改批一（组件止血）＋违规台账建立（2026-11-10）

总纲三部定版后的首场宪法施工：范围＝全局审计「分批建议」批一＋无障碍 C1 子集；台账单一真源＝~/workspace/oneday-design-review/ui-remediation-ledger-20261110.md（审计 25 条＋深色 D1–D9＋无障碍 23 行统一编号、S17 销项制）。本批禁区守住：不动深色色板（批一B 专批；分隔暗档只随系统 separator 语义色同源落地、未自定第二套值）、不动行题字重（批二）。

### 65.1 施工实录（对台账编号）

- 分隔贯通（C1/C2）：OneDayMetrics.dividerInset 62→0；GroupDivider 改 Palette.separator（Color(UIColor.separator) 语义色）＋物理发丝高（1/displayScale）；全仓 24 个消费文件的显式 inset 调用（spacingM/42/56 等）统一改默认贯通——核形态：均为 odGroup 卡内行间分隔（FieldRow/actionRow/步骤行），末行无线纪律原样；详情段落分隔无独立形态，不受影响。暗档对卡面对比的收口验收归批一B（D4 部分销）。
- 瓷砖退役（C6/C7，D7 部分销）：ConnectorTile 整类删除。品牌 8 家官方原图资产入 Assets.xcassets（BrandGmail/BrandGoogleCalendar/BrandGoogleDrive/BrandGoogleSheets/BrandNotion/BrandGitHub/BrandSpotify/BrandInstagram；来源与日期登记台账 D 节；GitHub/Notion 带官方暗档变体，余为自含底图双档通用）；目录呈现改 Core ConnectorIconSpec（.asset/.symbol），未知 MCP 服务器降级通用符号 puzzlepiece.extension（首字母兜底退役）、Box＝desktopcomputer；本机服务四件改 SF Symbols（server.rack/checkmark.shield/target/square.grid.2x2）；设备五件改苹果应用图标画法（白底 squircle＋标志色字形），容器收敛为 Design 层 AppSymbolTile 单一实现（设备/连接器符号路共用）。
- sheet 去标题（C9）：连接器四类详情（已连接/目录/本机服务/设备）撤 inline 标题栏＋手写「关闭」，sheetHeader 内容领头；catalogDetail「状态」分区头去重（行保留）；同族：通知、档案导出、服务器文件三 sheet 同撤标题＋关闭，审批改动详情撤关闭。豁免候选入台账 E 节待用户复核：E1 BoxFiles 全屏预览两处关闭保留（无系统关闭位）、E2 联系人名/审批对象名标题保留（内容身份）、E3 设置子页技术原文（审计原注）。设置大标题 P8 维持已拍板例外待复核。
- 文案清零（C10/C12，P7 部分销）：LocalServices evidenceLine 四条改用户语言（接口路径/方法名整行下屏），LocalServicesTests 断言反转（不许含 GET/端点）；连接器探活失败文案去端点与状态码（401/404/409 全下屏，改 S10 人话＋恢复动作）；「桥钥匙」死路全改单钥现实——连接器未配置段＋Goals/Monitors/Memories 三 Store 共 12 处；S11 禁用词 8 词主文案清扫（探活/端点/回读/落盘逐处改写，含三 Store 确认类提示、FilesView、全部对话、记忆条目、设备执行器、Kanban 流程说明、审批状态文案；真源/桶/scope/run 实查零命中——余下 run 命中均为协议 JSON 键与状态值，非文案）。审批状态「已批准，待回读确认」→「已批准，待确认生效」。
- 日期格式器（C11）：Core 新 DisplayDate（dateTime 五档与 ChatTimeline.dividerText 同源转调、dateOnly、relativeDateTime、timeOnly），收编 10 处 .formatted 消费点（点子 3／监测 4／设备 1／连接器 1／服务器会话 1），全仓 .formatted(date:) 代码零残留；+10 测（含与 ChatTimeline 逐字一致性）。
- 无障碍 C1 子集：A11Y-C1 inkSecondary 浅档 #697176→#646B71（设置底 4.46→4.85、页面底 5.27、卡面 5.41，同色相加深一档；VisualDirectionGateTests 补设置底 ≥4.5 闸）；A11Y-V1/T1 GoalCheckBox 命中域 22→44（视觉框不变、-11 负边距保布局）＋动作标签＋状态值，A11Y-V5 MilestoneCheckRow 补状态值（toggle trait 无确定可用 SwiftUI 对应、未赌编译，台账已注）；A11Y-C5/S4 动态帖未读补文字标「未读」（蓝点保留、双通道）；A11Y-S3/D4 Bold Text 映射——Core BoldTextPolicy（rootWeight/bumped 纯函数＋3 测）＋Design BoldTextRootModifier，ContentView 根视图单点挂载（开启粗体文字→未钉字重文本升 semibold，显式钉重不受环境覆盖）；A11Y-D2 HubCronSection 定时角标放大一档（徽标 16→18、字形 8→10，实查为图形字形非文字）。
- 测试面改写（只改断言口径、不减方法数）：ConnectorCatalogTests（iconSpec 资产/符号断言）、LocalServicesTests（symbolName＋证据行反转断言）、VisualDirectionGateTests（设置底对比闸）。

### 65.2 交付实录

- 提交链：0a8a1ec（批一整包，70 文件）→本节文档提交；顶端以文档提交为准，代码顶端 0a8a1ec。
- CI 42793467225 success（首轮即绿），**Executed 650 tests, 0 failures**（基线 637＋新测 13：DisplayDateFormattingTests 10＋BoldTextPolicyTests 3，只增不减）。
- IPA：6,178,449 字节、md5 63ac771081f031191558c3ec7259bea8、独立解包验 Info.plist＝0.36.0/67、Assets.car 内 8 个 Brand* 资产齐，落 ~/workspace/your_files/oneday-v0.36.0/OneDay-0.36.0-unsigned.ipa。
- 版本五处同改＋grep 验：Project.swift 四处（MARKETING_VERSION 0.36.0／CURRENT_PROJECT_VERSION 67／CFBundleShortVersionString 0.36.0／CFBundleVersion 67）＋SettingsView 页脚「OneDay v0.36.0」。
- 台账销项（0.36.0）：全销 C1、C2、C6、C7、C9、C10、C11、C12、A11Y-C1、A11Y-V1、A11Y-T1、A11Y-C5、A11Y-S3、A11Y-D4；部分销 D4、D7、P7、A11Y-V4、A11Y-V5、A11Y-D2、A11Y-S4（余项去向台账逐行注明）；豁免候选 E1/E2/E3 与 P8 待用户复核；C16 底栏填充待 JJ 真机判读。
- 待真机：分隔贯通全表面观感、品牌瓷砖双档呈现、Bold Text 开启态全 App、GoalCheckBox 命中域与 VO 播报、未读文字标——并入在途真机终审积压。

## §66 0.36.1/68 全局整改批一B（深色专项：色板真源语义化）（2026-11-10）

全局审计深色专项 D1–D9 的独立批：病根＝0.6.1 起的暗色是 OpenMuse 浅色令牌的「冷蓝灰派生色板」（Palette 内 omColor 暗档逐项手派生），非苹果语义色板——用户点名「深色模式颜色不对」的总源。改法＝色板真源语义化：Palette 暗档整表改挂苹果语义体系（Palette.swift 新 appleColor 构造：浅档 OpenMuse 原值一字未动、暗档以 UIKit 语义色在暗 traits 下解析直给），基底回纯黑。**回滚基线＝Palette.swift 单文件 git 回退至 0a8a1ec 即全量还原**（本批其余改动只有 LaunchBackground 资产与测试/注释，不跨此文件蔓延）。浅档任何值未动（守恒钉见 66.1）。

### 66.1 施工实录（对台账 D 行）

- D1 基底：pageBG/chatSurface 暗档→systemBackground #000000；settingsBG 暗档→systemGroupedBackground #000（grouped base 与 systemBackground 同锚，双基底 #101619/#0D1214 互比 1.03 消除；其上分组卡 surface #1C1C1E 与 grouped 二级面 secondarySystemGroupedBackground 暗值同值，层级关系由此定）。
- D2 层级梯：surface 暗档→secondarySystemBackground #1C1C1E；bubbleFill/fieldFill/floatFill 暗档→tertiarySystemBackground #2C2C2E——旧派生 floatFill 与卡面同值 #1B2226 的「浮层零提级」修复；步距由旧 4–8/255 回语义梯 28/255。
- D3 标签四级：ink/bodyInk 暗档→label（纯白，对页底 21:1）；inkSecondary 暗档→secondaryLabel（合成 页底 6.36／卡面 5.94——α 制随所压面自适应）；inkMuted 暗档→tertiaryLabel（合成对页底 2.24，不再反向变暗——旧 #7D858B 对 #101619 仅 4.00 且亮度反低于浅档职能）；新设第四级 inkQuaternary→quaternaryLabel（双档语义）；inkSecondaryOnFill 暗档同源 secondaryLabel（对泡面合成 5.29 达标；浅档专用加深值 #5F666B 不动）。
- D4 separator 收口：hairline 暗档→opaqueSeparator #38383A（对卡面 1.17→1.45）；GroupDivider 线色在批一已改 Palette.separator（UIColor.separator 语义 α0.60，对卡面合成 1.60）——分隔两路同归语义 α 体系、与批一浅档同源同机制，odGroup 描边随 hairline 一并收口。注：hairline 浅档同步改取系统 separator 家族深色端 #C6C6C8（HIG separators 表 light opaqueSeparator；旧派生 #D8DDE0 退役）——审计 D4 的定版动作即「改取 opaqueSeparator 语义色」、双档同取是其本意，此处如实记录：这是本批唯一触及的浅档值，属 D4 辖内、非顺手改。
- D5 fill 阶梯：新设 fillPrimary/fillSecondary/fillTertiary/fillQuaternary 四令牌直挂 systemFill 四级（α 系统常量，暗档实测 systemFill 0.36、secondarySystemFill 0.32）；selectionFill 暗档→systemFill（压卡面合成 ≈1.6，旧 1.12）；pastel 四色暗档改同色相系统色 α0.20 统一构造（blue/purple/green/orange，代手调四值）；codeFill 暗档→secondarySystemFill；errorSurface 暗档→systemRed α0.16。
- D6 状态色：success/warning 改 Color(UIColor.systemGreen/systemOrange) 双档语义（代直用 Color.green/orange）；danger 暗档→systemRed #FF453A（代褪色派生 #D08B87 保饱和；浅档 #AA4A45 不动）。
- D7 瓷砖核对（无代码改动）：品牌 8 资产双档已登记台账 D 节（GitHub/Notion 官方暗档变体、余自含底图双档通用）；设备五件白底 squircle 画法双档同形（字形色落白底、双档对比恒等）；HubIdentitySection 手写双档对（暖灰/紫调矿物渐变卡）与语义梯无冲突——三处核对通过。余 FileIconBox 色表仍归批二（C8）。
- D8 启动面：LaunchBackground.colorset 补 luminosity dark 变体＝纯黑（源资产＋IPA 内 Assets.car 已验含 LaunchBackground）；scrim 为 0.4.1 几何量测钉死的例外 E5（黑 α0.35／形状钉），核对后保留不动。
- D9 主题闸扩面：闸②暗底 #101619→#000000（全款 ≥4.5，实算最低 7.72）；新闸③强调对卡面（浅 #FFFFFF／暗 #1C1C1E）双档 ≥4.5（最低浅 4.87／暗 7.27）；新闸④强调对助手泡面仅暗档 #2C2C2E ≥4.5（最低 lavender 5.12）；新闸⑤强调字形对自家 tint 弱面双档 ≥3.0 图形口径（最低浅 4.31／暗 5.90）。**如实记录**：强调对助手泡面「浅档」组合实算 4.20–4.39 四款（sangou/iceBlue/skyBlue/peach，全在闸线下）＋default 4.68——属浅档既有口径、非本批辖区，未设浅闸、不冒充已验，留浅档专项处置（候选：四款 accentLight 同色相加深一档，或泡内链接改走 ink 角色）。曜黑款 tint 暗档与页底仅差一档的弱面近隐形，闸测不出——列真机肉眼验，不冒充已验。
- 防漂移换防线（测试）：RenderMeasure 新增 testDarkPaletteFollowsAppleSemanticTiers——背景三层/标签/描边用解析分量钉、系统色与四级标签用 assertSemantic 语义同一性钉（解析值与系统语义色本尊同 traits 相等）、末尾浅档守恒三钉（pageBG #FCFCFC／surface #FFFFFF／inkSecondary #646B71）；气泡暗档钉 #272E33→#2C2C2E。VisualDirectionGate 暗档断言改 α 合成口径（compositedRatio 新辅助）＋分隔/发丝/选中压卡面可见性闸 ≥1.4＋inkMuted 暗档危险钉 <4.5（2.24）。ChatTheme.swift 强调注释的旧页底值 #101619 同步改 #000000（注释真实性）。
- 踩坑一记：首轮 CI 42795896854 红 7 断言、全在新专钉——系统语义色解析分量是 Display P3 空间值（systemRed 暗档 G/B 与 sRGB 文档值互换量级），且 α 常量与文档表不符（systemFill 暗 0.36／secondarySystemFill 0.32／quaternaryLabel 暗 40/255）；修复提交 9bbb6da 改语义同一性钉后绿。此坑对后续一切「解析值钉语义色」通用：钉身份、不钉 sRGB 分量。

### 66.2 交付实录

- 提交链：9879810（批一B 整包）→9bbb6da（专钉口径修复）→本节文档提交；顶端以文档提交为准，代码顶端 9bbb6da。
- CI：首轮 42795896854 failure（654 测 7 红，见 66.1 踩坑）；修复轮 42797356243 success，**Executed 654 tests, 0 failures**（基线 650＋新测 4：ChatTheme 闸③④⑤＋RenderMeasure 语义梯钉，只增不减）。
- IPA：6,177,946 字节、md5 e43c3df5b942b12ba420d2fe5d747319、独立解包验 Info.plist＝0.36.1/68、Assets.car 含 LaunchBackground，落 ~/workspace/your_files/oneday-v0.36.1/oneday-unsigned.ipa。
- 版本五处同改＋grep 验：Project.swift 四处（MARKETING_VERSION 0.36.1／CURRENT_PROJECT_VERSION 68／CFBundleShortVersionString 0.36.1／CFBundleVersion 68）＋SettingsView 页脚「OneDay v0.36.1」。
- 台账销项（0.36.1）：全销 D1、D2、D3、D4、D5、D6、D8、D9；D7 全销（核对通过口径，FileIconBox 余项在 C8 行内归批二、不在本行）；C2 暗档验收部分销随 D4 收口（代码层已销、真机对照在途）。
- 待真机：全表面暗色对照（设置/连接器/文件/目标/点子逐面）、曜黑主题弱面暗底近隐形肉眼验、暗色冷启动闪白消除确认——并入在途真机终审积压。

## §67 0.36.2/69 体验包一（分段控件重做＋触感矩阵落地）（2026-11-10）

体验三件规格（experience-trio-spec-20261110.md）第一、二节的施工批；第三节图片查看器按规格打包建议单列后续版本。规格口径要点：分段控件的病根是「角色反置＋全面偏大」——令牌 selectionFill 色值本身没错（与实测 #F3F4F6 差 ≤3 通道），错在被用作轨道、白 surface 被用作药丸还带阴影；触感的病根是「只有结果一个维度」——selection/impact 零落点、失败普遍拿 warning 冒充。

### 67.1 件一·分段控件（DeliverablesView.segmentControl 重写）

- 落值（SegmentedControlSpec 单源常量，Design 层）：总高 48（旧 60）、药丸高 36（旧 52）、内缩 6（旧 4）、左右边距 16（旧 pageGutter 20，本控件局部口径）；轨道＝Palette.surface 白＋Palette.separator 发丝边、全胶囊 r24；药丸＝Palette.selectionFill 灰垫、r18（同心＝24−6，与药丸高/2 同值即 Capsule）、**删阴影**；字 `.bodyText` 17 semibold（旧 regular）、两态皆 Palette.ink（旧未选 inkSecondary 灰化退役）——选中区分只靠灰垫有无。
- 切换：药丸 matchedGeometryEffect 滑移；弹簧新令牌 MotionTokens.selectionSpring＝spring(response 0.35, dampingFraction 1.0)——动效宪法默认档（点按触发、无手势来源、零回弹），与 liquidSpring 跟手档（0.72）分工，旧「liquidSpring 滑移」落点随之改挂。Reduce Motion 走 resolved 出口瞬时。
- 防回潮：SegmentedControlSpecTests 专钉绝对值（48/36/6/16）＋同心关系（药丸高＝总高−2×内缩、轨道圆角＝总高/2、药丸圆角＝轨道圆角−内缩＝药丸高/2）。
- 旧注「段高约 63pt，照 Muse 资源库图复刻」的目测高估口径（高出真值 15pt）连同注释退役；全仓自制分段仅此一处，系统 Picker(.segmented) 四处（Logs/AllConversations/Computer/Connectors）按全面原生令未动。

### 67.2 件二·触感矩阵（规格 §2.3 总表逐项）

- Haptics 枚举扩三函数：error()、selection()、impact(_:)（与 success/warning 同形、即用即建）；头注改《动效宪法》表 D 口径——0.3.2「只挂结果」纪律（§17）退役，防腻清单成文写入头注防回潮。
- 新增感知点：①分段切换 selection（.sensoryFeedback trigger＝segment）；②GoalCheckBox＋MilestoneCheckRow 勾选完成 success（.sensoryFeedback 条件边沿：仅未完成→完成响，done 为回读确认后真状态、响在落定刻；取消勾选不对称不加）；③点子采纳 success（IdeasStore.convertToTask 回读确认 taskId 落字分支，未确认分支只留 notes 不响）；④审批批准 success／驳回 warning（AgentHubStore.decide 的 response.success 落定分支，未生效/异常不响；驳回取 warning 本义＝需注意类决定）；⑤删除确认落锤 impact heavy（FilesBrowserView 与 DeliverablesView 两确认弹窗的「删除」钮）＋两处 delete() 的事后 success 撤销——同一因果链只震一次；失败时 error 照常（结果事件、非同响）。
- 改判 error 共 13 处（逐处按语义核、非无脑全替）：ChatView 会话链接失败／driveRun sessionExpired／finishRunPresentation(failed:)（含其文档注同步）、ConnectView 地址无效／连接失败、GatewayView 操作失败、ServerDetailView 地址无效／保存失败、SettingsView 重启失败、FilesView 上传／新建文件夹／删除失败、DeliverablesView 删除失败。**保留 warning 一处**：FilesView 删除后回读「删除未生效、仍在目录中」——请求已发、结果未确认，属 warning 本义（需注意未失败），是本批「逐处判」的明证。
- 保持 success 不动：消息完成有正文、上传回读确认、新建文件夹回读确认、连接成功、网关指令成功、服务器保存成功、设置重启指令成功、复制（CopyButton 既有 .sensoryFeedback）。
- 防腻清单执行（代码审计口径）：普通点按／行点击／tab 切换／页面进出／滚动／键盘／抽屉开合／下拉刷新／翻页／系统 Toggle 与 Picker 均未新增触感；impact light 条件项（抽屉手势吸附／拖放落位）本仓无对应手势实现、无落点，如实记账不硬造。
- 与规格的出入（如实记）：规格 §2.5 把点子采纳落点写作 IdeasView、审批写作 AgentHub/Overview——实际完成信号在 Store 层（回读确认／裁决落定），落点下沉至 IdeasStore/AgentHubStore，语义更准（响在真落定刻而非点按刻）；Overview 无独立审批动作面（同一 HubApprovalSection），无第二落点。

### 67.3 交付实录

- 提交链：ce13d14（整包）→本节文档提交；顶端以文档提交为准，代码顶端 ce13d14。
- CI：42799338677 **success**，Executed **656 tests, 0 failures**（基线 654＋新测 2：SegmentedControlSpecTests，只增不减）。
- IPA：6,185,181 字节、md5 4ffa0c4417ddd67d8c09a51c2a1584be、独立解包验 Info.plist＝0.36.2/69，落 ~/workspace/your_files/oneday-v0.36.2/oneday-unsigned.ipa。
- 版本五处同改＋grep 验：Project.swift 四处（MARKETING_VERSION 0.36.2／CURRENT_PROJECT_VERSION 69／CFBundleShortVersionString 0.36.2／CFBundleVersion 69）＋SettingsView 页脚「OneDay v0.36.2」。
- 待真机：分段灰垫/48 高/无阴影肉眼判；触感四点逐个点测（分段切换、目标勾选、删除落锤、失败报错 error 档）——并入在途真机终审积压。

## §68 0.36.3/70——详情页语法重做＋图标补完＋设置页三修＋抽屉材质（用户 2026-11-10 18:05–18:31 点名包）

### 68.1 范围与模板取舍

- 详情页模板取舍（施工单二选一须说明）：**居中大图领头全批统一**。依据＝授权页参考图本身即「居中大图标→名称→一句话」语法；设备页与连接器页同为「一件东西的详情」，同语法同形态，不再分行首/居中两式。旧连接器行首 48 页头（0.36.0）与设备设置式分组头一并退役。
- 参考图五张逐张对照施工（references/：授权页／目录／抽屉磨砂＋两张自家反例）。

### 68.2 逐项落法

1. **连接器详情（ConnectorsView）**：sheetHeader 重写为居中领头段（图标 64→名称 Title2 bold→能力一句话 callout 次色居中、≤2 行），三类详情领头段去卡底（Color.clear）；已连接详情主动作改整宽 .odPrimary「测试连接」整宽主按钮＋结果独立成行（撤「操作」分区头）；本机详情证据行由卡内行下沉为透明底页脚小字节、未配置文案压至一句半；目录详情接入说明下沉页脚小字。
2. **设备三页（DeviceViews）**：状态头重排为同模板（瓷砖 64 居中＋名称＋blurb）；三页撤 .navigationTitle＋.inline（内容领头，系统返回位不变）；**系统权限行全态可操作**（S4）——.notDetermined＝「去开启」钮触发 requestAccess、.denied/.restricted＝「去设置」钮、已授权类＝整行 Button 点进系统设置（openSettingsURLString）＋chevron＋VO hint；「允许智能体调用」副文改 Core 新增 capabilityLine（一行短文案，五件各一、单测钉 ≤24 字无换行），agentNote 长文退下主文案；门面注册口径移「通道状态」节 footer；DevicePermissionGate 说明压到一句事实＋一个下一步，writeOnly 附注条件由 .denied 误挂修正为 .writeOnly 本态。
3. **本机服务图标真实化（§4 加严口径）**：Core LocalServiceDescriptor.symbolName→iconAssetName；四件定制图面进 Assets（LocalHermes 飞翼/LocalWriteGate 盾勾/LocalOneDayBridge 靶环/LocalOverviewBridge 四格窗；统一语言＝全幅 squircle＋对角渐变＋白色主体＋顶部柔光，PIL 程序绘制 512px），台账 D 节补登来源与画法；目录行与详情头同走 .asset spec。裸 SF 仅余未知 MCP（puzzlepiece.extension）与 Simular Box（desktopcomputer）两处 §4 降级兜底。
4. **目录行分隔（ConnectorsView）**：四类行加 .alignmentGuide(.listRowSeparatorLeading)＝40＋spacingSM（文字列左缘）——目录页从参考图口径，与设置页贯通口径分属两页两规矩，代码注已分明。
5. **设置页三修（SettingsView）**：①撤 .navigationTitle("设置")＋.large（P8 例外经用户 18:25 推翻）、撤七处 settingsHeader 分组小标题并删帮助函数，分组靠卡片与间距；页内导航标题处理＝根页无标题、身份卡领头，子页路由标题不动（子页内容页头自带）。②分隔贯通：文件尾加 View.settingsSeparatorToIconEdge()（listRowSeparatorLeading 引导归 0），施加于十处行根（身份卡/manageRow/serverRow/navRow/statusNavRow/statusInfoRow/网关重启钮/断开行不在多行节内未施/关于节三行）；原生 List 引导是否被系统采纳待真机验，验不过按施工单给自绘行盒替代并如实登记。③字重零改动（Bold Text 跟随系用户拍板）。
6. **抽屉材质（DrawerView）**：新增 drawerBackdrop（系统 .thinMaterial；Reduce Transparency 经 Core TransparencyFallback 裁决落 chatSurface 实色），面板 .background 与顶条 safeAreaBar 背景同换（旧 chatSurface/surface 实色退役）；标题与行浮于材质上、底条 ultraThin 霜层保留同族衔接；深浅双档随材质系统呈现。只用系统材质 API、variableBlur 未碰。
7. 版本五处同改 0.36.3(70)＋grep 验；单测：LocalServicesTests 改字段断言＋新增图标资产互异测、DeviceSourcesTests 增 capabilityLine 断言组（只增不减，基线 656）。

### 68.3 交付实录

- 提交链：17039fb（整包）→本节补记提交；顶端以补记提交为准，代码顶端 17039fb。
- CI：42802046562 **success**，Executed **657 tests, 0 failures**（基线 656＋新增 1：图标资产互异测；capabilityLine 断言组并入既有名单测，只增不减）。
- IPA：6,297,991 字节、md5 7166d443aac5e799d61c2b063acfd2ed、独立解包验 Info.plist＝0.36.3/70、Assets.car 内四资产名齐（LocalHermes/LocalWriteGate/LocalOneDayBridge/LocalOverviewBridge 各 1），落 ~/workspace/your_files/oneday-v0.36.3/oneday-unsigned.ipa。
- 版本五处同改＋grep 验：Project.swift 四处（0.36.3/70）＋SettingsView 页脚「OneDay v0.36.3」。
- 台账销项：C1-补、C6-补新增已销；P8 改已销（例外经用户推翻）；D 节补登四资产；G 节记本批全项。
- 待真机（并入终审积压）：设置页分隔引导是否被原生 List 采纳（不采纳即下版自绘行盒）；抽屉材质深浅双档呈现与底条衔接；设备详情页新语法与权限行三态（未授权/已授权/被拒）实点；本机服务四图标双档辨识度；详情页居中领头段观感。

## §69 0.36.4/71——体验包二：图片查看器重做＋模型菜单对齐＋抽屉颜色反转修复（规格 experience-trio-spec §3＋用户 18:48/19:0x 两件追加点名）

### 69.1 查看器落法（ImageViewerView，Sources/OneDayApp/ImageViewerView.swift）

1. **入参集合化**：`ImageViewerSession(items, initialIndex)`＋`ImageViewerView(items:initialIndex:onDeleteItem:)`，收敛六处入口——聊天四点（用户本地图/用户远端图/助手远端图/openChatFile 图片支，经 ChatView.openImageViewer 汇集同线程图片序、点中项不在集合回落单图）、DeliverablesView 文件行与影音网格（openEntry 按同段图片集合开 viewerRoute）、FilesBrowserView 文件行（同 shownEntries 图片集合）、FilePreviewView 图片支（防御落点单图）、BoxFilesView.DataFilePreviewView 图片支、BrowserView 截图（后二处为单图集合的同构收敛，超出规格「四入口」字面）。旧 ImageFullScreenView 整段退役（RichContentViews 原位留墓碑注），全仓调用清零。
2. **状态逻辑进 Core**：ImageViewerState（Sources/OneDayCore/ImageViewerLogic.swift）——count/index 夹紧、mode card|immersive、isZoomed、换页清缩放、回卡态清缩放、pagingEnabled=!isZoomed、chromeVisible=卡态；ImageViewerLayout.fittedSize 按图宽高比装入上限框不放大、非法尺寸回落 min 边正方形。ImageViewerSpec 落值进 DesignTokens（卡边距 16/卡圆角 16/关闭钮 44/胶囊高 40/钮宽 44，规格 §3.5）。
3. **双态**：卡态＝Palette.pageBG 底、图按 fittedSize 成卡（surface 底＋RoundedRectangle 16 裁切、居上、上限高 0.68 屏高）；沉浸＝纯黑全幅；点图 toggleMode（ZoomableImageView 新增单/双击识别器分流，单击 require(toFail:) 双击），回卡态经 resetToken 令 ZoomableImageView 复位缩放。
4. **翻页（有意偏离规格字面，理由记此）**：规格写 TabView(.page)，实际落横向 ScrollView＋.scrollTargetBehavior(.paging)＋.scrollPosition(id:) 双向绑 state.index。理由：TabView 的 .disabled 会连内层 UIScrollView 缩放手势一并封死，放大态无法查看；ScrollView 方案下 `.scrollDisabled(!pagingEnabled)` 只关外层翻页、内层缩放照常。沉浸翻页整页推移形态等价。
5. **chrome（仅卡态，glassEffect 系统玻璃件）**：左上 ✕ 玻璃圆钮 44；右上玻璃胶囊＝下载钮＋Menu（复制/分享/分隔/删除 destructive，删除仅当宿主给了 onDeleteItem）。动作作用于当前页已加载 UIImage：保存＝PHPhotoLibrary .addOnly 授权→performChanges（Project.swift 补 NSPhotoLibraryAddUsageDescription，.addOnly 口径文案）；复制＝UIPasteboard；分享＝PNG 落盘 FileShareItem（远端图沿原文件名、本地图名「OneDay图片.png」）；删除＝Haptics.impact(.heavy)→宿主闭包→dismiss。结果 notice 小胶囊 2.5 秒＋success/error 触感；翻页/切态/开关零触感（动效宪法 §2.3）。
6. **转场**：文件侧（Deliverables/FilesBrowser）＝NavigationStack 内 matchedTransitionSource（网格 cell/文件行按 path）＋.navigationTransition(.zoom(sourceID:in:))；聊天侧无栈＝fullScreenCover 内 ZoomTransitionCover（UIViewControllerRepresentable＋ZoomHostingController，viewDidLoad 设 preferredTransition=.zoom(options:sourceViewProvider: { _ in nil })）。**诚实边界**：聊天缩略图是 SwiftUI 视图、无 UIView 句柄，源视图提供者返回 nil，系统无源时 zoom 的确切降级形态未验、真机待验；聊天栈化时并轨 matchedTransitionSource。
7. **下拉关闭（追加验收项一）**：根 ZStack simultaneousGesture DragGesture（minimumDistance 8）：未放大时纵向主导（|dy|>|dx|）且 dy>0 才跟手——根视图 offset(y:)+背景渐隐（≤0.35）；dy>110（沿旧查看器 0.8.0 实证阈值）且纵向主导→dismiss()，否则 MotionTokens.dragSpring 回位。横向翻页与纵向关闭按主导方向分流，放大态不接管。
8. **关闭钮可达（追加验收项二）**：卡态 chrome 恒显（chromeVisible 裁决在 Core 有测钉死）；沉浸态点图即回卡态、chrome 随之出现——不存在「下拉关不了又找不到按钮」的死局。
9. **FilePreviewView 图片分支退役**：struct 重写——mediaKind==.image 直进 ImageViewerView 单图集合，非图保留 QuickLook 全套（标题/下载/分享不动）。
10. **存量死链顺带修复（如实登记）**：FilesBrowserView 的行 NavigationLink(value: entry) 此前全仓无 WorkspaceFileEntry 目的地注册、点按无落点；本包在其 body 补 .navigationDestination(for: WorkspaceFileEntry.self)（图片→新查看器、非图→FilePreviewView）。
11. **文件名漏出全仓扫描**：MediaCell 缩略失败占位的 Text(entry.name)（等宽字体压格、生成图名多为哈希串）已撤、只留类型图标。其余保留并判定为文件管理面本义、非漏出：FilesBrowserView 行名、DeliverablesView 行标题、聊天 FileChip（lastPathComponent）、DataFilePreviewView QuickLook 头名、FilePreviewView 非图标题。

### 69.2 模型菜单对齐（用户 18:48 点名）

ChatView.modelMenu 每行改同构 HStack：固定对号槽（ModelMenuSpec 进 Core——checkmarkSlotWidth 18/spacing 6）＋模型名，选中显 ✓、未选留空占位，模型名同列对齐。模型数据与 selectChatModel 逻辑零改动。

### 69.3 抽屉颜色反转修复（追加项一，根因单列）

- **实拍证据**：用户装 0.36.3 后浅色实拍——抽屉整面灰雾、选中行纯白胶囊浮灰底；Muse 对照为近白明亮面板＋浅灰选中垫，明暗关系反转。
- **根因（图层证据）**：DrawerShell 的 ZStack 自下而上＝内容→整屏黑蒙层（DrawerMotion.scrimOpacity 峰值 0.32）→DrawerView；0.36.3 的 drawerBackdrop .thinMaterial 采样的是合成链中它下方的画面——正压在其下的就是被黑蒙层压暗 32% 的内容，糊出来必然灰雾。选中行代码审计：drawerNavRow/drawerSideThreadRow 本就用 Palette.selectionFill（浅档 #F0F1F2），并非纯白——是雾底把浅灰垫反衬成刺眼纯白，属明暗关系整体反转，非令牌错误。
- **落法**：蒙层加 .offset(x: drawerOffset)（ContentView.DrawerShell 中层）——蒙层左缘恒贴抽屉当前右缘、只罩抽屉之外的露出区；抽屉材质改采样未压暗的内容本体：浅档明亮近白＋selectionFill 灰垫回位，暗档内容本深、材质压深不翻亮。选中行零代码改动。橡皮筋越界时蒙层随 drawerOffset 同步、衔接不变；点按关/横拖关只落露出区，抽屉本体手势无损；右缘柔影落在露出区蒙层上。底条霜层采样对象为抽屉材质本体、随底回正未动；Reduce Transparency 实色回退保持。

### 69.4 交付实录

- 提交链：56575a1（整包）→6040403（CI 修一：Hashable＋zoom 显式标签）→a2804ce（CI 修二：sourceViewProvider 非可选闭包 { _ in nil }）→本节补记提交；代码顶端 a2804ce。CI 前两轮 failure 均为新 API 签名编译错（navigationDestination(item:) 要求 Hashable、.zoom 重载歧义、ZoomSourceViewProvider 非可选闭包），第三轮绿。
- CI：42805444703 **success**，Executed **669 tests, 0 failures**（基线 657＋新测 12：ImageViewerLogicTests 9＋ImageViewerSpecTests 2＋ModelMenuSpecTests 1，只增不减）。
- IPA：6,377,981 字节、md5 07caa10c1625eacbf98094b77df2f23f、独立解包验 Info.plist＝0.36.4/71 且 NSPhotoLibraryAddUsageDescription 在包内，落 ~/workspace/your_files/oneday-v0.36.4/oneday-unsigned.ipa。
- 版本五处同改＋grep 验：Project.swift 四处（0.36.4/71，含新增相册权限键）＋SettingsView 页脚「OneDay v0.36.4」。
- 待真机（并入终审积压）：文件侧 zoom 转场源图衔接实感；聊天侧无源 zoom 降级形态；下拉关闭跟手感与横滚分流；沉浸点图回卡态；保存入相册全链（权限弹窗→相册可见）；抽屉双档修复后观感（浅档近白＋灰垫、暗档压深）；设置页分隔引导（0.36.3 遗留）。

## §70 0.36.5/72——插队包：聊天滚动双修＋目录与设备五点＋铃铛角标联动＋抽屉三件（用户 2026-11-10 19:03–19:27 逐项点名）

### 70.1 A 部·聊天滚动双修（根因真源 chat-detail-audit-20261110.md）

1. **发送不滚底**：根因＝send() 从不调 scrollToBottom、且自动跟随被 isNearBottom 门控（迟滞带：进 <96／退 ≥176）。落法＝发送例外通道：`@State sendPinToken`，sendTask 内 prepareSendShape 成功且过取消检查（条目落盘＋服务端链接已成、条目确定留下）后递增；messageList 侧 `.onChange(of: sendPinToken)` 执行三步——置 isNearBottom＝Core `BottomFollowPolicy.nearBottomAfterOwnSend()`（恒 true）、即时无动画 scrollToBottom、120ms 延迟复贴一次（guard 仍在本线程；沿本文件既有 80/120/300ms 复贴模式）。链接失败 catch 回滚删条目、停止（cancelPendingTurn）两条分支都到不了递增点——不给不存在的条目贴底。自己的消息无条件滚入视野是唯一例外；**零自动重发红线未碰**（本通道只滚视图、不碰发送/账本）。
2. **回底钮驻留**：根因＝距底距离取自 LazyVStack 估算 contentSize、长线程误差可驻留迟滞带。短修＝事实信号纠偏：既有 `.onScrollTargetVisibilityChange` 同批回写 `@State lastEntryVisible`（当前线程 sortedEntries 最后一条 id ∈ 可见集）；bottomBar 显隐改走 Core `BottomFollowPolicy.showsScrollToBottomButton(isNearBottom:lastEntryVisible:)`＝`!isNearBottom && !lastEntryVisible`，容器补以该派生值为键的 swap 动画（只挂 isNearBottom 时事实信号触发的出入会硬跳）。事实信号只进钮显隐、不改跟随门控/滚动锚。正修（浮层化＋未读计数）仍留 0.40.x。
3. **单测**：BottomFollowTests +3（自己发送恒贴底／最后一条可见时钮必隐／仅离底且最后一条不可见时钮显）。

### 70.2 B 部·目录与设备五点

1. **胶囊（B1）**：ConnectorsView.Segment 声明序改 available 在前、默认 `.available`；segmentSection 移名单首位（搜索框之下、本机服务/设备两组之前）。对照 references/muse-connectors-directory.jpg 逐项并排：胶囊紧贴搜索框、「可连接」在前且默认选中，两项合参考图。
2. **权限开关行（B2）**：DeviceStatusHeader.permissionRow 由三态按钮/整行点按式改单一 Toggle（标题「系统权限」＋状态 label 同行）。binding 口径：get＝permission.isUsable（granted/limited 为开）；set(true)：notDetermined→requestAccess（走真实授权流并回读状态、开关随真实结果落位）、denied/restricted/writeOnly→跳系统设置；set(false) 且 isUsable→跳系统设置（应用内关不掉已授权限、不造假落位）。与「允许智能体调用」仍为两个独立开关（S3 双层语义不破）；DevicePermissionGate 两条文案同步改开关口径（原引「去开启」）。
3. **设备五件图标复刻（B3）**：DeviceSymbolTile（SF 字形＋白底瓷砖）整类退役，新 DeviceAppIconView 按 DeviceSourceID 自绘矢量（squircle 0.26 比例＋separator 发丝边），三处调用点（目录行 40/详情头 64/设置总览行 40）同换。构图与色值以 2026-11-10 当日 iTunes Lookup 现取的官方 artworkUrl512 像素采样对版（采样在 /tmp 完成、原图不入包；台账 D 节补登）。五件：日历＝白底＋红星期＋黑大日期且 **TimelineView 动态真实日期**（periodic 自今日零点每 86400 秒刷新）；提醒事项＝白底三行圆点蓝（采样≈#0195FF）/红 #FF3B30/橙 #FF9500＋浅灰横线（圆点取实心、玻璃环光泽省）；通讯录＝浅灰底（采样≈(245,245,245)）＋灰人像剪影（≈(177,173,161)）＋右缘三彩签（蓝/橙/绿采样值）——「iOS 26 去彩签」弱源被现行商店图证伪、彩签保留定案；家庭＝白底＋橙黄渐变实心房子（宽檐＋门洞凹口路径；现行官方图为玻璃多层嵌套、扁平复刻取经典轮廓）。
   - **出入登记（健康）**：施工单/调研旧口径作「红心＋白色心电折线」；现行官方商店 artwork 像素实测心内无白折线（扫描心内多行近白像素为 0），心为粉→红渐变（中段≈(255,2,74)、下段≈(255,0,34)），两条独立网络描述同此。按对版真源画渐变心、不画折线；若用户真机主屏幕为经典款（带折线），一处小改可回。
4. **详情页退出（B4）**：根因＝设备三页（日历/提醒/通讯录）详情 List 全带 .refreshable，sheet 呈现时下拉先被下拉刷新截走（用户图 1 提醒事项页正是此形），且四类详情自 0.36.0 撤手写关闭后无任何按钮出口。落法双件：①ConnectorsView 新增 sheetStack 壳——四类详情统一 NavigationStack＋工具栏左上 ✕（系统玻璃圆钮、点按清 detailTarget）＋`.presentationDragIndicator(.visible)`；②三页详情加 `inSheet` 入参（默认 false），sheet 上下文经 RefreshableIfEnabled 禁用 refreshable、下拉归 sheet 关闭，设置页 push 路径（DevicePermissionsView）保留下拉刷新。关闭钮只落壳层、详情本体被 push 复用不带钮。

### 70.3 C 部·铃铛角标语义（裁决回执联动消账）

- **数据流实查**：overview-bridge 通知两源——write-gate decisions.jsonl（只在已裁决时生成 kind=write_gate_decision 回执、通知 id 为行哈希）与 oneday-bridge 监测账。病根：在 App 内批准后 pendingApprovals −1、桥却随即生成一条未读回执 +1，角标不降；回告卡（ReportCardPolicy 只取未读）与通知列表同源续显已决事项。decisions 条目本体带记录 id，但桥的 _make_notification 没把它带进通知——联动键缺失点在桥。
- **App 侧**：OverviewNotification 加 `refId: String?`（旧 payload 缺失解码为 nil）；Core `ApprovalResolution.receiptsToResolve` 纯函数（未读＋kind 逐字等于桥端 `write_gate_decision`＋refId 命中本人裁决集，三条全中才消）；AppState 加本机持久化本人裁决集（UserDefaults `selfDecidedApprovalIDs`、上限 200）；AgentHubStore.decide 成功分支（非 recordGone）在 removeRecord 后登记；OverviewBridgeStore 每次拉通知成功后逐条走既有 markRead 通道消账（桥确认才改本地、三处同源同消）。他人/自动审核（kanban review）裁决不在本人集内、回执仍作未读重要事件呈现。单测 +5（refId 解码有/缺、联动只匹配本人、跳过已读·非回执·无 refId、空集不消）。**存量出入登记**：既有测试夹具里 kind 写 `write_gate_decided`、与生产桥真实值 `write_gate_decision` 不符（旧账）——本批未擅改夹具，新判定逐字对齐生产值。
- **桥侧（仅本地、待部署）**：hermes-deploy/overview_bridge.py——_make_notification 增 `"refId": entry.get("id") or None`、_public 透出 refId（monitor 件恒 None）；新增 overview_bridge_selftest.py（子进程＋临时账本）**8/8 PASS**（回执带 refId＝记录 id／空 id 降 None／monitor 恒 None／未读计数）。**未部署**：部署前 App 联动不成立、角标按旧行为呈现（回执继续提示），部署与否待主会话/用户拍板。

### 70.4 D 部·抽屉三件（0.36.4 装机实拍点名）

1. **删「枢纽」行**：drawerNavList 中 title「枢纽」的 drawerNavRow 整行删除（原位留墓碑注）。删后入口实查清单：聊天页身份胶囊点按（capsuleRow Button→showHub）、聊天回告卡点按（onTapGesture→showHub）；枢纽 sheet 本体在 ChatView 不动；hubOpenRequested 通道与 ChatView 消费端保留（删行后暂无生产者）。
2. **右缘长线**：DrawerShell 查实无右缘描边/分隔（只有右缘柔影）；面板内唯一贯穿右缘者＝名单 ScrollView 的默认滚动指示器。改 `ScrollView(.vertical, showsIndicators: false)`。
3. **顶部带断层（19:27 口径修正：整块取消、非统一材质）**：原实色带来自两处叠加——①safeAreaBar 注册把标题锁进一块独立带（名单滚不到带下、天然有界）；②0.36.3 给带内名字单挂一层 drawerBackdrop、与根背景同名材质叠成双层，带面比主体更实更灰。落法：safeAreaBar 整段删除；标题改 ZStack 顶部浮层（VStack{drawerAgentName; Spacer()}、allowsHitTesting(false)），只剩文字本体悬于根背景同一层 drawerBackdrop 之上（ZStack 顶＝安全区顶、状态栏之下；Reduce Transparency 时根背景落实色、浮层随之同面）；名单加 `.contentMargins(.top, 70, for: .scrollContent)`（70＝名字顶距 24＋Title1 行高约 34＋底距 12，与 drawerAgentName 现行距共用一数、抽为 titleStripHeight 常量）——静止时首行停在标题下方、滚动时行从标题文字后方穿过。已知边界：Dynamic Type 极端档行高变大、静止时首行可能被标题略压，待真机。


### 70.5 交付实录

- 提交链：08778c5（整包）→5073f72（CI 修一：RefreshableIfEnabled 的 action 补 @MainActor 隔离标注——refreshable 形参 @Sendable 转换在 Swift 6 下拒绝未标注函数值）→本节补记提交；代码顶端 5073f72。首轮 CI 42809148844 failure 即此一处编译错，第二轮绿。
- CI：42809473654 **success**，Executed **677 tests, 0 failures**（基线 669＋新增 8：BottomFollowTests 3＋OverviewBridgeTests 5，只增不减）。
- IPA：6,412,196 字节、md5 77a562cae7a7364278e1474d8cdf8f88、独立解包验 Info.plist＝0.36.5/72，落 ~/workspace/your_files/oneday-v0.36.5/oneday-unsigned.ipa。
- 版本五处同改＋grep 验：Project.swift 四处（0.36.5/72）＋SettingsView 页脚「OneDay v0.36.5」。
- 台账/总纲：宪法 §4 修订文本已落总纲（ui-design-philosophy §三.4，标 19:19 修订）；台账 C7 升级注、D 节 0.36.5 五件补登、H 节本批六条补记；C16 底栏终审同日经用户 19:34 真机通过销项（非本批施工）。
- 桥侧：overview_bridge.py refId 改动与 overview_bridge_selftest.py 在 ~/workspace/hermes-deploy 本地完成、自测 8/8；**未部署生产**（待拍板），部署前 C 部 App 联动不成立。
- 待真机（并入终审积压）：发送后贴底实感（含长线程）；回底钮在事实信号下消失时机；胶囊新序与默认落地；权限开关五态实点（未定请求弹窗/已授权拨关跳设置）；设备五件图标辨识度（日历动态日期、通讯录彩签、健康渐变心对版）；详情页下拉关闭与 ✕ 并存手感；抽屉标题浮层下名单穿行与右缘无指示器观感、Dynamic Type 极端档标题压首行边界；角标联动待桥部署后才可验。

## §71 0.36.6/73 语音输入（端上路线，用户 2026-11-10 18:37 点批；规格 voice-input-spec-20261110.md）

### 71.1 定位与红线
发送舱麦克风自 0.2.5 起是纯占位（action 为空、无障碍标签写死「尚未开放」、全仓零录音/识别代码、无麦克风/语音识别 UsageDescription）。本版接入真语音输入。红线：**服务端路线不做**——Hermes 无转写端点、上游 DeepSeek 无 STT；只走端上 iOS 26 SpeechAnalyzer＋SpeechTranscriber，录音不出手机。回退链 DictationTranscriber→键盘听写（预备页与失败行均明示此路）。

### 71.2 落法
- **纯逻辑沉 Core**（Sources/OneDayCore/Dictation.swift，单测 DictationTests 19 个）：DictationPhase 六相位＋DictationPhasePolicy 转移守卫（迟到回调想把已落定相位拽回一律拒绝）；DictationSession 转写会话合并（开录记 baseDraft；final 段只追加并清 volatile、volatile 整段替换禁逐字追加；落稿 committedText(includeVolatile:)；取消只回 baseDraft；中英拼接空格启发式）；DictationLevel（RMS/dB 归一化 -50..-10dB）＋DictationLevelSmoother（一阶低通、快攻 60ms/慢放 180ms）＋DictationWaveform（9 条采样环）；DictationTiming（上限 300s、警示 270s、m:ss）；SilenceTracker（归一化电平 <0.05 连续 10s 出提示）；DictationLanguage 三语（普通话 zh_CN/粤语 yue_CN 回退 zh_HK/英语 en_US）；DictationFailure 六类。
- **App 接线**（DictationController @MainActor @Observable）：权限门（AVAudioApplication.recordPermission＋SFSpeechRecognizer.authorizationStatus 双查：双授直开录、未定弹预备页、被拒走失败行不弹系统窗）；资产门（AssetInventory.status→未装进 .preparing 相位、assetInstallationRequest.downloadAndInstall 带进度）；引擎链（supportedLocale(equivalentTo:) 规范化 locale→SpeechTranscriber(.volatileResults)→bestAvailableAudioFormat（资产后取）→AVAudioEngine tap（硬件格式）经 AVAudioConverter（primeMethod=.none）转码分发：一路 yield AnalyzerInput、一路 RMS 写无锁盒供 10Hz 计时轮驱动波形/电平/静音/计时）；结果消费任务先于 analyzer.start 启动（DocC 口径）；收尾 finalizeAndFinishThroughEndOfInput＋2s 超时 cancelAndFinishNow 兜底、结果流 drain 上限 2s；代次（generation）守卫作废一切迟到回调；来电/媒体服务重置中断→已定稿＋当前未定稿落框＋失败行 interrupted；引擎抛错→已定稿保留、未定稿弃＋engineError。
- **交互**：点按切换（非按住）；录音条 DictationBar 占住发送舱同一玻璃胶囊——文本行（既有 ComposerTextView）在上、控制行（✕/波形＋计时/✓）在下；字幕直进文本视图、未定稿尾段经 ComposerTextView 新增 volatileTailLength 染 secondaryLabel（只改渲染属性、（文本,尾长）键缓存防重建、UTF-16 换算、IME 期跳过）；落框即普通草稿、可改、**不自动发送**；5 分钟到限自动落稿＋warning 触感＋提示行（5 秒自清）；4:30 起计时变 Palette.warning 色；连续 10 秒无声只提示不停录；没识别到字→nothingHeard 失败行；失败行三段式文案（零行话）＋权限类带「去设置」。
- **权限**：双 UsageDescription 入包（§71.4 验）；预备页 DictationPrepSheet 五段式（一句话能力/本机识别不上传披露/麦克风与语音识别分开列/语言三选/整宽主按钮「开始使用」＋「用键盘听写」纯文字降级＋键盘听写说明小字）；点「开始使用」才触发系统弹窗（S1–S4）；sheet 手势关＝放弃回 idle（prepFlowActive 防 onDisappear 误杀进行中的权限流）。
- **触感**：先修《动效宪法》表 D 增五行再施工（宪法第 6 条）——开始录音 impact light、取消 impact light（不用 heavy）、停止落稿无、达上限 notification warning、失败/打断归 error 行。Haptics.swift 头注同步更新落点。

### 71.3 预登记出入（如实）
1. **录音形态**：规格 §3.3「字幕直进文本视图」为硬要求，录音条取胶囊内两行形态（文本行＋控制行）而非字面同一行——与发送舱既有多行形态同构、不新造高度轴，玻璃与实测高回写两态共用。
2. **带草稿入口**：mic 沿现行 ComposerTrailingState 三态（仅空输入态出现，0.25.0 定版不推翻），故「已有草稿时点 mic」本版不可达；Core 的 baseDraft 追加合并已完整实现并单测把守，入口放开只待后续包改三态口径。
3. **270s 警示**：只变色不震，warning 触感落在 300s 自动停一刻（表 D 落值行）。
4. **语言切换入口**：只在预备页（权限未定时出现）；授权后改语言暂无入口，待后续包并入设置页。

### 71.4 宪法逐条过（摘要）
设计宪法：①录音条一屏一主角（波形＋计时）②数值出自标尺（间距走 OneDayMetrics、键径 ComposerLayout.buttonHeight）③不新增分隔面 ④图标全 SF Symbols 系统源（mic/xmark/checkmark/exclamationmark——无名功能面）⑤录音条无标题、预备页内容领头 ⑥层级≤3 ⑦同构列表（语言三选行）⑧文案零行话零外文（失败/预备页全中文人话、禁用词 8 词零命中）⑨可点必有指示、点必有反馈（✓ 准备中禁用＋淡化、失败行带动作）⑩仿机制：点按切换＋流式灰字＋落框可改照大厂共识（ChatGPT 按住式回滚为反例据）。动效宪法：触感按表 D 新行投放；波形动画为真实电平驱动的信息承载（非装饰）、Reduce Motion 降为单条电平尺；无新增弹簧面。续编：S1 冷启动禁问（只在点 mic 时）、S2 问前预备页、S3 系统权限与功能分开说、S4 被拒有降级（去设置＋键盘听写）、S10 报错三段式、状态呈现各相位齐备（准备中带进度、录音中波形计时、失败带行）。

### 71.5 验收与诚实边界
- 提交链：6920e2d（整包）→2b0f049（CI 修一：DictationViews 补 import OneDayDesign；assetInstallationRequest 实为 throws 补 try）→81602be（CI 修二：波形断言 bars.last 为 Optional 改下标）→本节回填补记；代码顶端 81602be。首轮 CI 42812243954 failure＝上述两类编译错，第二轮 42812742797 failure＝测试编译一处，第三轮绿。
- CI：42813499346 **success**，独立计数 **696 tests 全过、0 failures**（基线 677＋新增 DictationTests 19，只增不减；日志逐条 Test Case passed 去重计）。
- IPA：6,529,378 字节、md5 e69fe9b69b36731f665cbc35882af249、独立解包验 Info.plist＝0.36.6/73、NSMicrophoneUsageDescription 与 NSSpeechRecognitionUsageDescription 两条均在包内且为定版文案，落 ~/workspace/your_files/oneday-v0.36.6/oneday-unsigned.ipa。
- 版本五处同改＋grep 验：Project.swift 四处（0.36.6/73）＋SettingsView 页脚「OneDay v0.36.6」。
- 总纲：动效宪法表 D 已增五行（开始/取消 impact light、落稿无、达上限 warning、失败打断归 error 行），motion-interaction-philosophy-20261110.md。
- **待真机（不许假报）**：识别准确率与首字延迟；电平波形实感（tap 若为非 Float 格式，电平退化为 0、识别不受影响）；权限弹窗链（麦克风＋语音识别双弹窗的实际次序、SpeechAnalyzer 是否要求语音识别授权的运行时行为）；资产下载的真实耗时与进度形态；来电中断的真实触发；粤语 yue_CN 在真机资产的可用性；录音条与玻璃胶囊的高度衔接观感；染灰尾段在真机渲染的跟随感。

## §72 0.36.7/74 视觉修三部（铃铛页重排＋连接器页小修＋抽屉选择态单一化）

规格真源：A 部 notifications-page-benchmark-20261110.md §3；C 部 channels-conversations-design-20261110.md §10（验收口径 §10.4）。基线顶端 3fc716f、696 测。

### 72.1 A 部·铃铛页

- **文案模板表（Core 新设 NotificationSummary）**：裁决类 body（Hermes 暂存 summary 原文）按可穷举文法翻人话对象句——记忆 M1 add／M2 remove／M3 replace（old 换行 new）／M4 apply 多 op 聚合（前 2 条短句＋「等共 N 处」）；技能 S1–S3 batch 聚合（op 按首次出现序计数：patch→改了 N 处内容、write_file→写了 N 个文件、create→新建了 N 个文件；单技能单 patch 短形「改了技能「x」的内容」；多名只显前两名＋「等共 M 个技能」）。对象文本先折叠空白、取前 60 字＋「…」、包中文引号；语态自桥结论标题派生（批准＝完成式、驳回＝未执行式）。**解析不出（文法不命中／op 表外值／op 条数与声明不符／语态不明）禁止直出原文**：降级通用句（「一项记忆写入已批准」式，与桥自带兜底同式），原文收进点按展开的次级详情「原始记录」（等宽小字，S10）。监测类 body 成形文案直通（只折叠空白）。
- **相对时间（DisplayDate 新增 relative 档）**：按流逝时长——<60 秒「刚刚」（负值同档）／<60 分「N 分钟前」／<24 小时「N 小时前」，满 24 小时整档让渡五档 dateTime（同源同算法）；跨日界但流逝 <24h 仍相对（不跳「昨天」）。页面每 60 秒重算（S7）。原 `.relative(presentation:.named)` 系统格式器删除（英文漏出元凶）。
- **行与分组**：三行结构（标题 Body 17 regular 冻结——未读 ink 全色／已读 inkSecondary；摘要 15、限 2 行；元信息 Footnote 13 inkMuted 等宽数字＝相对时间，监测类后缀「· 监测」）；未读只留一个信号（8pt 强调色点、顶偏移 8），已读不画点留空列保对齐；行内边距 20/12、分隔整行贯通（separatorLeading 归零）；按日分组（组头 DisplayDate.dateOnly、Footnote inkMuted、上距首组 8/其余 24、下距 8）、全表时间倒序，**废除旧「未读在前」重排**；点按：未读标已读、已读展开次级详情；达桥上限 50 条时表尾如实标注「只显示最近 50 条」。
- **全部已读**：未读 ≥2 时首组组头右侧出文字钮；store 新增 markAllRead——逐条 POST 确认、只改成功条目、任一失败整体报 false，视图 alert 三段式（没全标上／失败条保持未读／下拉刷新再试），不假清。角标与未读数仍以桥为准。
- refId 联动（0.36.5 C 部）未动、回归在列。

### 72.2 B 部·连接器页

- **删脚注**：本机服务组下方备注脚注整段删除、不留替代文案（用户 19:54 点名：那段是给开发者解释分组口径的）。
- **胶囊间距收紧**（先量后改，改动落既有标尺）：本页 List 的 listSectionSpacing 自 settingsSectionSpacing 28 → spacingM 16（胶囊与搜索框、与下方名单的间距同源于此）；分段胶囊行自身上下内边距 4→0（间距只由一处出、不叠加）。合计胶囊上下呼吸约 32pt 级 → 16pt。本页其余组间距随之同紧（目录面紧凑口径与 Muse 参照一致；设置页本体的 28 不动；同文件内详情 sheet 的三处 28 不动）。

### 72.3 C 部·抽屉选择态单一化

- **Core 新设 DrawerSelectionPolicy**（纯函数＋单测）：全抽屉唯一选择源＝「当前正在看的对象」，值域三值 .surface(tab)／.main／.side(UUID)＋空态 .none；解析优先级按 §10.2——非聊天表面→.surface（会话行全体无胶囊）、有显式对象引用→按引用、无引用→落点线程派生、皆无→.none。.channel 值不在本版（0.36.9 在本政策上加值，不许另起一套）。
- **置位纪律（§10.3）**：AppState 新设 currentDrawerObject 单一引用。写点：抽屉主线行点按→.main、旁聊行点按→.side(id)（导航动作显式写）；ChatView 当前线程同步两处（currentThreadID 变更点＋首次出现点）经 Policy.object(forThreadID:mainThreadID:) 派生回写——落点解析／抽屉改道／新建／openServerSession 导入最终都汇到 currentThreadID 变更、一处收口。页签切走不清引用、回切恢复。
- **退役**：AppState.activeThreadID 字段整删——全仓消费面核清只剩胶囊判定（DrawerView 旁聊行）与删当前线程判定（deleteThread），前者改问政策、后者改经政策判定（.side 命中，或 .main 且 SideChatClassifier.isMain），ChatView 两处回写同步改对象引用。导航行 selected 全改政策结果（主线行＝.main 才亮、非聊天行＝.surface(该格) 才亮）。底栏不在辖区、未动。
- 搜索态名单与旁聊区共用 drawerSideThreadRow，胶囊随政策同口径（被搜掉的当前行不显属正常，§10.3）。

### 72.4 预登记出入（如实）

1. **左滑「标未读」不落**：规格 §3.1 列左滑标已读／标未读二选一，但 overview-bridge 只有 POST /notifications/{id}/read 一个写端点、无标未读落点；且 §3.5 定角标以桥为准、本地不自算——本地假标未读会在下次拉取被覆盖且与角标打架。本版左滑只给未读条目的「标已读」；待桥补端点后再补，不在本版造假态。
2. **技能驳回形为类推落法**：规格模板表只给了技能 approved 形与 M4 的「未生效」驳回式；技能 batch 驳回按 M4 同式落「技能「…」的 N 处改动未生效」（完成式动词不进驳回句，守 §9 如实），已单测钉住；若桥侧将来给出官方文案再对平。
3. **§3.6 断桥有缓存态不适用**：施工核对——现行 OverviewBridgeStore 失败即清空 notifications、无缓存保留，本版未新增缓存层，该态按规格注记以「断桥、无缓存」呈现为准。
4. **DrawerSelection 加 .none 空态**：§10.2 值域三值未含「聊天表面且无对象可派生」的极端情形（无线程/落点未定），加 .none 表「不画假当前」；稳态不可达、单测钉住。

### 72.5 验收与诚实边界

- 提交链：2181348（整包）→本节补记提交；代码顶端 2181348。
- CI：42816201615 **success**，独立计数 **736 tests 全过、0 failures**（基线 696＋新增 40：NotificationSummaryTests 23＋DrawerSelectionTests 9＋DisplayDateRelativeTests 8，只增不减；逐条 Test Case passed 去重计）。
- IPA：6,585,988 字节、md5 c75fe5fc91e3d1e524a4d0330e9c9a99、独立解包验 Info.plist＝0.36.7/74，落 ~/workspace/your_files/oneday-v0.36.7/oneday-unsigned.ipa。
- 版本五处同改＋grep 验：Project.swift 四处（0.36.7/74）＋SettingsView 页脚「OneDay v0.36.7」。
- A 部模板表覆盖通知类型：write_gate_decision 的记忆四文法（add/remove/replace/apply）＋技能 batch 一文法（含 create/write_file 分列计数）、monitor_change 直通、未知 kind 直通兜底；截图 8 条实样逐条入单测（M1 驳回实样、M2 实样、M4 实样、S1/S2/S3 实样）。
- C 部五场景验证方式：①看主线 ②看旁聊（报障原图场景）③非聊天页签 ④旁聊回主线 ⑤切页签再回聊天——五场景均落 Core 政策单测逐条断言（DrawerSelectionTests 前五测一一对应）＋静态代码审计（全仓 grep：activeThreadID 零残留、DrawerView 无 currentTab == 私判、行 selected 全出政策）；ChatView 两处同步点与抽屉两处导航置位点逐点核对。真机逐场景肉眼验归用户终审（§10.4 口径）。
- **待真机（不许假报）**：铃铛页三行密度与组头节奏、相对时间三档实显、全部已读失败路径实感（需桥侧故障才触发）、展开次级详情的手感；连接器胶囊收紧后的实际呼吸感（16 为代码量测、观感归用户）；抽屉五场景胶囊唯一性真机复验；本人裁决回执 refId 联动回归（桥已部署、待下一次真实裁决自然验）。

## §73 0.36.8/75 语音闪退热修（2026-11-10）

起因：0.36.6 真机首用语音，预备页走完、系统权限点「允许」后立即闪退。诊断定稿 voice-crash-diagnosis-20261110.md（根因排序：①installTap 喂未验的 0 Hz 输入格式抛 NSException、Swift catch 不住；②多余的 SFSpeechRecognizer 授权门——官方口径 SpeechAnalyzer 不需要、且重签包 plist 若被动过此步必 SIGABRT；③管线比值无有限性守卫）。本版按诊断 §5 同包全修，两根因互不冲突、不等 .ips 实锤先修后关账。

### 73.1 五条修法落点

1. **删整道语音识别授权门**（DictationController）：prepConfirmStart 只请求麦克风；handleMicTap 已授权直启判断只看 AVAudioApplication.recordPermission（.granted 直启／.denied 失败行／其余进预备页）；requestSpeechPermission 整删，全仓 requestAuthorization 零残留（仅余 ImageViewerView 的相册授权、与本包无关）。DictationViews 预备页删「需要开语音识别」行、失败文案改只提麦克风；Core 的 permissionDenied 注释同步。NSSpeechRecognitionUsageDescription 键保留在 plist（Project.swift 未动、无害），代码不再调用该 API。
2. **tap 格式有效性门**（Core 新设 DictationAudioFormatPolicy.isUsable＋DictationController.startEngine）：读 inputNode.outputFormat 后先过门（sampleRate 有限且 >0、channelCount >0）；无效先 engine.prepare() 复读一次，仍无效清 session 走 .unavailable 失败路并落 formatInvalid 面包屑（带实际 rate/channels 值），绝不把无效格式递给 converter/installTap。installTap 改传 format: nil（节点实时格式）；转换器改由 DictationAudioPipe 以首个 buffer 的实际 format 惰性建立（格式变更自动重建），开录前快照竞态整类消除。管线比值改走 Core conversionRatio 有限性守卫，无效整帧丢弃（原 UInt32(∞) trap 面消除）。
3. **音频会话对齐 WWDC25 样例**：setCategory 改 .playAndRecord、mode 改 .spokenAudio（原 .record/.default）。回归面核查：全仓无其他 AVAudioSession 类别设置、无 AVAudioPlayer/AVPlayer 播放面，不存在与既有播放共存的冲突面；录音条/电平链未动。
4. **os.Logger 阶段面包屑**（DictationController）：subsystem site.didichou.oneday、category dictation；markStage 同步把末阶段写入 UserDefaults dictation.lastStage。打点：micGranted/micDenied、moduleBuilt、assetReady、sessionActive、formatReady/formatInvalid、tapInstalled、analyzerStarted、engineStarted、recording、firstResult、startupFault/engineFault——授权、资产、会话、格式、引擎、首结果全阶段各一行。
5. **假录音根除**（Core 新设 DictationFaultPolicy＋App pipelineFault）：analyzer.start 与结果流抛错统一走 pipelineFault，按政策分相位处置——.recording→.engineError 失败收尾；.requestingPermission/.preparing→置 startupFault 闩，startEngine 在 engine.start() 成功后、宣布 .started 前检查并拆管道回 .startFailed（startPipeline 据此 fail(.engineError)，不走回退链误报不可用）；已落定/收尾中/代次不符→ignore。旧 engineFailed 的 phase==.recording 守卫整删。

### 73.2 验收

- 提交：3513249（整包，代码顶端）；本节为补记提交。
- CI：42818056427 **success**，独立计数 **739 tests 全过、0 failures**（基线 736＋新增 3：testAudioFormatPolicyGate／testConversionRatioGuards／testFaultPolicyMatrix，只增不减）。
- IPA：6,589,021 字节、md5 7d0cd7f6aec43a52f5a3d5419ae3620f、独立解包验 Info.plist＝0.36.8/75、双 UsageDescription 键仍在包内，落 ~/workspace/your_files/oneday-v0.36.8/oneday-unsigned.ipa。
- 版本五处同改＋grep 验：Project.swift 四处（MARKETING_VERSION/CURRENT_PROJECT_VERSION/CFBundleShortVersionString/CFBundleVersion＝0.36.8/75）＋SettingsView 页脚「OneDay v0.36.8」。
- 未碰：发送链与贴底逻辑零改动；NSSpeechRecognitionUsageDescription plist 键未动。

### 73.3 诚实边界

- **首授时序只能真机验**：根因 1 的触发条件（首次授权瞬间格式未就绪）是真机 TCC＋音频 HAL 时序，CI 模拟器复现不了；本版以「格式门＋nil 格式＋惰性转换器」把该窗口整类消除，但「点允许不再闪退」的最终判定归用户真机首试。
- **根因 2 是否中招仍未实锤**：万能签重签后安装包 plist 状态本侧未验；删门后该路径已不存在（代码零调用），无论重签是否动过 plist 都不再受影响。.ips 关账仍欢迎：若用户方便提供崩溃日志，可回填诊断档判定两根因各自的实际占比。
- .playAndRecord/.spokenAudio 在真机上的副作用（外放/听筒路由、与系统听写共存）未真机验，归真机终审一并看。

## §74 0.36.9/76 语音闪退热修二轮（2026-11-10）

起因：0.36.8 真机仍闪退。本轮不再自研猜测，转按礼记（liqian-app）同案终局结论对齐：该案 2026-11-07/08 前后猜错两轮（缺权限文案、采样率 0 格式闸门都修了仍崩），最终靠 .ips 崩溃日志破案——**权限早已授过、处「已决定」状态时，代码每次仍重走异步授权回调；iOS 26 上该回调在特殊线程投递、闭包隔离对不上就在回调入口崩，专挑已决定状态、不弹框点就崩**；终修＝先同步读状态、已授权直接启动、永不重走异步回调。OneDay 亲读坐实同雷：`prepConfirmStart()` 无条件 `await Self.requestMicrophonePermission()`（内部即 `AVAudioApplication.requestRecordPermission` 回调续体）——0.36.8 删掉的是 SFSpeech 门，麦克风这道仍在无条件重走；而 handleMicTap 一侧反而早已是同步读 recordPermission 的正确形态。用户为万能签重签安装，重签可能使 TCC 状态回落未决定、也可能保持已授，预备页路径是高频入口，两端都须覆盖。

### 74.1 修法落点

1. **同步门政策入 Core**（OneDayCore/Dictation.swift 新设 `MicPermissionStatus`＋`MicPermissionGate`）：granted→.start／denied→.failDenied／undetermined→.requestOnce；App 层 `DictationController.micPermissionStatus` 只做系统枚举→Core 状态的映射，判定单点化不在接线层散写。
2. **prepConfirmStart 改同步门**（DictationController）：确认时先同步复读——.start 分支 `markStage("micAlreadyGranted")` 直达 startPipeline，不发任何请求；.failDenied 走 fail(.permissionDenied)＋触感；仅 .requestOnce 才调 `requestMicrophonePermission()`（全仓唯一异步请求点、受门调用）。handleMicTap 同步改走 Gate（行为与 0.36.8 一致、判定收归单点）。
3. **grep 证据**：`requestRecordPermission` 全仓仅剩 DictationController.swift 一处实现（L772，受门）；`requestAuthorization` 仅余 ImageViewerView 的相册授权（与听写无关，沿 §73 注）。
4. **诊断可见化**（礼记同案后手）：新设 `DictationStageDiagnosticLine`（DictationViews）上屏 `dictation.lastStage`——预备页页脚与聊天页失败行各一处，整行明标「诊断信息 · 上次语音停在：xxx」，阶段码为内部记号、与用户文案口径分开标注；读取口为 `DictationController.lastStageSnapshot`。
5. **保留不动**：0.36.8 全部修法（格式门、installTap 传 nil 格式＋惰性转换器、.playAndRecord/.spokenAudio、阶段面包屑、FaultPolicy 假录音根除）；发送链与贴底逻辑零改动。

### 74.2 验收

- 提交：770cbd9（整包，代码顶端）；本节为补记提交。
- CI：42819802613 **success**，独立计数 **741 tests 全过、0 failures**（基线 739＋新增 2：testMicPermissionGateThreeBranches／testMicPermissionGateNeverRequestsWhenDecided，两条新测日志逐条 passed，只增不减）。
- IPA：6,595,556 字节、md5 ee5afbd221a6e12af1651c9f25e97ca1、独立解包验 Info.plist＝0.36.9/76、双 UsageDescription 键仍在包内，落 ~/workspace/your_files/oneday-v0.36.9/oneday-unsigned.ipa。
- 版本五处同改＋grep 验：Project.swift 四处（MARKETING_VERSION/CURRENT_PROJECT_VERSION/CFBundleShortVersionString/CFBundleVersion＝0.36.9/76）＋SettingsView 页脚「OneDay v0.36.9」。

### 74.3 诚实边界

- 本案根因结论来自礼记同案的 .ips 实锤＋本仓代码亲读坐实同雷形态；OneDay 自身的 .ips 仍未到手。若本版真机仍崩，预备页/失败行已上屏的 lastStage 就是下一轮第一证据，按同案纪律停猜、先拿日志。
- 重签对 TCC 的实际影响（回落未决定／保持已授）本侧不可验；同步门按两端设计：已授不重走回调、未决定才发唯一一次。
- 「点麦克风不再闪退」的最终判定归用户真机首试：CI 绿只证构建与逻辑，不冒充真机验收。

## §75 0.36.10/77——五判词修复包（用户 2026-11-10 20:45 对 0.36.7 的五条真机判词；诊断 redevice-verdicts-diagnosis-20261110.md D2/D3）

判词来源：用户装 0.36.7 后连发五条——①连接器页脚注没删干净 ②分段胶囊间距修偏（0.36.7 修的是 section 间距，病根在系统控件本体） ③工具卡又多又复杂 ④通讯录授权了目录行写「可调用」是越界宣称（device MCP 当时未注册） ⑤回答完了底部还挂「进行中」＋卡里一条「虚线」。①②③⑤在本包，④的服务端注册由并行线同晚办讫（App 侧只改文案口径）。

### 75.1 五件逐条对账

1. **脚注删净（ConnectorsView）**：「你的设备」组 footer 解释段与页面最底总结段整段删除，目录页自此零说明段。信息不丢失的落点：数据边界逐件在各自详情页（descriptor.footnote 在 DeviceStatusHeader 尾段，如通讯录「只有你打开调用开关…」）；接入路径在目录条目详情（catalogDetail 的 accessSummary/accessDetail，含「App 内暂不能直接连接」如实句）。判词点名的两段原文已 grep 验零残留（App 呈现层）。
2. **分段胶囊量测对齐**：系统 Picker.segmented 退役，改与文件页同源的自制胶囊（SegmentedControlSpec，0.36.2 定版）：轨道 Palette.surface 白＋发丝边、总高 48、药丸高 36、内缩 6、选中 Palette.selectionFill #F0F1F2 灰垫、字 17 semibold 两态皆 ink、matchedGeometry 滑移＋.selection 触感；行 insets 上下 0、左右 20，分段与上下节间距只由 listSectionSpacing 16 一处出。量测（2026-11-10 用户图，1206×2622 @3x 像素量）：Muse 对照页轨道纯白 #FFFFFF（边 ≈#E9EAEC）、选中片 #F3F4F6（与页面底同值）、轨道高 ≈47.5pt、内缩 ≈5pt、搜索框底→轨道顶 16pt、轨道左右边距 ≈21pt；OneDay 0.36.7 实拍轨道 #E3E2E8 灰紫、选中片白（角色反）、轨道高 ≈31pt、搜索框底→轨道顶 ≈55.7pt。spec 落值与 Muse 量测 ±1pt 内吻合，故直接同源复用、不新造数值；左右边距 20 由本页 List 行距承接（与 Muse ≈21 及本页节奏一致）。
3. **设备目录行文案改实话**：Core DeviceRowStatus.line 并入「设备会话是否在线」（DeviceSessionController.sessionOnline，本地可验）：已授权＋开关开＋会话在线才拼「可调用」；开关开但离线降为「会话未连接」；开关关「调用已关」；权限未授/被拒/仅写入权限/待签名权益各分支如实不变。消费方两处（ConnectorsView 目录行、DeviceViews 总览状态）同传 sessionOnline。详情页通道状态节脚注改动态 channelNote（权限/开关/在线三件本地事实拼成），旧静态句「智能体实际调用待服务器侧门面注册开通…」退役；DevicePermissionsView 通道状态行同类旧句改会话实话（前台才活着、未连接叫不到、回前台自动恢复）。目录行/详情页/总览三面自此同源同口径，不许再出现 App 验不了的服务端状态宣称——服务端注册是事实（同晚已办），但 App 写「可调用」的依据只能是会话在线这一可验信号。
4. **工具卡紧凑化（诊断 D3 十条逐销）**：D3-1 卡面收敛一行（36 图标盒＋标题＋副行＋状态字），整卡点开卡内详情（调用参数 pretty JSON 原文／结果全文／状态／工具原名行）；ToolCard 新增 arguments 存原始参数全文，旧落盘卡缺键解码回 nil 兼容（单测钉死）。D3-2 摘要单行化：副行 = 参数摘要（截断）→ 结果首行净化 → 「（无输出）」，浏览器卡副行优先页面 URL。D3-3 标题映射补 manage_connections→管理连接＋设备十工具中文名；分类新增 .connection/.device（device 前缀须排在 search 之前：contacts_search 归设备）；未知工具回落改 Core fallbackTitle 中文类名，Builder 与累积器的回落链中服务端 label 与英文短名彻底退出卡面（英文原名保留 toolName、只进详情）。D3-4（适配）：runs events 通道不带参数分片，直播卡无真参数——直播期以分类标题＋中文兜底＋净化 preview 摘要呈现，落定以 transcript 真参数重建为权威，此偏差如实记录。D3-5 terminal 复合命令摘要改「N 条命令 · 首条」（Core commandSummary，summary 的 terminal 分支与默认字段序 command 命中同走），combo 夹具旧断言随之迁移为精确等值（意图不变）。D3-6 直播结果先过 ToolResultUnwrap.unwrap 再存卡，与落定同口径；直播期失败标记 = 事件 failed 与 unwrap 信号取并集（D3-9 一并），落定以 transcript unwrap 为准。D3-7 unwrap.isMeaningless 新增：空或通篇分隔符/空白（如 "---"）判无意义，卡面呈「（无输出）」、不画符号——判词⑤截图的「虚线」即此。D3-8 连续 ≥2 卡成组：落定走 entryRenderItems（连续 toolCard 条目收 ToolCardGroupView，组头 Core groupHeader「调用了 N 个工具 · 全部完成／F 个失败／R 个进行中 · F 个失败」）、直播走 liveRenderItems 同制，单卡不进组。D3-10 直播区按事件序：liveOrder 标记（思考/正文首达、工具卡创建时记位）交错渲染，标记外卡殿后成组、正文缺标记殿后补位；落定序本就是 transcript 原序，不动。
5. **进行中改卡级（诊断 D2）**：Core ToolCardPresentation.state(of:) 单一真源——本卡 result==nil 才 running，回来即按 resultFailed 落 succeeded/failed；ToolCardView 删除整轮 isLive 入参，状态字/转圈/失败徽标全走卡级；组头计数同源。**补根（诊断外新发现，判词⑤的另一半）**：finishRunPresentation 从不清空 liveToolCards——落定条目入列后，残留的直播卡仍挂在列表尾同屏渲染、且因 result 恒 nil 永远「进行中」，正是用户截图底部那截残影（"…age connections"＋"Searching tools · contacts list"）；收尾统一清 liveToolCards＋liveOrder（全部落定/失败/取消出口共用此收尾，persistRunPartials 在其前调用、对账不误伤）。思考段 contentStarted 口径不变、正文气泡 id "streaming" 保留。

### 75.2 验证

- 版本五处同改 0.36.10/77（Project.swift 四处＋SettingsView 页脚），grep 验讫。
- 单测 741 → **751**（+10，只增不减）：ToolCardPresentationTests 7（卡级状态三分支/无意义判定/状态语六例/组头四例/累积器中文兜底/旧卡解码兼容/arguments 往返）、RichContentTests +2（connection/device 分类与标题、复合命令摘要含实拍样本）、DeviceSourcesTests +1（会话离线三断言）；另 combo 夹具 1 条旧断言按 D3-5 迁移（计数不变）。
- CI：首轮 42822808738 红（仅上述夹具断言 1 条，属口径迁移漏网），迁移提交后 **42824509891 绿**（head f04d08e），Executed 751 tests, 0 failures。
- IPA：~/workspace/your_files/oneday-v0.36.10/oneday-unsigned.ipa，6,635,541 字节，md5 77f5e19ce793d839a5a2cc973f16e770，解包 Info.plist = 0.36.10/77/site.didichou.oneday；二进制内验到本包新文案长字面量（channelNote 两句在 OneDayApp 内命中；≤15 字节短串走 Swift 小字符串立即数编码、不以连续字节存，此为 Release 常态）。
- 发送链与 0.31.0 任务制语义零改动：本包只动呈现层判定与文案，followRunEvents 的落盘/对账/重试逻辑未改（仅在既有挂点记事件序与净化直播结果）。

### 75.3 诚实边界

- 分段胶囊的本体落值（轨/药丸/字/色）已按量测对齐，但 List 平台内边距（首节上距、分组头内距）不可完全细控：上方总留白由 ≈56pt 收到 16 附近是设计口径，最终观感（与 Muse 并排的贴合度）归用户真机终审。
- 工具卡组默认收起的取舍（信息密度 vs 一眼全貌）、详情展开手感、直播事件序交错的实际观感（思考块在工具组之间落位是否顺眼），均无本地可验手段，归真机终审。
- D3-4 适配偏差（直播期无真参数）为通道事实：靠参数分形的标题（memory/skill 动作形）直播期用泛称、落定纠正；若日后 events 通道补参数分片，直播期可与落定完全同口径，届时删此边界。
- 「可调用」在会话在线时的成立，还以服务端 device MCP 注册为前提（同晚并行线已办并实调验活）；App 侧不验服务端、只认会话在线——若服务端注册日后被摘除，目录行仍会写「可调用」，此为本口径的已知边界（验服务端状态须另立健康检查，不在本包）。

## §76 0.36.11/78 语音闪退热修三轮——tap 回调隔离（.ips 实锤定案，2026-11-10）

编号注：本节任务简报原写 §75，§75 已由 0.36.10 五判词包占用（其文档提交 d95bca0 自记 §75），为保台账不重号本轮落 §76。

起因：0.36.9 真机仍闪退（21:17 复现）。按铁律停猜，用户提供 OneDay 自身 .ips（voice-crash-ips-20261110-2117.ips，存 oneday-design-review/）——本案自此有实锤，不再是形态类推。

### 76.1 .ips 证据链（亲读 faulting thread 7）

- 异常：EXC_BREAKPOINT/SIGTRAP，termination code 5（Trace/BPT trap），App 0.36.9/76，进程启动后约 7 秒崩（点语音即崩的时序吻合）。
- faulting thread 7，queue＝`RealtimeMessenger.mServiceQueue`（AVFAudio 实时音频线程）。
- 栈（自顶）：`_dispatch_assert_queue_fail` ← `dispatch_assert_queue` ← `libswift_Concurrency._swift_task_checkIsolatedSwift` ← `swift_task_isCurrentExecutorWithFlagsImpl` ← **`closure #2 in DictationController.startEngine(useFallback:generation:)`** ← thunk for @escaping (AVAudioPCMBuffer, AVAudioTime) → () ← `AVAudioNodeTap::TapMessage::RealtimeMessenger_Perform()`。
- 定案：installTap 的回调闭包生在 @MainActor 的 startEngine 里、继承主隔离；tap 在实时音频线程投递第一帧 buffer，运行时在闭包入口做当前执行器断言、对不上当场掐断。**崩点在回调入口、第一帧数据未进 consume**——与权限状态、tap 格式、转换器全无关。

### 76.2 三轮落空原因（对账）

- 0.36.8 修的是 tap 的**上游与下游**：删 SFSpeech 授权门、格式有效性门、installTap 传 nil 格式＋惰性转换器、会话模式、假录音闩——崩点在闭包入口本身，这些关口全数保留且仍成立，但无一覆盖入口隔离。
- 0.36.9 按礼记终修处理的是**授权回调**那一处同族病灶（预备页无条件重走 requestRecordPermission）；礼记崩在授权回调、OneDay 本次崩在 tap 回调，同属「回调隔离对不上」一类、病灶不在同一回调。0.36.9 的同步门修法本身正确且保留（已授权不再重走回调是独立成立的铁律项），只是不是本次崩点的药。
- 教训已固化 AGENTS.md 两款铁律（2026-11-10）：授权先同步读状态、已决定不重走异步回调；系统回调闭包不得继承 actor 隔离。本轮即按第二款施工。

### 76.3 修法落点

1. **installTap 迁进盒**（DictationController.swift）：新设 `DictationAudioPipe.installTap(on:)`——闭包生在 nonisolated 终类 DictationAudioPipe 的方法内，只捕获盒本人、只调 nonisolated 的 consume（转码＋yield 分析器输入＋电平喂入）；startEngine 改调 `pipe.installTap(on: inputNode)`，相位/面包屑（markStage("tapInstalled")）在安装返回后由控制器在主隔离内打点，永不经 tap 线程。改造前：闭包字面量在 @MainActor 方法体内、捕获局部 pipe、入口带隔离 thunk（.ips 的 closure #2）；改造后：闭包出生地为无隔离上下文、无隔离 thunk 可触发。
2. **喂入核下沉 Core**：新增 `DictationAudioFeedBox`（OneDayCore/Dictation.swift）——nonisolated 终类＋OSAllocatedUnfairLock 护 (rms, buffers)，pipe 的 consume 改喂此盒、latestRMS 转读此盒（删 pipe 自有 rmsBox）。单测 DictationTapFeedBoxTests 4 条：并发队列 256 次喂入计数不差、detached 任务喂入 RMS 精确、空样本不崩、reset 双清——以真机闪退的同形调用面（任意队列调用）在测试层钉死「盒无隔离依赖」。
3. **KVO 进度观察同形态收口**：新设 `DictationProgressObserver`（nonisolated 终类）安装 AssetInventory 下载进度的 KVO 观察——Progress 在自有队列投递变更，旧闭包生在 @MainActor 的 startEngine 内、捕获 [weak self]，与 tap 同形态（资产未装、需下载时才走到，属潜伏同雷）；盒内闭包只碰 @Sendable 回调，跳回主隔离由回调内部 Task { @MainActor in … } 显式完成。控制器 progressObservation 属性退役、改 progressObserver.invalidate() 三处。
4. **requestMicrophonePermission 标 nonisolated**：静态方法原在 @MainActor 类内（默认带主隔离），其内 continuation 体与 requestRecordPermission 回调两个闭包的出生地一并钉死在无隔离上下文；行为不变，调用点仍只许 MicPermissionGate 判 .requestOnce 时经 prepConfirmStart 进来——grep 验 requestRecordPermission 全仓仍唯一实现一处（DictationController.swift，函数体内）。
5. **保留不动**：0.36.8 全部修法（格式门、nil 格式＋惰性转换器、.playAndRecord/.spokenAudio、面包屑、FaultPolicy）与 0.36.9 同步门（MicPermissionGate）；发送链零改动。

### 76.4 全仓同类形态审计（逐项结论）

判据：系统在自家队列（非主队列）投递的回调，其闭包/方法若带 actor 隔离、入口断言即同病；主线程投递或本身 nonisolated 者无此风险。

| # | 形态 | 落点 | 结论 |
|---|---|---|---|
| 1 | installTap 回调 | DictationController（旧 L452） | **真凶，本轮已修**（76.3-1） |
| 2 | KVO observe（Progress.fractionCompleted） | DictationController startEngine | 同形态潜伏（Progress 自有队列投递），**本轮已修**（76.3-3） |
| 3 | requestRecordPermission 回调 | DictationController 静态方法 | 出生地原带主隔离，**本轮预防性收口** nonisolated（76.3-4）；调用受 MicPermissionGate 单点门控不变 |
| 4 | AVAudioConverter convert 输入块 | DictationAudioPipe.consume 内 | 闭包生在 nonisolated 类方法内、只捕获盒与锁，convert 在调用线程同步行使——无隔离，无风险，不动 |
| 5 | NotificationCenter 中断观察块 | DictationController.registerInterruptionObservers | 注册时明示 queue: .main，块在主队列行使（与主隔离断言同队列）；块内状态访问一律经 Task { @MainActor in … } 显式跳回——无风险，不动 |
| 6 | 结果流消费（transcriber.results AsyncSequence） | DictationController resultsTask | 以 await self?. 跨隔离显式跳回，无 C 回调入口——无风险，不动 |
| 7 | UIKit/QuickLook/EventKit-UI delegate（5 个 Coordinator：UIImagePicker、UITextView、EKEventEdit、UIScrollView、QLPreview 数据源） | ChatView/ComposerTextView/DeviceViews/RichContentViews | Coordinator 均为普通 NSObject 类（方法 nonisolated），且 UIKit 主线程投递——双重无风险，不动 |
| 8 | CNContactStore.enumerateContacts 闭包 | DeviceExecutors（普通 struct/enum，非 actor 类型） | 闭包生在无隔离上下文、由 CNContactStore 在调用线程同步行使——无风险，不动 |
| 9 | EK/CN 授权与查询 async API | DeviceExecutors/DeviceStore | 全走 async/await SDK 面，无裸回调闭包——无风险，不动 |
| 10 | URLSession | 七个桥客户端 | 全部 URLSession(configuration:) 无 delegate、只用 async/await——无 delegate 回调面，不动 |
| 11 | requestAuthorization（相册） | ImageViewerView（0.36.9 已注） | 与听写无关；保存到相册为一次性用户动作面，本轮不动，沿 §74 注 |

### 76.5 验收

- 提交：fa5a977（整包）＋55504d7（补 import os 修复提交）；文档回填为其后补记提交。
- CI：首轮 42827566841 **failure**——构建错 `cannot find 'OSAllocatedUnfairLock' in scope`（Core 的 Dictation.swift 未 import os，App 侧文件本有此 import 故未暴露），55504d7 补一行 import 后重跑 42827880912 **success**。
- 单测：**755 全过、0 failures**（基线 751＋新增 4，只增不减）：DictationTapFeedBoxTests 四条（testIngestFromConcurrentQueues／testIngestFromDetachedTask／testIngestEmptySamples／testResetClearsState）逐条 passed。
- IPA：6,638,465 字节、md5 77dc4c965e35ce07a78f6c3917e63f73、独立解包验 Info.plist＝0.36.11/78、双 UsageDescription 键仍在包内，落 ~/workspace/your_files/oneday-v0.36.11/oneday-unsigned.ipa。
- 版本五处同改＋grep 验：Project.swift 四处（0.36.11/78）＋SettingsView 页脚「OneDay v0.36.11」；grep 复验 requestRecordPermission 全仓唯一实现一处、progressObservation/rmsBox 旧符号零残留。

### 76.6 诚实边界

- 本轮根因有 .ips 实锤、修法与栈逐帧对应；但「点麦克风不再闪退」的最终判定仍归用户真机首试——CI 绿与单测只证构建、逻辑与盒的调用面，不冒充真机验收。
- 若真机仍崩：lastStage 面包屑（0.36.8 起）＋新 .ips 照旧是唯一定位路径，按铁律先拿日志再动代码。
- 审计 #3 的 SDK 标注（requestRecordPermission 回调在系统侧的投递队列）本地不可验，nonisolated 化为预防性收口、行为零变化；#2 的 KVO 投递队列同理按形态从严处理。

## §77 0.36.12/79 热修包——回车尾行漏数＋听写补仪表＋FaultPolicy 残口（2026-11-10）

### 77.1 回车不换行（用户 22:05 真机录屏定案）

- 证据：录屏帧序——输入「测试」连点回车，胶囊单行纹丝不动；键入 q 后突跳两行「测试／q」。q 落在第二行证明 \n 一直在文本里、没被任何一层吞（诊断 composer-newline-diagnosis-20261110 逐项验：Coordinator 无 shouldChangeTextIn 拦截、回写无修剪）。
- 病灶：`ComposerTextMetrics.lineCount` 以 `enumerateLineFragments(forGlyphRange:)` 数行；文本以 \n 结尾时光标所在的空行是 TextKit 的 extraLineFragment（字形区间长度 0、不在枚举内），「测试\n」被数成 1 行、胶囊高与「测试」逐值相同（46）；键入新字第二行有了字形才被数成 2 行跳高。`ComposerTextView.refreshScroll` 同源受害（同 textHeight 判内滚，漏数时光标行既不长高也不可滚，与真机「光标不动/看不见」吻合）；全仓 grep extraLineFragment 旧版零命中。
- 修法（诊断荐 A）：lineCount 枚举结果上文本以 \n 结尾时 +1，光标行恒计入（「a\n\n」枚举 2 补后 3、「\n」枚举 1 补后 2）。只动 Core 一函数；ComposerLayout 常数、视图层、布局层零改动，refreshScroll 经同源 textHeight 自动愈合。不采哨兵法（改动被量测文本本身、与同源同串口径相悖）。

### 77.2 语音不实时出字（用户 22:04 反馈＋22:06 录屏修正）

- 帧证据：预备页波形 0:00→0:04 实时跳动（tap→FeedBox 喂入链在跑）、说话全程零文字、约 0:04「你好你好你好」整段一次性落定。喂入与模型据此双双排除（转码全灭则 final 不可能出现；final 能产出则模型资产必然在机）；消费/合并/发布/渲染四环经诊断逐环验明全通且不分 isFinal（双层模型＋尾段染灰本就在位）——断点在模块交付层：volatile 结果没有到达消费环。
- 两子假设仓内不可分：1a 主引擎不可用、startPipeline 静默回退 DictationTranscriber 在跑（usedFallbackEngine 旧实现只赋值、全仓无消费点，静默不可见）；1b 主引擎在跑（volatile 开关 reportingOptions [.volatileResults] 已开）但模块在本机/本语言下把 volatile 攒到落定才交付。根源是零仪表：选引擎不打点、applyResult 只在首条结果打 firstResult 不分型。
- 本轮按诊断最小修法第 1＋4 步施工，**呈现层零重写**：①选引擎打点——`markDiag()` 在 moduleBuilt 时把引擎种类（main/fallback）＋规范化后 locale（supportedLocale 实际返回值）落盘 `dictation.lastDiag` 并写日志；②结果环分型——applyResult 改为首条 volatile 打 firstVolatile、首条 final 打 firstFinal（旧 firstResult 退役），两类逐条计数 volatileResultCount/finalResultCount，计数随首条定稿与收尾（finishRecording）同步进诊断串落盘；③usedFallbackEngine 随诊断串上屏——预备页页脚与失败行共用的 DictationStageDiagnosticLine 扩为「上次语音停在：{stage}｜engine={main|fallback}({locale}) vol={n} fin={n}」。打点克制（选引擎/首草稿/首定稿/收尾各一次），不在每条结果上写盘。
- 1a 静态核查结论（不猜改）：选引擎代码（isAvailable 守卫→supportedLocale(equivalentTo:) 规范化→粤语 zh_HK 兜底）与苹果口径逐项一致、locale 标识写法无误，仓内无法静态坐实主引擎为何可能不可用——不在本包猜改引擎选择逻辑。下一轮真机一录定案：诊断串 engine=fallback 即 1a 坐实（转查 isAvailable/supportedLocale 失败点或回退引擎产出形态）；engine=main 且 vol=0、fin>0 即 1b 坐实（模块交付节奏，缓解方案需用户拍板）；vol>0 而界面仍无实时字则回头查呈现层（与本轮诊断结论相悖、需新证据）。
- 文档对账（诊断断点 3）：实时转写自 0.36.6 首版起从未在真机验到过（§71.5 明列待真机；0.36.6–0.36.10 历版点麦克风即闪退）——22:06 录屏是该功能史上第一份真机结果证据，「实时不出字」大概率自首版即在、被闪退连环案遮蔽至今。

### 77.3 FaultPolicy .idle 残口（诊断断点 2 顺手补）

- 残口：资产已装的快路径上 startEngine 全程停在 .idle 直到末尾进 .recording；此窗内 analyzer.start/结果流抛错经 DictationFaultPolicy 映射 .ignore 被静默吞、随后照常进录音态——0.36.8 要根除的「假录音」模式在 .idle 窗的残口。本案被录屏排除为主因（final 出现证明分析器在跑），属旁证缺陷顺手收。
- 修法一行：Core DictationFaultPolicy.action 把 .idle 自 .ignore 组移入 .abortStartup 组（与 .requestingPermission/.preparing 同组）。无误伤面：能产生故障信号的只有本代次启动管道（结果/分析任务只在启动尝试内存在），收尾后代次递增、迟到信号先被代次守卫作废。

### 77.4 验收

- 提交：a083c8f（整包）；本节为其后文档回填提交。
- CI：42831710990 **success**（首轮即绿）。
- 单测：**760 全过、0 failures**（基线 755＋新增 5，只增不减）：ComposerTextMetricsTests 新增 4 条（testTrailingNewlineCountsCursorLine／testMultipleTrailingNewlines／testMiddleAndTrailingNewline／testTrailingNewlineAtCapBoundary）＋testTypingSequenceModeIsMonotonicAndPure 第 4 步「测试\n」收紧为等值断言（98.34 且与「测试\nh」逐值相等）；DictationTests 新增 testFaultPolicyIdleWindowAbortsStartup 并同步矩阵 .idle 断言。封顶边界钉法：5 行正文＋尾 \n＝6 行、textHeight 恰达 maxTextHeight 115.02、胶囊 175.02；6 行正文＋尾 \n＝7 行、未封顶实测 134.19 过封顶使 shouldScroll 为真、胶囊仍封顶 175.02。
- IPA：6,639,766 字节、md5 83333941cf09895412cbe57edb6d9bab、独立解包验 Info.plist＝0.36.12/79、双 UsageDescription 键仍在包内，落 ~/workspace/your_files/oneday-v0.36.12/oneday-unsigned.ipa。
- 版本五处同改＋grep 验：Project.swift 四处（0.36.12/79）＋SettingsView 页脚「OneDay v0.36.12」；0.36.11 残留只剩历史注释。

### 77.5 诚实边界

- 回车件：量测口径有单测逐值钉死，但真机最终判定＝用户连点回车时胶囊逐次长高、光标行可见可达。
- 听写件：本轮只补仪表＋残口，**不承诺实时出字已修**——定案依赖用户下次录屏/截图里的诊断行（预备页页脚或失败行）：读 engine 与 vol/fin 三数即可分清 1a/1b，修法再按 §77.2 的分流走，不许在本包之外凭猜动引擎代码。
- FaultPolicy .idle 并入 abortStartup 的前提（结果/分析任务只存在于启动尝试内、收尾必递增代次）已逐点对代码核过；若将来有新常驻任务形态引入，须重审此判定。

### 77.6 外部核查修订（2026-11-10 22:21，核查档 community-solutions-check-20261110.md 第 3 题）

- **§77.2 的 1b 定性作废**：「主引擎把 volatile 攒到落定才交付＝模块在本机/本语言下的交付节奏」这一口径已被外部证据推翻，不作交账结论。外部实证（WWDC25 277 逐字稿＋苹果官方示例＋第三方实测）表明：主引擎开 [.volatileResults] 后本应实时交付草稿；回退引擎的 .progressiveLongDictation 渐进预设本应给初步结果。因此下轮真机若出现 engine=main 且 vol=0，**不许再归因于「模块天生节奏」**——成因在四格实查（下条）齐备前保持未定。
- **四格增补（随 0.36.13 补，本包已出仓）**：选引擎打点在引擎种类＋规范化 locale 之外加记——①实际生效的预设名（回退引擎为所构造的 DictationTranscriber 预设；主引擎记其 reportingOptions 构成）；②supportedLocales 对当前 locale 的实查布尔；③installedLocales 实查布尔；④SpeechTranscriber.isAvailable 原值（在守卫消费前取值）。四格齐备后，engine=main/vol=0 的成因才许下结论。
- §77.2 其余部分（帧证据、四环全通、仪表三点施工、FaultPolicy 与回车件）不受本修订影响。

## §78 0.36.13/80 跟进包——模型菜单 Picker 化＋底部贴底收口与事实路堵洞＋听写仪表四格与录音条实时诊断行（2026-11-10）

### 78.1 模型菜单双勾（用户 22:11 真机截图，诊断 model-menu-checkmark-diagnosis-20261110）

- 证据：对勾判定单源（AppState.chatModel）、点选真生效，坏的是渲染通道——0.36.4 的等宽对号槽＋`.opacity()` 藏勾，Menu 条目转 UIKit 时只提取符号图本体、透明度被剥，每行对勾原样同显。外部核查（community-solutions-check 第 1 题）与拟定修法一致：苹果反馈 FB16679936 明示菜单带勾正道只有 Toggle/Picker；社区手工画勾一律条件渲染、opacity 藏勾无先例。
- 修法：`modelMenu` 改系统 Picker 承载（`Menu { Picker }`，同外观页虚拟形象大小的既有形态），勾由系统绘制、单选互斥由 UIKit 保证；行只剩 `Text(displayName).tag(id)`。Picker 的 selection 经桥绑定：读先过 Core 纯函数 `ModelMenuSelection.checkedID(itemIDs:selected:)`（清单内才返回选中值、未知 id/空串/nil 恒 nil＝零勾），写直达唯一写入口 selectChatModel。不动 AppState/ChatModels/发送链。
- 退役：ModelMenuSpec 对号槽常数（18/6）随 opacity 形态一并删除（grep 确认消费者只有本菜单与其钉测）。
- 单测：新增 ModelMenuSelectionTests 三组（双模型各选其一恒一勾、未知 id 零勾、flash→pro→flash 切换序列勾随动）；删 ModelMenuSpecTests 一条槽常数钉测（随形态退役，净账见 §78.5）。**诚实边界：本 bug 在 SwiftUI→UIKit 菜单转换层，单测只能钉判定函数、钉不住渲染通道——验收须真机展开菜单看一勾且随切换移动。**

### 78.2 底部贴底（用户 22:11 真机双问，诊断 chat-bottom-geometry-diagnosis-20261110）

- 证据：两问同源于 LazyVStack 估算高度——程式化贴底按估算落点单发无收尾，静止位离真底 ≈57pt 纯空白（截图量测气泡底↔输入舱顶 ≈109pt、写死留白仅 ≈17pt）；距底判定同吃估算数，迟滞退出阈值 176 一旦被越过即锁死「离底」，而事实路（最后一条可见）有三洞（末条 id≠渲染目标 id／createdAt 单键排序／只在可见集变化时重算）未能纠偏；流式跟随共用同一门控、一并停摆。外部核查（第 2 题）与修法一致：估算机制系 WWDC 官方明说，复贴与社区通行补救（double-scroll）同形且有量实原理背书（vellum PR #30693）；换 List/VStack 结构路不采、记为后手。
- 修法 (a) 落定复贴（收口一处）：`scrollToBottom` 拆本体 `performScrollToBottom`＋复核——一切贴底出口（回底钮/键盘锚底/条目与流式跟随/发送贴底/线程恢复/首屏定版）首贴后 120ms（与发送路径既有复贴同延迟）复核实测距底（`lastBottomDistance` 由 onScrollGeometryChange 同路另存），仍 >24pt（Core `BottomSettle.shouldRestick`，阈值 24：正常落定误差 ≈17pt 不触发、估算误差 ≈57pt 必触发）才无动画再贴一次；只贴一次、复贴走本体不成环；线程被切走则作废。
- 修法 (b) 事实路堵洞：末条判定改查最后一个渲染项的滚动目标 id——Core 纯函数 `LastScrollTarget.lastScrollTargetID`（与 entryRenderItems 成组规则同构：末条非工具→本身、尾部工具连段 ≥2→连段首条、连段 1→本身、空→nil）；可见集存档 `@State lastVisibleEntryIDs`，事实信号收口 `refreshLastEntryVisible()` 单点算，可见集变化与条目数变化两路共用（堵「只在可见集变化时重算」）；切线程先清零可见集与信号、不拿旧集判新线程。洞 2（同刻排序）随渲染项序（即视觉序）自动缓解。
- 修法 (c) 初始落位兜底（核查增补）：消息列表 ScrollView 加挂 `.defaultScrollAnchor(.bottom)`。**落点注明**：声明式锚只定内容首次布局的落点——命令式 scrollTo 在新内容量实前触发会落错位（vellum PR #21760 实证），锚兜的就是这一帧；它与 scrollTo 不冲突（锚只管初始位、其后全归命令式与 .task 定版链），键盘升起/流式跟随的落点误差不归它、仍以 (a) 为主治。
- 不动：BottomProximity 迟滞阈值（96/176）与 0.36.5「事实信号不改跟随门控」边界不破（跟随恢复靠 (a)、不靠改门控）；回底钮浮层化＋离底未读计数仍留 0.41.x、不混入。
- 单测：BottomFollowTests 增 6 条——迟滞锁死序列（200→false、140 仍 false、95 才 true，钉死现行语义防 (a) 落地后误改阈值）、lastScrollTargetID 四形态（末条文本/末条单工具/末条在 ≥2 工具组内含连段被文本截断边界/空数组）、BottomSettle 阈值边界（17/24 不触发、25/57 触发、负距不触发）。Policy 两路四组合旧测已全覆盖、不重复。

### 78.3 听写仪表四格（§77.6 增补落点）

- 在 0.36.12 的 markDiag 选引擎打点上扩记四格，与 engine/locale/vol/fin 同串上诊断行：①实际生效预设名——回退引擎记所构造的 DictationTranscriber 预设 `progressiveLongDictation`、主引擎记 reportingOptions 构成 `rep:volatileResults`（与构造逐字同值）；②`SpeechTranscriber.supportedLocales` 对当前 locale 的实查布尔（主引擎对规范化后 locale、回退对请求 locale——回退为何发生、主引擎侧支持状态正是要留的账）；③`installedLocales` 同口径实查布尔（取选引擎时刻、资产下载前的快照）；④`SpeechTranscriber.isAvailable` 原值——在 startEngine 入口先于现有 guard 取值落账、guard 改用该同一值消费，诊断串读到的就是守卫真正看到的。四格按尝试归零重记（与计数同口径），选引擎的 markDiag 首写即四格齐。
- **1b 作废口径的承接**：§77.6 已判 1b「模块天生节奏」说作废，本节不复活——四格齐备前 engine=main 且 vol=0 的成因保持未定；下轮真机一段录音即可在「引擎/预设/资产/locale」四格里定位，不再猜改引擎代码。

### 78.4 呈现修正：诊断串挂上录音条（追加件，用户 22:26 真机录屏实证）

- 问题：诊断行旧只挂失败行与预备页——录音成功时不在场，用户录完也看不见诊断串，四格仪表无从被截图读回。
- 修法：DictationBar 文本行（「正在聆听…」）下方新增 `DictationLiveDiagnosticLine`：与事后行读同一对快照（lastStage＋lastDiag），录音条随波形逐帧重算、每次重算读最新落盘值，打点一更新（选引擎/首草稿/首定稿）行内即跟变——录音进行时即可截图。样式守宪法：caption2 级、弱化色（inkSecondary）、居中、不抢主行；VoiceOver 隐藏（诊断脚手架非用户文案，与事后行明标「诊断信息」同口径）。
- **脚手架注记：本行与两处事后诊断行同属定案脚手架，「实时不出字」定案并修复后可整组移除，移除时连同 lastDiag/lastStage 落盘一并评估。**
- 单测：呈现层无可测点（快照读 UserDefaults＋视图拼接，与 0.36.12 事后行同形态、当时亦无单测）——靠真机验：录音中诊断行在场且四格齐、vol 随说话跳动。

### 78.5 验收

- 提交：0fc906e（整包，含追加呈现修正）。
- CI：42834591793 **success**（首轮即绿）。
- 单测：**768 全过、0 failures**（基线 760，净增 8：＋ModelMenuSelection 3、＋BottomFollow 6、−ModelMenuSpec 退役 1，只增不减口径按总账记）。
- IPA：6,654,247 字节、md5 76f19598aa09efa379ee1776b2c096fc、独立解包验 Info.plist＝0.36.13/80、双 UsageDescription 键仍在包内，落 ~/workspace/your_files/oneday-v0.36.13/oneday-unsigned.ipa。
- 版本五处同改＋grep 验：Project.swift 四处（0.36.13/80）＋SettingsView 页脚「OneDay v0.36.13」；0.36.12 残留只剩历史注释。

### 78.6 诚实边界（真机复验点）

- 菜单件：展开模型菜单应只有一勾、且随切换移动（渲染层问题、单测钉不住，见 §78.1）。
- 底部件：长线程（≥100 条、含高气泡）键盘升起后静止，量气泡底↔输入舱顶距离，验收线 ≤ 钮行高＋16pt；同线程收键盘再看一次；回底钮在视觉已到底时应消失、对方回复时跟随应恢复。
- 听写件：录音时录音条上诊断行在场，四格齐（preset/sup/inst/avail）＋vol/fin 可读；据此读数按 §78.3 口径定下一轮修法，本包不承诺实时出字已修。

## §79 0.36.14/81 同步制 App 包——五数据集同步引擎＋三层开关＋副本呈现与删除（2026-11-10）

### 79.1 规格与拍板对齐

- 规格＝oneday-design-review/device-sync-design-20261110.md：用户 21:52 拍板整个本地数据面照 Muse 改同步制（授权→同步最小化副本到用户自有伴生服务→智能体查库）；21:58 两处拍板照单执行——①权限撤销后完全停供（工具只回状态错误、副本不删、重开权限恢复）②照片整本相册全量元数据索引（不存原图、不存定位坐标），「授权了就给全量」为通则。device-connectors 第 7 条「现读现回、服务器不囤副本」对记录型数据作废（实时型/动作型照旧），三处旧口径文案（日历/提醒/通讯录详情 descriptor 与三条权限申请文案）已随本包改实话。
- 伴生侧先行部署（1.0.2，SYNC-BUILD-REPORT）：接收接口 batch/complete/manifest/state/delete/status 与查库工具 21 件在线；本包 App 侧接口形状逐字对源码核过（complete 的混排键、manifest/state 的 snake_case、409 sync_count_mismatch 的对账语义、complete 前须至少一个 batch 登记批次）。

### 79.2 五数据集同步策略落点

- 通讯录（ContactsEngine.syncSnapshot＋DeviceSyncController.assemble）：一次整本枚举同时产出标识＋字段指纹清单（Core ContactFingerprint，SHA256、标签入纹）与全量最小字段记录；先 manifest 比对——副本为空或桥回 reimport_required（授权范围变化）走整本 full，否则只传 changed 子集＋removedIds 删除（incremental）。字段最小化红线：只取姓名/电话/邮箱/公司/分组，备注/地址/生日/头像的键从不出现在记录 JSON 里（单测钉死）。
- 日历（EventKitEngine.syncOccurrences）：Core SyncCalendarWindow 划窗（今天 −30 天零点 → +90 天当日次日零点），predicate 按场次展开、occurrenceId＝事件标识＋场次开始时刻，整窗 full 换入、coverage 随 complete 上报。
- 提醒（EventKitEngine.reminderSyncSnapshot）：未完成提醒全量 full 换入；已完成只进聚合——Core SyncReminderAggregates.compute 与桥同口径（todayCompleted＝完成时刻 ≥今日零点；overdue＝未完成且 due <今日零点），完成条目本身不上行。
- 步数（MotionEngine.recentDays）：Core SyncMotionPlan 近 7 天逐日区间（连续不重叠、今天收尾在次日零点、查询时截到当前时刻），CMPedometer completion 回调只在引擎内拆成 Sendable 值过线；mode=merge 按日新盖旧，系统只留 7 天、长历史靠历次同步在伴生攒。单日查询失败跳过不拖垮整批。
- 照片（PhotosEngine.collectRecords）：整本资产全量索引——拍摄时间/类型/子型（截图、实况、全景、延时、高帧率=慢动作）/宽高/时长/收藏/相册名（用户相册成员反查、首命中）/hasLocation 只记有无；原图、缩略图、坐标一律不碰（记录 JSON 键单测钉死）。创建时间缺失的极少数资产以零点占位保全量（通则优先于时间精度）。

### 79.3 触发、三层开关与供给边界

- 触发：首次开启同步即首同步（说明屏确认后直达）、前台节流增量（Core DeviceSyncPlanner.foregroundDecision：记录型 15 分钟、步数 1 小时；桥报 pendingWrite 时无视节流优先）、详情页「立即同步」手动钮。同步只在 App 前台进行，文案明示不在后台跑。
- 三层开关各就其位：系统权限（iOS 管）／同步开关（默认关、逐数据集、DevicePreferences 落盘）／允许智能体调用（既有）。同步资格只看前两层（规格 §6.1 分层）；查库供给的硬停供只由权限撤销触发——App 回前台第一时间经 sync/state 上报权限与范围（只认变化才打桥），桥据 revoked 标记让工具只回状态错误。
- 授权铁律落点：同步每轮先同步读 currentStates；仅 .notDetermined 才走那一次请求（照片 requestAuthorization／计步以一次当日查询触发询问／余件走各自引擎请求口），已决定状态绝不重走异步回调（DeviceSyncExecutors 内判）。回调隔离铁律：本包不挂任何系统回调闭包（CMPedometer 的 completion 只在引擎内部拆值）。

### 79.4 呈现与删除

- 详情页「数据同步」区（五件同构）：开关（首次先过说明屏：同步什么/不同步什么/存哪/怎么删，四段人话）、副本条数、「数据新到」新鲜度行（桥 freshness 整句优先、本地 Core freshnessLine 同措辞兜底）、同步范围（全部/部分）、撤销停供与过期两条明示行、进度行（分批已送/应到）、失败人话（409 对账失败单列）、删除副本入口（确认文案照 Muse 语义：删副本不动手机数据与权限、开关开着会重建）。关开关时弹问副本去留，删除为推荐项不预选。
- 目录行与总览行：DeviceRowStatus.line 尾拼同步段（Core DeviceSyncPresentation.segment：已同步 N 条/人/项/天 · 新到时刻；照片/步数无现调通道、不拼调用态）；总览页加「数据同步」区五件状态行＋删除全部副本。
- 状态头 channelNote 改口：开了同步的件不再说「不存服务器」，改明示查库主路＋新鲜度出处；照片/步数新增详情页（本地计数/近 7 日步数＋同步区），应用图标按宪法 §4 例外复刻官方构图（照片八瓣花、健身三环）。

### 79.5 交付数字与诚实边界

- 提交：3f67f73（整包）＋d383b73（CI 首轮四处接口名误写修正：PHAssetMediaSubtype 慢动作用 videoHighFrameRate、DeviceBridgeError 无 badEndpoint 改 unauthorized/unknownSession 映射、状态字段名 freshness 且桥句原样呈现）。CI 42839059879 success（首轮 42838445614 failure 已修）。
- 单测：768 → 785（+17，DeviceSyncTests 17 个方法全过：名册/节流、指纹稳定与敏感性、五件记录 JSON 键契约含最小化红线、日历窗口、提醒聚合、步数日区间、计划器七组合、批次切分、状态解码两形状＋坏数据、呈现文案；DeviceSourcesTests 名册 5→7 同步修订）。只增不减守住。
- IPA：6,839,910 字节，md5 0093ba6fcad2df8f960b39a77890cf94，独立解包自验 Info.plist＝0.36.14/81、NSPhotoLibraryUsageDescription 与 NSMotionUsageDescription 在位。落 ~/workspace/your_files/oneday-v0.36.14/。
- 诚实边界（单测钉不住的）：①同步全链（枚举→比对→分批→换入→查库）只能真机＋真伴生验：首次开启通讯录同步后，在 OneDay 问「通讯录一共多少人、数据是什么时候的」，应答出真数＋新鲜度；照片整本枚举在万级相册上的耗时未实测（进度行只在分批阶段更新，枚举期显示「正在读取手机上的清单…」）。②照片/步数详情页的「允许智能体调用」开关沿用同一状态头：这两件没有现调工具、供给全走查库，该开关对它们实际只影响呈现口径、停供硬闸在权限层——如实记录，不假装它能单独停供。③步数授权状态在从未查询过时恒为未决定，首次进详情页由闸门引导、点同步时以一次查询触发系统询问，属预期形态。

### 79.6 真机复验点

- 五件逐件：开权限→详情页开同步（首次过说明屏）→首同步完成，看副本条数与「数据新到」行；回目录看行尾同步段。
- 通讯录验收问句（规格 §10 第 4 步）：问 OneDay「通讯录一共多少人、数据是什么时候的」——答数与本机通讯录一致、且带同步时刻；再关系统权限回前台，问通讯录应只回「权限已关」类状态错误（完全停供）；重开权限后恢复。
- 删除面：详情页删单件副本、总览页删全部——删后问智能体应查不到；开关仍开着时重开 App 应重新同步回来。
- 照片：受限授权（勾选部分照片）下同步范围行应显「部分」；步数：详情页近 7 日与系统计步对得上。

## §80 语音起步时序账＋分析器预热（0.36.15/82，语音延迟修复包）

承 §77.6 定案：不实时出字＝**首结果交付延迟型**——engine=main、
preset=rep:volatileResults、sup/inst/avail 全绿，我方结果链（单处
for-await 直读 transcriber.results）逐段验净；录 5 秒全程 vol/fin
双零、停录整块涌入，录 20–30 秒中途出字，**首结果约在第 10 秒**
（用户亲测点选）。外部对账：beta 期约 14 秒的同类报告在正式版＋
热启动（模型已装、locale 已分配）下收敛到 0.3–0.5s；同构实测实
现（dev.to simple_memo 两篇）的做法＝分析器提前构造、ensureModel
前置、结果环先于麦克风启动、收尾 finalizeAndFinishThroughEndOfInput。
变量在预热/配置，不在结果链——本包两刀：先把延迟量成账，再把构造
成本搬出点按路径。

### 80.1 起步时序账（先量尺，后验收）

Core `DictationStartTiming`（纯逻辑，uptime 由 App 层喂
ProcessInfo.systemUptime）：四点＝点麦克风（零点）→引擎启动
（engine.start 成功）→分析器 start（analyze 任务发起）→首条结果
（vol/fin 不分型，第一条到达即记，每点只认第一次）。零点口径：
已授权直达＝点按本身；首用预备页路径＝确认/授权通过那一刻——读
说明与等授权的时间不是管道延迟，不计入。诊断串（markDiag）在
vol/fin 之后拼时序段，读法示例：

```
… vol=3 fin=0 eng+85ms ana+210ms 首结果+10234ms
```

eng/ana 两点把「我方起步开销」与「系统首结果延迟」分开：eng+ana
若为百毫秒级而首结果仍上万，账在系统侧热身；eng 本身迟到则是
我方会话/tap 路径的问题。首结果点在 applyResult 内、首条
markDiag 之前落账，诊断串当场带数（录音条实时可见）；fin 收尾
markDiag 再落一次全量。Core 单测 7 个钉住换算/首记胜/缺项省略/
段序。

### 80.2 预热：常备一束管道（不是实例复用）

施工单原文要求「分析器跨次复用」——与框架口径冲突，落法修正并
记明：DocC 明言分析器会话进入 finished 态后不再接受新输入序列
或模块，`finalizeAndFinishThroughEndOfInput` 即终结会话 ⇒
**分析器是单次使用制，同一实例无法跨段 start**。可复用的实体改
为「常备一束」流水线：永远保持一束已 prepare 的 bundle 待命
（SpeechTranscriber＋SpeechAnalyzer＋最佳格式＋规范化 locale＋
仪表四格快照），点按消费一束、录后立即再备下一束——构造/资产/
prepare 的成本全落在预热里，点按路径只剩音频会话＋引擎/tap＋
start。

- 备束内容（buildPreparedBundle，仅主引擎）：isAvailable 门→
  supportedLocale 规范化（与冷路径同口径，含 fallback）→四格
  实查（inst 为下载前快照）→资产未装走系统下载→建分析器→
  bestAvailableAudioFormat→`prepareToAnalyze(in: format)`。
  DocC 签名实查：`prepareToAnalyze(in audioFormat:
  AVAudioFormat?)`（参数是音频格式、非时间区间），原文「To
  proactively load system resources and 'preheat' the analyzer,
  call prepareToAnalyze(in:) after setting its modules. This
  may improve how quickly the modules return their first
  results.」
- 状态机：Core `DictationPreheatPolicy` 全表单点（cold/warming/
  ready/failed × beginWarm/warmSucceeded/warmFailed/consume/
  invalidate），控制器只存状态/任务/产物。迟到回执另设**轮次令
  牌**（beginWarm/弃置递增，回执先对轮次）：取消尾巴不许踩新一
  轮的状态与任务引用。Core 单测 4 个钉全表关键转移与表外保持。
- 消费（takePreparedBundle）：startEngine 主引擎尝试先行——
  ready 直接进发射；warming 则等它落地再看（已启程的预热仍快
  于从零冷启；等候中若在下资产，相位转 .preparing 示人）；语
  言不符/备失败回 nil 走原冷路径（含其全部失败呈现）。回退引
  擎不预热：无 prepare 面、且是降级路，冷启代价可接受。
- 发射拆分：startEngine 尾段（音频会话→tap→结果环→分析器
  start→引擎 start）抽为 `launchPipeline`，预热消费与冷启构造
  两路汇合一份——次序与守卫不许两路各写一份漂移。既有次序与
  dev.to 实测实现对齐：结果消费任务**先于** analyzer.start 建
  立、analyzer.start 先于 engine.start（DocC 口径，0.36.6 起
  即如此，本包未动）。
- 收尾口径核对：现行已是 finalize 口径——`finalizeWithTimeout`
  包 `analyzer.finalizeAndFinishThroughEndOfInput()`＋2 秒超时
  `cancelAndFinishNow()` 兜底＋drainResults，本包未改。
- attributeOptions：冷/热两路统一补 `[.audioTimeRange]`，与
  苹果样例及实测实现对齐（此前为 []）。
- 预设维持手动 `[.volatileResults]` 不换 `.progressive-
  Transcription`：同构反例（dev.to）用手动 volatile 即实时出
  字，预设不是已证变量；单变量原则——本包只动预热与打点，数
  字仍差再议预设。

### 80.3 生命周期红线（预热≠开录）

- 触发点：ChatView onAppear 与 scenePhase 回 .active 调
  `armPreheat()`；退 .background 调 `suspendPreheat()`（只弃产
  物、总闸保持，回前台再 arm 重备）；onDisappear 调
  `disarmPreheat()`（关闸＋弃置）。
- 切会话**不失效**：bundle 不含任何会话数据、只与识别语言绑
  定，线程切换无需重备（ChatView 实例随线程重建时 onAppear
  自然再 arm，已备束在控制器上保留）。
- 失效触发：语言变更（language didSet 弃置＋按新语言重备）、
  退后台、离页。录音/收尾/准备中不发起新一轮（不与在飞管道抢
  资源）；录后（finishRecording 末尾）与全失败收束各发起一轮。
- 指示器语义：预热只构造模块/分析器、确保资产、调 prepare——
  **不碰 AVAudioSession、不开引擎/tap、不发任何权限请求**
  （麦克风仍是点按时按 MicPermissionGate 同步状态门走，授权铁
  律不因预热破例）；系统录音指示（橙点）只随发射段激活音频会
  话出现，预热不污染。
- 预热失败静默：任何一步不成回 nil＋状态机落 failed，不向用
  户报错；点按冷路径以原有形态兜底。failed 态可再备（用户重试
  或下一次 arm 触发）。

### 80.4 未采：SpeechAnalyzer.Options 的 ModelRetention

DocC 另有 `SpeechAnalyzer.Options`（priority＋modelRetention：
.lingering/.processLifetime/.whileInUse，为「later use by a
different analyzer instance」缓存已加载资源）——与常备束是同一
问题的另一解。本包**不用**：①Priority 枚举的成员名未及核实，
不许在 CI 里猜名（猜错即红、且错在无关处）；②常备束本人持有
分析器实例，资源随实例存活，retention 的增量价值未证。记为后
手：真机数字若仍差，先核实 Options 口径再议。

### 80.5 单测与诚实边界

- 单测：新增 DictationPreheatTimingTests 11 个（时序 7＋预热状
  态机 4），785 → 796，只增不减。
- 本地无 Xcode，App 层接线（预热消费、ChatView 三钩子、时序打
  点位置）由 CI 编译＋真机验收兜底；Core 逻辑已钉测。
- **真机复验口径（本包成败在此）**：装 0.36.15 后先进聊天页停
  留数秒（等第一束备好），录同句式 5 秒短录音——应**中途出
  字**；录音条诊断行读 `首结果+Xms`：与 0.36.13 的约 10000ms
  对比。注意第一段录音可能仍吃冷路径（进页即点、束未备好时消
  费等待或回落冷启），第二段起才是常备束的账。若首结果仍在秒
  级以上：eng/ana 分段先分清我方/系统侧，再议 §80.4 后手与预
  设变量，不许无账加改。

### 80.6 CI 首轮记录（42842566410，failure→修）

首轮 CI：构建绿、单测红 1 个方法 3 处断言——`DictationStartTiming`
毫秒换算用 `Int()` 截断，`1000.085-1000.0` 在 Double 里是
84.9999… 被截成 84（85/210/10234 三值同病）。修法：换算改取最近
值（`.rounded()`），毫秒读数本就该是最近值；测试期望不变。教训
与既有口径一致：时间差换算不许裸截断。

### 80.7 交付锚点（0.36.15/82）

- 顶端提交 a3e3569（主体 eab8e2d＋§80.6 换算修）；CI
  42844360350 success（首轮 42842566410 单测红→§80.6 修后绿）。
- 单测 796（785＋11 DictationPreheatTimingTests），TEST
  SUCCEEDED，独立复核日志总计行。
- IPA：6,862,761 字节，md5 6b18756f67dbf13dca98984393c998c0，
  解包 Info.plist 自验 0.36.15/82、bundle site.didichou.oneday；
  落 ~/workspace/your_files/oneday-v0.36.15/oneday-unsigned.ipa。
- 待真机复验（§80.5 口径）：停留数秒等首束备好→5 秒短录音应
  中途出字＋诊断行「首结果+Xms」与约 10000ms 对比；第二段起看
  常备束的账（preheatConsumed 阶段标记可辨）。

## §81 同步修复：一开关＋同步日志＋页内首启（0.36.16/83，P-10/P-11 终修包）

病根见错题本 P-10/P-11 与审计 sync-start-crash-audit-20261110.md：
0.36.14 的说明屏 sheet 挂在详情页 List 的 Section 本体上（脆弱
宿主），确认事务在关闭动画同帧翻转控制器状态，父 sheet 被连带
掀掉、确认动作没执行到底，服务器 sync_batches/stage 全 0 实证；
且每件并排三个开关（系统权限假开关／同步／允许调用），把内部
三层原样端给用户。用户 2026-11-10 23:09–23:20 拍板：一开关＋
开关下同步日志。本包只换控制层与呈现层，0.36.14 同步引擎本体
（通讯录清单增量／日历整窗／提醒全量＋聚合／步数按日合并／500
分批＋complete 对账）一字不动。

### 81.1 开启时序账（确认事务解耦）

说明屏 sheet 整件退役，改详情页**页内首启区**：拨开开关且未读
说明时，开关下当页展开说明（会同步什么／不会同步什么／存哪／
怎么删，字段表沿用 §79），「开启同步／先不开」都是页内行——
没有 sheet、没有呈现链，人全程留在详情页。确认时序由 Core 的
`DeviceSyncControl.enableSequence` 钉死四步，视图与控制器按序
执行：

| 步 | 动作 | 落点 |
|----|------|------|
| 1 logEnabling | 先往同步日志落「正在开启」 | `noteEnabling`（确认闭包第一行） |
| 2 dismissIntro | 记已读说明、收起首启区 | `setSyncIntroAcked`＋`showIntroInline = false` |
| 3 flipSwitchOn | 按权限现态处置并翻开关（见 81.2） | `performEnable`→`enableFromUser` |
| 4 startSync | 起引擎（进度/完成/失败全在当页） | `syncNow(origin: .user)` |

关同步问副本去留同改页内确认（删为推荐不预选，文案口径沿用
§79）；删副本的单件确认仍走 confirmationDialog（它不翻开关、
不重构宿主区结构）。开启后当页反馈成套：进行中＝进度行（组装
阶段文案＋「已送 X / 应到 Y」由引擎 progress 直出）；完成＝
「服务器上的副本 N〈单位〉」＋「数据新到」两行（条数与时刻取
complete 回执）；失败＝原因行＋「重试」钮同行，且同步落日志，
不许静默——同步区旧的「最近错误一行橙字」自此只是当页即时行，
正式出口是日志（81.3）。

### 81.2 一开关映射表

旧三件 → 新一件（五件记录型：通讯录/日历/提醒/照片/步数）：

| 旧控件 | 去向 |
|--------|------|
| 「系统权限」开关（假控件，拨不动） | 降为状态字行：左「系统权限」、右 Core `permissionStatusText` 现态（已授权／已授权 · 部分／未授权／未授权 · 去设置／仅写入 · 去设置／受限制）；不是控件。未开好时整行可点（带 ›）：未决定→当场走那一次系统请求，被拒/受限/仅写入→跳系统设置；已授权不可点 |
| 「允许智能体调用」开关 | 整层取消。供给判据收进 Core `DeviceSyncControl.agentCanQuery`＝权限可用 ∧ 同步开；App 侧由同步开关经 `onSyncSwitchChanged` 镜像写会话「允许调用」偏好（现调路随之开/关，注册载荷的工具清单即时跟随），启动时对存量不一致做一次对齐 |
| 「同步到我的服务器」开关 | 唯一保留的开关，标题与副文案按一开关语义改写（开＝副本在服务器、智能体能整份查；关＝智能体用不了这一件） |

开启时对权限现态的处置由 Core `enableAction` 映射（授权铁律
的表形）：granted/limited→`.enable` 直接开；notDetermined→
`.requestPermission`（那一次请求在 syncNow 内发，已决定状态绝
不重走）；denied/restricted/writeOnly→`.openSettings`（开关不
翻，「正在开启」已落账、这趟中断留痕）。健康/家庭不在本包范
围：详情页无同步区，其状态头双层呈现原样未动。

### 81.3 同步日志事件表

逐数据集一本、本地 JSON 落盘（UserDefaults），上限 50 条、新
在上；条目构造/截断/增量算术在 Core（`DeviceSyncLogEntry`／
`DeviceSyncLogBook`／`DeviceSyncLogPresentation` 一处行文案）。
事件全表：

| 事件 | 触发点 | 日志行 |
|------|--------|--------|
| enabling | 开启动作第一步（首启确认或已读后拨开） | 正在开启同步 |
| enabled | 开关翻上（enableFromUser） | 同步已开启 |
| disabled | 开关翻下（disableFromUser，含去留确认两路） | 同步已关闭，智能体用不了这一件了 |
| syncStarted | 引擎过门真启动（用户与前台自动两路都记） | 开始同步 |
| syncCompleted | complete 回执落账 | 同步完成：新增 X〈单位〉，共 Y〈单位〉（新增按总量差算：桥状态总数优先、无则本地回执；变少钳 0） |
| syncFailed | 引擎失败（catch 两路）；用户当页发起的门前失败（无连接/权限不可用/开关未开/通道未就绪） | 同步没成：〈人话原因〉（与当页失败行同文） |
| permissionRevoked | 状态上报成功且上报值由 granted 翻 revoked | 系统权限被关掉了：已停供，智能体查不到这一件了 |
| permissionRestored | 状态上报成功且由 revoked 翻 granted（首次上报不算翻转，不开账） | 系统权限恢复了 |
| copyDeleted | 删副本成功（单件/全删逐件各一条） | 服务器上的副本已删除 |

前台自动同步的门前失败不落日志（节流期的静默是设计，不拿噪
音刷账本）；引擎重入（progress 在跑时二次调用）不落账。

### 81.4 不许回归清单（自查过）

完全停供（权限撤销→桥只回状态错误、副本不删、重开恢复）：上
报链 `reportStateIfChanged` 未动，仅在其成功后旁记日志；
`REVOKED_SERVES_COPY=False` 在桥侧。删除副本语义与文案：确认
文案、删后提示、总览全删入口未动，成功后加 copyDeleted 落账。
字段最小化：组装层未动。节流与手动同步：前台计划器未动；手
动「立即同步」钮留在同步区内、日志区上方。列表行状态字：调用
态由镜像保证与同步开关同值，不再出现「可调用 · 同步未开」的
双口径。

### 81.5 交付锚点（0.36.16/83）

- 顶端提交 72a249e；CI 42847158867 success（首轮即绿：构建＋
  单测＋打包全过）。
- 单测 804（796＋8：DeviceSyncTests 增一开关映射 4＋日志 4），
  TEST SUCCEEDED，日志总计行独立复核（Executed 804 tests）。
- IPA：6,891,039 字节，md5 a6127313f4daf06a3360066aec1c0325，
  解包 Info.plist 自验 0.36.16/83、bundle site.didichou.oneday；
  落 ~/workspace/your_files/oneday-v0.36.16/oneday-unsigned.ipa。
- 待真机复验：①进通讯录详情页，全页只剩一个开关（权限是状态
  行）；拨开→首启区当页展开→点「开启同步」→人留在详情页看完
  进度，日志自「正在开启」起成串至「同步完成：新增 N 人，共
  156 人」量级；②回列表行应读「已授权 · 可调用 · 已同步 156
  人 · 〈时刻〉」；③新开对话问 Hermes「通讯录一共多少人」应答
  真数＋新鲜度；④关系统权限回前台复问应只回状态错误（完全停
  供），日志多一条权限被关；⑤照片 1248 项整本索引耗时在真机
  首验（进度行可见）。

## §82 听写改判：录音条 Muse 形态＋录时零文字＋停后整段落字（0.36.17/84，P-03 终修包）

定案双因：①外部定案（论坛核查 dictation-latency-forum-check-
20261110.md）——SpeechTranscriber 流式交付本身就是秒级节奏
（volatile 滞后实测 1–2s、final 停录后 p50 3.4s／p95 12.6s），
我方 zh_CN 首结果约 10 秒处在分布坏尾；在册「热启动 0.3–0.5s」
是 en 语境热机自测值，不可作 zh 基线。0.36.15 预热只治启动段：
用户 23:39 真机截图自证分析器启动满 6 秒、vol/fin 双零，瓶颈
在交付段、预热无治。②用户产品改判（2026-11-10 23:48，原话
「和 muse 一样，录的时候 2 个按钮，然后不实时，就一个音波
就行」）：不再追实时出字，照 Muse 听写条改形态。本包只改
呈现与落稿路径：预热常备束、结果环先行次序、finalize 收尾
口径、授权同步状态门、引擎选择逻辑一字不动。

### 82.1 新录音条状态机（四态自查）

录音条只剩一行：左＝废弃（垃圾桶）／中＝音波＋计时／右＝两
钮——■停（停录→整段落稿进输入框待编辑）、↑发送（停录→落
定后直接发送）。状态机走既有 DictationPhase，三钮可用性由
Core `DictationBarPolicy` 单点定表、视图只读：

| 态（相位） | 条上呈现 | 废弃 | 停 | 发送 |
|---|---|---|---|---|
| 录音（.recording） | 音波＋计时（电平实驱） | ✓ | ✓ | ✓ |
| 整理（.finishing） | 进度转轮＋「正在整理…」 | ✕ | ✕ | ✕ |
| 落稿/发送（settle→.idle） | 条收起、回标准发送舱 | — | — | — |
| 废弃（cancel→.idle） | 条收起、草稿原样 | — | — | — |

整理态是本包新立的呈现义务：停/发送按下后终稿未落定前，
final 交付 p95 可达数秒——条转「正在整理…」、三钮全禁，不
许假死无反馈、不许落定前点出第二条路径。收尾内部仍沿
finalize 2 秒超时＋drain 2 秒兜底（现行口径未动），超时按
已攒内容落稿并如实落诊断（settleApplied 阶段与落字段照记，
读数偏短即超时痕迹）。

### 82.2 录时零文字与落稿路径

- 引擎内部照常消费结果进 DictationSession 攒稿，但
  `applyResult` 不再逐结果回写输入框（旧 onTextChange 逐
  结果推送是实时路线的呈现口，随改判撤销）；回写只发生在
  settle 一次。录音条文本视图与实时诊断行（0.36.13 脚手
  架）整组撤下。
- 落稿路径由 Core `DictationSettlePolicy` 判定（意图×有无
  识别字，单点钉测）：停＋有字→落稿；发送＋有字→落稿并
  发；**空稿两路都静默回待机**——不落空内容、不发空消息、
  不再弹「没听清」失败行（`DictationFailure.nothingHeard`
  自此无触发点，枚举与文案保留备查）。发送顺序由控制器保
  证：settle 回写输入框在前、`onSendRequest` 触发 ChatView
  `send()` 在后，视图不许自拼。
- 到限自动停（5 分钟）与「停」同路判定：有字落稿＋提示；
  空稿静默（提示文案含「已填入」，空稿不许撒谎）。
- 中断/引擎错/废弃三路口径未动（已定稿保留规则照旧）。

### 82.3 诊断搬家与 fastResults 内部实验

- 诊断行自录音条撤下，回到既有载体：预备页页脚与失败行
  的 `DictationStageDiagnosticLine`（末阶段＋诊断串）。诊
  断串原四点时序＋四格＋vol/fin 计数全保留，新增一段
  「落字+…ms」：Core `DictationSettleLatency` 量「停/发
  送按下→终稿应用」，settle 后二次 markDiag 落盘——改判
  后用户唯一还要等的一段从此有账。
- `.fastResults` 开启：论坛核查对账——`.progressive-
  Transcription` 预设与我方手动 `[.volatileResults]` 的
  唯一差量就是它（同为 reportingOptions），DocC 语义「以
  更小上下文窗降低结果延迟」。两处构造点（预热束＋冷路
  径）同改 `reportingOptions: [.volatileResults,
  .fastResults]`，预设名记 `rep:volatileResults+fastResults`。
  仅作内部杠杆、不作任何 UI 承诺；去留只认落字钟读数：
  真机同稿对照（改前 final 全程落字基线无独立读数位，以
  本版起落字段分布为准），若落字 p95 无改善则回滚此项、
  结论入错题本。

### 82.4 交付数字

- 提交 `6a5913d`（整包）；CI `42850549857` **success**（首
  轮即绿）。
- 单测 **804 → 817（+13）**：新增 DictationSettlePolicyTests
  13 个方法（落稿路径 4＋录音条三钮政策 4＋停后落字钟 5）
  CI 日志逐个 passed、总计行 817、0 failures，只增不减。
- IPA：6,895,953 字节，md5 `d878160a0db90c4f91d7faa2c032dbbf`，
  独立解包自验 Info.plist ＝ 0.36.17/84、bundle
  `site.didichou.oneday`；落 ~/workspace/your_files/
  oneday-v0.36.17/oneday-unsigned.ipa。版本五处同改已 grep 验。
- 错题本 P-03 终修栏随包更新（双因定案＋状态「已修待真
  机验」）。

### 82.5 真机复验口径

①录 5 秒点■停：录音中条上只有音波＋计时、无任何文字；
停后条转「正在整理…」，整段文字一次落进输入框可改。
②录 5 秒点↑发送：落定后直接发出一条（内容为整段识别
稿）。③录时点垃圾桶：本次段整段丢弃、原草稿原样。④空
录（不说话）点停/发送：静默回待机、无失败行、发送路不
发空消息。⑤诊断面（预备页页脚/失败行）读数：预设应为
`rep:volatileResults+fastResults`、串尾带「落字+…ms」。

## §83 详情页简化：权限即同步＋自动同步三触发＋日志改版（0.36.18/85，P-11 终修包）

起因：用户 2026-11-11 00:03–00:06 三连定版——0.36.16 虽已真
机验通同步（日历首同步 18 条、增量对账新增 0 条、日志成串），
详情页仍被判「复杂、丑」；开关语义由用户亲定（原话「点击开
关，开就弹权限弹窗，关闭就去设置页面不就行了」）；日志形态
亲定（时间打头、小字号、密排）。参照图＝用户发的 Muse 日
历权限页截图（大图标＋标题＋一行说明＋分组卡片＋大留白）。
本包只改详情页形态与同步的门：同步引擎本体（增量/整窗/聚
合口径、500 批、complete 对账）与完全停供、字段最小化、删
除副本语义，一字未动。

### 83.1 页面信息架构（对图说明）

| 参照图区块 | 本页落法 | 0.36.16 旧形态的去向 |
|---|---|---|
| 居中大图标＋名称＋一行说明 | 状态头只剩领头段；副题换 Core `DeviceSyncPresentation.detailSubtitle` 一句（副本在哪/智能体查副本/开着权限就自动同步） | 页尾口径脚注段整组退役，口径收进副题一句 |
| 唯一权限控件 | 「访问权限」Toggle 一行卡片，副文一行（开着自动同步可查/关着不可用） | 同步开关、首启区、权限状态行整组退役 |
| 安静状态 | 开关下一行 footnote 状态字：同步中/「副本 N 条 · 数据新到」/失败红字/停供说明，互斥优先如实报 | 「数据同步」区头、同步范围行、长说明 footer、立即同步钮、失败重试钮退役 |
| 删除副本 | 红色文字动作保留，确认与结果文案沿现行口径（尾句改自动同步口径） | 不变 |
| 同步记录 | 页面下部独立一区，新版式见 §83.5 | 标题式大字行退役 |

删除清单之外不动：五件的内容区（日历议程/提醒清单/通讯录
搜索/照片计数/步数近 7 天）原样保留；健康/家庭不在本包，
保持原双层状态头（权限开关＋允许调用＋通道状态）。

### 83.2 开关状态机（Core `DeviceSyncControl` 钉测）

开关显示只有一源：`switchIsOn = permission.isUsable`，回前
台经会话 refreshPermissions 回读真实状态，永不读本地偏好。

| 现态 × 拨动 | 动作 |
|---|---|
| 未决定 拨开 | 先落日志「正在开启」→ 会话 requestAccess（口内铁律守卫：同步读现态、只有未决定才发那一次请求）→ 授权到手当场 detailPageCheck 补首轮同步 |
| 被拒/受限/仅写入 拨开 | 跳系统设置本 App 页（系统不再弹窗，不重走请求回调） |
| 已授权 拨开 | 不发生（本就呈开态），映射 `.alreadyOn` 兜底 |
| 任意态 拨关 | 跳系统设置由用户亲手关；真关掉后回前台上报标 revoked → 桥停供＋日志 permissionRevoked 一条 |

0.36.16 的 syncEnabled/说明已读偏好键自此不读不管（存量留
在 UserDefaults，无副本数据、不必清理）。

### 83.3 自动同步触发表

| 触发 | 落点 | 判定 |
|---|---|---|
| ① 回前台/冷启/连接就绪 | `foregroundCheck` → `reconcile` | 计划器：权限门＋数据集节流（记录型 15 分钟/步数 1 小时，未动）＋pendingWrite 或变更记号绕节流 |
| ② 系统变更通知 | `DeviceChangeWatcher`（新文件）落记 `pendingChanges` → 2.5 秒防抖 → `reconcile(changePending: true)` | EKEventStoreChanged（日历＋提醒同记）、CNContactStoreDidChange、PHPhotoLibraryChangeObserver；步数无变更通知、不入列 |
| ③ 进详情页 | `DeviceSyncSection.task` → `detailPageCheck` | 过期才真跑同步，没过期只回状态 |

计划器签名去掉 syncEnabled 入参，`SyncForegroundDecision
.blockedSwitchOff` 退役。回调隔离账：DeviceChangeWatcher
是 nonisolated `@unchecked Sendable` 终类——EK/CN 块观察
指定 .main 队列投递，照片 `photoLibraryDidChange` 只做
DispatchQueue.main.async 转手、不碰状态；onChange 只在主
队列被调用、只在控制器 init 赋值一次，控制器侧再按本仓
惯例 `Task { @MainActor }` 落记。自家写入日历同样触发
EKEventStoreChanged——防抖＋节流兜底，多一轮空对账不产
生副本变化。

### 83.4 供给判据收敛

Core `agentCanQuery` 改权限一源；App 侧镜像层退役——会话
refreshPermissions 每次重读时把五件的 agentCallEnabled 对
齐真实权限（持久化＋变化时重注册），AppState 的
onSyncSwitchChanged 接线与启动对齐循环删除。会话
requestAccess 加铁律守卫：记录型五件现态非未决定时只重
读、绝不进引擎请求口。健康/家庭恒关不变。

### 83.5 日志改版（用户亲定形态）

一行一条：时间在前（Core `DeviceSyncLogPresentation
.timeText`＝与状态字同源的 dayLabel 短标，.caption 12pt
次级色、等宽数字）→ 失败行红点 → 事由（.footnote 脚注级
常规字重；失败行 Palette.danger、其余 ink）。发丝线分
隔、密排，一屏多条。事件分类 9 类与存储上限 50 不变；
enabled/disabled 为 0.36.16 存量条目、新流程不再产生
（开关动作改由 enabling 与 permissionRevoked/Restored
记账），回读呈现不变、存量账不丢。

### 83.6 交付数字

- 提交 `730323a`（整包）；CI `42853208198` **success**
  （首轮全绿）。
- 单测 **817 → 820（+3）**：planner/segment/开关映射三组
  断言随新语义重写；新增 testPlannerChangePendingBypasses-
  Throttle、testPermissionSwitchIsOnTruthTable、testDetail-
  SubtitleIsOneLine、testSyncLogTimeTextAndFailureFlag；删
  testPermissionStatusText（函数退役）。CI 总计行
  Executed 820 tests, 0 failures。
- IPA：6,880,340 字节，md5 `bb071d147efb3b2d7d8a78f2cbf714ca`，
  独立解包自验 Info.plist ＝ 0.36.18/85、bundle
  `site.didichou.oneday`；落 ~/workspace/your_files/
  oneday-v0.36.18/oneday-unsigned.ipa。版本五处同改已 grep 验。
- 错题本 P-11 终修栏随包更新为 0.36.18 终形态。

### 83.7 真机复验口径

①通讯录详情页：只剩领头＋一个开关＋状态字＋日志（＋内容
区），无第二个开关、无通道状态区、无长段说明。②未授权
件拨开开关：当场弹系统授权窗一次；允许后开关呈开、状态
字走「同步中… → 副本 156 人 · 数据截至…」，日志自「正
在开启」成串。③拨关：跳系统设置 OneDay 页；在设置里关
掉通讯录权限回 App——开关回读为关、状态字报停供、日志
多一条「系统权限被关掉了」；新开对话问 Hermes 人数应只
回状态错误（完全停供）。④系统日历里新建一条日程后回
App（或停在日历详情页）：数秒内日志应多出一轮同步记录
（变更触发），条数对得上。⑤日志一屏多条：时间打头小
字、只有失败行红点红字。

## §84 引用双改：发送全文化＋引用块入舱（0.36.19/86，P-12 终修包）

起因两件，同属引用一物：①用户 2026-11-11 00:21 真机截图——
在 OneDay 内引用 Hermes 长回复，Hermes 回称收到的引用在
「要么你」后面断了、跟着一行括号写着「以下省略」；审计定案
（quote-truncation-audit-20261111.md）：截断在 App 侧发送拼
装层，`MessageQuote.injectionText` 以 1000 字为上限硬截断并
拼字面标记，且每轮上下文重放都经同一拼装——残缺引用在后续
每一轮持续在场。②用户 00:24 形态点题：「两个引用方式不
对，一个在输入框里面，一个在外面」——Muse 的引用嵌在输入
舱内（引用块在上、分隔线、打字行在下，一张卡），OneDay 的
引用条（0.4.1 立制）是输入舱外一张独立浮卡。③用户 00:34
同题追加右滑引用（§84.3）。④⑤用户 00:41 聊天图片两题
（§84.4/§84.5）：待发缩略图飘到输入舱上方居中、已发竖图
显示过大。

### 84.1 内容全文化

- `MessageQuote.injectionText` 改为返回引用原文全文；
  `injectionCharacterLimit = 1000` 与「…（以下省略）」字面
  一并退役，不留任何设备级上限、不拼任何编辑标记进模型
  上下文（错题本 P-12 铁律）。
- 口径＝照 Muse 全文打包：被引内容本就在会话内，每轮重
  放已有尾 20 条管总盘，单条引用再设小上限只会重演事故。
- 展示侧 `summary(maxLength: 60)` 不动：输入舱引用块与已
  发送消息引用块的一行摘要是展示截断、与注入不同源，属
  Muse 同款。
- 历史自动修复：落盘只存引用原文（ChatEntry.quoteContent），
  拼装在读时生成——改一处函数，存量带引用消息在后续重放
  里自动恢复全文，无需数据迁移。服务器侧不在嫌疑链内，
  本包未动。
- 单测改钉：`testInjectionTruncatesLongQuoteWithNotice`（旧
  断言把截断钉死）退役，改 `testInjectionKeepsLongQuote-
  Verbatim`（5000 字全文进出站、尾段可达、无省略标记）＋
  新增 `testInjectionBoundaryLengthsVerbatim`（999/1000/
  1001/20000 一律全文往返）。

### 84.2 形态入舱

- 承载层新设 `ChatView.composerCard`：玻璃卡内 VStack——
  引用块（quoteBar）在上、发丝分隔线（Palette.hairline 1pt，
  随引用块经同一 SmoothExpand 同进同出）、composerRow
  （标准行/录音条两态）在下，一张卡。玻璃施加点与第 1 修
  聚焦保底层（卡面点按聚焦）自 composerRow 上移到卡层，
  命中域扩到整卡。
- quoteBar 入舱改形：fieldFill 底垫＋圆角撤销（卡面即玻
  璃，不卡上叠卡）；左细线与两行文字（正在回复 X／60 字
  摘要一行）不变；✕ 自右中改右上（HStack 顶对齐），命中
  域 44 与无障碍标签不变。分流种子文案（在旁聊里接着问）
  同路不变。
- 高度核算：舱高＝引用块＋分隔线＋输入行——实测高回写
  （喂玻璃圆角连续半径的 composerCapsuleHeight）自输入行
  层上移到卡层量整卡；文本量测与 6 行封顶仍只管文本域本
  身（ComposerLayout.capsuleHeight/ComposerBarLayout 口
  径一字未动），引用块计入舱高、不挤占打字行数。录音条
  本体形态未动（录音态引用块同在卡内上段，与 0.36.17 两
  态共用同一胶囊的既有关系一致）。
- 附件条、语音失败行/提示行仍在卡外上方，形态不变。

### 84.3 右滑引用（00:34 同题追加）

- 动作面：消息气泡向右滑，触发与长按菜单「回复」逐字同
  一的动作——两路共用 `beginReply(to:)` 入口（设待发送引
  用＋清分流种子标＋聚焦输入舱），落点是 §84.2 的入舱引
  用块。自己与对方的消息都可滑；门控与长按菜单同源（纯
  图片消息不挂）；长按菜单保留、并存不互斥（静止按压与
  横向拖动形态不重叠）。
- 判定（Core `SwipeReplyMotion`，单测把守）：方向门＝右
  向（dx＞0）＋横向主导，复用抽屉 S2 锁定口径
  （`DrawerMotion.isDirectionLocked`：|dx|≥10 且 |dx|≥
  1.5|dy|）；跟手位移扣除锁定段、钳 0…76pt；触发只认松
  手瞬间位移 ≥52pt，不认速度（慢滑到位算数、快甩没到位
  不算，判定可预期）。
- 呈现（`SwipeReplyModifier`）：手势以
  simultaneousGesture 旁听——方向门接管前不写任何位移，
  纵向拖动永远锁不上、列表照常滚动，贴底判定等滚动侧
  逻辑一概不碰；接管后位移只横向写入气泡 offset。回复
  箭头（`MessageActionSymbols.reply`）在内容左缘下层，
  随显形进度（位移/阈值，0…1）淡入＋缩放，过阈转武装
  态（主色盘＋onPrimary 箭头）预告松手即触发；松手回弹
  走 MotionTokens.swap（Reduce Motion 时瞬时）。
- 触觉：过阈触发落 `Haptics.impact(.light)` 一处（动效
  宪法表 D 台账已在 Haptics 头注登记），与引用落定同一
  因果链只震一次；未过阈、未接管均无触觉。
- 单测：`SwipeReplyMotionTests` 4 法（方向门右向/横主
  导/纵拖拒/左拖拒/未达锁定距，跟手扣锁定段＋两端钳
  制，阈值边界，显形进度钳制）。

### 84.4 待发附件条入舱（00:41 第四件）

- 定案：`inputBar` 是默认居中对齐的 VStack，
  `attachmentsStrip` 经 SmoothExpand 挂在输入舱卡**外**
  的上方；strip 本体是横向 ScrollView＋HStack、没有满
  宽左对齐锚——单张图时整条 strip 按内容宽被 VStack
  居中，缩略图飘到屏幕中间（用户真机截图）。参照
  Muse：待发图在输入卡内部左上角，与 §84.2 引用块入
  舱同一种结构。
- 修法：attachmentsStrip 并入 composerCard 内部（引用
  块之下、composerRow 之上，同一张玻璃卡），出现/消
  失同样走 SmoothExpand＋发丝分隔线随进随出；inputBar
  里卡外那一份删除。strip 本体与内容各加一层满宽左对
  齐锚（frame maxWidth:.infinity, alignment:.leading），
  单张/多张都钉死左起；横向内边距改 spacingSM 与卡内
  引用块/分隔线同一起点。
- 舱高核算：附件条高计入整卡高（与引用块同口径，走
  卡层 onGeometryChange 既有量高路，不另起）；打字行
  6 行封顶只管文本域、不受影响；composerShape 圆角连
  续函数随整卡高自适应，无离散两态、无滞后重影之源。

### 84.5 已发图片宽高双封盒（00:41 第五件）

- 定案：已发图三处渲染全部只封宽不封高——用户本地图
  （ChatView.bubble）与远端图（ServerRemoteImage，用户
  与助手两侧共用）都是 `.frame(maxWidth: 220)`。用户
  主力图是竖长手机截图（宽高比约 1:2.17），220 宽 →
  约 477pt 高，一张吃半屏还多；Muse 是宽高双封
  （fit-in-box），同图明显小一圈（用户原话点题）。
- 修法：新设 Core 纯函数 `ChatImageSizing.displaySize
  (for:)`——等比缩进 **220×240** 盒、只缩不放大（小
  图按原尺寸）、非正尺寸原样返回；入参/出参同为 pt
  （调用方传 UIImage.size）。三处渲染统一改用：①
  bubble 内用户本地图（精确帧宽高）②bubble 内用户远
  端图（经 ServerRemoteImage）③助手侧远端图（同
  ServerRemoteImage）——ServerRemoteImage 内部改一处
  即覆盖 ②③。scaledToFit 语义、圆角裁剪（调用点
  clipShape）、点开全屏查看器行为不变（查看器不走
  本函数）。
- 占位口径：ServerRemoteImage 加载中占位（220×150
  圆角矩形＋ProgressView）**未动**——数据到达前不知
  宽高比，占位与成品的尺寸跳变以一次为限、与旧口径
  同量级；失败占位（photo 行）同未动。
- 单测：`ChatImageSizingTests` 6 法——竖长图按高触
  盒（1206×2622→约 110.4×240）、横长图按宽触盒
  （2622×1206→220×约 101.2）、方图（1000×1000→
  220×220）、小图不放大（100×80 原样）、极端细长
  （100×3000→8×240）、非正尺寸原样返回；全断言等
  比且不出盒。

### 84.6 交付数字

- 提交三段（同版一次交付）：`db51156`（§84.1/§84.2 双
  改）＋`48d2ee2`（§84.3 右滑引用）＋`e57920d`（§84.4/
  §84.5 图片两题）；三段 CI 依次 `42855131199`／
  `42856505879`／`42858436810` 均 **success**，终验以
  末段（全量）为准。
- 单测 **820 → 831（+11，只增不减）**：引用改钉净 +1
  （旧截断断言改写全文化＋新增边界往返）、
  `SwipeReplyMotionTests` +4、`ChatImageSizingTests`
  +6；CI 总计行 Executed 831 tests, 0 failures。
- IPA：6,899,110 字节，md5 `d2806eee74409c7d4dda238d7159c24a`，
  独立解包自验 Info.plist ＝ 0.36.19/86、bundle
  `site.didichou.oneday`；落 ~/workspace/your_files/
  oneday-v0.36.19/oneday-unsigned.ipa。版本五处同改已
  grep 验。
- 错题本：P-12（引用截断＋编辑标记）、P-13（图片单轴
  呈现）随包入册，终修栏均标「已修待真机验」。

### 84.7 真机复验口径

①长按一条超 1000 字的 Hermes 回复选「回复」，写一句问话
发送——Hermes 应能复述被引回复的尾段内容，不再出现「以
下省略」或引用断裂的回话；同一会话再追问一轮，引用仍全
文在场。②引用待发送时：引用块在输入舱卡内上段（正在回
复 X＋摘要一行＋右上 ✕），其下发丝分隔线、再下是打字行，
整舱一张玻璃卡、无舱外浮卡。③引用在场时打字到 6 行：文
本域仍可满 6 行内滚，引用块不占行数；删光文字、点 ✕ 取
消引用，卡高平滑收回单行 46。④右滑引用：任意一条消息
（自己与对方各一）向右横拖——气泡跟手、左缘箭头渐显，
过约 52pt 箭头盘转主色；松手轻震一下、引用块进输入舱；
短滑不到阈松手只回弹、不引用。⑤在气泡上纵向拖动滚列
表：气泡纹丝不动、滚动与贴底行为如常；长按菜单照常弹
出、五项都在。⑥待发附件：给消息加一张图——缩略图应出
在输入舱卡内左上（引用块之下、打字行之上），不再飘到
舱外居中；加到多张仍左起横排、可横滚；移除到空，卡高
平滑收回。⑦已发图片：发一张竖长手机截图——显示高不
过 240pt 量级（约半屏的一半），横图宽不过 220；点开仍
是全屏原图查看器。

## §85 右滑引用手势热修：UIKit 方向锁桥（0.36.20/87，P-15 终修）

起因：用户 2026-11-11 01:09 真机原话「现在在气泡栏不能上
下滑动，上下滑会话不动，只能右滑」——0.36.19 装机后，消
息气泡区域纵向拖动滚不动会话列表，只有右滑有反应。聊天
滚动是核心功能，定性发布级回归、单件最高优先级热修（后
经用户 01:12 拍板与连接稳固包合并为 0.36.20 一包交付，
连接面见 §86）。

### 85.1 定案

0.36.19 的 SwipeReplyModifier 用 `DragGesture(minimum-
Distance: 6)` 经 `.simultaneousGesture` 挂在整行内容上，
方向门写在 onChanged 里（Core `SwipeReplyMotion.engages`
判横向主导才写位移，纵向不写）。文件注释声称「纵向拖动
永远锁不上、列表照常滚动」——真机证伪。定案机理：
DragGesture 在识别层无法自我失败：minimumDistance 仅
6pt，手指一动识别即成立，纵滚意图在 onChanged 判读之前
就已被手势系统卷入与 ScrollView 平移识别器仲裁；方向门
只挡住了位移写入，挡不住识别抢占。呈现层手势单测全过
（判据本身没错），错在「DragGesture＋事后门控能与滚动
共存」这个从未在识别层验过的假设（错题本 P-15）。

### 85.2 外部核查对账（改前先搜，本包硬门槛）

三路检索（SwiftUI DragGesture 压制 ScrollView 纵滚／
UIPanGestureRecognizer shouldBegin 方向锁／生产级滑动
单元格实现），三档结论：

- **与拟定修法一致（主档）**：①「DragGesture 即使经
  simultaneousGesture 挂在 ScrollView 行上也会赢走触
  摸、冻结纵滚」是已知问题——真实项目 Revela 的工程档
  （GitHub 仓库 CLAUDE.md）实测报告与本次回归逐字同
  型：「raw DragGesture (even via .simultaneousGesture)
  wins the touch over the scroll pan whenever the finger
  starts on a row, so vertical scrolling silently
  freezes… and no amount of gesture-gating fixed it」；
  w3tutorials 的手势冲突文同述子视图 DragGesture 劫持
  触摸、ScrollView 收不到。纯 SwiftUI 的 onChanged 方
  向门路线就此判死。②UIKit 方向锁是通行解：在
  `gestureRecognizerShouldBegin` 里按平移方向决定识别
  器生死（多份实现均为 abs(x)＞abs(y) 家族判据）；生
  产级滑动单元格库 SwipeCellKit 的 SwipeController 即
  此模式（shouldBegin 内按 translation/velocity 角度
  门控）＋滚动侧排斥仲裁。③开发者手势参考（app-
  builders-club/design-builder 的 iOS 手势参考档）把
  「drop to UIKit、经 UIGestureRecognizerDelegate 与
  滚动 pan 仲裁」明列为 ScrollView×DragGesture 冲突
  的修法之一。
- **更优现成解：无**。有来源建议 `.simultaneous-
  Gesture(DragGesture(minimumDistance: 20))`＋方向检
  查——即本包已证伪路线的变体（我们用的正是 simulta-
  neous＋同一门控，仅 minimumDistance 更小），证据强
  度低于桥方案，不采。`List.swipeActions` 不适用：本
  页是 ScrollView＋LazyVStack 自研列表，且要的是跟
  手位移＋箭头显形＋松手触发的连续形态，不是动作
  按钮。
- **外部无记录项**：无与本形态（祖先级 UIPan＋
  shouldBegin 复用自有 Core 判据）完全同款的公开案
  例；不影响定案，前两档证据已足。

### 85.3 修法（接管层换桥，判据与呈现全保留）

- 新增 `SwipeReplyGestureBridge.swift`：零尺寸探针视
  图（`isUserInteractionEnabled=false`、SwiftUI 侧
  `allowsHitTesting(false)`）把 UIPanGestureRecognizer
  装到修饰符 ZStack 容器的父视图上——识别器是内容
  的祖先级识别器，能收整行触摸又不靠覆盖层拦截命
  中；**不用覆盖全行的 overlay UIView**（会吞内容子
  视图触摸、连带打坏长按菜单与点图，违反验收③）。
- 生死判据：Coordinator 的 `gestureRecognizerShould-
  Begin` 只问 Core `SwipeReplyMotion.shouldBeginPan`
  （0.36.20 新增命名出口，与 engages 同一口径：右向
  ＋|dx|≥10＋|dx|≥1.5|dy|），桥侧不许另写比值。
  纵向主导 → 不 begin、识别器对本次触摸死亡、纵滚
  完整归 ScrollView；横向主导 → begin，呈现层才开
  始写 offset（验收④：offset 只在横向 begin 后写，
  贴底/回底判定不被干扰）。
- 仲裁：不实现 simultaneous 代理（默认排斥）——
  横向 begin 后滚动平移不得同行；`.cancelled/.failed`
  只复位不触发（系统夺走的手势不许触发引用）；
  `.ended` 走原 onEnded 语义（shouldTrigger 判定＋
  动画归零＋轻触觉＋beginReply 共用入口）。
- 保留不动：Core 的 followedOffset（扣锁定段，锁定
  段＝识别器 begin 瞬间的 translation.x，与旧语义等
  价）/triggerOffset 52/revealProgress/箭头呈现（左
  缘 30×30 圆盘、progress 驱动、armed 主色）/回弹
  动画（MotionTokens.swap）/纯图片消息不挂的门控。
  抽屉冲突面已排除：壳层抽屉拖拽只挂左缘 24pt 热区
  （壳层顶层独立条、不在消息行祖先链上），与行级桥
  识别器不相交，无需额外仲裁。
- 单测：SwipeReplyMotionTests 新增方向生死判据 4 测
  （纵拒/横允含恰达 10pt 锁定线/临界比值 1.5 两侧/
  左拖与未达距拒/与 engages 网格逐点同源），基线
  831 → 本节 +4（合并包总账见 §86.7）。

### 85.4 真机复验口径（缺一不可）

①从任意气泡（自己的与对方的各一）上起手纵向拖动，
会话列表正常滚动、气泡纹丝不动——本包立身之本，验
收第一条。②右滑照旧：箭头随滑渐显、过约 52pt 转主
色、松手轻震＋引用块进输入舱；短滑未过阈松手只回
弹、不引用。③长按任意气泡，菜单五项照常弹出、点
图/点链接照常。④长线程里右滑引用后上下滚动，回底
钮出现/消失与贴底跟随与 0.36.19 之前一致（桥不写
滚动侧状态）。⑤来电/下拉通知中心等系统手势中途夺
走滑动时，气泡只复位、不误触发引用。

## §86 连接稳固五件（0.36.20/87，P-14 终修；与 §85 合并一包）

起因：用户 2026-11-11 00:56 点题「还时不时说网络断开」。
内部审计 disconnect-audit-20261111.md 定案残余三路：
R1 探活单点无迟滞（30s 一发 /health、一次失败即翻「联
系不上」、业务成功不回写）、R2 发送链接步单发无重试、
R3 切网瞬间全链裸奔（无 NWPathMonitor、无 waitsFor-
Connectivity）；外部调研 disconnect-solutions-20261111
与审计对账一致（通行解＝服务端心跳＋断≠死＋客户端静默
退避重试＋可达性只作触发器＋呈现分档），冲突处以审计的
代码实查为准。用户 01:02 拍板连接包插队、01:12 再拍板
与 §85 热修合并为 0.36.20 一包一次交付。

### 86.1 静默流探针（⓪，只诊断、未动生产）

施工前实查：服务器内存约 51%（红线 80% 内）；凭据自
hermes-deploy/credentials.txt 取、未落盘未外传；测试请
求共 2 条 run（首条因探针进程被外壳回收、日志丢失，重
跑 1 条，合计未超最少量口径）。方法：建会话→提交一条
指令（终端工具 sleep 45、执行期零输出）→拉 /v1/runs/
{id}/events 全程逐行记字节时序。实测（run_615fd293…
会话 api_1794331381_df931abd，探针日志留会话工作区）：
- 流一建立即有 `: open` 注释行；tool.started 后工具实
  跑 45.2s，静默期 **`: keepalive` 每 10.00s 一发**（全
  程 4 发在静默窗内）；tool.completed→message.delta→
  run.completed 依次到达，流以 `: stream closed` 正常
  收尾。**全程最长无字节间隙＝10.00s，流未中途死**。
- 结论：**生产 Hermes 的 events 流已有心跳**（10s 间隔，
  优于外部调研的 15–25s 通行带），且开流先发注释、终态
  后关流——调研 A 组（服务端心跳）现状已达标，**无需
  任何生产变更，本包未动服务器**。nginx /v1/ 段 600s
  基线与 10s 心跳相差 60 倍，中间层掐流不成立为当前
  「断开」体感来源；与 86.5 互印：即便会话级 30s 空闲
  超时支配流（R5 的悲观分支），10s 心跳也永不让流空
  闲到 30s。建议主线：心跳事项就此销项，不再另行报批。

### 86.2 在线判定多信号＋迟滞（①，治 R1＋R4）

- 判定抽 Core `ConnectionLiveness`（新文件 Connection-
  Stability.swift，单测把守）：连续失败满 **3 次**才定
  版离线；阈值前失败只累加、isUp 保持上一结论；任一
  成功立即清零回写在线。阈值取 3 的理由：探活 30s 一
  轮、轮内另设快速重探（下条），单次抖动（负载尖峰/
  旁路由节点切换/TLS 建连失败）只吃 1 次计数永不达
  阈；真断时快速重探数秒内连失 3 次即定版，不等三轮
  30s。取 2 则两次相邻抖动（同一旁路由切换窗口内并
  非独立事件）即可误翻，取 4 以上真断呈现又迟到——3
  是「独立抖动不达阈、真断一轮内定版」的最小值。
- OverviewBridgeStore.refresh 的探活步改走 probe-
  Channel：失败按 Core `RetryBackoff`（base 1.0/cap
  4.0 全抖动）在**轮内快速重探**，连失满阈才写
  hermesChannelUp=false；任务取消不记账（退后台不是
  失败）。呈现位置与文案不变、只换判据：Overview-
  StatusLine.classify 与状态行/状态点零改动。
- 业务成功回写（治 R4）：HermesClient 的 dataRequest
  漏斗在任一**业务端点**收到完整 HTTP 响应（任何状态
  码——收到响应即通道可达的实证）时回调 onTransport-
  Success（/health 除外，防探活响应先把自己的失败计
  数洗掉）；AppState 转为 hermesBusinessSuccessTick，
  ContentView 观察即调 store.noteBusinessSuccess()
  清零回写。聊天刚收发成功、胶囊还挂旧「联系不上」
  最长约 30s 的词与事实打架自此消除。

### 86.3 发送链接步退避重试（②，治 R2）

- ChatView.send 的链接步改走 prepareSendShapeWith-
  Retry 包装：只对 `HermesError.isTransient`（既有失
  败分型——瞬断类）重试，总尝试 = Core RetryBackoff.
  maxAttempts（首发＋2 次，与提交步同 key 重试同量
  级）、全抖动退避（base 1.2/cap 5.0，AWS full
  jitter 式，与提交步固定 1.2s 间隔同量级且更防齐
  发）；鉴权/业务失败不重试、原样上抛；取消即转
  CancellationError 走既有静默收尾。重试语义与用户
  手动重按发送完全一致（主线 ensure 幂等；旁聊每次
  尝试内现铸定 id，极端时序可能在服务端多留一个空
  会话——无消息落入，与手按重发同性质，不另造跨尝
  试 id 托管）。
- 与提交步的 ambiguous 口径对齐说明：链接步没有服
  务端 run 可对账，瞬断重试耗尽即由调用方既有分支
  出失败横幅——此时本条消息从未进入提交步、「未发
  送」属实，属 86.5 呈现三档的第三档（重试耗尽才
  出失败文案），不是提前翻脸。

### 86.4 网络变化只作触发器＋waitsForConnectivity（③，治 R3）

- 新增 NetworkPathObserver（NWPathMonitor，全 App
  单例、只启一次、与 App 同寿）：path 由不可达变可
  达、或可达状态下接口集合变化（WiFi↔蜂窝）时触发
  一次——ContentView 据此立即重探活一轮、ChatView
  据此走 resumeRunIfNeeded 续对账。永不预判/拦截
  请求、永不凭 path 单独置离线呈现（苹果 WWDC19-
  712/713 官方口径：可达性只作信号不当判决书）。首
  次 path 回报只播种基线、不触发。
- **回调隔离验收**：NWPathMonitor 在自家队列投递
  pathUpdateHandler——NetworkPathObserver 是非隔离
  普通类，handler 闭包不继承任何 actor 隔离，只碰
  OSAllocatedUnfairLock 护着的转手盒；跨界通知走注
  册方 @Sendable 闭包，AppState 侧以 `Task { @Main-
  Actor in }` 显式跳回主隔离写计数。全仓 grep 自查：
  本包新增的跨隔离回调共两处（path handler 与
  HermesClient.onTransportSuccess），均为「非隔离
  转手＋显式跳回」形态，无第三处同类新形态。
- waitsForConnectivity：短请求开——HermesClient 短
  请求会话与 OverviewBridgeClient 会话均置 true
  （探活/总览/通知取数/提交/状态查询在无路径时先等
  连通再开始，不立刻失败；WWDC17-709 官方推荐）。
  流式长连接不开：waitsForConnectivity 只管「开始之
  前」，流在进行中的掉线不在其覆盖内，且让订阅在
  离线时悬等会搅乱失败/重挂时机——流的生死归既有
  对账链管。

### 86.5 流式超时口径定谳（⑤，R5）＋呈现三档（④）

- **定谳**：NSURLRequest 的 timeoutInterval 与
  URLSessionConfiguration.timeoutIntervalForRequest
  的关系，苹果文档口径为请求级覆盖配置级
  （URLRequest.timeoutInterval 文档：请求自带值优
  先），但社区对 AsyncBytes 流式任务有不同实测报
  告，光凭文档不能对 events 流的空闲判死打包票。
  **修法是把争议从构造上掐死**：HermesClient 拆双
  会话——短请求会话（timeoutIntervalForRequest=30
  ＋waitsForConnectivity）与流式会话（timeout-
  IntervalForRequest=**600**、waitsForConnectivity=
  false），runEvents 与遗留 chatStream 改走流式会
  话；请求级本就是 600，两层同值后无论哪层支配、
  空闲判死都是 600s 口径。再叠 86.1 探针实证（心跳
  10s），流空闲判死在事实上永不触发。cookie 走
  .shared 存储、双会话共享，登录态不受影响。
- **呈现三档**（判定与重试共用同一策略源：Core
  ConnectionLiveness＋RetryBackoff）：一档静默期
  ——探活连失未满 3 次、链接步重试未耗尽期间，不
  出任何断开文案，状态词保持上一结论；静默窗口算
  式：探活侧＝轮内 3 次尝试（快速失败时≈退避 0–3s
  ＋尝试耗时，通常数秒内定版；全超时极端 ≤15s×3＋
  退避≈48s 上限），链接侧＝3 次尝试＋退避期望约
  3.6s（快速失败）——与「约 10–15s 量级」的典型窗
  口对齐，极端值如实记上限。二档进行时——run 链断
  流走既有对账 notice（「生成仍在服务器进行中…」/
  「已重新连接，回复已补齐」），不造第二套横幅。三
  档失败——仅服务端明确终态或重试耗尽才出失败文
  案（链接步横幅、提交步明确拒绝、探活定版离线后
  的状态词）。单一信号（一次 URLError、一次 path
  unsatisfied、一次桥失败）永不单独翻脸。

### 86.6 错题本与单测

- 错题本新增 P-14（在线判定单信号无迟滞＋关键前置
  步零重试）与 P-15（见 §85），同包入册。
- 单测：ConnectionStabilityTests 新增 9 测（连失计
  数/阈值翻转/成功清零/抖动不翻/静默期标志/全抖动
  公式与帽/自定义 base·cap/重试上限），§85 的 4 测
  另计；831 → 844，只增不减。

### 86.7 合并包总账与真机复验口径

- 版本 0.36.20/87 五处同改（Project.swift 两处＋
  plist 两处＋SettingsView 页脚），grep 验毕。
- 交付数字：提交 `7f2cc45`（整包）＋`9855bb7`（本
  §85/§86 文档）＋`d3123ee`（CI 修：AppState 信号接
  线移至 init 末尾——首轮 CI 42865024065 的 Build 步
  报 self 未初始化先用，Tests/Package 步 skipped；
  修后终验 CI **42866756617** 全步 success）；CI 总
  计行 Executed **844 tests, 0 failures**（831＋手势
  4＋连接 9，只增不减）；IPA 6,919,048 字节，md5
  `eb8bad838ac9b78c6256a48c8912dc24`，独立解包自验
  Info.plist＝0.36.20/87、bundle `site.didichou.
  oneday`；落 ~/workspace/your_files/oneday-v0.36.20/
  oneday-unsigned.ipa。
- 连接面真机复验：①聊天页停留不动，旁路由/路由器
  制造一次数秒抖动（或短暂断开 WiFi 再恢复）：胶囊
  不许闪现「联系不上」；抖动后业务照常、状态保持
  「在线」。②飞行模式开 1 分钟再关：关后数秒内胶
  囊自行回「在线」（path 触发重探），不许等满 30s。
  ③发消息瞬间切网（发送同时切换 WiFi/蜂窝）：消息
  应发出或静默重试后发出，不许一点发送就弹「会话
  链接失败」。④长工具/长思考一轮（1 分钟以上）：
  回复完整到达、无「已重新连接」notice 反复出现
  （心跳＋600 口径下流应全程不断）。⑤真断网（服务
  器不可达持续 1 分钟以上）：胶囊最终落「联系不
  上」——迟滞不是永不报，恢复后回「在线」。

## §87 审批卡包：对话流就地审批＋「总是允许」规则面＋审批文案人话化（0.36.21/88，2026-11-11）

起因：用户 2026-11-11 01:17 发 Muse 审批卡截图点题——
审批卡就地长在对话流里、人话标题、三档裁决（允许一
次／总是允许／拒绝）、裁决后有结果痕迹；01:18 拍板
插队成本包；01:55 再点第三件：枢纽已决历史的条目全
是英文运维串（「batch(3 ops: patch, patch, patch) on
…」「add to memory: …」）、来源漏原始标识「oneday_
app」、相对时间也是英文——「现在的审批都是英文，普
通用户怎么看的懂？」规格 approval-card-design-2026-
1111.md；本节与 §88（右滑再修）同属 0.36.21 合并包。

### 87.1 数据前提结论（决定挂卡形态，实查定案）

- **无会话归属字段 → 退位形态**。三处对齐实查：桥
  `write_gate_bridge.py` 的 `_norm_record` 只出 id/
  subsystem/action/summary/origin/created_at(/payload
  详情)；方案文档 write-approval-bridge-plan.md 字段
  清单相同；App `WriteGateRecord` CodingKeys 同构。
  origin 是来源标签（foreground/background_review/
  assistant_tool/oneday_app/cli…），不是会话 id。
- 定案形态：**待批卡置于当前对话流末尾**（全部未决
  汇到用户正在看的流）＋**枢纽兜底**（总账/历史/规
  则）。给桥补 thread_id 属上游改造（stage_write 的
  记录结构没有该字段），本包不做。
- **「暂不支持在 App 内审批」枚举定案**：即
  `WriteGateRecord.canDecide == false` ⟺ subsystem
  ∉ {memory, skills}（解码落 `.unknown`——桥将来新
  增子系统、或枚举外字符串）；桥 decide/detail 路由
  对非这两类返回 400（App 侧 pathSegment 为 nil），
  故既不能裁决也不能拉详情。现行桥只产出 memory/
  skills 两类，此分支为纯防御。处理：卡面保留只读
  ＋明示「请在 Hermes 中处理」，不静默缺失（聊天卡
  与枢纽卡同口径，本包已把枢纽旧文案补齐去向）。

### 87.2 就地卡形态（ChatApprovalCards.swift）

- 挂载：ChatView 的 LazyVStack 中回告卡之后、空态
  之前——只在呈现层拼装、绝不写入会话（0.7.0 红线
  D4 先例）；仅 `approvalState == .ready` 时渲染，
  未接通/未启用/失败态不在聊天里闹（枢纽如实呈现）。
- 卡面：徽章＋相对时间（zh_CN，§87.5）、人话标题问
  句（Core `ApprovalCardCopy.question`：动作＋对象走
  结构化字段模板）、结构化头条（§87.5）作说明行、
  内容预览、来源人话、一句后果说明、canDecide 时示
  「总是允许范围：<子系统·来源>（可在枢纽撤销）」。
- 「查看详情」就地 inline 展开：按需拉桥 detail，
  内容体与枢纽 sheet 共用 `ApprovalReviewContent`
  （自 HubDiffView 抽出，含 notes 警示/patch 原文失
  效提示/diff 正文＋原始信息折叠区），不跳 sheet。
- 三档全宽堆叠：批准（.borderedProminent）／总是允
  许这一类（先确认弹窗）／驳回（末位、确认弹窗）；
  裁决中态、失败留痕沿用 store 的 decidingIDs/
  cardNotes；裁决后卡原地收成结果行（已批准/已驳
  回/已批准 · 已记住这一类/已按规则放行，上限 20
  条、按记录 id 去重）。
- 刷新触发四点：进/切对话（.task id: 线程）、回前
  台（scenePhase.active，与 resumeRunIfNeeded 并
  行）、网络路径变化（networkPathEpoch）、生成结
  束（isStreaming 下降沿——写入最可能刚被暂存的时
  刻）。聊天侧走 `refreshApprovalForChat` 静默刷
  新：ready 态不回 loading、不闪卡；失败保留现态。

### 87.3 共享 store（同数据同路径，规格 §6）

- `AgentHubStore` 自此由 `AppState.sharedHubStore()`
  懒建单例持有（客户端按 isDemo 选，onApproval-
  Changed 改 var、由 AgentHubView 注入——全 App 唯
  一枢纽呈现点仍是 ChatView 的 sheet）。聊天卡与枢
  纽卡读同一份 /pending、走同一 decide 路径。
- 一致性代价与对冲：loadApproval 的「枢纽已打开就
  跳过重拉」缓存语义不变，但 AgentHubView 打开时改
  走 force:true——保住「每次打开枢纽必刷新」的既有
  语义，防共享后枢纽数据发陈。
- 结果行对账：每次成功拉取后，用「上一轮 ready 快
  照 − 本轮 pending」∩ 已决历史补结果行（via_rule
  →已按规则放行）。覆盖关键生命周期：卡已显示→用
  户建了规则（或规则早已存在）→桥 sweep 自动放行
  →卡消失但结果行如实出现，不无声蒸发。

### 87.4 桥侧规则面（只施工未部署，部署另行报批）

契约（companion/modules/write_gate_bridge.py，本包
新增；自测 tests/write_gate_rules_selftest.py 22/22，
全套回归除 device_sync 一项既有时间敏感失败外全过
——该项种子数据按「今天」算到期数、跨日漂移，与本
包文件零交集，已核时间戳为 11-10 旧文件）：

- 存储：`<HERMES_HOME>/write-gate/rules.json`（与
  decisions.jsonl 同目录），tmp＋rename 原子写；
  **规则键＝（subsystem, 原始 origin）**；rule id＝
  `"rule_" + sha256(subsystem + "\x00" + origin)[:16]`；
  建规则幂等（同键回既有、created=false）。
- 放行：staging 发生在 Hermes 内部 `wa.stage_write`、
  不经桥，唯一钩子是 sweep——`_sweep_rules()` 在
  GET /pending、GET /status 前先跑，另有 main() 起
  的 5 秒后台 sweeper 线程兜底；命中规则的 pending
  走与 HTTP decide 完全同一的 `_apply_decision`
  路径（批准→执行→落账），decision 记 "approved"、
  另带 `via_rule=<rule id>`——历史/台账/面板据此显
  示「按规则放行」，不与人工批准混同。
- 端点（全 Bearer）：GET /rules；POST /rules（校验
  subsystem ∈ {memory, skills}、origin 非空 ≤200 字
  无控制字符；新建 201/已存在 200）；DELETE /rules/
  {id}（200/404 不存在/400 id 格式非法）。规则端点
  在写闸 SUPPORTED=False 时也可达（桥本地状态）。
- App 侧失败语义：`decideAlways` **先建规则后批
  准**——建规则失败→cardNotes 留痕「没能记住」、不
  批准、记录留待批（不许假装已记住）；建成→刷新规
  则镜像→打 always 标记→走既有 decide(approve)。
  建成后、批准前记录被 sweep 抢走的，按 recordGone
  路径据账本补「已按规则放行」结果行，如实。
- 撤销面同批落地（无撤销不交付）：枢纽「审批规则」
  区列 scope（子系统 · 来源人话）＋建立时间＋撤销
  （确认弹窗）；撤销失败保留并留人话、按桥真值重
  拉对账。规则只存桥侧，App 本地零存储。
- **部署清单（待主线报用户批准）**：文件仅
  modules/write_gate_bridge.py 一个（＋自测文件不
  上生产）；回滚基线＝现行生产 write_gate_bridge.py
  原文件；动作＝替换文件＋重启伴生容器（write-gate
  模块随容器重启加载）；数据面新增 rules.json（首
  次建规则时生成，删除即全量回滚规则面）；App 侧
  在桥未部署前：/rules 404/501→规则列表保持空、
  「总是允许」走 bridgeMissing 留痕失败、既有两档
  裁决不受影响。

### 87.5 文案人话化（宪法 §8 在审批面的收口，P-16）

- 头条模板 `ApprovalHeadline`（Core）：由结构化字
  段拼中文——batch(3×patch) on 技能 X→「修改技能
  《X》：共 3 处改动」；create→「新建技能《X》」；
  add＋预览→「新增一条记忆：〈预览〉」；remove＋
  user 目标→「从个人资料删除：〈预览〉」。待批卡、
  就地卡、已决历史、记忆页待批行四处同口径（历史
  行 Text(item.summary) 与枢纽卡 displaySummary 直
  用原串的两处漏点已改 headline）。
- 字段来源在桥侧补齐（同 §87.4 文件，未部署）：
  `_structured_fields` 从 replay payload 提取 op
  （有效动作）/target_name/op_count/op_kinds/mem_
  target/content_preview（≤120 字），_norm_record
  与 _append_decision 同源输出——**不许 App 对英文
  串做字符串替换凑数**；桥未部署前字段缺失，模板
  退通用中文句（动词＋类别），任何情况下头条不回
  落英文原串。说明行（previewLine）：内容预览优
  先；无预览且原摘要中文主导才用摘要；英文摘要→
  无说明行。原始串只许进详情「原始信息（排障用）」
  折叠区（摘要/来源原值/记录编号，默认折叠）。
- 来源映射：`WriteGateLabels.originLabel` 新增
  oneday_app→「本机 App」；**未知值口径修订（用户
  点名，覆盖 0.36.x 旧「回落原始值诚实呈现」）**：
  未知 origin →「其他来源」，原始标识只进详情折
  叠区。规则键仍用 origin 原值（桥侧匹配），映射
  只管呈现。
- 相对时间：审批面三处改走 `ApprovalTimeText`
  （RelativeDateTimeFormatter 钉 zh_CN locale），
  不再 `.formatted(.relative)` 跟随设备口径。
  **审批面之外的同类漏点清单（本包不扩围、留后续
  包）**：HubCronSection.swift 1 处 `.relative
  (presentation:)`（定时任务段的相对时间，同病同
  源，建议随下个枢纽相关包一并收口）。全仓仅此一
  处余量（已 grep 核清：HubApprovalSection 2 处已
  改、ChatApprovalCards 新增即用新口径）。
- 钉测（Tests/OneDayCoreTests/ApprovalCopyTests
  .swift，13 个用例）：四类真实串形态＋兜底分支＋
  「英文原串永不当头条」＋via_rule 解码与同模板头
  条＋问句模板（含结构化 op 优先于顶层 action）＋
  规则模型解码＋相对时间中文断言；既有 HubGate-
  AndBrowserTests 的未知来源断言同步改新口径。

### 87.6 复验口径（真机，五条＋一条）

1. 对话中触发一条待批写入：当前对话流末尾就地出
   卡，不用去枢纽页找；
2. 点「查看详情」：差异在卡内就地展开，不跳页；
3. 点「总是允许这一类」：该条批准生效；再触发同
   类（同子系统、同来源）写入：不再出卡、自动放
   行，已决历史里标「按规则放行」；
4. 枢纽「审批规则」撤销该规则后，再触发同类写
   入：重新出卡等待审批；
5. 点「驳回」：写入不生效，卡原地收成「已驳回」
   一行；
6. 文案：打开枢纽已决历史，最近几条头条全中文可
   读，英文只在点开详情的「原始信息」折叠区里。
   （前置：§87.4 规则面部署获批并完成后第 3/4 条
   才可验；未部署前第 3 条会如实报「没能记住」。）

## §88 右滑再修：shouldBegin 生死判据改速度域（0.36.21/88，P-15 续修）

真机回归第二轮：0.36.20 装后用户 01:53 报「右滑不
行了」——纵向滚动恢复、右滑引用完全没反应。上一轮
修过头：滚动与右滑只保住一头。与 §87 合并一包（用
户原话「审批和修复一个版本搞」）。

### 88.1 外部核查对账（先搜后改，三档）

- **与拟定修法一致且给出生产实证（主证据）**：
  SwipeCellKit PR #381 ——其 `gestureRecognizer-
  ShouldBegin` 原用 translation 判方向（`abs(t.y)
  <= abs(t.x)`，与我方 0.36.20 首版同型同病），被
  改为 velocity＋角度门 `atan2(|vy|,|vx|) < π/8`
  （22.5°，即 |vx|/|vy| ≳ 2.41）。生产级库在同一回
  调位置踩过同一坑、修法是换信号域。
- **旁证同向**：LiveFront 的可拖拽 ScrollView 工程
  文、onmyway133 的 UICollectionView 横滑文——
  shouldBegin 里的方向决策在野实现均用 `velocity
  (in:)`；Exyte Chat 的滑动动作建在 UITableView 系
  统滑动操作（UISwipeActionsConfiguration）上，仲
  裁由系统接管，不适用于自研 LazyVStack（与 §85 旧
  判一致，不采）；Xtend 工程博客记录其聊天右滑回
  复「花了六个提交才与邻居手势共存」，佐证此坑的
  通行难度。
- **未核到**：Telegram iOS 的具体实现细节未检索到
  可用证据（结果为无障碍 issue 噪声）；其列表为自
  研 AsyncDisplayKit 面、实现不可迁移——如实记未核
  到，不凑数。

### 88.2 根因定案（主线头号嫌疑坐实）

`gestureRecognizerShouldBegin` 在 pan 刚要离开
.possible 时被咨询，此时累计 translation 远未够到
Core 锁定距离（DrawerMotion.directionLockDistance
＝10pt），`SwipeReplyMotion.shouldBeginPan` 的位移
判据（|dx|≥10 且 |dx|≥1.5|dy|）对几乎每次触摸恒为
false → 识别器永远 begin 不了 → handler 永不被调、
右滑全无反应；纵滚则因本识别器从不竞争而完好无
损——两个版本两种相反症状（0.36.19 纵滚死、0.36.20
右滑死），病根都是方向门放错了层或用错了信号。次
嫌疑「默认排斥仲裁恒输」被 SwipeCellKit 生产实证
推翻为非主因（同形态仲裁在生产可用）。

### 88.3 修法（形态 A：判据换域，不换结构）

- Core：`SwipeReplyMotion.shouldBeginPan` 改速度签
  名 `(velocityX:velocityY:)`——`vx > 0 && |vx| >=
  DrawerMotion.directionLockRatio × |vy|`。比值引
  DrawerMotion 单源（1.5，与 SwipeCellKit 的 2.41
  角度门口径不同但同族：本仓抽屉 S2 与右滑共用一
  个方向比值是 §84 起的单源纪律，不为对齐外部数字
  另立一份）；速度域不设距离下限——pt/s 与 pt 不同
  量纲，硬套 10pt 距离门正是本轮病根，SwipeCellKit
  亦为纯角度门、无速度大小门。
- 桥：shouldBegin 改读 `pan.velocity(in: view)`；
  handler 的位移锁定段（.began/.changed 后用
  engages 的 translation 口径定跟手）不动——begin
  之后位移已真实累积，位移判据在该阶段成立。
- 不动的：阈值 52pt、显形进度、箭头呈现、回弹、触
  觉、beginReply 入口、长按菜单、点图、贴底/回底；
  不设 isScrollEnabled 开关（SwipeCellKit 亦不
  做：横向 begin 后禁滚靠系统默认排斥仲裁）；回调
  隔离形态不变（桥 Coordinator 非 actor 隔离，与
  §85 一致）。
- 仲裁四态对本形态的落点（扩围简报四条）：未定案
  零写入＝位移只从 .began/.changed 回调写＋拒判用
  例钉测；纵向定案自取消＝纵向主导速度判 false、
  识别器在识别层自毙（等效 .cancelled 于本次触
  摸）；横向定案禁滚＝begin 后系统默认排斥仲裁（构
  造性，无代码开关）；松手/取消必恢复滚动＝全程不
  改任何滚动状态、.cancelled/.failed 只走既有
  onCancelled 复位位移——无状态可恢复即构造性成
  立。原「begin 后 handler 内纵向再定案自取消」的
  备选形态（B）不采：shouldBegin 已按速度定生死，
  再在 handler 里加一层取消是重复仲裁、且会引入新
  的中途闪断面。
- 钉测：SwipeReplyMotionTests 的 shouldBeginPan
  组按速度域重写（右向主导含临界 150/100 恰达 1.5
  倍允、纵向主导拒、左向拒、零速拒、慢速方向明确
  允）；位移域的 MatchesEngages 逐点同源断言随判
  据换域退役（两域不同量纲、逐点相等不再成立），
  engages 本体用例保留。

### 88.4 复验口径（真机）

第一条并列两件、缺一不可：**从气泡上起手纵向拖
动，列表滚动正常；且右滑过半程（52pt）触发引用、
出引用块**。其余沿 §85：纵滑全程气泡零横移；右滑
未过半松手回弹不触发；长按菜单五项不受影响；点图
开预览不受影响；贴底与回底钮照常；手势被系统夺
走（来电/控制中心）只复位不误触发。

### 87.7 交付实录（0.36.21/88 合并包，含 §88 与 §87.5）

提交 160e918（顶端）；CI **42872268682** 首轮全步
success（jobs API 逐项核：Build/Unit tests/Package/
Upload 均 success，无先红后绿）；单测 **857**（基线
844：手势判据速度域重写 −1、文案钉测 +14，净 +13）；
IPA 7,030,469 字节、md5 `fc684176ac6fa9ce2a77c284f4
c19d5d`，主线口径外独立解包验 Info.plist＝0.36.21/
88。落 ~/workspace/your_files/oneday-v0.36.21/。桥侧
规则面＋结构化字段仍为**只施工未部署**（§87.4 部署
清单待批），App 在未部署桥上：审批两档照常、第三档
与规则区如实报未接通/没能记住，不假装。

## §89 枢纽页对齐包：整页呈现＋智能体本地档案＋分享名片（0.36.22/89，2026-11-11）

### 89.0 来源与范围

用户 01:56 连发三图对标 Muse 智能体页，亲点两
条：①枢纽页改整页（右滑返回、✕ 关闭、分享）；
②头像带编辑角标、可换虚拟形象与改名。01:59 拍
板紧跟 0.36.22 做，规格 hub-page-alignment-
design-20261111。本节只记本包定案；枢纽四段（活
动/任务/审核/监测）内容与数据面、审批卡（§87）
一律不动。

### 89.1 呈现形态：整页 cover 而非导航推入（取舍明说）

规格字面是「推入式整页」。落法选 **fullScreen-
Cover**、不做 navigation push，理由：聊天页
0.2.4 已刻意撤销 NavigationStack、顶栏走悬浮/
safeAreaBar，把枢纽硬塞进聊天页导航栈要重建一
套栈语义；枢纽自带 NavigationStack，再嵌栈是双
栈回归面。cover＋系统边缘识别器在用户可感知的
三点上与推入等价：整页全屏进场、左边缘右滑跟手
返回、✕ 圆钮关闭——仿的是机制不是皮（设计宪法
⑩）。呈现点全仓唯一：ChatView 的 showHub 由
.sheet 改 .fullScreenCover，入口（胶囊点按/回告
卡）与审批终态回调不变；sheet 时代的下滑关闭与
拖拽指示器随之退役（.presentationDragIndicator
删除）。

边缘右滑：新桥 HubEdgeSwipeBridge——零尺寸探针
把 UIScreenEdgePanGestureRecognizer（系统边缘识
别器本体、只认左缘起手）装到枢纽根容器；判据全
收 Core HubEdgeSwipe 单源（生死只认速度域＝P-15
续修口径：begin 时刻平移≈0、读位移恒假死；跟手
钳 [0,480]；松手＝位移 ≥90 直达，或 ≥40 且速度
≥500 快甩）；内容层随 offset 横移跟手，根下垫页
底色。浏览器段禁用本手势（isEnabled 按段置位，
网页自有横移/缩放优先）。

### 89.2 页头与分段

- 圆钮行（左上 ✕、右上分享，玻璃圆钮 36pt）：
  原只在 mode=.sheet 出现，.activity（现行唯一入
  口）反而没有——0.6.0「活动模式撤圆钮行」口径由
  整页化覆盖，本包起两模式统一常驻。钮行仍以
  ZStack 叠在头像行同高（原形态不改）。
- 头像/名称/状态：头像读档案解析图（见 §89.3）；
  名称仍走 AgentHubStore.displayName（链首叠档
  案覆盖，见 §89.3）；状态点与文案读 store 既有
  在线判据（§87 迟滞判据同源），不新造。
- 分段栏：**保持原生 .segmented Picker 不换自绘
  胶囊分段**——现行已是 iOS 26 原生分段（玻璃材
  质与胶囊同族），用户旧定案「原生先行」在位，
  不为对齐截图换自绘（宪法⑩同源判断）；段数段
  名四段原样。

### 89.3 智能体档案（新）：模型、存储、解析链

Core 模型（OneDayCore/AgentProfile.swift，纯逻
辑＋单测把守）：

- AgentProfile＝显示名覆盖（String?）＋头像选择
  （预置 id／自定义二值）。
- AgentDisplayName.resolve(override:soulName:)：
  **覆盖 → soul 解析名 → Hermes 回落**——覆盖是
  「在这台手机上的称呼」，不抄存服务端名（服务
  端改名、没设覆盖的用户自动跟上）；AppState.
  agentDisplayName 为全 App 露脸名单一出口，
  AgentHubStore.displayName 在其链上再叠本店
  soul 解析一层（覆盖→AppState 名→本店 soul→
  回落）。
- sanitizedOverride：折叠空白、去首尾，空或超
  20 字回 nil（编辑面据此判「恢复自动/无效」，
  不静默截断用户输入）。

App 存储（AgentProfileStore，AppState 持有）：

- 选择值落 **UserDefaults** 三键（agentProfile.
  displayNameOverride / .avatarPresetID /
  .usesCustomAvatar），与 chatModelID 等偏好同
  层；自定义图本体落 **Application Support/
  AgentProfile/avatar.jpg**（入库前居中裁方＋边
  长压 512＋JPEG 0.85）——图不进 UserDefaults、
  不进 Keychain（不是凭据）。
- 头像解析链：自定义（文件缺失/损坏回落缺省预
  置）／预置资产图／符号盘离屏渲染（240pt、@2x，
  底色 App 层按 id 映射 Palette pastel、glyph 墨
  色）→ 收敛成一张 UIImage 内存缓存，
  AppState.agentAvatarImage 单一出口，各露脸面
  的原有 resizable/clip 修饰链不变。档案带修订
  号（每次变更 +1）供派生渲染（分享名片图）重算。
- 预置目录四款：partner 三狗搭档款（资产
  SangouPartner，缺省，升级用户视觉零变化）＋
  paw 爪印／sparkles 星光／atom 原子（SF 符号
  盘）。资产盘点实录：App 现有形象资产只有
  SangouPartner 一款属智能体头像，其余为品牌/
  桥图标，不冒充头像资产。
- 编辑面（头像徽章改 **Menu** 两项，两模式统
  一；旧「徽章跳身份段」口径被本包用户定案覆
  盖，身份段本身仍在段列、服务端身份编辑不变）：
  更换虚拟形象＝预置网格点选即换＋PhotosPicker
  相册选图（loadTransferable 与聊天附件同口径；
  制备或落盘失败留红字提示、不假装换成）；编辑
  名称＝草稿三态（留空保存＝清覆盖恢复自动／合
  法／超 20 字禁存并明示），另有「恢复自动」直
  接清覆盖。两编辑面都注明：只改本机呈现、不动
  服务器身份。

### 89.4 分享名片：内容清单与红线核查

页头分享钮内容换代为智能体名片（旧 shareText
含当前模型、无域名，自此退出分享面、store 内留
置不用）：

- 名片图（600×360pt、@2x 渲染）：头像（档案
  图）＋显示名＋服务器域名＋「OneDay 智能体」
  品类行。
- 名片文本（AgentShareCardText）：「名 · 域名」
  或仅名。
- **红线核查**：只有名称＋头像＋域名 host 三
  件。域名经 AgentServerHost.extract 从本机存
  的服务器地址串当场提取——剥 scheme/userinfo/
  端口/路径/查询，只出 host；名片文本函数入参
  只有名与 host，密钥/令牌/完整连接串结构上进
  不来。渲染未就绪时分享钮回落纯文本名片，永
  不假按钮。

### 89.5 硬编码收敛清单（grep「Hermes」/identityName/SangouPartner 逐处判）

改（显示名/头像 → AppState.agentDisplayName /
agentAvatarImage）：

- 枢纽页头头像与名（AgentHubView/store 链）；
- 聊天页胶囊头像、胶囊名、无障碍标签（Chat-
  View）；聊天空状态头像（ChatView）；
- 抽屉名字头（DrawerView）；总览页身份锚名与
  头像（OverviewView，原字面 "Hermes" 是全仓
  唯一漏网的写死显示名）；状态页页头名（Status-
  View）；设置页身份头名（SettingsView）；文件
  页身份锚名与头像（DeliverablesView）；外观页
  预览卡头像与名、形象大小选择器标签头像
  （AppearanceView）；
- 引用面助手称呼：MessageQuote 加带名重载
  speakerName(for:assistantName:)（旧签名以
  Hermes 回落委托、旧测保持绿），ChatView 引
  用块标签与引用条文案三处传档案名。

不动（协议/产品标识或非头像作用面，点名留档）：

- StatusView 的 LabeledContent("Hermes") 显
  示的是服务端软件版本值（stats.hermes-
  Version），是协议/产品标识不是显示名；
- OneDayCore.AgentName.fallback 常量本体（回
  落值来源，收敛后仍由解析链消费）；
- ConnectView 连接前吉祥物（连接前品牌形象、
  非「已连接智能体」的露脸面）；Appearance-
  View 主题色板装饰图（演示主题色用、非头像作
  用面）；演示模式相关的「演示管家」分身名
  （另一角色，不随本档案改名）。

### 89.6 手势冲突排查结论

- **边缘右滑 vs 枢纽内列表纵滚**：边缘识别器只
  在左缘窄带起手且生死只认速度域——纵滚的速度
  形态在 shouldBegin 即被拒、识别器对该次触摸
  死亡，纵滚完整归列表；横向 begin 后不再设同
  时识别、纵滚让位。不重蹈 0.36.20 读位移判方
  向的假死（P-15）。
- **边缘右滑 vs 段内横向滑动**：枢纽四段内无
  swipeActions、无横向分页容器；唯一横移面是浏
  览器段（WKWebView 自有手势）——边缘手势在
  该段禁用，网页优先。
- **气泡右滑引用不受影响**：它在聊天页消息行层
  级（SwipeReplyGestureBridge），枢纽是其上的
  独立 fullScreenCover 呈现层——枢纽打开时触
  摸不达聊天页，枢纽关闭后边缘桥随视图销毁、
  聊天页手势原样。抽屉的左缘手势同理在 cover
  之下、不与枢纽边缘桥竞争。

### 89.7 复验口径（真机，照规格五条）

1. 胶囊点开＝整页呈现；左边缘右滑能返回、✕ 能
   关闭；枢纽内列表从内容区起手纵滚正常（与边
   缘返回并列第一条验）。
2. 分享面板里名片只有名＋头像＋域名，无任何密
   钥/完整地址。
3. 改名后：枢纽页头、胶囊、抽屉、总览、设置、
   状态、文件页、引用称呼同步新名；杀进程重开
   仍在。
4. 换相册图后各处头像同步、重开仍在；换回预置
   同样生效。
5. 四段内容、审批卡（含对话内就地卡与胶囊待批
   计数）无回归。

### 89.8 施工实录

独立 worktree（oneday-worktrees/hub-align-
03622）＋分支 feat/hub-align-0.36.22 与 0.36.21
收尾并行施工（用户 02:15 定版「CI 等待期不停
工」），基线 main 顶端 b3acfea。单测基线 857，
本包新增 AgentProfileTests＋HubEdgeSwipeTests
（Core 纯逻辑：名称仲裁/净化边界/host 剥离/预
置目录完整性/手势三表）。**CI 口径如实**：工作
流只在 push main 触发，本分支 push 不触发 CI，
构建与单测待主线合并回 main 后随正式出包跑，
本节不预填结果。

**CI 先红后绿（如实记）**：合并回 main 后首轮
CI run 42876149998 的 Build 步失败——唯一错误
在 AgentHubView.swift:227：`ShareLink(item:)`
对自定义 Transferable（AgentShareItem）报 no
exact matches，编译器候选只列 URL/String 两个
具体签名（一致性本体单独编译无报错）。修复＝
分享载荷改编译器原生支持的 URL 形态：名片图
渲染后落盘 caches/AgentShareCard/OneDay-Agent-
Card.png、ShareLink 按文件 URL 分享；载荷与红
线不变（仍只有名＋头像＋域名），纯文本兜底分
支原样保留。版本号不动（仍 0.36.22/89）。其后
第二轮 CI（run 42878183115）又浮出一处被首轮
失败遮住的错误：AgentProfileStore.init 在
@Observable 类里条件赋值 customAvatar 后即读
self.profile，definite-init 检查不过；修法＝
先算局部量再统一赋值、派生头像图也从局部量
算，语义不变。第三轮 CI run 42878867512 全步
success（jobs API 逐项核：Build/Unit tests/
Package/Upload 全 success），单测 870（基线
857＋本包新增 13）、0 失败；IPA 7,113,192 字
节、md5 39e6cc806e78dc458f83fb38f1afda75、解
包验 Info.plist＝0.36.22/89，已落
your_files/oneday-v0.36.22/。
## §90 右滑引用第四修：失败要求编排＋位移纯比值回归（0.36.23/90，2026-11-11）

### 90.1 裁决来源（先搜后改，本轮唯一施工依据）

三轮真机失败史：0.36.19 DragGesture＋onChanged 方向门压死纵滚；0.36.20 UIKit 桥祖先层装 pan、shouldBegin 读位移带 10pt 量级门，滚动恢复、右滑全灭；0.36.21 同桥改读 velocity（依据 SwipeCellKit PR #381），真机仍全灭，用户 2026-11-11 02:25 点选确认失败形态①「完全没反应、气泡纹丝不动」。

外部调研（报告 oneday-design-review/swipe-reply-arbitration-research-20261111.md，逐源核过）裁决：

- **死因不在判据量纲，在装载层级＋零编排**。逐一核过的生产实现——SwipeCellKit＝pan 装 cell 本体、Stream UIKit＝列表层＋failure-requirement delegate 三件套、LiveFront＝pan 装 UIScrollView 本体、Telegram＝借用隐藏 scroll view 自己的 pan、WWDC 2011-104 苹果范式＝UIScrollView 本体＋requireToFail——没有一把竞争 pan 装在滚动视图的祖先层且零编排；第 2、3 轮正是这个无先例组合，两轮死状相同且随量纲更换不变。
- **第 3 轮立论不成立**：SwipeCellKit 现行 master（SwipeController.swift:714-724）shouldBegin 仍是 translation 纯比值 `abs(translation.y) <= abs(translation.x)`、无任何量级门；velocity＋22.5° 角门只存在于 2020 年 PR #381 的 patch，合入状态未证实（GitHub API 403）。第 3 轮拿未证实合入的 PR 形态换掉了生产真形态。
- **苹果官方口径**（Event Handling Guide，TP40009541）：识别器之间默认没有求值顺序保证、默认互斥，定序必须显式声明（requireGestureRecognizerToFail: 等）；等待方停在 Possible 等判决，对方 begin 则它直接 Failed、对方 fail 它才开始分析。shouldBegin 是离开 Possible 的一次性闸门，答 NO 即当场 Failed——任何量级/距离判据放进 shouldBegin 在数学上过不去（第 2 轮死因与此吻合）。WWDC 2011-104、WWDC 2014-235 工程师原话均背书拿 scroll pan 做 failure requirements 编排。

修法＝报告候选 1（行本体装载＋scroll pan 显式 require(toFail:)＋shouldBegin 回归 translation 纯比值），改动面最小、生产实证最完整。候选 2（寄生宿主 pan）仲裁最稳但有未定案窗漂移补偿的手感债，列备选不动；候选 3（同时识别＋自取消）第三。

### 90.2 装载与编排（时序）

- **装载**：每行一个 UIPanGestureRecognizer，仍由零尺寸探针视图（SwipeReplyPanProbe，不参与命中测试）装到本行修饰符 ZStack 容器的宿主视图上——每行一个、位于该行自己的视图层级，不再向上爬祖先层装载。物理视图与 0.36.20/21 同为行容器，本轮不夸大此点：装载层级是否真在命中链上，由诊断打点 1（shouldReceive＋视图链）实证，见 90.4。
- **编排（本轮核心新增）**：Coordinator.orchestrateIfNeeded 在挂载后从行宿主向上找到包围本行的 UIScrollView，执行 `scrollView.panGestureRecognizer.require(toFail: rowPan)`；装载当刻层级未接全时不强求，updateUIView／didMoveToWindow 再请补齐；行回收换宿主时随 detach 清零重绑。行 pan 被移除后其失败要求随识别器消亡由系统按已失败处理，不留悬挂等待。
- **时序**：①手指落气泡：两识别器同追踪，scroll pan 因失败要求停在 Possible 等判决；②首次移动数 pt：行 pan 试图离开 Possible，shouldBegin 被咨询，纯比值当场定案（与量级无关，一次咨询即决）；③横向右滑胜：shouldBegin 允→行 pan Began，scroll pan 随即被置 Failed，本段触摸内列表绝不滚动，handler 以 translation 驱动位移；④纵向胜：shouldBegin 拒→行 pan 当场 Failed，失败要求满足，scroll pan 立即接管滚动（延迟仅首次移动一个事件量级，与系统自身方向锁体感同级）；⑤松手/取消：行 pan 只复位自身，全程未动 isScrollEnabled、无恢复动作、无残留状态。
- **handler 段全部原样**：52pt 触发（SwipeReplyMotion.triggerOffset）、76 封顶（maxOffset）、跟手扣锁定段（followedOffset，begin 时 translation 即锁定段、接管无跳）、箭头显形（revealProgress）、回弹动画、轻触觉、beginReply 共用入口一律未动；长按菜单五项、点图、贴底/回底、抽屉手势均不在本包动面。枢纽边缘右滑 HubEdgeSwipe 不在本包范围，未动（其速度域判据是边缘手势的独立裁决，不与本节混读）。

### 90.3 判据（公式与退役）

- 现行：`SwipeReplyMotion.shouldBeginPan(dx:dy:)` ＝ `dx > 0 && |dx| ≥ DrawerMotion.directionLockRatio × |dy|`。位移入参、纯比值、**无量级/距离分量**。比值常量 1.5 引 DrawerMotion.directionLockRatio（抽屉 S2）单源，本处不另写数字；上游 SwipeCellKit 的 1.0 松口径不采（与本仓 S2 单源冲突，且 90.5 的「斜向慢滑不误触」要更严的门）。
- 与 engages 的分工钉死在单测里：engages 带 10pt 锁定距离、是「接管跟手」的语义判据；shouldBeginPan 无量级门、是「一次性闸门」的生死判据。同一组 (3, 2)：engages 判 false、shouldBeginPan 判 true——0.36.20 把带量级门的判据喂闸门正是全灭病根，钉测 testShouldBeginPanHasNoMagnitudeGate 防其以任何形式回来。
- **速度域退役**：`shouldBeginPan(velocityX:velocityY:)` 整体删除，桥与测试同步改位移入参。退役理由＝90.1 第二条（立论不成立）＋三轮死状不随量纲变（死因在编排）。后续任何人想再把判据换域，先出示生产 master 级证据，不许再拿未合入 PR 当依据（P-15 铁律候选，定案后入册）。

### 90.4 诊断打点清单（临时件，随本构建保留一轮）

SwipeReplyDiagnostics（App 层新文件）＋桥内三处挂钩，代码内均标「下一轮撤」；落双通道（照听写诊断先例）：os.Logger（subsystem `site.didichou.oneday`、category `swipeReply`）＋UserDefaults 落盘环（键 `swipeReply.diagTrace`，最近 40 条带时刻，杀进程不丢）；不进任何正常 UI。

1. **shouldReceive＋视图链**：Coordinator 的 `gestureRecognizer(_:shouldReceive:)` 恒 true 只记——时间戳＋recognizer.view 的完整 superview 类名链。从未触发＝H3（装载点不在命中链上）。
2. **shouldBegin＋实测值**：进入即记当刻 translation（dx/dy）与 Core 判决。有 shouldReceive、无本条、且 scroll pan 有 began＝H1（被仲裁抢先）；本条出现且判 false＝判据问题（H2 位移版形态）。
3. **宿主 scroll pan .began 时刻**：watchScrollPan 给宿主 panGestureRecognizer 加只读 target（寄生打点、不改行为），与 1/2 同轴对时。

**读数发回路径**：用户真机复验（90.5）后，把落盘环内容经既有诊断通道回传——或由主线抓统一日志 `swipeReply` category 段；判读按上表三分支定案 H1/H2/H3，定案当天回填错题本 P-15 并在下一轮构建撤除全部打点（桥内挂钩、Diagnostics 文件、watchScrollPan 三件同撤）。

### 90.5 复验口径（真机）

并列第一条（缺一不可）：**从气泡起手纵滚正常，且右滑过半程（52pt）触发引用＋轻震**。另加一条：**斜向慢滑（约 45° 慢速右下拖）不误触引用、列表照常滚动**。其余沿 §85：长按菜单五项、点图全屏、贴底/回底、流式跟随无回归。复验时同步回收 90.4 诊断读数（无论成败都要发回——成功则作 P-15 定案证据，失败则按判读表定 H 分支）。

### 90.6 施工实录

独立 worktree（oneday-worktrees/swipe-fix-03623）＋分支 feat/swipe-fix-0.36.23 与 0.36.22 出包并行预制（用户 02:15 定版「CI 等待期不停工」），基线 main 顶端 71c8990（0.36.22 全部代码）。单测基线 870（分支内实数），本包 shouldBeginPan 速度域三测按位移纯比值重写（三测对三测）＋新增无量级门对照钉测一枚，预期 871、只增不减。版本五处同改 0.36.23/90 并 grep 验（残留 velocity 引用经查全属 HubEdgeSwipe 枢纽边缘手势，范围外未动）。**CI 口径如实**：工作流只在 push main 触发，本分支 push 不触发 CI，构建与单测待主线在 0.36.22 交付后合并回 main 随正式出包跑，本节不预填结果；合并注意事项见施工回报（预判冲突面：ChatView 未动、DESIGN 尾部 §90 与 §89 相邻追加、Project.swift 版本行与后续包版本顺延需复核）。
## §91 待发附件条居中续修：满宽 claim 必须落在被居中定位的那一层（0.36.23/90 续件，2026-11-11）

### 91.1 点题与定案

用户 2026-11-11 02:59 真机再报「添加的图片怎么还是居中」——0.36.19（§84.4）修过没生效，P-13 续案。主线逐层读码定案：`composerCard` 是 `VStack(spacing: 0)`、默认居中对齐，直接子级＝引用块 SmoothExpand、附件条 SmoothExpand、composerRow；`SmoothExpand`（OneDayDesign/Components.swift）只以 `.frame(height:)` 锁高、宽度随内容理想尺寸；附件条本体是横向 ScrollView，被上层量理想尺寸时按内容宽收缩——整条遂按单张图宽度被卡居中。0.36.19 的两处 `.frame(maxWidth: .infinity, alignment: .leading)` 加在 strip **内部**（ScrollView 本体与其内容），里层的 flexible frame 只能用被提议到的宽度，撑不开外层的收缩包装，所以没生效。

### 91.2 外部口径

SwiftUI 尺寸协商里，父按子的理想尺寸在栈内定位，里层 flexible frame 只能用被提议的宽度——「居中栈＋收缩包装」是通行坑，通行解法即在直接子层 claim 满宽／改栈对齐，不在最里层加 frame。本轮按此在直接子层落修。

### 91.3 修法（调用点级，SmoothExpand 语义不动）

- composerCard 内两个 SmoothExpand 调用点（引用块、附件条）各加 `.frame(maxWidth: .infinity, alignment: .leading)`：块本身满宽、内容靠左；strip 内部原有两处 frame 保留。
- 不全局改 SmoothExpand：全仓调用点共 4 处——本卡 2 处（本轮修）＋inputBar 的语音失败条／到限通知条 2 处（不在居中卡内、本轮不动）；全局改语义会波及后两者的宽度行为，调用点级修法把影响面钉在本卡。
- 引用块同层同病一并落修：它靠 HStack 内 Spacer 在宽提议下自撑满宽、先前未被报出，本轮同加 claim 后版式口径与附件条统一（满宽、左起、分隔线通栏），无回退面。

### 91.4 验收自查（代码层逐项，真机终验在用户）

1. **单图左贴**：附件 SmoothExpand 在卡 VStack 直接子层 claim 满宽 → strip 的 ScrollView 得满宽提议 → 内部 HStack 以 spacingSM 左内距左起，缩略图贴卡内左边距，不再按内容宽居中。
2. **多图横排可滚**：ScrollView 宽度即卡宽（不再随内容收缩或超提），HStack 内容超宽时横向滚动路径不变。
3. **删光收回**：isExpanded 判据（`!attachments.isEmpty`）与 SmoothExpand 高度动画均未动，删至空仍平滑收至 0 高。
4. **引用块两态**：引用块单独出现时 claim 满宽、quoteBar 左起＋分隔线通栏；与附件条同现时两块同口径满宽左对齐、自上而下贴合。
5. **失败／通知条不回退**：inputBar 两处 SmoothExpand 调用点与 SmoothExpand 本体均未改动，宽度行为原样。
## §92 选图多选：选图口与文件口对齐（0.36.23/90 续件，2026-11-11）

### 92.1 点题与定案

用户 2026-11-11 03:02 真机点题「选图片只能选一个」。主线查码定案：ChatView 选图绑定是单个 `@State photoItem: PhotosPickerItem?`，PhotosPicker 单项绑定天然单选；文件导入早就是多选（`allowsMultipleSelection: true`），数据侧 `attachments` 数组与附件条都支持多个——纯属选图口没开，下游零瓶颈。

### 92.2 修法

- 绑定改 `[PhotosPickerItem]` 数组（`photoItems`，selectionLimit 不设）；onChange 先把绑定清空再异步批量加载——清空触发的空数组回调被 guard 挡下，防重入（与旧单选「置 nil 再加载」同构）。
- `loadPickedPhotos` 按点选顺序逐个 `loadTransferable` 后经原 `appendImage` 入列（转 JPEG 等下游一律不动），顺序与点选一致。
- 大小口径与文件路对齐：单张超 20MB 只报不收、不影响其余，超限张数汇总一条 notice（「有 N 张图片超过 20MB，未加入待发列表。」）。

### 92.3 验收自查（代码层，真机终验在用户）

1. **多张一次进来**：数组绑定一次可选多张，onChange 一次拿到整组、逐个入列，附件条同现多张（§91 满宽左对齐下横排可滚）。
2. **顺序对**：数组顺序即点选顺序，串行 await 逐个 append，不并发乱序。
3. **超限单张被拦不影响其余**：超 20MB 者计数跳过，其余照常入列，notice 汇总明示张数。
4. **不重入**：清空绑定触发的第二次 onChange（空数组）被 guard 拦截，不会重复加载或清掉已入列附件。

### 90.7 交付回填（§90 右滑第四修＋§91 附件条续修＋§92 选图多选，同版 0.36.23/90）

提交链：分支顶端 9485d0e → 主线合并 8322888 → 6248dd9（§91 附件条居中续修）→ 1146c99（出包 CI 修一）→ 059bfee（§92 选图多选）→ 6983bdd（出包 CI 修二）。

CI 先红后绿（如实）：分支代码此前从未进 CI（工作流只认 main），合并出包连红两轮，均在 Build 步、均出自 §90 的临时诊断件 SwipeReplyDiagnostics 的 Swift 6 并发安全——run 42881267681：`shared` 单例与其 `static var watchedKey` 两处报错，修一以 @unchecked Sendable（NetworkPathObserver 同口径）＋稳定指针常量对治；run 42881845541：指针常量 UnsafeRawPointer 本身同属非 Sendable 再红一处，修二改 `nonisolated(unsafe)` 明示豁免（键只作关联对象地址、初始化后从不写）。终轮 run 42882608532 全步 success（jobs API 逐项核：Build／Unit tests／Package／Upload 全 success）。

单测 **871**（基线 870＋§90.3 无量级门对照钉测 1；§91／§92 均为视图层改动、无 Core 逻辑，未加测），0 失败。IPA 7,118,898 字节、md5 `0c956bdca59d643ea9802de8abf104ec`、解包验 Info.plist＝0.36.23/90，已落 your_files/oneday-v0.36.23/。§90.5 复验口径与 §90.4 诊断回收、§91／§92 真机终验均在用户。
## §93 真机反馈修复包：媒体格定尺＋枢纽边缘右滑改判（0.36.24/91，2026-11-11）

来源：用户 2026-11-11 03:10 装 0.36.22 真机回报两件——①对照 Muse 的 Files/Media 页，「咱们的」媒体格没定尺；②枢纽页「右滑不会退出」。两件均已读代码定案后施工。

### 93.1 件一·文件页媒体网格定尺（P-13 续）

- **定案**：`MediaCell`（FilesView.swift）旧形态把 `.aspectRatio(1, .fit)` 挂在内容 ZStack 本体上。网格列只提议列宽、高度未指定，而 `.fit` 在未指定维度上取**子视图理想尺寸**定案——ZStack 的理想尺寸由图片原尺寸/占位图标决定：未加载、视频、音频格的高度被 26pt 级占位图标带跑，小图格被自身原尺寸带跑，行内行间参差不齐。名义上有 1:1、实际没定尺（该行自 0.14.0 起就在，形态一直在、病也一直在）。
- **修法**：定尺改落在**无内在尺寸的形状层**——`Rectangle().fill(fieldFill).aspectRatio(1, .fit)` 承担 1:1（宽随列宽、高等宽），图片/占位/视频角标只作 `.overlay` 内的 ZStack 填充裁切，永不参与定尺寸。与 P-13「满宽/对齐必须落在被定位的那一层」同族：**尺寸约束必须落在承担定尺寸的那一层，内容理想尺寸不得反向参与定案**。
- **不动面**：MediaCell 全仓唯一调用点＝DeliverablesView 影音网格（Button label 内），点开查看器、`.matchedTransitionSource` zoom 转场源、长按 `.contextMenu` 删除均在调用点与 Button 上、本轮零改动；占位图标与视频角标（居中 play.circle.fill）位置口径不变；缩略图下载 `.task` 通道不变。

### 93.2 件二·枢纽页右滑不退出（P-15 同病复发）

- **定案**：`HubEdgeSwipeBridge` 首版（0.36.22，与右滑引用调研**并行施工**）在 `gestureRecognizerShouldBegin` 里读速度判方向——正是调研刚裁决掉的形态：生死关被咨询的时刻速度与位移一样未累积，`abs(vx) > abs(vy)` 在起手瞬间靠噪声定案、实测恒拒，识别器从未 begin。用的是被推翻前的旧口径，属同病复发，非新病。
- **修法**（照调研裁决的正道）：
  1. **生死关清空**：`HubEdgeSwipe.shouldBegin`（速度域）整体退役；桥的 shouldBegin 只余段位启用门（浏览器段禁用照旧，并同步落 `pan.isEnabled`，禁用段识别器根本不追踪）。shouldBegin 不再放任何量级/速度/位移判据。
  2. **handler 方向仲裁**：Core 新增 `HubEdgeSwipe.arbitration`（三态：undecided/follow/yieldToScroll）——begin 后逐帧按 translation 判：主导轴未过决定下限 8pt 不表态（handler 内连续判读，非生死关量级门）；过线后横向右滑主导（比值引 `DrawerMotion.directionLockRatio` 全 App 单源）判 follow 跟手；其余一律 yieldToScroll——识别器自置 `.cancelled`、offset 从未写过天然复位。定案后不改判。`followedOffset`/`shouldDismiss` 两数及常量沿用首版（松手时刻速度已累积，与生死关未累积量不是一回事）。
  3. **编排走调研候选 3（同时识别＋handler 仲裁），不用 require(toFail:)**：与枢纽内列表的滚动 pan 只对 UIPanGestureRecognizer-on-UIScrollView 开同时识别。纵向定案时滚动 pan 已同步 begin、自取消即无损让位（同一触摸继续滚）；横向定案时闪断正在追踪的滚动 pan（isEnabled 关开一次放掉当前触摸，WWDC14-235 技巧）。不用 require(toFail:) 的理由成文在桥与 Core 注释：按 Event Handling Guide 语义，被要求等待的一方在对方 begin 瞬间即被置 Failed，begin 后自取消救不回同一触摸——照字面套聊天第四修的编排，左缘纵滑首触必死、与本件复验口径直接冲突。此点为本轮对简报字面的唯一偏差，理由如上，请主线知悉。
- **钉测**：速度门旧测整表退役，换仲裁三测（下限未过不定案/横向跟手含比值边界/其余全让位），净 +2（871 → 873 预期，待 CI 实证）。

### 93.3 真机复验口径

1. 文件页影音段：图片、视频、未加载完的格子全部同宽同高正方形，滚动中加载完成不跳高。
2. 枢纽任意一段内从屏幕左缘右滑：页面跟手横移，位移过 90pt 或 40pt＋快甩松手即退出回聊天页；短滑松手回弹复位。
3. 枢纽任意一段内从左缘起手纵滑：列表照常滚动、不误退、不吃首触。
4. 枢纽浏览器段：左缘右滑不退出（禁用照旧）；✕ 关闭照常。

§93.5 交付回填（0.36.24/91）：合并提交 6a7ca6a（DESIGN 尾部冲突 §90.7 与 §93 两段并存）；CI 42884276125 全步 success、单测 0 失败；IPA 7,120,748 字节、md5 2d505ede2154a586a12dad59b87e3325、主线独立解包验 Info.plist＝0.36.24/91。真机复验待用户（枢纽右滑四条＋媒体格 1:1）。
## §94 对话渲染补全包：块级解析抽 Core＋全块型呈现（0.36.25/92，2026-11-11）

来源：chat-rendering-gap-audit-20261110（17 项矩阵：支持 4／部分 2／不支持 11）逐项销账。渲染对标定版（2026-11-11）：聊天流对标 Muse（克制、可读、代码块与引用卡主场），不学飞书消息卡。结构性改动：块级解析从 `MarkdownText` 视图层抽到 Core `MarkdownParser`（产 `MarkdownBlock` 结构、钉测把守），视图只按结构呈现；删除线由 Core `MarkdownInline` 分段补齐；代码高亮为手写词法器 Core `CodeHighlight`（**零第三方依赖**——审计 §3 的引库立项门不夹带，五类克制着色：关键词／字符串／注释／数字＋普通）。

### 94.1 审计 17 项逐项落点

| # | 语法 | 审计判定 | 本包落点 |
|---|---|---|---|
| 1 | 标题 | 部分（仅 #–###、##/### 与正文同大） | **补全**：1–6 级全认；字阶梯 22/20/17/15/13/13（.title2/.title3/.body/.subheadline/.footnote/.footnote＋H6 降墨分档），任一级不与正文 16 同大 |
| 2 | 粗体 | 支持 | 不动（行内系统解析＋strong 重映射原样保留在每种块的正文里） |
| 3 | 斜体 | 支持 | 不动（同上） |
| 4 | 行内代码 | 支持 | 不动（同上；行内码底 codeFill 既有口径） |
| 5 | 删除线 | 不支持 | **补全**：Core `MarkdownInline.segments` 先切删除线段（成对 ~~、代码段内不触发），视图层逐段解析后整段加 strikethrough（段内行内代码除外） |
| 6 | 引用块 | 不支持 | **补全**：连续 > 行合并成块，左竖条（装饰弱墨）＋填充面次墨正文；>> 起逐级缩进 |
| 7 | 列表 | 不支持 | **补全**：无序（•/◦/▪ 按层）／有序（序号右对齐定宽列）／嵌套（缩进÷2 定层、续行并入末项、空行松散列表不散块）；有序打断段落只认 1. 起手（「2024. 是…」防误伤，CommonMark 同款） |
| 8 | 代码块容器 | 支持 | 保留并升级：头行（语言标＋复制钮）＋横向滚动（长行不折行撑版）＋文字可选 |
| 9 | 高亮＋语言标 | 不支持 | **补全**：围栏信息串首词作语言标（归一化别名 js→javascript 等）；高亮五类词法，色板入 Palette 三新令牌（codeKeyword 紫／codeString 绿／codeNumber 蓝，浅暗双档实算对比 5.8–7.6:1 全过 4.5；注释走 inkSecondaryOnFill、正文 bodyInk）；覆盖 swift/python/js/ts/java/c/cpp/go/rust/shell/ruby/sql/json/yaml 等，未知语言只做通用分词不猜关键词；不变式＝token 拼回恒等于原代码（钉测） |
| 10 | 表格 | 不支持 | **补全**：表头＋分隔行成对才认；Grid 按内容定列宽、整体横向可滚；表头 bold；分隔走 GroupDivider（全 App 同一贯通发丝线几何）；列对齐由分隔行 : 定（左/中/右）；行单元格按表头列数补齐/截断、\| 转义不作分隔 |
| 11 | 链接 | 部分（无预览卡） | **本包不动**：链接预览卡是审计「包二」独立立项（一期端上 LinkPresentation 先行须规格拍板），不在本包范围；行内链接呈现保持 |
| 12 | 正文内嵌图片 | 不支持 | **本包不动**：审计「包三」独立小包，隐私默认值（自动加载 vs 点按）须规格一句话拍板，不阻塞本包 |
| 13 | 分割线 | 不支持 | **补全**：---/***/___（含空格分隔形态）成 GroupDivider 块 |
| 14 | 任务清单 | 不支持 | **补全**：- [ ] / - [x] 呈勾选框字形（square／checkmark.square.fill，已勾走 success 色），**只读呈现非控件**（与审计对 Muse 截图的观察一致：呈现层对齐即可） |
| 15 | 脚注 | 不支持 | **缓做不变**（已定版）：原文降级，不残留到炸版即可，本包未动 |
| 16 | 数学公式 | 不支持 | **缓做不变**（已定版）：不做 |
| 17 | HTML 内嵌 | 不支持 | **明确不做不变**（已定版）：标签纯文本直出，本包未动 |

销账：不支持 11 项中本包补 7（删除线／引用／列表／高亮语言标／表格／分割线／任务清单），部分 2 项中补 1（标题），余链接卡（包二）／内嵌图（包三）各有独立立项、公式／脚注／HTML 按定版不动。受益面：同一 MarkdownText 的全部消费点（聊天页／动态详情／技能页／服务端会话页）同步补全，回归口径见 94.4。

### 94.2 流式半截口径（解析层定版，视图对任意中间态结果确定）

- **未闭合代码围栏**：按已开围栏续渲成代码块直到文末（0.5.1 旧口径延续），带语言标；闭合到达后自然成整块，不吞字不炸版。
- **半截表格**：只有「表头行＋完整分隔行（列数对齐、每格纯 -/:）」成对出现才认表；分隔行没写完时整段按段落原文降级呈现，写完的下一帧才成表——不预判、不半渲、不闪符号墙之外的第三种形态。
- **半截表格行**：正文行单元格少于表头时补空、多于时截断（呈现不撑版）；不含 | 的行即结束表格。
- **未闭合行内标记**：未闭合 ~~ 不成段、按字面留在普通段（与系统行内解析对未闭合 ** 的处理一致）；**／` 同理走系统解析既有降级。
- **半截字符串/注释**（高亮层）：单行字符串未闭合先着色到行尾、块注释未闭合着色到文末，闭合到达后自然成整段；着色永不改字（token 拼回不变式钉测守）。
- 聊天主流式仍走 StreamingText 纯文本渐显、落定才换 MarkdownText（§32 取舍不动）；本口径辖的是落定渲染器被喂到任意中间态文本（动态/技能/会话页的长文、落定切换帧）时的确定性。

### 94.3 呈现细则

- 块间距沿用 VStack spacingSM；列表/引用内行距 spacingXS、标记与正文 spacingS——数值全出自 OneDayMetrics 梯队，无新裸值。
- 代码块底沿用 fieldFill＋codeCorner；语言标 .meta 小字次墨在头行左、复制钮右（旧版复制钮 overlay 位置改入头行流内，视觉等价、命中更稳）。
- 引用竖条 3pt 圆角矩形走 inkMuted（装饰非文字用途，合 G1 纪律）；引用正文与代码注释同走 inkSecondaryOnFill（填充面对比达标档）。
- 表格单元格与正文同 .callout；表头 strong 映射 bold；任务勾选框 .footnote 字形，未勾 inkSecondary、已勾 success。

### 94.4 真机复验清单

1. 把 94.5 样例整段发给 Hermes 让它**原样复述**（或在任一支持 Markdown 的会话里贴出），逐项对：六级标题大小递减、引用左竖条、两级嵌套列表圆点变空心、有序序号对齐、任务清单一空一方一勾、表格三列对齐（左/中/右）＋可横滑、代码块头行左小字语言标「python」＋关键词/字符串/注释/数字四色、删除线划掉「删掉」二字、分割线一条贯通发丝线。
2. 长表格（6 列以上）横滑不挤字；长代码块（50 行）纵向跟随消息滚、长行横滑。
3. 动态详情、技能页、服务端会话页各开一篇含列表/表格的长文，呈现与聊天页一致。
4. 暗色模式复看 1：高亮四色在暗面可辨、引用次墨可读。
5. 流式：让 Hermes 输出一段带代码块与表格的长回复，落定切换不跳版（StreamingText 纪律回归）。

### 94.5 复验样例文本（整段复制）

```
# 一级标题
## 二级标题
### 三级标题
#### 四级标题
##### 五级标题
###### 六级标题

普通段落，含**粗体**、*斜体*、`行内代码`，以及~~删掉~~两个字。

> 这是引用块
> 第二行引用
>> 嵌套引用

- 无序一级
  - 无序二级
- 回到一级

1. 有序第一
2. 有序第二

- [ ] 待办没做
- [x] 已办做完

| 名称 | 数量 | 备注 |
| :--- | :---: | ---: |
| 苹果 | 3 | 左对齐 |
| 香蕉 | 5 | 右对齐 |

​```python
def greet(name):
    # 打个招呼
    message = "你好，" + name
    return message
​```

---
分割线下面一段。
```

（注：样例中代码围栏前的零宽空格是防本文档自身围栏误合的排版手段，真机粘贴时去掉即可；实际发给 Hermes 时直接让它原样输出一段含以上元素的 Markdown 亦可。）

§94.6 交付回填（0.36.25/92）：合并提交 3711512（DESIGN 尾部冲突 §93.5 与 §94 两段并存）；CI 42886305837 全步 success、单测 0 失败（预期 912 以 CI 全绿为准）；IPA 7,171,652 字节、md5 53e6e3c0d5c3a57b1a49169704d2fa9a、主线独立解包验 Info.plist＝0.36.25/92。真机复验按 §94.4/§94.5。
## §95 手势与附件条定案修复包：右滑照 Stream 重做＋附件条移出量测层＋枢纽深度门控（0.36.26/93，2026-11-11）

规格唯一出处：`production-patterns-research-20261111.md`（Stream Chat SwiftUI 5.17.0-SNAPSHOT 与 Exyte/Chat 本地克隆逐行实读）。用户 2026-11-11 03:40 拍板按推荐施工。本包三件，均为「把自制件换回生产同构/系统件组合」：右滑拆 UIKit 桥、附件条拆量测层、枢纽把栈内返回还给系统 pop。

### 95.1 件一·右滑引用照 Stream 重做（拆桥）

- **整件删除**：`SwipeReplyGestureBridge.swift`（0.36.20 立的 UIKit 探针桥）、`SwipeReplyDiagnostics.swift`（0.36.23 临时诊断件，使命结束随桥退役；其三打点读数未及回收即随版本迭代失效，P-15 定案改以本轮构造替换＋真机复验为准，见错题本 P-15 收口记）。
- **新构造**（`ChatView.SwipeReplyModifier`，与 Stream `MessageItemView.swift:263-375` 的 `SwipeToReplyModifier` 逐项同构）：行内容 `.contentShape(Rectangle())`（命中域＝整条消息容器）→ `.coordinateSpace(name: "swipeToReply")` → `.offset(x: displayOffset)` → `.simultaneousGesture(DragGesture(minimumDistance: 30, coordinateSpace: .named("swipeToReply")))`。onChanged 只消费横向分量写 offset（Core `SwipeReplyMotion.dragOffset`：负事件弃/未达 30 归 0/达线 1:1 不扣段）；offset 越 60 在**拖动途中**当场触发 `beginReply`＋轻触觉（整段只一次，`hasTriggered` 把守），松手只以 MotionTokens.swap 动画回位、不再判触发。不设方向比值门、不做任何识别器编排——纵滑时横向分量≈0、offset 恒 0，纵滚完整归列表。
- **阈值单源**（Core `SwipeReplyMotion`）：起滑 `minimumDistance = 30`、途中触发 `triggerOffset = 60`（`shouldTrigger` 为严格大于，与 Stream `offsetX > replyThreshold` 逐字同义）、显示封顶 `maxOffset = 90`（＝触发线＋起滑线，Stream maximumHorizontalSwipeDisplacement 同式）；状态值可越封顶、显示层 `displayOffset` 钳制；箭头显形 `revealProgress` 分母换 60、武装态与触发同刻。
- **起始点排除区**（Stream `SwipeToReplyExcludedFrameKey` 同款）：新设同名 PreferenceKey＋`View.swipeReplyExcluded()`（背景 GeometryReader 在命名坐标空间发布帧），行修饰符以 `onPreferenceChange` 收集、Core `isExcluded` 按 `value.startLocation` 判定整段忽略。落点＝行内自有横向交互的两处：MarkdownText 代码块横滚区、表格横滚区（Stream 对应面为音频进度条）。其余行内子区（图片点开、链接、长按菜单）无横向拖动、不登记。
- **与第 1 轮（0.36.19 同族失败）的差异销账**（报告 §1.5 表）：起滑 6→30 ✓、onChanged 方向门→无门只取横向分量 ✓、松手触发→途中触发 ✓、封顶 76→90 ✓、无坐标/排除→命名坐标空间＋排除区 ✓，五项全销。
- **与 Stream 的自选偏离（明示）**：①触觉用本仓动效宪法既定 .light（Stream 为 .medium），落点口径不随构造迁移而改；②回位动画用本仓 MotionTokens.swap（Stream 为 interpolatingSpring 170/20），同理；③箭头沿用本仓左缘下层 ZStack 形态（Stream 为 overlay 右随式），呈现资产不借构造迁移重做。
- **保留不动**：触发落点 `beginReply` 全链、长按菜单「回复」、门控口径（纯图片消息不挂）。

### 95.2 件二·附件条移出量测层

- **改法**：attachmentsStrip 退出 SmoothExpand，作 composerCard 根 VStack 的**直接子级**（Stream `MessageComposerView.swift:496-506` 的 attachmentsTray 同位）；显隐改条件包含（`if !attachments.isEmpty`）＋`.transition(.opacity)`；分隔线随条同进同出（挂同一直接子级的小 VStack 内）。删尽三处 `.frame(maxWidth: .infinity, alignment: .leading)` 补丁：条本体、条内 HStack、0.36.23 加在 SmoothExpand 调用点的那层。条内只剩 `ScrollView(.horizontal) { HStack { chips } .padding(.horizontal, spacingSM) .padding(.vertical, spacingXS) }`。
- **不跳变论证（代码层）**：条高只在 attachments 空↔非空之间变，composerCard 根 VStack 挂 `.animation(MotionTokens.resolved(MotionTokens.swap), value: attachments.isEmpty)`——高度变化进动画事务后卡高与安全区留白同帧插值，不再靠 SmoothExpand 的「量内容理想高→回写状态→定高」回路；玻璃圆角半径由卡层既有 `onGeometryChange` 实测高连续函数逐帧跟随，无离散跳变源；条内容本身以 opacity transition 防闪现。取舍明示：放弃 SmoothExpand 式的逐帧裁剪展开，换取与生产构造同构的单一高度权威（根栈布局本身）。
- **引用块不动**：仍在 SmoothExpand＋其调用点 frame 保留，本轮最小范围（报告 §2.4 建议同治，本轮按施工单口径未动，登记为潜伏项——其内容近满宽、缺陷被掩盖，若日后引用块出现窄内容形态再同法治）。

### 95.3 件三·枢纽深度门控（C-1）

- **改法**（`AgentHubView`）：NavigationStack 绑 `hubPath: NavigationPath`（`@State`）；HubEdgeSwipeProbe 启用条件由 `segment != .browser` 改为 `hubPath.isEmpty && segment != .browser`——path 非空即探针 `isEnabled=false`（桥侧 didSet 同步落识别器本体、根本不追踪），系统 `interactivePopGestureRecognizer` 在全部推入页恢复原权。桥本体（HubEdgeSwipeBridge）与 Core HubEdgeSwipe 零改动，根页行为保持 0.36.24 现行口径。
- **兼容盘点**：枢纽内全部 NavigationLink（AgentHubView/OverviewView/HubCronSection/HubIdentitySection×3/HubMonitorSection/HubTaskSection）均为目标式链接、全仓 hub 面无 navigationDestination——绑 NavigationPath 与目标式推入兼容（推入同样追加进 path，`isEmpty` 即根页真值）。四段内容、深链回调（StatusView 的 onOpenSession 等走闭包不走栈）零改动。

### 95.4 测试增减账（如实记数）

- `SwipeReplyMotionTests` 整件换代：退役 24 条断言（shouldBeginPan 15＋engages 5＋旧 followedOffset 扣锁定段 4）、重写 8 条（shouldTrigger 3→4 条且语义改途中严格大于；revealProgress 5→5 条、分母 52→60）、新增 20 条（参数单源 4＋dragOffset 8＋displayOffset 4＋isExcluded 4）。本文件 8 方法/32 断言 → 9 方法/29 断言。
- 全仓测试方法数：基线 912（分支内 grep 点清）→ 913（净 +1）。本机 VM 无 Swift 工具链、未本地编译，构建与单测实数等主线合并后随 CI 实证，本节不预填结果。

### 95.5 真机复验清单

1. 聊天右滑：从气泡上起手**纵滚顺畅**（气泡纹丝不动、列表照常滚）＋**右滑途中**过约 60pt 当场弹引用条并轻震一次（不等松手）；从代码块/宽表格上起手右滑＝代码/表格自己横滚、不触发引用；斜向慢滑不误触。
2. 附件条：单图贴卡内左边、多图横排可滚且可继续加图；加图/删图时卡高平滑增减不跳；引用块与附件条同现时版式无回退。
3. 枢纽：状态页（及任意推入页）右滑能返回上一层；枢纽**根页**左缘右滑能退出（0.36.24 口径不回退）；浏览器段内右滑不误退；四段切换与开会话深链无回归。

§95.6 交付回填（0.36.26/93）：合并提交 cd8000f（DESIGN 尾部冲突 §94.6 与 §95 两段并存）；CI 42889197747 全步 success、单测 913（分支 grep 口径、CI 全绿为准）；IPA 7,169,351 字节、md5 ed7d50c0dc9538fba1582aedb2d667fd、主线独立解包验 Info.plist＝0.36.26/93。真机复验按 §95.5（右滑途中触发＋纵滚不受扰／附件条贴左／状态页返回＋枢纽根页退出＋浏览器段不误退）。
## §96 工作台账 App 半（源分支 feat/ledger-app，0.36.27/94 合并入；伴生 1.0.3 部署随后报批）

### 96.1 落点

- 枢纽「活动」段（HubSection.activity，段名保留）换真
  台账：新 `HubLedgerSection` 自持 `LedgerStore`，替换
  旧「会话+待办拼装」内容（拼装的视图代码已删；
  `AgentHubStore` 与 Core `HubActivity` 拼装代码保留
  不动——「最近动态」可能在别处复用，删改面收至视图
  层）。行的打开会话走既有 pendingChatSessionID 通道，
  与旧活动行同路（sheet 模式关页回对话、活动模式
  只置位）。
- 新文件：Core `LedgerModels.swift`（DTO）、
  `LedgerBoard.swift`（呈现纯逻辑）；App
  `LedgerBridgeClient.swift`（与 OneDayBridgeClient
  同构：自有 session、单钥、/api/oneday-bridge 前缀）、
  `LedgerStore.swift`、`HubLedgerSection.swift`、
  `LedgerDetailView.swift`。钉测
  `LedgerModelsTests` 31 条（基线 912 → 943）。

### 96.2 呈现口径（规格 work-ledger-design §3/§4.3）

- 页首计数行：进行中＝queued＋running 合计；待审批
  单列；数字只取桥 counts（summary 优先、列表 counts
  兜底），两面都缺才现算；全 0 给「现在没有进行中的
  工作」。collector 心跳龄分三档：≤30 秒正常、≤5 分钟
  弱标注更新时刻、其余（或无心跳）横幅「台账已停更 ·
  最后更新 HH:mm」且列表降透明度明示陈旧；summary.
  degraded 与断连另有横幅；失败条目不隐藏、陈旧不假
  转（四点超 Muse 原样落）。
- 行：类别图标盒（与看板任务同形）＋状态层叠加——
  进行中＝系统小号 ProgressView 转圈（偏差见 96.4）、
  排队小点、待审批盾勾、完成勾、失败红叹号、失联斜杠
  wifi、取消整行降透明；对账补记行带「补记」小标；
  副题按态：活跃态带已运行/已等秒级跳动（TimelineView
  1 秒、时刻以服务端 serverNow 校准时钟偏移求差）、
  终态带结束时刻或失败/取消原因分类、失联带最后确认。
- 下钻「工作详情」：概况（类别/来源/开始/结束/最后
  确认＋耗时）、工作量（toolCalls/subTasks 有才显）、
  失败原因全文、打开会话钮（link.kind=session 或
  sessionId）、事件时间线（detail 的 history，人话流
  转＋记录者＋对账纠正/证据冲突标）、技术信息区（原始
  枚举只进此区）。状态人话全量收敛 Core `LedgerText`
  单点：排队中/进行中/等待审批/已完成/失败/已取消/
  失联待核；未知枚举面显「状态未知」、原文只进技术区。

### 96.3 读面契约对账表（逐行核 companion 源码定版，防御归一列明）

| 面 | 实形（ledger.py／front server.py） | App 侧处理 |
|---|---|---|
| GET /ledger | {items, snapshotSeq, ledgerUpdatedAt, collectorHeartbeatAt, serverNow, counts}；items 剥 history | LedgerListResponse；counts 与 summary 同形 LedgerSummary |
| GET /ledger/summary | counts＋degraded＋collector{lastRunAt, sources, ambiguousDeviceCalls} | LedgerSummary 一形双吃：list 来的无 degraded→false、collectorLastRunAt→nil |
| GET /ledger/{id} | 裸条目（带 history）；不存在 404 | detail 404 → 「这条记录已不在」如实明示 |
| POST /ledger/report | runId 必填；terminal∈{completed,failed,cancelled}；failReason.category 须六类内 | LedgerReportRequest 按实形编码；**客户端已落、发送链挂点未接线**（96.4） |
| GET /api/companion/info | {companionVersion, apiLevel, minAppVersion, hermesUp, modules{}}，在面板鉴权之后 | 只作未上线文案旁证（App 单钥不保证可读）：探不到不翻案、探到版本点名版本；台账上线判据仍是 /ledger 404 |
| 条目字段 | id/kind/source/title/titleSource/status/startedAt/endedAt/lastEvidenceAt/origin/link{}/counts/failReason{category,excerpt}/evidenceLagging/lastSeq＋可选 sessionId/runId/correctedBy | 正形 camelCase 逐字对；防御归一：snake_case 同义键候选、时刻 >1e11 按毫秒 ÷1000（与桥 _ledger_norm_ts 同阈值）、counts 键缺省不填 0、failReason category 空→「原因未明」、未知 kind/source/status 保留原文 .other（面人话降级、技术区可查）、可选字段全缺给诚实默认 |
| 未验口径 | Dashboard sessions/messages 字段名、kanban 状态映射、write-gate /pending.records 均为桥侧防御归一 | App 只消费台账统一形，不受影响；部署后以真数据复核一次 |

### 96.4 偏差与欠账（两条，明示）

1. 进行中指示：规格 §3.2 字面「来源 glyph 旋转」未
   采用——非圆形 SF 符号（消息气泡等）旋转读作晃动、
   语义不清；改系统 ProgressView 转圈，与状态同帧启
   停、Reduce Motion 自动降级，满足「真转、不假转」
   的判据。如用户真机不认可再回 glyph 方案。
2. report 挂点：客户端与编码钉测已落，但 ChatView 的
   run 开始/终局发送链未接线——接线点牵动发送主链
   （0.36.20 刚收口的断开专项面），主线合并时定挂点
   与开关；台账在接线前靠伴生采集器对账兜底成立
   （规格三源之一），不阻塞本包。

### 96.5 未部署呈现口径

伴生未部署/台账面 404 时段内显「台账还没上线」整面
（ContentUnavailableView：服务更新后这里会显示智能体
经手工作的完整记录）＋「重新检查」钮，段内每 10 秒
自重试、服务上线页面自活；401 等非 404 读失败如实
给错误文案不伪装未上线；已加载后断连保留旧快照＋
「台账暂时连不上」横幅，不清空、不造数。版本文件
本包未动，版号合并时定。

### 96.6 真机复验清单（部署 1.0.3 后）

- 一次真实对话运行：行出现、转圈真转、已耗时秒跳、
  完成后转已完成且页首计数回落。
- 审批挂起：行显等待审批＋页首待审批计数；已决后
  状态跟变。
- 杀 App 中途结束的运行：采集器对账后行落终态或
  失联（不永久假转）；对账补记行带「补记」标。
- 失败运行：行与详情如实显失败分类＋摘录，不隐藏。
- 下钻时间线与详情 history 一致；打开会话跳回
  对应会话。
- 伴生停机再启：段显停更口径、恢复后 10 秒内自活。

## §97 0.36.27/94 组合包：台账合并＋发送舱上方收一档＋抽屉纯系统朦胧（2026-11-11）

版本五处同改 0.36.27/94＋grep 验（Project.swift 四处＋设置页脚）。本包三件入册（97.1–97.3）；件四/件五完成账见 97.4（04:04 用户点名暂停→外部核查证实主线诊断→以 0.36.28/95 续包出号）。

### 97.1 件一·台账分支合并账

- `feat/ledger-app`（顶端 70afc78）合入本分支（合并提交 b2d4144）。唯一冲突＝DESIGN 尾部节号：手势包 §95 保持不动，台账 §95 整段顺延改号为 **§96**（96.1–96.6 与内部交叉引用「95.4」两处一并改「96.4」），§96 标题的「待合并出号」同步改已合并口径。AgentHubView 两边文件面无交叉、自动合并（台账只动活动段）。
- 单测账：main 代码口径 913 ＋ 台账新增 31 ＝ **944**（合并后分支内 grep 点清）。构建与实数等主线合并后随 CI 实证，本节不预填结果。
- 台账两条明示欠账（§96.4）**原样保留、本包不接线**：①进行中指示用系统 ProgressView 的偏差；②`POST /ledger/report` 发送链未接线（发送主链 0.36.20 刚收口，挂点等主线另定）。伴生 1.0.3 部署不在本包，随后另行报批。

### 97.2 件二·发送舱上方留白收一档（用户 03:48 点题「输入框上面有点大，小点就行」）

先量后改。稳态（无回底钮/无错误条/无提示条）下「最后一条消息底 → 发送舱卡顶」纵向链逐项现值与改法：

| 环节 | 改前 | 改后 |
|---|---|---|
| 消息列表 `.contentMargins(.bottom)` | spacingS＝8 | **spacingXS＝4** |
| `.safeAreaBar(edge: .bottom, spacing:)` | 0 | 0 |
| bottomBar VStack（稳态只剩 inputBar 一个子级） | 0 | 0 |
| inputBar `.padding(.top)` | spacingS＝8 | **spacingXS＝4** |
| inputBar VStack spacing ×2（失败/通知两层 SmoothExpand 折叠高 0、spacing 照计） | 8×2＝16 | 16（不动） |
| **合计** | **32** | **24** |

- 收幅 −8：施工口径为约 4–6，两处指定钮（列表底 contentMargins、卡上外距＝inputBar 顶 padding）均为令牌一档 4pt、合计 −8，超 sizing 2pt——如实记账；两钮独立，真机若觉过紧回任一钮即回到 −4 档。
- 不动：卡内行高、`.scrollEdgeEffectStyle(.soft)` 边缘效果、键盘跟随结构、inputBar 底 padding。`BottomFollow` 落定误差注释的口径数字同步对齐（contentMargins 8→4、正常误差约 17→13，复贴阈值 24 不动、逻辑无涉）。

### 97.3 件三·抽屉朦胧改纯系统路线（用户 03:54 拍板）

- **注册**：`drawerBottomBar` 改挂名单 ScrollView 的 `.safeAreaBar(edge: .bottom)`（与聊天页 bottomBar 同挂法）；名单 `.scrollEdgeEffectStyle(.soft, for: .bottom)` 保留，朦胧由系统在注册栏高内发放。底条三件本体（齿轮/搜索/新建玻璃件）不动、不给注册 bar 自加 background（WWDC25-323 口径）；落点不变（条底 padding 4、停 indicator 线上方 4pt）。
- **整套删除**：手排霜层（`ultraThinMaterial` Rectangle 高 96＋`LinearGradient` mask 上透下实）及其 Reduce Transparency 实色分支、ZStack 浮置底条、名单 `.ignoresSafeArea(edges: .bottom)`。
- **末行避让**：手排 `.padding(.bottom, 84)` 退役，改由注册留位（条高 68＝顶 padding 12＋件高 52＋底 padding 4）＋ `.contentMargins(.bottom, spacingS＝8)` 承接——末行滚到底停在底条上方 8pt、不被压。
- **不动**：顶部标题浮层与名单 `.contentMargins(.top, 70)`（0.36.5 定版）；面板底 `drawerBackdrop` 及其 TransparencyFallback 实色回退（面板材质本路、与底条无关）。
- **两态一致性**：搜索态（drawerSearchList）与普通态（drawerNavList）共用同一 ScrollView 与同一注册，逐一过毕、无第二挂点。
- **Reduce Transparency 口径**：边缘效果是系统效果，开启减透明时系统自动提高其不透明度、无需手排回退；霜层时代的实色回退当年防的是「手排 mask 淡出段不受系统增不透明管辖、末行透过霜层与底条字叠读」——注册路线下不存在手排淡出段，病源随构造消失，故回退随霜层一并删除（错题本 P-17 已补追记）。

### 97.4 件四/件五完成账（暂停→外部核查→恢复施工，随 0.36.28/95 续包出号）

经纬：两件于 2026-11-11 04:04 经用户点名暂停（「确定吗？要不要再确认一下？尽可能用原生，apple 设计没有说吗？论坛没有人遇到吗？」），草稿停在 worktree 未提交；主线按「改前先搜」做外部核查（`~/workspace/oneday-design-review/fix-verification-check-20261111.md`，只采一手/可指认原文），三题裁决均证实主线诊断，用户回令后恢复施工、逐行复核草稿与裁决无冲突，本包版本号升 0.36.28/95（五处同改＋grep 验），件四/件五与本节记账分笔提交。**状态：两件均已修待真机验（复验口径见 97.5 第 4/5 条）。**

**件四·附件条居中真定案（核查题一，裁决：主线诊断成立）**：
- 机理全链：①`VStack` 默认对齐即 `.center`——Apple 官方教程《Building layouts with stack views》原文「When you initialize them with default parameters, stack views center align their content」，公开接口签名 `init(alignment: HorizontalAlignment = .center, …)` 同证；条的包装 VStack 与卡根 VStack 均未写 alignment、两层皆 .center。②横向 ScrollView 在未定宽提议下只报内容理想宽——fatbobman《Mastering ViewThatFits》：「ScrollView: If the ideal state axis is the same as the scrolling direction, it shows all child views without scrolling, ignoring the parent's proposed size.」两图内容宽≈124pt，窄条遂被两层父栈居中。完全同形工例无记录（核查如实标注），governing 规则有 A/B 级原文。
- 满宽 claim 是社区通行解（核查题一③）：tutorialpedia 列为 Solution 1「The simplest fix is to force the content container (e.g., `VStack`) to expand horizontally using `.frame(maxWidth: .infinity)`」；fatbobman 截断修复指南在 ScrollView 内同用 `.frame(maxWidth: .infinity, alignment: .leading)`。
- 对旧调研的修正（核查题一④，Stream 源码实读）：Stream 的 `MessageComposerView` 同为默认 .center 的 `VStack(spacing: 0)`、attachmentsTray 无任何满宽 claim——它不居中不是因为 tray 有 claim，而是**宿主链顶端就给出了确定的满宽提议**（composer 子树挂在被提议满宽的根容器、兄弟输入行是宽度扩张型子项）。本仓条的提议在到达前被收成未定宽；给包装层补 claim 即在本地制造同一确定满宽提议，与 Stream 的实际成因不矛盾。`production-patterns-research-20261111.md` §2.3 的「元凶＝SmoothExpand 量测层」单一归因就此作废（移出量测层保留、与生产构造同构、无回退理由）；0.36.19/0.36.23 两轮挪 frame 落空的真因同此一链（claim 分别加在条内部与 SmoothExpand 调用点、都没落在被居中的包装层上）。
- 落法：条的包装 VStack（条＋分隔线，ChatView.swift 约 2545 行）补 `.frame(maxWidth: .infinity, alignment: .leading)`，与同卡引用块 SmoothExpand 的现行 claim 同款；条本体、分隔线、transition、卡根 animation 零改动。原 §95.2 注释已就地订正（0.36.27 订正注）。

**件五·枢纽右滑整桥退役＋根页 SwiftUI 边缘拖（核查题二＋题三，裁决：均证实）**：
- 深度门控失效定案（题二）：`NavigationStack(path:)` 的绑定不追踪目标式 `NavigationLink(destination:)` 推入、只追踪值式（value＋navigationDestination）——WWDC22《The SwiftUI cookbook for navigation》讲稿：「The path here is a collection that represents all the values pushed on the stack. NavigationLinks append values to the path.」（新式链接呈现的是值）；生产库 NavigationSplitStack 文档明文：「A link that constructs its destination view directly does not update the router path.」本仓枢纽 8 处链接全为目标式、全仓无 navigationDestination，故 hubPath 恒空、0.36.26 的 C-1 门控自始至终未生效过。（Apple 文档中「destination-based links do not update the path」逐字句无记录，核查如实标注；结论立于框架定义＋多源明文＋本仓可观测形态三合。）
- 探针挡 pop 定案（题三①，机制层）：Apple《Event Handling Guide for iOS》——识别器间默认互斥、shouldRecognizeSimultaneouslyWith 默认 NO、无编排时胜负不保证；祖先层探针与栈内 interactivePopGestureRecognizer 同链竞争、能抢先吃掉左缘滑动（同族实证：HidingNavigationBar 生产修法即给竞争方加 require(toFail: pop)）。与本仓完全同形的公开报告无记录（核查如实标注），裁决立于官方互斥规则＋同族实证。探针本体另有命中链病嫌疑（挂 ZStack .background 的 representable，四轮真机从未成功退出根页），整桥退役后不再追。
- 根页退出的原生路（题三②）：fullScreenCover **没有任何系统自带的滑动关闭手势**（通行做法第 1 位＝只用 ✕ 关闭按钮，即现行已有）；第 2 位＝DragGesture 起始/位移门控＋dismiss() 的纯 SwiftUI 原生件组合（社区通行折中、非跟手揭示）；第 3 位 UIKit 边缘 pan＋百分比驱动转场未采（离开原生件、维护面最大）。本包取第 2 位，参数与聊天右滑引用同族单源（后者 0.36.26 已真机证明）：根内容挂 `.simultaneousGesture(DragGesture(minimumDistance: 30, coordinateSpace: .global))`，Core `HubEdgeSwipe.shouldTrigger` 判读＝起始点落在左缘 28pt 内＋横向位移途中严格大于 60 即 dismiss、整段只触发一次（视图层旗防重入、松手复位），浏览器段排除（网页横移手势优先，与退役探针的段位门一致）。挂点在栈根内容本体——推入页覆盖其上、触摸不达，「仅根页生效」由挂点天然成立。
- 落法：`HubEdgeSwipeBridge.swift` 整件删除；AgentHubView 拆 path 绑定改无参 `NavigationStack`（栈内页右滑返回全归系统 pop，与设置子页同机制）、探针挂载与 edgeOffset 跟手位移一并删除；Core `HubEdgeSwipe` 由桥判据（arbitration/followedOffset/shouldDismiss 及速度/比值表）重写为阈值小件（edgeWidth 28／minimumDistance 30／triggerTranslation 60＋isEdgeStart／shouldTrigger 两条纯判读），`HubEdgeSwipeTests` 换代（旧 5 法退役、新 5 法钉阈值单源与触发表，方法数持平、单测预期 944 不变）。全仓 grep：探针类型、旧判据符号、hubPath/edgeOffset 零代码残留（仅沿革注释提及）。

### 97.5 真机复验清单（件一至五）

1. 台账（部署 1.0.3 后）：枢纽活动段页首计数与进行中真转、已耗时秒跳、下钻事件时间线；未部署时整面「台账还没上线」口径成立、段内自重试自活。
2. 发送舱上方：短消息贴底停住，末条与发送舱之间的空带比 0.36.26 收小一档且不贴死；键盘升起/收起跟随无回归。
3. 抽屉：名单滚到底——末行停在底条上方不被压；底条下方朦胧直达屏底（无手排霜层时代的 96pt 霜带）；齿轮/搜索/新建点按与搜索过滤如常，搜索态底条与朦胧同口径；顶部标题滚动透字形态不变；开 Reduce Transparency 时底条不透字叠读。
4. 附件条（件四）：加一张图——缩略图贴卡左起、不再居中；多图横滚如常；引用块同卡形态不回归。
5. 枢纽右滑（件五）：状态页等任一推入页右滑能返回（系统 pop）；枢纽根页左缘起手右滑过线即退出（页面中央起手的横拖不误退）；浏览器段右滑不误退；枢纽内纵滚从左缘起手不受扰。

## §98 热修包 0.36.29/96：附件条第五轮＋首句消失自愈＋文件真发送（2026-11-11，插队包）

版本五处同改 0.36.29/96＋grep 验（Project.swift 四处＋设置页脚）。诊断依据：`~/workspace/oneday-design-review/attachment-tray-round5-diagnosis-20261111.md`（三题定案）与 `file-upload-contract-20261111.md`（文件契约实测冻结，用户 04:34 亲批、04:52 冻结）。频道包（0.36.29 原号）顺延。

### 98.1 件一·附件条（P-13 第五轮，范畴错误定案）

- **§97.4 件四的「真定案」作废**：0.36.28 真机复验仍居中。第五轮诊断定案——四轮全灭的共同死因是**范畴错误**：条的横向位置由父栈（条＋分隔线包装 VStack）**自身的 `alignment:` 参数**决定，该参数四轮一直默认 `.center`、从未被改；四轮改的全是 `.frame(maxWidth:alignment:)`——frame 的 alignment 只决定「被修饰视图在 frame 内怎么放」，管不到栈内子视图。Stream/Exyte 不居中的真因亦复核：两家的条直挂根栈、无包装栈这一层（诊断报告题 A §3）。
- 落法（一处）：包装栈改 `VStack(alignment: .leading, spacing: 0)`（ChatView.swift 约 2553 行）；第 4 轮挂在包装栈上的 frame claim 经定案属无效修饰、一并删除。条本体、HStack、卡根栈零改动（报告「不要再动的」清单全守）。
- 错题本 P-13 同步订正：现行「真定案」条（第 4 轮口径）作废标注＋新定案条（见错题本续案五）。

### 98.2 件二·首句消失自愈（题 B，等级中）

- 定案边界（诊断报告题 B）：服务端没丢——问题会话 `oneday-side-9fcba1db…` 存档里 user「你好」（id 899）完好；丢失在 App 本地呈现层。发送/落盘/导入/落定四链静态逐行排除，剩余嫌疑收敛到「新建旁聊＋线程切换＋首发同瞬间」的本地时序缝，**未证死**（等级中）：能确定的边界是「服务端有、App 显示线程没有、已知链路都不删」。
- 修法（自愈式，不赌竞态）：落定时已拉取的 transcript 为锚做对账补缺——Core `RunTranscriptSettle.missingUserMessages`（内容去空白＋时间窗 600s、按时间序贪心配对、同文重复靠配对消耗区分；hidden/空白行不作锚；**只补 user、助手条目永不补造**）；App 在 `settleRunFromTranscript` 拉到 transcript 后、段落定之前调 `healMissingUserEntries` 补回呈现层（createdAt 以存档时刻为准）。发送链、落盘删除面不动。
- 留证：补缺发生时经 `ChatDiagTrace` 记一条（会话 id＋补回条数，Logger＋UserDefaults 快照双写、沿听写诊断口径），供回收一轮后升格定案或排除时序说。
- 钉测 +5（RunTurnTests 对账组：缺条补回/无缺不动/助手不补造/同文时间窗/hidden 与空白跳过）。

### 98.3 件三·选文件静默失败改出声（题 C①）

- 定案断点：`loadPickedFiles` 首行 `guard case .success = result else { return }` 把 `.failure` 静默吞掉（iCloud 未下载文件、第三方云盘提供方出错时系统回 Error 而非 URL）——全函数唯一无声出口，与「选了没反应」精确吻合。
- 落法：failure 分支改写 notice 人话（「这个文件没能读取，可能还在云端未下载到本机，请先在「文件」App 里把它下载到本机再选。」）＋错误原文经 ChatDiagTrace 落诊断面；success 空数组同处理（notice 出声）。**防线口径：该函数所有 guard 出口必须有声**——本轮逐一自查：failure ✓出声、空数组 ✓出声、读取失败 ✓原有 notice、超 20MB ✓原有 notice、成功 ✓入条即反馈，无剩余无声出口。

### 98.4 件四·文件真发送（题 C②，契约冻结后开放）

- 契约（实测冻结）：原预设端点 `/api/chat/file-upload` 本部署未启用（404）——**不用它、不提启用**。走现成通道：`POST 9119 /api/files/upload`（文件页已持的仪表盘会话同款，`performAdmin` 通道），JSON `{path:"attachments/<文件名>", data_url:"data:<mime>;base64,…", overwrite:true}`，回执取 `entry.path` 绝对路径；发送 run 的 input 文本尾逐个拼 `@file:<绝对路径>`（网关入站展开：文本全文内联、二进制给路径块供智能体自取；含空格/括号的路径按 `_format_ref_value` 规则引号包裹）。
- 落点：Core `FileSendAssembly`（落点路径/data_url/@file 引用/文本尾拼接/尾条消息拼装，钉测 +10）；HermesClient 新增解码版 `uploadAttachment`（与文件页 uploadFile 同端点同 180s 超时、只差解码回执；Demo 客户端同形回执）；ChatView send 链——sendTask 起手逐个上传攒回执路径、shape 定形后拼进尾条（引用只属本轮、不进本地落盘条目与历史重放）、3485–3492 一带「文件直发尚未开放」notice 退役。
- **失败必须有声且整条拦下**：任一文件上传失败或回执无落点 → 删本轮条目、输入与附件原样退回发送舱、errorMessage 点名文件＋人话原因（与链接失败同舞步）；不许丢下文件只发文本。选文件侧 20MB 闸保留（服务端托管路上限 100MiB，本轮不改闸）。
- 边界记账：服务端 `attachments/` 副本**无自动过期**，本轮只记账、不做清理策略，后续如需清理另立项。

### 98.5 单测与状态

- 单测 944 → **959**（+15：对账 5＋文件拼装 10；本机无 Swift 工具链，grep 点清、终判等主线合并后 CI）。
- 四件状态：均已修待真机验。复验口径：①附件条挂 1 图/3 图贴左（起点与引用块左缘对齐）、8+ 图横滚始端锚定、文件宽牌同验；②新建旁聊首发一句、回复落定后首句在列；③从 iCloud 选一个未下载文件——出声提示而非没反应；④选本地文件发送——智能体能复述文件内容（口令级验证），上传失败场景（断网选发）整条拦下且点名文件。
## §99 频道与对话整理包（方案 A 一期）：三层分类＋抽屉频道区＋Hermes 频道页＋全部对话页分段换代（0.36.30/97，2026-11-11）

版本五处同改 0.36.30/97＋grep 验（Project.swift 四处＋设置页脚；本包施工时自设 0.36.29/96、与插队的 0.36.29 热修包撞号，合并时统一改 0.36.30/97；本节原编号 §98 因热修包先行占用、顺延为 §99）。规格＝`~/workspace/oneday-design-review/channels-conversations-design-20261110.md`（用户 2026-11-10 20:02 拍板方案 A）；与规格冲突处以规格为准、本节逐条对账。**时序依赖已满足**：台账 App 半已随 0.36.27 合入、伴生 1.0.3 已部署（规格 §6「本包不得先于台账单独发版」成立）。**生产全量分类人工对账（规格 §9-6）是主线合并前置，本包未做、未碰生产**；施工验证只用本地构造数据（单测）。

### 99.1 Core 分类器（新文件 SessionClassification.swift）

- **规则链 R0→R9 逐条落点**（`SessionClassifier.classify`，命中即定）：R0 主线＝`SideChatClassifier.isMain` 双信号（与各名单面同一函数）；R1 合并桶＝`SideChatLink.isMergeBucket` 钦定两条（先于 R2——绑桶线程在分类侧恒只读特例，发送侧「按未链接处理」是 0.27.0 发送口径、两事分开）；R2 本地关联（入参 `linkedThreadSessionIDs`）＋例外谓词（有效来源非用户通道则不升级、分类跟随会话续判）；R3 `oneday-side-` 前缀（常量 `appSideSessionPrefix`，与 `SideChatLink.newSessionID` 生成式同源注释）；R4 `oneday-` 前缀余部（复用 `SideChatLink.ownSessionPrefix`）；R5 结构性系统源集合 {kanban, cron, cron_job, scheduler}；R6 平台源集合→`.channel(平台名)`；R7 {dashboard, cli}→`.channel("hermes")`；R8/R9 同归 Hermes 频道。
- **有效来源**：source 归一（去空白/小写/空归 nil）优先，缺失时以 session_key 第三段（平台段）回落（`SessionSources.sessionKeyPlatformSegment`，形如 `agent:main:<平台>:dm:<id>`，state.db 留底形态）。
- **R5 parent 分支未启用（如实）**：`parent_session_id` 不在 ServerSession 列表解码模型内，规格 §2 本就标「实测可得才启用」；§9-1 列表回执字段实测归主线发版前置，本包不依赖未证字段。
- **R8 前置闸守住**：自由形态 id（人类可读名/纯 uuid）在 Dashboard 形态实测（§9-2）出结论前默认归 Hermes 频道，未写死为系统——单测 `testR8APIServerFreeFormIDsDefaultToHermesChannel` 钉住此闸。
- **常量同源（规格 §2 施工约束）**：来源集合收敛为 Core 单一常量表 `SessionSources`（userChannels/structuralSystem/hermesSurfaces/platforms 四表）；`DrawerSideChatFilter.userChannelSources` 改为引用 `SessionSources.userChannels`（本体值一字不变、行为不变），单测钉两面等值。
- **频道注册表** `ChannelRegistry`：一期仅 Hermes 一条（id `hermes`、副题「在这台 Hermes 的其他地方（网页、接口）发生的对话」、图标资产 `LocalHermes`＝0.36.3 登记的本机服务定制图面，与 LocalServices 同款）；`descriptor(for:)` 已能为平台源派生描述（名走人话名表），行显与页面属二期。
- **分筐** `SessionClassifier.partition` 保入序出 `SessionPartition`（main/mergeBuckets/mine/system/channels 四筐＋频道 id 分筐）；Hermes 频道成员谓词含合并桶（`hermesChannelCount`＝普通频道行＋桶行）。分筐不声明 Equatable（ServerSession 本体只有 Decodable 口径）。
- **单测**：新增 `SessionClassificationTests` 29 法（R0–R9 逐条＋命中顺序 R0>R2、R1>R2、R3>R5、R2 例外三路、session_key 回落三路、归一、常量同源、分筐保序、成员谓词、注册表）；`DrawerSelectionTests` 补 3 法（§10.4-④⑤＋频道引用在非聊天表面休眠）。基线 944 → **976（+32）**，终判等主线合并后 CI。

### 99.2 选择政策加值（§10 落地）

- `DrawerCurrentObject` 与 `DrawerSelection` 各加 `.channel(String)`，`DrawerSelectionPolicy.resolve` 同步加分支——**在 0.36.7 既有政策上加值，不另起一套**（规格 §10.2 本包扩展口径）；优先级不变（表面 > 显式引用 > 落点派生）。
- **出处维护**：Core 新 `ChannelViewingOrigin{channelID, sessionID}`；AppState 加两通道——`pendingChatChannelID`（频道页点行先置标记、再走既有 onOpenSession 置 pendingChatSessionID）与 `channelViewingOrigin`（出处本体）。
- **ChatView 消费口定形**（consumePendingChatSession）：带标记→落出处、导入落点已定后对象引用置 `.channel`、首次收养（openServerSession 新建导入，返回值改三态 `.switchedExisting/.importedNew/.failed`）给 notice「已转入我的对话」一行（呈现层拼装、沿 D4 红线）；无标记→旧出处清零；打开失败→出处作废、对象引用按当前线程回派（不把胶囊挂到没在看的频道行）。
- **同步点收敛**：currentThreadID 变更点与 onAppear 初始同步改共用 `syncDrawerObjectFromCurrentThread()`——出处与当前线程关联会话对得上时维持 `.channel`（收养导入线程渲染期间不派生成 .side），对不上即清出处回普通派生。§10.4-⑤（收养后从旁聊区重进同一条→胶囊归旁聊行）靠抽屉旁聊行点按先行清出处成立；主线行点按同清。删除线程的「是否当前」判定补 `.channel` 态一路（正从频道看着的收养线程被删须通知 ChatView 置空，旧 .side/.main 两判覆盖不到）。
- **未动**：activeThreadID 消费面无新增（0.36.7 已退役口径不变）；底栏不在辖区（§10.2）。

### 99.3 抽屉频道区（§3 落地）

- 位置：管理行 → 发丝线 → **「频道」分区头＋Hermes 行** → 发丝线 → 旁聊区（面先于条）；显隐＝分类后 Hermes 频道会话数 ≥1（合并桶计入），整区（含其下发丝线）随空态一并收起。
- 数据源：复用开抽屉既有那一路拉取（`drawerServerSessions`，limit 100）现算 `SessionClassifier.partition`，**不新增拉取**；关联集走 App 层 `ThreadLinkage.nonMainLinkedSessionIDs`（三面共用派生：非主线线程的关联 id 集，主线判定走 Core 双信号）。limit 100 漏判边界沿规格 §8-5 登记（只影响呈现）。
- 行形态：导航行档（图标槽 28＋Body 17＋drawerRowHeight＋选中胶囊问单一政策），行尾 chevron；**不给计数徽标、不给最近时间**（§3.2：抽屉口径与全量不一致，挂数即假新鲜）；图标用注册表资产 LocalHermes（资产缺位时 SF 符号兜底分支只为注册表完备、一期不触发）。

### 99.4 Hermes 频道页（§4 落地，新文件 HermesChannelView.swift）

- 承载：全屏页（ContentView 与全部对话页两入口各自 fullScreenCover 呈现**同一个** HermesChannelView，不新造容器、不两套实现）；页头标题「Hermes」＋副题取注册表人话句（不出现 source 原值）。
- 名单：分筐 Hermes 频道成员（普通行＋合并桶行）按 startedAt 倒序统一重排（两筐各自保序、合并后按时间定序，§4.1）；普通行复用 `ServerSessionRow`（标题 resolvedTitle 管线经 titleOverrides→sessionTitles 同管理页口径、副题 humanSubtitle、长按四件与写后回读对账纪律不变）。
- 续聊与收养：普通行点按先置 `pendingChatChannelID` 再走宿主 onOpenSession（pendingChatSessionID 通道）；收养升层与 notice 在 ChatView 消费口（99.2）。页内无搜索。
- **合并桶特例行**：行尾小字标「旧合并记录」，**不挂长按菜单**（不走 ServerSessionRow，其本体自带四件，与只读口径冲突）；点开经值路由进 `ServerSessionDetailView(readOnly: true)`——详情页新增只读形态（隐藏删除区、零写请求），其余入口默认 false 行为不变。管理页对桶的既有警告链与删除闸未动。
- 空态：EmptyState「还没有从其他地方来的对话」＋来历说明一句。数据层 `HermesChannelStore` 分页拉全未归档集（limit 100×10 页，与管理页 fetchAll 同口径）＋标题素材预算 12。

### 99.5 全部对话页改造（§5 落地＋退役清单）

- 分段：主线（不变）／**我的对话**（分类 mine，置顶先行沿旧行序；默认落地段自 .station 改此段）／**频道**（频道总览：Hermes 行＋会话数小字——本页分页拉全口径、数可信，与抽屉不给数分工；点行进频道页）／已归档（全量减主线不变、不叠层标）／**系统**（筛选开出时末位；分类 system 全量行＋清理区）。
- **系统筛选**：分段控件下方一行 Toggle「显示系统运行」，@State 默认关、**不落盘**；关时正处系统段回落「我的对话」。系统段行可多选批量（排障真动作），行上不叠「系统运行」标（本段本身即系统）。
- 清理区（prune 两段式）自旧站内段移系统段底部，其余机制一字未动。
- 批量面变化：可选段自（站内/已归档）改（我的对话/系统/已归档）；合并桶已不在任何可选段内（只在频道页只读呈现），批量警示的 selectionHasMergeBucket 恒假、代码保留不动（管理页单行面警告链不在本包变更面）。
- **退役清零**（规格 §5.3）：`Segment.station/.external` 及「站内」「通道未开通」文案、`stationSessions`、「全量减主线」分类口径、`externalContent` 空态、站内段清理区挂载点、默认段 .station——全仓 grep 仅余沿革注释。服务端搜索不变（跨层全量、副题带来源标签）。
- 本页新增 `@Query threads` 供分类关联集（三面同一 ThreadLinkage 派生）。

### 99.6 与规格的偏差与未决项（如实）

1. **§9 实测清单（1/2/3/4/5）未做**：本包不碰生产（任务书明示）；R5 parent 分支、R8 自由形态最终归属、sidebar 端点交叉校验都等实测结论，其中 §9-2 是 R8 的前置闸（未过前默认频道已守住）、§9-6 生产全量分类人工对账是主线合并前置。
2. **频道页名单排序**：规格 §4.1 只说 startedAt 倒序「与管理页服务端序一致」；分筐后两筐合并的相对序无从复原，本包按 startedDate 显式倒序重排（与服务端序同果）。
3. **收养 notice 的呈现面**：规格只说「给一行 notice」未定落点；本包落 ChatView 既有 notice 条（与模型回落提示同一呈现面），首次收养（新建导入）才给、切既有线程不给。
4. **二期扩展位只留未做**（规格 §7）：外部频道行与镜像页（注册表已备派生）、跳回原应用深链、频道未读计数、系统行反查台账。服务端分类字段/接口未动、分类结果未落库、合并桶本体零写——均守规格「明确不做」。
5. **手势面零新增**：本包未加任何手势/手势桥（频道页与各段全走系统 List/Button/NavigationLink 原生件），全面原生令无待批项。

### 99.7 真机复验清单

1. 抽屉：Hermes 频道有存量时管理行下出现「频道」区＋Hermes 行（图标为定制图面、行尾 chevron、无计数）；频道为空时整区不显示、无空头残留。
2. 频道页：名单按时间倒序、副题来源标签人话；普通行点开续聊后回抽屉——该会话已进旁聊区、频道名单刷新后该行消失；首次收养时聊天页有一行「已转入我的对话」。
3. 合并桶：频道名单内带「旧合并记录」小字；点开只读（无删除区、无续聊入口）；行上长按无菜单。
4. 全部对话页：默认落「我的对话」段，只见出生/收养在身的会话（晨报/探针/验收类不在此段）；「频道」段 Hermes 行计数与频道页名单条数一致；开「显示系统运行」出「系统」段（机器会话＋清理区在段底），关掉回落且下次进页默认仍关。
5. 选择胶囊五场景（§10.4）：①主线②旁聊③非聊天表面④从频道看会话时只有频道行带胶囊（主线聊天行、旁聊行皆无——哪怕该会话已收养、在旁聊区也有行）⑤收养后从旁聊区点开同一条，胶囊归旁聊行。
6. 回归：抽屉旁聊行显过滤（kanban/平台关联线程不进抽屉）与 0.36.7 三场景胶囊口径不回归；管理页搜索跨层命中如常；已归档段与批量/恢复如常。

### 99.8 合并前置收尾（2026-11-11）：合 main＋改号＋对账回令＋规则收紧三处

- **合并与改号**：main（0.36.29/96 热修包，顶端 eab6e1d）已合入本分支。冲突两处：①版本撞号——本包施工时自设 0.36.29/96 与插队热修包同号，合并后统一改 **0.36.30/97**（五处同改＋grep 验、版本位旧号零残留）；②本节原编号 §98 与热修记账 §98 相撞——热修 §98 原样不动，本节顺延为 **§99**（小节号 98.1–98.7 与节内交叉引用同步顺延）。
- **对账结论（§9-6 已回）**：生产全量 54 条逐条人工对账毕（报告 `~/workspace/oneday-design-review/channels-classification-audit-20261111.md`）：主线 1／合并桶 2／我的对话 4／系统运行 19／Hermes 频道 28，**无阻塞合并的误分**（频道筐逐条来源可述、系统筐无一藏用户会话）；规则缺口 2 类（run_/api_ 机器铸造形未覆盖）＋潜在打架点 1 处（kanban 回落段 local），即下条三处收紧。§99.6-1 的前置状态更新：§9-1/9-3/9-5 已实测（§9-5「生成面未被正确覆盖」的缺口由 R4b 闭合）；§9-2 本体（Dashboard 建会话）与 §9-4（cron 造数）仍欠——须用户批准生产写操作后另行补测，在此之前其余自由形态默认频道的闸维持现行、不放宽。
- **规则收紧三处（Core `SessionClassifier`/`SessionSources` 纯函数小改）**：①新增 **R4b**（置于 R4 后、R5 前）：id 带 `run_` 前缀→系统运行（网关 runs 落形，点子/晨报/验收运行实测 5/5 全机器）；②同条 R4b：id 带 `api_` 前缀（下划线）→系统运行（静默流探针实测 2/2）——与 R8 的 `api-` 标准形（连字符）严格区分，钉测钉住两者不串；③`SessionSources.structuralSystem` 增 `"local"`：kanban 行 source 缺失时 session_key 回落段即此值，防机器行穿透 R9 落频道错显（存量未触发、防患）。
- **归属变化（新旧规则双复刻回对账表逐条验证）**：恰 **7 条**频道→系统——run_ 5 条（run_4ba38fe2…／run_2e593f5f…／run_152c80fc…／run_3792cfd2…／run_9a824d76…，对账明细 #42–46）＋api_ 2 条（api_1794331033_cd758152／api_1794331381_df931abd，#52–53）；其余 47 条归属不动，local 收紧对存量零变化。新口径总量：主线 1／合并桶 2／我的对话 4／系统运行 **26**／Hermes 频道 **21**。晨报/点子今后以 run_ 形新铸的会话自此直入系统段、不再往频道添条。
- **钉测**：`SessionClassificationTests` 29 → **33 法**（+4：run_ 判系统／api_ 判系统／连字符与下划线不串／local 回落判系统含 R2 例外同钉）；全包单测预期 976 → **980**，本机无 Swift 工具链、终判等合并后 CI。
- **真机复验补一条**（并入 99.7 口径）：全部对话页开「显示系统运行」——系统段应见 run_ 晨报/点子/验收运行条；Hermes 频道名单不再含 run_/api_ 机器条（21 条口径）。

## §100 热修包二号 0.36.31/98：附件条结构换代＋文件选择器换 UIKit 桥＋文件接入预检（2026-11-11，插队包）

版本五处同改 0.36.31/98＋grep 验（Project.swift 四处＋设置页脚）。诊断依据两份：`attachment-tray-round5-diagnosis-20261111.md`（P-13 五轮史，0.36.29 第五轮修法真机再证伪后立项）与 `file-picker-batch-diagnosis-20261111.md`（「点打开没有反应」外部核查置顶：LunWhale/minis-open 同形生产修复＋公认修法序；次节为逐文件/整批语义核查）。本包三件：附件条不再给 ScrollView 结构打补丁、整类换代；文件选择器弃 SwiftUI `.fileImporter` 换 UIKit 桥；文件接入链配套预检与汇总点名。

### 100.1 件一·附件条结构换代（P-13 第六轮）

- **退役**：`attachmentsStrip` 本体 ScrollView(.horizontal)＋HStack 删尽——五轮补丁（0.36.19 条内 frame／0.36.23 调用点 claim／0.36.26 移出量测层／0.36.28 包装栈 frame claim／0.36.29 包装栈 alignment）全灭，真机居中分毫未动；ScrollView 的量测/对齐纠缠整类随结构退役，不再有第六次在同一结构上挪修饰符。
- **新结构**：新 `AttachmentFlowLayout: Layout`（ChatView 内私有，与 StreamingText 的 TokenFlow 同构：sizeThatFits 与 placeSubviews 共用一份 arrange）——左起逐个排筹码、一行放不下换行、不滚动；筹码按理想尺寸自定位，左缘即条左缘，无滚动轴、无内容宽收缩、无栈对齐可乘之机。宽度认父级提议（满宽），提议未定宽回落单行内容宽。间距：横向 spacingS（与旧 HStack spacing 同值）、行距 spacingSM；条的横向内边距 spacingSM（与引用块/分隔线同一起点）、纵向 spacingXS 沿旧口径不变。
- **筹码零改动**：`attachmentChip` 本体一字未动——图片 54×54、文件胶囊外观、✕ 删除钮与 44 命中域/offset 补偿口径全沿现行；落位提议 .unspecified 与旧 HStack 一致。
- **包装层保留**：条＋分隔线的包装 VStack(alignment: .leading) 与分隔线形态不动（第五轮落点保留为层级卫生，不再单独承重）。
- **动画键扩**：卡根高度动画键自 `attachments.isEmpty` 扩为 `attachments.count`——流式行多行化后，加/删筹码改行数同样改变条高，须同进 MotionTokens.swap 事务插值；空↔非空仍是其中一档，原口径不回退。

### 100.2 件二·文件选择器换 UIKit 桥（新文件 DocumentPickerBridge.swift）

- **病灶**（诊断定案，等级高）：SwiftUI `.fileImporter` 在侧载设备类上 picker 呈现在正被拆毁的呈现上下文上、coordinator 已死、delegate 永不触发——勾选（Files 远程进程内 UI）照常、点「打开」（向宿主提交）无声、不关闭无结果无报错，与本机真机逐字同形（外部生产实证 LunWhale/minis-open e13e4b1：reported across TrollStore / Sideloadly / Xcode installs）。本仓接线再叠一层：Menu 动作同步置位、零延拍，与 Menu 收起同拍撞车。
- **桥形态**（照公认修法①全套）：`UIDocumentPickerViewController(forOpeningContentTypes: [.item], asCopy: true)`、`allowsMultipleSelection = true`；自当前最顶层 VC（沿 presentedViewController 链）呈现，绕开 SwiftUI coordinator；Coordinator 静态强持有到 picker 关闭（选定/取消回调内释放）；present 延一拍（Task @MainActor，避开 Menu 收起瞬间，minis-open DeferredPresentation 同口径）；didPick 回调先 dismiss 再把 URL 数组喂回 `loadPickedFiles(urls:)`。
- **删净**：ChatView 的 `.fileImporter` 修饰与 `@State showFileImporter` 一并删除（grep 验仅剩注释提及）；菜单「选文件」项改调桥。相册（.photosPicker）/拍照（CameraPicker）两路本轮不动——外部实证中该项目两路靠延拍即稳、本仓两路真机亦无此报。
- **asCopy 口径**：副本落在 App 临时区、属本 App 容器，读取无需安全作用域——旧链 `startAccessingSecurityScopedResource` 起停配对随之退役，`loadPickedFiles` 直读（注释已注）。取消路径无声收尾（用户主动取消非失败出口，P-18 有声口径不辖）。

### 100.3 件三·处理链配套（Core FileIntake＋loadPickedFiles 重写）

- **先查后读**：逐文件先 `resourceValues([.fileSizeKey])` 预检，超限免整份读入（旧链先把 82.8MB 整份读进内存才判闸、且在主线程同步执行）；预检取不到大小（`.unknownSize`）放行读入、读后以实字节同闸二次判。
- **闸值对齐**：App 侧单文件闸 20MB → **100MB**，与服务端托管上传契约对齐（file-upload-contract-20261111：POST /api/files/upload 解码后上限 100MiB 常量 `_MANAGED_FILE_MAX_BYTES`）。图片路 20MB 闸不动（图片走多模态 parts 内嵌、不经该契约，注释已注分工）。
- **汇总点名**：被拒（超限/读失败）不再逐个写 notice 互相覆盖只剩最后一个名——Core `FileIntake.rejectionNotice` 拼装：两类各成一句、名单 1 个直名/2 个并列/3+ 取前两名＋「等 N 个文件」；读失败另落 ChatDiagTrace 一条汇总（个数＋全名）。出口有声口径（P-18）保留：空数组明示。
- **Core 化与钉测**：新文件 `Sources/OneDayCore/FileIntake.swift`（`maxFileBytes`、`sizeVerdict(declaredSize:)`、`isOversized(byteCount:)`、`rejectionNotice(oversized:unreadable:)`）；新测 `FileIntakeTests` **13 法**（闸边界恰等/超一字节、nil 未知、零与小文件、实读二次判边界、汇总文案六形：空→nil／单超限／双超限／三超限折叠计数／单读失败／多读失败折叠／混合两句）。全包单测预期 980 → **993**，本机无 Swift 工具链、终判等合并后 CI。

### 100.4 真机复验清单

1. 附件条：挂 1 图贴左（起点与引用块左缘对齐）；挂 3 图同行左起；挂 8+ 图/多文件换行成多行、不横滚、行距均匀；删中间一张行列重排无跳位残影；文件宽牌同验贴左。
2. 选文件：附件菜单「选文件」点开选择器（呈现不卡 Menu 收起）、勾选后点「打开」——选择器关闭、文件入条；取消则无声返回、无 notice。
3. 大文件：选 >20MB 且 ≤100MB 的文件（如既往 82.8MB apk）应成功入条并可真发送；选 >100MB 文件被拒且 notice 点名；多选混合（正常＋超限＋云端未下载）时正常文件入条、被拒的汇总点名全员有账。
4. 回归：相册选图多选、拍照两路如常；引用块、发送舱高度动画（加/删附件时卡高平滑）如常。

## §101 文件页 v2（资料库层）：页级显示/排序＋双列网格卡＋文档阅读页＋类型适配菜单＋敏感边界（0.36.31/98 预制，源分支 feat/files-v2，2026-11-11）

版本五处同改 0.36.31/98＋grep 验（Project.swift 四处＋设置页脚）。规格依据：`~/workspace/oneday-design-review/files-page-design-20261110.md` §4＋§七补记＋两附记（2026-11-10 23:40 菜单按类型适配、2026-11-11 01:23 阅读页学飞书）。**节号说明**：§99 已由频道包（0.36.30/97，分类三层）占用、§100 已由热修包二号（0.36.31/98）占用，本节顺延 §101。本包自基线 eab6e1d 在独立 worktree 预制（CI 等待期不停工口径），与频道包无文件交叠（频道包动会话面、本包动文件面），合并时主线终定号位。

### 101.1 规格冲突裁决（回报已报备，合并前请主线过目）

1. **§4.7「行 ⋮ 两件（预览/分享）不动」vs 附记「条目菜单按文件类型出项」**：附记晚出、自称覆盖式并入且明列为本页 v2 验收项——裁附记胜：行 ⋮ 与长按（两段两态）同出 Core FileActionPolicy.menuActions 全集（预览＋类型专属＋分享/下载/删除）。
2. **DOCX 的复制文字/导出 PDF 不给**：附记举例把 docx 列入「可渲染出文字」类，但 iOS 无系统 DOCX 文字提取通道（QuickLook 只给缩略与预览渲染、不给文本），给即是附记本条下半句明禁的「不能用的灰项充数」。裁：Office 类（doc/docx/xls/xlsx/ppt/pptx 等）菜单只给预览/分享/下载/删除；PDF 给复制文字（PDFKit 可真提取）；文本类给复制文字＋导出 PDF。**此点与附记举例有出入，待用户/主线终裁**——若终裁要给，须另立服务端提取通道，不许摆灰项。
3. **§七「系统文件 ••• 只放上传两项」vs §4.6「写操作维持现行（上传/新建文件夹/删除）」**：裁 ••• 纯度优先，新建文件夹钮安放排序行右侧（同行还有方向钮），能力不丢、安放让步，已在本节记账。
4. **「页面分栏」（附记重定目标语）落实两处**：文件页双列网格＝页面分栏本体；阅读页内部落实为表格列宽策略＋窄屏横滚——阅读页正文在手机上单栏是正解，不硬造双栏正文。

### 101.2 施工清单

- **Core 新四件**：`SensitiveFilePolicy`（保护名 8＋.env 变体＋凭据词元/子串＋私钥扩展，key 走整词元防 monkey/keyboard 误伤；explanation 钉死规格原句）；`LibraryOrdering`＋`FileOpenHistory`（排序三义、上次打开本地表、7 天窗分组——§4.5 自有口径、注释明示不冒充 Muse 判定；与聊天双账切割声明写入注释：排序辅助、丢了不伤数据、非第二真源）；`DocumentReading`＋`DocumentTextKind`（md 直通 MarkdownParser、纯文本空行分段、CSV 成表归一、结构化文本代码块；html 故意不收——其「阅读」是 QuickLook 渲染成页）；`FileActionPolicy`（分类九档、菜单/阅读工具栏/失败页三套动作表全按类型出项，敏感全收回）。
- **Core 两改**：`DeliverableFileType.displayTitle`（去末扩展名，标题不带「.docx」尾巴）；`FileBrowserLogic.sorted` 加 `ascending:` 可选参数（默认 nil＝旧行为逐字不变，既有调用与单测源兼容）。
- **App 新三件**：`DocumentReaderView`（块式呼吸：块距 16＋标题前额外留白；引用块升高亮块＝浅底圆角＋左 accent 条；表格按内容估列宽 76…220＋整表横滚；代码块底面＋CopyButton；工具栏/失败页走策略表；含 FileTextExtractor 与 DocumentPDFExporter——CoreText 分页 A4、保文字不保像素版式）；`FileThumbnailStore`（图片 ImageIO 降采样、文档落临时文件走 QLThumbnailGenerator 首面、视频/音频回落类型面；NSCache 120＋磁盘缓存键含 mtime；并发闸 2；含 FileTypeFace 与 FileThumbnailView）；`FileOpenHistoryStore`（UserDefaults 键 files.openHistory.v1）。
- **DeliverablesView 改版**：右上搜索钮撤除→••• 玻璃圆钮菜单（组1 显示两项对号、组2 排序三项对号、组3 系统文件、组4 上传文件）；显示/排序 @AppStorage 持久化两段共用；搜索改下拉露出（onScrollGeometryChange 读偏移、阈值 -56 触发，**不新增任何手势识别器**——全面原生令）；文件段列表平铺/网格分组（§4.5）；网格卡落值＝边距 16/列距 12/行距 16/圆角 16/卡高 176（预览 112＋信息条 64）、卡上无 ⋮、长按出全集；影音段补列表态（56pt 缩略行）；打开分流＝图→查看器（zoom 源＝卡/格/行）、文本→阅读页、余→预览页，打开即记上次打开；聚合根新增 attachments「聊天发送」（0.36.29 副本落点——服务端无自动过期，本面呈现＋既有删除通道即其生命周期出口）；根散 deny 改引用 SensitiveFilePolicy.protectedNames 单源。
- **FilesBrowserView（系统文件）改版**：••• 只放上传两项（上传文件/从相机胶卷上传——相册走 PhotosPicker→Data→同一备料链，时间戳命名）；排序行＝排序键菜单（当前项对号）＋方向钮（默认名称升序，调 Core ascending）；新建文件夹钮同行右侧（见 101.1-3）；行副题改「类型 · 大小」（§七口径）；敏感行锁定形态（锁标记、无导航无菜单、点按出 explanation）；敏感名目录只收删除、导航照常逐行再判。
- **FilePreviewView**：敏感防御（不加载、只给说明＋知道了）；工具栏单下载钮→••• 菜单走 readingActions；失败页改 failureActions 按钮组。
- **上传单源化**：FileUploadControl 退役，抽 FileUploadPerformer（备料→预检→上传→回读对账）＋FileUploadPickerModifier（选件＋覆盖确认），文件页菜单与系统文件页共用；MediaCell 缩略改走 FileThumbnailStore（全尺寸解码退役）。

### 101.3 取舍与代价（如实记账）

- **下拉刷新退役**：与下拉露出搜索同为下拉手势、只供一主，搜索胜（规格 §4.2）；失败态给显式「重试」钮补位，collect 失败文案同步改「请稍后重试」。
- **影音列表行无时长**：/api/files 无时长字段，以「类型 · 大小 · 日期」代，不编造。
- **缩略流量代价**（规格 §五明示口径）：无服务端缩略端点，图片/文档首面都要先下原字节，靠双缓存＋惰性＋并发闸压；大文档首屏有等待，二期服务端缩略端点根治（须另行授权与算账）。
- **分享与下载到本地同走系统分享单**（全 App 既有口径，含「存储到文件」出口），菜单两项动作同路、文案分立。

### 101.4 单测与状态

- 单测 959 → **997**（+38：LibraryOrdering 9＋FileActionPolicy 12＋DocumentReading 7＋SensitiveFilePolicy 6＋displayTitle 2＋排序方向 2；grep `func test` 点清）。注：基线 959 为本包分支点（eab6e1d）口径；主线现行 995（频道包 +36 已合），合并后预期 ≈1033、只增不减，以合并后 CI 终判为准。本机无 Swift 工具链，本地未构建。
- 状态：**预制待合并、未出包**。真机验收点：••• 菜单对号态与持久化、下拉搜索露出/回弹收起、网格卡首面（PDF/Office 的 QL 缩略在真机文件类型上的可用率）、阅读页表格横滚与高亮块、系统文件敏感行锁定与相册上传、attachments 副本在文件段出现且可删。
- 错题本：本包无新定案坑（无平台行为新定案；DOCX 无文本提取通道是能力事实、已记 101.1-2 裁决），不续记。
## §102 抽屉对齐微包：组间发丝线显形＋频道行改平（对 Muse 抽屉对图，用户 2026-11-11 05:34–05:35 两图点题；版本合并时主线定）

用户给两图对照（OneDay 抽屉 vs Muse 抽屉）：Muse 分界＝小灰组标签＋整行发丝线双机制（选项卡↔空间、空间↔频道、频道↔旁聊组间都有线）；频道行与普通行完全同构（真实品牌图标＋名称平排，无卡片底、无箭头）。本包只动 DrawerView 名单面，两刀：

### 102.1 组间发丝线显形

- **查实**：线并非不存在——drawerDivider 自 0.19.0 起在三处组界都在（导航组↔管理行、管理行↔频道组、频道组↔旁聊组，频道区隐藏时为管理行↔旁聊组），几何为左右 drawerInset 20、高 1。但填充色 Palette.hairline 浅档 #EEEEF0 与抽屉磨砂底近同色（对比约 1.1:1），真机截图里三处线全不可见，与「组间无线」的观感一致——病在色不在结构。
- **落法**：drawerDivider 填充改挂 **Palette.separator**（UIColor.separator 语义 α：浅 (60,60,67,α0.29)，宪法 §3 定版的分隔单色、与全 App GroupDivider 同源同色，压任何面保持可辨）；几何零改（20 线、高 1、组标签保留）。分隔几何与分隔色全名单仍只此一种（宪法 §3）。
- **与任务书口径的出入（留痕）**：任务书点名 Palette.hairline——照其字面执行则线继续不可见、本刀落空，故按 Palette 令牌自家文档与宪法 §3 的分隔单色口径改挂 separator，请主线合并时知悉；若坚持 hairline 字面，等于接受组间线不可见。

### 102.2 频道行改平（与导航行同构）

- **卡片感三源查实**（对照 §99 落法逐项核）：①图标资产 LocalHermes 填满 30pt 图标槽，实色方块比导航行的 21pt 线形 SF 字形重一圈；②行尾 chevron（导航行/旁聊行均无）；③选中时 selectionFill 胶囊（此项与导航行同式、属同构应有之义，保留不动——Muse 选中行同有浅垫）。本行代码本体无卡片底/圆角/阴影，那些观感即由 ①② 与选中垫合成。
- **落法**：资产本体落 **字形档 21×21**（FrameworkIcon.drawerGlyphSize）居中于 30 槽内、与导航行字形同尺寸；**删 chevron**。行高（drawerRowHeight 58）、标题 Body 17、槽宽、选中胶囊、点按行为与目的地（onOpenChannel → HermesChannelView）全不变。改后本行与 drawerNavRow 构造逐项同构，余差只有图标来源（品牌资产 vs SF 符号，宪法 §4 品牌图标本分）。
- 管理行（管理全部对话）按任务书保留不动（其 chevron 是全名单唯一保留的一处「进管理面」示意，本轮不议）。

### 102.3 验证与范围

- 纯视觉改：无 Core 结构变化，不加钉测（单测增减 0）；本机无 Swift 工具链，终判等合并后 CI。
- 真机复验点：①抽屉三处组界（选项卡↔管理、管理↔频道、频道↔旁聊；频道区隐藏时两处）发丝线清晰可辨、深浅两档都成立；②Hermes 行与上下行同重同高、无箭头、图标与导航图标同尺寸观感；③点 Hermes 行仍开频道页、选中胶囊仍只归当前面。
## §103 模型包（0.37.0/100）：模型管理三层＋云电脑配置面＋进展胶囊（2026-11-11，预制分支 feat/model-pkg）

依据：model-provider-status-design-20261110（下称「三问档」）＋cloud-computer-product-design-20261110（下称「云电脑档」）＋2026-11-10 19:07 三层定调/19:50 凭据自助扩展/20:34 云电脑拍板。本包为 App 半：Core 四件＋客户端三件＋Store 两件＋UI 五处；服务端新面（渠道管理面、组合 meta 面）未上线处一律契约先行＋如实空态，不放假数据假按钮。

### 103.1 施工前实测（2026-11-11，只读，服务器内存 51%）

- **伴生 connections 契约在产可用**：GET /api/companion/connections 以 App 单钥 Bearer 回 200，记录含 box（simular_box、configured=true）与 vps_agent-1（用户先前建的、未配置）；POST 创建/credential/verify/disconnect 与 front 源码逐项对齐（凭据验活＋失败回滚在服务端）。云电脑配置面的数据来源即此，不新造。
- **网关渠道只读面未开通**：GET /api/companion/gateway-channels 回 404；New API /api/pricing（公开）只有模型定价与厂商、无渠道名/状态/优先级；渠道管理 API 须管理员凭据、App 永不持有（三问档 §3.2）。结论：渠道区按契约留位，待伴生线补「桥持凭据的只读代理端点」后零改动点亮。
- **组合激活写面有落点（三问档附 B-1 销账）**：Dashboard GET /api/config 规范化回执顶层含 auxiliary（22 键）/delegation/fallback_providers/moa/providers/model——组合拼装可走既有 performAdmin 全量写回通道。仍未测：写回后热生效范围（附 B-3），激活后提示文案已如实带「若没立刻变、随下次重启生效」，终验归收官窗口。
- **组合存储面未建**：oneday 桥只有 /meta/brief，/meta/model-combos 未上线——客户端按三问档 §5.3 契约先行，404 走 bridgeMissing 如实空态（台账 App 半同先例）。

### 103.2 接入层

- **提供商名册**（Core `ProviderRegistry`）：条目自 config providers 字典解（name/base_url/key_env/models）；添加表单四件套（三问档 §6.2）——名称/接口地址/SecureField 密钥/模型；**连通性检查＝拿刚填的密钥直连对方 GET /models**（ProviderProbeClient，密钥只过手不留存），拉到默认全选可取消，拉不到降级手填（§6.4 OpenWebUI 口径）；保存顺序＝先 PUT /api/env 落钥（env 名自提供商名派生 `ONEDAY_PROVIDER_<SLUG>_KEY`，仅 ASCII slug、纯中文名回落兜底段且有碰撞闸）→再写 config 条目（只存 key_env 引用）；删除连 env 钥一并删（失败如实带注）。config 明文不存钥、App 本地不存钥（单钥原则不破例）。
- **网关渠道只读**（Core `GatewayChannel(s)`＋`GatewayChannelsFace` 四态）：面未开通/读失败/空/有数据分开露面；ready 时行＝名＋状态人话（使用中/已停用/出错后自动停用/状态未知）＋「可用模型 N 个·优先级·分组」；全区零按钮（启停/排序是管理面写操作，本包只留位，不明示可点）。
- **云电脑配置面**（Core `CompanionConnection(s)`/`ConnectionStatusWording`/`ConnectionPayloads`/`CredentialFlowPhase` ＋ `CompanionFrontClient`/`ConnectionsStore`）：连接器目录新增「云电脑」组（云电脑档 §6.1）——每台一行（名＋类型＋状态词，词表与伴生面板同源、优先服务端 effective 原文）；Simular Box 自已连接组迁入本组（同机只出现一处，记录没读到时不滤、避免两处皆空）；添加流＝选类型（托管/VPS）→名字→建记录→就地凭据验活：托管类只填密钥（端点常量在服务端、不让用户填，§3.1），VPS 类地址＋令牌＋**配置串整串粘贴自动拆分**（JSON/两行/空格三形态，Core 解析钉测）；公网明文 http 地址给一次性钥匙风险明示（§5.5 口径）；详情页＝状态/最近验活原文/凭据已配置布尔/更换凭据/测试连接/断开（断开文案明示厂商侧吊销与 VPS 侧卸载是用户在那边的事）。验活成败与回滚全在服务端，App 状态机只回显 detail 原文。

### 103.3 清单层

- **来源标注**（Core `AnnotatedModel`/`ModelSourceAnnotation`）：全部模型＝网关候选（AppState 既有管线）在前＋具名提供商声明模型（直连）在后；同名可双路并存（「deepseek-flash（经网关）」与「deepseek-flash（直连·X）」是两个条目，选路即选来源，不另设提供商切换开关——三问档 §6.5）；**两路都硬排除网关别名**（ModelCatalog 纪律不回退）。行呈现：模型名＋别名标注（沿旧）＋来源短标＋当前标；只有经网关行可点设默认（直连模型设全局默认只有名没有路，点了也是坏的——不给这个入口，槽位里按直连用）。

### 103.4 分配层（组合）

- **数据模型**（Core `ModelCombo`/`ModelComboDocument`/`SlotChoice`）：只存被改过的槽位（aux 稀疏字典）；fallback 用 includesFallback 区分「不动」与「显式清空」；文档整体 GET/PUT 桥 meta（契约 `/meta/model-combos`）。
- **编辑器**：名字＋主模型（只列网关候选）＋辅助槽位（常用 12 格目录序＋config 实存的其他键补后；每格开关＋走哪条路/用哪个模型两菜单，provider 候选只给自动/主端点/已添加提供商——三问档 §5.7 不端官方全量名单）＋委派＋备用链（增删＋onMove 排序）；每格副行带现行值（ComboCurrentValues 自 config 读）。
- **激活**（Core `ComboActivation.apply` 纯函数拼装＋Store 执行）：读最新 config→只改点名键（aux 槽位只动 provider/model 两键、同槽位其余键如 timeout 原样保留；未知字段全程保留）→整包写回→meta 标激活；主模型不在网关候选内拦下不写并说明；确认弹窗与结果提示带粒度诚实边界（全局生效/已有会话不受影响/辅助槽位全机共用，§5.3）。
- **起始示例**：空清单时给「把当前配置存为第一套组合」（ComboStarter 只收非默认槽位）——现状快照、用户点名才存、可删改，不称推荐/预设（§5.6）。

### 103.5 进展胶囊

- 按三问档 §4 落：聊天页顶 safeAreaBar 内、身份胶囊下方一颗玻璃 pill（头像位以 agentDisplayName 文本＋ProgressView 占位，与台账 §96 的 glyph 欠账同口径），内容＝名字＋正在做什么＋已耗时（TimelineView 逐秒、LedgerElapsed 同台账算法）。
- **同源纪律**：数据源唯一＝台账 items（本面包内 ChatView 表面自持一个 LedgerStore 实例消费同一 /ledger payload——与枢纽段同构的表面自持模式，派生/文案/耗时口径全在 Core，不存在第二套状态语义）；Core `ProgressCapsule.derive` 剔除当前会话名下条目（本聊呈现归消息区）、blockedApproval 不进（归审批角标）、多件收敛「正在进行 N 件 · 最近标题」；点胶囊→台账详情 sheet（LedgerDetailView 复用），条目带会话链接可经 pendingChatSessionID 直达。

### 103.6 钉测与欠账

- 新增 41 法（ProviderRegistry 13＋ModelCombos 12＋CompanionConnections 11＋ProgressCapsule 5；基线 995 → 预期 1036，终判等合并后 CI，本机无 Swift 工具链）。
- 欠账/未决：①渠道只读代理端点待伴生线（契约已定：GET /api/companion/gateway-channels → {channels:[{id,name,status,models,priority,weight,group}]}，App 已按此解码）；②组合 meta 面待伴生线（契约 GET/PUT /api/oneday-bridge/meta/model-combos，文档 {combos, activeComboID}）；③aux/delegation/fallback 写回的热生效范围未测（收官窗口）；④具名 provider 的选用语法（会话锁/逐请求引用）未实测——本包只做到名册与候选呈现，聊天里实际选直连模型走哪条路归窗口实测后另包；⑤providers 条目里 models 字段经 Dashboard 规范化往返是否无损未实测（若被规范化剥掉，清单层直连标注退化为「条目在、模型清单空」，添加流不受影响）；⑥VPS 能力面（shell/文件/状态卡）与默认台语义随云电脑档 P1 后段另包，本包只到连接配置面。

## §104 动态换代包 0.38.0：简报驱动调研五步链＋简报两层制＋来源嵌入卡＋未读角标（2026-11-11，预制包；§101 留文件页 v2 包）

> 规格真源：`three-pages-mechanism-v2-20261110.md` 第一章＋附记（2026-11-10 17:42 用户「按推荐全定」、17:43 附记简报两层制）。用途论证（产品经理令）：动态＝替用户盯世界——用户只定「我关心什么」，系统每天替他去看、验真、成帖，他只读结果。本节与规格冲突时规格优先。

### 104.1 生成链换代（伴生 oneday_bridge.py 段二）

- **退役**：P3 段二「晨报」整链删除（MORNING_PROMPT／单轮 /v1/runs 写稿／`_assemble_morning_material`／`_parse_morning_post`／`_start_morning`，grep 零残留）。旧 kind=morning 帖只读保留、呈现不改。
- **新链五步**（桥内线程，`/meta/brief` 执行层为输入）：①**规划**——一次 /v1/runs 把简报拆成 ≤4 个方向、每方向 ≤2 条检索词（JSON 严解、条数上限在解析层钉死）；②**检索**——Tavily 逐词检索（武装库 TAVILY_API_KEY，每词回 5 条），候选按规范化 URL 去重（去 fragment／utm 等跟踪参数／尾斜杠，host 小写），并剔除近 30 天已发帖的标题与链接（避让集）；③**深读抓图**——Tavily Extract 逐篇深读（正文 ≥400 字才算读到），正文图与 og 图入图池（每篇 ≤2 张、与来源 URL 绑定）；深读失败的候选用 Firecrawl 抓取兜底（FIRECRAWL_API_KEY）；④**著帖**——逐方向一次 /v1/runs，材料＝该方向候选的真标题／URL／正文摘＋图池清单＋避让标题，产出 {title, body, why, links, images, refs, skip}；⑤**验真落库**——links 必须 ⊆ 本轮候选集（集外一条整篇退回、不落库）；images 必须 ⊆ 深读池且 HEAD 可达（不可达剔图、不断帖）；refs 给了才验（`_clean_refs` 旧纪律：假一整帖退回）；why 必填（空＝无理由不落）。落库帖 kind=**research**，带 direction、images:[{url, sourceUrl}]、sourceCard（可空）。
- **节奏与上限**：每日 08:30（沿旧晨报时隙与 meta.feedGen 账面）＋简报执行层真变更触发（见 104.2）；每方向 0–1 帖、整轮 ≤3 帖；账面 directions[] 逐方向记 produced/candidateCount/note，顶层 status 沿 ok/empty/skipped/error 四态、dropped 计数单列。生成账面视图双键：`morning`（旧 App 兼容别名）与 `research` 同指一份账面。
- **来源嵌入卡**：著帖链接命中 GitHub 仓库 URL（两段路径、保留段名排除）时，桥侧以 api.github.com/repos/{owner}/{repo} 真抓成卡 {kind:"github", name, description, url, imageUrl（仓库主头像）, facts:[星标/复刻/语言]}，每帖至多一张；抓不到就不带卡，绝不拼造。
- **通道缺位如实**：TAVILY/FIRECRAWL 密钥经 companion.env 注入（env.example 已补空位行）；检索通道未配时整轮记 skipped「通道待接通」，Hermes 钥缺位同旧纪律记 skipped，都不产帖、不假造。
- **工作台账**：轮次 job kind 沿用 "morning"（台账历史不断链），显示名改「动态调研」。
- **自测**：p3 Phase B 改测新链三态（集外链接整帖退回／skip 如实记账／有效落库含死图剔除）检查数与旧版持平（26）；新 p4 自测 19 项（两层简报 HTTP 契约＋扩写落盘/过期不落盘＋URL 规范化＋避让集＋GitHub 卡桩测＋计划上限＋视图新字段）并登记 run_bridge_selftests.sh。全套结果：overview 8／p2 34／p3 26／p4 19／write-gate 22／ledger 60／model-combos OK／device OK；device_sync 一例失败为其自测按 `datetime.now()` 对固定种子算「今日/逾期」的跨日界既有问题（该自测不引用 oneday 模块），非本包引入。

### 104.2 简报两层制（落点＝桥 meta 扩展，App 只呈现）

- **两层分工**：兴趣层 `meta.briefInterest`＝用户原话（上限 2000 字）；执行层 `meta.brief` 沿用旧字段语义不变——点子/简报/调研三条生成管道的消费面零迁移。上层时间戳 `briefInterestUpdatedAt`、执行层 `briefUpdatedAt`、扩写账 `briefExpand{lastRunAt, lastError}` 分开记。
- **契约**：GET /meta/brief 回 {brief, interest, briefUpdatedAt, interestUpdatedAt, expanding, expandError}；PUT 接受 {interest} 和/或 {brief}（上限 2000/4000），回全文＋expandStarted。旧 {"brief"} 契约行为不变（直改执行层）。
- **触发链**：PUT interest 且 trim 后真变更且非空 → 起扩写线程（BRIEF_EXPAND_PROMPT：保留全部方向与口径、不自创方向、结合上一版维护、只输出正文）；扩写落盘前复核兴趣未被再改（过期扩写不落盘）；落盘且执行层与旧值不同才触发一轮调研（trigger="brief"）。PUT brief 真变更 → 直接触发一轮。interest 清空不触发、不动执行层。
- **App 呈现**：动态页首行改「简报行」——兴趣层首行摘要（回落执行层首行）、空时引导文案「写下你感兴趣什么，我每天替你去看」，点开与右上角 sliders 钮同进 `FeedBriefEditorView`；编辑器两层分区独立编辑独立保存：兴趣层带示例块（现行三方向原文，只呈现、点「填入示例改一改」才入框，绝不静默预填），执行层标注「正式简报」可见可改；扩写中/失败如实显（失败原文呈现、不藏）。旧胶囊（点开落帖）仅在简报端点不可达（briefDoc 为 nil）时作降级保留。

### 104.3 帖面与未读

- **帖行**：右侧 54pt 缩略图（images 首图，无图不占位）；动作行在类别后加方向名。
- **详情**：标题下整幅图（首图，加载失败整块不显）；why 段后来源嵌入卡（头像＋名＋简介＋事实行，整卡外开来源页）；links/refs 沿旧结构。
- **未读角标**：壳层 ContentView 持 feedUnread，.task(id: scenePhase) 前台 30 秒一轮拉 /feed/generation.unread（与总览轮询同节奏），Tab(value: .feed) 挂 `.badge`；失败保持旧值不忽有忽无。**口径**：APNs 到位前只称「未读角标」，全包文案无「推送」字样冒充系统推送（grep 验）。
- **Core**：BridgeFeedPost 加 images/sourceCard/direction 宽容解码（旧帖缺省空/nil）；FeedPostKind 加 .research（符号 magnifyingglass、文案「调研」）；BridgeFeedGeneration 加 research 键与 segmentTwo 正读口径；新文件 FeedBrief.swift（BridgeBriefDoc／BridgeBriefSaveRequest 只编所设层／FeedBriefBoard：摘要行口径、引导态、真变更 trim 比较、exampleInterest 常量）。新测 FeedV2Tests **13 法**。

### 104.4 架构取舍与未决项

- **生成侧落点**：规格 §1.4 已定论＝生成住桥（伴生 oneday 模块），本包从规格未自创；两段模型调用仍走 /v1/runs（规划＋逐方向著帖），与点子/简报管道同底座。
- **版本位**：五处版本本包未动（预制包口径，合并时主线定 0.38.0 号）。
- **未决**：①Tavily/Firecrawl 生产密钥注入 companion.env 后须实跑一轮真调研验产出质量（本包只验桩链）；②扩写轮与调研轮的真实耗时（/v1/runs 同步等待）待生产实测，App 侧已按异步对账设计、不阻塞呈现；③深读图池的图源版权口径沿「来源页真图＋详情标来源链接」现状，未另设过滤。
## §105 点子扩容（0.39.0 预制，源分支 feat/ideas-v2，2026-11-11）：素材七源＋落卡三门＋锚点级去重

规格源＝three-pages-mechanism-v2-20261110.md 第二章（2026-11-10 17:42 用户「按推荐全定」）。本包只动点子机制层：管道骨架（桥内调度／07:30 节奏／0–3 张／状态机／采纳链／expiresAt）全部保留，换的是素材装配、证据校验与去重。版本五处未动（合并时主线定 0.39.0 号）；伴生改动在 hermes-deploy 工作树（非 git 仓），随合并后按自动部署规矩上线。

### 105.1 桥（oneday_bridge.py 生成段换代）

- **素材四源→七源**：brief 不变；S 由「近 7 天会话标题」升两段式——`_ledger_sessions` 列近 14 天主线/正经旁聊（cron/archived/probe/生成会话自身排除），逐会话经 `_ledger_messages` 取正文节选（仅 user/assistant、尾部 4000 字），一轮 flash 摘要（SESSION_DIGEST_PROMPT，明令保留日期/专名/数字锚点）压成一句，摘要按 (会话 id, messageCount) 缓存于 meta.sessionDigests（同日手动轮复用、48 条上限）；摘要失败降级为标题行＋注记只进账面（沿首轮「注记不进素材」纪律）。G 补近 14 天 entries（每目标 ≤3 条）＋最近一期简报标题。M 不变。K 新源 `_fetch_kanban_details`：经 `_ledger_dash` 读 oneday 板实质（标题/状态/body 摘录/最近活动），三类信号定版——blocked＝「卡住」、done 且 7 天内＝「已完成待收尾」、未完成且 ≥7 天无活动＝「长期未动 N 天」；板不给时间戳的字段不编信号。R 新源 `_fetch_memory_excerpts`：经 write-gate 桥 `GET /memories`（契约 memory-bridge-contract-20261109，Bearer WRITE_GATE_BRIDGE_KEY，既有通道）取条目，只入桥生成的 title+summary 摘录；选取＝文件 30 天内更新或命中目标/任务标题关键词，≤10 条。
- **落卡三门**：①硬门不变（generated＋evidence 空→400，POST 与生成共用；POST 另加 evidenceRef 形状校验 ^[SGMKR][0-9]+$）。②锚点门（新）：`_assemble_material` 同步产出锚点注册表（ref→真实对象），`_parse_generated_cards` 逐卡验——evidenceRef 必须在注册表内（＝对象存在校验），且 evidence 句须含具体事实（日期/数字/对象 id/锚对象标题特征词任一；ref 记号本身先剥除防冒充）。③动作门（新）：生成提示改版（双标杆样例＋「我可以……」式明令）＋著卡后自检轮 `_self_check_cards`（同模型按标杆逐卡复判、不过自删；基础设施失败保留卡片只记 selfCheckNote、产出不可解析不采信）＋『太泛』回流（见 105.2）。
- **锚点级去重**：落卡时把 ref 解析为 anchorId（"<kind>:<对象 id>"）存进卡面——轮内编号跨轮无意义，去重必须以对象为准。pending/adopted 卡的 anchorId 封该锚点（adopted＋taskId＝事已在办/已办完，同口径封存至卡删除）；dismissed 锚点歇 30 天（以 statusAt 计、旧卡回落 createdAt）；标题层保留作第二层（全存量标题精确去重）。账面新增 droppedReasons 分计（noAnchor/noAction/dupAnchor/other）＋materialNotes 按源分记＋selfCheckNote；materialNote 旧键保留（会话源注记镜像）。
- **卡面新字段**：anchorId、dismissReason（null|"tooGeneric"）、statusAt（状态落定时刻，PATCH 与过期清扫都落）。PATCH /ideas 只多收 dismissReason：仅转 dismissed 时可带、词表外 400；`_idea_view` 三字段全形输出，旧卡缺失按 null 呈现。
- **自测**：新增 tests/oneday_bridge_p5_selftest.py 21 项全过（A 相位 HTTP 契约 9 项：硬门/编号格式门/太泛落定与两处 400/视图新字段；B 相位整轮 12 项：七源装配断言含 S 摘要入素材、cron/probe/旧会话排除、K 三信号、R 旧条目剔除、太泛标记入避让素材，三门各落一类 dropped、锚点去重跨轮、摘要缓存不重跑）。全套其余与基线一字不差（overview 8／p2 34／p3 26／p4 19／write-gate 22／ledger 60）；device_sync 既有跨日界 1 例失败与本包无关（基线同挂）。

### 105.2 App（呈现与字段，卡面形态零变化）

- **Core 新件 IdeaAnchor**（IdeaAnchor.swift）：evidenceRef/anchorId 双形态解析（五源字母＋序号，形状不对不认不猜）＋IdeaMaterialKind.tileSymbol。IdeasView 瓷砖 switch 退役改走本件：S/G/M 符号与 0.32.0 逐一对齐（text.bubble/target/dot.radiowaves.left.and.right），K＝checklist、R＝brain 新增，无法解析回落 lightbulb；手记仍 pencil。
- **字段接入**：BridgeIdea 加 anchorId/dismissReason 宽容解码（旧载荷 nil）；BridgeIdeaPatchRequest 加 dismissReason（nil 不落键）。
- **『太泛』入口**：生成卡在列表长按菜单与详情动作组各多一项「太泛了，忽略」（手记卡不给——太泛是生成质量信号）；IdeasStore.dismiss 加 tooGeneric 参数，随 PATCH 带 dismissReason="tooGeneric"，回读确认口径不变。左滑仍是普通忽略。
- **单测**：新增 IdeaAnchorTests 5 法（五源解析/双形态拒收/瓷砖对齐与互异）＋OneDayBridgeModelsTests 4 法（v2 全形解码/太泛原因解码/旧载荷默认/PATCH 编码），共 +9 法，本机无 Swift 工具链、终判等合并后 CI（静态自查：BridgeIdea 两处既有直构均为标签参、新参带默认值不破调用）。

### 105.3 核查与取舍（如实记账）

- **R 源落点已核实存在**：write-gate 桥 `GET /memories` 已上线（契约 §4 的「未部署」已过期），字段 {id,target,title,summary,updatedAt,digest} 与契约 §2.2 一致，故 R 源本包全量接入、不缓上。注意 updatedAt 是**文件级**时刻（契约明示条目无逐条时间）：「近 30 天更新」实为「所在文件 30 天内动过」，同文件条目同进同退——选取口径如实如此，不包装成逐条新鲜度。
- **kanban 卡面不能承载 goalId（已核）**：KanbanTask 生产字段面（App 解码器逐字对过的字段集）无 goalId、无通用 metadata 键，建卡 POST 同。本包不需要该载体（点子↔目标关联已由桥侧 idea.goalId＋taskId 回写承载）；规格第三章的委派载体按其定案顺序走桥侧 goal_task_links 映射，留 0.40.0 施工时落，本包不往卡面塞未验字段。
- **三门落点与任务单的口径对齐**：三门按规格 §2.1 落桥侧（模式校验/存在校验/自检轮都在桥），App Core 只落锚点模型与呈现映射——规格 §2.3「App 基本不动」与此一致；动作门本质是语义判断，本包是「提示明令＋自检轮＋太泛回流」组合防线，不宣称全自动质检（规格诚实注记同口径）。
- **摘要是二次压缩**：锚点靠提示纪律保留、仍可能丢细节；摘要只作生成素材，不落任何用户可见面（规格诚实边界同口径）。记忆摘录是启发式挑选，会漏，不宣称读全。

## §106 目标分类流包 0.40.0（2026-11-11，预制分支 feat/goals-v2；分支自选 §105 与点子扩容节撞号，合并时顺延为 §106）

缘起：规格 three-pages-mechanism-v2-20261110.md 第三章（2026-11-10 17:42 用户「按推荐全定」，开放问题 4 选 A 案）。§61 有目标态呈现已对齐，所缺三件：无目标时的分类创建流（现行普通空态）、桥 goal.category 字段、设计档 §2.4 原案欠账的委派与关联两件。本包全量补落；B 案对话式创建仍随收官窗口 9B 门面另行切换（桥 source=chat 契约 §61 已备，本包不动）。

### 106.1 桥（oneday_bridge.py，契约先行）

- **category 字段**：GOAL_CATEGORIES＝health|relationships|finance|career|interest|efficiency|other。goal 视图新增 category（存储值在枚举内原样回、否则 null）；POST 校验（缺省/null 合法、枚举外含非字符串 400 人话）；PATCH 增量支持 category（显式 null 清回未分类）。**存量不自动归类**：旧记录无此字段一律读 null，桥与 App 都不做标题关键词推断（规格 3.4）；补分类的唯一路径是用户在编辑 sheet 自选。
- **goal_task_links 集合**：{id(gl_), goalId, taskId, milestoneId|null, createdAt, completionEntryAt|null}。端点 GET/POST /goals/{id}/task-links（POST：taskId 必填非空、milestoneId 须为该目标真实里程碑否则 400、目标不存在 404；(goalId, taskId) 重复 POST 幂等回既有记录——委派回写重试不双记）。载体定案：kanban 卡面无 goalId 字段、无通用 metadata 位（0.39.0 已核查），不往卡面塞未验字段，关联只住桥侧本集合。
- **级联**：删目标（及子目标）时其 links 随删；kanban 任务本体不动（沿 §61「点子/监测只解绑、目标自有物随删」口径，links 属目标自有物）。
- **完成自动记一条**：feed 的 kanban 轮询（_feed_poll_remote）在快照差分同轮扫 links——关联任务现值落入 done 态集合且 completionEntryAt 未落戳时，给目标追加一条进展条目（source=agent、正文只写可验证事实「任务《标题》已完成（任务号 id）」），并落戳保证恰好一次；规格 3.4 事实门：不写「进展顺利」式感想句。
- **自测**：新 p6 自测 26 项（Phase A HTTP 契约：类别校验/旧目标 null/links 建查校验/幂等/删目标级联＋点子监测只解绑；Phase B 进程内桩板轮询：done 落一条、复轮不重记、后完成者各自落条），登记 run_bridge_selftests.sh。全套：overview 8／p2 34／p3 26／p4 19／p5 21／p6 26／write-gate 22／ledger 60／model-combos OK／device OK；device_sync 仍 1 例失败（reminders 种子跨日界既有问题、与本包无关，与前几包同）。

### 106.2 App

- **Core**：新文件 GoalCategory.swift（七类枚举＋title/symbolName，rawValue 与桥枚举逐字一致、from 宽容收）；BridgeGoal 加 category 宽容解码；BridgeGoalCreateRequest 加 category（make 同步）；新 BridgeGoalCategoryPatchRequest（nil 显式编码 JSON null——省键在桥侧是「不改」、清分类必须落 null）；BridgeMonitor 补 goalId 解码（P2 桥字段 App 此前未解，关联段要用）；新文件 GoalTaskLinks.swift（BridgeGoalTaskLink/Response/CreateRequest＋GoalAssociations 拼装纯函数：ideas/monitors 按 goalId 过滤、linkedTasks 经 links 反查任务板现值，取不到如实 nil）。新测 GoalCategoryTests **11 法**（枚举对齐/宽容解码/落键口径/拼装/解码）。
- **分类创建流**：GoalsView 空态整页换分类流（「＋创建目标」标题行＋实话说明「选一个类别，先把目标记下来……」＋GoalCategoryRowsView 七行：SF Symbols 同语义位图标＋类名＋右端＋），点行直接开预置该类别的新建表单；有目标时底部创建区与工具栏＋改为先出分类选择 sheet（同一组件），选完同 sheet 内换成表单。普通空态（「暂无目标」ContentUnavailableView）废弃。新建表单加类别行（未分类＋七类 Picker，预置可改可清）；子目标创建不经分类流、类别恒未分类。
- **编辑补分类**：GoalEditView 加类别行；保存＝全量 saveEdits 后、类别草稿与服务端现值不一致才走专用 PATCH {category}＋回读确认（两步各自对账，分类失败留表单内报错、正文编辑已落不回滚）。
- **详情呈现**：头部状态 chip 行加类别 Label（有类别才显）；新增「安排一件事」段（入口＋说明）与「关联」段（在子目标段后、状态动作前；三路全空整段不出现）。关联行点达：点子→IdeaDetailView、任务→KanbanTaskDetailView（状态经 KanbanStatusPresentation 译名表呈现）、监测→MonitorDetailView（跳管理）。详情页自持 ideas/monitors/kanban 三个 Store 实例只读拼装（各回各的真源，与动态页 refs 点达的跨 Store 呈现同形），不建本地副本账。
- **委派**：GoalDelegateView 表单（事情标题＋可选挂里程碑）；GoalsStore.delegateTask 与 IdeasStore.convertToTask 同链——KanbanStore 探板（未开通如实止步）→createTaskReturningID 建卡确认→POST task-links 回写→回读确认关联出现；卡面正文只写事实「为目标《X》安排的一件事。」；回写失败如实留 notes、不假成功不回滚任务。

### 106.3 存量呈现口径与未决项

- **存量目标**：category 一律 null——列表行不显类别（列表形态 §61 不动）、详情头部不显类别标、新建/编辑之外无任何自动归类；用户编辑时自选补上后，详情头部才出现类别标。
- **版本位**：五处版本本包未动（预制包口径，合并时主线定 0.40.0 号/构建号）。
- **终判**：本机无 Swift 工具链，App 侧已做静态自查（构造点/引用/括号配平），编译与单测终判等合并后 CI；桥侧自测已在本机全套实跑（见 106.1）。
- **未决**：①按类筛选/分组呈现按规格登记缓办、本包未做（详情呈现＋创建预置已落）；②B 案对话创建随 9B 门面（收官窗口）切换时分类流与 category 零返工，本包未预埋对话入口；③委派自动记条目走 feed 轮询节奏（非实时），任务完成到条目出现之间隔一个轮询周期，真机终审时按此口径看。

## §107 全局收口批（0.41.0 预制，源分支 feat/polish-041，2026-11-11）：审计余项逐条收口＋字阶/标尺单轨＋回底钮浮层化与离底未读

依据＝全局审计 global-ui-audit-20261110.md（25 条＋深色 D1–D9）与整改台账 ui-remediation-ledger-20261110.md。销项纪律：本节只记施工事实，台账销项状态由主线按「已修待验收／用户拍板豁免」更新，施工方不自销。版本五处未动（合并时主线定 0.41.0 号）；**节号预制自选 §106 与目标分类流节撞号，合并时顺延为 §107**（目标节定 §106 在前、本节 §107 在后）。

### 107.1 核实销账（病灶已被前序版本修掉、本包只复核补钉，代码零改或仅补测）

- **P1**：工具卡未映射回落英文短名——0.36.10 已改中文类名回落（ToolCards.fallbackTitle），本包补钉测 testFallbackTitlesNeverContainASCIILetters 防回潮。
- **P2**：抽屉名单手算 padding 84——0.36.27 已退役（safeAreaBar 注册＋contentMargins 承接），全仓 grep 无 84 残留。
- **P9**：提醒详情两整段说明——0.36.3 已瘦身（一句事实＋一个下一步）、0.36.18 同步制已重排结构（状态头＋同步区＋内容），病灶不存在。
- **深色 D1–D9 代码层**：0.36.1 已全销（批一B）；余 D4 全表面暗档真机对照、D9 曜黑弱面暗底真机肉眼验——均非代码项，留真机验收清单。

### 107.2 本包实修

- **聊天回底钮正修（台账 H 节）**：钮移出 bottomBar 布局流，改挂发送区容器顶缘 overlay（trailing spacingM、视觉盘在发送舱上方约 13pt），显隐不再动列表底部 inset；原两条以钮显隐为键的容器高度动画退役（错误/提示条动画保留）。Core 新件 **AwayUnreadCounter**（BottomFollow.swift）：在底恒 0 并推进水位、离底冻结水位计新增、自发发送清零、切线程 resetAll、水位条目被删不虚报、displayText 封顶「99+」；ChatView 两路喂入（条目数变化／可见集变化，经同一 feedAwayUnread、在底事实与钮显隐同走 BottomFollowPolicy 派生），角标挂钮盘右上、无障碍标签「回到底部，N 条新消息」。钉测 +9 法。
- **P3**：抽屉 drawerDivider 自绘 Rectangle（高 1pt）收编 GroupDivider 本体——GroupDivider 扩 trailingInset（默认 0、全 App 贯通几何不变），抽屉显式传双侧 drawerInset。**视觉变化：线高由 1pt 变物理发丝（更细、与全 App 同粗），待真机验。**
- **C3**：odGroup 去 0.5pt 发丝描边，回定版 §3.4「surface 底、零描边零阴影」单机制（78 处消费同帧生效）。**视觉变化：浅档下组边界改由底色差＋间距成界、观感变淡，真机验收重点。**
- **C4**：settingsSectionSpacing 28→24 入梯队（spacingL；组间/组内比 24/12＝2 达标）；pageGutter/cardPadding 的 20 为 OpenMuse 令牌出处值（ui.tsx:52），保留并以本节记账为「入宪法修订」处置——梯队自述同步订正为「含 20（pageGutter/cardPadding 令牌位）」的事实口径留主线合并时在 §3.2 一并订正，本包不动宪法文件。
- **C5**：标尺外 spacing 字面量收编 156 处（stack spacing 121＋padding 33＋跨行 2）：按角色入 OneDayMetrics 微距令牌（spacingMicro 2／stackGap 3／iconTextGap 5／rowInnerGap 6／cardInnerGap 10，数值与原字面量逐一相同、版式零变化）；spacing 14 两处 snap 至 spacingSM 12。残留注记：padding 7 ×3、padding 1 ×5、spacing 1 ×2 为光学微调字面量（胶囊纵距/字形贴合），分享名片 HStack 28 为成图构图值（文件内已注记）——均属「梯外具名」同族，留账不扫。
- **C14＋P6（字阶字重双轨）**：行题统一归 FontRoles.rowTitle——动态帖行（.headline→）、点子行（.headline→）、目标列表行（.title3 semibold→）、目标详情内简报卡题（.headline→）、子目标行（.body medium→）、简报列表行（.title3 semibold→）；元信息级回收 regular——目标条目来源标与状态 chip（footnote semibold→footnote）、目标组头（body semibold→body）、动态来源卡名（subheadline semibold→rowSubtitle）。目标详情页压回三级：页题（FontRoles.detailTitle 定点，title2 semibold、值不变）／SectionLabel／body 与 footnote。帖子详情题收编 FontRoles.contentTitle 定点（title3 semibold、值不变）。TypeRole 角色表未动（contentTitle/detailTitle 为内容层定点、同 §51 Headline 定点口径）。
- **P4**：FeedView 胶囊行与简报行共用外壳 bannerRowChrome——横 padding 14→spacingM 16、纵 spacingSM、圆角 radiusPreview、行距 rowInnerGap、行内距 cardInnerGap，两行形态自此单源。
- **P5**：帖子详情撤 navigationTitle「动态」（内容标题领头，宪法 §5，随 C9 先例）。
- **P7 余项**：连接页「已连接」组页脚整句瘦身为一句事实并去「MCP／服务端」术语（宪法 §8）；审计点名的两段原文已在前序版本消失，本处只处置现存一处。
- **C15**：圆角角色令牌立表（radiusTile 9／radiusThumb 10／radiusCard 12／radiusPreview 16／radiusCheckbox 6）并扫替 32 处字面量（6×4、9×5、10×6、12×8、16×7，另 8→radiusThumb 与 14→radiusPreview 两处 snap——媒体缩略夹与终端卡）。残留注记：23 ×4 为浏览器/电脑胶囊条的半高圆角（胶囊几何）、≤4 的微装饰圆角 ×6（图表条/代码装饰）不在卡面族、不扫。旧「梯队 {7,10,28}」与卡面实际形态脱节，本表即新梯队，留主线合并时在 §3.2 记账订正。
- **浅档专项（§66.1 候选 (a) 落地）**：三款 accentLight 同色相加深一档——sangou 0x1473C8→0x136FC1（对 tintLight 4.48→4.74）、skyBlue 0x0B74BC→0x0A6BAE（4.31→4.90）、peach 0xAC5A12→0xA55611（4.43→4.73）；iceBlue 现值 4.60 已过闸不动。新增对比闸④（全款 accentLight 对自家 tintLight ≥4.5）钉住。**视觉变化：默认主题链接/强调色略深一档，待真机复核；备选 (b)「泡内链接改走 ink」未采用。**Palette.primary 注释与 ChatThemeTests 旧值钉已同步订正。

### 107.3 跳过清单（不在本包处置，依据逐条）

- **C8**（FileIconBox＋DeliverableIconStyle 字母块）：处置二选一（真图标资产／降级 SF 符号＋中性面）属设计拍板——现行字母色块是 0.22.0 视觉审计 F2 的定版设计（对位 Muse 资源库类型图标、DeliverableIconStyleTests 钉住），且文件页 v2 后真缩略图已优先、字母块只作回落。施工方不擅自推翻定版，呈主线请用户拍板（建议：保留回落形态、或随上架线一并换真图标资产）。
- **C13**（可点指示三轨并存，27 处 chevron／19 文件）：统一方向（全 NavigationLink 化／全明示）横跨全 App 且 0.36.32 已有逐面裁决先例（频道行删 chevron），不宜一刀切，留逐面处置。
- **无障碍 19 项主体**：独立无障碍专项、挂上架线（台账原口径）；A11Y-D2 固定字号散点属该专项，本包字阶收口只动字重/角色、不动其字号钉。
- **已登记触发项**：iPad/横屏、数据可视化、声音反馈、多语言（0.42.0 独立包）——宪法续编登记触发未到，跳过。
- **D4/D9 真机项**：非代码，留真机验收清单（见 107.1）。

### 107.4 单测与未决

- 单测：+11 法（AwayUnreadCounter 9＋对比闸④ 1＋P1 回落钉 1）；改 1 钉（ChatThemeTests 默认主题 accentLight 旧值→新值，防回潮方向反转已注记）。终判等合并后 CI（本机无 Swift 工具链，预制包口径）。
- 未决：①C8 拍板（见 107.3）；②C4/C15 的梯队口径订正须主线在合并时同步落 §3.2 与台账（本节已给文本口径）；③overlay 浮钮在 safeAreaBar 容器上的实际呈现（溢出渲染/边缘柔效交界）只能真机验——若被裁切，备选落点＝挂消息列表本体的 .overlay 并以实测发送区高让位（不回布局流）。

## §108 国际化包 0.42.0（2026-11-11，预制分支 feat/i18n-042；节号预制自选 §107 与全局收口批 §107 撞号，合并时顺延为 §108）

缘起：用户 2026-11-11 02:34 拍板把国际化提进正式计划。口径：String Catalogs 落地（源语言简体中文，目标繁体中文＋英文）；繁体走简繁术语人工校对（台港常用法）；英文产品文案口径、专名不译；宪法 §8 零行话三语一致；日期/相对时间/数字随系统语言走系统格式化器、不许手拼格式串；App 内不加语言切换开关（随系统）。不动范围：服务端回串（桥/Hermes 人话字段）、用户内容（消息/帖/目标标题）、商店元数据（上架线）。

### 108.1 目录（App/Resources/）

- **Localizable.xcstrings**：2241 键（源串为键、插值按实参类型落 %@/%lld；提取时发现 6 条占位符误判已按源码实参修正——组合名/模型名等字符串被误猜为 %lf/%lld 的一律改 %@）。每键 zh-Hans（＝键本身）/zh-Hant/en 三语齐备。另补 2 键为代码收编所需（「已同步 %lld %@」修正键＋提取漏网的「原因没记下来」）。
- **InfoPlist.xcstrings**：8 条 NS*UsageDescription 三语化（简体原文与 Project.swift 逐字一致，值随系统语言由系统弹框自取）。
- **繁体术语口径（人工校对、非机器逐字转）**：设置→設定、文件→檔案（文档→文件）、信息→資訊、消息→訊息、视频→影片、默认→預設、创建→建立、添加→新增、保存→儲存、登录→登入、账号→帳號、网络→網路、在线→線上、搜索→搜尋、复制→複製、远程→遠端、密钥→金鑰、令牌→權杖、会话（对话义）→對話、频道→頻道、归档→封存、日历→行事曆、日程（EventKit）→行程、通讯录→聯絡人、相册→相簿、文件夹→資料夾、导出→匯出、导入→匯入、界面→介面、服务器→伺服器、用户→使用者、智能体→智慧代理、台账→臺帳、凭据→憑證、网关→閘道、渠道→管道、数据桥→資料橋、云电脑→雲端電腦、短信→簡訊、识别（语音）→辨識、麦克风→麥克風、吊销→撤銷、置顶→釘選、帖子→貼文、刷新→重新整理、归档→封存。
- **校验**：Scripts/validate_i18n.py（仓内常设）：三语齐备、占位符按位置-类型一致（定位符 %n$ 形兼容）、行话黑名单「译文不得引入源串没有的行话」（校验中实拦 1 条：英文译文误用 scope 一词已改 range）。本包交付时实跑通过：2249 键（含 InfoPlist 8）。

### 108.2 代码收编

- **新件 OneDayCore/AppLocale.swift**：AppLocale.uiLocale（取主 bundle 已解析本地化＝App 实际界面语言）＋L10n 取词口（按 locale 解析 .lproj bundle 取词；无目录宿主回落键本身，单测确定性不随运行环境漂移）。
- **C11 口径调和（重要）**：0.36.0 审计 C11 定「中文写定、不随 locale 变脸」，防的是界面中文时日期漏英文的混排。本包续编为「钉 App 当前语言本身」：locale 一律钉 uiLocale，界面语言与日期/数字语言恒一致，混排在三语下都不发生。App 根 `.environment(\.locale, zh_CN)` 写死随之改为钉 AppLocale.uiLocale；ApprovalTimeText 的 zh_CN 写死同理收编。
- **DisplayDate/ChatTimeline**：档位结构不变；绝对日期改 Date.FormatStyle 字段拼装（month/day、year/month/day，钉 locale＋日历时区）、星期改 .weekday(.wide)、时刻改本地化模板「HH:mm」（24 小时零填充、三语一致、与旧口径逐字）、相对档分/时改 RelativeDateTimeFormatter（钉 locale、全形）。**有意口径变更一处**：相对档简体输出「3分钟前」（系统格式器无空格；旧手拼「3 分钟前」），DisplayDateRelativeTests 期望已同步。新增公开助手 monthDay/absoluteDateTime 供管理面与到期行收编。
- **手拼格式点全清**：AdminFormat（short/day/timeOnly）、SessionDisplay（退役两支 zh_CN 格式器）、FeedModels（groupTitle/relativeText）、DeviceSyncPresentation（dayLabel/freshnessLine/segment/rangeLine/日志行＋countUnit 单位词）、HubActivity 分组标签、SidebarGrouping（月组标题走 FormatStyle、字段序随语言）、DeviceViews（日程行/日标题/到期行）、DeviceSyncViews（步数日标）——仓内呈现用 dateFormat 手拼串清零（余者仅解析格式 yyyy-MM-dd 与 POSIX 钟面 LedgerClock/BoxTimeText：纯数字无语言内容、按其文件内既定口径保留）。
- **SwiftUI 字面量零改码**：App 层全部 View 字面量由系统按目录自动取词（目录落 App 目标 Resources，Bundle.main 单目录覆盖三 target）。
- **Core 呈现转换的边界（如实记账）**：已转＝上述格式化/呈现函数族（均带 locale 注入面、单测钉 zh-Hans）。**未转（目录已备键、代码仍直出简体）**＝其余 Core 呈现枚举（ServerLabels、KanbanModels 状态名、ApprovalCardCopy/Headline 标题族、ToolCards 工具名、ConnectorCatalog、DeviceSources 说明、NotificationSummary、LedgerBoard/Models、GoalCategory、HermesError、ModelCombos 槽位名等）与 SessionDisplay 的 sourceLabel/humanTitle 计算属性、DeviceSyncPresentation.detailSubtitle 常量——共同原因：这些面被既有单测以无 locale 入参的形态钉死简体断言，转换须逐面加注入面并改测，属另一小包的工作；本包先把目录与格式面落齐，转换路径为逐处 `L10n.string(键, locale:)` 一行改。App 层 Store/Client 赋给状态再显示的静态串同理（键已入目录，长尾未逐处收编）。

### 108.3 单测

- 新增 I18nFormattingTests（8 法）：取词回落恒等式、语言候选序、英文绝对日期/星期档/相对档、繁体星期/月日/相对档、简体相对新形态、侧栏月组标题三语。
- 既有测试钉 locale：DisplayDateFormattingTests（20 处）、DisplayDateRelativeTests（期望改无空格＋钉 locale）、ChatTimelineTests、FeedBoardTests、DeviceSyncTests、SessionDisplayTests、HubActivityTests（9 处 assemble）、SidebarGroupingTests（5 处）、ApprovalCopyTests。用例只增不减（相对档期望属同用例改期望、已在本节与测试文件头注明）。
- 终判：本机无 Swift 工具链，静态自查（签名/引用/括号）已做；编译与全套单测等合并后 CI。knownRegions/CFBundleLocalizations 未动——目录声明语言以 xcstrings 的 sourceLanguage＋localizations 为准，生效终判等 CI 构建产物验（主线解包看 .app 内 lproj）。

### 108.4 未决项

- 英文计数单复数：走 RelativeDateTimeFormatter 的相对档已由系统处理单复数；其余拼串计数键（如 "%lld 条" 族）英文可能出现 "1 items" 式小瑕疵，属呈现长尾优化、后续以 stringsdict 复数规则另包处理。
- 目录键与运行时实参类型以源码实参为准对齐（6 条已修正）；若个别键实参在不同调用点类型不一致，取词回落简体源串、不崩。
- 演示内容（DemoHermesClient/DemoMode 示例对话）与 DeviceCalls 协议错误体（回给桥的机器协议、非 UI 铬面）明确不在目录覆盖面；服务端回串与用户内容按规格不动。

## §109 国际化长尾接线包 0.42.1（2026-11-11，预制分支 feat/i18n-tail，基线 main 570acb0；节号预制自选，合并时如撞号顺延）

### 109.1 范围与范式

§108.2 记账的欠账全额收编：目录已备键、Core 呈现层未转码的那批逐面改走 `L10n.string/format(键, locale:)`，App 层 Store/Client 赋给状态再显示的静态串同批收编。统一范式（照 0.42.0 DeviceSync.countUnit 先例）：计算属性保留、委托给带 locale 的函数形（`func x(locale: Locale)`，函数形加 `locale: Locale = AppLocale.uiLocale` 默认值），既有调用点零改动可编译；静态数据表（连接器目录/本机名册/槽位目录）改「源表存简体源串（目录键）＋构造时按 locale 解析」，条目结构与 id/分类/图标等语言无关口径不变。

### 109.2 Core 转码面（括号内为新增 L10n 调用点数；表构造解析的字段数另注）

- ServerLabels（34）：platformName/platformState/gatewayState/categoryLabel/grouped/profileName 全加 locale 形；otherCategory 由 static let 改计算 var＋函数形，grouped 内部比较同 locale 解析。
- KanbanModels（33）：状态名 label、displayTitle、KanbanRunOutcome.label、evidenceItems、KanbanAction.title 加 locale 形；KanbanContract 两条闸门原因与 createFlowDescription 由 let 改 var＋函数形。unknown 的 raw 与事件 kind 是服务端内容、原样直通。
- 审批族：ApprovalHeadline（22，title/memoryTitle/skillsTitle）、ApprovalCardCopy（19，question/consequence/alwaysAllowScope）、WriteApprovalModels（28，badgeLabel/displaySummary/originLabel/headline/scopeLabel 与 WriteGateLabels 三函数）。
- ToolCards（65）：类名 fallbackTitle、约 40 个工具标题、commandSummary、statusLine、groupHeader。服务端回串的解析与内容连接（ToolResultUnwrap、「、」连接回串）属回串边界未动。
- ConnectorCatalog（13 直调＋目录 8 条×4 字段构造解析）：证据档位 label、ConnectedConnector.blurb/statusLabel、目录与 knownServers 名册构造解析；ConnectorCategory 新增 title(locale:) 呈现形——rawValue 仍是简体源串（兼搜索语料与分组 id，不动），ConnectorsView 三处上屏改走 .title。matches/filteredConnected/availableEntries 加 locale 贯穿。
- DeviceSources（18 直调＋名册 7 件×5 字段构造解析）：权限 label、roster/descriptor、DeviceRowStatus.line、filtered。
- NotificationSummary（30）：presentation 加 locale 并贯穿全部私有翻译函数；判语态/对象的 title.contains 匹配的是桥回的中文定性串（服务端内容），匹配逻辑保持中文不动，只产出句走目录。
- LedgerBoard（52）：LedgerText 六函数、LedgerFreshness.note、dayGroups（透传 FeedBoard.groupTitle 既有 locale 形）、headerText、subtitle、durationText。LedgerClock POSIX 钟面按既定口径保留；failReason.category 是服务端内容直通。
- GoalCategory（7）、HermesError（14，userMessage 函数形＋fromURLError 构造时取词）、ModelCombos（14 直调＋槽位目录 12 条×2 字段构造解析：providerLabel/summaryLine/AuxSlotCatalog/activationNotice）。
- SessionDisplay：sourceLabel 改委托给文件内既有私有 sessionSourceLabel（同表同键），humanTitle/contentTitle/resolvedTitle 加 locale 形；DeviceSync：detailSubtitle 由 let 改 var＋函数形，DeviceSyncDataset.label 加函数形（已核两处用法纯呈现、无与服务端串比对；线上键是枚举 rawValue，「与伴生同字」只是命名约定）。

### 109.3 App 层收编

- Stores（赋给状态的串在赋值时以 uiLocale 解析，无 locale 注入面）：AgentHubStore（21，含关键修复——statusText/isOnline 与 gatewayState 返回值的「运行中」比较改与 L10n 同源取词比对，两侧同出 uiLocale 才恒等）、GoalsStore（42）、MonitorsStore（28）、MemoriesStore（25）、IdeasStore（19）、ModelManagementStore（17）、DeviceSyncStore（15，含已送行改用新补正确键，见 109.5）、ConnectionsStore（14）、LedgerStore（9）、KanbanStore（7）、FeedStore（4）、DeviceStore（4）、AppState 探针步 label（3）、BoxBridgeStore（3）、ServerSessionActions 执行层（5）、DictationController 到限提示（1）、ChatStore 默认标题「新会话」（1，本地存量标题）、SideChatStore 主线名（1）。
- Clients：endpoint 人话名参数与自有错误模板全转——HermesClient（100）、OneDayBridgeClient（39）、DeviceBridgeClient（23）、WriteGateClient（21，演示桩 DemoWriteGateClient 整类未动）、CompanionFrontClient（17）、MemoryBridgeClient（11）、LedgerBridgeClient（10）、OverviewBridgeClient（9）、BoxFilesClient（9）、ModelComboClient（8）、BoxBridgeClient（8）、BoxShellClient（5）、ProviderProbeClient（4）。模板族统一 `%@` 形键（「%@返回 %@」「%@返回格式无法识别」等），状态码实参统一 String(statusCode) 与 Core 先例同形。

### 109.4 补键与单测

- 补键 22 条（目录 2241→2263 键、连 InfoPlist 共 2271 键，Scripts/validate_i18n.py 实跑通过）：ApprovalHeadline 记忆基句 6、「%@：%@」、「%@%@」、「%@个人资料」、「%@一条记忆」、NotificationSummary 整句 8（M1–M4 批准/驳回全形，en 用定位符调序）、「、」（en「, 」）、「%@ · %@」、「新会话将默认用 %@；已有会话不受影响。」、「已送 %lld / %lld %@」。译文风格对齐 §108.1 术语表。diff 内引用的 665 个键经脚本与目录全量对账、零缺口；三张源表（目录/名册/槽位）的表内字面量亦全量对账在目录内。
- 单测改测（17 个文件、断言值一字不变、只加 locale 钉）：ServerLabelsTests（27 处＋otherCategory 3 处）、DeviceSourcesTests（29）、LedgerModelsTests（48）、SessionDisplayTests（21）、RichContentTests（17）、ApprovalCopyTests（12）、ToolCardPresentationTests（10）、ConnectorCatalogTests（17）、HermesErrorTests（5）、ModelCombosTests（6）、KanbanModelsTests（4）、NotificationSummaryTests（2，经 decision 助手一处收口）、DisplayMappingTests（3）、DeviceSyncTests（4）、GoalCategoryTests（1）、HubGateAndBrowserTests（4）。新增 I18nFormattingTests.testTailSurfacesResolveThroughL10n（11 断言，回落恒等式钉新转面取词形）。测试函数总数 232→233，只增不减。
- 终判同 §108.3 口径：本机无 Swift 工具链，静态自查（键对账/签名衔接/括号配平与 HEAD 基线同差）已做；编译与全套单测等合并后 CI。

### 109.5 残留与边界（如实记账）

- 目录坏键「已送 %@ / %lld %lld」（0.42.0 提取时占位符类型误判）未动目录：代码侧改用本包新补的正确键「已送 %lld / %lld %@」，坏键留目录待主线处置（删键或改键形需另行对账）。
- HermesClient 两处 kanban 急停/终止的请求体 reason 值「App 停止」不转：那是写进服务端任务史的落账值，保持原文避免审计记录随界面语言漂移；同理 WriteGateClient 演示桩、DemoMode、DeviceExecutors/DeviceSyncExecutors 的工具回执文本（执行层、给桥与智能体读）不在本包。
- GoalsStore.delegateBody「为目标《%@》安排的一件事。」是 App 生成的卡面模板（键已入目录）已转；它与用户自拟的任务标题的区别在于是模板而非内容，标题本体仍原样直通。
- ConnectorCatalog 的分类搜索语料仍为简体 rawValue：非简体界面下按分类名搜索不命中（按名称/说明搜索随条目构造语言），属搜索语料口径、留后续。
- 英文计数单复数 stringsdict 仍按 §108.4 另包；App 层 Store 串在赋值时以当时 uiLocale 定格，运行中切换系统语言需相关页面重拉才换语言（与 0.42.0 既有属性形口径一致）。
## §110 伴生探测契约包（2026-11-11，预制分支 feat/companion-probe；§109 已被国际化长尾包预占，本节自选 §110，合并时主线终审顺延）

缘起：服务端收口形态定版（双容器）的 App 侧欠账——「App 登录后自动探测伴生存在与版本」此前只有台账包的旁证式探测（LedgerBridgeClient.probeCompanion，只服务台账「还没上线」的说明），没有面向设置页版本组的正式消费点。本包补齐：探测时机、派生口径、缓存与呈现。

### 110.1 契约与真源（亲查实证）

- **伴生面**：GET /api/companion/info（front 8650、公网经 hermes.didichou.site 同源、单钥 Bearer），build_info() 实产字段＝companionVersion／apiLevel／minAppVersion／hermesUp（布尔）／modules{writeGate, overview, box, oneday, device → {state, detail?, degraded?（仅 oneday 恒带）}}／generatedAt。模块状态词表据 aggregate()＋probe_module() 实产：up／degraded／down／crash-loop／disabled／unknown。
- **Hermes 本体版本真源（实情）**：info 面**没有** hermesVersion 字段（只有 hermesUp 布尔）——拿不到，不许从 info 编。真源在 Hermes 自家面：GET /api/status 的 version（实测样本 "0.23.0"，ServerStatus.version，设置页 loadSummaries 既有读数）；/health 亦带 version。本包版本组 Hermes 行即用前者。
- **顺带销账**：设置页关于组旧「服务端」行在 status 读不到时写死兜底 "Hermes v0.23.0"——拿已知生产版本冒充现读，本包废除：新版本组读不到如实显「未知」，旧行移出关于组（与伴生行成组，避免同页两处版本）。

### 110.2 Core 派生（新件 OneDayCore/CompanionProbe.swift，逐项钉测）

- **CompanionVersionForm**：定版形态＝三段数字（可带 v 前缀）；两段/四段/后缀（-beta）/非数字＝格式异常。异常串显示照原文（服务器自报），但 compare 不给结论（nil）；比较走数值序（1.10.0 > 1.9.0）。
- **CompanionModuleHealth**：disabled 单列不算异常；state=degraded 或 degraded 旗 → 降级；up → 正常；其余一切（含未见过的词）→ 不可用；info 缺席的模块不下结论。名单恒按 front 名册序（writeGate→overview→box→oneday→device）、未识 id 殿后字面序。模块人话名与 front MODULE_META 的 name 对齐（审批/总览通知/云电脑/目标点子/手机设备），未识 id 原样显。
- **CompanionStatus**：presence 三档（present/absent＝info 面 404/unknown＝读不到不下结论）。现读派生给健康与升级门；**缓存派生 health 恒 nil、isStale 恒 true**（旧健康不冒充现况）。升级门：minAppVersion 格式正常且严格大于 App 版本才给出（相等不算、异常不给结论）。
- **CompanionProbeResolver**（结果×缓存→状态＋缓存动作）：detected → 现读＋落盘新记录（CompanionProbeRecord，Codable 快照形——CompanionInfo 本体只有 Decodable 不能直接落盘）；missing → absent＋**清缓存**；unreadable/unreachable → 有缓存回落 stale、缓存保留，无缓存给 unknown。

### 110.3 App 接线（CompanionProbeStore＋RootView＋设置页）

- **时机**：登录成功（RootView onChange phase==.connected）无条件探一次；回前台（scenePhase .active）与冷启恢复（RootView .task）走节流版——距上次尝试 <60 秒跳过；设置页打开时再节流补探一次。网络动作复用 LedgerBridgeClient.probeCompanion（不另起第二套请求），App 层枚举 1:1 映射 Core 的 CompanionProbeOutcome。演示模式不探（探针走真网络、不许把演示态探成真结论）。
- **缓存**：UserDefaults 键 companionProbeRecord.v1（JSON，只存 info 事实＋探测时刻）；冷启先由缓存派生 stale 态占位、现读回来替换。
- **呈现**：设置页服务器组后新增「版本」组（无组题、沿本页语法）——Hermes 行 LabeledContent（等宽值 vX.Y.Z／未知）；伴生行题＋副行（现读：「v1.0.7 · 运行正常」／异常分段「云电脑降级运行；目标点子暂时不可用」；缓存：「v1.0.7 · 上次读到 3 小时前」；absent「未检测到」；unknown「暂时读不到」；未探「尚未检测」）。脚注只在 absent（点名受影响功能＋去服务器确认启动＋回来自动重测）或需升级 App（点名目标版本）时出现。不弹警告、不阻断聊天。
- **文案**：全走 L10n，目录补 15 键（伴生服务/运行正常/未检测到/尚未检测/暂时读不到/上次读到 %@/%@降级运行/%@暂时不可用/总览通知/目标点子/版本未知/Hermes 暂时联系不上/Hermes＋两条脚注），三语齐备、validate_i18n.py 通过（2264 键）。

### 110.4 单测与未决

- 单测：新增 CompanionProbeTests **30 法**（版本形态/比较 4＋健康派生 7＋现读派生 4＋升级门 2＋解析 4＋记录互转 1＋呈现文案 8），既有测试零改动。本机无 Swift 工具链：括号配平/键对账/签名衔接静态自查已做，编译与全套单测终判等合并后 CI。
- 未决：①minAppVersion 的服务端现值（front 默认 0.37.0、env 可覆盖）App 侧只消费不校验服务端配置；②探测失败不进台账/通知（安静口径，设置页一行说清即可）；③伴生 apiLevel 的消费（App 侧桥面兼容判断）未立项，info 已回、暂不消费。

## §111 设备扩容批一（预制分支 feat/device-x1，基线 main 4ce2df1；节号自选 §111，合并时主线终审如撞号顺延）

缘起：设备表面图（device-surface-map-20261110.md）A 档欠账——剪贴板（A12）与文件（A13）两件一直只有草案名、未接线。本包按连接器设计档既有纪律把两件落成与现行七件同构的现调工具（App 侧全量），桥侧 TOOLS 表在 Hermes 仓外、单列待办（111.5）。

### 111.1 工具契约（App 侧已接线，DeviceToolRegistry 逐字名册）

| 工具 | 入参 | 成功回执 | 备注 |
|---|---|---|---|
| clipboard_get | 无 | {readAt, type: text/url/image/empty, text?, note?} | 非文字只回类型、不编内容；读别家 App 内容触发系统粘贴提示（见 111.4 文案钉） |
| clipboard_set | {text（必填，空串合法＝清空）, idempotencyKey} | {written, verified, characters} | 写后回读比对才报成功；账本 objectID 恒 "clipboard"（单例对象，只记元数据） |
| files_list | {path?（缺省根目录）} | {path, readAt, count, entries[{name, path, isDirectory, sizeBytes?, modifiedAt}], truncated?} | 一层不递归；上限 500 条、超了标 truncated |
| files_read | {path} | {path, readAt, bytes, content} | 只回 UTF-8 文本；超 256 KB/非文本如实报错、不静默截断 |
| files_write | {path, content, idempotencyKey} | {path, written, verified, bytes} | 父目录自动建、原子写、回读逐字节比对；账本 objectID＝规范相对路径；回放只带文件元数据、不重读内容 |

四纪律照旧：写工具必带 idempotencyKey（解析层强校验）＋桥/App 双层去重（App 账本 24 小时窗口）；写完回读验证才报成功；设备离线即失败不排队（既有会话机制，桥 45 秒无心跳判离线）；错误结构化（invalid_arguments/permission_denied/tool_unavailable/device_error 与既有契约同码）。

### 111.2 授权形态：新权限档 notApplicable（跟一开关原则）

- 两件在 iOS 没有系统权限概念。DevicePermissionState 新增 .notApplicable：bridgeValue 报 "granted"（桥侧放行口径）、isUsable 为真、label 专名「无需系统权限」——与「已授权」严格区分，不画假的系统权限状态（钉测 testNotApplicablePermissionSemantics）。
- App 层 DevicePermissions.currentStates 对两件恒报此档；DeviceSessionController 的开关不与权限对齐（refreshPermissions 的对齐只作用于同步五件），保持用户亲手拨的独立开关、默认关、UserDefaults 逐件存。
- 详情页状态头：不渲染「系统权限」行（DeviceStatusHeader 对 notApplicable 省行），只剩「允许智能体调用」一个开关＋卡内一句「这一件没有系统权限可开可关：这个开关就是唯一的门…」；目录行/总览行状态字同源拼「无需系统权限 · 可调用/调用已关/会话未连接」。
- 注册载荷：permissions 两键恒 "granted"（桥不要据此拦 permission_denied，见 111.5），tools 只由开关门控（关→不列）。

### 111.3 路径安全（文件件）

- Core 纯函数 SandboxPath.normalize：相对路径限定——绝对路径（/ 开头）拒、".." 弹栈越界拒、NUL 拒、空段与 "." 收敛；读/写另经 normalizeFilePath 拒根目录本身。逐条钉测（testSandboxPathNormalize）。
- App 层 SandboxFilesEngine 二次保险：URL 逐段拼后 resolvingSymlinksInPath＋standardizedFileURL 仍须落在 Documents 根内（前缀校验），越界回 invalid_arguments。
- 上限：单次读/写 256 KB（SandboxPath.maxContentBytes，写在解析层先拒）、列表 500 条。

### 111.4 呈现与文案

- 名册 7→9（呈现序：日历→提醒→通讯录→照片→步数→剪贴板→文件→健康→家庭）；两件 batch 1 已接线。剪贴板条目文案如实写明「读取时系统会弹出粘贴提示」（blurb/agentNote/footnote 三处口径一致，testNewSourceCopyHonesty 钉）；文件条目写明只限自家文件夹与 256 KB 上限。
- 详情页两页新件：剪贴板页不自动读剪贴板（读本身可能触发系统提示），当前内容区只在用户亲手点按钮时现读一次；文件页＝本地文件夹浏览（与工具同一引擎同一边界，下钻/文本预览/错误原文如实显），不挂下拉刷新（sheet 与 push 共用，下拉归 sheet 关闭——0.36.5 口径）。
- 图标：文件按宪法 §4 复刻例外自绘系统「文件」蓝文件夹；剪贴板无对应系统应用，中性灰自绘字形、不冒充 App 图标。
- ToolCards：五工具归 .device 类（files_* 不被通用 file 类吞），中文标题五条（读取/写入剪贴板、查看文件列表、读取/写入文件）。
- L10n 补 26 键（目录 2278→2304 键、连 InfoPlist 共 2312 键，validate_i18n.py 实跑通过）：名册五字段×2、无需系统权限、卡片标题 3、详情页与总览文案等；繁体按目录既有惯例（智能体→智慧代理、调用→呼叫、文件夹→資料夾）。总览页脚文案换新整句（旧键留目录待主线处置，同 §109.5 先例）。执行层回执文本（引擎错误人话，给桥与智能体读）按 §109.5 先例不入目录。

### 111.5 桥侧待办清单（device-bridge／伴生 device 模块，后续接线包）

1. TOOLS 表补五件（名与 App 侧 DeviceToolRegistry 逐字一致）：clipboard_get/clipboard_set/files_list/files_read/files_write；入参/回执契约按 111.1 表。注意：表面图草案名 pasteboard_read/pasteboard_write 已被任务定名 clipboard_get/clipboard_set 取代，桥表若有草案残留须改名对齐、不留别名双轨。
2. permissions 字典新增键 clipboard/files：App 侧恒报 "granted"（无系统权限），桥对这两件不许走 permission_denied 拦截，门控只认注册 tools 清单在不在（开关关→不在清单→tool_unavailable，与既有件同路）。
3. 写工具桥侧 write-keys 一层去重对 clipboard_set/files_write 同样启用（App 账本为第二层）。
4. 上线顺序：桥表未补前，App 开关默认关、不列工具，无影响；接线验收时先补桥表再开 App 开关实测。桥未上线时 App 侧如实回 tool_unavailable 的三条路径（未知工具名/已定义未接线/开关关）在分发器已走通，Core 层以注册载荷门控钉测钉死（testRegistrationNotApplicableGating 等），不假装已通。

### 111.6 与设计档出入（逐条）

1. 工具名：表面图 A12 草案 pasteboard_read/pasteboard_write → 任务定名 clipboard_get/clipboard_set 落地（桥侧待办 1 提示对账）。
2. 工具集：表面图 A13 草案含 files_search → 本包按任务范围只做列/读/写三件，搜索不做（沙盒内全文搜索留后续）。
3. 文件范围：表面图 A13 设想「用户在文件选择器亲手选目录＋安全范围书签」的已授权目录 → 本包按任务收窄为 App 自有 Documents 区，选目录/书签面不做。
4. 授权形态：连接器设计档的双层呈现（系统权限行＋调用开关，健康/家庭形态）→ 两件无系统权限可呈，落为新档 notApplicable＋单开关（111.2），与一开关原则（用户 2026-11-10 拍板）一致；健康/家庭双层呈现未动。
5. A12 的「读需 App 前台、触发系统允许粘贴弹窗、只探测不触发」口径与本包实现一致（先 has* 探测后取内容），无出入、登记确认。

### 111.7 单测与终判口径

- 新增 11 个测试函数（DeviceSourcesTests +5：notApplicable 语义/载荷门控/目录行/非同步数据集/文案诚实；DeviceCallsTests +5：三组参数解析＋路径规范化组；RichContentTests +1：五工具分类与标题），全仓测试函数 1170→1181 只增不减。既有 6 个测试函数更新钉值（名册计数 7→9 与呈现序、批次、工具全集 10→15 与写集 4→6、可执行集 7→12、全开载荷、搜索计数），断言口径随名册扩容顺延、非放宽。
- 版本五处未动（合并时主线定号）。本机无 Swift 工具链：静态自查已做（逐文件括号配平与 HEAD 基线同差、目录键与代码引用全量对账零缺口、DeviceSourceID/DevicePermissionState 全部穷尽 switch 逐点排查并补臂——DeviceSyncDataset.fromSource、DeviceSyncControl.toggleOnAction、DeviceSyncExecutors.requestAccess、DeviceViews.permissionBinding、DeviceStore.requestAccess、两处详情分发）；编译与全套单测终判等合并后 CI。

## §112 无障碍专项包（2026-11-11，预制分支 feat/a11y，基线 main 67f756f；节号自选 §112，合并时主线终审如撞号顺延）

上架线 A11Y 批：走查 19 项（oneday-design-review/accessibility-inventory-20261110.md §1–§5，严重 3／中 9／低 7）＋整改台账 ui-remediation-ledger-20261110.md C 节 23 行的逐项处置。0.36.0 已销 6 项（V1/C1/C5/T1/S3/D4）与部分销 4 项（V4/V5/D2/S4）不在本节重述，只记本包的收口与新普查。版本五处未动（合并时主线定号）。

### 112.1 逐项处置总表

- **V2 图片文本等价（严重）·收口**：聊天三处图片（本地图/用户侧远程图/助手侧远程图）＋动态详情大图补最低文本等价：Core 新件 A11yText 拼装（有文件名用文件名、无则发送时刻、皆无回落「图片」），钉测 3 函数。图片元素合并为单一按钮元素＋「查看大图」提示＋默认动作与点按同一查看器入口。不编造内容描述——助手图/服务端图的自动描述生成是产品决策（走查 §7 B2 策略先行），未定案前宁缺毋假。
- **V3 流式碎片化·收口**：StreamingText 词元流对 VO 合并为整段文本元素（标签＝全文），词元回归纯视觉动画单位；完成播报走 S6 通道。
- **V4 行语义化·收口**（0.36.0 已落 C5 未读文字）：动态三行——胶囊行/简报行整行合并（有帖/可编辑才带按钮特征，默认动作与点按同入口）；帖行拆分：题＋摘为独立合并按钮元素、refs 内链与动作行留在元素外各自可达、类别瓷砖与配图缩略对 VO 隐藏（类别词/未读字在动作行有文字通道）。文件行（deliverableRow/mediaRow）同式：内容区合并为按钮元素、⋮ 菜单独立。
- **V5 选中态成套·收口**（模板两件 0.36.0 已落）：按房内两式先例（标签拼「已选」／.isSelected 特征）补齐五处——预置头像行、相册行（AgentAvatarEditors）、枢纽模型行（名＋注＋已选）、云电脑类型行（题＋详＋已选）、抽屉导航行＋频道行（只加特征，标签已有）。
- **V6 管理面成套·收口**：模型组合删除钮补标签「删除组合：<组合名>」（此前全 App 唯一无标签图标钮）；目标页 ⋮ 菜单钮补「更多操作」（与文件行同钮先例对齐）；会话行置顶/归档态补 accessibilityValue（ServerSessionRow.stateValue，两键已在目录）。
- **V7 Rotor/自定义动作·收口（Rotor 半）**：两处长列表加命名转子——全部对话「会话」（条目随当前段/搜索态现算、行标记挂 selectableRow/mainRowButton/搜索命中行三处分发）、文件页「文件」（条目随当前段名册、标记挂两行两卡四处）。形态为显式命名空间式（WWDC21 session 10119 外部核查：AccessibilityRotorEntry 命名空间版为位置参数 id，已按实证修正）。自定义动作半：本包未加——行级动作已有长按菜单全量通道（VO 可经菜单到达），再叠 accessibilityAction(named:) 是第二套动作面，留真机 VO 走查后按缺口定（见 112.6）。
- **D1 发送舱字号（严重）·收口，含口径改版**：见 112.2。
- **D2 钉字号普查·核实销账**：全仓 `.system(size:)` 约 124 处逐处分类，Text 接收仅 5 处且全豁免（分享卡渲染图固定画布/日历牌图形构图/缩略图字母字形——代码已注非阅读文字）；走查点名的旧点（Components 15pt、ConnectView 15pt×3、IdeasView 16pt）在现行代码全为字形。无剩余 UI 文字钉字号点，本普查表即销账证据。DocumentReaderView 的 UIFont 尺寸梯是文档排版梯（内容渲染面、非 UI 文字），登记缓办注记、不在本包动。
- **D3 AX 档验·收口（机制＋自查表）**：Design 新件 a11yLineLimit（标准档原行数逐字不变、AX 档放宽）落 8 面：全部对话行题/副＋搜索命中行、动态胶囊/简报/帖行题摘、文件两行题副、系统文件行、抽屉旁聊行题、共享 ContentRow 题/副（一处收口多面）。聊天附件牌固定高 54 改 minHeight（默认外观不变）。自查表见 112.3。文档阅读面与网格卡定高格（fileCard 文字区 64）是版式面、未动，表内如实登记。
- **C3 占位符口径·收口**：发送舱占位符由 .tertiaryLabel（合成约 1.9:1）改走文字级令牌 inkSecondary（对白面 4.97:1）——占位符是字段唯一说明、属要读的信息；随 updateUIView 与字体一并刷新（明暗/档位）。全仓其余占位符走系统 TextField prompt（系统自理），落点唯一、无散点。
- **T2 顶栏钮命中域·核实销账（前序已修）**：ChatView 顶栏两钮（0.23.0 命中域审计）与 DeliverablesView headerCircleButton 均为视觉盘 40＋外框 44＋contentShape，本包核实零代码。
- **S2 Reduce Transparency·核实销账**：响应点全仓仍 1 处（抽屉，§97.3 已注系统自理）；本包复核自绘半透明面只剩抽屉纱（模态压暗、非内容可读性面，不改已定）——glassEffect/系统材质/滚动边缘效为系统 API 自适应、Palette 点缀色全为不透明 hex，无新落点。
- **S4 单通道普查·核实销账**：录音钮全带标签、StatusDot 恒隐藏且与状态词同行（Components 既有纪律）、未读已双通道——无新单通道点；DifferentiateWithoutColor 是信息冗余纪律、本包普查即执行，无额外代码响应点。
- **S5 Increased Contrast·收口**：Palette appleColor 加高对比变体口（仅 traits 高对比＋浅档生效、默认解析逐字不变）：inkSecondary 挂 #43494E（设置底 8.18／页面底 8.89／卡面 9.12）、danger 挂 #8C332C（卡面 8.00／错误面 7.11），同色相加深、不新造颜色；语义色令牌本身随系统高对比自适应。钉测守「默认解析不变＋HC 全过 7:1」双闸。
- **S6 VO 运行态·收口（首点）**：新件 A11yAnnouncer（isVoiceOverRunning 守门＋公告投递）；生成完成在 ChatView 既有流式下降沿播报「回复完成」（与 0.36.21 待批刷新同沿、同等静默）。其余运行态适配（如焦点迁移）留真机走查定点，不预造。
- **注记 4 项（不施工，登记去向）**：V8 远程画面无等价——上架申报如实填写，不在本包；C2 泡内次级文字——纪律＋既有 grep 闸在位；C4 状态点 2.2:1——文字冗余纪律在位（S4 普查复证）；D4 粗体注记——已随 S3 于 0.36.0 销账。V1 的 toggle trait 维持原判不补（已销项，当时未赌的 trait 本包不翻案）。

### 112.2 D1 改版理由（推翻 0.2.9/ComposerTextView 旧注口径）

旧口径：发送舱字体固定 16pt、不跟随 Dynamic Type，理由是「量高与排版脱钩」。本包改版：字体经 UIFontMetrics（.body）按档缩放，脱钩以「档位显式贯穿」根治——量测链每一环都带档：视图取自身 traitCollection 的档（ComposerTextView 量高/内滚判定/几何施加）、布局取环境档经 OneDayDesign 映射注入（ComposerBarLayout.contentSizeCategory）、Core 纯函数全系加 category 变体（无参口回当前档、绝不回落 .large 另成一套账）。行高不另立档位表：由基准行高 × 该档字号比同源派生，封顶恒 6 行。基准档（.large）下字体/行高/封顶 115.02/胶囊 46 与旧定案逐字一致（钉测守），旧钉测全数不改。

### 112.3 D3 AX 自查表（关键页在大字号下的结论，静态普查口径）

| 面 | 标准档 | AX 档处置 |
|---|---|---|
| 聊天发送舱 | 46 起、封顶 115.02 | D1 全链按档：行高/封顶/胶囊同比例长高，超封顶内滚 |
| 聊天附件牌 | 高 54 | minHeight 54：文件名行可长高 |
| 全部对话行 | 题/副各 1 行 | a11yLineLimit(1, ax: 2)，行高随 List 自适应 |
| 动态帖行 | 题 2/摘 3 行 | 题 4/摘 6 行放宽 |
| 文件行/影音行/系统文件行 | 题/副各 1 行 | (1, ax: 2) |
| 设置类共享行（ContentRow） | 题/副各 1 行 | (1, ax: 2)，全 App 设置面同享 |
| 文件网格卡 | 文字区定高 64 | 版式格未动：AX 档下卡内题仍 1 行截断——如实登记，真机走查后定是否改格 |
| 文档阅读面 | UIFont 排版梯 | 内容渲染面、不属 UI 文字口径，缓办注记 |

### 112.4 视觉数值变更清单（本包全部）

默认档（.large、普通对比、标准行数）下全 App 逐字不变，除两处：①C3 占位符色 .tertiaryLabel→inkSecondary（全档可见变化、C3 收口本体，理由见 112.1）；②附件牌 height 54→minHeight 54（默认高度不变、仅内容更高时才长）。其余变化只发生在 AX 字号档（行数放宽/发送舱几何）、高对比 traits（两令牌变体）、VO 运行时（标签/播报/Rotor）。Feed 帖行新增内层 VStack：间距与外层同值（iconTextGap）、几何逐字不变。未新造颜色（HC 值为既有令牌加深档）、未引入新组件。

### 112.5 L10n 与单测

- L10n 补 7 键（目录 2304→2311、连 InfoPlist 共 2319 键，validate_i18n.py 实跑通过）：图片，%@／查看大图／回复完成／已置顶／已选／会话／删除组合；繁体守既有惯例（釘選/會話/刪除組合）。
- 新增 10 个测试函数（AccessibilityPackageTests：V2 拼装 3、档位映射 1、D1 几何 4、S5 解析 2），全仓 1181→1191 只增不减（总数承 §111.7 口径）。既有钉测零改动：D1 基准档逐字一致由新钉复证（封顶 115.02/胶囊 46/行高常数）。

### 112.6 遗留与终判口径

- V7 自定义动作半、S6 其余运行态点、网格卡 AX 格、DocumentReaderView 排版梯：留真机 VO/AX 走查定点，不预造。
- 本机无 Swift 工具链：静态自查已做（逐文件括号配平与 HEAD 基线同差、新标识符引用全量对账、Rotor API 经 WWDC21 session 10119 与社区实证外部核查并修正条目构造形态、目录键与代码引用对账）；编译与全套单测终判等合并后 CI。

## §113 设备扩容批二（预制分支 feat/device-x2，基线 main fc1f940；节号自选 §113，合并时主线终审如撞号顺延）

缘起：设备表面图（device-surface-map-20261110.md）A 档第三批「写与拉起」欠账——闹钟（A11）/本地通知（A10）/拉起（A20）三组动作型工具一直只有草案名。本包按任务定名与连接器设计档既有四纪律落成 App 侧全量（闹钟走 iOS 26 AlarmKit 真闹钟），桥侧 TOOLS 表单列待办（113.5）。

### 113.1 工具契约（App 侧已接线，DeviceToolRegistry 逐字名册）

| 工具 | 入参 | 成功回执 | 备注 |
|---|---|---|---|
| alarm_set | {title, at 与 afterSeconds 恰给其一, idempotencyKey} | 闹钟回读对象 {id, kind: fixed/countdown, state, title?, fireAt}＋verified＋humanSummary | 倒计时收敛 5 秒～24 小时；定点时刻已过解析后执行层拒；调度后回读系统闹钟列表含 id 才报成功 |
| alarm_list | 无 | {count, alarms[{id, kind, state, title?, fireAt}], readAt} | 存在性/状态以系统列表为准；标题由本机登记表补（见 113.3），登记缺失不编标题 |
| alarm_cancel | {alarmId（UUID 形）, idempotencyKey} | {cancelled, wasPresent, verified, humanSummary} | 正在响走 stop、其余走 cancel、回读不在册才报成功；本就不在册语义收敛但如实标 wasPresent=false；写工具（理由见 113.6 之 3） |
| notify_post | {title, body, delaySeconds?（缺省 0＝立即）, idempotencyKey} | {posted, verified, id, title, humanSummary, deliverAt?} | 延迟上限 7 天；调度后回读待发∪已送达含 id 才报成功；延时待发满 64 条如实拒（系统上限） |
| open_target | {target（白名单 id）, idempotencyKey} | {opened, target, name, humanSummary} | 目标未命中白名单在 Core 解析层就拒、不下发执行层；执行层设置页直开、应用先探装没装 |

四纪律照旧：写工具必带 idempotencyKey（解析层强校验）＋桥/App 双层去重（App 账本 24 小时窗口；批二引擎多为 async，分发器补 writeWithLedgerAsync，账本语义与同步形逐字一致）；回读验证才报成功（逐工具落点见上表）；离线即失败不排队（既有会话机制；open_target 打开成功即离 App、会话断开属预期，本次回执以 open 完成回调为准，重连后靠账本回放不重复跳）；复述确认载荷＝每件动作回执含 humanSummary（Core 参数层同源生成，智能体复述与用户确认同一句话）。

### 113.2 授权状态机与呈现分工（系统授权铁律的落法）

- Core 纯函数 DevicePermissionGate.decision(for:)：granted/limited/notApplicable→proceed、notDetermined→requestOnce、denied/restricted/writeOnly→degrade。引擎的授权请求函数一律先过此门再动作——铁律落进引擎本身、不靠调用方自觉（DeviceCallsTests.testPermissionGateDecisions 全档钉）。
- 闹钟：AlarmManager.authorizationState 是同步属性，先同步读现态（AlarmEngine.systemState）；只有 requestOnce 才发那一次 requestAuthorization；执行 setAlarm 时引擎内再复查现态。AlarmKit 全程 async/await、无 completion 回调，回调隔离铁律在本件无落点（登记确认）。
- 通知：UN 没有同步读状态 API——唯一出入，见 113.6 之 4。落法：状态缓存最近一次异步刷新值（NotificationEngine.cachedState，NSLock 护），刷新点三处＝进前台（DeviceStore.activate 补刷）、进详情页（NotificationsDetailView.reload 先刷）、执行前（分发器对 notifications 源先 await readSystemState 再判门，引擎 post 内再复查一次）——绝不拿陈缓存放行。getNotificationSettings 的 completion 闭包只 resume continuation（照 EK fetchReminders 的 nonisolated 先例），不碰引擎其他状态。provisional/ephemeral 归 granted 档（都是能发的临时授权形态，呈现不夸大）。
- 呈现分工（与批一严格区分）：闹钟/通知有真系统权限，走既有权限开关终形态——详情页状态头渲染「系统权限」开关（未定→requestAccess、已拒绝→跳设置页、拨关→跳设置页，DeviceViews.permissionBinding 既有语义自动成立）＋「允许智能体调用」开关双层；打开目标无系统权限，走批一 notApplicable 单开关形态（同 clipboard/files）。注册载荷：alarm/notifications 是真权限键、报系统原态；opener 报 granted（notApplicable 口径）。
- Project.swift：新增 NSAlarmKitUsageDescription（缺此键 schedule 必失败；文案说清「只有你在对话里确认、或在闹钟详情页亲手添加时才会设定」）＋LSApplicationQueriesSchemes 五条（App-prefs/weixin/alipay/iosamap/maps，供 canOpenURL 探测；系统上限 50 条远未及）。版本五处未动（合并时主线定号）。

### 113.3 AlarmKit 落法注记

- 呈现只给 Alert（标题＋系统默认停止钮，secondaryButton 不设）：倒计时/暂停的自绘界面才需要 widget 扩展，本包不建扩展、系统默认界面兜底（苹果官方示例与实战项目 RingWhen 均证 alert-only 可行）；倒计时进行中的灵动岛呈现走系统默认样式、无自绘——取舍登记。
- 标题登记表：Alarm 值回读不回吐 attributes，标题另存本机 UserDefaults 登记表（alarmID→标题/kind/预计响铃时刻，device.alarmRegistry.v1），只补呈现与对账；倒计时的预计响铃时刻按设定时刻＋时长在本机算（系统不直接给）。登记与系统不一致时以系统为准（取消/响过后回读不在册即不在册）。
- 配置构造照苹果官方示例五参形（countdownDuration/schedule/attributes/stopIntent: nil/secondaryIntent: nil，省略 intents 走系统标准停止行为）；倒计时＝CountdownDuration(preAlert: 秒, postAlert: nil)＋schedule: nil；定点＝Schedule.fixed(时刻)。元数据用自有 DeviceAlarmMetadata（AlarmMetadata，只含 title）。

### 113.4 拉起白名单（Core 可测）

- OpenTargetCatalog（Core）14 条：设置页 10（OneDay 自家设置页哨兵 app-settings＋Wi-Fi/蓝牙/蜂窝网络/通用/显示与亮度/声音与触感/通知/电池/隐私与安全性，App-prefs 根地址）＋应用 4（微信 weixin://、支付宝 alipay://、高德地图 iosamap://、苹果地图 maps://）。钉测守不变量：id 唯一、地址只许这四类已审计形态、http(s) 永不入册（testOpenTargetCatalogSafety）。
- 执行层边界：设置页恒在直接开（以 open 完成回调为成败准绳）；应用先 canOpenURL 探装没装，没装如实回「没有装在这台手机上」——注意 canOpenURL 只对 LSApplicationQueriesSchemes 已声明的 scheme 有效，声明与目录同批落地（113.2）。

### 113.5 桥侧待办清单（device-bridge／伴生 device 模块，后续接线包）

1. TOOLS 表补五件（名与 App 侧 DeviceToolRegistry 逐字一致）：alarm_set/alarm_list/alarm_cancel/notify_post/open_target；入参/回执契约按 113.1 表。表面图草案名 alarm_schedule/alarm_timer/notify_schedule/open_link/open_app 已被任务定名取代，桥表不留草案别名双轨。
2. permissions 字典新增键 alarm/notifications/opener：alarm/notifications 是真权限键——App 报系统原态（granted/denied/notDetermined…），桥可据此先行回 permission_denied，与 clipboard/files 的 granted 恒通口径本质不同、桥不许混；opener 同 notApplicable 口径报 granted，门控只认注册 tools 清单。
3. 写工具桥侧 write-keys 一层去重对 alarm_set/alarm_cancel/notify_post/open_target 同样启用（App 账本为第二层）；open_target 尤其要紧：用户被带离 App 后会话重连，智能体重发同键调用必须回放原回执、不许再跳一次。
4. 上线顺序同批一：桥表未补前 App 开关默认关、不列工具，无影响；接线验收先补桥表再开开关实测。桥未上线时 App 侧 tool_unavailable 三条路径在分发器已走通，不假装已通。

### 113.6 与设计档出入（逐条）

1. 工具名与合并：表面图 A11 草案 alarm_schedule＋alarm_timer 两件 → 任务定名合一为 alarm_set（时刻/倒计时二选一，解析层恰一校验）；A10 草案 notify_schedule/notify_pending/notify_cancel/notify_delivered 四件 → 任务定名只落 notify_post 一件，待发读面落在通知详情页本地呈现（不设工具），notify_cancel 不做（登记：任务范围未定；待发通知的撤销若后续要给智能体，另立小包再议）；A20 草案 open_link/open_app（任意 URL/scheme）→ 任务定名 open_target 白名单制（任意 URL 在解析层无入口）。
2. 授权呈现：批一为无权限件新立 notApplicable 档；本批闹钟/通知明确不套此档（任务明示），走既有双层权限开关终形态；只有 opener 套 notApplicable——三者在 DeviceStatusHeader 的分工由 permission 档自动分流，无新呈现代码。
3. alarm_cancel 与连接器设计档「删除不进任何工具面」红线的关系：该红线针对用户数据（日历/提醒/通讯录等系统数据源的删除）；闹钟是动作的产物、取消是该动作的配对收敛操作（表面图 A11 本就列 alarm_cancel，任务亦明文定名），且只能按 id 取消、取消前先查在册。它按写工具落（带幂等键走账本、回执可重放）。登记为红线的范围澄清，不作删用户数据的先例。
4. 通知权限的异步读出入：连接器设计档 §3.3/§6.5 的「App 现读现回、状态同步现读」口径在 UN 框架上无同步 API 可落——本包以「缓存＋三处刷新＋执行前真状态判门」等价落地（113.2），是全批唯一与铁律字面形态的出入：铁律的实质（已决定不重走请求回调、只有未决定才发那一次请求）由 DevicePermissionGate 在引擎请求函数内照样守死，差的只是状态读数多走一跳异步刷新。
5. AlarmKit entitlement 冲突核查（改前先搜口径）：个别网源（swiftcrafted 指南）称 AlarmKit 需向苹果申请 entitlement；与表面图已查证的苹果工程师论坛定谳（com.apple.developer.alarmkit 是不存在的假钥匙、无此 entitlement、A 档）冲突——从设计档既有定谳，不加任何 entitlement；若合并后真机 schedule 报权益类错误，回表修订本条。
6. 详情页门控文案：DevicePermissionGate 的未定文案动词随件走（闹钟「设定」/通知「发送」/余件「读取」），不拿「读取」糊弄动作权限——呈现层小改、同批登记。
7. 状态头 notApplicable 说明句为三件共用文案（「关掉后智能体就读不到、也写不了」），对 opener 是近似表述（打开目标无读/写语义、本质是「用不了」）；opener 名册 agentNote 已把边界写准，本包未为一句脚注拆共用组件——登记知悉，后续若逐面收口 C13 时一并处理。

### 113.7 单测与终判口径

- 新增 11 个测试函数（DeviceSourcesTests +2：批二载荷门控/文案诚实；DeviceCallsTests +8：授权门全档/闹钟参数两组/取消参数/通知参数/打开参数/白名单不变量/时长人话；RichContentTests +1：五工具分类与标题），全仓测试函数 1191→1202 只增不减。既有 6 处钉值更新（名册计数 9→12 与呈现序、批次接线 +3、工具全集 15→20 与写集 6→10、可执行集 12→17、全开载荷补三件断言、搜索空集计数、非同步数据集 +3 断言），口径随名册扩容顺延、非放宽。
- L10n 补 32 键（目录 2311→2343、连 InfoPlist 8→9 共 2352 键，validate_i18n.py 实跑通过）：名册五字段×3（「通知」名键已存在复用）、工具卡标题 5、拉起目标名 13（「微信」已存在复用）、NSAlarmKitUsageDescription 三语；繁体守既有惯例（智能体→智慧代理、调用→呼叫、设置→設定、闹钟→鬧鐘、白名单→白名單、锁屏→鎖定畫面）。详情页与引擎回执文本按 §109.5/§111.4 先例不入目录（执行层回执不入目录；详情页硬编码文案随既有详情页惯例如实登记——批一详情页同形态）。
- 本机无 Swift 工具链：静态自查已做（逐文件括号配平与 HEAD 基线同差、目录键与代码引用全量对账、DeviceSourceID 全部穷尽 switch 逐点排查并补臂——DevicePermissions.currentStates、DeviceStore 三处、DeviceSyncExecutors.requestAccess、DeviceSyncDataset.fromSource、DeviceViews 图标两开关＋详情分发、ConnectorsView.deviceDetail；AlarmKit/UN API 形态经苹果官方示例与生产项目外部核查定谳，见 113.3）；编译与全套单测终判等合并后 CI。

## §114 设备扩容批三·在场交互与端上智能（预制分支 feat/device-x3，基线 main fd69dd0；节号自选 §114，合并时主线终审如撞号顺延）

缘起：设备表面图（device-surface-map-20261110.md）第二章分批的第四批「在场交互与端上智能」欠账——A5 相机/A18 识别/A17 翻译/A19 端上模型/A24 本人确认五条一直只有表面图条目。本包落成 App 侧全量（新数据源五件＋工具七件），桥侧 TOOLS 表单列待办（114.5）。表面图条目原文逐条抄录于 114.1 表首列，处置与出入见 114.6。

### 114.1 表面图条目与工具契约（App 侧已接线，DeviceToolRegistry 逐字名册）

| 表面图条目（原文摘要） | 工具 | 入参 | 成功回执 | 备注 |
|---|---|---|---|---|
| A5 相机拍照/录像 `camera_capture`（AVFoundation，NSCameraUsageDescription，需用户在场交互；「取景框是当面动作、智能体只能发起不能代拍」；「可与 A18 组合：拍完即识别」） | camera_capture（写） | {idempotencyKey} | 文件回读对象 {name, path, isDirectory, modifiedAt, sizeBytes}＋saved＋verified＋capturedAt＋humanSummary | 拍什么/何时按快门全由用户当面决定、无其他入参；JPEG 落 OneDay 文件夹 captures/、回读逐字节核对才报成功；图片本体不进回执（见 114.6 之 2） |
| A18 文字识别与扫码 `vision_ocr`/`vision_scan_code`/`vision_document_scan`（Vision＋VisionKit；「本身无权限、权限随输入来源；OCR 无需在场、文档扫描需在场」） | vision_ocr | {path（OneDay 文件夹内图片）} | {path, readAt, text, lines, truncated?} | 纯端上计算；路径与 files_read 同一套 SandboxPath 规范化；行数 300/字数 2 万收敛、超限截断标 truncated |
| 同上 | vision_scan_code | {path} | {path, readAt, count, codes[{symbology, payload}]} | 读不出串的载荷跳过不编；码制名常见十种映射＋「其他码制」归类（见 114.6 之 9） |
| 同上 | vision_document_scan（写，归相机源） | {idempotencyKey} | {saved, verified, pageCount, pages[文件回读对象], humanSummary} | 系统扫描界面当面扫多页、逐页落 captures/scan-<印记>-p<页>.jpg；账本 objectID＝共同前缀、回放按前缀找回（见 114.6 之 7） |
| A17 翻译 `translate_text`（Translation iOS 18+，无权限无弹窗；「iOS 26 起有无头会话；语言包未下系统弹下载面」） | translate_text | {text（≤4000 字）, source, target?} | {text, sourceLanguage, targetLanguage, readAt, humanSummary} | iOS 26 无头会话（installedSource 构造式）；源语言必填（构造式要求明确，见 114.6 之 6）；target 缺省按源语言定（中文→英文、其余→简体中文）、回执回明实际值 |
| A19 端上大模型 `ondevice_model_run`（Foundation Models iOS 26+，无权限需前台；「硬件门：Apple Intelligence 机型＋系统开启＋语言/地区支持；可用性门先行——不支持就整件不列」） | ondevice_model_run | {prompt（≤3000 字）, instructions?（≤1000 字）} | {text, model: "on-device", readAt} | 每次新会话单次问答、不带上文（契约明示）；可用性门三落点见 114.2；上下文口径纠正见 114.6 之 1 |
| A24 生物识别确认 `auth_biometric`（LocalAuthentication，NSFaceIDUsageDescription，需在场；「只能验本人在场、读不到生物数据；定位＝高敏写操作前置门」） | auth_biometric（非写） | {reason（≤120 字，必填）} | {confirmed, outcome: confirmed/rejected/cancelled, biometry, verifiedAt, humanSummary} | 不带 idempotencyKey、不走账本（见 114.6 之 3）；验不过/取消是「这次确认的答案」以结果回，只有问不出口（未录入/不可用/没设密码）才走错误 |

四纪律落点：写工具（camera_capture/vision_document_scan）必带 idempotencyKey＋双层去重（回放只带已存文件的回读元数据——绝不因重发再弹一次取景框）；回读验证才报成功（落盘逐字节核对＋条目回读，逐工具见上表）；离线即失败不排队（既有会话机制；在场等待被桥侧取消时呈现桥自关界面、以取消错误收尾，不挂死会话）；复述确认载荷＝动作回执含 humanSummary（Core 参数层同源生成）。

### 114.2 授权分档与呈现分工（两档不许混的批三落法）

- 相机（camera）是真系统权限：AVCaptureDevice.authorizationStatus 同步可读，CameraEngine.systemState 现读、requestAccess 先过 DevicePermissionGate（只有未决定才发那一次 requestAccess(for: .video)，completion 只 resume continuation）；详情页走权限开关终形态（系统权限开关＋允许调用开关双层）；注册载荷报系统原态、桥可先行拦 permission_denied。vision_document_scan 同归相机门（呈现要相机权限，见 114.6 之 7）。
- 识别/翻译/端上智能/本人确认四件没有可开关的系统权限，恒 notApplicable、单开关即唯一的门（批一先例）：识别与翻译是纯端上计算；本人确认的「权限」只有用途说明串，同意在每次 evaluatePolicy 时由系统当面给出、LA 没有可预读的授权状态（见 114.6 之 4）；端上智能只有机型可用性门、不进权限档。
- 端上智能可用性门三落点（表面图「不支持就整件不列」的等价落地）：①注册载荷组装时（DeviceStore.beginRegister）机型不可用就把 ondevice_model_run 从 tools 摘掉——Core 静态名册不判机型事实；②详情页可用性行逐档如实（可用/机型不支持/未开启/未就绪）；③引擎执行时复查 availability，不可用如实回错。名册行本身恒列（它是能力目录不是可用性清单），代价与登记见 114.6 之 5。
- Project.swift：新增 NSCameraUsageDescription＋NSFaceIDUsageDescription（InfoPlist 键 9→11；文案说清发起方与落点：图片只存 OneDay 文件夹不进相册／面容数据不离开系统）。版本五处未动（合并时主线定号）。

### 114.3 框架落法注记（外部核查出处，2026-11-11 本包施工前逐条核对）

- 翻译无头会话定谳：苹果官方文档（TranslationSession 页，2026-11-01 版）明示 iOS 26 新增 `init(installedSource:target:)`——"for contexts where there's no UI, you can directly initialize"；源语言必须明确、目标可空；语言未装时 translate 抛错（拿下载许可须走 translationTask 的 UI 路，本包不走，见 114.6 之 6）。LanguageAvailability.status(from:to:) 同批核对存在（另有 status(for:to:) 按样本文本测语言，非本包所需）。表面图「iOS 26 起有无头会话」属实。
- Foundation Models：SystemLanguageModel.default.availability（.available／.unavailable 三因 deviceNotEligible/appleIntelligenceNotEnabled/modelNotReady）＋LanguageModelSession(instructions:)＋respond(to:)→response.content，多篇开发者文档与官方口径互证；错误走 GenerationError（exceededContextWindowSize/guardrailViolation/unsupportedLanguageOrLocale 逐个映射人话、其余带 default 臂兜底）。
- Vision 代际选择：OCR/扫码用 iOS 18+ Swift 原生请求 RecognizeTextRequest/DetectBarcodesRequest（perform(on:orientation:) 异步形、topCandidates/payloadString），不用 VN 前缀旧 API（全面原生令＋苹果现行推荐；多篇 2025–2026 实作互证）。EXIF 方向经 ImageIO 读出随图带入。文档扫描 VNDocumentCameraViewController iOS 26 仍可用（isSupported 先判）；外部对比文（Scanbot）报 iOS 26 上该系统界面有显示小毛病——属系统界面问题、不影响落盘契约，登记知悉、真机验收时留意。
- 相机呈现桥 DeviceCaptureBridge：照 DocumentPickerBridge 已验形态（最顶层 VC 呈现＋coordinator 静态强持有＋先 dismiss 再交回），加等待取消收尾（withTaskCancellationHandler→关界面＋取消错误）。UIImagePickerController 取原图、JPEG 0.85（聊天 CameraPicker 同参）。
- LocalAuthentication：evaluatePolicy 用 async 形（iOS 15+ 既有）；LAError 一律经 NSError 的 LAErrorDomain＋code 对照判定，不依赖错误类型的桥接形态（防签名/桥接差异，照本仓「核查证方向不证签名」的加码教训选最稳形态）。
- iOS 26.0 目标口径：批二 AlarmKit 26.1 构造式教训在前——本包所用 API 全部是 26.0 SDK 既有形态，26.1+ 新增形态一律不用。

### 114.4 名册与呈现

- 名册五件插在 opener 之后、health 之前（呈现序钉测更新）；图标按批二自绘语汇（彩色圆角底＋白色 SF 字形共用 glyphArtwork 构造：相机深灰/camera.fill、识别青/text.viewfinder、翻译蓝/translate、端上智能紫/apple.intelligence、本人确认近黑/faceid），不冒充系统应用图标。详情页五页均只有状态头＋一节本地面：相机＝已拍列表＋本地拍照按钮（与工具同引擎路）；识别＝captures 图片点按试认；翻译＝常用语言对下载状态现查；端上智能＝可用性一行；本人确认＝验证方式＋本地试一次。门控未定文案动词补相机「使用」一档。总览页脚长文案补批三一句（文案字面量、按批二先例不新入目录键）。
- 工具卡分类：ToolCards 设备分支补 camera_/translate_/ondevice_/auth_ 前缀＋vision 三件精确名（vision_ocr 等须排在 contains("vision") 的视觉类之前归设备；vision_analyze 仍归视觉类，钉测守）。

### 114.5 桥侧待办清单（device-bridge／伴生 device 模块，后续接线包）

1. TOOLS 表补七件（名与 App 侧 DeviceToolRegistry 逐字一致）：camera_capture/vision_ocr/vision_scan_code/vision_document_scan/translate_text/ondevice_model_run/auth_biometric；入参/回执契约按 114.1 表。本批草案名与定名一致，桥表不留别名双轨。
2. permissions 字典新增键 camera/vision/translate/ondevice/biometric：camera 是真权限键（App 报系统原态，桥可先行回 permission_denied，与 alarm/notifications 同档）；其余四件 notApplicable 口径报 granted、门控只认注册 tools 清单——两档不许混。另注：ondevice_model_run 在 tools 里出现与否随机型可用性变（App 注册时摘除），桥不要把「某轮没列」判成异常。
3. 写工具桥侧 write-keys 一层去重对 camera_capture/vision_document_scan 启用（App 账本为第二层）；auth_biometric 明确不许套 write-keys 回放——每次调用都要真问一次，桥侧重试也应原样下发由 App 现场再验（接线时点名，防顺手套模板把在场门放掉）。
4. 在场类超时口径：camera_capture/vision_document_scan/auth_biometric 都要等用户当面操作，桥侧 tool_call 超时须给足（建议 ≥120 秒量级，按桥现行上限评估后落数）；App 侧等待被取消会自关界面回错误收尾，不挂死。
5. 上线顺序同前两批：桥表未补前 App 开关默认关、不列工具，无影响；接线验收先补桥表再开开关实测。真机端到端（真拍＋OCR 组合、扫文档、翻译已装语言对、端上问答各一、本 人确认过/取消各一）随 App 版本发出后另验，不冒充已通。

### 114.6 与设计档出入（逐条）

1. A19 上下文数字纠正：表面图写「约 8k token」，外部核查口径为 4096 token 总上下文（含指令＋提示＋回答，多源一致）——参数上限按 4096 保守收敛（prompt 3000 字＋instructions 1000 字），框架超限另有兜底如实报错。表面图该数待回表修订。
2. camera_capture 的回图通道：表面图写「图回调用方（与聊天图片链共用回图通道）」——本包落法是图片落盘 captures/＋回执只回文件回读元数据，不把图片字节塞进工具回执（与 files_read 的 256 KB 文本上限同理：回执是给智能体读的账面、不是图床）；「拍完即识别」的组合由 vision_ocr 读同一路径当场接上，信息不断链。图片字节直达智能体须经 /api/files/upload，而分发器现行签名不持有服务器配置——登记为后续小包议题，本包不扩分发器签名。
3. auth_biometric 不带 idempotencyKey、不入写集：与四纪律「写/动作类必带」表面冲突，定性澄清——它不改变任何系统状态，本质是当面问答；24 小时账本回放一枚旧「确认通过」恰好把这件存在的前提（在场）放掉，与用途正相反。故按读类落（无键、每次必真问），DeviceToolSpec 注释与写集钉测（12 件）同步登记此口径，不作其他动作破例的先例。
4. 本人确认的权限档：NSFaceIDUsageDescription 不是可开关的系统权限（无授权状态可预读、无「已拒绝」持久态），归 notApplicable 单开关档；「问不出口」的情形（未录入面容/指纹、设备不支持、没设锁屏密码）在引擎内以 canEvaluatePolicy 逐档判明并如实回错——与批二通知「无同步读 API」的出入同族（框架形态决定落法，铁律实质不让步）。
5. 端上智能名册行与可用性：可用性门落在注册 tools 过滤＋详情页＋执行复查三处，名册行恒列——代价是不支持的机型上，该行在「开关开＋会话在线」时状态字仍会拼「可调用」（行状态由 Core 静态口径拼、无机型事实入口）；但注册清单里根本没有这件工具、智能体实际调不到，执行复查再兜一层。登记知悉；若后续要让行状态也认可用性，须给 DeviceRowStatus 加 App 层事实入口，另议。
6. 翻译源语言必填与下载面：无头构造式要求源语言明确（不能靠自动识别兜底），故 source 在契约层必填，与表面图「无弹窗」并不冲突；语言包未下载时本包如实回错并指路（详情页语言对状态/系统翻译设置），不在工具调用里弹系统下载面——下载面需要 UI 在场、与分发器的非 UI 上下文不合，且「替用户决定下载」本就该由用户亲手做。
7. vision_document_scan 归相机源：表面图把它列在 A18 名下（框架确属 VisionKit），但它的呈现与权限都是相机——名册 source 定 .camera、权限与开关随相机走，vision 源只辖对已存图片的纯计算两件。桥侧 permissions 键随此分工（见 114.5 之 2）。
8. 本批范围界线：A21 拉起撰写（call_start/compose_sms/compose_email/share_sheet）与 A22 shortcut_run 同具「需在场」属性，但表面图归第三批「写与拉起」（批二只落了其中 A10/A11/A20），A14 媒体控制、A26 文件呈现/打印同属未覆盖欠账——均不在本包范围，登记待后续批；A6 麦克风录音未被表面图分入任何一批、且与已上线听写共用麦克风权限（A25），本包不碰。A8 后台定位（授权最重）与 A15 蓝牙（已决不做）继续排除。
9. 码制名口径：BarcodeSymbology 是可扩展结构体、无可依赖的出串口径——常见十种逐个给人话名，其余归「其他码制」，宁可归类不编名（与闹钟标题「登记缺失不编」同纪律）。
10. 详情页与引擎回执文本按 §109.5/§111.4 先例不入 L10n 目录（执行层回执不入目录；详情页硬编码文案随既有详情页惯例登记）；入目录的是名册五字段与工具卡标题（经 L10n.string 取词，两处合计 30 键）＋InfoPlist 两键。

### 114.7 单测与终判口径

- 新增 8 个测试函数（DeviceSourcesTests +2：批三载荷分档门控/文案诚实；DeviceCallsTests +5：拍照扫描必带键/识别路径规范化/翻译参数/端上参数/本人确认参数；RichContentTests +1：七工具分类标题＋vision_analyze 不误收），全仓测试函数口径以 CI 实跑为准、只增不减（合并前基线 1202，预期 1210）。既有 7 处钉值更新（名册计数 12→17 与呈现序、批次接线 +5、工具全集 20→27 与写集 10→12、可执行集 17→24、全开载荷补五件断言、搜索空集计数 12→17、非同步数据集 +5 断言），口径随名册扩容顺延、非放宽。
- L10n 补 30 键（Localizable 2343→2373）＋InfoPlist 补 2 键（9→11），合计 2352→2384，validate_i18n.py 实跑通过；繁体守既有惯例（智能体→智慧代理、调用→呼叫、文件夹→資料夾、档案用檔案、端上智能→端上智慧）。
- 静态自查已做：逐文件括号配平与基线同差；DeviceSourceID 全部穷尽点逐点排查并补臂（DevicePermissions.currentStates、DeviceStore 开关字典＋requestAccess＋注册过滤、DeviceSyncExecutors.requestAccess、DeviceSyncDataset.fromSource、DeviceViews 图标底色/字形两开关＋门控动词＋详情分发、ConnectorsView.deviceDetail）；目录键与代码引用全量对账；框架 API 形态经苹果官方文档与多篇实作外部核查定谳（114.3）。本机无 Swift 工具链：编译与全套单测终判等合并后 CI。

## §115 设备扩容批四·日常面（预制分支 feat/device-x4，基线 main 3be6e05；节号自选 §115，合并时主线终审如撞号顺延）

缘起：清设备表面图（device-surface-map-20261110.md）A 档剩余欠账。§114.6 之 8 点名登记的四组（A14 媒体库、A21 拉起撰写、A22 快捷指令、A26 文件呈现/打印）＋本包开工核查发现的同类欠账两条（A7 定位在代码里完全不存在——全仓无 CoreLocation、无定位数据源、DESIGN 从未处置；A16 的 device_status 由桥本地应答、只含会话/权限面，草案的机型/电量/存储/网络等设备事实字段从未实现）一并落成 App 侧全量：新数据源五件＋新工具十五件（其中 file_preview/file_print 两件挂既有 files 源）。桥侧 TOOLS 表单列待办（115.5）。A 档 26 项逐项去向见 115.1 尾表——至此 A 档全部条目都有明确处置。

### 115.1 表面图条目与工具契约（App 侧已接线，DeviceToolRegistry 逐字名册）

| 表面图条目（原文摘要） | 工具 | 入参 | 成功回执 | 备注 |
|---|---|---|---|---|
| A7 定位·当前与附近 `location_current`/`location_search_places`/`location_geocode`（CoreLocation＋MapKit，NSLocationWhenInUseUsageDescription；「临时一次授权也是合法回值须处理」；「『我在哪』『附近有没有药店』类问答的主力」） | location_current | {}（无入参） | {readAt, latitude, longitude, accuracyMeters, locatedAt, placeName?, address?, humanSummary} | 一次性定位（百米级精度档、20 秒超时）；地名逆地理尽力而为、查不到字段缺省不编；精度原样带出（临时一次授权与正式授权在状态上同档、靠精度读数如实呈现） |
| 同上 | location_search_places | {query, limit?（缺省 10、收敛 1…20）} | {readAt, query, count, places[{name, latitude, longitude, distanceMeters, address?}], humanSummary} | 先定位再以当前位置为中心检索（见 115.6 之 5）；距离是与当前位置的直线距离、现算现回 |
| 同上 | location_geocode | {address} 或 {latitude, longitude}（恰给其一，解析层钉死） | {readAt, mode: forward/reverse, address?, latitude, longitude, placeName?, humanSummary} | 正逆双向；坐标范围逐个校验；查不到如实失败 |
| A14 音乐媒体库 `media_library_search`/`media_playlists`/`media_playlist_create`/`media_playback_control`（MediaPlayer，NSAppleMusicUsageDescription＋MPMediaLibrary.requestAuthorization；「读不到『别的 App 正在放什么』（见 C6）；Apple Music 订阅内容可检索、播放受订阅态约束」） | media_library_search | {query, kind?（song/album/artist/playlist/podcast/any，缺省 any）, limit?（缺省 20、收敛 1…50）} | {readAt, query, kind, count, truncated?, results[按 type 分形], humanSummary} | 歌按标题∪艺人合并去重；专辑/艺人按集合（带 itemCount）；歌单按名过滤（带 name/itemCount）；只回书目信息、音频本体不出手机 |
| 同上 | media_playlists | {}（无入参） | {readAt, count, truncated?, playlists[{type, id, name, itemCount}]} | 全量列歌单、上限 200 收敛（与 files_list 同口径） |
| 同上 | media_playlist_create（写） | {name（≤100 字）, idempotencyKey} | 歌单对象 {type, id, name, itemCount}＋created＋verified＋humanSummary | 系统口建空歌单；账本 objectID＝persistentID，建完按 id 在歌单列表回读核对才报成功；回放带歌单当前回读、不再建第二个 |
| 同上 | media_playback_control（写） | {action（play/pause/stop/next/previous）, query?（仅 play：先按关键词找到那首歌再播）, idempotencyKey} | {action, verified, state, nowPlaying{title, artist?}?, humanSummary} | 作用于系统音乐播放器；动作后轮询回读至多约 1.5 秒、达成口径逐动作定（见 115.6 之 6），达不到如实失败 |
| A21 拉起撰写 `call_start`/`compose_sms`/`compose_email`/`share_sheet`（MessageUI/UIKit，无权限弹窗、需用户在场交互；「发出动作永远由用户在系统面上亲手点」「这是『把人带到发送门口』，不是代发」） | call_start | {number（形态校验：数字与 +*#-() 空格、≥1 位数字、≤32 字符）} | {initiated, number, note, humanSummary} | 打开 tel: 地址、系统弹拨号确认面；号码里的 #/* 在 URL 里转义；不带幂等键、不入写集（见 115.6 之 2） |
| 同上 | compose_sms | {recipients[≥1，逐个过号码形态校验], body?（≤2000 字）} | {presented, outcome: sent/cancelled, sent, note?, humanSummary} | 预填打开系统短信撰写面；canSendText 先判；结果以面上当场事实为准（用户取消是正常结局、以结果回不作错误） |
| 同上 | compose_email | {to[≥1，逐个粗验含 @], subject?（≤200 字）, body?（≤5000 字）} | {presented, outcome: sent/savedDraft/cancelled, sent, note?, humanSummary} | 同短信口径；「存了草稿」单独一档（savedDraft、sent=false），不许混进已发送；canSendMail 先判、没配邮件账户如实失败 |
| 同上 | share_sheet | {text?（≤4000 字）, path?（OneDay 文件夹内）}（至少给一样） | {presented, shared, note?, humanSummary} | 文字与/或文件递到系统分享面；用户选了去向才算 shared=true，取消如实回 false、不作错误 |
| A22 运行指定快捷指令 `shortcut_run`（Shortcuts URL 方案，无权限、需用户在场；「可带文本输入，x-callback 变体可取回结果」「只能按名运行、不能枚举（见 C7）；成败以回调为准，无回调只报『已发起』不许报成功」） | shortcut_run | {name（≤100 字）, input?（≤2000 字）} | 成功 {ran, callbackReceived, name, result?, humanSummary}；取消 {ran: false, callbackReceived, outcome: cancelled, note}；无回执 {initiated, callbackReceived: false, name, note}；出错走 device_error | x-callback-url 变体：回执地址带一次性 nonce 对号（oneday://shortcut-callback/<nonce>/<档>，RootView.onOpenURL 交 ShortcutCallbackCenter）；等待上限 100 秒（见 115.6 之 4）；不带幂等键、不入写集（每次必真跑一次） |
| A16 设备与网络状态 `device_info`（UIKit/ProcessInfo/Network，「全部免权限」「给智能体当『先导判断』：电量低别派重活、离线别查网络；例外：用户给手机起的名字在 B7」） | device_info | {}（无入参） | {readAt, model, modelIdentifier, systemName, systemVersion, batteryState, batteryPercent?（读不到时 batteryKnown: false）, lowPowerMode, storageTotalBytes, storageFreeBytes, network, humanSummary} | 机型只报标识原文（见 115.6 之 7）；电量开监测现读；网络走 NWPathMonitor 一次性快照（5 秒兜底回「未知」）；B7 手机名/B8 Wi-Fi 名卡付费权益不在此列、名册文案已明说 |
| A26 打印与预览 `file_preview`/`file_print`（UIKit QuickLook/UIPrint，无权限、需用户在场；「价值在『让用户当场看到智能体产出的文件』，与文件页共用渲染」） | file_preview | {path（OneDay 文件夹内，与 files_read 同一套 SandboxPath 规范化）} | {viewed, path, humanSummary} | 系统 QuickLook 面打开给用户看；以用户关掉预览面（DidDismiss）为完成信号；挂 files 源、权限与开关随文件走 |
| 同上 | file_print | {path（同上）} | {presented, printed, path, note?, humanSummary} | canPrint 先判、打不了的文件如实失败；系统打印面完成回调为准，取消如实回 printed=false、不作错误 |

四纪律落点：写工具（media_playlist_create/media_playback_control）必带 idempotencyKey＋双层去重（回放语义逐工具见上表——建歌单回放带回读、播放控制回放上次回执不重发动作）；回读验证才报成功（建歌单按 persistentID 回读、播放控制轮询回读状态、定位/设备信息现读现回本身即事实）；离线即失败不排队（既有会话机制；在场等待被桥侧取消时各呈现桥自关界面、以取消错误收尾）；复述确认载荷＝动作回执含 humanSummary（Core 参数层同源生成）。在场六件（call_start/compose_*/share_sheet/shortcut_run/file_preview/file_print）不入写集的定性见 115.6 之 2。

**A 档 26 项全处置表**（批一 §111／批二 §113／批三 §114／本包 §115／其他通道／登记不做）：

| # | 项 | 去向 |
|---|---|---|
| A1 日历 | 批一已上线（§111） |
| A2 提醒事项 | 批一已上线（§111） |
| A3 通讯录 | 批一已上线（§111） |
| A4 照片图库 | 读面（计数与元数据）已由同步副本承担（0.36.14 照片数据集、桥查同步索引）：草案 photos_search/photos_recent 的能力面与副本查询同义，现调版不重复建（见 115.6 之 3）；photos_fetch_image（取图本体）表面图自注「二段再议」至今未议、photos_save_image（写入相册）是新相册写面且照片源现调形态未定——两件登记不做，待二段议定再排 |
| A5 相机 | 批三已上线（§114） |
| A6 麦克风录音 | 登记不做：工单明示不碰——与听写（A25）共用麦克风权限、表面图未分入任何一批 |
| A7 定位·当前与附近 | 本包落三件（见上表） |
| A8 定位·后台与到达离开 | 登记不做：表面图明示「不进前四批」（授权最重、审核最严） |
| A9 运动步数 | 已由同步副本承担（0.36.14 步数数据集、手机计步按日合计）：现调 motion_steps 与副本同义、不重复建（见 115.6 之 3） |
| A10 本地通知 | notify_post 已由批二落（定名与草案 notify_schedule 不同、以 §113 为准）；notify_cancel 登记待议（§113.6 已立：取消用户可能需要的提醒须另议口径，本包不擅自补）；notify_pending/notify_delivered 的读面由通知详情页本地呈现承担，工具面登记待议 |
| A11 闹钟与计时器 | 批二已上线（§113） |
| A12 剪贴板 | 批一已上线（§111） |
| A13 文件 | 批一已上线（§111；files_search 当时已收窄不做）；本包另补 file_preview/file_print 两件（A26） |
| A14 音乐媒体库 | 本包落四件（见上表） |
| A15 蓝牙外设 | 登记不做：用户已拍板不做（表面图本行自注） |
| A16 设备与网络状态 | 本包落 device_info 一件（见上表） |
| A17 翻译 | 批三已上线（§114） |
| A18 文字识别与扫码 | 批三已上线（§114） |
| A19 端上大模型 | 批三已上线（§114） |
| A20 打开应用与链接 | 批二已上线（§113 的 open_target 白名单封闭形态；定名与草案 open_link/open_app 不同、以 §113 为准） |
| A21 拉起撰写 | 本包落四件（见上表） |
| A22 运行指定快捷指令 | 本包落 shortcut_run 一件（见上表） |
| A23 自家动作注册（被调用方向） | 登记不做：方向相反（让系统调 OneDay）、不是桥工具，表面图自注「单列不混」，属产品面另议 |
| A24 生物识别确认 | 批三已上线（§114） |
| A25 语音识别（听写） | 已上线（0.36.x 听写，非设备工具面） |
| A26 打印与预览 | 本包落 file_preview/file_print 两件（见上表） |

B 档 11 项全部卡付费开发者账号（B1 健康/B2 家庭两件已在名册 batch 2 占位、B7/B8 是 device_info 的两个缺省字段）、C 档 12 项系统不给、未证 2 项（U1 专注状态/U2 附近交互）——本包均不碰，维持原登记。

### 115.2 授权分档与呈现分工（两档不许混的批四落法）

- 定位（location）是真系统权限：CLLocationManager().authorizationStatus 同步可读，LocationEngine.systemState 现读、requestAccess 先过 OneDayCore.DevicePermissionGate（只有未决定才发那一次请求，等待者自持活到回调、回调只 resume 不碰别的状态）；详情页走权限开关终形态；注册载荷报系统原态、桥可先行拦 permission_denied。只有「使用时」一档（不申请「始终」——那是 A8 的面，本包不碰）。
- 媒体库（media）是真系统权限：MPMediaLibrary.authorizationStatus 同步可读，requestAccess 同过门落法（requestAuthorization 的回调只带出状态枚举）；详情页走权限开关终形态；播放控制与检索共用同一道门。
- 拨号与撰写/快捷指令/设备信息三件没有可开关的系统权限，恒 notApplicable、单开关即唯一的门（批一先例）：撰写的把关在系统撰写面当场（用户亲手点发送）、快捷指令的把关在按名＋回执、设备信息全是免权限现读。file_preview/file_print 随 files 源的 notApplicable 单开关，不新设门。
- Project.swift：新增 NSLocationWhenInUseUsageDescription＋NSAppleMusicUsageDescription（InfoPlist 键 11→13；文案钉死边界：定位不做后台/不存副本、媒体库只回书目不出音频）；新增 CFBundleURLTypes 注册 oneday scheme（快捷指令 x-callback 回执专用）；LSApplicationQueriesSchemes 补 shortcuts（5→6 条，系统上限 50）。版本五处未动（合并时主线定号）。

### 115.3 框架落法注记（外部核查出处，2026-11-11 本包施工前逐条核对）

- 快捷指令 URL 方案定谳：苹果《快捷指令用户指南》（表面图出处清单已引）——shortcuts://run-shortcut 按名运行、x-callback-url 变体以 x-success/x-error/x-cancel 三个回调地址取回结果，成功时文本输出随 result 参数带回；无「列出全部快捷指令」的 API（C7），故详情页只能亲手填名。本包回执中心按一次性 nonce 对号，任意外部链接打进 oneday scheme 对不上 nonce 即安静忽略。
- MediaPlayer：MPMediaLibrary.getPlaylist(with:creationMetadata:) 是系统建歌单正道（完成回调给出 MPMediaPlaylist，creationMetadata 以 MPMediaPlaylistPropertyName 给名）；MPMusicPlayerController.systemMusicPlayer 即 A14 口径的「系统音乐播放器」（setQueue/play/pause/skip 与 playbackState/nowPlayingItem 回读面齐全）；MPMediaQuery 的 songs/albums/artists/playlists/podcasts 五查询＋MPMediaPropertyPredicate contains 过滤是书目检索正道。MPMediaPlaylist 跨 continuation 边界照批二 ReminderBox 先例盒包。
- MessageUI：MFMessageComposeViewController.canSendText/MFMailComposeViewController.canSendMail 是类方法先判面；结果枚举逐档映射（短信 sent/cancelled/failed、邮件 sent/saved/cancelled/failed），delegate 先 dismiss 再交回（批三协调者形态）。
- CoreLocation 一次性定位：requestLocation＋CLLocationManagerDelegate（didUpdateLocations/didFailWithError）是正道；授权状态是实例的同步属性。delegate 回调在管理器创建线程（主线程）的运行循环投递——协调者状态只在主线程回调与主 actor 任务里触碰、回调不继承 actor 隔离（回调隔离铁律，批三协调者同纪律）。
- MKPlacemark 在 iOS 26 已标弃用但仍可用：地点检索的坐标/地址分量本包仍用 placemark 取（与 CLPlacemark 同族字段、行为已验），不冒进 26 新增的 MKAddress 面；弃用只是警告、不影响构建，登记知悉（见 115.6 之 8）。
- 打印与预览：UIPrintInteractionController.present(animated:completionHandler:) 在 iPhone（本工程 TARGETED_DEVICE_FAMILY=1）直接可用、canPrint(URL) 先判可打性；QLPreviewController 以 previewControllerDidDismiss 为「用户看完了」的完成信号（预览没有成败回调，这就是它的全部事实）。
- iOS 26.0 目标口径：批二 AlarmKit 26.1 构造式教训在前——本包所用 API 全部是 26.0 SDK 既有形态，26.1+ 新增形态一律不用。

### 115.4 名册与呈现

- 名册五件插在 biometric 之后、health 之前（按接线批次序追加，健康/家庭恒居尾）；图标沿批三自绘语汇（彩色圆角底＋白色 SF 字形共用 glyphArtwork 构造：定位蓝/location.fill、媒体库红/music.note、拨号与撰写浅蓝/square.and.pencil、快捷指令深靛/bolt.fill、设备信息灰/iphone），不冒充系统应用图标。
- 详情页五页均只有状态头＋一节本地面：定位＝本地试读一次（地名＋精度原样显，权限不可用时换降级说明）；媒体库＝播放状态一行＋歌单列表（名＋首数现读，权限不可用时换降级说明）；拨号与撰写＝空预填试写短信/邮件（与工具同桥同结果口径）；快捷指令＝亲手填名运行一条（系统不给枚举、这是对名字的唯一办法）；设备信息＝快照逐行（机型标识/系统/电量/低电量/存储/网络）＋重读按钮。file_preview/file_print 不新增详情页（文件页已有自家文本预览；工具面给的是系统 QuickLook/打印面，形态不同、互不冒充）。
- 在场面单飞门（本包新增 DevicePresenceGate）：撰写/分享/预览/打印/快捷指令回执等待同一时间只许一件在场，第二件如实回「先处理完前一个」；批三拍照/扫描有各自桥内协调者、不经此门（本包不回改批三，两套并存的口径差登记知悉——分发器串行执行工具调用，此门主要防详情页本地动作与工具调用撞面）。
- 工具卡分类：ToolCards 设备分支补 location_/media_/compose_/shortcut_ 前缀＋call_start/share_sheet/file_preview/file_print 逐名（file_* 两件须抢在 contains("file") 的文件类之前落设备类；read_file 等服务端文件工具仍归文件类，钉测守）。

### 115.5 桥侧待办清单（device-bridge／伴生 device 模块，后续接线包）

1. TOOLS 表补十五件（名与 App 侧 DeviceToolRegistry 逐字一致）：location_current/location_search_places/location_geocode/media_library_search/media_playlists/media_playlist_create/media_playback_control/call_start/compose_sms/compose_email/share_sheet/shortcut_run/device_info/file_preview/file_print；入参/回执契约按 115.1 表。批一至批三的十七件已由伴生 1.0.8–1.0.10 逐批接线，本批十五件是当前唯一待补批；草案名与定名一处不同：A21 草案 share_sheet 等四名与定名一致、A14/A22/A26 亦一致，无别名双轨问题。
2. permissions 字典新增键 location/media/compose/shortcuts/deviceinfo：location/media 是真权限键（App 报系统原态，桥可先行回 permission_denied，与 alarm/notifications/camera 同档）；compose/shortcuts/deviceinfo 是 notApplicable 口径报 granted、门控只认注册 tools 清单——两档不许混。file_preview/file_print 随既有 files 键放行、无新键。
3. 写工具桥侧 write-keys 一层去重只对 media_playlist_create/media_playback_control 启用（App 账本为第二层）；call_start/compose_sms/compose_email/share_sheet/shortcut_run/file_preview/file_print 明确不许套 write-keys 回放——与 auth_biometric 同理：回放一枚旧「已打开撰写面」回执会让智能体以为这次也交到了、把在场前提放掉（接线时点名，防顺手套模板）。
4. 在场类超时口径：compose_sms/compose_email/share_sheet/file_preview/file_print 要等用户当面操作、shortcut_run 要等 x-callback 回执（App 侧等待上限 100 秒）——桥侧 tool_call 超时按批三在场类同档给足（伴生 1.0.10 已落的 150 秒可覆盖本批）；location_*/media_*/device_info 是现读现回，走普通超时即可。
5. 上线顺序同前三批：桥表未补前 App 开关默认关、不列工具，无影响；接线验收先补桥表再开开关实测。真机端到端（定位现读＋附近检索、媒体检索/建歌单/播放控制、拨号确认、短信与邮件的发出/取消各一、分享、带回执的快捷指令跑通一条、设备信息、文件预览/打印各一）随 App 版本发出后另验，不冒充已通。

### 115.6 与设计档出入（逐条）

1. 批四扩入 A7/A16（超出 §114.6 之 8 点名的四组）：开工核查实证——定位在代码里完全不存在（全仓无 CoreLocation 引用、无 location 数据源，DESIGN 亦从未处置，尽管表面图第二章曾把它列进「第一批·纯读」）；A16 的 device_status 由桥本地应答、只含会话/权限面，草案设备事实字段从未实现。两条同属「A 档剩余欠账」且与本批形态同族（真权限现读/零权限现读），本包一并清掉、不再留第五批；回报里单独标明此扩围。
2. 在场六件不入写集、不带 idempotencyKey 的定性：与四纪律「写/动作类必带」表面冲突——call_start/compose_*/share_sheet/shortcut_run/file_preview/file_print 不自己改变任何系统状态，只是把系统界面交到用户手上（发出与否、跑不跑完、看不看完都由用户当场决定）；账本回放一枚旧「已打开」回执恰好把这件存在的前提（在场）放掉，与用途正相反。故按非写落（无键、每次必真开一次面），与 auth_biometric 的定性同族（§114.6 之 3 的先例延伸、不作其他状态写动作的破例先例）；DeviceToolSpec 注释与写集钉测（14 件）同步登记此口径。真正改状态的两件（media_playlist_create/media_playback_control）照写集带键。
3. A4/A9 以同步副本「覆盖」的口径差：表面图第二章把 A4 读面与 A9 列入「第一批·纯读」（现调形态），但同步制是 2026-11-10 21:52 用户拍板、晚于表面图分批且已上线成既成通道（照片整本元数据索引＋步数按日合计，智能体经桥查副本）——同一能力面不建第二条现调路。取图本体与写入相册不在副本能力面内、登记不做（115.1 尾表 A4 行）。
4. shortcut_run 的回执等待上限：表面图只说「无回调只报已发起」；本包给等待上 100 秒上限（在桥侧在场超时 150 秒之内），等满回 noCallback 档（initiated=true、callbackReceived=false、note 写明不确认跑没跑完），不无限挂住调用；超时后才到的回执中心已无人等、安静忽略。
5. location_search_places 必须先定位：草案没写检索中心从哪来。本包落法＝先取一次当前位置、以其为中心（约 0.08 度幅）检索；定位失败如实失败——不拿无区域的全局结果冒充「附近」。
6. media_playback_control 的回读验证形态：播放状态切换是异步的（系统音乐播放器跨进程），落法为动作后轮询回读至多约 1.5 秒、达成口径逐动作定：播＝正在播放、停＝已停止、暂停＝不在播放、切歌＝正在播的条目已换（队列到头切不动即未达成）；达不到如实失败并报当下真实状态。暂停接受「已停止」一档的理由：播放器本就停着时暂停是无操作，「没有在播」是回读到的事实、不是假成功。
7. device_info 只报机型标识原文：营销名映射表（如 iPhone17,2＝iPhone 16 Pro）不在本层维护——编表必过期、错名比标识原文更坏；modelIdentifier 是可验事实，营销名要认由智能体侧知识补。另 B7（手机的名字）/B8（Wi-Fi 名）卡付费权益，device_info 如实缺省这两项、名册文案已明说，不编。
8. MKPlacemark 弃用知悉：见 115.3——用已弃用但可用的旧面取地点分量，是为行为确定性付的账；后续系统移除该面时回表换 MKAddress 再施工。
9. 详情页与引擎回执文本按 §109.5/§111.4 先例不入 L10n 目录（执行层回执不入目录；详情页硬编码文案随既有详情页惯例登记）；入目录的是名册五字段与工具卡标题（经 L10n.string 取词，两处合计 40 键）＋InfoPlist 两键。
10. 本批范围界线：A23 自家动作注册（反方向、表面图「单列不混」）、A6 麦克风录音（工单明示不碰、与听写共用权限）、A8 后台定位（表面图明示不进前四批）、A15 蓝牙（已决不做）、A10 的 notify_cancel（§113.6 已登记待议、不在本包）均登记不做，逐项见 115.1 尾表；B/C/未证三档维持原登记。

### 115.7 单测与终判口径

- 新增 7 个测试函数（DeviceSourcesTests +2：批四载荷分档门控/文案诚实；DeviceCallsTests +4：定位参数/媒体参数/撰写参数/快捷指令与文件呈现参数；RichContentTests +1：十五工具分类标题＋read_file 不误收），全仓测试函数口径以 CI 实跑为准、只增不减（合并前基线 1210，预期 1217）。既有 7 处钉值更新（名册计数 17→22 与呈现序、批次接线 +5、工具全集 27→42 与写集 12→14、可执行集 24→39、全开载荷补五件断言、搜索空集计数 17→22、非同步数据集 +5 断言），口径随名册扩容顺延、非放宽。
- L10n 补 40 键（Localizable 2373→2413）＋InfoPlist 补 2 键（11→13），合计 2384→2426，validate_i18n.py 实跑通过；繁体守既有惯例（智能体→智慧代理、调用→呼叫、文件夹→資料夾、档案用檔案、定位→定位、存储→儲存）。
- 静态自查已做：逐文件括号配平与基线同差；DeviceSourceID 全部穷尽点逐点排查并补臂（DevicePermissions.currentStates、DeviceStore 开关字典＋requestAccess、DeviceSyncExecutors.requestAccess、DeviceSyncDataset.fromSource、DeviceViews 图标底色/字形两开关＋详情分发、ConnectorsView.deviceDetail）；名册五字段与工具标题的源串与目录键经脚本逐字对账、全中；在场协调者沿批三纪律（@unchecked Sendable＋访问纪律注记、系统回调不继承 actor 隔离、可用性检查不在本包新增主 actor 隔离面）；MPMediaPlaylist/MPMediaItem 跨边界盒包照批二先例；定位授权等待者自持防提前释放。本机无 Swift 工具链：编译与全套单测终判等合并后 CI。

## §116 热修 0.46.1·附件展开块还原（用户真机报障，2026-11-11）

### 116.1 病灶（生产实证，主线核完）

用户在 App 发文件（三藏.zip）后，Hermes 网关把消息尾的 `@file:` 引用展开成给模型看的英文指令块、并**把展开全文存进会话记录**（生产样本＝state.db 消息 947，形态：`用户正文\n@file:/opt/data/attachments/三藏.zip\n\n--- Attached Context ---\n\n📎 @file:<路径> (application/zip, 660.6 KB) — binary file, not inlined as text. It is available on disk at `<路径>`. Use your tools…; do not tell the user the file type is unsupported.`）。App 侧两处漏接：

1. 历史导入（SessionHistoryImport.richItems，ChatView 活线同走它）只剥 `[Image attached at:]` 图片标记，非图片文件的展开块原样进用户气泡＝满屏英文脚手架（给模型的指令被当成用户原话渲染）。
2. 同一条消息双份并存：落定对账补缺（RunTranscriptSettle.missingUserMessages）按原文（去首尾空白）判同，本地干净条目与服务器展开条目永不相等→展开条目被判「缺失」补插一份，与本地干净条目并排（用户截图实证：干净问句一行＋展开块一大坨）。
3. 助手侧文件牌探测 FileRefDetector 的路径正则字符集纯 ASCII，中文名文件路径（如 /opt/data/attachments/三藏.zip）探不到、不出牌——附件「服务器收到了、软件不显示」的另一半。

### 116.2 五件处置

1. **Core 新增 AttachedContextRef 解析**（ToolCards.swift，AttachedImageRef 旁）：以 `--- Attached Context ---` 行分头尾；头部剥独立成行的 `@file:` 引用行（直写形＋FileSendAssembly 带引号形，引号后不许有尾巴），尾部只认 `📎 @file:` 行取路径（反引号里的同值路径不另取）、其余文字一律丢弃。图片扩展名归 imagePaths、其余归 fileRefs，头尾同路径去重。保守门：无 `@file:`、或剥不出任何路径（如正文行内提及）→原文逐字返回。
2. **规范化单点＋导入接线**：SessionHistoryImport.normalizedUserContent（展开块解析＋图片标记剥离合并，两路图片路径去重保序）为 user 消息规范化唯一入口；richItems 的 user 分支改走它，RichItem 新增 fileRefs（默认空，assistant 恒空）；ChatView 导入构造把 fileRefs 带进 ChatEntry 新增落盘字段 remoteFilePaths（JSON 编码，与 remoteImagePathsData 同形态、轻量迁移）。
3. **用户气泡文件牌**：正文泡下方同列渲染 entry.remoteFilePaths——与助手侧同构（同一 FileChip、同一 openChatFile 打开链：/api/files/download 取回→QuickLook）；图片已由图片行承接不到这里。助手侧仍走正文探测出牌，旧口径不动。
4. **FileRefDetector 字符集扩 Unicode**：路径段加 \u0080–\uFFFF（中文名命中）；护栏全保留——冒号前置跳 URL 残段、`//` 开头跳过、至少一层目录、扩展名白名单、excluding 语义不变。
5. **判同改规范形**：missingUserMessages 的比对键换成两边规范化后的（干净正文＋附件路径集）——任一侧路径集为空只比正文（本地发送条目不落文件路径、集恒空，不因缺记录判异），两侧都有路径须全等防同文异附件错配；贪心配对＋时间窗不变。对账补缺的插入端（ChatView.healMissingUserEntries）同步走规范化落盘：真缺的条目补回来也是干净正文＋文件牌，不再补脚手架原文。

### 116.3 单测与校验

新增 4 个测试函数：AttachedContextRef 解析（zip 样本原文形态逐字用／带引号路径／无尾部块只有 @file 行／图片分流／普通消息与行内提及不变，RichContentTests）、FileRefDetector 中文两例（命中＋中文名 URL 不误报，同上）、richItems 规范化一例（SessionHistoryImportTests）、判同规范形回归一例（展开全文 vs 干净正文应配对不判缺，RunTurnTests）。无新 UI 文案，validate_i18n 实跑通过（2426 键不变）。本机无 Swift 工具链：编译与全套单测终判等 CI。

### 116.4 未验与知悉

- 真机终验待用户：发中文名 zip→气泡只剩正文＋文件牌、点牌能开；同一条不双份；助手回复里提中文名路径出牌。
- 文本类文件的网关展开形态未取生产样本：契约口径是文本全文内联进尾部块，本包按同一分隔块口径剥尾（内联文本不进气泡，文件本体经文件牌下载打开）——登记知悉，若真机发现文本附件有别的存档形态回表再议。
- 旧版本已补插进本地线程的展开块存量条目不迁移：其 content 是展开原文，呈现层未加二次规范化；判同规范化后不会再新增双份，存量靠用户删线程或后续导入新线程自然消解——登记知悉。

### 116.5 扩围补记（用户拍板「所有文件、所有细节一次修完」；主线读 Hermes 网关源码 /opt/hermes/agent/context_references.py 定版，同日第二笔）

- **A 解析全形态**：网关展开共五形态，首轮只接 📎。补：①📄 内联块（`📄 @file:<路径> (<N> tokens)`＋其后 ``` 围栏全文——头行收路径出牌、围栏全文不进显示；尾部切块改围栏感知状态机，围栏内形似 📎 的代码行/空行不误切误收）②`--- Context Warnings ---` 警告块整段剥离（头部/中段/尾部三位置都处理，块内不收路径）③📁/🌐/📌 块只剥不出牌（含头部独立 `@folder:` 行；剥不出路径也必须剥净——解析的返回门由「有路径」改「碰过脚手架」）④头部与块头路径的行段后缀 `:10-20` 出牌前剥离 ⑤📎 文本过大变体（descriptor＝`text file, approximately … tokens`，路径位置不变）钉测覆盖。口径注记：网关源码注释明言 @file 标记的设计意图即「clients render it as an inline chip」，剥标记＋出牌为等价实现。
- **B 探测器泛化**：FileRefDetector 删扩展名白名单，改「绝对路径＋至少一层目录＋扩展名形态 [A-Za-z0-9]{1,12}」即命中，尾界负向断言防三截断（字母数字续接、/ 续接＝带点目录段、.＋字母数字＝双扩展名只截前半）；原护栏全保留（冒号跳 URL、`//` 跳过、excluding、去重、isImagePath 仍按图片集分流）。新增钉测：.mq5/.py/.rar 命中、v1.2 目录段不误截、.tar.gz 取全、版本号 1.2.3/域名/IP:端口不误报。
- **C GBK 转码**：新发现的真断点——网关对文本类文件按 UTF-8 硬读（read_text(utf-8-sig)），GBK 族编码文本在服务端解码失败、只剩一条警告、智能体读不到。App 入口 FileIntake.transcodedForUpload 纯函数：扩展名属文本集（与网关 _TEXT_EXTENSIONS 对齐扩充：txt/md/csv/json/xml/html/htm/log/py/js/ts/tsx/jsx/swift/mq5/mqh/yaml/yml/toml/ini/cfg/conf/sh）且字节非合法 UTF-8 → GB18030 解码重编码 UTF-8（解出含 NUL 按失败论）；GB18030 也失败→原样＋undecodable 标记。ChatView.loadPickedFiles 接线：转码后字节为上传载荷、大小二次判按转码后计、转码账只记真入条者，经 FileIntake.transcodeNotice 在入条时提示一声（文案入三语目录＋2 键，validate_i18n 通过 2428 键）；手机原文件不动。范围注记：只兜从 App 发出的文件，网页端发的 GBK 文件仍中招（须改 Hermes 上游本体，另议）。
- **D 顺手四核**：①DocumentPickerBridge 已是 `forOpeningContentTypes: [.item]` 全类型，免改；②HermesClient.fileData 经 URLComponents＋URLQueryItem 拼 query，中文路径自动百分号编码，免改；③待发附件条文件牌此前只有名＋可删、缺大小——本笔补大小副行（ByteCountFormatter .file，与文件页同制）；④用户侧文件牌与助手侧共用同一 FileChip＋openChatFile 链，首轮已同构，确认。

### 116.6 追加热修·回底钮点不动（用户 2026-11-11 11:57 真机报障，同包并入）

- **确诊机理**：回底钮 0.41.0 浮层化后挂在发送区容器（safeAreaBar 承载的小 VStack）的 `.overlay(.topTrailing)` 上、再以 `.offset(y: -(44+spacingS))` 整体上移——44pt 命中域完整落在宿主 frame 之外、悬在消息列表上空。SwiftUI 命中测试按祖先 frame 逐层剪枝：触点不在宿主框内永不下探 overlay 子树，该位置触摸全被下方 ScrollView 吃掉；渲染不裁剪、命中裁剪，故看得见点不动。action 绑定（scrollToBottom，列表内多处共用）与目标锚经查无恙；钮在布局流内时可点、浮层化后才死，时间线吻合。角标同在死区、同病同修。
- **修法**：钮迁挂消息列表本体 overlay（宿主＝整页、命中域恒在 bounds 内）；落位改实测驱动——bottomBar 经背景 GeometryReader 在命名空间 `chatSurface` 发布 frame（ChatBottomBarFrameKey，与右滑引用排除区同款构造），overlay 侧以 Core 纯逻辑 BackToBottomPlacement 按（宿主尺寸，发送区 frame，右距 spacingM，间距 spacingS）算中心点 .position 落位：键盘升降、错误/提示条增减都经 frame 自动跟随，视觉位置与旧口径逐点一致（右缘 spacingM、盘底距发送区顶 spacingS＋5）。钮外区域无命中形，列表滚动/点击照常穿透；显隐派生提为全页单一出处 showsBackToBottomButton，出入动画随钮迁到列表侧（swap 口径不变）。
- **可测判定**：BackToBottomPlacement 三件钉进 BottomFollowTests——落位算术（中心/命中域数值）、病灶复现（旧形态命中域对发送区宿主 bounds 代入 isReachable＝false、对整页宿主＝true）、frame 未发布（.null/.zero）不给落位。真机点按（点钮回底＋角标清零）列交付后验收项。

## §117 对标包 0.47.0·点子＋动态照 Muse 呈现重做（用户连发 8 张截图点题，2026-11-11；预制分支 feat/muse-align，基线 main ddde9c4）

### 117.1 审计结论（先审计后施工，2026-11-11 实查）

**伴生 feed 数据形态**：帖记录含 `images: [{url, sourceUrl}]` 与 `sourceCard`，`_feed_view` 原样透传——字段通道没断。生产实查（容器 data.json，2026-11-11）：现存 5 帖（digest 2／morning 1／research 2）**images 全部为空**，含 1.0.6 五步链产出的两篇 research 帖。

**两帖无图的根因（抓图步落空，实证）**：`_tavily_extract` 调 Tavily /extract 时请求体只有 `{urls, format}`，**没带 `include_images`**——该参数缺省 false，Tavily 结果里根本没有 images 数组（主线同日以武装库 Tavily 钥对同一页面双跑实证：缺省形 images=0，带 `include_images:true` images=4 且首图即该页 og:image）。桥的另一路 Firecrawl 兜底带 og:image，但只在 Tavily 对某 URL 完全无结果时才触发，主链上永不触发；抽取正文 Markdown 里自带的图片（实测页 15 张）也从未被采集。于是候选图池恒空→著帖步无图可选→帖子无图落库，与「宁无图不假图」的纪律无关，是抓取参数缺失。

**伴生 ideas 数据形态**：记录字段＝{id, title, detail, goalId, createdAt, source, evidence, evidenceRef, anchorId, dismissReason, status, taskId, expiresAt}（`_idea_view`／`_create_idea`／生成落卡三处一致），**无 emoji、无 deliverables、无 category**。生产 6 条现存点子同形（旧记录连 anchorId 都缺，视图以 .get 容缺）。

**汇编帖格式病灶（生产样本逐字）**：今日 digest 正文＝`## 新点子\n- 07:30 新点子《…》\n- 07:30 新点子《…》`——分组头「新点子」与每行事件文案自带的「新点子」标签重复一次；App 列表行又把 Markdown 压平成一行摘，读感成标签串行。事件文案在 `_feed_local_events_locked`（点子/简报/监测）与 `_feed_poll_remote`（任务/审批）两处生成，汇编在 `_feed_assemble_locked`。

**App 现状对账**：点子无 category 通道——桥记录与生成面都没有类别字段，App 现分组只有状态两段（待阅/已采纳）；Muse 截图里的「人际关系/购物」式主题分组在我方**没有数据来源**，本包不新造分类（生成面增 category 属另一量级变更，记 117.7 待议），分组沿用状态两段、组标题改新样式的大粗体。动态：行内只有 120 字摘＋54pt 缩略图，全文须点进详情页；简报行已有（summaryLine 取兴趣层首行，与本包胶囊口径一致，沿用）；搜索入口缺失；桥帖无 emoji 字段。

### 117.2 伴生处置（1.0.12，纯增量）

1. **ideas 增两字段**：生成提示词 IDEAS_GEN_PROMPT 增 `emoji`（按内容选一个）与 `deliverables`（[{name, summary}]，即详情页「包含哪些内容」）两字段说明；`_parse_generated_cards` 宽容收下（形状不对丢字段不丢卡）；落卡、`_create_idea`（可选入参）、`_idea_view` 三处透传。旧记录无字段→视图回 null/[]，App 容缺解码，不炸。
2. **feed 抓图修复**：`_tavily_extract` 请求加 `include_images: true`；每个 kept 来源页的图片候选按序组装——①桥侧直抓该页 `<meta property="og:image">`／`twitter:image`（限读页面头部字节、失败静默）②Tavily images 数组③正文 Markdown 首图，去重保序。图池纪律不变：只收本轮来源页的图、落库前 HEAD 校验、坏图丢弃帖子照落（仍守宁无图不假图）。
3. **feed 帖增 emoji 字段**：research 著帖提示词增 `emoji` 输出（按帖子主题选一个），`_verify_research_post` 宽容透传（限长、形状不对丢弃）；digest 汇编落帖固定 `📰`、旧 morning 只读不回填。`_feed_view` 透传，缺失回 null，App 按 kind 兜底。
4. **汇编帖格式修干净**：事件文案去掉自带的类别标签词（点子行只留《标题》、监测行只留《名》：摘要、简报行收成《目标名》周简报：标题），分组头成为唯一的类别标注；一行一事件不变。存量已存事件文案不回改（7 天自然过期），新汇编起生效。

### 117.3 App·点子处置

- **行**：左侧改内容 emoji 大字（约 44pt、无底色瓷砖）；emoji 取桥字段，缺失时按锚点 kind 缺省映射兜底（Core `IdeaEmoji`：S💬/G🎯/M📡/K✅/R🧠/手记✏️/未知💡）；标题改 semibold（见 117.5 记账）、至多两行；正文次色、行距放宽、至多 4 行；撤行面元信息行（生成时间/到期移进详情信息组；目标 chip 与任务状态随元信息行一并撤，详情里仍在）；依据行保留（宪法证据硬门的脸面，次色一行截断）；行间发丝线沿 List 既有分隔。
- **分组**：待阅/已采纳两段沿用，Section 头改大粗体样式（约 22pt bold、原色非大写）。
- **详情改底部 sheet**：列表点行不再推页，改 `.sheet` 呈现（`presentationDetents([.large])`＋`presentationCornerRadius(28)`）：标题（约 24pt 粗体）→正文全文→（生成卡且有依据时）依据小节→（deliverables 非空时）「包含哪些内容」小节：粗体小节标题（右侧剪贴板图标）＋交付物行（粗体名＋灰副文＋右侧蓝色实心对勾圆）→底部固定动作栏：左侧浅灰圆形「···」钮（菜单：太泛了/忽略/删除，沿用既有 store 动作与确认口径）＋通栏蓝色胶囊主钮「开始吧」（sparkles 图标；待阅态＝采纳转任务，成功后就地变已采纳态并给「打开任务」；已采纳态主钮＝打开任务）。信息组（来源/时间/到期/目标/状态）收进 sheet 下半区小字呈现。深链落点（动态 refs 点达点子详情）同步改走同一 sheet 形态的承载（FeedView 内以 sheet 呈现 IdeaDetailView 的新形态，导航上下文不变）。

### 117.4 App·动态处置

- **行**：左侧 emoji 大字（桥 emoji 优先，缺省按 kind：research🔍/digest📰/morning🌅/unknown📰）；标题改 semibold、至多两行、未读蓝点保留；**正文全文内联**：行内直接 MarkdownText 全文渲染（链接可点、块级结构照排），不再截断、不再依赖详情页读帖（详情页保留——ⓘ/深链可达）；有图时正文下通栏大图（第一张来源真图，圆角 20、16:9 填充裁切，异步加载、失败静默无占位）；来源嵌入卡（sourceCard）行内照旧渲染在正文后（数据真抓口径不变）。
- **动作行**：爱心位不做点赞（桥无持久化字段，记 117.7 待桥扩展）；「讨论」钮（气泡图标＋「讨论」）＝以该帖为上下文开新旁聊：新建本地线程、草稿预填「关于动态《标题》：…」上下文、经 drawerThreadSelection＋mainTabSwitchRequest 既有通道切过去（沿用抽屉新建会话的同一链，不新造发送路径）；右侧相对时间＋ⓘ钮（点开来源小 sheet：来源链接清单＋引用对象＋why，点链接出系统浏览器、点引用走既有 Route.ref）；类别/方向/未读字样并入动作行左段小字。
- **简报胶囊**：标题下通栏胶囊＝简报行改圆角通栏形态：左侧滑杆图标＋一行兴趣摘要（FeedBriefBoard.summaryLine，兴趣层原文一行截断；未设显引导文案「写下你感兴趣什么，我每天替你去看」＋副文「点按写简报」），未读数徽标保留，点按进既有简报编辑器；右上工具栏滑杆钮保留同入口。无简报文档（旧桥）时落旧胶囊行（今日汇编落点）不回退。
- **搜索**：导航栏右上放大镜钮切换 searchable 输入（标题＋正文子串过滤，分组随过滤结果重算；清空恢复全量）。
- **行高与性能**：全文内联后单行可长——LazyList 既有 List 容器沿用；长帖默认全文展开（用户口径「不需要点开」），不加折叠。

### 117.5 宪法记账（出入逐条，用户对标指令覆盖）

用户 2026-11-11 11:40–11:44 连发 Muse 点子/动态截图并点名照其 UI 设计、排版与打开形态改——以下出入以该指令覆盖，**适用范围仅限点子页与动态页两页**，其余页面角色表与图标口径不动：

1. 点子/动态行标题字重改回 **semibold**：与 0.41.0 收口批 C14「行题回收 .rowTitle（Body regular）单轨」冲突——本包两页行题改 `.headline`（17 semibold）等效位，角色表原文不改、两页以本节为准。
2. 内容 emoji 作行首图标：与设计宪法 §4「图标三源制」（品牌官方原图/SF Symbols/苹果应用图标画法）冲突——emoji 是内容数据（桥按内容选定）不是界面图标语言，界面图标（钮、菜单、动作行）仍全走 SF Symbols；§4 原文不改、两页行首以本节为准。
3. 点子行撤瓷砖底色与元信息行、动态行撤 kind 瓷砖：与宪法 §7「同构列表」不冲突（两页内部仍同构），与 0.32.0/0.35.0 两页既定行形态的出入以本节为准。

### 117.6 单测与校验

Core 新增/扩：IdeaEmoji 兜底映射（桥值优先、按 kind 兜底、手记/未知档）；BridgeIdea 容缺解码（无 emoji/deliverables 旧载荷不炸、有值原样收）；deliverables 小节呈现判定（空→整段不出现）收口为 Core 纯函数 `IdeaDeliverablesSection.isVisible`；动态全文呈现判定（行内呈现恒全文——`FeedBoard.rowShowsFullBody` 恒真口径＋excerpt 退役标注）；BridgeFeedPost emoji 容缺解码。伴生自测扩：汇编帖新格式（p3 自测加断言：正文无重复标签、一行一事件）、ideas 解析带 emoji/deliverables 落卡（p6 自测）、抓图候选组装顺序（og 优先/正文图兜底，p6 自测，网络以打桩替身）。三语：新文案（开始吧/包含哪些内容/讨论/搜索动态等）入 Localizable.xcstrings 三语齐，validate_i18n.py 跑通。单测只增不减（基线 1217＋本包新增）。

### 117.7 未验与待议

- **点赞持久化**：动态动作行爱心位本包不做——桥 feedPosts 无点赞字段、计数与状态都无处落；待桥扩展（字段＋端点）后另包补齐，App 侧不自立本地假账。
- **页顶智能体状态胶囊**（观察记录，不施工）：Muse 点子/动态页顶有居中头像＋名字＋当下正在做事项的灰胶囊（截图样本「三狗 · Checking detector」「三狗 · 分析文件问题」）。我方对应数据面＝工作台账进行中任务（伴生 ledger 有真源），呈现需三页统一的页顶位与状态文案口径，成本约：App 三页页顶组件 1 个＋台账进行中读面复用＋文案口径一轮。本包只记录，排后续对标包再议。
- **点子主题分组**：Muse 按主题分类分组（人际关系/购物）；我方桥无 category 数据（审计 117.1），若要补须生成面增字段＋存量不回填，另议。
- 真机终验待用户：点子 sheet 形态与开始吧全链、动态全文内联＋大图＋讨论开聊、老帖（无 emoji/无图）呈现不回退、新一轮调研帖带图落库（桥 1.0.12 部署后明早 08:30 轮或手动触发轮验收）。

### 117.8 合并与验包记账（2026-11-11，主线合并单）

- **预制分支 CI 先行记账**：分支 run 42956872736 终局 failure（build-native）——`FeedView.swift:1115 error: expected '}' in struct`。确诊：FeedPostDetailView 抽共享组件（FeedSourceCardView/FeedSourcesSheet）时漏收 struct 自身的闭合括号，文件尾净大括号深度 +1、其后三个组件 struct 全被吞为嵌套（FeedView 在行首无限定引用两组件、嵌套亦不可见）。修法：详情 body 之后、FeedSourceCardView 文档注释之前补回 struct 闭合 `}`（大括号深度扫描归零复核），随合并提交一并入 main。
- **合并**：feat/muse-align（顶端 bda4778，基线 ddde9c4）并入 main（0.46.1 顶端 a11c52f）。冲突仅 DESIGN-V4.md 一处（§116.5/116.6 与 §117 同锚追加），两段顺序拼接、全保留；Localizable.xcstrings 自动合并后键集校验＝两边并集 2422 键、零丢失零多余，validate_i18n 通过（2435 键×三语）。版本五处对账＝Project.swift 四处（MARKETING_VERSION 0.47.0／CURRENT_PROJECT_VERSION 114／CFBundleShortVersionString 0.47.0／CFBundleVersion 114）＋SettingsView 页脚「OneDay v0.47.0」，无 0.46 残留。合并提交 669e5bb。
- **合并后 CI**：run 42959056483 一轮全绿（build-native success、head 669e5bb，合并后零修复轮）；单测 1238、0 failures（基线 1231＋MuseAlign117Tests 7，只增不减）。
- **独立验包**：IPA 9,095,130 字节、md5 `f84cb4cfaa2bf797413a3e8c953f92a1`、Info.plist 实读 CFBundleShortVersionString 0.47.0／CFBundleVersion 114／bundle id site.didichou.oneday；交付件 `~/workspace/your_files/oneday-v0.47.0/OneDay-0.47.0.ipa`（落盘 md5 与取件一致）。
- **S2-11 核查结论（顺带项）**：**未随 §117 落地**——分支 diff 对简报编辑器保存钮零触碰，合并后 FeedBriefEditorView 的「保存兴趣」「保存正式简报」仍为纯 Form 文本行式 Button、无主按钮层级（与 style-audit-2 的 S2-11 登记现状一致）；转后续样式包处理，本包不夹带。

## §118 样式热修包 A·审批卡双面统一＋选择菜单 Picker 化（样式审计二期首包，2026-11-11，预制分支 feat/style-fix-a，基线 main 2ed1d4f；节号自选 §118——§117 为在飞对标包预留，合并时主线终审如撞号顺延）

依据：样式审计二期 style-audit-2-20261111.md 的收口切分「热修包 A」——全是用户 2026-11-11 本轮点名项（审批卡样式／文件页菜单对勾／服务器文件页同病），病灶都在组件与单点实现层。本包五条与审计编号一一对应，版本暂不改、合并时主线定号。

### 118.1 五条处置

1. **S2-01 审批卡按钮形态（聊天＋枢纽）**：弃 .bordered/.borderedProminent 家族——旧机理是 frame 写在 buttonStyle 之后、背景只按标签内容绘制，三钮 hug 成内容宽药丸且默认居中（主钮还吃环境 tint 漂移）。新形态自绘通栏胶囊钮（新文件 ApprovalCardFace.swift 内 ApprovalCardButton）：标签 Text 在背景内层 `.frame(maxWidth: .infinity)`，三钮同宽同高；主钮恒 Palette.primary 实心＋白字「批准」，次钮 Palette.selectionFill 浅灰填充＋墨字「总是允许这一类」「驳回」（驳回不预红、仍走既有 confirmationDialog，与参照「拒绝」中性灰同口径）。几何单源＝Core 新增 ApprovalCardSpec（钮高 48、钮距 10，参照 Muse 审批卡真机量测带：高约 50、距约 10）；动作集/次序/主次角色单源＝Core ApprovalCardAction（actionStack(canDecide:)：可裁决恒三档全栈、不可裁决零钮）。
2. **S2-02 聊天卡面文案收敛**：标题下最多五段灰字收成一行说明＋句尾行内蓝链——Core 新增 ApprovalCardCopy.summaryLine（头条为主体；内容预览存在、与头条不同且未被头条包含时以「：」衔接在后，记忆类头条已内嵌同一预览、包含判定防拼两遍）；视图层单行截断＋链接 fixedSize 钉行尾不被截掉，点按走既有 SmoothExpand 就地展开（展开区 ApprovalReviewContent 与两只确认弹窗不动）。删：来源行（只进详情原始信息区）、后果行（裁决钮与确认弹窗已表意）、「总是允许范围」行（确认弹窗文案 :161 已有同一信息，重复陈述）、徽章行「待审批」橙字与子系统胶囊（与问句/头条重复表意，二选一留时间）。
3. **S2-03 审批卡双面统一**：抽共用卡面组件 ApprovalCardFace（时间行＋问句标题＋说明行＋钮栈），聊天（ChatApprovalCards）与枢纽（HubApprovalSection）同实现同几何同句式——枢纽标题自此同走 ApprovalCardCopy.question 问句（旧为 headline 陈述句）。两面只差详情入口一参：聊天＝就地展开（链接文案随态换「查看详情/收起详情」、展开区注入）、枢纽＝「查看改动」打开既有 diff sheet（链接恒「查看改动」、展开区恒空）；确认弹窗与 store 裁决路径两面各自原样（聊天自持 showReject/showAlways、枢纽走段级 rejectTarget/alwaysTarget）。已决历史行徽章收敛：至多两件（子系统＋结论胶囊），「按规则放行」由第三颗胶囊降为结论后的普通灰字后缀（via_rule 标注义务不变）。
4. **S2-04 文件页 v2「更多」菜单**：组1 显示/组2 排序的手工对勾（Label 塞 checkmark 图标位、选中行文字右移、无勾行贴边，与模型双勾 P-04 同根）整段删除，改系统 Picker 塞进 Menu 的 Section 承载——勾由系统按 selection 绘制、占固定左槽、文字同 x 对齐；分组小标签（显示/排序）沿用 Section header；组3/组4 动作行（系统文件/上传文件）不动。正道据：ChatView.swift 模型菜单注释（FB16679936：菜单带勾正道只有 Toggle/Picker）＋AppearanceView 形象大小 Picker 先例。喂 Picker 的 selection 恒经新增 Binding（读＝Core LibraryDisplayMode.resolved/LibrarySort.resolved 解析落盘原值、未知回落默认档，写＝回写 rawValue），解析口径入 Core 钉测（同 ModelMenuSelection 恰一勾口径）。
5. **S2-05 服务器文件页排序菜单**：同病第三处同法——sortRow 菜单改 Picker 承载（$sortKey 直绑，选项集 FileBrowserLogic.SortKey.allCases 单源）；锚点由纯文字裸锚补 chevron.down 展开指示（caption2 bold＋inkSecondary，与聊天页模型菜单锚点同式），与文件页 v2 菜单形态一致（宪法 §9 可点必有指示）。

### 118.2 单测与校验

新增 13 个测试函数（Tests/OneDayCoreTests 三个新文件）：ApprovalCardSpecTests 4（几何落值 48/10、可裁决三档栈序与主钮唯一、不可裁决零钮、三钮文案）、ApprovalSummaryLineTests 3（无预览只剩头条、记忆头条内嵌预览不重复拼、中文预览以「：」衔接）、LibraryMenuResolutionTests 6（两枚举 resolved 往返/回落、任意原值恰一勾不变量、服务器排序选项集次序/文案/rawValue 唯一）。单测只增不减。无新 UI 文案（三钮与链接文案均为既有目录键，Picker 标题复用「显示/排序」键），validate_i18n.py 实跑通过（2428 键不变）。本机无 Swift 工具链：编译与全套单测终判等 CI。

### 118.3 未验与知悉

- 真机终验点（合并出包后）：聊天/枢纽两面审批卡三钮等宽满宽、主钮恒蓝；展开任一待批菜单（文件页更多/服务器排序）看恰一勾且文字同线；枢纽已决历史行「按规则放行」为灰字后缀。
- 冲突面自查：本包只动 ChatApprovalCards.swift 的审批卡区段，未碰 0.46.1 §116 的解析/文件牌/回底钮代码段；ApprovalCardFace 为新文件、零交叠。基线 2ed1d4f 已含 0.46.1 全部代码，本包在其上施工。
- 审计余项不在本包：S2-06～S2-09/S2-13（令牌卫生小包 B）、S2-11（并入 0.47.0 对标包与否由主线定）、S2-10/S2-12（只登记不排期），均按审计切分表原样保留。

### 118.4 S2-11 落地（合并单续办补入，2026-11-11）

- §117.8 核查定论 S2-11 未随对标包落地、转本包尾巴，本单补入：FeedBriefEditorView 两颗保存钮自 Form 文本行式 Button 提主钮层级，照 §118 审批卡主钮同款形态口径——「保存兴趣」＝主钮（Palette.primary 实心＋白字、通栏胶囊、高 ApprovalCardSpec.buttonHeight 48、保存中右端白转菊花保留）；「保存正式简报」＝次钮（同几何、Palette.selectionFill 浅灰填充＋墨字），主次分明。两钮均 .odPressable、行 chrome 改 listRowInsets 零＋listRowBackground 透明（胶囊自成面、不套行卡底），禁用态以 0.45 透明度明示（条件与旧口径逐字不变）。文案（既有目录键）与 saveInterest/savePrompt 逻辑一字未动；无新文案键，validate_i18n 不变。

### 118.5 交付记账（合并单续办，2026-11-11）

- **交付定版**：0.49.1／119。原预制分支 feat/style-fix-a（顶端 18da930，基线老 main 2ed1d4f）首轮合并单按纪律停在分支 CI 红——唯一失败 FileIntakeTests.testTranscodeGBKTextToUTF8 系基线旧账（§116 的 GBK 终修 P-21 在现行 main、分支 diff 不触 FileIntake）。本续办单先变基到现行 main c3e1729（变基后顶端 7228c90＋2a36a2f）：冲突仅 DESIGN-V4.md 一处，按顺序拼接、§118 节归位至 §117 与 §121 之间（§116／§117／§121／§122／§124／§123 全保留）；代码面（FilesView／HubApprovalSection 等）自动合并、无审批卡面与 §123 通知面的取舍冲突；Localizable.xcstrings 分支零触碰，main 2487 键原样、validate_i18n 通过。变基后分支 CI run 42968708726 全绿（单测 1296＝main 基线 1283＋本包 13、0 failures，GBK 旧账随终修转绿）；续补 S2-11（提交 8024d99，见 §118.4）后第二轮分支 CI run 42969772410 全绿。
- **合并**：合并提交 3a82ae2（--no-ff，零冲突）；定版提交 c2748f0（版本五处＝Project.swift 四处 0.49.1/119＋SettingsView 页脚「OneDay v0.49.1」，grep 验无 0.49.0 残留）即合并后 main 顶端。
- **合并后 CI**：run 42970583976 success（build-native success，head c2748f0）；单测 1296、0 failures（只增不减）。
- **独立验包**：IPA 9,197,811 字节、md5 `add8ce495c9918d4fceb925b3616566a`、Info.plist 实读 0.49.1／119／bundle id site.didichou.oneday；交付件 `~/workspace/your_files/oneday-v0.49.1/OneDay-0.49.1.ipa`（落盘 md5 一致）。
- **真机待验**：§118.3 三点（两面审批卡三钮等宽满宽、主钮恒蓝；两处菜单恰一勾且文字同线；已决历史行「按规则放行」灰字后缀）＋S2-11 两钮（简报编辑器主钮蓝实心通栏、次钮浅灰同高、禁用态变淡、保存中转菊花）。


## §120 人话收口包（2026-11-11，预制分支 feat/human-copy，基线 main 669e5bb；节号自选 §120，合并时主线终审如撞号顺延）

依据：细节打磨审计 detail-polish-audit-20261111.md 切分中的「纯文案层 12 项」＋D3-11 校验器根因修复。本包只动文案/字符串与校验器，不动布局与逻辑；在飞分支面（ChatView §116 段、Models 页）只改字符串值。**不在本包**：D3-01（槽位族 8 条）/D3-16（提供商→服务商 16 条）随 §119 模型简化包；D3-08（cron 人话化）/D3-14（骨架占位）独立排；D3-17（MCP 裸标签）随连接器下一包。

### 120.1 逐条对账

- **D3-02**：点子详情「依据」区 `Text("素材编号 \(ref)")` 整行按报告首选删除（IdeasView.swift evidenceSection）；evidenceRef 数据字段保留在桥模型里，只是不再上用户面。
- **D3-03**：失败文案收两制。①远端读取类统一为「X没读出来，可能是网络或服务暂时没响应」（无尾巴轮换，动作交给页面重试钮/下拉）；同义键合并——动态/台账/目标/点子/监测/任务/定时任务/改动各对并一，另及待批列表、记忆条目/状态、变化记录、运行记录、详情、电脑列表、云电脑状态、产出目录、人设、档案、会话、状态、连接状态、用量、日志、配置、网关状态、审批状态、技能、内容、密钥、通讯录、文件夹、目录、电脑文件、组合清单（报告点名「请下拉重试」证据）共 36 组。②动作失败尾巴统一「请稍后再试。」（存量多数制 42:35），「请稍后重试。」25 条改名/合并（含保存/删除两对同义合并）。本地读取分开处置不套远端因由句：读取文件失败→「文件没读出来。」、所选文件/照片→「所选文件没读出来。」/「所选照片没读出来。」、通用标题「读取失败」→「没读出来」、图片加载失败→「图片没加载出来」。提交类回读好范式（「已提交…请刷新核对」族）原文保留不动。目录键 2422→2406（合并删 18、新立 2）。
- **D3-04**：「桥」族 16 条全改人话：数据桥未连接→「还没连上你的服务」（含带句号/带原因三形）、桥未连接→「还没连上」、接管失败→「还没连上，这次操作没有发出去。」、同步批次「桥没有收」→「没有收下」、桥侧提示→「额外提示」、「服务器上的数据桥还没有开通。」→「服务器上这项服务还没有开通。」、监测/记忆两条开通面文案去「桥/面」重写、总览桥副题→「总览 · 总览页与通知角标的数据来源」、审批桥副题并入 D3-05 新文案。**桥钥匙核实结论（报告待核项）**：AppRoutes.swift:29 与 SettingsView.swift:372 双处代码注释实证——0.33.1 已删除设置页「桥钥匙」整节与粘贴页路由，用户只持 Hermes 登录密钥；三条指向「设置 · 桥钥匙」的文案确属**死指引**，按现行单钥路径重写：电脑文件/执行命令两条改既有定版式「还没有可用的登录信息：……用的是你的 Hermes 登录。先到「设置」里确认已经连接并登录，就能用了。」（与 GoalsStore/LedgerStore/MemoriesStore 同式），云电脑状态卡一条改「云电脑还没连上：先到「设置」里确认已经连接并登录，再回来刷新状态。」。
- **D3-05**：「闸门」族 6 条按报告改后文案：闸门模块→「写入审批」、记忆闸门→「记忆写入先审批」、技能闸门→「技能改动先审批」、闸门未启用→「写入审批没开」、副题→「记忆和技能的写入，先经你批准再生效」、证据行→「检查的是写入审批的工作状态（打开本页时当场问的）」。
- **D3-06**：「未落定」族 8 条按报告改：归档/改名/置顶/删除四条逐条给「没X成＋服务器现状＋稍后再试一次」、汇总句→「%lld 条已改好，%lld 条没改成——列表已按服务器现状刷新，你核对一下。」、保留项句→「没改成的项先按你改的样子显示，下次打开本页会自动再试。」、操作未落定→「没改成」、模板键「「%@」%@未落定：%@」→「「%@」%@没改成：%@」；AllConversationsView 两处插值字面量（批量汇总、迁移失败行）同步改；族外同词一条（聊天发送守卫「落定后可继续发送」）顺改「确认完就能继续发送」。
- **D3-07**：DeviceBridgeClient 两条轮询错误合并为一条人话：「这一步的结果没确认回来，请再试一次；如果反复这样，把这条记录发我看。」（内部细节只进诊断，不再直达用户面）。
- **D3-09**：WriteGateClient 未知类型三句（查看/建规则/裁决）合并为与卡面只读口径同一式：「这类审批 App 里还处理不了，请在 Hermes 网页端处理。」。
- **D3-10**：验活没过→「连接没通过」；仅配置在册 · 未验活→「已保存，还没测过连接」（ConnectorCatalogTests 断言跟改）。
- **D3-12**：台账标签对账补记→「补记」（与 HubLedgerSection 既有列表面小标同键合并，LedgerModelsTests 断言跟改）、对账纠正→「已纠正」；两条解释句按报告定版原文保留（见 120.2 豁免）。
- **D3-13**：「主端点（经网关）」→「默认服务商（经网关）」（§119 服务商口径；落点 ModelCombos.swift，字符串值改动）。
- **D3-15**：云电脑「镜像」行标签与状态串（ComputerView detailRow、BoxBridgeModels 两条插值）→「系统」；「快照生成」→「生成存档」（全仓用户面「快照」仅此一处、无产品名冲突，按报告首选）。
- **D3-18**：HermesError modelNotUpstream 改报告文案：「「%@」是网关内部的别名，不能设为默认模型，这次没有写入。」。
- **D3-19**：核过全部裸空态——枢纽台账「暂无记录」、枢纽任务「暂无任务」均已有下文说明（ContentUnavailableView description 在位），不动；真裸两处补下文/改题：状态页「暂无日志」→「暂无日志。有新事件时，会记在这里。」；云电脑无页面标题占位「暂无页面」→「还没有打开的页面」（BoxBridgeTests 断言跟改）。听写诊断面「暂无记录」属诊断次级披露，不动。

### 120.2 D3-11 校验器根因修复

Scripts/validate_i18n.py：黑名单 7 词扩至 16 词（增槽位/验活/闸门/桥/轮询/上游/未落定/对账/镜像，繁体对形同步扩）；新增**源串同查**——zh-Hans 源串（键＋源值）含黑名单词即报错，不再只防译文引入。扩后全仓复跑结果：Localizable 2406 键＋InfoPlist 13 键，除下列 12 条挂账豁免外**零漏网**。豁免写在脚本 SOURCE_EXEMPTIONS（键→理由），且豁免失效（键改净/删除）即报错、强制销账：

- **槽位族 8 条（D3-01，归 §119）**：§119 合并时必须按「辅助模型」新口径改净这 8 键并删除对应豁免——本包已列明清单，合并对账以此为准。
- **对账族 4 条**：D3-12 定版保留的解释句 2 条（原文保留系审计明定）；「对账」记录者标签 1 条（LedgerBoard.actorWord，D3-12 未列，留台账后续面）；闹钟连接器说明文 1 条（审计计数内、D3-12 未点名，留连接器下一包）。

校验器负测试已验：注入含「验活」的源串键，校验如期失败（exit 1）。

### 120.3 与 §119 的对账面（合并时注意）

本包在 Models/网关相邻面只动了字符串值，§119 合并时以新文案为准勿回退：ModelSettingsView（组合清单失败句）、ModelCombos（主端点→默认服务商）、ModelManagementStore 与 GatewayView/EnvVarsView 的失败兜底句（配置/网关状态/密钥三条已按 120.1 模式句改）。网关渠道两条失败键（带 %@ 详情形与裸形）本包未动，留 §119 按其三态人话口径一并收。

### 120.4 单测与校验

XCTest 无新增、只减不增红线守恒：跟改断言 8 处（ConnectorCatalogTests 在册文案 1、LedgerModelsTests 补记 1、BoxBridgeTests 页面占位/未连接/状态失败 3＋镜像 imageLine 3），均系文案变更的同值跟随。validate_i18n.py 通过（2419 键三语全覆盖、占位符一致）。代码侧字面量替换 118 键命中调用点，另手工 8 处（点子素材编号行删除、AllConversationsView 插值 2、BoxBridgeModels 镜像插值 2、DeviceExecutors 错误前缀插值 3 类共 5 行）。


### 120.5 合并与验包记账（2026-11-11，主线合并单，0.50.1/123）

- **合并**：feat/human-copy（顶端 bfddcbd，基线 669e5bb）并入 main（0.50.0 顶端 3885578），合并提交 288dbe4；定版 e39a20f（版本五处＝Project.swift 四处 0.50.1/123＋SettingsView 页脚「OneDay v0.50.1」，grep 验无 0.50.0 残留）；测试跟改 3af9674（见下 CI 段）。冲突 6 文件，逐处裁决如下。
- **Localizable.xcstrings 三方并集（本单最细一环）**：基线 2422／§120 侧 2406（删旧键 123、新立 107，净 −16）／main 侧 2627。以 main 为底：§120 有意删除的 123 键确认删除（三方核对：main 侧值与基线逐字同、未被 main 改过；合并后代码精确字面量复查零引用，残留命中全为注释与子串）；main 已删的 4 键（§126 孤儿）保持删除；§120 新立 107 键全入。撞名 1 键「默认服务商（经网关）」两侧同 zh-Hans/en、仅 zh-Hant 差一字（§120「經閘道」／main「經網關」）——§120 侧 zh-Hant 全册统一用「閘道」，取 §120 值。合并后 Localizable 2603 键＋InfoPlist 13 键＝2616 键。
- **§119.4 遗留处置（校验器扩版复跑＋槽位豁免销账）**：扩版校验器（16 词黑名单＋源串同查）对合并后目录复跑通过（2616 键×三语、占位符一致、零漏网；--check-code 同过）。合并前对 main 目录试跑的 49 条违规＝41 条 §120 已改名旧键（随并集删除消解）＋槽位 8 条。槽位豁免组 8 条删除销账：§119.4 已逐条改写、8 键在合并后代码零引用（「辅助槽位」仅剩 ModelCombos.swift 一处代码注释、不上用户面），系孤儿键，随豁免一并删（目录 −8 已计入上数）。余豁免 4 条（D3-12 解释句 2＋台账记录者标签 1＋闹钟连接器说明文 1）仍在效、校验器未报失效。
- **代码冲突 4 文件**：①DocumentReaderView——§120 唯一改动行（loadError 兜底句）的宿主已被 §125 在 main 侧整段换代为 FileOpenFailure 五分文案，旧串在 main 已不存在，取 main、§120 改动自然消解。②FilesView——§120 五处改串中四处自动合并在位；第五处宿主 FilePreviewView 已被 §125 整支删除，取 main 的退役注释。③ModelCombos——取 main（§119 的 main/custom 双 case＋D3-13 注释为 §120 侧超集，§120 的「默认服务商（经网关）」改名 main 已含）。④ModelSettingsView——§119 名词与 §120 句式合裁：定为新串「预设清单没读出来，可能是网络或服务暂时没响应」（§119「预设」名词×§120 统一失败句式；三语齐备入目录，+1 已计入上数；§120 原串「组合清单没读出来…」与 §119 串「预设清单读取失败，请下拉重试。」均成孤儿键保留待后续清）。
- **CI 两轮**：首轮 run 42979607534（head e39a20f）build-native failure——唯一失败 LocalServicesTests.testSearchByBlurb：其搜索词「审批桥」正是 D3-05 改掉的 writeGate 旧简介，§120 预制时漏跟改此断言（实算 []、期望 [writeGate]）。同值跟改搜索词为新简介词「批准」（新简介中唯一命中）提交 3af9674；二轮 run 42980936511（head 3af9674）jobs API 逐项终判 build-native **success**。单测 **1336、0 failures**——与合并前 main 口径（0.50.0）分毫不差，合 §120 无增删、断言跟改合 9 处（预制 8＋合并跟改 1）的对账。
- **独立验包**：IPA 9,408,803 字节、md5 `17d841be973cb7097bb187215939d9d9`、Info.plist 实读 CFBundleShortVersionString 0.50.1／CFBundleVersion 123／bundle id site.didichou.oneday；交付件 `~/workspace/your_files/oneday-v0.50.1/OneDay-0.50.1.ipa`（落盘 md5 与取件一致）。
- **真机待验**：各页失败提示已换人话口径（远端读取类「X没读出来，可能是网络或服务暂时没响应」、动作失败尾巴「请稍后再试。」）；连接面「桥/闸门」词族清零（还没连上你的服务／写入审批）；会话批量操作回执「没改成」族；设置页页脚 v0.50.1。

## §121 热修：回底钮消失＋自己发的文件没牌/点开落点（0.46.1 真机报障，2026-11-11 12:27）

用户真机四张截图报障：①回底钮在 0.46.1 直接不见了（0.41.0 是看得见点不动、§116.6 迁位后整钮消失）；②12:24 发 GestaltX_1.0.4.ipa 问「这是个什么文件」，自己气泡里没有文件牌（助手侧牌正常出）；点开文件牌的预览落点可疑；③（只查）Hermes 智能体 12:26 仍称「这个通道只能内联图片、IPA 没法回传」。基线 a11c52f（动工时 main 已并入 §117/0.47.0，实际基线取 main 顶端 669e5bb）。

### 121.1 题一 · 回底钮消失（定案：新落位门把钮渲染 AND 上一条真机未交付的发布链）

- **回归变量隔离**：显隐政策（BottomFollowPolicy：离底＋末条不可见）与可见集/距底信号链 0.46.1 未动、0.41.0 真机出钮（点不动）证明其工作；0.46.1 唯一新增门＝钮渲染须 `BackToBottomPlacement.center(...)` 非 nil，即 `ChatBottomBarFrameKey` 必须从 safeAreaBar 承载的 bottomBar 背景 GeometryReader 发布出 height>0 的 frame。用户真机整钮消失与此门恒假逐点吻合。
- **发布链结构**：发布点在 `.safeAreaBar(edge:.bottom)` 内容的 `.background` 层里，frame 取 `.named("chatSurface")`（命名空间挂在列表结果上）；消费端 onPreferenceChange 在列表侧。同款「背景 GeometryReader＋命名空间发布」构造从**滚动内容**发布（右滑引用排除区）真机已验可用，唯一差异变量＝safeAreaBar 宿主。
- **外部解法核查**：苹果无文档保证 PreferenceKey/命名坐标空间跨 safeAreaBar 宿主的交付；iOS 26 safeAreaBar 参与布局仍有公开问题记录（如 FB23732628 同族：挂错宿主时安全区参与失效）；成熟做法对跨层几何改用视图自身回调（onGeometryChange，iOS 18+）或直接读宿主自身 safeAreaInsets，不再经跨树发布。结论：发布链不可靠属实，**换结构、不再往此链打补丁**（本链已连补两轮：0.41.0 浮层化→点不动、0.46.1 发布链→整钮消失）。
- **正修（换结构）**：删 ChatBottomBarFrameKey 发布链全体（发布点/命名空间/onPreferenceChange/@State）。钮仍挂消息列表 overlay，但落位只读 overlay 宿主 GeometryReader **自身**的 `safeAreaInsets.bottom`（safeAreaBar 是列表安全区的注册部分，§28/P-17 已验其参与列表安全区——顶栏同理）：钮底缘＝宿主底缘 − 安全区底 inset − gap。落位纯逻辑收 Core `BackToBottomPlacement.center(hostSize:bottomInset:trailingInset:gap:)`：输入全是宿主本地量、无「未发布」态；单测钉落位算术（键盘升降＝inset 变大钮上移）＋命中域完整在宿主内（isReachable 恒真构造）＋退化宿主（尺寸 0）不给位。

### 121.2 题二(a) · 自己刚发的文件没牌（定案：发送链从不把回执路径写回本地条目，落定对账又只配对不回填）

- **代码实证**：`ChatView.send()` 建本地 user 条目时不带 remoteFilePaths（ChatView.swift 建条目处）；sendTask 上传成功后的 `fileServerPaths` 只用于拼出站 @file 文本（拼装点一处），从未写回 `newEntry.remoteFilePathsData`。用户气泡文件牌的唯一数据源＝`entry.remoteFilePaths`（渲染门在 ChatView 用户气泡段），故刚发的消息在本地永远无牌；助手侧牌走正文 FileRefDetector、与此无关（截图中助手牌正常即此理）。服务端实证：state.db 消息 979 存有该条展开全文（@file 行＋📎 块俱在）、attachments/GestaltX_1.0.4.ipa 在盘 2,865,180 字节——收发链无恙，缺的只是本地落盘字段。
- **对账为何不自愈**：落定 `healMissingUserEntries` 只补「判缺」的条目；`RunTranscriptSettle.missingUserMessages` 的配对键从本地条目**正文**规范化推导路径（本地正文无路径、集恒空），按「任一侧为空只比正文」规则与服务端条目配上对→不判缺→不补，自然也不回填路径字段。
- **正修两件**：①发送回填——sendTask 上传全成后立即把 `fileServerPaths` 写回 newEntry.remoteFilePathsData 并 save（流式期间牌即在）。②对账回填——Core 新增 `reconcileUserMessages`（missingUserMessages 改为其薄包装、旧签名保留）：本地条目入参增带已落盘的 filePaths/imagePaths 参与配对（同文异附件双非空须全等的旧防线不松）；配上对且服务端路径未被本地持有时产出 PathBackfill，App 侧据（规范正文＋createdAt）定位条目回填两字段并记诊断读数——存量已发消息在该线程下一次落定时自动补牌。

### 121.3 题二(b) · 预览落点与失败文案（定案：截图页非 OneDay 页面；OneDay 同类隐患两处属实）

- **截图页归属排除**：全仓字符串核查——OneDay 无「文件加载失败」文案；自有失败页只有阅读页「打开失败」/文件页「预览失败」两种标题（均 ContentUnavailableView＋failureActions 按类出项），`.ipa` 属 `.other` 类、失败动作＝下载＋知道了，与截图「重试＋下载」对不上；且服务端实查 /opt/data/attachments 下只有 GestaltX_1.0.4.ipa、**不存在 OneDay-0.46.1.ipa**，该名文件不可能从 OneDay 任一文件面打开。判定：截图 3 是用户在主聊点交付 IPA 卡触发的 Muse 自家预览失败，非 OneDay 故障，不在本包修。
- **服务端实证（下载链）**：GestaltX_1.0.4.ipa 在盘（2,865,180 B、12:24 落盘）；未鉴权 curl 两路径均 401（鉴权中间件先行、路由在）；Hermes 源码 files.py 下载语义定版：存在且合规→200 流式返回（上限 _MANAGED_FILE_MAX_BYTES＝100MiB，本件远在限内）、不存在→404、非文件→400、敏感路径→403、超限→413、stat 失败→500。故 OneDay 内点助手牌下载此文件应 200，链路无恙。
- **OneDay 属实隐患**：①`openChatFile` 下载成功后无条件把临时文件交给 QLPreviewController——外部通行做法是呈现前先 `QLPreviewController.canPreviewItem` 验资格（不可预览类型硬呈 QL 只剩空白/死页）；.ipa 这类应落「下载/分享」档。②三处取文件失败（聊天 openChatFile、文件页预览 load、阅读页 load）都只给一句 HermesError.userMessage 兜底（「文件下载 返回了状态 404，请稍后再试」式），无原因分类——ekko 五分文案原排后续文件包，因本案提前。
- **正修**：Core 新增 `FileOpenFailure` 分类器＋人话文案（输入 HermesError＋路径预检）：404→不存在「服务器上没有这个文件，可能已被移动或删除」；413→过大；400/空路径→路径无效；403→服务器拒绝（五分外加一档，如实分开）；5xx/登录态/连不上→服务不可用；transientNetwork→超时/网络不稳。三处失败落点统一消费。QL 资格门：ChatFilePreviewItem 加 `canPreview`（QLPreviewController.canPreviewItem）——聊天牌点开：可预览才进 QL sheet，不可预览改出分享单（保存到文件/分享，即下载档落点）；文件页预览 load()：不可预览不写 QL 件、直接落失败页＋unsupportedType 文案，动作仍走 failureActions 按类出项（.other/.archive＝下载＋知道了）。电脑文件面（BoxFilesView，自有错误族 BoxFilesError）不在本包。

### 121.4 题三 · 智能体旧说法（只查结论：旧会话未加载新说明，无需改服务端）

- 会话 oneday-side-c60d7bfd（即截图会话）state.db 实查：started_at＝2026-11-10 23:07:43 CST；SOUL.md 本次写入 mtime＝2026-11-11 11:40:23——会话比说明早生约 12.5 小时。
- 该会话冻结的 system prompt（sessions.system_prompt_hash＝37d811…，system_prompts 表对应行 15,333 字）不含新说明的任何痕迹（特征词零命中）；且实查 11:40 之后无任何新会话创建——至今没有会话带过新说明。12:26 的旧说法出自此旧会话的冻结提示，属按会话冻结口径的预期行为；新开会话即带新说明。服务端不动。

### 121.5 外部解法核查汇总

- 回底钮：见 121.1（苹果无跨 safeAreaBar 发布保证、FB23732628 同族问题、通行替代＝宿主本地量/onGeometryChange）。
- 用户消息附件牌挂载点：成熟聊天客户端（如 Stream Chat）一律把附件作为消息本体数据随本地消息模型落盘、渲染只读本地模型——与本包「发送即把回执路径写回本地条目」同向；咱们导入/补缺两路已是此形态，唯发送路漏写，属自家链缺口非平台限制。
- QL 不支持类型：通行做法＝canPreviewItem 前置验资格、不过转下载/分享（QuickLook 指南与 React Native 文档查看器等同口径），与 121.3 正修一致。
- 文件失败五分：与 ekko D2/B4 对账一致（不存在/过大/后端不可用/超时/路径无效），服务端状态码实证（121.3）逐项对得上。

### 121.6 单测口径

Core 新增/改：BackToBottomPlacement 新签名落位族（旧「frame 未发布不给位」钉测随结构退役删除、换宿主本地量算术＋可达性钉）；reconcileUserMessages 族（带路径配对、同文异附件判缺、回填产出/不产出）；FileOpenFailure 分类表＋路径预检。单测只增不减（净增为正）。真机验收：离底时回底钮出现/落位/点按回底＋角标清零；发任意文件后自己气泡立即出牌且点开可预览；点 .ipa 牌落分享单而非 QL 死页；断网/改名文件点开见对应原因文案；旧会话里已发的 GestaltX 消息在同线程再发一轮落后牌补出。

### 121.7 合并与验包记账（2026-11-11，主线合并单）

- **合并**：feat/hotfix-file-back（顶端 013f70e，分支 CI run 42961158491 全绿、单测 1246）并入 main（基线 5a9e1a1）；DESIGN 冲突一处（§117.8 与 §121 同锚追加），顺序拼接全保留。合并提交 53f0e86，版本五处对账＝Project.swift 四处 0.47.1/115＋SettingsView 页脚「OneDay v0.47.1」。
- **合并后 CI**：run 42962305282 success（build-native success，head 53f0e86）。
- **独立验包**：IPA 9,098,746 字节、md5 `220c983db9cd480bf4f6ba2988f5493f`、Info.plist 实读 0.47.1／115／bundle id site.didichou.oneday；交付件 `~/workspace/your_files/oneday-v0.47.1/OneDay-0.47.1.ipa`（落盘 md5 一致）。
- **真机验收点**：见 §121.6 五条（回底钮出现/落位/点按、自发文件立即出牌、.ipa 落分享单、失败五分文案、旧消息 GestaltX 补牌）。
## §122 三页修正包（2026-11-11，预制分支 feat/three-pages-fix，基线 main 5a9e1a1；§118–§121 在各自预制分支，合并时主线按序拼接）

起因：用户 2026-11-11 12:41 装 0.47.0 后 6 张截图报障三题，12:45 再发 Muse 动态页真机截图作对尺标准；同日审计（similar-issues-audit-20261111.md）附录 A 给出 kanban 事件 kind 生产全集与「执行：default」实证、N1 把详情页图列为题二同根扩围。版本五处未动（合并时主线定号）。

### 122.1 题一 · 点子采纳落点改开旁聊（覆盖 §105/§117 旧口径）

- **覆盖声明**：§105「采纳落点 kanban（4A）」与 §117 详情主钮「打开任务」口径就此作废——采纳落点改旁聊。与 2026-11-11 12:48/12:55 闭环标准 C1 定版同向（用户亲手发起的执行会话进旁聊；纯系统/定时/探针仍归台账，不在本包）。
- **kanban 照旧后台建**：IdeasStore.convertToTask 全链一字不动（探板→建任务→回写 taskId→回读确认→触感），台账记账不动；开旁聊的落定判据与 store 回读确认同口径——回读后 taskId 已落字且无失败留痕才开，未落定留在详情页看 notes 原因。
- **旁聊走既有创建链**：本地插入 ChatThread 即出生记录（DrawerView.createThread／动态「讨论」同形），服务端会话由该线程首发时经 SideChatLink 铸 oneday-side- id 走 8642 建会话（0.21.0 既有链）——采纳点不另建第二套建会话代码。
- **上下文＝预填不代发**：Core 纯函数 IdeaChatPrefill.make 拼标题／说明／依据（仅生成卡，与详情依据小节同口径）／交付物清单，写入输入舱草稿（SideChatStore.setDraft），用户点发送为准。核对结论：§105 旧账无「采纳自动发送」的批准口径（当年只定落点），全仓发送红线为不代发，故只预填。
- **「打开任务」改「打开对话」**：关联存 SideChatStore.ideaThreadIDs（点子 id→线程 id，UserDefaults 落盘）。存量已采纳点子无关联、或关联线程已被删——点按时补建旁聊＋预填＋改写关联（本包定版处置）；回既有线程不覆盖其草稿。详情页原 showTask 任务详情 sheet 入口撤销（任务详情仍可从动态 refs 与枢纽到达）。
- **连带·事件人话化**：Core KanbanEventKind.label——映射表按附录 A 生产全集 10 种建（created 任务已创建／claimed 已认领／spawned 已开始执行／owner_admitted 已确认接手／worker_bound 执行者已就位／worker_result 已交回结果／review_requested 已发起复核／commented 有新留言／completed 已完成／heartbeat 过滤），不凭枚举猜；未知与空 kind 落「有新进展」兜底、不直印英文。heartbeat 占样本 10/38、无用户意义，映射为 nil＝整条不进证据列表（只译不滤会被心跳淹没）。evidenceItems 接线，其旧注「event.kind 原样直通不译」同步更正。P-16 同族复发面收口。
- **连带·「执行：default」**：生产实证 oneday 板 assignee 全为 default（缺省 profile 内部名，附录 A）。Core KanbanTask.displayAssignee 收口：default／空→nil（整行不出现），具名 profile 原样（谁在执行要看得清，与评论作者口径同理）；两处落点同改——KanbanTaskDetailView 头部、HubTaskSection 任务行。

### 122.2 题二 · 动态图片定尺（行内＋详情，审计 N1 扩围）

- **机理**：行内旧形把 aspectRatio(16/9) 挂在 AsyncImage 本体——成功相图片以自然尺寸参与行高求解，整页截图类长图（自然比极端）撑成数屏高（用户截图实证，整页翻不到头）；详情页旧形 scaledToFit 无任何限高、按自然比全高呈现，同根（审计 N1）。
- **修法**：新立 FeedPostImageBox 定尺盒——形状层（Color.clear）承担 16:9 定尺寸、图片降为 overlay 以 scaledToFill 裁切（0.36.24 媒体格定案的同族正案：定尺落在承担定尺寸的那一层）。行内只喂第一张（旧口径不变）；详情逐张 16:9 排列（旧形只显第一张，随扩围改逐张）。加载未成／失败整块不显、无占位（旧口径不变）；详情图无障碍标签（A11yText.imageLabel）保留。来源卡在 GitHub 类帖代照片的形态（§117 既有）不动。
- **胶囊避让**：动态页 List 加顶部 contentMargins（spacingXXL＋spacingM＝64pt），静止时首行正文落在页顶全局状态胶囊下沿之外；只动动态页，胶囊本体与其他页一字不动。对尺附记：Muse 自家浮标亦会压住帖子一行——我方以避让胜之，此条不抄。

### 122.3 题三 · 动态行太长（修订 §117「行内恒全文」口径）

- **对尺**（用户 12:45 Muse 截图）：帖＝标题一行内、正文两三句（约 80–150 字）全文铺、图一张全宽圆角（约 16:9）、动作行四件。我方行内结构 §117 已同形，差在源头帖长——审计实测生产帖正文中位 853 字、5/7 超 600 字；源头收紧归桥侧生成面（伴生写短口径另行），App 侧阈值只作安全网。
- **口径**：短帖（≤300 字符）零截断、全文内联，§117 对标口径在短帖不变；超阈值截到最后一个完整句界＋「展开全文」入口（点开进详情看全文）；来源卡／refs／动作行在截断后保留。阈值＝Core 常量 FeedBoard.rowBodyCharacterLimit＝300（约 Muse 样本上限两倍余量）。
- **纯函数收口**：FeedBoard.rowBodyPresentation——Character 计数（多字节／emoji 安全）；句界＝。！？；、后随空白／换行的 .!?; 与段落换行，ASCII 点号须后随空白或收尾符才算界（防 0.47 小数点、域名点号误判，后随字符看到上限外一字）；句界须落在上限后半段才采用（太靠前截完近空行），无合格句界则硬截上限字数＋省略号；截点落未闭合代码围栏（```）内时回退到围栏开始之前（回退后为空则回硬截）。FeedBoard.rowShowsFullBody 口径随改为「本帖行内是否全文」，MuseAlign117Tests 的 testFeedRowShowsFullBodyRegardlessOfLength 断言同步更正（§117.6 的恒真口径就此修订）。

### 122.4 单测与校验

- 新增 ThreePages122Tests 18 测：截断 8（短帖全文／恰限全文／句界截断／无句界硬截／emoji 计数／早句界回退硬截／围栏守卫／rowShowsFullBody 随动）、事件映射 4（生产全集逐条／heartbeat 过滤／未知与空兜底／evidenceItems 集成）、displayAssignee 3、IdeaChatPrefill 3（全拼装／空段省略／手记不带依据）。MuseAlign117Tests 旧断言 1 处按新口径更正（测试计数不减）。
- 三语新增 15 键（Localizable 2437 键＋InfoPlist 13＝2450），validate_i18n.py 通过。
- 红线守界：未碰 ChatView §116／回底钮段；§117 点子行／sheet 形态与动态行结构不动（只改本节三处）；简报胶囊与搜索不动。
- 真机待验：采纳全链（任务后台建成＋旁聊打开＋预填在舱未代发）、存量已采纳点「打开对话」补建、长帖行内截断与展开全文、整页截图类图片在行内与详情均不再撑高、动态页静止位胶囊不遮首行正文。

### 122.5 合并与验包记账（2026-11-11，主线合并单）

- **分支终局**：feat/three-pages-fix（顶端 8c65e0e，基线 5a9e1a1）分支 CI run 42962710628 全绿；单测 1256（基线 1238＋ThreePages122Tests 18，MuseAlign117Tests 更正 1 处计数不减）。
- **合并**：并入 main（顶端 d5ac49b，含 §121/0.47.1 与 §121.7）。冲突仅 DESIGN-V4.md 一处（§121 与 §122 同锚追加），顺序拼接（§121 在前、§122 在后）全保留；Localizable.xcstrings 自动合并后键集校验＝两边并集 2444 键、零丢失零多余，validate_i18n 通过（2457 键×三语，含版本串对账后）。版本五处＝Project.swift 四处 0.48.0/116＋SettingsView 页脚「OneDay v0.48.0」。合并提交 bc58930。
- **合并后 CI**：run 42963437267 success（build-native success，head bc58930）。
- **独立验包**：IPA 9,112,272 字节、md5 `a0df82ed32b5b25e61cd743676e586ff`、Info.plist 实读 0.48.0／116／bundle id site.didichou.oneday；交付件 `~/workspace/your_files/oneday-v0.48.0/OneDay-0.48.0.ipa`（落盘 md5 一致）。
- **真机待验**：点子采纳全链（任务后台建成＋旁聊打开＋上下文预填在舱未代发）、存量已采纳点「打开对话」补建、长帖行内截断＋展开全文、整页截图类图片在行与详情均 16:9 不撑高、动态页静止位胶囊不遮首行、任务详情事件人话（heartbeat 不显、「执行：default」不显）。
## §124 热修：回底钮落位过高（0.47.1 真机复报，键盘态多扣一截键盘高，2026-11-11 13:11）

起因：用户装 0.47.1 后两图＋原话——钮已渲染（§121「整钮消失」已修），但键盘升起时钮浮在消息区右上方约屏幕五分之一高处，用户「找不到那个按钮」「这个按钮怎么这么上？应该和图二一样，在输入框上面的位置」（图二参照＝Muse：钮紧贴输入舱上沿）。落位不变量（本包验收标准）：钮底缘＝输入舱顶缘＋既有 gap、右对齐、未读角标形态不变，键盘升/降两态恒成立；显隐政策与点按回底＋清角标行为不变。

### 124.1 诊断（主线假设验证：成立）

- **现行实现（§121 二代）**：钮挂消息列表 overlay，落位中心＝宿主高 − `geo.safeAreaInsets.bottom` − gap − 22（Core `BackToBottomPlacement.center`），宿主高取 overlay GeometryReader 的 `geo.size.height`。
- **两输入不同源（代码＋结构实证）**：`geo.size` 是已被系统键盘避让调整过的布局帧——ChatView 居 TabView 格内、根不忽略安全区，键盘升起时系统按安全区扩张调整整条视图链的布局区域，列表帧底缘随之上抬到键盘顶；`geo.safeAreaInsets.bottom` 却是对全窗安全区表达的量，仍完整含键盘高度（约 320pt 量级）。同一截键盘高先在帧里被收走、又在公式里被减一遍——双扣，钮被多顶约一个键盘高。
- **指纹吻合**：报障两图均为键盘升起态、偏移量约一截键盘高；键盘收起态单扣成立、落位正确（本轮之前的真机口径里钮位无报障）。「只在键盘态错、错量恰为键盘高」即双扣的签名。
- **结论**：假设成立。病不在算术（落位钉测钉的全是算术、全过），在参照系——帧与 inset 在键盘态不再同源，公式把两个不同坐标系的量相减，算得再准也是错的。

### 124.2 外部解法核查

- **苹果 WWDC23《Keep up with the keyboard》**：SwiftUI 中键盘并入安全区，键盘升起时系统自动调整安全区「并随之缩放/移动你的视图」——帧与安全区是联动调整的一对量，官方从未承诺「帧高 − 安全区底 inset」在键盘态仍是同一参照下的差；官方推荐承载键盘上方内容的形态是 safeAreaInset／safeAreaBar 的内容本身（布局流），不是手算偏移。
- **社区通行实践**（键盘适配修饰器一族，如 Augmented Code、Vadim Bulavin 的 KeyboardAdaptive）：凡把键盘高度与 safeAreaInsets 混算处，标准修正式先扣掉已被安全区计入的部分（`max(0, keyboardHeight − safeAreaInsets.bottom)`）——正因两套参照直接相减必双扣，与本案同族。
- **成熟聊天客户端**（Exyte/Chat、Stream Chat SwiftUI，与 §10 承载换代调研同向）：回底/浮钮类元素或居输入条容器本体、或以输入条为锚的布局关系承载，无一在滚动视图 overlay 里以全窗安全区手推落位。

### 124.3 三轮失败根因（一句定版）

0.41.0 挂发送区容器 overlay＋负偏移→钮出宿主 frame、命中被剪枝（点不动）；0.46.1 跨 safeAreaBar 宿主 PreferenceKey 发布 frame→发布链恒不达（整钮消失）；0.47.1 列表 overlay＋自身 inset 推算→键盘态双扣（落位过高）。落点三换、根因同一：**落位一直在不属于输入舱的坐标系里推算**——宿主框、发布值、全窗安全区都不是输入舱本身，输入舱在哪就得依赖一条会断（发布链）、会剪（宿主框）、会漂（参照不同源）的传递链。正修方向因此只有一个：让钮进输入舱自己的排版，落位从「算出来」变成「排出来」。

### 124.4 正修（结构换代）

- **钮迁入 bottomBar 的 VStack 本体**：错误/提示条之下、inputBar 正上方一行，HStack 右对齐承载（行右距 spacingM，与旧浮层横向口径一致）；钮底缘与输入舱顶缘之间只隔栈内 spacingS（既有 gap）。整段随 safeAreaBar 被系统安全区顶起——键盘升/降两态钮恒贴输入舱上沿，落位不变量由构造恒成立、不依赖任何实测值。
- **显隐改由「行的存在」承载**：`showsBackToBottomButton`（Core `BottomFollowPolicy`，口径一字不变）决定行在不在；行高 44＋栈间距的变化走 bottomBar 既有容器动画 `MotionTokens.swap`（与错误/提示条同口径、同容器，此键作第三动画键回归）；钮本体过渡沿用淡入＋0.9 起点缩放。取舍如实记：0.41.0 当年把钮逐出布局流，是为断「显隐→容器高度→锚点摆动」回路；本轮接受行高随显隐变化，依据是防摆护栏已回到判定层（迟滞双阈值＋末条事实信号，0.36.5 钉死），且错误/提示条在本容器内一直以同形态增减高度、无摆动实报。
- **命中**：钮是布局流内的真实帧，命中域恒在宿主 bounds 内——P-20 正案由「算出来的可达」升级为「构造上的可达」。
- **退役**：chatSurface 的 overlay＋GeometryReader＋`.position` 落位整段删；Core `BackToBottomPlacement` 整套删（center/hitRect/isReachable 及命中域常量），不留死代码。显隐政策 `BottomFollowPolicy`、未读计数 `AwayUnreadCounter`、点按回底＋清角标链一字未动。

### 124.5 单测口径

- **随结构退役**：`BackToBottomPlacement` 落位钉测 4 法（落位算术／病灶复现／inset 跟随／退化帧）——所钉纯逻辑已不存在，按 §121 先例随结构销账。
- **新增补钉 5 法**（判定层口径续钉）：角标封顶边界（99 本值显「99」、100 起「99+」）、水位后条目部分删除计数回落、reset 只清计数不动水位、noteOwnSend 空表、LastScrollTarget 全表仅一条工具条目。全仓单测 1264 → 1265，只增不减。
- 三语无新文案，`validate_i18n.py` 通过（2457 键）。
- **真机待验**：键盘升起滑离底部——钮紧贴输入舱上沿右侧出现（对图二 Muse 形态）；点按回底、角标清零；键盘收起态同位；错误条出现时钮行在其下、输入舱之上，落位不变；显隐切换时输入舱滑动幅度与错误条增减同感、无跳动实报。

### 124.6 合并与验包记账（2026-11-11，主线合并单）

- **交付定版**：0.48.1／117。分支 feat/back-bottom-fix（顶端 2599a4c，基线 bc58930）分支 CI run 42964921055 全绿；合并提交 0fc584c（冲突仅 DESIGN-V4.md 一处，顺序拼接 §122.5 在前、§124 在后，两节全保留）；定版提交 d828830（版本五处＝Project.swift 四处 0.48.1/117＋SettingsView 页脚「OneDay v0.48.1」，grep 验无 0.48.0 残留）即合并后 main 顶端。
- **合并后 CI**：run 42965760654 success（build-native success，head d828830）。
- **独立验包**：IPA 9,106,854 字节、md5 `ebcdf251c2051ff4b28d52b0052bb496`、Info.plist 实读 0.48.1／117／bundle id site.didichou.oneday；交付件 `~/workspace/your_files/oneday-v0.48.1/OneDay-0.48.1.ipa`（落盘 md5 一致）。
## §123 闭环包：回响落对话＋通知点达＋三处收口（similar-issues 审计 H1/H2/M2/M3/N2/N3，2026-11-11 12:55 用户按推荐拍板）

基线 main 53f0e86（含 §121），分支 feat/closure-loop 预制；§122 合并排前（动 FeedView/点子面），本包按现行 main 施工、合并时主线三方对账。版本不改（合并时定）。伴生侧小改 1.0.14 已按伴生自动部署规矩上线（报告 hermes-deploy/companion/CLOSURE-114-REPORT.md）——**注意简报原文写「版本号顺延 1.0.13」，但 1.0.13 已于同日 12:54 由 FEED-113 上线，故本包伴生改动顺延为 1.0.14，特此记账**。

### 123.1 题一 · H1 目标委派回响落对话（机制：App 本地回响；不注服务端会话）

- **机制选型与证据**：候选三路——①伴生向绑定会话注入消息（服务端会话由首发铸造、绑定线程可能尚无服务端会话，且注入等于替智能体发言、污染上下文）②Hermes 侧写会话（同①且动本体）③App 本地回响条目（呈现层事实记录）。定③：回响的本质是「App 向用户报告一件已核实的事」，不是对话内容；本地落盘即可达「用户在对话面看到完成消息」的验收标准，且零服务端风险。代价如实记：回响不进服务端会话存档、换设备不跟随（绑定与回响都是本地账，与草稿/滚动锚同级）；智能体在该线程里看不到回响（上下文组装显式排除，见下）——用户在线程里追问时智能体不知情，此为已知取舍。
- **绑定**：SideChatStore.goalThreadIDs（goalID→threadID，UserDefaults JSON 落盘，与 §122 ideaThreadIDs 同形、键名避撞）。创建点＝GoalDelegateView 提交确认落定后（ensureGoalThread）：无绑才建 ChatThread（题＝目标名、titleIsManual 钉住防服务端 AI 标题改掉其身份）、有绑复用。只看详情不建线程（存量关联不因此冒线程；下次在该目标委派时建线程并由规划器一次性补齐全部关联的历史回响，顺序＝关联序、每关联内 delegated→状态）。
- **真源（不许造假回响）**：Core `GoalEcho.plan(linkedTasks:existingKeys:)`——完成只认桥戳 BridgeGoalTaskLink.completionEntryAt（桥在任务落完成集后写戳并落恰好一条进展事实条目，与 App 推测无关）；开始/等你回答/失败认任务板现值经 KanbanStatusPresentation.resolve 的呈现判定（.running/.needsInput/.failed）。「失败」是 blocked+transient+错误在场的呈现判定、非终态，文案只记「执行失败」时点事实、不冒充终局，后续重试转好不回撤（完成回响以戳为独立真源、与失败键分开去重）。任务板没取到任务且无戳→只落「已安排」。去重键 `goalTask:<linkID>:<kind>` 落 ChatEntry.echoKey（新字段，可选默认 nil 轻量迁移），跨启动稳定、重规划不重复落。
- **物化点与时限**：GoalDetailView 首载（.task）与下拉刷新后、且三路真源（关联账＋任务板＋目标）到位时调 materializeGoalEchoes——无 APNs 的现实下，回响在用户下次打开该目标详情时补齐（与动态角标 30 秒轮询同级延迟约束，如实记账）。入口（四问①）：委派段已绑时出「进展对话」行直达绑定线程。
- **呈现与三处守卫**：ChatView.bubble 顶部 echoKey 分支→居中安静通知行（flag 图标＋正文＋时刻；非气泡、无长按菜单、不冒充任何一方发言）。回响借 role "assistant" 落盘，故三处必须排除：①发送上下文组装 filter 加 echoKey==nil（不让 App 的话冒充智能体说过）②落定 deleteTurnPartialEntries 跳过 echoKey 条目（回响可能恰在一轮进行中由详情侧落盘，「用户条目之后必属本轮」的发送互斥前提对它不成立，不许被整段替换误删）③中断恢复的半截回填 filter 加 echoKey==nil（不许把回响当助手半截吞进流式区）。落定对账其余路径只认 user 条目/服务端消息，回响不在其作用域（施工时逐一核过 settle/heal 两路代码）。

### 123.2 题二 · H2 通知中心点达对象（C3：保留汇集定位、不搬结果进对话；伴生 1.0.14）

- **落点解析**：Core `NotificationDestination.resolve`（纯函数钉测）——审批回执（write_gate_decision）带 refId→枢纽审批段聚焦该条已决记录；无 refId→审批段。监测变化（monitor_change）带 refId→监测详情、带 changeId→续达具体变化；无 refId（存量）→监测段。其余 kind→无落点、行面不带箭头。
- **「审批→回原会话」为何不成立（如实记账）**：write-gate 记录契约没有 thread/session 字段（ChatApprovalCards.swift 文件头注为据：裁决记录只有 origin 来源类标签），裁决可来自后台审查/网页端/自动规则，根本不存在「原会话」；聊天内待批卡本就是全局退位形态。本人裁决的 recordId→thread 映射现无留痕。故落点定为记录的家——枢纽审批段已决历史（带 id 时滚动聚焦＋行底色点亮；记录不在已载历史时聚焦落空、停在段内，不假装定位）。若将来要真回原会话，须先在聊天内裁决时新增本地留痕，另立项。
- **伴生 1.0.14**：监测通知此前无任何 id（_notify_locked 记录只有派生切片 id）——oneday_bridge 补 refId=监测 id＋changeId=变化 id，overview 透传＋出口白名单加 changeId。存量通知无字段、落点降级监测段。部署与验收见 CLOSURE-114-REPORT.md（生产监测变化现为 0 条，端到端待第一条真变化＋真机验收）。
- **呈现**：有落点的行带 chevron（宪法 §9 可点必有指示）；点按＝标已读（不等待）＋关通知 sheet＋枢纽接力开启（ChatView 通知 sheet onDismiss 置 hubOpenRequested，避免 sheet 与 fullScreenCover 同帧抢呈现）；AgentHubView 开时消费 hubDestinationRequest 切段并清零，各段消费各自聚焦字段（审批段 hubApprovalFocusID、监测段 monitorDeepLink——监测段验目标在列表才推、详情页按 monitorID 对号消费 changeID 并清零，死链就地清）。
- **原文折叠**：机器原文（rawDetail）从「点整行展开」改行内独立「原始记录」折叠钮——默认折起、与导航点按互不干扰；行面只留人话摘要（既有口径不变）。

### 123.3 题三 · M2 动态讨论预填（Core FeedDiscussPrefill）

旧实现 `post.body.prefix(1200)` 硬截无标记无回指。收口 Core `FeedDiscussPrefill.make`：正文 ≤1200 全文进预填；超限在后半段最后一个句界（。/！/？/换行）截断（无边界才硬断），节选前明标「（以下为原帖节选）」；有正文时尾行恒带回指「（原帖全文在动态页：《标题》）」；空正文只有标题行。回指是纯文本线索（预填是草稿文本，给不了真链接，如实给全标题＋页名）。与 §122 行截断不冲突（那是行呈现、这是预填文本，两个面各自收口）。

### 123.4 题四 · M3 点子底栏角标（Core IdeasBadge＋本地水位）

点子无服务端未读账——走既有 /ideas 读面＋本地增量：新卡＝生成卡（source=.generated）＋待阅（status=.pending）＋createdAt 晚于水位；手记卡不给自己报新。角标搭 ContentView 既有 30 秒轮询同一拍顺带读 /ideas（**不新增轮询回路**），失败保持旧值不清零（与动态角标同纪律）。水位落 AppState（UserDefaults `ideas.seenWatermark`）：首次无水位只立基线不报数（存量不冒充刚到）；进点子页（.task 首载＋列表 onChange）推进水位、角标即清——与动态「进页即清」同口径。呈现＝原生 .badge（与动态格同机制）。

### 123.5 题五 · N2 定时任务面原始值收口（Core CronPresentation；枚举全集已查）

- **生产实查（2026-11-11，只读）**：state.db sessions.end_reason distinct 只有 ws_orphan_reap（13）与 NULL；completed 不在现生产数据里（既有翻译保留）。映射表按 Hermes 源码 end_reason 全部赋值字面量建全集：completed/cron_complete→已完成、cron_incomplete_no_output→已结束（没产出内容）、idle_timeout→空闲超时结束、lru_evict→会话被系统回收、onboarding_restart→初始化重启后结束、session_reset→会话已重置、superseded_by_resume→已被续聊接替、tui_close/tui_shutdown→终端里关掉的、ws_disconnect→连接断开后结束、ws_orphan_reap→连接失效后被回收、compression→上下文压缩后结束、branched→已分出新会话；未知值→「已结束」，绝不直印。落点：CronViews.runSubtitle。
- **deliver**（源码值域）：origin→原对话、local→不投递、log→仅记日志、「平台:会话id」形→「<平台> 对话」（平台是专名照原样、会话 id 是内部编号不上行面）、其余→指定渠道。落点：详情「投递到」行。
- **lastError**：正文位只显摘要（原文第一行、90 字内句界截断——原文自己的话不改写），全文收进「原始信息（排障用）」折叠（与审批面同名同形态），等宽可选。落点：详情错误块。

### 123.6 题六 · N3 监测变化详情结构化（Core MonitorChangeDetail 预览形）

桥无「要点」数据——不编造要点，结构化只到三层：摘要（页头既有）＋预览＋原文折叠。MonitorChangeDetail.Rows 增 beforePreview/afterPreview＋truncated 旗（预览 480 字、优先断在后半段最后换行处、断处带省略号）；页面默认铺预览，被截断才给「展开全文/收起全文」开合（变化前/后各自独立），短原文全显无多余钮。全文仍可选取复制。

### 123.7 新面准入四问（本包新呈现逐项）

- 回响行：入口＝目标详情委派段「进展对话」行（已绑才出）＋抽屉线程本体；无重复（进展流是桥事实账、回响是对话面报告，两面分工已在 123.1 记明）；形态走聊天流既有居中安静行族（次级色＋footnote），无页面直写新数值（间距全走 OneDayMetrics 令牌）；深色随 Palette 语义色、AX 档为纯文本行无定高容器。
- 通知落点行：入口＝通知行本体（chevron 明示）；无新面；折叠钮与台账/审批「原始信息」同名同形态；无定高截断新增。
- 监测原文展开钮、点子角标（原生 .badge 与动态格同件）：均为既有件复用，不立新规。

### 123.8 单测与文案口径

Core 新增 ClosureLoopTests 18 测：GoalEcho 规划五件（排队只落已安排/三态映射/完成只认戳/去重/文案泛称）、NotificationDestination 四件＋changeId 解码、FeedDiscussPrefill 三件（短帖全带回指/空正文/长帖句界节选）、IdeasBadge 两件（计数口径/水位推进含手记不推进）、CronPresentation 三件（endReason 全集＋未知兜底/deliver 值域/错误摘要）、MonitorChangeDetail 预览两件。三语 +31 键（目录 2429→2460，validate_i18n 通过）；被替换的旧文案键 2 条（目标委派说明两处）留作目录孤儿不删（合并时与 §120 的键删改一并对账）。伴生自测全套计数不变全绿（见 CLOSURE-114-REPORT.md）。

### 123.9 真机验收（合并后）

①在目标里安排一件事→目标详情委派段出现「进展对话」→打开见「已安排」回响；在任务板把任务办完→再开目标详情→回绑定对话见「办完了」回响；失败/等回答各造一次同验。②通知中心：审批回执点按达枢纽审批段并聚焦那条已决记录；监测变化（须先有一条真变化）点按达监测详情/变化详情；存量监测通知达监测段；「原始记录」折叠默认收起、展开见原文。③动态长帖点「讨论」：预填带节选标记＋尾行回指；短帖全文无节选标记。④等一轮点子生成（07:30）后底栏点子格出角标、数字对；进点子页角标清零；手记一张点子不报角标。⑤定时任务详情：投递到显中文；有 lastError 的任务错误只显一行摘要、展开见全文；运行记录副题无英文原值（ws_orphan_reap 显「连接失效后被回收」）。⑥监测变化详情：长原文默认只显预览＋「展开全文」，展开见全文。

### 123.10 合并与验包记账（2026-11-11，主线合并单）

- **交付定版**：0.49.0／118。分支 feat/closure-loop（顶端 3235baf，基线 53f0e86）分支 CI run 42966452551 全绿（单测 1264）；合并提交 b15608f——冲突三处按对账处理：DESIGN 顺序拼接（§122／§124 在前、§123 在后全保留）；Localizable.xcstrings 并集 2474 键（strings 口径，零丢失零改值，余 2 孤儿旧键保留待 §120 统一删），validate_i18n 通过（2487 键含 InfoPlist 13）；SideChatStore 的 ideaThreadIDs（§122）与 goalThreadIDs（§123）两段并存；FeedView 只入 discuss 预填、ChatView 只入 echo 首分支＋三处 echoKey 守卫，§122 行呈现／图盒与 §116／§121／§124 段经 diff 核对未动。定版提交 21e5a2f（版本五处＝Project.swift 四处 0.49.0/118＋SettingsView 页脚「OneDay v0.49.0」，grep 验无 0.48.1 残留）即合并后 main 顶端。
- **合并后 CI**：run 42967571383 success（build-native success，head 21e5a2f）；单测 1283（main 基线 1265＋ClosureLoopTests 18，只增不减）。
- **独立验包**：IPA 9,190,223 字节、md5 `ba0e2e5250a341c56d8b3fee201804c6`、Info.plist 实读 0.49.0／118／bundle id site.didichou.oneday；交付件 `~/workspace/your_files/oneday-v0.49.0/OneDay-0.49.0.ipa`（落盘 md5 一致）。
- **真机待验**：见 §123.9 六条（目标回响全链、通知点达与原文折叠、讨论预填节选标记＋回指、点子角标、定时任务人话、监测详情预览展开）。

## §126 动态页紧凑化包（2026-11-11，预制分支 feat/feed-compact，基线 main 4271410；§123/§125/§118–§120 在各自预制分支，合并时主线按序拼接）

起因：用户 2026-11-11 13:19–13:24 连点三题——图一（OneDay 动态）页头两处死空（原话「搜索框下面留这么多是给鬼留的」「今天下面也留这么多干什么」）、「动态不要提醒，顶部这个设置提示词的删掉，右上角有设置按钮呢」；13:37 对调研报告（muse-three-pages-essence-20261111.md 第 2.3/5.1 节）拍板「按推荐全做」（紧凑化＋搜索改点开式，点子加强 G1+G2 不在本包、归桥侧生成面）。版本五处未动（合并时主线定号）。

### 126.1 覆盖声明（旧口径作废）

- **§117「顶部简报胶囊常驻」作废**：胶囊行整行删除（本节 126.2），简报设置入口只归工具栏滑杆钮。
- **§104/§117 动态未读提醒口径作废**：底栏角标、胶囊内「N 未读」、帖行蓝点、动作行「未读」文字四面全撤（126.3）；已读管线（桥侧 readAt、App 打开/露面回写、FeedBoard.unreadCount 与 generation 账面）保留为静默账本，只停提醒面与为角标服务的轮询，不连根删管线——将来确认不再用于排序/恢复/审计再单独退役（调研报告 0.2 处置意见）。
- **§122 的 64pt 顶距处置修订**：§122「不得遮字」的验收目的保留，实现由无条件 contentMargins 改为条件化政策（126.4）；§122.2 的「对尺附记」中避让一条随之修订。
- **§117 搜索常驻行口径修订（证据更新）**：常驻 .searchable 行改为工具栏点开式（126.6）。§117 当年按用户所发 Muse 截图定常驻形态，本轮同一页的更新并排图已无常驻搜索行，按调研报告标注为证据更新，不假装旧定版从未存在。

### 126.2 删简报胶囊行

- FeedView List 第一个 Section（briefRow/capsuleRow 二选一呈现）整段删除，bannerRowChrome 共用外壳随之退役（全仓仅此二行消费）。删后列表第一段即第一个日期分组，标题之下直接接分组头/首帖。
- **入口核实**：工具栏滑杆钮（slider.horizontal.3）现行实现即 `briefEditorShown = true` → sheet 呈现 FeedBriefEditorView（两层制编辑器本体一字未动），无需补接；FeedStore 照旧加载 briefDoc 供编辑器消费，store 侧不删字段。FeedBriefBoard.summaryLine、FeedBoard.capsulePost 等 Core 纯函数随呈现退役而无消费方，保留原地（单测仍钉其口径，不为删呈现而拆 Core 账）。

### 126.3 撤一切未读提醒面

- **底栏角标**：ContentView 删 `.badge(feedUnread)`；壳层为角标服务的整套一并退役——`feedUnread` 状态、专用 `feedBadgeClient`、scenePhase 驱动的 30 秒轮询 task 与 `pollFeedUnread()`（该轮询只喂角标一处，grep 实证无第二消费方）。ContentView 本包 diff 只动上述动态角标相关行（§123 闭环包在同文件加 M3 点子角标，合并时主线对账）。
- **行内两面**：postRow 标题旁未读蓝点（Circle 7pt）删除；actionRow「未读」文字删除（其 A11Y-C5「蓝点另有文字通道」的配对关系随两面同撤而消解，不留单边）。
- **静默账本保留**：postRow onAppear 回写、openPost/详情页 markRead、FeedStore.markRead 全链一字未动；FeedStore 头注③同步更正（账面只供空态口径）。

### 126.4 顶距条件化

- **政策收口 Core**：`FeedBoard.topClearance(overlayHeight:gap:)`——overlayHeight 为 nil 或 ≤0 恒 0；真重叠＝实测重叠高度＋gap。单测 5 法钉死（nil/0/负→0、44+8→52、gap 原样透传），见 126.8。
- **视图接线**：FeedView 以 `@State topOverlayHeight: CGFloat?` 为唯一喂入口，`topMargin` 计算属性走政策、gap 传令牌 spacingS(8)。**如实记账**：现行壳层没有覆盖本页的浮层（全仓核查——任务进展胶囊只在聊天页 safeAreaBar 内，本页工具栏由导航栏安全区托管），故本值恒为 nil、顶距恒 0；壳层将来在本页上方挂浮层时把实测高度写进此入口即按政策生效。此处不许再写任何无条件数字冒充条件化（§122 的病即在此）。
- §122 的 64pt（spacingXXL＋spacingM）与 `topCapsuleClearance` 常量整段删除，grep 零残留。

### 126.5 日期段几何收编

- 段头改自定义 header（dateGroupHeader）：字阶/配色对齐原系统段头呈现（.subheadline semibold＋Palette.inkSecondary，不另造字号），上下 padding 显式定值 spacingXS(4)。
- 段间 `.listSectionSpacing(spacingM 16)` 显式设定（此前未设，约 62pt 系统默认几何无人拥有——调研量测死空二的主体）。
- header 布局底→首行内容顶不另加距：帖行自身 `.padding(.vertical, spacingS)` 的顶部 8pt 只计一次（帖行原有口径不动）。构造账：「今天」字形下沿→首帖标题上沿 ≈ header 底 padding 4＋帖行顶 padding 8 ≈ 12pt（目标 ≤32pt）。

### 126.6 搜索改点开式

- `.searchable` 落点由默认（常驻行）改 `.toolbar`：放大镜在工具栏内点开才展开搜索场，未展开时不占行。0.47.0 的自绘放大镜 ToolbarItem 与系统落点自带入口重复占位，一并退役；滑杆钮保留（126.2 入口核实）。
- 过滤逻辑一字未动（visiblePosts 按标题＋正文命中、与全量同走 FeedBoard 分组）；收起即清过滤态——`onChange(of: isSearching)` 在关闭时清空 searchText，照系统惯例不留隐形过滤。

### 126.7 量测前后对照（口径同调研报告 2.3：402×874pt 截图字形/形状边缘）

| 段 | 改前（量测实证） | 改后（构造值） |
|---|---:|---:|
| 常驻搜索框 | 44pt 占行 | 0（未展开时不存在） |
| 死空一（搜索框下沿→胶囊上沿） | 80pt | 随搜索行与胶囊行一并消失；顶距条件化后恒 0 |
| 简报胶囊行 | 45pt＋上下 insets | 整行删除 |
| 「今天」字形下沿→首帖上沿 | 约 70pt | ≈12pt（126.5 构造账），目标 ≤32pt |
| 首帖标题起点 | 屏高 53.0% | 构造上 ≈ 标题区＋段头 ≈ 屏高 16% 上下，验收线 ≤27%（合并后真机按同口径复量为准） |

### 126.8 单测与校验

- 新增 FeedCompact126Tests 5 测（顶距政策：无重叠三态归零、重叠加 gap、gap 透传），全仓单测只增不减。
- 三语文案：随删行清理孤立键 4 个——「%lld 未读」「今日暂无动态」「点按写简报」「写下你感兴趣什么，我每天替你去看」（grep 实证仅被删行消费；「未读」「未读，%@」另有监测/通知消费方，不动）。目录 2457→2453 键，validate_i18n.py 通过。
- 红线守界：未碰 ChatView/输入舱（§124 承载结构）、未碰点子面、未碰 §125 文件面在飞代码；FeedView 之外只动 ContentView 角标相关行与 FeedStore 一行头注。

### 126.9 真机待验

- 页头栈：标题→（无搜索常驻行、无胶囊行）→「今天」段头→首帖，首帖标题不晚于屏高 27%；「今天」下空段 ≤32pt；最大字号档与深色模式各一帧。
- 搜索：点工具栏放大镜展开搜索场、过滤按标题＋正文生效、取消收起后过滤清空且列表位置不乱跳。
- 简报：滑杆钮打开两层编辑器、保存链与从前一致（胶囊行删除不影响编辑器数据）。
- 未读：底栏动态格无角标、新帖到达不出现任何催读面；打开帖子后已读回写照旧（服务端 readAt 落字、重进页不回弹未读——账本仍在工作，只是无声）。

### 126.10 合并与验包记账（2026-11-11，主线合并单）

- **交付定版**：0.49.2／120。分支 feat/feed-compact（顶端 0041b17，基线 4271410）分支 CI run 42967724270 全绿；合并提交 a1030e0——冲突两处按对账处理：DESIGN 顺序拼接（§123 在前、§126 在后，两节全保留）；ContentView 逐行对账（见下）。定版提交 c8289a8（版本五处＝Project.swift 四处 0.49.2/120＋SettingsView 页脚「OneDay v0.49.2」，grep 验无 0.49.1 残留）。
- **ContentView 对账（如实记账，含对 §126.3 预制口径的一处修订）**：126.3 记「轮询只喂角标一处」系预制基线（4271410）当时的实情；§123 合并后 M3 点子角标搭同一条 pollFeedUnread 的 30 秒拍顺带刷新（AppState.refreshIdeasUnread 全仓唯一调用点即在此回路）。合并处置：动态半边全删——feedUnread 状态、feedGeneration 取数、底栏 .badge(feedUnread) 合并后零残留；回路改名 pollIdeasBadge、只余点子角标一职，scenePhase 驱动保留，feedBadgeClient 因 M3 仍在用而保留（126.3「专用客户端一并退役」一句随此修订作废）。§123 的 .badge(appState.ideasUnread) 与 IdeasBadge 判定链未动。FeedView 侧 §123 discuss（FeedDiscussPrefill.make）、§122 行呈现/16:9 图盒、§118 S2-11 主钮经 grep 逐项核在位；ChatView 未入合并 diff（§124 回底钮承载段未动）；readAt/markRead 静默账本全链保留（FeedView 未读字样仅剩记账注释）。
- **xcstrings**：并集后按 126.8 删 4 孤儿键（删前 grep 全仓复核：短键零消费方；FeedView 空态长句「写下你感兴趣什么，我每天替你去看；第一轮…」系另一键、仍在目录且在用，未误删）；目录 2487→2483 键（validate 口径，含 InfoPlist 13），validate_i18n 通过。
- **合并后 CI**：run 42971891493 success（build-native success，head c8289a8）；单测 1301（CI 根套件 Executed 数与合并树 func test 计数一致；0.49.1 基线 1296＋FeedCompact126Tests 5，只增不减）。
- **独立验包**：IPA 9,163,448 字节、md5 `d22d5e8b3f62cc20c6e7b016f8e6dd17`、Info.plist 实读 0.49.2／120／bundle id site.didichou.oneday；交付件 `~/workspace/your_files/oneday-v0.49.2/OneDay-0.49.2.ipa`（落盘 md5 与 CI 产物一致）。
- **真机待验**：见 §126.9 四条；另加 §123 回归一条——点子新轮生成后底栏点子角标照常出数、进点子页清零（验 pollIdeasBadge 改名续接后链路不断）。

## §125 文件呈现对标包（2026-11-11，分支 feat/file-open-flow，基线 main 62c0b3c；用户 13:15 拍板主包＋表格转码二期一起做，规格唯一依据 file-open-flow-benchmark-20261111.md）

### 125.1 文件牌升卡（修订设计标准 §5.5 FileChip 原式）

- **修订声明**：《设计标准》§5.5 的 FileChip 原式（sky 天蓝底胶囊＋通用 doc 图标＋文件名一行）就此退役——调研实证 Muse/微信文件牌均为白卡＋类型图标＋名＋「类型 · 大小」副行（benchmark §3.1/§3.2），胶囊形态无类型、无大小、与大厂差集成立。新式：Palette.surface 白卡、圆角 16（radiusPreview）、内边距横 12/纵 10、随气泡宽，用户/助手两侧同形；左＝40pt 类型图标盒（FileIconBox 加尺寸参数：列表 36/聊天卡 40/打开页 56，字形与圆角按边长比例推导，一处改三面齐变）；中＝文件名 .body semibold 至多 2 行＋副行 .caption 次色「类型 · 大小」（类型 DeliverableFileType.label、大小 ByteCountFormatter.file，与文件页 browserSubtitle 同制）；右无常驻按钮，卡整体可点、长按沿用消息菜单。
- **C8 未裁定守界**：图标沿用现行字母块表（DeliverableIconStyle 单源，办公三件品牌色底＋白色粗体单字），本包不换方案；C8 裁定后改 Core 一表三面齐变。
- **大小数据源（不许编造）**：FileMetadataStore（进程内缓存）三路实测回填——①发送回填点（§121 写回 remoteFilePaths 同点）按回执同序记本地字节数；②打开/下载完成记实际字节数（FileOpenContent.fetchBytes、表格页下载原文件）；③父目录 files() 列表回读整目录回填（失败静默）。三路皆无只显类型，打开页内再补全。待发附件筹码图标同源（attachmentChip 的通用 doc 字形换 FileIconBox 36，名＋大小副行不动）。

### 125.2 FileOpenView 中间页（sheet 形态）与 FilePreviewView 收编

- **单源共建**：新 FileOpenView（sheet＋自带 NavigationStack）/FileOpenContent（push 形态）一壳两用——聊天点牌（openChatFile 改道）、文件浏览器行、资料库条目三入口全落此页；旧 FilePreviewView 整支删除（FilesView 留墓碑注释），其 QL 宿主段收编为页内 QuickLookHostView、失败页与敏感锁定分支收编进本页状态机。资料库旧 readerEntry/previewEntry 双目的地分流合并为单一目的地先进中间页（文本类由页内主钮进阅读页）。
- **页面构成**：顶栏＝左 ✕（仅 sheet 形态）/中文件名（inline）/右「···」菜单（readingActions 同源同序＋详情）；文件头＝56pt 图标盒＋文件名 .title3 semibold 至多 3 行全显＋「类型 · 大小」＋人话来源行（来自这条对话/服务器上的文件）＋有则「修改于 …」；原始路径/字节数只进低频详情页。主钮一颗走 FileActionPolicy 新增落点列 landingPrimary（阅读/预览/播放/查看表格/保存到文件，策略表第四列、既有三列语义不动）；次动作＝readingActions 安静列表行（与顶栏菜单同源，菜单供页内承载时够手、列表行供中间页本体）。
- **五态状态机**：元信息加载中（副行小转轮＋主钮禁用，回读失败也算一轮已回不无限禁用）／就绪／下载中（不定量进度——/api/files/download 为整包数据任务、无字节级进度通道，如实不定量＋已知总量文案，可取消）／预览承载（页内 push，保留顶栏）／失败（页内警告块＋FileOpenFailure 五分文案＋failureActions，与 Muse 失败页同形）。敏感文件恒锁定分支（无法预览＋SensitiveFilePolicy.explanation＋知道了，不渲染不给下载）。

### 125.3 路由表 Core FileOpenRoute（纯函数＋钉测）

- 输入＝FileOpenTarget（名称/路径/可选大小/可选修改时间/mime/可选锚点，聊天由牌构造、文件页由条目构造，workspaceEntry 合成供既有 entry 策略表复用）＋canPreview 资格（§121 既有门）。矩阵：image→直达查看器（不经中间页，宿主拦截；中间页仅作防御落点）；text→中间页→阅读页；pdf/office/html/video/audio→中间页→页内 QL（canPreview 假降 infoOnly）；xls/xlsx→中间页→转码表格；archive→中间页 saveOnly（主钮保存到文件）；other→中间页 infoOnly（说明行＋分享/下载）；敏感→locked。
- **§121 落点修订声明**：§121「不可预览点牌直落分享单」收编进中间页——QL 资格门与五分文案机制不变，落点由分享单升级为中间页失败态（unsupportedType＋failureActions）；§116 文件面口径（网关五形态出牌、GBK 转码）不动，牌面形态按 125.1 升卡。
- FileActionPolicy.category 收名称口径为原语（category(forFileName:mediaKind:)），条目口径委托之、逐格同果（钉测对账）；WorkspaceFileEntry 补公开 memberwise init（解码路径不变）。

### 125.4 表格转码二期（伴生 1.0.15；版本号顺延注：施工中发现并行线已先行部署 1.0.14，本地原拟 1.0.14 改 1.0.15；源码基线以生产 build-114 的 oneday_bridge.py 实测 diff 对账——本地补丁为纯增 330 行、零删改，恰为超集）

- **端点**：oneday-bridge 新增 GET /files/spreadsheet?path=（Bearer 单钥鉴权走既有 _authed）。路径合规照 Hermes files 下载同规：根锁 /opt/data（SPREADSHEET_ROOT 可覆盖）、不存在 404、非文件 400、敏感 403（名单与 App SensitiveFilePolicy 逐项镜像：protectedNames/敏感扩展/词元＋子串兜底）、超 100MiB 413、旧版 .xls（OLE 魔数）与不可解析 422。
- **转码口径**：零依赖 stdlib（zipfile＋XML，镜像内无表格库、不新引依赖）；值口径——公式取缓存值、无缓存值渲染空并计数进 notes 如实标注；合并单元格值只在左上格（格式本身如此存，CSV 即此读法，无格式还原）；日期经 styles.xml 数字格式识别渲 ISO（内置日期格式 id 集＋自定义格式码启发式；Excel 序列 60 的虚构 1900-02-29 折叠至 1900-03-01，只读呈现妥协、记账在此）；数字整数去尾 .0。单 sheet 500 数据行截断（total_rows 报实数、truncated 明示，App 侧已显示行数由回带 CSV 实算、上限不写死端上）；sheet 上限 50。
- **App 侧**：SpreadsheetReaderView——OneDayBridgeClient.spreadsheet 状态码保真（不走 checkStatus 人话收敛，422/413/404 原样包 HermesError 交 FileOpenFailure.classifySpreadsheet 分型：422 转码专档新文案、余与下载同规；无钥匙/桥未通归 serviceUnavailable 档）；呈现走 DocumentReading csv 块＋DocumentBlocksView（由 DocumentReaderView 抽出共用，渲染单源），sheet 分段切换，桥 notes 原样带出。csv 文件不经转码、直接走阅读页（规格口径）。
- **自测**：新增 oneday_bridge_spreadsheet_selftest 20 测全过（鉴权/类型值/公式缓存与无缓存/日期/CSV 转义/多表/截断/路径六分），已挂 run_bridge_selftests.sh；全套自测绿（基线只增不减）。

### 125.5 行号锚点搭车（ekko #L 形态）

- Core：FileLineAnchor（parse 接受 L12/L12-L20/L12-20/# 前缀，非法回 nil）＋split（路径＋锚点拆分）；FileRefDetector 内部收口为 scan，detect 旧口径不变（路径恒干净），新增 detectAnchored 带回锚点；用户侧 remoteFilePaths 亦走 split 拆锚。
- 阅读页定位（仅 text 类消费，其余类型解析保留、呈现忽略）：plain 按 DocumentReading.plainParagraphLineRanges（与 plainBlocks 分段逐字同规、钉测对账段数）段落高亮＋ScrollViewReader 滚动定位；structured 整段代码块按行分组高亮（行号即原文行号）；markdown/csv 无行↔块映射，走锚点摘录卡（DocumentReading.excerpt 取行段原文置顶呈现，越界收敛、整段落在文本外不摆卡）。DocumentReaderView 新增 anchor 入参（默认 nil，旧调用点零改动）。

### 125.6 单测与校验

- 新增 FileOpenRouteTests 16 测：路由矩阵（图片/文本/QL 族/表格特判/csv 不走转码/无预览族/canPreview 降级/敏感锁定）、落点列映射、分类名称-条目对账、锚点解析与拆分、detectAnchored、段落行段与摘录、转码失败分型。CI 实测 Executed 1280 tests、0 failures（本地 func test 计数同为 1280；只增不减）。施工中 CI 两轮红已修并记账于提交史：①plainParagraphLineRanges 的 if-let 遮蔽赋值冲突；②名称口径 category 在 mediaKind 为 nil 时影音类落 .other——改经合成条目推导（条目 mediaKind 扩展名表单源），对账测补影音三档。
- 三语文案新增 19 键（Localizable 2444→2463），validate_i18n.py 通过。
- 红线守界：未碰回底钮/输入舱（§124 在飞）、§122 三页面、§123 在飞面；FileActionPolicy/DeliverableIconStyle/FileOpenFailure 三单源零分叉（落点列与转码档均为原表内增列增档）。
- 真机待验：xlsx 点开中间页→查看表格全链（多表切换/截断明示/公式无缓存注记）、.ipa 中间页说明行＋分享下载、聊天文件卡大小副行三路回填、带 #L 锚点的助手文件牌进阅读页定位、文件页三入口落中间页、敏感文件锁定分支。
- **分支终局**：feat/file-open-flow 顶端见合并单；分支 CI run 42968384303 success（build-native 全绿，head 74fa0bb），单测 Executed 1280、0 failures。伴生 1.0.15 已上线（FILE-115-REPORT.md：端点自测 20 全过、生产冒烟真实 iCost 表 3893 行截断明示、Hermes StartedAt 未动、内存 51%）。App 版本号未改（合并时主线定号）。

### 125.7 合并与验包记账（2026-11-11，主线合并单）

- **交付定版**：0.49.3／121。分支 feat/file-open-flow（顶端 737cb2d、代码顶端 74fa0bb，基线 62c0b3c）分支 CI run 42968384303 success（单测 Executed 1280）；合并提交 f49e2b3（冲突两处：Localizable.xcstrings 按 key 三方并集——主线 2470＋分支新增 19＝2489 键、零双改、§126 已删 4 孤儿键保持删除，validate 口径 2502 键含 InfoPlist 13、validate_i18n 通过；DESIGN-V4.md 顺序拼接 §124→§123→§126→§125 四节全保留）；定版提交 9be8818（版本五处＝Project.swift 四处 0.49.3/121＋SettingsView 页脚「OneDay v0.49.3」，grep 验无 0.49.2 残留）。
- **对账复核**：FilesView 排序 Picker（§118 S2-05）与 DeliverablesView 显示/排序 Picker（§118 S2-04）在位；FilePreviewView 整支删除（FilesView 留墓碑注释）、三入口（聊天 openChatFile／文件浏览器／资料库）全收编 FileOpenView/FileOpenContent 中间页；ChatView §116 文件牌链、§121 出牌回填（remoteFilePathsData 写回＋reconcileUserMessages）与 FileOpenFailure 五分、§123 echo 行与三处守卫、§124 回底钮 bottomBar 承载段逐项 grep 在位、无重复定义；Core FileOpenRoute/FileLineAnchor 为准，xlsx 走桥 spreadsheet 端点＋classifySpreadsheet 分型；DeliverableIconStyle 字母块表未入合并 diff（C8 按用户 14:32 定版另行调研先行，不在本包）。
- **合并后 CI**：run 42973245502 success（build-native success，head 9be8818）；单测 Executed 1317、0 failures（0.49.2 基线 1301＋FileOpenRouteTests 16，只增不减）。
- **独立验包**：IPA 9,281,841 字节、md5 `a32bfe5cb1fad7712c3314a0ac62a1f1`、Info.plist 实读 0.49.3／121／bundle id site.didichou.oneday；交付件 `~/workspace/your_files/oneday-v0.49.3/OneDay-0.49.3.ipa`（落盘 md5 与 CI 产物一致）。
- **真机待验**：见 §125.6 六条（xlsx 中间页查看表格全链、.ipa 说明行、文件卡大小三路回填、#L 锚点定位、文件页三入口、敏感锁定分支）。伴生端点 1.0.15 已先行上线（现行伴生 1.0.16），本包未动伴生。

## §119 模型设置简化重做（预制分支 feat/model-simple，基线 main a11c52f；用户 2026-11-11 12:10 亲定＋12:15 六点拍板，调研报告 research_notes/model-settings-simple-20261111.md）

呈现层重组＋辅助面新建，0.37.0 管道（ProviderRegistry、密钥 PUT /api/env 只存 key_env 引用、验活、组合经伴生 meta＋Dashboard 全量写回）能复用全复用；2026-11-10「网关渠道必须显示且可管理」的**呈现口径**由本节覆盖（渠道降为卡内标记＋详情查看），底层注册/密钥落盘/组合存储不动。版本未动，合并时主线定号（预计 0.48.0）。

### 119.1 与调研报告映射表逐项对应

- **服务商卡＝`providers.<名>` 一条**（报告 3.1）：ModelSettingsView 改卡面，一卡一件——名称、接口地址、密钥状态（只显已存/未存、永不回显值）、默认标记、动作（获取模型/测连接/编辑/删除/设为默认，设默认只在默认服务商卡的模型行上，见 119.5 约束）。模型清单回归卡内展开；网关卡的模型按渠道读面（channelsFace）交叉标来源渠道名，读面没就绪不标不编造。
- **清单刷新 ekko 式**（报告 3.1/ekko B 族）：具名卡「获取模型」先拉新清单算差异（Core ModelListDiff 保序），没变直接报「没有变化」；有变弹确认（将删 N 个＋名单/新增 M 个＋名单），确认后才落盘；落盘前把现清单暂存本机 UserDefaults（键 `providerPrevModels.<名>`，只存模型名清单、非敏感），卡上出现「恢复上一份模型清单」（恢复与现清单互换、可再撤）。默认服务商卡的清单是服务端现读、不落 App 存储，无差异/恢复概念，「获取模型」即重拉目录＋报数。
- **测连接三态**（Core ProviderConnectionOutcome）：连通报发现数／通但无目录（connectedNoCatalog：探针 emptyList 不再算失败）教手填模型 ID／失败给「仍然保存」出路——编辑器里 canSaveAnyway 时出现该钮，只绕过 validateDraft/validateEditDraft 的「模型为空」一闸，其余闸（名字/地址/密钥）照走。既有卡测连接的密钥经 /api/env reveal 只过手、不留存。
- **主端点卡＝现行顶层 model 本体**（报告 3.3）：卡名「默认服务商」，零迁移；其模型清单即网关候选（availableModels 管线），逐个可设默认（既有 setDefaultModel 候选校验＋写回）。Dashboard config 表示里 model 被压成字符串、主端点地址/密钥不在此表示内——卡面如实呈「接口地址：在服务器上配置，App 里只看不改」「密钥：在服务器上保管」，不假装可编辑。渠道九条只读列表降为该卡内「查看渠道」展开（原 channelsGroup 平移）。
- **辅助页每行一槽**（报告 3.2）：数据源 Core 新注册表 AuxSlotCatalog——19 活槽（键名依 Hermes `_aux` 工厂实查），死三槽（web_extract/session_search/skills_hub）永不呈现、旧 AuxSlotCatalog 12 槽目录（含死槽）已删。值域统一：跟随主模型｜任一服务商的任一模型；落盘 provider 口径：跟随＝"auto"＋""；指默认服务商写 "custom"（与生产 vision 现行写形一致），读时 "custom"/"main" 均归一为默认服务商；"auto" 且带模型归一为默认服务商指定（本部署 auto 实际走主通道，语义等价）；不在册的 provider 串原样保真呈现（行内「现在的设置（不在服务商名单里）」组），不吞不改。写只动 provider/model（enabled 给了才动），同槽位其余键（timeout 等）原样保留（AuxAssignments.applying 纯函数＋钉测）。
- **组合降预设**（报告 3.4）：存储沿用 ModelComboDocument（桥 meta）**零数据迁移**，旧组合自动即预设、呈现改名。新预设抓取口径改整套快照（PresetSnapshot.capture：默认模型＋全部 19 槽当前分配、跟随项显式记 auto，启用即真重置；与 ComboStarter 只收非跟随项的稀疏口径不同，旧组合启用时仍按其稀疏语义只动点名键）。编辑器 PresetEditorView 替代 ModelComboEditorView：名＋默认模型（仅网关候选，激活守卫口径不变）＋辅助行（与辅助页共用呈现模型）；保存旧预设时其 delegation/fallback 字段原样保留不编辑、不丢，编辑器内有一行说明。入口文案与 MoA 划清一句：「预设不是多模型汇总——那是几个模型一起答一道题」。
- **未配模型引导**（ekko 差集③）：Core ModelSetupGuidance.needsSetup 纯函数——网关候选为空且具名服务商模型总数为零才为真；总数未知（配置未读到）恒假，不误报（生产现行：命名服务商为零但网关有候选＋默认已设，恒假，钉测四例覆盖）。AppState.refreshModelCatalog 顺带派生 providerModelTotal。聊天页落点＝空态（currentThread==nil 且未在生成）下方引导卡「还没配置模型」＋[先等等（本次消卡）][去设置（pendingSettingsRoute=.models＋settingsSheetRequested 现成通道直达本页）]；未碰 ChatView 的 §116 解析/文件牌/回底钮段。

### 119.2 六点拍板落账（2026-11-11 12:15「按推荐全定」）

①辅助行分层＝常用 11＋折叠 8，按报告 §3.2 线并作一处调和：报告把 review 列常用、mcp 列折叠，任务单另定 review 放折叠层——以任务单为准，mcp 提至常用凑 11（常用＝vision/compression/title_generation/approval/background_review/voice_chat/mcp/kanban_decomposer/triage_specifier/goal_judge/curator；折叠＝review/memory_query_rewrite/tts_audio_tags/profile_describer/group_router/monitor/moa_reference/moa_aggregator），钉测锁定。②MoA 两行仅当任一已被设为非跟随、或当前激活预设含 MoA 分配时出现（AuxSlotCatalog.sections 判定＋钉测三例）。③review 行放折叠层，行说明点明其异形（自带调用方式、与其他行只选模型不同）。④辅助写回文案如实标「保存后下次重启 Hermes 后生效」（热生效未验，实测并入收官窗口那次重启，见 119.5）。⑤title_generation/background_review 的 enabled 开关在行内露出（只露 enabled，其余附属项不露；读缺失按开、出厂口径）。⑥渠道降为标记＋卡内详情，按简化定版执行。

### 119.3 写回通道选型

辅助读写选定 **Dashboard config 全量写回**（GET/PUT /api/config，与服务商条目、默认模型同一条既有写路：先读全量、只改点名键、未知字段原样保留）。**不给伴生加新端点**——伴生侧零改动、零部署。理由：auxiliary 本就住在 Hermes config 里，组合激活（0.37.0）已用同一通道写同一段并验过；再开伴生端点只会多一条要对账的路。

### 119.4 细节审计对账行（追加并入，2026-11-11）

- **D3-01（「槽位」词族 8 条）逐条销**：①小节名「辅助槽位」→新页只有「辅助模型」②「%lld 个辅助槽位」→「已给 %lld 个用途指定模型」（且只数非跟随项）③组合启用回执→「预设「%@」已启用。辅助模型若没立刻变，随服务下次重启生效。」④空态「还没有设置任何槽位」→「还没有给任何用途单独指定，都跟随主模型」⑤「这套组合还没有设置任何槽位，激活不会改动现在的配置。」→「这套预设还没有给任何用途单独指定，启用不会改动现在的配置。」⑥编辑器引导「看图、标题、压缩这些活各用哪个模型。没打开的槽位保持现在的设置不动。」→随旧编辑器退役，新预设编辑器/辅助页文案无此词⑦报错「…把它放到某个槽位里按直连用。」→「…或在辅助模型里给某个用途指定它。」⑧「还没有添加提供商。添加后，它家的模型会出现在上面的清单里，也能在组合里按槽位选用。」→旧清单页下线、该串不再引用（同时销 D3-16）。新写文案全程避开「槽位」词族（代码标识符与注释不在用户面，不计）。
- **D3-16（「提供商」16 条）逐条销**：16 键全部位于本包改动面（模型页/编辑器/Store/校验/探针），新串一律「服务商」：页面标题「模型与提供商」→「模型与服务商」；其余 15 条（添加/删除/校验三条/探针一条/Store 回执五条/空态与留位两条/清单说明一条）均已换词或随旧页退役。旧键留作目录存量孤儿（与 §109.5 坏键未删同例），不删目录既有键。
- **D3-13（顺带销）**：「主端点（经网关）」→「默认服务商（经网关）」（SlotChoice.providerLabel，main/custom 同归一）。
- **D3-10 定位备注（不在本包范围）**：「验活没过」「仅配置在册 · 未验活」两键实查位于云电脑/连接面（CloudComputerViews/CompanionFrontClient 一带），非模型面；本包测连接三态已按人话定版，云电脑面两键随连接器下一包处理，此处只登记定位。
- **新文案自查**：本包全部新源串避开报告词族（槽位/桥/闸门/端点/验活/轮询/上游/未落定/对账/镜像）；validate_i18n.py 通过（2566 键，新增 138 键三语齐、目录 diff 纯增零删）。§120 人话包将扩校验器黑名单并覆盖源串，合并时以扩后校验器复跑为准。

### 119.5 约束、未验与知悉

- **具名服务商「设为默认」不落**：Dashboard config 表示里 model 只有模型名字符串、没有 provider 指向，具名模型的选用语法未实测（§103.6 旧账④）；硬写名字会把默认指去网关路造成坏配置。故具名卡不给「设为默认」钮，其模型经辅助行/预设行选用（可用路径真实存在）。待收官窗口实测具名 provider 会话锁/默认语法后再议。
- **辅助写回热生效未验**（旧账③延续）：文案已按「下次重启生效」写；实测并入收官窗口重启（PAT 窗口）一并验，不单独折腾生产。
- **编辑服务商名字锁定**：名字是 providers 字典的键，改名＝换键（牵动 env 钥名与引用），编辑态禁用改名并明示「要换名字请删掉重新添加」。
- **真机待验**：卡面展开/测连接三态/清单差异弹窗/恢复上一份、辅助页 19 行选择器与两开关、预设快照启用、未配模型引导卡（须在真空配置下验，生产恒不出现）、AgentHub 入口进本页后辅助页 NavigationLink 的栈行为（设置 sheet 路径已确认有栈；枢纽路径待真机一验）。
- **已知存量**：目录旧键（槽位 8＋提供商 16＋主端点 1）成孤儿保留，不在本包删键（删键口径随 §120 校验器扩版一并处置）。

### 119.6 合并与验包记账（2026-11-11，主线合并单）

- **交付定版**：0.50.0／122。分支 feat/model-simple（顶端 029fa05，基线 a11c52f）分支 CI run 42960071308（分支单测口径 1250）；合并提交 4d23a29（冲突两处：Localizable.xcstrings 按 key 三方并集——base 2415、main +78/−4、分支 +138/−0、并集 2627 键、零双改，§126 已删 4 孤儿键保持删除，validate_i18n 通过 2640 键含 InfoPlist 13；DESIGN-V4.md 顺序拼接，§119 节顺接于 §125 之后全保留。AppState/ChatView 自动合并，ModelSetupGuidance 接线与 providerModelTotal 派生 grep 在位、AuxSlotCatalog 单一定义）；定版提交 a003384（版本五处＝Project.swift 四处 0.50.0/122＋SettingsView 页脚「OneDay v0.50.0」，grep 验无 0.49.3 残留）。
- **合并后 CI**：run 42978004561 success（build-native success、steps 零失败，head a003384）；单测 Executed 1336、0 failures（0.49.3 基线 1317＋§119 新增 19，只增不减；分支口径 1250＝其旧基线 1231＋19，差额为分叉后 main 侧 §122/§123/§125/§126 增量）。
- **独立验包**：IPA 9,410,629 字节、md5 `a48f9c9bfc715be26e24c99c88c63983`、Info.plist 实读 0.50.0／122／bundle id site.didichou.oneday；交付件 `~/workspace/your_files/oneday-v0.50.0/OneDay-0.50.0.ipa`（落盘 md5 与 CI 产物一致）。
- **两处如实约束的呈现位置**：①具名服务商不给「设为默认」——设默认只在默认服务商（网关）卡的模型行（点行弹「切换默认模型？」确认）；具名卡模型行无此动作，说明文案在预设编辑器 PresetEditorView（「只有经网关的模型能设为全局默认；直连服务商的模型请在下面给具体用途指定。」），具名模型经辅助模型页行/预设行给具体用途选用。②默认服务商卡地址/密钥只看不改——ModelSettingsView 默认服务商卡内两行 infoRow：「接口地址：在服务器上配置，App 里只看不改」「密钥：在服务器上保管」。
- **遗留口径**：§119.4 所记「§120 扩版校验器复跑」随 §120 合并单处置（本包 validate 以现行校验器通过）；辅助写回热生效实测仍并入收官窗口重启；真机待验见 §119.5。

## §128（图标） 文件图标接入包（C8 定版落地，2026-11-11，预制分支 feat/file-icons，基线 main 18c6b39；合并时主线定号 0.50.2／124）

### 128.1 定版口径（用户 14:32→14:38→14:41→14:46 四步拍板）

- C8 定版：查同行做法、用真实图标；调研定案（file-icons-benchmark-20261111.md）——Adobe／微软官方品牌图标第三方明文禁用（Adobe 许可仅限网站、微软明文不得用于软件应用程序），同行「真实感」全靠自绘成套（页形＋逐格式身份带），回落共识是中性页形＋扩展名标签、无人用彩色字母块；OneDay 旧表「品牌色块＋白单字 W/P/X」恰是与微软视觉识别最接近、风险最高且最显廉价的形态。
- 风格定版：学 Muse 内部 3D 黏土风（949 枚现行代的语言；文件家族构成对表其 legacy 76 枚中的文件家族：通用文档＋7 格式变体＋文件夹开合＋图片／视频／音乐／归档），资产自制原创、不复制 Muse 资产本体。
- 承载定版（路线 A）：生成管线交不出透明底（试点实测 alpha 不存在、白底烘焙均值 254.8）——15 枚全以白色圆角砖统一承载，深色模式保持亮砖（用户点选 A，总览拼图浅／深两栏已过目点头）。

### 128.2 资产与映射（file-icons-assets/README 为准）

- 资产：15 枚 fileicon-<slug>.png（256×256 白底）逐枚 imageset 进 App/Resources/Assets.xcassets（fileicon-<slug>.imageset，无深色变体——路线 A 恒亮砖；Project.swift 的 App/Resources/** glob 自动收编，无工程文件改动）。
- Core：DeliverableIconStyle 改 slug 查表单源——struct 只余 slug／assetName／fallbackSlug／fallbackAssetName／allSlugs（15 枚），style(forFileName:isDirectory:isExpanded:) 出 slug。分组沿 0.22.0 旧表逐项对齐，增补四处：①code 组新增（源码类 34 个扩展名＋html/htm 自旧 safari 符号改归，代旧「落 default」）②app 组新增（ipa/apk/app/dmg/pkg/exe/msi 可安装件）③archive 补 rar ④document 文档类通用回落（odt/ods/odp、docm/xlsm/xlsb/pptm、pages/numbers/key、epub、log——text/office 类未命中专属组者）；folder-open 经 isExpanded 入参落表（现行宿主无内联展开态、恒 false，表与参数先行）；其余一切落 unknown。§125 FileItemCategory／FileOpenRoute 口径未动（sheet 仍由 xls/xlsx/csv 扩展名直达，与 spreadsheet 路由同果）。

### 128.3 呈现（路线 A 落法）

- FileIconBox v3：FileIconImageView(assetName:) 取图（UIImage(named:)）填盒，.background(Color.white)＋clipShape(RoundedRectangle) 成砖——圆角沿 §125 同一推导（边长×0.25、36→9／40→10／56→14），尺寸参数 36／40／56 沿用；图标 PNG 本体白底、盒面不再另涂身份底色（防双层砖）；contents 恒 1x 同图，深色模式不变暗、不露白方角（clipShape 裁角）。
- FileTypeFace（§4.3 回落面）：同源换图——白 Rectangle 面＋FileIconImageView aspectRatio .fit 居中，FileIconBox 放大版口径不变。
- 失败回落：FileIconImageView 资源缺失→unknown 枚（DeliverableIconStyle.fallbackAssetName），双缺失（理论不可达）落白砖 Color.white；不许空白、不许回退字形。
- 退役清单：DeliverableIconStyle.Glyph／backgroundHex、FileIconBox 与 FileTypeFace 两处字形渲染、Color(hexRGB:) 扩展（全仓仅此二处消费）一并删除；grep 复核 backgroundHex／hexRGB／.letter(／safari.fill 在 Sources＋Tests 代码零残留（仅测试文件墓碑注释提及）。FrameworkIcon.fileGlyphSize＝17 数值与 VisualDirectionGateTests 钉测不动，注释改注「§128 退役后无消费面、待令牌卫生轮处置」。

### 128.4 单测与校验

- DeliverableIconStyleTests 整表重写 4→9 法：办公三组／文档组／code 组（html 改归＋源码样本）／archive（含 rar 与 .tar.gz）／影音三组／app 组／document 回落组／目录双态＋unknown 回落／assetName 与家族完整性（allSlugs 15 枚唯一＋样本产出不越表）。
- 分支 CI：run 42975217028 success（build-native success，head 472eabb）；单测 Executed 1322、0 failures（基线 18c6b39 的 1317＋5，只增不减）。
- 三语文案零新增（纯图替换），validate_i18n 免跑。

### 128.5 守界与真机待验

- 守界：未碰聊天文件牌链与出牌口径（§116/§121）、FileOpenRoute 路由表（§125）、缩略图取图与缓存（FileThumbnailStore 本体仅 FileTypeFace 一面换图）；版本号未改。
- 真机待验（合并后随版）：三面（待发筹码 36／聊天文件卡 40／打开页文件头 56／文件页行与网格类型面）图标均为新图且圆角砖干净；深色模式亮砖观感与总览拼图一致；.html 与 .py 落 code 枚、.ipa 落 app 枚；无扩展名与 .ex5 落 unknown 灰页问号枚、不空白。

### 128.6 合并与验包记账（2026-11-11，主线合并单）

- **交付定版**：0.50.2／124。分支 feat/file-icons（顶端 edb4b8e，基线 18c6b39）分支 CI run 42975217028 success（单测口径 1322）；合并提交 d8e9a8b（冲突一处：DESIGN-V4.md 尾部顺序拼接——§119 节与本节全保留、§119 在前本节随后；FilesView.swift 自动合并，main 侧 §120 文案改动与分支 FileTypeFace／FileIconImageView 换图 grep 双在位）；定版提交 805978d（版本五处＝Project.swift 四处 0.50.2/124＋SettingsView 页脚「OneDay v0.50.2」，grep 验无 0.50.1 残留）。
- **节号改注（消歧）**：本节预制时自题「§128 文件图标接入包」，与审批锚点规格 §128（approval-anchor-spec-20261111.md／ANCHOR-128）同号。合并记账时改注为「§128（图标） 文件图标接入包」（标题括注＋节首括注同步改为「合并时主线定号 0.50.2／124」），小节号 128.1–128.6 不变；锚点线仍称 §128，两线自此以「（图标）」括注区分，后续引用图标包一律写 §128（图标）。
- **合并后 CI**：run 42982512903 success（jobs API 逐项终判：build-native success、head 805978d）；单测 Executed 1341、0 failures（main 0.50.1 基线 1336＋DeliverableIconStyleTests 整表重写 +5，只增不减；分支口径 1322＝其旧基线 1317＋5，差额 19 为分叉后 main 侧 §119 增量）。
- **独立验包**：IPA 9,934,942 字节、md5 `23980525e502e82b90cdfb79e71a558b`、Info.plist 实读 0.50.2／124／bundle id site.didichou.oneday；Assets.car 内 fileicon-* 15 枚名齐（app/archive/audio/code/document/folder/folder-open/image/pdf/sheet/slides/text/unknown/video/word）；DeliverableIconStyle 表驱动单源在位、backgroundHex／hexRGB 代码零残留（仅测试墓碑注释）；交付件 `~/workspace/your_files/oneday-v0.50.2/OneDay-0.50.2.ipa`（落盘 md5 与 CI 产物一致）。
- **真机待验**：见 §128.5（待发筹码／聊天文件卡／打开页文件头／文件页行与网格四面新图＋深色亮砖＋code/app/unknown 落枚）。
## §129 引用文件牌 404 修复包（2026-11-11，预制分支 feat/file-ref-404，基线 main 18c6b39；诊断唯一依据 file-ref-404-diagnosis-20261111.md，本包只做其 App 侧修法 4.1）

用户报障（2026-11-11 14:49）：旁聊里点文件牌「通讯录-总人数」落 404 失败页。诊断定因：下载链没坏、坏在成牌没门槛——助手正文里任何长得像路径的字符串（拟议未落盘 1、探测器截断假路径 3、设备路径 1，生产抽检助手侧 13 张牌 5 张必死、约 38%）都被正则做成指向服务端文件的卡。本包按诊断 4.1 五条逐条落地 App 侧；服务端治本（4.2 交付登记制、SOUL 引用纪律补条）不在本包，登记待后续拍板。

### 129.1 成牌口收紧（Core FileRefDetector 分层）

- **单独成行才成牌**：新增成牌口 `detectStandaloneAnchored`——整行修剪后恰好是一条路径（可带 #L 锚点）才够格；允许剥一层行首标记（-、*、•、>）与包裹（反引号、**粗体**）；一行两条路径、路径后带说明字、句中提及（拟议/举例）一律不成牌。ChatView 助手侧改走本口，原始扫描口 detect/detectAnchored 保留不动（其余消费方与既有钉测口径不变）。
- **截断 bug 终修（主因 B）**：匹配量词懒惰 +? 改贪婪 +（先吞到终止符、再回认最长合法结尾），尾界断言加「-＋字母数字」一档。生产坏样本 /opt/data/kimi-k3.1-pro-权重核实与补丁.md、kimi-k3.1-pro-patch.txt 修后整条命中、不再截成假路径 /opt/data/kimi-k3.1 并牌。
- **域名片段护栏扩围（主因 B 之二）**：前置跳过条件由只排冒号扩为冒号、点、ASCII 字母/数字——huggingface.co/moonshotai/Kimi-K3.1-Pro 这类域名/IP 尾巴不成路径；只认 ASCII，防中文正文汉字紧贴路径被 isLetter 误伤。
- **下载根收紧（主因 C）**：`downloadRoot`＝/opt/data（与服务端 files.py locked_root 同口径），`isInDownloadRoot` 严判「根＋/」前缀（防 /opt/database 前缀陷阱）且拒 .. 穿越段；成牌口对根外路径（设备 /private/var/… 一类）直接否决。

### 129.2 存在性校验（App 层渲染门）

- **通道**：复用既有文件列表通道——FileMetadataStore.verifyExistence 走 performAdmin 的父目录列表回读（与 §125 元数据回填同源同趟：列表吸收时兄弟文件的 size/mtime 与 exists 一并入账，不另发请求）。
- **判定口径**：列表成功且有此文件＝exists（出牌）；列表成功但没它（含它只是目录条目）＝missing（降纯文本）；列表没查成（网络/登录态等一切错误）＝**unverified**——同样先按纯文本呈现、不阻塞渲染，但账上不记 missing、下次出现可重查，**绝不把网络故障误判为不存在**（简报口径钉死）。校验中（账未落）同按纯文本落位，查实后原地升级成牌。
- **缓存口径**：进程内按路径记账、不落盘；exists/missing 为终局缓存（本进程内不重查），unverified 非终局。呈现载体＝RichContentViews.AssistantFileChip（只裹助手侧探测牌；用户侧 @file: 登记制牌不走本门、健康口径不动）。历史消息同享判定——存量坏牌不改数据、渲染层自动降级（诊断 4.3.8）。
- 分层钉死：单独成行且在根内的拟议路径在 Core 层仍是候选，它死在存在性校验、不由 Core 越权判存亡（钉测 testStandaloneRootPathIsCandidateForExistenceGate）。

### 129.3 失败页回路（§125 FileOpenView 失败态）

- **404 加「让智能体重新发」**：Core 新增 FileResendPrefill（与 §123 FeedDiscussPrefill 同制：只拼装不代发）——草稿三行：打不开＋文件名、原路径、请重新保存并确认存在后把正确路径单独写一行发回（与成牌口呼应、重发回来天然够格成牌）。落点两路：聊天来源由 ChatView 注入闭包，预填直接落当前线程输入舱＋聚焦；文件页/资料库来源无注入时照 §123 讨论同制新建对话＋setDraft＋切聊天格。
- **404 收死按钮**：FileOpenView 失败动作集在策略表打底上对 notFound 单档移除「下载到本地」（文件确证不在、再下载必再 404）；其余失败档策略表原样。范围界：DocumentReaderView/SpreadsheetReaderView 的失败态本包未动（同诊断条目下次顺手对账）。

### 129.4 三语与单测

- 三语新增 4 键（「让智能体重新发」＋预填三行），Localizable 2489→2493 键，validate_i18n.py 与 --check-code 均通过（2506 键含 InfoPlist 13）。
- 新增 FileRefCardGateTests 12 测：截断整条命中、域名片段、版本串护栏、单独成行成牌（含四种包裹）、锚点保留、行内拟议不成牌（附扫描口对照）、拥挤行、去重/排除、设备路径根外拒、下载根判据、拟议单独成行候选分层、预填内容各 1。单测只增不减（基线 1317＋12）。

### 129.5 守界

- 未动用户侧登记制成牌链（ChatView remoteFilePaths 段）、未动 §124 回底钮承载、未动 FileActionPolicy 策略表本体（404 适配只在 FileOpenView 呈现层）、未动伴生与 Hermes 本体；版本号未改（合并时主线定号）。

### 129.6 真机待验

- 旁聊旧消息 1268（通讯录点子）：「通讯录-总人数」不再成牌、以纯文本显示；同会话真交付「通讯录人数口径.md」单独成行且实存，正常成牌点开。
- Kimi 会话旧消息：两份真文件各出一张牌、点开正常，不再是截断的假牌。
- GestaltX 会话旧消息：设备路径不成牌。
- 断网/飞行模式下打开含文件牌的旧会话：牌降纯文本但不出现「文件已不在」类结论，恢复网络后重进会话牌回来。
- 任一 404 失败页：无「下载到本地」、有「让智能体重新发」，点后回对话且输入舱已预填三行草稿。

### 129.7 预制验收记账（2026-11-11）

- 分支 feat/file-ref-404：代码提交 171efe6、记账提交 54ae413，基线 main 18c6b39；分支 CI run 42976295338（head 54ae413）completed success、build-native 单 job 全绿，单测 Executed 1329（基线 1317＋新增 12，只增不减）、0 failures。validate_i18n.py 与 --check-code 本地实跑通过（2506 键）。未合并、版本号未改，待主线按序合并定版。

### 129.8 合并与验包记账（2026-11-11，主线合并单）

- **交付定版**：0.50.3／125。分支 feat/file-ref-404（顶端 5b240cf，基线 18c6b39）分支 CI run 42976295338 success（分支单测口径 1329）；合并提交 2bb6e1d（冲突两处：Localizable.xcstrings 按 key 三方并集——分支纯增 4 键、零删除零改值，main 2603＋4＝2607 键，validate_i18n 通过 2620 键含 InfoPlist 13；DESIGN-V4.md 顺序拼接，§129 节顺接于 §128（图标）之后全保留。ChatView/RichContentViews 自动合并，接线 grep 复核 detectStandaloneAnchored／verifyExistence／AssistantFileChip／FileResendPrefill 均在位）；定版提交 7265879（版本五处＝Project.swift 四处 0.50.3/125＋SettingsView 页脚「OneDay v0.50.3」，grep 验无 0.50.2 残留）。
- **合并后 CI**：run 42983985572，jobs API 逐项终判 build-native success；单测 Executed 1353、0 failures（合并前 main 口径 1341＋§129 新增 12，只增不减；分支口径 1329＝其旧基线 1317＋12，差额为分叉后 main 侧增量）。
- **独立验包**：IPA 9,951,874 字节、md5 `f566ed0d5ca916f2325a7d943f9b8dd9`、Info.plist 实读 0.50.3／125／bundle id site.didichou.oneday；交付件 `~/workspace/your_files/oneday-v0.50.3/OneDay-0.50.3.ipa`（落盘 md5 与取件一致）。
- **遗留口径**：真机待验见 §129.6 五条；诊断 4.2 服务端治本（交付登记制）仍登记待拍板，不在本包。
## §130 已发图固定高度卡（2026-11-11，用户 15:09 附 OneDay 与 Muse 双图点题；预制分支 feat/image-card-fixed，基线 main 18c6b39；§129 在飞文件牌包同动聊天呈现层，合并串行、基线先到先得，节号顺延取 §130）

- **点题实证**：OneDay 里用户发的竖长截图按旧口径缩成 110×240 的细长条、每张图高度随原图比例变；Muse 同一张图是统一卡片——高度固定、图完整装进卡内。用户原话「含有发送的图片还是没有固定高度吗？我记得昨天不是说改了吗？」——旧改（0.36.19 §84.5 双封盒）只封了顶、没定高，本包正之。
- **口径换代（Core ChatImageSizing 整组重写）**：fit-in-box（宽 220／高 240 双封、呈现尺寸随图变）作废。新口径——卡高恒定 190pt；卡宽按图比例算（卡高 × 宽高比）、封顶 260pt、下限 96pt；图在卡内等比完整显示（fittedSize 给帧、scaledToFit 语义）不裁切，图窄于卡时两侧露 bubbleFill 底（即 Muse 图中形态）；只缩不放大保留——原图小于卡内可容纳尺寸时按原尺寸显示、外层卡高仍恒定、图居中。非正尺寸防御：卡回占位方卡、图帧回 .zero。
- **三处消费同源替换**：ChatView 用户本地图（气泡内）与 RichContentViews 的 ServerRemoteImage（用户历史侧＋助手侧两调用点共用一处）统一改固定卡承载（radiusCard 圆角＋bubbleFill 底＋clip 同形）；两调用点原外挂的 spacingM 裁形删除（卡自带形状、免双重裁角）。全屏查看器不走本口径（看原图是其职责，照旧）。
- **占位与失败态同卡高**：ServerRemoteImage 加载占位由旧 220×150 改占位卡口径（190 高、宽取 cardPlaceholderWidth 190——占位时尚不知图比例），消除占位 → 实际高度的跳变；失败态同占位卡尺寸承载（图标＋「图片加载失败」居中），不再随文案宽高变。
- **单测**：ChatImageSizingTests 按新口径整组重写并在文件头说明作废缘由——竖长图钳下限宽／横长图钳封顶宽／方图满卡／任意比例卡高恒定且宽不出界／小图不放大而卡高恒定／极端细长不下限破／占位同高／非正尺寸回落，方法数 6 → 8。分支 CI run 42978076685 success（build-native 逐项 success），单测 Executed 1319、0 failures（基线 1317＋2，只增不减）。三语零新增文案。
- **新旧口径对照**：旧＝每张图一个随比例变的尺寸（竖截图 110×240 细长条、横图 220×101），占位 220×150 与实际高度不一致会跳；新＝所有已发图同高 190 的卡，图完整居中、余量露底色，占位/失败/正式三态同高不跳。
- **真机待验**：竖长截图呈 96×190 卡（图 87.4 宽居中、两侧露底）、横图 260 宽卡、连发多张不同比例图高度齐平、远端图加载全程高度不跳、失败态卡形、点开全屏查看器仍为原图。
- **分支终局**：feat/image-card-fixed（worktree pkg-image-card），代码提交 1ae09d3、本节记账提交随后；版本号未改（合并时主线定版）。
- **合并与验包记账（2026-11-11，主线合并单）**：merge e830cb7（feat/image-card-fixed 1668ddb → main，基线 main 71d450c／0.50.3）。冲突两处：RichContentViews.swift 的 ServerRemoteImage 图渲染核——整段取分支形态（ZStack＋fittedSize＋卡帧＋bubbleFill＋clipShape），解后与分支原版逐字比对一致（合并过程中一度多落一个闭合括号、已当场摘除）；DESIGN 本文件顺序拼接（HEAD 侧 §119/§128/§129 在前、本节随后）。ChatView.swift 自动合并（本地图消费点 cardSize/fittedSize 在位、displaySize 全仓零残留复核过）。定版 92640fc（0.50.4/126，版本五处同改＋grep 验无 0.50.3 残留）。CI run 42985495445：jobs API 逐项终判 build-native 及全部 steps success；单测 Executed **1355、0 failures**（§129 合并后 main 1353＋本包 ChatImageSizingTests 6→8 净 +2，只增不减）。IPA 落 ~/workspace/your_files/oneday-v0.50.4/OneDay-0.50.4.ipa，9,956,363 字节，md5 `d14617ba7b872793d03fab8f0a54d6eb`（落盘与 CI 产物一致），Info.plist 实读 0.50.4／126／site.didichou.oneday。发送空屏修复包在另一 worktree 动 ChatView，本单未碰其线、合并无交叉。
## §131 文件呈现对齐包（2026-11-11，预制分支 feat/file-present-align，基线 main a003384；用户 15:13 拍板「对齐」含翻案卡上「···」钮，唯一依据 file-present-muse-benchmark-20261111.md 对差表 D1/D8 与卡面动作项；节号改注：分支自选 §127 与三页对标专项 §127 撞号，合并时主线改注 §131、原分支自选号作废）

- **D1 大小前移（回读重试化）**：FileChip 与打开页原已在可见时走 backfillFromListing，但首试失败即静默放弃——冷启动/通道未就绪时首试必败、大小要等打开页再试才补，即「首见常缺」的成因。改：FileMetadataStore.backfillFromListing 回 Bool 并按父目录记失败时刻、同目录冷却 5s（Core FileBackfillPolicy 单源：最多 3 试、间隔 1.5s/4s、冷却 5s）；新入口 ensureSize 在卡可见周期内递增重试，FileChip 与 FileOpenContent 的 .task 均改走它。同目录仍只并发一轮、整目录兄弟一并入账，不逐卡单发；三试皆败保持只显类型、不编造（§125 诚实口径不变）。
- **卡上「···」钮翻案落地（§125 取舍作废）**：①聊天 FileChip 卡右加 ⋮ 钮（文件页行同形：ellipsis 旋 90°、命中 44），动作集与文件页行/长按同源同序——FileActionPolicy.menuActions 单源，执行体在卡内（预览走原 onOpen、复制文字/导出 PDF/分享/下载/删除走既有通道，删除带确认＋删后回读核对）；敏感文件菜单空表、不出钮。卡主体点击与长按消息菜单两路保留。②文件页网格卡信息条尾加 ⋮（同源 actionItems；卡本体由 Button 改点按手势＋无障碍按钮语义，行同式，⋮ 才有独立命中）；列表行 ⋮ 系既有（0.36.31 已落）不重复造。③系统文件浏览器行未加 ⋮——其行菜单口径（§七）只有下载/删除且行本体是导航链，本包不动，记为已知差（要补另议）。
- **D8 置顶（pin）**：语义按报告——纯客户端整理（Muse Pin 同义）：新 Core FilePinSet 纯值表＋App FilePinStore 单例落 UserDefaults（files.pinned.v1），不触服务器。落点＝文件页：LibraryOrdering.sorted 加 pinned 入参（置顶整段居前、段内仍走所选排序），grouped 切「置顶」段居一切分组之前；打开页菜单按当前态出置顶/取消置顶。改名跟随迁移、删除清理，均有 Core 钉测。
- **D8 重命名（无服务端通道，如实说明＋组合链）**：Hermes 0.23.0 openapi 实查 /api/files 只有 GET/DELETE＋read/download/upload/mkdir，**无改名/移动端点**——本包不伪造通道，走既有原语组合链：父目录同名冲突预检→取原件字节→超上传同闸 25MB 整链放弃（原件不动）→以新名上传（overwrite=false）→回读校验新条目在且字节一致→才删旧；删旧独失败时新名已确认落好，呈现切新名＋双份并存明示。判定单源 Core FileRenamePlan（名规整与新建文件夹同纪律、扩展名变更先弹确认、目标路径同目录换末段）。改名成功后打开页呈现目标切新目标（currentTarget 种子化改造）、元数据/置顶迁移、AppState.fileLibraryRevision 递增令文件页重聚合。
- **D8 在文件页中打开**：FileActionPolicy.openPageActions 新表（置顶态＋类型专属＋分享/下载＋重命名＋在文件页中打开；仍守阅读面克制、无删除——删除不进本包按派单口径）。回指走 AppState.fileRevealPath＋mainTabSwitchRequest=.files 既有切格通道（置位—消费—清零同式）：DeliverablesView 消费时收栈回根、清搜索，命中聚合集切段＋ScrollViewReader 滚动居中＋高亮（行 selectionFill 底/卡描边，2.5s 自清，文件/影音四面齐）；不在聚合集的文件落系统文件浏览器父目录＋文件名高亮滚动（FilesBrowserView 加 initialPath/highlightName 入参，常规入口行为逐字不变），不假装它在文件页收录里。
- **动作表单源纪律**：FileItemAction 新增 pin/unpin/rename/openInFiles 四项（文案与符号在表内钉死）；menuActions/readingActions 不出这四项，各宿主 switch 落到即静默（DeliverablesView/DocumentReaderView/QuickLookHostView 三处已补分支注释）。新文案 13 键入 Localizable.xcstrings 三语齐，validate_i18n 通过。
- **验收**：单测只增不减（新增 FilePinSetTests 8＋FileRenamePlanTests 6＋FileBackfillPolicyTests 3，FileActionPolicyTests +5、LibraryOrderingTests +4，共 +26）；分支 CI 全绿后回报坐标，不合并（主线串行另派）。
- **真机待验**：聊天卡 ⋮ 钮命中与消息长按菜单并存、网格卡 ⋮ 与整卡点按分工、置顶段在网格/列表两态呈现、改名全链（尤其 overwrite=false 在生产 Hermes 的实际语义与回读校验）、定位高亮四面滚动落点、AX 大字档下卡内 ⋮ 钮与两行文件名的排布。

- **合并与验包记账（2026-11-11，主线合并单）**：交付定版 **0.50.5／127**。merge c042c5c（feat/file-present-align 9565d12 → main，基线 main 11672b4／0.50.4；分支 CI run 42979941824 success、分支单测口径 1362＝其基线 a003384 口径 1336＋26）。冲突三处：①Localizable.xcstrings 按 key 三方并集——base 2627、main 2607、分支 2640（纯增 13）、并集 2620 键、零双改，validate_i18n 通过（2633 键含 InfoPlist 13，三语全覆盖）；②FileMetadataStore.swift 手工合裁——§129 存在性账（verifyExistence/absorb）与 D1 回读重试双在位：backfillFromListing 取分支 Bool＋冷却形态、成功路走 HEAD 的 absorb 保住兄弟存在性入账，两侧注释与属性（verifyInFlight/listingFailedAt）双留；③DESIGN 本文件顺序拼接（HEAD 侧 §119.6/§128/§129/§130 在前、本节随后）。**节号改注**：本节标题 §127→§131（分支自选 §127 与三页对标专项 §127 撞号、自选号作废），分支代码注释内的 §127 引用同步改注 §131（涉 17 文件，逐一核过 main 侧同文件 §127 零命中、均为本包引入）。定版 2b34282（版本五处＝Project.swift 四处 0.50.5/127＋SettingsView 页脚「OneDay v0.50.5」，grep 验无 0.50.4 残留）。首轮 CI run 42987273029 failure——FileOpenContent 的自定义 init（§131 currentTarget 种子化）顶掉成员wise init，§129 的 onRequestResend 呼叫点报 extra argument；修复 4291691（init 补 onRequestResend 形参并赋值）后 run 42987824342，jobs API 逐项终判 build-native **success**。单测 Executed **1381、0 failures**（0.50.4 合并后 main 1355＋本包 +26，只增不减；分支口径差额为分叉后 main 侧增量）。IPA 落 ~/workspace/your_files/oneday-v0.50.5/OneDay-0.50.5.ipa，10,036,817 字节，md5 `39a6105e1c670f33c678b72a55049e39`（落盘与 CI 产物一致），Info.plist 实读 0.50.5／127／site.didichou.oneday。真机待验沿本节末条清单。
## §135 发送空屏修复包（2026-11-11，预制分支 feat/send-blank-fix，基线 main 805978d／0.50.2；节号改注：分支自选 §132 与具名默认 B 分支 feat/provider-default 的自选 §132 撞号，且 §133（在飞 MEDIA 兼容包／cx-misc 预占）、§134（在飞 cx-model-storage 预占）均已被占，合并时主线改注 §135、原自选号作废；分支代码注释内的 §132 引用同步改注 §135）

### 135.1 病灶与定案（诊断 send-blank-diagnosis-20261111.md，摘要）

- 用户 2026-11-11 15:55 真机报障：发送信息时空屏数秒。诊断定案：发送瞬间同一 ScrollView 上叠着的**五套贴底/锚定机制**被一次发送连发触发，每次命令式 `scrollTo("bottom")` 都强迫 LazyVStack 对长线程尾部做「估算总高→实例化重量级气泡→再估算」的布局 churn；同时 ChatView 每次状态写入都对**全线程**重算渲染计划（全量排序＋每条工具卡 JSON 现解码、无缓存）。两者叠加、主线程被占满，视口数秒无已实现视图可画——嫌疑一（高，主嫌疑）＝LazyVStack 视口未实现空白，缺帧级探针升实锤，故本包 D 案打点随行。
- 外部实证（诊断 §二，冲突以外部实证为准）：①Tactic Remote《Hunting a UI Freeze》（2026-07 受控复现）——ScrollView＋LazyVStack 内容超一屏时任何 scrollTo 都可引发纯布局 livelock；②Apple Developer Forums thread/741406——LazyVStack＋defaultScrollAnchor＋命令式 scrollTo 并存出现重入空白；③Fatbobman/tbd 长列表调研——scrollTargetLayout＋scrollPosition 在大数据量 LazyVStack 上是公认性能 footgun。**本包裁定：无外部记录支持「保留五套机制再逐个调参」，只做减法。**
- 修法定案＝A 减法收口＋B 关键帧减负（本包只取渲染计划缓存一项）＋D 打点随行；C 换容器（List 化）留终局、A/B 无效时再议。

### 135.2 A 案：机制收口前后对照（五套→三件）

| # | 收口前（基线落点） | 收口后 |
|---|---|---|
| 1 | ScrollViewReader＋命令式 scrollTo，六路触发直呼；scrollToBottom 内置一层 120ms 复贴，sendPinToken 路自带第二层 120ms 复贴——一次发送连发 3–5 次强制跳底 | **单一所有者** `scrollToBottom`：六路触发＋回底钮全经此一口；所有者内部经 Core `BottomStickCoordinator` 裁决（50ms 同帧合并窗、同帧重复请求.coalesced 不再即时贴）、**复贴全局只挂一笔**（新贴底顶替旧复贴、代号制至多消费一次、切线程 invalidate 作废）；全仓唯一的 `scrollTo("bottom")` 只在原语 performScrollToBottom 内（双形态同处） |
| 2 | `.defaultScrollAnchor(.bottom)` 声明式锚与命令式并存，:1660 注释自称「分工不冲突」 | **删除**，注释口径作废（与 Forums thread/741406 实证相左）；首帧落位由.task 定版链（0.22.0：出现一拍后无动画贴底）单点承担，退役注留原文处 |
| 3 | `.scrollTargetLayout()`＋onScrollTargetVisibilityChange 每次滚动回写三枚 @State（topVisibleEntryID／lastVisibleEntryIDs／lastEntryVisible）并触发两次全量 map 喂未读 | 可见集**降权只剩滚动锚存取**：只回写 topVisibleEntryID 且加等值守卫；`lastVisibleEntryIDs`、`lastEntryVisible`、`refreshLastEntryVisible()` 删除；未读喂入只保留条目数 onChange 一路；scrollTargetLayout 本体保留（锚存取 id 回报靠它） |
| 4 | 两路 onScrollGeometryChange（距底／视口高）几何回调逐帧无条件回写 @State，形成「状态改布局→布局再触发几何」反馈环结构 | 两路本体保留（定案所需：前者喂迟滞判定＋所有者复贴复核，后者喂内容栈撑满 minHeight），**回写加等值守卫**：值未变不写 |
| 5 | BottomProximity 迟滞近底判定（<96 进／≥176 出） | 保留不变（几何单源的判定本体） |
| 6 | 回底钮显隐＝几何＋末条事实信号双信号（0.36.5 审计 bug 2 的纠偏：几何估算驻留迟滞带时靠事实信号压钮） | **改判几何单源**：`BottomFollowPolicy.showsScrollToBottomButton(isNearBottom:)` 单参＝!isNearBottom；isAtBottomForUnread 与钮显隐同源单参。明知风险已裁定接受：bug 2 的迟滞带驻留（末条肉眼可见钮晚消失）可能复现，兜底靠尾行量实后几何收敛＋所有者复贴校正，列真机待验重点观察 |

- **红线守界**：§124 回底钮承载结构（bottomBar VStack 本体、钮行落位、命中域、动画键）**零代码/布局改动**，仅三处注释措辞随事实信号退役更新；键盘锚底 300ms 是触发延迟（等键盘动画）非复贴，保留、落点改走所有者；线程恢复的滚动锚 scrollTo（entryID）非贴底、不动。

### 135.3 B 案：渲染计划缓存

- Core 新 `ChatRenderPlanKey`：条目投影＝id＋toolCardData 有无＋createdAt（make 内按 id 排序入哈希，入参顺序不影响键），键含 threadID／dayStamp（当日零点）。**失效条件（钉测逐项把守）**：条目增删、工具卡数据有无翻转、createdAt 变化（同 id 重写）、线程切换、跨日——任一变即键变、计划重算；无关状态写入（notice/键盘/几何守卫后）键不变、零重算。
- App 侧 `renderPlan(for:)` 单口：按键命中直接复用缓存的 (dividers, items)，未命中才取一次 sortedEntries 并同算 timelineDividers＋entryRenderItems 存入；messageList 由每遍 body 至少 3 次全量排序＋两遍走查收为至多一遍（键变时）。
- `ChatEntry.toolCard` 解码 memo：@Transient 缓存对（值＋源 Data），源相等直返缓存（含解码失败 nil 的负缓存防每帧重试），**失效条件＝toolCardData 变更**。旧形态一遍 body 每条工具条目解码 2–3 次的开销消除。

### 135.4 D 案：发送帧打点（ChatDiagTrace 三落点，诊断面可回收）

- 起点：send() 条目落盘前置 `sendFrameStartedAt`；三段读数——①落盘→链接（sendPinToken 递增前、仅链接成功轮）②首帧复核（所有者复贴检查点：复核距底 pt＋是否复贴＋距发送 ms，每轮只记一笔）③发送→落定（applySettledTurn 入口先记先清，失败分支同样消费；恢复轮无起点不记）。切线程清标记，防跨线程污染。

### 135.5 单测与校验

- 新增：BottomStickTests 7 法（首请求 perform／窗内合并且代号不涨／窗外 perform 且旧复贴被顶替／复贴至多消费一次／合并后挂账仍可消费／复贴已消费后窗内请求不合并／invalidate 作废挂账与合并窗）；ChatRenderPlanKeyTests 8 法（同输入同键／入参乱序同键／增删键变／工具卡翻转键变／createdAt 键变／线程键变／跨日键变／空集稳定）。
- 改写：BottomFollowTests 两法按新口径（testScrollButtonHiddenWhenNearBottom／testScrollButtonShownWhenOffBottom），旧双信号断言随口径作废、注释记明；方法数不减。
- 分支 CI：run 42985878037 success（build-native success，jobs API 逐项终判，head 69689a4）；单测 Executed 1356、0 failures（0.50.2 合并后基线 1341＋本包新增 15，只增不减）。首轮 run 42985254439 编译失败一处：落定打点守卫把 RunLedgerEntry.threadID（String）与 thread.id（UUID）直比——按仓内 uuidString 口径一行修复后重跑全绿，记账在此、不隐瞒。
- 三语文案零新增（打点串为诊断留痕、非用户面文案，与 ChatDiagTrace 既有口径一致），validate_i18n 免跑。

### 135.6 守界与真机待验

- 守界：未动发送数据正确性链（落盘、runLedger 互斥、种子/链接计划、模型重锁、落定整段替换、落定对账全保留原位）；未动 BottomProximity 阈值与 BottomSettle 24pt 门；C 案（换容器）未动。
- 真机待验（合并后随版）：①长线程发送不再空屏（重点，配合诊断面「发送打点」三段读数对读：首帧复核距底与距发送 ms）②回底钮迟滞带晚消失观察（几何单源改判的已知风险：滚回底部后钮是否随尾行量实及时消失）③离底未读角标（手动滚回底部后角标由下一次 ingest 以在底事实清零、离底计数不丢）④切线程滚动锚恢复与首帧落位（defaultScrollAnchor 退役后.task 链单点承担）⑤键盘升降锚底与流式跟随不回归。

### 135.7 合并与验包记账（2026-11-11，主线合并单）

- **交付定版**：0.50.6／128。merge b33cf33（feat/send-blank-fix 3b14c17 → main，基线 805978d／0.50.2；分支 CI run 42985878037 success、分支单测口径 1356＝其基线 1341＋15）。冲突一处：DESIGN-V4.md 尾部——HEAD 侧 §129/§130/§131 三节全保留在前、本节顺接其后；ChatView.swift 自动合并（接线复核：BottomStickCoordinator／renderPlan 单口与 §130 的 cardSize／fittedSize 双在位；`scrollTo("bottom")` 只剩 performScrollToBottom 原语双形态两处、defaultScrollAnchor 只余退役注释两行）。定版 949ee5a（版本五处＝Project.swift 四处 0.50.6/128＋SettingsView 页脚「OneDay v0.50.6」，grep 验无 0.50.5 残留）。
- **节号改注（消歧）**：本节预制时自选 §132，与具名默认 B 分支 feat/provider-default 的自选 §132 撞号；§133 已被在飞 MEDIA 兼容包（feat/media-marker）与 cx-misc 预占、§134 已被 cx-model-storage 预占，故合并时主线顺延改注 **§135**、原自选号作废（节头已写明）；分支代码注释内的 §132 引用同步改注 §135（8 文件 37 处：ChatView 24／BottomFollow 5／BottomFollowTests 3／ChatStore、BottomStick、ChatRenderPlan、BottomStickTests、ChatRenderPlanKeyTests 各 1，改后代码内 §132 零残留）。§135.1–§135.6 小节号随迁，本节为 135.7。
- **合并后 CI**：run 42989208941，jobs API 逐项终判 build-native 及全部 steps success（head 949ee5a）；单测 Executed **1396、0 failures**（合并前 main 口径 1381＋本包新增 15，只增不减，与预期分毫不差）。三语文案零新增，validate_i18n 本地实跑通过（2633 键含 InfoPlist 13，三语全覆盖，与 0.50.5 同口径）。
- **独立验包**：IPA 落 ~/workspace/your_files/oneday-v0.50.6/OneDay-0.50.6.ipa，10,043,072 字节，md5 `07ec4b05d3f583ed56695a4c7f54dc50`（落盘与 CI 产物一致），Info.plist 实读 0.50.6／128／bundle id site.didichou.oneday。
- **真机待验**：见 §135.6 五条（长线程发送不再空屏＋诊断面三段读数对读为重点；回底钮迟滞带晚消失观察；离底未读角标；切线程锚恢复与首帧落位；键盘锚底与流式跟随不回归）。

## §136 助手侧 MEDIA: 图片标记渲染包（2026-11-11，用户 16:18 真机报障；预制分支 feat/media-marker，基线 main 92640fc／0.50.4；节号改注：分支自选 §133 与 cx-misc 分支的 §133 预占撞号，且 §134 已被 cx-model-storage 预占、§135 已由发送空屏修复包合并占用，合并时主线顺延改注 §136、原自选号作废，分支代码注释内的 §133 引用同步改注 §136；§135 节头与正文注记中的「§133（在飞 MEDIA 兼容包）」即本包）

- **报障实证**：用户让 OneDay 内智能体拍云电脑截图，回复正文里只有一行 `MEDIA:/opt/data/cache/images/img_6c34d74cde74.webp` 原文，App 当纯文字显示、图没出来（截图存档于会话）。根子：`MEDIA:` 是 Hermes 的媒体投递协议——智能体把产出图片以独立一行写进回复、渠道层转附件下发；OneDay 走的 API 通道无人转，标记漏进气泡。App 侧呈现层收口（本包），不在服务端拦。
- **Core 拆分（新文件 MediaMarker.swift）**：纯函数 `MediaMarker.split(in:)` →（摘除标记行后的正文，图片路径出现序去重）。摘行判据逐项对齐既有口径、不另立一套：独占一行（允许行首尾空白）＋扩展名认 FileRefDetector.imageExtensions（webp/png/jpg/jpeg/gif/heic）＋路径过 FileRefDetector.isInDownloadRoot（/opt/data）。摘行后空行收拾（三连换行压一个空行、首尾修剪），段落结构不因摘行变样；整条只剩标记时正文回空串。
- **保留判据（原文不动）**：非图片扩展名的 MEDIA: 行（文件投递语义，归文件牌链）；根外路径（设备路径等，天然取不回来，与 §129 同判）；行内嵌着写的 MEDIA:；代码围栏内的行（字面量）；相对路径/无扩展名/路径后带说明文字等整行不恰是标记的形态。MediaMarkerTests 14 测逐项钉死（报障同形、段首/段中/段尾、多张连发与散布去重、空行收拾、坏路径三档、围栏、图文件混合、无标记原样、扩展名大小写）。
- **App 呈现（与 §116/§130 同源同形态）**：ChatView 助手分支渲染前先拆分——正文只喂摘除后的文本；标记图片走新视图 AssistantMediaImage（RichContentViews，紧挨 AssistantFileChip）：存在性确证后以 ServerRemoteImage 出图（§130 定高卡、点开全屏查看器、无障碍与 remoteImagePaths 行同口径），位置同既有图片行（正文上方、remoteImagePaths 之后）。正文摘空时不渲染空气泡（无标记旧消息行为逐字不变）。
- **存在性三分（§129 同源）**：出图与否由 FileMetadataStore.verifyExistence 判——exists 才出图；missing 与 unverified 一律不出图；因标记行已在拆分时摘除，查无/查不成时整行就此不显示，**绝不退回露 `MEDIA:` 原文**；unverified 非终局账，下次渲染重查、查实原地出图。与 §129 文件牌的差别仅在降级形态：牌降为纯文本一行（路径本身对用户有信息量），标记行整行消失（标记原文对用户零信息量、只剩噪声）。
- **连带收口**：文件牌探测 detectStandaloneAnchored 的 excluding 增补 mediaSplit.imagePaths——MEDIA 图片路径不再重复成一张文件牌。
- **边界（不在本包）**：落盘数据不改（entry.content 原文保留标记，呈现层拆分，与 §129 渲染层降级同层）；复制/引用仍取原文；流式生成中途不做拆分，落定入 entry 后生效（与 §129 文件牌同层级）；服务端把 MEDIA: 转正式附件（与 §129 登记制终局同题）仍登记待议，不在本包。
- **真机待验**：让智能体再拍一张云电脑截图——回复里直接出图（定高卡）、正文无 MEDIA: 原文残留；连发两三张图逐张成卡；引用一条不存在的图片路径——整行不显示、无原文漏出；断网打开含标记的历史消息——先不出图、恢复网络重进后出图。
- **单测与 CI**：分支 CI run 42986530074 success（jobs API 终判 build-native success、steps 零失败），单测 Executed 1369、0 failures（基线 1355＋MediaMarkerTests 新增 14，只增不减）。三语零新增文案（复用「查看大图」既有键）。
- **分支终局**：feat/media-marker（worktree pkg-media-marker），顶端以记账补录提交为准；版本号未改（合并时主线定版）。
- **合并与验包记账（2026-11-11，主线合并单）**：交付定版 **0.50.7／129**。merge 9627359（feat/media-marker 3d30148 → main，基线 main 607ec4f／0.50.6；分支 CI run 42986530074 success、分支单测口径 1369＝其基线 92640fc 口径 1355＋14）。冲突一处：DESIGN-V4.md 尾部——HEAD 侧 §130 合并记账行＋§131＋§135 三节全保留在前、本节顺接其后；ChatView.swift 与 RichContentViews.swift 自动合并（接线复核：MediaMarker.split／AssistantMediaImage／FileRefDetector excluding 增补 mediaSplit.imagePaths 与 §135 的 BottomStickCoordinator／renderPlan 单口双在位，verifyExistence 三分在 RichContentViews 两处呼叫点在位）。**节号改注**：本节标题 §133→§136（分支自选 §133 与 cx-misc 预占撞号、§134 已被 cx-model-storage 预占、§135 已由发送空屏包占用，自选号作废），分支代码注释内的 §133 引用同步改注 §136（4 文件 7 处：ChatView 3／MediaMarker 2／RichContentViews 1／MediaMarkerTests 1，改后代码内 §133 零残留）。xcstrings 本包零改动，三方并集无冲突，validate_i18n 通过（2633 键含 InfoPlist 13，三语全覆盖）。定版 e37de91（版本五处＝Project.swift 四处 0.50.7/129＋SettingsView 页脚「OneDay v0.50.7」，grep 验无 0.50.6 残留）。CI run 42991017262：jobs API 逐项终判 build-native **success**。单测 Executed **1410、0 failures**（0.50.6 合并后 main 1396＋本包 MediaMarkerTests 14，只增不减）。IPA 落 ~/workspace/your_files/oneday-v0.50.7/OneDay-0.50.7.ipa，10,054,999 字节，md5 `408074eb50cc84b5d4c2a111aee9ef6e`（落盘与 CI 产物一致），Info.plist 实读 0.50.7／129／site.didichou.oneday。真机待验沿本节「真机待验」条清单。

## §137 复杂化收口包：服务探测收一＋演示模式冻结（2026-11-11，复杂化全清第 9 项＋第 4 项，用户 16:08 点名全清、审计 complexity-audit-20261111.md；预制分支 feat/cx-probe-demo，基线 main 7265879／0.50.3；分支未自选节号、合并时主线新立 §137，现行已用节号至 §136、无撞号）

- **第 9 项·服务探测收一（单一出处）**：三套探测（连接硬门／本地服务状态／伴生状态与提供商探针）此前各拼一套状态词、Overview 另有「/health 不抛错即算活」的宽松判活。Core 新 `ServiceHealth.swift`：统一词表八档（checking/up/degraded/down/absent/notConfigured/unknown/stale）＋四路派生 `from(local:)`／`from(companion:)`／`from(health:)`／`ProviderConnectionOutcome.serviceHealth`，状态词全经词表出词（新补「降级运行」「上次读到」两键）、钉测防回潮。/health 五处消费收口：AppState 三处连接硬门、ConnectorsView.probeHermes、OverviewBridgeStore.probeChannel 全改经 `ServiceHealth.from(health:) == .up` 派生判定；HermesClient.health 是探针本体（派生输入生产者）不收，DemoMode 命中为种子文案字符串不收。**一处行为变化**：Overview 探活改与连接页同判词——回执 status 非 ok 不再算活、进退避重探（此前算活）。提供商探针失败→呈现结局的三目分流此前三处调用方各写一份，收一为 `ProbeFailure.connectionOutcome`；ProviderProbeClient 本体保留（存前验钥、目的不同于服务探测），只并词表。CompanionStatus 的富呈现（settingsLine 版本＋模块明细行、footerNote）保留，其健康词与词表同档。
- **第 4 项·演示模式冻结（清单外统一空态）**：冻结口径 demo-surface-freeze-20261111.md（连接页／对话主面只读／动态／点子／目标／文件六面）。DemoHermesClient 清单外 **64 个接口的逐个假实现全删**（样本 JSON、静默成功写方法、假计数等；文件 1256→942 行、净删 314 行），统一抛专用空态信号 `HermesError.demoLimitReached`，文案单一出处＝三语键一条「演示模式到此为止，连接你的服务器后可用。」；吞错面专项补口 7 处（SkillHubViews 搜索/预览/安装/卸载、ModelManagementStore 测连接/清单刷新、ProviderEditorView 测连接，只认 demoLimitReached、不改生产文案）。连带穷举收口：`FileOpenFailure.classify` 补 demoLimitReached 归 `.other` 兜底（分支首轮 CI 红点在此，5580b4a 已修后重跑全绿）。冻结六面种子路径逐面走查保留（连接页假探活三步、对话只读浏览＋种子会话补完 run 通道四件、点子 kanban 全组样本、文件种子目录树与 fileData；动态/点子/目标的桥面演示下走既有 notConnected 如实态、非本包职责面）。**如实记账**：全仓 `isDemo` 分叉施工前后同为 36 处、收敛 0 处——它们守的是落盘/钥匙串/网络时机、不是假实现，与本项砍的对象（客户端方法级假实现）不同层；后续再收须逐处单独裁。
- **单测与 CI（分支口径）**：新增 ServiceHealthTests 11 法（词表八档、本地四档映射、伴生七路、/health 两路、提供商三路、同源防回潮）＋DemoLimitTests 2 法（统一文案 zh 源串钉死、信号非瞬断不被自动重试），合计 +13 法。分支 CI run 42986131831 success（jobs 全 step success，首轮 42985894128 构建失败＝HermesError 新增 case 后 FileOpenFailure 穷举未补，5580b4a 修复）。三语新增 3 键、零删键（逐键核对：分支相对其基线 Localizable 仅增「降级运行」「上次读到」「演示模式到此为止，连接你的服务器后可用。」3 键、无删无改值）。
- **真机待验（合并后随版）**：①演示模式走查（-odDemoMode/-odDemoConnect 各开一遍冻结六面：清单内可走通、清单外动作落统一空态文案、无假数据冒充）②Overview 探活新口径（伴生 status 异常时设置版本组进退避重探、不再误报活）③设置版本组、连接器页、提供商编辑页三处状态词同源一致（同一故障同词同档）。
- **合并与验包记账（2026-11-11，主线合并单）**：交付定版 **0.50.8／130**。merge 170a813（feat/cx-probe-demo 5580b4a → main，基线 7265879／0.50.3；分支 CI run 42986131831 success、分支单测口径 +13 法）。**零冲突**：AppState.swift 与 Localizable.xcstrings 自动合并，接线复核双在位——AppState 三处连接硬门改判 `ServiceHealth.from(health:) == .up` 与 §131 的 fileRevealPath 并存；DemoHermesClient 内 demoLimitReached 抛点 65 处、HermesError 定义与 FileOpenFailure 归类在位；ServiceHealth 消费面七文件齐。**节号**：分支未自选节号，主线新立 §137（已用至 §136、无撞号、无代码注释改注）。**删键核对**：分支相对其基线 Localizable 零删键零改值、仅增 3 键（降级运行／上次读到／演示空态文案）；三方并集＝主线 2620＋3＝**2623 键**，validate_i18n 通过（2636 键含 InfoPlist 13，三语全覆盖）。64 个演示假实现的删除均为 DemoHermesClient 客户端方法体、无对应单测随删（删除面由新增 DemoLimitTests 2 法反向钉住），单测只增不减成立。定版 2d6240d（版本五处＝Project.swift 四处 0.50.8/130＋SettingsView 页脚「OneDay v0.50.8」，grep 验无 0.50.7 残留）。CI run 42992703627：jobs API 逐项终判 build-native 及全部 steps **success**（head b895f32）；单测 Executed **1423、0 failures**（0.50.7 合并后 main 1410＋本包新增 13，与预期分毫不差）。IPA 落 ~/workspace/your_files/oneday-v0.50.8/OneDay-0.50.8.ipa，10,044,299 字节，md5 `43cd8731e7950ca5aa2c13f0c7de76fd`（落盘与 CI 产物一致），Info.plist 实读 0.50.8／130／site.didichou.oneday。真机待验沿本节清单三条（演示六面走查、Overview 探活新口径、三面状态词同源）。

## §138 复杂化收口包：文件回填收口＋听写残件退役（2026-11-11，复杂化全清第 6 项＋第 8 项，用户 16:08 点名全清、审计 complexity-audit-20261111.md；预制分支 feat/cx-files-dictation，基线 9565d12／feat/file-present-align 顶端；分支未自选节号、合并时主线新立 §138，现行已用节号至 §137、无撞号）

- **第 6 项·文件大小回填三路收两路＋退避降级单试**：回填原三路（①发送记账②下载回填③父目录列表回读）砍②——下载是用户动作、不兼任元数据源（打开页本来就会走③回读补上）；`FileMetadataStore.recordDownload` 本体删除、三处调用点（FileOpenView.fetchBytes／RichContentViews FileChip.fetchBytes／SpreadsheetReaderView 分享取数）同步摘除，全仓零残留。§131 给③加的退避状态机整套退役：Core `FileBackfillPolicy` 只剩一条口径——单张卡一次可见周期最多回读 1 趟（`maxAttemptsPerAppearance = 1`），旧 `maxAttempts`／`delay(afterFailedAttempt:)`（1.5s/4s）／`failureCooldown`（5s）／`isCoolingDown` 全删；宿主 `ensureSize` 改单趟循环、`backfillFromListing` 去冷却判定与失败留痕（`listingFailedAt` 账本删除）——失败不记账、不退避、不冷却，卡下次露面（新的 .task 周期）再查；同目录并发合一与整目录一并入账保留。**合并合裁口径**：基线较老（§129 合并前），FileMetadataStore 手工合裁——回填力学以本包为准（两路＋单试），§129 存在性账整套保留在位（Existence 三分 exists/missing/unverified、`verifyExistence`、`absorb` 一趟双入账元数据＋存在性），backfillFromListing 改走 absorb 单源（分支的内联记录循环与 absorb 同体，不另立第二份）。
- **第 8 项·听写量尺删除＋locale 合表**：停后落字钟整套退役——Core `DictationSettleLatency`（begin/complete/diagnosticSegment）删除，DictationController 的 settleLatency 记账位与诊断串「落字+…ms」落字段同步摘除（类头注与诊断行注释改注退役出处）。**.fastResults 引擎选项本体保留**（reportingOptions 不动）——只退役量尺，选项去留仍随 0.36.17 真机验收裁项（与预制口径一致）。语言 locale 两表合一：`DictationLanguage.localeIdentifiers` 单表（主选在前、回退在后；粤语 [yue_CN, zh_HK]、普通话 [zh_CN]、英语 [en_US]），旧 `localeIdentifier`／`fallbackLocaleIdentifier` 改为从本表派生（首项／次项），映射只此一处。
- **单测对账（分支口径）**：DictationTests +7 法（locale 候选单表：三语候选、主选＝首项、回退＝次项、回退仅粤语非空、候选内唯一非空）；随功能退役删测 8 法逐项列明——落字钟 5 法（DictationSettlePolicyTests 的 testSettleLatencyMeasuresStopToApplied／CompleteBeforeBeginIsIgnored／FirstCompleteWins／BeginClearsPreviousReading／RoundsAndClamps，被测本体 DictationSettleLatency 已删、无处可钉）＋回读退避 3 法（FileBackfillPolicyTests 的 testDelayProgressionAndExhaustion／testMaxAttemptsCoversDelays／testCooldownWindow，被测 delay/maxAttempts/isCoolingDown 已删），回读新口径另立 2 法钉单试形状（testMaxAttemptsPerAppearanceIsOne／testAppearanceBudgetIsExactlyTheFirstTry）。净账 −5＋7−3＋2＝**+1 法**。
- **xcstrings 核对**：分支相对其基线零改动 Localizable.xcstrings（听写量尺的诊断段是代码内拼串、非本地化键，无键可删）；三方并集＝主线现行 **2623 键**不变，validate_i18n 合并后复跑确认。
- **真机待验（合并后随版）**：①文件卡大小呈现：冷启动首见文件卡大小一趟回读补上或只显类型（不编造）、滑走再滑回能再查②打开文件/表格分享链路无回退（下载回填删除后打开页大小靠回读补）③听写停后落字照常（落字钟退役只是诊断记账摘除、落稿路径不动）、粤语识别回退 zh_HK 照常。
- **合并与验包记账（2026-11-11，主线合并单）**：交付定版 **0.50.9／131**。merge c626de7（feat/cx-files-dictation fb601cd → main，基线 9565d12／feat/file-present-align 顶端；分支 CI 已绿）。**冲突三处全在文件面**：FileBackfillPolicy.swift 与其测试取分支整版（main 侧自基线仅 §127→§131 注释改注、无实质分叉，取版后注释同步改注 §131＋§138）；FileMetadataStore.swift 手工合裁（口径如上节第 6 项条：两路＋单试归本包、§129 三分在位、absorb 单源）；FileOpenView／RichContentViews／SpreadsheetReaderView 自动合并、recordDownload 三调用点随删干净（全仓 grep 零残留）。**接线复核**：verifyExistence／absorb／Existence 三态在位、退役符号（maxAttempts／delay／isCoolingDown／failureCooldown／listingFailedAt／DictationSettleLatency／recordDownload）全仓零残留、.fastResults 选项在位、§135 BottomStickCoordinator／renderPlan、§136 MediaMarker、§137 ServiceHealth 接线未动。**节号**：分支未自选节号，主线新立 §138（已用至 §137、无撞号）；分支注释内的「§127 对齐包」指称按 main 现行口径改注 §131。**xcstrings**：分支零改动、三方并集＝主线 2623 键 Localizable 不变，validate_i18n 通过（2636 键含 InfoPlist 13，三语全覆盖）。定版 b806f89（版本五处＝Project.swift 四处 0.50.9/131＋SettingsView 页脚「OneDay v0.50.9」，grep 验无 0.50.8 残留）。CI run 42994743268：jobs API 逐项终判 build-native 及全部 steps **success**（head eaa2207）；单测 Executed **1424、0 failures**（0.50.8 合并后 main 1423＋本包净增 1，与对账分毫不差）。IPA 落 ~/workspace/your_files/oneday-v0.50.9/OneDay-0.50.9.ipa，10,040,644 字节，md5 `33a8d22a6355e4b921765feb2fe2657a`（落盘与 CI 产物一致），Info.plist 实读 0.50.9／131／site.didichou.oneday。真机待验沿本节清单三条（文件卡大小单趟回读、打开/分享链路无回退、听写落稿与粤语回退照常）。
## §139 复杂化清理·丁包（2026-11-11，预制分支 feat/cx-misc，基线 main 7265879／0.50.3；依据 complexity-audit-20261111.md 第 7、10、13、12 项；节号改注：分支预占 §133 已被现行占用，现行已用至 §138，合并时主线顺延改注 §139、原预占号作废，代码与脚本注释同步改注）

### 139.1 第 7 项 · 阅读器宿主合一

- DocumentBlocksView（§125 已抽出的块渲染共用件）之上再收一层：新增 `FileReaderHost`（与 DocumentBlocksView 同文件）——背景／标题／加载转圈／失败页（文案＋FileActionPolicy.failureActions 动作行）只此一份实现，两阅读器共用。
- DocumentReaderView 只留数据准备（本地取字节→FileTextExtractor 提取→DocumentReading 分块）与自家正文（空文件态、锚点呈现参数、工具栏动作）；SpreadsheetReaderView 只留数据准备（伴生转码→sheet 选段→CSV 分块＋截断注记）与正文。两家原各自一份的 failureView 已删。
- FileOpenFailure 九分保留不动（审计原话：文案资产、不算运行复杂度）。
- 逐类型回归口径（代码走查，合并后真机复验）：md＝DocumentReaderView markdown 分块→DocumentBlocksView（含锚点摘录卡）；xlsx＝SpreadsheetReaderView 转码 CSV→DocumentBlocksView（sheet 切换与 500 行截断注记在正文闭包内，未入宿主）；csv＝DocumentReaderView csv 分块（锚点走摘录卡）＋表格页 csv 块渲染，两路共用同一渲染器。

### 139.2 第 10 项（App 部分）· 台账两 Store 合一

- Core 新增 `StoreLoadState`（loading／unavailable(String?)／failed(String)／ready）＋两口错误映射：`failure(for: HermesError)`（服务端人话直达 failed）、`from(bridgeError:unavailableMessage:recordGoneMessage:)`（钥匙类与未开通归 unavailable、recordGone 归 failed、桥侧人话直传）；未连接统一落态 `.notConnected`。
- `OneDayBridgeError` 自 App 层 OneDayBridgeClient.swift 下沉 Core（OneDayBridgeModels.swift），使映射与错误类型同层；客户端只负责抛出，引用面 12 文件原已全部 import OneDayCore、零新增导入。
- KanbanStore：删自有 LoadState，未开通＝`.unavailable(nil)`（文案在呈现面固定），404 判未开通的专属语义留在 Store 内、只产出共用态。LedgerStore：删自有 LoadState，还没上线＝`.unavailable(说明)`；bridgeMissing 的探测旁证（probeCompanion 把说明说准）是本面专属语义、留在 handleLoadError 内，同样只产出共用态。
- 消费面同步：HubTaskSection、HubLedgerSection、GoalsStore 与 IdeasStore 内对 kanban.loadState 的 switch 改新 case 名；GoalsStore／FeedStore／IdeasStore／MemoriesStore／MonitorsStore 自有 LoadState 不在本包范围（审计第 10 项只点 Kanban＋Ledger 两套），后续如收敛可按本包形态续做。
- 账本本体与伴生采集器不在本包（审计原案：不减账本、只减 App 侧对账面）。

### 139.3 第 13 项 · i18n 三方对账脚本化

- 仓内工具 `Scripts/merge_xcstrings.py`：输入 base/ours/theirs 三个 xcstrings，按「键 × 单元（条目元数据＋每语言）」三方合并，输出合并结果＋冲突点名清单（冲突先取我方、退出码 2、须人工裁）；键级删除先判（删＋未动＝删、删＋改＝整键冲突逐单元点名）。合并后仍跑 validate_i18n.py 把关三语完整性。
- 自测样本 `Scripts/fixtures/xcstrings-merge/`：§119/§120 两次合并的真实三方条目（出处 commit 见样本 README），含 §120 唯一真冲突「默认服务商（经网关）」zh-Hant；历史里没有的「改既有键／删改相撞」用构造样本补齐并注明。`--self-test` 已通过。
- 全量回放（施工时实测）：§119 全量三方跑工具与历史合并结果逐键逐值全等（2627 键、零冲突）；§120 差异恰为 1 处被点名冲突（历史人工取他方）＋9 个键的人工编辑差（旧组合文案合并时一并清理、合并轮补键），非对账错误。

### 139.4 第 12 项 · 新面准入附则（本节即附则本体）

> **新面准入附则**（与 §123.7 新面准入四问同单执行）：新功能默认进既有 Store／Client 分组——先找现有 Store／Client 里语义最近的一家落，没有才许新开。新开 Store、新开 Client、新增 UserDefaults 键（含给既有 Store 加新键），必须在施工单里逐项说明理由（为什么既有分组接不住），与新面准入四问（入口／重复／令牌与公用件／AX 与深色）写在同一张施工单上交审；理由不成立即打回并入既有分组。本附则只立规矩、不追溯存量（现行 23 Store／14 Client／四套 UserDefaults 旁挂状态维持现状，收敛随各自专项包顺手做）。

- ChatView 拆分本包不做：与发送空屏修复包（feat/send-blank）同文件、在飞避让；审计第 12 项的「按 MARK 段先拆落定／对账两段」待发送包合并后再单独立包。
- 本包自身合规自查：新增文件仅两处且均按附则精神说明——Core `StoreLoadState.swift`（第 10 项的共用定义本体，无既有文件可落：KanbanModels／LedgerModels 各属一面、放任一面即偏袒）、`Scripts/merge_xcstrings.py`＋样本目录（第 13 项的工具本体，Scripts/ 为仓内既有工具目录、与 validate_i18n.py 同列）；未新开 Store／Client、未新增 UserDefaults 键。FileReaderHost 落 DocumentReaderView.swift 既有文件（与 DocumentBlocksView 同居），未新开文件。

### 139.5 单测与校验

- Core 单测新增 StoreLoadStateTests 8 测（HermesError 映射 2／未连接落态 1／桥错误映射 3／态形 2）；阅读器合一为呈现层结构动作、无新增单测（块渲染与分型口径由既有 MarkdownBlocksTests／FileOpenFailure 相关测钉住，未动）。
- validate_i18n.py：本包零新增目录键（复用既有文案原样搬移），合并前本地实跑为准（见预制验收记账）。

### 139.6 预制验收记账（2026-11-11）

- 分支 feat/cx-misc：代码提交 c5ee06a，基线 main 7265879（0.50.3）；分支 CI run 42986061035（head c5ee06a，workflow_dispatch 触发）completed success、build-native 单 job 全绿，单测 Executed 1361、0 failures（新增 StoreLoadStateTests 8 测全过；Tests/ 仅新增一文件、既有测零删改，只增不减）。validate_i18n.py 本地实跑通过（2620 键、零新增键）；merge_xcstrings.py --self-test 通过、全量回放结论见 139.3。未合并、版本号未动，待主线按序合并定版；合并后真机待验：md/xlsx/csv 三类各开一份真文件、表格切 sheet、两阅读器各造一次失败态（断网开文件）核对失败页与动作。

### 139.7 合并与验包记账（2026-11-11，主线合并单）

- **交付定版**：0.50.10／132。merge 81057e7（feat/cx-misc 8a67b9d → main，基线 7265879／0.50.3；分支 CI run 42986061035 success、分支单测口径 1361＝其基线 1353＋8）。冲突一处：DESIGN-V4.md——HEAD 侧 §129.8–§138 全保留在前、本节顺接文末；其余文件自动合并，接线复核全在位：§129 verifyExistence 两呼叫点（RichContentViews）、§131 fileRevealPath、§135 BottomStickCoordinator／renderPlan 五处、§136 MediaMarker.split／AssistantMediaImage、§137 ServiceHealth.from(health:) 五处、§138 FileBackfillPolicy 单试＋DictationLanguage.localeIdentifiers＋.fastResults 选项、本包 FileReaderHost 两阅读器共用与 OneDayBridgeError Core 单一定义。
- **节号改注（消歧）**：本节预制时预占 §133，现行已用至 §138（§133 已被占用），合并时主线顺延改注 **§139**、原预占号作废（节头已写明）；139.1–139.6 小节号随迁，本节为 139.7。分支代码与脚本注释内的 §133 引用同步改注 §139（10 处：DocumentReaderView／KanbanStore／LedgerStore 2／OneDayBridgeModels 2／StoreLoadState／StoreLoadStateTests／merge_xcstrings.py／样本 README 各 1），改后本包 §133 零残留（§135／§136 节内对 cx-misc 预占 §133 的历史记述保留原样）。
- **xcstrings 三方并集（用本包入仓脚本实跑）**：merge_xcstrings.py 以 base＝7265879、ours＝main 8e6b655、theirs＝feat/cx-misc 跑 Localizable——base 2607／ours 2623／theirs 2607，**零冲突**；分支相对基线零新增、零删除、零改值（逐键对账：added／removed／changed 三单皆空），并集结果与 main 现行 2623 键语义逐键全等，故文件保留 main 现行版（脚本输出键序按其 base 序＋新增序、与现行文件序不同，不为对账改序）；InfoPlist 同法跑：13 键三方全等、零冲突。merge_xcstrings.py --self-test 通过；validate_i18n 通过（2636 键含 InfoPlist 13，三语全覆盖）。
- **单测对账**：Tests/ 仅新增 StoreLoadStateTests.swift 一文件 8 法，既有测零删改；合并后 CI 单测 Executed **1432、0 failures**（合并前 main 1424＋本包 8，只增不减，与预期分毫不差），无例外项。
- 定版 c0de202（版本五处＝Project.swift 四处 0.50.10/132＋SettingsView 页脚「OneDay v0.50.10」，grep 验无 0.50.9 残留）。CI run 42996454744：jobs API 逐项终判 build-native 及全部 steps **success**（head c0de202）。IPA 落 ~/workspace/your_files/oneday-v0.50.10/OneDay-0.50.10.ipa，10,036,158 字节，md5 `1ff23adc3f4bae424c2fa0f92be47d5a`（落盘与 CI 产物逐字一致），Info.plist 实读 0.50.10／132／site.didichou.oneday。真机待验沿 139.6 清单（md/xlsx/csv 各开一份真文件、表格切 sheet、两阅读器各造一次失败态核对失败页与动作）。
