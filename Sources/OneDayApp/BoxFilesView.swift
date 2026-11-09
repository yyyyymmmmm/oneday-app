import Foundation
import OneDayCore
import OneDayDesign
import SwiftUI
import UIKit

// 文件格「电脑」段与 P9 电脑面「文件」段共用同一面
// （0.15.0 抽出）：同一个 BoxFilesView 组件、同一把桥
// 钥匙、同一套四态口径，两处入口不许出现两套呈现。

// MARK: - 电脑段（Box 工作区产出）

/// Box /workspace 文件面（契约 box-files-contract-
/// 20261109.md）：桥侧端点未部署前整段如实露「尚未
/// 开通」，不拿空列表冒充。相对路径状态驱动浏览，与
/// 浏览段同款行与面包屑（相对版）。
struct BoxFilesView: View {
    @Environment(AppState.self) private var appState
    private let client = BoxFilesClient()

    private enum Phase {
        case loading
        case notConnected
        case notAvailable
        case failed(String)
        case ready
    }

    /// 相对 Box 工作区根的路径（"" 为根）
    @State private var currentPath = ""
    @State private var listing: FilesListing?
    @State private var phase: Phase = .loading
    @State private var previewEntry: WorkspaceFileEntry?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            switch phase {
            case .loading:
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .notConnected:
                EmptyState(
                    icon: "key.slash",
                    title: "数据桥未连接",
                    message: "先在设置里填好数据桥钥匙，才能读电脑里的文件。"
                )
                .padding(.top, OneDayMetrics.spacingXXL)
                Spacer()
            case .notAvailable:
                EmptyState(
                    icon: "desktopcomputer",
                    title: "电脑文件尚未开通",
                    message: "智能体电脑的文件面还在路上；开通后这里能直接浏览它工作区里的产出。"
                )
                .padding(.top, OneDayMetrics.spacingXXL)
                Spacer()
            case .failed(let message):
                EmptyState(
                    icon: "exclamationmark.triangle",
                    title: "读取失败",
                    message: message
                )
                .padding(.top, OneDayMetrics.spacingXXL)
                Spacer()
            case .ready:
                readyContent
            }
        }
        .background(Palette.pageBG)
        .task(id: currentPath) { await load() }
        .fullScreenCover(item: $previewEntry) { entry in
            DataFilePreviewView(name: entry.name) {
                guard let config = appState.config else {
                    throw BoxFilesError.noKey
                }
                return try await client.fileData(
                    config: config, path: entry.path
                )
            }
        }
    }

    @ViewBuilder
    private var readyContent: some View {
        if let listing {
            let crumbs = FileBrowserLogic.relativeBreadcrumbs(
                rootName: "电脑工作区", path: currentPath
            )
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: OneDayMetrics.spacingXS) {
                    ForEach(Array(crumbs.enumerated()), id: \.element.id) {
                        index, crumb in
                        if index > 0 {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 10))
                                .foregroundStyle(Palette.inkMuted)
                                .accessibilityHidden(true)
                        }
                        Button {
                            currentPath = crumb.path
                        } label: {
                            Text(crumb.name)
                                .font(.callout)
                                .foregroundStyle(
                                    index == crumbs.count - 1
                                        ? Palette.ink : Palette.primary
                                )
                        }
                        .buttonStyle(.plain)
                        .disabled(index == crumbs.count - 1)
                    }
                }
            }
            .padding(.horizontal, OneDayMetrics.pageGutter)
            .padding(.bottom, OneDayMetrics.spacingS)
            ScrollView {
                if listing.entries.isEmpty {
                    EmptyState(
                        icon: "folder",
                        title: "这个文件夹是空的",
                        message: "智能体在电脑里生成的文件会出现在这里。"
                    )
                    .padding(.top, OneDayMetrics.spacingXXL)
                } else {
                    VStack(spacing: 0) {
                        ForEach(
                            Array(
                                FileBrowserLogic.sorted(
                                    listing.entries, by: .modified
                                ).enumerated()
                            ),
                            id: \.element.id
                        ) { index, entry in
                            if index > 0 {
                                GroupDivider(
                                    inset: OneDayMetrics.dividerInset
                                )
                            }
                            if entry.isDirectory {
                                Button {
                                    currentPath = entry.path
                                } label: {
                                    FileBrowserRow(entry: entry)
                                }
                                .buttonStyle(.odPressable)
                            } else {
                                Button {
                                    previewEntry = entry
                                } label: {
                                    FileBrowserRow(entry: entry)
                                }
                                .buttonStyle(.odPressable)
                            }
                        }
                    }
                    .odGroup()
                    .padding(.horizontal, OneDayMetrics.pageGutter)
                }
            }
        }
    }

    private func load() async {
        guard let config = appState.config else {
            phase = .notConnected
            return
        }
        do {
            let result = try await client.list(
                config: config,
                path: currentPath.isEmpty ? nil : currentPath
            )
            listing = result
            phase = .ready
        } catch let error as BoxFilesError {
            switch error {
            case .noKey, .unauthorized:
                phase = .notConnected
            case .notAvailable:
                phase = .notAvailable
            case .failed(let message):
                phase = .failed(message)
            }
        } catch {
            phase = .failed("读取电脑文件失败，请稍后再试。")
        }
    }
}

/// 字节直读预览（Box 文件用）：加载字节后图片走与聊天
/// 同一个全屏查看器（data 源），其余落临时文件走
/// QuickLook 原生预览——与 P1 共用组件、不另造。
struct DataFilePreviewView: View {
    @Environment(\.dismiss) private var dismiss
    let name: String
    let loadData: () async throws -> Data

    @State private var imageItem: ChatImageViewerItem?
    @State private var quickLookItem: ChatFilePreviewItem?
    @State private var failedMessage: String?

    var body: some View {
        Group {
            if let imageItem {
                ImageFullScreenView(item: imageItem)
            } else if let quickLookItem {
                VStack(spacing: 0) {
                    HStack {
                        Text(name)
                            .font(.callout)
                            .foregroundStyle(Palette.ink)
                            .lineLimit(1)
                        Spacer()
                        Button("关闭") { dismiss() }
                    }
                    .padding(.horizontal, OneDayMetrics.pageGutter)
                    .padding(.vertical, OneDayMetrics.spacingS)
                    QuickLookPreview(url: quickLookItem.url)
                }
                .background(Palette.pageBG)
            } else if let failedMessage {
                VStack(spacing: OneDayMetrics.spacingM) {
                    EmptyState(
                        icon: "exclamationmark.triangle",
                        title: "预览失败",
                        message: failedMessage
                    )
                    Button("关闭") { dismiss() }
                }
                .padding(.top, OneDayMetrics.spacingXXL)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task {
            do {
                let data = try await loadData()
                if FileBrowserLogic.mimeType(forFileName: name)
                    .hasPrefix("image/"),
                   UIImage(data: data) != nil {
                    imageItem = ChatImageViewerItem(source: .data(data))
                } else {
                    quickLookItem = try ChatFilePreviewItem.write(
                        data: data, name: name
                    )
                }
            } catch {
                failedMessage = (error as? BoxFilesError)
                    .map(boxFilesMessage) ?? "读取文件失败，请稍后再试。"
            }
        }
    }

    private func boxFilesMessage(_ error: BoxFilesError) -> String {
        switch error {
        case .noKey, .unauthorized:
            return "数据桥未连接。"
        case .notAvailable:
            return "电脑文件尚未开通。"
        case .failed(let message):
            return message
        }
    }
}
