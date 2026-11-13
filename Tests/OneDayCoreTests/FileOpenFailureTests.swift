import XCTest
@testable import OneDayCore

/// 文件打开失败五分分类（§121 题二 b）：分类锚点
/// ＝Hermes files.py 实证状态码（404/413/400/403）
/// 与 HermesError 既有分型（瞬断档＝超时、登录态
/// 与连不上＝服务不可用）
final class FileOpenFailureTests: XCTestCase {

    func testClassifyByStatusCode() {
        XCTAssertEqual(
            FileOpenFailure.classify(
                error: .unexpectedStatus(
                    endpoint: "文件下载", status: 404
                )
            ),
            .notFound
        )
        XCTAssertEqual(
            FileOpenFailure.classify(
                error: .unexpectedStatus(
                    endpoint: "文件下载", status: 413
                )
            ),
            .tooLarge
        )
        XCTAssertEqual(
            FileOpenFailure.classify(
                error: .unexpectedStatus(
                    endpoint: "文件下载", status: 400
                )
            ),
            .invalidPath
        )
        // 403 是服务器拒绝（敏感路径），不许混进路径
        // 无效——文案与归因都是两回事
        XCTAssertEqual(
            FileOpenFailure.classify(
                error: .unexpectedStatus(
                    endpoint: "文件下载", status: 403
                )
            ),
            .forbidden
        )
        XCTAssertEqual(
            FileOpenFailure.classify(
                error: .unexpectedStatus(
                    endpoint: "文件下载", status: 503
                )
            ),
            .serviceUnavailable
        )
        XCTAssertEqual(
            FileOpenFailure.classify(
                error: .unexpectedStatus(
                    endpoint: "文件下载", status: 401
                )
            ),
            .serviceUnavailable
        )
        // 未列名状态码不冒充已分类
        XCTAssertEqual(
            FileOpenFailure.classify(
                error: .unexpectedStatus(
                    endpoint: "文件下载", status: 418
                )
            ),
            .other
        )
    }

    func testClassifyByErrorKind() {
        XCTAssertEqual(
            FileOpenFailure.classify(error: .transientNetwork),
            .timeout
        )
        XCTAssertEqual(
            FileOpenFailure.classify(
                error: .unreachable("无法建立连接")
            ),
            .serviceUnavailable
        )
        XCTAssertEqual(
            FileOpenFailure.classify(error: .sessionExpired),
            .serviceUnavailable
        )
        XCTAssertEqual(
            FileOpenFailure.classify(error: .cancelled),
            .other
        )
        // sessionBusy 是删会话围栏信号，文件打开面实际
        // 不会收到；归 other 兜底，不冒充服务不可用
        XCTAssertEqual(
            FileOpenFailure.classify(error: .sessionBusy),
            .other
        )
        XCTAssertEqual(
            FileOpenFailure.classify(
                error: .decodingFailed(endpoint: "文件下载")
            ),
            .other
        )
    }

    func testInvalidPathPrecheck() {
        XCTAssertTrue(FileOpenFailure.isInvalidPath(""))
        XCTAssertTrue(FileOpenFailure.isInvalidPath("   "))
        XCTAssertFalse(
            FileOpenFailure.isInvalidPath(
                "/opt/data/attachments/GestaltX_1.0.4.ipa"
            )
        )
        XCTAssertFalse(
            FileOpenFailure.isInvalidPath("attachments/a.zip")
        )
    }

    /// 五分文案互不相同、不许两档共用一句兜底（人
    /// 话口径：用户看文案能分出原因）
    func testFailureMessagesAreDistinct() {
        let messages = FileOpenFailure.allCases.map {
            $0.message(locale: Locale(identifier: "zh-Hans"))
        }
        XCTAssertEqual(Set(messages).count, messages.count)
        XCTAssertTrue(
            messages.allSatisfy { !$0.isEmpty }
        )
    }
}
