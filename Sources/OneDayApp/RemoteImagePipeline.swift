import ImageIO
import OneDayCore
import UIKit

/// 远程图统一管线（§138，§33 规格 §5）：全仓远端图只许
/// 走这一条路——三级缓存（内存已解码图 NSCache／磁盘
/// 变体字节／网络变体端点），同键请求合并，解码一律
/// ImageIO 降采样（禁远端图 UIImage(data:) 全尺寸直
/// 解）。原图只在查看器放大越界或显式动作时才下。
/// 消费面：聊天图卡（ServerRemoteImage）、查看器
/// （ImageViewerPage）、文件/影音缩略（FileThumbnail-
/// Store 生成后经 storeMemory 播种同键——影音格点开
/// 查看器时种子即在此，首帧有图）。
/// 取数通道由调用方注入（与 FileThumbnailStore 的
/// loader 口径一致）：变体走 OneDayBridgeClient（桥
/// 钥在客户端内读）、原图走宿主 performAdmin 的
/// Hermes 文件下载。
@MainActor
final class RemoteImagePipeline {
    static let shared = RemoteImagePipeline()

    private let memory = NSCache<NSString, UIImage>()
    private var inFlight: [String: Task<UIImage?, Never>] = [:]
    private var prefetchTasks: [String: Task<UIImage?, Never>] = [:]
    private let bridgeClient = OneDayBridgeClient()

    /// 磁盘缓存上限（§33 规格 §5.2：约 512MB，LRU 淘汰）
    private static let diskLimitBytes = 512 * 1024 * 1024

    private init() {
        memory.totalCostLimit = 256 * 1024 * 1024
        memory.countLimit = 300
    }

    // MARK: - 内存层

    func memoryImage(
        path: String, mtime: Double, tier: ImageRenditionTier
    ) -> UIImage? {
        memory.object(
            forKey: RemoteImageKey.make(
                path: path, mtime: mtime, tier: tier) as NSString)
    }

    func storeMemory(
        _ image: UIImage, path: String, mtime: Double,
        tier: ImageRenditionTier
    ) {
        let pixelWidth = Int(image.size.width * image.scale)
        let pixelHeight = Int(image.size.height * image.scale)
        memory.setObject(
            image,
            forKey: RemoteImageKey.make(
                path: path, mtime: mtime, tier: tier) as NSString,
            cost: max(pixelWidth * pixelHeight * 4, 0))
    }

    /// 查看器种子：已到手的图里从高到低找（影音格 360、
    /// 气泡已显图都在内存层）；内存没有再探磁盘 360 档
    /// （解码快、够当首帧）。种子命中＝查看器第一帧有图
    func seedImage(path: String, mtime: Double) -> UIImage? {
        for tier in [ImageRenditionTier.detail, .viewer, .thumb] {
            if let image = memoryImage(
                path: path, mtime: mtime, tier: tier) {
                return image
            }
        }
        if let data = diskData(path: path, mtime: mtime, tier: .thumb),
           let image = Self.downsampled(
               data: data, pixelSize: CGFloat(ImageRenditionTier.thumb.longEdge)) {
            storeMemory(image, path: path, mtime: mtime, tier: .thumb)
            return image
        }
        return nil
    }

    // MARK: - 取图主口

    /// 取某档图：内存→磁盘→网络（变体优先、回落原图降
    /// 采样）。同键并发请求合并为一笔（首位调用方的取数
    /// 通道为准）。共享请求不随单个视图消失而取消——多
    /// 消费者合并的取舍，结果落缓存供后来者（§138 记账）
    func image(
        path: String, mtime: Double, tier: ImageRenditionTier,
        config: ServerConfig?,
        originalLoader: @escaping () async -> Data?
    ) async -> UIImage? {
        if let cached = memoryImage(
            path: path, mtime: mtime, tier: tier) {
            return cached
        }
        let key = RemoteImageKey.make(
            path: path, mtime: mtime, tier: tier)
        if let task = inFlight[key] {
            return await task.value
        }
        let task = Task { @MainActor in
            await self.fetch(
                path: path, mtime: mtime, tier: tier,
                config: config, originalLoader: originalLoader)
        }
        inFlight[key] = task
        let result = await task.value
        inFlight[key] = nil
        return result
    }

    /// 预取：低优先、只填缓存不回图；已在内存/磁盘的跳
    /// 过。与锚点无关的预取可经 cancelPrefetches 批量撤
    /// （快滑时未发出的预取不许继续抢带宽）
    func prefetch(
        path: String, mtime: Double, tier: ImageRenditionTier,
        config: ServerConfig?,
        originalLoader: @escaping () async -> Data?
    ) {
        let key = RemoteImageKey.make(
            path: path, mtime: mtime, tier: tier)
        guard memoryImage(path: path, mtime: mtime, tier: tier) == nil,
              diskData(path: path, mtime: mtime, tier: tier) == nil,
              inFlight[key] == nil, prefetchTasks[key] == nil
        else { return }
        let task = Task(priority: .utility) { @MainActor in
            await self.fetch(
                path: path, mtime: mtime, tier: tier,
                config: config, originalLoader: originalLoader)
        }
        prefetchTasks[key] = task
        Task { @MainActor in
            _ = await task.value
            self.prefetchTasks[key] = nil
        }
    }

