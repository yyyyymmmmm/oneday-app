import OneDayCore
import XCTest

/// 盒桥契约测试（P2，0.9.0）：fixture 按
/// box-bridge-rollout-20261109.md 的冻结形状原文落字
/// （base64 为 JPEG SOI 短样本、字节数为样本实长，
/// 其余字段逐值照抄）。红线：creditsLeft 恒 null 不许
/// 编、活读落空只许退「最后确认于 HH:mm」、桥未连接
/// 不许压成电脑离线、点空（letterbox）不许译成点击。
final class BoxBridgeTests: XCTestCase {
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()
    private let tzPlus8 = TimeZone(secondsFromGMT: 8 * 3600)!

    // rollout §契约 GET /status 原形状（checkedAt 补实值）
    private let statusLiveJSON = """
    {"state": "running", "name": "main",
     "boxId": "cb-b8486e59e25a", "image": "sbxdesk:v13",
     "latestImage": "sbxdesk:v13", "upgradeAvailable": false,
     "lastSavedAtMs": 1794149613120,
     "viewUrl": "https://box.simular.ai/box/cb-b8486e59e25a/live",
     "creditsLeft": null, "creditsNote": "box plans are not enabled",
     "page": {"title": "Example Domain", "url": "https://example.com/"},
     "lastKnownPage": {"title": "Example Domain", "url": "https://example.com/"},
     "lastKnownPageAt": "2026-11-09T08:17:38+00:00",
     "checkedAt": "2026-11-09T08:17:40+00:00"}
    """

    private let shotJSON = """
    {"mime": "image/jpeg", "width": 1024, "height": 640, "bytes": 6,
     "imageBase64": "/9j/4AAQ", "capturedAt": "2026-11-09T08:17:38+00:00"}
    """

    // MARK: - 状态解码与呈现

    func testStatusDecodeLivePage() throws {
        let status = try decoder.decode(
            BoxBridgeStatus.self, from: Data(statusLiveJSON.utf8)
        )
        XCTAssertTrue(status.isRunning)
        XCTAssertEqual(status.stateText, "运行中")
        XCTAssertEqual(status.statusLine, "云电脑运行中")
        XCTAssertEqual(status.name, "main")
        // 额度口径：当前计划恒 null，只解码不编造
        XCTAssertNil(status.creditsLeft)
        XCTAssertEqual(status.creditsNote, "box plans are not enabled")
        XCTAssertEqual(
            status.pagePresentation,
            .live(BoxPageRef(
                title: "Example Domain", url: "https://example.com/"
            ))
        )
        XCTAssertEqual(status.pageTitleText, "Example Domain")
        XCTAssertEqual(
            status.pageMetaText(timeZone: tzPlus8), "https://example.com/"
        )
        XCTAssertNotNil(status.checkedAt)
    }

    func testStatusLiveReadFallsBackToLastKnownWithTime() throws {
        // 活读落空（自动化绑定失效）：page=null，只许以
        // lastKnownPage＋时刻呈现，副行必须带「最后确认于」
        let json = """
        {"state": "running", "name": "main", "creditsLeft": null,
         "page": null,
         "lastKnownPage": {"title": "Example Domain", "url": "https://example.com/"},
         "lastKnownPageAt": "2026-11-09T08:17:38+00:00",
         "checkedAt": "2026-11-09T08:20:00+00:00"}
        """
        let status = try decoder.decode(
            BoxBridgeStatus.self, from: Data(json.utf8)
        )
        guard case .lastKnown(let page, let at) = status.pagePresentation
        else {
            return XCTFail("活读落空应退最后确认态，实际 \(status.pagePresentation)")
        }
        XCTAssertEqual(page.title, "Example Domain")
        XCTAssertNotNil(at)
        XCTAssertEqual(
            status.pageMetaText(timeZone: tzPlus8),
            "https://example.com/ · 最后确认于 16:17"
        )
    }

