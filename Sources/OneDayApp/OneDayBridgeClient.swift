import Foundation
import OneDayCore

/// oneday-bridge 错误口径：与总览桥同分法——「没有钥匙」
/// 「钥匙被拒（401）」是桥未连接（钥匙问题），要在面
/// 上如实露；集合端点 404 是「桥未开通」；条目端点
/// 404 是记录已不在；其余失败给人话、不混报。
enum OneDayBridgeError: Error, Sendable, Equatable {
    case noKey
    case unauthorized
    case bridgeMissing
    case recordGone
    case failed(String)
}

/// oneday-bridge 客户端（0.11.0，冻结契约）：目标/点子
/// 仓（0.12.0 增监测面，契约 monitor-bridge-contract-
/// 20261109.md），路径挂在当前服务器根下（/api/oneday-bridge，
/// 与桥部署口径一致）。Bearer 只从 Keychain 的
/// BridgeCredential 统一读（0.33.1：聊天同一份
/// Hermes 登录密钥，入口在服务器内部换桥钥）；
/// 读不到钥匙一律 noKey、
/// 不发请求、不冒充已接通。
final class OneDayBridgeClient: @unchecked Sendable {
    private let session: URLSession
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    init() {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 15
        session = URLSession(configuration: configuration)
    }

    private var bridgeKey: String? {
        BridgeCredential.read()
    }

    // MARK: - 目标

    func goals(config: ServerConfig) async throws -> [BridgeGoal] {
        let response: BridgeGoalsResponse = try await get(
            config: config, path: "/goals", endpoint: L10n.string("目标列表"),
            collection: true
        )
        return response.items
    }

    func createGoal(
        config: ServerConfig, request body: BridgeGoalCreateRequest
    ) async throws -> BridgeGoal {
        try await send(
            config: config, path: "/goals", method: "POST",
            body: body, endpoint: L10n.string("新建目标"), collection: true
        )
    }

    func patchGoal(
        config: ServerConfig, id: String,
        request body: BridgeGoalPatchRequest
    ) async throws -> BridgeGoal {
        try await send(
            config: config, path: "/goals/\(id)", method: "PATCH",
            body: body, endpoint: L10n.string("保存目标"), collection: false
        )
    }

    func deleteGoal(config: ServerConfig, id: String) async throws {
        let _: BridgeOKResponse = try await sendEmpty(
            config: config, path: "/goals/\(id)", method: "DELETE",
            endpoint: L10n.string("删除目标")
        )
    }

    /// PATCH /goals/{id} 状态流转（P2）：只送 {status}；
    /// completedAt 由桥落字，回执全形供调用方对账
    func patchGoalStatus(
        config: ServerConfig, id: String, status: GoalStatus
    ) async throws -> BridgeGoal {
        try await send(
            config: config, path: "/goals/\(id)", method: "PATCH",
            body: BridgeGoalStatusPatchRequest(status: status),
            endpoint: L10n.string("目标状态"), collection: false
        )
    }

    /// GET /goals/{id}/entries（P2）：进展条目流
    /// （createdAt 升序）；目标不在 → recordGone
    func goalEntries(
        config: ServerConfig, goalID: String
    ) async throws -> [BridgeGoalEntry] {
        let response: BridgeGoalEntriesResponse = try await get(
            config: config, path: "/goals/\(goalID)/entries",
            endpoint: L10n.string("进展记录"), collection: false
        )
        return response.items
    }

    /// POST /goals/{id}/entries（P2）：追加一条进展；
    /// 成功与否以调用方回读条目流确认出现为准
    func createGoalEntry(
        config: ServerConfig, goalID: String,
        request body: BridgeGoalEntryCreateRequest
    ) async throws -> BridgeGoalEntry {
        try await send(
            config: config, path: "/goals/\(goalID)/entries",
            method: "POST", body: body, endpoint: L10n.string("记录进展"),
            collection: false
        )
    }

    /// DELETE /goals/{id}/entries/{eid}（P2）：删单条纠错
    func deleteGoalEntry(
        config: ServerConfig, goalID: String, entryID: String
    ) async throws {
        let _: BridgeOKResponse = try await sendEmpty(
            config: config,
            path: "/goals/\(goalID)/entries/\(entryID)",
            method: "DELETE", endpoint: L10n.string("删除进展")
        )
    }

