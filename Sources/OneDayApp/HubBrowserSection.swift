import SwiftUI

/// 枢纽页电脑段（0.9.0 P2 转正为浏览器段；§493 扩容
/// 为完整电脑面）：本体 ComputerFaceView——状态头＋
/// 桌面（云电脑真实截图、可接管）/文件/终端三段。
/// 原本段只呈 BrowserFaceView 实时画面，文件/终端
/// 两段只住在设置「电脑」sheet 里；§493（D4 甲）整
/// 面并入本格当家、设置行退役，「电脑」全 App 只剩
/// 这一副面孔。原留口形态（系统空态＋9119 computer-
/// use 就绪行）早已随错位源退役（施工图 §4.3）。
struct HubBrowserSection: View {
    var body: some View {
        ComputerFaceView()
    }
}
