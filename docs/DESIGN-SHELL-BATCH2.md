# §183 外壳批二·证据轮（2026-11-12）

**全证据、零施工。原生审计暂停令（12:36）：症一、症二修法全部暂停，只许产出实验、量测与记录。**

## 症一·纯色块：现状层证据表

### 裁决定因（会诊已定，不重查）
边缘背景责任碎片化（页面根／UIKit 容器底色／系统材质各管一段）＋玻璃背后只有平色画布、内容流不到栏下、边缘处理为 .hard／隐藏。

### 现状层证据（五页×顶/底×浅/深）

#### 1. 聊天页（ChatView.swift）
| 层级 | 责任方 | 实现 | 文件:行号 |
|------|--------|------|-----------|
| **顶栏** | ScrollView .safeAreaBar(edge: .top) | headerBar + ProgressCapsuleView；**顶栏本体无 background**（§179 后改，见注"顶栏自此不挂任何 background"），滚动态由 .scrollEdgeEffectStyle(.soft) 在栏高内柔化；静止态直接坐在画布上 | ChatView.swift:1861-1889 |
| **底栏** | ScrollView .safeAreaBar(edge: .bottom) | bottomBar 本体；§165 底缘模糊带已删，发送区下方零自绘层 | ChatView.swift:1945-1961 |
| **画布** | chatSurface 根 | .background { Palette.chatSurface.ignoresSafeArea(edges: .bottom) } | ChatView.swift:641-644 |

#### 2. 点子页（IdeasView.swift）
| 层级 | 责任方 | 实现 | 文件:行号 |
|------|--------|------|-----------|
| **顶栏** | NavigationStack .toolbar | 系统导航栏（.navigationTitle("点子") + .toolbar primaryAction 新建钮） | IdeasView.swift:62-70 |
| **底栏** | TabView 系统底栏 | DrawerContainer 提供，页面不自绘 | — |
| **画布** | 页面根多处 | Group/List/ContentUnavailableView 各自挂 .background(Palette.pageBG)，共4处 | IdeasView.swift:61, 161, 413, 632 |

#### 3. 目标页（GoalsView.swift）
| 层级 | 责任方 | 实现 | 文件:行号 |
|------|--------|------|-----------|
| **顶栏** | NavigationStack .toolbar | 系统导航栏（.navigationTitle("目标") + .toolbar primaryAction 新建钮） | GoalsView.swift:74-82 |
| **底栏** | TabView 系统底栏 | DrawerContainer 提供，页面不自绘 | — |
| **画布** | 页面根多处 | Group/ScrollView 各自挂 .background(Palette.pageBG)，共2处 | GoalsView.swift:73, 407 |

#### 4. 枢纽页（AgentHubView.swift）
| 层级 | 责任方 | 实现 | 文件:行号 |
|------|--------|------|-----------|
| **顶栏** | 页头圆钮行 | 自绘页头（✕/分享钮 + 头像 + 名称 + 状态），无系统导航栏 | AgentHubView.swift:142-148（ZStack 根先铺 Palette.pageBG.ignoresSafeArea()） |
| **底栏** | 无 | sheet/fullScreenCover 呈现，无底栏 | — |
| **画布** | ZStack 根 | Palette.pageBG.ignoresSafeArea() | AgentHubView.swift:148 |

#### 5. 文件页（DeliverablesView.swift）
| 层级 | 责任方 | 实现 | 文件:行号 |
|------|--------|------|-----------|
| **顶栏** | 自绘 identityHeader | ZStack { HStack(左抽屉钮 + Spacer + 右菜单钮) + IdentityAnchor }，**无显式 background**（继承画布色） | DeliverablesView.swift:246-325 |
| **底栏** | TabView 系统底栏 | DrawerContainer 提供，页面不自绘 | — |
| **画布** | NavigationStack > VStack 根 | .background(Palette.pageBG) | DeliverablesView.swift:148 |

### 边缘效应档位现状
- **聊天页**：ScrollView .scrollEdgeEffectStyle(.soft, for: .top/.bottom)，顶底双向柔化（ChatView.swift:1861-1889, 1945-1961）
- **点子/目标页**：系统 NavigationStack 默认行为（未显式设置边缘效应）
- **枢纽页**：非滚动容器主导，无边缘效应声明
- **文件页**：四个滚动面（文件列表/网格、影音列表/网格）底缘一律 .scrollEdgeEffectStyle(.hard, for: .bottom)（§170 用户亲定，DeliverablesView.swift:603/750/958/997）

### 症状与现状对账
纯色块症状＝玻璃栏下方出现平色带（非柔化渐变）。现状：
1. **聊天页**特殊：顶栏无 background、依赖 .soft 边缘效应，画布 chatSurface 自定义色
2. **点子/目标/文件页**：标准 NavigationStack + Palette.pageBG 画布
3. **所有页**：底栏由 TabView 系统底栏（DrawerContainer 层）统一提供

**修法暂停、待原生审计裁决。**

---

## 症二·胶囊（误开＋穿层）：同宿主对照实验

