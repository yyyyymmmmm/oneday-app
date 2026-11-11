import OneDayCore
import OneDayDesign
import SwiftUI

/// 表格呈现页（§125 表格二期）：xlsx 经伴生转码端
/// 点按 sheet 转 CSV（值口径），回 App 走既有阅读
/// 页表格呈现（DocumentReading.csv 块＋Document-
/// BlocksView 渲染器单源），sheet 分段切换；单
/// sheet 500 行截断由桥侧执行并明示，本页把截断
/// 说清、不静默。转码失败/超限落失败态——文案走
/// FileOpenFailure 转码分型（classifySpreadsheet），
/// 动作走 failureActions，不另立第二套。
struct SpreadsheetReaderView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    let target: FileOpenTarget

    private let bridgeClient = OneDayBridgeClient()

    @State private var spreadsheet: BridgeSpreadsheet?
    @State private var failure: FileOpenFailure?
    @State private var selectedSheet: String?
    @State private var shareItem: FileShareItem?

    private var entry: WorkspaceFileEntry { target.workspaceEntry }

    private var currentSheet: BridgeSpreadsheet.Sheet? {
        guard let spreadsheet else { return nil }
        if let selectedSheet,
           let sheet = spreadsheet.sheets.first(
               where: { $0.name == selectedSheet }
           ) {
            return sheet
        }
        return spreadsheet.sheets.first
    }

    var body: some View {
        Group {
            if let spreadsheet {
                if spreadsheet.sheets.isEmpty {
                    ContentUnavailableView(
                        "表格是空的",
                        systemImage: "tablecells",
                        description: Text("这个文件没有可读的工作表。")
                    )
                } else {
                    sheetBody(spreadsheet)
                }
            } else if let failure {
                failureView(failure)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Palette.pageBG)
        .navigationTitle(target.name)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $shareItem) { item in
            FileShareSheet(url: item.url)
        }
        .task { await load() }
    }

    private func sheetBody(
        _ spreadsheet: BridgeSpreadsheet
    ) -> some View {
        VStack(spacing: 0) {
            if spreadsheet.sheets.count > 1 {
                Picker(
                    "工作表",
                    selection: Binding(
                        get: { currentSheet?.name ?? "" },
                        set: { selectedSheet = $0 }
                    )
                ) {
                    ForEach(spreadsheet.sheets) { sheet in
                        Text(sheet.name).tag(sheet.name)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, OneDayMetrics.pageGutter)
                .padding(.vertical, OneDayMetrics.spacingS)
            }
            if let sheet = currentSheet {
                if sheet.csv.trimmingCharacters(
                    in: .whitespacesAndNewlines
                ).isEmpty {
                    ContentUnavailableView(
                        "工作表是空的",
                        systemImage: "tablecells",
                        description: Text("这个工作表没有内容。")
                    )
                } else {
                    DocumentBlocksView(
                        blocks: DocumentReading.blocks(
                            for: sheet.csv, kind: .csv
                        ),
                        notice: noticeText(
                            for: sheet, spreadsheet: spreadsheet
                        )
                    )
                }
            }
        }
    }

    /// 截断与口径注记：截断必明示（前 500 行/总行
    /// 数）；伴生 notes（公式无缓存值等如实标注）原
    /// 样带出，不加工不隐藏
    private func noticeText(
        for sheet: BridgeSpreadsheet.Sheet,
        spreadsheet: BridgeSpreadsheet
    ) -> String? {
        var lines: [String] = []
        if sheet.truncated {
            // 已显示行数由回带 CSV 实算（非空行减表
            // 头），上限数字不写死在端上——桥侧改上
            // 限时本页自动跟随，不许两处口径漂移
            let shownRows = max(
                0,
                sheet.csv.components(separatedBy: "\n")
                    .filter {
                        !$0.trimmingCharacters(
                            in: .whitespaces
                        ).isEmpty
                    }
                    .count - 1
            )
            lines.append(
                L10n.format(
                    "表格较大，只显示前 %lld 行（共 %lld 行）。",
                    Int64(shownRows), Int64(sheet.totalRows)
                )
            )
        }
        lines.append(contentsOf: spreadsheet.notes)
        return lines.isEmpty ? nil : lines.joined(separator: "\n")
    }

    private func failureView(_ failure: FileOpenFailure) -> some View {
        ContentUnavailableView {
            Label("打开失败", systemImage: "exclamationmark.triangle")
        } description: {
            Text(failure.message())
        } actions: {
            ForEach(
                FileActionPolicy.failureActions(for: entry),
                id: \.self
            ) { action in
                Button(action.label) {
                    performFailure(action)
                }
            }
        }
    }

    private func performFailure(_ action: FileFailureAction) {
        switch action {
        case .retry:
            Task { await load() }
        case .download:
            Task { await downloadOriginal() }
        case .dismiss:
            dismiss()
        }
    }

    /// 下载原文件（转码失败的出路）：走文件下载通
    /// 道取原字节落分享单——用别的 App 打开原 xlsx
    private func downloadOriginal() async {
        do {
            let data = try await appState.performAdmin {
                client, config in
                try await client.fileData(
                    config: config, path: target.path
                )
            }
            FileMetadataStore.shared.recordDownload(
                path: target.path, byteCount: data.count
            )
            shareItem = try FileShareItem.write(
                data: data, name: target.name
            )
        } catch {
            failure = (error as? HermesError).map {
                FileOpenFailure.classify(error: $0)
            } ?? .other
        }
    }

    private func load() async {
        failure = nil
        guard let config = appState.config else {
            failure = .serviceUnavailable
            return
        }
        do {
            spreadsheet = try await bridgeClient.spreadsheet(
                config: config, path: target.path
            )
        } catch let error as HermesError {
            failure = FileOpenFailure.classifySpreadsheet(
                error: error
            )
        } catch {
            // 无钥匙/桥未开通/网络不可达：服务不可用档
            failure = .serviceUnavailable
        }
    }
}
