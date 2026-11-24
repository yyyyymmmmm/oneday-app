import OneDayCore
import OneDayDesign
import SwiftUI

/// 配对引导页共用骨架（台账 199，普查 R2 收敛）：
/// Telegram/飞书打样页（ChannelPairingView）与令
/// 牌四家页（TokenChannelPairingView）此前同结构各
/// 写一份——页头、状态带、页脚、列表 chrome 全是
/// 两套实现，相位判定更是一份在 Core、一份在本
/// 文件内靠纪律对齐的重写。自此骨架只留本文件一
/// 套：两宿主只留各自真差异（逐家步骤内容与字段
/// 规格、提交路径），相位判定统一走 Core
/// ChannelApplyPhase（宿主把回执与 status 喂进来）。
/// 状态带文案以打样页口径为单源；飞书专属补注
/// （第四步提醒）以入参注入，不在共用件里判平台

/// 页头：官方图标＋平台名＋一句人话（副题由宿主
/// 按平台给）
struct ChannelPairingHeaderSection: View {
    let channel: ChannelDescriptor
    let subtitle: String

    var body: some View {
        Section {
            VStack(spacing: OneDayMetrics.spacingS) {
                if let asset = channel.iconAssetName {
                    Image(asset)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 72, height: 72)
                        .accessibilityHidden(true)
                }
                Text(channel.name)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Palette.ink)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(Palette.inkSecondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, OneDayMetrics.spacingSM)
            .listRowBackground(Palette.surface)
        }
    }
}

/// 状态带：加载／读不到／四态呈现＋「正在生效」
/// 期间的自动刷新轮询，一并收在本件——相位由宿
/// 主经 Core ChannelApplyPhase 解算后注入，本件
/// 只呈现与陪跑
struct ChannelPairingStatusSection: View {
    let channel: ChannelDescriptor
    var store: ChannelStatusStore
    let phase: ChannelApplyPhase
    /// 等待生效带内的平台专属补注（飞书第四步提
    /// 醒），其余平台 nil
    var pendingNote: String? = nil
    /// 正在生效带内的平台专属补注（飞书第四步提
    /// 醒），其余平台 nil
    var applyingNote: String? = nil
    var onShowList: () -> Void

    @Environment(AppState.self) private var appState

    private var status: ChannelPlatformStatus? {
        store.status(for: channel.id)
    }

    var body: some View {
        Section {
            if store.isLoading, status == nil {
                HStack(spacing: OneDayMetrics.spacingS) {
                    ProgressView()
                    Text("正在读取状态…")
                        .font(.bodyText)
                        .foregroundStyle(Palette.inkSecondary)
                }
                .listRowBackground(Palette.surface)
            } else if status == nil, let error = store.loadError {
                VStack(alignment: .leading,
                       spacing: OneDayMetrics.spacingS) {
                    Text("暂时读不到状态")
                        .font(.rowTitle)
                        .foregroundStyle(Palette.ink)
                    Text(error)
                        .font(.captionText)
                        .foregroundStyle(Palette.inkSecondary)
                    Button("重试") {
                        Task { await store.load(appState: appState) }
                    }
                }
                .listRowBackground(Palette.surface)
            } else if let status {
                statusBand(status)
                    .listRowBackground(Palette.surface)
            }
        }
        .task(id: phase == .applying) {
            await pollWhileApplying()
        }
    }

    /// 正在生效期间自动刷新状态：每 3 秒回读一次、
    /// 最多约两分钟；status 翻 connected/error 后
    /// 相位退场、循环收口，页面消失自动取消
    private func pollWhileApplying() async {
        guard phase == .applying else { return }
        for _ in 0..<40 {
            try? await Task.sleep(for: .seconds(3))
            if Task.isCancelled { return }
            await store.load(appState: appState)
            if phase != .applying { return }
        }
    }

    @ViewBuilder
    private func statusBand(
        _ status: ChannelPlatformStatus
    ) -> some View {
        switch phase {
        case .applying:
            applyingBand
        case .applyFailed(let reason):
            applyFailedBand(reason)
        case .none, .awaitingRestart:
            // 未触发即时生效时 status 的等待态就是如
            // 实口径；无流程态时呈现完全归 status
            statusStateBand(status)
        }
    }

