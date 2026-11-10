import XCTest
@testable import OneDayCore

/// 会话三层分类闸（0.36.29，频道规格 §2 R0–R9）：
/// 规则链逐条钉＋命中顺序钉（先行规则压过后行）＋
/// 边界钉（来源缺失/未知、session_key 回落、前置
/// 闸的自由形态默认）。验收问句：每条测名即该条
/// 的「从哪来、为什么在这」。
final class SessionClassificationTests: XCTestCase {

    private let mainSession = "oneday-main-11111111-2222-3333-4444-555555555555"
    private let bucketA = "api-592647b9ae21ec54"
    private let bucketB = "api-e8c923beeaebed9c"

    private func session(
        id: String,
        source: String? = nil,
        sessionKey: String? = nil
    ) -> ServerSession {
        ServerSession(
            id: id, source: source, sessionKey: sessionKey,
            displayName: nil, serverTitle: nil, titleSource: nil,
            isArchived: nil, isPinned: nil, model: nil, profile: nil,
            startedAt: nil, endedAt: nil, endReason: nil,
            messageCount: nil, toolCallCount: nil,
            inputTokens: nil, outputTokens: nil
        )
    }

    /// 便捷口：main 传 nil＝用默认钦定（mainSession）；
    /// 要测「无钦定」须直调 SessionClassifier（见
    /// testR0MainPrefixIsMainEvenWithoutDesignation）
    private func classify(
        _ session: ServerSession,
        main: String? = nil,
        linked: Set<String> = []
    ) -> SessionLayer {
        SessionClassifier.classify(
            session: session,
            mainServerSessionID: main ?? mainSession,
            linkedThreadSessionIDs: linked
        )
    }

    // MARK: - R0 主线

    func testR0DesignatedMainSessionIsMain() {
        XCTAssertEqual(
            classify(session(id: mainSession, source: "api_server")),
            .main
        )
    }

    func testR0MainPrefixIsMainEvenWithoutDesignation() {
        // 钦定未回存（mainServerSessionID=nil）时只剩
        // 前缀信号——直调分类器本体传 nil（本文件助
        // 手的 main 参数 nil 是「用默认钦定」义，不合
        // 此测）
        let s = session(
            id: "oneday-main-99999999-8888-7777-6666-555555555555",
            source: "api_server"
        )
        XCTAssertEqual(
            SessionClassifier.classify(
                session: s,
                mainServerSessionID: nil,
                linkedThreadSessionIDs: []
            ),
            .main
        )
    }

    // R0 先于 R2：主线会话即便有线程关联（主线线程
    // 本体）也只归主线、不进我的对话名单重复出现
    func testR0BeatsLinkage() {
        XCTAssertEqual(
            classify(
                session(id: mainSession, source: "api_server"),
                linked: [mainSession]
            ),
            .main
        )
    }

    // MARK: - R1 合并桶

    func testR1MergeBucketsAreBucketLayer() {
        for bucket in [bucketA, bucketB] {
            XCTAssertEqual(
                classify(session(id: bucket, source: "api_server")),
                .mergeBucket
            )
        }
    }

    // R1 先于 R2：绑桶的存量线程按未链接处理是发送
    // 侧口径（0.27.0），分类侧桶恒为只读特例、不因
    // 有线程关联升入我的对话
    func testR1BeatsLinkage() {
        XCTAssertEqual(
            classify(
                session(id: bucketA, source: "api_server"),
                linked: [bucketA]
            ),
            .mergeBucket
        )
    }

    // MARK: - R2 本地关联（出生/收养）

    func testR2LinkedAPISessionIsMine() {
        let s = session(id: "api-abcdef0123456789", source: "api_server")
        XCTAssertEqual(classify(s, linked: [s.id]), .mine)
    }

    func testR2LinkedDashboardSessionIsMine() {
        // dashboard 本是 R7 频道面——有关联先升层
        // （规则序 R2 在 R7 之前，收养优先于来源）
        let s = session(id: "dash-session-1", source: "dashboard")
        XCTAssertEqual(classify(s, linked: [s.id]), .mine)
    }

    func testR2LinkedSessionWithoutSourceIsMine() {
        // 来源未知不压升层：字段缺失不许藏掉本人对话
        let s = session(id: "api-abcdef0123456789", source: nil)
        XCTAssertEqual(classify(s, linked: [s.id]), .mine)
    }

    // R2 例外：关联会话是 kanban 源——线程本体保留、
    // 分类跟随会话走 R5 系统，不升级
    func testR2ExceptionLinkedKanbanStaysSystem() {
        let s = session(id: "local-kanban-1", source: "kanban")
        XCTAssertEqual(classify(s, linked: [s.id]), .system)
    }

