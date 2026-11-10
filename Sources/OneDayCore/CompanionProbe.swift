import Foundation

/// 伴生探测契约（本包，DESIGN §110）：登录后自动探
/// 测 /api/companion/info，把「伴生在不在、什么版本、
/// 模块健不健康、App 版本够不够」派生成设置页版本
/// 组可直接呈现的状态。本文件只管纯派生与缓存记录
/// 形：探测的网络动作在 App 层（LedgerBridgeClient.
/// probeCompanion 已有实现），其结果枚举经 App 层
/// 1:1 映射成本文件的 CompanionProbeOutcome 再入
/// 本文件的解析口——派生口径全部钉在这里、逐项有测。
///
/// 诚实口径（与全仓一致）：读不到不臆断——网络不
/// 可达/钥匙读不到面时 presence 只给 .unknown；缓存
/// 里的上次成功值只许以「上次读到」形态露面、带时
/// 刻、且不带健康结论（isStale），绝不冒充现值。

// MARK: - 探测结果（Core 映射形）

/// 一次探测的原始结果：与 App 层 CompanionProbe
/// 同构（detected 带 info 全量；missing＝info 面
/// 404；unreadable＝面在但钥读不到/格式不识；un-
/// reachable＝网络不可达/无钥）
public enum CompanionProbeOutcome: Equatable, Sendable {
    case detected(CompanionInfo)
    case missing
    case unreadable(Int)
    case unreachable
}

// MARK: - 版本串形态

/// 版本串形态与比较：定版形态＝三段数字（可带 v
/// 前缀），如 "1.0.7"/"0.37.0"。两段式（"1.0"）、
/// 后缀式（"1.0.7-beta"）、非数字一律「格式异常」：
/// 显示时原文照显（那是服务器自报的串），但版本
/// 比较不给结论（compare 返回 nil），不许拿异常串
/// 硬比出「需要升级/不需要」
public enum CompanionVersionForm {
    public static func isWellFormed(_ raw: String?) -> Bool {
        components(of: raw) != nil
    }

    /// 三段数字分量；格式异常返回 nil
    public static func components(of raw: String?) -> [Int]? {
        guard var text = raw?.trimmingCharacters(
            in: .whitespacesAndNewlines
        ), !text.isEmpty else { return nil }
        if text.hasPrefix("v") || text.hasPrefix("V") {
            text.removeFirst()
        }
        let parts = text.split(
            separator: ".", omittingEmptySubsequences: false
        )
        guard parts.count == 3 else { return nil }
        var out: [Int] = []
        for part in parts {
            guard !part.isEmpty,
                  part.allSatisfy({ $0.isNumber }),
                  let value = Int(part) else { return nil }
            out.append(value)
        }
        return out
    }

    /// 数值序比较（"1.10.0" > "1.9.0"，不走字面序）；
    /// 任一侧格式异常返回 nil（不给结论）
    public static func compare(
        _ lhs: String, _ rhs: String
    ) -> ComparisonResult? {
        guard let a = components(of: lhs),
              let b = components(of: rhs) else { return nil }
        for index in 0..<3 {
            if a[index] != b[index] {
                return a[index] < b[index]
                    ? .orderedAscending : .orderedDescending
            }
        }
        return .orderedSame
    }
}

// MARK: - 模块健康派生

/// 模块健康：由 info.modules 派生。状态词表据伴生
/// front 的 aggregate()/probe_module() 实产——up／
/// degraded／down／crash-loop／disabled／unknown。
/// 派生口径（逐项钉测）：
/// - "disabled"＝用户在服务端关掉的模块：单列，
///   不算异常（是人家自己的选择）
/// - "degraded" 或 degraded 旗为 true＝降级（还在
///   工作、功能打折）→ degradedModules
/// - "up"＝正常；其余一切（down/crash-loop/
///   unknown/空串/未见过的词）＝不可用 →
///   impairedModules（没见过的状态词不往好处猜）
/// - info 里缺席的模块不入任何名单（没报就不下结论）
/// 名单排序恒定：先按伴生模块定序（writeGate→
/// overview→box→oneday→device），未识 id 殿后按字
/// 面序——字典迭代序不许漏进呈现
public struct CompanionModuleHealth: Equatable, Sendable {
    public let degradedModules: [String]
    public let impairedModules: [String]
    public let disabledModules: [String]

    public init(
        degradedModules: [String], impairedModules: [String],
        disabledModules: [String]
    ) {
        self.degradedModules = degradedModules
        self.impairedModules = impairedModules
        self.disabledModules = disabledModules
    }

    public var isHealthy: Bool {
        degradedModules.isEmpty && impairedModules.isEmpty
    }

