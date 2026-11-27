import ImageIO
import Nuke
import OneDayCore
import OneDayDesign
import QuickLookThumbnailing
import SwiftUI
import UIKit

/// 文件页缩略图（0.36.31，文件页 v2 规格 §4.3 一期策
/// 略；§144 二期收口——服务端变体端点已上线）：
/// - 图片：先走伴生变体端点 360 档（几十 KB），拿
///   不到才回落原字节经 ImageIO 降采样解码（禁全
///   尺寸解码，影音格 0.36.4 前的全量解码病已销）；
/// - 视频：伴生海报帧（ffmpeg 首帧）当缩略源（§144
///   新增）；拿不到回落类型面——整段下载抽帧仍不做；
/// - 音频：不生成（类型面回落）；
/// - PDF/Office/HTML/文本：落临时文件走系统 QLThumb-
///   nailGenerator 取首面（系统对这些类型有缩略提供
///   者）；取不到回落类型面（FileTypeFace），不留白；
/// - 缓存：内存 NSCache＋磁盘（Caches/FileThumbs），
///   键含 path＋mtime＋目标像素——文件变了自动失效；
///   图片缩略生成后同键播种 RemoteImagePipeline，
///   供查看器首帧种子（点开即显的来源）；
/// - 并发闸 2：滚动时不让缩略生成把带宽与解码打满。
/// §410：缩略图解码产物跨任务装箱（UIImage 非
/// Sendable，照 RemoteImagePipeline.DecodedImageBox
/// 同式：单写单读、无并发触碰）
private final class ThumbImageBox: @unchecked Sendable {
    let image: UIImage
    init(_ image: UIImage) { self.image = image }
}

/// §418 接缝收编：图片变体与视频海报的取数改走统一
/// 构造器＋Nuke 管线（按路由键登记本笔通道，loader 内
/// 变体优先／原图回落），不再自拼桥调用；生成后播种
/// 改投管线内存缓存（经 RemoteImagePipeline 门面）。
/// 本体（生成器：QL 首面/并发闸/自有双缓存）保留。
@MainActor
/// §416 新鲜度普查豁免：本地缩略图缓存件，无远端新鲜度问题（判定表见 DESIGN §416）
final class FileThumbnailStore {
    static let shared = FileThumbnailStore()

    private let memoryCache = NSCache<NSString, UIImage>()
    private let gate = ThumbnailGate()

    private init() {
        memoryCache.countLimit = 120
    }

    /// 同步 peek（§329 行高合成用）：该条目该档
    /// 缩略图是否已在内存或磁盘缓存——只查在席、
    /// 不生成不取数；合成器据此判交付文件卡的封
    /// 面形态（缓存命中＝视图 .task 即时得图）
    func hasCachedThumbnail(
        for entry: WorkspaceFileEntry,
        targetPixelSize: CGFloat
    ) -> Bool {
        if entry.mediaKind == .audio { return false }
        let key = cacheKey(
            for: entry, pixel: Int(targetPixelSize)
        )
        if memoryCache.object(forKey: key as NSString)
            != nil {
            return true
        }
        guard let url = diskDirectory?
            .appendingPathComponent("\(key).png")
        else { return false }
        return FileManager.default.fileExists(
            atPath: url.path
        )
    }

    /// 取字节通道组（§144）：原图走宿主 performAdmin
    /// 文件下载、变体走桥 rendition 端点（Bearer 经
    /// BridgeCredential 统一读，宽度固定 360 档）——FileThumbnailView／
    /// 文件卡／影音预取三处同源，不各拼一份
    static func originalLoader(
        appState: AppState, path: String
    ) -> () async -> Data? {
        {
            try? await appState.performAdmin { client, config in
                try await client.fileData(
                    config: config, path: path)
            }
        }
    }

    private static let bridgeClient = OneDayBridgeClient()

    static func renditionLoader(
        appState: AppState, path: String
    ) -> (String) async -> Data? {
        { kind in
            guard let config = appState.config else { return nil }
            return try? await bridgeClient.rendition(
                config: config, path: path, width: 360,
                kind: kind)
        }
    }

