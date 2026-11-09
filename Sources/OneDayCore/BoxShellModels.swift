import Foundation

// MARK: - 盒终端契约模型（P9 电脑面·终端段，2026-11-09 冻结）
//
// 契约以 box-shell-contract-20261109.md 为准：POST
// /api/box-bridge/shell {command} → {ok, output,
// exitCode, truncated}。桥以 MCP 长活会话调厂商 shell
// 工具（持久会话、cwd /workspace），命令由用户逐条手输
// 原样透传。三条如实口径钉在本层：① 成败以 exitCode
// 为第一口径（0 成功/非 0 失败），exitCode 缺失才回落
// ok，两者皆缺按失败处理——不许猜成功；② output 为
// 厂商合并输出原文，空输出呈现「（无输出）」占位，不许
// 拿空串冒充执行过了；③ truncated 为真时输出是被截断
// 的，界面必须另行标注，不许静默当完整。

/// POST /shell 请求体：只有命令一条（桥原样透传）
public struct BoxShellRequest: Encodable, Equatable, Sendable {
    public let command: String

    public init(command: String) {
        self.command = command
    }
}

/// POST /shell 回执（容缺解码：exitCode/truncated 桥
/// 给得出才有，output 缺失按空输出处理）
public struct BoxShellResponse: Decodable, Equatable, Sendable {
    public let ok: Bool?
    public let output: String
    public let exitCode: Int?
    public let truncated: Bool?

    public init(
        ok: Bool? = nil, output: String, exitCode: Int? = nil,
        truncated: Bool? = nil
    ) {
        self.ok = ok
        self.output = output
        self.exitCode = exitCode
        self.truncated = truncated
    }

    private enum CodingKeys: String, CodingKey {
        case ok, output, exitCode, truncated
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        ok = try container.decodeIfPresent(Bool.self, forKey: .ok)
        output = try container.decodeIfPresent(String.self, forKey: .output) ?? ""
        exitCode = try container.decodeIfPresent(Int.self, forKey: .exitCode)
        truncated = try container.decodeIfPresent(Bool.self, forKey: .truncated)
    }

    /// 成败判定：exitCode 优先（契约第一口径）；缺失
    /// 回落 ok；两者皆缺＝不成功（不许猜）
    public var succeeded: Bool {
        if let exitCode { return exitCode == 0 }
        return ok ?? false
    }

    /// 输出呈现：原文直出；空输出给占位说明
    public var outputText: String {
        output.isEmpty ? "（无输出）" : output
    }

    /// 是否被桥侧截断（缺失按未截断）
    public var wasTruncated: Bool { truncated == true }
}

/// 命令输入规范化：去首尾空白；空串返回 nil 不发请求
/// （桥侧对空命令回 400，客户端先拦一道）。命令本体
/// 一字不改——不许在客户端拼接或改写用户命令。
public enum BoxShellCommandText {
    public static func normalize(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
