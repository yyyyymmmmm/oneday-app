import SwiftUI
import OneDayCore
import OneDayDesign

/// 凭据库选中项（中栏→详情联动）
enum MacVaultSelection: Hashable {
    case entry(String)
    case request(String)
}

/// 凭据库中栏（棒 2，对位 #71/#20）：条目与凭据请
/// 求两段列表。能力门未过时如实呈现未启用（与 iOS
/// 同口径：查不到能力即按不可用），不摆假数据。
struct MacVaultView: View {
    @Environment(SessionStore.self) private var session
    @Bindable var store: MacVaultStore
    @Binding var selection: MacVaultSelection?
    @State private var segment = Segment.entries
    @State private var creating = false

    enum Segment: String, CaseIterable {
        case entries = "条目"
        case requests = "请求"
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $segment) {
                ForEach(Segment.allCases, id: \.self) { item in
                    Text(item.rawValue).tag(item)
                }
            }
            .pickerStyle(.segmented)
            .padding(10)
            Divider()
            content
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    creating = true
                } label: {
                    Label("新建条目", systemImage: "plus")
                }
                .disabled(!store.isSupported(session: session))
                .help("新建凭据条目")
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task { await store.refresh(session: session) }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help("刷新")
            }
        }
        .sheet(isPresented: $creating) {
            MacVaultEditView(store: store, entry: nil)
        }
        .task {
            await store.refresh(session: session)
        }
    }

    @ViewBuilder
    private var content: some View {
        if !store.isSupported(session: session) {
            ContentUnavailableView(
                "凭据库未启用",
                systemImage: "key.slash",
                description: Text("服务端尚未开放凭据库功能。")
            )
        } else if store.loading && !store.loaded {
            ProgressView("正在读取凭据库…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = store.loadError {
            ContentUnavailableView(
                "凭据库加载失败",
                systemImage: "exclamationmark.triangle",
                description: Text(error)
            )
        } else {
            switch segment {
            case .entries:
                entriesList
            case .requests:
                requestsList
            }
        }
    }

    private var entriesList: some View {
        List(selection: $selection) {
            if store.entries.isEmpty {
                Text("暂无条目。点右上角＋新建第一条。")
                    .foregroundStyle(.secondary)
            }
            ForEach(store.entries) { entry in
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(entry.name)
                            .font(.callout.weight(.medium))
                            .lineLimit(1)
                        if entry.hasSecret {
                            Image(systemName: "lock.fill")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    Text(
                        entry.domains.first ?? entry.service
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                }
                .tag(MacVaultSelection.entry(entry.id))
            }
        }
        .listStyle(.inset)
    }

    private var requestsList: some View {
        List(selection: $selection) {
            if store.requests.isEmpty {
                Text("暂无凭据请求。")
                    .foregroundStyle(.secondary)
            }
            ForEach(store.requests) { request in
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(request.service)
                            .font(.callout.weight(.medium))
                            .lineLimit(1)
                        if request.isPending {
                            Text("待处理")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.orange)
                        } else {
                            Text(requestStatusLabel(request.status))
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    Text(request.domain)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .tag(MacVaultSelection.request(request.id))
            }
        }
        .listStyle(.inset)
    }

    private func requestStatusLabel(_ status: String) -> String {
        switch status {
        case "fulfilled": return "已提供"
        case "rejected": return "已拒绝"
        case "expired": return "已过期"
        default: return status
        }
    }
}