### 用户新线索（12:33）
**胶囊在 0.49.3 及之前都是好的——这是回归，不是老病。**

### 回归窗锁定（0.49.3 → 0.50.22）
- **0.49.3 定版**：9be8818（用户确认正常）
- **0.50.22 定版**：9c634b0（当前基线，症状已存在）
- **回归窗内与胶囊相关的变更**（初步候选）：
  1. §149/§153（0.50.16）：模型侧由原生 Menu 改为 ChatModelPickerView 自定义 sheet
  2. 0.50.21：模型面宿主迁移（外部补丁）
  3. §179（0.50.22）：玻璃降背景＋胶囊独立成件 IdentityCapsuleView

### 0.49.3 实查形态（git show 9be8818 初查）
- **模型侧**：原生 Menu + Picker（系统件、无 sheet）
- **胶囊玻璃**：挂在**行本体**（即 §179 后来改掉的形态）
- **胶囊位置**：内联在 ChatView 的 capsuleRow 函数内
- **枢纽钮**：与现行逐字同构

### 2a. 误开复现：胶囊本体命中扫描（第一优先）

#### 12:41 范围收口（硬约束）
误开定因只盯**胶囊本体**（模型侧 Menu→Button 变更 + 胶囊自身命中结构）。**抽屉容器不许作为误开的根因或解释出现、不许往容器方向花实验预算**；容器只与 2b 穿层相关。

#### 实验条件
- **静止态**：抽屉关闭、无动画、页面正常装配
- **扫描范围**：胶囊全宽（左缘 0pt → 右缘 ~256pt，真机实测值）
- **扫描粒度**：每 8pt 一个采样点，覆盖头像、名字、状态、分隔线、模型短名、chevron

#### A/B 对照组设计（决定性）
将 0.49.3 形态放进**现行容器**（宿主、容器恒定），与现行形态同条件扫描：

**A 组（0.49.3 历史形态，git show 9be8818）**：
- 身份域：`Button { showHub = true } label: { HStack(头像/名/状态) }`
- 模型域：`Menu { Picker(...) } label: { HStack(短名/chevron) }`（系统件）
- 玻璃：`.glassEffect(.regular, in: Capsule())` 直接挂行本体
- 胶囊位置：内联在 ChatView 的 capsuleRow 函数内

**B 组（0.50.22 现行形态，IdentityCapsuleView）**：
- 身份域：`Button { onOpenHub() }`，`.buttonStyle(.odPressable)`
- 模型域：`Button { onOpenModelPicker() }`，`.buttonStyle(.odPressable)`
- 玻璃：`.background { Capsule().fill(.clear).glassEffect(.regular) }`（§179 降背景层）
- 胶囊位置：独立成件 IdentityCapsuleView

**唯一变量**：胶囊形态本身（宿主 DrawerContainer + TabView + safeAreaBar 恒定）

#### 实验交付物
1. **CapsuleHitTestScenarios.swift**：测试场景框架，记录预期与实测命中行为
2. **CapsuleFormComparison.swift**：对照视图，可在真机/模拟器上并排展示两种形态供手动扫描
3. **实测记录**（待真机扫描后填入）：
   - 每个落点（x 偏移）触发的动作（枢纽/模型/无响应）
   - 特别关注胶囊上缘（靠近状态栏）与 0.5pt 分隔线附近的行为

#### 逐笔二分（若 A 组干净）
回归窗内三笔变更，逐笔构造中间形态同宿主重扫：
1. **中间态 1**：§149/§153（0.50.16）Menu → ChatModelPickerView sheet
2. **中间态 2**：0.50.21 模型面宿主迁移（§175 外部补丁）
3. **中间态 3**：§179（0.50.22）玻璃降背景 + 胶囊独立（即 B 组）

锁定哪一笔引入异常。

#### 候选根因（待裁决）
1. **UIPlatformGlassInteractionView 盖满胶囊**（§179 文档记录）：若 A 组也误开→成立；若 A 组干净→排除
2. **0.5pt 发丝线亚像素命中域歧义**：若误开集中分隔线附近→成立；若分布在身份域中部→排除
3. **模型面呈现失败落回按位置派发**：若与 Menu→sheet 变更时序对应→成立；否则→排除

### 2b. 穿层观察：呈现层级记录（第二位）

#### 观察范围
同装配下（容器静止态）记录模型 sheet／枢纽 cover 的实际呈现层级。**此件才与容器/宿主深度相关**，2a 不涉及。

#### 观察项
1. **模型选择面（sheet）**：
   - 是否完整盖住下层内容（聊天页、背景）
   - 状态栏行为（可见/穿透/遮挡）
   - 坞行为（隐藏/穿透/遮挡）
   - 输入栏是否被盖住

2. **枢纽面（fullScreenCover）**：
   - 是否完整盖住所有下层内容（包括 TabView 坞）
   - 状态栏行为
   - 内容是否触及屏幕边缘

