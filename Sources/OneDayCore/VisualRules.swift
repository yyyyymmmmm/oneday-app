import Foundation

/// 视觉纪律的纯逻辑部分（0.3.0，DESIGN-V4 §14）：字重
/// 映射与断行整形——可单测、不依赖渲染环境的部分先钉
/// 死在这里，视图层只消费结果。

/// 字重（条 3：暗色全降一档）。CSS 权重量纲 100–900
/// 与命名档的对应是行业惯例：100 ultraLight、200 thin、
/// 300 light、400 regular、500 medium、600 semibold、
/// 700 bold、800 heavy、900 black。用户原令「降 40
/// （CSS 权重量纲），即视觉降一档」——落法取命名档降
/// 一档（600→500、500→400、…），100 已是地板不降。
public enum VisualWeight {
    /// 命名档序列（细→粗）
    public static let grades: [Int] = [
        100, 200, 300, 400, 500, 600, 700, 800, 900,
    ]

    /// 就近落到命名档（输入任意 CSS 权重值时用）
    public static func nearestGrade(_ css: Int) -> Int {
        grades.min(by: { abs($0 - css) < abs($1 - css) }) ?? 400
    }

    /// 暗色降一档：先就近落档，再沿序列降一级，地板 100
    public static func steppedDown(_ css: Int) -> Int {
        let grade = nearestGrade(css)
        guard let index = grades.firstIndex(of: grade), index > 0
        else { return 100 }
        return grades[index - 1]
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
    /// 句末/收尾标点：与前字绑定范围扩到三个字形
    private static let closingPunctuation: Set<Character> = [
        "。", "！", "？", "；", "：", "）", "】", "」", "』",
        ".", "!", "?", ";", ":", ")", "]",
    ]

    /// 对单个段落做尾行孤字防护。字形数 ≤2 的段落与含
    /// 换行的多行文本原样返回（调用方按段落逐段施加）
    public static func prettyWrap(_ paragraph: String) -> String {
        guard !paragraph.contains("\n") else { return paragraph }
        let chars = Array(paragraph)
        guard chars.count > 2 else { return paragraph }
        let bindCount = closingPunctuation.contains(chars[chars.count - 1])
            ? 3 : 2
        guard chars.count > bindCount else { return paragraph }
        // WORD JOINER 插在尾部字形「之间」（逐对绑定）：
        // 它禁止两侧断行，把最后 bindCount 个字形锁成
        // 不可断单元——要防的是最后一字被断行孤立，绑
        // 定点必须落在尾部内部而非尾部之前（0.3.0 首轮
        // 单测以此定案：插在尾前时末字仍可被断开）
        var result = ""
        for (index, character) in chars.enumerated() {
            if index >= chars.count - bindCount + 1 {
                result += wordJoiner
            }
            result.append(character)
        }
        return result
    }

    /// 全文版：按空行分段，逐段整形后拼回（段内换行不动）
    public static func prettyWrapDocument(_ text: String) -> String {
        text.components(separatedBy: "\n")
            .map { prettyWrap($0) }
            .joined(separator: "\n")
    }
}
