import Foundation
import OneDayCore

/// oneday-bridge 客户端（0.11.0，冻结契约）：目标/点子
/// 仓（0.12.0 增监测面，契约 monitor-bridge-contract-
/// 20261109.md），路径挂在当前服务器根下（/api/oneday-bridge，
/// 与桥部署口径一致）。Bearer 只从 Keychain 的
/// BridgeCredential 统一读（0.33.1：聊天同一份
/// Hermes 登录密钥，入口在服务器内部换桥钥）；
/// 读不到钥匙一律 noKey、
/// 不发请求、不冒充已接通。
final class OneDayBridgeClient: @unchecked Sendable {
    /// C-10 收敛：连接/单钥/管线/文案全走统一基座，
    /// 本类只留路径、DTO 与 oneday 系状态口径
    private let base = BridgeClientBase<OneDayBridgeError>(
        pathPrefix: "/api/oneday-bridge", timeout: 15,
        noKey: .noKey, failed: OneDayBridgeError.failed
    )

    private var decoder: JSONDecoder { base.decoder }

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

    /// POST /goals/{id}/briefings/{bid}/opened（GD-3）：
    /// 打开信件时记下打开时刻，回执为盖过记录的简报
    /// 全形。只供台账看「写了没看」，调用方失败静默
    func markBriefingOpened(
        config: ServerConfig, goalID: String, briefingID: String
    ) async throws -> BridgeBriefing {
        try await sendEmpty(
            config: config,
            path: "/goals/\(goalID)/briefings/\(briefingID)/opened",
            method: "POST", endpoint: L10n.string("简报打开记录")
        )
    }

    /// GET /goals/{id}/tasks（GD-2 读面一）：关联任务
    /// 实时行（关联记录×任务板现况，桥侧拼好下发）
    func goalTasks(
        config: ServerConfig, goalID: String
    ) async throws -> [BridgeGoalTask] {
        let response: BridgeGoalTasksResponse = try await get(
            config: config, path: "/goals/\(goalID)/tasks",
            endpoint: L10n.string("目标任务"), collection: false
        )
        return response.items
    }

