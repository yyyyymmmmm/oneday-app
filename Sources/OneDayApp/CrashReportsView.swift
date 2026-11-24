import OneDayCore
import OneDayDesign
import SwiftUI

/// 崩溃报告面（DESIGN §384／总表 131 G-14）
///
/// CrashReportStore 的唯一可读面：设置→关于→内
/// 部实验节直达（与聊天诊断同置同式）。数据真回
/// 读——MetricKit 投递落盘的记录在此逐条呈现，
/// 全文皆已过隐私门（白名单字段＋三道清洗），可
/// 选中复制、可经系统分享整表外发（用户手动，
/// App 不自动上传）。只读呈现＋清空一钮，不写
/// 任何业务状态。
struct CrashReportsView: View {
    @State private var refreshTick = 0
    @State private var showClearConfirm = false

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()

    var body: some View {
        // refreshTick 入依赖：刷新钮自增即整面重读
        let _ = refreshTick
        let records = CrashReportStore.shared.all()
        List {
            if records.isEmpty {
                Section {
                    Text("暂无崩溃报告")
                        .font(.footnote)
                        .foregroundStyle(Palette.inkSecondary)
                }
                .listRowBackground(Palette.surface)
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
                }
            }
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(OneDayMetrics.settingsSectionSpacing)
        .scrollContentBackground(.hidden)
        .background(Palette.settingsBG)
        .navigationTitle("崩溃报告")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                ShareLink(item: CrashReportStore.shared.exportText()) {
                    Image(systemName: "square.and.arrow.up")
                }
                .disabled(records.isEmpty)
                Button {
                    refreshTick += 1
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
            "清空全部崩溃报告？",
            isPresented: $showClearConfirm,
            titleVisibility: .visible
        ) {
            Button("清空", role: .destructive) {
                CrashReportStore.shared.clear()
                refreshTick += 1
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("只清这台手机上的报告副本，不影响任何其他数据。")
        }
    }
}
