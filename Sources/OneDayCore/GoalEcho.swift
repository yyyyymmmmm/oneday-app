import Foundation

/// 目标委派回响规划（§123 H1，闭环包）：用户亲手在目标里
/// 「安排一件事」委派出去的任务，进展与结果要落回这个
/// 目标绑定的旁聊里（C1 定版：用户亲手发起的进旁聊）。
/// 本枚举只做纯规划——该落哪些回响、文案是什么；落盘
/// 与渲染在 App 层（ChatEntry.echoKey 标记，见 ChatView）。
///
/// 真源纪律（不许造假回响）：
/// - 完成只认桥侧落戳：BridgeGoalTask.completionEntryAt
///   非空——它是桥回声账的只读投影，桥是在任务板状态
///   落进完成集、事实进展条目写下后才落这条戳的，与
///   App 本地推测无关（§308 单轨后载体从链接记录换成
///   GD-2 行的派生字段，判定口径不变）；
/// - 开始/等你回答/失败认任务板现值经
///   KanbanStatusPresentation.resolve 的呈现判定
///   （.running/.needsInput/.failed），其中「失败」是
///   blocked+transient+错误在场的呈现判定、不是终态——
///   回响文案只记「执行失败」这一时点事实，不冒充终局；
/// - 任务板没取到任务（task 为 nil）且无完成戳时，只落
///   「已安排」一条，不脑补状态。
public enum GoalEcho {
    public enum Kind: String, Equatable, Sendable, CaseIterable {
        case delegated
        case started
        case needsInput
        case failed
        case completed
    }

    public struct Planned: Equatable, Sendable {
        public let key: String
        public let kind: Kind
        public let taskID: String
        /// 任务标题；任务板没取到时为空串，文案走泛称
        public let taskTitle: String

        public init(
            key: String, kind: Kind, taskID: String,
            taskTitle: String
        ) {
            self.key = key
            self.kind = kind
            self.taskID = taskID
            self.taskTitle = taskTitle
        }
    }

    /// 去重键（落盘在 ChatEntry.echoKey，跨启动稳定）。
    /// §308 起键材料是任务本身——旧链接 id 键从未在生产
    /// 落过盘（存量链接为零），无迁移负担
    public static func key(taskID: String, kind: Kind) -> String {
        "goalTask:\(taskID):\(kind.rawValue)"
    }

    /// 按关联序规划待落回响：每条关联先「已安排」，再按
    /// 真源补状态回响；existingKeys 里已有的整类跳过。
    /// 同一关联的回响按 delegated→状态 的序返回，调用方
    /// 按序落盘即时间序。
    public static func plan(
        linkedTasks: [GoalAssociations.LinkedTask],
        existingKeys: Set<String>
    ) -> [Planned] {
        var planned: [Planned] = []
        for linked in linkedTasks {
            let row = linked.row
            let title = linked.task?.title ?? ""
            func append(_ kind: Kind) {
                let k = key(taskID: row.taskId, kind: kind)
                guard !existingKeys.contains(k) else { return }
                planned.append(
                    Planned(
                        key: k, kind: kind, taskID: row.taskId,
                        taskTitle: title
                    )
                )
            }
            append(.delegated)
            if row.completionEntryAt != nil {
                append(.completed)
            } else if let task = linked.task {
                let presentation = KanbanStatusPresentation.resolve(
                    status: task.status,
                    blockKind: task.blockKind,
                    lastFailureError: task.lastFailureError
                )
                switch presentation {
                case .running: append(.started)
                case .needsInput: append(.needsInput)
                case .failed: append(.failed)
                default: break
                }
            }
        }
        return planned
    }

    /// 回响正文（人话、只记事实；任务标题缺失时用泛称
    /// 「这件事」，不编名）
    public static func text(
        kind: Kind, taskTitle: String,
        locale: Locale = AppLocale.uiLocale
    ) -> String {
        let trimmed = taskTitle.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        let subject = trimmed.isEmpty
            ? L10n.string("这件事", locale: locale)
            : L10n.format("《%@》", locale: locale, trimmed)
        switch kind {
        case .delegated:
            return L10n.format(
                "已安排%@，进展会记在这里。", locale: locale, subject
            )
        case .started:
            return L10n.format(
                "%@已经开始办了。", locale: locale, subject
            )
        case .needsInput:
            return L10n.format(
                "%@在等你回答，去任务里看看。", locale: locale, subject
            )
        case .failed:
            return L10n.format(
                "%@执行失败了，详情在目标的关联任务里。",
                locale: locale, subject
            )
        case .completed:
            return L10n.format(
                "%@办完了。", locale: locale, subject
            )
        }
    }
}
