import Foundation
import OneDayCore

/// 盒文件错误：与各桥同分法——「没有钥匙」「钥匙被拒
/// （401）」是桥未连接；列表端点 404 是「电脑文件尚未
/// 开通」（桥还没部署文件面）；其余失败给人话、不混报。
enum BoxFilesError: Error, Sendable, Equatable {
    case noKey
    case unauthorized
    case notAvailable
    case failed(String)
}

/// Box 文件客户端（A1 甩桥，MCP 直连）：
///
/// 原桥端点（已退役）：
/// - GET /api/box-bridge/files → list_dir MCP 工具
/// - GET /api/box-bridge/files/read → read_file MCP 工具
///
/// 公开 API 不变（list/fileData 签名保持），内部改为直连
/// Box MCP。文件路径为相对 /workspace 的相对路径（"" 为根）。
///
/// list_dir 返回纯文本（对齐 box_bridge.py:476-596）：
/// 格式 `<path>:\n` + 每行 `name/` 或 `name  (N bytes)`
final class BoxFilesClient: @unchecked Sendable {
    init() {}

    /// 列出目录（对齐 box_bridge.py:533-596）
    func list(
        config: ServerConfig, path: String?
    ) async throws -> FilesListing {
        let client = try await getClient()

        // 构建绝对路径
        let relPath = path?.trimmingCharacters(in: CharacterSet(charactersIn: "/")) ?? ""
        let absPath = relPath.isEmpty ? "/workspace" : "/workspace/\(relPath)"

        let result = try await client.callTool(
            name: "list_dir",
            arguments: ["path": absPath],
            timeout: 60
        )

        if result.isError == true {
            let errorText = mcpErrorText(result)
            if errorText.contains("No such file or directory") {
                throw BoxFilesError.notAvailable
            }
            throw BoxFilesError.failed(errorText)
        }

        // 解析纯文本目录列表（box_bridge.py:543-596）
        let texts = mcpTexts(result)
        guard let text = texts.first else {
            throw BoxFilesError.failed(L10n.string("电脑文件列表返回格式无法识别"))
        }

        return try parseDirectoryListing(text: text, requestedPath: relPath)
    }

    /// 读取文件（对齐 box_bridge.py:606-653，分页读取并剥离行号前缀）
    func fileData(
        config: ServerConfig, path: String
    ) async throws -> Data {
        let client = try await getClient()

        let relPath = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let absPath = "/workspace/\(relPath)"

        // 分页读取（每页 2000 行）
        var lines: [String] = []
        var offset = 1
        let pageSize = 2000
        let maxLines = 200000

        while true {
            let result = try await client.callTool(
                name: "read_file",
                arguments: ["path": absPath, "offset": offset, "limit": pageSize],
                timeout: 60
            )

            if result.isError == true {
                let errorText = mcpErrorText(result)
                if errorText.contains("No such file or directory") {
                    throw BoxFilesError.failed(L10n.string("这个文件已不存在。"))
                }
                if errorText.contains("Is a directory") {
                    throw BoxFilesError.failed(L10n.string("这是一个目录，不能作为文件读取。"))
                }
                throw BoxFilesError.failed(errorText)
            }

            let texts = mcpTexts(result)
            guard let text = texts.first else { break }

            let body = text.trimmingCharacters(in: .newlines)

            // 检查是否到达文件末尾
            if body.contains("has") && body.contains("lines; nothing at offset") {
                break
            }

            // 检查是否是二进制文件
            if offset == 1 && body.contains("is a binary file of") {
                // 二进制文件：回退用 shell base64 读取
                return try await readFileBytesShell(client: client, absPath: absPath)
            }

            // 解析行（剥离行号前缀 `  \d+\t`）
            let rawLines = body.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
            var hasMore = false

            for (index, line) in rawLines.enumerated() {
                // 检查是否是分页尾行
                if line.hasPrefix("[showing lines") && line.hasSuffix("]") {
                    hasMore = true
                    continue
                }

                // 剥离行号前缀
                if let range = line.range(of: #"^\s*\d+\t"#, options: .regularExpression) {
                    let content = String(line[range.upperBound...])
                    lines.append(content)
                } else {
                    // 无行号前缀的行直接保留
                    lines.append(line)
                }
            }

            if lines.count > maxLines {
                throw BoxFilesError.failed(L10n.string("文件过大，无法读取"))
            }

            if !hasMore || rawLines.count < pageSize {
                break
            }

            offset += pageSize
        }

        // 拼接所有行
        let content = lines.joined(separator: "\n")
        return content.data(using: .utf8) ?? Data()
    }

