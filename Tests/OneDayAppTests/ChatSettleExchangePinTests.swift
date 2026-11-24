import SwiftUI
import UIKit
import XCTest
@testable import OneDayApp
import OneDayCore
import OneDayDesign

/// §413（0.50.103 热修）落定交换端到端钉测＋落点
/// 意图探针：
/// ①甲（主判）：控制器级全链——冷开→生成期占位
/// 趟（live-placeholder 入列）→落定趟（删占位＋
/// 落定条目以流式行键首见入列、走 applyChanges
/// 增量路），断言落定行 cell 在落写趟内已被配置
/// （configuredKey 命中）——§407 前落定走同键重
/// 配路、从未演练「删＋插」形态，本例即该形态的
/// 首个控制器级覆盖；兼断快照序与高度账在位、
/// 后续稳态趟不自愈式丢失（配置仍在位）。
/// ②乙（探针）：长列表在底＋落点意图在席→占位
/// 行稳态期多拍→落定增长拍，断言终距 ≤0.5——
/// 验意图消费判据（整拍在底＋contentSize 逐值
/// 同）是否在占位行恒高稳态期被提前满足、吃掉
/// 增长拍的钉底承接。
@MainActor
final class ChatSettleExchangePinTests: XCTestCase {

    private let styleKey = "style-a"
    private let layout = ChatNativeLayout(
        horizontalPadding: OneDayMetrics.pageGutter,
        topPadding: OneDayMetrics.spacingM,
        bottomPadding: 8,
        rowSpacing: OneDayMetrics.spacingL,
        arrowTrailing: OneDayMetrics.spacingM,
        arrowGapAboveComposer: 8,
        arrowSize: OneDayMetrics.minTapTarget
    )

    private var window: UIWindow!
    private var controller: ChatRootViewController!
    private var handle: ChatNativeListHandle!
    private var tracker: ChatFeedChangeTracker!

    override func tearDown() {
        window?.isHidden = true
        window = nil
        controller = nil
        handle = nil
        tracker = nil
        super.tearDown()
    }

    private func assemble() {
        let w = UIWindow(
            frame: CGRect(x: 0, y: 0, width: 390, height: 844)
        )
        let root = UIViewController()
        w.rootViewController = root
        w.makeKeyAndVisible()
        let h = ChatNativeListHandle()
        let c = ChatRootViewController()
        c.handle = h
        c.callbacks = ChatNativeListCallbacks(
            onScrollGeometry: {},
            onTopVisibleEntry: { _ in },
            onBlankTap: {}
        )
        h.controller = c
        root.addChild(c)
        c.view.frame = root.view.bounds
        root.view.addSubview(c.view)
        c.didMove(toParent: root)
        // 坞座位（与 ChatNativeListAssemblyTests 真
        // 壳同构）：壳层 83 高坞——控制器锚点解析
        // 据此定舱位/底 inset；缺此座位时回落常量
        // 使落定拍钉底 offset 失真（测试壳伪影、
        // 非产品行为）
        let dock = UIView()
        dock.backgroundColor = .systemGray5
        dock.translatesAutoresizingMaskIntoConstraints = false
        root.view.addSubview(dock)
        NSLayoutConstraint.activate([
            dock.leadingAnchor.constraint(
                equalTo: root.view.leadingAnchor
            ),
            dock.trailingAnchor.constraint(
                equalTo: root.view.trailingAnchor
            ),
            dock.bottomAnchor.constraint(
                equalTo: root.view.bottomAnchor
            ),
            dock.heightAnchor.constraint(
                equalToConstant: 83
            ),
        ])
        root.view.layoutIfNeeded()
        window = w
        controller = c
        handle = h
        tracker = ChatFeedChangeTracker()
    }

    // MARK: - 语料（与 ChatView.nativeRows 同法）

    private func makeEntry(
        _ index: Int, role: String, content: String
    ) -> ChatEntry {
        let entry = ChatEntry(
            role: role, content: content,
            thread: nil, reasoning: nil,
            reasoningSeconds: nil
        )
        entry.createdAt = Date(
            timeIntervalSinceReferenceDate:
                780_000_000 + Double(index * 60)
        )
        return entry
    }

