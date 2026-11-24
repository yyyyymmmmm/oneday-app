import OneDayCore
import XCTest

/// §177 动态/点子对标包钉测：点子分类解析与分类小
/// 节分组（硬验收：列表全程分类小节、无分类卡不进
/// 列表、无无分类区）、分类字段解码与新建请求携带。
/// 动态两项（去日期分组/帖面同色）是纯视图结构，无
/// Core 口径可钉，验收走真机与 DESIGN §177 记账。
/// §459 增补：domain 十二值分节（节序/节名与服务端
/// DOMAIN_LABELS 逐字同）、旧 category 折算兜底、
/// kind 三态解码、categoryLabel 字段解码。
final class FeedIdeasParityTests: XCTestCase {

    private let now: Double = 1_000_000

    private func idea(
        _ id: String, category: String?,
        status: IdeaStatus = .pending,
        createdAt: Double = 100
    ) -> BridgeIdea {
        BridgeIdea(
            id: id, title: id, detail: "", goalId: nil,
            createdAt: createdAt, status: status,
            category: category
        )
    }

    // MARK: - 分类解析

    func testIdeaCategoryResolvesKeysToTitles() {
        let expected: [(String, String)] = [
            ("health", "健康"),
            ("relationships", "人际关系"),
            ("finance", "财务"),
            ("career", "事业"),
            ("interest", "兴趣"),
            ("efficiency", "效率提升"),
            ("other", "其他"),
        ]
        for (index, pair) in expected.enumerated() {
            let resolved = IdeaCategory.resolve(pair.0)
            XCTAssertEqual(resolved?.title, pair.1)
            XCTAssertEqual(resolved?.knownOrder, index)
        }
    }

    func testIdeaCategoryResolvesTitlesToSameKnown() {
        XCTAssertEqual(
            IdeaCategory.resolve("人际关系"),
            IdeaCategory.resolve("relationships")
        )
        XCTAssertEqual(
            IdeaCategory.resolve(" 财务 ")?.title, "财务"
        )
    }

    func testIdeaCategoryBlankIsNoCategory() {
        XCTAssertNil(IdeaCategory.resolve(nil))
        XCTAssertNil(IdeaCategory.resolve(""))
        XCTAssertNil(IdeaCategory.resolve("   "))
    }

    func testIdeaCategoryUnknownPassesThroughVerbatim() {
        // 「购物」是对标规格在 Muse 截图实证过的分
        // 类、不在已知七类表内：原样成段、不丢不改
        let shopping = IdeaCategory.resolve("购物")
        XCTAssertEqual(shopping?.title, "购物")
        XCTAssertNil(shopping?.knownOrder)
    }

    // MARK: - 分类小节

    func testCategorySectionsGroupByCategory() {
        let sections = IdeaBoard.categorySections([
            idea("a", category: "finance"),
            idea("b", category: "health"),
            idea("c", category: "finance"),
        ], now: now)
        XCTAssertEqual(
            sections.map(\.category.title), ["健康", "财务"]
        )
        XCTAssertEqual(sections[1].ideas.map(\.id), ["a", "c"])
    }

    func testCategorySectionsKnownOrderBeatsInputOrder() {
        // 输入序事业在前、健康在后：小节序仍按定表
        // （健康 0 < 事业 3），不随到达顺序漂
        let sections = IdeaBoard.categorySections([
            idea("x", category: "career"),
            idea("y", category: "health"),
        ], now: now)
        XCTAssertEqual(
            sections.map(\.category.title), ["健康", "事业"]
        )
    }

    func testCategorySectionsUnknownAfterKnown() {
        let sections = IdeaBoard.categorySections([
            idea("u1", category: "购物"),
            idea("k", category: "other"),
            idea("u2", category: "旅行"),
        ], now: now)
        XCTAssertEqual(sections.first?.category.title, "其他")
        XCTAssertEqual(
            Set(sections.dropFirst().map(\.category.title)),
            ["购物", "旅行"]
        )
    }

