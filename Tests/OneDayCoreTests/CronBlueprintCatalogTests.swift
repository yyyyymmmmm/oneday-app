import Foundation
import XCTest
@testable import OneDayCore

/// §388 H6/H7 模型钉测：蓝图目录/投递目标/MCP 目录的解码
/// 形状以部署实查为准（v0.23.0 web_routers/cron.py＋
/// blueprint_catalog.py 的 blueprint_catalog_entry、mcp.py
/// 的 _catalog_entry_json 逐字对位），不许凭规格猜形状。
final class CronBlueprintCatalogTests: XCTestCase {

    // MARK: - 蓝图目录解码

    private let blueprintsJSON = """
    {"blueprints": [
      {"key": "morning-brief", "title": "Morning briefing",
       "description": "A short daily briefing", "category": "daily",
       "tags": ["briefing"],
       "fields": [
         {"name": "time", "type": "time", "label": "What time?",
          "default": "08:00", "options": [], "optional": false,
          "strict": true, "help": "24h local time"},
         {"name": "deliver", "type": "enum", "label": "Where to deliver?",
          "default": "origin", "options": ["origin", "local", "telegram"],
          "optional": false, "strict": false, "help": ""},
         {"name": "focus", "type": "text", "label": "Focus",
          "default": null, "options": [], "optional": true,
          "strict": true, "help": ""}
       ],
       "source": "builtin", "plugin": null,
       "schedule": "{minute} {hour} * * *",
       "scheduleHuman": "daily at 08:00",
       "command": "/blueprint morning-brief time=08:00",
       "appUrl": "hermes://blueprint/morning-brief"},
      {"key": "habit-checkin", "title": "Habit check-in",
       "description": "Nudge", "category": "health", "tags": [],
       "fields": [
         {"name": "recurrence", "type": "weekdays", "label": "When?",
          "default": "weekdays", "options": [], "optional": false,
          "strict": true, "help": ""},
         {"name": "interval_min", "type": "text", "label": "Interval",
          "default": 30, "options": [], "optional": true,
          "strict": true, "help": ""}
       ],
       "source": "plugin", "plugin": "demo",
       "schedule": "*/{interval_min} * * * {dow}",
       "scheduleHuman": "every 30 minutes",
       "command": "/blueprint habit-checkin",
       "appUrl": "hermes://blueprint/habit-checkin"}
    ]}
    """

    func testBlueprintsResponseDecodesServerShape() throws {
        let response = try JSONDecoder().decode(
            CronBlueprintsResponse.self,
            from: Data(blueprintsJSON.utf8)
        )
        XCTAssertEqual(response.blueprints.count, 2)
        let brief = response.blueprints[0]
        XCTAssertEqual(brief.key, "morning-brief")
        XCTAssertEqual(brief.id, "morning-brief")
        XCTAssertEqual(brief.category, "daily")
        XCTAssertEqual(brief.tags, ["briefing"])
        XCTAssertEqual(brief.fields.count, 3)
        XCTAssertEqual(brief.source, "builtin")
        XCTAssertNil(brief.plugin)
        XCTAssertEqual(brief.scheduleHuman, "daily at 08:00")

        let timeField = brief.fields[0]
        XCTAssertTrue(timeField.isTime)
        XCTAssertEqual(timeField.defaultText, "08:00")
        let deliverField = brief.fields[1]
        XCTAssertTrue(deliverField.isEnum)
        XCTAssertFalse(deliverField.strict)
        XCTAssertEqual(deliverField.options, ["origin", "local", "telegram"])
        XCTAssertEqual(deliverField.defaultText, "origin")

        let habit = response.blueprints[1]
        XCTAssertEqual(habit.source, "plugin")
        XCTAssertEqual(habit.plugin, "demo")
        XCTAssertTrue(habit.fields[0].isWeekdays)
        // 数字默认值摊平为整数字面（间隔分钟不许带小数点）
        XCTAssertEqual(habit.fields[1].defaultText, "30")
    }

    // MARK: - 填空组装（CronBlueprintFill）

    func testFillUsesDefaultsAndSkipsEmptyOptional() throws {
        let response = try JSONDecoder().decode(
            CronBlueprintsResponse.self,
            from: Data(blueprintsJSON.utf8)
        )
        let fields = response.blueprints[0].fields
        let values = CronBlueprintFill.values(fields: fields, texts: [:])
        let unwrapped = try XCTUnwrap(values)
        XCTAssertEqual(unwrapped["time"], .string("08:00"))
        XCTAssertEqual(unwrapped["deliver"], .string("origin"))
        // 可选槽空值不带（不拿空串去烦服务端校验）
        XCTAssertNil(unwrapped["focus"])
    }