    func testStatusHibernatedNoPage() throws {
        let json = """
        {"state": "hibernated", "name": "main", "creditsLeft": null,
         "page": null, "lastKnownPage": null, "lastKnownPageAt": null,
         "checkedAt": "2026-11-09T08:20:00+00:00"}
        """
        let status = try decoder.decode(
            BoxBridgeStatus.self, from: Data(json.utf8)
        )
        XCTAssertFalse(status.isRunning)
        XCTAssertEqual(status.statusLine, "云电脑休眠中")
        XCTAssertEqual(status.pagePresentation, .none)
        XCTAssertEqual(status.pageTitleText, "暂无页面")
        XCTAssertEqual(status.pageMetaText(timeZone: tzPlus8), "")
    }

    func testStatusCreditsValueDecodesWhenPresent() throws {
        // 将来计划开通后桥自动填数：有值必须解得出
        let json = """
        {"state": "running", "creditsLeft": 512.5, "page": null,
         "lastKnownPage": null}
        """
        let status = try decoder.decode(
            BoxBridgeStatus.self, from: Data(json.utf8)
        )
        XCTAssertEqual(status.creditsLeft, 512.5)
    }

    // MARK: - P9 状态面派生（镜像/额度/最后保存单一口径）

    func testStatusImageLineNoUpgrade() throws {
        let status = try decoder.decode(
            BoxBridgeStatus.self, from: Data(statusLiveJSON.utf8)
        )
        XCTAssertEqual(status.imageLine, "镜像 sbxdesk:v13")
    }

    func testStatusImageLineUpgradeAvailable() throws {
        let json = """
        {"state": "running", "image": "sbxdesk:v13",
         "latestImage": "sbxdesk:v14", "upgradeAvailable": true}
        """
        let status = try decoder.decode(
            BoxBridgeStatus.self, from: Data(json.utf8)
        )
        XCTAssertEqual(
            status.imageLine, "镜像 sbxdesk:v13 · 可更新到 sbxdesk:v14"
        )
    }

    func testStatusImageLineUpgradeSameVersionStaysPlain() throws {
        // 可更新标记为真但目标镜像与现行相同：不带后缀
        let json = """
        {"state": "running", "image": "sbxdesk:v13",
         "latestImage": "sbxdesk:v13", "upgradeAvailable": true}
        """
        let status = try decoder.decode(
            BoxBridgeStatus.self, from: Data(json.utf8)
        )
        XCTAssertEqual(status.imageLine, "镜像 sbxdesk:v13")
    }

