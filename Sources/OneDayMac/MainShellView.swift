import SwiftUI
import OneDayDesign

/// 一级项（拟案信息架构）：iOS 底栏五格＋凭据库提级
/// ＋枢纽，逐件对位表落点见 docs/mac-parity.md
enum MacSection: String, CaseIterable, Identifiable {
    case chat
    case feed
    case ideas
    case goals
    case files
    case vault
    case hub

    var id: String { rawValue }

    var title: String {
        switch self {
        case .chat: return "聊天"
        case .feed: return "动态"
        case .ideas: return "想法"
        case .goals: return "目标"
        case .files: return "文件"
        case .vault: return "凭据库"
        case .hub: return "枢纽"
        }
    }

    var symbol: String {
        switch self {
        case .chat: return "bubble.left.and.bubble.right"
        case .feed: return "newspaper"
        case .ideas: return "lightbulb"
        case .goals: return "target"
        case .files: return "folder"
        case .vault: return "key"
        case .hub: return "point.3.connected.trianglepath.dotted"
        }
    }
}

/// 三栏主窗空壳（地基棒）：NavigationSplitView 三栏
/// 骨架——侧边栏（一级项＋频道/旁聊分组占位＋连接状
/// 态卡）、中栏（当前一级项的列表占位）、详情区（连
/// 接摘要）。只到壳：各面功能按对位表在后续棒逐面接
/// 入，占位处明示棒次，不冒充已实现。
struct MainShellView: View {
    @Environment(SessionStore.self) private var session
    @State private var section: MacSection? = .chat

    var body: some View {
        NavigationSplitView {
            sidebar
        } content: {
            contentColumn
        } detail: {
            detailColumn
        }
        .frame(minWidth: 980, minHeight: 620)
    }

    // MARK: - 栏 1：侧边栏

    private var sidebar: some View {
        List(selection: $section) {
            Section {
                ForEach(
                    [MacSection.chat, .feed, .ideas, .goals, .files, .vault]
                ) { item in
                    Label(item.title, systemImage: item.symbol)
                        .tag(item)
                }
            }
            Section("频道") {
                Text("暂无频道")
                    .foregroundStyle(.tertiary)
            }
            Section("旁聊") {
                Text("暂无旁聊")
                    .foregroundStyle(.tertiary)
            }
            Section {
                Label(MacSection.hub.title, systemImage: MacSection.hub.symbol)
                    .tag(MacSection.hub)
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .top) {
            connectionCard
        }
        .navigationSplitViewColumnWidth(min: 200, ideal: 230, max: 300)
    }

    /// 侧边栏顶：当前服务器＋健康点（拟案信息架构：
    /// 连接状态卡是侧边栏第一件）
    private var connectionCard: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(Color.green)
                .frame(width: 9, height: 9)
            VStack(alignment: .leading, spacing: 1) {
                Text(session.config?.host ?? "已连接")
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                Text("已连接")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - 栏 2：列表占位

    @ViewBuilder
    private var contentColumn: some View {
        switch section ?? .chat {
        case .chat:
            ContentUnavailableView(
                "暂无会话",
                systemImage: "bubble.left.and.bubble.right",
                description: Text("会话列表在聊天主链棒接入。")
            )
        case .hub:
            ContentUnavailableView(
                "枢纽",
                systemImage: MacSection.hub.symbol,
                description: Text("工作／审计／电脑／身份／邮件五面在枢纽棒接入。")
            )
        default:
            ContentUnavailableView(
                (section ?? .chat).title,
                systemImage: (section ?? .chat).symbol,
                description: Text("本面列表在后续棒按对位表接入。")
            )
        }
    }

    // MARK: - 栏 3：详情占位（连接摘要证明地基链路）

    @ViewBuilder
    private var detailColumn: some View {
        if section == .chat {
            connectionSummary
        } else {
            ContentUnavailableView(
                (section ?? .chat).title,
                systemImage: (section ?? .chat).symbol,
                description: Text("本面在后续棒按对位表接入。")
            )
        }
    }

    private var connectionSummary: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("已连接到你的服务器")
                .font(.title2.bold())
            VStack(alignment: .leading, spacing: 8) {
                summaryRow("服务器", session.config?.baseString ?? "—")
                summaryRow("Hermes 版本", session.hermesVersion ?? "—")
                summaryRow(
                    "当前模型", session.modelID ?? "—"
                )
                summaryRow(
                    "可用模型", "\(session.modelCount) 个"
                )
                summaryRow(
                    "服务端能力", session.capabilitySummary ?? "—"
                )
            }
            .padding(14)
            .background(
                Palette.surface,
                in: RoundedRectangle(cornerRadius: 10)
            )
            Text("登录链（健康检查 → 面板密码验证 → 换取登录密钥 → 模型与能力读取）已全链走通。聊天面在下一棒接入。")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.pageBG)
    }

    private func summaryRow(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title)
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(width: 76, alignment: .leading)
            Text(value)
                .font(.callout)
                .textSelection(.enabled)
                .lineLimit(2)
        }
    }
}
