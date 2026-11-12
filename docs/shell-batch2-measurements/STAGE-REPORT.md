# 外壳批二·胶囊重建简报执行回报（2026-11-12 13:15）

工作区：`~/workspace/oneday-worktrees/ext-shell-batch2`  
分支：`feat/ext-shell-batch2`  
基线：8ac6193（0.50.22/144发版验包补记）

---

## 阶段零：分支清账 ✅

### 执行记录

**清账前状态**：
```
002fbca fix(tests): 修正 CapsuleFormComparison 编译错误
80cbb2e docs(shell-batch2): 证据轮交付·症一二三全套实验与量测框架（零施工）
01c7680 fix(shell): §183 症一·纯色块统一修法（Feed/Goals/Ideas 三页底缘 .hard→.soft）← 需剔除
8ac6193 docs(design): §180 发版验包补记（0.50.22/144，run 43106169047、单测 1679＋12、IPA md5）
```

**rebase操作**：
```bash
git rebase --onto 8ac6193 01c7680 feat/ext-shell-batch2
```

**清账后状态**：
```
78e0fed docs(shell-batch2): §183 阶段零清账＋阶段一执行路径分析与数据框架
5010b0b test(shell-batch2): 添加C组苹果官方定式实验（GlassEffectContainer＋逐元素交互玻璃＋glassEffectUnion）
8343578 fix(tests): 修正 CapsuleFormComparison 编译错误
f7fb6f8 docs(shell-batch2): 证据轮交付·症一二三全套实验与量测框架（零施工）
8ac6193 docs(design): §180 发版验包补记（0.50.22/144，run 43106169047、单测 1679＋12、IPA md5）← 基线
```

**验证**：
- ✅ 症一生产提交01c7680已剔除
- ✅ git log无任何Sources/生产提交（仅Tests/与docs/）
- ✅ force-push完成（origin/feat/ext-shell-batch2已更新）

---

## 阶段一：三组命中扫描

### 三组对照设计

#### ①组：现行形态（B组 0.50.22）
- 背景玻璃背板：`.background { Capsule().fill(.clear).glassEffect(.regular) }`
- 两个独立Button：身份域＋模型域
- 按压样式：`.buttonStyle(.odPressable)`
- 发丝线分隔：0.5pt Rectangle
- 文件：Tests/OneDayAppTests/ShellBatch2/CapsuleFormComparison.swift:202-268

#### ②组：历史形态（A组 0.49.3）
- 行本体玻璃：`.glassEffect(.regular, in: Capsule())` 直接挂HStack
- 身份域：Button
- 模型域：原生Menu + Picker
- 按压样式：`.buttonStyle(.odPressable)`
- 文件：Tests/OneDayAppTests/ShellBatch2/CapsuleFormComparison.swift:133-200

#### ③组：苹果官方定式（C组，新增）
- **GlassEffectContainer** 包裹
- 身份/模型两钮**各自**：`.glassEffect(.regular.interactive(), in: Capsule())`
- **glassEffectUnion(id: "identity-capsule")** 拼成一片
- **不挂.odPressable**：系统玻璃按压行为接管
- 发丝线：纯视觉分隔
- **ViewThatFits两档**：全量（头像+名+状态+模型）/ 紧凑（去名字）
- 文件：Tests/OneDayAppTests/ShellBatch2/CapsuleFormComparison.swift:270-328
- 提交：5010b0b

### CI编译验证

**运行信息**：
- Run ID: 43159007720
- 触发方式：workflow_dispatch（5010b0b推送后）
- 状态：⏳ **构建中**（Build步骤）

**监控命令**：
```bash
gh run watch 43159007720 --exit-status
```
（后台任务ID: byr18d32r，输出写入临时文件）

**待验证项**：
- C组代码是否编译通过（GlassEffectContainer等iOS 26.0 API）
- 既有单测是否通过（OneDayAppTests套件）
- Package步骤是否成功

**CI终判方式**：
```bash
gh api repos/yyyyymmmmm/oneday-app/actions/runs/43159007720/jobs \
  --jq '.jobs[] | {name, conclusion, steps: [.steps[] | select(.conclusion != null) | {name, conclusion}]}'
```

### 执行路径分析

**CI能力范围**：
- ✅ **可验证**：C组代码编译通过性
- ✅ **可执行**：既有单测（IdentityCapsuleHitDomainTests等XCTest用例）
- ❌ **不可执行**：三组命中扫描（需真实触摸交互）

**执行路径阻塞**：
三组命中扫描**无法在CI中自动化执行**，原因：
1. 扫描需真实点按胶囊全宽（每8pt采样点）
2. XCTest无法模拟SwiftUI视图的真实触摸事件和命中测试
3. 需观察实际触发的动作（枢纽/模型选择器）

