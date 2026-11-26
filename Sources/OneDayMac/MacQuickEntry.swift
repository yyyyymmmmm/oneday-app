import SwiftUI
import AppKit
import Carbon
import OneDayCore

/// 速记窗（棒 3，对位 M2）：全局快捷键 ⌥Space 唤出
/// 的置顶小窗（Claude Quick Entry / ChatGPT
/// Companion Window 通例形态）——写一句话发送即起
/// 一条新会话，任务在服务端继续跑；可在主窗打开跟
/// 进。热键经 Carbon RegisterEventHotKey 注册（系
/// 统级、无三方依赖）。热键改键（录制器）未落，见
/// 对位表销账说明。
@MainActor
final class MacQuickEntryController {
    static weak var shared: MacQuickEntryController?

    private var panel: NSPanel?
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private(set) var session: SessionStore?

    func bind(session: SessionStore) {
        self.session = session
        Self.shared = self
    }

    // MARK: - 全局热键（⌥Space）

    func registerHotKey() {
        guard hotKeyRef == nil else { return }
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
        let hotKeyID = EventHotKeyID(
            signature: OSType(0x4F44_4159), id: 1
        )
        RegisterEventHotKey(
            UInt32(kVK_Space), UInt32(optionKey), hotKeyID,
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
