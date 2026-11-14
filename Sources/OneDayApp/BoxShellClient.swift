import Foundation
import OneDayCore

/// 盒终端错误：与各桥同分法——「没有钥匙」「钥匙被拒
/// （401）」是桥未连接；端点 404 是「电脑终端尚未开通」
/// （桥还没部署 shell 面）；其余失败给人话、不混报。
enum BoxShellError: Error, Sendable, Equatable {
    case noKey
    case unauthorized
    case notAvailable
    case failed(String)
}

/// Box 终端客户端（A1 甩桥，MCP 直连）：
///
/// 原桥端点（已退役）：
/// - POST /api/box-bridge/shell → shell MCP 工具
///
/// 公开 API 不变（run 签名保持），内部改为直连 Box MCP。
/// 命令由用户逐条手输、原样透传，超时 90 秒。
///
/// shell 工具返回文本，尾部带 `[exit status N]` 标记
/// （对齐 box_bridge.py:416-455）。
final class BoxShellClient: @unchecked Sendable {
    init() {}

    func run(
        config: ServerConfig, command: String
    ) async throws -> BoxShellResponse {
        let client = try await getClient()

        // 确保 Box 运行（shell 需要运行中的 Box）
        try await client.ensureRunning()

        let result = try await client.callTool(
            name: "shell",
            arguments: ["command": command],
            timeout: 90
        )

        if result.isError == true {
            // 厂商侧失败（无 exit status）：按契约 SS3 返回错误
            throw BoxShellError.failed(mcpErrorText(result))
        }

        // 解析输出文本
        let texts = mcpTexts(result)
        guard let rawText = texts.first else {
            return BoxShellResponse(ok: false, output: "", exitCode: nil, truncated: nil)
        }

        // 提取 exit status 尾行（对齐 box_bridge.py:433-439）
        let exitPattern = #"\[exit status (-?\d+)\]\s*$"#
        var text = rawText
        var exitCode: Int?

        if let regex = try? NSRegularExpression(pattern: exitPattern),
           let match = regex.firstMatch(in: rawText, range: NSRange(rawText.startIndex..., in: rawText)) {
            if let codeRange = Range(match.range(at: 1), in: rawText) {
                exitCode = Int(rawText[codeRange])
            }
            // 剥离尾行
            text = String(rawText[..<rawText.index(rawText.startIndex, offsetBy: match.range.location)])
            // 去除尾部分隔换行
            if text.hasSuffix("\n") {
                text = String(text.dropLast())
            }
        }

        // 检查截断（box_bridge.py:445-448）
        let truncated = text.contains("[box-bridge: output truncated at")

        return BoxShellResponse(
            ok: exitCode == 0,
            output: text,
            exitCode: exitCode,
            truncated: truncated ? true : nil
        )
    }

    // MARK: - 辅助方法

    private func getClient() async throws -> BoxMCPClient {
        do {
            return try await BoxMCPClientFactory.getClient()
        } catch let error as BoxMCPError {
            switch error {
            case .noKey:
                throw BoxShellError.noKey
            case .sessionFailed, .toolCallFailed:
                throw BoxShellError.failed(error.localizedDescription)
            case .networkError:
                throw BoxShellError.failed(L10n.string("终端网络不可达"))
            }
        }
    }
}
