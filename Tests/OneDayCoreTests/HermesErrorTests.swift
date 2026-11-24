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
            .cannotConnectToHost, .internationalRoamingOff,
        ]
        for code in codes {
            let error = HermesError.fromURLError(URLError(code), locale: Locale(identifier: "zh-Hans"))
            XCTAssertTrue(
                error.isTransient,
                "\(code.rawValue) 应归瞬断档，实际 \(error)"
            )
        }
    }

    /// 确定未发出分型（§414 增补，断网发送态规格
    /// 5.2）：系统报无网/蜂窝被禁是设备侧确定事实
    /// ——请求不可能出设备，拆出 transientNetwork
    /// 单立 notSentOffline：不许 isTransient（提交
    /// 段不许按瞬态重试后判结果未知），大类仍归
    /// network；真未知三码（超时/连接丢失/连不上
    /// 主机）保持瞬态不变（上表把守）
    func testDefinitelyUnsentCodesClassifyAsNotSentOffline() {
        let codes: [URLError.Code] = [
            .notConnectedToInternet, .dataNotAllowed,
        ]
        for code in codes {
            let error = HermesError.fromURLError(URLError(code), locale: Locale(identifier: "zh-Hans"))
            guard case .notSentOffline = error else {
                return XCTFail("\(code.rawValue) 应归未发出档，实际 \(error)")
            }
            XCTAssertFalse(
                error.isTransient,
                "\(code.rawValue) 不许归瞬态（会把没出设备的请求判成结果未知）"
            )
            XCTAssertEqual(error.category, .network)
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

    /// 「对象不存在」分型（§223）：只有 unexpected-
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
