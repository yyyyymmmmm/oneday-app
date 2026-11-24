import OneDayCore
import XCTest

/// H8/H9/H11/H13 服务端契约钉测（DESIGN §390）：样本按
/// Hermes 官方仓 v0.23.0 源码逐 handler 冻结的形状手写
/// （web_routers/delegation.py、models.py、ops.py、
/// status.py），只钉客户端解码/校验/拼装口径，端点真
/// 形态以服务端源码为准
final class HermesAdvancedModelsTests: XCTestCase {

    // MARK: - H8 委派路由读形

    func testDelegationRoutingDecodesServerShape() {
        let routing = DelegationRouting(jsonValue: .object([
            "configured": .string("local"),
            "blocked_reason": .null,
            "backends": .array([
                .object([
                    "name": .string("local"), "label": .string("本机"),
                    "description": .string("在本机跑"),
                    "available": .bool(true), "reason": .string(""),
                    "builtin": .bool(true),
                ]),
                .object([
                    "name": .string("docker"), "label": .string("容器"),
                    "description": .string(""),
                    "available": .bool(false), "reason": .string("未装 Docker"),
                    "builtin": .bool(true),
                ]),
            ]),
            "model_map": .object([
                "options": .array([
                    .object([
                        "name": .string("heavy"),
                        "description": .string("重活走强模型"),
                        "provider": .string("custom"),
                        "model": .string("gpt-x"),
                        "api_key": .string("sk-…1234"),
                        "future_field": .string("keep-me"),
                    ]),
                ]),
                "default": .string("heavy"),
            ]),
            "profile_routes": .object([
                "profiles": .array([
                    .object([
                        "name": .string("researcher"),
                        "description": .string("调研专用"),
                    ]),
                ]),
                "default": .string("researcher"),
            ]),
            "profiles": .array([.string("default"), .string("researcher")]),
        ]))
        XCTAssertEqual(routing.configured, "local")
        XCTAssertNil(routing.blockedReason)
        XCTAssertEqual(routing.backends.count, 2)
        XCTAssertEqual(routing.backends[0].displayLabel, "本机")
        XCTAssertFalse(routing.backends[1].available)
        XCTAssertEqual(routing.modelRoutes.count, 1)
        XCTAssertEqual(routing.modelRoutes[0].apiKeyPreview, "sk-…1234")
        XCTAssertEqual(routing.modelRoutes[0].extras["future_field"], .string("keep-me"))
        XCTAssertEqual(routing.modelRouteDefault, "heavy")
        XCTAssertEqual(routing.profileRoutes.first?.name, "researcher")
        XCTAssertEqual(routing.profileRouteDefault, "researcher")
        XCTAssertEqual(routing.profiles, ["default", "researcher"])
    }

    /// 密钥预览原样带回、改名带 original_name、新填优先、
    /// 未知字段往返保全——四条都是服务端保留真钥的前提
    func testModelRoutePutFieldsKeyHandling() {
        var route = DelegationModelRoute(
            name: "heavy", routeDescription: "重活", provider: "custom",
            model: "gpt-x", apiKeyPreview: "sk-…1234",
            extras: ["future_field": .string("keep-me")]
        )
        var fields = route.putFields()
        XCTAssertEqual(fields["api_key"], .string("sk-…1234"))
        XCTAssertEqual(fields["future_field"], .string("keep-me"))
        XCTAssertNil(fields["original_name"])

        route.originalName = "heavy"
        route.name = "heavy2"
        fields = route.putFields()
        XCTAssertEqual(fields["original_name"], .string("heavy"))

        route.pendingAPIKey = "sk-new"
        fields = route.putFields()
        XCTAssertEqual(fields["api_key"], .string("sk-new"))
    }

