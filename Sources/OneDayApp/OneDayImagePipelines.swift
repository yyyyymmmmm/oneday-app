import Foundation
import Nuke
import UIKit

/// §418（#23 图片管线换底）：Nuke 管线装配单点（施工
/// 图第二部 2.4 配置定版，开工即按此配）：
/// - remote：远端图（聊天图卡／查看器／Feed 公开图）；
///   磁盘 DataCache 名 OneDayRemoteImages、512MB（旧
///   磁盘口径），内存 ImageCache 256MB／300 枚（旧内
///   存口径）；渐进解码开（查看器大图受益）、断点续
///   传开（库默认已开、明示钉死）；解码在管线队列、
///   主线程只收成品。
/// - local：聊天本地图（合成键）；无磁盘层（字节本体
///   已在条目落盘里，不重复落盘），内存 64MB（旧本地
///   缓存封顶同值）。
/// 两条管线共用 HermesImageDataLoader 与解码探针包
/// 装（ChatLagProbe 解码回读口径延续：探针点由旧
/// decodeOffMain 迁到解码器包装，记的仍是解码本体
/// 时长）。
enum OneDayImagePipelines {

    static let remote: ImagePipeline = {
        var configuration = ImagePipeline.Configuration(
            dataLoader: HermesImageDataLoader.shared)
        let dataCache = try? DataCache(
            name: "OneDayRemoteImages")
        dataCache?.sizeLimit = 512 * 1024 * 1024
        configuration.dataCache = dataCache
        configuration.imageCache = ImageCache(
            costLimit: 256 * 1024 * 1024, countLimit: 300)
        configuration.isProgressiveDecodingEnabled = true
        configuration.isResumableDataEnabled = true
        configuration.makeImageDecoder = Self.makeProbeDecoder
        return ImagePipeline(configuration: configuration)
    }()

    /// 远端预取器（查看器翻页预取）：目标内存缓存、
    /// 并发 2（库默认，与旧预取低优先口径同级）
    static let remotePrefetcher = ImagePrefetcher(
        pipeline: remote, destination: .memoryCache)

    static let local: ImagePipeline = {
        var configuration = ImagePipeline.Configuration(
            dataLoader: HermesImageDataLoader.shared)
        configuration.dataCache = nil
        configuration.imageCache = ImageCache(
            costLimit: 64 * 1024 * 1024, countLimit: 300)
        configuration.makeImageDecoder = Self.makeProbeDecoder
        return ImagePipeline(configuration: configuration)
    }()

    private static let makeProbeDecoder:
        @Sendable (ImageDecodingContext) -> (any ImageDecoding)? = {
            context in
            ImageDecoderRegistry.shared.decoder(for: context)
                .map { ProbeImageDecoder(base: $0) }
        }
}

/// 解码探针包装（§418）：转发默认解码器的全部行为，
/// 只在整图解码本体两侧计时入 ChatLagProbe（渐进预
/// 览的局部解码不计——旧探针同口径，只记整图）
private struct ProbeImageDecoder: ImageDecoding {
    let base: any ImageDecoding

    var isAsynchronous: Bool { base.isAsynchronous }

    func decode(_ data: Data) throws -> ImageContainer {
        let start = ContinuousClock.now
        defer {
            ChatLagProbe.noteDecode(
                duration: start.duration(to: .now))
        }
        return try base.decode(data)
    }

    func decodePartiallyDownloadedData(
        _ data: Data
    ) -> ImageContainer? {
        base.decodePartiallyDownloadedData(data)
    }
}
