import ProjectDescription

let iOS26 = DeploymentTargets.iOS("26.0")

let project = Project(
    name: "OneDay",
    organizationName: "site.didichou",
    settings: .settings(base: [
        "SWIFT_VERSION": "6.0",
        "TARGETED_DEVICE_FAMILY": "1",
        "MARKETING_VERSION": "0.50.30",
        "CURRENT_PROJECT_VERSION": "158",
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
                "CFBundleShortVersionString": "0.50.30",
                "CFBundleVersion": "158",                "ITSAppUsesNonExemptEncryption": false,
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
                // 闹钟（设备扩容批二，AlarmKit）：文
                // 案说清谁在什么时机设定——只有用户
                // 在对话里确认、或在闹钟详情页亲手添
                // 加时才设定；缺此键 schedule 必失败
                "NSAlarmKitUsageDescription": "OneDay 需要设定闹钟与倒计时：只有你在对话里确认、或在闹钟详情页亲手添加时才会设定；到点由系统响铃，能穿透静音与专注模式。",
                // 相机（设备扩容批三）：拍照与文档扫
                // 描都由用户当面取景完成，文案说清发
                // 起方与落点——图片只存进 OneDay 自
                // 己文件夹、不进系统相册；缺此键取景
                // 界面打不开
                "NSCameraUsageDescription": "OneDay 需要使用相机：只有智能体在对话里请你拍照或扫描文档、或你在相机详情页亲手点拍照时才会打开取景框；拍到的图片只存进 OneDay 自己的文件夹，不进系统相册。",
                // 本人确认（设备扩容批三）：Face ID
                // 的用途说明——系统在每次验证时把这
                // 句与发起方给的理由一同显示；缺此键
                // 面容验证直接失败
                "NSFaceIDUsageDescription": "OneDay 需要用面容 ID 确认是你在操作：只在重要操作前当面验一次，系统只告诉 OneDay 过没过，你的面容数据不会离开系统。",
                // 定位（设备扩容批四）：只有「使用
                // 时」一档——文案钉死不做后台定位、
                // 不存位置副本；缺此键定位请求直接
                // 失败
                "NSLocationWhenInUseUsageDescription": "OneDay 需要在你开着 App 时读取你的位置：只有智能体在对话里问你在哪、查附近地点时才现读一次，现读现回，不做后台定位，不保存你的位置记录。",
                // 媒体库（设备扩容批四）：文案说清只
                // 回书目、音频不出手机、播放控制只
                // 作用于系统音乐播放器；缺此键媒体
                // 库授权请求直接失败
                "NSAppleMusicUsageDescription": "OneDay 需要读取你的媒体库书目：只有智能体在对话里请你查歌、建歌单或控制播放时才会用到；只回歌曲与歌单的书目信息，音频文件不会离开手机。",
                // 快捷指令回执的 URL scheme（设备扩
                // 容批四）：x-callback-url 运行完一条
                // 快捷指令后，系统按 oneday://shortcut-
                // callback/<随机码>/<档> 回到 OneDay
                // 交回执；随机码一次性，外部链接打进
                // 来对不上就安静忽略
                "CFBundleURLTypes": [
                    [
                        "CFBundleURLName": "site.didichou.oneday.shortcut-callback",
                        "CFBundleURLSchemes": ["oneday"],
                    ],
                ],
                // 拉起白名单的「装没装」探测声明（设
                // 置页根地址＋四个登记应用的 scheme＋
                // 快捷指令；系统上限 50 条，本表只用
                // 6 条）
                "LSApplicationQueriesSchemes": ["App-prefs", "weixin", "alipay", "iosamap", "maps", "shortcuts"],
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
        // App 宿主测试（抽屉热修诊断起）：控制器级
        // 行为只能在 App 模块内验（@testable 宿主
        // 测试），与 Core 纯逻辑测试分家
        .target(
            name: "OneDayAppTests",
            destinations: .iOS,
            product: .unitTests,
            bundleId: "site.didichou.oneday.app.tests",
            deploymentTargets: iOS26,
            infoPlist: .default,
            sources: ["Tests/OneDayAppTests/**"],
            dependencies: [
                .target(name: "OneDayApp"),
            ]
        ),
        // UI 测试（症二阶段二动作级验证起）：系统级
        // 真实点按只能走 XCUITest（宿主内自造 UIEvent
        // 投递两轮实证到不了 SwiftUI 按钮 machinery，
        // 见 TAP-DISPATCH-DATA 的仪表记录）；实验装配
        // 在 App 侧 DEBUG 启动参数门后（CapsuleTap-
        // Harness），发布构建恒不触发
        .target(
            name: "OneDayUITests",
            destinations: .iOS,
            product: .uiTests,
            bundleId: "site.didichou.oneday.app.uitests",
            deploymentTargets: iOS26,
            infoPlist: .default,
            sources: ["Tests/OneDayUITests/**"],
            dependencies: [
                .target(name: "OneDayApp"),
            ]
        ),
    ],
    schemes: [
        .scheme(
            name: "OneDayApp",
            shared: true,
            buildAction: .buildAction(targets: ["OneDayApp"]),
            testAction: .targets([
                "OneDayCoreTests", "OneDayAppTests", "OneDayUITests",
            ]),
            runAction: .runAction(executable: "OneDayApp")
        ),
    ]
)
