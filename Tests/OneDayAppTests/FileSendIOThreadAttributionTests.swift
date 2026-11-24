import Foundation
import MachO
import OneDayCore
import UIKit
import XCTest
@testable import OneDayApp

/// §410 钉测共用探针：MainActor 节拍器（5ms 周期）——
/// 被测段若在主线程同步付字节成本，最长 tick 间隔会
/// 随载荷量级放大；下主线程后只剩调度噪声
@MainActor
final class FileIOStallProbe {
    private(set) var maxGapMs: Double = 0
    private var task: Task<Void, Never>?

    func start() {
        maxGapMs = 0
        task = Task { @MainActor in
            var last = ContinuousClock.now
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(5))
                let now = ContinuousClock.now
                let gap = last.duration(to: now)
                let ms = Double(gap.components.seconds) * 1_000
                    + Double(gap.components.attoseconds) / 1e15
                if ms > maxGapMs { maxGapMs = ms }
                last = now
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }

    func settle() async {
        try? await Task.sleep(for: .milliseconds(40))
    }
}

/// §410 钉测共用：进程物理内存占用（MB），组包段
/// 瞬时增量对账用
func fileIOPhysFootprintMB() -> Double {
    var info = task_vm_info_data_t()
    var count = mach_msg_type_number_t(
        MemoryLayout<task_vm_info_data_t>.size
            / MemoryLayout<integer_t>.size
    )
    let kr = withUnsafeMutablePointer(to: &info) { pointer in
        pointer.withMemoryRebound(
            to: integer_t.self, capacity: Int(count)
        ) {
            task_info(
                mach_task_self_, task_flavor_t(TASK_VM_INFO),
                $0, &count
            )
        }
    }
    guard kr == KERN_SUCCESS else { return -1 }
    return Double(info.phys_footprint) / 1_048_576
}

/// §410 四段线程归属钉测：每段从 MainActor 上下文调
/// 生产入口＋大载荷，断言主线节拍不断档（旧同步链在
/// 同载荷下会把节拍堵出数量级间隔，基线阶梯有实测）
@MainActor
final class FileSendIOThreadAttributionTests: XCTestCase {
    private let probe = FileIOStallProbe()
    /// 主线占用上限：调度噪声量级，远低于 30MB 级同
    /// 步读/写/编码在主线的实测量级
    private let gapLimitMs: Double = 200

