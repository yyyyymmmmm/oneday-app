import OneDayCore
import XCTest

/// FA-1（App 包 A，契约 rev2 §1.9 冻结）：点赞真源
/// 字段 likedAt 的解码与保真、点赞/信号请求体形态、
/// 讨论信号 note 提取口径、呈现序契约（落盘时间倒
/// 序、不重排不分组）。视图与网络不在此测。
final class FeedAppATests: XCTestCase {

    private func decodePost(_ json: String) throws -> BridgeFeedPost {
        try JSONDecoder().decode(
            BridgeFeedPost.self, from: Data(json.utf8)
        )
    }

    // MARK: - likedAt 解码（桥为真源）

    func testLikedAtDecodesFromBridgeView() throws {
        let post = try decodePost("""
        {"id":"p1","kind":"research","title":"t","body":"b",
         "createdAt":1762700000.5,"likedAt":1762700100.25}
        """)
        XCTAssertEqual(post.likedAt, 1762700100.25)
        XCTAssertTrue(post.isLiked)
    }

    func testLikedAtNullAndAbsentBothMeanUnliked() throws {
        let nullPost = try decodePost("""
        {"id":"p2","kind":"research","title":"t","body":"b",
         "createdAt":1762700000,"likedAt":null}
        """)
        XCTAssertNil(nullPost.likedAt)
        XCTAssertFalse(nullPost.isLiked)

        let absentPost = try decodePost("""
        {"id":"p3","kind":"digest","title":"t","body":"b",
         "createdAt":1762700000}
        """)
        XCTAssertNil(absentPost.likedAt)
        XCTAssertFalse(absentPost.isLiked)
    }

    func testLikedAtSurvivesMarkedReadCopy() {
        let post = BridgeFeedPost(
            id: "p4", kind: .research, title: "t", body: "b",
            createdAt: 100, likedAt: 200
        )
        let read = post.markedRead(at: 300)
        XCTAssertEqual(read.readAt, 300)
        XCTAssertEqual(read.likedAt, 200)
        XCTAssertTrue(read.isLiked)

        let unliked = post.withLikedAt(nil)
        XCTAssertNil(unliked.likedAt)
        XCTAssertFalse(unliked.isLiked)
        XCTAssertEqual(unliked.readAt, post.readAt)
    }

    // MARK: - 请求体形态（契约冻结）

    func testLikeRequestEncodesLikedBool() throws {
        let data = try JSONEncoder().encode(
            BridgeFeedLikeRequest(liked: true)
        )
        let json = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        XCTAssertEqual(json["liked"] as? Bool, true)
        XCTAssertEqual(json.count, 1)
    }

    func testSignalRequestOmitsNoteKeyWhenNil() throws {
        let data = try JSONEncoder().encode(
            BridgeFeedSignalRequest(type: "discuss")
        )
        let json = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        XCTAssertEqual(json["type"] as? String, "discuss")
        XCTAssertNil(json["note"])

        let noted = try JSONEncoder().encode(
            BridgeFeedSignalRequest(type: "discuss", note: "我喜欢这类")
        )
        let notedJSON = try XCTUnwrap(
            JSONSerialization.jsonObject(with: noted) as? [String: Any]
        )
        XCTAssertEqual(notedJSON["note"] as? String, "我喜欢这类")
    }

    // MARK: - note 提取（只取自述偏好句）

    func testPreferenceNotePicksStatedSentence() {
        let note = FeedDiscussSignal.preferenceNote(
            in: "这篇写得不错。我对量化交易没兴趣，以后少给我推。先这样。"
        )
        XCTAssertEqual(note, "我对量化交易没兴趣，以后少给我推。")
    }

    func testPreferenceNoteNilWithoutStatement() {
        XCTAssertNil(FeedDiscussSignal.preferenceNote(
            in: "这篇讲得很细，数据也可信，辛苦了。"
        ))
        XCTAssertNil(FeedDiscussSignal.preferenceNote(in: ""))
        XCTAssertNil(FeedDiscussSignal.preferenceNote(in: "   "))
    }

    func testPreferenceNoteEnglishAndTruncation() {
        let note = FeedDiscussSignal.preferenceNote(
            in: "Interesting read. I prefer posts about local models."
        )
        XCTAssertEqual(note, "I prefer posts about local models.")

        let long = "我想看" + String(repeating: "开", count: 200) + "。"
        let capped = FeedDiscussSignal.preferenceNote(in: long)
        XCTAssertEqual(capped?.count, FeedDiscussSignal.noteLimit)
    }

    // MARK: - 呈现序契约（倒序、不重排、不按 edition 分组）

    func testSortedStaysPureCreatedAtDescendingAcrossKinds() {
        func make(_ id: String, _ kind: FeedPostKind, _ ts: Double)
            -> BridgeFeedPost {
            BridgeFeedPost(
                id: id, kind: kind, title: id, body: "",
                createdAt: ts
            )
        }
        let posts = [
            make("a", .research, 300),
            make("b", .digest, 500),
            make("c", .research, 400),
            make("d", .digest, 500),
        ]
        let sorted = FeedBoard.sorted(posts)
        // 同刻以 id 倒序定序（d>b），异刻纯时间倒序；
        // kind 混排不分组——版次/汇编不许被二次归拢
        XCTAssertEqual(sorted.map(\.id), ["d", "b", "c", "a"])
    }
}
