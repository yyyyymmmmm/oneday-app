import Foundation

/// 手机本地智能体包库（台账 165，DESIGN §393）：
/// 从服务器下载到手机的档案包（tar.gz）存 App
/// 沙盒 Documents/AgentPackages——包与服务器解
/// 耦：在一台服务器下载、切到另一台再装，是
/// 「成包」跨机流的中转站。本件只管本地文件
/// 存取，不碰网络；包本体口径在 Core
/// ProfilePackage。
enum AgentPackageLibrary {

    struct LocalPackage: Identifiable, Equatable {
        let fileName: String
        let byteCount: Int64
        let modifiedAt: Date?

        var id: String { fileName }
    }

    static var directory: URL {
        let docs = FileManager.default.urls(
            for: .documentDirectory, in: .userDomainMask
        )[0]
        return docs.appendingPathComponent(
            "AgentPackages", isDirectory: true
        )
    }

    static func url(for fileName: String) -> URL {
        directory.appendingPathComponent(
            (fileName as NSString).lastPathComponent
        )
    }

    /// 本地包名单（新包在前）：只认档案包扩展名
    static func list() -> [LocalPackage] {
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(
            atPath: directory.path
        ) else { return [] }
        return names
            .filter {
                $0.lowercased().hasSuffix(".tar.gz")
                    || $0.lowercased().hasSuffix(".tgz")
            }
            .map { name in
                let attrs = try? fm.attributesOfItem(
                    atPath: url(for: name).path
                )
                return LocalPackage(
                    fileName: name,
                    byteCount: (attrs?[.size] as? NSNumber)?
                        .int64Value ?? 0,
                    modifiedAt: attrs?[.modificationDate]
                        as? Date
                )
            }
            .sorted {
                ($0.modifiedAt ?? .distantPast)
                    > ($1.modifiedAt ?? .distantPast)
            }
    }

    /// 存入本地库（同名覆盖：同一包重新下载即
    /// 刷新副本）；返回落盘 URL 供分享
    @discardableResult
    static func save(
        data: Data, fileName: String
    ) throws -> URL {
        let fm = FileManager.default
        try fm.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let target = url(for: fileName)
        try data.write(to: target, options: .atomic)
        return target
    }

    static func read(fileName: String) throws -> Data {
        try Data(contentsOf: url(for: fileName))
    }

    static func delete(fileName: String) {
        try? FileManager.default.removeItem(
            at: url(for: fileName)
        )
    }
}
