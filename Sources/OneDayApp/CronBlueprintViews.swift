import OneDayDesign
import OneDayCore
import SwiftUI

/// 定时任务模板面（§388 H6，总表 166）：服务端蓝图目录
/// 单源——GET /api/cron/blueprints 拉表单模式，挑选后按
/// fields 动态填空，POST instantiate 建任务，落定靠
/// CronStore 刷新回读（onCreated 由任务页接刷新）。
/// 空白新建仍走任务页「＋」原路，本面不重复造建任务表单。

// MARK: - 槽名/分类人话（服务端标签为英文原文，常见槽名在
// 客户端给中文名，未知者原样呈现服务端标签，不改语义）

private func blueprintSlotLabel(_ field: CronBlueprintField) -> String {
    switch field.name {
    case "time": return "时间"
    case "deliver": return "投递目标"
    case "recurrence": return "重复"
    case "day": return "星期"
    case "interval_min": return "间隔（分钟）"
    case "interval_hours": return "间隔（小时）"
    case "topic": return "主题"
    case "prompt": return "指令"
    case "note": return "备注"
    case "title": return "标题"
    case "name": return "名称"
    case "message": return "内容"
    case "city": return "城市"
    case "source": return "来源"
    default: return field.label.isEmpty ? field.name : field.label
    }
}

private func blueprintCategoryTitle(_ category: String) -> String {
    switch category {
    case "daily": return "日常"
    case "weekly": return "每周"
    case "work": return "工作"
    case "health": return "健康"
    case "finance": return "财务"
    case "learning": return "学习"
    case "social": return "社交"
    case "reminders": return "提醒"
    case "monitoring": return "监控"
    case "news": return "资讯"
    case "planning": return "计划"
    case "reflection": return "回顾"
    default: return category.isEmpty ? "模板" : category
    }
}

/// weekdays 槽的兜底选项（服务端 options 为空时）：值与
/// 服务端 WEEKDAY_PRESETS 的键逐字一致
private let weekdayPresetOptions: [(value: String, title: String)] = [
    ("everyday", "每天"),
    ("weekdays", "工作日"),
    ("weekends", "周末"),
]

// MARK: - 挑选面

struct CronBlueprintPickerView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    var onCreated: () -> Void = {}

    @State private var blueprints: [CronBlueprint] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    /// 服务端原序分组（分类首现序）
    private var groups: [(category: String, items: [CronBlueprint])] {
        var order: [String] = []
        var dict: [String: [CronBlueprint]] = [:]
        for blueprint in blueprints {
            if dict[blueprint.category] == nil { order.append(blueprint.category) }
            dict[blueprint.category, default: []].append(blueprint)
        }
        return order.map { (category: $0, items: dict[$0] ?? []) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if isLoading {
                        HStack(spacing: OneDayMetrics.spacingS) {
                            ProgressView()
                            Text("正在读取模板…")
                                .font(.footnote)
                                .foregroundStyle(Palette.inkSecondary)
                        }
                        .padding(.top, OneDayMetrics.spacingL)
                    } else if let errorMessage, blueprints.isEmpty {
                        InlineError(errorMessage)
                        Button("重试") { Task { await load() } }
                            .buttonStyle(.odSecondary)
                            .padding(.top, OneDayMetrics.spacingSM)
                    } else if blueprints.isEmpty {
                        ContentUnavailableView(
                            "暂无模板",
                            systemImage: "square.stack.3d.up.slash",
                            description: Text("服务器没有返回可用模板，可以用「＋」空白新建。")
                        )
                        .padding(.top, OneDayMetrics.spacingXXL)
                    } else {
                        ForEach(groups, id: \.category) { group in
                            SectionLabel(blueprintCategoryTitle(group.category))
                                .padding(.bottom, OneDayMetrics.spacingS)
                                .padding(.top, OneDayMetrics.spacingM)
                            VStack(spacing: 0) {
                                ForEach(Array(group.items.enumerated()), id: \.element.id) { index, blueprint in
                                    if index > 0 { GroupDivider() }
                                    NavigationLink {
                                        CronBlueprintFormView(
                                            blueprint: blueprint,
                                            onCreated: onCreated
                                        )
                                    } label: {
                                        blueprintRow(blueprint)
                                    }
                                }
                            }
                            .odGroup()
                        }
                    }
                }
                .padding(.horizontal, OneDayMetrics.pageGutter)
                .padding(.top, OneDayMetrics.spacingM)
                .padding(.bottom, OneDayMetrics.spacingXL)
            }
            .background(Palette.pageBG)
            .navigationTitle("从模板新建")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
        }
        .fullscreenPopBridge()
        .task { await load() }
    }

    private func blueprintRow(_ blueprint: CronBlueprint) -> some View {
        HStack(spacing: OneDayMetrics.spacingS) {
            VStack(alignment: .leading, spacing: OneDayMetrics.spacingMicro) {
                Text(blueprint.title)
                    .font(.rowTitleL)
                    .foregroundStyle(Palette.ink)
                if let scheduleHuman = blueprint.scheduleHuman, !scheduleHuman.isEmpty {
                    Text(scheduleHuman)
                        .font(.footnote)
                        .foregroundStyle(Palette.inkSecondary)
                }
                if !blueprint.description.isEmpty {
                    Text(blueprint.description)
                        .font(.footnote)
                        .foregroundStyle(Palette.inkSecondary)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: OneDayMetrics.spacingS)
            DisclosureChevron(font: .footnote.weight(.semibold))
        }
        .frame(minHeight: OneDayMetrics.rowHeight)
        .contentShape(Rectangle())
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            blueprints = try await appState.performAdmin { client, config in
                try await client.cronBlueprints(config: config)
            }
            errorMessage = nil
        } catch {
            errorMessage = (error as? HermesError)?.userMessage
                ?? "模板没读出来，请稍后再试。"
        }
    }
}

