import Foundation
import OneDayCore

/// oneday-bridge 客户端的协议面（§367 接缝）：本面
/// 只收动态/点子/目标三店所用的 28 口，与 Hermes-
/// ClientProtocol 同式——实客户端 OneDayBridgeClient
/// 本体零改、经 extension  conform；三店改持本协议
/// 注入（默认实客户端），测试得以用假客户端做请求
/// 计数（CacheFreshnessGateC1Tests）。其余桥面
/// （看板/监测/记忆等）不在本包范围，后续包按需扩入。
protocol OneDayBridgeClientProtocol: Sendable {
    // MARK: - 动态

    func feedPosts(config: ServerConfig) async throws -> [BridgeFeedPost]
    func feedGeneration(
        config: ServerConfig
    ) async throws -> BridgeFeedGeneration
    func feedBrief(config: ServerConfig) async throws -> BridgeBriefDoc
    func generateFeed(config: ServerConfig) async throws
    func saveFeedText(
        config: ServerConfig, text: String
    ) async throws -> BridgeBriefDoc
    func markFeedPostRead(
        config: ServerConfig, id: String
    ) async throws -> BridgeFeedPost
    func setFeedPostLiked(
        config: ServerConfig, id: String, liked: Bool
    ) async throws -> BridgeFeedPost

    // MARK: - 点子

    func ideas(config: ServerConfig) async throws -> [BridgeIdea]
    func generateIdeas(config: ServerConfig) async throws
    func createIdea(
        config: ServerConfig, request body: BridgeIdeaCreateRequest
    ) async throws -> BridgeIdea
    func deleteIdea(config: ServerConfig, id: String) async throws
    func patchIdea(
        config: ServerConfig, id: String,
        request body: BridgeIdeaPatchRequest
    ) async throws -> BridgeIdea
    func generationInfo(
        config: ServerConfig
    ) async throws -> BridgeGenerationInfo

    // MARK: - 目标

    func goals(config: ServerConfig) async throws -> [BridgeGoal]
    func createGoal(
        config: ServerConfig, request body: BridgeGoalCreateRequest
    ) async throws -> BridgeGoal
    func patchGoal(
        config: ServerConfig, id: String,
        request body: BridgeGoalPatchRequest
    ) async throws -> BridgeGoal
    func deleteGoal(config: ServerConfig, id: String) async throws
    func patchGoalStatus(
        config: ServerConfig, id: String, status: GoalStatus
    ) async throws -> BridgeGoal
    func goalEntries(
        config: ServerConfig, goalID: String
    ) async throws -> [BridgeGoalEntry]
    func createGoalEntry(
        config: ServerConfig, goalID: String,
        request body: BridgeGoalEntryCreateRequest
    ) async throws -> BridgeGoalEntry
    func deleteGoalEntry(
        config: ServerConfig, goalID: String, entryID: String
    ) async throws
    func goalBriefings(
        config: ServerConfig, goalID: String
    ) async throws -> [BridgeBriefing]
    func markBriefingOpened(
        config: ServerConfig, goalID: String, briefingID: String
    ) async throws -> BridgeBriefing
    func goalTasks(
        config: ServerConfig, goalID: String
    ) async throws -> [BridgeGoalTask]
    func ungroupedTasks(
        config: ServerConfig
    ) async throws -> BridgeUngroupedTasksResponse
    func patchGoalCategory(
        config: ServerConfig, id: String, category: GoalCategory?
    ) async throws -> BridgeGoal
    func delegateGoalTask(
        config: ServerConfig, goalID: String,
        request body: BridgeGoalDelegateRequest
    ) async throws -> BridgeGoalDelegateResponse
    func setTaskGoal(
        config: ServerConfig, taskID: String,
        request body: BridgeTaskGoalWrite
    ) async throws -> BridgeTaskGoalAssignment

    // MARK: - 交付

    func delivery(
        config: ServerConfig, id: String
    ) async throws -> BridgeDelivery
}

extension OneDayBridgeClient: OneDayBridgeClientProtocol {}