    func testDelegationValidationMirrorsServerRules() {
        let good = DelegationModelRoute(
            name: "heavy", routeDescription: "重活",
            provider: "custom", model: "gpt-x"
        )
        XCTAssertTrue(DelegationValidation.modelRouteProblems(
            routes: [good], defaultRoute: "heavy"
        ).isEmpty)
        // 缺说明
        var noDesc = good; noDesc.routeDescription = ""
        XCTAssertFalse(DelegationValidation.modelRouteProblems(
            routes: [noDesc], defaultRoute: nil
        ).isEmpty)
        // provider 与 base_url 都缺
        var noProvider = good; noProvider.provider = ""
        XCTAssertFalse(DelegationValidation.modelRouteProblems(
            routes: [noProvider], defaultRoute: nil
        ).isEmpty)
        // 重名
        XCTAssertFalse(DelegationValidation.modelRouteProblems(
            routes: [good, good], defaultRoute: nil
        ).isEmpty)
        // 默认不在名单
        XCTAssertFalse(DelegationValidation.modelRouteProblems(
            routes: [good], defaultRoute: "cheap"
        ).isEmpty)
        // 档案：不存在的档案被拦
        XCTAssertFalse(DelegationValidation.profileRouteProblems(
            routes: [DelegationProfileRoute(name: "ghost")],
            defaultRoute: nil, knownProfiles: ["default"]
        ).isEmpty)
        XCTAssertTrue(DelegationValidation.profileRouteProblems(
            routes: [DelegationProfileRoute(name: "default")],
            defaultRoute: "default", knownProfiles: ["default"]
        ).isEmpty)
    }

    // MARK: - H9 MoA 读形/校验/选择器组

    private func moaFixture() -> MoaConfig {
        MoaConfig(jsonValue: .object([
            "default_preset": .string("careful"),
            "active_preset": .string(""),
            "presets": .object([
                "careful": .object([
                    "reference_models": .array([
                        .object([
                            "provider": .string("custom"),
                            "model": .string("gpt-x"),
                            "enabled": .bool(true),
                        ]),
                        .object([
                            "provider": .string("openrouter"),
                            "model": .string("claude-y"),
                            "enabled": .bool(false),
                        ]),
                    ]),
                    "aggregator": .object([
                        "provider": .string("custom"),
                        "model": .string("gpt-x"),
                    ]),
                    "enabled": .bool(true),
                ]),
            ]),
        ]))
    }

    func testMoaConfigDecodesAndPicksEffective() {
        let config = moaFixture()
        XCTAssertEqual(config.presetNames, ["careful"])
        XCTAssertEqual(config.effectivePresetName, "careful")
        XCTAssertEqual(config.presets["careful"]?.referenceModels.count, 2)
        XCTAssertEqual(config.presets["careful"]?.aggregator.model, "gpt-x")
        XCTAssertTrue(config.allProblems().isEmpty)
    }

    func testMoaProblemsMirrorServerValidation() {
        var preset = MoaPreset()
        XCTAssertFalse(preset.problems(named: "x").isEmpty)
        preset.referenceModels = [MoaSlot(provider: "custom", model: "")]
        XCTAssertFalse(preset.problems(named: "x").isEmpty)
        preset.referenceModels = [MoaSlot(provider: "custom", model: "m")]
        preset.aggregator = MoaSlot(provider: "custom", model: "agg")
        XCTAssertTrue(preset.problems(named: "x").isEmpty)
    }

    func testMoaPickerGroupShape() {
        let group = moaFixture().pickerGroup()
        XCTAssertEqual(group.title, "多模型会商")
        XCTAssertEqual(group.choices.count, 1)
        XCTAssertEqual(group.choices[0].model, "careful")
        XCTAssertEqual(group.choices[0].providerField, "moa")
        XCTAssertEqual(group.choices[0].sourceLabel, "多模型会商")
        XCTAssertTrue(group.choices[0].isDefault)
    }

