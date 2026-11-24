import XCTest

/// §332（二次修复题 3）结构断言：composerCard 内
/// 引用块已移出 SmoothExpand 的 @State 高度量测
/// 反馈环——与附件条同构造（卡 VStack 直接子级
/// ＋条件包含，quote＋分隔线同进同出），三变体
/// （quote/feed/source）同槽全覆盖；舱高口径不
/// 变（整卡实测高回写仍在卡层 onGeometryChange）。
/// 结构层守护的理由与本仓源码守护族同：量测环
/// 的病灶是视图树位置本身，运行时帧读数在 CI 无
/// 有效信号（真机终判归用户），位置回归必须在
/// 源码层钉死
final class ChatComposerQuote332Tests: XCTestCase {

    private func composerCardCode() throws -> String {
        let testFile = URL(fileURLWithPath: #filePath)
        let repositoryRoot = testFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let url = repositoryRoot.appendingPathComponent(
            "Sources/OneDayApp/ChatView.swift"
        )
        let raw = try String(contentsOf: url, encoding: .utf8)
        let start = try XCTUnwrap(
            raw.range(of: "private var composerCard"),
            "ChatView 须有 composerCard"
        )
        let tail = raw[start.lowerBound...]
        let end = try XCTUnwrap(
            tail.range(of: "private var composerRow"),
            "composerCard 后须有 composerRow 作界"
        )
        return Self.stripComments(
            String(tail[..<end.lowerBound])
        )
    }

    /// 引用块不在 SmoothExpand 子树：composerCard
    /// 整段代码（去注释）不许再出现 SmoothExpand
    /// 实例化——引用块与附件条都已直挂卡根
    func testComposerCardHasNoSmoothExpand() throws {
        let code = try composerCardCode()
        XCTAssertFalse(
            code.contains("SmoothExpand("),
            "composerCard 内不许再有 SmoothExpand"
                + "（引用块须在量测环外）"
        )
    }

    /// 三变体同槽直挂：quote/feed/source 三个条本
    /// 体都在 composerCard 内以条件包含出现，分隔
    /// 线随条同进同出（同 VStack 内的 hairline
    /// Rectangle 在席）
    func testQuoteVariantsAreDirectChildren() throws {
        let code = try composerCardCode()
        XCTAssertTrue(
            code.contains("quoteBar(pendingQuote)"),
            "消息引用变体须在槽内"
        )
        XCTAssertTrue(
            code.contains(
                "feedQuoteBar(pendingFeedQuote)"
            ),
            "动态引用变体须在槽内"
        )
        XCTAssertTrue(
            code.contains(
                "sourceQuoteBar(pendingSourceQuote)"
            ),
            "点子/文件引用变体须在槽内"
        )
        XCTAssertTrue(
            code.contains("if !attachments.isEmpty"),
            "附件条须仍是卡根直接子级条件包含"
        )
    }

    /// 舱高口径不变：整卡实测高回写（卡层
    /// onGeometryChange→composerCapsuleHeight）仍
    /// 在 composerCard，引用块高计入整卡实测、不
    /// 经任何独立量测环；引用在场态已挂卡根动画
    /// 键（高度插值承接）
    func testComposerHeightAccountingUnchanged() throws {
        let code = try composerCardCode()
        XCTAssertTrue(
            code.contains(
                ".onGeometryChange(for: CGFloat.self)"
            ),
            "整卡实测高回写须仍在卡层"
        )
        XCTAssertTrue(
            code.contains("composerCapsuleHeight"),
            "舱高回写目标须仍是 composerCapsuleHeight"
        )
        XCTAssertTrue(
            code.contains("value: pendingQuote != nil"),
            "引用在场态须挂卡根动画键承接高变插值"
        )
    }

    /// 去注释（行/块）与字符串字面量——断言只读
    /// 代码本体，不被沿革注释里的旧形态字样误伤
    private static func stripComments(
        _ source: String
    ) -> String {
        var result = ""
        var index = source.startIndex
        var inLineComment = false
        var inBlockComment = false
        var inString = false
        var escaped = false
        while index < source.endIndex {
            let character = source[index]
            let nextIndex = source.index(
                after: index
            )
            let next: Character? =
                nextIndex < source.endIndex
                ? source[nextIndex] : nil
            if inLineComment {
                if character == "\n" {
                    inLineComment = false
                    result.append(character)
                }
            } else if inBlockComment {
                if character == "*"
                    && next == "/" {
                    inBlockComment = false
                    index = source.index(
                        after: nextIndex
                    )
                    continue
                }
            } else if inString {
                if escaped {
                    escaped = false
                } else if character == "\\" {
                    escaped = true
                } else if character == "\"" {
                    inString = false
                }
                result.append(character)
            } else if character == "/"
                && next == "/" {
                inLineComment = true
            } else if character == "/"
                && next == "*" {
                inBlockComment = true
            } else {
                if character == "\"" {
                    inString = true
                }
                result.append(character)
            }
            index = nextIndex
        }
        return result
    }
}
