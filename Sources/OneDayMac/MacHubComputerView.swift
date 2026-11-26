import SwiftUI
import OneDayCore

/// 电脑面（棒 4，对位 #41）：电脑操控状态＋出口状
/// 态两段状态呈现（与 iOS 电脑面同源两口）；桌面/
/// 文件/终端的操控动作在 iOS 走盒桥交互面，Mac 本
/// 棒只落状态总览，操控面归后续（见销账段明示）
struct MacHubComputerView: View {
    let store: MacHubStore

    var body: some View {
        HubScroll {
            HubSectionHeader(title: "电脑操控状态")
            if let status = store.computerStatus {
                HubJSONSummaryView(value: status)
            } else {
                HubEmptyText(text: "电脑状态暂不可用。")
            }
            HubSectionHeader(title: "出口状态")
            if let egress = store.egressStatus {
                HubJSONSummaryView(value: egress)
            } else {
                HubEmptyText(text: "出口状态暂不可用。")
            }
        }
    }
}
