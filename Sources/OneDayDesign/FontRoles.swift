import SwiftUI

// MARK: - 字阶角色（0.23.0，视觉审计 G2 十角色表）
// 纪律：全 App 文字只许用本表角色（或系统文本样式的
// 同名直用），不许 .system(size:) 钉文字。角色的数
// 值对账面在 Core TypeRole（样式名/默认 pt/字重档，
// 单测钉）；本文件只落 SwiftUI 形态。默认字号下每
// 个角色与 0.22.0 定版落值逐项等值（抽屉名 34
// semibold/行题 20/副行与时间 15），迁移只换实现
// 形态——固定号→文本样式，Dynamic Type 与 Bold
// Text 自此全 App 归一（native-ios-design 排版第
// 一规：只用系统文本样式、按角色命名、一个文件）。
// 映射不了的展示位（总览大数字 .title/.title2、徽标
// 内字形）不在本表，逐项登记于 DESIGN-V4 §50。

public extension Font {
    /// 屏名（抽屉名字头）：34 semibold——审计原表为
    /// largeTitle.bold，0.22.0 用户并排图定版 semibold
    /// 覆盖之（§49.5），本角色从定版
    static let screenName: Font = .largeTitle.weight(.semibold)
    /// 大行题（抽屉旁聊题/设置行题/交付物题）：20 regular
    static let rowTitleL: Font = .title3
    /// 大行题半粗（抽屉导航行/管理行/设置身份卡/文件分段）：20 semibold
    static let rowTitleLSemi: Font = .title3.weight(.semibold)
    /// 内容行题（ContentRow/UnifiedRow/会话行）：17 semibold
    static let rowTitle: Font = .headline
    /// 正文：17 regular
    static let bodyText: Font = .body
    /// 行副题（设置状态副行/交付物类型小字）：15 regular
    static let rowSubtitle: Font = .subheadline
    /// 元信息（行尾时间/计数）：15 regular，等宽场合
    /// 用 metaMonospaced
    static let meta: Font = .subheadline
    /// 元信息等宽变体（服务器 host 等标识读数）
    static let metaMonospaced: Font = .system(
        .subheadline, design: .monospaced
    )
    /// 分区头（全 App 统一，审计 S4）：15 medium
    static let sectionLabel: Font = .subheadline.weight(.medium)
    /// 说明小字（思考正文/引用条摘要/状态说明）：13 regular
    static let captionText: Font = .footnote
    /// 仅徽标：12，禁作正文
    static let badgeOnly: Font = .caption
}
