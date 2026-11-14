import Foundation
import OneDayCore

/// 文件加工客户端（API 直连 B 包，2026-11-14）：表格
/// 转码（§125）与媒体变体（§138）从 oneday 桥拆出为
/// 伴生独立 fileproc 模块（Hermes /api/files* 只回原
/// 文件、无转码与缩放，/api/media 只回整图 data URL，
/// 均无对应原生端点——按总纲「先给服务端补 API」在
/// 伴生侧立独立薄端点收敛，不再寄生 oneday 桥）。
/// 路径挂服务器根下 /api/fileproc-bridge，Bearer 与
/// 全 App 桥客户端同口径（登录密钥经入口换桥钥）；
/// 两端点的状态码口径与桥时代逐字不变：不走人话
/// 收敛、状态码原样包成 HermesError.unexpectedStatus
/// 交调用方分型，无钥匙走 OneDayBridgeError.noKey
final class FilesProcClient: @unchecked Sendable {
    private let base = BridgeClientBase<OneDayBridgeError>(
        pathPrefix: "/api/fileproc-bridge", timeout: 15,
        noKey: .noKey, failed: OneDayBridgeError.failed
    )

    private var decoder: JSONDecoder { base.decoder }

    // MARK: - 表格转码（§125，GET /files/spreadsheet）

    /// xlsx 按 sheet 转 CSV（值口径）。状态码分型见
    /// 文件头：422 转码专档/413 过大/404 不存在各有
    /// 出路，收敛成一句会丢分型
    func spreadsheet(
        config: ServerConfig, path: String
    ) async throws -> BridgeSpreadsheet {
        let allowed = CharacterSet.alphanumerics.union(
            CharacterSet(charactersIn: "-._~/")
        )
        let encoded = path.addingPercentEncoding(
            withAllowedCharacters: allowed
        ) ?? path
        let request = try base.makeRequest(
            config: config,
            path: "/files/spreadsheet?path=\(encoded)",
            method: "GET"
        )
        let (data, http) = try await base.data(
            for: request, endpoint: L10n.string("表格转换")
        )
        guard (200...299).contains(http.statusCode) else {
            throw HermesError.unexpectedStatus(
                endpoint: L10n.string("表格转换"),
                status: http.statusCode
            )
        }
        do {
            return try decoder.decode(
                BridgeSpreadsheet.self, from: data
            )
        } catch {
            throw OneDayBridgeError.failed(
                L10n.string("表格转换返回格式无法识别")
            )
        }
    }

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
