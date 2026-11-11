import Foundation

/// 代码块轻量高亮（0.36.25）：手写单遍词法扫描，只分
/// 五类——普通／关键词／字符串／注释／数字，克制着色
/// （呈现侧映射：关键词紫、字符串绿、注释灰、数字蓝）。
/// 零第三方依赖（本仓既定姿态，审计 §3 的立项门不夹
/// 带）。覆盖常见语言的关键字面与注释/字符串语法；
/// 不认识的语言只做字符串/注释/数字的通用分词、不猜
/// 关键词。不变式：所有 token 文本拼回恒等于原代码
/// （单测钉死，着色永不吞字改字）。
public enum CodeTokenKind: Equatable {
    case plain
    case keyword
    case string
    case comment
    case number
}

public struct CodeToken: Equatable {
    public var kind: CodeTokenKind
    public var text: String

    public init(kind: CodeTokenKind, text: String) {
        self.kind = kind
        self.text = text
    }
}

public enum CodeHighlight {
    /// 语言名归一：小写＋别名映射（js→javascript 等）；
    /// 空串与纯空白归 nil
    public static func normalizeLanguage(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let value = raw.lowercased()
            .trimmingCharacters(in: .whitespaces)
        guard !value.isEmpty else { return nil }
        switch value {
        case "js", "jsx", "mjs": return "javascript"
        case "ts", "tsx": return "typescript"
        case "py", "python3": return "python"
        case "sh", "bash", "zsh", "shell": return "shell"
        case "c++", "cpp", "cxx", "cc": return "cpp"
        case "objc", "objective-c": return "objectivec"
        case "yml": return "yaml"
        case "rb": return "ruby"
        case "golang": return "go"
        case "rs": return "rust"
        case "kt": return "kotlin"
        case "cs": return "csharp"
        default: return value
        }
    }

    /// §157（2026-11-11）：入口先过解析记忆——键＝归
    /// 一化语言＋代码原文；同代码块再算即查表
    /// （MarkdownParseMemo），纯函数同入同果、输出逐
    /// 字不变；未命中才走 tokensUncached
    public static func tokens(
        code: String, language: String?
    ) -> [CodeToken] {
        guard !code.isEmpty else { return [] }
        let key = normalizeLanguage(language) + "\u{1}" + code
        return MarkdownParseMemos.codeTokens.value(for: key) {
            tokensUncached(code: code, language: language)
        }
    }

    private static func tokensUncached(
        code: String, language: String?
    ) -> [CodeToken] {
        let config = LexConfig(language: normalizeLanguage(language))
        let chars = Array(code)
        var raw: [CodeToken] = []
        var plain = ""
        var index = 0

        func emit(_ kind: CodeTokenKind, _ text: String) {
            if !plain.isEmpty {
                raw.append(CodeToken(kind: .plain, text: plain))
                plain = ""
            }
            if !text.isEmpty {
                raw.append(CodeToken(kind: kind, text: text))
            }
        }

        while index < chars.count {
            let char = chars[index]
            // —— 注释 ——
            if let prefix = config.lineComments.first(where: {
                matches(chars, at: index, prefix: $0)
            }) {
                var end = index
                while end < chars.count, chars[end] != "\n" {
                    end += 1
                }
                emit(.comment, String(chars[index..<end]))
                index = end
                continue
            }
            if config.blockComments,
               matches(chars, at: index, prefix: "/*") {
                var end = index + 2
                var closed = false
                while end + 1 < chars.count + 1 {
                    if end + 1 < chars.count,
                       chars[end] == "*", chars[end + 1] == "/" {
                        end += 2
                        closed = true
                        break
                    }
                    if end >= chars.count { break }
                    end += 1
                }
                if !closed { end = chars.count }
                emit(.comment, String(chars[index..<end]))
                index = end
                continue
            }
            // —— 字符串 ——
            if let stringEnd = scanString(
                chars, at: index, config: config
            ) {
                emit(.string, String(chars[index...stringEnd]))
                index = stringEnd + 1
                continue
            }
            // —— 数字 ——
            if char.isNumber {
                var end = index
                while end < chars.count,
                      chars[end].isNumber || chars[end].isLetter
                        || chars[end] == "." || chars[end] == "_" {
                    end += 1
                }
                emit(.number, String(chars[index..<end]))
                index = end
                continue
            }
            // —— 标识符／关键词 ——
            if char.isLetter || char == "_" || char == "$" {
                var end = index
                while end < chars.count,
                      chars[end].isLetter || chars[end].isNumber
                        || chars[end] == "_" || chars[end] == "$" {
                    end += 1
                }
                let word = String(chars[index..<end])
                let probe = config.caseInsensitiveKeywords
                    ? word.lowercased() : word
                if config.keywords.contains(probe) {
                    emit(.keyword, word)
                } else {
                    plain += word
                }
                index = end
                continue
            }
            plain.append(char)
            index += 1
        }
        if !plain.isEmpty {
            raw.append(CodeToken(kind: .plain, text: plain))
        }
        // 相邻同类合并（呈现侧少建 run）
        var merged: [CodeToken] = []
        for token in raw {
            if let last = merged.last, last.kind == token.kind {
                merged[merged.count - 1].text += token.text
            } else {
                merged.append(token)
            }
        }
        return merged
    }