    /// GET /goals/{id}/briefings（P2）：周简报信件
    /// （createdAt 降序，最新在前）
    func goalBriefings(
        config: ServerConfig, goalID: String
    ) async throws -> [BridgeBriefing] {
        let response: BridgeBriefingsResponse = try await get(
            config: config, path: "/goals/\(goalID)/briefings",
            endpoint: L10n.string("目标简报"), collection: false
        )
        return response.items
    }

    /// PATCH /goals/{id} 分类变更（0.40.0）：只送
    /// {category}（nil 显式送 null＝清除分类）；回执全形
    /// 供调用方对账
    func patchGoalCategory(
        config: ServerConfig, id: String, category: GoalCategory?
    ) async throws -> BridgeGoal {
        try await send(
            config: config, path: "/goals/\(id)", method: "PATCH",
            body: BridgeGoalCategoryPatchRequest(category: category),
            endpoint: L10n.string("目标分类"), collection: false
        )
    }

    /// GET /goals/{id}/task-links（0.40.0）：目标↔任务
    /// 关联记录（createdAt 升序）；目标不在 → recordGone
    func goalTaskLinks(
        config: ServerConfig, goalID: String
    ) async throws -> [BridgeGoalTaskLink] {
        let response: BridgeGoalTaskLinksResponse = try await get(
            config: config, path: "/goals/\(goalID)/task-links",
            endpoint: L10n.string("目标关联任务"), collection: false
        )
        return response.items
    }

    /// POST /goals/{id}/task-links（0.40.0）：委派建卡后
    /// 回写关联（与点子采纳回写 taskId 同形）；桥侧对
    /// (goalId, taskId) 重复回写幂等
    func createGoalTaskLink(
        config: ServerConfig, goalID: String,
        request body: BridgeGoalTaskLinkCreateRequest
    ) async throws -> BridgeGoalTaskLink {
        try await send(
            config: config, path: "/goals/\(goalID)/task-links",
            method: "POST", body: body, endpoint: L10n.string("关联任务"),
            collection: false
        )
    }

    // MARK: - 点子

    func ideas(config: ServerConfig) async throws -> [BridgeIdea] {
        let response: BridgeIdeasResponse = try await get(
            config: config, path: "/ideas", endpoint: L10n.string("点子列表"),
            collection: true
        )
        return response.items
    }

    func createIdea(
        config: ServerConfig, request body: BridgeIdeaCreateRequest
    ) async throws -> BridgeIdea {
        try await send(
            config: config, path: "/ideas", method: "POST",
            body: body, endpoint: L10n.string("新建点子"), collection: true
        )
    }

    func deleteIdea(config: ServerConfig, id: String) async throws {
        let _: BridgeOKResponse = try await sendEmpty(
            config: config, path: "/ideas/\(id)", method: "DELETE",
            endpoint: L10n.string("删除点子")
        )
    }

    /// PATCH /ideas/{id}（P1）：只许改 status/taskId——
    /// 忽略（dismissed）与采纳回写（taskId）共用此口；
    /// 桥侧状态机把关，非法流转回 400 人话、透传不猜
    func patchIdea(
        config: ServerConfig, id: String,
        request body: BridgeIdeaPatchRequest
    ) async throws -> BridgeIdea {
        try await send(
            config: config, path: "/ideas/\(id)", method: "PATCH",
            body: body, endpoint: L10n.string("更新点子"), collection: false
        )
    }

    /// GET /ideas/generation（P1）：生成管道账面——上次/
    /// 下次运行时刻与近轮记录；点子页空态与页脚节奏文
    /// 案的数据源。端点不存在（旧桥）走 collection 404
    /// ＝未开通口径，调用方降级为「无生成信息」
    func generationInfo(
        config: ServerConfig
    ) async throws -> BridgeGenerationInfo {
        try await get(
            config: config, path: "/ideas/generation",
            endpoint: L10n.string("生成记录"), collection: true
        )
    }

    // MARK: - 监测（P6，契约 monitor-bridge-contract-20261109.md）

