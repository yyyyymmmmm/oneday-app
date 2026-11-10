import Foundation

/// 桥钥匙分权范围（0.32.1，审计 F03/R8）：五桥不再共用
/// 一把全权 Bearer，App 侧按 scope 分项存 Keychain、
/// 各客户端只读自己 scope 的钥。scope 名即钥匙组导入
/// 文本的行标签（bridge-keys.txt 与设置页解析器逐字
/// 对齐），改名须两边同改。
public enum BridgeKeyScope: String, CaseIterable, Equatable, Sendable {
    /// 总览桥（8644）：只读总览/通知
    case overview
    /// oneday 桥（8646）：目标/点子/监测业务读写
    case oneday
    /// write-gate 桥（8643）：记忆/技能审批写
    case writegate
    /// box 桥（8645）：云电脑状态/文件/Shell 执行
    case box
    /// device 桥（8647）：本机设备工具门面
    case device

    /// 设置页逐项状态行的显示名
    public var displayName: String {
        switch self {
        case .overview: return "总览（只读）"
        case .oneday: return "目标 / 点子"
        case .writegate: return "审批（记忆 / 技能）"
        case .box: return "云电脑（Box）"
        case .device: return "本机设备"
        }
    }

    /// 导入文本的行标签（小写英文，与 bridge-keys.txt
    /// 逐字一致）
    public var importLabel: String { rawValue }

    /// 标签归一匹配：大小写不敏感、忽略连字符/下划线
    /// （write-gate / write_gate 都认得），命中返回 scope
    public static func fromImportLabel(_ raw: String) -> BridgeKeyScope? {
        let normalized = raw
            .trimmingCharacters(in: .whitespaces)
            .lowercased()
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: "_", with: "")
        return allCases.first {
            $0.rawValue.replacingOccurrences(of: "-", with: "") == normalized
        }
    }
}

/// 钥匙组导入文本解析（纯函数，设置页与单测共用）。
///
/// 格式（与服务器侧产出的 bridge-keys.txt 逐字对齐）：
/// 每行 `scope: 钥匙值`，冒号半角/全角均可；空行与
/// `#`/`//` 开头的说明行跳过；认不出的行计入
/// ignoredLineCount 如实上报，不许静默吞。同 scope
/// 重复出现时后行覆盖先行（粘贴纠错的自然语义）。
/// 钥值只做首尾空白清洗，清洗后为空的行按未识别计。
public enum BridgeKeyImport {
    public struct Result: Equatable, Sendable {
        public var keys: [BridgeKeyScope: String] = [:]
        public var ignoredLineCount: Int = 0
        public init() {}
    }

    public static func parse(_ text: String) -> Result {
        var result = Result()
        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") || line.hasPrefix("//") {
                continue
            }
            // 首个冒号（半角或全角）分标签与钥值
            let colonIdx = line.firstIndex(where: { $0 == ":" || $0 == "：" })
            guard let colonIdx else {
                result.ignoredLineCount += 1
                continue
            }
            let label = String(line[..<colonIdx])
            let value = String(line[line.index(after: colonIdx)...])
                .trimmingCharacters(in: .whitespaces)
            guard let scope = BridgeKeyScope.fromImportLabel(label),
                  !value.isEmpty else {
                result.ignoredLineCount += 1
                continue
            }
            result.keys[scope] = value
        }
        return result
    }
}
