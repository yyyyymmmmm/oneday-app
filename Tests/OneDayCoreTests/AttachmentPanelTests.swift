import OneDayCore
import XCTest

/// §146 附件面板钉测：授权政策矩阵（只读现态、不发
/// 请求）、照片条拼装（相机恒首、去重、截断）、图片
/// 接入闸与汇总文案（两条取图路共用）、视频入条命名。
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