    func testCategorySectionsExcludeUncategorized() {
        // 硬验收：无分类的卡不进列表、不设散卡区
        let sections = IdeaBoard.categorySections([
            idea("n1", category: nil),
            idea("n2", category: ""),
            idea("n3", category: "  "),
            idea("y", category: "health"),
        ], now: now)
        XCTAssertEqual(sections.count, 1)
        XCTAssertEqual(sections[0].ideas.map(\.id), ["y"])
        // 全无分类 → 零小节（页面走空态，不摆散卡）
        XCTAssertTrue(
            IdeaBoard.categorySections(
                [idea("n", category: nil)], now: now
            ).isEmpty
        )
    }

    func testCategorySectionsVisibilityWindow() {
        let sections = IdeaBoard.categorySections([
            idea("p", category: "health", createdAt: 10),
            idea(
                "a1", category: "health", status: .adopted,
                createdAt: now - 24 * 3600
            ),
            idea(
                "a2", category: "health", status: .adopted,
                createdAt: now - 31 * 24 * 3600
            ),
            idea(
                "d", category: "health", status: .dismissed,
                createdAt: now
            ),
            idea(
                "e", category: "health", status: .expired,
                createdAt: now
            ),
        ], now: now)
        XCTAssertEqual(sections.count, 1)
        XCTAssertEqual(
            Set(sections[0].ideas.map(\.id)), ["p", "a1"]
        )
    }

    func testCategorySectionsNewestFirstWithinSection() {
        let sections = IdeaBoard.categorySections([
            idea("old", category: "finance", createdAt: 100),
            idea("new", category: "finance", createdAt: 300),
            idea("mid", category: "finance", createdAt: 200),
        ], now: now)
        XCTAssertEqual(
            sections[0].ideas.map(\.id), ["new", "mid", "old"]
        )
    }

    // MARK: - 字段通路

    func testBridgeIdeaDecodesCategoryField() throws {
        let withCategory = """
        {"id": "i_1", "title": "t", "detail": "d",
         "goalId": null, "createdAt": 100,
         "category": "relationships"}
        """
        let decoded = try JSONDecoder().decode(
            BridgeIdea.self,
            from: Data(withCategory.utf8)
        )
        XCTAssertEqual(decoded.category, "relationships")

        let without = """
        {"id": "i_2", "title": "t", "detail": "d",
         "goalId": null, "createdAt": 100}
        """
        let legacy = try JSONDecoder().decode(
            BridgeIdea.self,
            from: Data(without.utf8)
        )
        XCTAssertNil(legacy.category)
    }

    func testCreateRequestCarriesCategory() throws {
        let withCategory = BridgeIdeaCreateRequest.make(
            title: "t", detail: "", goalId: nil,
            category: "finance"
        )
        let json = String(
            data: try JSONEncoder().encode(withCategory),
            encoding: .utf8
        ) ?? ""
        XCTAssertTrue(json.contains("\"category\":\"finance\""))

        let without = BridgeIdeaCreateRequest.make(
            title: "t", detail: "", goalId: nil
        )
        let legacyJSON = String(
            data: try JSONEncoder().encode(without),
            encoding: .utf8
        ) ?? ""
        XCTAssertFalse(legacyJSON.contains("category"))
        XCTAssertNil(without.category)
    }

    // MARK: - §459 domain 分节

    private func domainIdea(
        _ id: String, domain: String?,
        category: String? = nil,
        status: IdeaStatus = .pending,
        createdAt: Double = 100
    ) -> BridgeIdea {
        BridgeIdea(
            id: id, title: id, detail: "", goalId: nil,
            createdAt: createdAt, status: status,
            category: category, domain: domain
        )
    }

    func testDomainTitlesMatchServerLabels() {
        // 与服务端 DOMAIN_LABELS 逐字同（十二值全集）
        let expected: [(IdeaDomain, String)] = [
            (.personalProductivity, "个人效率"),
            (.entertainment, "娱乐"),
            (.shopping, "购物"),
            (.finance, "财务"),
            (.relationships, "人际关系"),
            (.health, "健康"),
            (.career, "事业"),
            (.homeAutomation, "智能家居"),
            (.connectDevices, "设备连接"),
            (.creationMedia, "创作媒体"),
            (.family, "家庭"),
            (.goalScoped, "目标相关"),
        ]
        XCTAssertEqual(IdeaDomain.allCases.count, 12)
        for (domain, title) in expected {
            XCTAssertEqual(domain.title, title)
        }
        // 节序＝声明序（CaseIterable 序）
        XCTAssertEqual(
            IdeaDomain.allCases.map(\.rawValue),
            [
                "personal_productivity", "entertainment",
                "shopping", "finance", "relationships",
                "health", "career", "home_automation",
                "connect_devices", "creation_media",
                "family", "goal_scoped",
            ]
        )
    }