    private func tempFileURL(
        name: String, data: Data
    ) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(name)
        try data.write(to: url)
        return url
    }

    // MARK: 选择段

    func testPickedFilesLoadRunsOffMain() async throws {
        let bigURL = try tempFileURL(
            name: "pin-big-\(UUID().uuidString).bin",
            data: Data(count: 30 * 1_024 * 1_024)
        )
        // 「中文测试」的 GBK 字节（转码名单对账；
        // 接管修：末字「试」GBK 为 CA D4——前任夹具
        // 误写 CA C7（那是「是」），产品转码无误、
        // 夹具与期望对不上，2026-11-23 实跑抓出）
        let gbkURL = try tempFileURL(
            name: "pin-note-\(UUID().uuidString).txt",
            data: Data([
                0xD6, 0xD0, 0xCE, 0xC4, 0xB2, 0xE2, 0xCA, 0xD4,
            ])
        )
        defer {
            try? FileManager.default.removeItem(at: bigURL)
            try? FileManager.default.removeItem(at: gbkURL)
        }
        probe.start()
        let outcome = await ChatView.loadPickedFilesDetached(
            urls: [bigURL, gbkURL]
        )
        await probe.settle()
        let gap = probe.maxGapMs
        probe.stop()
        XCTAssertEqual(
            Set(outcome.accepted.map(\.name)),
            Set([bigURL.lastPathComponent,
                 gbkURL.lastPathComponent])
        )
        XCTAssertEqual(
            outcome.transcoded, [gbkURL.lastPathComponent]
        )
        let gbkPayload = try XCTUnwrap(outcome.accepted.first {
            $0.name == gbkURL.lastPathComponent
        })
        XCTAssertEqual(
            String(data: gbkPayload.data, encoding: .utf8),
            "中文测试"
        )
        XCTAssertLessThan(
            gap, gapLimitMs,
            "选文件读盘段仍在主线程（maxGap=\(gap)ms）"
        )
    }

    // MARK: 暂存段

    func testStageAsyncOffMainAndFlightGate() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "pin-stage-\(UUID().uuidString)",
                isDirectory: true
            )
        let store = StagedSendAttachmentStore(rootURL: root)
        defer {
            try? FileManager.default.removeItem(at: root)
        }
        let entryID = UUID()
        let payload = StagedSendPayload(
            name: "big.bin",
            data: Data(count: 50 * 1_024 * 1_024)
        )
        probe.start()
        _ = try await store.stageAsync(
            entryID: entryID, payloads: [payload]
        )
        await probe.settle()
        let gap = probe.maxGapMs
        probe.stop()
        XCTAssertLessThan(
            gap, gapLimitMs,
            "暂存写盘段仍在主线程（maxGap=\(gap)ms）"
        )
        let loaded = try store.loadPayloads(entryID: entryID)
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded.first?.data, payload.data)

        // 即发即走＋读侧等落定：stageDetached 后立刻读
        // 必须等在飞写完成、读到完整载荷而非半写目录
        let entry2 = UUID()
        let small = StagedSendPayload(
            name: "s.txt", data: Data("hello".utf8)
        )
        store.stageDetached(entryID: entry2, payloads: [small])
        let loaded2 = try await Task.detached {
            try store.loadPayloads(entryID: entry2)
        }.value
        XCTAssertEqual(loaded2.first?.data, small.data)
        XCTAssertFalse(store.stageInFlight(entryID: entry2))
    }

    // MARK: 上传组包段

    func testUploadBodyFileOffMainAndRoundTrip() async throws {
        var source = Data(count: 20 * 1_024 * 1_024)
        source.withUnsafeMutableBytes { buffer in
            let bytes = buffer.bindMemory(to: UInt8.self)
            for index in 0..<bytes.count {
                bytes[index] = UInt8(index % 251)
            }
        }
        probe.start()
        let url = try await HermesClient.makeUploadBodyFile(
            path: "attachments/f.bin", fileName: "f.bin",
            data: source
        )
        await probe.settle()
        let gap = probe.maxGapMs
        probe.stop()
        defer {
            try? FileManager.default.removeItem(at: url)
        }
        XCTAssertLessThan(
            gap, gapLimitMs,
            "上传组包段仍在主线程（maxGap=\(gap)ms）"
        )
        let body = try Data(contentsOf: url)
        let parsed = try XCTUnwrap(
            JSONSerialization.jsonObject(with: body)
                as? [String: Any]
        )
        XCTAssertEqual(parsed["path"] as? String, "attachments/f.bin")
        XCTAssertEqual(parsed["overwrite"] as? Bool, true)
        // 与旧链 dataURL 逐字一致＝线上请求体不变
        XCTAssertEqual(
            parsed["data_url"] as? String,
            FileSendAssembly.dataURL(
                fileName: "f.bin", data: source
            )
        )
    }

    // MARK: 缩略图段

    func testThumbnailGenerationRunsOffMain() async throws {
        let png = try Self.noisePNGData(side: 3000)
        let entry = WorkspaceFileEntry(
            name: "pin-noise.png",
            path: "pin/noise-\(UUID().uuidString).png",
            isDirectory: false, size: Int64(png.count), mtime: 1,
            mimeType: "image/png"
        )
        probe.start()
        let image = await FileThumbnailStore.shared.thumbnail(
            for: entry, targetPixelSize: 360,
            loader: { png }
        )
        await probe.settle()
        let gap = probe.maxGapMs
        probe.stop()
        XCTAssertNotNil(image)
        XCTAssertLessThan(
            gap, gapLimitMs,
            "缩略图生成段仍在主线程（maxGap=\(gap)ms）"
        )
    }

    /// 随机噪声 PNG（不可压缩，解码/编码成本真实）
    static func noisePNGData(side: Int) throws -> Data {
        let bytesPerRow = side * 4
        var pixels = Data(count: bytesPerRow * side)
        pixels.withUnsafeMutableBytes { buffer in
            let bytes = buffer.bindMemory(to: UInt8.self)
            for index in 0..<bytes.count {
                bytes[index] = UInt8.random(in: 0...255)
            }
        }
        let provider = try XCTUnwrap(
            CGDataProvider(data: pixels as CFData)
        )
        let image = try XCTUnwrap(CGImage(
            width: side, height: side,
            bitsPerComponent: 8, bitsPerPixel: 32,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(
                rawValue: CGImageAlphaInfo.premultipliedLast.rawValue
            ),
            provider: provider, decode: nil,
            shouldInterpolate: false, intent: .defaultIntent
        ))
        return try XCTUnwrap(UIImage(cgImage: image).pngData())
    }
}
