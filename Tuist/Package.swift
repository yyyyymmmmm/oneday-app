// swift-tools-version: 5.9
import PackageDescription

#if TUIST
import ProjectDescription

let packageSettings = PackageSettings(
    // EventSource 同时被 OneDayCore 与 modelcontextprotocol/swift-sdk 依赖，
    // 显式指定为动态库避免静态符号重复链接警告（#22）。
    productTypes: [
        "EventSource": .framework,
    ]
)
#endif

// 外部 SPM 依赖总账（Tuist 4 口径：依赖声明在本文件、
// Project.swift 侧以 .external(name:) 引用；版本钉死、
// Tuist/Package.resolved 随仓入库，升级须单独成包记账）。
// - swiftlang/swift-markdown 0.6.0        : Markdown AST 解析核
// - kean/Nuke 13.2.3                      : 图片加载与缓存管线（Nuke + NukeUI）
// - kishikawakatsumi/KeychainAccess 4.2.2 : 钥匙串安全存取（#20）
// - raspu/Highlightr 2.3.0                : 185+ 语言代码语法高亮（#21）
// - mattt/EventSource 1.6.0               : RFC 8895 标准 SSE 流式解析（#22）
// - modelcontextprotocol/swift-sdk 0.12.1 : 官方 MCP Swift SDK（#23）
let package = Package(
    name: "OneDay",
    dependencies: [
        .package(
            url: "https://github.com/swiftlang/swift-markdown.git",
            exact: "0.6.0"
        ),
        .package(
            url: "https://github.com/kean/Nuke.git",
            exact: "13.2.3"
        ),
        .package(
            url: "https://github.com/kishikawakatsumi/KeychainAccess.git",
            exact: "4.2.2"
        ),
        .package(
            url: "https://github.com/raspu/Highlightr.git",
            exact: "2.3.0"
        ),
        .package(
            url: "https://github.com/mattt/EventSource.git",
            exact: "1.6.0"
        ),
        .package(
            url: "https://github.com/modelcontextprotocol/swift-sdk.git",
            exact: "0.12.1"
        ),
    ]
)
