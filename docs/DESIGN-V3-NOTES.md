# DESIGN-V3-NOTES —— 0.2.2 调研与设计沉淀

> 0.2.2 施工前置产出：先查证、后写码。本文档此后是 OneDay 的设计沉淀基线，
> 与 DESIGN.md（v1 令牌）、DESIGN-V2.md（v2 纪律）并行有效；冲突时以本文较新者为准。

## 1. 腾讯蓝核值（纠正 0.2.1 实证错误）

0.2.1 主题默认值「腾讯蓝 #00A4FF」是未经查证的猜值，**作废**。

腾讯官方设计体系 TDesign 的品牌色阶（官方站点主题面板与组件页一致）：

| 角色 | 色阶 | 值 |
|---|---|---|
| 品牌主色（腾讯蓝） | brand7 | **#0052D9** |
| hover | brand6 | #366EF4 |
| active / 按下 | brand8 | #003CAB |
| 浅染底（light） | brand1 | #F2F3FF |
| focus 浅阶 | brand2 | #D9E1FF |

出处：
- TDesign 官网组件/主题面板（腾讯蓝 HEX: #0052D9、brand-color #0052d9、brand-color-active #003cab、brand-color-light #f2f3ff）：https://tdesign.tencent.com/react/ 及 https://tdesign.tencent.com/flutter
- 腾讯 CoDesign《网页设计规范·色彩篇》：TDesign 以腾讯蓝为默认主题色：https://codesign.qq.com/hc/article/design-system-color/

注：OneDay 0.1.x–0.2.0 曾用的 #0052D9/#003CAB 恰与官方色阶一致；0.2.1 改 #00A4FF 是倒退，本轮改回。

## 2. OneDay 五款主题的取值口径（逐个有据，推导规则统一）

规则：primary＝锚点色；primaryFill（填充档，白字底）＝同色阶加深一档、保证白字对比；
primaryTint（浅染档）＝同色阶最浅档。锚点逐个注明出处，不再凭感觉给值：

| 主题 | primary | primaryFill | primaryTint | 锚点出处 |
|---|---|---|---|---|
| 腾讯蓝（默认） | #0052D9 | #003CAB | #F2F3FF | TDesign brand7 / brand8 / brand1（见 §1） |
| 深蓝 | #003CAB | #002A66 | #D9E1FF | TDesign brand8 起、按规则加深/取 brand2 |
| 墨黑 | #1F1F24 | #000000 | #ECECF1 | TDesign 中性深色画布 #181818 一带的中性墨（官网深色主题画布值） |
| 紫 | #AF52DE | #8E3DB8 | #F6E9FB | Apple HIG 系统色 systemPurple（iOS 官方色板） |
| 绿 | #00A870 | #007A52 | #E6F7F0 | TDesign 功能色·成功 #00A870（官网令牌表） |

深色模式：沿 v2 纪律逐主题给亮一档的值（实现见 AccentTheme.darkPrimary 等）。

## 3. 侧边栏与发送栏：成熟实现参考（逐项出处）

- **Muse 侧边栏**（用户截图口径，仓内 docs/IA-V3.md 已记录）：顶部智能体名标题、
  分组小节（搜索/新建/工作区/最近…）、**底部固定行**（齿轮·搜索·新建三功能）。
  形态要点：行＝图标＋文字单行、分组标题小字、底行与内容区以分隔线分开、常驻不滚走。
- **LobeChat**（开源，github.com/lobehub/lobe-chat）：会话列表项＝标题＋次级信息两行、
  选中项用填充底色令牌而非描边；ChatInput（src/features/ChatInput）为
  「动作按钮行＋输入区」结构，动作均为等径圆形图标按钮，发送键为填充态圆钮。
- **Open WebUI**（开源，github.com/open-webui/open-webui）：输入栏是单个大圆角容器，
  「＋」在容器内左侧、发送键在容器内右侧＝填充圆＋白色上箭头；按钮与输入行同高对齐。
