import Foundation
import OneDayCore

/// 头像仓镜像同步（§253 身份包收敛）：头像仓是服务
/// 端单真值，本同步只做一件事——把仓的当前指针整份
/// 替换进本机缓存（IdentityAvatarCache），呈现只读
/// 缓存。旧双槽对账（AI 槽投影＋本地裁决）退役：
/// 谁最后写仓、仓的当前就是谁，末写胜在服务端天然
/// 成立、App 不再复刻裁决。
///
/// - 待推先行：§253 迁移留下的本机胜出值（avatar-
///   PushPending）先写穿上仓再谈同步；写穿失败直接
///   返回、缓存原样保留，不许让服务端旧指针把用户
///   胜出值冲掉。
/// - 失败口径：任何一步失败静默保留上次缓存——头
///   像是装饰面、不打扰用户；下个触发点再试（连
///   接成立/回前台/开抽屉等既有刷新触发）。
/// - 触发节流在 AppState.refreshAgentAvatarFromBridge
///   （30 秒，写穿链走 force 绕过）。
@MainActor
enum AgentAvatarSync {
    static func run(config: ServerConfig, store: AgentProfileStore) async {
        let client = IdentityBridgeClient()

        // 待推先行（§253 迁移一次性）：本机胜出值写穿
        if store.avatarPushPending, let pending = store.avatarCache {
            do {
                switch pending.selection {
                case .preset(let id):
                    try await client.addAvatarPreset(
                        config: config, presetID: id
                    )
                case .image(_):
                    guard let data = store.cachedAvatarImageData()
                    else { return }
                    try await client.addAvatarImage(
                        config: config, imageData: data
                    )
                }
                store.markAvatarPushed()
            } catch {
                return
            }
        }

        guard let state = try? await client.avatarState(config: config)
        else { return }
        guard let current = state.currentItem else {
            // 仓明确为空：清缓存，呈现回落缺省预置
            store.applyAvatarFromSync(cache: nil, imageData: nil)
            return
        }
        let updatedAt = state.currentUpdatedAtDate
        switch current.kind {
        case "preset":
            guard let presetID = current.presetId else { return }
            store.applyAvatarFromSync(
                cache: IdentityAvatarCache(
                    selection: .preset(
                        id: AgentAvatarPreset.resolve(id: presetID).id
                    ),
                    itemID: current.id,
                    serverUpdatedAt: updatedAt,
                    cachedAt: Date()
                ),
                imageData: nil
            )
        case "image":
            let cache = IdentityAvatarCache(
                selection: .image(itemID: current.id),
                itemID: current.id,
                serverUpdatedAt: updatedAt,
                cachedAt: Date()
            )
            if store.avatarCache?.itemID == current.id,
               store.hasCachedAvatarImage {
                // 同一条目：只刷时刻、不重下载图字节
                store.applyAvatarFromSync(cache: cache, imageData: nil)
                return
            }
            guard let data = try? await client.avatarImage(
                config: config, id: current.id
            ) else { return }
            store.applyAvatarFromSync(cache: cache, imageData: data)
        default:
            return
        }
    }
}
