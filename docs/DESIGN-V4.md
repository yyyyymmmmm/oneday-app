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
