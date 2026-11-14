import OneDayCore
import OneDayDesign
import SwiftData
import SwiftUI

/// 本地线程关联集派生（0.36.29，频道规格 §2 R2）：
/// 分类函数的 linkedThreadSessionIDs 入参——存在
/// 非主线本地线程关联的服务端会话 id 集（出生/收
/// 养证明）。主线判定走 Core SideChatClassifier
/// .isMain 双信号（与抽屉旁聊区同一函数）：绑着主
/// 线会话的线程即主线线程，其关联不算旁聊出生证
/// 明。抽屉频道区、Hermes 频道页、全部对话页三面
/// 共用本派生，不许各面重算。
enum ThreadLinkage {
    @MainActor
    static func nonMainLinkedSessionIDs(
        threads: [ChatThread], sideChats: SideChatStore
    ) -> Set<String> {
        var ids = Set<String>()
        for thread in threads {
            guard let sessionID = thread.serverSessionID,
                  !sessionID.isEmpty else { continue }
            if SideChatClassifier.isMain(
                localThreadID: thread.id,
                linkedServerSessionID: sessionID,
                mainThreadID: sideChats.mainThreadID,
                mainServerSessionID: sideChats.mainServerSessionID
            ) {
                continue
            }
            ids.insert(sessionID)
        }
        return ids
    }
}

/// Hermes 频道页（0.36.29，频道规格 §4）：非 App
/// 出生、来自这台 Hermes 其他表面（网页/接口）的
/// 会话名单。入口两处同目的地（抽屉频道行、全部
/// 对话页「频道」段 Hermes 行），均以全屏页承载
/// （ContentView/管理页既有 fullScreenCover 通道，
/// 不新造容器）。名单＝Core 分类后归 Hermes 频道
/// 的会话（含合并桶只读特例行），startedAt 倒序；
/// 普通行点按走既有续聊通道续聊即收养（R2 升层、
/// 下轮名单刷新该行消失，首次收养的 notice 在
/// ChatView 消费口落）；页内不做搜索（全量搜索在
/// 全部对话页一处，不许两套）。
struct HermesChannelView: View {
    /// 打开会话（宿主关页＋切聊天格＋置 pendingChat-
    /// SessionID；频道标记由本页点行时先行置位）
    var onOpenSession: (String) -> Void
    var onClose: () -> Void

    @Environment(AppState.self) private var appState
    /// 本地写上下文（§223 删除收口清线程用）
    @Environment(\.modelContext) private var modelContext
    @Query private var threads: [ChatThread]
    @State private var store = HermesChannelStore()

    private var channel: ChannelDescriptor { ChannelRegistry.hermes }

    /// 名单分筐（每次呈现按当前拉取与本地关联现算，
    /// 与分类纯函数同口径；收养后重开本页即按新分
    /// 类刷新）
    private var partition: SessionPartition {
        SessionClassifier.partition(
            sessions: store.sessions,
            mainServerSessionID: appState.sideChats.mainServerSessionID,
            linkedThreadSessionIDs: ThreadLinkage.nonMainLinkedSessionIDs(
                threads: threads, sideChats: appState.sideChats
            )
        )
    }

