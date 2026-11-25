#if ONEDAY_TABBAR_DIAG

import Foundation
import OneDayCore
import OneDayDesign
import SwiftUI
import UIKit

/// §382 底栏图标真机诊断（诊断分支专用）：ONEDAY_TABBAR_DIAG
/// 编译开关隔离，出货线零污染；本文件只取证、不落任何修复。
///
/// 要证/证伪的推断：冷启时宿主首帧快照未应用底栏 label 的
/// 变体环境赋值（.symbolVariants＝.none），五格被按填充形态
/// 栅格化；首次切格后宿主重建条目、环境生效、回描边形态；
/// 其他重渲染（新建对话等）不触发条目重建、故不回正。
///
/// 进程内四点快照：
///   P1  底栏首次出现帧（轮询到 UITabBarButton 载图即抓）
///   P2  P1 后 +1s
///   P3  首次切格前残留态＝切格标记之前最后一帧 ROLL 快照
///       （滚动序列事后读日志认定）
///   P4  首次切格后 +0.4s（另 +1.5s 一帧 P4b）
/// 切格检出不挂 SwiftUI 钩子：滚动轮询实读按钮 isSelected
/// 变化检出（SWITCH-SEEN），selection 读数由按钮选中态映射
/// TabBarSymbols 顺序得到，同为进程内实读。
///
/// 每帧逐格实读：按钮内实际呈现图的墨迹密度（alpha 覆盖
/// 率）、像素尺寸、renderingMode、symbol 配置（pointSize/
/// weight/scale）；UITabBarItem 自持 image/selectedImage
/// 同口径；label 环境探针回读的 symbolVariants 环境值。
/// 另有同进程参考定标：同符号按代码口径（24pt light 原
/// 名）/.fill 名/semibold/bold 现渲密度，供逐帧比对归因
/// （变体派生 vs 字重派生可分辨）。
///
/// 快照只落本机 Application Support/OneDayDiagnostics/
/// tabbar-diag.json（跨进程启动追加、同文件留全程），经
/// 诊断页 ShareLink 由用户手动外发，绝不自动上传（与
/// §384 崩溃报告同口径）。

// MARK: - 数据模型

struct TabBarDiagTab: Codable {
    var tabID: String
    var intendedSymbol: String
    var buttonFound: Bool = false
    var buttonSelected: Bool = false
    var buttonImageInk: Double? = nil
    var buttonImageSize: String? = nil
    var buttonImageRenderMode: String? = nil
    var buttonImageConfig: String? = nil
    var itemImageInk: Double? = nil
    var itemImageConfig: String? = nil
    var itemSelectedImageInk: Double? = nil
    var itemSelectedImageConfig: String? = nil
    var envNote: String? = nil
}

struct TabBarDiagRef: Codable {
    var tabID: String
    var symbol: String
    /// 代码口径现渲：24pt light、原名
    var intendedInk: Double? = nil
    /// 同上但 .fill 名（符号无 fill 变体时为 nil）
    var fillInk: Double? = nil
    /// 24pt semibold 原名（字重派生对照）
    var semiboldInk: Double? = nil
    /// 24pt bold 原名（字重派生对照）
    var boldInk: Double? = nil
}

struct TabBarDiagEnvEvent: Codable {
    var uptime: Double
    var tabID: String
    var note: String
}

struct TabBarDiagSnapshot: Codable, Identifiable {
    var seq: Int
    var trigger: String
    var uptime: Double
    var wall: String
    var selection: String
    var barNote: String
    var tabs: [TabBarDiagTab]
    var id: Int { seq }
}

struct TabBarDiagPayload: Codable {
    var appVersion: String = ""
    var startedWall: String = ""
    var references: [TabBarDiagRef] = []
    var envEvents: [TabBarDiagEnvEvent] = []
    var snapshots: [TabBarDiagSnapshot] = []
}

private func tabDiagFmt(_ value: Double?) -> String {
    value.map { String(format: "%.3f", $0) } ?? "-"
}

private func tabDiagFmtT(_ value: Double) -> String {
    String(format: "%.2fs", value)
}

// MARK: - 本机存储（§384 CrashReportStore 同式）

