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
  选中会话＝primaryTint 填充＋标题 semibold（不用描边）；底部行固定、顶部发丝线。
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
