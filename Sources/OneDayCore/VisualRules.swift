import Foundation

/// 视觉纪律的纯逻辑部分（0.3.0，DESIGN-V4 §14）：断行
/// 整形——可单测、不依赖渲染环境的部分先钉死在这里，
/// 视图层只消费结果。（字重映射 VisualWeight 已于
/// 0.4.0 随 TypeScale 废止删除，审计 §3.1）

/// 减透明回退裁决（0.23.0，三设置检查的代码层落点）：
/// 自制材质面（抽屉底条霜层＝Material＋渐变 mask）在
/// Reduce Transparency 开启时必须落实色分支——渐变
/// mask 的上沿淡出不受系统材质自动增不透明的管辖、
/// 仍会透字。系统玻璃（glassEffect）与系统 Material
/// 本体（无 mask 时）由系统全权回退、不经本裁决。
public enum TransparencyFallback {
    public enum Surface: Equatable {
        /// 系统材质原形态（可叠渐变 mask 等自制加工）
        case material
        /// 实色面（Palette.surface 同档），零透出
        case solid
    }

    public static func surface(reduceTransparency: Bool) -> Surface {
        reduceTransparency ? .solid : .material
    }
}

/// 断行整形（条 8：text-wrap: pretty 等价近似）。SwiftUI
/// 无 pretty 原语，近似法＝尾行孤字防护：把段落最后两
/// 个字形以 WORD JOINER（U+2060）绑定，使排版器不能在
/// 两者之间断行——末行因此至少携带 2 个字形，孤字尾行
/// 被结构性消除；末字为句末标点时绑最后三个（标点不
/// 落单、也不与前字分家）。绑定对非尾行情形无副作用
/// （两字本就同行时排版不变）。
/// 近似边界（如实记）：逐行断点最终由 TextKit 按实际
/// 宽度决定，本整形不估算行宽——它保证的是「无论断点
/// 落在哪，末行不小于 2 字形」，这正是 pretty 要消灭
/// 的孤字情形；行长均衡（balance）不在本近似范围内。
public enum TextShaping {
    /// WORD JOINER：零宽、禁断行
    public static let wordJoiner = "\u{2060}"
    /// 对单个段落做尾行孤字防护。字形数 ≤2 的段落与含
    /// 换行的多行文本原样返回（调用方按段落逐段施加）
    public static func prettyWrap(_ paragraph: String) -> String {
        // 台账 200 件四（2026-11-22，用户拍板）：整
        // 形退役、原文直入。尾行孤字绑定靠往字间插
        // U+2060 实现——污染找字（UI 测试按正文找不
        // 到文本视图实证）、复制与读屏，且曾劈开数
        // 据检测令牌；入口保留签名防调用方 churn，
        // 恒原样返回。wordJoiner 常量保留：存量文本
        // 的复制净化仍按它剥离（SelectableText-
        // View §149）
        paragraph
    }

    /// 全文版：按空行分段，逐段整形后拼回（段内换行不动）
    public static func prettyWrapDocument(_ text: String) -> String {
        text.components(separatedBy: "\n")
            .map { prettyWrap($0) }
            .joined(separator: "\n")
    }

    /// run 层整形（§271，第 72 条文本管线根治）：先解
    /// 析、后整形——对行内解析已产出的语义 run 施加
    /// 与 prettyWrap 同口径的尾行孤字绑定（逐行、尾
    /// 2 字形／句末标点尾 3 字形）。连接符只落进普通
    /// 文本 run 的字间，结构上不可能劈开定界符：成
    /// 对定界符已被解析消费、run 文本里不存在待劈
    /// 的对（文本层整形的病根——解析前插符劈开段尾
    /// 闭合 `**`／链接尾 `)`／代码闭合反引号——整类
    /// 消除）。两条豁免（同为真值保真、优先于防孤字）：
    /// - 代码 run 相邻不插：代码文本逐字保真，连接
    ///   符不进代码内容（文本层整形曾把符插进闭合
    ///   反引号内侧、污染代码 run 文本）；
    /// - 数字字之间不插：电话／时间／金额等检测令
    ///   牌（NSDataDetector 口径）被零宽符从中劈开
    ///   即识别失败（gen5 T4 探针实见 `1380013800⁠0`
    ///   与 `13:0⁠0`，同根在此一并收）。
    /// 链接 run 的可见标签文本可插（URL 属性不经文
    /// 本、不受影响）。输入为空／无可绑行时原样返回
    public static func shapeRuns(_ runs: [InlineRun]) -> [InlineRun] {
        // 台账 200 件四：同 prettyWrap——整形退役、
        // 原文直入，恒原样返回（调用点四处保留，行
        // 为自此与未整形一致）
        runs
    }
}
