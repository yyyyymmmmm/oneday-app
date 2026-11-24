import OneDayCore
import XCTest

/// 连接自检契约钉测（DESIGN §357）：能力发现/深度健
/// 康/状态扩键/待批聚合四份回文按官方源码与部署包
/// 补丁的字面形态固化；结论合成（SelfCheckReport-
/// Builder）逐景钉——全绿、单项失败隔离、401、未配
/// 密钥、降级、探针分流、未探不假绿
final class CapabilitySelfCheckTests: XCTestCase {

    // MARK: - 样本（源码字面形态）

    private let capabilitiesJSON = """
    {
      "object": "hermes.api_server.capabilities",
      "platform": "hermes-agent",
      "model": "hermes-agent",
      "auth": {"type": "bearer", "required": true},
      "runtime": {
        "mode": "server_agent", "tool_execution": "server",
        "split_runtime": false, "description": "server-side agent"
      },
      "features": {
        "chat_completions": true, "chat_completions_streaming": true,
        "responses_api": true, "responses_streaming": true,
        "run_submission": true,
        "runs_idempotency": {
          "supported": true, "durable": true,
          "retention_seconds": 86400
        },
        "run_status": true, "run_events_sse": true,
        "run_stop": true, "run_steer": true,
        "run_approval_response": true,
        "tool_progress_events": true, "approval_events": true,
        "session_resources": true, "model_options": true,
        "session_chat": true, "session_chat_streaming": true,
        "session_fork": true, "session_model_lock": true,
        "reasoning_streaming": true,
        "admin_config_rw": false, "jobs_admin": false,
        "memory_write_api": false, "skills_api": true,
        "audio_api": false, "realtime_voice": false,
        "session_continuity_header": "X-Hermes-Session-Id",
        "session_key_header": "X-Hermes-Session-Key",
        "run_unknown_resolution": true, "cors": false
      },
      "endpoints": {
        "health": {"method": "GET", "path": "/health"},
        "health_detailed": {"method": "GET", "path": "/health/detailed"},
        "models": {"method": "GET", "path": "/v1/models"},
        "model_options": {"method": "GET", "path": "/api/model/options"},
        "chat_completions": {"method": "POST", "path": "/v1/chat/completions"},
        "runs": {"method": "POST", "path": "/v1/runs"},
        "sessions": {"method": "GET", "path": "/api/sessions"}
      }
    }
    """

    private let detailedJSON = """
    {
      "status": "ok",
      "readiness": {
        "status": "ok",
        "checks": {
          "state_db": {"status": "ok"},
          "session_store": {"status": "ok"},
          "config": {"status": "ok"},
          "model": {"status": "ok"},
          "disk": {
            "status": "ok", "used_percent": 62.4,
            "free_bytes": 123456789
          },
          "gateway": {
            "status": "ok", "state": "running",
            "connected_platforms": 1, "platforms": 1
          },
          "background_queues": {
            "status": "ok", "active_api_runs": 2,
            "process_completions": 0, "active_delegations": 0
          }
        }
      },
      "platform": "hermes-agent", "version": "0.23.0",
      "gateway_state": "running",
      "platforms": {
        "api_server": {"state": "connected", "metrics": {}}
      },
      "metrics_today": {
        "day": "2026-11-22", "requests": 10, "messages": 8,
        "tokens": 1234, "latency_p95_ms": 950.5
      },
      "last_heartbeat": "2026-11-22T09:00:00Z",
      "active_agents": 1, "gateway_busy": true,
      "gateway_drainable": true, "exit_reason": null,
      "updated_at": "2026-11-22T09:00:00Z", "pid": 4242
    }
    """