    func testStatusImageLineAbsentWithoutImage() throws {
        let status = try decoder.decode(
            BoxBridgeStatus.self,
            from: Data(#"{"state": "running"}"#.utf8)
        )
        XCTAssertNil(status.imageLine)
    }

    func testStatusCreditsLineFallsBackToVendorNoteVerbatim() throws {
        // 数字恒 null：给厂商原文，不翻译不编造
        let status = try decoder.decode(
            BoxBridgeStatus.self, from: Data(statusLiveJSON.utf8)
        )
        XCTAssertEqual(status.creditsLine, "box plans are not enabled")
    }

    func testStatusCreditsLinePrefersRealValue() throws {
        let json = """
        {"state": "running", "creditsLeft": 512.5,
         "creditsNote": "box plans are not enabled"}
        """
        let status = try decoder.decode(
            BoxBridgeStatus.self, from: Data(json.utf8)
        )
        let line = try XCTUnwrap(status.creditsLine)
        XCTAssertTrue(line.hasPrefix("剩余额度"), "实际：\(line)")
        XCTAssertTrue(line.contains("512.5"), "实际：\(line)")
    }

    func testStatusCreditsLineAbsentWhenNeitherPresent() throws {
        let status = try decoder.decode(
            BoxBridgeStatus.self,
            from: Data(#"{"state": "running"}"#.utf8)
        )
        XCTAssertNil(status.creditsLine)
    }

    func testStatusLastSavedAtFromMillis() throws {
        let status = try decoder.decode(
            BoxBridgeStatus.self, from: Data(statusLiveJSON.utf8)
        )
        let saved = try XCTUnwrap(status.lastSavedAt)
        XCTAssertEqual(
            saved.timeIntervalSince1970, 1_794_149_613.12, accuracy: 0.001
        )
        XCTAssertEqual(
            BoxTimeText.dateTime(saved, timeZone: tzPlus8), "11-08 22:53"
        )
    }

    func testStatusLastSavedAtAbsent() throws {
        let status = try decoder.decode(
            BoxBridgeStatus.self,
            from: Data(#"{"state": "running"}"#.utf8)
        )
        XCTAssertNil(status.lastSavedAt)
    }

    func testPageTitleFallsBackToURL() throws {
        let json = """
        {"state": "running",
         "page": {"title": "", "url": "https://example.com/"}}
        """
        let status = try decoder.decode(
            BoxBridgeStatus.self, from: Data(json.utf8)
        )
        XCTAssertEqual(status.pageTitleText, "https://example.com/")
    }

    func testHubStateLines() {
        XCTAssertEqual(
            BoxBridgeHubState.loading.statusLine, "正在读取云电脑状态…"
        )
        // 桥未连接独立一态：不许说成电脑离线/未运行
        XCTAssertEqual(BoxBridgeHubState.bridgeUnavailable.statusLine, "桥未连接")
        XCTAssertEqual(BoxBridgeHubState.failed.statusLine, "云电脑状态读取失败")
        let running = BoxBridgeStatus(state: "running")
        XCTAssertEqual(
            BoxBridgeHubState.ready(running).statusLine, "云电脑运行中"
        )
    }

    // MARK: - 截图与动作回执

    func testScreenshotDecode() throws {
        let shot = try decoder.decode(
            BoxScreenshot.self, from: Data(shotJSON.utf8)
        )
        XCTAssertEqual(shot.width, 1024)
        XCTAssertEqual(shot.height, 640)
        XCTAssertEqual(shot.aspect, 1.6, accuracy: 0.0001)
        XCTAssertNotNil(shot.imageData)
        XCTAssertNotNil(shot.capturedAt)
        XCTAssertEqual(
            BoxTimeText.hhmmss(shot.capturedAt!, timeZone: tzPlus8),
            "16:17:38"
        )
    }

    func testActNavigateResponseDecode() throws {
        let json = """
        {"ok": true, "action": "navigate", "tool": "browser_navigate",
         "page": {"title": "Example Domain", "url": "https://example.com/"},
         "summary": "opened", "screenshot": \(shotJSON)}
        """
        let response = try decoder.decode(
            BoxActResponse.self, from: Data(json.utf8)
        )
        XCTAssertTrue(response.ok)
        XCTAssertEqual(response.tool, "browser_navigate")
        XCTAssertEqual(response.page?.title, "Example Domain")
        XCTAssertEqual(response.screenshot?.width, 1024)
    }

    func testActClickResponseWithoutPage() throws {
        let json = """
        {"ok": true, "action": "click", "tool": "computer_act",
         "summary": "clicked", "screenshot": \(shotJSON)}
        """
        let response = try decoder.decode(
            BoxActResponse.self, from: Data(json.utf8)
        )
        XCTAssertTrue(response.ok)
        XCTAssertNil(response.page)
        XCTAssertNotNil(response.screenshot)
    }

    // MARK: - 动作请求编码（字段白名单子集，nil 不编码）

    private func encodedObject(
        _ request: BoxActRequest
    ) throws -> [String: Any] {
        let data = try encoder.encode(request)
        let object = try JSONSerialization.jsonObject(with: data)
        return try XCTUnwrap(object as? [String: Any])
    }

    func testNavigateRequestEncoding() throws {
        let object = try encodedObject(.navigate("https://example.com/"))
        XCTAssertEqual(object["action"] as? String, "navigate")
        XCTAssertEqual(object["url"] as? String, "https://example.com/")
        XCTAssertEqual(object["front"] as? Bool, true)
        XCTAssertNil(object["x"])
        XCTAssertNil(object["text"])
        XCTAssertNil(object["key"])
    }

    func testClickRequestEncoding() throws {
        let object = try encodedObject(.click(x: 512, y: 300))
        XCTAssertEqual(object["action"] as? String, "click")
        XCTAssertEqual(object["x"] as? Int, 512)
        XCTAssertEqual(object["y"] as? Int, 300)
        XCTAssertNil(object["url"])
        XCTAssertNil(object["front"])
    }

    func testTypeAndKeyRequestEncoding() throws {
        let type = try encodedObject(.type("你好"))
        XCTAssertEqual(type["action"] as? String, "type")
        XCTAssertEqual(type["text"] as? String, "你好")
        let key = try encodedObject(.key("Enter"))
        XCTAssertEqual(key["action"] as? String, "key")
        XCTAssertEqual(key["key"] as? String, "Enter")
    }

    func testScreenshotRequestEncoding() throws {
        let data = try encoder.encode(BoxScreenshotRequest())
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        // 桥口径是驼峰 maxEdge，不是 max_edge
        XCTAssertEqual(object["maxEdge"] as? Int, 1024)
    }

    // MARK: - 地址规范化

    func testAddressNormalize() {
        XCTAssertNil(BoxAddressText.normalize("   "))
        XCTAssertEqual(
            BoxAddressText.normalize(" example.com "),
            "https://example.com"
        )
        XCTAssertEqual(
            BoxAddressText.normalize("http://a.b/c"), "http://a.b/c"
        )
        XCTAssertEqual(
            BoxAddressText.normalize("https://x.dev/p?q=1"),
            "https://x.dev/p?q=1"
        )
    }

    // MARK: - 坐标换算

    private let imageSize = CGSize(width: 1024, height: 640)

    func testMapperExactFit() {
        let container = CGSize(width: 1024, height: 640)
        XCTAssertEqual(
            BoxCoordinateMapper.fittedRect(
                container: container, image: imageSize
            ),
            CGRect(x: 0, y: 0, width: 1024, height: 640)
        )
        let center = BoxCoordinateMapper.imagePoint(
            viewPoint: CGPoint(x: 512, y: 320),
            container: container, image: imageSize
        )
        XCTAssertEqual(center?.x, 512)
        XCTAssertEqual(center?.y, 320)
        let origin = BoxCoordinateMapper.imagePoint(
            viewPoint: CGPoint(x: 0, y: 0),
            container: container, image: imageSize
        )
        XCTAssertEqual(origin?.x, 0)
        XCTAssertEqual(origin?.y, 0)
    }

    func testMapperLetterboxBarsRejectTaps() {
        // 容器 400×400、图 1024×640：fit 后 400×250，
        // 上下各 75 黑边——黑边点按必须落空
        let container = CGSize(width: 400, height: 400)
        XCTAssertEqual(
            BoxCoordinateMapper.fittedRect(
                container: container, image: imageSize
            ),
            CGRect(x: 0, y: 75, width: 400, height: 250)
        )
        XCTAssertNil(BoxCoordinateMapper.imagePoint(
            viewPoint: CGPoint(x: 200, y: 10),
            container: container, image: imageSize
        ))
        XCTAssertNil(BoxCoordinateMapper.imagePoint(
            viewPoint: CGPoint(x: 200, y: 399),
            container: container, image: imageSize
        ))
        let center = BoxCoordinateMapper.imagePoint(
            viewPoint: CGPoint(x: 200, y: 200),
            container: container, image: imageSize
        )
        XCTAssertEqual(center?.x, 512)
        XCTAssertEqual(center?.y, 320)
    }

    func testMapperPillarbox() {
        // 容器 800×300：fit 后 480×300，左右各 160
        let container = CGSize(width: 800, height: 300)
        XCTAssertNil(BoxCoordinateMapper.imagePoint(
            viewPoint: CGPoint(x: 10, y: 150),
            container: container, image: imageSize
        ))
        let center = BoxCoordinateMapper.imagePoint(
            viewPoint: CGPoint(x: 400, y: 150),
            container: container, image: imageSize
        )
        XCTAssertEqual(center?.x, 512)
        XCTAssertEqual(center?.y, 320)
    }

    func testMapperDegenerateSizes() {
        XCTAssertNil(BoxCoordinateMapper.imagePoint(
            viewPoint: CGPoint(x: 1, y: 1),
            container: .zero, image: imageSize
        ))
        XCTAssertEqual(
            BoxCoordinateMapper.fittedRect(
                container: CGSize(width: 100, height: 100), image: .zero
            ),
            .zero
        )
    }
}
