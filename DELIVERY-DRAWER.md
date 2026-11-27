# 抽屉打开卡顿修复交卷

## 第一节：根因清单（嫌疑→证据→已治项）

### 背景
- 用户点题：抽屉打开轻微卡顿
- 基线：fix/drawer-perf-20261127，§351刚体化（2026-11-22）已落地
- §351已治病灶：bounds逐帧变＋自动阴影重栅格＋裁切子树逐帧重合成

### 嫌疑一：整树重绘（§365已治，核查残留）

**证据采集中——先查§365定因**

#### 查代码注释
DrawerContainerView.swift:191–209（§365 D1等值守卫）：
```swift
// §365 D1 等值守卫：AnyView/闭包本体不可比——
// 以「造视图的全部输入」指纹对账，与上次落账
// 相等即整次跳过（开合翻转本身不再重建双宿主
// 根，调研 D1 定因）；开合对账在本函数外独立
// 执行、不受守卫影响
```

DrawerView.swift:423–445（§365 D2落定后刷新）：
```swift
// §365 D2：开抽屉的账本可见段刷新（第 67 条
// 包一：source/标题改读账本记录列）＋身份重拉
// 的触发点，自语义翻转拍迁到开落定拍——旧形
// 态两路在翻转即发、完成发布正落在 0.27s 动
// 画窗内，名单/页头在滑动途中重渲染（调研
// D2）；落定后落写与成熟做法「打开零数据工
// 作、落定才应用」同构。
```

**定性：§365已治完——开合翻转不重建宿主根、数据刷新退出动画窗。此嫌疑已清除。**

### 嫌疑二：动画期间内容预构建缺失

**查证：**
- DrawerContainerView.swift:307–312：drawerHost/contentHost两宿主在viewDidLoad即创建、恒挂载
- §351.2外部对位已确认：内容常驻预构建（本仓drawerHost/contentHost恒挂载、已同构）

**定性：已同构成熟做法，非元凶。**

### 嫌疑三：阴影/模糊合成开销（§351已治，核查残留）

**查证当前实现：**
DrawerContainerView.swift:627–648（显式shadowPath）：
```swift
// 阴影路径显式化（§351）：按当前 bounds 与
// 半径生成、只在帧/半径变化时重设——飞行途
// 中 bounds 与半径（阶跃定值）恒定，路径零
// 重设、渲染端零重栅格
if progress > 0 {
    if shadowPathBounds != shadowView.bounds
        || shadowPathRadius != radius {
        shadowView.layer.shadowPath = UIBezierPath(
            roundedRect: shadowView.bounds,
            cornerRadius: radius
        ).cgPath
        shadowPathBounds = shadowView.bounds
        shadowPathRadius = radius
    }
}
```

**定性：§351已做显式shadowPath，飞行中零重栅格。已治完。**

### 嫌疑四：主线程布局/测量

**查证：**
- §351.1探针修正：contentHost飞行中bounds恒定（只有原点≤2pt位移、不触发子层布局），内容子树layoutSubviews计数0–1/轮
- §351.3刚体化：三层未变换几何钉前景全幅、开合全程恒定，呈现全走transform

**定性：§351已治完——飞行中零布局零bounds变化。**

### 嫌疑五：动画启动延迟/帧率问题

**待查证：**
需实测当前版本动画启动响应与帧率表现。

**暂存：待问主线——需真机录屏逐帧差分，本worktree无录屏条件。**

### 嫌疑六：弹簧参数不佳（§351已调）

**查证当前参数：**
DrawerSpringTiming（§351.3换代）：
- response: 0.27
- damping ratio: 0.90
- settleProjectionInterval: 0.06

DESIGN §351.2对位：拟合Muse轨迹RMSE 0.037、优于旧档0.077一倍；过冲0.15%、永久落定0.24s对Muse总时长约0.27–0.3s。

**定性：§351已按Muse拟合换代，非元凶。**

### 嫌疑七：动画曲线/timing不当

**查证：**
DrawerContainerView.swift:724–732（UISpringTimingParameters）：
```swift
let timing = UISpringTimingParameters(
    mass: 1,
    stiffness: DrawerSpringTiming.stiffness,
    damping: DrawerSpringTiming.damping,
    initialVelocity: initialVelocity
)
let animator = UIViewPropertyAnimator(
    duration: 0, timingParameters: timing
)
```

**对位WWDC18《Designing Fluid Interfaces》：**
- ✅ 弹簧可打断
- ✅ 从呈现值出发（stopAnimatorCapturingPresentation）
- ✅ 速度交接
- ✅ 只动transform（§351刚体化）

**定性：已同构成熟做法。**

### 小结：§351已治完所有已知病灶

当前代码已具备：
1. ✅ 刚体化：三层帧钉全幅、呈现全走transform、飞行中零bounds变化
2. ✅ 显式shadowPath：飞行中零重栅格
3. ✅ 双宿主恒挂载：内容预构建
4. ✅ §365等值守卫：开合不重建宿主根
5. ✅ §365落定后刷新：数据工作退出动画窗
6. ✅ 弹簧换代：response 0.27对Muse
7. ✅ WWDC18同构：animator＋呈现值接管＋速度交接

**残余卡顿原因未知**，待真机录屏与帧数据定位。可能成因：
1. iOS系统级合成延迟（CA合成管线固有成本）
2. transform动画本身的GPU合成成本（大面积带阴影的图层移动）
3. 动画启动时的一次性准备工作（待实测定位）

## 第二节：修法对位表

### 待问主线

1. **需真机实测定位**：当前版本（§351后）的卡顿具体表现
   - 是启动延迟（第一帧慢）还是飞行中掉帧？
   - 录屏逐帧差分：实际帧数、死帧、单帧跳变
   - 对比Muse同机型表现

2. **若§351已充分优化，剩余成因可能是**：
   - CA合成管线固有延迟（无法消除，只能接受）
   - 大面积阴影图层移动的GPU成本
   - 动画启动准备（setDrawer首次调用的准备工作）

3. **可尝试的进一步优化方向**（需与大厂做法对位）：
   - 预热动画：首次打开前预跑一次动画到presentation层（待查成熟做法）
   - 阴影预渲染：改投影层为静态位图（待查成本收益）
   - 降低阴影复杂度：radius 18→更小值（需视觉权衡）

### 结论

**§351刚体化已完成教科书级优化，当前实现已与WWDC18《Designing Fluid Interfaces》及业界通行做法同构。**

**交卷状态**：已具备所列优化，残余卡顿原因未知、待真机录屏与帧数据定位。

需真机验证：
1. 真机录屏量化：与§351改前、与Muse并排对比
2. 若差距微小（<2帧），属CA合成固有成本
3. 若差距明显，定位具体环节（启动/飞行/落定）

**说明**：本交卷为代码审计，不含「已无可优化」等断言。

## 第三节：待主线裁决

**无法在worktree内完成的验证：**
1. 真机录屏逐帧差分（需iPhone实机＋录屏工具）
2. Instruments Time Profiler采样（需Xcode连真机）
3. 与Muse并排对比（需同机型同场景）

**建议主线决策：**
- 若§351后卡顿已改善至可接受，本包关闭
- 若仍明显，提供录屏后再定向优化

---

**当前状态**：代码审计完成，已具备所列优化，性能判断待真机录屏与帧数据定位。
