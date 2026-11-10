import Foundation

/// 待发文件接入预检（0.36.31 件三，诊断 file-picker-
/// batch-diagnosis-20261111 次节口径）：文件入条前
/// 的纯判定与文案拼装——先查大小（fileSize）再读数
/// 据，超限不整份读入；被拒文件汇总点名，不再逐个
/// 写 notice 互相覆盖、只剩最后一个名。网络与文件
/// 读取动作在 App 层，本枚举只管判定与拼装。
public enum FileIntake {
    /// App 侧单文件大小闸（字节）：与服务端托管上
    /// 传契约对齐（file-upload-contract-20261111：
    /// POST /api/files/upload 解码后上限 100 MiB）；
    /// 0.36.29 前为 20MB，选大文件（安装包级）必撞
    /// 闸、且旧链先整份读入才判，本轮改预检＋对齐
    public static let maxFileBytes = 100 * 1024 * 1024

    /// 大小预检判定：App 层先以 resourceValues 取
    /// fileSize 问本函数，`.tooLarge` 直接拒收免读；
    /// `.unknownSize`（取不到大小）放行读入、读后以
    /// `isOversized` 对实字节二次判，不许因查不到
    /// 大小就拒人
    public enum SizeVerdict: Equatable, Sendable {
        case acceptable
        case tooLarge
        case unknownSize
    }

    public static func sizeVerdict(declaredSize: Int?) -> SizeVerdict {
        guard let declaredSize else { return .unknownSize }
        return declaredSize > maxFileBytes ? .tooLarge : .acceptable
    }

    /// 实读字节的超限判（预检 `.unknownSize` 的兜底
    /// 二次判，与预检同闸值）
    public static func isOversized(byteCount: Int) -> Bool {
        byteCount > maxFileBytes
    }

    /// 被拒文件汇总点名：超限与读失败各成一句、都有
    /// 才并列；名单 1 个直名、2 个并列、3 个以上取
    /// 前两名＋「等 N 个文件」，不让用户对着一个名
    /// 子猜其余下落（对图片路计数汇总口径的补全：
    /// 文件路逐个点名更有用、但必须全员有账）。
    /// 两类皆空返回 nil（调用方不写 notice）
    public static func rejectionNotice(
        oversized: [String], unreadable: [String]
    ) -> String? {
        var sentences: [String] = []
        if !oversized.isEmpty {
            sentences.append(
                "\(namedList(oversized))超过 100MB，未加入待发列表。"
            )
        }
        if unreadable.count == 1 {
            sentences.append(
                "读取「\(unreadable[0])」失败，未加入待发列表。"
            )
        } else if !unreadable.isEmpty {
            sentences.append(
                "\(namedList(unreadable))没能读取，未加入待发列表。"
            )
        }
        guard !sentences.isEmpty else { return nil }
        return sentences.joined()
    }

    /// 名单拼装（「」逐名）：1 个直名、2 个并列、
    /// 3+ 取前两名＋总数收尾
    private static func namedList(_ names: [String]) -> String {
        switch names.count {
        case 0:
            return ""
        case 1:
            return "「\(names[0])」"
        case 2:
            return "「\(names[0])」、「\(names[1])」"
        default:
            return "「\(names[0])」、「\(names[1])」等 \(names.count) 个文件"
        }
    }
}