    // R2 例外：关联会话是平台源——跟随会话走 R6
    // 外部频道，不升级
    func testR2ExceptionLinkedPlatformGoesToItsChannel() {
        let s = session(id: "wa-123", source: "whatsapp")
        XCTAssertEqual(classify(s, linked: [s.id]), .channel("whatsapp"))
    }

    // R2 例外：关联会话是 cron 源——跟随 R5 系统
    func testR2ExceptionLinkedCronStaysSystem() {
        let s = session(id: "cron-run-1", source: "cron_job")
        XCTAssertEqual(classify(s, linked: [s.id]), .system)
    }

    // MARK: - R3 App 铸旁聊前缀

    func testR3AppSidePrefixIsMineWithoutLinkage() {
        // 本地线程已删、服务端行留痕：出生证明仍在
        let s = session(
            id: "oneday-side-11111111-2222-3333-4444-555555555555",
            source: "api_server"
        )
        XCTAssertEqual(classify(s), .mine)
    }

    // 规则序钉：R3 在 R5 之前——App 铸旁聊即便回执
    // source 异常也不被系统源吞掉
    func testR3BeatsSystemSource() {
        let s = session(
            id: "oneday-side-11111111-2222-3333-4444-555555555555",
            source: "kanban"
        )
        XCTAssertEqual(classify(s), .mine)
    }

    // MARK: - R4 部署侧铸 id

    func testR4BridgeCastOneDayIDsAreSystem() {
        // 桥铸点子生成会话（生产旁证 oneday-ideas-gen）
        XCTAssertEqual(
            classify(session(id: "oneday-ideas-gen", source: "api_server")),
            .system
        )
        // 同形新 id 按前缀段判、不枚举名单
        XCTAssertEqual(
            classify(session(id: "oneday-brief-gen-2", source: "api_server")),
            .system
        )
    }

    // MARK: - R5 结构性系统源

    func testR5StructuralSystemSources() {
        for source in ["kanban", "cron", "cron_job", "scheduler"] {
            XCTAssertEqual(
                classify(session(id: "sys-\(source)", source: source)),
                .system,
                "source=\(source) 应归系统运行"
            )
        }
    }

    // MARK: - R6 平台源

    func testR6PlatformSourcesGoToOwnChannel() {
        for platform in ["whatsapp", "telegram", "feishu", "wechat"] {
            XCTAssertEqual(
                classify(session(id: "ext-\(platform)", source: platform)),
                .channel(platform),
                "source=\(platform) 应归其外部频道"
            )
        }
    }

    // session_key 回落：source 缺失时平台段同值判
    // （session_key 形如 agent:main:whatsapp:dm:…）
    func testR6PlatformViaSessionKeyFallback() {
        let s = session(
            id: "ext-key-1", source: nil,
            sessionKey: "agent:main:telegram:dm:4242"
        )
        XCTAssertEqual(classify(s), .channel("telegram"))
    }

    // MARK: - R7 Hermes 人工表面

    func testR7DashboardAndCliAreHermesChannel() {
        XCTAssertEqual(
            classify(session(id: "dash-1", source: "dashboard")),
            .channel("hermes")
        )
        XCTAssertEqual(
            classify(session(id: "cli-1", source: "cli")),
            .channel("hermes")
        )
    }

    func testR7DashboardViaSessionKeyFallback() {
        let s = session(
            id: "dash-key-1", source: nil,
            sessionKey: "agent:main:dashboard:dm:7"
        )
        XCTAssertEqual(classify(s), .channel("hermes"))
    }

    // MARK: - R8 API 来源（前置闸默认频道）

    func testR8APIServerWithAPIPrefixIsHermesChannel() {
        XCTAssertEqual(
            classify(session(id: "api-0123456789abcdef", source: "api_server")),
            .channel("hermes")
        )
    }

    // 前置闸（规格 §8-3）：自由形态 id（人类可读名/
    // 纯 uuid）在 Dashboard 形态实测出结论前默认归
    // Hermes 频道——不许写死为系统运行（会错藏用户
    // 在网页端亲手开的会话）
    func testR8APIServerFreeFormIDsDefaultToHermesChannel() {
        XCTAssertEqual(
            classify(session(id: "my-weekend-plan", source: "api_server")),
            .channel("hermes")
        )
        XCTAssertEqual(
            classify(
                session(
                    id: "3f2504e0-4f89-11d3-9a0c-0305e82c3301",
                    source: "api_server"
                )
            ),
            .channel("hermes")
        )
    }