    /// 监测列表：集合端点 404＝监测数据源未开通
    /// （bridgeMissing），与 goals/ideas 同口径分流
    func monitors(config: ServerConfig) async throws -> [BridgeMonitor] {
        let response: BridgeMonitorsResponse = try await get(
            config: config, path: "/monitors", endpoint: L10n.string("监测列表"),
            collection: true
        )
        return response.items
    }

    func monitorChanges(
        config: ServerConfig, monitorID: String
    ) async throws -> [BridgeMonitorChange] {
        let response: BridgeMonitorChangesResponse = try await get(
            config: config, path: "/monitors/\(monitorID)/changes",
            endpoint: L10n.string("变化记录"), collection: true
        )
        return response.items
    }

    /// 标记单条变化已读：服务端同步扣减该监测的
    /// unreadChanges，客户端随后回读列表对账
    func markMonitorChangeRead(
        config: ServerConfig, monitorID: String, changeID: String
    ) async throws {
        let _: BridgeOKResponse = try await sendEmpty(
            config: config,
            path: "/monitors/\(monitorID)/changes/\(changeID)/read",
            method: "POST",
            endpoint: L10n.string("标记已读")
        )
    }

    // MARK: - 监测控制（0.12.1：桥上线实形）

    /// 建监测：201 返回监测全形（桥建时已抓基线）；
    /// 成功与否以调用方回读列表确认为准，回执本体
    /// 只用来拿新 id。集合路径 404＝监测面未开通
    func createMonitor(
        config: ServerConfig, request body: BridgeMonitorCreateRequest
    ) async throws -> BridgeMonitor {
        try await send(
            config: config, path: "/monitors", method: "POST",
            body: body, endpoint: L10n.string("新建监测"), collection: true
        )
    }

    /// 立即检查：200 返回检查后的监测全形；已暂停
    /// 桥回 409＋人话（checkStatus 透传到 .failed）
    func checkMonitor(
        config: ServerConfig, monitorID: String
    ) async throws -> BridgeMonitor {
        try await sendEmpty(
            config: config, path: "/monitors/\(monitorID)/check",
            method: "POST", endpoint: L10n.string("立即检查")
        )
    }

    /// 暂停：200 返回监测全形（enabled 已翻转）
    func pauseMonitor(
        config: ServerConfig, monitorID: String
    ) async throws -> BridgeMonitor {
        try await sendEmpty(
            config: config, path: "/monitors/\(monitorID)/pause",
            method: "POST", endpoint: L10n.string("暂停监测")
        )
    }

    /// 恢复：200 返回监测全形（enabled 已翻转）
    func resumeMonitor(
        config: ServerConfig, monitorID: String
    ) async throws -> BridgeMonitor {
        try await sendEmpty(
            config: config, path: "/monitors/\(monitorID)/resume",
            method: "POST", endpoint: L10n.string("恢复监测")
        )
    }

    /// 删监测：桥连其全部变化记录一并删，{"ok":true}
    func deleteMonitor(
        config: ServerConfig, monitorID: String
    ) async throws {
        let _: BridgeOKResponse = try await sendEmpty(
            config: config, path: "/monitors/\(monitorID)",
            method: "DELETE", endpoint: L10n.string("删除监测")
        )
    }

    // MARK: - 动态（P3，桥 /feed 契约）

    /// GET /feed?days=30：近 30 天帖子（桥侧 createdAt
    /// 倒序、过期不回）；集合端点 404＝动态面未开通
    func feedPosts(config: ServerConfig) async throws -> [BridgeFeedPost] {
        let response: BridgeFeedPostsResponse = try await get(
            config: config, path: "/feed?days=30", endpoint: L10n.string("动态列表"),
            collection: true
        )
        return response.items
    }

    /// GET /feed/generation（P3）：双生产者账面——段
    /// 一汇编状态＋段二晨报节奏＋未读数；旧桥无此端
    /// 点走 collection 404＝未开通，调用方降级处理
    func feedGeneration(
        config: ServerConfig
    ) async throws -> BridgeFeedGeneration {
        try await get(
            config: config, path: "/feed/generation",
            endpoint: L10n.string("动态账面"), collection: true
        )
    }

