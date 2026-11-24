import Compression
import Foundation

/// 智能体成包（台账 165，DESIGN §393）：Hermes 档
/// 案导出包（tar.gz）的 App 侧纯逻辑——包清单解
/// 析（装前预览的真读口）、导出文件名推断、导入
/// 名校验、装包路径口径。
///
/// 背景口径：上游导出/导入只换路径不换字节
/// （hermes_cli/web_routers/profiles.py 源码明言
/// "Paths are exchanged, not bytes"），包离机与
/// 跨机装包的字节流由文件面既有端点组合：下载
/// GET /api/files/download、上传 POST /api/files
/// /upload（托管根锁 HERMES_HOME，导出默认落点
/// profile-exports/ 在根内）。本文件只管包本体
/// 与名字口径，不碰网络。
public enum ProfilePackage {

    /// 包清单（装前预览口）：全部字段来自真解
    /// 包头走读，不是文件名猜测；解不开回 nil，
    /// 呈现层降级走文件名推断、不假装读过包。
    public struct Manifest: Equatable, Sendable {
        /// 包内顶层目录名＝档案名（上游 import
        /// 以 archive root 推断档案名，同口径）
        public let profileName: String
        /// 全部条目数（含目录）
        public let entryCount: Int
        /// 文件条目数（不含目录）
        public let fileCount: Int
        /// 文件内容总字节（未压缩）
        public let totalFileBytes: Int64
        /// 档案根下是否有人设文件 SOUL.md
        public let hasSoul: Bool
        /// 档案根下是否有 config.yaml
        public let hasConfig: Bool
        /// 条目名预览（包内原序，上限见
        /// previewLimit）
        public let previewEntries: [String]

        public init(
            profileName: String, entryCount: Int,
            fileCount: Int, totalFileBytes: Int64,
            hasSoul: Bool, hasConfig: Bool,
            previewEntries: [String]
        ) {
            self.profileName = profileName
            self.entryCount = entryCount
            self.fileCount = fileCount
            self.totalFileBytes = totalFileBytes
            self.hasSoul = hasSoul
            self.hasConfig = hasConfig
            self.previewEntries = previewEntries
        }
    }

    /// 解压上限（防坏包/炸弹包把内存打满）：
    /// 档案包是配置＋技能文本，100MB 已极宽
    public static let maxUncompressedBytes = 100 * 1024 * 1024

    // MARK: - 清单解析（gzip + ustar 走读）

    /// gzip（RFC 1952）解压：剥 10 字节头与
    /// 8 字节尾（CRC32＋ISIZE），中段是 raw
    /// deflate（RFC 1951），用 Compression 框
    /// 架 COMPRESSION_ZLIB 解（该算法在本框架
    /// 里即 raw deflate，社区通行 gzip 解法）。
    /// 头内 FEXTRA/FNAME/FCOMMENT 可选字段按
    /// 规范跳过；格式不对或超上限回 nil。
    public static func gunzip(_ data: Data) -> Data? {
        guard data.count > 18,
              data[0] == 0x1F, data[1] == 0x8B,
              data[2] == 0x08
        else { return nil }
        let flags = data[3]
        var cursor = 10
        if flags & 0x04 != 0 { // FEXTRA
            guard cursor + 2 <= data.count else { return nil }
            let xlen = Int(data[cursor])
                | Int(data[cursor + 1]) << 8
            cursor += 2 + xlen
        }
        if flags & 0x08 != 0 { // FNAME
            while cursor < data.count, data[cursor] != 0 {
                cursor += 1
            }
            cursor += 1
        }
        if flags & 0x10 != 0 { // FCOMMENT
            while cursor < data.count, data[cursor] != 0 {
                cursor += 1
            }
            cursor += 1
        }
        if flags & 0x02 != 0 { // FHCRC
            cursor += 2
        }
        guard cursor < data.count - 8 else { return nil }
        let body = data[cursor..<(data.count - 8)]
        return inflate(Data(body))
    }

