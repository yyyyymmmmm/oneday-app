import OneDayCore
import XCTest

/// §147 附件面板钉测：授权政策矩阵（只读现态、不发
/// 请求）、照片条拼装（相机恒首、去重、截断）、图片
/// 接入闸与汇总文案（两条取图路共用）、视频入条命名。
/// §152 修订二续：照片条多选（切换/呈现序/确认文案）。
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
        XCTAssertNil(AttachmentPanel.addSelectedTitle(count: 0))
        XCTAssertEqual(
            AttachmentPanel.addSelectedTitle(count: 1), "添加 1 张"
        )
        XCTAssertEqual(
            AttachmentPanel.addSelectedTitle(count: 3), "添加 3 张"
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
}
