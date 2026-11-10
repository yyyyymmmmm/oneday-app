import OneDayCore
import XCTest

/// 钥匙组导入解析（0.32.1，审计 F03/R8）：格式与服务
/// 器侧 bridge-keys.txt 逐字对齐——每行 `scope: 钥匙`，
/// 五个 scope 标签；说明行/空行跳过，认不出的行计数
/// 如实上报，同 scope 后行覆盖先行。
final class BridgeKeyImportTests: XCTestCase {
    /// 标准五项整段（带文件头说明行）一次解析全中
    func testParsesCanonicalBlock() {
        let text = """
        # OneDay 桥钥匙组（bridge-keys）——整段粘贴到 App 设置页导入
        // 生成于服务器侧，请勿外传
        overview: aaaa1111
        oneday: bbbb2222
        writegate: cccc3333
        box: dddd4444
        device: eeee5555
        """
        let result = BridgeKeyImport.parse(text)
        XCTAssertEqual(result.keys.count, 5)
        XCTAssertEqual(result.keys[.overview], "aaaa1111")
        XCTAssertEqual(result.keys[.oneday], "bbbb2222")
        XCTAssertEqual(result.keys[.writegate], "cccc3333")
        XCTAssertEqual(result.keys[.box], "dddd4444")
        XCTAssertEqual(result.keys[.device], "eeee5555")
        XCTAssertEqual(result.ignoredLineCount, 0)
    }

    /// 全角冒号、标签大小写/连字符/下划线变体、值两侧
    /// 空白都容忍
    func testToleratesFormattingVariants() {
        let text = """
        Overview：  key-one
        write-gate:key-two
        WRITE_GATE: key-three
          box  :   key-four
        """
        let result = BridgeKeyImport.parse(text)
        XCTAssertEqual(result.keys[.overview], "key-one")
        // write-gate 与 WRITE_GATE 同 scope，后行覆盖
        XCTAssertEqual(result.keys[.writegate], "key-three")
        XCTAssertEqual(result.keys[.box], "key-four")
        XCTAssertEqual(result.ignoredLineCount, 0)
    }

    /// 认不出的行计数上报、不静默吞：未知标签、无冒
    /// 号行、空钥值行各一
    func testCountsIgnoredLines() {
        let text = """
        overview: ok-key
        notion: not-a-scope
        这行没有冒号
        box:
        """
        let result = BridgeKeyImport.parse(text)
        XCTAssertEqual(result.keys, [.overview: "ok-key"])
        XCTAssertEqual(result.ignoredLineCount, 3)
    }

    /// 空文本与纯说明文本：零钥、零忽略（不误报）
    func testEmptyAndCommentOnly() {
        XCTAssertEqual(BridgeKeyImport.parse("").keys.count, 0)
        let comments = BridgeKeyImport.parse("# 说明\n\n// 另一行说明\n")
        XCTAssertEqual(comments.keys.count, 0)
        XCTAssertEqual(comments.ignoredLineCount, 0)
    }

    /// 钥值内部字符原样保留（只清首尾空白）
    func testPreservesKeyInnerCharacters() {
        let result = BridgeKeyImport.parse("device:  ab-cd_ef.12  \n")
        XCTAssertEqual(result.keys[.device], "ab-cd_ef.12")
    }

    /// scope 标签全集与导入标签逐字一致（与服务器侧
    /// bridge-keys.txt 的契约锚点）
    func testScopeLabelsMatchRawValues() {
        XCTAssertEqual(
            BridgeKeyScope.allCases.map(\.importLabel),
            ["overview", "oneday", "writegate", "box", "device"]
        )
        XCTAssertEqual(BridgeKeyScope.allCases.count, 5)
    }
}
