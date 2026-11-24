import Foundation

/// 附件面板拼装口径（§147，用户 2026-11-11 19:01 点题
/// 改版）：「＋」自浮窗小卡菜单改为 Muse 式底部附仴
/// 面板——「资源库」照片条＋动作行。照片条的数据洐
/// 拼装、相册授权政策、选图/选视颙的接入判定全在此/// 处纯函数化（PHAsset 读取与呈现动作在全层），
/// 选中后一律汇入现行附件管线（附件条筹码、上传链、
/// 发送拼装不动）＂§152 修订二在此续：照片条多选的
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

    /// 单张图片大小闸（字节）：图片走多模态册发
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

    /// 确认按钮文案（§152 立、§461 改文案）：未选
    /// 任何照片回 nil（确认按钮不呈现、动作不可用
    /// 同源）；有选时逐字点数，文案随 §461 目标图
    /// 作「添加 N 个附件」
    public static func addSelectedTitle(count: Int) -> String? {
        guard count > 0 else { return nil }
        return "添加 \(count) 个附件"
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

    // MARK: - 布局常量与定高（D5，台账 11）

    /// 布局常量单源（D5 收编）：面板内容形态值——照
    /// 片格边长、行高、标题行高。间距仍引用 OneDayMetrics
    /// （spacingM 16 / spacingSM 12），不另立
    public enum Layout {
        /// 照片格边长（§152 定版：照 Muse 近方形大格）
        public static let cellSize: CGFloat = 118
        /// 行高（动作行用）
        public static let rowHeight: CGFloat = 52
        /// 确认按钮高（§461：确认动作改底部整宽大
        /// 按钮，独立于动作行高定版）
        public static let confirmButtonHeight: CGFloat = 56
        /// 资源库标题行高（.headline 字体实测约值）
        public static let titleRowHeight: CGFloat = 22
    }

    /// 贴合档理想高度纯算（D5 立）：按与内容同一组常
    /// 量算内容理想高——无状态、无量
    /// 测、无回调。装配测试逐值对账防漂移
    ///
    /// - Parameters:
    ///   - showsLibrary: 资源库区是否呈现（授权相关）
    ///   - hasSelection: 是否有照片选中（确认行是否在场）
    ///
    /// SwiftUI `.height()` detent 参数是 detent 解析高度
    /// （相当于 sheetHeight - safeAreaInsets.bottom），
    /// 系统会自动加上安全区得到实际帧高，故此函数只返回
    /// 纯内容高，不包含安全区。
    ///
    /// - Returns: detent 高度（纯内容高，系统自动加安全区）
    public static func fittedSheetHeight(
        showsLibrary: Bool,
        hasSelection: Bool
    ) -> CGFloat {
        // 上下 padding：各 spacingM(16)
        let verticalPadding: CGFloat = 16 * 2
        
        // 资源库区：标题行 + spacingSM(12) + 照片格
        let libraryHeight: CGFloat = showsLibrary 
            ? (Layout.titleRowHeight + 12 + Layout.cellSize) 
            : 0
        
        // 确认按钮（§461：有选时在场，底部整宽大按钮）
        let confirmHeight: CGFloat = hasSelection
            ? Layout.confirmButtonHeight : 0
        
        // 动作行：两行 + Divider(~1)
        let actionHeight: CGFloat = Layout.rowHeight * 2 + 1
        
        // 区段间 spacingM(16) 计数：
        // - 有库未选：library + 16 + action
        // - 有库已选：library + 16 + confirm + 16 + action
        // - 无库态：action（padding 已含，无额外间距）
        var spacingCount = 0
        if showsLibrary {
            spacingCount += 1  // library 与下方间距
            if hasSelection {
                spacingCount += 1  // confirm 与 action 间距
            }
        }
        let interSpacing: CGFloat = CGFloat(spacingCount) * 16
        
        let contentHeight = verticalPadding + libraryHeight + confirmHeight + actionHeight + interSpacing
        
        return contentHeight
    }

    // MARK: - 定高注释续（D5 修订条）

    // §152/§154 的定高决策（detentHeight＋可信下限
    // ＋75% 钳顶）已随 A-08 收口整节退役：面板高度
    // 先改由系统 fitted 尺寸按内容理想尺寸单源决定
    // （§303 custom detent），§327 再退役精确贴合、
    // 改系统 detent 档位 [.medium, .large]（App 层
    // attachmentPanelPresentation），Core 不再参与
    // 定高、不留任何量测判据。
    //
    // D5（台账 11）修订：定高条以常量纯算有限回归——
    // fittedSheetHeight 按与内容同一组 Layout 常量
    // 纯函数算出三态理想高（137/305/373＋safeArea），
    // App 层配成系统 .height() 贴合档；与 §303 量测
    // 回路的区别：无 PreferenceKey、无宿主状态、无
    // 指纹 invalidate。§327 退役清单（custom detent
    // resolver 桥、安全区反向补偿、指纹、§317 过渡
    // 守卫）仍不得复活
}
