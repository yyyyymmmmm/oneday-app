import OneDayCore
import XCTest

/// 失败分型（0.20.0，用户 23:35 真机点名「词与事实
/// 打架」）：URLError 分型表——瞬断类归 transient-
/// Network（文案只提示重试、不许让人查地址），只有
/// 主机名解析失败才归地址档。发送链的自动重试资格
/// 只认 isTransient。
final class HermesErrorTests: XCTestCase {

    func testTransientURLErrorCodesClassifyAsTransient() {
        let codes: [URLError.Code] = [
            .timedOut, .networkConnectionLost,
            .notConnectedToInternet, .cannotConnectToHost,
            .dataNotAllowed, .internationalRoamingOff,
        ]
        for code in codes {
            let error = HermesError.fromURLError(URLError(code), locale: Locale(identifier: "zh-Hans"))
            XCTAssertTrue(
                error.isTransient,
                "\(code.rawValue) 应归瞬断档，实际 \(error)"
            )
        }
    }

    func testHostResolutionFailuresStayInAddressBucket() {
        let codes: [URLError.Code] = [.cannotFindHost, .dnsLookupFailed]
        for code in codes {
            let error = HermesError.fromURLError(URLError(code), locale: Locale(identifier: "zh-Hans"))
            XCTAssertFalse(error.isTransient)
            guard case .unreachable = error else {
                return XCTFail("\(code.rawValue) 应归 unreachable，实际 \(error)")
            }
        }
    }

    func testOtherURLErrorCodesFallBackToGenericUnreachable() {
        let error = HermesError.fromURLError(URLError(.badURL), locale: Locale(identifier: "zh-Hans"))
        XCTAssertFalse(error.isTransient)
        XCTAssertEqual(error.userMessage(locale: Locale(identifier: "zh-Hans")).contains("网络错误"), true)
    }

    func testTransientCopyNeverBlamesAddress() {
        let message = HermesError.transientNetwork.userMessage(locale: Locale(identifier: "zh-Hans"))
        XCTAssertFalse(message.contains("检查地址"))
        XCTAssertFalse(message.contains("服务器是否在线"))
    }

    func testNonTransientErrorsAreNotRetryable() {
        XCTAssertFalse(HermesError.unreachable("无法建立连接").isTransient)
        XCTAssertFalse(HermesError.apiKeyRejected.isTransient)
        XCTAssertFalse(HermesError.sessionExpired.isTransient)
        XCTAssertFalse(HermesError.cancelled.isTransient)
    }

    /// 「对象不存在」分型（§217）：只有 unexpected-
    /// Status 404 认领——点开残留行导入会话撞它走
    /// 清残留＋人话提示；其余状态码与失败族不许误
    /// 认（500 是服务器出错、不是会话没了）
    func testSessionNotFoundClassification() {
        XCTAssertTrue(
            HermesError.unexpectedStatus(
                endpoint: "会话消息", status: 404
            ).isSessionNotFound
        )
        XCTAssertFalse(
            HermesError.unexpectedStatus(
                endpoint: "会话消息", status: 500
            ).isSessionNotFound
        )
        XCTAssertFalse(
            HermesError.unexpectedStatus(
                endpoint: "会话消息", status: 409
            ).isSessionNotFound
        )
        XCTAssertFalse(HermesError.transientNetwork.isSessionNotFound)
        XCTAssertFalse(HermesError.sessionBusy.isSessionNotFound)
        XCTAssertFalse(HermesError.decodingFailed(endpoint: "会话消息").isSessionNotFound)
    }
}
