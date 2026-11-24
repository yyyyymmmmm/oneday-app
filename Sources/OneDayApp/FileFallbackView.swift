import SwiftUI
import OneDayCore
import OneDayDesign

/// 聊天 QuickLook 呈示项（§452.6）
struct ChatQuickLookItem: Identifiable {
    let url: URL
    let name: String
    var id: String { url.path }
}

/// 文件兜底页（§452.6，微信图三形态）：大图标＋完
/// 整文件名（不截断）＋大小＋一句说明＋主按钮「用
/// 其他应用打开」→系统分享表。不可预览/压缩包/
/// 未知格式与敏感文件（锁定变体：无按钮、只说明）
/// 的聊天侧唯一落点；文件页侧仍走 FileOpenView 中
/// 间页、两面不混。未下载时主按钮先下载（按钮内
/// 显进度与已下载量）后唤分享；下载失败按钮变重
/// 试。形态学微信、主按钮用 App 强调令牌不抄其绿
struct FileFallbackView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    let target: FileOpenTarget

    @State private var shareItem: FileShareItem?
    @State private var failed = false

    private var store: ChatFileStore { .shared }

    private var isLocked: Bool {
        FileOpenRoute.resolve(target: target) == .locked
    }

    private var fileState: ChatFileStore.State {
        store.state(for: target.path)
    }

    private var sizeText: String? {
        let size = target.size
            ?? FileMetadataStore.shared
                .metadata(for: target.path)?.size
        return size.map { FileSizeText.compact($0) }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: OneDayMetrics.spacingM) {
                Spacer()
                FileTypeIconView(
                    fileName: target.name, height: 64
                )
                Text(target.name)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Palette.ink)
                    .multilineTextAlignment(.center)
                    .textSelection(.enabled)
                if let sizeText {
                    Text(sizeText)
                        .font(.subheadline)
                        .foregroundStyle(Palette.inkSecondary)
                }
                Text(
                    isLocked
                        ? "这是敏感文件，无法在 App 内打开或导出。"
                        : "暂时无法打开此类文件，你可以使用其他应用打开并预览。"
                )
                .font(.subheadline)
                .foregroundStyle(Palette.inkSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, OneDayMetrics.spacingL)
                if !isLocked {
                    mainButton
                        .padding(.top, OneDayMetrics.spacingS)
                }
                Spacer()
            }
            .padding(.horizontal, OneDayMetrics.spacingL)
            .navigationTitle(target.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
            .sheet(item: $shareItem) { item in
                FileShareSheet(url: item.url)
            }
        }
    }

    private var mainButton: some View {
        Button {
            Task { await openExternally() }
        } label: {
            HStack(spacing: OneDayMetrics.spacingS) {
                if case .downloading(let received, let expected)
                    = fileState {
                    ProgressView()
                        .tint(.white)
                    Text(
                        expected > 0
                            ? "下载中 \(FileSizeText.compact(received)) / \(FileSizeText.compact(expected))"
                            : "下载中…"
                    )
                } else if failed {
                    Text("下载失败，点按重试")
                } else {
                    Text("用其他应用打开")
                }
            }
            .font(.body.weight(.semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 47)
            .background(Palette.primaryFill, in: Capsule())
        }
        .buttonStyle(.odPressable)
        .disabled(
            {
                if case .downloading = fileState { return true }
                return false
            }()
        )
    }

    private func openExternally() async {
        failed = false
        if let url = store.localURL(for: target.path) {
            shareItem = FileShareItem(url: url)
            return
        }
        do {
            let url = try await store.download(
                path: target.path, appState: appState
            )
            shareItem = FileShareItem(url: url)
        } catch is CancellationError {
            // 静默
        } catch {
            failed = true
            Haptics.error()
        }
    }
}
