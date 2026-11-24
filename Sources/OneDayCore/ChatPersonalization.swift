import CoreGraphics
import Foundation

/// 聊天个性化（台账 179，OB-I1；DESIGN §391）：气泡样式
/// 与聊天背景做成可选开关——默认恒为自家风格定版（台账
/// 146/188/197），用户在外观页主动改才变。智能体专属
/// backdrop 未在本包落地（缺口登记见 §391：需逐智能体
/// 资产与身份 plumbing，不在本包硬造）。
///
/// §503 扩容：背景一期补课——新增「跟随主题」档（消费
/// 主题整包背景行）、两款取样纯色（微信灰/浅灰）与三款
/// 内置低对比图案（点阵/网格/斜纹）；相册自定义图片列
/// 二期缺件（§503 明示）。文字大小新设五档（跟随系统＋
/// 四个固定档），映射在 App 层（DynamicTypeSize 是
/// SwiftUI 型、Core 只存档位）。
///
/// 本文件只管「选了哪档」的值与几何/色值口径；持久化键
/// 归 AppearanceStorageKeys、读写口归 AppearancePrefer-
/// ences（与主题/形象档同制），呈现层（Palette）现读现解。

/// 气泡样式三档：定版＝现行圆角原值（22/22/7，与
/// OneDayMetrics 旧常量逐值相同，未设置时呈现零变化）。
/// §503 归位：外观页行名自「气泡样式」改「气泡圆角」
/// （原名暗示整套样式、实只辖圆角——假名行取消）；键与
/// 枚举本体不动，存量值零漂移
public enum ChatBubbleStyle: String, CaseIterable, Equatable, Sendable {
    /// 自家定版（默认）
    case standard
    /// 圆润：三角放大
    case rounded
    /// 利落：三角收紧
    case squared

    public var displayName: String {
        switch self {
        case .standard: return "定版"
        case .rounded: return "圆润"
        case .squared: return "利落"
        }
    }

    /// 用户泡圆角
    public var bubbleCorner: CGFloat {
        switch self {
        case .standard: return 22
        case .rounded: return 28
        case .squared: return 12
        }
    }

    /// AI 卡圆角（§503 改名注：原 assistantBubbleCorner
    /// ——助手面自 §503 起为全宽底衬卡、圆角与用户泡同
    /// 源同值，沿 0.6.1 双边同圆角口径）
    public var assistantBubbleCorner: CGFloat {
        bubbleCorner
    }

    /// 气泡尾角
    public var bubbleTailCorner: CGFloat {
        switch self {
        case .standard: return 7
        case .rounded: return 10
        case .squared: return 4
        }
    }
}

/// 聊天背景：默认＝现行 chatSurface 原值（standard，
/// 存量 rawValue 三档一字不动、老用户零漂移）；§503
/// 新增六档。色值口径在 Palette 侧解析（纯色档逐值见
/// Palette.chatBackground 注）；图案档只给 kind，渲染
/// 走 ChatBackgroundSurface 单源（聊天页与外观预览同
/// 消费）。抽屉/卡面等共用 chatSurface 的面不跟随任
/// 何一档（各守定版）
public enum ChatBackgroundStyle: String, CaseIterable, Equatable, Sendable {
    /// 跟随主题（§503）：取当前主题整包的背景行
    case theme
    /// 自家定版（默认，与 Palette.chatSurface 同值）
    case standard
    /// 雾灰：比定版深一档的浅灰
    case mist
    /// 石板：再深一档
    case slate
    /// 微信灰（§503）：#EDEDED，微信聊天背景取样值
    /// （WeUI --weui-BG-0）；暗档无取样、沿用雾灰暗值
    case wechatGray
    /// 浅灰（§503）：#F4F4F4，ChatGPT 浅面取样值；
    /// 暗档沿用石板暗值
    case gptGray
    /// 点阵图案（§503）：定版底色＋低对比圆点阵
    case dots
    /// 网格图案（§503）：定版底色＋低对比细网格
    case grid
    /// 斜纹图案（§503）：定版底色＋低对比斜线
    case diagonal

    public var displayName: String {
        switch self {
        case .theme: return "跟随主题"
        case .standard: return "默认"
        case .mist: return "雾灰"
        case .slate: return "石板"
        case .wechatGray: return "微信灰"
        case .gptGray: return "浅灰"
        case .dots: return "点阵"
        case .grid: return "网格"
        case .diagonal: return "斜纹"
        }
    }

    /// 图案档判别：纯色/跟随主题档为 nil
    public var patternKind: ChatBackgroundPattern? {
        switch self {
        case .dots: return .dots
        case .grid: return .grid
        case .diagonal: return .diagonal
        default: return nil
        }
    }
}

/// 背景图案三款（§503）：低对比骨架纹理——渲染口径
/// （间距/线宽/对比上限）由 ChatBackgroundSurface 定
/// 死，图案只改底面质感、正文对比不受影响（纹理色对
/// 底色的对比 ≤1.15，量测钉在 Palette 侧测试）
public enum ChatBackgroundPattern: Equatable, Sendable {
    case dots
    case grid
    case diagonal
}

/// 聊天文字大小五档（§503）：聊天面字阶的覆盖层——
/// 「跟随系统」＝不覆盖（聊天恒读环境 Dynamic Type，
/// 现行行为）；其余四档映射为固定 DynamicTypeSize
/// （App 层映射：小=.small／标准=.large／大=.xLarge
/// ／特大=.xxLarge——DynamicTypeSize 的 .large 即系
/// 统默认正文档，命名差异在映射处注明）。全 App 其
/// 他面不读本档（辖区只限聊天面与其量测链）
public enum ChatTextSizeTier: String, CaseIterable, Equatable, Sendable {
    case system
    case small
    case standard
    case large
    case xlarge

    public var displayName: String {
        switch self {
        case .system: return "跟随系统"
        case .small: return "小"
        case .standard: return "标准"
        case .large: return "大"
        case .xlarge: return "特大"
        }
    }
}
