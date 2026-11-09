import Foundation

/// 交付物准入（0.22.0，视觉审计 F1 策展规格）：文件格
/// 聚合面（DeliverablesView.collect）的准入纯函数——
/// 0.20.0 的旧口径是「产出根全收＋根散文件 deny 8 名」，
/// Hermes 的状态/缓存文件（state.db-wal、kanban.db-shm、
/// models_dev_cache.etag…）不在 deny 名单内、又因 mtime
/// 恒新而霸占倒序首屏（2026-11-10 00:12 用户实机图首屏
/// 9 行全是内脏）。黑名单永远追不上新长出来的内部文件，
/// 本版按审计四层规格改白名单思维：
/// 1. 产出根收紧在宿主侧（十根→七根，见 DeliverablesView
///    .outputRoots），本函数不管根的选择；
/// 2. **根目录散文件改扩展名白名单准入**：扩展名不在交
///    付扩展集内一律拒（json 等数据管道文件就此出局）；
/// 3. **内部名形态拦截（全来源生效）**：内部后缀形态、
///    内部主干名、隐藏文件，命中任一即拒——不逐个追名字，
///    按形态一网打尽已知内脏及其变体；
/// 4. 验收样本：00:12 图 9 个污染文件名作单测拒收样本
///    钉死（DeliverableAdmissionTests）。
/// 宿主的旧 deny 名单保留作第二道（在白名单之外再挡一
/// 层人格/配置文件，本函数不替代它）。
public enum DeliverableAdmission {
    /// 交付扩展集（小写）：根目录散文件只有扩展名在此
    /// 集内才准入——「用户让做的东西」的成品形态（文档/
    /// 表格/演示/图片/音视频/压缩包/电子书）
    public static let rootDeliverableExtensions: Set<String> = [
        "pdf", "doc", "docx", "xls", "xlsx", "ppt", "pptx",
        "pages", "numbers", "key", "md", "txt", "rtf",
        "html", "htm", "csv", "zip", "7z", "tar", "gz", "epub",
        "png", "jpg", "jpeg", "gif", "webp", "heic",
        "mp4", "mov", "m4v", "mp3", "wav", "m4a", "aac",
    ]

    /// 内部后缀形态（小写、带点）：数据库本体与伴生文
    /// 件、缓存指纹、锁/进程/临时文件——全来源命中即拒
    public static let internalSuffixes: [String] = [
        ".db", ".db-wal", ".db-shm", ".sqlite", ".sqlite3",
        ".etag", ".lock", ".pid", ".tmp",
    ]

    /// 内部主干名（去末扩展名后的小写主干）：Hermes 的
    /// 状态/网关/频道/模型缓存/看板/会话/鉴权/配置主干，
    /// 命中即拒（覆盖 state.db、gateway_state.json、
    /// models_dev_cache.* 等已知内脏及后续变体）
    public static let internalStems: Set<String> = [
        "state", "gateway_state", "channel_directory",
        "models_dev_cache", "kanban", "sessions", "auth", "config",
    ]

    /// 准入判定：name 为文件名（非路径）；isRootLooseFile
    /// ＝来自工作区根目录的散文件（适用第二层白名单），
    /// 产出根内的文件传 false（只过形态拦截——产出根本
    /// 身已是策展过的来源）
    public static func isAdmitted(
        name: String, isRootLooseFile: Bool
    ) -> Bool {
        let lower = name.lowercased()
        // 隐藏文件全拒（0.20.0 前只在根目录拒，本版扩到
        // 全来源，规格三后段）
        if lower.hasPrefix(".") { return false }
        // 内部后缀形态拦截（全来源）
        for suffix in internalSuffixes where lower.hasSuffix(suffix) {
            return false
        }
        // 内部主干拦截（全来源）
        let stem = (lower as NSString).deletingPathExtension
        if internalStems.contains(stem) { return false }
        // 根散文件扩展名白名单
        if isRootLooseFile {
            let ext = (lower as NSString).pathExtension
            return rootDeliverableExtensions.contains(ext)
        }
        return true
    }
}
