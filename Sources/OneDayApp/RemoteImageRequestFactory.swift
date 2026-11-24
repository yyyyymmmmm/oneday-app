import Foundation
import Nuke
import OneDayCore
import UIKit

/// §418（#23 图片管线换底，施工图 swap-md-image-prep
/// 第二部）：远端图请求构造单点——档位／变体端点／缓存
/// 键只许在这里构造，消费面不许自拼 URL 或键。
///
/// 路由形态：宿主鉴权图不是裸 URL 可直取的公开资源，
/// 构造器以虚构主机 img.oneday.invalid 打标三条路由
/// （rendition 变体／original 原图／poster 海报帧），
/// 真实取数由 HermesImageDataLoader 按登记表分发（见
/// HermesImageRouting）——公开 URL 与鉴权 URL 在本层
/// 分开建请求，loader 不猜鉴权。
///
/// 缓存键等价：路由 URL 路径段嵌旧键 RemoteImageKey
/// .make(path,mtime,tier) 原文——新键对 (path,mtime,
/// tier) 的划分与旧键逐字同构（钉测把守）；mtime 与
/// 档位同时入 URL，文件变或换档即换键。
enum RemoteImageRequestFactory {

    /// 管线内路由主机（虚构，只作分发标记，永不真连）
    static let routeHost = "img.oneday.invalid"
    private static let routeBase = "https://\(routeHost)"

    /// 本地图解码长边封顶（显示卡高 190pt 的 3 倍余量
    /// 之上取整）：只治全尺寸解码，比例不变、布局口径
    /// （ChatImageSizing 只吃宽高比）不受影响
    static let localDecodeCap = 1024

    // MARK: - 鉴权图三路由

    /// 变体档请求：桥 rendition 按档位宽取变体，解码
    /// 后 Resize 到档位长边（与旧管线 ImageIO 降采样
    /// 封顶逐值同口径）
    static func renditionRequest(
        path: String, mtime: Double, tier: ImageRenditionTier
    ) -> ImageRequest {
        precondition(tier.renditionWidth != nil)
        let key = RemoteImageKey.make(
            path: path, mtime: mtime, tier: tier)
        var components = URLComponents(
            string: "\(routeBase)/rendition/\(key)")!
        components.queryItems = [
            URLQueryItem(name: "path", value: path),
            URLQueryItem(
                name: "w",
                value: String(tier.renditionWidth ?? 0)),
        ]
        return ImageRequest(
            url: components.url,
            processors: [Self.capProcessor(tier.longEdge)]
        )
    }

    /// 原图档请求：宿主 performAdmin 鉴权下载，解码
    /// 封顶 4096（与旧管线同值）
    static func originalRequest(
        path: String, mtime: Double
    ) -> ImageRequest {
        let key = RemoteImageKey.make(
            path: path, mtime: mtime, tier: .original)
        var components = URLComponents(
            string: "\(routeBase)/original/\(key)")!
        components.queryItems = [
            URLQueryItem(name: "path", value: path),
        ]
        return ImageRequest(
            url: components.url,
            processors: [Self.capProcessor(4096)]
        )
    }

    /// 档位分发总口（门面用）：original 档走原图路，
    /// 其余走变体路
    static func tierRequest(
        path: String, mtime: Double, tier: ImageRenditionTier
    ) -> ImageRequest {
        if tier == .original {
            return originalRequest(path: path, mtime: mtime)
        }
        return renditionRequest(
            path: path, mtime: mtime, tier: tier)
    }

    /// 海报帧请求（FileThumbnailStore 视频缩略源）：
    /// 桥 rendition kind=poster；无原图回落（旧口径：
    /// 海报拿不到回类型面）
    /// 海报路由键（登记表与 URL 路径段共用此值）
    static func posterKey(path: String, mtime: Double) -> String {
        "\(RemoteImageKey.stableHash(path))-\(Int(mtime))-poster"
    }

    static func posterRequest(
        path: String, mtime: Double, pixelCap: Int
    ) -> ImageRequest {
        let key = posterKey(path: path, mtime: mtime)
        var components = URLComponents(
            string: "\(routeBase)/poster/\(key)")!
        components.queryItems = [
            URLQueryItem(name: "path", value: path),
        ]
        return ImageRequest(
            url: components.url,
            processors: [Self.capProcessor(pixelCap)]
        )
    }

    // MARK: - 公开图（Feed/引用卡：裸 http(s)，默认通道）

    /// 公开 URL 直通＋长边封顶 Resize：补上旧 AsyncImage
    /// 没有的降采样（长图全尺寸解码的内存风险随之消）
    static func publicRequest(
        url: URL, longEdgeCap: Int
    ) -> ImageRequest {
        ImageRequest(
            url: url,
            processors: [Self.capProcessor(longEdgeCap)]
        )
    }

    // MARK: - 本地图（合成键＋注入表）

    /// 本地图合成键：条目 id＋图序＋字节数（与旧
    /// LocalImageDecodeCache 键口径逐字同构——条目图
    /// 数据落盘后不可变，字节数入键防串图）
    static func localKey(
        entryID: UUID, index: Int, byteCount: Int
    ) -> String {
        "\(entryID.uuidString)/\(index)/\(byteCount)"
    }

