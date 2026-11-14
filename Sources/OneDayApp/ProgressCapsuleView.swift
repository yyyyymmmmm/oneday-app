import OneDayDesign
import OneDayCore
import SwiftUI

/// 顶部任务进展胶囊（0.37.0，设计 §4 定版）：聊天页
/// 顶栏下方一颗独立悬浮 pill，与身份胶囊并存。数据
/// 唯一来源＝工作台账（LedgerStore 同 payload 消费，
/// 派生与已耗时算法全在 Core ProgressCapsule /
/// LedgerElapsed，与台账同源同算法，不另建状态）。
/// 只在他聊/后台有进行中工作时出现；本聊的运行归
/// 本页消息区呈现，不进胶囊（Core 派生已剔除）。
struct ProgressCapsuleView: View {
    /// 当前聊天会话 id（派生时剔除它名下的条目）
    var currentSessionID: String?
    /// 台账条目里跳会话的出口（与枢纽台账段同通道）
    var onOpenSession: (String) -> Void

    @Environment(AppState.self) private var appState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var store = LedgerStore()
    /// §208：台账详情的任务下钻要 KanbanStore——本面
    /// 自持一份（与枢纽活动段同形态，进面时加载）
    @State private var kanbanStore = KanbanStore()
    @State private var detailItem: LedgerItem?

    private var content: ProgressCapsule.Content? {
        ProgressCapsule.derive(
            items: store.items, currentSessionID: currentSessionID
        )
    }

    var body: some View {
        Group {
            if let content {
                TimelineView(.periodic(from: .now, by: 1)) { timeline in
                    Button {
                        detailItem = store.items.first {
                            $0.id == content.headlineItemID
                        }
                    } label: {
                        HStack(spacing: OneDayMetrics.rowInnerGap) {
                            ProgressView()
                                .controlSize(.mini)
                            Text(appState.agentDisplayName)
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(Palette.ink)
                            Text(content.headlineText)
                                .font(.footnote)
                                .foregroundStyle(Palette.inkSecondary)
                                .lineLimit(1)
                            Text(LedgerElapsed.format(seconds: LedgerElapsed.elapsed(
                                startedAt: content.headlineStartedAt,
                                serverNow: store.displayServerNow(at: timeline.date)
                            )))
                            .font(.footnote.monospacedDigit())
                            .foregroundStyle(Palette.inkSecondary)
                        }
                        .padding(.horizontal, OneDayMetrics.spacingSM)
                        .padding(.vertical, OneDayMetrics.iconTextGap)
                        .glassEffect(.regular, in: Capsule())
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.odPressable)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(
            MotionTokens.resolved(MotionTokens.swap, reduceMotion: reduceMotion),
            value: content != nil
        )
        .task {
            await store.load(appState: appState)
            await kanbanStore.load(appState: appState)
            await store.runVisibleLoop(appState: appState)
        }
        .sheet(item: $detailItem) { item in
            NavigationStack {
                LedgerDetailView(
                    store: store, item: item,
                    hubStore: appState.sharedHubStore(),
                    kanbanStore: kanbanStore,
                    onOpenSession: { sessionID in
                        detailItem = nil
                        onOpenSession(sessionID)
                    }
                )
            }
            .presentationDragIndicator(.visible)
        }
    }
}
