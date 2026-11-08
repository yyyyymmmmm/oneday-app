import OneDayCore
import XCTest

/// 样本 JSON 均为 2026-11-08 对生产 Hermes v0.23.0 的 GET 实测
/// 结构（值已脱敏/改写，字段与类型逐项对齐，见施工记录）。
final class AdminModelsDecodeTests: XCTestCase {
    private let decoder = JSONDecoder()

    func testJSONValueRoundTrip() throws {
        let json = #"{"model": "deepseek-chat", "agent": {"max_turns": 90, "daybreak": true}, "toolsets": ["hermes-cli"], "nothing": null}"#
        let value = try decoder.decode(JSONValue.self, from: Data(json.utf8))
        guard case .object(let object) = value else {
            return XCTFail("顶层应为对象")
        }
        XCTAssertEqual(object["model"]?.stringValue, "deepseek-chat")
        XCTAssertEqual(object["agent"]?.displayString, "{…}")
        let encoded = try JSONEncoder().encode(value)
        let reparsed = try decoder.decode(JSONValue.self, from: encoded)
        XCTAssertEqual(reparsed, value)
    }

    func testMemoryStatus() throws {
        let json = """
        {"active": "", "providers": [{"name": "byterover",
         "description": "ByteRover", "available": false, "configured": true,
         "status": "unavailable", "setup": {"required_env": []}}],
         "builtin_files": {"memory": 12, "user": 3}}
        """
        let status = try decoder.decode(MemoryStatus.self, from: Data(json.utf8))
        XCTAssertEqual(status.active, "")
        XCTAssertEqual(status.providers.first?.name, "byterover")
        XCTAssertEqual(status.providers.first?.available, false)
        XCTAssertEqual(status.builtinFiles["memory"], 12)
    }

    func testMemoryProviderConfig() throws {
        let json = """
        {"name": "byterover", "label": "ByteRover", "fields": [
         {"key": "api_key", "label": "API Key", "kind": "secret",
          "description": "…", "placeholder": "", "required": true,
          "value": "", "is_set": false, "options": []}]}
        """
        let config = try decoder.decode(MemoryProviderConfig.self, from: Data(json.utf8))
        XCTAssertEqual(config.fields.first?.key, "api_key")
        XCTAssertEqual(config.fields.first?.isSet, false)
        XCTAssertEqual(config.fields.first?.value?.stringValue, "")
    }

    func testSkillsBareArray() throws {
        let json = """
        [{"name": "web-research", "description": "检索并汇总网页资料",
          "category": "research", "locked": false, "enabled": true,
          "usage": 12, "provenance": "builtin"},
         {"name": "daily-briefing", "description": "每日简报",
          "category": "productivity", "locked": true, "enabled": false,
          "usage": 0, "provenance": "local"}]
        """
        let skills = try decoder.decode([SkillItem].self, from: Data(json.utf8))
        XCTAssertEqual(skills.count, 2)
        XCTAssertTrue(skills[0].isEnabled)
        XCTAssertFalse(skills[1].isEnabled)
        XCTAssertEqual(skills[1].locked, true)
    }

    func testCronJobScheduleObjectAndDisplay() throws {
        let json = """
        {"id": "job-1", "name": "节点巡检", "prompt": "检查全部节点状态",
         "schedule": {"kind": "interval", "minutes": 360},
         "schedule_display": "每 6 小时", "enabled": true, "state": "scheduled",
         "deliver": "local", "model": null, "provider": null,
         "last_run_at": "2026-11-08T08:00:00Z", "next_run_at": "2026-11-08T14:00:00Z",
         "last_error": null}
        """
        let job = try decoder.decode(CronJob.self, from: Data(json.utf8))
        XCTAssertEqual(job.title, "节点巡检")
        XCTAssertEqual(job.scheduleText, "每 6 小时")
        XCTAssertTrue(job.enabled)

        let pausedJSON = #"{"id": "job-2", "prompt": "提醒", "schedule": "0 9 * * *", "paused": true}"#
        let paused = try decoder.decode(CronJob.self, from: Data(pausedJSON.utf8))
        XCTAssertFalse(paused.enabled)
        XCTAssertEqual(paused.scheduleText, "0 9 * * *")
        XCTAssertEqual(paused.title, "提醒")
    }

    func testSessionsPageAndTitleFallback() throws {
        let json = """
        {"sessions": [{"id": "sess-0001", "source": "dashboard",
          "session_key": "k", "display_name": null, "model": "deepseek-chat",
          "started_at": 1762000000, "ended_at": null, "end_reason": null,
          "message_count": 7, "tool_call_count": 1,
          "input_tokens": 1200, "output_tokens": 300}],
         "total": 1, "limit": 20, "offset": 0}
        """
        let page = try decoder.decode(SessionsPage.self, from: Data(json.utf8))
        XCTAssertEqual(page.total, 1)
        let session = try XCTUnwrap(page.sessions.first)
        XCTAssertEqual(session.title, "dashboard 会话")
        XCTAssertTrue(session.isActive)
        XCTAssertEqual(session.messageCount, 7)
        XCTAssertNotNil(session.startedDate)
    }