**最小可执行路线**：
1. ✅ CI验证C组编译通过（监控中）
2. ⏳ 在OneDayApp添加CapsuleFormComparison测试入口
3. ⏳ 真机/模拟器运行App
4. ⏳ 手动对三组胶囊逐点扫描
   - 扫描粒度：每8pt一个采样点
   - 记录格式：x偏移 → 触发动作（枢纽/模型/无响应）
   - 特别关注：胶囊上缘（靠近状态栏）、分隔线附近
5. ⏳ 记录数据填入HIT-SCAN-DATA.md
6. ⏳ 根据③组数据判定阶段门

### 数据记录框架

**文件**：docs/shell-batch2-measurements/HIT-SCAN-DATA.md

**内容**：
- 实验设计（三组对照、扫描方法）
- 三组数据表格（x偏移、区域描述、触发动作、备注）
- 串扰落点分析
- 阶段门判定记录

**当前状态**：⏳ 待真机扫描数据填入

### 扫描数据

**三组数据**：待真机执行后填入

**预期基线**：
- ①组：可能存在串扰（症状已知）
- ②组：命中域清晰（用户确认0.49.3正常）
- ③组：全宽零串扰（阶段门判定依据）

---

## 阶段门判定 ⏳

**判定依据**：③组（官方定式）全宽扫描结果

**判定规则**：
- ✅ **全宽零串扰** → 进阶段二（重建IdentityCapsuleView）
- ❌ **仍有串扰** → 停手（只交数据与结论，不落生产代码）

**串扰定义**：
- 左半身份域（头像/名字/状态）触发模型选择
- 右半模型域（分隔线后）触发枢纽

**当前状态**：⏳ 待③组扫描数据判定

---

## 阶段二：胶囊重建 ⏳

**前置条件**：阶段门通过（③组全宽零串扰）

**重建目标**：Sources/OneDayApp/IdentityCapsuleView.swift

**重建规范**：
1. **结构**：
   - GlassEffectContainer包裹
   - ViewThatFits两档（全量/紧凑）
   - 两钮各自`.glassEffect(.regular.interactive(), in: Capsule())`
   - `.glassEffectUnion(id: "identity-capsule")`同id拼合
2. **保持不变**：
   - 动作闭包（onOpenHub / onOpenModelPicker）
   - 无障碍标签
   - 文案与数据派发
   - 发丝线视觉
3. **移除**：
   - `.buttonStyle(.odPressable)`（系统玻璃按压行为接管）
   - 背景层玻璃（改为逐元素玻璃）
4. **不动**：
   - ChatView接线
   - 模型面内容与选择逻辑
   - 枢纽/模型两面呈现

**验收标准**：
- 重建后同扫描复跑（生产形态）全宽零串扰
- 既有IdentityCapsuleHitDomainTests不许删改、须仍绿
- 单测只增不减
- CI全绿（Build/Unit tests/Package须success）
- DESIGN §183补记：裁决依据、三组数据摘要、重建形态

**当前状态**：⏳ 暂停等待阶段门通过

---

## 执行摘要

### 已完成
- ✅ 阶段零：分支清账、剔除症一生产提交、force-push
- ✅ C组代码构造（GlassEffectContainer＋逐元素交互玻璃＋union）
- ✅ 提交5010b0b推送
- ✅ CI触发（run 43159007720）
- ✅ 数据记录框架（HIT-SCAN-DATA.md）
- ✅ 执行路径分析与文档

### 进行中
- ⏳ CI编译验证（Build步骤）

### 阻塞
- ⚠️ **命中扫描需真机手动操作**（本环境无法执行）
- ⚠️ 阶段门判定待扫描数据
- ⚠️ 阶段二重建待阶段门通过

### 待CI完成后补充
- CI run 43159007720终判（success/failure）
- Build/Unit tests/Package各步conclusion
- 测试增减数（若编译通过）

---

## 回报检查清单

简报要求的回报项：

- ✅ **清账后git log**：8ac6193→f7fb6f8→8343578→5010b0b→78e0fed
- ⏳ **CI红最终定性**：run 43159007720构建中，待终判
- ⏳ **三组逐点数据与串扰清单**：待真机扫描
- ✅ **执行路径结论**：CI可验证编译、不可执行扫描，需真机手动操作
- ⏳ **阶段门判定**：待③组数据
- ⚠️ **若落码**：阶段二暂停，待阶段门通过

**当前卡点**：命中扫描需真机执行，本环境无法完成自动化。
