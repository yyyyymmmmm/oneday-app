import OneDayApp
import OneDayCore
import OneDayDesign
import SwiftUI
import XCTest

/// 症二 2a·误开复现：胶囊命中域对照实验（2026-11-12）
///
/// **12:41 范围收口（硬约束）**：误开定因只盯胶囊本体
/// （模型侧 Menu→Button 变更＋胶囊自身命中结构），容器
/// 不作根因。本实验在**容器静止态**（抽屉关闭、无动画）
/// 下对胶囊全宽做命中扫描，记录每个落点触发的动作。
///
/// **回归窗**：0.49.3（9be8818，用户确认正常）→ 0.50.22
/// （9c634b0，症状已存在）
///
/// **A/B 对照设计**：
/// - **A 组（历史形态）**：0.49.3 capsuleRow（原生 Menu +
///   Picker，玻璃挂行本体）
/// - **B 组（现行形态）**：IdentityCapsuleView（两个独立
///   Button，玻璃在背景层）
/// - **唯一变量**：胶囊形态本身（容器、宿主恒定）
///
/// **实验方法**：构造可切换的测试视图，对全宽逐点扫描命
/// 中域，记录触发 onOpenHub 还是 onOpenModelPicker。
final class CapsuleHitTestScenarios: XCTestCase {
    // MARK: - 测试数据

    struct HitTestRecord {
        let xOffset: CGFloat  // 相对胶囊左缘的水平偏移
        let triggeredAction: TriggeredAction

        enum TriggeredAction: String {
            case openHub = "打开枢纽"
            case openModelPicker = "打开模型选择"
            case none = "无响应"
        }
    }

    // MARK: - 对照组标记

    /// 实验条件：容器静止态（抽屉关闭、无动画、页面正常装配）
    /// 扫描范围：胶囊全宽（左缘 0pt → 右缘 ~256pt，真机实测值）
    /// 扫描粒度：每 8pt 一个采样点（覆盖头像、名字、状态、分隔线、模型短名、chevron）
    func testCapsuleHitRegions_HistoricalForm_0_49_3() throws {
        // A 组：0.49.3 形态（capsuleRow，Menu + Picker）
        // 预期：全宽命中域清晰分界——左侧身份域触发枢纽、右侧模型域（分隔线起）触发模型菜单
        //
        // 历史形态特征（git show 9be8818）：
        // - 身份域：Button { showHub = true } label: { HStack(头像/名/状态) }
        // - 模型域：Menu { Picker(...) } label: { HStack(短名/chevron) }
        // - 玻璃：.glassEffect(.regular, in: Capsule()) 直接挂行本体
        //
        // **此测试记录 0.49.3 形态的预期命中行为作为基线**
        XCTExpectFailure("A 组历史形态需构造 0.49.3 capsuleRow 放进现行容器，真机扫描后填入实测记录")

        // 预期基线（待真机扫描验证）：
        // 左缘 0–170pt：身份域 Button → openHub
        // 中间 ~176pt：0.5pt 分隔线 → 可能落在任一侧
        // 右侧 182–256pt：模型域 Menu → openModelPicker
    }

    func testCapsuleHitRegions_CurrentForm_0_50_22() throws {
        // B 组：0.50.22 形态（IdentityCapsuleView，两个独立 Button）
        // 观测：用户报告「点状态栏求回顶却开模型面」
        //
        // 现行形态特征（IdentityCapsuleView.swift）：
        // - 身份域：Button { onOpenHub() } label: { HStack(头像/名/状态) }.buttonStyle(.odPressable)
        // - 模型域：Button { onOpenModelPicker() } label: { HStack(短名/chevron) }.buttonStyle(.odPressable)
        // - 玻璃：.background { Capsule().fill(.clear).glassEffect(.regular) }（§179 降背景层）
        //
        // **此测试记录现行形态的实际命中行为**
        XCTExpectFailure("B 组现行形态需真机扫描后填入实测记录")

        // 症状描述：胶囊上缘玻璃带（在任何标签之外、紧贴状态栏带下沿 9pt）落点
        // 被吞下按位置派给模型钮，用户点状态栏求回顶却开模型面
    }

