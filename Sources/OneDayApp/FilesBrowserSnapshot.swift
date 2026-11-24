import Foundation
import OneDayCore

/// 文件浏览器派生快照（§415，四面收口包）：过滤＋
/// 排序＋图片子集＋路径表一趟算齐，下传列表本体/
/// 查看器目的地/定位 onChange 共用。取代旧形态：
/// shownEntries 计算属性每趟 body 做 filter＋sort
/// （与资源库面 §363 快照口径同 App 双轨，骨架排
/// 查 F4）。
///
/// 等价口径（钉测把守）：派生直接走 FileBrowser-
/// Logic.filtered/sorted 单源、入参顺序与旧 shown-
/// Entries 逐字同（先过滤后排序）；图片子集＝派生
/// 结果里 mediaKind == .image（与旧目的地闭包内
/// filter 同谓词同时点）；路径表＝派生结果逐项
/// path（与旧 onChange 的 map(\.path) 同）。
struct FilesBrowserSnapshot {
    /// 过滤＋排序后的可见条目（列表本体消费）
    let entries: [WorkspaceFileEntry]
    /// 可见条目中的图片子集（图片查看器集合）
    let imageEntries: [WorkspaceFileEntry]
    /// 可见条目路径表（定位 onChange 的观察值）
    let paths: [String]

    static func make(
        entries: [WorkspaceFileEntry]?,
        query: String,
        sortKey: FileBrowserLogic.SortKey,
        ascending: Bool
    ) -> FilesBrowserSnapshot {
        let shown = FileBrowserLogic.sorted(
            FileBrowserLogic.filtered(entries ?? [], query: query),
            by: sortKey, ascending: ascending
        )
        return FilesBrowserSnapshot(
            entries: shown,
            imageEntries: shown.filter { $0.mediaKind == .image },
            paths: shown.map(\.path)
        )
    }
}

/// 文件浏览器派生快照缓存（§415）：快照按全输入
/// 指纹缓存——输入未变直接复用上一份，body 因无
/// 关状态重跑时不整趟重付过滤＋排序。与 Library-
/// SnapshotCache 同式：指纹＝四入参逐值比对（名
/// 单逐项、搜索词、排序键、方向），任一变即整趟
/// 重算——不许显旧（钉测把守修订号）。本类自含、
/// 无外部状态，宿主持 @State 实例；只许主线程触
/// 碰（宿主皆为主 actor 上下文），不做跨线程同步。
final class FilesBrowserSnapshotCache {
    private var lastEntries: [WorkspaceFileEntry]?
    private var lastQuery: String?
    private var lastSortKey: FileBrowserLogic.SortKey?
    private var lastAscending: Bool?
    private var lastSnapshot: FilesBrowserSnapshot?

    /// 快照修订号：每次真重算 +1、命中不增（钉测
    /// 以此断言 body 重跑不重算）
    private(set) var revision = 0

    /// 与 FilesBrowserSnapshot.make 同参同果：首
    /// 调与输入变更时走 make 整趟，命中时回存量
    /// 快照
    func snapshot(
        entries: [WorkspaceFileEntry]?,
        query: String,
        sortKey: FileBrowserLogic.SortKey,
        ascending: Bool
    ) -> FilesBrowserSnapshot {
        if let lastSnapshot,
           lastQuery == query,
           lastSortKey == sortKey,
           lastAscending == ascending,
           Self.entriesEqual(lastEntries, entries) {
            return lastSnapshot
        }
        let made = FilesBrowserSnapshot.make(
            entries: entries, query: query,
            sortKey: sortKey, ascending: ascending
        )
        lastEntries = entries
        lastQuery = query
        lastSortKey = sortKey
        lastAscending = ascending
        lastSnapshot = made
        revision += 1
        return made
    }

    /// 名单逐值比对：nil 与空数组分开记（与 Lib-
    /// rarySnapshotCache 同口径——目录从未加载到
    /// 已加载空目录不许被误判未变）
    private static func entriesEqual(
        _ a: [WorkspaceFileEntry]?, _ b: [WorkspaceFileEntry]?
    ) -> Bool {
        switch (a, b) {
        case (nil, nil):
            return true
        case let (a?, b?):
            return a == b
        default:
            return false
        }
    }
}
