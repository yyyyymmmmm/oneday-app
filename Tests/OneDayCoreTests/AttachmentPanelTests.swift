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

    // MARK: 定高决策（§154 热修）

    /// 量测未到/无效一律回 nil（宿主回落 .medium、
    /// 面板照常打开）：0 与负值是 §152 的旧口径，
    /// §154 起低于可信下限的正值同判——那是量测链
    /// 塌陷途中的伪值，绝不许当 detent
    func testDetentHeightRejectsImplausibleMeasurements() {
        XCTAssertNil(
            AttachmentPanel.detentHeight(
                measured: 0, screenHeight: 852
            )
        )
        XCTAssertNil(
            AttachmentPanel.detentHeight(
                measured: -20, screenHeight: 852
            )
        )
        XCTAssertNil(
            AttachmentPanel.detentHeight(
                measured: 42, screenHeight: 852
            )
        )
        XCTAssertNil(
            AttachmentPanel.detentHeight(
                measured: AttachmentPanel
                    .detentMinimumPlausibleHeight - 1,
                screenHeight: 852
            )
        )
    }

    /// 屏高无效（宿主几何还没回写）同回 nil，不拿
    /// 0 屏高算出 0 高 detent
    func testDetentHeightRejectsInvalidScreenHeight() {
        XCTAssertNil(
            AttachmentPanel.detentHeight(
                measured: 330, screenHeight: 0
            )
        )
        XCTAssertNil(
            AttachmentPanel.detentHeight(
                measured: 330, screenHeight: -852
            )
        )
    }

    /// 有效量测原样贴合（含可信下限边界值）；超
    /// 75% 屏高钳顶
    func testDetentHeightFitsAndClamps() {
        XCTAssertEqual(
            AttachmentPanel.detentHeight(
                measured: 330, screenHeight: 852
            ),
            330
        )
        XCTAssertEqual(
            AttachmentPanel.detentHeight(
                measured: AttachmentPanel
                    .detentMinimumPlausibleHeight,
                screenHeight: 852
            ),
            AttachmentPanel.detentMinimumPlausibleHeight
        )
        XCTAssertEqual(
            AttachmentPanel.detentHeight(
                measured: 900, screenHeight: 852
            ),
            852 * AttachmentPanel.detentMaxScreenFraction
        )
    }

    /// 不动点（§154 定因的回归钉）：决策只认内容
    /// 理想高与宿主真高、与当前 detent 无关——宿
    /// 主回路「量测→detent→按 detent 重排→再量
    /// 测」迭代多少轮都收敛在同一值。§152 的坏回
    /// 路是把当前 sheet 高当屏高：min(H, 0.75·s)
    /// 每轮剩 0.75 倍、塌到近零（本测以旧递推式
    /// 在测试内复算作对照，证明坏式确实单调衰
    /// 减、新式恒定）
    func testDetentHeightIsFixedPointUnderPresenterLoop() {
        let contentHeight: CGFloat = 330
        let screenHeight: CGFloat = 852
        var decided = AttachmentPanel.detentHeight(
            measured: contentHeight, screenHeight: screenHeight
        )
        for _ in 0..<10 {
            let next = AttachmentPanel.detentHeight(
                measured: contentHeight,
                screenHeight: screenHeight
            )
            XCTAssertEqual(next, decided)
            decided = next
        }
        XCTAssertEqual(decided, contentHeight)
        // 旧坏式对照：以当前 sheet 高冒充屏高，从
        // .medium（≈半屏）起步严格单调衰减
        var sheetHeight = screenHeight / 2
        var previous = sheetHeight
        for _ in 0..<10 {
            sheetHeight = min(
                contentHeight, sheetHeight * 0.75
            )
            XCTAssertLessThan(sheetHeight, previous)
            previous = sheetHeight
        }
        XCTAssertLessThan(sheetHeight, 60)
    }
}
