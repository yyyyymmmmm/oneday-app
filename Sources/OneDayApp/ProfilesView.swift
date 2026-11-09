import OneDayDesign
import OneDayCore
import SwiftUI

/// 档案页（设置·服务器）：档案列表＋切换。
/// 切换走 POST /api/profiles/active {name}，切换后新对话
/// 使用该档案的模型/技能/记忆（已有数据不迁移）。
struct ProfilesView: View {
    @Environment(AppState.self) private var appState

    @State private var profiles: [ProfileItem] = []
    @State private var activeName: String?
    @State private var errorMessage: String?
    @State private var isLoading = false
    @State private var pendingSwitch: ProfileItem?
    @State private var notice: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if !profiles.isEmpty {
                    // 0.3.7 卡 7：摘要卡——当前档案名＋「使用中」
                    if let activeName {
                        SectionLabel("现在用的")
                            .padding(.bottom, OneDayMetrics.spacingS)
                        HStack(spacing: OneDayMetrics.spacingSM) {
                            Text(activeName)
                                .font(.body)
                                .foregroundStyle(Palette.ink)
                            Spacer()
                            Text("使用中")
                                .font(.footnote)
                                .foregroundStyle(Palette.success)
                        }
                        .padding(.horizontal, OneDayMetrics.spacingM)
                        .frame(minHeight: OneDayMetrics.rowHeight)
                        .odGroup()
                    }
                    SectionLabel("全部档案")
                        .padding(.top, 28)
                        .padding(.bottom, OneDayMetrics.spacingS)
                    VStack(spacing: 0) {
                        ForEach(Array(profiles.enumerated()), id: \.element.id) { index, profile in
                            if index > 0 {
                                GroupDivider(inset: OneDayMetrics.spacingM)
                            }
                            profileRow(profile)
                        }
                    }
                    .odGroup()
                } else if let errorMessage {
                    InlineError(errorMessage)
                    Button("重试") { Task { await load() } }
                        .buttonStyle(.odSecondary)
                        .padding(.top, OneDayMetrics.spacingSM)
                } else {
                    HStack(spacing: OneDayMetrics.spacingS) {
                        ProgressView()
                        Text("正在读取档案…")
                            .font(.footnote)
                            .foregroundStyle(Palette.inkSecondary)
                    }
                    .padding(.top, OneDayMetrics.spacingL)
                }
                if let notice {
                    Text(notice)
                        .font(.footnote)
                        .foregroundStyle(Palette.inkSecondary)
                        .padding(.top, OneDayMetrics.spacingM)
                }
            }
            .padding(.horizontal, OneDayMetrics.pageGutter)
            .padding(.top, OneDayMetrics.spacingM)
            .padding(.bottom, OneDayMetrics.spacingXL)
        }
        .background(Palette.pageBG)
        .navigationTitle("档案")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await load() }
        .task { await load() }
        .confirmationDialog(
            "切换档案？",
            isPresented: Binding(
                get: { pendingSwitch != nil },
                set: { if !$0 { pendingSwitch = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("切换到 \(pendingSwitch?.name ?? "")") {
                if let profile = pendingSwitch {
                    Task { await switchTo(profile) }
                }
                pendingSwitch = nil
            }
            Button("取消", role: .cancel) { pendingSwitch = nil }
        } message: {
            Text("切换后新的对话将使用该档案的模型、技能与记忆；当前对话不受影响。")
        }
    }

    private func profileRow(_ profile: ProfileItem) -> some View {
        let isActive = profile.name == activeName
        return Button {
            if !isActive {
                pendingSwitch = profile
            }
        } label: {
            HStack(spacing: OneDayMetrics.spacingSM) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: OneDayMetrics.spacingXS) {
                        Text(profile.name)
                            .font(.body)
                            .foregroundStyle(Palette.ink)
                        if profile.isDefault == true {
                            Text("默认")
                                .font(.caption)
                                .foregroundStyle(Palette.inkMuted)
                        }
                    }
                    Text(subtitle(profile))
                        .font(.footnote)
                        .foregroundStyle(Palette.inkSecondary)
                        .lineLimit(1)
                }
                Spacer(minLength: OneDayMetrics.spacingS)
                if isActive {
                    Text("使用中")
                        .font(.footnote)
                        .foregroundStyle(Palette.success)
                }
            }
            .padding(.horizontal, OneDayMetrics.spacingM)
            .padding(.vertical, OneDayMetrics.spacingS)
            .frame(minHeight: OneDayMetrics.rowHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func subtitle(_ profile: ProfileItem) -> String {
        var parts: [String] = []
        if let model = profile.model, !model.isEmpty {
            parts.append(model)
        }
        if let count = profile.skillCount {
            parts.append("技能 \(count)")
        }
        if profile.gatewayRunning == true {
            parts.append("网关运行中")
        }
        return parts.isEmpty ? "—" : parts.joined(separator: " · ")
    }

    private func load() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            async let list = appState.performAdmin { client, config in
                try await client.profiles(config: config)
            }
            async let active = appState.performAdmin { client, config in
                try await client.activeProfileName(config: config)
            }
            profiles = try await list
            activeName = try await active
            errorMessage = nil
        } catch {
            errorMessage = (error as? HermesError)?.userMessage ?? "档案读取失败。"
        }
    }

    private func switchTo(_ profile: ProfileItem) async {
        do {
            try await appState.performAdmin { client, config in
                try await client.setActiveProfile(config: config, name: profile.name)
            }
            activeName = profile.name
            notice = "已切换到档案 \(profile.name)。"
        } catch {
            notice = (error as? HermesError)?.userMessage ?? "切换失败，请稍后再试。"
        }
    }
}