enum TabBarDiagStore {
    static var fileURL: URL {
        let base = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory
        let dir = base.appendingPathComponent(
            "OneDayDiagnostics", isDirectory: true
        )
        try? FileManager.default.createDirectory(
            at: dir, withIntermediateDirectories: true
        )
        return dir.appendingPathComponent("tabbar-diag.json")
    }

    static func save(_ payload: TabBarDiagPayload) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(payload) {
            try? data.write(to: fileURL, options: [.atomic])
        }
    }

    static func load() -> TabBarDiagPayload? {
        guard let data = try? Data(contentsOf: fileURL) else {
            return nil
        }
        return try? JSONDecoder().decode(
            TabBarDiagPayload.self, from: data
        )
    }

    static func clear() {
        try? FileManager.default.removeItem(at: fileURL)
    }

    /// 外发全文：人读摘要（定标/探针/逐帧逐格）在前、
    /// 原始 JSON 在后，一次分享带齐
    static func exportText() -> String {
        guard let payload = load() else {
            return "（暂无底栏诊断记录）"
        }
        var lines: [String] = []
        lines.append(
            "§382 底栏图标诊断 version=\(payload.appVersion)"
                + " started=\(payload.startedWall)"
        )
        lines.append("— 参考定标（同进程现渲）—")
        for ref in payload.references {
            lines.append(
                "REF \(ref.tabID) \(ref.symbol):"
                    + " intended(24pt light)=\(tabDiagFmt(ref.intendedInk))"
                    + " fill=\(tabDiagFmt(ref.fillInk))"
                    + " semibold=\(tabDiagFmt(ref.semiboldInk))"
                    + " bold=\(tabDiagFmt(ref.boldInk))"
            )
        }
        lines.append("— label 环境探针事件 —")
        for event in payload.envEvents {
            lines.append(
                "ENV t+\(tabDiagFmtT(event.uptime))"
                    + " \(event.tabID): \(event.note)"
            )
        }
        lines.append("— 快照（P3＝首切标记前最后一帧 ROLL）—")
        for snap in payload.snapshots {
            lines.append(
                "[\(snap.seq)] \(snap.trigger)"
                    + " t+\(tabDiagFmtT(snap.uptime))"
                    + " wall=\(snap.wall) selection=\(snap.selection)"
            )
            lines.append("    bar: \(snap.barNote)")
            for tab in snap.tabs {
                lines.append(
                    "    \(tab.tabID) sym=\(tab.intendedSymbol)"
                        + " btn=\(tab.buttonFound)"
                        + " sel=\(tab.buttonSelected)"
                        + " ink=\(tabDiagFmt(tab.buttonImageInk))"
                        + " size=\(tab.buttonImageSize ?? "-")"
                        + " mode=\(tab.buttonImageRenderMode ?? "-")"
                        + " cfg=\(tab.buttonImageConfig ?? "-")"
                        + " itemInk=\(tabDiagFmt(tab.itemImageInk))"
                        + " itemCfg=\(tab.itemImageConfig ?? "-")"
                        + " selItemInk=\(tabDiagFmt(tab.itemSelectedImageInk))"
                        + " env=\(tab.envNote ?? "-")"
                )
            }
        }
        if let data = try? Data(contentsOf: fileURL),
           let raw = String(data: data, encoding: .utf8) {
            lines.append("— 原始 JSON —")
            lines.append(raw)
        }
        return lines.joined(separator: "\n")
    }
}

// MARK: - 记录器（进程内四点快照调度＋UIKit 实读）

@MainActor
final class TabBarDiagRecorder {
    static let shared = TabBarDiagRecorder()

    private var armed = false
    private var begun = false
    private var startUptime: TimeInterval = 0
    private var seq = 0
    private var payload = TabBarDiagPayload()
    private var lastSelectedIndex: Int? = nil
    private var sawFirstSwitch = false
    private var stopRolling = false
    private var rollCount = 0
    private var envLatest: [String: String] = [:]
    private var scheduleTask: Task<Void, Never>? = nil

    private init() {}

