import Foundation

/// 已发送图片显示尺寸（0.36.19，§84.5）：等比缩进
/// 「宽高双封」盒——旧口径只封宽（frame(maxWidth:
/// 220) 不封高），竖长手机截图（宽高比约 1:2.17）
/// 220pt 宽要长到约 477pt 高，一张图吃掉半屏还多；
/// Muse 是宽高双封（fit-in-box），同图明显小一圈。
/// 本函数是三处已发图渲染的唯一尺寸口径：用户本地
/// 图（ChatView.bubble）、远端图（ServerRemoteImage，
/// 用户与助手两侧共用一处）。
///
/// 口径：
/// - 入参/出参同为 pt：调用方传 UIImage.size（已
///   是 pt），不许传像素尺寸——只缩不放大的判定建
///   立在同口径比较上
/// - 只缩不放大：原图小于盒时按原尺寸显示
/// - 非正尺寸（宽或高 ≤0）原样返回：坏数据防御，
///   尺寸判定不替渲染层拿主意
/// - 全屏查看器不走本函数（看原图是它的职责）
public enum ChatImageSizing {
    /// 显示盒宽（沿旧口径 220，用户已习惯的横图宽）
    public static let maxWidth: CGFloat = 220
    /// 显示盒高（本包新增的封顶：竖图到此为止）
    public static let maxHeight: CGFloat = 240

    /// 等比缩进盒内的显示尺寸（pt）
    public static func displaySize(for imageSize: CGSize) -> CGSize {
        guard imageSize.width > 0, imageSize.height > 0 else {
            return imageSize
        }
        let scale = min(
            maxWidth / imageSize.width,
            maxHeight / imageSize.height,
            1
        )
        return CGSize(
            width: imageSize.width * scale,
            height: imageSize.height * scale
        )
    }
}