// MARK: - 填空面

struct CronBlueprintFormView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    let blueprint: CronBlueprint
    var onCreated: () -> Void = {}

    @State private var texts: [String: String]
    @State private var times: [String: Date]
    @State private var errorMessage: String?
    @State private var isSubmitting = false

    init(blueprint: CronBlueprint, onCreated: @escaping () -> Void = {}) {
        self.blueprint = blueprint
        self.onCreated = onCreated
        var texts: [String: String] = [:]
        var times: [String: Date] = [:]
        for field in blueprint.fields {
            texts[field.name] = field.defaultText
            if field.isTime {
                times[field.name] = Self.parseTime(field.defaultText) ?? Date()
            }
        }
        _texts = State(initialValue: texts)
        _times = State(initialValue: times)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if !blueprint.description.isEmpty {
                    Text(blueprint.description)
                        .font(.footnote)
                        .foregroundStyle(Palette.inkSecondary)
                        .padding(.bottom, OneDayMetrics.spacingM)
                }
                SectionLabel("填空")
                    .padding(.bottom, OneDayMetrics.spacingS)
                VStack(spacing: 0) {
                    ForEach(Array(blueprint.fields.enumerated()), id: \.element.id) { index, field in
                        if index > 0 { GroupDivider() }
                        fieldBlock(field)
                    }
                }
                .odGroup()
                if let scheduleHuman = blueprint.scheduleHuman, !scheduleHuman.isEmpty {
                    Text("默认节奏：\(scheduleHuman)（按所填内容生成实际计划）")
                        .font(.footnote)
                        .foregroundStyle(Palette.inkSecondary)
                        .padding(.top, OneDayMetrics.spacingM)
                }
                if let errorMessage {
                    InlineError(errorMessage)
                        .padding(.top, OneDayMetrics.spacingM)
                }
            }
            .padding(.horizontal, OneDayMetrics.pageGutter)
            .padding(.top, OneDayMetrics.spacingM)
            .padding(.bottom, OneDayMetrics.spacingXL)
        }
        .background(Palette.pageBG)
        .navigationTitle(blueprint.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(isSubmitting ? "创建中…" : "创建") {
                    Task { await submit() }
                }
                .disabled(isSubmitting)
            }
        }
    }

    @ViewBuilder
    private func fieldBlock(_ field: CronBlueprintField) -> some View {
        FieldRow(label: blueprintSlotLabel(field)) {
            VStack(alignment: .leading, spacing: OneDayMetrics.spacingMicro) {
                fieldControl(field)
                if !field.help.isEmpty {
                    Text(field.help)
                        .font(.caption)
                        .foregroundStyle(Palette.inkSecondary)
                }
                if field.optional {
                    Text("可不填")
                        .font(.caption)
                        .foregroundStyle(Palette.inkSecondary)
                }
            }
        }
    }

    @ViewBuilder
    private func fieldControl(_ field: CronBlueprintField) -> some View {
        if field.isTime {
            DatePicker(
                "",
                selection: timeBinding(field),
                displayedComponents: .hourAndMinute
            )
            .labelsHidden()
        } else if field.isWeekdays {
            Picker("", selection: textBinding(field)) {
                if field.options.isEmpty {
                    ForEach(weekdayPresetOptions, id: \.value) { option in
                        Text(option.title).tag(option.value)
                    }
                } else {
                    ForEach(field.options, id: \.self) { option in
                        Text(option).tag(option)
                    }
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
        } else if field.isEnum, !field.options.isEmpty {
            Picker("", selection: textBinding(field)) {
                ForEach(field.options, id: \.self) { option in
                    Text(option).tag(option)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
        } else if field.name == "prompt" || field.name == "message" {
            TextField(field.label, text: textBinding(field), axis: .vertical)
                .lineLimit(2...5)
        } else {
            TextField(field.label, text: textBinding(field))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        }
    }

    private func textBinding(_ field: CronBlueprintField) -> Binding<String> {
        Binding(
            get: { texts[field.name] ?? field.defaultText },
            set: { texts[field.name] = $0 }
        )
    }

    private func timeBinding(_ field: CronBlueprintField) -> Binding<Date> {
        Binding(
            get: { times[field.name] ?? Date() },
            set: { times[field.name] = $0 }
        )
    }

    /// 提交组装：time 槽以 HH:mm 文本回填 texts 后走 Core
    /// 单源组装（必填缺失整单拦下，不发半成品到服务端）
    private func submit() async {
        var assembled = texts
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm"
        for field in blueprint.fields where field.isTime {
            if let date = times[field.name] {
                assembled[field.name] = formatter.string(from: date)
            }
        }
        guard let values = CronBlueprintFill.values(
            fields: blueprint.fields, texts: assembled
        ) else {
            errorMessage = "有必填项还没填。"
            return
        }
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            try await appState.performAdmin { client, config in
                try await client.instantiateBlueprint(
                    config: config, blueprint: blueprint.key, values: values
                )
            }
            onCreated()
            dismiss()
        } catch {
            errorMessage = (error as? HermesError)?.userMessage
                ?? "创建失败，请稍后再试。"
        }
    }

    /// "HH:mm" → 今天该时刻（DatePicker 初值用）
    private static func parseTime(_ text: String) -> Date? {
        let parts = text.split(separator: ":")
        guard parts.count == 2,
              let hour = Int(parts[0]), let minute = Int(parts[1]),
              (0...23).contains(hour), (0...59).contains(minute)
        else { return nil }
        return Calendar.current.date(
            bySettingHour: hour, minute: minute, second: 0, of: Date()
        )
    }
}