    /// 频道全名单（普通行＋合并桶行）：合并桶与普通
    /// 行在分筐里是两筐、各自保序，呈现按 startedAt
    /// 倒序统一重排（规格 §4.1）；无开始时间者沉底
    private var channelRows: [ServerSession] {
        partition.hermesChannelSessions.sorted {
            ($0.startedDate ?? .distantPast)
                > ($1.startedDate ?? .distantPast)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(channel.pageSubtitle)
                        .font(.captionText)
                        .foregroundStyle(Palette.inkSecondary)
                        .listRowSeparator(.hidden)
                }
                if store.isLoading, store.sessions.isEmpty {
                    Text("正在读取…")
                        .font(.captionText)
                        .foregroundStyle(Palette.inkSecondary)
                } else if let error = store.loadError {
                    Text(error)
                        .font(.captionText)
                        .foregroundStyle(Palette.inkSecondary)
                } else if channelRows.isEmpty {
                    ContentUnavailableView(
                        "还没有从其他地方来的对话",
                        systemImage: "tray",
                        description: Text("在这台 Hermes 的网页端或通过接口开始的对话会出现在这里，点开就能接着聊。")
                    )
                    .listRowSeparator(.hidden)
                } else {
                    ForEach(channelRows) { session in
                        if SideChatLink.isMergeBucket(session.id) {
                            bucketRow(session)
                        } else {
                            ServerSessionRow(
                                session: session,
                                title: rowTitle(session),
                                onOpen: { openSession(session) },
                                onChanged: {
                                    Task {
                                        await store.load(appState: appState)
                                    }
                                },
                                onDeleted: { id in
                                    // §223：频道页删除同走共
                                    // 享收口（旧路不回写共享
                                    // 目录、本地线程残留）
                                    DeletedSessionCloseout.apply(
                                        sessionID: id,
                                        appState: appState,
                                        threads: threads,
                                        modelContext: modelContext
                                    )
                                }
                            ) {
                                rowLabel(session)
                            }
                        }
                    }
                }
            }
            .listStyle(.plain)
            .background(Palette.pageBG)
            .navigationTitle(channel.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("完成") { onClose() }
                }
            }
            // 合并桶只读详情（§4.3）：值路由进详情的
            // 只读形态——不提供续聊入口、不发写请求
            .navigationDestination(for: String.self) { id in
                ServerSessionDetailView(sessionID: id, readOnly: true)
            }
            .refreshable { await store.load(appState: appState) }
        }
        .task { await store.load(appState: appState) }
    }

    /// 合并桶特例行（§4.3）：普通行同型呈现＋行尾
    /// 小字标「旧合并记录」；**不挂长按菜单**（防从
    /// 新面误触归档/删除，管理页既有警告链不变），
    /// 点开只读查看。本行不走 ServerSessionRow（其
    /// 本体自带四件菜单，与只读口径冲突）
    private func bucketRow(_ session: ServerSession) -> some View {
        NavigationLink(value: session.id) {
            HStack(spacing: OneDayMetrics.spacingS) {
                rowLabel(session)
                Text("旧合并记录")
                    .font(.captionText)
                    .foregroundStyle(Palette.inkSecondary)
                    .fixedSize(horizontal: true, vertical: false)
            }
        }
    }

    /// 普通行点按续聊：先置频道来源标记、再走宿主
    /// 续聊通道（标记与 pendingChatSessionID 同行，
    /// ChatView 消费口据此落频道出处与收养提示，
    /// 见 AppState.pendingChatChannelID 注）
    private func openSession(_ session: ServerSession) {
        appState.pendingChatChannelID = ChannelRegistry.hermesChannelID
        onOpenSession(session.id)
    }

    /// 行标题：与全部对话页同口径（存量本地覆盖优
    /// 先，其后统一管线 resolvedTitle）
    private func rowTitle(_ session: ServerSession) -> String {
        appState.sideChats.titleOverrides[session.id]
            ?? appState.sessionTitles.title(for: session)
    }

    /// 行面：标题（统一管线）＋置顶标＋人话副题，与
    /// 全部对话页行同型（标题/副题管线全 App 同源）
    private func rowLabel(_ session: ServerSession) -> some View {
        VStack(alignment: .leading, spacing: OneDayMetrics.stackGap) {
            HStack(spacing: OneDayMetrics.rowInnerGap) {
                Text(rowTitle(session))
                    .font(.rowTitle)
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                if session.isPinned == true {
                    Image(systemName: "pin.fill")
                        .font(.caption2)
                        .foregroundStyle(Palette.inkMuted)
                }
            }
            Text(session.humanSubtitle(now: Date()))
                .font(.meta)
                .foregroundStyle(Palette.inkSecondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
}

/// 频道页数据层（0.36.29）：可见全量分页拉取（与
/// 全部对话页 fetchAll 同口径：limit 100 逐页、上
/// 限 10 页）＋标题回落素材预算。只拉未归档集——
/// 分类规则作用于未归档集（规格 §2），归档集在全
/// 部对话页全量呈现
@MainActor
@Observable
final class HermesChannelStore {
    var sessions: [ServerSession] = []
    var isLoading = false
    var loadError: String?

    func load(appState: AppState) async {
        isLoading = true
        loadError = nil
        do {
            let visible = try await appState.performAdmin {
                client, config in
                var all: [ServerSession] = []
                var offset = 0
                for _ in 0..<10 {
                    let page = try await client.serverSessionsPage(
                        config: config, limit: 100,
                        offset: offset, archived: "exclude"
                    )
                    all.append(contentsOf: page.sessions)
                    if page.sessions.count < 100 { break }
                    if let total = page.total, all.count >= total { break }
                    offset += 100
                }
                return all
            }
            sessions = visible
            await appState.sessionTitles.ensureTitles(
                for: visible, appState: appState, budget: 12
            )
        } catch {
            loadError = (error as? HermesError)?.userMessage
                ?? "名单没拉下来，请稍后再试。"
        }
        isLoading = false
    }
}
