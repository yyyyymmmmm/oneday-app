import Foundation
import OneDayCore
import UIKit
import XCTest
@testable import OneDayApp

/// §410 阶梯量测（修后·新 API）：四段新路径在主 actor
/// 上的占用，与基线树 FileSendIOLadderBaselineTests
/// 同口径对账（5ms 节拍器最大间隔＋墙钟＋组包瞬时内存）
@MainActor
final class FileSendIOLadderTests: XCTestCase {
    private let probe = FileIOStallProbe()

    private func ms(of duration: Duration) -> Double {
        Double(duration.components.seconds) * 1_000
            + Double(duration.components.attoseconds) / 1e15
    }

    private func tempFileURL(sizeMB: Int) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "ladder-new-\(UUID().uuidString).bin"
            )
        try Data(count: sizeMB * 1_024 * 1_024).write(to: url)
        return url
    }

    // MARK: 选择段

    func testLadderPickedNew() async throws {
        for sizeMB in [1, 10, 50, 100] {
            let url = try tempFileURL(sizeMB: sizeMB)
            defer {
                try? FileManager.default.removeItem(at: url)
            }
            probe.start()
            let start = ContinuousClock.now
            let outcome = await ChatView.loadPickedFilesDetached(
                urls: [url]
            )
            let wall = start.duration(to: .now)
            await probe.settle()
            let gap = probe.maxGapMs
            probe.stop()
            XCTAssertEqual(outcome.accepted.count, 1)
            print(String(
                format: "LADDER-NEW picked size=%dMB wall=%.0fms maxGap=%.0fms",
                sizeMB, ms(of: wall), gap
            ))
        }
    }

    // MARK: 暂存段

    func testLadderStageNew() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "ladder-stage-new-\(UUID().uuidString)",
                isDirectory: true
            )
        let store = StagedSendAttachmentStore(rootURL: root)
        defer {
            try? FileManager.default.removeItem(at: root)
        }
        for sizeMB in [1, 10, 50, 100] {
            let payload = StagedSendPayload(
                name: "f\(sizeMB).bin",
                data: Data(count: sizeMB * 1_024 * 1_024)
            )
            probe.start()
            let start = ContinuousClock.now
            _ = try await store.stageAsync(
                entryID: UUID(), payloads: [payload]
            )
            let wall = start.duration(to: .now)
            await probe.settle()
            let gap = probe.maxGapMs
            probe.stop()
            print(String(
                format: "LADDER-NEW stage size=%dMB wall=%.0fms maxGap=%.0fms",
                sizeMB, ms(of: wall), gap
            ))
        }
    }

    // MARK: 上传组包段

    func testLadderPackageNew() async throws {
        for sizeMB in [1, 10, 50, 100] {
            let source = Data(count: sizeMB * 1_024 * 1_024)
            let baseMB = fileIOPhysFootprintMB()
            probe.start()
            let start = ContinuousClock.now
            let url = try await HermesClient.makeUploadBodyFile(
                path: "attachments/f.bin", fileName: "f.bin",
                data: source
            )
            let wall = start.duration(to: .now)
            let peakMB = fileIOPhysFootprintMB()
            await probe.settle()
            let gap = probe.maxGapMs
            probe.stop()
            let bodySize = (try? FileManager.default
                .attributesOfItem(atPath: url.path)[.size]
                as? NSNumber)??.intValue ?? 0
            print(String(
                format: "LADDER-NEW package size=%dMB wall=%.0fms maxGap=%.0fms transient=%.1fMB body=%.1fMB",
                sizeMB, ms(of: wall), gap, peakMB - baseMB,
                Double(bodySize) / 1_048_576
            ))
            try? FileManager.default.removeItem(at: url)
            XCTAssertGreaterThan(bodySize, source.count)
        }
    }

    // MARK: 缩略图段

    func testLadderThumbNew() async throws {
        let png = try FileSendIOThreadAttributionTests
            .noisePNGData(side: 3000)
        for run in 0..<2 {
            let entry = WorkspaceFileEntry(
                name: "noise\(run).png",
                path: "ladder-new/noise-\(UUID().uuidString).png",
                isDirectory: false, size: Int64(png.count),
                mtime: Double(run), mimeType: "image/png"
            )
            probe.start()
            let start = ContinuousClock.now
            let image = await FileThumbnailStore.shared.thumbnail(
                for: entry, targetPixelSize: 360,
                loader: { png }
            )
            let wall = start.duration(to: .now)
            await probe.settle()
            let gap = probe.maxGapMs
            probe.stop()
            XCTAssertNotNil(image)
            print(String(
                format: "LADDER-NEW thumb run=%d png=%.1fMB wall=%.0fms maxGap=%.0fms",
                run, Double(png.count) / 1_048_576,
                ms(of: wall), gap
            ))
        }
    }
}
