import Foundation
import OneDayCore
import SwiftData

/// 本地会话（里程碑 1 存储从简：SwiftData 两表）。
/// 0.4.0（审计 §3.4）：服务端会话与本地线程的映射打通
/// ——续聊导入时把服务端会话 id 落在 serverSessionID，
/// 再点同一条服务端会话按 id 找回本线程、不重复导入。
@Model
final class ChatThread {
    var id: UUID
    var title: String
    var createdAt: Date
    var updatedAt: Date
    /// 侧边栏置顶（0.3.6，§21；默认 false、SwiftData
    /// 轻量迁移，置顶组口径见 SidebarGrouping）
    var isPinned: Bool = false
    /// 关联的服务端会话 id（/api/sessions/{id}）：从
    /// 服务端会话导入续聊的线程导入时落；App 内新建
    /// 旁聊 0.21.0 起首发即建真会话落 id（此前恒
    /// nil——无状态重放不建会话，是标题断环的根）；
    /// 建会话失败的线程暂为 nil、下次发送再试（可
    /// 选＋默认 nil、SwiftData 轻量迁移）
    var serverSessionID: String? = nil
    /// 标题是否用户手改（0.20.0）：抽屉/管理页本地改名
    /// 时置 true——手改名永不被服务端 AI 标题覆盖
    /// （DrawerThreadTitle 解析口径；默认 false、Swift-
    /// Data 轻量迁移。此前本地存储无此标记，标题回流
    /// 无从分辨手改与派生，是 0.20.0 第三条的补环）
    var titleIsManual: Bool = false
    /// 旁聊链接失败留痕（0.21.0）：App 内旁聊首发建
    /// 服务端会话失败的累计次数与最近一次原因——
    /// 失败不挡消息（回退无状态重放）、不静默，下
    /// 次发送再试链接；链接成功即清零（状态机见
    /// OneDayCore.SideChatLink；默认值、SwiftData
    /// 轻量迁移）
    var linkFailureCount: Int = 0
    var linkLastError: String? = nil
    /// 本线程链接时锁定的模型（0.21.0）：建会话以
    /// require_model_lock 落锁时记下（＝建时胶囊所
    /// 选）；此后胶囊改选与记录不一致才推一次会话
    /// 内切换（POST /api/sessions/{id}/model）。导
    /// 入线程为 nil——锁非我方所设、永不代推（可
    /// 选＋默认 nil、SwiftData 轻量迁移）
    var linkedModel: String? = nil
    /// 服务端种子已落位（0.27.0）：本线程的历史已
    /// 经导入导入其自有 oneday- 会话（或线程出生即
    /// 带服务端历史——续聊导入线程落盘时直接置
    /// true）。自有会话未种子前不许进会话模式发送
    /// （发送计划见 SideChatLink.sendPlan）；合并桶
    /// 解绑重链时随新绑定重新种子（默认 false、
    /// SwiftData 轻量迁移）
    var serverSeeded: Bool = false

    @Relationship(deleteRule: .cascade, inverse: \ChatEntry.thread)
    var entries: [ChatEntry] = []

    init(title: String = L10n.string("新会话")) {
        id = UUID()
        self.title = title
        createdAt = Date()
        updatedAt = Date()
    }

    /// 按时间排序的消息（视图层统一走它，不散落 sort）
    var sortedEntries: [ChatEntry] {
        entries.sorted { $0.createdAt < $1.createdAt }
    }
}