    func testDomainResolvePrefersCardDomain() {
        let idea = domainIdea(
            "d1", domain: "shopping", category: "health"
        )
        XCTAssertEqual(IdeaDomain.resolve(idea), .shopping)
    }

    func testDomainResolveFoldsLegacyCategory() {
        // 与服务端 _LEGACY_CATEGORY_DOMAIN 逐项同
        let folds: [(String, IdeaDomain)] = [
            ("health", .health),
            ("relationships", .relationships),
            ("finance", .finance),
            ("career", .career),
            ("efficiency", .personalProductivity),
            ("interest", .entertainment),
            ("other", .personalProductivity),
        ]
        for (category, domain) in folds {
            XCTAssertEqual(
                IdeaDomain.resolve(domainIdea("x", domain: nil, category: category)),
                domain
            )
        }
        // 未知 domain 值不直用、走 category 折算
        XCTAssertEqual(
            IdeaDomain.resolve(
                domainIdea("y", domain: "nope", category: "finance")
            ),
            .finance
        )
        // 两字段皆缺：默认域（与服务端缺省同值），不丢卡
        XCTAssertEqual(
            IdeaDomain.resolve(domainIdea("z", domain: nil)),
            .personalProductivity
        )
    }

    func testDomainSectionsOrderAndNoCardDropped() {
        let ideas = [
            domainIdea("a", domain: "goal_scoped", createdAt: 90),
            domainIdea("b", domain: "health", createdAt: 80),
            domainIdea("c", domain: nil, createdAt: 70),
            domainIdea("d", domain: "health", createdAt: 95),
            domainIdea(
                "e", domain: "finance", status: .dismissed
            ),
        ]
        let sections = IdeaBoard.domainSections(ideas, now: now)
        // 节序走十二域定序：个人效率（默认折算）→健康→目标相关
        XCTAssertEqual(
            sections.map(\.domain),
            [.personalProductivity, .health, .goalScoped]
        )
        // 节内 createdAt 倒序
        XCTAssertEqual(sections[1].ideas.map(\.id), ["d", "b"])
        // 可见卡全数在节（已忽略的不进、其余不丢）
        XCTAssertEqual(
            sections.flatMap(\.ideas).map(\.id).sorted(),
            ["a", "b", "c", "d"]
        )
    }

    // MARK: - §459 kind 与 categoryLabel 解码

    func testIdeaDecodesDomainLabelKind() throws {
        let json = #"""
        {"id": "k1", "title": "t", "detail": "",
         "createdAt": 5, "domain": "career",
         "categoryLabel": "服务器运维", "kind": "routine"}
        """#
        let idea = try JSONDecoder().decode(
            BridgeIdea.self, from: Data(json.utf8)
        )
        XCTAssertEqual(idea.domain, "career")
        XCTAssertEqual(idea.categoryLabel, "服务器运维")
        XCTAssertEqual(idea.kind, .routine)
    }

    func testIdeaKindFoldsUnknownAndMissingToChat() throws {
        let legacy = #"""
        {"id": "k2", "title": "t", "detail": "", "createdAt": 5}
        """#
        let old = try JSONDecoder().decode(
            BridgeIdea.self, from: Data(legacy.utf8)
        )
        XCTAssertEqual(old.kind, .chat)
        XCTAssertNil(old.domain)
        XCTAssertNil(old.categoryLabel)

        let weird = #"""
        {"id": "k3", "title": "t", "detail": "",
         "createdAt": 5, "kind": "teleport"}
        """#
        let folded = try JSONDecoder().decode(
            BridgeIdea.self, from: Data(weird.utf8)
        )
        XCTAssertEqual(folded.kind, .chat)
        XCTAssertEqual(IdeaKind.from("goal"), .goal)
        XCTAssertEqual(IdeaKind.from(nil), .chat)
    }
}
