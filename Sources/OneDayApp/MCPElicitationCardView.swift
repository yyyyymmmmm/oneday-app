import OneDayCore
import OneDayDesign
import SwiftUI

// MARK: - #35 MCP 事件订阅配置存储（对接 NotificationsView 与服务端配置）

struct MCPEventSubscriptionConfig: Codable, Equatable {
    var subscribeEvents: Bool = false
    var routeToNotifications: Bool = true
    var allowElicitationForms: Bool = true
}

@MainActor
final class MCPEventSubscriptionStore {
    static let shared = MCPEventSubscriptionStore()
    private let defaultsKey = "mcp.event.subscriptions.v1"
    private var cache: [String: MCPEventSubscriptionConfig] = [:]

    private init() {
        if let data = UserDefaults.standard.data(forKey: defaultsKey),
           let decoded = try? JSONDecoder().decode([String: MCPEventSubscriptionConfig].self, from: data) {
            cache = decoded
        }
    }

    func config(for serverName: String) -> MCPEventSubscriptionConfig {
        cache[serverName] ?? MCPEventSubscriptionConfig()
    }

    func update(_ config: MCPEventSubscriptionConfig, for serverName: String) {
        cache[serverName] = config
        if let data = try? JSONEncoder().encode(cache) {
            UserDefaults.standard.set(data, forKey: defaultsKey)
        }
    }
}

// MARK: - #35 MCP Elicitation 结构化表单卡片（对话流内原生交互）

struct MCPElicitationField: Identifiable, Equatable {
    enum FieldKind: Equatable {
        case text
        case secret
        case boolean
        case choice([String])
    }

    let id: String
    let key: String
    let label: String
    let placeholder: String
    let required: Bool
    let kind: FieldKind
}

struct MCPElicitationPrompt: Equatable {
    let id: String
    let serverName: String
    let title: String
    let message: String
    let fields: [MCPElicitationField]
}

enum MCPElicitationParser {
    static func parse(from card: ToolCard) -> MCPElicitationPrompt? {
        let lowerName = card.name.lowercased()
        let combined = "\(card.args)\n\(card.result ?? "")"
        let looksLikeElicitation = lowerName.contains("elicit")
            || lowerName.contains("mcp_form")
            || combined.contains("\"requestedSchema\"")
            || combined.contains("\"elicitation\"")
        guard looksLikeElicitation else { return nil }

        let payloadSource = (card.result?.contains("{") == true ? card.result : nil) ?? card.args
        guard let data = payloadSource.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return MCPElicitationPrompt(
                id: card.id,
                serverName: card.name,
                title: "MCP 服务请求补充信息",
                message: "请确认或补充参数以继续执行 \(card.name)。",
                fields: [
                    MCPElicitationField(
                        id: "value",
                        key: "value",
                        label: "补充参数",
                        placeholder: "输入回复内容",
                        required: true,
                        kind: .text
                    )
                ]
            )
        }

        let serverName = (obj["server"] as? String)
            ?? (obj["mcp_server"] as? String)
            ?? card.name
        let message = (obj["message"] as? String)
            ?? (obj["prompt"] as? String)
            ?? "MCP 服务需要你补充以下信息后才能继续。"
        let title = (obj["title"] as? String) ?? "\(serverName) 参数确认"

        var parsedFields: [MCPElicitationField] = []
        if let schema = obj["requestedSchema"] as? [String: Any],
           let properties = schema["properties"] as? [String: [String: Any]] {
            let requiredSet = Set(schema["required"] as? [String] ?? [])
            for key in properties.keys.sorted() {
                let prop = properties[key] ?? [:]
                let label = (prop["title"] as? String) ?? key
                let placeholder = (prop["description"] as? String) ?? "请输入 \(label)"
                let typeStr = (prop["type"] as? String)?.lowercased() ?? "string"
                let formatStr = (prop["format"] as? String)?.lowercased() ?? ""
                let kind: MCPElicitationField.FieldKind
                if let enumValues = prop["enum"] as? [String], !enumValues.isEmpty {
                    kind = .choice(enumValues)
                } else if typeStr == "boolean" {
                    kind = .boolean
                } else if formatStr == "password" || key.lowercased().contains("secret") || key.lowercased().contains("token") {
                    kind = .secret
                } else {
                    kind = .text
                }
                parsedFields.append(
                    MCPElicitationField(
                        id: key,
                        key: key,
                        label: label,
                        placeholder: placeholder,
                        required: requiredSet.contains(key),
                        kind: kind
                    )
                )
            }
        }

