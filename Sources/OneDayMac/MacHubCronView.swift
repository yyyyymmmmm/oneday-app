import SwiftUI
import OneDayCore

/// 定时任务面（棒 4，对位 #49，兼全局搜索定时段
/// #10 的数据源）：任务清单（系统任务按 is_system
/// 如实标注）＋暂停/恢复/立即跑/删除＋新建表单＋蓝
/// 图目录，全走 /api/cron/jobs 系（与 iOS 同口）
struct MacHubCronView: View {
    @Environment(SessionStore.self) private var session
    let store: MacHubStore
    @State private var newName = ""
    @State private var newPrompt = ""
    @State private var newSchedule = ""
    @State private var confirmDelete: CronJob?

    var body: some View {
        HubScroll {
            HubSectionHeader(
                title: "定时任务", count: store.cronJobs.count
            )
            if store.cronJobs.isEmpty {
                HubEmptyText(text: "暂无定时任务。")
            }
            ForEach(store.cronJobs) { job in
                HStack(alignment: .top, spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(job.name ?? "（未命名）")
                                .font(.callout.weight(.medium))
                            if job.isSystem == true {
                                Text("系统任务")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 1)
                                    .overlay {
                                        RoundedRectangle(
                                            cornerRadius: 4
                                        )
                                        .stroke(
                                            Color.secondary.opacity(0.4)
                                        )
                                    }
                            }
                        }
                        Text([
                            job.scheduleDisplay,
                            job.state,
                            job.nextRunAt.map { "下次 \($0)" },
                            job.lastError.map { "末错：\($0)" },
                        ].compactMap { $0 }.joined(separator: " · "))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    Spacer()
                    Button(job.enabled ? "暂停" : "恢复") {
                        Task {
                            await store.cronAction(
                                session: session, id: job.id,
                                action: job.enabled
                                    ? "pause" : "resume"
                            )
                        }
                    }
                    .buttonStyle(.borderless)
                    Button("立即跑") {
                        Task {
                            await store.cronAction(
                                session: session, id: job.id,
                                action: "trigger"
                            )
                        }
                    }
                    .buttonStyle(.borderless)
                    Button("删除") { confirmDelete = job }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.red)
                }
                Divider()
            }
            HubSectionHeader(title: "新建定时任务")
            TextField("名称（可空）", text: $newName)
                .textFieldStyle(.roundedBorder)
            TextField("提示词", text: $newPrompt)
                .textFieldStyle(.roundedBorder)
            TextField(
                "计划（如 every 1h / 0 9 * * *）",
                text: $newSchedule
            )
            .textFieldStyle(.roundedBorder)
            HStack {
                Spacer()
                Button("新建") {
                    Task {
                        await store.createCron(
                            session: session, name: newName,
                            prompt: newPrompt, schedule: newSchedule
                        )
                        newName = ""
                        newPrompt = ""
                        newSchedule = ""
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(newPrompt.isEmpty || newSchedule.isEmpty)
            }
            if !store.blueprints.isEmpty {
                HubSectionHeader(
                    title: "蓝图目录", count: store.blueprints.count
                )
                ForEach(
                    Array(store.blueprints.enumerated()), id: \.offset
                ) { _, blueprint in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(blueprint.hubFirstStr(["name", "id"])
                            ?? "（未命名蓝图）")
                            .font(.callout.weight(.medium))
                        Text(blueprint.hubFirstStr(["description"])
                            ?? "")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Divider()
                }
            }
        }
        .confirmationDialog(
            "删除这个定时任务？",
            isPresented: Binding(
                get: { confirmDelete != nil },
                set: { if !$0 { confirmDelete = nil } }
            )
        ) {
            Button("删除", role: .destructive) {
                if let job = confirmDelete {
                    Task {
                        await store.deleteCron(
                            session: session, id: job.id
                        )
                    }
                }
                confirmDelete = nil
            }
            Button("取消", role: .cancel) { confirmDelete = nil }
        }
    }
}
