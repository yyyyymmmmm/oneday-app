/// 跨页深链路由（IA v3）：总览的指标行/最近会话/快捷动作要把
/// 用户直接送进智能体格或设置格的某个二级页，路由经 AppState
/// 的 pending 字段传递，目标页消费后清空。
enum AgentRoute: Hashable {
    case memory
    case skills
    case cron
    case serverSessions
    case serverSessionDetail(String)
    case mcp
    /// 设备与权限总览（0.34.0，本机连接器批一）：五件
    /// 数据源的授权状态＋调用开关汇总（设计档 §6.3）
    case devicePermissions
    /// 审批规则（§244 归位）：设置页权限区内的规则面
    case approvalRules
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
    /// 侧边栏分区管理面（§198，抽屉包题二）：抽屉四
    /// 区显隐账的唯一治理面（设置→偏好与权限→侧边栏）
    case sidebar
    /// 设置页重塑（DESIGN §164）：身份卡详情页与支持
    /// 组三页（帮助/关于/协议草稿）——目的地与 Core
    /// SettingsCatalog 一一对应
    case identity
    case help
    case about
    case privacy
    case terms
    /// prototype-2（DESIGN §164 升级）：四个二级枢纽页
    case agentConfig        // 智能体配置枢纽页
    case serverManagement   // 服务器管理枢纽页
    case sessionManagement  // 会话管理枢纽页
    case workspaceHub       // 工作区枢纽页
    case mainSession        // 主线会话详情页
    case restartGateway     // 重启网关页
}

/// 工作区组三页的 sheet 呈现枚举（§260 上移公共层：
/// 原为 SettingsView.ManageSheet 嵌套枚举，被工作区
/// 枢纽页 WorkspaceHubView 反向借用——类型归属倒挂；
/// 上移至本文件后设置页与枢纽页平级引用，成员与
/// rawValue 不变，呈现行为零变）
enum ManageSheet: String, Identifiable {
    case overview, computer, serverFiles
    var id: String { rawValue }
}

/// 跨页信箱单一出处（§260，设置路由信箱归并）：跨页
/// 导航的「置位—消费—清零」请求原散作 AppState 五个
/// 字段（深链两路自 0.2.x、sheet 请求 0.20.0、切格
/// 请求 0.29.0、文件定位 §131），投递方与消费方各记
/// 各的出处；本结构体收成一份，AppState 只持 `routes`
/// 一处。字段语义与时序逐项沿旧口径，不增不减：
struct AppRoutes {
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
}
