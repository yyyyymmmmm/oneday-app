import XCTest
@testable import OneDayCore

/// 引导连接四步与失败分型（引导线预制）：分型只认步
/// 位＋错误种类、不靠文案猜；成功面摘要只拼实测有值
/// 的项、取不到整项消失；建议条三条与图标同序。
final class OnboardingTests: XCTestCase {

    private let zh = Locale(identifier: "zh-Hans")

    // MARK: - 四步齐全与顺序

    func testStepsAreFourInOrder() {
        XCTAssertEqual(
            OnboardingStep.allCases,
            [.addressFormat, .serverReachable, .credentialValid, .serviceInfo]
        )
    }

    // MARK: - 失败分型：错误种类映射

    func testClassifyInvalidAddress() {
        let failure = OnboardingFailure.classify(
            step: .addressFormat, error: HermesError.invalidServerAddress
        )
        XCTAssertEqual(failure.kind, .invalidAddress)
        XCTAssertEqual(failure.step, .addressFormat)
    }

    func testClassifyUnreachableFamily() {
        for error in [
            HermesError.unreachable("boom"),
            .transientNetwork,
            .healthCheckFailed(status: 503),
        ] {
            let failure = OnboardingFailure.classify(
                step: .serverReachable, error: error
            )
            XCTAssertEqual(failure.kind, .unreachable, "\(error)")
        }
    }

    func testClassifyCredentialRejectedFamily() {
        XCTAssertEqual(
            OnboardingFailure.classify(
                step: .credentialValid, error: HermesError.loginRejected
            ).kind,
            .credentialRejected
        )
        XCTAssertEqual(
            OnboardingFailure.classify(
                step: .credentialValid, error: HermesError.apiKeyRejected
            ).kind,
            .credentialRejected
        )
    }

    func testClassifyUnknownFallsToOther() {
        XCTAssertEqual(
            OnboardingFailure.classify(
                step: .serviceInfo,
                error: HermesError.unexpectedStatus(
                    endpoint: "x", status: 500
                )
            ).kind,
            .other
        )
        XCTAssertEqual(
            OnboardingFailure.classify(
                step: .serviceInfo, error: HermesError.cancelled
            ).kind,
            .other
        )
        struct Weird: Error {}
        XCTAssertEqual(
            OnboardingFailure.classify(step: .serviceInfo, error: Weird()).kind,
            .other
        )
    }

    /// 已是 OnboardingFailure 的错误直通（密码链在
    /// serviceInfo 步自抛 keyUnavailable，不被二次分类
    /// 洗成 other）
    func testClassifyPassesThroughOnboardingFailure() {
        let original = OnboardingFailure(
            step: .serviceInfo, kind: .keyUnavailable
        )
        let classified = OnboardingFailure.classify(
            step: .credentialValid, error: original
        )
        XCTAssertEqual(classified, original)
    }

    /// 五型的标题互不相同（失败面按型分面、不许五型一面）
    func testFailureHeadlinesDifferPerKind() {
        let kinds: [OnboardingFailureKind] = [
            .invalidAddress, .unreachable, .credentialRejected,
            .keyUnavailable, .other,
        ]
        let headlines = kinds.map {
            OnboardingFailure(step: .serviceInfo, kind: $0)
                .headline(locale: zh)
        }
        XCTAssertEqual(Set(headlines).count, kinds.count)
        for headline in headlines {
            XCTAssertFalse(headline.isEmpty)
        }
    }

    // MARK: - 成功面摘要：只拼有值的项

    func testSummaryLineFull() {
        let info = ConnectionServiceInfo(
            host: "hermes.example.com", hermesVersion: "0.23.0",
            modelCount: 12, latencyMs: 82
        )
        XCTAssertEqual(
            info.summaryLine(locale: zh),
            "Hermes 0.23.0 · 12 个可用模型 · 延迟 82 ms"
        )
    }

    /// 密钥链没有模型数：整项消失、不留空位不编造
    func testSummaryLineOmitsMissingModelCount() {
        let info = ConnectionServiceInfo(
            host: "hermes.example.com", hermesVersion: "0.23.0",
            modelCount: nil, latencyMs: 82
        )
        XCTAssertEqual(
            info.summaryLine(locale: zh),
            "Hermes 0.23.0 · 延迟 82 ms"
        )
    }

    func testSummaryLineOmitsMissingVersionAndLatency() {
        let info = ConnectionServiceInfo(
            host: "hermes.example.com", hermesVersion: nil,
            modelCount: 3, latencyMs: nil
        )
        XCTAssertEqual(info.summaryLine(locale: zh), "3 个可用模型")
    }

    func testSummaryLineAllMissingIsEmpty() {
        let info = ConnectionServiceInfo(
            host: "hermes.example.com", hermesVersion: nil,
            modelCount: nil, latencyMs: nil
        )
        XCTAssertEqual(info.summaryLine(locale: zh), "")
    }

    /// 空版本字符串按缺失处理（不许拼出「Hermes 」空壳）
    func testSummaryLineTreatsEmptyVersionAsMissing() {
        let info = ConnectionServiceInfo(
            host: "hermes.example.com", hermesVersion: "",
            modelCount: nil, latencyMs: 10
        )
        XCTAssertEqual(info.summaryLine(locale: zh), "延迟 10 ms")
    }

    // MARK: - 建议条

    func testSuggestionsThreeWithSymbols() {
        XCTAssertEqual(EmptyChatSuggestions.texts.count, 3)
        XCTAssertEqual(
            EmptyChatSuggestions.symbols.count,
            EmptyChatSuggestions.texts.count
        )
        for text in EmptyChatSuggestions.texts {
            XCTAssertFalse(text.isEmpty)
        }
    }
}
