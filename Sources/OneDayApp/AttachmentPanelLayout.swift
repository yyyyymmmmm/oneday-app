import SwiftUI

/// 附件面板内容高量测（§150 修订二）：面板 body 把自
/// 身高度经 PreferenceKey 报给宿主，宿主以此作 sheet
/// 的 .height detent——sheet 高度贴内容（标题行＋照
/// 片条＋可选确认行＋动作行组），底部不留 .medium 的
/// 死空。量测值钳制一档：内容异常时也不许把 sheet
/// 撑过屏幕大部（上限 75% 屏高，本机量高——sheet 呈
/// 现时取宿主全屏高，与几何教训 P-13「量测层与定尺
/// 层须同一层」同戒：detent 高就是内容高本身，不做
/// 二次推算）。
struct AttachmentPanelHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

enum AttachmentPanelLayout {
    /// 量得内容高 → detent 高：零/负值回落 nil（宿主
    /// 退回默认档）；正值按屏高比例钳顶
    static func detentHeight(
        measured: CGFloat, screenHeight: CGFloat
    ) -> CGFloat? {
        guard measured > 0, screenHeight > 0 else { return nil }
        return min(measured, screenHeight * 0.75)
    }
}
