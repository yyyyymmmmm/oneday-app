import SwiftUI
import AppKit
import Carbon
import OneDayCore

/// 速记窗热键持久化模型（棒 5 / mac-07 补齐 M2 改键录制器）：
/// 默认 ⌥Space（kVK_Space + optionKey）；用户可在「设置 → 通用」
/// 录制新快捷键，立即卸载旧热键并重绑，落盘 UserDefaults。
struct MacHotKeyBinding: Equatable, Sendable {
    var keyCode: UInt32
    var carbonModifiers: UInt32

    static let `default` = MacHotKeyBinding(
        keyCode: UInt32(kVK_Space),
        carbonModifiers: UInt32(optionKey)
    )

    private static let keyCodeDefaultsKey = "mac.quickEntry.keyCode.v1"
    private static let modifiersDefaultsKey = "mac.quickEntry.modifiers.v1"

    static func load(defaults: UserDefaults = .standard) -> MacHotKeyBinding {
        guard defaults.object(forKey: keyCodeDefaultsKey) != nil,
              defaults.object(forKey: modifiersDefaultsKey) != nil
        else { return .default }
        let code = UInt32(defaults.integer(forKey: keyCodeDefaultsKey))
        let mods = UInt32(defaults.integer(forKey: modifiersDefaultsKey))
        guard mods != 0 else { return .default }
        return MacHotKeyBinding(keyCode: code, carbonModifiers: mods)
    }

    func save(defaults: UserDefaults = .standard) {
        defaults.set(Int(keyCode), forKey: Self.keyCodeDefaultsKey)
        defaults.set(Int(carbonModifiers), forKey: Self.modifiersDefaultsKey)
    }

    static func reset(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: keyCodeDefaultsKey)
        defaults.removeObject(forKey: modifiersDefaultsKey)
    }

    static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var result: UInt32 = 0
        if flags.contains(.command) { result |= UInt32(cmdKey) }
        if flags.contains(.option) { result |= UInt32(optionKey) }
        if flags.contains(.control) { result |= UInt32(controlKey) }
        if flags.contains(.shift) { result |= UInt32(shiftKey) }
        return result
    }

    var displayString: String {
        var parts = ""
        if (carbonModifiers & UInt32(controlKey)) != 0 { parts += "⌃" }
        if (carbonModifiers & UInt32(optionKey)) != 0 { parts += "⌥" }
        if (carbonModifiers & UInt32(shiftKey)) != 0 { parts += "⇧" }
        if (carbonModifiers & UInt32(cmdKey)) != 0 { parts += "⌘" }
        parts += Self.keyName(for: keyCode)
        return parts
    }

    private static func keyName(for keyCode: UInt32) -> String {
        switch Int(keyCode) {
        case kVK_Space: return "Space"
        case kVK_Return: return "↩"
        case kVK_Tab: return "⇥"
        case kVK_Escape: return "⎋"
        case kVK_Delete: return "⌫"
        case kVK_ANSI_A: return "A"
        case kVK_ANSI_B: return "B"
        case kVK_ANSI_C: return "C"
        case kVK_ANSI_D: return "D"
        case kVK_ANSI_E: return "E"
        case kVK_ANSI_F: return "F"
        case kVK_ANSI_G: return "G"
        case kVK_ANSI_H: return "H"
        case kVK_ANSI_I: return "I"
        case kVK_ANSI_J: return "J"
        case kVK_ANSI_K: return "K"
        case kVK_ANSI_L: return "L"
        case kVK_ANSI_M: return "M"
        case kVK_ANSI_N: return "N"
        case kVK_ANSI_O: return "O"
        case kVK_ANSI_P: return "P"
        case kVK_ANSI_Q: return "Q"
        case kVK_ANSI_R: return "R"
        case kVK_ANSI_S: return "S"
        case kVK_ANSI_T: return "T"
        case kVK_ANSI_U: return "U"
        case kVK_ANSI_V: return "V"
        case kVK_ANSI_W: return "W"
        case kVK_ANSI_X: return "X"
        case kVK_ANSI_Y: return "Y"
        case kVK_ANSI_Z: return "Z"
        case kVK_ANSI_0: return "0"
        case kVK_ANSI_1: return "1"
        case kVK_ANSI_2: return "2"
        case kVK_ANSI_3: return "3"
        case kVK_ANSI_4: return "4"
        case kVK_ANSI_5: return "5"
        case kVK_ANSI_6: return "6"
        case kVK_ANSI_7: return "7"
        case kVK_ANSI_8: return "8"
        case kVK_ANSI_9: return "9"
        default: return "Key(\(keyCode))"
        }
    }
}

/// 速记窗（棒 3，对位 M2；棒 5 补齐热键改键录制器）：
/// 全局快捷键（默认 ⌥Space，可在设置页修改）唤出置顶小窗，
/// 写一句话发送即起一条新会话，任务在服务端继续跑。
@MainActor
final class MacQuickEntryController {
    static weak var shared: MacQuickEntryController?

