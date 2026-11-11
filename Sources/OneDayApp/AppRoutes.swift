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