    /// GET /goals/ungrouped-tasks（GD-2 读面二）：用户
    /// 发起类（点子采纳/对话派发）且未归任何目标的
    /// 任务；系统/定时/探针任务不在此面
    func ungroupedTasks(
        config: ServerConfig
    ) async throws -> BridgeUngroupedTasksResponse {
        try await get(
            config: config, path: "/goals/ungrouped-tasks",
            endpoint: L10n.string("未归类任务"), collection: false
        )
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

    /// POST /goals/{id}/delegate（§308 单轨）：一次调用
    /// 里桥建卡＋写任务的 goalId 字段，取代旧「App 直连
    /// 看板建卡 → 再回桥补关联」的两步两账；
    /// idempotencyKey 同键重试回原归属、不重复建卡
    func delegateGoalTask(
        config: ServerConfig, goalID: String,
        request body: BridgeGoalDelegateRequest
    ) async throws -> BridgeGoalDelegateResponse {
        try await send(
            config: config, path: "/goals/\(goalID)/delegate",
            method: "POST", body: body,
            endpoint: L10n.string("委派任务"),
            collection: false
        )
    }

    /// PUT /tasks/{taskId}/goal（§308）：任务 goalId
    /// 字段的独立写面——归入/移交/清除（goalId 传 nil
    /// ＝清除归属，编码显式送 null）
    func setTaskGoal(
        config: ServerConfig, taskID: String,
        request body: BridgeTaskGoalWrite
    ) async throws -> BridgeTaskGoalAssignment {
        try await send(
            config: config, path: "/tasks/\(taskID)/goal",
            method: "PUT", body: body,
            endpoint: L10n.string("任务归属"),
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

    /// POST /feed/{id}/like {liked}（FA-1，契约 rev2
    /// §1.9 冻结）：幂等，回执为帖视图全形——点赞态
    /// 以桥 likedAt 为唯一真源，调用方以回执整帖替换
    func setFeedPostLiked(
        config: ServerConfig, id: String, liked: Bool
    ) async throws -> BridgeFeedPost {
        try await send(
            config: config, path: "/feed/\(id)/like", method: "POST",
            body: BridgeFeedLikeRequest(liked: liked),
            endpoint: L10n.string("点赞"), collection: false
        )
    }

    /// POST /feed/{id}/signal {type:"discuss", note?}
    /// （FA-1，契约 rev2 §1.9 冻结）：讨论建聊后发一
    /// 记；note 只取用户在旁聊首句的自述偏好句（Core
    /// FeedDiscussSignal 提取），无则不带、桥记弱信号
    func sendFeedDiscussSignal(
        config: ServerConfig, id: String, note: String?
    ) async throws {
        let _: BridgeOKResponse = try await send(
            config: config, path: "/feed/\(id)/signal", method: "POST",
            body: BridgeFeedSignalRequest(type: "discuss", note: note),
            endpoint: L10n.string("讨论信号"), collection: false
        )
    }

    /// GET /meta/brief：简报全文——§459 起含 text（当
    /// 前生效全文）＋polished＋polishState，旧两层字段
    /// 照旧出；旧桥无新字段时按宽容解码收
    func feedBrief(config: ServerConfig) async throws -> BridgeBriefDoc {
        try await get(
            config: config, path: "/meta/brief",
            endpoint: L10n.string("动态简报"), collection: true
        )
    }

    /// PUT /meta/brief {text}（§459 单层）：服务端折
    /// 为 interest 保存（interest 显式给出才优先，本
    /// 口不发）；真变更时桥侧起润色/调研；回执为保
    /// 存后的全文（含 expandStarted）
    func saveFeedText(
        config: ServerConfig, text: String
    ) async throws -> BridgeBriefDoc {
        try await send(
            config: config, path: "/meta/brief", method: "PUT",
            body: BridgeBriefSaveRequest(text: text),
            endpoint: L10n.string("保存简报"), collection: false
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

    // MARK: - 图片变体（§138）

    /// 端点已迁伴生独立 fileproc 模块（API 直连 B
    /// 包，2026-11-14）：本类只留委托，签名与状态码
    /// 口径（unexpectedStatus 原样上抛分型、noKey 走
    /// OneDayBridgeError）逐字不变，实现见
    /// FilesProcClient。表格转码委托已随 §259 退役
    private let fileproc = FilesProcClient()

    func rendition(
        config: ServerConfig, path: String,
        width: Int, kind: String = "image"
    ) async throws -> Data {
        try await fileproc.rendition(
            config: config, path: path, width: width, kind: kind
        )
    }

    // MARK: - 文件交付登记（§146，规格 delivery-registry-spec-20261111 §5/§7）

    /// GET /deliveries/{id}：登记元数据＋读时状态
    /// （ok/stale/gone 由桥按指纹实时复核）；未知
    /// id 走条目 404＝recordGone，调用方按规格
    /// §7.3 降级为纯文本（查无此号不成卡）。
    /// 先走 /api/oneday-bridge，若网关反代未配置该前缀，
    /// 自动回落到同网关的 /v1/oneday/deliveries/{id}。
    func delivery(
        config: ServerConfig, id: String
    ) async throws -> BridgeDelivery {
        let primaryPath = "/deliveries/\(id)"
        do {
            return try await get(
                config: config, path: primaryPath,
                endpoint: L10n.string("交付内容"), collection: false
            )
        } catch let error as OneDayBridgeError
            where error == .noKey || error == .unauthorized {
            throw error
        } catch {
            return try await getFullPath(
                config: config,
                fullPath: "/v1/oneday/deliveries/\(id)",
                endpoint: L10n.string("交付内容"),
                collection: false
            )
        }
    }

    /// GET /deliveries/{id}/thumb|cover：登记时快照
    /// JPEG 字节。本口不走 checkStatus 的人话收敛
    /// ——404（无此档快照）/410（文件已删）对调用
    /// 方是分型信号（走回落链的判据），收敛成一句
    /// 会丢分型，状态码原样包成
    /// HermesError.unexpectedStatus；无钥
    /// 匙仍走 OneDayBridgeError.noKey 口径
    func deliveryImage(
        config: ServerConfig, id: String,
        variant: DeliveryImageVariant
    ) async throws -> Data {
        do {
            return try await fetchDeliveryBinary(
                config: config,
                fullPath: "\(base.pathPrefix)/deliveries/\(id)/\(variant.rawValue)"
            )
        } catch let error as OneDayBridgeError
            where error == .noKey || error == .unauthorized {
            throw error
        } catch let error as HermesError {
            if case .unexpectedStatus(_, let status) = error, status == 401 {
                throw error
            }
            return try await fetchDeliveryBinary(
                config: config,
                fullPath: "/v1/oneday/deliveries/\(id)/\(variant.rawValue)"
            )
        } catch {
            return try await fetchDeliveryBinary(
                config: config,
                fullPath: "/v1/oneday/deliveries/\(id)/\(variant.rawValue)"
            )
        }
    }

    /// GET /deliveries/{id}/content：原文件/原图字节（走桥鉴权，
    /// 不依赖 Admin 会话登录态）
    func deliveryContent(
        config: ServerConfig, id: String
    ) async throws -> Data {
        do {
            return try await fetchDeliveryBinary(
                config: config,
                fullPath: "\(base.pathPrefix)/deliveries/\(id)/content"
            )
        } catch let error as OneDayBridgeError
            where error == .noKey || error == .unauthorized {
            throw error
        } catch let error as HermesError {
            if case .unexpectedStatus(_, let status) = error, status == 401 {
                throw error
            }
            return try await fetchDeliveryBinary(
                config: config,
                fullPath: "/v1/oneday/deliveries/\(id)/content"
            )
        } catch {
            return try await fetchDeliveryBinary(
                config: config,
                fullPath: "/v1/oneday/deliveries/\(id)/content"
            )
        }
    }

    private func fetchDeliveryBinary(
        config: ServerConfig, fullPath: String
    ) async throws -> Data {
        let request = try base.makeRequest(
            config: config, fullPath: fullPath, method: "GET"
        )
        let (data, http) = try await send(
            request, endpoint: L10n.string("交付内容")
        )
        guard (200...299).contains(http.statusCode) else {
            throw HermesError.unexpectedStatus(
                endpoint: L10n.string("交付内容"),
                status: http.statusCode
            )
        }
        return data
    }

    private func getFullPath<T: Decodable>(
        config: ServerConfig, fullPath: String,
        endpoint: String, collection: Bool
    ) async throws -> T {
        let request = try base.makeRequest(
            config: config, fullPath: fullPath, method: "GET"
        )
        let (data, http) = try await base.data(
            for: request, endpoint: endpoint
        )
        try base.checkStatus(
            http, data: data, endpoint: endpoint,
            collection: collection
        )
        return try base.decode(
            data,
            orThrow: OneDayBridgeError.failed(
                L10n.format("%@返回格式无法识别", endpoint)
            )
        )
    }

    // MARK: - 文件库聚合（A-06，伴生 1.0.66）

    /// GET /file-library：文件页聚合读面——产出根走查、
    /// 准入、去重、排序全在服务端，客户端只消费单流
    /// （取代 0.50.60 前客户端 BFS 爬 /api/files 目录树
    /// 的聚合形态）。默认整集下发；total 为准入全量、
    /// truncated 恒 false（无静默截断）
    func fileLibrary(
        config: ServerConfig
    ) async throws -> FileLibraryPage {
        try await get(
            config: config, path: "/file-library",
            endpoint: L10n.string("文件库"), collection: false
        )
    }

    // MARK: - 留痕回响（P0/P2，2026-11-13）

    /// GET /traces：AI 内部动作留痕（最新在前）。主线
    /// 拉全量近百条作总账面；旁聊传 targetId 只拉指向
    /// 本会话的（桥侧过滤，省流量）。失败照桥错误口径
    /// 抛（调用方决定呈现策略，回响拉取本身失败不许
    /// 冒充「没有动作发生」——ChatView 拉取失败时保留
    /// 已有卡、不清空）
    func traces(
        config: ServerConfig, limit: Int = 100, targetId: String? = nil
    ) async throws -> [BridgeTrace] {
        var path = "/traces?limit=\(limit)"
        if let targetId, !targetId.isEmpty {
            let encoded = targetId.addingPercentEncoding(
                withAllowedCharacters: .urlQueryAllowed) ?? targetId
            path += "&targetId=\(encoded)"
        }
        let response: BridgeTracesResponse = try await get(
            config: config, path: path,
            endpoint: L10n.string("留痕回响"), collection: true
        )
        return response.items
    }

    // MARK: - 留痕自报（§383 包一：直连写口的留痕落点）

    /// POST /traces：五要素留痕自报——已迁直连
    /// 的写口（如改名 soul 直写）把动作补报进同
    /// 一本留痕账，与桥内各模块的记账同口径
    /// （服务端在门口校验五要素：action/actor/
    /// target/status/result|error/detail）。回执
    /// 为新建的留痕条目（201）
    func recordTrace(
        config: ServerConfig, action: String, actor: String,
        targetKind: String, targetID: String,
        targetLabel: String, targetRef: String,
        status: String, result: String?, error: String?,
        detail: [String: String]?
    ) async throws {
        let body = BridgeTraceReportRequest(
            action: action, actor: actor,
            target: .init(
                kind: targetKind, id: targetID,
                label: targetLabel, ref: targetRef
            ),
            status: status, result: result, error: error,
            detail: detail
        )
        let _: BridgeTrace = try await send(
            config: config, path: "/traces", method: "POST",
            body: body, endpoint: L10n.string("留痕自报"),
            collection: false
        )
    }

    // MARK: - 请求底座（基座代行，本类只给状态口径）

    private func makeRequest(
        config: ServerConfig, path: String, method: String
    ) throws -> URLRequest {
        try base.makeRequest(config: config, path: path, method: method)
    }

    private func get<T: Decodable>(
        config: ServerConfig, path: String, endpoint: String,
        collection: Bool
    ) async throws -> T {
        try await base.get(
            config: config, path: path, endpoint: endpoint
        ) { http, data in
            try self.base.checkStatus(
                http, data: data, endpoint: endpoint,
                collection: collection
            )
        }
    }

    private func send<Body: Encodable, T: Decodable>(
        config: ServerConfig, path: String, method: String,
        body: Body, endpoint: String, collection: Bool
    ) async throws -> T {
        try await base.send(
            config: config, path: path, method: method,
            body: body, endpoint: endpoint
        ) { http, data in
            try self.base.checkStatus(
                http, data: data, endpoint: endpoint,
                collection: collection
            )
        }
    }

    private func sendEmpty<T: Decodable>(
        config: ServerConfig, path: String, method: String,
        endpoint: String
    ) async throws -> T {
        try await base.sendEmpty(
            config: config, path: path, method: method,
            endpoint: endpoint
        ) { http, data in
            try self.base.checkStatus(
                http, data: data, endpoint: endpoint,
                collection: false
            )
        }
    }

    private func send(
        _ request: URLRequest, endpoint: String
    ) async throws -> (Data, HTTPURLResponse) {
        try await base.data(for: request, endpoint: endpoint)
    }
}
/// 留痕自报请求体（§383）：与桥 POST /traces 的
/// 五要素契约同形（target 与 BridgeTraceTarget
/// 同四键）
private struct BridgeTraceReportRequest: Encodable {
    struct Target: Encodable {
        let kind: String
        let id: String
        let label: String
        let ref: String
    }

    let action: String
    let actor: String
    let target: Target
    let status: String
    let result: String?
    let error: String?
    let detail: [String: String]?
}