- **Chatbox**（开源桌面/移动聊天客户端）：底部工具行同为等径圆钮阵列，发送键填充强调色。
- **iOS HIG**：点按目标最小 44pt（紧凑工具钮可 36pt 视觉＋44pt 热区以 padding 补足）。

### OneDay 0.2.2 采用规格（定版数值）

- 抽屉唤出钮：**36pt 圆形材质底**（fieldFill 填充＋sidebar 图标 16pt），不再裸图标；
  热区由导航栏按钮天然 ≥44pt 承接。
- 抽屉行高：双行行（会话）最小 54pt；单行动作行（新建会话）46pt；
  图标列固定 30pt 宽对齐；分组标题＝caption semibold 三级色、上距 18pt；
  选中会话＝**浅灰填充（fieldFill）＋黑字 semibold**（不用描边、不用品牌色
  填充——见 §6 规则 1）；底部行固定、顶部发丝线。
- 发送栏：**＋键与发送键同径 36pt 圆形**，与输入框单行高对齐；
  发送键可用＝primaryFill 填充＋白色上箭头、禁用＝fieldFill＋三级色箭头；
  流式停止键同 36pt。输入框圆角 20、内距与按钮基线对齐。

## 4. 礼记仓设计沉淀摘录（github.com/yyyyymmmmm/liqian-app · docs/DESIGN.md）

可复用条目（已在 OneDay 部分生效，本轮起全量执行）：

1. **90% 中性打底＋唯一强调色**：界面九成是中性色（系统底、墨色阶），
   强调色只出现在主按钮、选中态、链接、状态点等行动点，一屏内面积受控。
2. **金色/装饰色退出 UI**：不引入第二装饰色系。
3. **分层靠发丝线与留白，不靠阴影堆叠**；阴影只许登记过的少数档位。
4. **填充令牌与染色令牌分离**：需要「色底＋白字」的场景用专门的加深填充档
   （礼记的填充令牌口径），不直接拿染色主色当底——OneDay 的 primary/primaryFill 双档即源于此。
5. **主按钮实心白字、次按钮描边**；方向/状态标记小而明确。
6. **对比度逐值验算**：强调色与底、白字与填充档都要过对比线，给值时写明，
   不用「看上去差不多」。
7. **逐屏 QA 与防假绿**：构建成功≠功能好了；CI 须防假绿（pipefail、产物解包验），
   交付前逐屏看图、数据任务要看到真实数字。

## 5. 交付物库数据源实查（2026-11-08，生产 GET /api/files）

Hermes 数据根 /opt/data 被服务端锁定。实查产出落点：

- `cache/images|videos|audio|documents|screenshots|scratch`：智能体工作缓存/产出区
- `cron/output`：定时任务产出
- `image_cache`、`audio_cache`：生成媒体缓存
- 以上目录在当前生产**均为空**（Hermes 刚部署、暂无产出文件）；根目录其余为系统区
  （config、logs、backups、sessions 数据、skills、memories 等），不属交付物。
- 文件与会话之间**没有关联字段**（/api/files 回执只有 name/path/size/mtime/mime），
  「来源会话」无接口支撑——交付物库的来源只标到**产出目录**级，不编造会话溯源。

0.2.2 文件页据此实现：聚合上述产出根（递归 ≤3 层）＋根目录散文件
（排除已知系统文件与隐藏文件），按时间倒序；来源＝产出目录语义名。


## 6. 对照 Muse 分析（0.2.2 并入，用户同屏截图实证）

### Muse 的五条规则

1. **近单色**：白底、黑字、灰阶做次级；品牌色只以微点出现（菜单钮上一颗
   小蓝点），选中态用浅灰胶囊＋黑字，绝不用品牌色大面积填充。
2. **图标全线条体**：统一细线 outline 图标、统一尺寸；不用实心填充符号。
3. **行密度精细**：列表行标题约 17pt 常规字重、行高克制，靠字阶和留白
   分层，不靠粗体和大字。
