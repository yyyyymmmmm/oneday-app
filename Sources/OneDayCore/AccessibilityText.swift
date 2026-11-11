import Foundation

/// 无障碍呈现文案拼装（0.43.0 无障碍专项，台账
/// A11Y-V2）：VoiceOver 标签是「读出来的一句话」，
/// 拼装规则（分段、连接、缺省回落）在此单点成型
/// 并钉测，视图层只喂数据。取词走 L10n、语言钉
/// AppLocale，与全仓呈现串同口径。
public enum A11yText {
    /// 图片的最低文本等价（V2）：有文件名用文件名
    /// （服务端图/文件图——文件名是该图唯一可凭的
    /// 身份），没有就只报「图片」。不编造内容描述：
    /// 助手图/服务端图的自动描述生成是产品决策
    /// （走查 §7 B2 策略先行），未定案前宁缺毋假
    public static func imageLabel(
        fileName: String?, locale: Locale = AppLocale.uiLocale
    ) -> String {
        let base = L10n.string("图片", locale: locale)
        guard let fileName, !fileName.isEmpty else { return base }
        return L10n.format("图片，%@", locale: locale, fileName)
    }

    /// 图片的最低文本等价·本地图（用户刚拍/刚选的
    /// 图只有发送时刻可凭）：「图片，14:32」——时
    /// 刻口径走 DisplayDate.timeText，与界面时间戳
    /// 同源同语言
    public static func imageLabel(
        sentAt: Date, calendar: Calendar = .current,
        locale: Locale = AppLocale.uiLocale
    ) -> String {
        let time = DisplayDate.timeText(
            of: sentAt, calendar: calendar, locale: locale
        )
        return L10n.format("图片，%@", locale: locale, time)
    }
}