@Model
final class ChatEntry {
    var id: UUID
    /// "user" / "assistant"（与 ChatMessage.role 同口径）
    var role: String
    var content: String
    /// 0.2.1：随消息发送的首张图片（JPEG 数据），气泡回显用；
    /// 多图发送时其余图片不落盘（只走当次请求）——
    /// §150 起此口径作废：全集落 imageDatasData，
    /// 本字段保留作首图兼容读口（存量条目与旧消费
    /// 者），呈现/查看器/重演改走 allImageDatas
    var imageData: Data?
    /// §150：随消息发送的全部图片（JPEG 数据，
    /// JSON 编码的 [Data]）——单槽 imageData 让多
    /// 图消息本地只剩一张（用户 19:09/19:11 真机
    /// 实证：服务端两张全收、本地气泡只显一张），
    /// 本字段落全集（可选＋默认 nil、SwiftData
    /// 轻量迁移，同 quoteRole 先例）
    var imageDatasData: Data? = nil
    /// 0.4.1：本条消息引用了哪条消息（长按「回复」）——
    /// 只在发送时由用户消息携带，存被引消息的角色与正文
    /// 原文两字段；摘要与注入拼装读时经 MessageQuote
    /// 生成（可选＋默认 nil、SwiftData 轻量迁移）
    var quoteRole: String? = nil
    var quoteContent: String? = nil
    /// 0.5.1：助手回复的思考原文（reasoning 通道落盘，
    /// §32）——只作折叠单元展示、不回灌请求上下文；
    /// reasoningSeconds 为流内实测思考耗时（首个思考增
    /// 量→首个正文增量或流结束），无思考或无数据为 nil
    /// （可选＋默认 nil、SwiftData 轻量迁移）
    var reasoning: String? = nil
    var reasoningSeconds: Double? = nil
    /// 0.8.0（P1 富内容）：工具调用卡的 JSON 编码 payload
    /// （OneDayCore.ToolCard）——非 nil 即本条是工具卡
    /// （role 恒 "tool"），不作气泡渲染、不进发送上下文
    /// （上下文组装只取 user/assistant，见 ChatView.send）
    var toolCardData: Data? = nil
    /// 0.8.0：历史导入消息里服务端图片路径的 JSON 编码
    /// （[String]）——图片本体在服务器，呈现时经文件
    /// 下载通道取回；本地发送消息的图片仍走 imageData
    var remoteImagePathsData: Data? = nil
    /// 0.46.1（§116）：历史导入/对账补缺的 user 消息
    /// 里网关展开块剥出的非图片附件路径（JSON 编码，
    /// 与 remoteImagePathsData 同形态）——呈现走用户
    /// 气泡文件牌、点开同走文件下载通道
    var remoteFilePathsData: Data? = nil
    /// §123（H1）：目标委派回响标记——非 nil 即本条是
    /// App 按真源（桥完成戳/任务板状态）落的回响条目，
    /// 值＝去重键（Core GoalEcho.key）。回响不是智能体
    /// 发言：呈现走居中通知行、不进发送上下文、不被
    /// 落定整段替换当半截删（见 ChatView 三处守卫）
    /// （可选＋默认 nil、SwiftData 轻量迁移）
    var echoKey: String? = nil
    /// §165（锚点包）：审批锚定标记——非 nil 即本条是
    /// 按伴生时序关联（anchor）把一条 write-gate 记录
    /// 物化回其发起对话的锚定条目，值＝去重键（Core
    /// ApprovalAnchor.key，形态 wg:<子系统>:<记录id>）。
    /// 与回响同族纪律：不是任何一方的发言——呈现走锚
    /// 定审批行（卡/已决行/失效行）、不进发送上下文、
    /// 不被落定整段替换当半截删、不进半截回填（见
    /// ChatView 守卫谓词 isSystemAnchored 的四处引用）；
    /// createdAt 落盘后由物化方改写为记录的 created_at
    /// ——sortedEntries 按它排序，条目自然落进发起那一
    /// 轮的位置、永不漂移（可选＋默认 nil、SwiftData
    /// 轻量迁移）
    var approvalKey: String? = nil
    /// 基础止血包（P1/P2）：发送失败标记——本条用户
    /// 消息的一轮没能成立（上传/链接失败）或 run 落
    /// 定失败时置真：条目留原地、气泡旁挂失败标记、
    /// 点标记以原条目重发（新 run＋新幂等键，不新建
    /// 重复条目）；重发启动即清、再失败再置。发送队
    /// 列正解的状态机全套归专包，本字段只承「失败」
    /// 一态（默认 false、SwiftData 轻量迁移，同
    /// isPinned 先例）
    var sendFailed: Bool = false
    var createdAt: Date
    var thread: ChatThread?