    /// POST /feed/{id}/read：已读落服务端真源；回执
    /// 全形供调用方对账（readAt 以桥落字为准）
    func markFeedPostRead(
        config: ServerConfig, id: String
    ) async throws -> BridgeFeedPost {
        try await sendEmpty(
            config: config, path: "/feed/\(id)/read", method: "POST",
            endpoint: L10n.string("标记已读")
        )
    }

    /// GET /meta/brief（0.38.0）：简报两层全文——兴趣
    /// 层（用户原话）＋执行层（AI 扩写维护的正式简报）
    /// ＋扩写状态；旧桥无两层字段时按宽容解码收
    func feedBrief(config: ServerConfig) async throws -> BridgeBriefDoc {
        try await get(
            config: config, path: "/meta/brief",
            endpoint: L10n.string("动态简报"), collection: true
        )
    }

    /// PUT /meta/brief {interest}：存兴趣层；真变更时
    /// 桥侧起扩写，扩写落盘且执行层变了再触发一轮
    /// 调研；回执为保存后的全文（含 expandStarted）
    func saveFeedInterest(
        config: ServerConfig, interest: String
    ) async throws -> BridgeBriefDoc {
        try await send(
            config: config, path: "/meta/brief", method: "PUT",
            body: BridgeBriefSaveRequest(interest: interest),
            endpoint: L10n.string("保存简报兴趣"), collection: false
        )
    }

    /// PUT /meta/brief {brief}：直改执行层；真变更时
    /// 桥侧直接触发一轮调研；回执同上
    func saveFeedPrompt(
        config: ServerConfig, brief: String
    ) async throws -> BridgeBriefDoc {
        try await send(
            config: config, path: "/meta/brief", method: "PUT",
            body: BridgeBriefSaveRequest(brief: brief),
            endpoint: L10n.string("保存执行简报"), collection: false
        )
    }

    /// POST /feed/generate：手动起一轮调研（已有轮次
    /// 在跑时桥回 409，错误文案原样呈现）
    func generateFeed(config: ServerConfig) async throws {
        let _: BridgeOKResponse = try await sendEmpty(
            config: config, path: "/feed/generate", method: "POST",
            endpoint: L10n.string("生成动态")
        )
    }

    // MARK: - 表格转码（§125，桥 /files/spreadsheet）

    /// GET /files/spreadsheet?path=：xlsx 按 sheet 转
    /// CSV（值口径）。本端点不走 checkStatus 的人话
    /// 收敛——状态码原样包成 HermesError.unexpected-
    /// Status 交调用方走 FileOpenFailure.classify-
    /// Spreadsheet 分型（422 转码专档/413 过大/404
    /// 不存在各有出路，收敛成一句会丢分型）；无钥匙
    /// 仍走 OneDayBridgeError.noKey 口径
    func spreadsheet(
        config: ServerConfig, path: String
    ) async throws -> BridgeSpreadsheet {
        let allowed = CharacterSet.alphanumerics.union(
            CharacterSet(charactersIn: "-._~/")
        )
        let encoded = path.addingPercentEncoding(
            withAllowedCharacters: allowed
        ) ?? path
        let request = try makeRequest(
            config: config,
            path: "/files/spreadsheet?path=\(encoded)",
            method: "GET"
        )
        let (data, http) = try await send(
            request, endpoint: L10n.string("表格转换")
        )
        guard (200...299).contains(http.statusCode) else {
            throw HermesError.unexpectedStatus(
                endpoint: L10n.string("表格转换"),
                status: http.statusCode
            )
        }
        do {
            return try decoder.decode(
                BridgeSpreadsheet.self, from: data
            )
        } catch {
            throw OneDayBridgeError.failed(
                L10n.string("表格转换返回格式无法识别")
            )
        }
    }

    // MARK: - 图片变体（§138，桥 /media/rendition）

