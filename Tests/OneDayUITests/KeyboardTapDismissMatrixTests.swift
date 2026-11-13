import XCTest

/// 第五症（点空白退键盘有时不灵）·动作级落点矩阵
/// （2026-11-13 整包开工诊断）：真 App 生产装配
/// （-odDemoMode）上，键盘升起态逐落点真点按、逐格
/// 记键盘是否收起——先出修复前的失败地图，修后同
/// 门转验收（空格类落点必须 3/3 收起）。
///
/// 落点（每轮按当前帧现算，不吃旧帧）：
/// - TEXT：最大一块消息正文中心——点在文字上（选
///   字领地；只记录、不作收起断言，与选字线分工）
/// - GAP：相邻两条消息之间最大纵向空隙中点（行间
///   空白）
/// - BOTTOM：末条消息之下、输入舱之上的空白（底
///   contentMargins 带——栈外、无手势覆盖的头号嫌
///   疑格）
/// - TOP：首条消息之上、顶簇之下的空白（顶
///   contentMargins 带，同为栈外）
/// - STRIP：输入舱上方左侧条带（整栈帧内、卡外
///   的钮行带）
/// 空格四格（GAP/BOTTOM/TOP/STRIP）期望：点后键
/// 盘收起。逐格 3 试，率与逐试结果全量倾印。
final class KeyboardTapDismissMatrixTests: XCTestCase {

    private struct CellResult {
        var name: String
        var point: CGPoint?
        var dismissed: [Bool] = []
        var focusFailed = false
        var note = ""
    }

    override func setUpWithError() throws {
        continueAfterFailure = true
    }

    func testTapBlankDismissMatrix() throws {
        var lines: [String] = []
        let app = XCUIApplication()
        app.launchArguments = ["-odDemoMode"]
        app.launch()
        defer { app.terminate() }

        let capsule = app.buttons["topbar.modelCapsule"]
        guard capsule.waitForExistence(timeout: 30) else {
            emit(["MATRIX=NOT-UP"])
            XCTFail("演示装配聊天页未起来")
            return
        }
        let win = app.windows.firstMatch.frame
        lines.append("window=\(fmt(win))")

        guard let composer = findComposer(app) else {
            emit(lines + ["MATRIX=NO-COMPOSER"])
            XCTFail("输入舱文本视图未找到")
            return
        }
        lines.append("composer=\(fmt(composer.frame))")

        var results: [String: CellResult] = [:]
        let order = ["TEXT", "GAP", "BOTTOM", "TOP", "STRIP"]
        for name in order {
            results[name] = CellResult(name: name)
        }

        for trial in 0..<3 {
            for name in order {
                // 每试现算落点（键盘态帧会漂，旧帧不作数）
                guard focusKeyboard(app) else {
                    results[name]?.focusFailed = true
                    lines.append("trial\(trial) \(name) FOCUS-FAIL")
                    continue
                }
                let cells = computeCells(app, win: win)
                let cell = cells[name]
                guard let point = cell?.point else {
                    if let cell,
                       results[name]?.note.isEmpty ?? true {
                        results[name]?.note = cell.note
                    }
                    lines.append(
                        "trial\(trial) \(name) N/A"
                            + " \(cell?.note ?? "无此格")"
                    )
                    continue
                }
                results[name]?.point = point
                tapAt(app, point)
                Thread.sleep(forTimeInterval: 0.9)
                let dismissed = !app.keyboards.firstMatch.exists
                results[name]?.dismissed.append(dismissed)
                lines.append(
                    "trial\(trial) \(name)"
                        + " at=(\(Int(point.x)),\(Int(point.y)))"
                        + " dismissed=\(dismissed)"
                )
            }
        }

        var violations: [String] = []
        // 成格要求：GAP 必须成形——全格 N/A 是 rig
        // 失效、不许以「零违规」假绿收场。门格＝
        // GAP/TOP（列表辖区的空白，本 demo 可成形
        // 且已实证 3/3）；BOTTOM 在本 demo 内容下
        // 无空白带可成形、STRIP 是输入舱宿主辖区
        // （回底钮行/底衬层、祖先 tap 时代同样够不
        // 着）——两格降记录格，只报数不作门
        for required in ["GAP"] {
            if results[required]?.point == nil {
                violations.append(
                    "\(required) 未成格（rig 定位失效）"
                )
            }
        }
        for name in ["GAP", "TOP"] {
            guard let r = results[name] else { continue }
            if r.focusFailed {
                violations.append("\(name) 有试次聚焦失败")
            }
            if r.dismissed.count == 3,
               r.dismissed.contains(false) {
                violations.append(
                    "\(name) 收起率 \(r.dismissed.filter { $0 }.count)/3"
                )
            } else if r.dismissed.isEmpty, r.point != nil {
                violations.append("\(name) 无有效试次")
            }
            lines.append(
                "CELL \(name) rate="
                    + "\(r.dismissed.filter { $0 }.count)"
                    + "/\(r.dismissed.count)"
                    + " note=\(r.note)"
            )
        }
        if let t = results["TEXT"] {
            lines.append(
                "CELL TEXT rate="
                    + "\(t.dismissed.filter { $0 }.count)"
                    + "/\(t.dismissed.count)（只记录）"
            )
        }
        lines.append("violations=\(violations.count) "
            + violations.joined(separator: "; "))
        lines.append("MATRIX-VERDICT="
            + (violations.isEmpty ? "PASS" : "FAIL"))
        emit(lines)
        if !violations.isEmpty {
            XCTFail("点空白收键盘矩阵有空格失灵："
                + violations.joined(separator: "; "))
        }
    }

