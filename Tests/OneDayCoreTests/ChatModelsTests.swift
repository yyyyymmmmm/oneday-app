import OneDayCore
import XCTest

/// 聊天模型接线口径（0.3.0，DESIGN-V4 §15）。
final class ChatModelsTests: XCTestCase {
    /// 清单写死三项、顺序与 id 不许漂移（服务端实测口径）
    func testFixedListOfThree() {
        XCTAssertEqual(
            ChatModels.items.map(\.id),
            [
                "deepseek-flash",
                "deepseek-v4-pro",
                "Qwen/Qwen3-30B-A3B-Instruct-2507-FP8",
            ]
        )
    }

    /// 清单内带 provider=custom，清单外（网关别名）不带
    func testProviderField() {
        XCTAssertEqual(
            ChatModels.providerField(for: "deepseek-flash"), "custom"
        )
        XCTAssertEqual(
            ChatModels.providerField(for: ChatModels.coldStartID),
            "custom"
        )
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
        XCTAssertEqual(
            ChatModels.shortDisplayName(for: ChatModels.coldStartID),
            "Qwen3"
        )
        for item in ChatModels.items {
            XCTAssertTrue(
                item.displayName.hasSuffix(item.shortDisplayName)
                    || item.shortDisplayName == "Qwen3",
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

    /// 初始选择：已存 > 服务端默认（须在清单内）> fallback
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
    }
}