    /// raw deflate 解压（流式，带上限）
    public static func inflate(_ data: Data) -> Data? {
        let streamPointer = UnsafeMutablePointer<
            compression_stream
        >.allocate(capacity: 1)
        var status = compression_stream_init(
            streamPointer, COMPRESSION_STREAM_DECODE,
            COMPRESSION_ZLIB
        )
        guard status == COMPRESSION_STATUS_OK else {
            streamPointer.deallocate()
            return nil
        }
        defer {
            compression_stream_destroy(streamPointer)
            streamPointer.deallocate()
        }
        var output = Data()
        let chunkSize = 64 * 1024
        var chunk = [UInt8](repeating: 0, count: chunkSize)
        return data.withUnsafeBytes { raw -> Data? in
            guard let base = raw.baseAddress else { return nil }
            streamPointer.pointee.src_ptr =
                base.assumingMemoryBound(to: UInt8.self)
            streamPointer.pointee.src_size = data.count
            while true {
                let produced: Int = chunk
                    .withUnsafeMutableBufferPointer { buf in
                        streamPointer.pointee.dst_ptr =
                            buf.baseAddress!
                        streamPointer.pointee.dst_size = chunkSize
                        status = compression_stream_process(
                            streamPointer, 0
                        )
                        return chunkSize
                            - streamPointer.pointee.dst_size
                    }
                if produced > 0 {
                    output.append(
                        contentsOf: chunk.prefix(produced)
                    )
                }
                if output.count > maxUncompressedBytes {
                    return nil
                }
                switch status {
                case COMPRESSION_STATUS_OK:
                    if streamPointer.pointee.src_size == 0,
                       streamPointer.pointee.dst_size != 0 {
                        // 输入耗尽却没到流尾＝截断
                        return nil
                    }
                case COMPRESSION_STATUS_END:
                    return output
                default:
                    return nil
                }
            }
        }
    }

    /// tar（ustar）头走读：逐 512 字节头块读
    /// 名/大小/类型，长名走 GNU 'L' 扩展与
    /// ustar prefix 拼接；只读头不读内容（按
    /// 大小跳块）。顶层目录必须恰一个（与上
    /// 游 import 的 archive_root 口径一致），
    /// 否则回 nil（呈现层按坏包处理）。
    public static func manifest(
        tarGz data: Data, previewLimit: Int = 20
    ) -> Manifest? {
        guard let tar = gunzip(data) else { return nil }
        var offset = 0
        var topLevel: String?
        var entryCount = 0
        var fileCount = 0
        var totalBytes: Int64 = 0
        var hasSoul = false
        var hasConfig = false
        var preview: [String] = []
        var pendingLongName: String?
        while offset + 512 <= tar.count {
            let header = tar[offset..<(offset + 512)]
            if header.allSatisfy({ $0 == 0 }) { break }
            guard let nameField = tarString(header, 0, 100)
            else { return nil }
            let prefix = tarString(header, 345, 155) ?? ""
            var name = nameField
            if let pendingLongName {
                name = pendingLongName
            } else if !prefix.isEmpty {
                name = prefix + "/" + nameField
            }
            pendingLongName = nil
            guard let size = tarOctal(header, 124, 12)
            else { return nil }
            let typeFlag = header[header.startIndex + 156]
            offset += 512
            if typeFlag == 0x4C { // 'L' GNU 长名
                let end = min(offset + Int(size), tar.count)
                let content = tar[offset..<end]
                pendingLongName = String(
                    bytes: content.prefix(while: { $0 != 0 }),
                    encoding: .utf8
                )
                offset += tarPadded(size)
                continue
            }
            if typeFlag == 0x78 { // 'x' pax 扩展头：跳过
                offset += tarPadded(size)
                continue
            }
            let isDirectory = typeFlag == 0x35 // '5'
                || name.hasSuffix("/")
            let cleanName = name.hasSuffix("/")
                ? String(name.dropLast()) : name
            guard !cleanName.isEmpty else {
                offset += tarPadded(size)
                continue
            }
            let top = cleanName.split(
                separator: "/", maxSplits: 1
            ).first.map(String.init) ?? cleanName
            if let topLevel {
                guard top == topLevel else { return nil }
            } else {
                topLevel = top
            }
            entryCount += 1
            if preview.count < previewLimit {
                preview.append(cleanName)
            }
            if !isDirectory {
                fileCount += 1
                totalBytes += size
                if cleanName == top + "/SOUL.md" {
                    hasSoul = true
                }
                if cleanName == top + "/config.yaml" {
                    hasConfig = true
                }
            }
            offset += tarPadded(size)
        }
        guard let topLevel, entryCount > 0 else {
            return nil
        }
        return Manifest(
            profileName: topLevel,
            entryCount: entryCount,
            fileCount: fileCount,
            totalFileBytes: totalBytes,
            hasSoul: hasSoul, hasConfig: hasConfig,
            previewEntries: preview
        )
    }

