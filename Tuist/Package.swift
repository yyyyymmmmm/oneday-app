// swift-tools-version: 5.9
import PackageDescription

#if TUIST
import ProjectDescription

let packageSettings = PackageSettings(
    productTypes: [:]
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
        )
    ]
)
