import Foundation

/// 附件面板拼装口径（§146，用户 2026-11-11 19:01 点题
/// 改版）：「+」自浮窗小卡菜单改为 Muse 式底部附件
/// 面板——「资源库」照片条＋动作行。照片条的数据源
/// 拼装、相册授权政策、选图/选视频的接入判定全在此
/// 处纯函数化（PHAsset 读取与呈现动作在 App 层），
/// 选中后一律汇入现行附件管线（附件条筹码、上传链、
/// 发送拼装不动）。
public enum AttachmentPanel {

    // MARK: - 相册授权政策

    /// 相册授权态（App 层自 PHPhotoLibrary 同步读得
    /// 后映射进来）：面板只读现态、绝不发请求——面板
    /// 不是一套新的授权流（系统授权铁律）；未决定与
    /// 已拒绝同等对待：资源库区不显，动作行（选图器
    /// 由系统代管、不需本 App 授权）照常可用
    public enum PhotoAccess: Equatable, Sendable {
        case authorized
        case limited
        case denied
        case notDetermined
        case restricted
    }

    /// 资源库区（标题行＋照片条）是否呈现：只有已授
    /// 权（含有限授权）才显；有限授权下 App 层
    /// PHAsset 取数天然只回已授权子集，不另做过滤
    public static func showsLibrary(access: PhotoAccess) -> Bool {
        switch access {
        case .authorized, .limited:
            return true
        case .denied, .notDetermined, .restricted:
            return false
        }
    }

    // MARK: - 照片条拼装

    /// 照片条一格：相机格恒居首（点它直接开相机），
    /// 其后是最近照片（App 层按创建时间倒序取 id）
    public enum StripCell: Equatable, Hashable, Sendable {
        case camera
        case photo(id: String)
    }

    /// 照片条照片上限（横滑条一屏外靠滑动，不整本
    /// 相册搬进面板；全量走「查看全部」选图器）
    public static let stripPhotoLimit = 30

    /// 拼装照片条：相机格恒首位、照片按入参序（新→
    /// 旧）跟随、重复 id 只留首现、总数按上限截断
    public static func stripCells(
        photoIDs: [String], limit: Int = stripPhotoLimit
    ) -> [StripCell] {
        var seen = Set<String>()
        var cells: [StripCell] = [.camera]
        for id in photoIDs {
            guard cells.count - 1 < limit else { break }
            guard seen.insert(id).inserted else { continue }
            cells.append(.photo(id: id))
        }
        return cells
    }

    // MARK: - 图片接入判定（选图器与照片条共用）

    /// 单张图片大小闸（字节）：图片走多模态内嵌发
    /// 送、不经文件上传契约，故闸独立于 FileIntake
    /// 的 100MiB（0.36.23 立、0.36.31 文件闸抬升时
    /// 明示不牵动本闸）；自 ChatView 内联常量收编至
    /// 此，两条取图路（选图器/照片条点选）共用一闸
    public static let maxPhotoBytes = 20 * 1024 * 1024

    public static func photoFits(byteCount: Int) -> Bool {
        byteCount <= maxPhotoBytes
    }

    /// 超限汇总文案（与旧选图器路径逐字一致）：0 张
    /// 不出声（P-18 有声口径管的是有事才报）
    public static func oversizedPhotosNotice(count: Int) -> String? {
        guard count > 0 else { return nil }
        return "有 \(count) 张图片超过 20MB，未加入待发列表。"
    }

    /// 读取失败汇总文案：取图失败（iCloud 未下载等）
    /// 不许静默吞（P-18 所有出口有声）
    public static func failedPhotosNotice(count: Int) -> String? {
        guard count > 0 else { return nil }
        return "有 \(count) 张图片读取失败，未加入待发列表。"
    }

    // MARK: - 视频接入命名

    /// 选视频入条文件名：PhotosUI 载荷不带原名，以
    /// 「视频」为名＋系统给的首选扩展名（清洗后只留
    /// 字母数字、转小写）；无可用扩展名回落 mov
    public static func videoFileName(preferredExtension: String?) -> String {
        let cleaned = (preferredExtension ?? "")
            .lowercased()
            .filter { $0.isLetter || $0.isNumber }
        return "视频.\(cleaned.isEmpty ? "mov" : cleaned)"
    }
}
