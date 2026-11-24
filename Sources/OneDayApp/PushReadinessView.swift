import OneDayCore
import OneDayDesign
import SwiftUI

/// 推送就绪面（总表 138，DESIGN §397）：渲染 PushRegis-
/// trationStore 的就绪报告——三行状态（通知权限／远程
/// 推送登记／服务端推送）＋总括，文案与判定全走 Core
/// PushReadiness 单源，本面只呈现、不自拟口径。
///
/// 入口（入口四问的答卷）：通知设置面（§385 Notifica-
/// tionSettingsView）是它唯一的家——该面在 162/163 线
/// 手里，本线不抢改其文件；本组件按可嵌入 Section 形
/// 态交付，组版合并时在该面加一行即接入（接法记
/// §397.5）。本分支内组件与 store 的接线形态由结构
/// 钉测在册把守，不许先落一个无入口的孤页。
struct PushReadinessView: View {
    let store: PushRegistrationStore

    var body: some View {
        Section {
            ForEach(
                Array(store.readinessReport.rows.enumerated()),
                id: \.offset
            ) { _, row in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: symbol(for: row.tone))
                        .foregroundStyle(color(for: row.tone))
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: OneDayMetrics.spacingMicro) {
                        Text(row.title)
                            .font(.subheadline)
                            .foregroundStyle(Palette.ink)
                        Text(row.statusText)
                            .font(.footnote)
                            .foregroundStyle(Palette.inkSecondary)
                    }
                }
            }
        } header: {
            Text("推送准备")
        } footer: {
            Text(store.readinessReport.summary)
        }
    }

    private func symbol(
        for tone: PushReadinessRow.Tone
    ) -> String {
        switch tone {
        case .ok: return "checkmark.circle.fill"
        case .pending: return "clock"
        case .blocked: return "exclamationmark.triangle.fill"
        case .info: return "info.circle"
        }
    }

    private func color(
        for tone: PushReadinessRow.Tone
    ) -> Color {
        switch tone {
        case .ok: return Palette.primary
        case .pending, .info: return Palette.inkSecondary
        case .blocked: return Palette.danger
        }
    }
}