3. **容器深度关系**：
   - 呈现宿主在哪一层（DrawerContainer / TabView / ChatView）
   - UIHostingController 是否传播多余安全区
   - 与 §175 宿主迁移的关系

#### 当前装配（ChatView.swift）
- 模型 sheet 宿主：ChatView 根（§175 迁移后）
- 枢纽 cover 宿主：ChatView 根（未变更）

#### 0.49.3 对照基线
- 模型域：原生 Menu（系统管理呈现，无自定义 sheet）
- 枢纽：fullScreenCover（与现行同形态）

若 0.49.3 的 Menu 呈现层级正常 → 怀疑与 §149/§153 的 sheet 改造相关。

#### 实验交付物
1. **PresentationLayerScenarios.swift**：呈现层级测试场景
2. **PresentationLayerObservation.swift**：真机观察辅助视图，带背景参照层与边界标记
3. **实测记录**（待真机观察后填入）：
   - 两种呈现面的层级行为
   - 系统栏遮挡关系截图（如有异常）
   - 与容器深度的对账

---

### 交付范围（冻结令约束）
1. 复现实验落成**测试文件**（Tests/OneDayAppTests/ShellBatch2/），留仓
2. 结论记录（本节）：回归点候选清单 + 每条的对照证据 + 被排除项及排除理由
3. **到此停手**，修法等主线考古对账

**修法冻结、待主线考古对账。**

---

## 症三·浮空距离：量测裁决

### 代码层定论（已坐实）
显式增距＝0pt（两方审计一致），不许再往代码常量里找。

### 量测任务

#### 素材
- **录屏**：`~/workspace/user/media_library/video/56/56bf987c1873dbe0f2ce035991455955768dde0e5f144a1b08268a9fde4680d5.mp4`
- **分辨率**：720×1566 px（@3x，逻辑分辨率 240×522 pt）
- **抽帧**：5个关键帧（1s, 2s, 3s, 4s, 5s）→ `docs/shell-batch2-measurements/frame-001~005.png`
- **Muse 参照图**：`~/workspace/user/media_library/image/` 子目录（待确认具体文件）

#### 量测方法
- **主量**：自家坞栏下缘 ↔ 屏底距离
- **换算**：1 pt = 3 px（@3x）
- **标准带**：34–36 pt（iOS Home Indicator 标准区域）

### 初步量测结果（Frame-001 自动检测）

```
检测方法：水平行平均亮度分析，定位内容区→Home Indicator 转换点
坞栏内容下缘：1503 px（自动检测）
屏幕底部：1566 px
浮空距离：63 px = 21.0 pt
```

**异常**：实测 21.0 pt **小于**标准带下限（34 pt），不足 13.0 pt

### 量测异常分析

**预期 vs 实测**：
- 标准 iOS：34-36 pt（Home Indicator 区域含上下安全边距）
- 实测：21.0 pt（明显不足）

**可能原因**：
1. **检测点误判**：自动检测的 y=1503 可能不是坞栏视觉下缘，而是内部某个分界
2. **坞栏定义歧义**：需要明确"坞栏下缘"的具体含义
   - Tab Bar 图标行的底部边界（内容区下缘）
   - Tab Bar 整体背景/模糊层的底部边界（视觉下缘）
   - Home Indicator 上方的某个分界点
3. **特殊布局**：自家坞栏可能采用了非标准布局

**需要补充**：
- 手动标记坞栏的视觉下缘（在录屏帧上精确标注）
- 与 Muse 参照图对比同一位置的量测
- 确认用户报告的"浮空"具体指什么视觉现象
- 检查是否与聊天页输入栏的浮空（非坞栏）混淆

### 裁决分支（待手动量测确认）
- **量值 ≈ 标准带（34–36pt）** → 定性视觉拉伸，归症一收口（症一修法待审计放行），**不动容器**
- **量值明显超出** → 只把「容器经 UIHostingController 传播多余安全区」候选与量测证据记录在案，**修复同样待审计裁决、本轮不许动 contentHost**
- **量值不足（如当前 21pt）** → 需要重新定义量测目标或排除量测错误

### 交付物
1. **量测脚本**：`docs/shell-batch2-measurements/measure.py`
2. **量测日志**：`docs/shell-batch2-measurements/MEASUREMENT-LOG.md`
3. **录屏帧**：`docs/shell-batch2-measurements/frame-001~005.png`
4. **待补充**：手动标注图与 Muse 参照对比

**本轮不许动 DrawerContainerView 的 contentHost。**

---

## 通用纪律
- 提交逐件分明（症一证据／症二实验／症三量测各成提交线），**全部只含测试与文档、生产代码零改动**
- 单测只增不减（main 基线 Core 1679 + App 12）
- §124 回底钮承载不许动；ComposerGuideHost/输入舱托管不许碰（feat/composer-kbguide 在改）
- ChatView 与 DrawerContainerView 的改动保持最小，凡触及在回报里逐处单列
- 推送后 `gh workflow run ios-native.yml --ref feat/ext-shell-batch2` 触发 CI
- 不合并、不发版、不动版本号
