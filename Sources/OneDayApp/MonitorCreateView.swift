import OneDayCore
import OneDayDesign
import SwiftUI

/// 新建监测表单（0.12.1 P6 控制接线）：名称＋链接＋频率三档（手动检查/每小时/每天）。
/// 统一原生 iOS 26 Form，告别手绘 ScrollView + .odGroup()。
struct MonitorCreateView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    let store: MonitorsStore

    @State private var name = ""
    @State private var target = ""
    @State private var frequency: MonitorFrequency = .manual

    /// 与桥端 400 对齐的本地校验（单点在 Core）
    private var validationProblem: String? {
        MonitorCreateValidation.problem(name: name, target: target)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("名称") {
                        TextField("如：PokePay 价格页", text: $name)
                            .multilineTextAlignment(.trailing)
                    }
                    LabeledContent("链接") {
                        TextField("https://…", text: $target)
                            .keyboardType(.URL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .multilineTextAlignment(.trailing)
                    }
                } header: {
                    SettingsSectionHeader("监测目标")
                } footer: {
                    if let problem = validationProblem,
                       !name.isEmpty || !target.isEmpty {
                        Text(problem)
                            .font(.footnote)
                            .foregroundStyle(Palette.danger)
                    }
                }
                .listRowBackground(Palette.surface)

                Section {
                    Picker("检查频率", selection: $frequency) {
                        ForEach(MonitorFrequency.allCases, id: \.self) { option in
                            Text(option.label).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                } header: {
                    SettingsSectionHeader("多久检查一次")
                } footer: {
                    if let error = store.createError {
                        Text(error)
                            .font(.footnote)
                            .foregroundStyle(Palette.danger)
                    }
                }
                .listRowBackground(Palette.surface)
            }
            .scrollContentBackground(.hidden)
            .background(Palette.settingsBG)
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
        .fullscreenPopBridge()
    }
}
