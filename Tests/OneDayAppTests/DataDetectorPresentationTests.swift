import OneDayCore
import OneDayDesign
import SwiftUI
import UIKit
import XCTest
@testable import OneDayApp

/// §265（换代包 5·T4）数据探测真呈现路径验收：
/// 探针报告 gen5-t4-probe-20261115 §5.5 明令——
/// T4 验收不许只用纯字符串单测口径（NSDataDetec-
/// tor 对原文），必须经生产呈现路径（Markdown-
/// Text→SelectableInlineText.build→TextShaping
/// 整形→SelectableTextView 入窗）验检测仍准：
/// 整形会在数字串内部插 U+2060（WORD JOINER），
/// 探测命中范围/载荷须在整形后的真文本上成立。
///
/// 断言面：
/// 1. 电话/URL/邮箱在真呈现路径下成 .link 属性，
///    载荷逐字为 tel:/https:/mailto: 规范形态，
///    覆盖子串剥 U+2060 后与原文一致；
/// 2. 负语料零命中：长订单号、金额 ¥1,299.00、
///    版本号不被链化（.all 的金额误报面在开集
///    [.phoneNumber, .link] 下不存在）；
/// 3. 出口：Coordinator.shouldInteractWith 对
///    tel/http/mailto 一律转发环境 openURL 且
///    return false（系统不直开），与手写链接同口。
@MainActor
final class DataDetectorPresentationTests: XCTestCase {

    private var window: UIWindow!

    override func tearDown() async throws {
        window?.rootViewController = nil
        window?.isHidden = true
        window = nil
        try await super.tearDown()
    }

    private func spinRunLoop(seconds: TimeInterval) {
        let exp = expectation(description: "spin \(seconds)s")
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
            exp.fulfill()
        }
        wait(for: [exp], timeout: seconds + 5)
    }

    private func host<V: View>(_ view: V) {
        let host = UIHostingController(rootView: view)
        window = UIWindow(
            frame: CGRect(x: 0, y: 0, width: 402, height: 874)
        )
        window.rootViewController = host
        window.makeKeyAndVisible()
        window.layoutIfNeeded()
        spinRunLoop(seconds: 0.6)
        window.layoutIfNeeded()
    }

    private func textViews() -> [UITextView] {
        var out: [UITextView] = []
        func walk(_ view: UIView) {
            if let textView = view as? UITextView {
                out.append(textView)
            }
            for sub in view.subviews { walk(sub) }
        }
        if let root = window.rootViewController?.view {
            walk(root)
        }
        return out
    }

    /// 枚举全部承载文本视图的 .link 属性：返回
    /// （载荷 URL, 覆盖子串剥 U+2060 后）对
    private func detectedLinks() -> [(url: String, text: String)] {
        var out: [(String, String)] = []
        for textView in textViews() {
            guard let attributed = textView.attributedText
            else { continue }
            attributed.enumerateAttribute(
                .link,
                in: NSRange(
                    location: 0, length: attributed.length
                )
            ) { value, range, _ in
                guard let url = value as? URL else { return }
                let raw = attributed
                    .attributedSubstring(from: range).string
                let stripped = raw.replacingOccurrences(
                    of: "\u{2060}", with: ""
                )
                out.append((url.absoluteString, stripped))
            }
        }
        return out.map { (url: $0.0, text: $0.1) }
    }

    /// 探测是入窗后异步落的：轮询到命中出现或超时
    private func awaitLinks(
        timeout: TimeInterval = 4
    ) -> [(url: String, text: String)] {
        var links = detectedLinks()
        var waited: TimeInterval = 0
        while links.isEmpty, waited < timeout {
            spinRunLoop(seconds: 0.25)
            window.layoutIfNeeded()
            waited += 0.25
            links = detectedLinks()
        }
        return links
    }

    private let corpus =
        "值班电话 13800138000，状态页 "
        + "https://example.org/status ，邮箱 "
        + "oncall@example.org。订单号 "
        + "20261115093012345678，金额 ¥1,299.00，"
        + "版本 0.50.48 照常。"

    /// 助手散文真呈现路径（MarkdownText 全链）
    func testDetectorsSurviveAssistantPresentationPath() {
        host(
            MarkdownText(corpus)
                .frame(width: 320, alignment: .leading)
                .padding()
        )
        let views = textViews()
        XCTAssertEqual(views.count, 1, "散文段应恰一台承载文本视图")
        XCTAssertEqual(
            views.first?.dataDetectorTypes,
            UIDataDetectorTypes([.phoneNumber, .link]),
            "承载视图探测开集应为 [.phoneNumber, .link]"
        )
        let links = awaitLinks()
        print("T4 links=\(links)")
        XCTAssertTrue(
            links.contains {
                $0.url == "tel:13800138000"
                    && $0.text == "13800138000"
            },
            "整形后电话应成 tel: 链接且覆盖原文号码；实得 \(links)"
        )
        XCTAssertTrue(
            links.contains {
                $0.url == "https://example.org/status"
            },
            "URL 应成 https 链接；实得 \(links)"
        )
        XCTAssertTrue(
            links.contains {
                $0.url == "mailto:oncall@example.org"
            },
            "邮箱应成 mailto 链接；实得 \(links)"
        )
        XCTAssertFalse(
            links.contains {
                $0.text.contains("20261115093012345678")
            },
            "长订单号不许被链化；实得 \(links)"
        )
        XCTAssertFalse(
            links.contains { $0.text.contains("1,299") },
            "金额不许被链化；实得 \(links)"
        )
    }

    /// 用户纯文本真呈现路径（ChatView 调用点同构：
    /// prettyWrapDocument 整形→.plain 段→同一
    /// SelectableInlineText）
    func testDetectorsSurviveUserPlainPath() {
        host(
            SelectableInlineText(
                paragraphs: [
                    .plain(
                        TextShaping.prettyWrapDocument(corpus)
                    )
                ],
                textStyle: .callout,
                foreground: Palette.userBubbleText
            )
            .frame(width: 320, alignment: .leading)
            .padding()
        )
        let links = awaitLinks()
        print("T4 user links=\(links)")
        XCTAssertTrue(
            links.contains {
                $0.url == "tel:13800138000"
                    && $0.text == "13800138000"
            },
            "用户行整形后电话应成 tel: 链接；实得 \(links)"
        )
        XCTAssertFalse(
            links.contains { $0.text.contains("1,299") },
            "金额不许被链化；实得 \(links)"
        )
    }

    /// 出口：三类 URL 一律转发 openURL＋return
    /// false（与手写链接同一出口、系统不直开）
    func testCoordinatorRoutesAllLinkKindsToOpenURL() {
        var opened: [URL] = []
        let action = OpenURLAction { url in
            opened.append(url)
            return .handled
        }
        let coordinator = SelectableTextRepresentable.Coordinator(
            onSelectionChange: nil, openURL: action
        )
        let textView = UITextView()
        for raw in [
            "tel:13800138000",
            "https://example.org/status",
            "mailto:oncall@example.org",
        ] {
            let url = URL(string: raw)!
            let allowed = coordinator.textView(
                textView,
                shouldInteractWith: url,
                in: NSRange(location: 0, length: 1),
                interaction: .invokeDefaultAction
            )
            XCTAssertFalse(
                allowed, "\(raw) 不许系统直开"
            )
        }
        XCTAssertEqual(
            opened.map(\.absoluteString),
            [
                "tel:13800138000",
                "https://example.org/status",
                "mailto:oncall@example.org",
            ]
        )
    }
}