    /// GET /media/rendition?path=&w=&kind=：回变体 JPEG
    /// 字节（kind=image 取图变体、kind=poster 取视频首
    /// 帧海报）。与 spreadsheet 同口径：状态码原样包成
    /// HermesError.unexpectedStatus 交调用方分型（415
    /// 格式不支持/404 不存在时回落原图通道），不收敛
    /// 成一句人话丢分型；无钥匙仍走 noKey 口径
    func rendition(
        config: ServerConfig, path: String,
        width: Int, kind: String = "image"
    ) async throws -> Data {
        let allowed = CharacterSet.alphanumerics.union(
            CharacterSet(charactersIn: "-._~/")
        )
        let encoded = path.addingPercentEncoding(
            withAllowedCharacters: allowed
        ) ?? path
        let request = try makeRequest(
            config: config,
            path: "/media/rendition?path=\(encoded)"
                + "&w=\(width)&kind=\(kind)",
            method: "GET"
        )
        let (data, http) = try await send(
            request, endpoint: L10n.string("图片预览")
        )
        guard (200...299).contains(http.statusCode) else {
            throw HermesError.unexpectedStatus(
                endpoint: L10n.string("图片预览"),
                status: http.statusCode
            )
        }
        return data
    }

    // MARK: - 请求底座

    private func makeRequest(
        config: ServerConfig, path: String, method: String
    ) throws -> URLRequest {
        guard let key = bridgeKey, !key.isEmpty else {
            throw OneDayBridgeError.noKey
        }
        var request = URLRequest(
            url: config.endpoint("/api/oneday-bridge" + path)
        )
        request.httpMethod = method
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        return request
    }

    private func get<T: Decodable>(
        config: ServerConfig, path: String, endpoint: String,
        collection: Bool
    ) async throws -> T {
        let request = try makeRequest(config: config, path: path, method: "GET")
        let (data, http) = try await send(request, endpoint: endpoint)
        try checkStatus(http, data: data, endpoint: endpoint, collection: collection)
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw OneDayBridgeError.failed(L10n.format("%@返回格式无法识别", endpoint))
        }
    }

    private func send<Body: Encodable, T: Decodable>(
        config: ServerConfig, path: String, method: String,
        body: Body, endpoint: String, collection: Bool
    ) async throws -> T {
        var request = try makeRequest(config: config, path: path, method: method)
        do {
            request.httpBody = try encoder.encode(body)
        } catch {
            throw OneDayBridgeError.failed(L10n.format("%@请求组装失败", endpoint))
        }
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let (data, http) = try await send(request, endpoint: endpoint)
        try checkStatus(http, data: data, endpoint: endpoint, collection: collection)
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw OneDayBridgeError.failed(L10n.format("%@回执格式无法识别", endpoint))
        }
    }

    private func sendEmpty<T: Decodable>(
        config: ServerConfig, path: String, method: String,
        endpoint: String
    ) async throws -> T {
        let request = try makeRequest(config: config, path: path, method: method)
        let (data, http) = try await send(request, endpoint: endpoint)
        try checkStatus(http, data: data, endpoint: endpoint, collection: false)
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw OneDayBridgeError.failed(L10n.format("%@回执格式无法识别", endpoint))
        }
    }

    /// 桥错误体（冻结口径）：失败响应统一 {"error": 人话}
    private struct BridgeErrorBody: Decodable {
        let error: String
    }

    /// 状态口径：2xx 通过；401 钥匙被拒；404 按端点分流
    /// （集合＝桥未开通、条目＝记录已不在）；400 等内容
    /// 问题优先透服务端人话（标题为空/关联目标不存在
    /// 等，客户端不许猜成固定一条）
    private func checkStatus(
        _ http: HTTPURLResponse, data: Data,
        endpoint: String, collection: Bool
    ) throws {
        switch http.statusCode {
        case 200...299:
            return
        case 401:
            throw OneDayBridgeError.unauthorized
        case 404:
            throw collection
                ? OneDayBridgeError.bridgeMissing
                : OneDayBridgeError.recordGone
        default:
            if let body = try? decoder.decode(
                BridgeErrorBody.self, from: data
            ), !body.error.isEmpty {
                throw OneDayBridgeError.failed(body.error)
            }
            throw OneDayBridgeError.failed(
                L10n.format("%@返回 %@", endpoint, String(http.statusCode))
            )
        }
    }

    private func send(
        _ request: URLRequest, endpoint: String
    ) async throws -> (Data, HTTPURLResponse) {
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw OneDayBridgeError.failed(L10n.format("%@无响应", endpoint))
            }
            return (data, http)
        } catch let error as OneDayBridgeError {
            throw error
        } catch {
            throw OneDayBridgeError.failed(L10n.format("%@网络不可达", endpoint))
        }
    }
}