    func testMoaPutBodyIsWholeGraph() {
        let body = moaFixture().putBody()
        XCTAssertEqual(body["default_preset"], .string("careful"))
        guard case .object(let presets)? = body["presets"],
              case .object(let careful)? = presets["careful"],
              case .object(let aggregator)? = careful["aggregator"]
        else {
            XCTFail("putBody 结构不对：presets 应为整图对象")
            return
        }
        XCTAssertEqual(presets.keys.sorted(), ["careful"])
        XCTAssertEqual(aggregator["model"], .string("gpt-x"))
        // aggregator 不带 enabled 键（服务端槽形口径）
        XCTAssertNil(aggregator["enabled"])
    }

    // MARK: - H9 辅助端点读形

    func testAuxiliaryRowAssignmentMapping() {
        let page = AuxiliaryTasksResponse(jsonValue: .object([
            "tasks": .array([
                .object([
                    "task": .string("vision"),
                    "provider": .string("auto"),
                    "model": .string(""),
                ]),
                .object([
                    "task": .string("compression"),
                    "provider": .string("ailey"),
                    "model": .string("gpt-x"),
                ]),
            ]),
            "main": .object([
                "provider": .string("custom"), "model": .string("gpt-x"),
            ]),
        ]))
        XCTAssertEqual(page.tasks.count, 2)
        XCTAssertEqual(
            page.row(forTask: "vision")?.assignment(namedProviders: ["ailey"]),
            .follow
        )
        XCTAssertEqual(
            page.row(forTask: "compression")?.assignment(namedProviders: ["ailey"]),
            .use(.named("ailey"), model: "gpt-x")
        )
    }

    func testModelSetReceiptConfirmShape() {
        let receipt = ModelSetReceipt(jsonValue: .object([
            "ok": .bool(false),
            "confirm_required": .bool(true),
            "confirm_message": .string("这个模型很贵"),
        ]))
        XCTAssertFalse(receipt.ok)
        XCTAssertTrue(receipt.confirmRequired)
        XCTAssertEqual(receipt.confirmMessage, "这个模型很贵")
    }

    // MARK: - H11 Webhooks

    func testWebhooksPageDecodesWithoutSecret() {
        let page = WebhooksPage(jsonValue: .object([
            "enabled": .bool(true),
            "base_url": .string("https://example.com"),
            "subscriptions": .array([
                .object([
                    "name": .string("github-push"),
                    "description": .string("仓库推送"),
                    "events": .array([.string("push")]),
                    "deliver": .string("log"),
                    "deliver_only": .bool(false),
                    "prompt": .string("看看这次推送"),
                    "url": .string("https://example.com/webhooks/github-push"),
                    "secret_set": .bool(true),
                    "enabled": .bool(true),
                ]),
            ]),
        ]))
        XCTAssertTrue(page.platformEnabled)
        XCTAssertEqual(page.subscriptions.first?.name, "github-push")
        XCTAssertTrue(page.subscriptions.first?.secretSet ?? false)
    }

    func testWebhookCreateInputNamingAndProblems() {
        XCTAssertEqual(
            WebhookCreateInput.normalizedName("GitHub Push"), "github-push"
        )
        XCTAssertNil(WebhookCreateInput.nameProblem("github-push"))
        XCTAssertNotNil(WebhookCreateInput.nameProblem("  "))
        XCTAssertNotNil(WebhookCreateInput.nameProblem("中文名"))
        var input = WebhookCreateInput(name: "alerts")
        XCTAssertTrue(input.problems.isEmpty)
        input.deliverOnly = true
        XCTAssertFalse(input.problems.isEmpty)
        input.deliver = "telegram"
        XCTAssertTrue(input.problems.isEmpty)
        let body = input.putBody()
        XCTAssertEqual(body["name"], .string("alerts"))
        XCTAssertEqual(body["deliver"], .string("telegram"))
        XCTAssertEqual(body["deliver_only"], .bool(true))
    }

    // MARK: - H13 小件读形

