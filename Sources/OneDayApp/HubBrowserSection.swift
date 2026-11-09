import SwiftUI

/// 枢纽页浏览器段（0.9.0 P2 转正）：与应用格「浏览器」
/// 页共用同一面 BrowserFaceView——状态读盒桥、画面是
/// 云电脑真实截图、可接管。原留口形态（系统空态＋
/// 9119 computer-use 就绪行）随错位源一并退役：
/// computer-use 是本机桌面自动化状态，与 Box 浏览器
/// 能力无关，继续读它状态行永远是错的（施工图 §4.3）。
struct HubBrowserSection: View {
    var body: some View {
        BrowserFaceView()
    }
}