    func testCronRunsWrapper() throws {
        let json = """
        {"runs": [{"id": "run-1", "source": "cron", "started_at": 1762000000000,
          "ended_at": 1762000060000, "end_reason": "completed", "message_count": 3}]}
        """
        let runs = try decoder.decode(CronRunsResponse.self, from: Data(json.utf8))
        XCTAssertEqual(runs.runs.count, 1)
        XCTAssertEqual(runs.runs.first?.endReason, "completed")
        // 毫秒量级应被归一到秒
        XCTAssertEqual(
            runs.runs.first?.startedDate?.timeIntervalSince1970 ?? 0,
            1_762_000_000,
            accuracy: 1
        )
    }

    func testEnvVarsOrderingAndFields() throws {
        let json = """
        {"ZZZ_API_KEY": {"is_set": false, "redacted_value": null,
          "description": "未设", "url": null, "category": "provider",
          "is_password": true},
         "DEEPSEEK_API_KEY": {"is_set": true, "redacted_value": "sk-…51af",
          "description": "DeepSeek", "url": "https://api.deepseek.com",
          "category": "provider", "is_password": true}}
        """
        let vars = try decoder.decode(EnvVars.self, from: Data(json.utf8))
        XCTAssertEqual(vars.entries.count, 2)
        // 已设定的排前面
        XCTAssertEqual(vars.entries.first?.key, "DEEPSEEK_API_KEY")
        XCTAssertEqual(vars.entries.first?.redactedValue, "sk-…51af")
    }

    func testUsageAnalytics() throws {
        let json = """
        {"daily": [{"day": "2026-11-08", "input_tokens": 1000,
          "output_tokens": 250, "cache_read_tokens": 0, "reasoning_tokens": 0,
          "estimated_cost": 0.01, "actual_cost": 0.0, "sessions": 2,
          "api_calls": 5}],
         "totals": {"total_input": 5000, "total_output": 900,
          "total_sessions": 6, "total_api_calls": 20,
          "total_estimated_cost": 0.05},
         "period_days": 7}
        """
        let usage = try decoder.decode(UsageAnalytics.self, from: Data(json.utf8))
        XCTAssertEqual(usage.daily.first?.tokens, 1250)
        XCTAssertEqual(usage.totals.tokens, 5900)
        XCTAssertEqual(usage.totals.totalAPICalls, 20)
    }

    func testModelAnalytics() throws {
        let json = """
        {"models": [{"model": "deepseek-chat", "provider": "custom",
          "input_tokens": 5000, "output_tokens": 900, "estimated_cost": 0.05,
          "sessions": 6, "api_calls": 20}], "period_days": 7}
        """
        let analytics = try decoder.decode(ModelAnalytics.self, from: Data(json.utf8))
        XCTAssertEqual(analytics.models.first?.model, "deepseek-chat")
        XCTAssertEqual(analytics.models.first?.tokens, 5900)
    }

    func testLogsAndProfiles() throws {
        let logs = try decoder.decode(
            LogsResponse.self,
            from: Data(#"{"file": "agent.log", "lines": ["a", "b"]}"#.utf8)
        )
        XCTAssertEqual(logs.lines.count, 2)

        let profiles = try decoder.decode(
            ProfilesResponse.self,
            from: Data("""
            {"profiles": [{"name": "default", "is_default": true,
             "model": "deepseek-chat", "provider": "custom", "skill_count": 39,
             "gateway_running": true, "display_name": ""}]}
            """.utf8)
        )
        XCTAssertEqual(profiles.profiles.first?.skillCount, 39)

        let active = try decoder.decode(
            ActiveProfileResponse.self,
            from: Data(#"{"active": "default", "current": "default"}"#.utf8)
        )
        XCTAssertEqual(active.name, "default")
    }

    func testEgressAbnormalRule() throws {
        let disabled = try decoder.decode(
            EgressStatus.self,
            from: Data(#"{"text": "Egress proxy status\n\nEnabled: no\nListening: no\nProcess: (stopped)"}"#.utf8)
        )
        XCTAssertFalse(disabled.isAbnormal)

        let broken = try decoder.decode(
            EgressStatus.self,
            from: Data(#"{"text": "Enabled: yes\nListening: no\nProcess: (running)"}"#.utf8)
        )
        XCTAssertTrue(broken.isAbnormal)
    }

    func testSessionMessages() throws {
        let json = """
        {"session_id": "s1", "profile": "default", "messages": [
         {"id": 1, "role": "user", "content": "在吗", "timestamp": 1762000000},
         {"id": 2, "role": "assistant", "content": "在的", "timestamp": 1762000005}]}
        """
        let response = try decoder.decode(SessionMessagesResponse.self, from: Data(json.utf8))
        XCTAssertEqual(response.messages.count, 2)
        XCTAssertEqual(response.messages.last?.content, "在的")
    }
}
