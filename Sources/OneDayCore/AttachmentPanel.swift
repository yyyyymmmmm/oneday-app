import Foundation

/// 附件面板拼装口径（§147，用户 2026-11-11 19:01 点题
/// 改版）：「+」自浮窗小卡菜单改为 Muse 式底部附件
/// 面板——「资源库」照片条＋动作行。照片条的数据源
/// 拼装、相册授权政策、选图/选视频的接入判定全在此
/// 处纯函数化（PHAsset 读取与呈现动作在 App 层），
/// 选中后一律汇入现行附件管线（附件条筹码、上传链、
/// 发送拼装不动）。§152 修订二在此续：照片条多选的
/// 切换/排序/确认文案纯函数（选中态本体在 App 层）。
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

    // MARK: - 照片条多选（§152 修订二）

    /// 照片条点选切换：已选再点取消、未选点之加入；
    /// 返回新选中集（相对入参的增删单点由调用方按集
    /// 合差自明）。顺序由 orderedSelection 另行收口，
    /// 本函数只管成员关系
    public static func toggledSelection(
        _ selected: Set<String>, id: String
    ) -> Set<String> {
        var next = selected
        if next.contains(id) {
            next.remove(id)
        } else {
            next.insert(id)
        }
        return next
    }

    /// 批量入条顺序：按照片条呈现序（新→旧，与条内
    /// 位置一致）过滤出选中者——入附件条的顺序与用
    /// 户在条里看到的从左到右一致，不按点选先后（点
    /// 选序无处回看、呈现序是唯一可预期序）
    public static func orderedSelection(
        selected: Set<String>, stripOrder: [String]
    ) -> [String] {
        stripOrder.filter { selected.contains($0) }
    }

    /// 「添加 N 张」确认行文案：未选任何照片回 nil
    /// （确认行不呈现、动作不可用同源）；有选时逐字
    /// 点数
    public static func addSelectedTitle(count: Int) -> String? {
        guard count > 0 else { return nil }
        return "添加 \(count) 张"
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

    // MARK: - 定高决策（§154 热修收口）

    /// detent 钳顶占屏比：内容再高也不许把 sheet
    /// 撑过宿主高度的四分之三
    public static let detentMaxScreenFraction: CGFloat = 0.75

    /// 量测可信下限（pt）：面板最矮形态（无资源库
    /// 区、无确认行）的内容高是上下内边距 32＋动作
    /// 行两行 104＝136，低于 120 的「内容高」不可能是
    /// 真量测——只能是量测链坏掉时的伪值（见
    /// detentHeight 的热修记账），一律按量测失败处
    /// 理、回落默认档
    public static let detentMinimumPlausibleHeight: CGFloat = 120

    /// 量得内容高 → detent 高（§152 立、§154 热修）：
    /// 零/负/低于可信下限的量测与无效屏高一律回
    /// nil——宿主据此回落 .medium，面板照常打开，
    /// 绝不许拿伪值当 detent 把 sheet 压没；有效
    /// 量测按屏高比例钳顶后原样返回。
    ///
    /// §154 定因（0.50.16 真机「+」点开无反应）：
    /// 本函数的 screenHeight 必须是**宿主真高**
    /// （呈现方整页几何）——§152 施工时误把 sheet
    /// 内容里的 GeometryReader 所量当作屏高，那量
    /// 到的其实是 detent 驱动的 sheet 自身高度 s：
    /// detent＝min(量测, 0.75·s) 每过一轮布局至多
    /// 剩 0.75 倍，几何衰减塌到近零，sheet 等于没
    /// 出现。入参口径自此钉死：screenHeight 只许
    /// 来自 sheet 之外的呈现方几何；量测本身须取
    /// 内容理想高（App 层 fixedSize 保真），与当
    /// 前 detent 无关——本函数对同一 (measured,
    /// screenHeight) 恒回同值，是不动点，宿主回路
    /// 不再自激。
    public static func detentHeight(
        measured: CGFloat, screenHeight: CGFloat
    ) -> CGFloat? {
        guard screenHeight > 0,
              measured >= detentMinimumPlausibleHeight
        else { return nil }
        return min(measured, screenHeight * detentMaxScreenFraction)
    }
}
