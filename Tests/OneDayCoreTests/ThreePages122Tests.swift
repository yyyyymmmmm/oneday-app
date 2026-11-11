import OneDayCore
import XCTest

/// §122 三页修正包钉测：动态行内截断（句界/硬截/
/// 多字节/围栏守卫）、kanban 事件 kind 人话映射
/// （生产全集 10 种＋heartbeat 过滤＋未知兜底）、
/// 执行者内部名收口、点子采纳旁聊预填拼装。
final class ThreePages122Tests: XCTestCase {
    private let zh = Locale(identifier: "zh-Hans")

    // MARK: - 题三：行内正文截断

    func testRowBodyShortPostStaysFull() {
        let body = String(repeating: "短帖一句。", count: 10)
        let presentation = FeedBoard.rowBodyPresentation(body)
        XCTAssertFalse(presentation.isTruncated)
        XCTAssertEqual(presentation.text, body)
    }

    func testRowBodyExactlyAtLimitStaysFull() {
        let body = String(
            repeating: "字", count: FeedBoard.rowBodyCharacterLimit
        )
        let presentation = FeedBoard.rowBodyPresentation(body)
        XCTAssertFalse(presentation.isTruncated)
        XCTAssertEqual(presentation.text, body)
    }

    func testRowBodyLongPostCutsAtLastSentenceBoundary() {
        // 每句 5 字、共 500 字：上限 300 恰落句末
        let body = String(repeating: "正文一段。", count: 100)
        let presentation = FeedBoard.rowBodyPresentation(body)
        XCTAssertTrue(presentation.isTruncated)
        XCTAssertEqual(presentation.text.count, 300)
        XCTAssertTrue(presentation.text.hasSuffix("。"))
        XCTAssertFalse(presentation.text.hasSuffix("…"))
    }

    func testRowBodyNoBoundaryHardCutsWithEllipsis() {
        let body = String(repeating: "字", count: 500)
        let presentation = FeedBoard.rowBodyPresentation(body)
        XCTAssertTrue(presentation.isTruncated)
        XCTAssertEqual(
            presentation.text.count,
            FeedBoard.rowBodyCharacterLimit + 1
        )
        XCTAssertTrue(presentation.text.hasSuffix("…"))
    }

    func testRowBodyCountsCharactersNotBytes() {
        // emoji 按 Character 计：400 个必超限、硬截后
        // 301 个 Character（不许截半个字形）
        let body = String(repeating: "😀", count: 400)
        let presentation = FeedBoard.rowBodyPresentation(body)
        XCTAssertTrue(presentation.isTruncated)
        XCTAssertEqual(
            presentation.text.count,
            FeedBoard.rowBodyCharacterLimit + 1
        )
    }

    func testRowBodyEarlyBoundaryFallsBackToHardCut() {
        // 句界远在上限前半段、其后无句界长串：截到那
        // 里近乎空行，改走硬截＋省略号
        let body = "短句。" + String(repeating: "长", count: 500)
        let presentation = FeedBoard.rowBodyPresentation(body)
        XCTAssertTrue(presentation.isTruncated)
        XCTAssertTrue(presentation.text.hasSuffix("…"))
        XCTAssertEqual(
            presentation.text.count,
            FeedBoard.rowBodyCharacterLimit + 1
        )
    }

    func testRowBodyCutDoesNotStrandOpenCodeFence() {
        // 句界在围栏内也有：截点须回退到围栏开始之前，
        // 不许留下半截 ``` 把余下内容染成代码块
        let lead = "开头一段话先把背景交代清楚，这里是一个完整的句子。"
        let body = lead + "\n```\n"
            + String(repeating: "这是一行代码说明。", count: 40)
        let presentation = FeedBoard.rowBodyPresentation(body)
        XCTAssertTrue(presentation.isTruncated)
        XCTAssertFalse(presentation.text.contains("```"))
        XCTAssertEqual(presentation.text, lead)
    }

    func testRowShowsFullBodyFollowsTruncation() {
        let short = BridgeFeedPost(
            id: "f_s", kind: .research, title: "t",
            body: "两三句正文。", createdAt: 100
        )
        XCTAssertTrue(FeedBoard.rowShowsFullBody(short))
        let long = BridgeFeedPost(
            id: "f_l", kind: .research, title: "t",
            body: String(repeating: "正文一段。", count: 100),
            createdAt: 100
        )
        XCTAssertFalse(FeedBoard.rowShowsFullBody(long))
    }

    // MARK: - 题一连带：事件 kind 人话映射

