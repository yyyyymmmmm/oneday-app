import Foundation

/// 文件真发送拼装（0.36.29，契约实测冻结
/// file-upload-contract-20261111）：待发文件先经
/// 9119 会话通道 POST /api/files/upload 写进托管根
/// 的 attachments/ 目录，发送 run 时在 input 文本尾
/// 逐个拼 `@file:<回执绝对路径>`，网关入站展开
/// （文本全文内联、二进制给路径块供智能体自取）。
/// 本枚举只管纯拼装：落点相对路径、data_url、
/// @file 引用串与文本尾拼接；网络动作在 App 层。
public enum FileSendAssembly {
    /// 服务端落点目录（托管根下；网关缓存挂载清单
    /// 内，沙盒/远程后端可达——契约报告正道口径）
    public static let uploadDirectory = "attachments"

    /// 上传相对路径：attachments/<文件名>（重名由
    /// overwrite=true 覆盖语义承接，契约实测口径）。
    /// 文件名取基名、去首尾空白；含路径分隔的输入
    /// 只取末段，防把目录结构带进落点
    public static func uploadPath(fileName: String) -> String {
        let base = (fileName as NSString).lastPathComponent
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return "\(uploadDirectory)/\(base)"
    }

    /// 上传请求 data_url（MIME 按扩展名推断，与文件
    /// 页上传同走 FileBrowserLogic 单点，不另起口径）
    public static func dataURL(fileName: String, data: Data) -> String {
        FileBrowserLogic.makeDataURL(data: data, fileName: fileName)
    }

    /// `@file:` 引用值：路径含空格/括号时按网关
    /// `_format_ref_value` 规则以双引号包裹，其余
    /// 直写（App 生成路径通常无空格）
    public static func fileRef(serverPath: String) -> String {
        if serverPath.contains(" ")
            || serverPath.contains("(")
            || serverPath.contains(")") {
            return "@file:\"\(serverPath)\""
        }
        return "@file:\(serverPath)"
    }

    /// input 文本尾拼装：正文之后逐个文件各占一行
    /// `@file:` 引用，顺序即待发顺序；正文为空（只
    /// 发文件）时引用自成全文、不留领头空行
    public static func appendingFileRefs(
        to text: String, serverPaths: [String]
    ) -> String {
        guard !serverPaths.isEmpty else { return text }
        let refs = serverPaths.map(fileRef)
            .joined(separator: "\n")
        if text.isEmpty { return refs }
        return text + "\n" + refs
    }

    /// 尾条消息拼装：run 的 input 即尾条 user 消息
    /// 文本（契约拼装口径），引用只拼本轮尾条、不
    /// 进本地落盘条目与历史重放；多模态尾条（带图）
    /// 拼进文本部分、图片部分原样保留
    public static func appendingFileRefs(
        to message: ChatMessage, serverPaths: [String]
    ) -> ChatMessage {
        guard !serverPaths.isEmpty else { return message }
        let newText = appendingFileRefs(
            to: message.content, serverPaths: serverPaths
        )
        if let parts = message.parts {
            let urls = parts.compactMap { part -> String? in
                if case .imageURL(let url) = part { return url }
                return nil
            }
            return ChatMessage(
                role: message.role, text: newText,
                imageDataURLs: urls
            )
        }
        return ChatMessage(role: message.role, content: newText)
    }
}

/// POST /api/files/upload 回执（契约实测形态）：
/// {"ok":true,"entry":{…WorkspaceFileEntry…},
///  "path":"/opt/data/attachments/<文件名>",…}
/// 发送拼装只认 entry.path（绝对路径）；entry 缺失
/// 时以顶层 path 兜底，两处皆无即回执不合格
public struct ManagedFileUploadReceipt: Decodable, Sendable {
    public let ok: Bool?
    public let entry: WorkspaceFileEntry?
    public let path: String?

    /// 演示态/拼装用直构（解码路径外）
    public init(
        ok: Bool?, entry: WorkspaceFileEntry?, path: String?
    ) {
        self.ok = ok
        self.entry = entry
        self.path = path
    }

    /// 拼装用绝对路径（entry 优先、顶层兜底）
    public var serverPath: String? {
        entry?.path ?? path
    }
}