    func testCuratorStatusDecodes() {
        let status = CuratorStatus(jsonValue: .object([
            "enabled": .bool(true),
            "paused": .bool(false),
            "interval_hours": .number(24),
            "last_run_at": .string("2026-11-22T04:00:00Z"),
            "min_idle_hours": .number(2),
            "stale_after_days": .number(7),
            "archive_after_days": .number(30),
        ]))
        XCTAssertTrue(status.enabled)
        XCTAssertFalse(status.paused)
        XCTAssertEqual(status.intervalHours, 24)
        XCTAssertEqual(status.lastRunAt, "2026-11-22T04:00:00Z")
    }

    func testSessionStoreStatsBySourceDescending() {
        let stats = SessionStoreStats(jsonValue: .object([
            "total": .number(10),
            "active_store": .number(8),
            "archived": .number(2),
            "messages": .number(345),
            "by_source": .object([
                "api_server": .number(3),
                "telegram": .number(7),
            ]),
        ]))
        XCTAssertEqual(stats.total, 10)
        XCTAssertEqual(stats.messages, 345)
        XCTAssertEqual(stats.bySource.map(\.source), ["telegram", "api_server"])
        XCTAssertEqual(stats.bySource.map(\.count), [7, 3])
    }

    func testOpsHooksPageDecodes() {
        let page = OpsHooksPage(jsonValue: .object([
            "hooks": .array([
                .object([
                    "event": .string("session_start"),
                    "matcher": .string(""),
                    "command": .string("/opt/hooks/start.sh"),
                    "allowed": .bool(true),
                    "executable": .bool(true),
                ]),
            ]),
            "valid_events": .array([.string("session_start")]),
        ]))
        XCTAssertEqual(page.hooks.first?.event, "session_start")
        XCTAssertEqual(page.validEvents, ["session_start"])
    }

    func testKanbanDecomposeReceiptSummary() {
        let ok = KanbanDecomposeReceipt(jsonValue: .object([
            "ok": .bool(true),
            "task_id": .string("t1"),
            "reason": .string(""),
            "fanout": .bool(true),
            "child_ids": .array([.string("c1"), .string("c2")]),
            "new_title": .null,
        ]))
        XCTAssertTrue(ok.ok)
        XCTAssertEqual(ok.childIDs, ["c1", "c2"])
        XCTAssertTrue(ok.summary.contains("2"))
        let refused = KanbanDecomposeReceipt(jsonValue: .object([
            "ok": .bool(false),
            "task_id": .string("t1"),
            "reason": .string("任务已经在进行中"),
            "fanout": .bool(false),
            "child_ids": .array([]),
        ]))
        XCTAssertFalse(refused.ok)
        XCTAssertTrue(refused.summary.contains("任务已经在进行中"))
    }

    // MARK: - 结构钉：设置目录委派条目

    func testSettingsCatalogHasDelegationEntry() {
        let entry = SettingsCatalog.entries.first { $0.id == "delegation" }
        XCTAssertNotNil(entry)
        XCTAssertEqual(entry?.group, .agent)
        XCTAssertEqual(entry?.destination, .delegation)
    }

    // MARK: - 结构钉：看板动作含自动拆解且只在待整理/已排期出现

    func testKanbanDecomposeActionPlacement() {
        XCTAssertEqual(KanbanAction.decompose.title, "自动拆解")
        XCTAssertTrue(KanbanAction.decompose.isDispatchClass)
        XCTAssertFalse(KanbanAction.decompose.isDestructive)
        let triage = KanbanTask(
            id: "t1", title: "大任务", status: "triage"
        )
        XCTAssertEqual(
            KanbanActionPolicy.actions(for: triage).first, .decompose
        )
        XCTAssertEqual(
            KanbanControlPlan.steps(action: .decompose, task: triage),
            [.decompose(taskID: "t1")]
        )
    }
}
