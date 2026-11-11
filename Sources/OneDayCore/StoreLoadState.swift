import Foundation

/// Store 加载态与错误映射共用定义（§133，复杂度审
/// 计第 10 项）：KanbanStore 与 LedgerStore 原各有
/// 一套 LoadState 枚举（loading/未开通/未上线/
/// failed/ready）与各自的错误→态映射，同形两写、
/// 口径靠逐面适配维持。自本包起两 Store 共用本定
/// 义：态只此四档，错误映射只此两口——HermesError
/// 走 failure(for:)、OneDayBridgeError 走
/// from(bridgeError:…)。各面的专属语义（任务板
/// 404 判未开通、台账未上线态的探测旁证）仍留在各
/// Store 内，但只许产出本枚举的态，不许另立枚举。
public enum StoreLoadState: Equatable, Sendable {
    case loading
    /// 功能未开通／未上线（附说明文案；呈现面自备
    /// 固定文案时为 nil，如任务板未开通态）
    case unavailable(String?)
    case failed(String)
    case ready

    public var isReady: Bool { self == .ready }

    /// 未连接服务器（无配置）统一落态：两 Store 原
    /// 各自写同一句 failed，收成一处
    public static var notConnected: StoreLoadState {
        .failed(L10n.string("尚未连接服务器。"))
    }

    /// HermesError 映射（HermesClient 系 Store 共
    /// 用）：一律 failed＋服务端人话，不把状态码甩
    /// 给用户（HermesError.userMessage 口径）
    public static func failure(
        for error: HermesError
    ) -> StoreLoadState {
        .failed(error.userMessage)
    }

    /// OneDayBridgeError 映射（桥系 Store 共用）：
    /// 钥匙类（noKey/unauthorized）与桥未开通
    /// （bridgeMissing）归 unavailable——不是「读
    /// 失败」、是「这项功能还没法用」，说明文案由调
    /// 用面按错误提供（各面措辞不同、分类只此一
    /// 处）；记录已不在（recordGone）归 failed＋面
    /// 定回落文案；桥侧人话（failed）直传。
    public static func from(
        bridgeError error: OneDayBridgeError,
        unavailableMessage: (OneDayBridgeError) -> String,
        recordGoneMessage: String
    ) -> StoreLoadState {
        switch error {
        case .noKey, .unauthorized, .bridgeMissing:
            return .unavailable(unavailableMessage(error))
        case .recordGone:
            return .failed(recordGoneMessage)
        case .failed(let message):
            return .failed(message)
        }
    }
}
