import Foundation

/// 服务端原始命名的屏上翻译层（0.3.7，DESIGN-V4 §22.3
/// 红线「数据先翻译」＋0.3.7 待裁 4 已裁口径）：平台名/
/// 状态词/类别名先经本表译成人话再上屏，原始标识不许
/// 直出。本表是全部翻译的单一事实源（总览/网关/设置/
/// 密钥/技能各页共用），单测把守：已知值逐项对表、未
/// 知类别回落「其他」、未知状态回落「未知」。
public enum ServerLabels {
    // MARK: - 平台

    /// 平台 key → 人话名：内部标识（api_server 等）译
    /// 成通称；品牌专名（Telegram/Discord 等）无中文
    /// 通称、原样保留（卡 11 口径：有通称用通称、无
    /// 映射才原文——品牌名是内容名不是内部标识）。
    public static func platformName(
        _ key: String, locale: Locale = AppLocale.uiLocale
    ) -> String {
        switch key.lowercased() {
        case "api_server", "api": return L10n.string("API 接口", locale: locale)
        case "dashboard", "web": return L10n.string("控制台", locale: locale)
        case "cli": return L10n.string("命令行", locale: locale)
        case "cron", "cron_job", "scheduler": return L10n.string("定时任务", locale: locale)
        default: return key
        }
    }

    // MARK: - 状态词

    /// 平台连接状态 → 人话词（connected 不许再原文上屏）
    public static func platformState(
        _ state: String?, locale: Locale = AppLocale.uiLocale
    ) -> String {
        switch state?.lowercased() {
        case "connected": return L10n.string("已连接", locale: locale)
        case "disconnected": return L10n.string("未连接", locale: locale)
        case "running": return L10n.string("运行中", locale: locale)
        case "stopped": return L10n.string("已停止", locale: locale)
        case "error", "failed": return L10n.string("异常", locale: locale)
        case "degraded", "warning": return L10n.string("降级", locale: locale)
        case "restarting": return L10n.string("重启中", locale: locale)
        case "ok", "ready": return L10n.string("正常", locale: locale)
        default: return L10n.string("未知", locale: locale)
        }
    }

    /// 网关状态 → 人话词（总览/网关/设置三处同口径）
    public static func gatewayState(
        _ state: String?, running: Bool?,
        locale: Locale = AppLocale.uiLocale
    ) -> String {
        switch state?.lowercased() {
        case "running": return L10n.string("运行中", locale: locale)
        case "stopped": return L10n.string("已停止", locale: locale)
        case "error", "failed": return L10n.string("异常", locale: locale)
        default: return running == true
            ? L10n.string("运行中", locale: locale)
            : L10n.string("未运行", locale: locale)
        }
    }

    // MARK: - 类别（密钥/技能分组，待裁 4 已裁）

    /// 类别回落组名：未知/缺失类别一律落此组，不许直
    /// 出原始英文（单测把守）
    public static var otherCategory: String {
        otherCategory(locale: AppLocale.uiLocale)
    }

    /// 回落组名的目录取词形（0.42.1 国际化长尾包）
    public static func otherCategory(locale: Locale) -> String {
        L10n.string("其他", locale: locale)
    }

    /// 服务端类别原始值 → 人话组名。映射按语义簇建：
    /// 密钥目录（模型/搜索/平台…）与技能分类（研究/
    /// 开发/数据…）共用一表，未知值回落「其他」。
    public static func categoryLabel(
        _ raw: String?, locale: Locale = AppLocale.uiLocale
    ) -> String {
        guard let raw else { return otherCategory(locale: locale) }
        switch raw.trimmingCharacters(in: .whitespaces).lowercased() {
        case "llm", "model", "models", "ai", "ai_models":
            return L10n.string("模型", locale: locale)
        case "search", "web", "web_search":
            return L10n.string("搜索", locale: locale)
        case "messaging", "platform", "platforms", "chat",
             "communication", "social":
            return L10n.string("消息平台", locale: locale)
        case "tool", "tools", "utility", "utilities":
            return L10n.string("工具", locale: locale)
        case "core", "system", "general", "builtin", "built-in":
            return L10n.string("系统", locale: locale)
        case "media", "image", "images", "audio", "video",
             "multimedia":
            return L10n.string("媒体", locale: locale)
        case "memory", "storage", "database", "db", "data_storage":
            return L10n.string("存储与记忆", locale: locale)
        case "auth", "security", "credentials":
            return L10n.string("安全", locale: locale)
        case "research", "analysis", "analytics":
            return L10n.string("研究", locale: locale)
        case "dev", "development", "coding", "code",
             "software", "programming":
            return L10n.string("开发", locale: locale)
        case "data", "data_science", "ml", "machine_learning":
            return L10n.string("数据", locale: locale)
        case "productivity", "workflow", "automation":
            return L10n.string("效率", locale: locale)
        case "writing", "content", "docs", "documentation":
            return L10n.string("写作", locale: locale)
        default:
            return otherCategory(locale: locale)
        }
    }

    /// 按类别分组：组按组名排序、「其他」恒垫底；组内
    /// 保持输入顺序（调用方的排序口径不被打乱）。
    public static func grouped<T>(
        _ items: [T], category: (T) -> String?,
        locale: Locale = AppLocale.uiLocale
    ) -> [(label: String, items: [T])] {
        var order: [String] = []
        var buckets: [String: [T]] = [:]
        for item in items {
            let label = categoryLabel(category(item), locale: locale)
            if buckets[label] == nil {
                order.append(label)
                buckets[label] = []
            }
            buckets[label]?.append(item)
        }
        let other = otherCategory(locale: locale)
        let sorted = order.sorted { a, b in
            if a == other { return false }
            if b == other { return true }
            return a < b
        }
        return sorted.map { (label: $0, items: buckets[$0] ?? []) }
    }

    // MARK: - 档案名

    /// 档案（profile）名翻译（0.3.8，fixlist 第 7 条）：
    /// 默认档案原始名 "default" 不上屏、写「默认档案」；
    /// 其余档案名是用户自取的名字（内容），原样呈现
    public static func profileName(
        _ raw: String?, locale: Locale = AppLocale.uiLocale
    ) -> String {
        guard let raw, !raw.isEmpty else {
            return L10n.string("默认档案", locale: locale)
        }
        return raw == "default"
            ? L10n.string("默认档案", locale: locale) : raw
    }

    // MARK: - 文案可见性

    /// 服务端 description 的上屏口径（卡 9/13 点名）：
    /// 英文原文原样上屏是半翻译状态——有中文才显示，
    /// 纯英文说明隐去（内容标识如键名/技能名不受此限）。
    public static func isChineseText(_ text: String) -> Bool {
        text.unicodeScalars.contains {
            (0x4E00...0x9FFF).contains(Int($0.value))
        }
    }
}
