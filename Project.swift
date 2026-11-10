import ProjectDescription

let iOS26 = DeploymentTargets.iOS("26.0")

let project = Project(
    name: "OneDay",
    organizationName: "site.didichou",
    settings: .settings(base: [
        "SWIFT_VERSION": "6.0",
        "TARGETED_DEVICE_FAMILY": "1",
        "MARKETING_VERSION": "0.36.13",
        "CURRENT_PROJECT_VERSION": "80",
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
                "CFBundleShortVersionString": "0.36.13",
                "CFBundleVersion": "80",
                "ITSAppUsesNonExemptEncryption": false,
                "UILaunchScreen": ["UIColorName": "LaunchBackground"],
                // 自托管场景：允许连接局域网内的自建服务器（http）。
                // 公网服务器仍走 https；上架前如需收紧在此复核
                // （取舍记录见 docs/M1-NOTES.md）。
                "NSAppTransportSecurity": [
                    "NSAllowsLocalNetworking": true,
                ],
                // 本机连接器批一（0.34.0，设计档 §6.4）：
                // 逐件用到才申请，文案说清「被智能体问
                // 到时现读现回、服务器不保存」；健康/
                // 家庭（批二）与蓝牙（已决不做）的键不在
                // 此列，entitlements 待签名权益核查后另加
                "NSCalendarsFullAccessUsageDescription": "OneDay 需要读取你的日历：安排只在这台手机上查看；你开启智能体调用后，智能体被问到时才现读现回，服务器不保存日程内容。",
                "NSRemindersFullAccessUsageDescription": "OneDay 需要读取你的提醒事项：待办只在这台手机上查看；你开启智能体调用后，智能体被问到时才现读现回，服务器不保存提醒内容。",
                "NSContactsUsageDescription": "OneDay 需要按关键词查询你的通讯录：搜索在手机上完成、只有命中条目会显示；你开启智能体调用后，被问到时才现查现回，通讯录全量从不离开手机。",
                // 图片查看器保存（0.36.4）：只在用户在查
                // 看器里点「下载」时申请 addOnly、只保存
                // 用户选中的那一张；不读相册、不作其他用
                "NSPhotoLibraryAddUsageDescription": "OneDay 需要把图片存入你的相册：只在你在图片查看器里点「下载」时保存你选中的那一张图片，不会读取你的相册。",
                // 语音输入（0.36.6）：端上识别——只在用
                // 户点麦克风时申请；文案说清录音只在本
                // 机处理、不出手机（规格 §3.4 定版文案）
                "NSMicrophoneUsageDescription": "OneDay 需要使用麦克风，把你说的话转成文字填入输入框；录音只在本机处理，不上传服务器。",
                "NSSpeechRecognitionUsageDescription": "OneDay 使用语音识别把你的话转成文字；识别在你的 iPhone 本机完成，录音不会离开手机。",
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
            dependencies: [
                .target(name: "OneDayCore"),
                .target(name: "OneDayDesign"),
            ]
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
