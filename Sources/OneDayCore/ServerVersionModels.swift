import Foundation

// MARK: - GET /api/hermes/update/check（Dashboard 会话，DESIGN §360）

/// 自更新检查回文。字段一律宽容解码：一般形态含
/// behind/update_available 等键，本部署（容器＋数据卷
/// /opt/data）恒走 managed 分支——install_method 为
/// "managed-runtime"、behind 为 null、can_apply 为
/// false、update_command 为空串（探活报告
/// blueprint-phase1-recon-20261122 §4.1 源码闭环＋
/// /api/status.can_update_hermes=false 生产旁证）。
public struct UpdateCheckResponse: Decodable, Sendable, Equatable {
    public let installMethod: String?
    public let currentVersion: String?
    public let behind: Int?
    public let updateAvailable: Bool?
    public let canApply: Bool?
    public let updateCommand: String?
    public let message: String?

    enum CodingKeys: String, CodingKey {
        case installMethod = "install_method"
        case currentVersion = "current_version"
        case behind
        case updateAvailable = "update_available"
        case canApply = "can_apply"
        case updateCommand = "update_command"
        case message
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        installMethod = try container.decodeIfPresent(String.self, forKey: .installMethod)
        currentVersion = try container.decodeIfPresent(String.self, forKey: .currentVersion)
        behind = try container.decodeIfPresent(Int.self, forKey: .behind)
        updateAvailable = try container.decodeIfPresent(Bool.self, forKey: .updateAvailable)
        canApply = try container.decodeIfPresent(Bool.self, forKey: .canApply)
        updateCommand = try container.decodeIfPresent(String.self, forKey: .updateCommand)
        message = try container.decodeIfPresent(String.self, forKey: .message)
    }

    /// 托管运行时形态：升级由部署外流程（换镜像）完成，
    /// 应用内永不执行更新（案 A 口径，DESIGN §360）
    public var isManagedRuntime: Bool { installMethod == "managed-runtime" }
}

// MARK: - GET /api/hermes/update/receipt（Dashboard 会话，DESIGN §360）

/// 更新回执回文（有更新运行记录时）。本部署从不在
/// 容器内跑 update，本端点恒 404——回执在位是面向
/// 非托管部署的宽容建模：只取摘要与结果两键，其余
/// 字段（steps/skips 等）不建模、解码忽略；键名对不
/// 上时落 nil，界面回落「有更新记录」，不编造内容。
public struct UpdateReceiptResponse: Decodable, Sendable, Equatable {
    public let summary: String?
    public let receipt: Receipt?

    public struct Receipt: Decodable, Sendable, Equatable {
        public let outcome: String?

        enum CodingKeys: String, CodingKey {
            case outcome
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            outcome = try container.decodeIfPresent(String.self, forKey: .outcome)
        }
    }

    enum CodingKeys: String, CodingKey {
        case summary
        case receipt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        summary = try container.decodeIfPresent(String.self, forKey: .summary)
        receipt = try container.decodeIfPresent(Receipt.self, forKey: .receipt)
    }

    /// 回执一句话：摘要优先，其次结果，再次只报「有」
    /// ——三级回落都不编造具体内容
    public var displayText: String {
        if let summary, !summary.isEmpty { return summary }
        if let outcome = receipt?.outcome, !outcome.isEmpty { return outcome }
        return "有更新记录"
    }
}

/// 更新回执的专属空态（DESIGN §360）：GET receipt
/// 回 404＝从未在本部署内跑过更新——空态是常态，
/// 不走通用失败面、不报「拉取失败」
public enum UpdateReceiptError: Error, Sendable, Equatable {
    case absent
}

// MARK: - 版本与更新段呈现合成（纯函数，DESIGN §360）

/// 「版本与更新」段的呈现事实：全部来自服务端真实
/// 回读（/api/status 与 update/check），合成口径在此
/// 单点钉死——拉不到的字段显「未记录」，版本在状态
/// 面缺席时以检查面的 current_version 回落（同为服
/// 务端原话）；托管判定以 /api/status 的
/// can_update_hermes 为主证、检查面 install_method
/// 为旁证，任一坐实即出托管说明
public struct ServerVersionFacts: Equatable, Sendable {
    public let versionText: String
    public let releaseDateText: String
    public let configVersionText: String
    /// 托管说明（已知托管时有值；非托管且服务端有原
    /// 话时为服务端 message 原文；皆无则 nil 不编造）
    public let managedNote: String?
}

public enum ServerVersionBuilder {
    /// 字段缺席的如实文案
    public static let missingText = "未记录"
    /// 托管说明定版文案（案 A：感知与执行分离——升级
    /// 走运维侧换镜像＋部署包流程，应用内不执行更新）
    public static let managedNoteText =
        "此服务器为容器部署，Hermes 的升级由运维侧更换镜像完成，应用内不执行更新。"

    public static func facts(
        status: ServerStatus?, check: UpdateCheckResponse?
    ) -> ServerVersionFacts {
        let version = status?.version ?? check?.currentVersion
        let configText: String
        if let current = status?.configVersion,
           let latest = status?.latestConfigVersion {
            configText = "\(current) / \(latest)"
        } else {
            configText = missingText
        }
        let isManaged = status?.canUpdateHermes == false
            || check?.isManagedRuntime == true
        let note: String?
        if isManaged {
            note = managedNoteText
        } else if status?.canUpdateHermes == true {
            // 非托管部署：只转述服务端原话，无原话不编造
            let message = check?.message?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            note = (message?.isEmpty == false) ? message : nil
        } else {
            note = nil
        }
        return ServerVersionFacts(
            versionText: version ?? missingText,
            releaseDateText: status?.releaseDate ?? missingText,
            configVersionText: configText,
            managedNote: note
        )
    }
}
