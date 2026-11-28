import Foundation
import OneDayCore
import SwiftUI

/// 跨页深链路由（IA v3）：总览的指标行/最近会话/快捷动作要把
/// 用户直接送进智能体格或设置格的某个二级页，路由经 AppRouter
/// 的 pending 字段传递，目标页消费后清空。
/// （§305 前本文件名为 AppRoutes.swift、只有两个枚举——信箱
/// 本体从未并入；A-03 收口后枚举与信箱同归 AppRouter 一处。）
enum AgentRoute: Hashable {
    case memory
    case skills
    /// 工具集治理（台账 34，DESIGN §358）：设置·智能
    /// 体组「工具集」页
    case toolsets
    case delegation
    case cron
    /// （.serverSessions 名单页路由已随台账 199 删
    /// 除：名单正主归全部对话一级面，设置「服务端
    /// 会话」行改深链经 allConversationsRequested
    /// 直达，不再有设置内名单页可垫层）
    case serverSessionDetail(String)
    case mcp
    /// 设备与权限总览（0.34.0，本机连接器批一）：五件
    /// 数据源的授权状态＋调用开关汇总（设计档 §6.3）
    case devicePermissions
    /// Agent Plugins 插件市场（Hermes v0.23.0 dashboard_ui.py）
    case plugins
    /// 宿主机实时 PTY WebSocket 终端（Hermes v0.23.0 WS /api/pty）
    case hostPTY
    /// 自定义模型供应商端点与多 Key 凭据池（Hermes v0.23.0）
    case customEndpoints
    /// Bot Mode 多智能体房间协作与授权管理（Hermes v0.23.0）
    case botMode
    /// Git & Worktree 评审工作台（Hermes v0.23.0 git.py）
    case gitWorkbench
    /// 本地模型管理器（Hermes v0.23.0 local_models.py）
    case localModels
    // 审批规则路由已退役（§493，D3 改判 §244）：规
    // 则页迁中枢审核段、由中枢内层栈直推，不再经设
    // 置页 AgentRoute 点达
}

/// （应用格内页面枚举 AppsPage 已于 0.20.0 随应用格
/// 一并退役：总览/电脑/服务器文件迁设置「管理」组
/// sheet 呈现、设置改根级 sheet、文件升底栏第四格，
/// 「格内页面切换」的状态机不再存在。）

enum SettingsRoute: Hashable {
    case serverDetail
    case profiles
    case models
    case envVars
    case usage
    case gateway
    case logs
    /// （0.33.1 退役：原 .writeGateKey 桥钥匙粘贴页路由随
    /// 设置页「桥钥匙」整节删除，用户只持 Hermes 登录密钥）
    /// 0.2.1：运维四模块并入设置「智能体」组，路由复用 AgentRoute
    case agent(AgentRoute)
    /// 0.2.1：外观（主题）
    case appearance
    /// 语言面（§503）：外观页语言节迁出独立页（Core
    /// 目录 language 条目直达）
    case language
    /// 互动面（§503）：反应浮排＋AI 反应两开关（Core
    /// 目录 interaction 条目直达）
    case interaction
    /// 设置页重塑（DESIGN §164）：身份卡详情页与支持
    /// 组三页（帮助/关于/协议草稿）——目的地与 Core
    /// SettingsCatalog 一一对应
    case identity
    case help
    case about
    case privacy
    case terms
    /// prototype-2（DESIGN §164 升级）曾设四个二级枢纽页；
    /// 结构归位（2026-11-20，纲要 D7-1）后枢纽页撤销、
    /// 路由随之退役——子项全部提回设置根组直达，深链
    /// 落点改指叶子路由本身（迁移口径见 SettingsCatalog）
    case mainSession        // 主线会话详情页
    // 重启网关页路由已退役（台账 198 收敛 S4）：重启
    // 只走网关状态页控制组，根行独立页与本路由一并删
    /// 体检面（H1-a，台账 158）：原服务器管理「维护」段，
    /// 结构归位后归设置根服务器组维护尾段
    case healthCheck
    /// 高级与诊断面（总表 70）：运维诊断枢纽页，统一路由管理
    /// 避免直接目标式 NavigationLink 与 value 路由混用
    /// 造成的导航栈状态冲突
    case advancedDiagnostics
    /// 连接自检面（H13，台账 33，DESIGN §357）：客
    /// 户端只读探活驻留面，落设置根服务器段（Core
    /// 目录 connectionSelfCheck 条目直达）
    case connectionSelfCheck
    // 状态详情页路由已退役（§493，D1）：StatusView
    // 整页删除、三段内容各归正主（系统段收进网关页）
    /// 语音面（H2-a，台账 159）：台账 198 收敛 S13
    /// 归组后落设置根偏好与权限组（Core 目录 voice
    /// 条目直达）
    case voice
    /// 通知面（总表 162/163，DESIGN §385）：分级提
    /// 醒开关＋实时活动总开关，落设置根偏好与权限
    /// 组（Core 目录 notifications 条目直达）
    case notifications
    /// 添加设备（配对一期，台账 153/160）：已登录侧
    /// 出码面，台账 198 收敛 S13 后落设置根服务器段
    case addDevice
    /// 登录会话与短时票据管理面（与设置页其他路由统一走 value 栈）
    case authSessions
    /// 平台用户配对（H5，台账 35，DESIGN §359）：
    /// 网关消息平台用户白名单管理面，落设置根服务
    /// 器段、紧随添加设备（两物分清见 Core 目录）
    case pairingManagement
    /// 聊天诊断（台账 189/190）：本机聊天面探针可
    /// 读面，入口在关于页内部实验节（Core 目录
    /// chatDiagnostics 条目仅搜索可达）
    case chatDiagnostics
    /// 崩溃报告（G-14，DESIGN §384）：入口在关于页
    /// 内部实验节（Core 目录 crashReports 条目仅搜索可达）
    case crashReports
    /// 凭据库（sj-07）：密码与安全凭证管理
    case vault
    /// 云电脑与远程主机管理（托管云电脑 / Linux & Windows VPS / NAT 机 / 内网穿透节点）
    case cloudComputers
    /// 智能体工作台二级收口页（记忆 / 技能 / 工具集 / 委派路由 / 定时任务）
    case agentWorkspace
}

