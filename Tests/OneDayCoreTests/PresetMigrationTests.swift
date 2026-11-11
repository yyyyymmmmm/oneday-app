import XCTest
@testable import OneDayCore

/// 预设存储迁移钉测（复杂化全清第 5 项，A 案）：
/// 稠密化填跟随、旧值逐字保留、对账与幂等
final class PresetMigrationTests: XCTestCase {

    private func combo(
        id: String, aux: [String: SlotChoice],
        mainModel: String? = nil,
        delegation: SlotChoice? = nil,
        fallback: [SlotChoice] = [],
        includesFallback: Bool = false
    ) -> ModelCombo {
        ModelCombo(
            id: id, name: "预设\(id)", mainModel: mainModel,
            aux: aux, delegation: delegation, fallback: fallback,
            includesFallback: includesFallback, updatedAt: 42
        )
    }

    func testEmptyDocument() {
        let result = PresetMigration.migrate(.empty)
        XCTAssertEqual(result.document, .empty)
        XCTAssertEqual(result.report.comboCount, 0)
        XCTAssertNil(result.report.activeComboID)
        XCTAssertTrue(result.report.mappings.isEmpty)
        XCTAssertTrue(result.report.isConsistent)
    }

    func testPureSparseComboFillsFollow() {
        let vision = SlotChoice(provider: "甲厂", model: "cheap-1")
        let legacy = ModelComboDocument(
            combos: [combo(id: "a", aux: ["vision": vision])],
            activeComboID: "a"
        )
        let result = PresetMigration.migrate(legacy)
        let migrated = result.document.combos[0]
        XCTAssertEqual(migrated.aux.count, 19, "活槽全稠密")
        XCTAssertEqual(migrated.aux["vision"], vision)
        for slot in AuxSlotCatalog.all where slot.key != "vision" {
            XCTAssertEqual(
                migrated.aux[slot.key], .auto,
                "缺失活槽 \(slot.key) 应按 A 案填跟随"
            )
        }
        XCTAssertEqual(result.document.activeComboID, "a")
        XCTAssertEqual(result.report.filledCount, 18)
        XCTAssertTrue(result.report.isConsistent)
    }

    func testPureDenseComboIsIdentity() {
        var aux: [String: SlotChoice] = [:]
        for slot in AuxSlotCatalog.all {
            aux[slot.key] = .auto
        }
        aux["approval"] = SlotChoice(provider: "main", model: "x")
        let dense = combo(id: "d", aux: aux)
        let result = PresetMigration.migrate(
            ModelComboDocument(combos: [dense], activeComboID: nil)
        )
        XCTAssertEqual(result.document.combos[0], dense)
        XCTAssertEqual(result.report.filledCount, 0)
        XCTAssertTrue(result.report.isConsistent)
    }

    func testMixedDocumentPreservesScalarsAndOrder() {
        let delegation = SlotChoice(provider: "main", model: "d-1")
        let fallback = [SlotChoice(provider: "甲厂", model: "f-1")]
        let sparse = combo(
            id: "s", aux: ["vision": .auto], mainModel: "m-1",
            delegation: delegation, fallback: fallback,
            includesFallback: true
        )
        var denseAux: [String: SlotChoice] = [:]
        for slot in AuxSlotCatalog.all { denseAux[slot.key] = .auto }
        let dense = combo(id: "t", aux: denseAux)
        let legacy = ModelComboDocument(
            combos: [sparse, dense], activeComboID: "t"
        )
        let result = PresetMigration.migrate(legacy)
        XCTAssertEqual(result.document.combos.map(\.id), ["s", "t"])
        let first = result.document.combos[0]
        XCTAssertEqual(first.mainModel, "m-1")
        XCTAssertEqual(first.delegation, delegation)
        XCTAssertEqual(first.fallback, fallback)
        XCTAssertTrue(first.includesFallback)
        XCTAssertEqual(result.document.activeComboID, "t")
        XCTAssertTrue(result.report.isConsistent)
    }

    func testOutOfCatalogKeysPreservedVerbatim() {
        let dead = SlotChoice(provider: "main", model: "old-1")
        let future = SlotChoice(provider: "乙厂", model: "new-1")
        let legacy = ModelComboDocument(
            combos: [combo(id: "k", aux: [
                "web_extract": dead, "future_slot": future,
            ])],
            activeComboID: nil
        )
        let result = PresetMigration.migrate(legacy)
        let migrated = result.document.combos[0]
        XCTAssertEqual(migrated.aux.count, 21, "19 活槽＋2 注册表外键")
        XCTAssertEqual(migrated.aux["web_extract"], dead)
        XCTAssertEqual(migrated.aux["future_slot"], future)
        XCTAssertTrue(result.report.isConsistent)
    }

    func testIdempotentSecondRun() {
        let legacy = ModelComboDocument(
            combos: [combo(id: "a", aux: [
                "vision": SlotChoice(provider: "甲厂", model: "v"),
            ])],
            activeComboID: "a"
        )
        let once = PresetMigration.migrate(legacy)
        let twice = PresetMigration.migrate(once.document)
        XCTAssertEqual(twice.document, once.document)
        XCTAssertEqual(twice.report.filledCount, 0)
        XCTAssertTrue(twice.report.isConsistent)
    }

    func testVerifyCatchesTampering() {
        let legacy = ModelComboDocument(
            combos: [combo(id: "a", aux: [:])], activeComboID: nil
        )
        var tampered = PresetMigration.migrate(legacy).document
        tampered.combos[0].aux["vision"] = SlotChoice(
            provider: "甲厂", model: "sneaky"
        )
        XCTAssertFalse(PresetMigration.verify(
            legacy: legacy, migrated: tampered
        ))
        var dropped = PresetMigration.migrate(legacy).document
        dropped.combos[0].aux["monitor"] = nil
        XCTAssertFalse(PresetMigration.verify(
            legacy: legacy, migrated: dropped
        ))
    }
}
