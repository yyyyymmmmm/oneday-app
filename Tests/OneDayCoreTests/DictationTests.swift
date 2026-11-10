import OneDayCore
import XCTest

/// 语音输入纯逻辑（0.36.6，DESIGN-V4 §71）：转写会
/// 话合并、电平平滑、波形环、计时政策、静音判定、
/// 相位守卫的构造断言——引擎与系统 API 不在此测
/// （真机面），数据面规则全钉在此处
final class DictationTests: XCTestCase {

    // MARK: - 转写会话合并（规格 §3.3）

    func testVolatileReplacesWholeSegment() {
        var session = DictationSession(baseDraft: "")
        session.applyResult(text: "今天", isFinal: false)
        XCTAssertEqual(session.displayText, "今天")
        // 未定稿整段替换，不许逐字追加成「今天今天天」
        session.applyResult(text: "今天天气", isFinal: false)
        XCTAssertEqual(session.displayText, "今天天气")
        XCTAssertEqual(session.volatileLength, 4)
    }

    func testFinalAppendsAndClearsVolatile() {
        var session = DictationSession(baseDraft: "")
        session.applyResult(text: "今天天气", isFinal: false)
        session.applyResult(text: "今天天气不错，", isFinal: true)
        XCTAssertEqual(session.displayText, "今天天气不错，")
        XCTAssertEqual(session.volatileLength, 0)
        // 下一段从空 volatile 重新开始
        session.applyResult(text: "我们出", isFinal: false)
        session.applyResult(text: "我们出门吧", isFinal: false)
        XCTAssertEqual(session.displayText, "今天天气不错，我们出门吧")
        session.applyResult(text: "我们出门吧。", isFinal: true)
        XCTAssertEqual(session.recognizedText, "今天天气不错，我们出门吧。")
    }

    func testBaseDraftPreservedAndCancelReturnsBase() {
        var session = DictationSession(baseDraft: "先写一半")
        session.applyResult(text: "继续说", isFinal: true)
        XCTAssertEqual(session.displayText, "先写一半继续说")
        // 取消路径：App 层直接取 baseDraft，本次段整段丢弃
        XCTAssertEqual(session.baseDraft, "先写一半")
    }

    func testCommitExcludeVolatileDropsTail() {
        var session = DictationSession(baseDraft: "")
        session.applyResult(text: "已定稿。", isFinal: true)
        session.applyResult(text: "未定稿半句", isFinal: false)
        XCTAssertEqual(
            session.committedText(includeVolatile: true),
            "已定稿。未定稿半句"
        )
        XCTAssertEqual(
            session.committedText(includeVolatile: false), "已定稿。"
        )
    }

    func testJoinInsertsSpaceBetweenASCIILetters() {
        var session = DictationSession(baseDraft: "Hello")
        session.applyResult(text: "world", isFinal: true)
        XCTAssertEqual(session.displayText, "Hello world")
    }

    func testJoinNoSpaceWhenBaseEndsWithSpaceOrPunctuation() {
        var spaced = DictationSession(baseDraft: "Hello ")
        spaced.applyResult(text: "world", isFinal: true)
        XCTAssertEqual(spaced.displayText, "Hello world")
        var zh = DictationSession(baseDraft: "你好")
        zh.applyResult(text: "世界", isFinal: true)
        XCTAssertEqual(zh.displayText, "你好世界")
    }

    func testEmptySessionHasNoRecognizedText() {
        let session = DictationSession(baseDraft: "草稿")
        XCTAssertFalse(session.hasRecognizedText)
        XCTAssertEqual(session.displayText, "草稿")
    }

    // MARK: - 电平（规格 §3.2）

    func testRMSOfEmptyAndSilenceIsZero() {
        XCTAssertEqual(DictationLevel.rms(samples: []), 0)
        XCTAssertEqual(DictationLevel.rms(samples: [0, 0, 0]), 0)
        XCTAssertEqual(
            DictationLevel.rms(samples: [1, -1, 1, -1]), 1, accuracy: 1e-9
        )
        XCTAssertEqual(
            DictationLevel.rms(samples: [0.5, 0.5]), 0.5, accuracy: 1e-9
        )
    }

    func testNormalizedLevelBounds() {
        XCTAssertEqual(DictationLevel.normalizedLevel(rms: 0), 0)
        XCTAssertEqual(DictationLevel.normalizedLevel(rms: -1), 0)
        // -50dB=0.00316 → 0；-10dB=0.316 → 1
        XCTAssertEqual(
            DictationLevel.normalizedLevel(rms: 0.00316227766), 0,
            accuracy: 0.01
        )
        XCTAssertEqual(
            DictationLevel.normalizedLevel(rms: 0.316227766), 1,
            accuracy: 0.01
        )
        // 满幅不许越界
        XCTAssertEqual(DictationLevel.normalizedLevel(rms: 1), 1)
        // 中间值单调
        let low = DictationLevel.normalizedLevel(rms: 0.01)
        let high = DictationLevel.normalizedLevel(rms: 0.1)
        XCTAssertTrue(low < high)
        XCTAssertTrue(low > 0 && high < 1)
    }

