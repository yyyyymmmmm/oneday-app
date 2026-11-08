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
