import Foundation
import OneDayCore

/// 文件加工客户端（API 直连 B 包，2026-11-14）：媒体
/// 变体（§138）从 oneday 桥拆出为伴生独立 fileproc
/// 模块（Hermes /api/files* 只回原文件、无缩放，
/// /api/media 只回整图 data URL，均无对应原生端
/// 点——按总纲「先给服务端补 API」在伴生侧立独立
/// 薄端点收敛，不再寄生 oneday 桥）。表格转码端点
/// 仍在伴生侧（作降级保留），App 侧消费已随 §259
/// 文件预览双轨合一退役（表格一律走 QuickLook 原
/// 文件预览），本类不再留转码方法。
/// 路径挂服务器根下 /api/fileproc-bridge，Bearer 与
/// 全 App 桥客户端同口径（登录密钥经入口换桥钥）；
/// 状态码口径与桥时代逐字不变：不走人话收敛、状态
/// 码原样包成 HermesError.unexpectedStatus 交调用
/// 方分型，无钥匙走 OneDayBridgeError.noKey
final class FilesProcClient: @unchecked Sendable {
    private let base = BridgeClientBase<OneDayBridgeError>(
        pathPrefix: "/api/fileproc-bridge", timeout: 15,
        noKey: .noKey, failed: OneDayBridgeError.failed
    )

    private var decoder: JSONDecoder { base.decoder }

    // MARK: - 图片变体（§138，GET /media/rendition）

    /// 回变体 JPEG 字节（kind=image 取图变体、kind=
    /// poster 取视频首帧海报）；415 格式不支持/404
    /// 不存在时调用方回落原图通道
    func rendition(
        config: ServerConfig, path: String,
        width: Int, kind: String = "image"
    ) async throws -> Data {
        let allowed = CharacterSet.alphanumerics.union(
            CharacterSet(charactersIn: "-._~/")
        )
        let encoded = path.addingPercentEncoding(
            withAllowedCharacters: allowed
        ) ?? path
        let request = try base.makeRequest(
            config: config,
            path: "/media/rendition?path=\(encoded)"
                + "&w=\(width)&kind=\(kind)",
            method: "GET"
        )
        let (data, http) = try await base.data(
            for: request, endpoint: L10n.string("图片预览")
        )
        guard (200...299).contains(http.statusCode) else {
            throw HermesError.unexpectedStatus(
                endpoint: L10n.string("图片预览"),
                status: http.statusCode
            )
        }
        return data
    }
}