    private func entryRow(
        _ entry: ChatEntry,
        height: CGFloat,
        keyOverride: String? = nil
    ) -> ChatNativeRow {
        let revision = ChatNativeRowRevision.entryBase(
            entry, dividerText: nil,
            showsUnreadDivider: false
        )
        return ChatNativeRow(
            key: keyOverride
                ?? "entry-\(entry.id.uuidString)",
            entryID: entry.id,
            revision: revision,
            height: height,
            makeView: {
                AnyView(
                    Text(entry.content)
                        .frame(maxWidth: .infinity,
                               alignment: .leading)
                )
            }
        )
    }

    private func basis(
        for entry: ChatEntry, height: CGFloat
    ) -> ChatFeedEntryBasis {
        ChatFeedEntryBasis(
            entryID: entry.id,
            snapshot: ChatEntryRevisionSnapshot
                .capture(entry),
            dividerText: nil,
            showsUnreadDivider: false,
            sources: [],
            highlighted: false,
            styleKey: styleKey,
            feedHeight: height,
            heightIsProvisional: false
        )
    }

    /// §407 直播占位行：键恒定、高为常量、修订只
    /// 折状态文案（与 ChatView.livePlaceholderRow
    /// 同法）
    private func placeholderRow() -> ChatNativeRow {
        var revision = ChatNativeRowRevision()
        revision.addText("正在生成…")
        return ChatNativeRow(
            key: "live-placeholder",
            entryID: nil,
            revision: revision,
            height: 62,
            makeView: {
                AnyView(Text("正在生成…"))
            }
        )
    }

    @discardableResult
    private func feed(
        rows: [ChatNativeRow],
        bases: [ChatFeedEntryBasis],
        label: String
    ) -> EntryChangeSet {
        for basis in bases {
            tracker.noteEntryBasis(basis)
        }
        let set = tracker.ingest(rows: rows)
        controller.applyChanges(
            rows: rows, changeSet: set,
            layout: layout,
            topInset: 122, bottomMargin: 16,
            composerView: AnyView(
                Rectangle()
                    .fill(Color.clear)
                    .frame(height: 54)
            ),
            arrowView: AnyView(Color.clear)
        )
        XCTAssertEqual(
            tracker.shadowLedger.diffCount, 0,
            "影子账须清零（\(label)）"
        )
        return set
    }

    private func pump(_ seconds: TimeInterval) {
        let exp = expectation(description: "pump")
        DispatchQueue.main.asyncAfter(
            deadline: .now() + seconds
        ) { exp.fulfill() }
        wait(for: [exp], timeout: seconds + 5)
    }

    /// 可见托管 cell 中帧最靠下者（末行 cell）
    private func lastVisibleCell() -> ChatNativeHostingCell? {
        controller.collectionView.visibleCells
            .compactMap { $0 as? ChatNativeHostingCell }
            .max(by: { $0.frame.minY < $1.frame.minY })
    }

    /// 按行序取 cell：先滚入可见区再取（两构造
    /// 的 indexPath 换算与控制器 indexPath(forRow:)
    /// 同式——单 section＝(item 行序, 0)、逐行＝
    /// (0, section 行序)，以 section 数分流）
    private func cellForRow(
        _ row: Int
    ) -> ChatNativeHostingCell? {
        let cv = controller.collectionView
        let indexPath = cv.numberOfSections == 1
            ? IndexPath(item: row, section: 0)
            : IndexPath(item: 0, section: row)
        cv.scrollToItem(
            at: indexPath, at: .bottom, animated: false
        )
        cv.layoutIfNeeded()
        return cv.cellForItem(at: indexPath)
            as? ChatNativeHostingCell
    }

    // MARK: - ① 甲：落定交换 cell 配置钉测