    private static func matches(
        _ chars: [Character], at index: Int, prefix: String
    ) -> Bool {
        let needle = Array(prefix)
        guard index + needle.count <= chars.count else { return false }
        for offset in needle.indices {
            if chars[index + offset] != needle[offset] { return false }
        }
        return true
    }

    /// 字符串扫描：命中返回闭合引号下标，未命中 nil。
    /// 单行字符串找不到闭合时吃到行尾（流式半截口径：
    /// 先按字符串着色到行尾，闭合到达后自然成整串，
    /// 不改字、不跳版）。Python 三引号与 JS 模板串可
    /// 跨行。
    private static func scanString(
        _ chars: [Character], at index: Int,
        config: LexConfig
    ) -> Int? {
        let char = chars[index]
        // Python 三引号
        if config.tripleStrings,
           index + 2 < chars.count,
           (char == "\"" || char == "'"),
           chars[index + 1] == char, chars[index + 2] == char {
            var end = index + 3
            while end + 2 < chars.count + 1 {
                if end + 2 < chars.count,
                   chars[end] == char, chars[end + 1] == char,
                   chars[end + 2] == char {
                    return end + 2
                }
                if end >= chars.count { return chars.count - 1 }
                end += 1
            }
            return chars.count - 1
        }
        let isQuote = char == "\""
            || (char == "'" && config.singleQuotes)
            || (char == "`" && config.backtickStrings)
        guard isQuote else { return nil }
        let multiline = char == "`"
        var end = index + 1
        while end < chars.count {
            let current = chars[end]
            if current == "\\" {
                end += 2
                continue
            }
            if current == char { return end }
            if current == "\n", !multiline { return end - 1 }
            end += 1
        }
        return chars.count - 1
    }

    // MARK: - 语言配置

    private struct LexConfig {
        var lineComments: [String] = []
        var blockComments = false
        var singleQuotes = true
        var backtickStrings = false
        var tripleStrings = false
        var keywords: Set<String> = []
        var caseInsensitiveKeywords = false

        init(language: String?) {
            switch language {
            case "swift":
                lineComments = ["//"]
                blockComments = true
                singleQuotes = false
                keywords = Self.swiftKeywords
            case "python":
                lineComments = ["#"]
                tripleStrings = true
                keywords = Self.pythonKeywords
            case "javascript":
                lineComments = ["//"]
                blockComments = true
                backtickStrings = true
                keywords = Self.javascriptKeywords
            case "typescript":
                lineComments = ["//"]
                blockComments = true
                backtickStrings = true
                keywords = Self.javascriptKeywords
                    .union(Self.typescriptKeywords)
            case "java", "kotlin", "scala", "csharp":
                lineComments = ["//"]
                blockComments = true
                keywords = Self.javaKeywords
            case "c":
                lineComments = ["//"]
                blockComments = true
                keywords = Self.cKeywords
            case "cpp", "objectivec":
                lineComments = ["//"]
                blockComments = true
                keywords = Self.cKeywords.union(Self.cppKeywords)
            case "go":
                lineComments = ["//"]
                blockComments = true
                backtickStrings = true
                keywords = Self.goKeywords
            case "rust":
                lineComments = ["//"]
                blockComments = true
                singleQuotes = false
                keywords = Self.rustKeywords
            case "shell":
                lineComments = ["#"]
                keywords = Self.shellKeywords
            case "ruby", "perl":
                lineComments = ["#"]
                keywords = Self.rubyKeywords
            case "sql":
                lineComments = ["--"]
                blockComments = true
                keywords = Self.sqlKeywords
                caseInsensitiveKeywords = true
            case "json":
                keywords = ["true", "false", "null"]
                singleQuotes = false
            case "yaml", "toml":
                lineComments = ["#"]
                keywords = ["true", "false", "null"]
            default:
                // 未知语言：只认最通用的注释与字符串
                lineComments = ["//", "#"]
                blockComments = true
            }
        }

