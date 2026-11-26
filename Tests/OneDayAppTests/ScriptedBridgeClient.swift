import Foundation
import OneDayCore
@testable import OneDayApp

/// 桥脚本盒（§367）：引用型计数盒——脚本客户端是值
/// 型、跨拷贝存活靠它（ScriptedToolsetsClient 同式）。
/// 每端点一本计数账；写口按脚本把新建条目落进名单，
/// 供写后回读确认命中。出演范围只到三店计数所需：
/// 名单读口出演真值、写口 create 出演落名单，其余
/// 恒抛桩错（调用方多为 try? 降级口径）。
final class BridgeScript: @unchecked Sendable {
    var feedPostsCount = 0
    var feedGenerationCount = 0
    var feedBriefCount = 0
    var generateFeedCount = 0
    var markReadCount = 0
    var setLikedCount = 0

    var ideasCount = 0
    var createIdeaCount = 0
    var deleteIdeaCount = 0
    var patchIdeaCount = 0
    var generationInfoCount = 0

    var goalsCount = 0
    var createGoalCount = 0
    var ungroupedCount = 0
    var goalEntriesCount = 0

    var feedPostsResult: [BridgeFeedPost] = []
    /// 简报脚本值（§473 件一）：设了才出演 feedBrief，
    /// 未设维持旧桩（抛错、调用方 try? 降级）
    var feedBriefResult: BridgeBriefDoc?
    var ideasList: [BridgeIdea] = []
    var goalsList: [BridgeGoal] = []
    var entriesByGoal: [String: [BridgeGoalEntry]] = [:]
    private var createdIdeaSeq = 0
    private var createdGoalSeq = 0

    func nextCreatedIdea() -> BridgeIdea {
        createdIdeaSeq += 1
        let idea = BridgeIdea(
            id: "idea-created-\(createdIdeaSeq)",
            title: "脚本新建点子", detail: "", goalId: nil,
            createdAt: 1, status: .pending, category: "interest"
        )
        ideasList.append(idea)
        return idea
    }

    func nextCreatedGoal() -> BridgeGoal {
        createdGoalSeq += 1
        let goal = BridgeGoal(
            id: "goal-created-\(createdGoalSeq)",
            title: "脚本新建目标", note: "",
            createdAt: 1, updatedAt: 1
        )
        goalsList.append(goal)
        return goal
    }
}

/// 桥脚本客户端（§367）：供 CacheFreshnessGateC1Tests
/// 做请求计数——TTL 内二次读触发＝0 请求、过期＝1
/// 轮、写后回读不经门仍全量，全靠本盒计数断言
struct ScriptedBridgeClient: OneDayBridgeClientProtocol {
    let script: BridgeScript

    private var stub: OneDayBridgeError {
        .failed("脚本桩未出演此口")
    }

    // MARK: - 动态

    func feedPosts(config: ServerConfig) async throws -> [BridgeFeedPost] {
        script.feedPostsCount += 1
        return script.feedPostsResult
    }

    func feedGeneration(
        config: ServerConfig
    ) async throws -> BridgeFeedGeneration {
        script.feedGenerationCount += 1
        throw stub
    }

    func feedBrief(config: ServerConfig) async throws -> BridgeBriefDoc {
        script.feedBriefCount += 1
        if let doc = script.feedBriefResult { return doc }
        throw stub
    }

    func generateFeed(config: ServerConfig) async throws {
        script.generateFeedCount += 1
        throw stub
    }

    func saveFeedText(
        config: ServerConfig, text: String
    ) async throws -> BridgeBriefDoc {
        throw stub
    }

    func markFeedPostRead(
        config: ServerConfig, id: String
    ) async throws -> BridgeFeedPost {
        script.markReadCount += 1
        throw stub
    }

    func setFeedPostLiked(
        config: ServerConfig, id: String, liked: Bool
    ) async throws -> BridgeFeedPost {
        script.setLikedCount += 1
        throw stub
    }

    // MARK: - 点子

    func ideas(config: ServerConfig) async throws -> [BridgeIdea] {
        script.ideasCount += 1
        return script.ideasList
    }

    func createIdea(
        config: ServerConfig, request body: BridgeIdeaCreateRequest
    ) async throws -> BridgeIdea {
        script.createIdeaCount += 1
        return script.nextCreatedIdea()
    }

    func deleteIdea(config: ServerConfig, id: String) async throws {
        script.deleteIdeaCount += 1
        script.ideasList.removeAll { $0.id == id }
    }

    func patchIdea(
        config: ServerConfig, id: String,
        request body: BridgeIdeaPatchRequest
    ) async throws -> BridgeIdea {
        script.patchIdeaCount += 1
        throw stub
    }

    func generationInfo(
        config: ServerConfig
    ) async throws -> BridgeGenerationInfo {
        script.generationInfoCount += 1
        throw stub
    }

    // MARK: - 目标

    func goals(config: ServerConfig) async throws -> [BridgeGoal] {
        script.goalsCount += 1
        return script.goalsList
    }

    func createGoal(
        config: ServerConfig, request body: BridgeGoalCreateRequest
    ) async throws -> BridgeGoal {
        script.createGoalCount += 1
        return script.nextCreatedGoal()
    }

    func patchGoal(
        config: ServerConfig, id: String,
        request body: BridgeGoalPatchRequest
    ) async throws -> BridgeGoal {
        throw stub
    }

    func deleteGoal(config: ServerConfig, id: String) async throws {
        throw stub
    }

    func patchGoalStatus(
        config: ServerConfig, id: String, status: GoalStatus
    ) async throws -> BridgeGoal {
        throw stub
    }

    func goalEntries(
        config: ServerConfig, goalID: String
    ) async throws -> [BridgeGoalEntry] {
        script.goalEntriesCount += 1
        if let entries = script.entriesByGoal[goalID] {
            return entries
        }
        throw stub
    }

    func createGoalEntry(
        config: ServerConfig, goalID: String,
        request body: BridgeGoalEntryCreateRequest
    ) async throws -> BridgeGoalEntry {
        throw stub
    }

    func deleteGoalEntry(
        config: ServerConfig, goalID: String, entryID: String
    ) async throws {
        throw stub
    }

    func goalBriefings(
        config: ServerConfig, goalID: String
    ) async throws -> [BridgeBriefing] {
        throw stub
    }

    func markBriefingOpened(
        config: ServerConfig, goalID: String, briefingID: String
    ) async throws -> BridgeBriefing {
        throw stub
    }

    func goalTasks(
        config: ServerConfig, goalID: String
    ) async throws -> [BridgeGoalTask] {
        throw stub
    }

    func ungroupedTasks(
        config: ServerConfig
    ) async throws -> BridgeUngroupedTasksResponse {
        script.ungroupedCount += 1
        throw stub
    }

    func patchGoalCategory(
        config: ServerConfig, id: String, category: GoalCategory?
    ) async throws -> BridgeGoal {
        throw stub
    }

    func delegateGoalTask(
        config: ServerConfig, goalID: String,
        request body: BridgeGoalDelegateRequest
    ) async throws -> BridgeGoalDelegateResponse {
        throw stub
    }

    func setTaskGoal(
        config: ServerConfig, taskID: String,
        request body: BridgeTaskGoalWrite
    ) async throws -> BridgeTaskGoalAssignment {
        throw stub
    }

    // MARK: - 交付

    func delivery(
        config: ServerConfig, id: String
    ) async throws -> BridgeDelivery {
        throw stub
    }
}