    func testR8APIServerViaSessionKeyFallback() {
        let s = session(
            id: "api-fedcba9876543210", source: nil,
            sessionKey: "agent:main:api_server:dm:api"
        )
        XCTAssertEqual(classify(s), .channel("hermes"))
    }

    // MARK: - R9 判不准

    func testR9UnknownSourceDefaultsToHermesChannel() {
        XCTAssertEqual(
            classify(session(id: "mystery-1", source: "smoke_test")),
            .channel("hermes")
        )
    }

    func testR9MissingSourceAndKeyDefaultsToHermesChannel() {
        XCTAssertEqual(
            classify(session(id: "mystery-2", source: nil, sessionKey: nil)),
            .channel("hermes")
        )
        // 空串 source 与残缺 session_key 同按缺失论
        XCTAssertEqual(
            classify(session(id: "mystery-3", source: "  ", sessionKey: "agent")),
            .channel("hermes")
        )
    }

    // MARK: - 来源归一与常量同源

    func testSourceNormalizationIsCaseAndWhitespaceInsensitive() {
        XCTAssertEqual(
            classify(session(id: "local-x", source: " Kanban ")),
            .system
        )
        XCTAssertEqual(
            SessionSources.sessionKeyPlatformSegment("agent:main:API_SERVER:dm:1"),
            "api_server"
        )
        XCTAssertNil(SessionSources.sessionKeyPlatformSegment("agent:main"))
        XCTAssertNil(SessionSources.sessionKeyPlatformSegment(nil))
    }

    // 常量同源钉（规格 §2 施工约束）：抽屉过滤集合
    // 与分类常量表必须是同一份值
    func testUserChannelSourcesAreSingleSourced() {
        XCTAssertEqual(
            DrawerSideChatFilter.userChannelSources,
            SessionSources.userChannels
        )
        XCTAssertTrue(SessionSources.isNonUserChannel("kanban"))
        XCTAssertTrue(SessionSources.isNonUserChannel("whatsapp"))
        XCTAssertFalse(SessionSources.isNonUserChannel("api_server"))
        XCTAssertFalse(SessionSources.isNonUserChannel(nil))
    }

    // MARK: - 分筐与频道成员

    func testPartitionKeepsOrderAndBuckets() {
        let rows = [
            session(id: mainSession, source: "api_server"),
            session(id: bucketA, source: "api_server"),
            session(id: "api-aaaa", source: "api_server"),
            session(id: "local-k", source: "kanban"),
            session(id: "oneday-side-11111111-2222-3333-4444-555555555555",
                    source: "api_server"),
            session(id: "wa-9", source: "whatsapp"),
        ]
        let part = SessionClassifier.partition(
            sessions: rows,
            mainServerSessionID: mainSession,
            linkedThreadSessionIDs: ["api-aaaa"]
        )
        XCTAssertEqual(part.main.map(\.id), [mainSession])
        XCTAssertEqual(part.mergeBuckets.map(\.id), [bucketA])
        XCTAssertEqual(part.mine.map(\.id), [
            "api-aaaa",
            "oneday-side-11111111-2222-3333-4444-555555555555",
        ])
        XCTAssertEqual(part.system.map(\.id), ["local-k"])
        XCTAssertEqual(part.channels["whatsapp"]?.map(\.id), ["wa-9"])
        // Hermes 频道计数＝普通频道行（0）＋合并桶（1）
        XCTAssertEqual(part.hermesChannelCount, 1)
    }

    func testHermesChannelMembershipPredicate() {
        XCTAssertTrue(SessionLayer.mergeBucket.isHermesChannelMember)
        XCTAssertTrue(SessionLayer.channel("hermes").isHermesChannelMember)
        XCTAssertFalse(SessionLayer.channel("whatsapp").isHermesChannelMember)
        XCTAssertFalse(SessionLayer.mine.isHermesChannelMember)
        XCTAssertFalse(SessionLayer.system.isHermesChannelMember)
        XCTAssertFalse(SessionLayer.main.isHermesChannelMember)
    }

    // 注册表：一期只有 Hermes；平台描述可派生、
    // 未知 id 无描述
    func testChannelRegistryPhaseOne() {
        XCTAssertEqual(ChannelRegistry.phaseOne, [ChannelRegistry.hermes])
        XCTAssertEqual(
            ChannelRegistry.descriptor(for: "hermes")?.iconAssetName,
            "LocalHermes"
        )
        XCTAssertEqual(
            ChannelRegistry.descriptor(for: "feishu")?.name, "飞书"
        )
        XCTAssertNil(ChannelRegistry.descriptor(for: "smoke_test"))
    }
}