        static let swiftKeywords: Set<String> = [
            "let", "var", "func", "class", "struct", "enum",
            "protocol", "extension", "import", "return", "if",
            "else", "for", "while", "do", "catch", "throw",
            "throws", "rethrows", "guard", "switch", "case",
            "default", "break", "continue", "fallthrough",
            "in", "where", "defer", "init", "deinit",
            "typealias", "associatedtype", "private",
            "fileprivate", "public", "internal", "static",
            "final", "override", "weak", "unowned", "lazy",
            "mutating", "nonmutating", "convenience",
            "required", "some", "any", "actor", "async",
            "await", "nil", "true", "false", "self", "Self",
            "super", "is", "as", "try", "inout", "subscript",
            "willSet", "didSet", "get", "set", "indirect",
            "operator", "precedencegroup",
        ]
        static let pythonKeywords: Set<String> = [
            "def", "return", "if", "elif", "else", "for",
            "while", "import", "from", "as", "class", "try",
            "except", "finally", "with", "lambda", "pass",
            "break", "continue", "raise", "global",
            "nonlocal", "assert", "del", "yield", "async",
            "await", "True", "False", "None", "and", "or",
            "not", "in", "is",
        ]
        static let javascriptKeywords: Set<String> = [
            "const", "let", "var", "function", "return",
            "if", "else", "for", "while", "do", "switch",
            "case", "default", "break", "continue", "new",
            "delete", "typeof", "instanceof", "in", "of",
            "class", "extends", "super", "this", "try",
            "catch", "finally", "throw", "async", "await",
            "yield", "static", "get", "set", "true",
            "false", "null", "undefined", "void", "export",
            "import", "from",
        ]
        static let typescriptKeywords: Set<String> = [
            "interface", "type", "enum", "implements",
            "readonly", "abstract", "declare", "namespace",
            "keyof", "infer", "public", "private",
            "protected", "string", "number", "boolean",
            "unknown", "never",
        ]
        static let javaKeywords: Set<String> = [
            "public", "private", "protected", "class",
            "interface", "enum", "extends", "implements",
            "static", "final", "abstract", "void", "int",
            "long", "double", "float", "boolean", "char",
            "byte", "short", "new", "return", "if", "else",
            "for", "while", "do", "switch", "case",
            "default", "break", "continue", "try", "catch",
            "finally", "throw", "throws", "this", "super",
            "import", "package", "true", "false", "null",
            "instanceof", "synchronized", "volatile",
            "transient", "var", "record", "sealed",
        ]
        static let cKeywords: Set<String> = [
            "int", "char", "float", "double", "void", "if",
            "else", "for", "while", "do", "switch", "case",
            "default", "break", "continue", "return",
            "struct", "union", "enum", "typedef", "static",
            "const", "unsigned", "signed", "long", "short",
            "extern", "sizeof", "volatile", "register",
            "goto", "inline",
        ]
        static let cppKeywords: Set<String> = [
            "class", "public", "private", "protected",
            "virtual", "template", "typename", "namespace",
            "using", "new", "delete", "this", "friend",
            "constexpr", "nullptr", "true", "false",
            "override", "operator", "throw", "try", "catch",
            "auto", "concept", "requires",
        ]
        static let goKeywords: Set<String> = [
            "package", "import", "func", "var", "const",
            "type", "struct", "interface", "map", "chan",
            "go", "defer", "return", "if", "else", "for",
            "range", "switch", "case", "default", "break",
            "continue", "select", "fallthrough", "true",
            "false", "nil", "iota", "string", "int", "bool",
            "error", "make", "new", "append", "len", "cap",
        ]
        static let rustKeywords: Set<String> = [
            "fn", "let", "mut", "pub", "struct", "enum",
            "impl", "trait", "for", "in", "loop", "while",
            "if", "else", "match", "return", "break",
            "continue", "const", "static", "type", "where",
            "use", "mod", "crate", "self", "Self", "super",
            "move", "ref", "async", "await", "dyn", "box",
            "true", "false", "unsafe", "extern",
        ]
        static let shellKeywords: Set<String> = [
            "if", "then", "else", "elif", "fi", "for",
            "while", "do", "done", "case", "esac",
            "function", "in", "return", "local", "export",
            "source", "set", "shift", "true", "false",
        ]
        static let rubyKeywords: Set<String> = [
            "def", "end", "class", "module", "if", "elsif",
            "else", "unless", "case", "when", "for",
            "while", "until", "do", "begin", "rescue",
            "ensure", "return", "yield", "break", "next",
            "self", "nil", "true", "false", "require",
            "include", "lambda", "puts",
        ]
        static let sqlKeywords: Set<String> = [
            "select", "from", "where", "insert", "into",
            "values", "update", "delete", "set", "join",
            "left", "right", "inner", "outer", "on",
            "group", "by", "order", "limit", "offset",
            "create", "table", "drop", "primary", "key",
            "not", "null", "and", "or", "as", "distinct",
            "union", "all", "between", "like", "in", "is",
            "having", "count",
        ]
    }
}
