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
            inputTokens: nil, outputTokens: nil,
            runtimeRevision: nil, runtimeGeneration: nil
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

    // MARK: - R3b 伴生铸 AI 旁聊（P2 会话包收养）

    // 出生证明收养：伴生门面铸的 oneday-ai- 会话、无
    // 本地关联也归我的对话（与用户手开的旁聊同列）
    func testR3bAICastPrefixIsMineWithoutLinkage() {
        let s = session(
            id: "oneday-ai-0123456789abcdef0123456789abcdef",
            source: "api_server"
        )
        XCTAssertEqual(classify(s), .mine)
    }

    // 规则序钉：R3b 在 R4 之前——同为 oneday- 前缀，
    // AI 铸归我的对话、桥铸系统会话仍归系统（R4 本体
    // 不被本条连带放宽，见 testR4BridgeCastOneDayIDs）
    func testR3bBeatsR4ButIdeasGenStaysSystem() {
        XCTAssertEqual(
            classify(session(
                id: "oneday-ai-aaaa", source: "api_server")),
            .mine
        )
        XCTAssertEqual(
            classify(session(
                id: "oneday-ideas-gen", source: "api_server")),
            .system
        )
    }

    // 判据只认出生证明：AI 旁聊与探针同为 api_server
    // 来源——无 oneday-ai- 标记的同源会话一律旧规
    // （探针 api_ 归系统、自由形态归频道），不许因
    // 「也是机器开的」借道升层
    func testR3bNoMarkNoAdoption() {
        XCTAssertEqual(
            classify(session(
                id: "api_1730000000_deadbeef", source: "api_server")),
            .system
        )
        XCTAssertEqual(
            classify(session(
                id: "ai-side-chat-1", source: "api_server")),
            .channel(ChannelRegistry.hermesChannelID)
        )
    }

    // 规则序钉：R3b 在 R5 之前——AI 铸旁聊即便回执
    // source 异常也不被系统源吞掉（与 R3 同纪律）
    func testR3bBeatsSystemSource() {
        let s = session(
            id: "oneday-ai-0123456789abcdef0123456789abcdef",
            source: "kanban"
        )
        XCTAssertEqual(classify(s), .mine)
    }

    // 分筐钉：partition 把 AI 铸会话放进 mine 筐、
    // 与用户手开旁聊同筐同列，频道/系统筐不掺
    func testR3bPartitionPutsAICastInMineBucket() {
        let ai = session(
            id: "oneday-ai-0123456789abcdef0123456789abcdef",
            source: "api_server"
        )
        let own = session(
            id: "oneday-side-11111111-2222-3333-4444-555555555555",
            source: "api_server"
        )
        let probe = session(
            id: "api_1730000000_deadbeef", source: "api_server"
        )
        let partition = SessionClassifier.partition(
            sessions: [ai, own, probe],
            mainServerSessionID: mainSession,
            linkedThreadSessionIDs: []
        )
        XCTAssertEqual(partition.mine.map(\.id), [ai.id, own.id])
        XCTAssertEqual(partition.system.map(\.id), [probe.id])
        XCTAssertEqual(partition.hermesChannelCount, 0)
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

    // MARK: - R4b 机器铸造前缀（对账 A1/A2 收紧）

    // run_ 前缀＝网关 runs 落形：点子/晨报生成轮次
    // 与验收运行（对账存量 #42–46，5/5 全机器）
    func testR4bRunPrefixIsSystem() {
        XCTAssertEqual(
            classify(session(
                id: "run_2e593f5fb9c94882a8216b75300be1df",
                source: "api_server"
            )),
            .system
        )
        // 同形新 id 按前缀判、不枚举名单（晨报次日
        // 新铸同理入系统、不再往频道添条）
        XCTAssertEqual(
            classify(session(
                id: "run_00000000000000000000000000000000",
                source: "api_server"
            )),
            .system
        )
    }

    // api_ 下划线形＝探针铸造（对账存量 #52/#53
    // 静默流探针，2/2）
    func testR4bAPIUnderscorePrefixIsSystem() {
        XCTAssertEqual(
            classify(session(
                id: "api_1794331033_cd758152",
                source: "api_server"
            )),
            .system
        )
    }

    // 串扰钉：api- 连字符（R8 标准形、联调与用户
    // 接口会话）归频道，api_ 下划线归系统——两个
    // 前缀只差第三字符，不许互相串
    func testR4bUnderscoreAndHyphenFormsDoNotCross() {
        XCTAssertEqual(
            classify(session(
                id: "api-1794331033cd758152",
                source: "api_server"
            )),
            .channel("hermes")
        )
        XCTAssertEqual(
            classify(session(
                id: "api_1794331033_cd758152",
                source: "api_server"
            )),
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

    // 对账 A6 防患钉：kanban 行 source 本体缺失时，
    // 有效来源回落 session_key 平台段得 "local"——
    // 必须由 R5 结构性系统源兜住归系统，不许穿透
    // R9 落 Hermes 频道错显；即便有本地关联，R2 例
    // 外（非用户通道）同样不升级
    func testR5LocalFallbackSegmentIsSystem() {
        let s = session(
            id: "local-1439bc1d89730af939d1611ed8a4c3ce7073d200251b710e84126c82ada9b03a",
            source: nil,
            sessionKey: "agent:main:local:dm:local-1439bc1d89730af939d1611ed8a4c3ce7073d200251b710e84126c82ada9b03a"
        )
        XCTAssertEqual(
            SessionSources.effectiveSource(
                source: s.source, sessionKey: s.sessionKey
            ),
            "local"
        )
        XCTAssertEqual(classify(s), .system)
        XCTAssertEqual(classify(s, linked: [s.id]), .system)
    }

    // MARK: - R6 平台源

    func testR6PlatformSourcesGoToOwnChannel() {
        for platform in ["whatsapp", "telegram", "feishu", "weixin"] {
            XCTAssertEqual(
                classify(session(id: "ext-\(platform)", source: platform)),
                .channel(platform),
                "source=\(platform) 应归其外部频道"
            )
        }
    }

    // 2026-11-13 对账（规格 §2.3）：旧名 wechat/qq 是
    // 别名，频道 id 恒归一为网关实值 weixin/qqbot——
    // 不许再穿透落 Hermes 频道
    func testR6LegacyAliasesCanonicalizeToGatewayNames() {
        XCTAssertEqual(
            classify(session(id: "ext-wx", source: "wechat")),
            .channel("weixin"))
        XCTAssertEqual(
            classify(session(id: "ext-qq", source: "qq")),
            .channel("qqbot"))
        XCTAssertEqual(
            classify(session(id: "ext-qqbot", source: "qqbot")),
            .channel("qqbot"))
        let keyForm = session(
            id: "ext-wx-key", source: nil,
            sessionKey: "agent:main:weixin:dm:888")
        XCTAssertEqual(classify(keyForm), .channel("weixin"))
    }

    // 补齐的平台（规格 §2.3 缺项表）逐个钉住归频道
    func testR6NewlyCoveredPlatformsGoToOwnChannel() {
        for platform in [
            "whatsapp_cloud", "email", "mattermost", "wecom_callback",
            "bluebubbles", "yuanbao", "line", "teams", "google_chat",
            "photon", "simplex", "dingtalk", "wecom", "discord",
            "slack", "signal", "matrix", "sms",
        ] {
            XCTAssertEqual(
                classify(session(id: "ext-\(platform)", source: platform)),
                .channel(platform),
                "source=\(platform) 应归其外部频道"
            )
        }
    }

    // 注册表：抽屉恒显清单与图标登记（组版并集：
    // 飞书二期上行、微信行下架＋令牌四家续登；平台
    // 图标只许官方原图登记过的有值，未登记的平台
    // 回 nil 不许仿绘顶替）
    func testChannelRegistryDrawerListAndIcons() {
        XCTAssertEqual(
            ChannelRegistry.drawerList.map(\.id),
            ["hermes", "telegram", "feishu", "dingtalk",
             "qqbot", "discord", "slack"])
        XCTAssertEqual(
            ChannelRegistry.descriptor(for: "telegram")?.iconAssetName,
            "ChannelTelegram")
        XCTAssertEqual(
            ChannelRegistry.descriptor(for: "feishu")?.iconAssetName,
            "ChannelFeishu")
        XCTAssertEqual(
            ChannelRegistry.descriptor(for: "feishu")?.name, "飞书")
        // §241 改名：Hermes 频道用户面展示名＝「服务
        // 器会话」，内部 id 恒为 hermes 不动
        XCTAssertEqual(
            ChannelRegistry.descriptor(for: "hermes")?.name, "服务器会话")
        XCTAssertEqual(ChannelRegistry.hermes.id, "hermes")
        XCTAssertNil(
            SessionSources.platformIconAssetName("weixin"))
        XCTAssertEqual(
            ChannelRegistry.pairingKind(for: "telegram"), .token)
        XCTAssertEqual(
            ChannelRegistry.pairingKind(for: "feishu"), .token)
        XCTAssertEqual(
            ChannelRegistry.pairingKind(for: "hermes"), .none)
    }

    // 二期令牌四家（钉钉/QQ/Discord/Slack）：注册表
    // 描述、官方图标登记与配对形态逐家钉住
    func testChannelRegistryTokenBatch() {
        let expected: [(id: String, name: String, asset: String)] = [
            ("dingtalk", "钉钉", "ChannelDingtalk"),
            ("qqbot", "QQ", "ChannelQQ"),
            ("discord", "Discord", "ChannelDiscord"),
            ("slack", "Slack", "ChannelSlack"),
        ]
        for item in expected {
            let descriptor = ChannelRegistry.descriptor(for: item.id)
            XCTAssertEqual(descriptor?.name, item.name,
                           "\(item.id) 频道名")
            XCTAssertEqual(descriptor?.iconAssetName, item.asset,
                           "\(item.id) 官方图标资产")
            XCTAssertEqual(
                SessionSources.platformIconAssetName(item.id),
                item.asset, "\(item.id) 平台图标登记")
            XCTAssertEqual(
                ChannelRegistry.pairingKind(for: item.id), .token,
                "\(item.id) 配对形态为令牌型")
        }
        // QQ 的历史别名 qq 同样指到官方图标与频道描述
        XCTAssertEqual(
            SessionSources.platformIconAssetName("qq"), "ChannelQQ")
        XCTAssertEqual(
            ChannelRegistry.descriptor(for: "qqbot")?.pageSubtitle,
            "在 QQ 里和你的智能体聊的对话")
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

    /// §198 题一钉（全量口径）：显行闸与名单拉取共
    /// 用 limit 100 窗口时的生产失效形态——按最近活
    /// 动取的前 100 条全是 api_ 探针（R4b 判系统）、
    /// 真频道成员全沉在窗口外，窗口分类恒 0；同一分
    /// 类器吃全量集必须把成员数全数得出（抽屉闸已
    /// 改读全量同源，本测钉「全量才有数」这一前提）
    func testPartitionFullSetCountsChannelMembersBeyondWindow() {
        let probes = (0..<100).map {
            session(id: "api_probe\($0)", source: "api_server")
        }
        let members = (0..<25).map {
            session(id: "web-\($0)", source: "dashboard")
        }
        let all = probes + members
        let windowPartition = SessionClassifier.partition(
            sessions: Array(all.prefix(100)),
            mainServerSessionID: mainSession,
            linkedThreadSessionIDs: []
        )
        XCTAssertEqual(windowPartition.hermesChannelCount, 0)
        let fullPartition = SessionClassifier.partition(
            sessions: all,
            mainServerSessionID: mainSession,
            linkedThreadSessionIDs: []
        )
        XCTAssertEqual(fullPartition.hermesChannelCount, 25)
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