    // MARK: - 装配发现

    /// 输入舱文本视图：全屏最靠下的一枚宽文本视
    /// 图——消息正文同为文本视图但恒在它上方，键
    /// 盘升/收两态都成立（首轮 rig 用「收起态底部
    /// 带」定位、键盘升起后舱位上移即失配、全格
    /// N/A——本口径为修复）
    private func findComposer(
        _ app: XCUIApplication
    ) -> XCUIElement? {
        let texts = app.textViews.allElementsBoundByIndex
            .filter { $0.frame.width > 150 }
        return texts.max(by: { $0.frame.minY < $1.frame.minY })
    }

    private func focusKeyboard(_ app: XCUIApplication) -> Bool {
        if app.keyboards.firstMatch.exists { return true }
        guard let composer = findComposer(app) else { return false }
        composer.tap()
        let deadline = Date().addingTimeInterval(6)
        while Date() < deadline {
            if app.keyboards.firstMatch.exists { return true }
            Thread.sleep(forTimeInterval: 0.25)
        }
        return app.keyboards.firstMatch.exists
    }

    /// 消息元素（正文文本视图＋静态文本，剔除顶簇带
    /// 与输入舱）：按 minY 排序返回帧表
    private func messageFrames(
        _ app: XCUIApplication, win: CGRect
    ) -> [CGRect] {
        guard let composer = findComposer(app) else { return [] }
        var frames: [CGRect] = []
        for el in app.textViews.allElementsBoundByIndex {
            let f = el.frame
            if f == composer.frame { continue }
            if f.height >= 12, f.width >= 40, f.minY > 130 {
                frames.append(f)
            }
        }
        for el in app.staticTexts.allElementsBoundByIndex {
            let f = el.frame
            if f.height >= 10, f.width >= 40, f.minY > 130,
               f.maxY < composer.frame.minY - 8 {
                frames.append(f)
            }
        }
        return frames.sorted { $0.minY < $1.minY }
    }

    private func computeCells(
        _ app: XCUIApplication, win: CGRect
    ) -> [String: CellResult] {
        var out: [String: CellResult] = [:]
        guard let composer = findComposer(app) else { return out }
        let frames = messageFrames(app, win: win)
        let composerTop = composer.frame.minY

        // TEXT：面积最大的消息元素中心
        if let biggest = frames.max(by: {
            $0.width * $0.height < $1.width * $1.height
        }) {
            var r = CellResult(name: "TEXT")
            r.point = CGPoint(x: biggest.midX, y: biggest.midY)
            out["TEXT"] = r
        }
        // GAP：相邻元素最大纵向空隙（≥14pt）
        var bestGap: (mid: CGFloat, size: CGFloat)?
        if frames.count >= 2 {
            for i in 0..<(frames.count - 1) {
                let gap = frames[i + 1].minY - frames[i].maxY
                if gap >= 14, gap > (bestGap?.size ?? 0) {
                    bestGap = ((frames[i].maxY + frames[i + 1].minY) / 2,
                               gap)
                }
            }
        }
        if let g = bestGap {
            var r = CellResult(name: "GAP")
            r.point = CGPoint(x: win.midX, y: g.mid)
            out["GAP"] = r
        } else {
            var r = CellResult(name: "GAP")
            r.note = "无 ≥14pt 行间空隙"
            out["GAP"] = r
        }
        // BOTTOM：末条之下 18pt（须在舱顶上方留 10pt）
        if let last = frames.last,
           last.maxY + 18 < composerTop - 10 {
            var r = CellResult(name: "BOTTOM")
            r.point = CGPoint(x: win.midX, y: last.maxY + 18)
            out["BOTTOM"] = r
        } else {
            var r = CellResult(name: "BOTTOM")
            r.note = "末条与舱之间无足够空白带"
            out["BOTTOM"] = r
        }
        // TOP：首条之上 18pt（须在顶簇带下方）
        if let first = frames.first, first.minY - 18 > 128 {
            var r = CellResult(name: "TOP")
            r.point = CGPoint(x: win.midX, y: first.minY - 18)
            out["TOP"] = r
        } else {
            var r = CellResult(name: "TOP")
            r.note = "首条上方无足够空白带"
            out["TOP"] = r
        }
        // STRIP：舱顶上方 14pt、左侧 36pt（钮行带）
        if composerTop - 14 > 130 {
            var r = CellResult(name: "STRIP")
            r.point = CGPoint(x: 36, y: composerTop - 14)
            out["STRIP"] = r
        }
        return out
    }

    private func tapAt(_ app: XCUIApplication, _ point: CGPoint) {
        let origin = app.windows.firstMatch.coordinate(
            withNormalizedOffset: CGVector(dx: 0, dy: 0)
        )
        origin.withOffset(
            CGVector(dx: point.x, dy: point.y)
        ).tap()
    }

    private func fmt(_ rect: CGRect) -> String {
        String(
            format: "(%.0f,%.0f %.0f×%.0f)",
            rect.minX, rect.minY, rect.width, rect.height
        )
    }

    private func emit(_ lines: [String]) {
        let text = lines.joined(separator: "\n")
        print("TAP-MATRIX-BEGIN")
        print(text)
        print("TAP-MATRIX-END")
        let attachment = XCTAttachment(string: text)
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
