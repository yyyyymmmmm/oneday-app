import XCTest

/// §382 定因探针（非守门）：冷启首帧底栏图标呈实心、点一下
/// 恢复——分相位截图＋逐格墨迹密度取证。
/// 相位：A 首帧（栏件出现即拍）／B 静置 3 秒后／C 重点已选格
/// （聊天）后／D 切到目标格后／E 切回聊天后／F 重启再拍首帧。
/// 墨迹密度＝字形盒内与背景主导亮度差 >0.3 的像素占比：
/// fill 变体墨量约为 outline 的 2 倍量级（仓内 RenderMeasure
/// 同口径），同格跨相位对比即判变体是否翻转。
final class TabBarIconInitialProbeTests: XCTestCase {

    private let tabLabels = ["聊天", "动态", "点子", "目标", "资源库"]

    func testTabBarIconInitialVariantProbe() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-odDemoMode"]
        app.launch()
        defer { app.terminate() }

        let tabBar = app.tabBars.firstMatch
        guard tabBar.waitForExistence(timeout: 30) else {
            XCTFail("PROBE: tab bar not up")
            return
        }
        let firstBtn = tabBar.buttons["聊天"]
        guard firstBtn.waitForExistence(timeout: 10) else {
            XCTFail("PROBE: chat tab button not up")
            return
        }

        var report: [String] = []
        report.append(measure(app: app, phase: "A-initial"))

        Thread.sleep(forTimeInterval: 3)
        report.append(measure(app: app, phase: "B-idle3s"))

        tabBar.buttons["聊天"].tap()
        Thread.sleep(forTimeInterval: 1)
        report.append(measure(app: app, phase: "C-retapSelected"))

        tabBar.buttons["目标"].tap()
        Thread.sleep(forTimeInterval: 1)
        report.append(measure(app: app, phase: "D-switchGoals"))

        tabBar.buttons["聊天"].tap()
        Thread.sleep(forTimeInterval: 1)
        report.append(measure(app: app, phase: "E-backChat"))

        app.terminate()
        app.launch()
        guard tabBar.waitForExistence(timeout: 30) else {
            XCTFail("PROBE: tab bar not up after relaunch")
            return
        }
        _ = tabBar.buttons["聊天"].waitForExistence(timeout: 10)
        report.append(measure(app: app, phase: "F-relaunch"))

        // G 相位：深色外观冷启（设备外观未知，补此态取证）
        XCUIDevice.shared.appearance = .dark
        app.terminate()
        app.launch()
        if tabBar.waitForExistence(timeout: 30) {
            _ = tabBar.buttons["聊天"].waitForExistence(timeout: 10)
            report.append(measure(app: app, phase: "G-darkInitial"))
            tabBar.buttons["目标"].tap()
            Thread.sleep(forTimeInterval: 1)
            report.append(measure(app: app, phase: "H-darkSwitch"))
        } else {
            report.append("G-darkInitial: tabbar-missing")
        }
        XCUIDevice.shared.appearance = .light

        let text = report.joined(separator: "\n")
        let att = XCTAttachment(string: text)
        att.name = "tabicon-probe-report"
        att.lifetime = .keepAlways
        add(att)
        print("PROBE-REPORT-BEGIN\n\(text)\nPROBE-REPORT-END")
    }

    /// 拍全屏图，逐格算墨迹密度，返回一行文本
    private func measure(app: XCUIApplication, phase: String) -> String {
        let shot = XCUIScreen.main.screenshot()
        let att = XCTAttachment(screenshot: shot)
        att.name = "shot-\(phase)"
        att.lifetime = .keepAlways
        add(att)

        let image = shot.image
        guard let cg = image.cgImage else { return "\(phase): NO-CGIMAGE" }
        let pxW = cg.width
        let pxH = cg.height
        // 全屏图与窗口同幅：点→像素比例按图宽/窗宽
        let winW = app.frame.width
        guard winW > 0 else { return "\(phase): NO-WINDOW" }
        let scale = CGFloat(pxW) / winW

        // 读像素（RGBA8）
        var data = [UInt8](repeating: 0, count: pxW * pxH * 4)
        let cs = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: &data, width: pxW, height: pxH,
            bitsPerComponent: 8, bytesPerRow: pxW * 4,
            space: cs,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return "\(phase): NO-CTX" }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: pxW, height: pxH))

        let tabBar = app.tabBars.firstMatch
        var cells: [String] = []
        for label in tabLabels {
            let btn = tabBar.buttons[label]
            guard btn.exists else {
                cells.append("\(label)=missing")
                continue
            }
            let f = btn.frame
            // 字形盒：以钮中心为心的 40pt 方盒（像素坐标，
            // CGImage 原点左上、与窗口坐标同向）
            let boxPt: CGFloat = 40
            let cx = f.midX
            let cy = f.midY
            let x0 = Int((cx - boxPt / 2) * scale)
            let y0 = Int((cy - boxPt / 2) * scale)
            let side = Int(boxPt * scale)
            var hist = [Int](repeating: 0, count: 16)
            var lums: [Double] = []
            lums.reserveCapacity(side * side)
            for y in y0..<(y0 + side) {
                if y < 0 || y >= pxH { continue }
                for x in x0..<(x0 + side) {
                    if x < 0 || x >= pxW { continue }
                    let i = (y * pxW + x) * 4
                    let r = Double(data[i]) / 255
                    let g = Double(data[i + 1]) / 255
                    let b = Double(data[i + 2]) / 255
                    let lum = 0.2126 * r + 0.7152 * g + 0.0722 * b
                    lums.append(lum)
                    hist[min(15, Int(lum * 16))] += 1
                }
            }
            guard !lums.isEmpty else {
                cells.append("\(label)=empty")
                continue
            }
            // 背景＝直方图主导桶的中心亮度
            let bgBucket = hist.enumerated().max(by: { $0.element < $1.element })!.offset
            let bg = (Double(bgBucket) + 0.5) / 16
            let ink = lums.filter { abs($0 - bg) > 0.3 }.count
            let ratio = Double(ink) / Double(lums.count)
            cells.append(String(format: "%@=%.3f", label, ratio))
        }
        return "\(phase): " + cells.joined(separator: " ")
    }
}
