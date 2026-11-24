import OneDayCore
import XCTest

/// §147 附件面板钉测：授权政策矩阵（只读现态、不发
/// 请求）、照片条拼装（相机恒首、去重、截断）、图片
/// 接入闸与汇总文案（两条取图路共用）、视频入条命名。
/// §152 修订二续：照片条多选（切换/呈现序/确认文案）。
/// D5（台账 11）续：布局常量单源＋贴合高度三态逐值。
final class AttachmentPanelTests: XCTestCase {

    // MARK: 授权政策

    func testShowsLibraryOnlyWhenGranted() {
        XCTAssertTrue(AttachmentPanel.showsLibrary(access: .authorized))
        XCTAssertTrue(AttachmentPanel.showsLibrary(access: .limited))
        XCTAssertFalse(AttachmentPanel.showsLibrary(access: .denied))
        XCTAssertFalse(AttachmentPanel.showsLibrary(access: .notDetermined))
        XCTAssertFalse(AttachmentPanel.showsLibrary(access: .restricted))
    }

    // MARK: 照片条拼装

    func testStripStartsWithCameraThenPhotosInOrder() {
        let cells = AttachmentPanel.stripCells(
            photoIDs: ["a", "b", "c"]
        )
        XCTAssertEqual(
            cells,
            [.camera, .photo(id: "a"), .photo(id: "b"), .photo(id: "c")]
        )
    }

    func testStripWithNoPhotosIsCameraOnly() {
        XCTAssertEqual(AttachmentPanel.stripCells(photoIDs: []), [.camera])
    }

    func testStripDedupesKeepingFirstOccurrence() {
        let cells = AttachmentPanel.stripCells(
            photoIDs: ["a", "b", "a", "c", "b"]
        )
        XCTAssertEqual(
            cells,
            [.camera, .photo(id: "a"), .photo(id: "b"), .photo(id: "c")]
        )
    }

    func testStripTruncatesAtLimit() {
        let ids = (0..<50).map { "p\($0)" }
        let cells = AttachmentPanel.stripCells(photoIDs: ids, limit: 30)
        XCTAssertEqual(cells.count, 31)
        XCTAssertEqual(cells.last, .photo(id: "p29"))
    }

    func testStripDefaultLimitIsThirty() {
        let ids = (0..<40).map { "p\($0)" }
        let cells = AttachmentPanel.stripCells(photoIDs: ids)
        XCTAssertEqual(cells.count, 1 + AttachmentPanel.stripPhotoLimit)
    }

    // MARK: 图片接入闸与文案

    func testPhotoFitsBoundary() {
        XCTAssertTrue(
            AttachmentPanel.photoFits(byteCount: AttachmentPanel.maxPhotoBytes)
        )
        XCTAssertFalse(
            AttachmentPanel.photoFits(
                byteCount: AttachmentPanel.maxPhotoBytes + 1
            )
        )
        XCTAssertTrue(AttachmentPanel.photoFits(byteCount: 0))
    }

    func testOversizedNotice() {
        XCTAssertNil(AttachmentPanel.oversizedPhotosNotice(count: 0))
        XCTAssertEqual(
            AttachmentPanel.oversizedPhotosNotice(count: 2),
            "有 2 张图片超过 20MB，未加入待发列表。"
        )
    }

    func testFailedNotice() {
        XCTAssertNil(AttachmentPanel.failedPhotosNotice(count: 0))
        XCTAssertEqual(
            AttachmentPanel.failedPhotosNotice(count: 1),
            "有 1 张图片读取失败，未加入待发列表。"
        )
    }

    // MARK: 照片条多选（§152 修订二）

    func testToggleSelectionAddsThenRemoves() {
        var selected: Set<String> = []
        selected = AttachmentPanel.toggledSelection(selected, id: "a")
        XCTAssertEqual(selected, ["a"])
        selected = AttachmentPanel.toggledSelection(selected, id: "b")
        XCTAssertEqual(selected, ["a", "b"])
        selected = AttachmentPanel.toggledSelection(selected, id: "a")
        XCTAssertEqual(selected, ["b"])
    }

