import OneDayCore
import OneDayDesign
import SwiftUI

/// 新建监测表单（0.12.1 P6 控制接线）：名称＋链接＋
/// 频率三档（手动检查/每小时/每天）；间隔档落
/// intervalSeconds、scheduleText 由客户端组人话串
/// 上送（桥原样存作显示串）。cron 高级档本包不出
/// UI（契约字段在请求体留口）。创建走 MonitorsStore
/// 回读确认：列表里确认出现才关表单，未确认/失败
/// 的人话留在表单内，不假装建好。
struct MonitorCreateView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    let store: MonitorsStore

    @State private var name = ""
    @State private var target = ""
    @State private var frequency: MonitorFrequency = .manual

    /// 与桥端 400 对齐的本地校验（单点在 Core）：
    /// 有问题时创建钮禁用、问题原文露在表单里
    private var validationProblem: String? {
        MonitorCreateValidation.problem(name: name, target: target)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: OneDayMetrics.spacingL) {
                    VStack(alignment: .leading, spacing: 0) {
                        SectionLabel("监测")
                            .padding(.bottom, OneDayMetrics.spacingS)
                        VStack(spacing: 0) {
                            FieldRow(label: "名称") {
                                TextField("如：PokePay 价格页", text: $name)
                            }
                            GroupDivider()
                            FieldRow(label: "链接") {
                                TextField(
                                    "https://…", text: $target
                                )
                                .keyboardType(.URL)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                            }
                        }
                        .odGroup()
                    }
                    VStack(alignment: .leading, spacing: 0) {
                        SectionLabel("多久检查一次")
                            .padding(.bottom, OneDayMetrics.spacingS)
                        VStack(
                            alignment: .leading,
                            spacing: OneDayMetrics.spacingSM
                        ) {
                            Picker("频率", selection: $frequency) {
                                ForEach(
                                    MonitorFrequency.allCases, id: \.self
                                ) { option in
                                    Text(option.label).tag(option)
                                }
                            }
                            .pickerStyle(.segmented)
                            Text(frequencyNote)
                                .font(.footnote)
                                .foregroundStyle(Palette.inkSecondary)
                        }
                        .padding(OneDayMetrics.spacingM)
                        .odGroup()
                    }
                    if let problem = validationProblem,
                       !name.isEmpty || !target.isEmpty {
                        InlineError(problem)
                    }
                    if let error = store.createError {
                        InlineError(error)
                    }
                }
                .padding(.horizontal, OneDayMetrics.pageGutter)
                .padding(.top, OneDayMetrics.spacingM)
                .padding(.bottom, OneDayMetrics.spacingXL)
            }
            .background(Palette.pageBG)
            .navigationTitle("新建监测")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(store.creating ? "创建中…" : "创建") {
                        Task {
                            if await store.create(
                                appState: appState, name: name,
                                target: target, frequency: frequency
                            ) {
                                dismiss()
                            }
                        }
                    }
                    .disabled(validationProblem != nil || store.creating)
                }
            }
            .onAppear {
                store.clearCreateError()
            }
        }
    }

    /// 频率说明：手动档说清只在点检查时跑；自动档
    /// 说清先抓基线（基线本身不算变化，与桥口径一致）
    private var frequencyNote: String {
        switch frequency {
        case .manual:
            return "手动检查：只在你点「立即检查」时才会去看一次。"
        case .hourly, .daily:
            return "到点自动检查。新建时会先抓一次当前内容作基线，基线本身不算变化。"
        }
    }
}