    func testFillRejectsMissingRequired() throws {
        let response = try JSONDecoder().decode(
            CronBlueprintsResponse.self,
            from: Data(blueprintsJSON.utf8)
        )
        let fields = response.blueprints[0].fields
        // time 必填被清空 → 整单不成立
        XCTAssertNil(CronBlueprintFill.values(
            fields: fields, texts: ["time": "  "]
        ))
        // 用户改值原样透传
        let values = CronBlueprintFill.values(
            fields: fields,
            texts: ["time": "07:30", "focus": "财报"]
        )
        XCTAssertEqual(values?["time"], .string("07:30"))
        XCTAssertEqual(values?["focus"], .string("财报"))
    }

    // MARK: - 投递目标解码

    func testDeliveryTargetsDecodeAndNote() throws {
        let json = """
        {"targets": [
          {"id": "local", "name": "Local (save only)",
           "home_target_set": true, "home_env_var": null},
          {"id": "telegram", "name": "Telegram",
           "home_target_set": false, "home_env_var": "TELEGRAM_HOME_CHANNEL"}
        ]}
        """
        let response = try JSONDecoder().decode(
            CronDeliveryTargetsResponse.self, from: Data(json.utf8)
        )
        XCTAssertEqual(response.targets.count, 2)
        XCTAssertEqual(response.targets[0].id, "local")
        XCTAssertNil(response.targets[0].availabilityNote)
        // 未设主频道的平台仍列出且如实标注（服务端原文口径）
        XCTAssertEqual(response.targets[1].availabilityNote, "未设主频道")
        XCTAssertEqual(
            response.targets[1].homeEnvVar, "TELEGRAM_HOME_CHANNEL"
        )
    }

    // MARK: - MCP 目录解码

    private let catalogJSON = """
    {"entries": [
      {"name": "github", "description": "GitHub MCP",
       "connector_slug": "github", "source": "nous",
       "transport": "stdio", "auth_type": "env",
       "required_env": [
         {"name": "GITHUB_TOKEN", "prompt": "Paste a token", "required": true},
         {"name": "GITHUB_HOST", "prompt": "Host", "required": false}
       ],
       "command": "npx", "args": ["-y", "@modelcontextprotocol/server-github"],
       "url": null, "install_url": null, "install_ref": null,
       "bootstrap": [], "post_install": "", "needs_install": false,
       "installed": true, "enabled": false},
      {"name": "maps", "description": "Maps",
       "connector_slug": null, "source": "nous",
       "transport": "http", "auth_type": "none",
       "required_env": [],
       "command": null, "args": [], "url": "https://example.com/mcp",
       "install_url": "https://github.com/x/y", "install_ref": "main",
       "bootstrap": ["git clone https://github.com/x/y", "npm ci"],
       "post_install": "Restart gateway", "needs_install": true,
       "installed": false, "enabled": false}
    ],
    "diagnostics": [
      {"name": "broken", "kind": "parse", "message": "manifest invalid"}
    ]}
    """

    func testCatalogDecodesServerShape() throws {
        let response = try JSONDecoder().decode(
            MCPCatalogResponse.self, from: Data(catalogJSON.utf8)
        )
        XCTAssertEqual(response.entries.count, 2)
        XCTAssertEqual(response.diagnostics.count, 1)
        XCTAssertEqual(response.diagnostics[0].message, "manifest invalid")

        let github = response.entries[0]
        XCTAssertEqual(github.id, "github")
        XCTAssertEqual(github.stateLabel, "已安装 · 未启用")
        XCTAssertEqual(
            github.commandLine, "npx -y @modelcontextprotocol/server-github"
        )
        XCTAssertEqual(github.requiredEnv.count, 2)
        XCTAssertTrue(github.requiredEnv[0].required)
        // 密钥类按名判（目录 JSON 不带 secret 标记）
        XCTAssertTrue(github.requiredEnv[0].looksSecret)
        XCTAssertFalse(github.requiredEnv[1].looksSecret)

        let maps = response.entries[1]
        XCTAssertEqual(maps.stateLabel, "未安装")
        XCTAssertTrue(maps.needsInstall)
        XCTAssertEqual(maps.bootstrap.count, 2)
        XCTAssertEqual(maps.url, "https://example.com/mcp")
        XCTAssertNil(maps.commandLine)
    }

    func testInstallReceiptDecodes() throws {
        let sync = """
        {"ok": true, "name": "github", "background": false}
        """
        let receipt = try JSONDecoder().decode(
            MCPInstallReceipt.self, from: Data(sync.utf8)
        )
        XCTAssertTrue(receipt.ok)
        XCTAssertFalse(receipt.background)
        XCTAssertNil(receipt.action)

        let background = """
        {"ok": true, "name": "maps", "background": true, "action": "mcp-install-maps"}
        """
        let bgReceipt = try JSONDecoder().decode(
            MCPInstallReceipt.self, from: Data(background.utf8)
        )
        XCTAssertTrue(bgReceipt.background)
        XCTAssertEqual(bgReceipt.action, "mcp-install-maps")
    }
}