/// 目的地 → 设置路由映射（原 SettingsView 内私有，
/// 台账 176/DESIGN §391 起收口共用：设置页与全局搜索
/// 共用一份，不许再各写一份）；sheet 三件与无路由项
/// 返回 nil，由调用方分流
extension SettingsRoute {
    static func from(
        destination: SettingsDestination
    ) -> SettingsRoute? {
        switch destination {
        case .identity: return .identity
        case .profiles: return .profiles
        case .memory: return .agent(.memory)
        case .skills: return .agent(.skills)
        case .toolsets: return .agent(.toolsets)
        case .delegation: return .agent(.delegation)
        case .cron: return .agent(.cron)
        case .models: return .models
        case .envVars: return .envVars
        case .usage: return .usage
        case .serverDetail: return .serverDetail
        case .connectors: return .agent(.mcp)
        case .devicePermissions: return .agent(.devicePermissions)
        case .gateway: return .gateway
        case .logs: return .logs
        case .appearance: return .appearance
        case .language: return .language
        case .interaction: return .interaction
        case .help: return .help
        case .about: return .about
        case .privacy: return .privacy
        case .terms: return .terms
        // §493：电脑/服务器文件/状态/审批规则四目的
        // 地的设置侧入口已全退役（各归正主，见目录沿
        // 革），映射恒 nil、目的地枚举保留备查
        case .computer, .serverFiles, .status,
             .approvalRules,
             .disconnect, .serverSessions: return nil
        case .mainSession: return .mainSession
        case .healthCheck: return .healthCheck
        case .connectionSelfCheck: return .connectionSelfCheck
        case .voice: return .voice
        case .notifications: return .notifications
        case .addDevice: return .addDevice
        case .pairingManagement: return .pairingManagement
        case .chatDiagnostics: return .chatDiagnostics
        case .crashReports: return .crashReports
        }
    }
}

// 「工作区」组 sheet 呈现槽枚举（ManageSheet）已
// 退役（§493）：电脑并入中枢电脑格、服务器文件正口
// 归资源库，设置页不再有 sheet 呈现的工作区面