    func testSmootherAttacksFasterThanReleases() {
        var attacker = DictationLevelSmoother()
        attacker.ingest(rms: 0.316227766, dt: 0.05) // 目标 1
        let attacked = attacker.level
        var releaser = DictationLevelSmoother()
        releaser.ingest(rms: 0.316227766, dt: 10) // 先充到近 1
        let charged = releaser.level
        releaser.ingest(rms: 0, dt: 0.05) // 目标 0
        let releasedDrop = charged - releaser.level
        XCTAssertGreaterThan(attacked, 0.4) // 60ms 快攻：50ms 已过半程
        XCTAssertLessThan(releasedDrop, attacked) // 180ms 慢放：同 dt 落得少
        XCTAssertGreaterThanOrEqual(releaser.level, 0)
    }

    func testSmootherNeverExceedsBounds() {
        var smoother = DictationLevelSmoother()
        for _ in 0..<100 { smoother.ingest(rms: 1, dt: 0.05) }
        XCTAssertLessThanOrEqual(smoother.level, 1)
        XCTAssertGreaterThan(smoother.level, 0.99)
        smoother.reset()
        XCTAssertEqual(smoother.level, 0)
    }

    // MARK: - 波形环

    func testWaveformShiftsLeftAndClamps() {
        var wave = DictationWaveform()
        XCTAssertEqual(wave.bars.count, DictationWaveform.barCount)
        wave.push(0.5)
        XCTAssertEqual(wave.bars.last, 0.5)
        XCTAssertEqual(wave.bars.first, 0)
        for i in 1...9 { wave.push(Double(i) / 10) }
        XCTAssertEqual(wave.bars.count, DictationWaveform.barCount)
        XCTAssertEqual(
            wave.bars[DictationWaveform.barCount - 1], 0.9, accuracy: 1e-9)
        wave.push(2) // 越界钳到 1
        XCTAssertEqual(wave.bars.last, 1)
        wave.reset()
        XCTAssertTrue(wave.bars.allSatisfy { $0 == 0 })
    }

    // MARK: - 计时政策（规格 §3.1）

    func testTimingThresholds() {
        XCTAssertEqual(DictationTiming.limitSeconds, 300)
        XCTAssertFalse(DictationTiming.isWarning(elapsedSeconds: 269))
        XCTAssertTrue(DictationTiming.isWarning(elapsedSeconds: 270))
        XCTAssertFalse(DictationTiming.reachedLimit(elapsedSeconds: 299))
        XCTAssertTrue(DictationTiming.reachedLimit(elapsedSeconds: 300))
    }

    func testTimingFormat() {
        XCTAssertEqual(DictationTiming.format(elapsedSeconds: 0), "0:00")
        XCTAssertEqual(DictationTiming.format(elapsedSeconds: 7), "0:07")
        XCTAssertEqual(DictationTiming.format(elapsedSeconds: 65), "1:05")
        XCTAssertEqual(DictationTiming.format(elapsedSeconds: 299), "4:59")
        XCTAssertEqual(DictationTiming.format(elapsedSeconds: 300), "5:00")
        XCTAssertEqual(DictationTiming.format(elapsedSeconds: -3), "0:00")
    }

    // MARK: - 静音判定（规格 §3.1）

    func testSilencePromptsAfterTenSecondsOnly() {
        var tracker = SilenceTracker()
        XCTAssertFalse(tracker.ingest(level: 0, dt: 9.9))
        XCTAssertTrue(tracker.ingest(level: 0, dt: 0.2))
        // 一有声即清零
        XCTAssertFalse(tracker.ingest(level: 0.5, dt: 0.1))
        XCTAssertFalse(tracker.ingest(level: 0, dt: 9.9))
        tracker.reset()
        XCTAssertEqual(tracker.silentDuration, 0)
    }

    // MARK: - 相位守卫（规格 §3.5）

    func testPhasePolicyHappyPath() {
        XCTAssertTrue(DictationPhasePolicy.canTransition(
            from: .idle, to: .requestingPermission))
        XCTAssertTrue(DictationPhasePolicy.canTransition(
            from: .requestingPermission, to: .preparing))
        XCTAssertTrue(DictationPhasePolicy.canTransition(
            from: .preparing, to: .recording))
        XCTAssertTrue(DictationPhasePolicy.canTransition(
            from: .recording, to: .finishing))
        XCTAssertTrue(DictationPhasePolicy.canTransition(
            from: .finishing, to: .idle))
        // 资产已装可跳过 preparing 直达录音
        XCTAssertTrue(DictationPhasePolicy.canTransition(
            from: .requestingPermission, to: .recording))
        XCTAssertTrue(DictationPhasePolicy.canTransition(
            from: .idle, to: .recording))
    }