    private static func tarPadded(_ size: Int64) -> Int {
        let s = Int(size)
        return ((s + 511) / 512) * 512
    }

    private static func tarString(
        _ header: Data.SubSequence, _ start: Int,
        _ length: Int
    ) -> String? {
        let lo = header.startIndex + start
        let slice = header[lo..<(lo + length)]
        let bytes = slice.prefix(while: { $0 != 0 })
        return String(bytes: bytes, encoding: .utf8)
    }

    private static func tarOctal(
        _ header: Data.SubSequence, _ start: Int,
        _ length: Int
    ) -> Int64? {
        let lo = header.startIndex + start
        let slice = header[lo..<(lo + length)]
        // base-256 编码（首字节高位置位）只出现
        // 在超大文件，本包口径不支持、判坏包
        if let first = slice.first, first & 0x80 != 0 {
            return nil
        }
        let text = String(
            bytes: slice, encoding: .ascii
        )?.trimmingCharacters(
            in: CharacterSet(charactersIn: " \0")
        ) ?? ""
        if text.isEmpty { return 0 }
        return Int64(text, radix: 8)
    }

    // MARK: - 文件名推断与导入名校验

    /// 上游导出文件名口径：<档案名>-%Y%m%d
    /// -%H%M%S.tar.gz（hermes_cli/profiles.py
    /// get_profile_export_path）。剥扩展名与
    /// 时间戳后缀推断原档案名；推断不出（空
    /// 名）回 nil。仅作导入名预填，权威名字
    /// 以包清单 profileName 为准。
    public static func inferredName(
        fromFileName fileName: String
    ) -> String? {
        var base = (fileName as NSString).lastPathComponent
        for ext in [".tar.gz", ".tgz", ".tar"] {
            if base.lowercased().hasSuffix(ext) {
                base = String(base.dropLast(ext.count))
                break
            }
        }
        // -%Y%m%d-%H%M%S（8 位 - 6 位纯数字）；
        // 空段不省（名以 - 起头时首段为空、仍要
        // 能识别出只剩时间戳的无名形态）
        let parts = base.split(
            separator: "-", omittingEmptySubsequences: false
        )
        if parts.count >= 3 {
            let tail = parts.suffix(2)
            if tail.allSatisfy({
                $0.allSatisfy(\.isNumber)
            }), tail.first?.count == 8,
               tail.last?.count == 6 {
                base = parts.dropLast(2)
                    .joined(separator: "-")
            }
        }
        let trimmed = base.trimmingCharacters(
            in: .whitespaces
        )
        return trimmed.isEmpty ? nil : trimmed
    }

    public enum ImportNameVerdict: Equatable, Sendable {
        case ok
        case empty
        /// default 是内置根档案，上游 import 明拒
        case reservedDefault
        /// 与目标服务器现有档案同名，上游会拒
        /// （FileExistsError），客户端先拦
        case alreadyExists
    }

    public static func importNameVerdict(
        _ name: String, existingNames: [String]
    ) -> ImportNameVerdict {
        let trimmed = name.trimmingCharacters(
            in: .whitespaces
        )
        if trimmed.isEmpty { return .empty }
        if trimmed == "default" { return .reservedDefault }
        if existingNames.contains(trimmed) {
            return .alreadyExists
        }
        return .ok
    }

    // MARK: - 装包路径口径

    /// 导出目录（托管根内相对路径）：上游导
    /// 出默认落点同名目录，装包上传亦落此处，
    /// 与导出产物同位、文件面里互相可见。
    public static let exportsDirectory = "profile-exports"

    /// 上传目标（相对托管根）：文件名只取末
    /// 段，防选包名带路径穿越
    public static func uploadRelativePath(
        fileName: String
    ) -> String {
        let base = (fileName as NSString).lastPathComponent
        return "\(exportsDirectory)/\(base)"
    }
}