    init(role: String, content: String, thread: ChatThread? = nil, imageData: Data? = nil, imageDatas: [Data] = [], quote: MessageQuote? = nil, reasoning: String? = nil, reasoningSeconds: Double? = nil, toolCard: ToolCard? = nil, remoteImagePaths: [String] = [], remoteFilePaths: [String] = [], echoKey: String? = nil, approvalKey: String? = nil) {
        id = UUID()
        self.role = role
        self.content = content
        // §150：全集在场时首图以全集首张为准（与
        // imageData 兼容读口同值），全集另落
        // imageDatasData；只有单图入参的旧调用点
        // （imageData）行为不变
        self.imageData = imageDatas.first ?? imageData
        imageDatasData = imageDatas.isEmpty
            ? nil
            : try? JSONEncoder().encode(imageDatas)
        quoteRole = quote?.role
        quoteContent = quote?.content
        self.reasoning = reasoning
        self.reasoningSeconds = reasoningSeconds
        toolCardData = toolCard.flatMap {
            try? JSONEncoder().encode($0)
        }
        remoteImagePathsData = remoteImagePaths.isEmpty
            ? nil
            : try? JSONEncoder().encode(remoteImagePaths)
        remoteFilePathsData = remoteFilePaths.isEmpty
            ? nil
            : try? JSONEncoder().encode(remoteFilePaths)
        self.echoKey = echoKey
        self.approvalKey = approvalKey
        createdAt = Date()
        self.thread = thread
    }

    /// 系统锚定条目（§165 统一谓词，规格 §4.1）：回响
    /// （echoKey）与审批锚定（approvalKey）同族——都
    /// 是 App 按真源落进对话流的事实条目、不是发言。
    /// 四处守卫（发送上下文排除／落定整段替换跳过／
    /// 半截名单排除／半截回填排除）一律引本谓词，不
    /// 另起平行判断
    var isSystemAnchored: Bool {
        echoKey != nil || approvalKey != nil
    }

    /// 工具卡解码缓存（§135 B 案，非持久化）：旧形
    /// 态 toolCard 是计算属性、每次访问现解码——一遍
    /// 列表 body 内每条工具条目被解码 2–3 次（成组
    /// 走查／分隔过滤／气泡渲染），外加事实信号的全
    /// 量走查，是发送帧全量重算的一环。缓存以源数
    /// 据本体为失效键：toolCardData 变更（落定回填、
    /// 导入覆写）即源不等、自动重解；解码失败（损坏
    /// 数据）同样入缓存，不许每帧重试解码
    @Transient var toolCardCacheValue: ToolCard? = nil
    @Transient var toolCardCacheSource: Data? = nil

    /// 工具卡 payload 解码（无或损坏为 nil；结果按
    /// 源数据缓存，见 toolCardCacheSource）
    var toolCard: ToolCard? {
        guard let toolCardData else { return nil }
        if toolCardCacheSource == toolCardData {
            return toolCardCacheValue
        }
        let decoded = try? JSONDecoder().decode(
            ToolCard.self, from: toolCardData
        )
        toolCardCacheValue = decoded
        toolCardCacheSource = toolCardData
        return decoded
    }

    /// 本条全部本地图片（§150）：新落盘走
    /// imageDatasData 全集；存量条目（旧口径只落
    /// 首图）回落 imageData 单张——呈现、查看器
    /// 集合、重演三处同走本口径，不再各取首图
    var allImageDatas: [Data] {
        if let imageDatasData,
           let decoded = try? JSONDecoder().decode(
               [Data].self, from: imageDatasData
           ), !decoded.isEmpty {
            return decoded
        }
        if let imageData { return [imageData] }
        return []
    }

    /// 服务端图片路径（历史导入消息用）
    var remoteImagePaths: [String] {
        guard let remoteImagePathsData else { return [] }
        return (try? JSONDecoder().decode(
            [String].self, from: remoteImagePathsData
        )) ?? []
    }

    /// 服务端文件路径（历史导入/对账补缺的用户附件用）
    var remoteFilePaths: [String] {
        guard let remoteFilePathsData else { return [] }
        return (try? JSONDecoder().decode(
            [String].self, from: remoteFilePathsData
        )) ?? []
    }

    /// 落盘两字段 → 引用值对象（任一缺失即无引用）
    var quote: MessageQuote? {
        guard let quoteRole, let quoteContent else { return nil }
        return MessageQuote(role: quoteRole, content: quoteContent)
    }
}
