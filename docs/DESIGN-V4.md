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
