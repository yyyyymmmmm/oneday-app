import Foundation
import XCTest
@testable import OneDayCore

/// §233 基础正解批 Core 验收：待发附件跨实例重建、
/// 历史分页计划、上传进度聚合与发送状态恢复口径。
final class BasicsFixBatchTests: XCTestCase {

    private func temporaryRoot() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "BasicsFixBatchTests-\(UUID().uuidString)",
                isDirectory: true
            )
    }

    func testStagedAttachmentsSurviveStoreRecreation() throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let entryID = UUID()
        let first = StagedSendAttachmentStore(rootURL: root)
        let records = try first.stage(
            entryID: entryID,
            payloads: [
                StagedSendPayload(
                    name: "报告.pdf", data: Data("pdf".utf8)
                ),
                StagedSendPayload(
                    name: "数据.bin", data: Data([0, 1, 2, 3])
                ),
            ]
        )
        XCTAssertEqual(records.map(\.byteCount), [3, 4])

        // 新实例等价于进程重启：只凭条目 id 与磁盘
        // manifest 必须把文件名和字节原样重建。
        let restarted = StagedSendAttachmentStore(rootURL: root)
        let loaded = try restarted.loadPayloads(entryID: entryID)
        XCTAssertEqual(loaded.map(\.name), ["报告.pdf", "数据.bin"])
        XCTAssertEqual(loaded.map(\.data.count), [3, 4])
        XCTAssertEqual(loaded.first?.data, Data("pdf".utf8))
    }

    func testStagedAttachmentsTransferAndRemove() throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let sourceID = UUID()
        let destinationID = UUID()
        let store = StagedSendAttachmentStore(rootURL: root)
        try store.stage(
            entryID: sourceID,
            payloads: [
                StagedSendPayload(name: "a.txt", data: Data("a".utf8))
            ]
        )

        try store.transfer(from: sourceID, to: destinationID)
        XCTAssertTrue(
            try store.loadPayloads(entryID: sourceID).isEmpty
        )
        XCTAssertEqual(
            try store.loadPayloads(entryID: destinationID).first?.name,
            "a.txt"
        )

        try store.remove(entryID: destinationID)
        XCTAssertTrue(
            try store.loadPayloads(entryID: destinationID).isEmpty
        )
    }

    func testStagedAttachmentByteMismatchIsNotSilent() throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let entryID = UUID()
        let store = StagedSendAttachmentStore(rootURL: root)
        let records = try store.stage(
            entryID: entryID,
            payloads: [
                StagedSendPayload(name: "a.txt", data: Data("abc".utf8))
            ]
        )
        let file = root
            .appendingPathComponent(entryID.uuidString, isDirectory: true)
            .appendingPathComponent(records[0].relativePath)
        try Data("x".utf8).write(to: file)

        XCTAssertThrowsError(
            try store.loadPayloads(entryID: entryID)
        ) { error in
            XCTAssertEqual(
                error as? StagedSendAttachmentStoreError,
                .byteCountMismatch("a.txt")
            )
        }
    }

    func testHistoryPagePlannerAdvancesOnlyOnFullPage() {
        XCTAssertEqual(
            SessionHistoryPagePlanner.nextOffset(
                currentOffset: 0, receivedCount: 100
            ),
            100
        )
        XCTAssertEqual(
            SessionHistoryPagePlanner.nextOffset(
                currentOffset: 100, receivedCount: 100
            ),
            200
        )
        XCTAssertNil(
            SessionHistoryPagePlanner.nextOffset(
                currentOffset: 200, receivedCount: 37
            )
        )
    }

    func testHistoryPagePlannerChronologicalAndDedupes() throws {
        // SessionMessage 只有解码构造，按生产同路从
        // JSON 造（字段口径与服务端回包一致）
        let messages = try JSONDecoder().decode(
            [SessionMessage].self,
            from: Data("""
            [
                {"id": 3, "role": "user", "content": "三"},
                {"id": 1, "role": "user", "content": "一"},
                {"id": 2, "role": "assistant", "content": "二"}
            ]
            """.utf8)
        )
        XCTAssertEqual(
            SessionHistoryPagePlanner.chronological(messages).map(\.id),
            [1, 2, 3]
        )
        XCTAssertEqual(
            SessionHistoryPagePlanner.unseen(
                messages, seenIDs: [2]
            ).map(\.id),
            [3, 1]
        )
    }

    func testUploadProgressAggregatorUsesBytesAndNeverRegresses() {
        var progress = UploadProgressAggregator(
            fileSizes: [100, 300]
        )
        progress.beginFile(size: 100)
        XCTAssertEqual(
            progress.updateCurrentFile(fraction: 0.5),
            0.125, accuracy: 0.000_001
        )
        XCTAssertEqual(
            progress.finishCurrentFile(),
            0.25, accuracy: 0.000_001
        )
        progress.beginFile(size: 300)
        XCTAssertEqual(
            progress.updateCurrentFile(fraction: 0.5),
            0.625, accuracy: 0.000_001
        )
        // 当前文件的后续回调即使报了更小比例，总进
        // 度也不许倒退。
        XCTAssertEqual(
            progress.updateCurrentFile(fraction: 0.25),
            0.625, accuracy: 0.000_001
        )
        XCTAssertEqual(
            progress.finishCurrentFile(),
            1, accuracy: 0.000_001
        )
    }

    func testSendStateRestoresLegacyFields() {
        XCTAssertEqual(
            ChatSendState.restored(
                rawValue: ChatSendState.sending.rawValue,
                sendFailed: false, deliveryState: nil
            ),
            .sending
        )
        XCTAssertEqual(
            ChatSendState.restored(
                rawValue: nil, sendFailed: true, deliveryState: nil
            ),
            .failed
        )
        XCTAssertEqual(
            ChatSendState.restored(
                rawValue: nil, sendFailed: false,
                deliveryState: "pending"
            ),
            .queued
        )
        XCTAssertNil(
            ChatSendState.restored(
                rawValue: nil, sendFailed: false, deliveryState: nil
            )
        )
        XCTAssertTrue(ChatSendState.failed.remainsInQueue)
        XCTAssertFalse(ChatSendState.failed.mayAutoResume)
        XCTAssertTrue(ChatSendState.uploading.mayAutoResume)
    }
}