    /// loader＝原图取字节通道；renditionLoader＝变体
    /// 取字节通道（入参 kind：image/poster）
    func thumbnail(
        for entry: WorkspaceFileEntry,
        targetPixelSize: CGFloat,
        loader: @escaping () async -> Data?,
        renditionLoader: ((String) async -> Data?)? = nil
    ) async -> UIImage? {
        // 音频不生成（类型面回落由调用方呈现）
        if entry.mediaKind == .audio {
            return nil
        }
        let key = cacheKey(for: entry, pixel: Int(targetPixelSize))
        if let cached = memoryCache.object(forKey: key as NSString) {
            return cached
        }
        if let disk = await loadFromDisk(key: key) {
            memoryCache.setObject(disk, forKey: key as NSString)
            return disk
        }
        await gate.acquire()
        let image = await generate(
            for: entry, targetPixelSize: targetPixelSize,
            loader: loader, renditionLoader: renditionLoader
        )
        await gate.release()
        if let image {
            memoryCache.setObject(image, forKey: key as NSString)
            await saveToDisk(image, key: key)
            // 播种管线：影音格/文件行点开查看器时，
            // 这张 360 就是首帧种子（§144）
            if entry.mediaKind == .image {
                RemoteImagePipeline.shared.storeMemory(
                    image, path: entry.path,
                    mtime: entry.mtime ?? 0, tier: .thumb)
            }
        }
        return image
    }

    private func generate(
        for entry: WorkspaceFileEntry,
        targetPixelSize: CGFloat,
        loader: @escaping () async -> Data?,
        renditionLoader: ((String) async -> Data?)?
    ) async -> UIImage? {
        if entry.mediaKind == .image {
            // §418：变体取数收编——按 thumb 路由键登记
            // 本笔通道后走统一管线（loader 内变体优先、
            // 回落原图），解码封顶＝目标像素（与旧
            // downsampledImage 封顶逐值同口径）
            HermesImageRouting.shared.register(
                key: RemoteImageKey.make(
                    path: entry.path,
                    mtime: entry.mtime ?? 0, tier: .thumb),
                config: nil,
                originalLoader: loader,
                renditionLoader: renditionLoader)
            var request = RemoteImageRequestFactory
                .renditionRequest(
                    path: entry.path,
                    mtime: entry.mtime ?? 0, tier: .thumb)
            request.processors = [
                ImageProcessors.Resize(
                    size: CGSize(
                        width: targetPixelSize,
                        height: targetPixelSize),
                    unit: .pixels,
                    contentMode: .aspectFit,
                    crop: false,
                    upscale: false),
            ]
            return try? await OneDayImagePipelines.remote
                .image(for: request)
        }
        if entry.mediaKind == .video {
            // 海报帧当缩略源（§418 同收编 poster 路）；
            // 拿不到回落类型面（调用方呈现），整段下载
            // 抽帧不做（旧口径保留）
            guard renditionLoader != nil else { return nil }
            HermesImageRouting.shared.register(
                key: RemoteImageRequestFactory.posterKey(
                    path: entry.path,
                    mtime: entry.mtime ?? 0),
                config: nil,
                originalLoader: loader,
                renditionLoader: renditionLoader)
            let request = RemoteImageRequestFactory
                .posterRequest(
                    path: entry.path,
                    mtime: entry.mtime ?? 0,
                    pixelCap: Int(targetPixelSize))
            return try? await OneDayImagePipelines.remote
                .image(for: request)
        }
        guard let data = await loader() else { return nil }
        return await Self.quickLookThumbnail(
            data: data, entry: entry,
            targetPixelSize: targetPixelSize
        )
    }

