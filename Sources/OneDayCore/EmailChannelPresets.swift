import Foundation

/// 邮箱服务商预置（特殊批）：主流邮件客户端的通行
/// 形态——选服务商，收发服务器与端口自动带出、用
/// 户只填地址与授权码；预置值带出后仍可改（「其他
/// 邮箱」即全手填）。参数与授权码口径的出处见
/// channels-special-batch-report-20261113 §1.1.2：
/// QQ/163/126 为 16 位授权码（须先在网页版开启
/// IMAP/SMTP 服务），Gmail 为应用专用密码（须先
/// 开两步验证），iCloud 为 App 专用密码。
/// Outlook.com 个人账户已停用密码登录（微软
/// 2024-09-16 起只认 OAuth2），适配器无 OAuth 路，
/// 故不进预置名单（报告 §1.1.4）。
public struct EmailProviderPreset: Equatable, Sendable, Identifiable {
    /// 伴生 preset 标识（credentials 请求体原样带它，
    /// 桥据此定入站信任档：gmail 严格档、其余白名单档）
    public let id: String
    /// 服务商显示名
    public let name: String
    /// 命中的邮箱域名（地址填完自动对位预置）
    public let domains: [String]
    public let imapHost: String
    public let imapPort: Int
    public let smtpHost: String
    public let smtpPort: Int
    /// 密码栏的人话说明：填什么码、去哪生成
    public let credentialHint: String

    public init(
        id: String, name: String, domains: [String],
        imapHost: String, imapPort: Int,
        smtpHost: String, smtpPort: Int,
        credentialHint: String
    ) {
        self.id = id
        self.name = name
        self.domains = domains
        self.imapHost = imapHost
        self.imapPort = imapPort
        self.smtpHost = smtpHost
        self.smtpPort = smtpPort
        self.credentialHint = credentialHint
    }
}

public enum EmailProviderPresets {
    public static let qq = EmailProviderPreset(
        id: "qq", name: "QQ 邮箱",
        domains: ["qq.com", "foxmail.com", "vip.qq.com"],
        imapHost: "imap.qq.com", imapPort: 993,
        smtpHost: "smtp.qq.com", smtpPort: 465,
        credentialHint: "填授权码，不是登录密码。先在网页版 QQ 邮箱"
            + "「设置 → 账户」里开启 IMAP 服务，再生成授权码填进来。"
    )

    public static let netease163 = EmailProviderPreset(
        id: "netease163", name: "163 邮箱",
        domains: ["163.com", "yeah.net"],
        imapHost: "imap.163.com", imapPort: 993,
        smtpHost: "smtp.163.com", smtpPort: 465,
        credentialHint: "填客户端授权码，不是登录密码。先在网页版邮箱"
            + "「设置 → POP3/SMTP/IMAP」里开启服务，生成授权码填进来。"
    )

    public static let netease126 = EmailProviderPreset(
        id: "netease126", name: "126 邮箱",
        domains: ["126.com"],
        imapHost: "imap.126.com", imapPort: 993,
        smtpHost: "smtp.126.com", smtpPort: 465,
        credentialHint: "填客户端授权码，不是登录密码。先在网页版邮箱"
            + "「设置 → POP3/SMTP/IMAP」里开启服务，生成授权码填进来。"
    )

    public static let gmail = EmailProviderPreset(
        id: "gmail", name: "Gmail",
        domains: ["gmail.com", "googlemail.com"],
        imapHost: "imap.gmail.com", imapPort: 993,
        smtpHost: "smtp.gmail.com", smtpPort: 587,
        credentialHint: "填应用专用密码，不是登录密码。先在 Google "
            + "账号里开启两步验证，再生成一个应用专用密码填进来。"
    )

    public static let icloud = EmailProviderPreset(
        id: "icloud", name: "iCloud 邮箱",
        domains: ["icloud.com", "me.com", "mac.com"],
        imapHost: "imap.mail.me.com", imapPort: 993,
        smtpHost: "smtp.mail.me.com", smtpPort: 587,
        credentialHint: "填 App 专用密码，不是 Apple 账号密码。在 "
            + "Apple 账户的「登录与安全」里生成一个填进来。"
    )

    /// 引导页可选的预置（选择器顺序）
    public static let all: [EmailProviderPreset] = [
        qq, netease163, netease126, gmail, icloud,
    ]

    /// 「其他邮箱」：无预置值，服务器全部手填；preset
    /// 标识仍报 custom，桥走白名单信任档
    public static let custom = EmailProviderPreset(
        id: "custom", name: "其他邮箱",
        domains: [],
        imapHost: "", imapPort: 993,
        smtpHost: "", smtpPort: 587,
        credentialHint: "多数邮箱要填服务商给的授权码或应用专用密码，"
            + "不是网页登录密码；在哪生成看你邮箱的设置页。"
    )

    /// 按标识取预置（custom 与未知标识回 custom）
    public static func preset(id: String) -> EmailProviderPreset {
        all.first { $0.id == id } ?? custom
    }

    /// 按邮箱地址域名对位预置：命中回该预置，未命中
    /// 回 nil（呈现层据此决定是否自动切换选择器）
    public static func matching(address: String) -> EmailProviderPreset? {
        let domain = address
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .split(separator: "@")
            .last
            .map(String.init) ?? ""
        guard !domain.isEmpty else { return nil }
        return all.first { $0.domains.contains(domain) }
    }
}
