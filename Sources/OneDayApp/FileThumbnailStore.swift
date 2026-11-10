import ImageIO
import OneDayCore
import OneDayDesign
import QuickLookThumbnailing
import SwiftUI
import UIKit

/// 文件页缩略图（0.36.31，文件页 v2 规格 §4.3 一期策
/// 略——服务端无缩略端点，全部在 App 侧生成，流量代
/// 价如实存在、二期服务端根治）：
/// - 图片：原字节经 ImageIO 降采样解码（禁全尺寸解
///   码，影音格 0.36.4 前的全量解码病在本版一并销）；
/// - PDF/Office/HTML/文本：落临时文件走系统 QLThumb-
///   nailGenerator 取首面（系统对这些类型有缩略提供
///   者）；取不到回落类型面（FileTypeFace），不留白；
/// - 视频/音频：不生成（一期回落类型面＋角标，规格
///   §4.3 定版：整段下载抽帧代价不成比例）；
/// - 缓存：内存 NSCache＋磁盘（Caches/FileThumbs），
///   键含 path＋mtime＋目标像素——文件变了自动失效；
/// - 并发闸 2：滚动时不让缩略生成把带宽与解码打满。
@MainActor
final class FileThumbnailStore {
    static let shared = FileThumbnailStore()

    private let memoryCache = NSCache<NSString, UIImage>()
    private let gate = ThumbnailGate()

    private init() {
        memoryCache.countLimit = 120
    }

    /// loader＝宿主的取字节通道（performAdmin fileData）
    func thumbnail(
        for entry: WorkspaceFileEntry,
        targetPixelSize: CGFloat,
        loader: @escaping () async -> Data?
    ) async -> UIImage? {
        // 视频/音频不生成（类型面回落由调用方呈现）
        if let kind = entry.mediaKind, kind != .image {
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
            loader: loader
        )
        await gate.release()
        if let image {
            memoryCache.setObject(image, forKey: key as NSString)
            saveToDisk(image, key: key)
        }
        return image
    }

    private func generate(
        for entry: WorkspaceFileEntry,
        targetPixelSize: CGFloat,
        loader: () async -> Data?
    ) async -> UIImage? {
        guard let data = await loader() else { return nil }
        if entry.mediaKind == .image {
            return Self.downsampledImage(
                data: data, pixelSize: targetPixelSize
            )
        }
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
        let request = QLThumbnailGenerationRequest(
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
/// 版——身份色满底＋大号类型字形居中；缩略取不到、
/// 视频/音频、生成中的占位都用它，不许留白、不许拿
/// 文件名当占位（0.36.4 已立此规）
struct FileTypeFace: View {
    let entry: WorkspaceFileEntry

    var body: some View {
        let style = DeliverableIconStyle.style(
            forFileName: entry.name,
            isDirectory: entry.isDirectory
        )
        ZStack {
            Rectangle().fill(Color(hexRGB: style.backgroundHex))
            switch style.glyph {
            case .letter(let letter):
                Text(letter)
                    // 图标字形非阅读文字，固定字号合法
                    // （FileIconBox 同口径）
                    .font(.system(size: 40, weight: .bold))
                    .foregroundStyle(Color.white)
            case .symbol(let name):
                Image(systemName: name)
                    .font(.system(size: 36))
                    .foregroundStyle(Color.white)
            }
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
                for: entry, targetPixelSize: targetPixelSize
            ) {
                try? await appState.performAdmin {
                    client, config in
                    try await client.fileData(
                        config: config, path: entry.path
                    )
                }
            }
        }
    }
}
