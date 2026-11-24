import OneDayCore
import OneDayDesign
import SwiftData
import SwiftUI

/// 平台频道页（频道扩展一期）：已配对平台的会话名
/// 单，与 Hermes 频道页同口径——Core 分类里归本频
/// 道的会话按开始时间倒序，点行走既有续聊通道续聊
/// （续聊即与本地线程关联；分类跟随会话来源，平台
/// 会话常驻本频道不升层，见 R2 例外）。名单数据读
/// 账本频道投影（第 67 条包二：一处拉取口径，不许
/// 各频道页各拉一套）。
struct PlatformChannelView: View {
    let channel: ChannelDescriptor
    var onOpenSession: (String) -> Void
    var onClose: () -> Void

    @Environment(AppState.self) private var appState
    /// 本地写上下文（§223 删除收口清线程用）
    @Environment(\.modelContext) private var modelContext
    @Query private var threads: [ChatThread]
    @State private var store = HermesChannelStore()

    private var channelRows: [ServerSession] {
        appState.sessionLedger.channelList(
            appState: appState, localThreads: threads,
            channelID: channel.id
        ).sorted {
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
                if store.isLoading, channelRows.isEmpty {
                    Text("正在读取…")
                        .font(.captionText)
                        .foregroundStyle(Palette.inkSecondary)
                } else if let error = store.loadError {
                    Text(error)
                        .font(.captionText)
                        .foregroundStyle(Palette.inkSecondary)
                } else if channelRows.isEmpty {
                    ContentUnavailableView(
                        "这个频道里还没有对话",
                        systemImage: "tray",
                        description: Text("连上之后，在那边开始的对话会出现在这里，点开就能接着聊。")
                    )
                    .listRowSeparator(.hidden)
                } else {
                    ForEach(channelRows) { session in
                        ServerSessionRow(
                            session: session,
                            title: rowTitle(session),
                            onOpen: { openSession(session) },
                            onChanged: {
                                Task {
                                    await store.load(
                                        appState: appState,
                                        localThreads: threads
                                    )
                                }
                            },
                            onDeleteRequested: { session in
                                // §232 乐观删除：同拍摘账
                                // 本名单行＋协调器起手（墓
                                // 碑/后台删）；最终失败时
                                // 引擎恢复账本名单、本页
                                // 读投影自动回行
                                appState.sessionLedger
                                    .removeSession(
                                        sessionID: session.id
                                    )
                                appState.sessionDeletions.begin(
                                    sessionID: session.id,
                                    title: rowTitle(session),
                                    appState: appState,
                                    modelContext: modelContext
                                )
                            }
                        ) {
                            rowLabel(session)
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
            .refreshable {
                await store.load(
                    appState: appState, localThreads: threads
                )
            }
            // §232 恢复回行：本页直读账本投影，引擎恢
            // 复时账本名单回行即自动呈现（第 67 条包二）
        }
        .fullscreenPopBridge()
        .task {
            await store.load(
                appState: appState, localThreads: threads
            )
        }
    }

    private func openSession(_ session: ServerSession) {
        appState.router.pendingChatChannelID = channel.id
        onOpenSession(session.id)
    }

    private func rowTitle(_ session: ServerSession) -> String {
        appState.sessionLedger.title(
            for: session, appState: appState
        )
    }

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