    /// 伴生模块定序（front MODULE_META 名册序）
    public static let moduleOrder = [
        "writeGate", "overview", "box", "oneday", "device",
    ]

    public static func derive(
        modules: [String: CompanionModuleInfo]
    ) -> CompanionModuleHealth {
        var degraded: [String] = []
        var impaired: [String] = []
        var disabled: [String] = []
        for (id, module) in modules {
            if module.state == "disabled" {
                disabled.append(id)
            } else if module.state == "degraded"
                        || module.degraded == true {
                degraded.append(id)
            } else if module.state == "up" {
                continue
            } else {
                impaired.append(id)
            }
        }
        return CompanionModuleHealth(
            degradedModules: sorted(degraded),
            impairedModules: sorted(impaired),
            disabledModules: sorted(disabled)
        )
    }

    private static func sorted(_ ids: [String]) -> [String] {
        ids.sorted { a, b in
            let rankA = moduleOrder.firstIndex(of: a)
                ?? Int.max
            let rankB = moduleOrder.firstIndex(of: b)
                ?? Int.max
            if rankA != rankB { return rankA < rankB }
            return a < b
        }
    }

    /// 模块人话名（front MODULE_META 的 name 字段；
    /// 未识 id 原样回 id 本身——它是服务端自报的名
    /// 册键，照显不编造）
    public static func displayName(
        _ id: String, locale: Locale = AppLocale.uiLocale
    ) -> String {
        switch id {
        case "writeGate": return L10n.string("审批", locale: locale)
        case "overview": return L10n.string("总览通知", locale: locale)
        case "box": return L10n.string("云电脑", locale: locale)
        case "oneday": return L10n.string("目标点子", locale: locale)
        case "device": return L10n.string("手机设备", locale: locale)
        default: return id
        }
    }
}

// MARK: - 缓存记录（最近一次成功探测）

/// 模块快照（Codable 形，与 CompanionModuleInfo
/// 互转；CompanionInfo 本体只有 Decodable、不能直
/// 接落盘，故落盘走本记录形）
public struct CompanionModuleSnapshot: Codable, Equatable, Sendable {
    public var state: String
    public var detail: String?
    public var degraded: Bool?

    public init(state: String, detail: String?, degraded: Bool?) {
        self.state = state
        self.detail = detail
        self.degraded = degraded
    }

    public init(_ info: CompanionModuleInfo) {
        state = info.state
        detail = info.detail
        degraded = info.degraded
    }

    public var info: CompanionModuleInfo {
        CompanionModuleInfo(
            state: state, detail: detail, degraded: degraded
        )
    }
}

/// 最近一次成功探测的落盘记录：只存 info 事实＋探
/// 测时刻（epoch 秒），呈现派生每次重算——旧记录
/// 绝不直接当现值显（见 CompanionStatus.isStale）
public struct CompanionProbeRecord: Codable, Equatable, Sendable {
    public var companionVersion: String?
    public var apiLevel: Int?
    public var minAppVersion: String?
    public var hermesUp: Bool?
    public var modules: [String: CompanionModuleSnapshot]
    public var probedAtEpoch: Double

    public init(
        companionVersion: String?, apiLevel: Int?,
        minAppVersion: String?, hermesUp: Bool?,
        modules: [String: CompanionModuleSnapshot],
        probedAtEpoch: Double
    ) {
        self.companionVersion = companionVersion
        self.apiLevel = apiLevel
        self.minAppVersion = minAppVersion
        self.hermesUp = hermesUp
        self.modules = modules
        self.probedAtEpoch = probedAtEpoch
    }

    public init(info: CompanionInfo, probedAt: Date) {
        companionVersion = info.companionVersion
        apiLevel = info.apiLevel
        minAppVersion = info.minAppVersion
        hermesUp = info.hermesUp
        modules = info.modules.mapValues(CompanionModuleSnapshot.init)
        probedAtEpoch = probedAt.timeIntervalSince1970
    }

    public var probedAt: Date {
        Date(timeIntervalSince1970: probedAtEpoch)
    }

    public var info: CompanionInfo {
        CompanionInfo(
            companionVersion: companionVersion,
            apiLevel: apiLevel, minAppVersion: minAppVersion,
            hermesUp: hermesUp,
            modules: modules.mapValues { $0.info },
            generatedAt: nil
        )
    }
}

// MARK: - 派生态

/// 设置页版本组的派生态：presence 三档（present＝
/// 读到了 info；absent＝info 面 404、这台服务器没
/// 有伴生面；unknown＝读不到、下不了结论）。isStale
/// ＝本状态来自缓存记录而非本轮现读——呈现必须走
/// 「上次读到」形态且不带健康结论（health 为 nil）
public struct CompanionStatus: Equatable, Sendable {
    public enum Presence: Equatable, Sendable {
        case present
        case absent
        case unknown
    }

