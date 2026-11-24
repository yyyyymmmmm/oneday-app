import Foundation

/// 主线候选选定（§220 既定序的共用核，根治版包 1
/// DESIGN §330 提取）：标题全等匹配（不做包含/模糊）、
/// 排除集先过滤；多条时 oneday-main- 前缀池优先、池
/// 内最近活动优先、活动同值 id 升序——判定确定性可
/// 复现。收养（§220 错误触发）与认领（§330 主动发
/// 现）共用本核，不许两处各抄一份选法。
public enum MainlineCandidateSelection {
    public static func matches(
        title: String,
        candidates: [MainlineAdoptionCandidate],
        excludedIDs: Set<String> = []
    ) -> [MainlineAdoptionCandidate] {
        candidates.filter {
            $0.title == title && !excludedIDs.contains($0.id)
        }
    }

    /// 已匹配集里选定一条：恰一条即它；多条按前缀
    /// 池＋最近活动＋id 升序定序取首
    public static func pick(
        from matches: [MainlineAdoptionCandidate]
    ) -> MainlineAdoptionCandidate? {
        guard let first = matches.first else { return nil }
        guard matches.count > 1 else { return first }
        let prefixed = matches.filter {
            $0.id.hasPrefix("oneday-main-")
        }
        let pool = prefixed.isEmpty ? matches : prefixed
        return pool.sorted { lhs, rhs in
            let l = lhs.lastActivityAt ?? -.infinity
            let r = rhs.lastActivityAt ?? -.infinity
            if l != r { return l > r }
            return lhs.id < rhs.id
        }.first ?? pool[0]
    }
}

/// 主线主动认领判定（根治版包 1，DESIGN §330）：登
/// 录后向服务端目录「发现」既有主线——把 §220 收养
/// 的判定从错误触发提升为主动判定。候选＝标题全等
/// 「主线」的会话（主线裁定：不加第二判据、不做前
/// 缀池兜底认领，误认领面不扩大——前缀只在多条同
/// 标题时作取舍序、不作候选来源）；排除集（本地删
/// 除账＋围栏态）命中的候选先过滤，已删会话不许被
/// 认领复活。零候选＝服务端确无主线，调用方才许走
/// 冷启动；归档候选照常认领（isArchived 随判定交
/// 出：主线裁定认领保持归档、解档归用户打开动作，
/// 不在认领时发生）。
public enum MainlineClaimDirective: Sendable, Equatable {
    /// 名单里无（未被排除的）同标题会话
    case noCandidate
    /// 恰一条同标题会话：认领它
    case claim(sessionID: String, isArchived: Bool)
    /// 多条同标题会话：已按既定序选定（matchCount
    /// 为过滤后的匹配数，供调用方留痕）
    case claimAmongMultiple(
        sessionID: String, matchCount: Int, isArchived: Bool
    )

    public static func directive(
        title: String,
        candidates: [MainlineAdoptionCandidate],
        excludedIDs: Set<String>
    ) -> MainlineClaimDirective {
        let matches = MainlineCandidateSelection.matches(
            title: title, candidates: candidates,
            excludedIDs: excludedIDs
        )
        guard let pick = MainlineCandidateSelection.pick(
            from: matches
        ) else { return .noCandidate }
        if matches.count == 1 {
            return .claim(
                sessionID: pick.id, isArchived: pick.isArchived
            )
        }
        return .claimAmongMultiple(
            sessionID: pick.id, matchCount: matches.count,
            isArchived: pick.isArchived
        )
    }
}
