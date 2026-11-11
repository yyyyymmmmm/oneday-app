import Foundation

/// 文件打开失败后「让智能体重新发」的预填（§129，
/// 诊断 file-ref-404-diagnosis-20261111 §4.1.5）：
/// 404 失败页除重试外给一条回到对话的出路——把
/// 「打不开＋原路径＋请重新交付」拼成一条草稿预
/// 填进输入舱，用户点发送为准、本组件不代发（与
/// §123 FeedDiscussPrefill 同制：Core 只拼装纯文
/// 本，落点与发送都归宿主）。话术三要点缺一不可：
/// 说清哪个文件打不开、报出它原来指向的路径（让
/// 智能体能对账自己写错/没写成什么）、要求确认
/// 真存在后再发且路径单独成行（与成牌口径呼应，
/// 重发回来天然够格成牌）。
public enum FileResendPrefill {
    public static func make(
        name: String, path: String,
        locale: Locale = AppLocale.uiLocale
    ) -> String {
        let headline = L10n.format(
            "这个文件我打不开，服务器上没有找到：《%@》",
            locale: locale, name
        )
        let origin = L10n.format(
            "它原来的路径是：%@", locale: locale, path
        )
        let ask = L10n.string(
            "请把文件重新保存好，确认真的存在后，再把正确路径单独写一行发给我。",
            locale: locale
        )
        return [headline, origin, ask].joined(separator: "\n")
    }
}