/// 全 App 唯一导航真值（§305，横扫 A-03 router-unify）：
/// 0.4.0–§219 六代「置位—消费—清零」信箱原散在 AppState
/// （约 20 个字段各自为政、消费方各写 onChange 猜时序），
/// 本类整组收口为唯一持有者——跨页路由意图、底栏格、
/// sheet 呈现槽、抽屉呈现与当前对象、频道观看出处全
/// 在此一处；视图只经本类读写导航状态，不再有第二
/// 个导航状态源。字段名与置位—消费—清零协议逐项沿
/// 旧制（行为不变是本包硬口径），变的只是持有者。
/// 面内导航栈仍归各面自有（设置页 NavigationStack
/// path 即官方形态），本类只管跨面一层。
@MainActor
@Observable
final class AppRouter {
    /// 跨页深链（总览 → 智能体格/设置格二级页）：目标页消费后置 nil
    var pendingAgentRoute: AgentRoute?
    var pendingSettingsRoute: SettingsRoute?
    /// 设置 sheet 打开请求（0.20.0）：抽屉齿轮置位，
    /// ContentView 消费呈现根级设置 sheet 后置 false。
    /// 0.6.0 的 pendingAppsPage 通道随应用格退役一并
    /// 删除——应用格页面已各有新家（总览/电脑/服务器
    /// 文件进设置「管理」组、文件格升底栏），不再有
    /// 「切格落位」这回事
    var settingsSheetRequested = false
    /// 全部对话页打开请求（结构归位第二批，2026-11
    /// -20，纲要 D2-1）：抽屉名单收尾行「全部对话」
    /// 置位，ContentView 消费呈现根级 fullScreen-
    /// Cover 后置 false——置位—消费—清零与 settings-
    /// SheetRequested 同式。全量列表自此是一级面入
    /// 口（抽屉名单自身），不再只经设置页行进入
    var allConversationsRequested = false
    /// 底栏切格请求（0.29.0）：设置内页面（如连接器目
    /// 录的本机服务详情）要把用户送到目标/点子底栏格
    /// 时置位，ContentView 消费后关设置 sheet 并切格
    /// 并清零——置位—消费—清零与 settingsSheet-
    /// Requested 同式；目标格枚举与底栏本体同源
    /// （ContentView.MainTab），不另立第二套格名
    var mainTabSwitchRequest: ContentView.MainTab?
    /// 文件页定位请求（§131，D8「在文件页中打开」）：
    /// 打开页动作置位目标路径并同行置 mainTabSwitch-
    /// Request=.files 切格，DeliverablesView 消费后
    /// 滚动定位＋高亮该行并清零——置位—消费—清零与
    /// pendingChatSessionID 同式
    var fileRevealPath: String?
    /// 待续聊的服务端会话 id（0.4.0，审计 §3.4）：四处
    /// 入口（抽屉／服务端会话页／状态页／定时运行记录）
    /// 置位，ContentView 据此切聊天格、ChatView 消费后
    /// 导入历史并置 nil。不再走设置格的只读详情页
    var pendingChatSessionID: String?
    /// 待续聊会话的频道来源标记（0.36.29，频道规格
    /// §10.3）：频道页点行时与 pendingChatSessionID
    /// 同行置位（先标记、后置 id），ChatView 消费时
    /// 据此把抽屉当前对象置为 .channel 并落频道观
    /// 看出处；其他入口打开会话不置此标记，消费口
    /// 径据「无标记」清旧出处。消费后清零
    var pendingChatChannelID: String?
    /// 频道观看出处（0.36.29，§10.2）：当前线程是
    /// 从哪个频道的哪条会话打开的——ChatView 当前
    /// 线程同步据此维持 .channel 对象引用（导入线
    /// 程渲染期间不派生成 .side）；线程切离该会话
    /// 或从旁聊区/主线行重进同一条时由各置位点清
    /// 除。只存呈现出处、不参与分类（分类归属与选
    /// 择归属是两件事）
    var channelViewingOrigin: ChannelViewingOrigin?
    /// 总览快捷动作「新建定时任务」：定时页消费后自动拉起新建表单
    var cronCreateRequested = false

    /// 通知落点请求（§123 H2）：通知中心点条目时置位
    /// （落点解析在 Core NotificationDestination），
    /// AgentHubView 开枢纽时消费段位、对应段消费各自
    /// 的聚焦字段，消费后清零——置位—消费—清零与
    /// hubOpenRequested 同式
    var hubDestinationRequest: NotificationDestination?
    /// 审批段聚焦的已决记录 id（approvalDecision 携带来）
    var hubApprovalFocusID: String?
    /// 监测段深链：直达的监测 id 与变化 id（变化 id 为
    /// nil 时只达监测详情）
    var monitorDeepLink: (monitorID: String, changeID: String?)?
    /// 锚点点达请求（§165）：枢纽记录行/通知回执命中本
    /// 机锚时置位——目标线程＋锚定键（键为 nil＝只切线
    /// 程不定位）；ChatView 消费（切线程→滚动定位→点
    /// 亮→清零），与 hubDestinationRequest 分家：锚点
    /// 落点不在枢纽里、不经枢纽开启接力
    var approvalAnchorRequest: (
        threadID: UUID, approvalKey: String?
    )?

