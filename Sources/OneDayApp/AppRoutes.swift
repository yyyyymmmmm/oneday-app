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

enum SettingsRoute: Hashable {
    case serverDetail
    case profiles
    case models
    case envVars
    case usage
    case gateway
    case logs
}
