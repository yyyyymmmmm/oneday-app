import ProjectDescription

let iOS26 = DeploymentTargets.iOS("26.0")

let project = Project(
    name: "OneDay",
    organizationName: "site.didichou",
    settings: .settings(base: [
        "SWIFT_VERSION": "6.0",
        "TARGETED_DEVICE_FAMILY": "1",
        "MARKETING_VERSION": "0.3.0",
        "CURRENT_PROJECT_VERSION": "15",
    ]),
    targets: [
        .target(
            name: "OneDayCore",
            destinations: .iOS,
            product: .framework,
            bundleId: "site.didichou.oneday.core",
            deploymentTargets: iOS26,
            infoPlist: .default,
            sources: ["Sources/OneDayCore/**"],
            dependencies: []
        ),
        .target(
            name: "OneDayDesign",
            destinations: .iOS,
            product: .framework,
            bundleId: "site.didichou.oneday.design",
            deploymentTargets: iOS26,
            infoPlist: .default,
            sources: ["Sources/OneDayDesign/**"],
            dependencies: [.target(name: "OneDayCore")]
        ),
        .target(
            name: "OneDayApp",
            destinations: .iOS,
            product: .app,
            bundleId: "site.didichou.oneday",
            deploymentTargets: iOS26,
            infoPlist: .extendingDefault(with: [
                "CFBundleDisplayName": "OneDay",
                // 版本号直写 Info.plist（沿礼记 v4.4 实证口径）：Tuist 默认
                // 模板不把工程设置的 MARKETING_VERSION 展开进 plist，
                // 只写字面量才进包。
                "CFBundleShortVersionString": "0.3.0",
                "CFBundleVersion": "15",
                "ITSAppUsesNonExemptEncryption": false,
                "UILaunchScreen": ["UIColorName": "LaunchBackground"],
                // 自托管场景：允许连接局域网内的自建服务器（http）。
                // 公网服务器仍走 https；上架前如需收紧在此复核
                // （取舍记录见 docs/M1-NOTES.md）。
                "NSAppTransportSecurity": [
                    "NSAllowsLocalNetworking": true,
                ],
            ]),
            sources: ["Sources/OneDayApp/**"],
            resources: ["App/Resources/**"],
            dependencies: [
                .target(name: "OneDayCore"),
                .target(name: "OneDayDesign"),
            ]
        ),
        .target(
            name: "OneDayCoreTests",
            destinations: .iOS,
            product: .unitTests,
            bundleId: "site.didichou.oneday.core.tests",
            deploymentTargets: iOS26,
            infoPlist: .default,
            sources: ["Tests/OneDayCoreTests/**"],
            dependencies: [.target(name: "OneDayCore")]
        ),
    ],
    schemes: [
        .scheme(
            name: "OneDayApp",
            shared: true,
            buildAction: .buildAction(targets: ["OneDayApp"]),
            testAction: .targets(["OneDayCoreTests"]),
            runAction: .runAction(executable: "OneDayApp")
        ),
    ]
)
