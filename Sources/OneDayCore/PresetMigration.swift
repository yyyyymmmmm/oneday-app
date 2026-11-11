import Foundation

/// 预设存储迁移（复杂化全清第 5 项，用户 2026-11-11
/// 16:33 按抉择书 A 案拍板）：旧组合文档（稀疏 aux、
/// 存伴生桥 meta）→ 预设快照文档（稠密 aux、落 App
/// 本地）。稠密化填法＝A：旧组合缺失的活槽一律填
/// .auto（跟随主模型，与 §119 PresetSnapshot 的显式
/// auto 口径逐字合）；旧组合已有的值逐字保留——含
/// delegation/fallback 与注册表外的 aux 键（死槽、
/// 未知键都在内，aux 是开放字典，保留才无损）。
///
/// 本函数是无环境依赖的纯变换：不读 config、不等
/// 连接，启动时即可跑且幂等（对已稠密文档再跑结果
/// 不变）。迁移前后逐条对账由 verify 把守：条数、
/// active 标记、逐槽位映射全等才算一致。
public enum PresetMigration {

    /// 一个槽位在迁移中的去向
    public enum SlotAction: Equatable, Sendable {
        /// 旧文档已有此键，值逐字保留
        case kept
        /// 旧文档缺此活槽，按 A 案填跟随
        case filledFollow
    }

    public struct SlotMapping: Equatable, Sendable {
        public var comboID: String
        public var slot: String
        public var action: SlotAction

        public init(comboID: String, slot: String, action: SlotAction) {
            self.comboID = comboID
            self.slot = slot
            self.action = action
        }
    }

    /// 对账报告：迁移留痕用（条数/active/逐槽位映射
    /// ＋一致性结论），App 侧落盘记账
    public struct Report: Equatable, Sendable {
        public var comboCount: Int
        public var activeComboID: String?
        public var mappings: [SlotMapping]
        public var isConsistent: Bool

        public var filledCount: Int {
            mappings.filter { $0.action == .filledFollow }.count
        }

        public init(
            comboCount: Int, activeComboID: String?,
            mappings: [SlotMapping], isConsistent: Bool
        ) {
            self.comboCount = comboCount
            self.activeComboID = activeComboID
            self.mappings = mappings
            self.isConsistent = isConsistent
        }
    }

    public struct Result: Sendable {
        public var document: ModelComboDocument
        public var report: Report

        public init(document: ModelComboDocument, report: Report) {
            self.document = document
            self.report = report
        }
    }

    /// 迁移主口：旧文档 → 稠密快照文档＋对账报告。
    /// 组合次序、id、name、mainModel、delegation、
    /// fallback、includesFallback、updatedAt 全部原样；
    /// aux 先按注册表活槽序写全 19 槽（缺失填跟随），
    /// 再补注册表外旧键（按字典序，值逐字保留）。
    public static func migrate(
        _ legacy: ModelComboDocument
    ) -> Result {
        var mappings: [SlotMapping] = []
        var combos: [ModelCombo] = []
        combos.reserveCapacity(legacy.combos.count)
        let liveKeys = AuxSlotCatalog.all.map(\.key)
        let liveSet = Set(liveKeys)
        for combo in legacy.combos {
            var aux: [String: SlotChoice] = [:]
            for key in liveKeys {
                if let existing = combo.aux[key] {
                    aux[key] = existing
                    mappings.append(SlotMapping(
                        comboID: combo.id, slot: key, action: .kept
                    ))
                } else {
                    aux[key] = .auto
                    mappings.append(SlotMapping(
                        comboID: combo.id, slot: key,
                        action: .filledFollow
                    ))
                }
            }
            for key in combo.aux.keys.sorted()
            where !liveSet.contains(key) {
                aux[key] = combo.aux[key]
                mappings.append(SlotMapping(
                    comboID: combo.id, slot: key, action: .kept
                ))
            }
            combos.append(ModelCombo(
                id: combo.id, name: combo.name,
                mainModel: combo.mainModel, aux: aux,
                delegation: combo.delegation,
                fallback: combo.fallback,
                includesFallback: combo.includesFallback,
                updatedAt: combo.updatedAt
            ))
        }
        let document = ModelComboDocument(
            combos: combos, activeComboID: legacy.activeComboID
        )
        let report = Report(
            comboCount: legacy.combos.count,
            activeComboID: legacy.activeComboID,
            mappings: mappings,
            isConsistent: verify(legacy: legacy, migrated: document)
        )
        return Result(document: document, report: report)
    }

    /// 对账：迁移结果与旧文档逐条核对——条数与次序、
    /// active 标记、每套的标量字段全等；每个活槽等于
    /// 「旧值或跟随」；注册表外旧键逐字在；迁移结果
    /// 不许多出旧文档与活槽之外的 aux 键。
    public static func verify(
        legacy: ModelComboDocument, migrated: ModelComboDocument
    ) -> Bool {
        guard migrated.combos.count == legacy.combos.count,
              migrated.activeComboID == legacy.activeComboID
        else { return false }
        let liveSet = Set(AuxSlotCatalog.all.map(\.key))
        for (old, new) in zip(legacy.combos, migrated.combos) {
            guard old.id == new.id, old.name == new.name,
                  old.mainModel == new.mainModel,
                  old.delegation == new.delegation,
                  old.fallback == new.fallback,
                  old.includesFallback == new.includesFallback,
                  old.updatedAt == new.updatedAt
            else { return false }
            for key in liveSet {
                let expected = old.aux[key] ?? .auto
                guard new.aux[key] == expected else { return false }
            }
            for (key, value) in old.aux where !liveSet.contains(key) {
                guard new.aux[key] == value else { return false }
            }
            let allowed = liveSet.union(old.aux.keys)
            guard Set(new.aux.keys).isSubset(of: allowed)
            else { return false }
        }
        return true
    }
}
