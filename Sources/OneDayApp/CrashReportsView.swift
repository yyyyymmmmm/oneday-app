import OneDayCore
import OneDayDesign
import SwiftUI

/// 崩溃报告面（DESIGN §384／总表 131 G-14 + hermes-deploy 2.6.0 服务端上报与回读）
/// 支持查看本机 MetricKit 崩溃记录、一键上传至 `POST /v1/diagnostics/crash-reports`，
/// 并通过 `GET /v1/diagnostics/crash-reports` 回读服务端已落盘记录。
struct CrashReportsView: View {
    @Environment(AppState.self) private var appState

    private enum Tab: String, CaseIterable {
        case local = "本机记录"
        case server = "服务端已上报"
    }

    @State private var selectedTab: Tab = .local
    @State private var refreshTick = 0
    @State private var showClearConfirm = false
    @State private var serverItems: [ServerCrashReportItem] = []
    @State private var isLoadingServer = false
    @State private var isUploading = false
    @State private var statusBanner: String?

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()

    var body: some View {
        let _ = refreshTick
        let records = CrashReportStore.shared.all()
        List {
            Section {
                Picker("来源", selection: $selectedTab) {
                    ForEach(Tab.allCases, id: \.self) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
            }

            if let statusBanner {
                Section {
                    Text(statusBanner)
                        .font(.footnote)
                        .foregroundStyle(Palette.inkSecondary)
                }
                .listRowBackground(Palette.surface)
                .listRowInsets(OneDayMetrics.settingsRowInsets)
            }

            if selectedTab == .local {
                if records.isEmpty {
                    Section {
                        Text("暂无本机崩溃报告")
                            .font(.footnote)
                            .foregroundStyle(Palette.inkSecondary)
                    }
                    .listRowBackground(Palette.surface)
                    .listRowInsets(OneDayMetrics.settingsRowInsets)
                } else {
                    ForEach(records) { record in
                        Section {
                            Text(record.displayText(
                                dateFormatter: Self.dateFormatter
                            ))
                            .font(.footnote.monospaced())
                            .textSelection(.enabled)
                        }
                        .listRowBackground(Palette.surface)
                        .listRowInsets(OneDayMetrics.settingsRowInsets)
                    }
                }
            } else {
                if isLoadingServer && serverItems.isEmpty {
                    Section {
                        HStack(spacing: OneDayMetrics.spacingS) {
                            ProgressView()
                            Text("正在读取服务端记录…")
                                .font(.footnote)
                                .foregroundStyle(Palette.inkSecondary)
                        }
                    }
                    .listRowBackground(Palette.surface)
                    .listRowInsets(OneDayMetrics.settingsRowInsets)
                } else if serverItems.isEmpty {
                    Section {
                        Text("服务端暂无已上报的崩溃报告")
                            .font(.footnote)
                            .foregroundStyle(Palette.inkSecondary)
                    }
                    .listRowBackground(Palette.surface)
                    .listRowInsets(OneDayMetrics.settingsRowInsets)
                } else {
                    ForEach(serverItems) { item in
                        Section {
                            Text(item.displayText)
                                .font(.footnote.monospaced())
                                .textSelection(.enabled)
                        }
                        .listRowBackground(Palette.surface)
                        .listRowInsets(OneDayMetrics.settingsRowInsets)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(OneDayMetrics.settingsSectionSpacing)
        .scrollContentBackground(.hidden)
        .background(Palette.settingsBG)
        .navigationTitle("崩溃报告")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            let uploaded = await CrashDiagnosticsCollector.shared.uploadPendingIfNeeded(appState: appState)
            if uploaded > 0 {
                statusBanner = "已自动上报 \(uploaded) 条脱敏崩溃记录至服务器。"
            }
            await loadServerReports()
        }
        .onChange(of: selectedTab) { _, tab in
            if tab == .server {
                Task { await loadServerReports() }
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    Task { await uploadNow() }
                } label: {
                    if isUploading {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "icloud.and.arrow.up")
                    }
                }
                .disabled(records.isEmpty || isUploading || appState.config == nil || appState.isDemo)
                .accessibilityLabel("上报到服务器")

                ShareLink(item: CrashReportStore.shared.exportText()) {
                    Image(systemName: "square.and.arrow.up")
                }
                .disabled(records.isEmpty)

                Button {
                    refreshTick += 1
                    Task { await loadServerReports() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }

                Button(role: .destructive) {
                    showClearConfirm = true
                } label: {
                    Image(systemName: "trash")
                }
                .disabled(records.isEmpty)
            }
        }
        .confirmationDialog(
            "清空全部本机崩溃报告？",
            isPresented: $showClearConfirm,
            titleVisibility: .visible
        ) {
            Button("清空", role: .destructive) {
                CrashReportStore.shared.clear()
                refreshTick += 1
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("只清这台手机上的报告副本，不影响服务端已上报的记录。")
        }
    }

    private func uploadNow() async {
        guard let config = appState.config,
              let apiKey = appState.apiKey,
              !appState.isDemo
        else { return }
        let records = CrashReportStore.shared.all()
        guard !records.isEmpty else { return }
        isUploading = true
        defer { isUploading = false }
        do {
            let receipt = try await appState.client.uploadCrashReports(
                config: config, apiKey: apiKey, reports: records
            )
            statusBanner = "已上报 \(receipt.accepted) 条记录至服务器。"
            await loadServerReports()
        } catch {
            statusBanner = (error as? HermesError)?.userMessage ?? "上报失败，请稍后重试。"
        }
    }

    private func loadServerReports() async {
        guard let config = appState.config,
              let apiKey = appState.apiKey,
              !appState.isDemo
        else { return }
        isLoadingServer = true
        defer { isLoadingServer = false }
        if let list = try? await appState.client.listServerCrashReports(
            config: config, apiKey: apiKey, limit: 50
        ) {
            serverItems = list
        }
    }
}