    /// App.init 挂点：只登记激活通知，进程激活后自启
    /// （不碰视图树、不改生产形态）
    func arm() {
        guard !armed else { return }
        armed = true
        NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.begin() }
        }
    }

    func begin() {
        guard !begun else { return }
        begun = true
        startUptime = ProcessInfo.processInfo.systemUptime
        // 跨进程追加：旧进程的冷启证据不被新进程覆盖
        if let old = TabBarDiagStore.load() {
            payload = old
            seq = old.snapshots.last?.seq ?? 0
        }
        let info = Bundle.main.infoDictionary
        payload.appVersion =
            (info?["CFBundleShortVersionString"] as? String ?? "?")
            + " (" + (info?["CFBundleVersion"] as? String ?? "?") + ")"
        payload.startedWall = Self.wallString(Date())
        payload.references = makeReferences()
        capture(trigger: "SESSION-进程启动")
        scheduleTask = Task { await self.runSchedule() }
    }

    /// label 环境探针回读（值变化才记事件，避免刷屏）
    func noteLabelEnv(
        tabID: String, variants: SymbolVariants,
        scale: Double, scheme: String
    ) {
        if armed && !begun { begin() }
        guard begun else { return }
        let note = "variants[eqNone=\(variants == .none)"
            + " eqFill=\(variants == .fill)"
            + " desc=\(String(describing: variants))]"
            + " scale=\(scale) scheme=\(scheme)"
        guard envLatest[tabID] != note else { return }
        envLatest[tabID] = note
        payload.envEvents.append(TabBarDiagEnvEvent(
            uptime: uptimeNow(), tabID: tabID, note: note
        ))
        if payload.envEvents.count > 200 {
            payload.envEvents.removeFirst(
                payload.envEvents.count - 200
            )
        }
        persist()
    }

    /// 诊断页手动抓帧
    func manualSnapshot() {
        if armed && !begun { begin() }
        guard begun else { return }
        capture(trigger: "MANUAL-手动快照")
    }

    func clearAll() {
        payload = TabBarDiagPayload()
        seq = 0
        lastSelectedIndex = nil
        envLatest = [:]
        TabBarDiagStore.clear()
    }

    // MARK: 调度

    private func runSchedule() async {
        // P1：50ms 轮询至底栏按钮载图（上限 15s）
        var ready = false
        for _ in 0..<300 {
            if tabBarImagesReady() { ready = true; break }
            try? await Task.sleep(for: .milliseconds(50))
        }
        capture(trigger: ready ? "P1-首帧" : "P1-超时未见底栏图")
        // P2：首帧后 +1s
        try? await Task.sleep(for: .seconds(1))
        capture(trigger: "P2-首帧后1s")
        // ROLL：250ms 滚动（切格前残留态全程留痕），
        // 首切结清或 480 帧（约 2 分钟）后停
        while !stopRolling && rollCount < 480 {
            try? await Task.sleep(for: .milliseconds(250))
            if stopRolling { break }
            rollCount += 1
            if capture(trigger: "ROLL") {
                handleSwitchDetected()
            }
        }
    }

    private func handleSwitchDetected() {
        let first = !sawFirstSwitch
        sawFirstSwitch = true
        capture(
            trigger: first ? "SWITCH-SEEN-首切检出" : "SWITCH-SEEN-切格检出"
        )
        Task {
            try? await Task.sleep(for: .milliseconds(400))
            self.capture(
                trigger: first ? "P4-首切后0.4s" : "SWITCH+0.4s"
            )
            if first {
                try? await Task.sleep(for: .milliseconds(1100))
                self.capture(trigger: "P4b-首切后1.5s")
                self.stopRolling = true
            }
        }
    }

    // MARK: 抓帧（返回值＝本帧检出 selection 变化）

    @discardableResult
    private func capture(trigger: String) -> Bool {
        seq += 1
        let (tabs, note, selectedIdx) = collect()
        var changed = false
        if let idx = selectedIdx {
            if let last = lastSelectedIndex, last != idx {
                changed = true
            }
            lastSelectedIndex = idx
        }
        payload.snapshots.append(TabBarDiagSnapshot(
            seq: seq, trigger: trigger, uptime: uptimeNow(),
            wall: Self.wallString(Date()),
            selection: selectedIdx.map {
                TabBarSymbols.all[$0].id
            } ?? "?",
            barNote: note, tabs: tabs
        ))
        // 总量护栏：超 800 帧先丢最旧 ROLL
        while payload.snapshots.count > 800,
              let idx = payload.snapshots.firstIndex(where: {
                  $0.trigger == "ROLL"
              }) {
            payload.snapshots.remove(at: idx)
        }
        persist()
        return changed
    }

    private func collect() -> ([TabBarDiagTab], String, Int?) {
        let pairs = TabBarSymbols.all
        var tabs: [TabBarDiagTab] = pairs.map {
            TabBarDiagTab(
                tabID: $0.id, intendedSymbol: $0.normal,
                envNote: envLatest[$0.id]
            )
        }
        guard let bar = findTabBar() else {
            return (tabs, "未找到 UITabBar", nil)
        }
        let buttons = findButtons(in: bar)
        let items = bar.items ?? []
        var selectedIdx: Int? = nil
        for i in tabs.indices {
            if i < buttons.count {
                let button = buttons[i]
                tabs[i].buttonFound = true
                let selected = (button as? UIControl)?.isSelected
                    ?? false
                tabs[i].buttonSelected = selected
                if selected { selectedIdx = i }
                if let imageView = findImageView(in: button),
                   let image = imageView.image {
                    tabs[i].buttonImageInk = inkDensity(of: image)
                    tabs[i].buttonImageSize = sizeString(image)
                    tabs[i].buttonImageRenderMode =
                        renderModeString(image.renderingMode)
                    tabs[i].buttonImageConfig =
                        symbolConfigString(image)
                }
            }
            if i < items.count {
                let item = items[i]
                if let image = item.image {
                    tabs[i].itemImageInk = inkDensity(of: image)
                    tabs[i].itemImageConfig =
                        symbolConfigString(image)
                }
                if let image = item.selectedImage {
                    tabs[i].itemSelectedImageInk =
                        inkDensity(of: image)
                    tabs[i].itemSelectedImageConfig =
                        symbolConfigString(image)
                }
                if item == bar.selectedItem { selectedIdx = i }
            }
        }
        let traits = bar.traitCollection
        let note = "barClass=\(type(of: bar))"
            + " items=\(items.count) buttons=\(buttons.count)"
            + " style=\(traits.userInterfaceStyle == .dark ? "dark" : "light")"
            + " scale=\(traits.displayScale)"
            + " tint=\(colorString(bar.tintColor))"
            + " frame=\(bar.frame.minX),\(bar.frame.minY)"
            + " \(bar.frame.width)x\(bar.frame.height)"
        return (tabs, note, selectedIdx)
    }

    // MARK: UIKit 内省

    private func findTabBar() -> UITabBar? {
        let windows = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
        var candidates: [UITabBar] = []
        for window in windows {
            collectTabBars(in: window, into: &candidates)
        }
        return candidates.first {
            ($0.items?.count ?? 0) == TabBarSymbols.all.count
                && $0.bounds.height > 0
        } ?? candidates.first
    }

    private func collectTabBars(
        in view: UIView, into acc: inout [UITabBar]
    ) {
        if let bar = view as? UITabBar { acc.append(bar) }
        for sub in view.subviews {
            collectTabBars(in: sub, into: &acc)
        }
    }

    private func findButtons(in bar: UITabBar) -> [UIView] {
        var found: [UIView] = []
        func walk(_ view: UIView) {
            if NSStringFromClass(type(of: view))
                == "UITabBarButton" {
                found.append(view)
            }
            for sub in view.subviews { walk(sub) }
        }
        walk(bar)
        return found.sorted {
            $0.convert($0.bounds, to: bar).minX
                < $1.convert($1.bounds, to: bar).minX
        }
    }

    private func findImageView(in root: UIView) -> UIImageView? {
        var all: [UIImageView] = []
        func walk(_ view: UIView) {
            if let imageView = view as? UIImageView {
                all.append(imageView)
            }
            for sub in view.subviews { walk(sub) }
        }
        walk(root)
        return all.first {
            NSStringFromClass(type(of: $0))
                == "UITabBarSwappableImageView" && $0.image != nil
        } ?? all.first { $0.image != nil }
    }

    private func tabBarImagesReady() -> Bool {
        guard let bar = findTabBar() else { return false }
        let buttons = findButtons(in: bar)
        guard buttons.count == TabBarSymbols.all.count else {
            return false
        }
        return buttons.allSatisfy {
            findImageView(in: $0)?.image != nil
        }
    }

    // MARK: 量测与格式化

    /// 墨迹密度：图按自身像素尺寸栅格化后 alpha>0.5 的
    /// 像素占比（模板符号的 alpha 即字形本体）
    private func inkDensity(of image: UIImage) -> Double? {
        let scale = max(image.scale, 1)
        let width = Int((image.size.width * scale).rounded())
        let height = Int((image.size.height * scale).rounded())
        guard width > 0, height > 0 else { return nil }
        var pixels = [UInt8](
            repeating: 0, count: width * height * 4
        )
        let space = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: &pixels, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: width * 4,
            space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.scaleBy(x: scale, y: scale)
        UIGraphicsPushContext(context)
        image.draw(in: CGRect(origin: .zero, size: image.size))
        UIGraphicsPopContext()
        var ink = 0
        for i in stride(from: 3, to: pixels.count, by: 4) {
            if pixels[i] > 127 { ink += 1 }
        }
        return Double(ink) / Double(width * height)
    }

    private func makeReferences() -> [TabBarDiagRef] {
        TabBarSymbols.all.map { pair in
            func image(
                _ name: String, _ weight: UIImage.SymbolWeight
            ) -> UIImage? {
                UIImage(
                    systemName: name,
                    withConfiguration: UIImage.SymbolConfiguration(
                        pointSize: 24, weight: weight
                    )
                )
            }
            return TabBarDiagRef(
                tabID: pair.id, symbol: pair.normal,
                intendedInk: image(pair.normal, .light)
                    .flatMap { inkDensity(of: $0) },
                fillInk: image(pair.normal + ".fill", .light)
                    .flatMap { inkDensity(of: $0) },
                semiboldInk: image(pair.normal, .semibold)
                    .flatMap { inkDensity(of: $0) },
                boldInk: image(pair.normal, .bold)
                    .flatMap { inkDensity(of: $0) }
            )
        }
    }

    private func symbolConfigString(_ image: UIImage) -> String? {
        guard let config = image.symbolConfiguration else {
            return nil
        }
        // 本 SDK 的 SymbolConfiguration 不再公开 pointSize/
        // weight/scale 成员，整配置 description 即运行时
        // 规范形态（含三项数值），同进程内逐帧可比
        return String(describing: config)
    }

    private func renderModeString(
        _ mode: UIImage.RenderingMode
    ) -> String {
        switch mode {
        case .automatic: return "automatic"
        case .alwaysOriginal: return "alwaysOriginal"
        case .alwaysTemplate: return "alwaysTemplate"
        @unknown default: return "unknown"
        }
    }

    private func sizeString(_ image: UIImage) -> String {
        "\(image.size.width)x\(image.size.height)@\(image.scale)x"
    }

    private func colorString(_ color: UIColor?) -> String {
        guard let color else { return "nil" }
        var r: CGFloat = 0, g: CGFloat = 0
        var b: CGFloat = 0, a: CGFloat = 0
        if color.getRed(&r, green: &g, blue: &b, alpha: &a) {
            return String(
                format: "rgba(%.2f,%.2f,%.2f,%.2f)", r, g, b, a
            )
        }
        return String(describing: color)
    }

    private func uptimeNow() -> Double {
        begun
            ? ProcessInfo.processInfo.systemUptime - startUptime
            : 0
    }

    private static func wallString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return formatter.string(from: date)
    }

    private func persist() {
        TabBarDiagStore.save(payload)
    }
}