    // MARK: - 候选根因验证

    func testHypothesis_GlassInteractionViewCoverage() throws {
        // 候选 1：UIPlatformGlassInteractionView 盖满整颗胶囊
        // 来源：§179 文档「0.17.0–0.50.21 的行本体玻璃会在 iOS 26
        // 生成单一交互视图盖满整颗胶囊（宿主实测 256×42、与行帧逐点
        // 同域），两钮失去独立命中域」
        //
        // 裁决方法：
        // 1. 若 A 组（0.49.3，玻璃挂行本体）也出现误开 → 候选成立
        // 2. 若 A 组命中干净、B 组（玻璃降背景层）仍误开 → 候选排除
        XCTExpectFailure("待 A/B 对照扫描结果裁决")
    }

    func testHypothesis_HairlineTouchTarget() throws {
        // 候选 2：0.5pt 发丝线亚像素命中域歧义
        // 来源：Rectangle().fill(Palette.hairline).frame(width: 0.5, height: 18)
        //
        // 裁决方法：
        // 1. 对分隔线 ±4pt 范围做密集扫描（每 1pt 一个采样点）
        // 2. 若误开集中在分隔线附近 → 候选成立
        // 3. 若误开分布在身份域中部、远离分隔线 → 候选排除
        XCTExpectFailure("待细粒度扫描后裁决")
    }

    func testHypothesis_PresentationFallback() throws {
        // 候选 3：模型面呈现失败落回按位置派发
        // 来源：§149/§153 模型侧由原生 Menu 改为 ChatModelPickerView
        // 自定义 sheet（0.50.16）+ §175 宿主迁移（0.50.21）
        //
        // 裁决方法：
        // 1. 若 A 组（0.49.3，原生 Menu）命中干净 → 怀疑与 sheet 改造相关
        // 2. 逐笔二分回归窗内三笔变更（Menu→sheet / 宿主迁移 / 玻璃降背景）
        //    锁定哪一笔引入异常
        XCTExpectFailure("待 A/B 对照 + 逐笔二分后裁决")
    }

    // MARK: - 回归窗逐笔二分（若 A 组干净）

    func testRegressionBisect_Step1_MenuToSheet() throws {
        // 中间态 1：§149/§153（0.50.16）模型侧由原生 Menu 改为
        // ChatModelPickerView 自定义 sheet
        //
        // 变更点：Menu { Picker(...) } → Button { showModelPicker = true }
        // + .sheet(isPresented: $showModelPicker) { ChatModelPickerView(...) }
        //
        // 构造方法：用 0.49.3 的 capsuleRow 身份域 + 0.50.16 的模型域
        // Button + sheet，放进现行容器扫描
        XCTExpectFailure("待 A 组基线确认后构造")
    }

    func testRegressionBisect_Step2_HostMigration() throws {
        // 中间态 2：0.50.21 模型面宿主迁移（§175 外部补丁）
        //
        // 变更点：sheet 宿主从某处迁移到 ChatView 根
        //
        // 构造方法：用 0.50.21 定版代码（git show 对应 commit）提取
        // 胶囊与 sheet 装配，放进现行容器扫描
        XCTExpectFailure("待中间态 1 确认后构造")
    }

    func testRegressionBisect_Step3_GlassToBackground() throws {
        // 中间态 3：§179（0.50.22）玻璃降背景 + 胶囊独立成件
        //
        // 变更点：.glassEffect 从行本体移到 .background { Capsule()... }
        // + capsuleRow 独立为 IdentityCapsuleView
        //
        // 构造方法：即 B 组现行形态（已在 testCapsuleHitRegions_CurrentForm_0_50_22）
        XCTExpectFailure("B 组已覆盖此态")
    }
}
