import XCTest
@testable import OneDayCore

/// 服务端语音映射层钉测（H2-a，台账 159）：fixture
/// 全部按 H2-0 探活＋开通复探的实测形态冻结——
/// voice-config 开通前后逐字不变（reason 恒为 relay
/// 拓扑描述）、speak 成功回执 {ok,data_url,mime_
/// type,provider}、失败 400 detail 原文。判定/分型/
/// 文本/状态机口径改一寸，这里先红。
final class VoiceSpeechTests: XCTestCase {

    // MARK: - DTO 解码（探活/复探冻结形状）

    /// 开通复探实测原文（pkg-hermes-voice-probe
    /// §1.1；开通后复测逐字不变——本 fixture 同时是
    /// 「reason 非空不等于未开通」的钉子）
    private let voiceConfigJSON = #"""
    {"ok": true,
     "stt": {"mode": "relay", "reason": "command/plugin provider", "streaming": false},
     "tts": {"mode": "relay", "reason": "provider 'edge' has no client wire"}}
    """#

    func testVoiceConfigDecodes() throws {
        let decoded = try JSONDecoder().decode(
            VoiceConfigResponse.self,
            from: Data(voiceConfigJSON.utf8)
        )
        XCTAssertTrue(decoded.ok)
        XCTAssertEqual(decoded.stt?.mode, "relay")
        XCTAssertEqual(decoded.stt?.streaming, false)
        XCTAssertEqual(decoded.tts?.mode, "relay")
        XCTAssertEqual(
            decoded.tts?.reason, "provider 'edge' has no client wire"
        )
    }

    func testSpeakResponseDecodesAndExtractsAudio() throws {
        let payload = Data("fake-mp3-bytes".utf8)
        let json = """
        {"ok": true, "data_url": "data:audio/mpeg;base64,\(payload.base64EncodedString())", "mime_type": "audio/mpeg", "provider": "edge"}
        """
        let decoded = try JSONDecoder().decode(
            SpeakResponse.self, from: Data(json.utf8)
        )
        XCTAssertTrue(decoded.ok)
        XCTAssertEqual(decoded.mimeType, "audio/mpeg")
        XCTAssertEqual(decoded.provider, "edge")
        XCTAssertEqual(decoded.audioData, payload)
    }

    func testSpeakResponseRejectsMalformedDataURL() throws {
        for bad in [
            "https://example.com/a.mp3",
            "data:audio/mpeg;base64,",
            "data:audio/mpeg,QUJD",
            "data:audio/mpeg;base64,!!!",
        ] {
            let json = """
            {"ok": true, "data_url": "\(bad)", "mime_type": "audio/mpeg", "provider": "edge"}
            """
            let decoded = try JSONDecoder().decode(
                SpeakResponse.self, from: Data(json.utf8)
            )
            XCTAssertNil(decoded.audioData, "坏形态不许出字节：\(bad)")
        }
    }

    func testElevenLabsVoicesDecodes() throws {
        let empty = #"{"available": false, "voices": []}"#
        let decodedEmpty = try JSONDecoder().decode(
            ElevenLabsVoicesResponse.self, from: Data(empty.utf8)
        )
        XCTAssertFalse(decodedEmpty.available)
        XCTAssertTrue(decodedEmpty.voices.isEmpty)
        XCTAssertNil(decodedEmpty.error)

        let populated = #"""
        {"available": true, "voices": [{"voice_id": "v1", "name": "Rachel"}]}
        """#
        let decoded = try JSONDecoder().decode(
            ElevenLabsVoicesResponse.self,
            from: Data(populated.utf8)
        )
        XCTAssertTrue(decoded.available)
        XCTAssertEqual(decoded.voices.first?.voiceID, "v1")
        XCTAssertEqual(decoded.voices.first?.name, "Rachel")
    }

    // MARK: - 可用性判定（组合字段＋实调精修）

    func testAssessEnabledInstanceIsAvailable() throws {
        // 全包最要紧的一条钉：开通后的真实配置里
        // reason 照样非空——读 reason 判未开通会把
        // 已开通的实例误判死（开通报告 §三）
        let config = try JSONDecoder().decode(
            VoiceConfigResponse.self,
            from: Data(voiceConfigJSON.utf8)
        )
        XCTAssertEqual(
            VoiceAvailability.assess(config: config), .available
        )
    }

    func testAssessNilAndBrokenConfig() {
        XCTAssertEqual(
            VoiceAvailability.assess(config: nil), .unknown
        )
        let notOK = VoiceConfigResponse(ok: false, stt: nil, tts: nil)
        XCTAssertEqual(
            VoiceAvailability.assess(config: notOK), .unavailable
        )
        let noTTS = VoiceConfigResponse(
            ok: true,
            stt: .init(mode: "relay", reason: nil, streaming: nil),
            tts: nil
        )
        XCTAssertEqual(
            VoiceAvailability.assess(config: noTTS), .unavailable
        )
    }

    func testConfigMergeNeverResurrectsRefutedState() {
        // speak 已证伪的未开通，配置的暂定可用不许翻回
        XCTAssertEqual(
            VoiceAvailability.mergingConfigAssessment(
                current: .unavailable, assessed: .available
            ),
            .unavailable
        )
        // 未知可被暂定可用升起
        XCTAssertEqual(
            VoiceAvailability.mergingConfigAssessment(
                current: .unknown, assessed: .available
            ),
            .available
        )
        // 配置证伪优先于现态可用（服务端把组件卸了）
        XCTAssertEqual(
            VoiceAvailability.mergingConfigAssessment(
                current: .available, assessed: .unavailable
            ),
            .unavailable
        )
        // 拉不到（未知评估）不动现态
        XCTAssertEqual(
            VoiceAvailability.mergingConfigAssessment(
                current: .available, assessed: .unknown
            ),
            .available
        )
    }

    func testRefineBySpeakOutcome() {
        XCTAssertEqual(
            VoiceAvailability.refined(
                current: .unknown, by: .succeeded
            ),
            .available
        )
        XCTAssertEqual(
            VoiceAvailability.refined(
                current: .available, by: .providerUnavailable
            ),
            .unavailable
        )
        // 其余失败不携带可用性信息
        XCTAssertEqual(
            VoiceAvailability.refined(
                current: .unknown, by: .failedOther
            ),
            .unknown
        )
        XCTAssertEqual(
            VoiceAvailability.refined(
                current: .available, by: .failedOther
            ),
            .available
        )
    }

    // MARK: - speak 失败分型（400 detail 原文）

    func testSpeakFailureClassification() {
        // 探活 §1.2 失败原文（未开通时）
        XCTAssertEqual(
            SpeakFailureKind.classify(
                status: 400,
                detail: "TTS chunk 1 failed (edge): No TTS provider available. Enable Edge TTS with: hermes pm install --extra edge-tts"
            ),
            .providerUnavailable
        )
        XCTAssertEqual(
            SpeakFailureKind.classify(
                status: 400, detail: "Text is required"
            ),
            .emptyText
        )
        // 合成失败（音色不匹配中文时的原文形态）
        XCTAssertEqual(
            SpeakFailureKind.classify(
                status: 400,
                detail: "TTS generation failed (edge): No audio was received"
            ),
            .server
        )
        XCTAssertEqual(
            SpeakFailureKind.classify(status: 500, detail: nil),
            .server
        )
        // 只有未开通投影到可用性精修
        XCTAssertEqual(
            SpeakFailureKind.providerUnavailable.outcome,
            .providerUnavailable
        )
        XCTAssertEqual(
            SpeakFailureKind.server.outcome, .failedOther
        )
    }

    // MARK: - 朗读文本预处理

    func testSpeechTextStripsMarkdown() {
        let markdown = """
        # 结论