// MARK: - label 环境探针（挂 tabLabel 背景，零尺寸不入视觉）

/// 回读 label 渲染点的 symbolVariants 环境实值：宿主构建
/// 底栏条目时若未吃进 label 的环境赋值，探针读数与按钮图
/// 的实际形态应当场对不上——这正是要抓的现行。
struct TabBarDiagEnvProbe: View {
    let tabID: String
    @Environment(\.symbolVariants) private var symbolVariants
    @Environment(\.displayScale) private var displayScale
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .onAppear { report() }
            .onChange(of: symbolVariants) { _, _ in report() }
    }

    private func report() {
        TabBarDiagRecorder.shared.noteLabelEnv(
            tabID: tabID, variants: symbolVariants,
            scale: Double(displayScale),
            scheme: colorScheme == .dark ? "dark" : "light"
        )
    }
}

// MARK: - 诊断页（设置→关于→内部实验区，§384 同置同式）

struct TabBarDiagView: View {
    @State private var refreshTick = 0
    @State private var showClearConfirm = false

    var body: some View {
        let _ = refreshTick
        let payload = TabBarDiagStore.load()
        List {
            Section {
                Text("冷启后进程自动抓底栏四点快照（首帧／+1s／切格前滚动／切格后），逐格实读实际呈现图的密度与符号配置，并附同进程参考定标。记录只存本机、不会自动上传；需要时用右上角分享发回。")
                    .font(.footnote)
                    .foregroundStyle(Palette.inkSecondary)
                Button {
                    TabBarDiagRecorder.shared.manualSnapshot()
                    refreshTick += 1
                } label: {
                    Text("立即抓一帧")
                }
            }
            .listRowBackground(Palette.surface)

            if let payload, !payload.references.isEmpty {
                Section {
                    ForEach(payload.references, id: \.tabID) { ref in
                        Text("REF \(ref.tabID) \(ref.symbol): intended=\(tabDiagFmt(ref.intendedInk)) fill=\(tabDiagFmt(ref.fillInk)) semibold=\(tabDiagFmt(ref.semiboldInk)) bold=\(tabDiagFmt(ref.boldInk))")
                            .font(.footnote.monospaced())
                            .textSelection(.enabled)
                    }
                } header: {
                    Text("参考定标（24pt 现渲）")
                }
                .listRowBackground(Palette.surface)
            }

            if let payload, !payload.envEvents.isEmpty {
                Section {
                    ForEach(
                        Array(payload.envEvents.suffix(20).enumerated()),
                        id: \.offset
                    ) { _, event in
                        Text("t+\(tabDiagFmtT(event.uptime)) \(event.tabID): \(event.note)")
                            .font(.footnote.monospaced())
                            .textSelection(.enabled)
                    }
                } header: {
                    Text("label 环境探针（近 20 条）")
                }
                .listRowBackground(Palette.surface)
            }

            if let payload, !payload.snapshots.isEmpty {
                ForEach(payload.snapshots) { snap in
                    Section {
                        Text(snapshotText(snap))
                            .font(.footnote.monospaced())
                            .textSelection(.enabled)
                    } header: {
                        Text("[\(snap.seq)] \(snap.trigger) · t+\(tabDiagFmtT(snap.uptime)) · 选中 \(snap.selection)")
                    }
                    .listRowBackground(Palette.surface)
                }
            } else {
                Section {
                    Text("暂无快照（冷启后自动抓取，或点上方「立即抓一帧」）")
                        .font(.footnote)
                        .foregroundStyle(Palette.inkSecondary)
                }
                .listRowBackground(Palette.surface)
            }
        }
        .listStyle(.insetGrouped)
        .background(Palette.settingsBG)
        .navigationTitle("底栏诊断（§382）")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                ShareLink(item: TabBarDiagStore.exportText()) {
                    Image(systemName: "square.and.arrow.up")
                }
                .disabled(payload == nil)
                Button {
                    refreshTick += 1
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                Button(role: .destructive) {
                    showClearConfirm = true
                } label: {
                    Image(systemName: "trash")
                }
                .disabled(payload == nil)
            }
        }
        .confirmationDialog(
            "清空全部底栏诊断记录？",
            isPresented: $showClearConfirm,
            titleVisibility: .visible
        ) {
            Button("清空", role: .destructive) {
                TabBarDiagRecorder.shared.clearAll()
                refreshTick += 1
            }
            Button("取消", role: .cancel) {}
        }
    }

    private func snapshotText(_ snap: TabBarDiagSnapshot) -> String {
        var lines = ["bar: \(snap.barNote)"]
        for tab in snap.tabs {
            lines.append(
                "\(tab.tabID) sym=\(tab.intendedSymbol)"
                    + " btn=\(tab.buttonFound) sel=\(tab.buttonSelected)"
                    + " ink=\(tabDiagFmt(tab.buttonImageInk))"
                    + " size=\(tab.buttonImageSize ?? "-")"
                    + " mode=\(tab.buttonImageRenderMode ?? "-")"
                    + " cfg=\(tab.buttonImageConfig ?? "-")"
                    + " itemInk=\(tabDiagFmt(tab.itemImageInk))"
                    + " selItemInk=\(tabDiagFmt(tab.itemSelectedImageInk))"
            )
        }
        return lines.joined(separator: "\n")
    }
}

#endif
