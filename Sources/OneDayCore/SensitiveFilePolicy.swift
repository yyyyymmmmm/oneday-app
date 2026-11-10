import Foundation

/// 敏感文件边界（0.36.31，文件页 v2 规格 §4.6）：系统
/// 文件浏览器（FilesBrowserView）里凭据类文件的处置单
/// 一事实源——行可见，但禁预览、禁下载、禁删除，点按
/// 只给一句说明。现行缺口：浏览器能把 auth.json 下载
/// 到手机，等于凭据外带通道，与单钥原则冲突，本版堵
/// 上。名单纪律（规格 §4.6）：与交付物面的 deny 名单
/// 合并维护在本文件——DeliverablesView 的根散文件排除
/// 名单直接引用 protectedNames，禁两处各写一份。
public enum SensitiveFilePolicy {
    /// 受保护文件名（原样大小写集）：服务端自身的配置/
    /// 人格/鉴权文件。交付物面根散文件排除名单与浏览器
    /// 敏感判定共用此集（判定走小写比对，显示无关）。
    public static let protectedNames: Set<String> = [
        "config.yaml", ".env", "auth.json",
        "SOUL.md", "AGENTS.md", "USER.md", "MEMORY.md", "IDENTITY.md",
    ]

    private static let protectedLower: Set<String> =
        Set(protectedNames.map { $0.lowercased() })

    /// 敏感扩展名：私钥/证书类，整扩展命中即敏感
    public static let sensitiveExtensions: Set<String> = [
        "pem", "key", "p12", "keystore",
    ]

    /// 敏感词元（按非字母数字切分后整词比对）：key 走整
    /// 词是为防 monkey/keyboard 这类含子串的正常文件名
    /// 被误伤；credential/secret/token 另有子串兜底（黏
    /// 连命名 mytoken 一类照样命中）
    private static let sensitiveTokens: Set<String> = [
        "credential", "credentials", "secret", "secrets",
        "token", "tokens", "key", "keys", "password", "passwd",
    ]

    private static let sensitiveSubstrings: [String] = [
        "credential", "secret", "token",
    ]

    /// 敏感判定：入参是文件名（非路径）
    public static func isSensitive(fileName name: String) -> Bool {
        let lower = name.lowercased()
        if protectedLower.contains(lower) { return true }
        // .env 本体与 .env.local/.env.production 变体
        if lower == ".env" || lower.hasPrefix(".env.") { return true }
        let ext = (lower as NSString).pathExtension
        if sensitiveExtensions.contains(ext) { return true }
        for substring in sensitiveSubstrings
        where lower.contains(substring) {
            return true
        }
        let tokens = lower
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
        return tokens.contains { sensitiveTokens.contains($0) }
    }

    /// 点按敏感行时给用户的一句说明（规格 §4.6 原文口径）
    public static let explanation =
        "这是智能体的凭据文件，只能在服务器上管理。"
}
