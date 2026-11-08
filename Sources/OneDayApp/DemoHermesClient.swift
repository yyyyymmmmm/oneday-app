import Foundation
import OneDayCore
#if canImport(UIKit)
import UIKit
#endif

/// 演示模式的假客户端：实现 HermesClientProtocol，全部返回本地
/// 静态样本（经 JSONDecoder 走真实模型解码，不另造假模型），
/// 不发出任何网络请求。读数口径对齐 2026-11-08 线上实测样本：
/// 版本 0.23.0、网关 running、模型 deepseek-chat；0.2.0 新增的
/// 管理面样本（技能/定时/会话/用量/日志等）按实测结构拟真，
/// 时间一律相对当前时刻生成，截图里不出现过期日期。
/// 写方法一律静默成功、不落任何状态（演示数据每次启动复位）。
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
            "config_version": 52,
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

    /// 演示上游候选（与网关别名 hermes-agent 分开：选择器里
    /// 只该出现这一组，含一个别名 deepseek-chat 供标注演示）
    func modelOptions(config: ServerConfig) async throws -> [String] {
        ["deepseek-flash", "deepseek-v4-pro", "deepseek-chat"]
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

    // MARK: - 记忆（样本结构对实测：active 空串＝内置当值）

    func memoryStatus(config: ServerConfig) async throws -> MemoryStatus {
        decode(MemoryStatus.self, """
        {
            "active": "",
            "providers": [
                {"name": "byterover", "description": "ByteRover — persistent knowledge tree with tiered retrieval via the brv CLI.",
                 "available": false, "configured": true, "status": "unavailable"},
                {"name": "local-notes", "description": "Local markdown notes as long-term memory.",
                 "available": true, "configured": false, "status": "not_configured"}
            ],
            "builtin_files": {"memory": 12, "user": 3}
        }
        """)
    }

    func setMemoryProvider(config: ServerConfig, name: String) async throws {}

    func memoryProviderConfig(
        config: ServerConfig, name: String
    ) async throws -> MemoryProviderConfig {
        decode(MemoryProviderConfig.self, """
        {
            "name": "\(name)",
            "label": "\(name)",
            "fields": [
                {"key": "api_key", "label": "API 密钥", "kind": "secret",
                 "description": "服务商发放的密钥，只存服务端环境变量。",
                 "placeholder": "", "required": true, "value": "",
                 "is_set": true, "options": []},
                {"key": "workspace", "label": "工作区", "kind": "string",
                 "description": "知识树所在的本地目录。",
                 "placeholder": "/opt/data/memory", "required": false,
                 "value": "/opt/data/memory", "is_set": true, "options": []}
            ]
        }
        """)
    }

    func updateMemoryProviderConfig(
        config: ServerConfig, name: String, values: [String: JSONValue]
    ) async throws {}

    func resetMemory(config: ServerConfig, target: String) async throws {}

    // MARK: - 技能

    func skills(config: ServerConfig) async throws -> [SkillItem] {
        decode([SkillItem].self, """
        [
            {"name": "web-research", "description": "检索网页并汇总成带出处的简报",
             "category": "research", "locked": false, "enabled": true,
             "usage": 42, "provenance": "builtin"},
            {"name": "daily-briefing", "description": "每天早上生成一页纸简报",
             "category": "productivity", "locked": false, "enabled": true,
             "usage": 18, "provenance": "builtin"},
            {"name": "code-review", "description": "按团队规范审查改动并给出结论",
             "category": "development", "locked": true, "enabled": true,
             "usage": 7, "provenance": "local"},
            {"name": "image-ocr", "description": "截图文字识别与结构化提取",
             "category": "media", "locked": false, "enabled": false,
             "usage": 0, "provenance": "hub"}
        ]
        """)
    }

    func skillContent(config: ServerConfig, name: String) async throws -> SkillContent {
        decode(SkillContent.self, """
        {
            "name": "\(name)",
            "path": "/opt/data/skills/\(name)/SKILL.md",
            "content": "# \(name)\\n\\n演示样本内容：技能说明正文（Markdown）。\\n\\n- 触发条件与输入约定\\n- 执行步骤与验收口径\\n- 失败时的兜底话术\\n"
        }
        """)
    }

    func updateSkillContent(config: ServerConfig, name: String, content: String) async throws {}
    func toggleSkill(config: ServerConfig, name: String, enabled: Bool) async throws {}
    func lockSkill(config: ServerConfig, name: String, locked: Bool) async throws {}

    // MARK: - 定时任务

    func cronJobs(config: ServerConfig) async throws -> [CronJob] {
        let now = Date()
        let iso = ISO8601DateFormatter()
        let lastRun = iso.string(from: now.addingTimeInterval(-2 * 3600))
        let nextRun = iso.string(from: now.addingTimeInterval(4 * 3600))
        let lastRun2 = iso.string(from: now.addingTimeInterval(-26 * 3600))
        return decode([CronJob].self, """
        [
            {"id": "job-patrol", "name": "节点巡检",
             "prompt": "检查全部代理节点的连通性与延迟，异常时汇总报告",
             "schedule": {"kind": "interval", "minutes": 360},
             "schedule_display": "每 6 小时", "enabled": true,
             "state": "scheduled", "deliver": "local", "model": null,
             "provider": null, "last_run_at": "\(lastRun)",
             "next_run_at": "\(nextRun)", "last_error": null},
            {"id": "job-cert", "name": "证书到期检查",
             "prompt": "检查全部站点证书剩余天数，少于 14 天时提醒",
             "schedule": "0 9 * * *", "schedule_display": "每天 09:00",
             "enabled": false, "state": "paused", "deliver": "local",
             "model": null, "provider": null, "last_run_at": "\(lastRun2)",
             "next_run_at": null, "last_error": null}
        ]
        """)
    }

    func createCronJob(
        config: ServerConfig, name: String?, prompt: String, schedule: String, deliver: String?
    ) async throws -> CronJob {
        decode(CronJob.self, """
        {"id": "job-new", "name": \(name.map { "\"\($0)\"" } ?? "null"),
         "prompt": "\(prompt)", "schedule": "\(schedule)",
         "schedule_display": "\(schedule)", "enabled": true,
         "state": "scheduled", "deliver": "local"}
        """)
    }

    func updateCronJob(
        config: ServerConfig, id: String, updates: [String: JSONValue]
    ) async throws {}

    func deleteCronJob(config: ServerConfig, id: String) async throws {}
    func pauseCronJob(config: ServerConfig, id: String) async throws {}
    func resumeCronJob(config: ServerConfig, id: String) async throws {}
    func triggerCronJob(config: ServerConfig, id: String) async throws {}

    func cronRuns(config: ServerConfig, id: String, limit: Int) async throws -> [ServerSession] {
        let now = Date().timeIntervalSince1970
        return decode(CronRunsResponse.self, """
        {"runs": [
            {"id": "run-1", "source": "cron", "started_at": \(now - 2 * 3600),
             "ended_at": \(now - 2 * 3600 + 95), "end_reason": "completed",
             "message_count": 6, "tool_call_count": 3},
            {"id": "run-2", "source": "cron", "started_at": \(now - 8 * 3600),
             "ended_at": \(now - 8 * 3600 + 61), "end_reason": "completed",
             "message_count": 5, "tool_call_count": 2}
        ]}
        """).runs
    }

    // MARK: - 服务端会话

    func serverSessions(config: ServerConfig, limit: Int) async throws -> SessionsPage {
        let now = Date().timeIntervalSince1970
        return decode(SessionsPage.self, """
        {"sessions": [
            {"id": "sess-live", "source": "dashboard", "display_name": "帮我看看服务器状态",
             "model": "deepseek-chat", "profile": "default",
             "started_at": \(now - 25 * 60), "ended_at": null,
             "message_count": 9, "tool_call_count": 2,
             "input_tokens": 18200, "output_tokens": 2400},
            {"id": "sess-cron-1", "source": "cron", "display_name": "节点巡检",
             "model": "deepseek-chat", "profile": "default",
             "started_at": \(now - 2 * 3600), "ended_at": \(now - 2 * 3600 + 95),
             "end_reason": "completed", "message_count": 6, "tool_call_count": 3,
             "input_tokens": 5200, "output_tokens": 640},
            {"id": "sess-old", "source": "api_server", "display_name": null,
             "model": "deepseek-chat", "profile": "default",
             "started_at": \(now - 30 * 3600), "ended_at": \(now - 30 * 3600 + 240),
             "end_reason": "completed", "message_count": 4, "tool_call_count": 0,
             "input_tokens": 2100, "output_tokens": 480}
        ], "total": 3, "limit": \(limit), "offset": 0}
        """)
    }

    func serverSession(config: ServerConfig, id: String) async throws -> ServerSession {
        let page = try await serverSessions(config: config, limit: 20)
        return page.sessions.first { $0.id == id } ?? page.sessions[0]
    }

    func sessionMessages(config: ServerConfig, id: String) async throws -> [SessionMessage] {
        let now = Date().timeIntervalSince1970
        return decode(SessionMessagesResponse.self, """
        {"session_id": "\(id)", "profile": "default", "messages": [
            {"id": 1, "role": "user", "content": "帮我看看服务器现在的状态。",
             "timestamp": \(now - 1500)},
            {"id": 2, "role": "assistant",
             "content": "刚查过，一切正常：网关运行中，API 服务已连接，健康检查返回 ok。",
             "timestamp": \(now - 1440)}
        ]}
        """).messages
    }

    func deleteServerSession(config: ServerConfig, id: String) async throws {}
    func bulkDeleteServerSessions(config: ServerConfig, ids: [String]) async throws {}
    func emptySessionCount(config: ServerConfig) async throws -> Int { 2 }
    func deleteEmptySessions(config: ServerConfig) async throws {}

    // MARK: - 档案

    func profiles(config: ServerConfig) async throws -> [ProfileItem] {
        decode(ProfilesResponse.self, """
        {"profiles": [
            {"name": "default", "is_default": true, "model": "deepseek-chat",
             "provider": "custom", "skill_count": 39, "gateway_running": true,
             "display_name": ""},
            {"name": "work", "is_default": false, "model": "deepseek-chat",
             "provider": "custom", "skill_count": 12, "gateway_running": false,
             "display_name": ""}
        ]}
        """).profiles
    }

    func activeProfileName(config: ServerConfig) async throws -> String? { "default" }

    func setActiveProfile(config: ServerConfig, name: String) async throws {}

    // MARK: - 配置与密钥

    func rawConfig(config: ServerConfig) async throws -> [String: JSONValue] {
        decode([String: JSONValue].self, """
        {
            "model": "deepseek-chat",
            "providers": {
                "deepseek": {"base_url": "https://api.deepseek.com/v1"}
            },
            "toolsets": ["hermes-cli"]
        }
        """)
    }

    func updateConfig(config: ServerConfig, newConfig: [String: JSONValue]) async throws {}

    func envVars(config: ServerConfig) async throws -> [EnvVarEntry] {
        decode(EnvVars.self, """
        {
            "DEEPSEEK_API_KEY": {"is_set": true, "redacted_value": "sk-…51af",
                "description": "DeepSeek 平台密钥，后端模型调用使用。",
                "url": "https://platform.deepseek.com", "category": "provider",
                "is_password": true},
            "API_SERVER_KEY": {"is_set": true, "redacted_value": "od-…9c2e",
                "description": "OneDay 等客户端连接 API 服务的密钥。",
                "url": null, "category": "server", "is_password": true},
            "OPENROUTER_API_KEY": {"is_set": false, "redacted_value": null,
                "description": "OpenRouter 聚合网关密钥（未配置）。",
                "url": "https://openrouter.ai", "category": "provider",
                "is_password": true}
        }
        """).entries
    }

    func setEnvVar(config: ServerConfig, key: String, value: String) async throws {}
    func deleteEnvVar(config: ServerConfig, key: String) async throws {}
    func revealEnvVar(config: ServerConfig, key: String) async throws -> String {
        "demo-secret-value"
    }

    // MARK: - 用量与日志

    func usageAnalytics(config: ServerConfig, days: Int) async throws -> UsageAnalytics {
        // 七日样本：今天有真实量级，前几日递减，趋势条用得上
        let dayNames = (0..<7).map { offset -> String in
            let date = Calendar.current.date(
                byAdding: .day, value: -offset, to: Date()
            ) ?? Date()
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            return formatter.string(from: date)
        }
        let inputs = [18200, 12400, 15800, 8600, 19300, 10200, 13400]
        let outputs = [2400, 1700, 2100, 1100, 2600, 1400, 1850]
        let daily = zip(dayNames, zip(inputs, outputs)).map { day, pair in
            """
            {"day": "\(day)", "input_tokens": \(pair.0), "output_tokens": \(pair.1),
             "sessions": 3, "api_calls": 9, "estimated_cost": 0.02}
            """
        }.joined(separator: ",")
        return decode(UsageAnalytics.self, """
        {"daily": [\(daily)],
         "totals": {"total_input": 97900, "total_output": 13150,
          "total_sessions": 21, "total_api_calls": 63,
          "total_estimated_cost": 0.14},
         "period_days": 7}
        """)
    }

    func modelAnalytics(config: ServerConfig, days: Int) async throws -> ModelAnalytics {
        decode(ModelAnalytics.self, """
        {"models": [
            {"model": "deepseek-chat", "provider": "custom",
             "input_tokens": 81200, "output_tokens": 10900,
             "estimated_cost": 0.11, "sessions": 17, "api_calls": 52},
            {"model": "deepseek-reasoner", "provider": "custom",
             "input_tokens": 16700, "output_tokens": 2250,
             "estimated_cost": 0.03, "sessions": 4, "api_calls": 11}
        ], "period_days": 7}
        """)
    }

    func logs(
        config: ServerConfig, level: String?, search: String?, lines: Int
    ) async throws -> LogsResponse {
        let stamp = ISO8601DateFormatter().string(from: Date())
        var entries = [
            "\(stamp) INFO gateway: health check ok",
            "\(stamp) INFO api_server: request completed in 212ms",
            "\(stamp) WARNING cron: job job-cert is paused, skipping",
        ]
        if level == "error" {
            entries = [
                "\(stamp) ERROR gateway: platform telegram poll timeout, will retry",
            ]
        }
        let joined = entries.map { "\"\($0)\"" }.joined(separator: ",")
        return decode(LogsResponse.self, """
        {"file": "agent.log", "lines": [\(joined)]}
        """)
    }

    func egressStatus(config: ServerConfig) async throws -> EgressStatus {
        decode(EgressStatus.self, """
        {"text": "Egress proxy status\\n\\nEnabled: no\\nBinary: (missing)\\nListening: no\\nProcess: (stopped)"}
        """)
    }

    // MARK: - 网关动作

    func gatewayRestart(config: ServerConfig) async throws {}
    func gatewayStart(config: ServerConfig) async throws {}
    func gatewayStop(config: ServerConfig) async throws {}

    // MARK: - 工作区文件与系统（0.2.1 样本，结构对实查回执）

    func files(config: ServerConfig, path: String?) async throws -> FilesListing {
        let root = "/opt/data"
        switch path ?? root {
        case "/opt/data/cache/images":
            return decode(FilesListing.self, """
            {"path": "/opt/data/cache/images", "parent": "/opt/data/cache",
             "root": "/opt/data", "locked_root": "/opt/data",
             "can_change_path": false,
             "entries": [
                {"name": "生成图-节点拓扑.png", "path": "/opt/data/cache/images/生成图-节点拓扑.png",
                 "is_directory": false, "size": 48213, "mtime": 1794141188.0,
                 "mime_type": "image/png"},
                {"name": "巡检截图.png", "path": "/opt/data/cache/images/巡检截图.png",
                 "is_directory": false, "size": 35110, "mtime": 1794054788.0,
                 "mime_type": "image/png"}
             ]}
            """)
        case "/opt/data/cache/videos":
            return decode(FilesListing.self, """
            {"path": "/opt/data/cache/videos", "parent": "/opt/data/cache",
             "root": "/opt/data", "locked_root": "/opt/data",
             "can_change_path": false,
             "entries": [
                {"name": "演示录屏.mp4", "path": "/opt/data/cache/videos/演示录屏.mp4",
                 "is_directory": false, "size": 5242880, "mtime": 1793968388.0,
                 "mime_type": "video/mp4"}
             ]}
            """)
        case "/opt/data/cache/audio":
            return decode(FilesListing.self, """
            {"path": "/opt/data/cache/audio", "parent": "/opt/data/cache",
             "root": "/opt/data", "locked_root": "/opt/data",
             "can_change_path": false,
             "entries": [
                {"name": "语音备忘.m4a", "path": "/opt/data/cache/audio/语音备忘.m4a",
                 "is_directory": false, "size": 96256, "mtime": 1793881988.0,
                 "mime_type": "audio/mp4"}
             ]}
            """)
        case "/opt/data/cache/documents":
            return decode(FilesListing.self, """
            {"path": "/opt/data/cache/documents", "parent": "/opt/data/cache",
             "root": "/opt/data", "locked_root": "/opt/data",
             "can_change_path": false,
             "entries": [
                {"name": "网络巡检周报.md", "path": "/opt/data/cache/documents/网络巡检周报.md",
                 "is_directory": false, "size": 3110, "mtime": 1794054788.0,
                 "mime_type": "text/markdown"}
             ]}
            """)
        case "/opt/data/cache/screenshots":
            return decode(FilesListing.self, """
            {"path": "/opt/data/cache/screenshots", "parent": "/opt/data/cache",
             "root": "/opt/data", "locked_root": "/opt/data",
             "can_change_path": false,
             "entries": [
                {"name": "官网首页截图.png", "path": "/opt/data/cache/screenshots/官网首页截图.png",
                 "is_directory": false, "size": 66410, "mtime": 1793881988.0,
                 "mime_type": "image/png"}
             ]}
            """)
        case "/opt/data/cron/output":
            return decode(FilesListing.self, """
            {"path": "/opt/data/cron/output", "parent": "/opt/data/cron",
             "root": "/opt/data", "locked_root": "/opt/data",
             "can_change_path": false,
             "entries": [
                {"name": "每日简报-1108.txt", "path": "/opt/data/cron/output/每日简报-1108.txt",
                 "is_directory": false, "size": 1890, "mtime": 1793968388.0,
                 "mime_type": "text/plain"}
             ]}
            """)
        case "/opt/data/image_cache":
            return decode(FilesListing.self, """
            {"path": "/opt/data/image_cache", "parent": "/opt/data",
             "root": "/opt/data", "locked_root": "/opt/data",
             "can_change_path": false,
             "entries": [
                {"name": "参考图-架构.png", "path": "/opt/data/image_cache/参考图-架构.png",
                 "is_directory": false, "size": 51200, "mtime": 1793795588.0,
                 "mime_type": "image/png"}
             ]}
            """)
        case "/opt/data/images":
            return decode(FilesListing.self, """
            {"path": "/opt/data/images", "parent": "/opt/data",
             "root": "/opt/data", "locked_root": "/opt/data",
             "can_change_path": false,
             "entries": [
                {"name": "nodes-status.png", "path": "/opt/data/images/nodes-status.png",
                 "is_directory": false, "size": 48213, "mtime": 1794141188.0,
                 "mime_type": "image/png"},
                {"name": "chart-weekly.png", "path": "/opt/data/images/chart-weekly.png",
                 "is_directory": false, "size": 35110, "mtime": 1794054788.0,
                 "mime_type": "image/png"},
                {"name": "screen-record.mp4", "path": "/opt/data/images/screen-record.mp4",
                 "is_directory": false, "size": 5242880, "mtime": 1793968388.0,
                 "mime_type": "video/mp4"},
                {"name": "voice-note.m4a", "path": "/opt/data/images/voice-note.m4a",
                 "is_directory": false, "size": 96256, "mtime": 1793881988.0,
                 "mime_type": "audio/mp4"}
             ]}
            """)
        case "/opt/data/reports":
            return decode(FilesListing.self, """
            {"path": "/opt/data/reports", "parent": "/opt/data",
             "root": "/opt/data", "locked_root": "/opt/data",
             "can_change_path": false,
             "entries": [
                {"name": "weekly.md", "path": "/opt/data/reports/weekly.md",
                 "is_directory": false, "size": 3110, "mtime": 1794054788.0,
                 "mime_type": "text/markdown"}
             ]}
            """)
        case "/opt/data/cache/scratch", "/opt/data/audio_cache":
            let emptyPath = path ?? root
            return decode(FilesListing.self, """
            {"path": "\(emptyPath)", "parent": "/opt/data",
             "root": "/opt/data", "locked_root": "/opt/data",
             "can_change_path": false, "entries": []}
            """)
        case "/opt/data":
            return decode(FilesListing.self, """
            {"path": "/opt/data", "parent": null,
             "root": "/opt/data", "locked_root": "/opt/data",
             "can_change_path": false,
             "entries": [
                {"name": "images", "path": "/opt/data/images",
                 "is_directory": true, "size": null, "mtime": 1794141188.0,
                 "mime_type": null},
                {"name": "reports", "path": "/opt/data/reports",
                 "is_directory": true, "size": null, "mtime": 1794054788.0,
                 "mime_type": null},
                {"name": "交付说明.md", "path": "/opt/data/交付说明.md",
                 "is_directory": false, "size": 2048, "mtime": 1793711588.0,
                 "mime_type": "text/markdown"}
             ]}
            """)
        default:
            let unknownPath = path ?? root
            return decode(FilesListing.self, """
            {"path": "\(unknownPath)", "parent": "/opt/data",
             "root": "/opt/data", "locked_root": "/opt/data",
             "can_change_path": false, "entries": []}
            """)
        }
    }

    func deleteFile(config: ServerConfig, path: String, recursive: Bool) async throws {}

    func fileData(config: ServerConfig, path: String) async throws -> Data {
        if path.hasSuffix(".png") {
            return Self.placeholderPNG(label: (path as NSString).lastPathComponent)
        }
        if path.hasSuffix(".md") {
            return Data("# 演示文件\n\n这是演示模式的文本预览样本。\n".utf8)
        }
        if path.hasSuffix(".txt") {
            return Data("每日简报（演示）\n节点 41 个全部在线，电费余额读数正常。\n".utf8)
        }
        if path.hasSuffix(".json") {
            return Data("{\"demo\": true, \"count\": 3}\n".utf8)
        }
        if path.hasSuffix(".log") {
            return Data("INFO demo log line\n".utf8)
        }
        return Data()
    }

    /// 演示缩略图：纯色块＋文件名（UIKit 渲染，不连网）
    private static func placeholderPNG(label: String) -> Data {
        #if canImport(UIKit)
        let size = CGSize(width: 300, height: 300)
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { context in
            UIColor(red: 0.85, green: 0.91, blue: 0.98, alpha: 1).setFill()
            context.fill(CGRect(origin: .zero, size: size))
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 20, weight: .medium),
                .foregroundColor: UIColor(red: 0.1, green: 0.25, blue: 0.55, alpha: 1),
            ]
            let text = label as NSString
            let textSize = text.size(withAttributes: attributes)
            text.draw(
                at: CGPoint(
                    x: (size.width - textSize.width) / 2,
                    y: (size.height - textSize.height) / 2
                ),
                withAttributes: attributes
            )
        }
        return image.pngData() ?? Data()
        #else
        return Data()
        #endif
    }

    func systemStats(config: ServerConfig) async throws -> SystemStats {
        decode(SystemStats.self, """
        {"os": "Linux", "os_release": "3.10.0-1160.el7.x86_64",
         "platform": "Linux-x86_64", "arch": "x86_64",
         "hostname": "demo-host", "python_version": "3.14.9",
         "hermes_version": "0.23.0", "cpu_count": 4,
         "cpu_percent": 2.5, "load_avg": [0.07, 0.09, 0.12],
         "uptime_seconds": 2358766,
         "memory": {"total": 8101019648, "available": 4321755136,
                    "used": 3779264512, "percent": 46.7},
         "disk": {"total": 126691618816, "used": 54956441600,
                  "free": 66478796800, "percent": 45.3},
         "process": {"pid": 155, "rss": 301142016,
                     "create_time": 1794142047, "num_threads": 11}}
        """)
    }

    private func decode<T: Decodable>(_ type: T.Type, _ json: String) -> T {
        // 样本与模型同仓维护，解码失败即开发期错误，直接暴露
        // swiftlint:disable:next force_try
        try! JSONDecoder().decode(type, from: Data(json.utf8))
    }
}
