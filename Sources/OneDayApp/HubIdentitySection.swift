import OneDayCore
import OneDayDesign
import SwiftUI

/// 枢纽页身份段（规格 §3.5）：段内大名＋小头像、人设
/// 正文、风格块、全宽编辑钮（跳 ProfilesView，用户
/// 定案⑤：本页不直编）、SOUL/记忆双卡（L6，用户定案
/// ④打包）。卡面日期取不到字段就省略，不编造。
struct HubIdentitySection: View {
    let store: AgentHubStore

    var body: some View {
        if store.identityFailed {
            ContentUnavailableView {
                Label("人设读取失败", systemImage: "exclamationmark.triangle")
            } description: {
                Text("请稍后重试。")
            } actions: {
                Button("重试") {
                    Task { await store.loadIdentityIfNeeded() }
                }
                .buttonStyle(.bordered)
            }
        } else if let sections = store.soulSections {
            List {
                Section {
                    headerRow
                    personaBlock(sections)
                    if let style = sections.style {
                        styleBlock(style)
                    }
                    editRow
                }
                Section {
                    cardsRow
                }
            }
            .listStyle(.plain)
        } else {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /// 段内大名（左对齐）＋右端小头像（与页头同一视觉）
    private var headerRow: some View {
        HStack(spacing: OneDayMetrics.spacingSM) {
            Text(store.displayName)
                .font(.title)
                .fontWeight(.bold)
                .foregroundStyle(Palette.ink)
                .lineLimit(1)
            Spacer()
            ZStack {
                Circle().fill(Palette.chatSurface)
                Circle().stroke(Palette.hairline, lineWidth: 0.5)
                Image(systemName: "sparkles")
                    .font(.system(size: 20, weight: .regular))
                    .foregroundStyle(Palette.ink)
            }
            .frame(width: 52, height: 52)
        }
        .listRowSeparator(.hidden)
    }

    private func personaBlock(_ sections: SoulSections) -> some View {
        Text(sections.displayedPersona)
            .font(.body)
            .foregroundStyle(Palette.inkSecondary)
            .listRowSeparator(.hidden)
    }

    private func styleBlock(_ style: String) -> some View {
        VStack(alignment: .leading, spacing: OneDayMetrics.spacingXS) {
            Text("风格")
                .font(.caption)
                .foregroundStyle(Palette.inkSecondary)
            Text(style)
                .font(.body)
                .foregroundStyle(Palette.ink)
        }
        .listRowSeparator(.hidden)
    }

    /// 全宽「编辑」钮（规格 #40：系统 bordered 钮，内容
    /// 层不用玻璃）：跳 ProfilesView 改 soul（PUT 由该
    /// 页承载），本页只读
    private var editRow: some View {
        NavigationLink {
            ProfilesView()
        } label: {
            Label("编辑", systemImage: "pencil")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .listRowSeparator(.hidden)
    }

    /// 双卡并列等宽（规格 #41–#43，L6）：渐变矿物色面
    /// （内容层色面、合规），暗色给同系深值；SOUL 卡副
    /// 题「人设全文」、记忆卡副题「长期记忆」（不照抄
    /// 样板隐私文案）；日期无字段则省略
    private var cardsRow: some View {
        HStack(spacing: OneDayMetrics.spacingSM) {
            NavigationLink {
                HubSoulDetailView(store: store)
            } label: {
                identityCard(
                    title: "SOUL",
                    subtitle: "人设全文",
                    date: store.soulDocument?.updatedAt,
                    glyph: "heart",
                    gradient: Self.soulGradient
                )
            }
            .buttonStyle(.plain)

            NavigationLink {
                MemoryView()
            } label: {
                identityCard(
                    title: "记忆",
                    subtitle: "长期记忆",
                    date: nil,
                    glyph: "text.bubble",
                    gradient: Self.memoryGradient
                )
            }
            .buttonStyle(.plain)
        }
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(
            top: 8, leading: OneDayMetrics.pageGutter,
            bottom: 8, trailing: OneDayMetrics.pageGutter
        ))
    }

    private func identityCard(
        title: String, subtitle: String, date: Date?,
        glyph: String, gradient: LinearGradient
    ) -> some View {
        VStack(alignment: .leading, spacing: OneDayMetrics.spacingXS) {
            HStack {
                Text(title)
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundStyle(.white)
                Spacer()
                Image(systemName: glyph)
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(.white.opacity(0.9))
            }
            Spacer()
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.85))
            if let date {
                Text(AdminFormat.day(date))
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
        .padding(OneDayMetrics.spacingM)
        .frame(maxWidth: .infinity)
        .frame(height: 110)
        .background(
            gradient,
            in: RoundedRectangle(cornerRadius: OneDayMetrics.containerCorner)
        )
    }

    /// SOUL 卡渐变（暖灰矿物；样板口径，暗色同系深值）
    private static let soulGradient = LinearGradient(
        colors: [
            Color(UIColor { traits in
                traits.userInterfaceStyle == .dark
                    ? UIColor(red: 0x6E / 255.0, green: 0x65 / 255.0, blue: 0x57 / 255.0, alpha: 1)
                    : UIColor(red: 0xA8 / 255.0, green: 0x9F / 255.0, blue: 0x91 / 255.0, alpha: 1)
            }),
            Color(UIColor { traits in
                traits.userInterfaceStyle == .dark
                    ? UIColor(red: 0x55 / 255.0, green: 0x4D / 255.0, blue: 0x40 / 255.0, alpha: 1)
                    : UIColor(red: 0x8C / 255.0, green: 0x82 / 255.0, blue: 0x72 / 255.0, alpha: 1)
            }),
        ],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )

    /// 记忆卡渐变（紫调矿物；暗色同系深值）
    private static let memoryGradient = LinearGradient(
        colors: [
            Color(UIColor { traits in
                traits.userInterfaceStyle == .dark
                    ? UIColor(red: 0x6A / 255.0, green: 0x5F / 255.0, blue: 0x8C / 255.0, alpha: 1)
                    : UIColor(red: 0x9A / 255.0, green: 0x8F / 255.0, blue: 0xB8 / 255.0, alpha: 1)
            }),
            Color(UIColor { traits in
                traits.userInterfaceStyle == .dark
                    ? UIColor(red: 0x4E / 255.0, green: 0x45 / 255.0, blue: 0x68 / 255.0, alpha: 1)
                    : UIColor(red: 0x7C / 255.0, green: 0x6F / 255.0, blue: 0xA3 / 255.0, alpha: 1)
            }),
        ],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )
}

/// SOUL 全文详情（SOUL 卡点按落点，规格 #41）：只读
/// 呈现解析前的全文，编辑仍跳 ProfilesView
struct HubSoulDetailView: View {
    let store: AgentHubStore

    var body: some View {
        ScrollView {
            Text(store.soulDocument?.content ?? "")
                .font(.body)
                .foregroundStyle(Palette.ink)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(OneDayMetrics.pageGutter)
        }
        .background(Palette.pageBG)
        .navigationTitle("人设全文")
        .navigationBarTitleDisplayMode(.inline)
    }
}
