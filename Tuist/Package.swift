// swift-tools-version: 5.9
import PackageDescription

#if TUIST
import ProjectDescription

let packageSettings = PackageSettings(
    // 移植 1.5：EventSource 同时被 OneDayCore 与 MCP
    // （swift-sdk）依赖，显式指定为动态库，避免静态
    // 符号重复链接警告（随封存分支原形态落）。
    productTypes: [
        "EventSource": .framework,
    ]
)
#endif

// 外部 SPM 依赖总账（Tuist 4 口径：依赖声明在本文件、
// Project.swift 侧以 .external(name:) 引用；版本钉死、
// 解析结果随仓入库，升级须单独成包记账）。
// §417（#13 Markdown 换底）：swiftlang/swift-markdown
// 解析核，Apache-2.0；钉版 0.6.0（2026-11-23 最新稳定版）。
// §418（#23 图片管线换底）：kean/Nuke 图片管线（核心＋
// NukeUI），MIT；钉版 13.2.3（2026-11-08 发布，13.2 线
// 最新稳定 patch；14.0 仅 beta 不取）。
// 移植 1.3：kishikawakatsumi/KeychainAccess 钥匙串安全
// 存取，MIT；钉版 4.2.2。
// 移植 1.4：raspu/Highlightr 代码语法高亮（highlight.js
// 185+ 语言），MIT；钉版 2.3.0。
// 移植 1.5：mattt/EventSource 标准 SSE 流式客户端，MIT；
// 钉版 1.6.0（与官方 MCP swift-sdk 共用同一依赖无冲突）。
// 移植 1.6：modelcontextprotocol/swift-sdk 官方 MCP
// Swift SDK，MIT；钉版 0.12.1。
// 注：Exyte 钉不在本版范围（0.50.104 组版单明示勿带入）。
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
        )
    ]
)
