import OneDayDesign
import SwiftUI

/// 点子格（0.6.0 一期占位）：二期才有数据层（蓝图 §4
/// 第二期：点子生成技能＋任务桥同仓 ideas 表）。一期只
/// 给原生空态＋一句事实文案，不放假卡片、假入口。
struct IdeasPlaceholderView: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView(
                "暂无点子",
                systemImage: "lightbulb",
                description: Text("点子会在第二期上线")
            )
            .background(Palette.pageBG)
            .navigationTitle("点子")
        }
    }
}

/// 目标格（0.6.0 一期占位）：二期随任务桥同仓建目标表
/// （蓝图 §2.14）。一期只给原生空态＋一句事实文案。
struct GoalsPlaceholderView: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView(
                "暂无目标",
                systemImage: "checklist",
                description: Text("目标会在第二期上线")
            )
            .background(Palette.pageBG)
            .navigationTitle("目标")
        }
    }
}