    func cancelPrefetches(except keepKeys: Set<String> = []) {
        for (key, task) in prefetchTasks where !keepKeys.contains(key) {
            task.cancel()
            prefetchTasks[key] = nil
        }
    }

    // MARK: - 取数实现

    private func fetch(
        path: String, mtime: Double, tier: ImageRenditionTier,
        config: ServerConfig?,
        originalLoader: () async -> Data?
    ) async -> UIImage? {
        // 磁盘层（变体字节，解码降采样到档位）
        if let data = diskData(path: path, mtime: mtime, tier: tier) {
            let pixelCap = tier == .original
                ? 4096 : CGFloat(tier.longEdge)
            if let image = Self.downsampled(
                data: data, pixelSize: pixelCap) {
                storeMemory(
                    image, path: path, mtime: mtime, tier: tier)
                return image
            }
        }
        // 网络层：变体优先
        if tier != .original, let width = tier.renditionWidth,
           let config,
           let data = try? await bridgeClient.rendition(
               config: config, path: path, width: width),
           let image = Self.downsampled(
               data: data, pixelSize: CGFloat(tier.longEdge)) {
            storeDisk(data, path: path, mtime: mtime, tier: tier)
            storeMemory(image, path: path, mtime: mtime, tier: tier)
            return image
        }
        // 回落原图通道：降采样到档位（原图档封顶 4096px，
        // 与查看器放大上限同量级）；落盘存降采样后的
        // JPEG，不把原图大字节塞进变体缓存层
        guard let data = await originalLoader() else { return nil }
        let pixelCap = tier == .original
            ? 4096 : CGFloat(tier.longEdge)
        guard let image = Self.downsampled(
            data: data, pixelSize: pixelCap) else { return nil }
        if tier == .original {
            storeDisk(data, path: path, mtime: mtime, tier: tier)
        } else if let jpeg = image.jpegData(compressionQuality: 0.85) {
            storeDisk(jpeg, path: path, mtime: mtime, tier: tier)
        }
        storeMemory(image, path: path, mtime: mtime, tier: tier)
        return image
    }

    /// ImageIO 降采样：只解到目标像素量级，不整图入内存
    /// （与 FileThumbnailStore 同法）
    static func downsampled(
        data: Data, pixelSize: CGFloat
    ) -> UIImage? {
        let sourceOptions: [CFString: Any] = [
            kCGImageSourceShouldCache: false,
        ]
        guard let source = CGImageSourceCreateWithData(
            data as CFData, sourceOptions as CFDictionary
        ) else { return nil }
        let thumbOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: pixelSize,
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(
            source, 0, thumbOptions as CFDictionary
        ) else { return nil }
        return UIImage(cgImage: cgImage)
    }

    // MARK: - 磁盘层（Caches/RemoteImages，LRU 512MB）

    private var diskDirectory: URL? {
        guard let caches = FileManager.default.urls(
            for: .cachesDirectory, in: .userDomainMask
        ).first else { return nil }
        let directory = caches.appendingPathComponent(
            "RemoteImages", isDirectory: true)
        try? FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func diskURL(
        path: String, mtime: Double, tier: ImageRenditionTier
    ) -> URL? {
        diskDirectory?.appendingPathComponent(
            RemoteImageKey.make(path: path, mtime: mtime, tier: tier)
                + ".jpg")
    }

    private func diskData(
        path: String, mtime: Double, tier: ImageRenditionTier
    ) -> Data? {
        guard let url = diskURL(path: path, mtime: mtime, tier: tier)
        else { return nil }
        return try? Data(contentsOf: url)
    }

    private func storeDisk(
        _ data: Data, path: String, mtime: Double,
        tier: ImageRenditionTier
    ) {
        guard let url = diskURL(path: path, mtime: mtime, tier: tier)
        else { return }
        try? data.write(to: url)
        pruneDisk()
    }

    /// 超限按文件修改时间从老到新淘汰（LRU 近似）
    private func pruneDisk() {
        guard let directory = diskDirectory,
              let items = try? FileManager.default
                .contentsOfDirectory(
                    at: directory,
                    includingPropertiesForKeys: [
                        .fileSizeKey, .contentModificationDateKey,
                    ])
        else { return }
        var total = 0
        var sized: [(url: URL, size: Int, date: Date)] = []
        for item in items {
            let values = try? item.resourceValues(
                forKeys: [.fileSizeKey, .contentModificationDateKey])
            let size = values?.fileSize ?? 0
            total += size
            sized.append((
                item, size,
                values?.contentModificationDate ?? .distantPast))
        }
        guard total > Self.diskLimitBytes else { return }
        for entry in sized.sorted(by: { $0.date < $1.date }) {
            if total <= Self.diskLimitBytes { break }
            try? FileManager.default.removeItem(at: entry.url)
            total -= entry.size
        }
    }
}
