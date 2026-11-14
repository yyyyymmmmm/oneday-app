import OneDayCore
import XCTest

/// 主线模型化石迁移裁决（§216.2）：五条合取的决策
/// 矩阵——命中两处置（清条/迁入）与不命中各形态逐
/// 条钉死。入参口径：storeStored＝钦定副本键存量、
/// threadStored＝线程绑定键存量、threadResolved＝线
/// 程绑定账现行解析值、server＝钦定会话服务端行
/// model 字段。
final class MainlineModelFossilMigrationTests: XCTestCase {

    private let fossil = ChatModelChoice(
        model: "deepseek-flash", providerField: nil
    )
    private let claude = ChatModelChoice(
        model: "claude-sonnet-4-6", providerField: "custom"
    )

    private func decide(
        diverged: Bool = true,
        storeStored: ChatModelChoice? = nil,
        threadStored: ChatModelChoice? = nil,
        threadResolved: String = "claude-sonnet-4-6",
        server: String? = "deepseek-flash"
    ) -> MainlineModelFossilMigration.Action {
        MainlineModelFossilMigration.action(
            copiesDiverged: diverged,
            storeStored: storeStored,
            threadStored: threadStored,
            threadResolvedModel: threadResolved,
            serverReportedModel: server
        )
    }

    // MARK: - 命中

    /// 全形态命中、线程账无存量 → 清钦定键条目（合
    /// 一账回落解析链，落值＝线程账现行解析值）
    func testHitWithoutThreadStoredClearsStoreEntry() {
        XCTAssertEqual(
            decide(storeStored: fossil), .clearStoreEntry
        )
    }

    /// 全形态命中、线程账有真选择 → 以线程账条目迁
    /// 入钦定键（真选择成为合一账存量，不许清掉）
    func testHitWithThreadStoredAdoptsThreadStored() {
        XCTAssertEqual(
            decide(storeStored: fossil, threadStored: claude),
            .adoptThreadStored
        )
    }

    // MARK: - 不命中（逐条形态）

    /// 副本同值＝单账常态：存量与真选择不可区分，
    /// 即使条目恰与服务端行同值也绝不许动
    func testKeepWhenCopiesConverged() {
        XCTAssertEqual(
            decide(diverged: false, storeStored: fossil), .keep
        )
    }

    /// 钦定键无存量条目 → 无可清
    func testKeepWhenNoStoreEntry() {
        XCTAssertEqual(decide(storeStored: nil), .keep)
    }

    /// 钦定键条目不是该会话的服务端化石（用户在枢
    /// 纽账自选了别的模型）→ 不动
    func testKeepWhenStoreValueDiffersFromServerModel() {
        XCTAssertEqual(
            decide(storeStored: claude, server: "deepseek-flash"),
            .keep
        )
    }

    /// 服务端行 model 是别的值 → 钦定键的 deepseek
    /// 条目不是「该会话」的化石（可能是用户真选）
    /// → 不动
    func testKeepWhenServerModelIsAnotherValue() {
        XCTAssertEqual(
            decide(storeStored: fossil, server: "gpt-5.6-terra"),
            .keep
        )
    }

    /// 线程账解析值与化石同值（用户真选 deepseek、
    /// 两账同值）→ 两面本已一致，不动——真选不殃及
    func testKeepWhenThreadAccountResolvesToSameFossil() {
        XCTAssertEqual(
            decide(
                storeStored: fossil, threadStored: fossil,
                threadResolved: "deepseek-flash"
            ),
            .keep
        )
    }

    /// 服务端值取不到（离线/回读失败）→ 不裁决，
    /// 留待下次（App 侧 runner 据此不置一次性标记）
    func testKeepWhenServerModelUnknown() {
        XCTAssertEqual(
            decide(storeStored: fossil, server: nil), .keep
        )
        XCTAssertEqual(
            decide(storeStored: fossil, server: ""), .keep
        )
    }
}