    /// QL 首面：缩略提供者认扩展名，临时文件必须保原名
    /// §410 接管补漏：建目录＋整份字节写临时文件下主
    /// 线程（取证 §1.5 第四个同步点）——旧链在
    /// @MainActor 上同步写全量字节；现独立任务写完
    /// 再回主线发 QL 请求，写失败回 nil 与旧口径一致
    private static func quickLookThumbnail(
        data: Data, entry: WorkspaceFileEntry,
        targetPixelSize: CGFloat
    ) async -> UIImage? {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "od-thumb-\(stableHash(entry.path))",
                isDirectory: true
            )
        let fileURL = directory.appendingPathComponent(entry.name)
        let written = await Task.detached(
            priority: .userInitiated
        ) {
            do {
                try FileManager.default.createDirectory(
                    at: directory,
                    withIntermediateDirectories: true
                )
                try data.write(to: fileURL)
                return true
            } catch {
                return false
            }
        }.value
        guard written else { return nil }
        defer {
            try? FileManager.default.removeItem(at: directory)
        }
        let request = QLThumbnailGenerator.Request(
            fileAt: fileURL,
            size: CGSize(
                width: targetPixelSize, height: targetPixelSize
            ),
            scale: 1,
            representationTypes: .thumbnail
        )
        return await withCheckedContinuation { continuation in
            QLThumbnailGenerator.shared.generateBestRepresentation(
                for: request
            ) { representation, _ in
                continuation.resume(
                    returning: representation?.uiImage
                )
            }
        }
    }

    // MARK: 缓存键与磁盘层

    private func cacheKey(
        for entry: WorkspaceFileEntry, pixel: Int
    ) -> String {
        "\(Self.stableHash(entry.path))"
            + "-\(Int(entry.mtime ?? 0))-\(pixel)"
    }

    /// FNV-1a 稳定哈希（跨启动不变，磁盘缓存键用）
    static func stableHash(_ string: String) -> UInt64 {
        var hash: UInt64 = 1469598103934665603
        for byte in string.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1099511628211
        }
        return hash
    }

    private var diskDirectory: URL? {
        guard let caches = FileManager.default.urls(
            for: .cachesDirectory, in: .userDomainMask
        ).first else { return nil }
        let directory = caches.appendingPathComponent(
            "FileThumbnails", isDirectory: true
        )
        try? FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true
        )
        return directory
    }

    /// §410：磁盘命中解码下主线程——UIImage(contentsOfFile:)
    /// 同步解码整图，旧链在 @MainActor 上直付；现独立任务
    /// 解码、装箱回主线（同 RemoteImagePipeline 的离主解
    /// 码待遇）。落点 URL 仍在主线算（目录确保是便宜元数据）
    private func loadFromDisk(key: String) async -> UIImage? {
        guard let url = diskDirectory?
            .appendingPathComponent("\(key).png")
        else { return nil }
        let box = await Task.detached(priority: .userInitiated) {
            () -> ThumbImageBox? in
            guard FileManager.default.fileExists(atPath: url.path)
            else { return nil }
            return UIImage(contentsOfFile: url.path)
                .map(ThumbImageBox.init)
        }.value
        return box?.image
    }

    /// §410：PNG 编码＋写盘下主线程（编码是整图字节活，
    /// 与解码同待遇）；落点 URL 仍在主线算
    private func saveToDisk(_ image: UIImage, key: String) async {
        guard let url = diskDirectory?
            .appendingPathComponent("\(key).png")
        else { return }
        let box = ThumbImageBox(image)
        await Task.detached(priority: .utility) {
            guard let data = box.image.pngData() else { return }
            try? data.write(to: url)
        }.value
    }
}

/// 缩略生成并发闸（上限 2，规格 §4.3 护栏）
actor ThumbnailGate {
    private var permits = 2
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func acquire() async {
        if permits > 0 {
            permits -= 1
            return
        }
        await withCheckedContinuation { waiters.append($0) }
    }

    func release() {
        if waiters.isEmpty {
            permits += 1
        } else {
            waiters.removeFirst().resume()
        }
    }
}

/// 类型面（规格 §4.3 回落形态）：低饱和度家族色
/// 淡底＋放大居中扁平图标＋右下角格式徽标；不可渲
/// 类（代码/Markdown/Office/音频/压缩包/文件夹）与
/// 缩略取不到时统一走它，深浅色模式均柔和不刺眼
struct FileTypeFace: View {
    let entry: WorkspaceFileEntry
    var iconHeight: CGFloat = 44

