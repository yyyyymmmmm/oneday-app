import ImageIO
import OneDayCore
import OneDayDesign
import QuickLookThumbnailing
import SwiftUI
import UIKit

/// 文件页缩略图（0.36.31，文件页 v2 规格 §4.3 一期策
/// 略；§138 二期收口——服务端变体端点已上线）：
/// - 图片：先走伴生变体端点 360 档（几十 KB），拿
///   不到才回落原字节经 ImageIO 降采样解码（禁全
///   尺寸解码，影音格 0.36.4 前的全量解码病已销）；
/// - 视频：伴生海报帧（ffmpeg 首帧）当缩略源（§138
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
@MainActor
final class FileThumbnailStore {
    static let shared = FileThumbnailStore()

    private let memoryCache = NSCache<NSString, UIImage>()
    private let gate = ThumbnailGate()

    private init() {
        memoryCache.countLimit = 120
    }

    /// 取字节通道组（§138）：原图走宿主 performAdmin
    /// 文件下载、变体走桥 rendition 端点（桥钥在客户
    /// 端内读，宽度固定 360 档）——FileThumbnailView／
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
        if let disk = loadFromDisk(key: key) {
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
            saveToDisk(image, key: key)
            // 播种管线：影音格/文件行点开查看器时，
            // 这张 360 就是首帧种子（§138）
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
        loader: () async -> Data?,
        renditionLoader: ((String) async -> Data?)?
    ) async -> UIImage? {
        if entry.mediaKind == .image {
            // 变体优先（360 档 JPEG），回落原图降采样
            if let renditionLoader,
               let data = await renditionLoader("image"),
               let image = Self.downsampledImage(
                   data: data, pixelSize: targetPixelSize) {
                return image
            }
            guard let data = await loader() else { return nil }
            return Self.downsampledImage(
                data: data, pixelSize: targetPixelSize
            )
        }
        if entry.mediaKind == .video {
            // 海报帧当缩略源；拿不到回落类型面（调用
            // 方呈现），整段下载抽帧不做（旧口径保留）
            if let renditionLoader,
               let data = await renditionLoader("poster") {
                return Self.downsampledImage(
                    data: data, pixelSize: targetPixelSize
                )
            }
            return nil
        }
        guard let data = await loader() else { return nil }
        return await Self.quickLookThumbnail(
            data: data, entry: entry,
            targetPixelSize: targetPixelSize
        )
    }

    /// ImageIO 降采样：只解到目标像素量级，不整图入内存
    private static func downsampledImage(
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

    /// QL 首面：缩略提供者认扩展名，临时文件必须保原名
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
        do {
            try FileManager.default.createDirectory(
                at: directory, withIntermediateDirectories: true
            )
            try data.write(to: fileURL)
        } catch {
            return nil
        }
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

    private func loadFromDisk(key: String) -> UIImage? {
        guard let url = diskDirectory?
            .appendingPathComponent("\(key).png"),
              FileManager.default.fileExists(atPath: url.path)
        else { return nil }
        return UIImage(contentsOfFile: url.path)
    }

    private func saveToDisk(_ image: UIImage, key: String) {
        guard let url = diskDirectory?
            .appendingPathComponent("\(key).png"),
              let data = image.pngData()
        else { return }
        try? data.write(to: url)
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

/// 类型面（规格 §4.3 回落形态）：FileIconBox 的放大
/// 版——白砖面＋自制类型图标图居中（§128 路线 A，
/// 与图标盒同源）；缩略取不到、视频/音频、生成中的
/// 占位都用它，不许留白、不许拿文件名当占位
/// （0.36.4 已立此规）
struct FileTypeFace: View {
    let entry: WorkspaceFileEntry

    var body: some View {
        let style = DeliverableIconStyle.style(
            forFileName: entry.name,
            isDirectory: entry.isDirectory
        )
        ZStack {
            Rectangle().fill(Color.white)
            FileIconImageView(assetName: style.assetName)
                .aspectRatio(contentMode: .fit)
        }
        .accessibilityHidden(true)
    }
}

/// 远程条目缩略视图：有图显图（填充裁切）、无图/未到
/// 显类型面。宿主只管定框，取图与缓存全在 Store。
struct FileThumbnailView: View {
    @Environment(AppState.self) private var appState
    let entry: WorkspaceFileEntry
    var targetPixelSize: CGFloat = 360

    @State private var image: UIImage?

    var body: some View {
        ZStack {
            FileTypeFace(entry: entry)
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            }
        }
        .clipped()
        .task(id: entry.path) {
            guard image == nil else { return }
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
