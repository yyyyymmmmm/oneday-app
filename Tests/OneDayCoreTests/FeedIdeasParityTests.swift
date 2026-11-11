import OneDayCore
import XCTest

/// §177 动态/点子对标包钉测：点子分类解析与分类小
/// 节分组（硬验收：列表全程分类小节、无分类卡不进
/// 列表、无无分类区）、分类字段解码与新建请求携带。
/// 动态两项（去日期分组/帖面同色）是纯视图结构，无
/// Core 口径可钉，验收走真机与 DESIGN §177 记账。
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
}