    private var slug: String {
        DeliverableIconStyle.style(
            forFileName: entry.name,
            isDirectory: entry.isDirectory
        ).slug
    }

    private var badgeText: String? {
        if entry.isDirectory { return nil }
        let ext = (entry.name as NSString).pathExtension.uppercased()
        return ext.isEmpty ? nil : ext
    }

    var body: some View {
        let palette = FileTypeIconView.palette(for: slug)
        ZStack {
            Palette.surface
            palette.base.opacity(0.08)
            FileTypeIconView(
                fileName: entry.name,
                isDirectory: entry.isDirectory,
                height: iconHeight
            )
            if let badgeText {
                VStack {
                    Spacer(minLength: 0)
                    HStack {
                        Spacer(minLength: 0)
                        Text(badgeText)
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundStyle(palette.base)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                palette.base.opacity(0.14),
                                in: Capsule()
                            )
                    }
                }
                .padding(OneDayMetrics.spacingS)
            }
        }
        .accessibilityHidden(true)
    }
}

/// 远程条目缩略视图：按大厂三档策略分流——
/// 1) 图片/视频：变体图或海报帧，scaledToFill 铺满，
///    视频叠毛玻璃播放角标；
/// 2) PDF/PPT/HTML：QL 首面，浅灰衬底 + aspectFit
///    纸张框（不硬裁页边距）；
/// 3) Markdown/代码/Word/Excel/音频/压缩包/文件夹：
///    不走重型下载与 QL，直接呈现家族淡底类型面
struct FileThumbnailView: View {
    @Environment(AppState.self) private var appState
    let entry: WorkspaceFileEntry
    var targetPixelSize: CGFloat = 360
    var compact: Bool = false

    @State private var image: UIImage?

    private var shouldFetchThumbnail: Bool {
        if entry.isDirectory { return false }
        if entry.mediaKind == .image || entry.mediaKind == .video {
            return true
        }
        if entry.mediaKind == .audio { return false }
        let ext = (entry.name as NSString).pathExtension.lowercased()
        if compact {
            return ext == "pdf"
        }
        return ["pdf", "ppt", "pptx", "key", "html", "htm"].contains(ext)
    }

    private var isPageDocument: Bool {
        guard entry.mediaKind == nil else { return false }
        let ext = (entry.name as NSString).pathExtension.lowercased()
        return ["pdf", "ppt", "pptx", "key", "html", "htm"].contains(ext)
    }

    var body: some View {
        ZStack {
            if let image {
                if isPageDocument && !compact {
                    ZStack {
                        Palette.fieldFill
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                            .overlay {
                                RoundedRectangle(cornerRadius: 4)
                                    .strokeBorder(Palette.hairline, lineWidth: 0.5)
                            }
                            .shadow(color: .black.opacity(0.08), radius: 4, y: 2)
                            .padding(OneDayMetrics.spacingS)
                    }
                } else {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                }
            } else {
                FileTypeFace(
                    entry: entry,
                    iconHeight: compact ? 28 : 44
                )
            }

            if entry.mediaKind == .video && image != nil {
                ZStack {
                    Circle()
                        .fill(.ultraThinMaterial)
                        .frame(width: compact ? 18 : 30, height: compact ? 18 : 30)
                    Image(systemName: "play.fill")
                        .font(.system(size: compact ? 8 : 12, weight: .bold))
                        .foregroundStyle(.white)
                        .offset(x: compact ? 0.5 : 1)
                }
            }
        }
        .clipped()
        .task(id: entry.path) {
            guard shouldFetchThumbnail, image == nil else { return }
            image = await FileThumbnailStore.shared.thumbnail(
                for: entry, targetPixelSize: targetPixelSize,
                loader: FileThumbnailStore.originalLoader(
                    appState: appState, path: entry.path),
                renditionLoader: FileThumbnailStore.renditionLoader(
                    appState: appState, path: entry.path)
            )
        }
    }
}
