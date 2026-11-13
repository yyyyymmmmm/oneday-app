import Foundation
import OneDayCore

/// 头像仓同步（P1 身份包）：把伴生 identity 桥头像仓
/// 的当前头像投影进 AgentProfileStore 的 AI 档槽位。
/// 触发与伴生探测同拍（连接成立/回前台/冷启恢复，
/// 见 OneDayApp 与 AppState.syncAgentAvatarFromBridge）。
///
/// 失败口径：一律静默保现状——仓不可达/回执异常时根
/// 本不动 AI 档（保持上次同步值），呈现由存储层裁决
/// 回落本机现行头像，绝不清空、绝不白屏。只有仓明
/// 确回「没有当前头像」才清槽。
@MainActor
enum AgentAvatarSync {
    static func run(config: ServerConfig, store: AgentProfileStore) async {
        let client = IdentityBridgeClient()
        guard let state = try? await client.avatarState(config: config)
        else { return }
        guard let current = state.currentItem else {
            store.clearAIAvatar()
            return
        }
        // 末写胜凭据：桥报的指针时刻（缺失回落条目写
        // 入时刻，再缺失按最早——不许拿假时刻裁决）
        let updatedAt = state.currentUpdatedAtDate ?? .distantPast
        switch current.kind {
        case "preset":
            guard let presetID = current.presetId else { return }
            store.applyAIAvatarPreset(
                id: presetID, itemID: current.id, updatedAt: updatedAt
            )
        case "image":
            // 同一条已同步且槽位在位：跳过重复下载
            // （图文件丢失时存储层解析自动回落，不白屏）；
            // 但指针时刻变了（同一条被重设为当前）只刷
            // 槽位时刻——末写胜比的是时刻，不刷就裁错
            if case .image(let syncedID, _) = store.aiAvatar,
               syncedID == current.id {
                store.refreshAIAvatarTimestamp(
                    itemID: current.id, updatedAt: updatedAt
                )
                return
            }
            guard let data = try? await client.avatarImage(
                config: config, id: current.id
            ) else { return }
            store.applyAIAvatarImage(
                data: data, itemID: current.id, updatedAt: updatedAt
            )
        default:
            return
        }
    }
}
