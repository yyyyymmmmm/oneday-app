/// 跨页深链路由（IA v3）：总览的指标行/最近会话/快捷动作要把
/// 用户直接送进智能体格或设置格的某个二级页，路由经 AppState
/// 的 pending 字段传递，目标页消费后清空。
enum AgentRoute: Hashable {
    case memory
    case skills
    case cron
    case serverSessions
    case serverSessionDetail(String)
}

/// 应用格内页面（0.6.0 五格 IA）：应用格首页是入口行
/// 列表，总览/文件/设置是其内页面；抽屉齿轮、总览深链
/// 等跨格入口经 AppState.pendingAppsPage 置位、应用格
/// 消费后清空（与 pendingChatSessionID 同模式）。
enum AppsPage: Hashable {
    case home
    case overview
    case files
    case settings
}

enum SettingsRoute: Hashable {
    case serverDetail
    case profiles
    case models
    case envVars
    case usage
    case gateway
    case logs
    /// 0.5.0（§31 追加件）：审批桥钥匙粘贴页（服务器与连接组）
    case writeGateKey
    /// 0.2.1：运维四模块并入设置「智能体」组，路由复用 AgentRoute
    case agent(AgentRoute)
    /// 0.2.1：外观（主题）
    case appearance
}
