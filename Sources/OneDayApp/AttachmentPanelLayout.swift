import OneDayCore
import SwiftUI

/// 附件面板内容高量测（§152 立、§154 热修）：面板
/// body 把自身高度经 PreferenceKey 报给宿主，宿主
/// 以此作 sheet 的 .height detent——sheet 高度贴
/// 内容（标题行＋照片条＋可选确认行＋动作行组），
/// 底部不留 .medium 的死空。
///
/// §154 纠正一处要命的旧假设：本文件初版注释写
/// 「sheet 呈现时取宿主全屏高」——错。sheet 内容
/// 里的 GeometryReader 量到的是 **detent 驱动的
/// sheet 自身高度**，不是屏高；宿主拿它当屏高做
/// 75% 钳顶，detent 每轮布局按 0.75 倍自噬塌陷，
/// 0.50.16 真机点「+」面板等于没出现。自此口径
/// 钉死两条：①钳顶用的屏高只许来自 sheet 之外
/// 的呈现方几何（ChatView 根层 onGeometryChange
/// 回写）；②决策纯函数收口 Core AttachmentPanel
/// .detentHeight（含量测可信下限：伪值一律回
/// nil、宿主回落 .medium 照常打开）。量测值本
/// 身取面板理想高（宿主给面板挂 fixedSize 保
/// 真），不随当前 detent 伸缩——回路无自激。
struct AttachmentPanelHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

enum AttachmentPanelLayout {
    /// 量得内容高 → detent 高：转发 Core 单源决策
    /// （§154；零/负/伪量测回落 nil＝宿主退回默认
    /// 档，正值按真屏高 75% 钳顶）
    static func detentHeight(
        measured: CGFloat, screenHeight: CGFloat
    ) -> CGFloat? {
        AttachmentPanel.detentHeight(
            measured: measured, screenHeight: screenHeight
        )
    }
}