        这是**重点**，还有[说明](https://example.com)与`代码`。

        ```swift
        let x = 1
        ```
        """
        let text = SpeechText.make(fromMarkdown: markdown)
        XCTAssertNotNil(text)
        XCTAssertFalse(text!.contains("#"))
        XCTAssertFalse(text!.contains("**"))
        XCTAssertFalse(text!.contains("`"))
        XCTAssertTrue(text!.contains("结论"))
        XCTAssertTrue(text!.contains("重点"))
        XCTAssertTrue(text!.contains("let x = 1"))
    }

    func testSpeechTextCollapsesBlankRuns() {
        let text = SpeechText.make(
            fromMarkdown: "第一段。\n\n\n\n第二段。"
        )
        XCTAssertEqual(text, "第一段。\n\n第二段。")
    }

    func testSpeechTextEmptyIsNil() {
        XCTAssertNil(SpeechText.make(fromMarkdown: ""))
        XCTAssertNil(SpeechText.make(fromMarkdown: "  \n\n  "))
        // 纯图片（alt 为空）剥完为空
        XCTAssertNil(SpeechText.make(fromMarkdown: "![](x.png)"))
    }

    func testSpeechTextLongTextPassesThroughWhole() {
        // 长文本策略钉：整段单次提交、不截断——服务
        // 端内部分块（探活实证），客户端切段无依据
        let sentence = "这是一句用来撑长度的中文回复内容。"
        let markdown = Array(repeating: sentence, count: 600)
            .joined(separator: "\n")
        let text = SpeechText.make(fromMarkdown: markdown)
        XCTAssertNotNil(text)
        XCTAssertEqual(
            text!.components(separatedBy: sentence).count - 1,
            600,
            "600 句必须一句不少地整段过"
        )
    }

    func testProviderDisplayName() {
        XCTAssertEqual(
            SpeechProviderDisplay.name(for: "edge"), "Edge TTS"
        )
        XCTAssertEqual(
            SpeechProviderDisplay.name(for: nil), "服务端决定"
        )
        XCTAssertEqual(
            SpeechProviderDisplay.name(for: "neutts"), "neutts"
        )
    }

    // MARK: - 播放状态机

    private let entryA = UUID()
    private let entryB = UUID()

    func testTapFromIdleStartsRequest() {
        var machine = SpeechPlaybackMachine()
        let effects = machine.tap(entryID: entryA)
        XCTAssertEqual(effects, [.startRequest(entryID: entryA)])
        XCTAssertEqual(machine.state, .requesting(entryID: entryA))
        XCTAssertEqual(machine.menuTitle(for: entryA), "停止朗读")
        XCTAssertEqual(machine.menuTitle(for: entryB), "朗读")
    }

    func testTapSameWhileRequestingOrPlayingStops() {
        var machine = SpeechPlaybackMachine()
        _ = machine.tap(entryID: entryA)
        XCTAssertEqual(machine.tap(entryID: entryA), [.tearDown])
        XCTAssertEqual(machine.state, .idle)

        _ = machine.tap(entryID: entryA)
        _ = machine.requestSucceeded(entryID: entryA)
        XCTAssertEqual(machine.state, .playing(entryID: entryA))
        XCTAssertEqual(machine.tap(entryID: entryA), [.tearDown])
        XCTAssertEqual(machine.state, .idle)
    }

    func testTapOtherSwitches() {
        var machine = SpeechPlaybackMachine()
        _ = machine.tap(entryID: entryA)
        _ = machine.requestSucceeded(entryID: entryA)
        let effects = machine.tap(entryID: entryB)
        XCTAssertEqual(
            effects,
            [.tearDown, .startRequest(entryID: entryB)]
        )
        XCTAssertEqual(machine.state, .requesting(entryID: entryB))
        XCTAssertTrue(machine.isActive(entryID: entryB))
        XCTAssertFalse(machine.isActive(entryID: entryA))
    }

    func testStaleReceiptsAreDropped() {
        var machine = SpeechPlaybackMachine()
        _ = machine.tap(entryID: entryA)
        // 已切到 B 后，A 的迟到回执不许动状态
        _ = machine.tap(entryID: entryB)
        XCTAssertEqual(machine.requestSucceeded(entryID: entryA), [])
        XCTAssertEqual(machine.state, .requesting(entryID: entryB))
        XCTAssertEqual(
            machine.requestFailed(entryID: entryA, message: "x"),
            []
        )
        XCTAssertEqual(machine.state, .requesting(entryID: entryB))
        // 播放结束同理只认当前条
        _ = machine.requestSucceeded(entryID: entryB)
        XCTAssertEqual(machine.playbackFinished(entryID: entryA), [])
        XCTAssertEqual(machine.state, .playing(entryID: entryB))
        XCTAssertEqual(machine.playbackFinished(entryID: entryB), [])
        XCTAssertEqual(machine.state, .idle)
    }

    func testFailureStateAndRetry() {
        var machine = SpeechPlaybackMachine()
        _ = machine.tap(entryID: entryA)
        _ = machine.requestFailed(
            entryID: entryA, message: "这次朗读没成功。"
        )
        XCTAssertEqual(
            machine.state,
            .failed(entryID: entryA, message: "这次朗读没成功。")
        )
        // 失败条目菜单回到「朗读」（再点即重试）
        XCTAssertEqual(machine.menuTitle(for: entryA), "朗读")
        XCTAssertFalse(machine.isActive(entryID: entryA))
        let effects = machine.tap(entryID: entryA)
        XCTAssertEqual(effects, [.startRequest(entryID: entryA)])
        XCTAssertEqual(machine.state, .requesting(entryID: entryA))
    }

    func testPlaybackFailureLandsInFailed() {
        var machine = SpeechPlaybackMachine()
        _ = machine.tap(entryID: entryA)
        _ = machine.requestSucceeded(entryID: entryA)
        _ = machine.playbackFailed(
            entryID: entryA, message: "这次朗读没成功。"
        )
        XCTAssertEqual(
            machine.state,
            .failed(entryID: entryA, message: "这次朗读没成功。")
        )
    }

    func testStopFromEachState() {
        var machine = SpeechPlaybackMachine()
        XCTAssertEqual(machine.stop(), [])
        _ = machine.tap(entryID: entryA)
        XCTAssertEqual(machine.stop(), [.tearDown])
        XCTAssertEqual(machine.state, .idle)
        // 失败态 stop 只清态、不发效果
        _ = machine.tap(entryID: entryA)
        _ = machine.requestFailed(entryID: entryA, message: "x")
        XCTAssertEqual(machine.stop(), [])
        XCTAssertEqual(machine.state, .idle)
        XCTAssertNil(machine.activeEntryID)
    }

    /// 播放条派生（台账 183）：显隐与文案只随状
    /// 态机走——静默不出条、请求中出条（正在准备
    /// 朗读）、播放中出条（正在朗读）、停止/失败/
    /// 自然结束收条（失败走通知口不占舱面）
    func testPlaybackBarDerivation() {
        var machine = SpeechPlaybackMachine()
        XCTAssertFalse(machine.showsPlaybackBar)
        XCTAssertNil(machine.playbackBarText)

        _ = machine.tap(entryID: entryA)
        XCTAssertTrue(machine.showsPlaybackBar)
        XCTAssertEqual(machine.playbackBarText, "正在准备朗读")

        _ = machine.requestSucceeded(entryID: entryA)
        XCTAssertTrue(machine.showsPlaybackBar)
        XCTAssertEqual(machine.playbackBarText, "正在朗读")

        // 条上停止＝状态机 stop 既有出口
        _ = machine.stop()
        XCTAssertFalse(machine.showsPlaybackBar)
        XCTAssertNil(machine.playbackBarText)

        // 请求失败：收条（人话走通知口）
        _ = machine.tap(entryID: entryA)
        _ = machine.requestFailed(
            entryID: entryA, message: "这次朗读没成功。"
        )
        XCTAssertFalse(machine.showsPlaybackBar)
        XCTAssertNil(machine.playbackBarText)

        // 自然播完：收条
        _ = machine.tap(entryID: entryA)
        _ = machine.requestSucceeded(entryID: entryA)
        _ = machine.playbackFinished(entryID: entryA)
        XCTAssertFalse(machine.showsPlaybackBar)
        XCTAssertNil(machine.playbackBarText)

        // 切换条目：条不灭、文案随新条请求态
        _ = machine.tap(entryID: entryA)
        _ = machine.requestSucceeded(entryID: entryA)
        _ = machine.tap(entryID: entryB)
        XCTAssertTrue(machine.showsPlaybackBar)
        XCTAssertEqual(machine.playbackBarText, "正在准备朗读")
    }

    /// 暂停/继续转换矩阵（D1）：pause 只认播放中、
    /// resume 只认已暂停；暂停中 finished/failed
    /// 不认（与引擎语义自洽）；条常驻＋文案「已暂
    /// 停」；菜单仍显「停止朗读」、isActive 认暂停
    func testPauseResumeMatrix() {
        var machine = SpeechPlaybackMachine()
        // 静默/请求中：pause/resume 都空转
        XCTAssertEqual(machine.pause(), [])
        XCTAssertEqual(machine.resume(), [])
        _ = machine.tap(entryID: entryA)
        XCTAssertEqual(machine.pause(), [])
        XCTAssertEqual(machine.resume(), [])
        XCTAssertEqual(machine.state, .requesting(entryID: entryA))

        _ = machine.requestSucceeded(entryID: entryA)
        // resume 在播放中空转
        XCTAssertEqual(machine.resume(), [])
        let effects = machine.pause()
        XCTAssertEqual(effects, [.pausePlayback])
        XCTAssertEqual(machine.state, .paused(entryID: entryA))
        // 暂停派生：条常驻、文案可区分、仍是活动条
        XCTAssertTrue(machine.showsPlaybackBar)
        XCTAssertEqual(machine.playbackBarText, "已暂停")
        XCTAssertTrue(machine.isActive(entryID: entryA))
        XCTAssertFalse(machine.isActive(entryID: entryB))
        XCTAssertEqual(machine.menuTitle(for: entryA), "停止朗读")
        XCTAssertEqual(machine.activeEntryID, entryA)
        // 重复 pause 空转
        XCTAssertEqual(machine.pause(), [])
        // 暂停中迟到 finished/failed 不许动状态
        XCTAssertEqual(machine.playbackFinished(entryID: entryA), [])
        XCTAssertEqual(
            machine.playbackFailed(entryID: entryA, message: "x"),
            []
        )
        XCTAssertEqual(machine.state, .paused(entryID: entryA))

        let resumeEffects = machine.resume()
        XCTAssertEqual(resumeEffects, [.resumePlayback])
        XCTAssertEqual(machine.state, .playing(entryID: entryA))
        XCTAssertEqual(machine.playbackBarText, "正在朗读")
    }

    /// 暂停中的 tap/stop（D1）：同条 tap＝停（全
    /// 拆）、异条 tap＝先拆后发切换、stop＝全拆回
    /// 静默（断点不豁免其余停因）
    func testPausedTapAndStop() {
        var machine = SpeechPlaybackMachine()
        _ = machine.tap(entryID: entryA)
        _ = machine.requestSucceeded(entryID: entryA)
        _ = machine.pause()
        XCTAssertEqual(machine.tap(entryID: entryA), [.tearDown])
        XCTAssertEqual(machine.state, .idle)

        _ = machine.tap(entryID: entryA)
        _ = machine.requestSucceeded(entryID: entryA)
        _ = machine.pause()
        let effects = machine.tap(entryID: entryB)
        XCTAssertEqual(
            effects, [.tearDown, .startRequest(entryID: entryB)]
        )
        XCTAssertEqual(machine.state, .requesting(entryID: entryB))

        var machine2 = SpeechPlaybackMachine()
        _ = machine2.tap(entryID: entryA)
        _ = machine2.requestSucceeded(entryID: entryA)
        _ = machine2.pause()
        XCTAssertEqual(machine2.stop(), [.tearDown])
        XCTAssertEqual(machine2.state, .idle)
        XCTAssertFalse(machine2.showsPlaybackBar)
    }
}
