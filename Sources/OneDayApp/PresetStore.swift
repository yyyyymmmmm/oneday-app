import Foundation
import OneDayCore

/// 预设本地存储（复杂化全清第 5 项）：预设定义落 App
/// 本地 UserDefaults JSON 文档（与 SideChatStore 同
/// 模式）。0.37 §5「服务端为真源、防多设备双账」的
/// 旧口径随本项放弃——预设变本机数据、多设备不互通
/// （用户 2026-11-11 16:33 按抉择书 A 案拍板）。
/// 稠密化与对账在 Core PresetMigration，本类只管落
/// 盘、迁移标记与迁移留痕。
@MainActor
@Observable
final class PresetStore {
    private(set) var document: ModelComboDocument
    /// 迁移已完成（标记落盘后永不再读服务端旧档）
    private(set) var migrated: Bool
    /// 迁移对账留痕（条数/填跟随数/一致性/时刻）
    private(set) var migrationReport: String?

    private let defaults: UserDefaults

    private enum Key {
        static let document = "presets.document"
        static let migrated = "presets.migrated"
        static let migrationReport = "presets.migrationReport"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        migrated = defaults.bool(forKey: Key.migrated)
        migrationReport = defaults.string(forKey: Key.migrationReport)
        if let data = defaults.data(forKey: Key.document),
           let decoded = try? JSONDecoder().decode(
               ModelComboDocument.self, from: data
           ) {
            document = decoded
        } else {
            document = .empty
        }
    }

    /// 本地文档整体替换（保存/删除/激活标记共用一口）
    func replace(_ document: ModelComboDocument) {
        self.document = document
        if let data = try? JSONEncoder().encode(document) {
            defaults.set(data, forKey: Key.document)
        }
    }

    /// 迁移落定：写本地文档＋置标记＋记对账留痕，
    /// 三件一次做完，之后旧档读取器永不再被调用
    func completeMigration(
        _ document: ModelComboDocument, report: String
    ) {
        replace(document)
        migrated = true
        migrationReport = report
        defaults.set(true, forKey: Key.migrated)
        defaults.set(report, forKey: Key.migrationReport)
    }
}

/// 一次性旧档读取器（第 5 项迁移专用）：最后读一次
/// 伴生桥 meta 上的旧组合文档，供 Core 稠密化迁移。
/// 由 PresetStore.migrated 标记门控——标记落盘后永
/// 不再调用，迁移完成后 App 不再碰 combos 端点（端
/// 点本体由伴生线随后删除）。只读、无写口。
final class LegacyComboReader: @unchecked Sendable {
    private let session: URLSession
    private let decoder = JSONDecoder()

    init() {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 15
        session = URLSession(configuration: configuration)
    }

    func loadDocument(
        config: ServerConfig
    ) async throws -> ModelComboDocument {
        let endpoint = L10n.string("组合清单")
        guard let key = BridgeCredential.read(), !key.isEmpty else {
            throw OneDayBridgeError.noKey
        }
        var request = URLRequest(
            url: config.endpoint("/api/oneday-bridge/meta/model-combos")
        )
        request.httpMethod = "GET"
        request.setValue(
            "Bearer \(key)", forHTTPHeaderField: "Authorization"
        )
        let data: Data
        let http: HTTPURLResponse
        do {
            let (rawData, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw OneDayBridgeError.failed(
                    L10n.format("%@无响应", endpoint)
                )
            }
            data = rawData
            http = httpResponse
        } catch let error as OneDayBridgeError {
            throw error
        } catch {
            throw OneDayBridgeError.failed(
                L10n.format("%@网络不可达", endpoint)
            )
        }
        switch http.statusCode {
        case 200...299:
            break
        case 401:
            throw OneDayBridgeError.unauthorized
        case 404:
            throw OneDayBridgeError.bridgeMissing
        default:
            throw OneDayBridgeError.failed(
                L10n.format("%@返回 %@", endpoint, String(http.statusCode))
            )
        }
        do {
            return try decoder.decode(ModelComboDocument.self, from: data)
        } catch {
            throw OneDayBridgeError.failed(
                L10n.format("%@返回格式无法识别", endpoint)
            )
        }
    }
}
