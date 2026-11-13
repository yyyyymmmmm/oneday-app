import OneDayCore
import OneDayDesign
import SwiftUI

/// 分区管理面（§198，抽屉包题二新建，照 Muse 本体
/// 侧边栏分区管理面形态）：抽屉四区——选项卡／频
/// 道／管理全部对话／旁聊——逐行「显示⇄隐藏」，写
/// 显隐账（Core SectionVisibilityState，落盘键
/// SectionVisibilityStorageKeys.drawerSections），
/// 抽屉渲染＝显隐账 ∧ 内容闸（合成在 Core
/// DrawerSectionGates：频道区无成员仍不显）。本面
/// 只管整区在不在，不管折叠——折叠是另一本账、另
/// 一件事，两账不合并（规格新面四问②）；入口＝设
/// 置页「侧边栏」行（目录条目 sidebar），抽屉内不
/// 另设编辑钮（避免双入口，四问①）。不设「空间」
/// 行：OneDay 无此区（场景功能未立项，审计 §0）。
/// 分隔走系统 List 口径（规格 R9）：四条目是同级
/// 行、行间有线、末行无线，本面无组头——不存在
/// 「标题与子项被线切开」的结构；抽屉的段内线几
/// 何不搬进本面、本面的系统线也不搬进抽屉
struct DrawerSectionsView: View {
    @AppStorage(SectionVisibilityStorageKeys.drawerSections)
    private var visibilityData: Data = Data()

    /// 显隐账现读（Core 唯一判定，缺键恒显示）
    private var visibility: [String: Bool] {
        SectionVisibilityState.decode(visibilityData)
    }

    var body: some View {
        List {
            Section {
                visibilityRow(
                    "选项卡", key: DrawerSectionKey.navigation
                )
                visibilityRow(
                    "频道", key: DrawerSectionKey.channels
                )
                visibilityRow(
                    "管理全部对话", key: DrawerSectionKey.manage
                )
                visibilityRow(
                    "旁聊", key: DrawerSectionKey.sideChats
                )
            }
            .listRowBackground(Palette.surface)
            .listRowInsets(settingsRowInsets)
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(OneDayMetrics.settingsSectionSpacing)
        .scrollContentBackground(.hidden)
        .background(Palette.settingsBG)
        .navigationTitle("侧边栏")
        .navigationBarTitleDisplayMode(.inline)
    }

    /// 一行：标题＋右侧「显示/隐藏」系统菜单选择器
    /// （Picker .menu——行尾值即当前显隐、点开可改；
    /// VoiceOver 读标题＋当前值，行可完整朗读，规格
    /// 四问④）。写账走 Core setting 直置目标态，不
    /// 经切换推导（重复选同一值不翻转）
    private func visibilityRow(
        _ title: String, key: String
    ) -> some View {
        Picker(selection: visibilityBinding(key)) {
            Text("显示").tag(true)
            Text("隐藏").tag(false)
        } label: {
            Text(title)
                .font(.rowTitleL)
                .foregroundStyle(Palette.ink)
        }
        .pickerStyle(.menu)
        .frame(minHeight: OneDayMetrics.settingsRowHeight)
        .accessibilityLabel(title)
    }

    private func visibilityBinding(
        _ key: String
    ) -> Binding<Bool> {
        Binding(
            get: {
                SectionVisibilityState.isVisible(
                    key: key, in: visibility
                )
            },
            set: { newValue in
                visibilityData = SectionVisibilityState.encode(
                    SectionVisibilityState.setting(
                        key: key, visible: newValue,
                        in: visibility
                    )
                ) ?? visibilityData
            }
        )
    }

    /// 与设置首页统一行盒（纵向 0、横向 20；行高由
    /// 行内容决定——SettingsView.settingsRowInsets
    /// 同口径在本页复刻，设置详情页先例同式）
    private var settingsRowInsets: EdgeInsets {
        EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20)
    }
}