    private var panel: NSPanel?
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private(set) var session: SessionStore?
    private(set) var binding: MacHotKeyBinding = MacHotKeyBinding.load()

    func bind(session: SessionStore) {
        self.session = session
        Self.shared = self
    }

    // MARK: - 全局热键注册与热重绑

    func registerHotKey() {
        if handlerRef == nil {
            var spec = EventTypeSpec(
                eventClass: OSType(kEventClassKeyboard),
                eventKind: UInt32(kEventHotKeyPressed)
            )
            InstallEventHandler(
                GetApplicationEventTarget(),
                { _, _, _ in
                    Task { @MainActor in
                        MacQuickEntryController.shared?.toggle()
                    }
                    return noErr
                },
                1, &spec, nil, &handlerRef
            )
        }
        applyBinding(binding)
    }

    func updateHotKey(_ newBinding: MacHotKeyBinding) {
        binding = newBinding
        newBinding.save()
        applyBinding(newBinding)
    }

    func resetHotKey() {
        MacHotKeyBinding.reset()
        binding = .default
        applyBinding(.default)
    }

    private func applyBinding(_ target: MacHotKeyBinding) {
        if let existing = hotKeyRef {
            UnregisterEventHotKey(existing)
            hotKeyRef = nil
        }
        let hotKeyID = EventHotKeyID(
            signature: OSType(0x4F44_4159), id: 1
        )
        RegisterEventHotKey(
            target.keyCode, target.carbonModifiers, hotKeyID,
            GetApplicationEventTarget(), 0, &hotKeyRef
        )
    }

    // MARK: - 面板

    func toggle() {
        if let panel, panel.isVisible {
            panel.orderOut(nil)
        } else {
            show()
        }
    }

    func show() {
        guard let session else { return }
        if panel == nil {
            let hosting = NSHostingController(
                rootView: MacQuickEntryView(
                    session: session, controller: self
                )
            )
            let created = NSPanel(
                contentRect: NSRect(
                    x: 0, y: 0, width: 520, height: 190
                ),
                styleMask: [.titled, .closable],
                backing: .buffered, defer: false
            )
            created.title = "速记"
            created.contentViewController = hosting
            created.isFloatingPanel = true
            created.level = .floating
            created.hidesOnDeactivate = true
            created.becomesKeyOnlyIfNeeded = false
            panel = created
        }
        panel?.center()
        NSApp.activate(ignoringOtherApps: true)
        panel?.makeKeyAndOrderFront(nil)
    }

    func hide() {
        panel?.orderOut(nil)
    }
}

/// 速记窗内容：输入＋发送。发送＝建新会话并提交一
/// 轮（服务端续跑），成功后给「在主窗打开」落点。
struct MacQuickEntryView: View {
    var session: SessionStore
    var controller: MacQuickEntryController
    @State private var text = ""
    @State private var sending = false
    @State private var sentSessionID: String?
    @State private var note: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !session.isConnected {
                Text("尚未连接服务器。先在主窗登录，再用速记窗。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else if let sentSessionID {
                Label("已发送，任务在服务端继续跑。", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                HStack(spacing: 10) {
                    Button("在主窗打开") {
                        NotificationCenter.default.post(
                            name: .macOpenSession, object: nil,
                            userInfo: ["sessionID": sentSessionID]
                        )
                        NSApp.activate(ignoringOtherApps: true)
                        controller.hide()
                    }
                    .keyboardShortcut(.defaultAction)
                    Button("再写一条") {
                        self.sentSessionID = nil
                        text = ""
                    }
                }
            } else {
                MacComposerView(
                    text: $text,
                    onSend: { send() },
                    onPasteAttachments: { _ in }
                )
                .frame(height: 64)
                .background(
                    Color(nsColor: .textBackgroundColor),
                    in: RoundedRectangle(cornerRadius: 8)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.secondary.opacity(0.3))
                )
                HStack {
                    Text("Return 发送（起新会话）· Esc 收起")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    if let note {
                        Text(note)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                    Button("发送") { send() }
                        .keyboardShortcut(.return, modifiers: .command)
                        .disabled(
                            sending || text.trimmingCharacters(
                                in: .whitespacesAndNewlines
                            ).isEmpty
                        )
                }
            }
            Button("") { controller.hide() }
                .keyboardShortcut(.cancelAction)
                .hidden()
        }
        .padding(14)
        .frame(width: 520)
    }

    private func send() {
        let content = text.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !content.isEmpty, !sending,
              let config = session.config, let key = session.apiKey
        else { return }
        sending = true
        note = nil
        Task {
            defer { sending = false }
            do {
                let created = try await session.chatClient
                    .createSession(
                        config: config, apiKey: key,
                        id: UUID().uuidString, title: nil
                    )
                _ = try await session.chatClient.submitRun(
                    config: config, apiKey: key,
                    sessionID: created.id, input: .text(content),
                    model: session.modelID ?? "",
                    idempotencyKey: UUID().uuidString
                )
                sentSessionID = created.id
            } catch let error as HermesError {
                note = error.userMessage
            } catch {
                note = "发送失败"
            }
        }
    }
}