    public let presence: Presence
    /// 服务器自报版本原文（非空才有；格式异常也照
    /// 存原文，wellFormed 另记）
    public let version: String?
    public let versionWellFormed: Bool
    /// 健康结论：只在现读 present 时给；stale/absent/
    /// unknown 恒 nil（不拿旧健康冒充现况）
    public let health: CompanionModuleHealth?
    public let hermesUp: Bool?
    /// 伴生要求的最低 App 版本：仅当 minAppVersion
    /// 格式正常且严格大于当前 App 版本时给出（相等
    /// 不算、异常串不给结论）
    public let appUpdateRequired: String?
    public let isStale: Bool
    public let probedAt: Date?

    public init(
        presence: Presence, version: String?,
        versionWellFormed: Bool,
        health: CompanionModuleHealth?, hermesUp: Bool?,
        appUpdateRequired: String?, isStale: Bool,
        probedAt: Date?
    ) {
        self.presence = presence
        self.version = version
        self.versionWellFormed = versionWellFormed
        self.health = health
        self.hermesUp = hermesUp
        self.appUpdateRequired = appUpdateRequired
        self.isStale = isStale
        self.probedAt = probedAt
    }

    /// 现读派生（detected）：健康/升级结论全给
    public static func derive(
        info: CompanionInfo, appVersion: String, probedAt: Date
    ) -> CompanionStatus {
        CompanionStatus(
            presence: .present,
            version: nonEmpty(info.companionVersion),
            versionWellFormed: CompanionVersionForm.isWellFormed(
                info.companionVersion
            ),
            health: CompanionModuleHealth.derive(
                modules: info.modules
            ),
            hermesUp: info.hermesUp,
            appUpdateRequired: updateRequired(
                minAppVersion: info.minAppVersion,
                appVersion: appVersion
            ),
            isStale: false,
            probedAt: probedAt
        )
    }

    /// 缓存派生：presence/version/升级结论照记录重
    /// 算，健康不给（nil）、isStale 恒 true
    public static func derive(
        cached record: CompanionProbeRecord, appVersion: String
    ) -> CompanionStatus {
        CompanionStatus(
            presence: .present,
            version: nonEmpty(record.companionVersion),
            versionWellFormed: CompanionVersionForm.isWellFormed(
                record.companionVersion
            ),
            health: nil,
            hermesUp: record.hermesUp,
            appUpdateRequired: updateRequired(
                minAppVersion: record.minAppVersion,
                appVersion: appVersion
            ),
            isStale: true,
            probedAt: record.probedAt
        )
    }

    public static func absent(probedAt: Date) -> CompanionStatus {
        CompanionStatus(
            presence: .absent, version: nil,
            versionWellFormed: false, health: nil,
            hermesUp: nil, appUpdateRequired: nil,
            isStale: false, probedAt: probedAt
        )
    }

    public static func unknown(probedAt: Date?) -> CompanionStatus {
        CompanionStatus(
            presence: .unknown, version: nil,
            versionWellFormed: false, health: nil,
            hermesUp: nil, appUpdateRequired: nil,
            isStale: false, probedAt: probedAt
        )
    }

    private static func nonEmpty(_ raw: String?) -> String? {
        guard let raw,
              !raw.trimmingCharacters(in: .whitespacesAndNewlines)
                .isEmpty else { return nil }
        return raw
    }

    private static func updateRequired(
        minAppVersion: String?, appVersion: String
    ) -> String? {
        guard let minAppVersion,
              CompanionVersionForm.isWellFormed(minAppVersion),
              let order = CompanionVersionForm.compare(
                appVersion, minAppVersion
              ) else { return nil }
        return order == .orderedAscending ? minAppVersion : nil
    }
}

// MARK: - 探测解析（结果×缓存→状态＋缓存动作）

/// 一次探测的完整解析：状态给呈现、缓存动作给存
/// 储层执行。口径（逐项钉测）：
/// - detected → 现读状态＋落盘新记录
/// - missing（404）→ absent 状态＋清缓存（面都没
///   了，不许再拿上次的版本出来显）
/// - unreadable/unreachable → 有缓存则回落缓存的
///   stale 状态、缓存保留；无缓存则 unknown
public struct CompanionProbeResolution: Equatable, Sendable {
    public enum CacheAction: Equatable, Sendable {
        case persist(CompanionProbeRecord)
        case clear
        case keep
    }

    public let status: CompanionStatus
    public let cacheAction: CacheAction

    public init(status: CompanionStatus, cacheAction: CacheAction) {
        self.status = status
        self.cacheAction = cacheAction
    }
}

