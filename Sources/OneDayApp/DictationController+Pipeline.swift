import AVFoundation
import OneDayCore
import os
import Speech

/// iOS 26 原生 SpeechAnalyzer 能力探测（#32 模块化收口）：
/// 确认端上 SpeechTranscriber 可用性与当前语言资产状态。
enum SpeechAnalyzerCapability {
    static var isNativeTranscriberAvailable: Bool {
        SpeechTranscriber.isAvailable
    }

    static func supportedLocale(for language: DictationLanguage) async -> Locale? {
        if let locale = await SpeechTranscriber.supportedLocale(
            equivalentTo: Locale(identifier: language.localeIdentifier)
        ) {
            return locale
        }
        if let fallbackID = language.fallbackLocaleIdentifier {
            return await SpeechTranscriber.supportedLocale(
                equivalentTo: Locale(identifier: fallbackID)
            )
        }
        return nil
    }
}

/// 音频管线（tap 线程侧，#32 抽离自 DictationController）：
/// 硬件格式 buffer 在此转码到 SpeechAnalyzer 格式并 yield，同时把原始电平写进无锁盒
/// 供主线程 10Hz 轮询。nonisolated 终类，installTap 由盒本人安装，彻底规避主隔离断言崩。
final class DictationAudioPipe: @unchecked Sendable {
    private let targetFormat: AVAudioFormat
    private let continuation: AsyncStream<AnalyzerInput>.Continuation
    private let feedBox = DictationAudioFeedBox()
    private let consumedBox = OSAllocatedUnfairLock(initialState: false)
    private let converterBox = OSAllocatedUnfairLock<AVAudioConverter?>(
        initialState: nil)

    init(
        targetFormat: AVAudioFormat,
        continuation: AsyncStream<AnalyzerInput>.Continuation
    ) {
        self.targetFormat = targetFormat
        self.continuation = continuation
    }

    var latestRMS: Double { feedBox.latestRMS }

    func installTap(on inputNode: AVAudioInputNode) {
        inputNode.installTap(
            onBus: 0, bufferSize: 1024, format: nil
        ) { buffer, _ in
            self.consume(buffer)
        }
    }

    private func converter(
        for inputFormat: AVAudioFormat
    ) -> AVAudioConverter? {
        converterBox.withLock { current in
            if let current, current.inputFormat == inputFormat {
                return current
            }
            let created = AVAudioConverter(
                from: inputFormat, to: targetFormat)
            created?.primeMethod = .none
            current = created
            return created
        }
    }

    func consume(_ buffer: AVAudioPCMBuffer) {
        if let channel = buffer.floatChannelData?[0] {
            let samples = Array(UnsafeBufferPointer(
                start: channel, count: Int(buffer.frameLength)))
            feedBox.ingest(samples: samples)
        }
        guard buffer.frameLength > 0,
              let converter = converter(for: buffer.format),
              let ratio = DictationAudioFormatPolicy.conversionRatio(
                  inputSampleRate: buffer.format.sampleRate,
                  outputSampleRate: targetFormat.sampleRate)
        else { return }
        let capacity = AVAudioFrameCount(
            Double(buffer.frameLength) * ratio) + 16
        guard let converted = AVAudioPCMBuffer(
            pcmFormat: converter.outputFormat, frameCapacity: capacity
        ) else { return }
        consumedBox.withLock { $0 = false }
        var error: NSError?
        let status = converter.convert(to: converted, error: &error) {
            _, outStatus in
            let already = self.consumedBox.withLock { state -> Bool in
                let was = state
                state = true
                return was
            }
            if already {
                outStatus.pointee = .noDataNow
                return nil
            }
            outStatus.pointee = .haveData
            return buffer
        }
        if status != .error, error == nil, converted.frameLength > 0 {
            continuation.yield(AnalyzerInput(buffer: converted))
        }
    }

    func finish() {
        continuation.finish()
    }
}

/// 进度观察盒（#32 抽离自 DictationController）：nonisolated 终类，
/// 避免 AssetInventory 下载进度 KVO 回调在非主线程触发 @MainActor 隔离断言。
final class DictationProgressObserver: @unchecked Sendable {
    private var observation: NSKeyValueObservation?

    func observe(
        _ progress: Progress,
        onChange: @escaping @Sendable (Double) -> Void
    ) {
        observation = progress.observe(
            \.fractionCompleted, options: [.new]
        ) { observed, _ in
            onChange(observed.fractionCompleted)
        }
    }

    func invalidate() {
        observation = nil
    }
}