    func testSettleExchangeConfiguresLandedCell() {
        assemble()
        let greet = makeEntry(
            0, role: "assistant", content: "你好，我是助手。"
        )
        let user = makeEntry(
            1, role: "user", content: "你是谁？"
        )
        let greetRow = entryRow(greet, height: 80)
        let userRow = entryRow(user, height: 60)
        let bases = [
            basis(for: greet, height: 80),
            basis(for: user, height: 60),
        ]
        // 趟 0：冷开（问候＋用户行）
        feed(rows: [greetRow, userRow], bases: bases,
             label: "冷开")
        controller.collectionView.layoutIfNeeded()
        // 趟 1：生成期——占位行入列（增量路）
        feed(
            rows: [greetRow, userRow, placeholderRow()],
            bases: bases, label: "占位趟"
        )
        controller.collectionView.layoutIfNeeded()
        XCTAssertEqual(
            controller.testSnapshotKeyOrder,
            [greetRow.key, userRow.key, "live-placeholder"],
            "占位趟后快照序须含占位行居尾"
        )
        // 趟 2：落定——删占位＋落定条目以流式行键
        // 首见入列（§407 新形态的删＋插交换）
        let settled = makeEntry(
            2, role: "assistant",
            content: String(
                repeating: "我是运行在 Hermes 上的助手，可以帮你处理任务、查资料、写代码。 ",
                count: 6
            )
        )
        let streamKey = StreamingRowIdentity
            .streamRowKey(
                userEntryID: user.id.uuidString
            )
        let settledRow = entryRow(
            settled, height: 350, keyOverride: streamKey
        )
        let set = feed(
            rows: [greetRow, userRow, settledRow],
            bases: bases
                + [basis(for: settled, height: 350)],
            label: "落定趟"
        )
        XCTAssertTrue(
            set.deleted.contains("live-placeholder"),
            "落定趟变更集须含占位行删除"
        )
        XCTAssertTrue(
            set.inserted.contains(streamKey),
            "落定趟变更集须含落定键首见插入"
        )
        // 即时断言（不先 layoutIfNeeded）：落写趟内
        // 物化的落定行 cell 必须已配置——未配置＝
        // 有高无内容（0.50.102 真机主症状）
        let immediate = lastVisibleCell()
        XCTAssertNotNil(
            immediate,
            "落定行 cell 应在落写趟内物化"
        )
        XCTAssertEqual(
            immediate?.configuredKey, streamKey,
            "落定行 cell 须在落写趟内已配置"
        )
        XCTAssertGreaterThan(
            immediate?.configureCount ?? 0, 0,
            "落定行 cell 配置次数须 ≥1"
        )
        // 快照序与高度账对账
        XCTAssertEqual(
            controller.testSnapshotKeyOrder,
            [greetRow.key, userRow.key, streamKey],
            "落定后快照序须为落定键居尾"
        )
        XCTAssertEqual(
            controller.testAdoptedRowHeights.count, 3,
            "高度账行数须与行集同"
        )
        XCTAssertEqual(
            controller.testRowHeightsByKey[streamKey],
            350,
            "高度账须有落定行高"
        )
        // 持久性：泵落定拍＋再喂一趟稳态（空变更
        // 集），配置仍在位——不许靠后续趟自愈掩盖
        pump(0.3)
        feed(
            rows: [greetRow, userRow, settledRow],
            bases: bases
                + [basis(for: settled, height: 350)],
            label: "稳态趟"
        )
        pump(0.3)
        // 末态在位：把落定行滚入可见区后取其 cell
        // 验配置。注：本壳舱座位走回落常量、静止
        // 位 offset 被钉底推过内容顶，visibleCells
        // 在静止位为空——壳几何伪影（装配真壳另
        // 有口径），断言对象是行自身的供应配置与
        // 内容在位，不取静止位可见集
        let settledCell = cellForRow(2)
        XCTAssertEqual(
            settledCell?.configuredKey, streamKey,
            "稳态后落定行 cell 配置仍须在位"
        )
    }

    // MARK: - ①乙 附探针：短会话落定走重建路

