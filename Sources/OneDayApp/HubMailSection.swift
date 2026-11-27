import OneDayCore
import OneDayDesign
import SwiftUI

/// Mail inbox with drafts and compose capability.
struct HubMailSection: View {
    @Environment(AppState.self) private var appState
    private let client = HermesClient()
    @State private var messages: [MailMessage] = []
    @State private var total = 0
    @State private var loading = true
    @State private var errorMessage: String?
    @State private var showingCompose = false
    @State private var showingDrafts = false

    var body: some View {
        Group {
            if loading && messages.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let errorMessage, messages.isEmpty {
                ContentUnavailableView {
                    Label("邮箱暂时无法读取", systemImage: "envelope.badge")
                } description: {
                    Text(errorMessage)
                } actions: {
                    Button("重试", action: load)
                }
            } else if messages.isEmpty {
                ContentUnavailableView(
                    "收件箱为空",
                    systemImage: "tray",
                    description: Text("服务器收件箱目前没有同步到邮件。")
                )
            } else {
                List {
                    if let errorMessage {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(Palette.inkSecondary)
                    }
                    ForEach(messages) { message in
                        NavigationLink {
                            HubMailDetailView(message: message)
                        } label: {
                            messageRow(message)
                        }
                    }
                    if messages.count < total {
                        Button("加载更多") { loadMore() }
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                }
                .listStyle(.plain)
                .refreshable { await refresh() }
            }
        }
        .navigationTitle("邮箱")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button {
                        showingCompose = true
                    } label: {
                        Label("写信", systemImage: "square.and.pencil")
                    }
                    Button {
                        showingDrafts = true
                    } label: {
                        Label("草稿箱", systemImage: "doc.text")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $showingCompose) {
            MailComposeView()
                .onDisappear { load() }
        }
        .sheet(isPresented: $showingDrafts) {
            NavigationStack {
                MailDraftsView()
            }
        }
        .task { await loadMessages(reset: true) }
    }

    private func messageRow(_ message: MailMessage) -> some View {
        VStack(alignment: .leading, spacing: OneDayMetrics.spacingXS) {
            HStack(alignment: .firstTextBaseline, spacing: OneDayMetrics.spacingSM) {
                Text(message.from.isEmpty ? message.to : message.from)
                    .font(.body.weight(message.seen ? .regular : .semibold))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text(Date(timeIntervalSince1970: TimeInterval(message.date)), style: .date)
                    .font(.caption)
                    .foregroundStyle(Palette.inkSecondary)
                    .lineLimit(1)
            }
            Text(message.subject.isEmpty ? "（无主题）" : message.subject)
                .font(.subheadline.weight(message.seen ? .regular : .medium))
                .foregroundStyle(Palette.ink)
                .lineLimit(1)
            if !message.snippet.isEmpty {
                Text(message.snippet)
                    .font(.footnote)
                    .foregroundStyle(Palette.inkSecondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, OneDayMetrics.spacingXS)
    }

    private func load() {
        Task { await loadMessages(reset: true) }
    }

    private func loadMore() {
        Task { await loadMessages(reset: false) }
    }

    private func refresh() async {
        await loadMessages(reset: true)
    }

    @MainActor
    private func loadMessages(reset: Bool) async {
        guard let config = appState.config,
              let apiKey = await appState.effectiveBearerToken() else {
            errorMessage = "服务器连接凭据不可用。"
            loading = false
            return
        }
        loading = true
        errorMessage = nil
        do {
            let page = try await client.mailMessages(
                config: config, apiKey: apiKey, limit: 50,
                offset: reset ? 0 : messages.count
            )
            if reset { messages = page.data } else { messages += page.data }
            total = page.total
        } catch {
            errorMessage = error.localizedDescription
        }
        loading = false
    }
}

private struct HubMailDetailView: View {
    let message: MailMessage
    @Environment(AppState.self) private var appState
    private let client = HermesClient()
    @State private var detail: MailMessage?
    @State private var errorMessage: String?
    @State private var loading = true
    @State private var showingReply = false
    @State private var showingForward = false

    var body: some View {
        Group {
            if loading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let detail {
                ScrollView {
                    VStack(alignment: .leading, spacing: OneDayMetrics.spacingM) {
                        Text(detail.subject.isEmpty ? "（无主题）" : detail.subject)
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(Palette.ink)
                        metadata("发件人", detail.from)
                        metadata("收件人", detail.to)
                        metadata("时间", Date(timeIntervalSince1970: TimeInterval(detail.date)).formatted(date: .abbreviated, time: .shortened))

                        HStack(spacing: OneDayMetrics.spacingSM) {
                            Button {
                                showingReply = true
                            } label: {
                                Label("回复", systemImage: "arrowshape.turn.up.left")
                            }
                            .buttonStyle(.bordered)

                            Button {
                                showingForward = true
                            } label: {
                                Label("转发", systemImage: "arrowshape.turn.up.right")
                            }
                            .buttonStyle(.bordered)
                        }

                        Divider()
                        Text(detail.bodyText ?? "邮件正文为空。")
                            .font(.body)
                            .foregroundStyle(Palette.ink)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                    .padding(OneDayMetrics.hubGutter)
                }
            } else {
                ContentUnavailableView {
                    Label("邮件详情无法读取", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(errorMessage ?? "邮件正文暂时不可用。")
                } actions: {
                    Button("重试") { Task { await loadDetail() } }
                }
            }
        }
        .navigationTitle("邮件")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingReply) {
            if let detail {
                MailComposeView(
                    to: detail.from,
                    subject: detail.subject.hasPrefix("Re:") ? detail.subject : "Re: \(detail.subject)",
                    body: "\n\n---\n\(detail.from) 写道：\n\(detail.bodyText ?? "")"
                )
            }
        }
        .sheet(isPresented: $showingForward) {
            if let detail {
                MailComposeView(
                    to: "",
                    subject: detail.subject.hasPrefix("Fwd:") ? detail.subject : "Fwd: \(detail.subject)",
                    body: "\n\n---\n转发自：\(detail.from)\n主题：\(detail.subject)\n\n\(detail.bodyText ?? "")"
                )
            }
        }
        .task { await loadDetail() }
    }

    private func metadata(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: OneDayMetrics.spacingSM) {
            Text(title)
                .font(.footnote)
                .foregroundStyle(Palette.inkSecondary)
                .frame(width: 52, alignment: .leading)
            Text(value.isEmpty ? "—" : value)
                .font(.footnote)
                .foregroundStyle(Palette.ink)
                .textSelection(.enabled)
        }
    }

    @MainActor
    private func loadDetail() async {
        guard let config = appState.config,
              let apiKey = await appState.effectiveBearerToken() else {
            errorMessage = "服务器连接凭据不可用。"
            loading = false
            return
        }
        loading = true
        errorMessage = nil
        do {
            detail = try await client.mailMessage(
                config: config, apiKey: apiKey, accountID: message.accountID,
                folder: message.folder, uid: message.uid
            )
        } catch {
            errorMessage = error.localizedDescription
        }
        loading = false
    }
}
