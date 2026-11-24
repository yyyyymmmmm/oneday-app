import Foundation

/// 本地库迁移前备份（根治版包 3，DESIGN §332）：
/// 容器带迁移链打开落盘库之前，把库文件整组（主
/// 文件＋-wal/-shm 边车）复制为带版本与时间戳的
/// 备份——迁移/打开失败时的回滚点（工程通则兜
/// 底，规格 §3.3）。保留最近 2 组，旧组整组清理。
/// 命名：<库文件名>.backup-<版本>-<yyyyMMddHHmmss>
/// （边车同名加 -wal/-shm 后缀，备份组可按原库
/// 方式直接打开）
enum ChatStoreBackup {
    static let retentionCount = 2

    /// 库文件不存在（首装）回 nil；存在则复制整组
    /// 并轮转保留，返回备份主文件 URL。复制失败抛
    /// 错——调用方留痕后继续打开原库：备份是兜底，
    /// 不是打开的前置闸，备份失败不许把 App 砖死
    @discardableResult
    static func backupStoreIfPresent(
        at storeURL: URL, versionTag: String,
        fileManager: FileManager = .default,
        now: Date = Date()
    ) throws -> URL? {
        guard fileManager.fileExists(atPath: storeURL.path)
        else { return nil }
        let directory = storeURL.deletingLastPathComponent()
        let storeName = storeURL.lastPathComponent
        let stamp = Self.stampFormatter.string(from: now)
        var baseName =
            "\(storeName).backup-\(versionTag)-\(stamp)"
        var mainBackup = directory
            .appendingPathComponent(baseName)
        var counter = 2
        while fileManager.fileExists(atPath: mainBackup.path) {
            baseName =
                "\(storeName).backup-\(versionTag)-\(stamp)-\(counter)"
            mainBackup = directory
                .appendingPathComponent(baseName)
            counter += 1
        }
        try fileManager.copyItem(at: storeURL, to: mainBackup)
        for suffix in ["-wal", "-shm"] {
            let sidecar = URL(
                fileURLWithPath: storeURL.path + suffix
            )
            if fileManager.fileExists(atPath: sidecar.path) {
                try fileManager.copyItem(
                    at: sidecar,
                    to: URL(
                        fileURLWithPath: mainBackup.path + suffix
                    )
                )
            }
        }
        pruneOldBackups(
            in: directory, storeName: storeName,
            fileManager: fileManager
        )
        return mainBackup
    }

    /// 保留最近 retentionCount 组：按备份主文件名
    /// 排序（时间戳定宽、字典序即时序），旧组主文
    /// 件与边车一并删
    private static func pruneOldBackups(
        in directory: URL, storeName: String,
        fileManager: FileManager
    ) {
        guard let names = try? fileManager
            .contentsOfDirectory(atPath: directory.path)
        else { return }
        let prefix = "\(storeName).backup-"
        let mains = names.filter {
            $0.hasPrefix(prefix)
                && !$0.hasSuffix("-wal")
                && !$0.hasSuffix("-shm")
        }.sorted()
        guard mains.count > retentionCount else { return }
        for name in mains.dropLast(retentionCount) {
            for suffix in ["", "-wal", "-shm"] {
                try? fileManager.removeItem(
                    atPath: directory
                        .appendingPathComponent(name + suffix)
                        .path
                )
            }
        }
    }

    private static let stampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMddHHmmss"
        return formatter
    }()
}
