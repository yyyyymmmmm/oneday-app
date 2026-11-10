import ProjectDescription

let iOS26 = DeploymentTargets.iOS("26.0")

let project = Project(
    name: "OneDay",
    organizationName: "site.didichou",
    settings: .settings(base: [
        "SWIFT_VERSION": "6.0",
        "TARGETED_DEVICE_FAMILY": "1",
        "MARKETING_VERSION": "0.42.1",
        "CURRENT_PROJECT_VERSION": "106",
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
                "CFBundleShortVersionString": "0.42.1",
                "CFBundleVersion": "106",
                "ITSAppUsesNonExemptEncryption": false,
                "UILaunchScreen": ["UIColorName": "LaunchBackground"],
                // 自托管场景：允许连接局域网内的自建服务器（http）。
                // 公网服务器仍走 https；上架前如需收紧在此复核
                // （取舍记录见 docs/M1-NOTES.md）。
                "NSAppTransportSecurity": [
                    "NSAllowsLocalNetworking": true,
                ],
                // 本机连接器批一（0.34.0，设计档 §6.4；
                // 0.36.14 同步制修订）：逐件用到才申请；
                // 文案两面说清——现读现回仍在；在连接
                // 器详情页亲手开启「数据同步」后，才会
                // 把最小字段的副本同步到你自己的服务器。
                // 健康/家庭（批二）与蓝牙（已决不做）的
                // 键不在此列，entitlements 待签名权益核
                // 查后另加
                "NSCalendarsFullAccessUsageDescription": "OneDay 需要读取你的日历：安排只在这台手机上查看；开启智能体调用后，被问到时现读现回；只有你在连接器详情页亲手开启「数据同步」时，才会把过去 30 天到未来 90 天日程的标题与时间同步一份到你自己的服务器，供智能体整份查询。",
                "NSRemindersFullAccessUsageDescription": "OneDay 需要读取你的提醒事项：待办只在这台手机上查看；开启智能体调用后，被问到时现读现回；只有你在连接器详情页亲手开启「数据同步」时，才会把没做完的提醒同步一份到你自己的服务器，供智能体整份查询。",
                "NSContactsUsageDescription": "OneDay 需要读取你的通讯录：搜索在手机上完成；开启智能体调用后，被问到时现查现回；只有你在连接器详情页亲手开启「数据同步」时，才会把姓名、电话、邮箱同步一份到你自己的服务器（不含备注、地址、生日、头像），供智能体整份查询。",
                // 同步制照片/步数（0.36.14）：照片只读
                // 清单信息、步数只读按日合计，都只喂同
                // 步副本与详情页本地查看
                "NSPhotoLibraryUsageDescription": "OneDay 需要读取你的照片清单：只看每项的拍摄时间、类型和大小，用来在手机上展示数量；只有你在连接器详情页亲手开启「数据同步」时，才会把这份清单（不含照片本身、不含拍摄地点）同步一份到你自己的服务器，供智能体查询。",
                "NSMotionUsageDescription": "OneDay 需要读取手机计步的每日合计：只看每天的步数、距离和爬楼层数；只有你在连接器详情页亲手开启「数据同步」时，才会把每日合计同步一份到你自己的服务器，供智能体查询。",
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