    // MARK: - 辅助方法

    private func getClient() async throws -> BoxMCPClient {
        do {
            return try await BoxMCPClientFactory.getClient()
        } catch let error as BoxMCPError {
            switch error {
            case .noKey:
                throw BoxFilesError.noKey
            case .sessionFailed, .toolCallFailed:
                throw BoxFilesError.failed(error.localizedDescription)
            case .networkError:
                throw BoxFilesError.failed(L10n.string("电脑文件网络不可达"))
            }
        }
    }

    /// 解析目录列表文本（对齐 box_bridge.py:543-596）
    private func parseDirectoryListing(text: String, requestedPath: String) throws -> FilesListing {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)

        guard let headerLine = lines.first, headerLine.hasSuffix(":") else {
            throw BoxFilesError.failed(L10n.string("电脑文件列表返回格式无法识别"))
        }

        var entries: [[String: Any]] = []
        let sizePattern = #"^(.*)  \((\d+) bytes\)$"#

        for line in lines.dropFirst() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed == "." || trimmed == ".." {
                continue
            }

            if trimmed.hasSuffix("/") {
                // 目录
                let name = String(trimmed.dropLast())
                let entryPath = requestedPath.isEmpty ? name : "\(requestedPath)/\(name)"
                entries.append([
                    "name": name,
                    "path": entryPath,
                    "isDirectory": true
                ])
            } else {
                // 文件
                var name = trimmed
                var size: Int64?

                if let regex = try? NSRegularExpression(pattern: sizePattern),
                   let match = regex.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)) {
                    if let nameRange = Range(match.range(at: 1), in: trimmed),
                       let sizeRange = Range(match.range(at: 2), in: trimmed) {
                        name = String(trimmed[nameRange])
                        size = Int64(trimmed[sizeRange])
                    }
                }

                let entryPath = requestedPath.isEmpty ? name : "\(requestedPath)/\(name)"
                var entry: [String: Any] = [
                    "name": name,
                    "path": entryPath,
                    "isDirectory": false
                ]
                if let size = size {
                    entry["size"] = size
                }
                if let mimeType = guessMimeType(name) {
                    entry["mimeType"] = mimeType
                }
                entries.append(entry)
            }
        }

        let parent = requestedPath.isEmpty ? nil : (requestedPath.contains("/") ? String(requestedPath[..<requestedPath.lastIndex(of: "/")!]) : "")

        // 构造 JSON 并解码为 FilesListing
        var dict: [String: Any] = [
            "path": requestedPath,
            "entries": entries,
            "root": "/workspace",
            "locked_root": "/workspace",
            "can_change_path": false
        ]
        if let parent = parent {
            dict["parent"] = parent
        }

        let jsonData = try JSONSerialization.data(withJSONObject: dict)
        return try JSONDecoder().decode(FilesListing.self, from: jsonData)
    }

    /// 通过 shell base64 读取二进制文件（对齐 box_bridge.py:656-682）
    private func readFileBytesShell(client: BoxMCPClient, absPath: String) async throws -> Data {
        let escapedPath = absPath.replacingOccurrences(of: "'", with: "'\\''")
        let command = "base64 -w 0 -- '\(escapedPath)'"

        let result = try await client.callTool(
            name: "shell",
            arguments: ["command": command],
            timeout: 120
        )

        if result.isError == true {
            throw BoxFilesError.failed(mcpErrorText(result))
        }

        let texts = mcpTexts(result)
        guard let text = texts.first else {
            throw BoxFilesError.failed(L10n.string("文件读取失败"))
        }

        // 剥离 [exit status N] 尾行
        let body = text.replacingOccurrences(of: #"\n?\[exit status \d+\]\s*$"#, with: "", options: .regularExpression)

        guard let data = Data(base64Encoded: body.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            throw BoxFilesError.failed(L10n.string("文件内容解码失败"))
        }

        return data
    }

    private func guessMimeType(_ filename: String) -> String? {
        let ext = (filename as NSString).pathExtension.lowercased()
        let mimeTypes: [String: String] = [
            "txt": "text/plain",
            "json": "application/json",
            "xml": "application/xml",
            "html": "text/html",
            "css": "text/css",
            "js": "application/javascript",
            "png": "image/png",
            "jpg": "image/jpeg",
            "jpeg": "image/jpeg",
            "gif": "image/gif",
            "pdf": "application/pdf",
            "zip": "application/zip"
        ]
        return mimeTypes[ext]
    }
}
