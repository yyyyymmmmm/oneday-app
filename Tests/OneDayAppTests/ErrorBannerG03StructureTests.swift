import XCTest
@testable import OneDayApp
import OneDayCore

/// G-03 结构钉测（DESIGN §389，台账 120）：错误横
/// 幅恢复三件（重试/详情/时间戳）的形态把守——
/// ①HermesError 源码内旧状态码模板零残留（主文
/// 案洁净的源头钉）；②ChatView 横幅三件穿线在
/// 场（presentError 赋值口＋errorOccurredAt 时
/// 刻＋errorDetailExpanded 详情展开＋「详情」
/// 钮）；③台账 117 回补降级穿线在场（Backfiller
/// 认 isPaginationRejected 并退全量拉取）。
final class ErrorBannerG03StructureTests: XCTestCase {

    private func repoRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func source(_ relative: String) throws -> String {
        try String(
            contentsOf: repoRoot()
                .appendingPathComponent(relative),
            encoding: .utf8
        )
    }

    func testHermesErrorSourceHasNoStatusTemplates() throws {
        let hermesError = try source(
            "Sources/OneDayCore/HermesError.swift"
        )
        XCTAssertFalse(
            hermesError.contains("返回了状态"),
            "§389：旧模板「%@ 返回了状态 %@」不许在 HermesError 复活"
        )
        XCTAssertFalse(
            hermesError.contains("（状态 %@）"),
            "§389：状态码括号模板不许在 userMessage 复活"
        )
        XCTAssertTrue(hermesError.contains("var diagnosticDetail"))
        XCTAssertTrue(hermesError.contains("HermesErrorCategory"))
        XCTAssertTrue(hermesError.contains("var isPaginationRejected"))
    }

    func testChatViewBannerRecoveryTrioWiring() throws {
        // #37 模块化拆分后 ChatView 分布在多个文件，合并读取
        let mainChat = try source("Sources/OneDayApp/ChatView.swift")
        let sendChat = try source("Sources/OneDayApp/ChatView+SendAndOutbox.swift")
        let chatView = mainChat + "\n" + sendChat
        XCTAssertTrue(
            chatView.contains("private func presentError(_ error: HermesError)"),
            "§389：HermesError 驱动失败须走 presentError 赋值口"
        )
        XCTAssertTrue(chatView.contains("errorOccurredAt"))
        XCTAssertTrue(chatView.contains("errorDetailExpanded"))
        XCTAssertTrue(
            chatView.contains("Text(\"详情\")"),
            "§389：横幅须有「详情」展开钮承接技术原文"
        )
        XCTAssertTrue(
            chatView.contains("Text(errorOccurredAt, style: .time)"),
            "§389：横幅须有发生时刻时间戳"
        )
        // 0.51.0 改钉（判读 release-0510-red12-triage
        // B1）：发送失败机制包已删提交拒绝／run 落定
        // 失败的两个 presentError 调用点，改走 present-
        // SendFailure 行内分类文案——§389 横幅自此只管
        // 非发送类错误，发送失败呈现面以行内分类为准
        XCTAssertTrue(
            chatView.contains(
                "presentSendFailure(kind: .authRejected)"),
            "§389 改钉：提交凭据被拒须走 presentSendFailure 行内分类"
        )
        XCTAssertTrue(
            chatView.contains(
                "kind: SendFailureKind.classify(run: failure)"),
            "§389 改钉：run 落定失败须经 SendFailureKind 分类走 presentSendFailure"
        )
    }

    func testBackfillerPaginationFallbackWiring() throws {
        let backfiller = try source(
            "Sources/OneDayApp/SessionHistoryBackfiller.swift"
        )
        XCTAssertTrue(
            backfiller.contains("isPaginationRejected"),
            "§389/台账 117：回补链须认分页被拒信号"
        )
        XCTAssertTrue(
            backfiller.contains("paginationFallbackUsed"),
            "§389/台账 117：全量降级每轮只许一次，须有记账位"
        )
        XCTAssertTrue(
            backfiller.contains("client.sessionMessages("),
            "§389/台账 117：降级目标是无参全量拉取 sessionMessages"
        )
    }
}
