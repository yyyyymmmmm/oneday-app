import OneDayDesign
import OneDayCore
import SwiftUI

/// 日志页（设置·网关）：/api/logs 只读查看，级别与关键词
/// 筛选都走服务端参数；行按最新在前呈现（文件本身正序）。
struct LogsView: View {
    @Environment(AppState.self) private var appState

    @State private var lines: [String] = []
    @State private var level: String = ""
    @State private var search: String = ""
    @State private var errorMessage: String?
    @State private var isLoading = false

    private let levels: [(value: String, label: String)] = [
        ("", "全部"), ("error", "错误"), ("warning", "警告"),
        ("info", "信息"), ("debug", "调试"),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Picker("级别", selection: $level) {
                    ForEach(levels, id: \.value) { item in
                        Text(item.label).tag(item.value)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: level) { _, _ in
                    Task { await load() }
                }
                HStack(spacing: OneDayMetrics.spacingS) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 15))
                        .foregroundStyle(Palette.inkMuted)
                        .accessibilityHidden(true)
                    TextField("搜索日志", text: $search)
                        .font(.body)
                        .foregroundStyle(Palette.ink)
                        .onSubmit { Task { await load() } }
                    if !search.isEmpty {
                        Button {
                            search = ""
                            Task { await load() }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(Palette.inkMuted)
                        }
                        .accessibilityLabel("清空搜索")
                    }
                }
                .padding(.horizontal, OneDayMetrics.spacingSM)
                .frame(minHeight: OneDayMetrics.minTapTarget)
                .background(
                    Palette.fieldFill,
                    in: RoundedRectangle(cornerRadius: OneDayMetrics.fieldCorner)
                )
                .padding(.top, OneDayMetrics.spacingM)

                if let errorMessage {
                    InlineError(errorMessage)
                        .padding(.top, OneDayMetrics.spacingL)
                } else if lines.isEmpty && !isLoading {
                    Text("没有匹配的日志行。")
                        .font(.callout)
                        .foregroundStyle(Palette.inkSecondary)
                        .padding(.top, OneDayMetrics.spacingL)
                } else {
                    // 0.3.8 基线补遗（哲学条：数据先翻译连审
                    // 计都不例外）：日志行改人话三行结构——
                    // 人话动作＋白话说明＋级别·时间·模块脚注
                    // （LogDisplay 解析）；错误行标题点红（级
                    // 别在脚注里已明示，颜色只作强调）。原始
                    // 整行 mono 直出就此退场
                    VStack(alignment: .leading, spacing: OneDayMetrics.spacingM) {
                        ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                            let entry = LogDisplay.parse(line)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(entry.headline)
                                    .font(.callout)
                                    .foregroundStyle(
                                        line.contains("ERROR")
                                            ? Palette.danger : Palette.ink
                                    )
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                if let detail = entry.detail {
                                    Text(detail)
                                        .font(.footnote)
                                        .foregroundStyle(Palette.inkSecondary)
                                        .lineLimit(3)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                Text(entry.meta)
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundStyle(Palette.inkMuted)
                            }
                        }
                    }
                    .padding(.top, OneDayMetrics.spacingL)
                }
            }
            .padding(.horizontal, OneDayMetrics.pageGutter)
            .padding(.top, OneDayMetrics.spacingM)
            // 0.4.0（§3.2）：tabBarZone 手算留白删除，底部
            // 避让回系统安全区；留常规尾距
            .padding(.bottom, OneDayMetrics.spacingXL)
        }
        .background(Palette.pageBG)
        .navigationTitle("日志")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await load() }
        .task { await load() }
    }

    private func load() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let response = try await appState.performAdmin { client, config in
                try await client.logs(
                    config: config,
                    level: level.isEmpty ? nil : level,
                    search: search.isEmpty ? nil : search,
                    lines: 200
                )
            }
            lines = Array(response.lines.reversed())
            errorMessage = nil
        } catch {
            errorMessage = (error as? HermesError)?.userMessage ?? "日志读取失败。"
        }
    }
}
