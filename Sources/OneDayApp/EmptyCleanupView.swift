import OneDayCore
import OneDayDesign
import SwiftUI

/// 空会话清理审计留痕（§241）：本机 JSON 落盘最近
/// 20 次——计划段（候选快照）在第一条删除动手前就
/// 先写入，执行/核验结果以同 id 回填；进程中途死
/// 掉，记录里也留得下「本打算删什么、删到哪」。
enum EmptyCleanupAuditStore {
    private static let key = "emptyCleanupAuditRecords.v1"
    private static let retention = 20

    static func load() -> [EmptyCleanupAuditRecord] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let records = try? JSONDecoder().decode(
                [EmptyCleanupAuditRecord].self, from: data)
        else { return [] }
        return records
    }

    static func save(_ record: EmptyCleanupAuditRecord) {
        var records = load().filter { $0.id != record.id }
        records.insert(record, at: 0)
        records = Array(records.prefix(retention))
        if let data = try? JSONEncoder().encode(records) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    /// 最近一次已收口的清理（管理页「上次清理」行用）
    static var latestFinished: EmptyCleanupAuditRecord? {
        load().first { $0.finishedAt != nil }
    }
}

/// 空会话清理面（§241 安全处置）：进面第一步永远是
/// dry-run——全量扫描＋服务端计数对账＋候选清单预
/// 览，什么都不删；只有在预览里二次点名确认，才逐
/// 条走围栏单删（ServerSessionActions.delete），删
/// 后全量重扫逐条核验，结果连同候选快照进审计记录。
struct EmptyCleanupSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    /// 收口后请宿主重拉名单（以服务端为准）
    var onFinished: () -> Void

    private struct Scan {
        var sessions: [ServerSession]
        var serverCount: Int
        var candidates: [ServerSession]
        var countsMatch: Bool {
            EmptySessionCleanup.countsMatch(
                candidateCount: candidates.count,
                serverCount: serverCount)
        }
    }

    private enum Phase {
        case scanning
        case scanFailed(String)
        case preview(Scan)
        case running(done: Int, total: Int)
        case done(EmptyCleanupAuditRecord)
    }

    @State private var phase: Phase = .scanning

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("清理空会话")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("关闭") { dismiss() }
                    }
                }
        }
        .task { await scan() }
    }

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .scanning:
            VStack(spacing: OneDayMetrics.spacingM) {
                ProgressView()
                Text("正在扫描全部会话…")
                    .font(.footnote)
                    .foregroundStyle(Palette.inkSecondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .scanFailed(let message):
            ContentUnavailableView {
                Label("扫描没完成", systemImage: "exclamationmark.triangle")
            } description: {
                Text(message)
            } actions: {
                Button("重新扫描") { Task { await scan() } }
                    .buttonStyle(.bordered)
            }
        case .preview(let scan):
            preview(scan)
        case .running(let done, let total):
            VStack(spacing: OneDayMetrics.spacingM) {
                ProgressView()
                Text("正在删除 \(done)/\(total) 条…")
                    .font(.footnote)
                    .foregroundStyle(Palette.inkSecondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .done(let record):
            result(record)
        }
    }

    // MARK: - 预览（dry-run 结果，人没确认前不删）

    private func preview(_ scan: Scan) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("这是预演结果，还没有删除任何会话。")
                    .font(.footnote)
                    .foregroundStyle(Palette.inkSecondary)
                    .padding(.bottom, OneDayMetrics.spacingS)
                summaryLine(
                    "已扫描全部会话", "\(scan.sessions.count) 条")
                summaryLine(
                    "服务器自报空会话", "\(scan.serverCount) 条")
                summaryLine(
                    "按消息数数出的空会话", "\(scan.candidates.count) 条")
                if !scan.countsMatch {
                    Text("两边数目对不上，说明扫描口径和服务端口径不一致，这次不删。先把名单读全、口径对齐再来。")
                        .font(.footnote)
                        .foregroundStyle(Palette.danger)
                        .padding(.top, OneDayMetrics.spacingM)
                } else if scan.candidates.isEmpty {
                    Text("没有空会话需要清理。")
                        .font(.body)
                        .foregroundStyle(Palette.ink)
                        .padding(.top, OneDayMetrics.spacingM)
                } else {
                    SectionLabel("将要删除的空会话")
                        .padding(.top, OneDayMetrics.sectionOuterSpacing)
                        .padding(.bottom, OneDayMetrics.spacingS)
                    VStack(spacing: 0) {
                        ForEach(
                            Array(scan.candidates.enumerated()),
                            id: \.element.id
                        ) { index, session in
                            if index > 0 { GroupDivider() }
                            candidateRow(session)
                        }
                    }
                    .odGroup()
                    Text("删除走逐条围栏校验，删完会再全量核对一遍；候选清单和结果会存进本机清理记录。空会话没有任何消息，删掉的是会话本身。")
                        .font(.footnote)
                        .foregroundStyle(Palette.inkSecondary)
                        .padding(.top, OneDayMetrics.spacingM)
                    Button(role: .destructive) {
                        Task { await execute(scan) }
                    } label: {
                        Text("删除这 \(scan.candidates.count) 条空会话")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.odPrimary)
                    .padding(.top, OneDayMetrics.spacingL)
                }
            }
            .padding(.horizontal, OneDayMetrics.pageGutter)
            .padding(.top, OneDayMetrics.spacingM)
            .padding(.bottom, OneDayMetrics.spacingXL)
        }
        .background(Palette.pageBG)
    }

    private func summaryLine(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(.body)
                .foregroundStyle(Palette.ink)
            Spacer()
            Text(value)
                .font(.system(.footnote, design: .monospaced))
                .foregroundStyle(Palette.inkSecondary)
        }
        .frame(minHeight: OneDayMetrics.rowHeight)
    }

    private func candidateRow(_ session: ServerSession) -> some View {
        VStack(alignment: .leading, spacing: OneDayMetrics.stackGap) {
            Text(session.resolvedTitle(firstUserMessage: nil))
                .font(.body)
                .foregroundStyle(Palette.ink)
                .lineLimit(1)
            if let date = session.startedDate {
                Text(DisplayDate.dateTime(date))
                    .font(.caption)
                    .foregroundStyle(Palette.inkSecondary)
            }
        }
        .padding(.horizontal, OneDayMetrics.spacingM)
        .padding(.vertical, OneDayMetrics.spacingS)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - 结果（核验后收口）

    private func result(_ record: EmptyCleanupAuditRecord) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                summaryLine("已删除", "\(record.deletedIDs.count) 条")
                summaryLine(
                    "核验已消失",
                    "\(record.verifiedGoneIDs?.count ?? 0) 条")
                if let remaining = record.verifiedRemainingIDs,
                   !remaining.isEmpty {
                    summaryLine(
                        "删后仍在", "\(remaining.count) 条")
                }
                if !record.failures.isEmpty {
                    SectionLabel("没删掉的")
                        .padding(.top, OneDayMetrics.sectionOuterSpacing)
                        .padding(.bottom, OneDayMetrics.spacingS)
                    VStack(spacing: 0) {
                        ForEach(
                            Array(record.failures.enumerated()),
                            id: \.offset
                        ) { index, failure in
                            if index > 0 { GroupDivider() }
                            VStack(
                                alignment: .leading,
                                spacing: OneDayMetrics.stackGap
                            ) {
                                Text(title(for: failure.id, in: record))
                                    .font(.body)
                                    .foregroundStyle(Palette.ink)
                                    .lineLimit(1)
                                Text(failure.reason)
                                    .font(.footnote)
                                    .foregroundStyle(Palette.danger)
                            }
                            .padding(.horizontal, OneDayMetrics.spacingM)
                            .padding(.vertical, OneDayMetrics.spacingS)
                            .frame(
                                maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .odGroup()
                }
                Text("这次清理的候选清单和结果已存进本机清理记录。")
                    .font(.footnote)
                    .foregroundStyle(Palette.inkSecondary)
                    .padding(.top, OneDayMetrics.spacingM)
            }
            .padding(.horizontal, OneDayMetrics.pageGutter)
            .padding(.top, OneDayMetrics.spacingM)
            .padding(.bottom, OneDayMetrics.spacingXL)
        }
        .background(Palette.pageBG)
    }

    private func title(
        for id: String, in record: EmptyCleanupAuditRecord
    ) -> String {
        record.candidates.first(where: { $0.id == id })?.title ?? id
    }

    // MARK: - 扫描与执行

    /// 全量分页拉取（管理页日常只拉首 100 条，清理
    /// 扫描必须拉全——名单不全不清，是围栏的前提）
    private func fetchAllSessions() async throws -> [ServerSession] {
        try await appState.performAdmin { client, config in
            var all: [ServerSession] = []
            let pageSize = 100
            var offset = 0
            while offset < 10_000 {
                let page = try await client.serverSessionsPage(
                    config: config, limit: pageSize, offset: offset,
                    archived: "include")
                all.append(contentsOf: page.sessions)
                if page.sessions.isEmpty { break }
                if let total = page.total, all.count >= total { break }
                offset += pageSize
            }
            return all
        }
    }

    private func scan() async {
        phase = .scanning
        do {
            let sessions = try await fetchAllSessions()
            let serverCount = try await appState.performAdmin {
                client, config in
                try await client.emptySessionCount(config: config)
            }
            phase = .preview(Scan(
                sessions: sessions,
                serverCount: serverCount,
                candidates: EmptySessionCleanup.candidates(
                    from: sessions)))
        } catch {
            phase = .scanFailed(
                (error as? HermesError)?.userMessage
                    ?? "扫描失败，请稍后再试。")
        }
    }

    private func execute(_ scan: Scan) async {
        let formatter = ISO8601DateFormatter()
        var record = EmptyCleanupAuditRecord(
            id: UUID().uuidString,
            plannedAt: formatter.string(from: Date()),
            scannedCount: scan.sessions.count,
            serverReportedCount: scan.serverCount,
            candidates: scan.candidates.map { session in
                .init(
                    id: session.id,
                    title: session.resolvedTitle(firstUserMessage: nil),
                    startedAt: session.startedDate.map {
                        formatter.string(from: $0)
                    })
            })
        // 审计先行：动手前候选快照先落盘
        EmptyCleanupAuditStore.save(record)
        phase = .running(done: 0, total: scan.candidates.count)
        for (index, session) in scan.candidates.enumerated() {
            switch await ServerSessionActions.delete(
                appState: appState, id: session.id
            ) {
            case .verified:
                record.deletedIDs.append(session.id)
            case .failed(let reason):
                record.failures.append(.init(id: session.id, reason: reason))
            }
            phase = .running(
                done: index + 1, total: scan.candidates.count)
        }
        EmptyCleanupAuditStore.save(record)
        // 删后核验：全量重扫，候选逐条对存活集
        if let survivors = try? await fetchAllSessions() {
            let verification = EmptySessionCleanup.verify(
                candidateIDs: scan.candidates.map(\.id),
                survivingIDs: Set(survivors.map(\.id)))
            record.verifiedGoneIDs = verification.goneIDs
            record.verifiedRemainingIDs = verification.remainingIDs
        }
        record.finishedAt = formatter.string(from: Date())
        EmptyCleanupAuditStore.save(record)
        phase = .done(record)
        onFinished()
    }
}
