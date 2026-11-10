import XCTest
@testable import OneDayCore

/// 会话屏上文案（0.3.6 立、0.3.7 按卡 16/18 收紧）：
/// 标题只有内容名（display_name/首条消息摘要），无
/// 内容可名时「未命名会话」；时间＋条数只作副信息；
/// source 原始标识永不上屏。
final class SessionDisplayTests: XCTestCase {
    private var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        return cal
    }

    private func epoch(_ y: Int, _ mo: Int, _ d: Int, _ h: Int, _ mi: Int) -> Double {
        calendar.date(from: DateComponents(
            year: y, month: mo, day: d, hour: h, minute: mi
        ))!.timeIntervalSince1970
    }

    private func session(
        source: String? = "api_server",
        displayName: String? = nil,
        serverTitle: String? = nil,
        titleSource: String? = nil,
        isArchived: Bool? = nil,
        isPinned: Bool? = nil,
        startedAt: Double? = nil,
        endedAt: Double? = nil,
        messageCount: Int? = nil
    ) -> ServerSession {
        ServerSession(
            id: "sess-1", source: source, sessionKey: nil,
            displayName: displayName,
            serverTitle: serverTitle, titleSource: titleSource,
            isArchived: isArchived, isPinned: isPinned,
            model: nil, profile: nil,
            startedAt: startedAt, endedAt: endedAt, endReason: nil,
            messageCount: messageCount, toolCallCount: nil,
            inputTokens: nil, outputTokens: nil
        )
    }

    /// 0.3.7 收紧回归（用户真机纠正）：无 display_name
    /// 的会话标题不再是「今天 06:12 · 24 条」——标题
    /// 只给「未命名会话」，时间条数全部下沉副题；两
    /// 条同来源会话靠副题区分，原始标识两处都不出现。
    func testUnnamedSessionsUsePlaceholderTitleAndRichSubtitle() {
        let now = calendar.date(from: DateComponents(
            year: 2026, month: 11, day: 9, hour: 12
        ))!
        let a = session(
            startedAt: epoch(2026, 11, 9, 6, 12), messageCount: 24
        )
        let b = session(
            startedAt: epoch(2026, 11, 8, 21, 30),
            endedAt: epoch(2026, 11, 8, 22, 0), messageCount: 7
        )
        XCTAssertEqual(a.humanTitle(locale: Locale(identifier: "zh-Hans")), "未命名会话")
        XCTAssertEqual(b.humanTitle(locale: Locale(identifier: "zh-Hans")), "未命名会话")
        let subA = a.humanSubtitle(now: now, calendar: calendar, locale: Locale(identifier: "zh-Hans"))
        let subB = b.humanSubtitle(now: now, calendar: calendar, locale: Locale(identifier: "zh-Hans"))
        // 0.3.8 第 18 条改序：时间 · 条数 · 来源（来源
        // 退尾）；0.6.1 再删「进行中」段——Hermes 不写
        // ended_at、活跃判定全量恒真，是假数据（用户
        // 真机点名），a/b 都不再带状态段
        XCTAssertEqual(subA, "今天 06:12 · 24 条 · 其他应用")
        XCTAssertEqual(subB, "昨天 21:30 · 7 条 · 其他应用")
        XCTAssertNotEqual(subA, subB)
        XCTAssertFalse(subA.contains("api_server"))
        XCTAssertEqual(a.sourceLabel(locale: Locale(identifier: "zh-Hans")), "其他应用")
    }

    /// 人话 display_name 直接采用；标识符形态的
    /// display_name 视为原始名、回落未命名会话。
    func testHumanDisplayNameWinsAndIdentifierNameFallsBack() {
        let named = session(
            displayName: "帮我写周报",
            startedAt: epoch(2026, 11, 9, 6, 12), messageCount: 3
        )
        XCTAssertTrue(named.hasHumanName)
        XCTAssertEqual(named.humanTitle(locale: Locale(identifier: "zh-Hans")), "帮我写周报")
        let raw = session(
            displayName: "api_server",
            startedAt: epoch(2026, 11, 5, 9, 0), messageCount: nil
        )
        XCTAssertFalse(raw.hasHumanName)
        XCTAssertEqual(raw.humanTitle(locale: Locale(identifier: "zh-Hans")), "未命名会话")
    }

    /// 首条用户消息摘要（待裁 5 已裁口径）：取首个
    /// 非空行、压平空白、剥 Markdown 行首标记、超
    /// 24 字截断；摘要优先于未命名回落，但不压过
    /// 人话 display_name 之外——contentTitle 的优先
    /// 序＝摘要 → display_name → 未命名会话。
    func testContentSummaryTitle() {
        XCTAssertEqual(
            ServerSession.contentSummaryTitle("  帮我看看今天的日程  "),
            "帮我看看今天的日程"
        )
        XCTAssertEqual(
            ServerSession.contentSummaryTitle("\n\n## 修复登录页崩溃\n第二行不进标题"),
            "修复登录页崩溃"
        )
        XCTAssertEqual(
            ServerSession.contentSummaryTitle("这是一个非常长的首条消息用来验证截断行为是否正确工作"),
            "这是一个非常长的首条消息用来验证截断行为是否正确…"
        )
        XCTAssertNil(ServerSession.contentSummaryTitle("   \n  "))
        XCTAssertNil(ServerSession.contentSummaryTitle(nil))

        let plain = session()
        XCTAssertEqual(
            plain.contentTitle(firstUserMessage: "查一下服务器状态", locale: Locale(identifier: "zh-Hans")),
            "查一下服务器状态"
        )
        XCTAssertEqual(plain.contentTitle(firstUserMessage: nil, locale: Locale(identifier: "zh-Hans")), "未命名会话")
        let named = session(displayName: "帮我写周报")
        XCTAssertEqual(named.contentTitle(firstUserMessage: nil, locale: Locale(identifier: "zh-Hans")), "帮我写周报")
    }

    /// 兜底：未知来源只给「服务端」，原样标识永不透出。
    func testFallbacksNeverLeakRawIdentifiers() {
        let now = Date()
        // 时间/条数全缺时副题只剩来源段（0.6.1 起无
        // 「进行中」段可带）
        let bare = session(source: "some_internal_bus", endedAt: 1)
        XCTAssertEqual(bare.humanTitle(locale: Locale(identifier: "zh-Hans")), "未命名会话")
        XCTAssertEqual(
            bare.humanSubtitle(now: now, calendar: calendar, locale: Locale(identifier: "zh-Hans")), "服务端"
        )
        XCTAssertEqual(bare.sourceLabel(locale: Locale(identifier: "zh-Hans")), "服务端")
        XCTAssertEqual(session(source: nil).sourceLabel(locale: Locale(identifier: "zh-Hans")), "服务端")
        XCTAssertEqual(session(source: "dashboard").sourceLabel(locale: Locale(identifier: "zh-Hans")), "控制台")
        XCTAssertEqual(session(source: "cron").sourceLabel(locale: Locale(identifier: "zh-Hans")), "定时任务")
    }
    /// 首条 user 消息提取（0.6.1 派生标题数据源）：
    /// 按数组原序取第一条 role=user 的非空消息，
    /// assistant/空白消息跳过，全空回 nil
    func testFirstUserMessageExtraction() throws {
        func messages(_ json: String) throws -> [SessionMessage] {
            try JSONDecoder().decode(
                SessionMessagesResponse.self, from: Data(json.utf8)
            ).messages
        }
        let mixed = try messages("""
        {"messages": [
          {"id": 1, "role": "assistant", "content": "你好"},
          {"id": 2, "role": "user", "content": "  "},
          {"id": 3, "role": "user", "content": "第一条真问题"},
          {"id": 4, "role": "user", "content": "第二条不取"}
        ]}
        """)
        XCTAssertEqual(
            ServerSession.firstUserMessage(in: mixed), "第一条真问题"
        )
        let assistantOnly = try messages("""
        {"messages": [{"id": 1, "role": "assistant", "content": "只有助手消息"}]}
        """)
        XCTAssertNil(ServerSession.firstUserMessage(in: assistantOnly))
        XCTAssertNil(ServerSession.firstUserMessage(in: []))
    }

    /// 0.18.0 统一标题管线（专题二方案序①）：服务端
    /// 标题（user/llm/derived）压过本地派生；无服务
    /// 端标题才落本地派生→display_name→未命名。
    func testResolvedTitlePrefersServerTitleOverLocalDerivation() {
        let llm = session(serverTitle: "确认链路正常", titleSource: "llm")
        XCTAssertTrue(llm.hasServerTitle)
        XCTAssertEqual(
            llm.resolvedTitle(firstUserMessage: "只回复四个字：链路正常", locale: Locale(identifier: "zh-Hans")),
            "确认链路正常"
        )
        let user = session(serverTitle: "我手动改的名字", titleSource: "user")
        XCTAssertEqual(
            user.resolvedTitle(firstUserMessage: "随便什么首句", locale: Locale(identifier: "zh-Hans")),
            "我手动改的名字"
        )
        // derived 占位也是服务端标题：压过本地摘要
        let derived = session(
            serverTitle: "你好，用一句话说说西安的特", titleSource: "derived"
        )
        XCTAssertEqual(
            derived.resolvedTitle(firstUserMessage: "你好，用一句话说说西安的特色。", locale: Locale(identifier: "zh-Hans")),
            "你好，用一句话说说西安的特"
        )
        // 空白标题不算有标题（清洗后落回落层）
        let blank = session(serverTitle: "   ", titleSource: "llm")
        XCTAssertFalse(blank.hasServerTitle)
        XCTAssertEqual(
            blank.resolvedTitle(firstUserMessage: "查一下服务器状态", locale: Locale(identifier: "zh-Hans")),
            "查一下服务器状态"
        )
    }

    /// Qwen 会话回落链（立项档钉死）：llm 标题升级
    /// 被拒、title 为空时落本地派生；连派生都没有
    /// 才是「未命名会话」——不许拿原文首句冒充 AI 名
    /// 的意思是回落层如实是回落层（titleSource 为空、
    /// hasServerTitle 为假，来源可查）。
    func testResolvedTitleQwenFallbackChain() {
        let qwen = session(serverTitle: nil, titleSource: nil)
        XCTAssertFalse(qwen.hasServerTitle)
        XCTAssertEqual(
            qwen.resolvedTitle(firstUserMessage: "请仔细看这张图片并回答", locale: Locale(identifier: "zh-Hans")),
            "请仔细看这张图片并回答"
        )
        XCTAssertEqual(qwen.resolvedTitle(firstUserMessage: nil, locale: Locale(identifier: "zh-Hans")), "未命名会话")
        XCTAssertEqual(
            qwen.resolvedTitle(firstUserMessage: "   ", locale: Locale(identifier: "zh-Hans")), "未命名会话"
        )
    }

    /// 真实列表样本形态冻结（2026-11-09 晚带登录态
    /// 只读实拉、脱敏改 id/标题同型）：title/title_
    /// source/archived/pinned 必须解得出，分布与生
    /// 产一致（llm 多数、null 两条、归档/置顶位真值）。
    func testRealShapeSessionsPageDecodesTitleFields() throws {
        let json = """
        {"sessions": [
          {"id": "api-aaaa0001", "source": "api_server",
           "session_key": "k1", "display_name": null,
           "title": "确认链路正常", "title_source": "llm",
           "archived": false, "pinned": false,
           "model": "deepseek-flash", "profile": "default",
           "started_at": 1794200000, "ended_at": null,
           "message_count": 4, "tool_call_count": 0,
           "input_tokens": 120, "output_tokens": 40},
          {"id": "api-bbbb0002", "source": "dashboard",
           "session_key": "k2", "display_name": null,
           "title": "周报助手", "title_source": "user",
           "archived": false, "pinned": true,
           "model": "deepseek-flash", "profile": "default",
           "started_at": 1794190000, "ended_at": null,
           "message_count": 9, "tool_call_count": 1,
           "input_tokens": 800, "output_tokens": 300},
          {"id": "api-cccc0003", "source": "api_server",
           "session_key": "k3", "display_name": null,
           "title": null, "title_source": null,
           "archived": false, "pinned": false,
           "model": "Qwen3-30B-A3B-Instruct-2507-FP8",
           "profile": "default",
           "started_at": 1794180000, "ended_at": null,
           "message_count": 2, "tool_call_count": 0,
           "input_tokens": 50, "output_tokens": 10},
          {"id": "api-dddd0004", "source": "api_server",
           "session_key": "k4", "display_name": null,
           "title": "已归档的旧会话", "title_source": "llm",
           "archived": true, "pinned": false,
           "model": "deepseek-flash", "profile": "default",
           "started_at": 1794100000, "ended_at": 1794103600,
           "end_reason": "completed",
           "message_count": 6, "tool_call_count": 0,
           "input_tokens": 200, "output_tokens": 90}
        ], "total": 4, "limit": 100, "offset": 0}
        """
        let page = try JSONDecoder().decode(
            SessionsPage.self, from: Data(json.utf8)
        )
        XCTAssertEqual(page.sessions.count, 4)
        let byID = Dictionary(
            uniqueKeysWithValues: page.sessions.map { ($0.id, $0) }
        )
        XCTAssertEqual(byID["api-aaaa0001"]?.titleSource, "llm")
        XCTAssertEqual(
            byID["api-aaaa0001"]?.resolvedTitle(firstUserMessage: nil, locale: Locale(identifier: "zh-Hans")),
            "确认链路正常"
        )
        XCTAssertEqual(byID["api-bbbb0002"]?.titleSource, "user")
        XCTAssertEqual(byID["api-bbbb0002"]?.isPinned, true)
        XCTAssertNil(byID["api-cccc0003"]?.serverTitle)
        XCTAssertNil(byID["api-cccc0003"]?.titleSource)
        XCTAssertEqual(byID["api-dddd0004"]?.isArchived, true)
        XCTAssertEqual(byID["api-aaaa0001"]?.isArchived, false)
    }

    /// 0.17.0 单行行尾时间：与副题首段逐字一致（同一
    /// 实现派生），条数/来源不上行；无开始时间为 nil
    func testListTimeTextMatchesSubtitleFirstSegment() {
        let now = calendar.date(from: DateComponents(
            year: 2026, month: 11, day: 9, hour: 12
        ))!
        let today = session(
            startedAt: epoch(2026, 11, 9, 6, 12), messageCount: 24
        )
        XCTAssertEqual(
            today.listTimeText(now: now, calendar: calendar, locale: Locale(identifier: "zh-Hans")), "今天 06:12"
        )
        XCTAssertEqual(
            today.humanSubtitle(now: now, calendar: calendar, locale: Locale(identifier: "zh-Hans")),
            "今天 06:12 · 24 条 · 其他应用"
        )
        let yesterday = session(startedAt: epoch(2026, 11, 8, 21, 30))
        XCTAssertEqual(
            yesterday.listTimeText(now: now, calendar: calendar, locale: Locale(identifier: "zh-Hans")), "昨天 21:30"
        )
        let older = session(startedAt: epoch(2026, 10, 30, 9, 5))
        XCTAssertEqual(
            older.listTimeText(now: now, calendar: calendar, locale: Locale(identifier: "zh-Hans")), "10月30日 09:05"
        )
        // 无开始时间：nil（行尾留空，不编造）
        XCTAssertNil(session().listTimeText(now: now, calendar: calendar, locale: Locale(identifier: "zh-Hans")))
        // 本地行尾时间同源：与 LocalThreadSubtitle.text 首段一致
        let updated = calendar.date(from: DateComponents(
            year: 2026, month: 11, day: 9, hour: 6, minute: 12
        ))!
        XCTAssertEqual(
            LocalThreadSubtitle.timeText(
                updatedAt: updated, now: now, calendar: calendar,
                locale: Locale(identifier: "zh-Hans")
            ),
            "今天 06:12"
        )
        XCTAssertEqual(
            LocalThreadSubtitle.text(
                updatedAt: updated, messageCount: 24,
                now: now, calendar: calendar,
                locale: Locale(identifier: "zh-Hans")
            ),
            "今天 06:12 · 24 条"
        )
    }

    // 0.19.0 返工：抽屉旁聊区行显过滤（用户 22:45
    // 口径：只留本人在 App 里开的旁聊）——主线/归档
    // 先撤，关联会话来源非用户通道（kanban/平台）
    // 撤，无关联或来源未知恒放行（不因服务端不可
    // 达藏掉本人旁聊）
    func testDrawerSideChatFilterRules() {
        XCTAssertFalse(DrawerSideChatFilter.threadListed(
            isMainThread: true, isLocallyArchived: false, linkedSource: nil
        ))
        XCTAssertFalse(DrawerSideChatFilter.threadListed(
            isMainThread: false, isLocallyArchived: true, linkedSource: nil
        ))
        XCTAssertTrue(DrawerSideChatFilter.threadListed(
            isMainThread: false, isLocallyArchived: false, linkedSource: nil
        ))
        XCTAssertTrue(DrawerSideChatFilter.threadListed(
            isMainThread: false, isLocallyArchived: false, linkedSource: ""
        ))
    }

    func testDrawerSideChatFilterRejectsWorkerAndPlatformSources() {
        for source in ["kanban", "whatsapp", "telegram", "feishu", "cron"] {
            XCTAssertFalse(
                DrawerSideChatFilter.threadListed(
                    isMainThread: false, isLocallyArchived: false,
                    linkedSource: source
                ),
                "source \(source) 应撤出抽屉"
            )
        }
    }

    func testDrawerSideChatFilterKeepsUserChannelSources() {
        for source in ["api_server", "api", "dashboard", "web"] {
            XCTAssertTrue(
                DrawerSideChatFilter.threadListed(
                    isMainThread: false, isLocallyArchived: false,
                    linkedSource: source
                ),
                "source \(source) 是用户通道、应留"
            )
        }
    }
}