public enum CompanionProbeResolver {
    public static func resolve(
        outcome: CompanionProbeOutcome,
        cached: CompanionProbeRecord?,
        appVersion: String, now: Date
    ) -> CompanionProbeResolution {
        switch outcome {
        case .detected(let info):
            return CompanionProbeResolution(
                status: .derive(
                    info: info, appVersion: appVersion,
                    probedAt: now
                ),
                cacheAction: .persist(
                    CompanionProbeRecord(info: info, probedAt: now)
                )
            )
        case .missing:
            return CompanionProbeResolution(
                status: .absent(probedAt: now),
                cacheAction: .clear
            )
        case .unreadable, .unreachable:
            if let cached {
                return CompanionProbeResolution(
                    status: .derive(
                        cached: cached, appVersion: appVersion
                    ),
                    cacheAction: .keep
                )
            }
            return CompanionProbeResolution(
                status: .unknown(probedAt: now),
                cacheAction: .keep
            )
        }
    }
}

// MARK: - 呈现文案（设置页版本组，L10n 三语）

extension CompanionStatus {
    /// 版本位：present 给 "v"＋原文（格式异常照显原
    /// 文——那是服务器自报的串）；无版本串给「版本
    /// 未知」；absent/unknown 在设置行走 settingsLine
    /// 的整行口径、本位不用
    public func versionText(
        locale: Locale = AppLocale.uiLocale
    ) -> String {
        if let version {
            return version.hasPrefix("v") || version.hasPrefix("V")
                ? version : "v\(version)"
        }
        return L10n.string("版本未知", locale: locale)
    }

    /// 设置行副行（一行说清版本与状态）：
    /// - present 现读：「v1.0.7 · 运行正常」／
    ///   「v1.0.7 · 目标点子暂时不可用」／降级与不
    ///   可用并存时以「；」分段；Hermes 联系不上另
    ///   附一段
    /// - present 缓存：「v1.0.7 · 上次读到 3 小时
    ///   前」——不带任何健康结论
    /// - absent：「未检测到」；unknown：「暂时读不到」
    public func settingsLine(
        now: Date = Date(), locale: Locale = AppLocale.uiLocale
    ) -> String {
        switch presence {
        case .absent:
            return L10n.string("未检测到", locale: locale)
        case .unknown:
            return L10n.string("暂时读不到", locale: locale)
        case .present:
            if isStale {
                let when = probedAt.map {
                    DisplayDate.relative(
                        $0, now: now, locale: locale
                    )
                } ?? ""
                return versionText(locale: locale) + " · "
                    + L10n.format(
                        "上次读到 %@", locale: locale, when
                    )
            }
            var segments: [String] = []
            if let health {
                if health.isHealthy {
                    segments.append(
                        L10n.string("运行正常", locale: locale)
                    )
                } else {
                    if !health.degradedModules.isEmpty {
                        let names = health.degradedModules
                            .map {
                                CompanionModuleHealth.displayName(
                                    $0, locale: locale
                                )
                            }
                            .joined(separator: "、")
                        segments.append(L10n.format(
                            "%@降级运行", locale: locale, names
                        ))
                    }
                    if !health.impairedModules.isEmpty {
                        let names = health.impairedModules
                            .map {
                                CompanionModuleHealth.displayName(
                                    $0, locale: locale
                                )
                            }
                            .joined(separator: "、")
                        segments.append(L10n.format(
                            "%@暂时不可用", locale: locale, names
                        ))
                    }
                }
            }
            if hermesUp == false {
                segments.append(L10n.string(
                    "Hermes 暂时联系不上", locale: locale
                ))
            }
            if segments.isEmpty {
                return versionText(locale: locale)
            }
            return versionText(locale: locale) + " · "
                + segments.joined(separator: "；")
        }
    }

    /// 版本组脚注（可行动的人话，只在有事时出现）：
    /// - absent：没探测到伴生——点名受影响的功能与
    ///   怎么办（去服务器确认已启动、回来自动重测）
    /// - 需要升级 App：点名目标版本
    /// - 其余（正常/读不到/缓存）：不出现（读不到不
    ///   吓人、缓存有「上次读到」在行内说清）
    public func footerNote(
        locale: Locale = AppLocale.uiLocale
    ) -> String? {
        if presence == .absent {
            return L10n.string(
                "未检测到伴生服务，动态、点子、台账暂时不可用。请在服务器上确认伴生服务已经启动，启动后回到这个页面会自动重新检测。",
                locale: locale
            )
        }
        if let appUpdateRequired {
            return L10n.format(
                "请把 App 升级到 %@ 版，伴生服务才能正常配合工作。",
                locale: locale, appUpdateRequired
            )
        }
        return nil
    }
}
