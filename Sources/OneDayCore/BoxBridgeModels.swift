import Foundation

// MARK: - 盒桥契约模型（P2 浏览器打通，2026-11-09 冻结）
//
// 契约以 box-bridge-rollout-20261109.md 为准：基址
// /api/box-bridge，鉴权复用 write-gate 桥钥匙。三条如实
// 口径钉在本层：① creditsLeft 在当前计划下恒 null（厂商
// billing 报错），模型只解码不编造；② 页面活读（page）
// 会随厂商自动化绑定失效而落空，此时只许以 lastKnownPage
// ＋时刻呈现，文案必须带「最后确认于」不许冒充实时；
// ③ 接管是「一动作一回图」的回合制（computer_act 语义），
// 坐标系＝最近一张截图的像素空间（默认 1024×640）。

/// ISO8601 解析（桥的时间字段形态：带时区偏移、可带
/// 小数秒；两种都试，失败返回 nil 不许猜）
public enum BoxISO8601 {
    // ISO8601DateFormatter 非 Sendable，Swift 6 不许作
    // 静态共享——解析是低频调用，每次现造，不缓存
    public static func parse(_ raw: String?) -> Date? {
        guard let raw, !raw.isEmpty else { return nil }
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [
            .withInternetDateTime, .withFractionalSeconds
        ]
        if let date = withFraction.date(from: raw) { return date }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: raw)
    }
}

/// 时刻文案（HH:mm / HH:mm:ss）：时区可注入以便单测
/// 钉死，生产走设备当前时区
public enum BoxTimeText {
    public static func hhmm(_ date: Date, timeZone: TimeZone = .current) -> String {
        format(date, pattern: "HH:mm", timeZone: timeZone)
    }

    public static func hhmmss(_ date: Date, timeZone: TimeZone = .current) -> String {
        format(date, pattern: "HH:mm:ss", timeZone: timeZone)
    }

    /// 日期＋时刻（P9 电脑状态面「最后保存」用）
    public static func dateTime(_ date: Date, timeZone: TimeZone = .current) -> String {
        format(date, pattern: "MM-dd HH:mm", timeZone: timeZone)
    }

    private static func format(
        _ date: Date, pattern: String, timeZone: TimeZone
    ) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = pattern
        return formatter.string(from: date)
    }
}

// MARK: - 状态

/// 页面引用（活读 page 与 lastKnownPage 同形）
public struct BoxPageRef: Decodable, Equatable, Sendable {
    public let title: String
    public let url: String

    public init(title: String, url: String) {
        self.title = title
        self.url = url
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? ""
        url = try container.decodeIfPresent(String.self, forKey: .url) ?? ""
    }

    private enum CodingKeys: String, CodingKey {
        case title, url
    }

    /// 标题行为人话：标题为空回落网址，网址再空给占位
    public var titleText: String {
        if !title.isEmpty { return title }
        if !url.isEmpty { return url }
        return "未命名页面"
    }
}

/// 页面呈现三态：活读／最后确认（带时刻）／无页面——
/// 旧状态只许以第二态出现，不许混进活读
public enum BoxPagePresentation: Equatable, Sendable {
    case live(BoxPageRef)
    case lastKnown(BoxPageRef, at: Date?)
    case none
}

/// GET /status 回执（rollout 冻结形状）
public struct BoxBridgeStatus: Decodable, Equatable, Sendable {
    /// box_status 原生值（running / hibernated 等），原样保留
    public let state: String
    public let name: String?
    public let boxId: String?
    public let image: String?
    public let latestImage: String?
    public let upgradeAvailable: Bool?
    public let lastSavedAtMs: Int64?
    public let viewUrl: String?
    /// 当前计划下恒 nil（厂商 billing 未启用）——只解码，
    /// 有值才显示，没值不出现额度行，不许编造
    public let creditsLeft: Double?
    public let creditsNote: String?
    /// 活读页面：自动化绑定失效时为 nil（诚实落空）
    public let page: BoxPageRef?
    public let lastKnownPage: BoxPageRef?
    public let lastKnownPageAtRaw: String?
    public let checkedAtRaw: String?

    public init(
        state: String, name: String? = nil, boxId: String? = nil,
        image: String? = nil, latestImage: String? = nil,
        upgradeAvailable: Bool? = nil, lastSavedAtMs: Int64? = nil,
        viewUrl: String? = nil, creditsLeft: Double? = nil,
        creditsNote: String? = nil, page: BoxPageRef? = nil,
        lastKnownPage: BoxPageRef? = nil, lastKnownPageAtRaw: String? = nil,
        checkedAtRaw: String? = nil
    ) {
        self.state = state
        self.name = name
        self.boxId = boxId
        self.image = image
        self.latestImage = latestImage
        self.upgradeAvailable = upgradeAvailable
        self.lastSavedAtMs = lastSavedAtMs
        self.viewUrl = viewUrl
        self.creditsLeft = creditsLeft
        self.creditsNote = creditsNote
        self.page = page
        self.lastKnownPage = lastKnownPage
        self.lastKnownPageAtRaw = lastKnownPageAtRaw
        self.checkedAtRaw = checkedAtRaw
    }

