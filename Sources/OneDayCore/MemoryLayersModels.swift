import Foundation

/// OneDay 分层记忆清单、语义混合搜索与 ExpeL 洞察账本模型（hermes-deploy 1.11.0+ / 2.6.0）
/// 对应真实网关端点：
/// - `GET /v1/memory/layers`
/// - `GET /v1/memory/search?q=&limit=&mode=hybrid`
/// - `GET /v1/memory/insights`

public struct MemoryLayerSummary: Decodable, Equatable, Sendable, Identifiable {
    public var id: String { layer }
    public let layer: String
    public let files: Int
    public let entries: Int
    public let bytes: Int
    public let newestMtime: String?
    public let provenanceCoverage: Double?

    private enum CodingKeys: String, CodingKey {
        case layer, files, entries, bytes
        case newestMtime = "newest_mtime"
        case provenanceCoverage = "provenance_coverage"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.layer = (try? c.decode(String.self, forKey: .layer)) ?? "unknown"
        self.files = (try? c.decode(Int.self, forKey: .files)) ?? 0
        self.entries = (try? c.decode(Int.self, forKey: .entries)) ?? 0
        self.bytes = (try? c.decode(Int.self, forKey: .bytes)) ?? 0
        self.newestMtime = try? c.decode(String.self, forKey: .newestMtime)
        self.provenanceCoverage = try? c.decode(Double.self, forKey: .provenanceCoverage)
    }

    public var displayTitle: String {
        switch layer.lowercased() {
        case "core", "memory": return "核心长期记忆"
        case "user", "profile": return "用户画像"
        case "episodic", "episodes": return "情景记忆"
        case "semantic", "facts": return "事实与知识"
        case "procedural", "rules": return "行为规则"
        case "insights": return "提炼洞察"
        case "projects", "goals": return "项目与目标"
        case "scratch", "working": return "工作暂存"
        default: return layer
        }
    }

    public var symbolName: String {
        switch layer.lowercased() {
        case "core", "memory": return "brain.head.profile"
        case "user", "profile": return "person.crop.circle"
        case "episodic", "episodes": return "clock.arrow.circlepath"
        case "semantic", "facts": return "book.closed"
        case "procedural", "rules": return "checklist"
        case "insights": return "lightbulb"
        case "projects", "goals": return "flag"
        default: return "tray.full"
        }
    }
}

public struct MemoryLayersResponse: Decodable, Equatable, Sendable {
    public let layers: [MemoryLayerSummary]

    public init(layers: [MemoryLayerSummary] = []) {
        self.layers = layers
    }
}

public struct MemorySearchHit: Decodable, Equatable, Sendable, Identifiable {
    public let id: String
    public let title: String
    public let layer: String
    public let file: String?
    public let score: Double
    public let recency: Double?
    public let snippet: String
    public let plain: Bool

    private enum CodingKeys: String, CodingKey {
        case id, title, layer, file, score, recency, snippet, plain
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = (try? c.decode(String.self, forKey: .id)) ?? UUID().uuidString
        self.title = (try? c.decode(String.self, forKey: .title)) ?? ""
        self.layer = (try? c.decode(String.self, forKey: .layer)) ?? ""
        self.file = try? c.decode(String.self, forKey: .file)
        self.score = (try? c.decode(Double.self, forKey: .score)) ?? 0
        self.recency = try? c.decode(Double.self, forKey: .recency)
        self.snippet = (try? c.decode(String.self, forKey: .snippet)) ?? ""
        self.plain = (try? c.decode(Bool.self, forKey: .plain)) ?? false
    }
}

public struct MemorySearchResponse: Decodable, Equatable, Sendable {
    public let query: String
    public let hits: [MemorySearchHit]

    public init(query: String = "", hits: [MemorySearchHit] = []) {
        self.query = query
        self.hits = hits
    }
}

public struct MemoryInsightItem: Decodable, Equatable, Sendable, Identifiable {
    public let id: String
    public let rule: String
    public let scope: String
    public let votesUp: Int
    public let votesDown: Int
    public let relapseCount: Int
    public let status: String
    public let src: String?
    public let first: String?
    public let last: String?

    private enum CodingKeys: String, CodingKey {
        case id, rule, scope, status, src, first, last
        case votesUp = "votes_up"
        case votesDown = "votes_down"
        case relapseCount = "relapse_count"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = (try? c.decode(String.self, forKey: .id)) ?? UUID().uuidString
        self.rule = (try? c.decode(String.self, forKey: .rule)) ?? ""
        self.scope = (try? c.decode(String.self, forKey: .scope)) ?? "general"
        self.votesUp = (try? c.decode(Int.self, forKey: .votesUp)) ?? 0
        self.votesDown = (try? c.decode(Int.self, forKey: .votesDown)) ?? 0
        self.relapseCount = (try? c.decode(Int.self, forKey: .relapseCount)) ?? 0
        self.status = (try? c.decode(String.self, forKey: .status)) ?? "candidate"
        self.src = try? c.decode(String.self, forKey: .src)
        self.first = try? c.decode(String.self, forKey: .first)
        self.last = try? c.decode(String.self, forKey: .last)
    }

    public var statusLabel: String {
        switch status.lowercased() {
        case "active": return "生效中"
        case "candidate": return "候选中"
        case "retired": return "已退役"
        default: return status
        }
    }
}

public struct MemoryInsightsResponse: Decodable, Equatable, Sendable {
    public let insights: [MemoryInsightItem]

    private enum CodingKeys: String, CodingKey {
        case insights, data, items
    }

    public init(insights: [MemoryInsightItem] = []) {
        self.insights = insights
    }

    public init(from decoder: Decoder) throws {
        if let single = try? decoder.singleValueContainer(),
           let array = try? single.decode([MemoryInsightItem].self) {
            self.insights = array
            return
        }
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let list = try? c.decode([MemoryInsightItem].self, forKey: .insights) {
            self.insights = list
        } else if let list = try? c.decode([MemoryInsightItem].self, forKey: .data) {
            self.insights = list
        } else if let list = try? c.decode([MemoryInsightItem].self, forKey: .items) {
            self.insights = list
        } else {
            self.insights = []
        }
    }
}

/// 中途插话纠偏回执（POST /v1/runs/{run_id}/steer）
public struct RunSteerReceipt: Decodable, Equatable, Sendable {
    public let runID: String
    public let accepted: Bool

    private enum CodingKeys: String, CodingKey {
        case runID = "run_id"
        case accepted
    }

    public init(runID: String, accepted: Bool) {
        self.runID = runID
        self.accepted = accepted
    }
}