    func testEventKindProductionSetMapsToHumanLabels() {
        let expected: [String: String] = [
            "created": "任务已创建",
            "claimed": "已认领",
            "spawned": "已开始执行",
            "owner_admitted": "已确认接手",
            "worker_bound": "执行者已就位",
            "worker_result": "已交回结果",
            "review_requested": "已发起复核",
            "commented": "有新留言",
            "completed": "已完成",
        ]
        for (kind, label) in expected {
            XCTAssertEqual(
                KanbanEventKind.label(for: kind, locale: zh), label,
                "kind \(kind) 应映射为「\(label)」"
            )
        }
    }

    func testEventKindHeartbeatIsFilteredOut() {
        XCTAssertNil(KanbanEventKind.label(for: "heartbeat", locale: zh))
    }

    func testEventKindUnknownFallsBackWithoutRawEnglish() {
        XCTAssertEqual(
            KanbanEventKind.label(for: "some_raw_kind", locale: zh),
            "有新进展"
        )
        XCTAssertEqual(
            KanbanEventKind.label(for: "", locale: zh), "有新进展"
        )
    }

    func testEvidenceItemsUseMappedTitlesAndSkipHeartbeat() throws {
        let json = """
        {"task": {"id": "t_1", "title": "样本", "status": "done",
                  "created_at": 1794150000},
         "events": [
           {"id": 1, "kind": "created", "created_at": 1794150000},
           {"id": 2, "kind": "heartbeat", "created_at": 1794150100},
           {"id": 3, "kind": "worker_bound", "created_at": 1794150200},
           {"id": 4, "kind": "owner_admitted", "created_at": 1794150300}
         ]}
        """
        let detail = try JSONDecoder().decode(
            KanbanTaskDetail.self, from: Data(json.utf8)
        )
        let events = detail.evidenceItems(locale: zh)
            .filter { $0.kind == .event }
        XCTAssertEqual(
            events.map(\.title),
            ["已确认接手", "执行者已就位", "任务已创建"]
        )
    }

    // MARK: - 题一连带：执行者内部名收口

    func testDisplayAssigneeHidesDefaultProfile() {
        let task = KanbanTask(
            id: "t_x", title: "样本", status: "done",
            assignee: "default"
        )
        XCTAssertNil(task.displayAssignee)
    }

    func testDisplayAssigneeKeepsNamedProfile() {
        let task = KanbanTask(
            id: "t_x", title: "样本", status: "running",
            assignee: "researcher"
        )
        XCTAssertEqual(task.displayAssignee, "researcher")
    }

    func testDisplayAssigneeNilAndEmptyHide() {
        XCTAssertNil(KanbanTask(id: "t_x").displayAssignee)
        XCTAssertNil(
            KanbanTask(id: "t_x", assignee: "").displayAssignee
        )
    }

    // MARK: - 题一：采纳旁聊预填

    private func idea(
        source: IdeaSource = .generated,
        detail: String = "给双十一列一份购买清单。",
        evidence: String = "对话里你说过想趁双十一把会员开齐",
        deliverables: [BridgeIdeaDeliverable] = []
    ) -> BridgeIdea {
        BridgeIdea(
            id: "i_1", title: "双11 AI 会员购买清单",
            detail: detail, goalId: nil, createdAt: 100,
            source: source, evidence: evidence,
            status: .pending, deliverables: deliverables
        )
    }

    func testIdeaChatPrefillFullAssembly() {
        let text = IdeaChatPrefill.make(
            idea: idea(deliverables: [
                BridgeIdeaDeliverable(
                    name: "购买清单表格", summary: "列清要买的会员"
                ),
                BridgeIdeaDeliverable(name: "时间节点提醒"),
            ]),
            locale: zh
        )
        XCTAssertTrue(text.hasPrefix("我们来聊聊这个点子：《双11 AI 会员购买清单》"))
        XCTAssertTrue(text.contains("给双十一列一份购买清单。"))
        XCTAssertTrue(text.contains("依据：对话里你说过想趁双十一把会员开齐"))
        XCTAssertTrue(text.contains("包含的内容："))
        XCTAssertTrue(text.contains("· 购买清单表格：列清要买的会员"))
        XCTAssertTrue(text.contains("· 时间节点提醒"))
        XCTAssertFalse(text.contains("· 时间节点提醒："))
    }

    func testIdeaChatPrefillOmitsEmptySections() {
        // 手记卡：无依据、无交付物、无详情——只剩开场句
        let text = IdeaChatPrefill.make(
            idea: idea(source: .manual, detail: "", evidence: ""),
            locale: zh
        )
        XCTAssertEqual(text, "我们来聊聊这个点子：《双11 AI 会员购买清单》")
    }

    func testIdeaChatPrefillManualIdeaSkipsEvidence() {
        // 手记卡即使带了 evidence 也不进预填（与详情页
        // 依据小节只对生成卡出现的口径一致）
        let text = IdeaChatPrefill.make(
            idea: idea(source: .manual), locale: zh
        )
        XCTAssertFalse(text.contains("依据："))
    }
}