    @ViewBuilder
    private func statusStateBand(
        _ status: ChannelPlatformStatus
    ) -> some View {
        switch status.state {
        case "connected":
            VStack(alignment: .leading,
                   spacing: OneDayMetrics.spacingS) {
                Text("已配对")
                    .font(.rowTitle)
                    .foregroundStyle(Palette.ink)
                Text("这个频道已经连上了。")
                    .font(.captionText)
                    .foregroundStyle(Palette.inkSecondary)
                Button("去频道看看") { onShowList() }
            }
        case "pending_restart":
            VStack(alignment: .leading,
                   spacing: OneDayMetrics.spacingS) {
                Text("钥匙已保存，等待生效")
                    .font(.rowTitle)
                    .foregroundStyle(Palette.ink)
                Text(L10n.string("服务器下一次重启后就会自动连上，这期间"
                    + "不用你再做什么。连上之后，抽屉里这一行"
                    + "会变成已配对的样子。"))
                    .font(.captionText)
                    .foregroundStyle(Palette.inkSecondary)
                if let pendingNote {
                    Text(pendingNote)
                        .font(.captionText)
                        .foregroundStyle(Palette.inkSecondary)
                }
                Button("刷新状态") {
                    Task { await store.load(appState: appState) }
                }
            }
        case "error":
            VStack(alignment: .leading,
                   spacing: OneDayMetrics.spacingS) {
                Text("连接失败")
                    .font(.rowTitle)
                    .foregroundStyle(Palette.danger)
                if let message = status.message {
                    Text(message)
                        .font(.captionText)
                        .foregroundStyle(Palette.inkSecondary)
                }
                Text("检查一下钥匙，按下面三步重新连接。")
                    .font(.captionText)
                    .foregroundStyle(Palette.inkSecondary)
            }
        default:
            VStack(alignment: .leading,
                   spacing: OneDayMetrics.spacingS) {
                Text("还没配对")
                    .font(.rowTitle)
                    .foregroundStyle(Palette.ink)
                Text("按下面三步连上，几分钟就好。")
                    .font(.captionText)
                    .foregroundStyle(Palette.inkSecondary)
            }
        }
    }

    /// 正在生效带（回执 applyTriggered=true）：网关
    /// 重启的空窗里给明确的进行时，不许显成笼统的
    /// 连接中/等待；status 翻 connected 后由状态带
    /// 正常收口（ChannelEntryView 会直接进频道页）
    private var applyingBand: some View {
        VStack(alignment: .leading,
               spacing: OneDayMetrics.spacingS) {
            HStack(spacing: OneDayMetrics.spacingS) {
                ProgressView()
                Text("正在生效")
                    .font(.rowTitle)
                    .foregroundStyle(Palette.ink)
            }
            Text(L10n.string("钥匙已保存，服务器正在让它生效，通常"
                + "几秒钟就好。连上之后这里会自动变成已配对"
                + "的样子，你不用再做什么。"))
                .font(.captionText)
                .foregroundStyle(Palette.inkSecondary)
            if let applyingNote {
                Text(applyingNote)
                    .font(.captionText)
                    .foregroundStyle(Palette.inkSecondary)
            }
        }
    }

    /// 即时生效没触发成功的回退带：口径仍是等待生
    /// 效，原因用桥回的人话原样摆出来——不许包装
    /// 成已经在生效
    private func applyFailedBand(_ reason: String) -> some View {
        VStack(alignment: .leading,
               spacing: OneDayMetrics.spacingS) {
            Text("钥匙已保存，等待生效")
                .font(.rowTitle)
                .foregroundStyle(Palette.ink)
            Text(reason)
                .font(.captionText)
                .foregroundStyle(Palette.inkSecondary)
            Text(L10n.string("服务器下一次重启后就会自动连上，这期间"
                + "不用你再做什么。连上之后，抽屉里这一行"
                + "会变成已配对的样子。"))
                .font(.captionText)
                .foregroundStyle(Palette.inkSecondary)
            Button("刷新状态") {
                Task { await store.load(appState: appState) }
            }
        }
    }
}

/// 页脚：钥匙归属一句话，两页同文同式
struct ChannelPairingFooterSection: View {
    var body: some View {
        Section {
            Text("钥匙只存在你自己的服务器上，这个 App 不保存。")
                .font(.captionText)
                .foregroundStyle(Palette.inkSecondary)
                .frame(maxWidth: .infinity)
                .multilineTextAlignment(.center)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
        }
    }
}

extension View {
    /// 配对引导页的列表 chrome 单源（台账 199）：
    /// insetGrouped 列表、段距、设置底、导航标题与
    /// 「完成」工具钮、下拉刷新——两宿主共用，不许
    /// 两边各写一份漂移
    func channelPairingListChrome(
        title: String,
        onClose: @escaping () -> Void,
        onRefresh: @escaping () async -> Void
    ) -> some View {
        self
            .listStyle(.insetGrouped)
            .listSectionSpacing(OneDayMetrics.settingsSectionSpacing)
            .scrollContentBackground(.hidden)
            .background(Palette.settingsBG)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("完成") { onClose() }
                }
            }
            .refreshable { await onRefresh() }
    }
}