    /// 新线程首轮：落定前行集仅［用户行＋占位行］
    /// 2 行，落定交换的插＋删（2）≥现行行数（2）
    /// ——applyChangesNow 按判据分流整表重建路
    /// （applyChangesFullRebuild）。该路落写序
    /// 同病（快照先行、三账随后）——本例修前同红
    /// （即时 configuredKey＝nil）、与增量段同不
    /// 变量同修（§413.2-2）
    func testSettleExchangeShortThreadRebuildPath() {
        assemble()
        let user = makeEntry(
            0, role: "user", content: "你是谁？"
        )
        let userRow = entryRow(user, height: 60)
        let userBases = [basis(for: user, height: 60)]
        feed(rows: [userRow], bases: userBases,
             label: "首轮冷开")
        controller.collectionView.layoutIfNeeded()
        feed(
            rows: [userRow, placeholderRow()],
            bases: userBases, label: "占位趟"
        )
        controller.collectionView.layoutIfNeeded()
        let settled = makeEntry(
            1, role: "assistant",
            content: String(
                repeating: "我是运行在 Hermes 上的助手。 ",
                count: 6
            )
        )
        let streamKey = StreamingRowIdentity
            .streamRowKey(
                userEntryID: user.id.uuidString
            )
        let settledRow = entryRow(
            settled, height: 350, keyOverride: streamKey
        )
        feed(
            rows: [userRow, settledRow],
            bases: userBases
                + [basis(for: settled, height: 350)],
            label: "落定趟（重建路）"
        )
        let immediate = lastVisibleCell()
        XCTAssertNotNil(
            immediate,
            "落定行 cell 应在落写趟内物化（重建路）"
        )
        XCTAssertEqual(
            immediate?.configuredKey, streamKey,
            "重建路落定行 cell 须在落写趟内已配置"
        )
        pump(0.3)
        let settledCell = cellForRow(1)
        XCTAssertEqual(
            settledCell?.configuredKey, streamKey,
            "重建路稳态后落定行 cell 配置仍须在位"
        )
    }

    // MARK: - ② 乙：落点意图占位稳态期存续探针

    func testLandingIntentSurvivesPlaceholderSteadyState() {
        assemble()
        // 长列表：10 行 ×100 ＝1000pt 内容高，超
        // 视口（844）——钉底承接有实际行程
        var rows: [ChatNativeRow] = []
        var bases: [ChatFeedEntryBasis] = []
        var entries: [ChatEntry] = []
        for i in 0..<10 {
            let e = makeEntry(
                i,
                role: i % 2 == 0 ? "user" : "assistant",
                content: "第 \(i) 条"
            )
            entries.append(e)
            rows.append(entryRow(e, height: 100))
            bases.append(basis(for: e, height: 100))
        }
        feed(rows: rows, bases: bases, label: "冷开")
        pump(0.3)
        controller.collectionView.layoutIfNeeded()
        XCTAssertLessThanOrEqual(
            handle.latestDistance, 0.5,
            "冷开后应在底（前置条件）"
        )
        // 发送口径：回底命令置意图（与 ChatView 发
        // 送时 scrollToBottom 同口）
        let userEntry = entries[8]
        controller.scrollToBottom(animated: false)
        // 生成期：占位行入列，稳态多拍（意图消费
        // 判据在此窗内是否被恒高 contentSize 满足）
        var genRows = rows
        genRows.append(placeholderRow())
        feed(rows: genRows, bases: bases, label: "占位趟")
        pump(0.5)
        XCTAssertLessThanOrEqual(
            handle.latestDistance, 0.5,
            "占位趟后应在底（前置条件）"
        )
        // 落定增长拍：占位（62）→落定行（300），
        // 净增长 238——意图若已被提前消费，本拍无
        // 钉底承接、终距 ≈238；存续则钉底归零
        let settled = makeEntry(
            10, role: "assistant", content: "落定长回复"
        )
        let streamKey = StreamingRowIdentity
            .streamRowKey(
                userEntryID: userEntry.id.uuidString
            )
        var settledRows = rows
        settledRows.append(
            entryRow(
                settled, height: 300,
                keyOverride: streamKey
            )
        )
        feed(
            rows: settledRows,
            bases: bases
                + [basis(for: settled, height: 300)],
            label: "落定趟"
        )
        pump(0.5)
        controller.collectionView.layoutIfNeeded()
        XCTAssertLessThanOrEqual(
            handle.latestDistance, 0.5,
            "落定增长拍后须钉底（意图不得在占位稳态期被提前消费）"
        )
    }
}
