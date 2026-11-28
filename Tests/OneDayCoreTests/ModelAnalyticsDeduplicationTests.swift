import XCTest
@testable import OneDayCore

final class ModelAnalyticsDeduplicationTests: XCTestCase {
    func testDeduplicatesSameModelName() {
        let usage1 = ModelAnalytics.ModelUsage(
            model: "gpt-4",
            provider: "openai",
            inputTokens: 100,
            outputTokens: 50,
            estimatedCost: 0.01,
            sessions: 2,
            apiCalls: 5
        )
        let usage2 = ModelAnalytics.ModelUsage(
            model: "gpt-4",
            provider: "openai",
            inputTokens: 200,
            outputTokens: 100,
            estimatedCost: 0.02,
            sessions: 3,
            apiCalls: 7
        )
        let analytics = ModelAnalytics(models: [usage1, usage2])
        let result = analytics.deduplicated

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].model, "gpt-4")
        XCTAssertEqual(result[0].inputTokens, 300)
        XCTAssertEqual(result[0].outputTokens, 150)
        XCTAssertEqual(result[0].tokens, 450)
        XCTAssertEqual(result[0].estimatedCost, 0.03)
        XCTAssertEqual(result[0].sessions, 5)
        XCTAssertEqual(result[0].apiCalls, 12)
    }

    func testDoesNotMergeDifferentModels() {
        let usage1 = ModelAnalytics.ModelUsage(
            model: "gpt-4",
            provider: "openai",
            inputTokens: 100,
            outputTokens: 50,
            estimatedCost: 0.01,
            sessions: 2,
            apiCalls: 5
        )
        let usage2 = ModelAnalytics.ModelUsage(
            model: "claude-3",
            provider: "anthropic",
            inputTokens: 200,
            outputTokens: 100,
            estimatedCost: 0.02,
            sessions: 3,
            apiCalls: 7
        )
        let analytics = ModelAnalytics(models: [usage1, usage2])
        let result = analytics.deduplicated

        XCTAssertEqual(result.count, 2)
    }

    func testPreservesFirstNonNullProvider() {
        let usage1 = ModelAnalytics.ModelUsage(
            model: "gpt-4",
            provider: nil,
            inputTokens: 100,
            outputTokens: 50,
            estimatedCost: 0.01,
            sessions: 2,
            apiCalls: 5
        )
        let usage2 = ModelAnalytics.ModelUsage(
            model: "gpt-4",
            provider: "openai",
            inputTokens: 200,
            outputTokens: 100,
            estimatedCost: 0.02,
            sessions: 3,
            apiCalls: 7
        )
        let analytics = ModelAnalytics(models: [usage1, usage2])
        let result = analytics.deduplicated

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].provider, "openai")
    }

    func testSortsByTokensDescending() {
        let usage1 = ModelAnalytics.ModelUsage(
            model: "gpt-3.5",
            provider: "openai",
            inputTokens: 100,
            outputTokens: 50,
            estimatedCost: 0.01,
            sessions: 2,
            apiCalls: 5
        )
        let usage2 = ModelAnalytics.ModelUsage(
            model: "gpt-4",
            provider: "openai",
            inputTokens: 500,
            outputTokens: 300,
            estimatedCost: 0.05,
            sessions: 10,
            apiCalls: 20
        )
        let usage3 = ModelAnalytics.ModelUsage(
            model: "claude-3",
            provider: "anthropic",
            inputTokens: 200,
            outputTokens: 100,
            estimatedCost: 0.02,
            sessions: 3,
            apiCalls: 7
        )
        let analytics = ModelAnalytics(models: [usage1, usage2, usage3])
        let result = analytics.deduplicated

        XCTAssertEqual(result.count, 3)
        XCTAssertEqual(result[0].model, "gpt-4")
        XCTAssertEqual(result[0].tokens, 800)
        XCTAssertEqual(result[1].model, "claude-3")
        XCTAssertEqual(result[1].tokens, 300)
        XCTAssertEqual(result[2].model, "gpt-3.5")
        XCTAssertEqual(result[2].tokens, 150)
    }
}
