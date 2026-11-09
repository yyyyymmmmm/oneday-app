import OneDayDesign
import SwiftUI

/// 外观模式三档（0.4.0）：跟随系统／浅色／深色。AppStorage
/// 键 appearanceMode 为单一事实源——本页 Picker 写、根层
/// RootView 读后施加 .preferredColorScheme。
enum AppearanceMode: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system: return "跟随系统"
        case .light: return "浅色"
        case .dark: return "深色"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

/// 外观页（0.4.0 最小改型，审计 §1.1）：AccentTheme 主题
/// 体系整套废止——预览卡与五款主题选择整组撤下，本期只
/// 留系统外观三档 Picker 的占位结构；整页 Form 化与行
/// 规格对齐归二期。本期结构即系统 Form＋inline Picker，
/// 选择即时经 AppStorage 生效于根层。
struct AppearanceView: View {
    @AppStorage("appearanceMode") private var appearanceModeRaw =
        AppearanceMode.system.rawValue

    var body: some View {
        Form {
            Section("外观") {
                Picker(
                    "外观",
                    selection: Binding(
                        get: {
                            AppearanceMode(
                                rawValue: appearanceModeRaw
                            ) ?? .system
                        },
                        set: { appearanceModeRaw = $0.rawValue }
                    )
                ) {
                    ForEach(AppearanceMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            }
        }
        .navigationTitle("外观")
        .navigationBarTitleDisplayMode(.inline)
    }
}
