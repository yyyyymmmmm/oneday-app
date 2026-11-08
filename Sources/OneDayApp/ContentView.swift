import OneDayDesign
import SwiftUI

/// 底部四栏：总览 / 聊天 / 管理（里程碑 2）/ 设置。
struct ContentView: View {
    var body: some View {
        TabView {
            Tab("总览", systemImage: "gauge.with.dots.needle.33percent") {
                OverviewView()
            }
            Tab("聊天", systemImage: "bubble.left.and.bubble.right") {
                ChatView()
            }
            Tab("管理", systemImage: "square.grid.2x2") {
                ManageView()
            }
            Tab("设置", systemImage: "gearshape") {
                SettingsView()
            }
        }
        .tint(Palette.ink)
    }
}