    private let statusJSON = """
    {
      "version": "0.23.0", "release_date": "2026.9.24",
      "config_version": 52, "latest_config_version": 52,
      "can_update_hermes": false,
      "gateway_running": true, "gateway_state": "running",
      "gateway_platforms": {
        "api_server": {"state": "connected"}
      },
      "overall": "ok",
      "components": {
        "gateway": {"status": "ok", "state": "running"},
        "dashboard": {
          "status": "ok", "recent_unhandled_errors": 0,
          "last_error_at": null, "selftest": "passing"
        },
        "storage": {"status": "ok"},
        "platforms": {"status": "ok", "configured": 1, "connected": 1}
      },
      "disk": {
        "pressure": "ok", "total_mb": 102400,
        "free_mb": 40000, "used_percent": 60.9
      },
      "memory": {
        "pressure": "ok", "gateway_rss_mb": 512.5,
        "system_total_mb": 8192, "system_available_mb": 4096
      }
    }
    """

    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder().decode(type, from: Data(json.utf8))
    }

    private func healthOK() throws -> HealthResponse {
        try decode(
            HealthResponse.self,
            #"{"status": "ok", "platform": "hermes-agent", "version": "0.23.0"}"#
        )
    }

    private func grantsEmpty() throws -> GrantsListResponse {
        try decode(GrantsListResponse.self, """
        {
          "object": "hermes.grants", "grants": [],
          "exec_count": 0, "writegate_count": 0,
          "partial": false, "source_errors": [],
          "projection_degraded": false
        }
        """)
    }

    private func approvals(pending: Int, degraded: Bool = false) throws -> ApprovalsListResponse {
        try decode(ApprovalsListResponse.self, """
        {
          "object": "hermes.approvals", "approvals": [],
          "pending_count": \(pending),
          "ledger_degraded": \(degraded)
        }
        """)
    }

    private func row(
        _ report: SelfCheckReport, _ id: String
    ) -> SelfCheckRow {
        guard let found = report.rows.first(where: { $0.id == id })
        else {
            XCTFail("缺行 \(id)")
            return SelfCheckRow(id: id, title: id, status: .unprobed)
        }
        return found
    }

    // MARK: - 回文解码

    func testCapabilitiesDecodesHeterogeneousFeatures() throws {
        let response = try decode(
            CapabilitiesResponse.self, capabilitiesJSON
        )
        XCTAssertEqual(response.object, "hermes.api_server.capabilities")
        XCTAssertEqual(response.platform, "hermes-agent")
        XCTAssertEqual(response.model, "hermes-agent")
        XCTAssertEqual(response.authRequired, true)
        XCTAssertEqual(response.runtimeMode, "server_agent")
        XCTAssertEqual(response.featureFlag("skills_api"), true)
        XCTAssertEqual(response.featureFlag("audio_api"), false)
        // 字符串型旗标（头名）不冒充布尔
        XCTAssertNil(response.featureFlag("session_continuity_header"))
        XCTAssertNil(response.featureFlag("no_such_flag"))
        XCTAssertEqual(response.runsIdempotencySupported, true)
        XCTAssertEqual(response.missingKeyEndpoints, [])
        XCTAssertEqual(response.endpoints["runs"]?.method, "POST")
    }

    func testCapabilitiesMissingEndpointIsDetected() throws {
        let json = capabilitiesJSON.replacingOccurrences(
            of: #""runs": {"method": "POST", "path": "/v1/runs"},"#,
            with: ""
        )
        let response = try decode(CapabilitiesResponse.self, json)
        XCTAssertEqual(response.missingKeyEndpoints, ["runs"])
    }

    func testHealthDetailedDecodesReadinessChecks() throws {
        let response = try decode(
            HealthDetailedResponse.self, detailedJSON
        )
        XCTAssertEqual(response.status, "ok")
        XCTAssertEqual(response.readinessStatus, "ok")
        XCTAssertEqual(response.gatewayState, "running")
        XCTAssertEqual(response.apiServerState, "connected")
        XCTAssertEqual(response.checks["disk"]?.usedPercent, 62.4)
        XCTAssertEqual(response.checks["disk"]?.freeBytes, 123456789)
        XCTAssertEqual(
            response.checks["background_queues"]?.activeAPIRuns, 2
        )
        XCTAssertEqual(
            response.checks["gateway"]?.connectedPlatforms, 1
        )
        XCTAssertEqual(response.metricsToday?.tokens, 1234)
        XCTAssertEqual(response.metricsToday?.latencyP95Ms, 950.5)
        XCTAssertEqual(response.activeAgents, 1)
        XCTAssertEqual(response.gatewayBusy, true)
    }

    func testStatusDecodesSelfCheckExpansion() throws {
        let status = try decode(ServerStatus.self, statusJSON)
        XCTAssertEqual(status.version, "0.23.0")
        XCTAssertEqual(status.configVersion, 52)
        XCTAssertEqual(status.latestConfigVersion, 52)
        XCTAssertEqual(status.canUpdateHermes, false)
        XCTAssertEqual(status.overall, "ok")
        XCTAssertEqual(status.components?.gateway?.state, "running")
        XCTAssertEqual(
            status.components?.dashboard?.recentUnhandledErrors, 0
        )
        XCTAssertEqual(status.components?.platforms?.connected, 1)
        XCTAssertEqual(status.components?.platforms?.configured, 1)
        XCTAssertEqual(status.disk?.usedPercent, 60.9)
        XCTAssertEqual(status.memory?.pressure, "ok")
    }

    func testApprovalsDecodesCounts() throws {
        let response = try approvals(pending: 3, degraded: true)
        XCTAssertEqual(response.pendingCount, 3)
        XCTAssertEqual(response.ledgerDegraded, true)
    }

    // MARK: - 结论合成

    func testBuilderAllGreen() throws {
        let report = SelfCheckReportBuilder.build(
            health: .success(try healthOK()),
            capabilities: .success(
                try decode(CapabilitiesResponse.self, capabilitiesJSON)
            ),
            detailed: .success(
                try decode(HealthDetailedResponse.self, detailedJSON)
            ),
            status: .success(try decode(ServerStatus.self, statusJSON)),
            approvals: .success(try approvals(pending: 0)),
            grants: .success(try grantsEmpty()),
            enrollmentProbe: .success(
                RouteProbeResult(status: 405, errorCode: nil)
            ),
            reactionsProbe: .success(
                RouteProbeResult(status: 405, errorCode: nil)
            ),
            checkedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        XCTAssertEqual(report.groups.map(\.id), [
            "connection", "service", "capabilities", "extensions",
        ])
        XCTAssertEqual(report.warnCount, 0)
        XCTAssertEqual(report.overallWord, "正常")

        let reachable = row(report, "reachable")
        XCTAssertEqual(reachable.status, .ok)
        XCTAssertEqual(reachable.value, "Hermes 0.23.0")
        XCTAssertEqual(row(report, "credential").status, .ok)
        XCTAssertEqual(row(report, "gateway").status, .ok)
        XCTAssertEqual(row(report, "gateway").value, "运行中")
        XCTAssertEqual(
            row(report, "componentPlatforms").value, "已连 1/1"
        )
        let disk = row(report, "check-disk")
        XCTAssertEqual(disk.status, .ok)
        XCTAssertEqual(disk.value, "已用 62.4%")
        XCTAssertEqual(
            row(report, "check-background_queues").value,
            "2 个任务运行中"
        )
        // 恒假旗标显未开放、不显异常（口径不开非故障）
        XCTAssertEqual(row(report, "feature-audio_api").status, .off)
        XCTAssertEqual(row(report, "feature-admin_config_rw").status, .off)
        XCTAssertEqual(row(report, "feature-skills_api").status, .ok)
        XCTAssertEqual(row(report, "feature-runs_idempotency").status, .ok)
        XCTAssertEqual(row(report, "endpointIntegrity").status, .ok)
        XCTAssertEqual(row(report, "extApprovals").status, .ok)
        XCTAssertEqual(row(report, "extApprovals").value, "无待批")
        XCTAssertEqual(row(report, "extGrants").value, "共 0 条授权")
        XCTAssertEqual(row(report, "extEnrollment").status, .ok)
        XCTAssertEqual(row(report, "extReactions").status, .ok)
        // rewind 无只读探针：恒未探、不假探
        XCTAssertEqual(row(report, "extRewind").status, .unprobed)
    }

    func testBuilderSingleFailureIsIsolated() throws {
        let report = SelfCheckReportBuilder.build(
            health: .failure(.unreachable),
            capabilities: .success(
                try decode(CapabilitiesResponse.self, capabilitiesJSON)
            ),
            detailed: .success(
                try decode(HealthDetailedResponse.self, detailedJSON)
            ),
            status: .success(try decode(ServerStatus.self, statusJSON)),
            approvals: .success(try approvals(pending: 2)),
            grants: .success(try grantsEmpty()),
            enrollmentProbe: .success(
                RouteProbeResult(status: 405, errorCode: nil)
            ),
            reactionsProbe: nil,
            checkedAt: Date()
        )
        let reachable = row(report, "reachable")
        XCTAssertEqual(reachable.status, .warn)
        XCTAssertEqual(reachable.reason, "连不上服务器")
        // 一项挂不拖整面：其余结论照旧成立
        XCTAssertEqual(row(report, "credential").status, .ok)
        XCTAssertEqual(row(report, "gateway").status, .ok)
        XCTAssertEqual(row(report, "extApprovals").value, "待批 2 件")
        XCTAssertEqual(report.warnCount, 1)
        XCTAssertEqual(report.overallWord, "1 项异常")
        // 无会话可探：未探＋缘由，不下结论
        let reactions = row(report, "extReactions")
        XCTAssertEqual(reactions.status, .unprobed)
        XCTAssertEqual(reactions.reason, "暂无会话可探")
    }

    func testBuilderUnauthorizedMarksCredentialAndUnprobesFeatures() throws {
        let report = SelfCheckReportBuilder.build(
            health: .success(try healthOK()),
            capabilities: .failure(.unauthorized),
            detailed: .failure(.unauthorized),
            status: .success(try decode(ServerStatus.self, statusJSON)),
            approvals: .failure(.unauthorized),
            grants: .failure(.unauthorized),
            enrollmentProbe: .success(
                RouteProbeResult(status: 405, errorCode: nil)
            ),
            reactionsProbe: .failure(.unauthorized),
            checkedAt: Date()
        )
        let credential = row(report, "credential")
        XCTAssertEqual(credential.status, .warn)
        XCTAssertEqual(credential.reason, "密钥被服务器拒绝")
        // 能力面没拿到：整组未探，不许推成正常/未开放
        XCTAssertEqual(row(report, "feature-skills_api").status, .unprobed)
        XCTAssertEqual(row(report, "endpointIntegrity").status, .unprobed)
        XCTAssertEqual(row(report, "check-state_db").status, .unprobed)
        // 免鉴权面照常成立
        XCTAssertEqual(row(report, "reachable").status, .ok)
        XCTAssertEqual(row(report, "extEnrollment").status, .ok)
    }

    func testBuilderMissingCredentials() throws {
        let report = SelfCheckReportBuilder.build(
            health: .success(try healthOK()),
            capabilities: .failure(.missingCredentials),
            detailed: .failure(.missingCredentials),
            status: .success(try decode(ServerStatus.self, statusJSON)),
            approvals: .failure(.missingCredentials),
            grants: .failure(.missingCredentials),
            enrollmentProbe: .success(
                RouteProbeResult(status: 405, errorCode: nil)
            ),
            reactionsProbe: nil,
            checkedAt: Date()
        )
        XCTAssertEqual(row(report, "credential").status, .unprobed)
        XCTAssertEqual(row(report, "extApprovals").status, .unprobed)
        XCTAssertEqual(row(report, "extGrants").status, .unprobed)
        XCTAssertEqual(report.warnCount, 0)
    }

    func testBuilderDegradedSurfacesReasons() throws {
        let degradedDetailed = detailedJSON
            .replacingOccurrences(
                of: #""state_db": {"status": "ok"}"#,
                with: #""state_db": {"status": "degraded", "detail": "corrupt"}"#
            )
        let degradedStatus = statusJSON
            .replacingOccurrences(
                of: #""storage": {"status": "ok"}"#,
                with: #""storage": {"status": "degraded", "reason": "corrupt"}"#
            )
            .replacingOccurrences(
                of: #""status": "ok", "recent_unhandled_errors": 0"#,
                with: #""status": "degraded", "recent_unhandled_errors": 3"#
            )
        let report = SelfCheckReportBuilder.build(
            health: .success(try healthOK()),
            capabilities: .success(
                try decode(CapabilitiesResponse.self, capabilitiesJSON)
            ),
            detailed: .success(
                try decode(HealthDetailedResponse.self, degradedDetailed)
            ),
            status: .success(try decode(ServerStatus.self, degradedStatus)),
            approvals: .success(try approvals(pending: 1, degraded: true)),
            grants: .success(try grantsEmpty()),
            enrollmentProbe: .success(
                RouteProbeResult(status: 404, errorCode: nil)
            ),
            reactionsProbe: .success(
                RouteProbeResult(status: 404, errorCode: "message_not_found")
            ),
            checkedAt: Date()
        )
        let stateDB = row(report, "check-state_db")
        XCTAssertEqual(stateDB.status, .warn)
        XCTAssertEqual(stateDB.reason, "corrupt")
        let storage = row(report, "componentStorage")
        XCTAssertEqual(storage.status, .warn)
        XCTAssertEqual(storage.reason, "存储损坏")
        let dashboard = row(report, "componentDashboard")
        XCTAssertEqual(dashboard.status, .warn)
        XCTAssertEqual(dashboard.reason, "近期有 3 次未处理错误")
        // 待批账本降级：有结论但带警告，不冒充全好
        XCTAssertEqual(row(report, "extApprovals").status, .warn)
        // 认领路由不在：未开放（补丁未装），不是异常
        XCTAssertEqual(row(report, "extEnrollment").status, .off)
        // reactions 的 message_not_found 404 是在位实证
        XCTAssertEqual(row(report, "extReactions").status, .ok)
        XCTAssertEqual(report.warnCount, 4)
        XCTAssertEqual(report.overallWord, "4 项异常")
    }

    func testBuilderProjectionUnavailableCodes() throws {
        let report = SelfCheckReportBuilder.build(
            health: .success(try healthOK()),
            capabilities: .success(
                try decode(CapabilitiesResponse.self, capabilitiesJSON)
            ),
            detailed: .success(
                try decode(HealthDetailedResponse.self, detailedJSON)
            ),
            status: .success(try decode(ServerStatus.self, statusJSON)),
            approvals: .failure(.serverCode("approval_projection_unavailable")),
            grants: .failure(.serverCode("grant_projection_unavailable")),
            enrollmentProbe: .failure(.unreachable),
            reactionsProbe: .success(
                RouteProbeResult(status: 404, errorCode: nil)
            ),
            checkedAt: Date()
        )
        let approvalsRow = row(report, "extApprovals")
        XCTAssertEqual(approvalsRow.status, .warn)
        XCTAssertEqual(approvalsRow.reason, "待批投影不可用")
        let grantsRow = row(report, "extGrants")
        XCTAssertEqual(grantsRow.status, .warn)
        XCTAssertEqual(grantsRow.reason, "授权投影不可用")
        // 探针传输失败：未探，不下结论
        XCTAssertEqual(row(report, "extEnrollment").status, .unprobed)
        // reactions 裸 404（无在位错误码）：未开放
        XCTAssertEqual(row(report, "extReactions").status, .off)
    }

    func testBuilderNothingProbedIsNotGreen() {
        let report = SelfCheckReportBuilder.build(
            health: .notAttempted,
            capabilities: .notAttempted,
            detailed: .notAttempted,
            status: .notAttempted,
            approvals: .notAttempted,
            grants: .notAttempted,
            enrollmentProbe: .notAttempted,
            reactionsProbe: nil,
            checkedAt: Date()
        )
        XCTAssertEqual(report.probedCount, 0)
        XCTAssertEqual(report.warnCount, 0)
        XCTAssertEqual(report.overallWord, "未检出")
    }
}