4. **容器轻**：大圆角白卡＋发丝线分隔＋轻阴影的悬浮输入舱；chrome 元素
   各安其层，不跨层漂浮。
5. **每页有自己的形态**：设置是 sheet 分组行、状态是居中头像＋分段控件、
   资源库是图标网格——不一张模板套全站。

### OneDay 0.2.1 的五宗罪与本轮修复

1. 底栏大面积亮蓝实心图标＋蓝色选中块；悬浮胶囊底栏压在抽屉 scrim 之上
   跨层漂浮 → **底栏改自绘贴底栏**（回归布局流、表面色＋顶部发丝线），
   图标线条体，选中态＝墨色＋字重区分＋一颗 4pt 主题色微点；抽屉打开时
   底栏隐藏，scrim 完整覆盖全屏，不再有跨层漂浮。
2. 图标混用实心符号 → 全 App 统一 outline：底栏四图标（气泡/仪表/文件夹/
   齿轮皆线条体）、技能页 lock.fill 改 lock；语义徽标例外登记：视频播放
   角标、附件移除钮、流式停止键（填充是其语义本身）。
3. 抽屉会话标题过大过粗 → 标题降至 callout（16pt）常规字重（选中
   semibold），元信息降 monoCaption＋三级灰，行高收至 50pt。
4. 搜索框重灰填充 → 浅灰胶囊（secondarySystemBackground ≈ #F2F2F7、
   无描边），与 Muse 搜索药丸同语言。
5. 各页同为「标题＋分组行」一模板 → 形态分工（不动 IA）：总览＝状态头
   ＋指标数字排（数字 22pt semibold 为主角）；文件＝影音网格为先、
   文件段紧凑行（46pt）；设置＝sheet 式分组行（保持并精细化）；
   抽屉＝身份块＋精细列表；状态屏＝身份头＋分段（已有）。

### 截图审查对照清单（0.2.2 起每轮执行）

六张图逐张过五条规则：①有无品牌色大面积填充 ②图标是否全线条
③行密度/字重是否克制 ④容器是否轻、chrome 是否跨层 ⑤该页形态
是否区别于其他页。

## 7. 动效与交互登记（0.2.2 专项）

口径（承礼记教训）：动效只服务状态感知——让用户看清发生了什么；
不炫技、不堆叠。每处登记场景/曲线/时长，手感终审在真机。

| 场景 | 实现 | 曲线/参数 |
|---|---|---|
| 抽屉开合 | MotionTokens.indicator 弹簧 | spring(response 0.35, damping 0.85)，Reduce Motion 瞬时 |
| 抽屉拖拽 | 跟手实时位移（横向分量>纵向才接管）＋松手按 predictedEndTranslation 预测位移判开合（阈值 30% 宽），scrim 透明度随进度 0→0.4 | 同上弹簧归位 |
| 页签切换 | 四页常驻 opacity 交叉淡化 | easeInOut 0.18s |
| 页面 push/pop | 系统 NavigationStack 默认过渡 | 系统 |
| 行/钮按压 | PressableButtonStyle（.odPressable）：opacity 0.55＋scale 0.985 | MotionTokens.press（easeOut 0.15s） |
| 回到底部钮 | 出现/消失 opacity＋scale 0.85 组合过渡；上翻时流式不再强拉回底 | MotionTokens.swap（easeInOut 0.2s） |
| 流式光标/打字点 | 既有实现保留（0.9s 阶梯闪烁/三点错峰，Reduce Motion 静止） | 见 ChatView |
| 触觉（UIImpact） | light：发送消息、抽屉吸附（状态变化时）；medium：删除会话/删除交付物确认、网关启停/重启确认 | 系统发生器，不给普通点按与滚动 |

未做（登记为已知取舍）：消息气泡入场过渡（LazyVStack 内 transition
收益低、易掉帧，本轮不加）；深色模式动效差异（无）。
