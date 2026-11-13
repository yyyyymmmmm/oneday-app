import XCTest
@testable import OneDayCore

/// 邮箱服务商预置（特殊批）：参数与报告 §1.1.2 的
/// 核实表逐项对位；域名对位与自定义回落不许错位
final class EmailChannelPresetsTests: XCTestCase {

    func testPresetServerValues() {
        let qq = EmailProviderPresets.qq
        XCTAssertEqual(qq.imapHost, "imap.qq.com")
        XCTAssertEqual(qq.imapPort, 993)
        XCTAssertEqual(qq.smtpHost, "smtp.qq.com")
        XCTAssertEqual(qq.smtpPort, 465)

        let n163 = EmailProviderPresets.netease163
        XCTAssertEqual(n163.imapHost, "imap.163.com")
        XCTAssertEqual(n163.imapPort, 993)
        XCTAssertEqual(n163.smtpHost, "smtp.163.com")
        XCTAssertEqual(n163.smtpPort, 465)

        let n126 = EmailProviderPresets.netease126
        XCTAssertEqual(n126.imapHost, "imap.126.com")
        XCTAssertEqual(n126.smtpHost, "smtp.126.com")
        XCTAssertEqual(n126.smtpPort, 465)

        let gmail = EmailProviderPresets.gmail
        XCTAssertEqual(gmail.imapHost, "imap.gmail.com")
        XCTAssertEqual(gmail.imapPort, 993)
        XCTAssertEqual(gmail.smtpHost, "smtp.gmail.com")
        XCTAssertEqual(gmail.smtpPort, 587)

        let icloud = EmailProviderPresets.icloud
        XCTAssertEqual(icloud.imapHost, "imap.mail.me.com")
        XCTAssertEqual(icloud.imapPort, 993)
        XCTAssertEqual(icloud.smtpHost, "smtp.mail.me.com")
        XCTAssertEqual(icloud.smtpPort, 587)
    }

    func testPresetIDsAreStableBridgeValues() {
        XCTAssertEqual(
            EmailProviderPresets.all.map(\.id),
            ["qq", "netease163", "netease126", "gmail", "icloud"])
        XCTAssertEqual(EmailProviderPresets.custom.id, "custom")
        XCTAssertEqual(
            EmailProviderPresets.preset(id: "gmail").id, "gmail")
        XCTAssertEqual(
            EmailProviderPresets.preset(id: "nope").id, "custom")
    }

    func testDomainMatching() {
        XCTAssertEqual(
            EmailProviderPresets.matching(
                address: "someone@qq.com")?.id, "qq")
        XCTAssertEqual(
            EmailProviderPresets.matching(
                address: "someone@foxmail.com")?.id, "qq")
        XCTAssertEqual(
            EmailProviderPresets.matching(
                address: "Someone@163.COM")?.id, "netease163")
        XCTAssertEqual(
            EmailProviderPresets.matching(
                address: "a@126.com")?.id, "netease126")
        XCTAssertEqual(
            EmailProviderPresets.matching(
                address: "a@gmail.com")?.id, "gmail")
        XCTAssertEqual(
            EmailProviderPresets.matching(
                address: "a@icloud.com")?.id, "icloud")
        XCTAssertEqual(
            EmailProviderPresets.matching(
                address: "a@me.com")?.id, "icloud")
    }

    func testDomainMatchingMisses() {
        // Outlook 不进预置（密码登录已被微软停用，
        // 报告 §1.1.4）：域名不许命中任何预置
        XCTAssertNil(
            EmailProviderPresets.matching(
                address: "a@outlook.com"))
        XCTAssertNil(
            EmailProviderPresets.matching(
                address: "a@hotmail.com"))
        XCTAssertNil(
            EmailProviderPresets.matching(
                address: "not-an-address"))
        XCTAssertNil(
            EmailProviderPresets.matching(address: ""))
    }

    func testEveryPresetHasCredentialHint() {
        // 每家口径都必须说清填的是授权码/专用密码而
        // 非登录密码（用户最容易填错的一项）
        for preset in EmailProviderPresets.all
            + [EmailProviderPresets.custom] {
            XCTAssertFalse(
                preset.credentialHint.isEmpty, preset.id)
            XCTAssertTrue(
                preset.credentialHint.contains("授权码")
                    || preset.credentialHint.contains("专用密码"),
                preset.id)
        }
    }
}
