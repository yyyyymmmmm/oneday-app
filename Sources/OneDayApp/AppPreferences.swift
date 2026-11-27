import Foundation
import OneDayCore

// MARK: - 强类型本地偏好存储收口（#38：统一 UserDefaults 键治理）

/// 集中收口 AppState 与核心设置页的 UserDefaults 读写，
/// 100% 沿用既有持久化键名，确保老版本升级零数据丢失。
enum AppPreferences {
    private nonisolated(unsafe) static let defaults = UserDefaults.standard

    private enum Key {
        static let selfReactionsAvailability = "selfReactionsAvailability.v1"
        static let legacyChatModelMigrated = "chatModelMigrated149"
        static let legacyChatModelID = "chatModelID"
        static let chatModelBySession = "chatModelBySession"
        static let selfDecidedApprovalIDs = "selfDecidedApprovalIDs"
    }

    // MARK: - AI 自反应能力缓存

    static func selfReactionsAvailability(for base: String?) -> CapabilityAvailability {
        guard let base,
              let dict = defaults.dictionary(forKey: Key.selfReactionsAvailability) as? [String: String]
        else { return .unknown }
        switch dict[base] {
        case "available": return .available
        case "unavailable": return .unavailable
        default: return .unknown
        }
    }

    static func setSelfReactionsAvailability(_ verdict: CapabilityAvailability, for base: String) {
        guard verdict != .unknown else { return }
        var dict = (defaults.dictionary(forKey: Key.selfReactionsAvailability) as? [String: String]) ?? [:]
        dict[base] = verdict == .available ? "available" : "unavailable"
        defaults.set(dict, forKey: Key.selfReactionsAvailability)
    }

    // MARK: - 会话模型选择账

    static var legacyChatModelMigrated: Bool {
        get { defaults.bool(forKey: Key.legacyChatModelMigrated) }
        set { defaults.set(newValue, forKey: Key.legacyChatModelMigrated) }
    }

    static var legacyChatModelID: String? {
        defaults.string(forKey: Key.legacyChatModelID)
    }

    static func loadSessionModelChoices() -> [String: ChatModelChoice] {
        guard let data = defaults.data(forKey: Key.chatModelBySession),
              let dict = try? JSONDecoder().decode([String: [String: String]].self, from: data)
        else { return [:] }
        return dict.compactMapValues { fields in
            guard let model = fields["model"], !model.isEmpty else { return nil }
            return ChatModelChoice(model: model, providerField: fields["provider"])
        }
    }

    static func saveSessionModelChoices(_ choices: [String: ChatModelChoice]) {
        let dict: [String: [String: String]] = choices.mapValues { choice in
            var fields = ["model": choice.model]
            if let provider = choice.providerField {
                fields["provider"] = provider
            }
            return fields
        }
        if let data = try? JSONEncoder().encode(dict) {
            defaults.set(data, forKey: Key.chatModelBySession)
        }
    }

    // MARK: - 已隐藏服务商分组

    static func loadHiddenProviderGroupKeys() -> Set<String> {
        ProviderGroupVisibility.decodeHidden(
            defaults.data(forKey: SectionCollapseStorageKeys.hiddenProviders)
        )
    }

    static func saveHiddenProviderGroupKeys(_ keys: Set<String>) {
        defaults.set(
            ProviderGroupVisibility.encodeHidden(keys),
            forKey: SectionCollapseStorageKeys.hiddenProviders
        )
    }

    // MARK: - 本人已裁决审批 ID 集合

    static func loadSelfDecidedApprovalIDs() -> Set<String> {
        Set(defaults.stringArray(forKey: Key.selfDecidedApprovalIDs) ?? [])
    }

    static func saveSelfDecidedApprovalIDs(_ ids: Set<String>) {
        defaults.set(Array(ids), forKey: Key.selfDecidedApprovalIDs)
    }
}