    private enum CodingKeys: String, CodingKey {
        case state, name, boxId, image, latestImage, upgradeAvailable
        case lastSavedAtMs, viewUrl, creditsLeft, creditsNote
        case page, lastKnownPage
        case lastKnownPageAtRaw = "lastKnownPageAt"
        case checkedAtRaw = "checkedAt"
    }

    public var isRunning: Bool { state == "running" }

    /// 状态词：只对实测过的原生值给译名（running＝运行、
    /// hibernated 系＝休眠），其余一律「未运行」，不猜
    public var stateText: String {
        switch state {
        case "running":
            return "运行中"
        case "hibernated", "hibernating", "sleeping", "asleep":
            return "休眠中"
        default:
            return "未运行"
        }
    }

    public var statusLine: String { "云电脑\(stateText)" }

    public var lastKnownPageAt: Date? { BoxISO8601.parse(lastKnownPageAtRaw) }
    public var checkedAt: Date? { BoxISO8601.parse(checkedAtRaw) }

    /// 最后保存时刻（桥给毫秒时间戳；缺失为 nil 不许猜）
    public var lastSavedAt: Date? {
        guard let lastSavedAtMs else { return nil }
        return Date(timeIntervalSince1970: Double(lastSavedAtMs) / 1000)
    }

    /// 镜像行（P9 状态面）：镜像名原文；桥报可更新且
    /// 目标镜像不同才带「可更新到」后缀，其余不加戏
    public var imageLine: String? {
        guard let image, !image.isEmpty else { return nil }
        if upgradeAvailable == true, let latestImage,
           !latestImage.isEmpty, latestImage != image {
            return "系统 \(image) · 可更新到 \(latestImage)"
        }
        return "系统 \(image)"
    }

    /// 额度行（全 App 单一口径，浏览器面与电脑面共用）：
    /// 有真实数字给「剩余额度 X」；数字恒缺（当前计划
    /// billing 未启用）时给厂商原文 note——原文呈现、
    /// 不翻译不编造；两者皆无则整行不出
    public var creditsLine: String? {
        if let creditsLeft {
            return "剩余额度 \(creditsLeft.formatted())"
        }
        if let creditsNote, !creditsNote.isEmpty {
            return creditsNote
        }
        return nil
    }

    /// 页面呈现：活读优先；活读落空才退最后确认（带时刻）
    public var pagePresentation: BoxPagePresentation {
        if let page { return .live(page) }
        if let lastKnownPage {
            return .lastKnown(lastKnownPage, at: lastKnownPageAt)
        }
        return .none
    }

    /// 页面标题行（活读与最后确认同取标题，无页面给占位）
    public var pageTitleText: String {
        switch pagePresentation {
        case .live(let page), .lastKnown(let page, _):
            return page.titleText
        case .none:
            return "还没有打开的页面"
        }
    }

    /// 页面副行：活读给网址；最后确认给网址＋「最后确认
    /// 于 HH:mm」（时刻解析不出时只给网址＋标注无时刻，
    /// 不许装实时）；无页面为空串
    public func pageMetaText(timeZone: TimeZone = .current) -> String {
        switch pagePresentation {
        case .live(let page):
            return page.url
        case .lastKnown(let page, let at):
            guard let at else { return page.url }
            return "\(page.url) · 最后确认于 \(BoxTimeText.hhmm(at, timeZone: timeZone))"
        case .none:
            return ""
        }
    }
}

/// 浏览器面状态机：桥未连接（无钥匙/401）是独立一态——
/// 沿 0.7.0 口径露「桥未连接」，绝不压成电脑离线/未运行
public enum BoxBridgeHubState: Equatable, Sendable {
    case loading
    case ready(BoxBridgeStatus)
    case bridgeUnavailable
    case failed

    public var statusLine: String {
        switch self {
        case .loading:
            return "正在读取云电脑状态…"
        case .ready(let status):
            return status.statusLine
        case .bridgeUnavailable:
            return "还没连上"
        case .failed:
            return "云电脑状态没读出来，可能是网络或服务暂时没响应"
        }
    }
}

// MARK: - 截图

/// POST /screenshot 与 /act 回带的截图结构（同形）
public struct BoxScreenshot: Decodable, Equatable, Sendable {
    public let mime: String
    public let width: Int
    public let height: Int
    public let bytes: Int
    public let imageBase64: String
    public let capturedAtRaw: String?

    public init(
        mime: String, width: Int, height: Int, bytes: Int,
        imageBase64: String, capturedAtRaw: String? = nil
    ) {
        self.mime = mime
        self.width = width
        self.height = height
        self.bytes = bytes
        self.imageBase64 = imageBase64
        self.capturedAtRaw = capturedAtRaw
    }

