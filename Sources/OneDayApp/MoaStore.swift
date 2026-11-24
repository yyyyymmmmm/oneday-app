import Foundation
import OneDayCore

/// MoA 操作注入（DESIGN §390）：视图层以 AppState
/// .performAdmin＋HermesClient MoA 两口组装；测试脚本注入
struct MoaOperations {
    var load: () async throws -> MoaConfig
    var save: (MoaConfig) async throws -> MoaConfig
}

/// 多模型会商页状态机（H9，DESIGN §390）：预设全图的真值
/// 在服务端 config 的 moa 节。写口是整图替换（图外名字
/// ＝删除），且服务端对半填槽位 422 硬拒——本店保存前
/// 先按同义规则本地预检（MoaConfig.allProblems），不让
/// 必拒的提交出门；写成功回执即服务端 normalize 真值，
/// 直接采纳并核对预设名集与生效预设同值
@MainActor
@Observable
final class MoaStore {
    enum State {
        case idle
        case loading
        case notLoggedIn
        case failed(String)
        case ready(MoaConfig)
    }

    private(set) var state: State = .idle
    private(set) var isWriting = false
    private(set) var note: String?
    private(set) var noteIsProblem = false

    var config: MoaConfig? {
        if case .ready(let config) = state { return config }
        return nil
    }

/// §416 新鲜度普查豁免：config 编辑面（ops 注入）——读待编辑现值、写后回读对账（判定表见 DESIGN §416）
    func load(ops: MoaOperations) async {
        if case .ready = state {
            // 已有真值时刷新不闪空
        } else {
            state = .loading
        }
        do {
            state = .ready(try await ops.load())
        } catch let error as HermesError {
            if case .sessionExpired = error {
                state = .notLoggedIn
            } else {
                state = .failed(error.userMessage)
            }
        } catch {
            state = .failed("读取会商配置失败，请稍后再试。")
        }
    }

    /// 保存整图：预检不过不发；采纳回执真值后核对名集
    func save(ops: MoaOperations, edited: MoaConfig) async {
        guard config != nil, !isWriting else { return }
        let problems = edited.allProblems()
        guard problems.isEmpty else {
            setNote(problems[0], problem: true)
            return
        }
        isWriting = true
        defer { isWriting = false }
        do {
            let normalized = try await ops.save(edited)
            state = .ready(normalized)
            if normalized.presetNames == edited.presetNames
                && normalized.effectivePresetName == edited.effectivePresetName {
                setNote("会商配置已保存", problem: false)
            } else {
                setNote("服务端受理了保存，但回读对不上，先按服务端原样显示。", problem: true)
            }
        } catch let error as HermesError {
            setNote(error.userMessage, problem: true)
        } catch {
            setNote("保存会商配置失败，请稍后再试。", problem: true)
        }
    }

    private func setNote(_ text: String, problem: Bool) {
        note = text
        noteIsProblem = problem
    }
}
