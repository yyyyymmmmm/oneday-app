import OneDayDesign
import SwiftUI

/// 管理页：里程碑 2 的入口结构先行，各模块接口路径摸排后逐个点亮
/// （清单见 docs/API-SURFACE.md 的「待摸排」节）。
/// v2 视觉（docs/DESIGN-V2.md §3.5）：行式列表、图标墨色一列、
/// 「开发中」是安静的等宽文字，不进胶囊。
struct ManageView: View {
    private struct Module: Identifiable {
        let id = UUID()
        let title: String
        let subtitle: String
        let icon: String
    }

    private let modules: [Module] = [
        Module(title: "模型与配置", subtitle: "切换模型、管理提供商与工具集", icon: "cpu"),
        Module(title: "记忆", subtitle: "查看与维护 Agent 的长期记忆", icon: "brain"),
        Module(title: "技能", subtitle: "已装技能的查看与开关", icon: "puzzlepiece.extension"),
        Module(title: "会话", subtitle: "服务端会话列表与清理", icon: "bubble.left.and.text.bubble.right"),
        Module(title: "定时任务", subtitle: "Cron 任务的查看与启停", icon: "clock.arrow.2.circlepath"),
        Module(title: "日志", subtitle: "网关与 Agent 运行日志", icon: "doc.text.magnifyingglass"),
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    SectionLabel("模块")
                    VStack(spacing: 0) {
                        ForEach(Array(modules.enumerated()), id: \.element.id) { index, module in
                            if index > 0 {
                                GroupDivider(inset: 56)
                            }
                            ContentRow(
                                icon: module.icon,
                                title: module.title,
                                subtitle: module.subtitle,
                                trailing: "开发中"
                            )
                        }
                    }
                    .odGroup()
                    .padding(.top, OneDayMetrics.spacingS)
                    Text("全部功能将在里程碑 2 逐个点亮。")
                        .font(TypeScale.footnote)
                        .foregroundStyle(Palette.inkMuted)
                        .padding(.top, OneDayMetrics.spacingM)
                }
                .padding(.horizontal, OneDayMetrics.pageGutter)
                .padding(.top, OneDayMetrics.spacingM)
                .padding(.bottom, OneDayMetrics.spacingXL)
            }
            .background(Palette.pageBG)
            .navigationTitle("管理")
        }
    }
}
