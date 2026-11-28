import OneDayDesign
import SwiftUI

/// Hermes v0.23.0 原生斜杠命令与 `!shell` 快捷指令目录（对齐 `hermes_cli/commands.py` 与 `bang_shell.py`）
struct HermesSlashCommand: Identifiable, Equatable {
    enum Category: String {
        case session = "会话"
        case mode = "模式"
        case skill = "技能"
        case terminal = "终端"
    }

    let id: String
    let command: String
    let insertText: String
    let title: String
    let subtitle: String
    let symbol: String
    let category: Category

    static let catalog: [HermesSlashCommand] = [
        HermesSlashCommand(
            id: "spawn",
            command: "/spawn",
            insertText: "/spawn ",
            title: "开启常驻分身",
            subtitle: "创建常驻本对话的分身，可随时 @ 派活与共享上下文",
            symbol: "person.badge.plus",
            category: .mode
        ),
        HermesSlashCommand(
            id: "close",
            command: "/close",
            insertText: "/close ",
            title: "关闭常驻分身",
            subtitle: "输入 /close @分身名 或 /close all 关闭常驻分身",
            symbol: "person.crop.circle.badge.xmark",
            category: .mode
        ),
        HermesSlashCommand(
            id: "compress",
            command: "/compress",
            insertText: "/compress",
            title: "压缩上下文",
            subtitle: "总结历史对话释放 Token 空间",
            symbol: "arrow.down.right.and.arrow.up.left",
            category: .session
        ),
        HermesSlashCommand(
            id: "context",
            command: "/context",
            insertText: "/context",
            title: "查看上下文占用",
            subtitle: "查看当前 Token、记忆与工具挂载情况",
            symbol: "gauge.with.dots.needle.33percent",
            category: .session
        ),
        HermesSlashCommand(
            id: "rewind",
            command: "/rewind",
            insertText: "/rewind",
            title: "回溯对话节点",
            subtitle: "撤销最近一轮并回到之前状态",
            symbol: "arrow.uturn.backward.circle",
            category: .session
        ),
        HermesSlashCommand(
            id: "branch",
            command: "/branch",
            insertText: "/branch ",
            title: "创建对话分支",
            subtitle: "从当前节点分叉出独立探索分支",
            symbol: "arrow.triangle.branch",
            category: .session
        ),
        HermesSlashCommand(
            id: "reasoning",
            command: "/reasoning",
            insertText: "/reasoning ",
            title: "切换推理强度",
            subtitle: "设置思考深度（low / medium / high）",
            symbol: "brain.head.profile",
            category: .mode
        ),
        HermesSlashCommand(
            id: "yolo",
            command: "/yolo",
            insertText: "/yolo",
            title: "切换自动审批模式",
            subtitle: "开启或关闭免确认自动执行工具",
            symbol: "bolt.shield",
            category: .mode
        ),
        HermesSlashCommand(
            id: "learn",
            command: "/learn",
            insertText: "/learn",
            title: "沉淀为新技能",
            subtitle: "将当前对话流程提炼为可复用 Skill",
            symbol: "sparkles",
            category: .skill
        ),
        HermesSlashCommand(
            id: "bundle",
            command: "/bundle",
            insertText: "",
            title: "Skill Bundles 技能组合",
            subtitle: "一键装载场景化技能套件或提炼新技能",
            symbol: "shippingbox.fill",
            category: .skill
        ),
        HermesSlashCommand(
            id: "rollback",
            command: "/rollback",
            insertText: "",
            title: "文件检查点与回滚",
            subtitle: "查看本会话文件变更彩色 Diff 并一键回滚",
            symbol: "clock.arrow.trianglehead.counterclockwise.rotate.90",
            category: .session
        ),
        HermesSlashCommand(
            id: "export",
            command: "/export",
            insertText: "",
            title: "脱敏导出与跨端 Handoff",
            subtitle: "导出脱敏 MD/HTML/JSON 或转交其他渠道",
            symbol: "square.and.arrow.up",
            category: .session
        ),
        HermesSlashCommand(
            id: "handoff",
            command: "/handoff",
            insertText: "",
            title: "跨端转交会话",
            subtitle: "将当前会话无缝交接给 Telegram/Slack/Web/CLI",
            symbol: "arrow.triangle.swap",
            category: .session
        ),
        HermesSlashCommand(
            id: "preview",
            command: "/preview",
            insertText: "",
            title: "交互预览与画布批注",
            subtitle: "打开 WKWebView 预览窗，支持引导游览与落点批注",
            symbol: "rectangle.and.pencil.and.ellipsis",
            category: .mode
        ),
        HermesSlashCommand(
            id: "profiles",
            command: "/profiles",
            insertText: "",
            title: "管理与切换分身",
            subtitle: "直达分身档案页：新建、克隆、导入导出",
            symbol: "person.2.crop.square.stack.fill",
            category: .mode
        ),
        HermesSlashCommand(
            id: "connectors",
            command: "/connectors",
            insertText: "",
            title: "连接器与 MCP 中心",
            subtitle: "直达本机权限、官方 MCP 目录与自定义 MCP",
            symbol: "puzzlepiece.extension.fill",
            category: .mode
        ),
        HermesSlashCommand(
            id: "bang",
            command: "!",
            insertText: "! ",
            title: "直跑终端命令（!shell）",
            subtitle: "直接执行 Shell 命令并回显，不消耗模型 Token",
            symbol: "terminal.fill",
            category: .terminal
        ),
    ]