    func testPhasePolicyRejectsLateCallbacks() {
        // 落定后迟到的结果回调不许把相位拽回录音
        XCTAssertFalse(DictationPhasePolicy.canTransition(
            from: .idle, to: .finishing))
        XCTAssertFalse(DictationPhasePolicy.canTransition(
            from: .finishing, to: .recording))
        XCTAssertFalse(DictationPhasePolicy.canTransition(
            from: .failed, to: .finishing))
        XCTAssertFalse(DictationPhasePolicy.canTransition(
            from: .recording, to: .idle))
        XCTAssertFalse(DictationPhasePolicy.canTransition(
            from: .recording, to: .preparing))
        // 失败可重试、可退出
        XCTAssertTrue(DictationPhasePolicy.canTransition(
            from: .failed, to: .preparing))
        XCTAssertTrue(DictationPhasePolicy.canTransition(
            from: .failed, to: .idle))
        XCTAssertTrue(DictationPhasePolicy.canTransition(
            from: .recording, to: .failed))
    }

    // MARK: - 语言表

    func testLanguageTable() {
        XCTAssertEqual(DictationLanguage.mandarin.localeIdentifier, "zh_CN")
        XCTAssertEqual(DictationLanguage.cantonese.localeIdentifier, "yue_CN")
        XCTAssertEqual(
            DictationLanguage.cantonese.fallbackLocaleIdentifier, "zh_HK")
        XCTAssertEqual(DictationLanguage.english.localeIdentifier, "en_US")
        XCTAssertNil(DictationLanguage.mandarin.fallbackLocaleIdentifier)
        XCTAssertEqual(DictationLanguage.allCases.count, 3)
    }

    func testFailureCasesCovered() {
        // 六类失败全在（App 文案映射按此枚举，漏一类即漏一种呈现）
        XCTAssertEqual(DictationFailure.allCases.count, 6)
    }

    // MARK: - tap 格式有效性门（0.36.8 热修，诊断 §2/§5.2）

    func testAudioFormatPolicyGate() {
        // 诊断实锤形态：采样率 0——首次授权后硬件未就
        // 绪的合法形态，必须挡在 installTap 之前
        XCTAssertFalse(DictationAudioFormatPolicy.isUsable(
            sampleRate: 0, channelCount: 2))
        XCTAssertFalse(DictationAudioFormatPolicy.isUsable(
            sampleRate: 48000, channelCount: 0))
        XCTAssertFalse(DictationAudioFormatPolicy.isUsable(
            sampleRate: -44100, channelCount: 2))
        XCTAssertFalse(DictationAudioFormatPolicy.isUsable(
            sampleRate: .nan, channelCount: 1))
        XCTAssertFalse(DictationAudioFormatPolicy.isUsable(
            sampleRate: .infinity, channelCount: 1))
        XCTAssertTrue(DictationAudioFormatPolicy.isUsable(
            sampleRate: 48000, channelCount: 1))
        XCTAssertTrue(DictationAudioFormatPolicy.isUsable(
            sampleRate: 16000, channelCount: 2))
    }

    func testConversionRatioGuards() {
        // 正常降采样比值
        let ratio = DictationAudioFormatPolicy.conversionRatio(
            inputSampleRate: 48000, outputSampleRate: 16000)
        XCTAssertNotNil(ratio)
        XCTAssertEqual(ratio ?? 0, 1.0 / 3.0, accuracy: 1e-9)
        // 输入 0 率：比值无定义，整帧丢弃而不是算出 inf
        XCTAssertNil(DictationAudioFormatPolicy.conversionRatio(
            inputSampleRate: 0, outputSampleRate: 16000))
        XCTAssertNil(DictationAudioFormatPolicy.conversionRatio(
            inputSampleRate: 48000, outputSampleRate: 0))
        XCTAssertNil(DictationAudioFormatPolicy.conversionRatio(
            inputSampleRate: .nan, outputSampleRate: 16000))
        XCTAssertNil(DictationAudioFormatPolicy.conversionRatio(
            inputSampleRate: 48000, outputSampleRate: .infinity))
    }

    // MARK: - 故障传播政策（0.36.8 热修，诊断 §6）

    func testFaultPolicyMatrix() {
        // 代次不符：任何相位都作废（迟到信号）
        for phase in DictationPhase.allCases {
            XCTAssertEqual(
                DictationFaultPolicy.action(
                    generationMatches: false, phase: phase),
                .ignore)
        }
        // 录音中抛错：失败收尾，错误必达用户面
        XCTAssertEqual(
            DictationFaultPolicy.action(
                generationMatches: true, phase: .recording),
            .finishWithError)
        // 启动中抛错（旧实现在此静默吞＝假录音根源）：
        // 闩住作废，绝不许进录音态
        XCTAssertEqual(
            DictationFaultPolicy.action(
                generationMatches: true, phase: .requestingPermission),
            .abortStartup)
        XCTAssertEqual(
            DictationFaultPolicy.action(
                generationMatches: true, phase: .preparing),
            .abortStartup)
        // 已落定/收尾中：收尾流程自己管，不重复触发
        XCTAssertEqual(
            DictationFaultPolicy.action(
                generationMatches: true, phase: .idle), .ignore)
        XCTAssertEqual(
            DictationFaultPolicy.action(
                generationMatches: true, phase: .finishing), .ignore)
        XCTAssertEqual(
            DictationFaultPolicy.action(
                generationMatches: true, phase: .failed), .ignore)
    }
}