        if parsedFields.isEmpty {
            parsedFields.append(
                MCPElicitationField(
                    id: "response",
                    key: "response",
                    label: "回复内容",
                    placeholder: "输入需要提交给 MCP 服务的值",
                    required: true,
                    kind: .text
                )
            )
        }

        return MCPElicitationPrompt(
            id: card.id,
            serverName: serverName,
            title: title,
            message: message,
            fields: parsedFields
        )
    }
}

struct MCPElicitationCardView: View {
    let prompt: MCPElicitationPrompt
    let onSubmit: (String) -> Void

    @State private var textValues: [String: String] = [:]
    @State private var boolValues: [String: Bool] = [:]
    @State private var submitted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "puzzlepiece.extension.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Palette.tintSkyInk)
                    .frame(width: 26, height: 26)
                    .background(Palette.tintSky, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 6) {
                        Text(prompt.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Palette.ink)
                        Text("MCP Elicitation")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(Palette.tintSkyInk)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Palette.tintSky, in: Capsule())
                    }
                    Text(prompt.message)
                        .font(.caption)
                        .foregroundStyle(Palette.inkSecondary)
                }
            }

            if submitted {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Palette.success)
                    Text("已向 \(prompt.serverName) 提交表单响应")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Palette.successText)
                }
                .padding(.vertical, 4)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(prompt.fields) { field in
                        fieldView(field)
                    }
                }

                HStack(spacing: 8) {
                    Button {
                        Haptics.selection()
                        submitted = true
                        onSubmit("已拒绝 MCP Elicitation 请求（\(prompt.serverName)）")
                    } label: {
                        Text("取消")
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(Palette.inkSecondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(Palette.fillTertiary, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    .buttonStyle(.odPressable)

                    Button {
                        Haptics.success()
                        submitted = true
                        onSubmit(serializedPayload())
                    } label: {
                        Text("提交给 MCP")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(Palette.primary, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    .buttonStyle(.odPressable)
                }
            }
        }
        .padding(12)
        .background(
            Palette.surface,
            in: RoundedRectangle(cornerRadius: OneDayMetrics.radiusCard, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: OneDayMetrics.radiusCard, style: .continuous)
                .strokeBorder(Palette.hairline, lineWidth: 1)
        )
    }

    @ViewBuilder
    private func fieldView(_ field: MCPElicitationField) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Text(field.label)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Palette.ink)
                if field.required {
                    Text("*")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Palette.danger)
                }
            }

            switch field.kind {
            case .text:
                TextField(
                    field.placeholder,
                    text: Binding(
                        get: { textValues[field.key] ?? "" },
                        set: { textValues[field.key] = $0 }
                    )
                )
                .font(.subheadline)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(Palette.fieldFill, in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            case .secret:
                SecureField(
                    field.placeholder,
                    text: Binding(
                        get: { textValues[field.key] ?? "" },
                        set: { textValues[field.key] = $0 }
                    )
                )
                .font(.subheadline)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(Palette.fieldFill, in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            case .boolean:
                Toggle(
                    field.placeholder,
                    isOn: Binding(
                        get: { boolValues[field.key] ?? false },
                        set: { boolValues[field.key] = $0 }
                    )
                )
                .font(.footnote)

            case .choice(let options):
                Picker(
                    field.label,
                    selection: Binding(
                        get: { textValues[field.key] ?? options.first ?? "" },
                        set: { textValues[field.key] = $0 }
                    )
                ) {
                    ForEach(options, id: \.self) { opt in
                        Text(opt).tag(opt)
                    }
                }
                .pickerStyle(.menu)
            }
        }
    }

    private func serializedPayload() -> String {
        var dict: [String: Any] = [:]
        for field in prompt.fields {
            switch field.kind {
            case .boolean:
                dict[field.key] = boolValues[field.key] ?? false
            case .choice(let opts):
                dict[field.key] = textValues[field.key] ?? opts.first ?? ""
            case .text, .secret:
                dict[field.key] = textValues[field.key] ?? ""
            }
        }
        if let data = try? JSONSerialization.data(withJSONObject: dict, options: [.sortedKeys]),
           let json = String(data: data, encoding: .utf8) {
            return "MCP Elicitation 响应（\(prompt.serverName)）：\(json)"
        }
        return "已确认 MCP Elicitation（\(prompt.serverName)）"
    }
}