    static func matching(for rawInput: String) -> [HermesSlashCommand] {
        let trimmed = rawInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        if trimmed == "!" {
            return catalog.filter { $0.id == "bang" }
        }
        guard trimmed.hasPrefix("/"), !trimmed.contains("\n") else { return [] }
        let token = trimmed.split(separator: " ", maxSplits: 1).first.map(String.init) ?? trimmed
        if trimmed.contains(" ") {
            return []
        }
        if token == "/" {
            return catalog
        }
        let needle = token.lowercased()
        return catalog.filter {
            $0.command.lowercased().hasPrefix(needle)
                || $0.title.lowercased().contains(needle.dropFirst())
        }
    }
}

/// 聊天输入框上方斜杠命令补全浮层（大厂原生卡片形态）
struct ChatSlashCommandPaletteView: View {
    let commands: [HermesSlashCommand]
    let onSelect: (HermesSlashCommand) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "command")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Palette.primary)
                Text("Hermes 快捷指令")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Palette.inkSecondary)
                Spacer()
                Text("点击填入")
                    .font(.caption2)
                    .foregroundStyle(Palette.inkMuted)
            }
            .padding(.horizontal, 14)
            .padding(.top, 10)
            .padding(.bottom, 6)

            Divider()
                .overlay(Palette.hairline)

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(commands) { item in
                        Button {
                            Haptics.selection()
                            onSelect(item)
                        } label: {
                            HStack(spacing: OneDayMetrics.spacingSM) {
                                Image(systemName: item.symbol)
                                    .font(.system(size: 14, weight: .semibold))
                                    .symbolRenderingMode(.hierarchical)
                                    .foregroundStyle(Palette.tintSkyInk)
                                    .frame(width: 28, height: 28)
                                    .background(
                                        Palette.tintSky,
                                        in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    )

                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 6) {
                                        Text(item.command)
                                            .font(.subheadline.monospaced().weight(.semibold))
                                            .foregroundStyle(Palette.ink)
                                        Text(item.title)
                                            .font(.caption.weight(.medium))
                                            .foregroundStyle(Palette.inkSecondary)
                                    }
                                    Text(item.subtitle)
                                        .font(.caption)
                                        .foregroundStyle(Palette.inkSecondary)
                                        .lineLimit(1)
                                }

                                Spacer(minLength: 4)

                                Text(item.category.rawValue)
                                    .font(.caption2.weight(.medium))
                                    .foregroundStyle(Palette.inkSecondary)
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 3)
                                    .background(Palette.fillTertiary, in: Capsule())
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 9)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.odPressable)
                    }
                }
            }
            .frame(maxHeight: 220)
        }
        .background(
            Palette.surface,
            in: RoundedRectangle(cornerRadius: OneDayMetrics.radiusCard, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: OneDayMetrics.radiusCard, style: .continuous)
                .strokeBorder(Palette.hairline, lineWidth: 1)
        )
        .shadow(color: Palette.shadowBase.opacity(0.08), radius: 12, y: 4)
        .padding(.horizontal, OneDayMetrics.spacingSM)
    }
}