    func testOrderedSelectionFollowsStripOrderNotTapOrder() {
        // 条内呈现序（新→旧）为 a,b,c：无论点选先后，
        // 批量入条序恒按呈现序
        let ordered = AttachmentPanel.orderedSelection(
            selected: ["c", "a"], stripOrder: ["a", "b", "c"]
        )
        XCTAssertEqual(ordered, ["a", "c"])
    }

    func testOrderedSelectionDropsIDsNotInStrip() {
        let ordered = AttachmentPanel.orderedSelection(
            selected: ["a", "ghost"], stripOrder: ["a", "b"]
        )
        XCTAssertEqual(ordered, ["a"])
        XCTAssertEqual(
            AttachmentPanel.orderedSelection(
                selected: [], stripOrder: ["a", "b"]
            ),
            []
        )
    }

    func testAddSelectedTitle() {
        // §461 文案：随目标图作「添加 N 个附件」；未
        // 选回 nil（确认按钮不呈现）与旧行同源
        XCTAssertNil(AttachmentPanel.addSelectedTitle(count: 0))
        XCTAssertEqual(
            AttachmentPanel.addSelectedTitle(count: 1),
            "添加 1 个附件"
        )
        XCTAssertEqual(
            AttachmentPanel.addSelectedTitle(count: 3),
            "添加 3 个附件"
        )
    }

    // MARK: 视频命名

    func testVideoFileName() {
        XCTAssertEqual(
            AttachmentPanel.videoFileName(preferredExtension: "mov"),
            "视频.mov"
        )
        XCTAssertEqual(
            AttachmentPanel.videoFileName(preferredExtension: "MP4"),
            "视频.mp4"
        )
        XCTAssertEqual(
            AttachmentPanel.videoFileName(preferredExtension: nil),
            "视频.mov"
        )
        XCTAssertEqual(
            AttachmentPanel.videoFileName(preferredExtension: ""),
            "视频.mov"
        )
        XCTAssertEqual(
            AttachmentPanel.videoFileName(preferredExtension: ".m4v"),
            "视频.m4v"
        )
    }

    // MARK: 布局常量与定高（D5，台账 11）

    func testLayoutConstants() {
        // 常量单源：与 AttachmentPanelView 引用同值
        XCTAssertEqual(AttachmentPanel.Layout.cellSize, 118)
        XCTAssertEqual(AttachmentPanel.Layout.rowHeight, 52)
        XCTAssertEqual(AttachmentPanel.Layout.titleRowHeight, 22)
        XCTAssertEqual(
            AttachmentPanel.Layout.confirmButtonHeight, 56
        )
    }

    func testFittedSheetHeightThreeStates() {
        // 无库态：32（padding）＋ 105（动作行）＝ 137
        let noLibrary = AttachmentPanel.fittedSheetHeight(
            showsLibrary: false,
            hasSelection: false
        )
        XCTAssertEqual(noLibrary, 137)

        // 有库未选：32 ＋ 152（库区）＋ 16 ＋ 105 ＝ 305
        let libraryNoSelection = AttachmentPanel.fittedSheetHeight(
            showsLibrary: true,
            hasSelection: false
        )
        XCTAssertEqual(libraryNoSelection, 305)

        // 有库已选：305 ＋ 16 ＋ 56（§461 确认按钮）＝ 377
        let libraryWithSelection = AttachmentPanel.fittedSheetHeight(
            showsLibrary: true,
            hasSelection: true
        )
        XCTAssertEqual(libraryWithSelection, 377)
    }

    func testFittedSheetHeightExcludesSafeArea() {
        // D5 根因口径：贴合高只算内容、安全区不入参——系统 sheet 的
        // detent 解析值已含安全区处理，函数再加一层即多算 34.3pt
        // （装配测 testAttachPanelPresentsAtFittedHeight 钉死此口径）
        let height = AttachmentPanel.fittedSheetHeight(
            showsLibrary: false,
            hasSelection: false
        )
        XCTAssertEqual(height, 137)
    }
}
