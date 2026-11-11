import Foundation

/// 远程图片档位（§138，§33 规格 §5.1/§7）：缩略 360／查看
/// 1080／细节 2048／原图。声明序即档位序，查看器递进链
/// 「只升不降」靠它判定。seed 不是网络档位，是入口已到手
/// 的小图（影音格内 360 档、聊天气泡已显图）占的位——
/// 它的存在让查看器第一帧永远有图，不许白屏。
public enum ImageRenditionTier: Int, CaseIterable, Sendable, Comparable {
    case seed
    case thumb
    case viewer
    case detail
    case original

    /// 该档长边像素上限（seed 无网络尺寸、original 不设限）
    public var longEdge: Int {
        switch self {
        case .seed: return 0
        case .thumb: return 360
        case .viewer: return 1080
        case .detail: return 2048
        case .original: return Int.max
        }
    }

    /// 变体端点的 w 参数（只有三个网络档位有）
    public var renditionWidth: Int? {
        switch self {
        case .thumb: return 360
        case .viewer: return 1080
        case .detail: return 2048
        case .seed, .original: return nil
        }
    }

    public static func < (
        lhs: ImageRenditionTier, rhs: ImageRenditionTier
    ) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// 远程图缓存键（§138）：path 的 FNV-1a 哈希＋mtime＋档位。
/// 文件变了（mtime 变）键即变，旧字节不会被新内容命中；
/// 聊天图拿不到 mtime 时以 0 占位——聊天图以截图/上传的
/// 一次性文件为主、写一次读多次，可接受（§138 记账）。
public enum RemoteImageKey {
    public static func make(
        path: String, mtime: Double, tier: ImageRenditionTier
    ) -> String {
        "\(stableHash(path))-\(Int(mtime))-\(tier.rawValue)"
    }

    /// FNV-1a 稳定哈希（与 FileThumbnailStore 同算法，跨
    /// 启动不变，磁盘缓存键用）
    public static func stableHash(_ string: String) -> UInt64 {
        var hash: UInt64 = 1469598103934665603
        for byte in string.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1099511628211
        }
        return hash
    }
}

/// 查看器加载状态机（§138）：纯值型，宿主（ImageViewer-
/// Page）只按它呈现，不自拼状态。规则钉死：
/// - 已显示档位只升不降（低档迟到不许把高清图换回糊图）；
/// - 某档失败时，有图在显只记 degraded、不毁图、不弹
///   失败态；无图才进 failed（失败态必须带重试）；
/// - 种子先到即显——任何入口都不许出现「无图＋转圈」
///   作第一帧以外的常态；真冷开的首帧窗口由宿主按时
///   间门（300ms）决定菊花出不出，状态机不管时间。
public struct ViewerImageProgression: Equatable, Sendable {
    public enum Phase: Equatable, Sendable {
        /// 还没有任何图（真冷开）
        case empty
        /// 有图在显（displayedTier 有效）
        case showing
        /// 无图且加载失败——失败态，有重试
        case failed
    }

    public private(set) var displayedTier: ImageRenditionTier?
    public private(set) var phase: Phase = .empty
    /// 有图在显但更高档拿不到（保持现图，不打扰用户）
    public private(set) var degraded = false
    /// 已重试次数（真机排障与防死循环记账）
    public private(set) var attempt = 0

    public init() {}

    public var hasImage: Bool { displayedTier != nil }

    /// 种子图带入：只在无图时接管显示（已有更高档不许被
    /// 种子顶掉——种子永远是最低档）
    public mutating func seedArrived() {
        guard displayedTier == nil else { return }
        displayedTier = .seed
        phase = .showing
    }

    /// 某档图到达：高于现显示才换；等档/低档迟到不换。
    /// 换上更高档即清 degraded（缺的档补回来了）
    public mutating func tierArrived(_ tier: ImageRenditionTier) {
        if let current = displayedTier, tier <= current { return }
        displayedTier = tier
        phase = .showing
        degraded = false
    }

    /// 某档加载失败：无图→failed；有图→保持显示＋degraded
    public mutating func tierFailed() {
        if displayedTier == nil {
            phase = .failed
        } else {
            degraded = true
        }
    }

    /// 重试：仅 failed 态有效，清回 empty 并计 attempt；
    /// 其余状态返回 false（宿主不许在有图时乱重置）
    @discardableResult
    public mutating func retry() -> Bool {
        guard phase == .failed else { return false }
        phase = .empty
        degraded = false
        attempt += 1
        return true
    }

    /// 切页/换图复位
    public mutating func reset() {
        self = ViewerImageProgression()
    }
}
