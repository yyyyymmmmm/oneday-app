import Foundation
import OneDayCore

/// 盒桥错误：与总览桥同分法——「没有钥匙」「钥匙被拒
/// （401）」是桥未连接（钥匙问题）；其余（网络/厂商
/// 502/格式）如实归因，不许混报成未连接或电脑离线。
enum BoxBridgeError: Error, Sendable, Equatable {
    case noKey
    case unauthorized
    case failed(String)
}

/// Box 客户端（A1 甩桥，MCP 直连）：
///
/// 原桥端点（已退役，不再调用）：
/// - GET /api/box-bridge/status → box_status MCP 工具
/// - POST /api/box-bridge/screenshot → screenshot MCP 工具
/// - POST /api/box-bridge/act → computer_act / browser_navigate MCP 工具
///
/// 公开 API 不变（status/screenshot/act 签名保持），内部
/// 改为直连 Box MCP 服务。凭据：盒子钥匙从 Keychain
/// box.mcp.key 读取（独立于 Hermes api.key），MCP 地址
/// 默认 https://mcp.box.simular.ai/mcp（可由用户覆盖）。
///
/// 会话语义对齐 box_bridge.py：长驻会话、串行调用、懒重连
/// （重连=新会话，浏览器窗口重置是已知行为）。
final class BoxBridgeClient: @unchecked Sendable {
    init() {}

    func status(config: ServerConfig) async throws -> BoxBridgeStatus {
        let client = try await getClient()
        let result = try await client.callTool(name: "box_status", arguments: [:], timeout: 30)

        // 检查工具错误
        if result.isError == true {
            throw BoxBridgeError.failed(mcpErrorText(result))
        }

        // 解析结构化数据
        guard let structured = mcpStructured(result) else {
            throw BoxBridgeError.failed(L10n.string("云电脑状态返回格式无法识别"))
        }

        // 转换为 BoxBridgeStatus（复用现有 DTO）
        return try parseStatus(structured)
    }

    func screenshot(config: ServerConfig) async throws -> BoxScreenshot {
        let client = try await getClient()

        // 确保 Box 运行（对齐 box_bridge.py:341 MCP.ensure_running）
        try await client.ensureRunning()

        let result = try await client.callTool(
            name: "screenshot",
            arguments: ["max_edge": 1024],
            timeout: 60
        )

        if result.isError == true {
            throw BoxBridgeError.failed(mcpErrorText(result))
        }

        // 提取截图（对齐 box_bridge.py:215-238 extract_screenshot）
        guard let screenshot = extractScreenshot(result) else {
            throw BoxBridgeError.failed(L10n.string("截图中没有图像数据"))
        }

        return screenshot
    }

    func act(
        config: ServerConfig, request: BoxActRequest
    ) async throws -> BoxActResponse {
        let client = try await getClient()

        // 确保 Box 运行
        try await client.ensureRunning()

        // 根据 action 选择工具（对齐 box_bridge.py:361-399 post_act）
        let result: MCPResult
        if request.action == "navigate" {
            // 浏览器导航
            guard let url = request.url, url.hasPrefix("http") else {
                throw BoxBridgeError.failed(L10n.string("导航需要 http(s) 网址"))
            }
            result = try await client.callTool(
                name: "browser_navigate",
                arguments: ["url": url, "front": request.front ?? true],
                timeout: 60
            )
        } else {
            // 桌面动作（click/type/key 等）
            var args: [String: Any] = ["action": request.action]
            if let x = request.x { args["x"] = x }
            if let y = request.y { args["y"] = y }
            if let text = request.text { args["text"] = text }
            if let key = request.key { args["key"] = key }

            result = try await client.callTool(
                name: "computer_act",
                arguments: args,
                timeout: 90
            )
        }

        if result.isError == true {
            throw BoxBridgeError.failed(mcpErrorText(result))
        }

        // 提取截图和页面信息
        let screenshot = extractScreenshot(result)
        let page = parsePage(result)
        let summary = mcpTexts(result).first

        return BoxActResponse(
            ok: true,
            action: request.action,
            tool: request.action == "navigate" ? "browser_navigate" : "computer_act",
            page: page,
            summary: summary,
            screenshot: screenshot
        )
    }

    // MARK: - 辅助方法

    private func getClient() async throws -> BoxMCPClient {
        do {
            return try await BoxMCPClientFactory.getClient()
        } catch let error as BoxMCPError {
            switch error {
            case .noKey:
                throw BoxBridgeError.noKey
            case .sessionFailed(let msg):
                throw BoxBridgeError.failed(msg)
            case .toolCallFailed(let msg):
                throw BoxBridgeError.failed(msg)
            case .networkError:
                throw BoxBridgeError.failed(L10n.string("网络不可达"))
            }
        }
    }