    static func localRequest(
        entryID: UUID, index: Int, byteCount: Int
    ) -> ImageRequest {
        let key = localKey(
            entryID: entryID, index: index,
            byteCount: byteCount)
        return ImageRequest(
            url: URL(string: "localdata://local/\(key)"),
            processors: [Self.capProcessor(localDecodeCap)]
        )
    }

    // MARK: - 路由解析（loader 侧）

    enum Route: Equatable {
        case rendition(path: String, width: Int)
        case original(path: String)
        case poster(path: String)
    }

    /// 路由 URL → 分发判据；非路由 URL 返回 nil
    static func route(for url: URL) -> Route? {
        guard url.host == routeHost,
              let components = URLComponents(
                  url: url, resolvingAgainstBaseURL: false),
              let path = components.queryItems?.first(
                  where: { $0.name == "path" })?.value
        else { return nil }
        if url.path.hasPrefix("/rendition/") {
            let width = components.queryItems?.first(
                where: { $0.name == "w" })?.value
                .flatMap(Int.init) ?? 0
            return .rendition(path: path, width: width)
        }
        if url.path.hasPrefix("/original/") {
            return .original(path: path)
        }
        if url.path.hasPrefix("/poster/") {
            return .poster(path: path)
        }
        return nil
    }

    /// localdata URL → 注入表键；非本地图 URL 返回 nil
    static func localKey(for url: URL) -> String? {
        guard url.scheme == "localdata" else { return nil }
        let path = url.path
        guard path.hasPrefix("/") else { return nil }
        return String(path.dropFirst())
    }

    /// 路由 URL → 登记键（路径末段，即构造时嵌入的旧
    /// 键原文）；非路由 URL 返回 nil。登记按此键分格，
    /// 同 path 不同档位/路由的通道互不串线
    static func routeKey(for url: URL) -> String? {
        guard url.host == routeHost else { return nil }
        let key = url.lastPathComponent
        return key.isEmpty ? nil : key
    }

    private static func capProcessor(
        _ longEdge: Int
    ) -> any ImageProcessing {
        ImageProcessors.Resize(
            size: CGSize(
                width: longEdge, height: longEdge),
            unit: .pixels,
            contentMode: .aspectFit,
            crop: false,
            upscale: false
        )
    }
}

/// 取数路由登记表（§418）：门面／缩略店在每次取图前
/// 按**路由键**（URL 路径末段＝旧缓存键，含档位）登记
/// 本笔的取数通道（config＋原图通道＋变体通道），
/// HermesImageDataLoader 只按登记分发。按路由键分格
/// 而非按 path——同文件不同档位、缩略店与查看器并发
/// 同文件时通道互不串线；同路由键的整笔覆盖与旧管线
/// 「合并请求以首位调用方通道为准」同级近似。通道闭
/// 包只经本表进出，loader 不猜鉴权。
final class HermesImageRouting: @unchecked Sendable {
    static let shared = HermesImageRouting()

    final class Entry {
        let config: ServerConfig?
        let originalLoader: (() async -> Data?)?
        let renditionLoader: ((String) async -> Data?)?

        init(
            config: ServerConfig?,
            originalLoader: (() async -> Data?)?,
            renditionLoader: ((String) async -> Data?)?
        ) {
            self.config = config
            self.originalLoader = originalLoader
            self.renditionLoader = renditionLoader
        }
    }

    private let lock = NSLock()
    private var entries: [String: Entry] = [:]

    func register(
        key: String,
        config: ServerConfig?,
        originalLoader: (() async -> Data?)?,
        renditionLoader: ((String) async -> Data?)? = nil
    ) {
        let entry = Entry(
            config: config,
            originalLoader: originalLoader,
            renditionLoader: renditionLoader)
        lock.lock()
        entries[key] = entry
        lock.unlock()
    }

    func entry(forKey key: String) -> Entry? {
        lock.lock()
        defer { lock.unlock() }
        return entries[key]
    }
}

/// 本地图数据注入表（§418）：条目内嵌 Data 无 URL，
/// 由消费方在取图前按合成键注入，localdata 路由的
/// DataLoader 据键回查。数据落盘后不可变；表只服务
/// 「登记后即取」的短窗，FIFO 封顶 256 键防无界增长
/// （淘汰只伤异步重取、不伤同步门面路——门面每次调
/// 用都重新登记）
final class LocalImageDataRegistry: @unchecked Sendable {
    static let shared = LocalImageDataRegistry()

    private static let capacity = 256

    private let lock = NSLock()
    private var datas: [String: Data] = [:]
    private var order: [String] = []

    func register(key: String, data: Data) {
        lock.lock()
        if datas[key] == nil {
            order.append(key)
            while order.count > Self.capacity {
                datas[order.removeFirst()] = nil
            }
        }
        datas[key] = data
        lock.unlock()
    }

    func data(for key: String) -> Data? {
        lock.lock()
        defer { lock.unlock() }
        return datas[key]
    }
}
