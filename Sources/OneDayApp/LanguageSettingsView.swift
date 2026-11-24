import OneDayCore
import OneDayDesign
import SwiftUI

/// 语言页（§503 自外观页迁出独立叶子页）：§145 的
/// 语言四档原在外观页尾节——语言是全局偏好（辖整
/// 个 App 界面与回复语言）、与聊天呈现分家，归位
/// 独立页与目录「语言」条目直达（SettingsCatalog
/// §503）。形态与模式行同构（四档勾选行）；档名经
/// L10n 按当前界面语言取词（切档瞬间整树重建、
/// 新语言下重渲本页，档名随之换语）；区脚小字如
/// 实注明系统托管面（权限弹窗/分享单等）仍随系统
/// 语言——平台常态、不在本档承诺内。键与消费链
/// 一字不动：AppStorage 单一事实源（Language-
/// StorageKeys.appLanguage），本页写、根层
/// OneDayApp 消费（.environment＋.id 整树重建，
/// 即时生效不重启）
struct LanguageSettingsView: View {
    @AppStorage(LanguageStorageKeys.appLanguage)
    private var appLanguageRaw = AppLanguagePreference.system.rawValue

    private var languagePreference: AppLanguagePreference {
        AppLanguagePreference(rawValue: appLanguageRaw) ?? .system
    }

    var body: some View {
        List {
            Section {
                ForEach(AppLanguagePreference.allCases) { item in
                    Button {
                        appLanguageRaw = item.rawValue
                    } label: {
                        HStack(spacing: OneDayMetrics.spacingSM) {
                            Color.clear
                                .frame(width: OneDayMetrics.iconSlot)
                                .accessibilityHidden(true)
                            Text(L10n.string(item.displayKey))
                                .font(.rowTitleL)
                                .foregroundStyle(Palette.ink)
                            Spacer()
                            if item == languagePreference {
                                Image(systemName: "checkmark")
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(Palette.primary)
                                    .accessibilityHidden(true)
                            }
                        }
                        .frame(minHeight: OneDayMetrics.settingsRowHeight)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.odPressable)
                    .accessibilityLabel(
                        L10n.string(item.displayKey)
                            + (item == languagePreference ? "，已选" : "")
                    )
                }
            } header: {
                SettingsSectionHeader(L10n.string("语言"))
            } footer: {
                Text(L10n.string("系统弹窗与分享界面等由系统显示的部分，仍跟随系统语言。"))
                    .font(.footnote)
                    .foregroundStyle(Palette.inkSecondary)
            }
            .listRowBackground(Palette.surface)
            .listRowInsets(OneDayMetrics.settingsRowInsets)
            .sensoryFeedback(.selection, trigger: appLanguageRaw)
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(OneDayMetrics.settingsSectionSpacing)
        .scrollContentBackground(.hidden)
        .background(Palette.settingsBG)
        .navigationTitle(L10n.string("语言"))
        .navigationBarTitleDisplayMode(.inline)
    }
}