    /// 通知条目落点分发：把落点拆成各消费方能消费的
    /// 字段；返回 false 表示无落点（调用方不导航）。
    /// §165：锚点落点（approvalAnchor/approvalThread）
    /// 不进 hubDestinationRequest——它由通知页直接切聊
    /// 天格＋置 approvalAnchorRequest，ChatView 消费；
    /// 返回 true 表示落点成立（调用方关通知页即可，不
    /// 走枢纽接力）
    @discardableResult
    func requestHubDestination(
        _ destination: NotificationDestination
    ) -> Bool {
        switch destination {
        case .approvalDecision(let id):
            hubApprovalFocusID = id
        case .monitorChange(let monitorID, let changeID):
            monitorDeepLink = (monitorID, changeID)
        case .approvalAnchor(let threadID, let key):
            approvalAnchorRequest = (threadID, key)
            return destination.hasDestination
        case .approvalThread(let threadID):
            approvalAnchorRequest = (threadID, nil)
            return destination.hasDestination
        case .approvalHome, .monitorsHome, .none:
            break
        }
        guard destination.hasDestination else { return false }
        hubDestinationRequest = destination
        return true
    }
    /// 抽屉「枢纽」导航行的开枢纽请求（0.19.0）：抽屉置
    /// 位（先切聊天格再置位），ChatView 消费后开枢纽
    /// sheet 并清零——置位—消费—清零与 cronCreate-
    /// Requested 同式。枢纽 sheet 本体长在聊天页（胶囊
    /// 入口同处），不在抽屉另立第二份承载
    var hubOpenRequested = false
    /// 聊天抽屉开合的语义状态（0.2.2 立；0.4.5 改口径，
    /// §30）：壳层 ContentView 是执行者（覆盖式动画与跟手
    /// 状态在壳层），任何视图想开/关抽屉只写这里、壳层
    /// onChange 执行；DrawerView 据此在打开时补拉服
    /// 务端会话 source 映射（0.19.0 返工瘦身：只喂旁
    /// 聊行显的来源过滤判定，不再拉名单成行——名单
    /// 本体是本地线程）。（0.2.2–0.4.4 的旧注「Con-
    /// tentView 据此隐藏自绘底栏」随自绘底栏与覆盖式
    /// 抽屉一并作废）
    var drawerPresented = false
    /// 抽屉与 ChatView 之间的通道（0.4.5，抽屉提到
    /// 壳层后立；模式与 pendingChatSessionID 一致：置位
    /// 方写、消费方读后清零）
    /// 抽屉当前对象引用（0.36.7，频道规格 §10.2/§10.3）：
    /// 全抽屉唯一选择源——写入点只有导航动作（抽屉主
    /// 线行→.main、旁聊行→.side）与 ChatView 的当前线
    /// 程同步（落点/切换/新建/导入都经它派生）；抽屉
    /// 胶囊只许问 Core DrawerSelectionPolicy，不许再
    /// 私读页签或线程 id 自画。页签切走不清、回切恢
    /// 复。0.4.5 的 activeThreadID 随本引用落地退役
    /// （其消费面——胶囊判定与删当前线程判定——已全
    /// 部改读本引用经政策解析）
    var currentDrawerObject: DrawerCurrentObject?
    /// 动态原帖回跳请求（§208）：聊天里点消息的动态
    /// 引用块时置位帖 id 并同行置 mainTabSwitch-
    /// Request=.feed 切格，FeedView 消费后定位原帖
    /// （查无此帖给诚实提示）并清零——置位—消费—
    /// 清零与 fileRevealPath 同式
    var feedOpenPostRequest: String?
    /// 点子回跳请求（§219）：聊天里点消息的点子引
    /// 用块时置位点子 id 并同行置 mainTabSwitch-
    /// Request=.ideas 切格，IdeasView 消费后开该点
    /// 子详情（查无此点子给诚实提示）并清零——与
    /// feedOpenPostRequest 同式
    var ideaOpenRequest: String?
    /// 抽屉点选/新建的线程 id（DrawerView 写，ChatView
    /// 消费后切 currentThreadID 并清零）
    var drawerThreadSelection: UUID?
    /// 抽屉点行延迟导航（台账 147）：会话行的点按先
    /// 经 stageDrawerThreadSelection 入账待办，关抽
    /// 屉进度降到近闭合（Core DrawerDeferredNavi-
    /// gation 阈值 0.05）才落进 drawerThreadSelec-
    /// tion 真正跳页——跳页不再与关抽屉动画抢帧。
    /// 进度事实由抽屉容器经桥喂入（noteDrawerPro-
    /// gress，呈现层逐帧采样，非观察属性、不触发
    /// 任何视图重算）；关动画被打断/关落定由容器
    /// 回调同一组口径收口
    @ObservationIgnored
    private var deferredDrawerNavigation =
        DrawerDeferredNavigation()
    /// 最近一次开度事实（1＝全开、0＝全合；容器喂
    /// 入的 DrawerMotion.progress 即开度——控制器
    /// offset 语义为前景位移：0＝合、travel＝开）
    @ObservationIgnored
    private var lastDrawerProgress: Double = 1

