import OneDayCore
import XCTest

/// 聊天模型接线口径（0.3.0，DESIGN-V4 §15；0.32.1
/// F05 止血后清单两项＋Qwen 下线口径，§60）。
final class ChatModelsTests: XCTestCase {
    /// 0.32.1 前的 Qwen id（下线判定与历史名映射的锚）
    private let qwenID = "Qwen/Qwen3-30B-A3B-Instruct-2507-FP8"

    /// 可选清单只剩 DeepSeek 两项、顺序与 id 不许漂移
    /// （Qwen 已下线：上游拆除＋渠道禁用，见 §60）
    func testFixedListOfTwo() {
        XCTAssertEqual(
            ChatModels.items.map(\.id),
            [
                "deepseek-flash",
                "deepseek-v4-pro",
            ]
        )
        XCTAssertFalse(ChatModels.contains(qwenID))
    }

    /// 清单内带 provider=custom，清单外（网关别名与
    /// 已下线模型）不带
    func testProviderField() {
        XCTAssertEqual(
            ChatModels.providerField(for: "deepseek-flash"), "custom"
        )
        XCTAssertNil(ChatModels.providerField(for: qwenID))
        XCTAssertNil(ChatModels.providerField(for: "hermes-agent"))
    }

    /// 短名映射（0.4.1，身份胶囊窄档）：整词缩短、
    /// 不截断词中间；清单外回全名口径（不许字符串截断）
    func testShortDisplayNames() {
        XCTAssertEqual(
            ChatModels.shortDisplayName(for: "deepseek-flash"), "Flash"
        )
        XCTAssertEqual(
            ChatModels.shortDisplayName(for: "deepseek-v4-pro"), "V4 Pro"
        )
        for item in ChatModels.items {
            XCTAssertTrue(
                item.displayName.hasSuffix(item.shortDisplayName),
                "短名须是全名的整词收尾，不许截断词中间"
            )
            XCTAssertLessThan(
                item.shortDisplayName.count, item.displayName.count
            )
        }
        XCTAssertEqual(
            ChatModels.shortDisplayName(for: "unknown-model"),
            "unknown-model"
        )
    }

    /// 初始选择：已存 > 服务端默认（须在清单内）> fallback；
    /// 已存为已下线模型时落回 fallback（F05 止血核心）
    func testInitialSelection() {
        XCTAssertEqual(
            ChatModels.initialSelection(
                stored: "deepseek-v4-pro", serverDefault: "deepseek-flash"
            ),
            "deepseek-v4-pro"
        )
        XCTAssertEqual(
            ChatModels.initialSelection(
                stored: "hermes-agent", serverDefault: "deepseek-v4-pro"
            ),
            "deepseek-v4-pro"
        )
        XCTAssertEqual(
            ChatModels.initialSelection(
                stored: nil, serverDefault: "hermes-agent"
            ),
            "deepseek-flash"
        )
        XCTAssertEqual(
            ChatModels.initialSelection(
                stored: qwenID, serverDefault: nil
            ),
            "deepseek-flash"
        )
    }

    /// 已下线模型：isRetired 命中、显示名/短名映射保
    /// 留（历史消息名牌不许掉成原始 id 或「服务端默认」）
    func testRetiredModelNamesSurvive() {
        XCTAssertTrue(ChatModels.isRetired(qwenID))
        XCTAssertFalse(ChatModels.isRetired("deepseek-flash"))
        XCTAssertEqual(ChatModels.displayName(for: qwenID), "Qwen3-30B")
        XCTAssertEqual(ChatModels.shortDisplayName(for: qwenID), "Qwen3")
        XCTAssertEqual(
            ModelDisplayNames.displayName(for: qwenID), "Qwen3-30B"
        )
    }

    /// 落回提示：仅已存选择命中已下线模型时有文案，
    /// 其余情况 nil 不打扰
    func testRetiredFallbackNotice() {
        let notice = ChatModels.retiredFallbackNotice(stored: qwenID)
        XCTAssertNotNil(notice)
        XCTAssertTrue(notice?.contains("Qwen3-30B") ?? false)
        XCTAssertTrue(notice?.contains("已停用") ?? false)
        XCTAssertNil(
            ChatModels.retiredFallbackNotice(stored: "deepseek-flash")
        )
        XCTAssertNil(ChatModels.retiredFallbackNotice(stored: nil))
        XCTAssertNil(
            ChatModels.retiredFallbackNotice(stored: "hermes-agent")
        )
    }
}
