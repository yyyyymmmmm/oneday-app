import Foundation
import SwiftData

/// 演示模式：只由启动参数触发，正常启动零影响。
/// - `-odDemoMode`：直接进已连接状态，五页全用本地静态样本驱动，
///   不连任何服务器、不读写 Keychain、不落真实数据（内存库）。
/// - `-odDemoConnect`：停在连接页，字段预填展示值（账号 admin，
///   密码与密钥为占位假串，SecureField 里只显示圆点）。点「测试
///   并连接」会走 DemoHermesClient 的假探活成功进主界面，全程
///   不碰网络与钥匙串。
/// 注：本模式原为已停用的 CI 截图验收环服务；截图环与自检
/// 脚手架已按用户令根除（DESIGN-V4 §13），本枚举与种子数据
/// 保留——它们只在显式启动参数下激活、生产路径恒为 .off，
/// 留作本地人工演示/调试入口，不属于交付验收路径。
enum DemoMode: Equatable {
    case off
    case connected
    case connectPage

    static var current: DemoMode {
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-odDemoConnect") {
            return .connectPage
        }
        if arguments.contains("-odDemoMode") {
            return .connected
        }
        return .off
    }

    var isDemo: Bool { self != .off }
}

/// 演示样本对话的播种：内存库每次启动都是空的，播一份拟真多轮
/// 对话（状态询问 → 代码块 → 长回复 → 收尾），让聊天演示页能
/// 同时看到用户气泡、助手裸排、代码块与长文。最后一句用户消息的
/// 回复不在种子里，由演示模式开流补上（截流式帧用）。
enum DemoSeeder {
    @MainActor
    static func seedIfNeeded(context: ModelContext) {
        let existing = (try? context.fetch(FetchDescriptor<ChatThread>())) ?? []
        guard existing.isEmpty else { return }

        let thread = ChatThread(title: "帮我看看服务器状态")
        context.insert(thread)

        let base = Date().addingTimeInterval(-25 * 60)
        let samples: [(role: String, content: String)] = [
            ("user", "帮我看看服务器现在的状态，顺便确认 Hermes 还在正常跑。"),
            ("assistant", [
                "刚查过，一切正常：",
                "",
                "网关运行中，API 服务已连接，健康检查返回 ok；当前模型是 deepseek-chat，工具集 hermes-cli 已加载。",
                "",
                "内存和磁盘都在正常区间，暂时没有要处理的事。",
            ].joined(separator: "\n")),
            ("user", "把手动查状态的命令发我一份，我存到备忘录里。"),
            ("assistant", [
                "存这两条就够了，第一条看健康、第二条看容器：",
                "",
                "```bash",
                "# 健康检查（免登录）",
                "curl -s https://hermes.didichou.site/health",
                "",
                "# 容器状态",
                "docker ps --filter name=hermes",
                "```",
                "",
                "第一条返回 `{\"status\": \"ok\"}` 就是活着；第二条看 STATUS 列，是 Up 就行。",
            ].joined(separator: "\n")),
            ("user", "OneDay 的智能体页，接下来先做哪个模块最值？"),
            ("assistant", [
                "先做定时任务，我的排序理由有三条：",
                "",
                "一是离日常最近。节点巡检、证书到期提醒这类事本质都是定时任务，手机上能看列表、能暂停、能立即触发一次，价值当天就兑现。",
                "",
                "二是接口最完整。/api/cron/jobs 的增删改查、暂停、恢复、触发和运行记录都是现成的，照着规格接就行，不用拼凑，翻车概率最低。",
                "",
                "三是它能顺带验证智能体页的整套交互——列表、详情、危险操作二次确认——这套交互跑通之后，技能和会话模块只是换数据源。记忆涉及提供方切换，误操作影响面最大，放最后。",
            ].joined(separator: "\n")),
            ("user", "巡检类的定时任务，一般都盯哪些指标？"),
            ("assistant", [
                "我盯五项，按重要性排：",
                "",
                "一是节点握手延迟。Railway 和 Cloady 四个节点每六小时握手一次，超过 2000ms 标降级、连续两次失败才报你，避免夜里误报。",
                "",
                "二是证书到期天数。七个域名共用一张多域名证书，到期前 30 天进待办面，前 7 天每天提醒。",
                "",
                "三是容器重启次数。Hermes 和几个业务容器重启计数异常增长，往往是内存打满的前兆，比等它真挂了再报有用。",
                "",
                "四是磁盘与内存水位。118 那台内存过 80% 是红线，巡检读数贴近红线就提前预警，不等触发。",
                "",
                "五是任务自身的上次运行结果。巡检任务自己失败是最危险的——其他四项全靠它报，所以它的失败要走单独的兜底通道。",
            ].joined(separator: "\n")),
            ("user", "好，就按你说的顺序来。"),
        ]
        for (index, sample) in samples.enumerated() {
            let entry = ChatEntry(role: sample.role, content: sample.content, thread: thread)
            entry.createdAt = base.addingTimeInterval(Double(index * 47))
            context.insert(entry)
        }
        thread.createdAt = base
        thread.updatedAt = base.addingTimeInterval(Double((samples.count - 1) * 47))

        // 第二条旧会话：抽屉历史列表的行节奏靠它（时间在主会话之前）
        let earlier = ChatThread(title: "下雨天节点会不会掉线")
        context.insert(earlier)
        let earlierBase = base.addingTimeInterval(-26 * 3600)
        let earlierSamples: [(role: String, content: String)] = [
            ("user", "昨晚洛川雨挺大，几个节点还稳吗？"),
            ("assistant", "三个节点都在线，握手延迟比平时高一些，还在降级线以内，不用处理。明早我再复查一遍。"),
        ]
        for (index, sample) in earlierSamples.enumerated() {
            let entry = ChatEntry(role: sample.role, content: sample.content, thread: earlier)
            entry.createdAt = earlierBase.addingTimeInterval(Double(index * 47))
            context.insert(entry)
        }
        earlier.createdAt = earlierBase
        earlier.updatedAt = earlierBase.addingTimeInterval(47)

        try? context.save()
    }
}