    /// 解析 box_status 结构化数据为 BoxBridgeStatus
    private func parseStatus(_ dict: [String: Any]) throws -> BoxBridgeStatus {
        let state = dict["state"] as? String ?? ""
        let name = dict["name"] as? String
        let boxId = dict["box_id"] as? String
        let image = dict["image"] as? String
        let latestImage = dict["latest_image"] as? String
        let upgradeAvailable = dict["upgrade_available"] as? Bool
        let lastSavedAtMs = dict["last_saved_at_ms"] as? Int64
        let viewUrl = dict["view_url"] as? String
        let creditsLeft = dict["credits_left"] as? Double
        let creditsNote = dict["credits_note"] as? String

        // 解析页面信息
        var page: BoxPageRef?
        if let pageDict = dict["page"] as? [String: Any] {
            page = BoxPageRef(
                title: pageDict["title"] as? String ?? "",
                url: pageDict["url"] as? String ?? ""
            )
        }

        var lastKnownPage: BoxPageRef?
        if let lkpDict = dict["lastKnownPage"] as? [String: Any] {
            lastKnownPage = BoxPageRef(
                title: lkpDict["title"] as? String ?? "",
                url: lkpDict["url"] as? String ?? ""
            )
        }

        let lastKnownPageAt = dict["lastKnownPageAt"] as? String
        let checkedAt = dict["checkedAt"] as? String

        return BoxBridgeStatus(
            state: state,
            name: name,
            boxId: boxId,
            image: image,
            latestImage: latestImage,
            upgradeAvailable: upgradeAvailable,
            lastSavedAtMs: lastSavedAtMs,
            viewUrl: viewUrl,
            creditsLeft: creditsLeft,
            creditsNote: creditsNote,
            page: page,
            lastKnownPage: lastKnownPage,
            lastKnownPageAtRaw: lastKnownPageAt,
            checkedAtRaw: checkedAt
        )
    }

    /// 提取截图（对齐 box_bridge.py:215-238）
    private func extractScreenshot(_ result: MCPResult) -> BoxScreenshot? {
        guard let content = result.content else { return nil }

        for item in content {
            if case .image(let data, let mimeType) = item {
                // 解析图像尺寸
                guard let imageData = Data(base64Encoded: data) else { continue }
                let (width, height) = imageDimensions(imageData)

                return BoxScreenshot(
                    mime: mimeType,
                    width: width ?? 1024,
                    height: height ?? 640,
                    bytes: imageData.count,
                    imageBase64: data,
                    capturedAtRaw: ISO8601DateFormatter().string(from: Date())
                )
            }
        }

        return nil
    }

    /// 解析页面信息（对齐 box_bridge.py:241-248）
    private func parsePage(_ result: MCPResult) -> BoxPageRef? {
        let texts = mcpTexts(result)
        let pattern = #"^Page:\s*(.*?)\s*\((https?://[^)]+)\)\s*$"#

        for text in texts {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .anchorsMatchLines),
               let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) {
                let titleRange = Range(match.range(at: 1), in: text)
                let urlRange = Range(match.range(at: 2), in: text)

                if let titleRange = titleRange, let urlRange = urlRange {
                    return BoxPageRef(
                        title: String(text[titleRange]),
                        url: String(text[urlRange])
                    )
                }
            }
        }

        return nil
    }

    /// 解析图像尺寸（PNG/JPEG，对齐 box_bridge.py:192-212）
    private func imageDimensions(_ data: Data) -> (Int?, Int?) {
        guard data.count > 24 else { return (nil, nil) }

        // PNG: 前 8 字节是签名，16-24 字节是 IHDR 宽高
        if data.prefix(8) == Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]) {
            let width = data[16..<20].withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
            let height = data[20..<24].withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
            return (Int(width), Int(height))
        }

        // JPEG: 扫描 SOF0/SOF1/SOF2 标记
        if data.prefix(2) == Data([0xFF, 0xD8]) {
            var i = 2
            while i + 9 < data.count {
                if data[i] != 0xFF { i += 1; continue }
                let marker = data[i + 1]
                if marker == 0xC0 || marker == 0xC1 || marker == 0xC2 {
                    let height = UInt16(data[i + 5]) << 8 | UInt16(data[i + 6])
                    let width = UInt16(data[i + 7]) << 8 | UInt16(data[i + 8])
                    return (Int(width), Int(height))
                }
                if i + 3 < data.count {
                    let segLen = Int(UInt16(data[i + 2]) << 8 | UInt16(data[i + 3]))
                    i += 2 + segLen
                } else {
                    break
                }
            }
        }

        return (nil, nil)
    }
}