    /// 是否已有延迟导航待办在位（抽屉行点按的连点
    /// 守卫：待办在位时后续点按整下忽略，OB 同口径）
    var hasPendingDrawerNavigation: Bool {
        deferredDrawerNavigation.hasPending
    }

    /// 会话行点按的置位口：进度已近闭合（抽屉本就
    /// 关着/瞬时关）时立即落真值，否则入账待触发
    func stageDrawerThreadSelection(_ id: UUID) {
        if let fire = deferredDrawerNavigation.stage(
            id, currentProgress: lastDrawerProgress
        ) {
            drawerThreadSelection = fire
        }
    }

    /// 抽屉呈现进度喂入（容器桥）：待办在位且降到
    /// 阈值即落真值执行。容器喂的 DrawerMotion.-
    /// progress 与状态机同口径（开度：offset 为前
    /// 景位移、0＝合 travel＝开，比值即开度），直
    /// 喂不换算。（沿革：曾误判其为关合度而加 1−x
    /// 翻转，装配测试实证翻转后点行立即跳页、已回
    /// 滚——几何方向以 setDrawer 的 target＝open ?
    /// travel : 0 为准）
    func noteDrawerProgress(_ progress: Double) {
        lastDrawerProgress = progress
        if let fire = deferredDrawerNavigation
            .progressSample(progress) {
            drawerThreadSelection = fire
        }
    }

    /// 关动画被另一运动打断（容器桥）：待办即刻执
    /// 行、不吞（理由见 Core 文件头）
    func noteDrawerCloseInterrupted() {
        if let fire = deferredDrawerNavigation
            .closeInterrupted() {
            drawerThreadSelection = fire
        }
    }

    /// 抽屉开落定计数（§365 D2）：容器 finishSettle
    /// 经桥喂入（noteDrawerSettled），只记开落定——
    /// DrawerView 的打开刷新（账本可见段＋身份重拉）
    /// 触发点自语义翻转拍迁到此计数：完成发布退出
    /// 0.27s 动画窗、名单/页头不在滑动途中重渲染
    /// （调研 D2 定因）
    private(set) var drawerOpenSettledCount = 0

    /// 抽屉落定喂入（容器桥）：关落定不触发打开刷
    /// 新、不计数
    func noteDrawerSettled(open: Bool) {
        if open {
            drawerOpenSettledCount += 1
        }
    }

    /// 搜索落点请求（台账 150）：会话搜索命中点按时
    /// 与 pendingChatSessionID 同行置位（先置本两
    /// 件、后置 id，与 pendingChatChannelID 同式），
    /// ChatView 在导入/切换落定后消费——按摘要在本
    /// 地线程回找目标条目并收敛落点；消费后清零。
    /// 无此两件（其余入口打开会话）＝不落点、照常
    /// 开会话
    var pendingSearchFocusSnippet: String?
    var pendingSearchFocusRole: String?
    /// 抽屉刚删掉的线程 id（DrawerView 写，ChatView 若
    /// 正显示该线程则置空 currentThreadID 并清零）
    var drawerDeletedThreadID: UUID?
}