    private enum CodingKeys: String, CodingKey {
        case mime, width, height, bytes, imageBase64
        case capturedAtRaw = "capturedAt"
    }

    public var capturedAt: Date? { BoxISO8601.parse(capturedAtRaw) }

    /// 图字节：base64 解不出返回 nil（视图据此走失败态，
    /// 不许拿空图冒充画面）
    public var imageData: Data? { Data(base64Encoded: imageBase64) }

    /// 宽高比（整屏预览 aspect 用）：高非法时回落 1.6
    public var aspect: Double {
        height > 0 ? Double(width) / Double(height) : 1.6
    }
}

/// POST /screenshot 请求体（桥口径：maxEdge 驼峰键）
public struct BoxScreenshotRequest: Encodable, Sendable, Equatable {
    public let maxEdge: Int

    public init(maxEdge: Int = 1024) {
        self.maxEdge = maxEdge
    }
}

// MARK: - 接管动作

/// POST /act 请求体：字段白名单内的子集（导航/点击/
/// 输入/按键），nil 字段不编码（桥按动作取用）
public struct BoxActRequest: Encodable, Equatable, Sendable {
    public let action: String
    public let url: String?
    public let front: Bool?
    public let x: Int?
    public let y: Int?
    public let text: String?
    public let key: String?

    private init(
        action: String, url: String? = nil, front: Bool? = nil,
        x: Int? = nil, y: Int? = nil, text: String? = nil,
        key: String? = nil
    ) {
        self.action = action
        self.url = url
        self.front = front
        self.x = x
        self.y = y
        self.text = text
        self.key = key
    }

    public static func navigate(_ url: String) -> BoxActRequest {
        BoxActRequest(action: "navigate", url: url, front: true)
    }

    public static func click(x: Int, y: Int) -> BoxActRequest {
        BoxActRequest(action: "click", x: x, y: y)
    }

    public static func type(_ text: String) -> BoxActRequest {
        BoxActRequest(action: "type", text: text)
    }

    public static func key(_ key: String) -> BoxActRequest {
        BoxActRequest(action: "key", key: key)
    }
}

/// POST /act 回执：一动作一回图（screenshot 可缺——
/// 桥补截失败时如实缺，视图保留旧图并标注）
public struct BoxActResponse: Decodable, Equatable, Sendable {
    public let ok: Bool
    public let action: String
    public let tool: String?
    public let page: BoxPageRef?
    public let summary: String?
    public let screenshot: BoxScreenshot?

    public init(
        ok: Bool, action: String, tool: String? = nil,
        page: BoxPageRef? = nil, summary: String? = nil,
        screenshot: BoxScreenshot? = nil
    ) {
        self.ok = ok
        self.action = action
        self.tool = tool
        self.page = page
        self.summary = summary
        self.screenshot = screenshot
    }
}

/// 接管地址栏输入规范化：去空白；已有 scheme（含 ://)
/// 原样；裸域名/路径补 https://；空串返回 nil 不发动作。
/// 桥侧对 navigate 只放行 http/https，补全只补 https。
public enum BoxAddressText {
    public static func normalize(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.contains("://") { return trimmed }
        return "https://" + trimmed
    }
}

// MARK: - 坐标换算（接管点击）

/// 截图在显示区内 aspect-fit 后的坐标换算：点按位置
/// （视图坐标）→ 截图像素坐标（桥的坐标系）。落在
/// letterbox 黑边区返回 nil——点空不许误译成图内点击。
public enum BoxCoordinateMapper {
    /// aspect-fit 后图在容器内的实际矩形
    public static func fittedRect(
        container: CGSize, image: CGSize
    ) -> CGRect {
        guard container.width > 0, container.height > 0,
              image.width > 0, image.height > 0 else { return .zero }
        let scale = min(
            container.width / image.width, container.height / image.height
        )
        let width = image.width * scale
        let height = image.height * scale
        return CGRect(
            x: (container.width - width) / 2,
            y: (container.height - height) / 2,
            width: width, height: height
        )
    }

    /// 视图点 → 图像素点（四舍五入＋钳进图界）
    public static func imagePoint(
        viewPoint: CGPoint, container: CGSize, image: CGSize
    ) -> (x: Int, y: Int)? {
        let rect = fittedRect(container: container, image: image)
        guard rect.width > 0, rect.height > 0,
              rect.contains(viewPoint) else { return nil }
        let fractionX = (viewPoint.x - rect.minX) / rect.width
        let fractionY = (viewPoint.y - rect.minY) / rect.height
        let pixelX = Int((fractionX * image.width).rounded())
        let pixelY = Int((fractionY * image.height).rounded())
        return (
            x: min(max(pixelX, 0), Int(image.width) - 1),
            y: min(max(pixelY, 0), Int(image.height) - 1)
        )
    }
}
