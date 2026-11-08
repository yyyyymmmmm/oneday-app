import Foundation
import OneDayCore

/// 演示模式的假客户端：实现 HermesClientProtocol，全部返回本地
/// 静态样本（经 JSONDecoder 走真实模型解码，不另造假模型），
/// 不发出任何网络请求。读数口径对齐 2026-11-08 线上实测样本：
/// 版本 0.23.0、网关 running、模型 deepseek-chat。
struct DemoHermesClient: HermesClientProtocol {
    func health(config: ServerConfig) async throws -> HealthResponse {
        decode(HealthResponse.self, #"{"status": "ok", "platform": "hermes-agent", "version": "0.23.0"}"#)
    }

    func login(config: ServerConfig, username: String, password: String) async throws {
        // 演示探活：恒成功，不发请求
    }

    func status(config: ServerConfig) async throws -> ServerStatus {
        decode(ServerStatus.self, """
        {
            "version": "0.23.0",
            "release_date": "2026.9.24",
            "gateway_running": true,
            "gateway_state": "running",
            "gateway_platforms": {
                "api_server": {"state": "connected", "error_message": null},
                "dashboard": {"state": "connected", "error_message": null}
            }
        }
        """)
    }

    func configSummary(config: ServerConfig) async throws -> ServerConfigSummary {
        decode(ServerConfigSummary.self, """
        {
            "model": "deepseek-chat",
            "providers": {"deepseek": {}},
            "toolsets": ["hermes-cli"]
        }
        """)
    }

    func models(config: ServerConfig, apiKey: String) async throws -> [String] {
        ["hermes-agent"]
    }

    /// 演示流式：把定稿回复逐字慢速产出，让截图环能截到
    /// 「已出半截字＋流式光标」的静止帧；总时长约 14 秒
    ///（首轮 5 秒版实测在 CI 里截到的是已完成帧，故放慢）。
    func chatStream(
        config: ServerConfig, apiKey: String, model: String, messages: [ChatMessage]
    ) -> AsyncThrowingStream<String, Error> {
        let reply = """
        好。那我先从定时任务模块动手：列表、新建、暂停、立即触发、运行记录，五条接口都是现成的，第一版只做查看和启停，编辑放第二轮。做完先出包给你验，通过了我再碰技能和会话。
        """
        return AsyncThrowingStream { continuation in
            let task = Task {
                let characters = Array(reply)
                var index = 0
                while index < characters.count {
                    if Task.isCancelled {
                        continuation.finish(throwing: HermesError.cancelled)
                        return
                    }
                    let next = min(index + 1, characters.count)
                    continuation.yield(String(characters[index..<next]))
                    index = next
                    try? await Task.sleep(for: .milliseconds(130))
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func clearCookies(config: ServerConfig) {
        // 演示模式没有 cookie 可清
    }

    private func decode<T: Decodable>(_ type: T.Type, _ json: String) -> T {
        // 样本与模型同仓维护，解码失败即开发期错误，直接暴露
        // swiftlint:disable:next force_try
        try! JSONDecoder().decode(type, from: Data(json.utf8))
    }
}
