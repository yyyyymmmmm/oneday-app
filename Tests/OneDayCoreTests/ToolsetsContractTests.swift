import OneDayCore
import XCTest

/// 工具集治理契约钉测（DESIGN §358）：清单解码、启停
/// 请求体组装、失败分类矩阵、状态合成（config-only
/// 集真值）、细调三面解码与回读判定——全部对探活与
/// 34-S 真行为验收实测字面（部署包 1.4.0），不许凭
/// 图臆测
final class ToolsetsContractTests: XCTestCase {

    private func decodeList(
        _ json: String
    ) throws -> ToolsetsListResponse {
        try JSONDecoder().decode(
            ToolsetsListResponse.self, from: Data(json.utf8)
        )
    }

    /// 生产形态清单节选（探活实测：27 行＝26 内置＋
    /// kanban 插件集；基线启用 14 集；stt 是 config-
    /// only 集、读面 enabled 恒 false）
    private let productionListJSON = """
    {
      "object": "list",
      "platform": "api_server",
      "data": [
        {
          "name": "web", "label": "Web",
          "description": "联网搜索与网页提取",
          "enabled": true, "configured": true,
          "tools": ["web_search", "web_extract"]
        },
        {
          "name": "image_gen", "label": "Image Generation",
          "description": "生成图片",
          "enabled": true, "configured": true,
          "tools": ["image_generate"]
        },
        {
          "name": "video_gen", "label": "Video Generation",
          "description": "生成视频",
          "enabled": false, "configured": false,
          "tools": ["video_generate"]
        },
        {
          "name": "kanban", "label": "Kanban",
          "description": "看板插件集",
          "enabled": false, "configured": true,
          "tools": ["kanban_list", "kanban_update"]
        },
        {
          "name": "stt", "label": "Speech to Text",
          "description": "语音转写",
          "enabled": false, "configured": true,
          "tools": ["transcribe"]
        }
      ]
    }
    """

    // MARK: - 清单解码

    func testListDecodesProductionShape() throws {
        let response = try decodeList(productionListJSON)
        XCTAssertEqual(response.platform, "api_server")
        XCTAssertEqual(response.data.count, 5)
        let web = try XCTUnwrap(response.row(named: "web"))
        XCTAssertTrue(web.enabled)
        XCTAssertTrue(web.configured)
        XCTAssertEqual(web.tools, ["web_search", "web_extract"])
        XCTAssertEqual(web.displayLabel, "Web")
        let video = try XCTUnwrap(response.row(named: "video_gen"))
        XCTAssertFalse(video.enabled)
        XCTAssertFalse(video.configured)
        let kanban = try XCTUnwrap(response.row(named: "kanban"))
        XCTAssertEqual(kanban.tools.count, 2)
        XCTAssertNil(response.row(named: "nope"))
    }

    /// 行数口径钉：页面行数＝data 行数（生产 27 行），
    /// 不许按「59 条」功能计数造行或漏行
    func testListRowCountMatchesDataExactly() throws {
        let rows = (0..<27).map { index in
            """
            {"name": "set_\(index)", "label": "S\(index)",
             "description": "", "enabled": \(index % 2 == 0),
             "configured": true, "tools": ["tool_\(index)"]}
            """
        }.joined(separator: ",")
        let response = try decodeList(
            "{\"object\": \"list\", \"platform\": \"api_server\","
                + "\"data\": [\(rows)]}"
        )
        XCTAssertEqual(response.data.count, 27)
        XCTAssertEqual(
            response.row(named: "set_26")?.tools, ["tool_26"]
        )
    }

    /// 字段缺席宽容：label/description/tools 缺席不炸
    func testListRowToleratesMissingFields() throws {
        let response = try decodeList("""
        {"data": [{"name": "bare", "enabled": true}]}
        """)
        let row = try XCTUnwrap(response.row(named: "bare"))
        XCTAssertEqual(row.displayLabel, "bare")
        XCTAssertEqual(row.description, "")
        XCTAssertEqual(row.tools, [])
        XCTAssertFalse(row.configured)
    }

    // MARK: - 状态合成（config-only 集真值）

    private func config(
        _ json: String
    ) throws -> [String: JSONValue] {
        try JSONDecoder().decode(
            [String: JSONValue].self, from: Data(json.utf8)
        )
    }

    func testConfigBackedExtraction() throws {
        // stt 节带 enabled＝config 承托；web 节只有
        // backend（无 enabled 键）不入表；terminal 节
        // 带 enabled=false 如实入表
        let raw = try config("""
        {
          "stt": {"enabled": true, "provider": "local"},
          "web": {"backend": "tavily"},
          "terminal": {"backend": "local", "enabled": false}
        }
        """)
        let map = ToolsetStateResolution.configBackedEnabled(
            in: raw
        )
        XCTAssertEqual(map, ["stt": true, "terminal": false])
        XCTAssertEqual(
            ToolsetStateResolution.configBackedEnabled(in: nil),
            [:]
        )
    }

    func testEffectiveEnabledResolution() throws {
        let response = try decodeList(productionListJSON)
        let stt = try XCTUnwrap(response.row(named: "stt"))
        let web = try XCTUnwrap(response.row(named: "web"))
        // 读面口径：stt 恒 false（34-S 实测 E 步）
        XCTAssertFalse(stt.enabled)
        // config 说开：有效态以 config 为准
        XCTAssertTrue(
            ToolsetStateResolution.effectiveEnabled(
                stt, configEnabled: ["stt": true]
            )
        )
        XCTAssertTrue(
            ToolsetStateResolution.isConfigBacked(
                stt, configEnabled: ["stt": true]
            )
        )
        // config 没读到：回落读面值、不冒充
        XCTAssertFalse(
            ToolsetStateResolution.effectiveEnabled(
                stt, configEnabled: [:]
            )
        )
        // 普通集恒以读面为准（config 里没它的 enabled 键）
        XCTAssertTrue(
            ToolsetStateResolution.effectiveEnabled(
                web, configEnabled: ["stt": true]
            )
        )
        XCTAssertFalse(
            ToolsetStateResolution.isConfigBacked(
                web, configEnabled: ["stt": true]
            )
        )
    }

    func testEnabledCountUsesEffectiveState() throws {
        let response = try decodeList(productionListJSON)
        // 读面启用：web、image_gen 两行
        XCTAssertEqual(
            ToolsetStateResolution.enabledCount(
                in: response, configEnabled: [:]
            ),
            2
        )
        // stt 经 config 打开后计入
        XCTAssertEqual(
            ToolsetStateResolution.enabledCount(
                in: response, configEnabled: ["stt": true]
            ),
            3
        )
    }

    // MARK: - 启停契约

    func testToggleReceiptDecodes() throws {
        // 34-S 验收 B1 步实测回执形态
        let receipt = try JSONDecoder().decode(
            ToolsetToggleReceipt.self,
            from: Data(
                """
                {"ok": true, "name": "image_gen",
                 "platform": "api_server", "enabled": false}
                """.utf8
            )
        )
        XCTAssertTrue(receipt.ok)
        XCTAssertEqual(receipt.name, "image_gen")
        XCTAssertEqual(receipt.platform, "api_server")
        XCTAssertFalse(receipt.enabled)
    }

    func testToggleRequestBodyShape() throws {
        let data = try JSONEncoder().encode(
            ToolsetToggleRequest.set(false)
        )
        let body = try JSONSerialization.jsonObject(
            with: data
        ) as? [String: Any]
        XCTAssertEqual(body?["enabled"] as? Bool, false)
        XCTAssertEqual(body?.count, 1)
    }

    func testToggleDirectiveMatrix() {
        // 34-S 实测：未知集 400 unknown_toolset、非
        // bool 400 invalid_enabled、无鉴权 401
        XCTAssertEqual(
            ToolsetToggleDirective.directive(
                status: 200, serverCode: nil
            ),
            .done
        )
        XCTAssertEqual(
            ToolsetToggleDirective.directive(
                status: 400, serverCode: "unknown_toolset"
            ),
            .unknownToolset
        )
        XCTAssertEqual(
            ToolsetToggleDirective.directive(
                status: 400, serverCode: "invalid_enabled"
            ),
            .invalidRequest
        )
        XCTAssertEqual(
            ToolsetToggleDirective.directive(
                status: 400, serverCode: "something_else"
            ),
            .failed
        )
        XCTAssertEqual(
            ToolsetToggleDirective.directive(
                status: 401, serverCode: nil
            ),
            .unauthorized
        )
        XCTAssertEqual(
            ToolsetToggleDirective.directive(
                status: 503, serverCode: nil
            ),
            .failed
        )
    }

    // MARK: - 启停回读判定

    func testToggleReadbackConfirmedOnFlip() throws {
        // 34-S B2 步：关 image_gen 后回读仅该行翻转
        let after = try decodeList("""
        {
          "object": "list", "platform": "api_server",
          "data": [
            {"name": "image_gen", "label": "Image Generation",
             "description": "", "enabled": false,
             "configured": true, "tools": ["image_generate"]}
          ]
        }
        """)
        XCTAssertTrue(
            ToolsetReadback.isToggleConfirmed(
                name: "image_gen", target: false,
                in: after, configEnabled: [:]
            )
        )
        XCTAssertFalse(
            ToolsetReadback.isToggleConfirmed(
                name: "image_gen", target: true,
                in: after, configEnabled: [:]
            )
        )
        // 行不在回读清单里：不确认（不许认回执自报）
        XCTAssertFalse(
            ToolsetReadback.isToggleConfirmed(
                name: "video_gen", target: false,
                in: after, configEnabled: [:]
            )
        )
    }

    func testToggleReadbackForConfigOnlySetUsesConfig() throws {
        // stt 回读：清单行恒 false，判定必须看 config
        // ——config 翻到 false 才算「关」确认
        let list = try decodeList(productionListJSON)
        XCTAssertTrue(
            ToolsetReadback.isToggleConfirmed(
                name: "stt", target: false,
                in: list, configEnabled: ["stt": false]
            )
        )
        XCTAssertFalse(
            ToolsetReadback.isToggleConfirmed(
                name: "stt", target: true,
                in: list, configEnabled: ["stt": false]
            )
        )
        XCTAssertTrue(
            ToolsetReadback.isToggleConfirmed(
                name: "stt", target: true,
                in: list, configEnabled: ["stt": true]
            )
        )
    }

    // MARK: - 细调面板解码

    func testConfigPanelDecodes() throws {
        // 源码形状（tools.py config 面）：provider 矩
        // 阵＋env 只回 is_set
        let panel = try JSONDecoder().decode(
            ToolsetConfigPanel.self,
            from: Data(
                """
                {
                  "name": "web", "has_category": true,
                  "providers": [
                    {
                      "name": "tavily", "badge": "推荐",
                      "tag": "搜索与提取",
                      "env_vars": [
                        {"key": "TAVILY_API_KEY",
                         "prompt": "Tavily 密钥",
                         "url": "https://tavily.com",
                         "default": null, "is_set": true}
                      ],
                      "post_setup": null,
                      "requires_nous_auth": false,
                      "is_active": true, "status": "ready"
                    },
                    {
                      "name": "brave", "badge": "", "tag": "",
                      "env_vars": [
                        {"key": "BRAVE_API_KEY",
                         "prompt": "Brave 密钥", "url": null,
                         "default": null, "is_set": false}
                      ],
                      "post_setup": null,
                      "requires_nous_auth": false,
                      "is_active": false, "status": ""
                    }
                  ],
                  "active_provider": "tavily"
                }
                """.utf8
            )
        )
        XCTAssertEqual(panel.name, "web")
        XCTAssertTrue(panel.hasCategory)
        XCTAssertEqual(panel.providers.count, 2)
        XCTAssertEqual(panel.activeProvider, "tavily")
        let tavily = try XCTUnwrap(panel.provider(named: "tavily"))
        XCTAssertTrue(tavily.isActive)
        XCTAssertEqual(tavily.envVars.first?.isSet, true)
        XCTAssertEqual(tavily.envVars.first?.key, "TAVILY_API_KEY")
        let brave = try XCTUnwrap(panel.provider(named: "brave"))
        XCTAssertEqual(brave.envVars.first?.isSet, false)
        // 回读判定：active_provider 对上才确认
        XCTAssertTrue(
            ToolsetReadback.isProviderConfirmed(
                panel, provider: "tavily"
            )
        )
        XCTAssertFalse(
            ToolsetReadback.isProviderConfirmed(
                panel, provider: "brave"
            )
        )
    }

    // MARK: - 模型目录解码

    func testModelCatalogDecodes() throws {
        // strengths 数组形态＋price 数字形态（宽容口径）
        let catalog = try JSONDecoder().decode(
            ToolsetModelCatalog.self,
            from: Data(
                """
                {
                  "name": "image_gen", "has_models": true,
                  "provider": "openai",
                  "models": [
                    {"id": "dall-e-3", "display": "DALL·E 3",
                     "speed": "慢", "strengths": ["质量", "细节"],
                     "price": 0.04},
                    {"id": "gpt-image-1", "display": "",
                     "speed": "", "strengths": "编辑强",
                     "price": "$0.02"}
                  ],
                  "current": "dall-e-3", "default": "dall-e-3"
                }
                """.utf8
            )
        )
        XCTAssertTrue(catalog.hasModels)
        XCTAssertEqual(catalog.models.count, 2)
        XCTAssertEqual(catalog.models[0].strengths, "质量、细节")
        XCTAssertEqual(catalog.models[0].price, "0.04")
        XCTAssertEqual(catalog.models[1].displayName, "gpt-image-1")
        XCTAssertEqual(catalog.models[1].strengths, "编辑强")
        XCTAssertEqual(catalog.current, "dall-e-3")
        XCTAssertEqual(catalog.defaultModel, "dall-e-3")
        XCTAssertTrue(
            ToolsetReadback.isModelConfirmed(
                catalog, model: "dall-e-3"
            )
        )
        XCTAssertFalse(
            ToolsetReadback.isModelConfirmed(
                catalog, model: "gpt-image-1"
            )
        )
    }

    func testModelCatalogWithoutModels() throws {
        let catalog = try JSONDecoder().decode(
            ToolsetModelCatalog.self,
            from: Data(
                """
                {"name": "web", "has_models": false,
                 "provider": null, "models": [],
                 "current": null, "default": null}
                """.utf8
            )
        )
        XCTAssertFalse(catalog.hasModels)
        XCTAssertTrue(catalog.models.isEmpty)
        XCTAssertNil(catalog.current)
    }

    // MARK: - 终端后端解码

    func testTerminalBackendsDecode() throws {
        let backends = try JSONDecoder().decode(
            TerminalBackends.self,
            from: Data(
                """
                {
                  "active": "local",
                  "backends": [
                    {"name": "local", "label": "本机",
                     "description": "在服务器本机执行",
                     "active": true, "status": "ready",
                     "detail": ""},
                    {"name": "docker", "label": "Docker",
                     "description": "容器内执行",
                     "active": false, "status": "needs_setup",
                     "detail": "镜像未拉取"},
                    {"name": "modal", "label": "Modal",
                     "description": "云端执行",
                     "active": false, "status": "unavailable",
                     "detail": ""},
                    {"name": "future", "label": "Future",
                     "description": "", "active": false,
                     "status": "beta", "detail": ""}
                  ]
                }
                """.utf8
            )
        )
        XCTAssertEqual(backends.active, "local")
        XCTAssertEqual(backends.backends.count, 4)
        let local = try XCTUnwrap(backends.backend(named: "local"))
        XCTAssertEqual(local.status, .ready)
        XCTAssertTrue(local.status.isSelectable)
        let docker = try XCTUnwrap(backends.backend(named: "docker"))
        XCTAssertEqual(docker.status, .needsSetup)
        XCTAssertFalse(docker.status.isSelectable)
        XCTAssertEqual(docker.detail, "镜像未拉取")
        let modal = try XCTUnwrap(backends.backend(named: "modal"))
        XCTAssertEqual(modal.status, .unavailable)
        // 未知状态原样保留、不猜
        let future = try XCTUnwrap(backends.backend(named: "future"))
        XCTAssertEqual(future.status, .other("beta"))
        XCTAssertFalse(future.status.isSelectable)
        // 回读判定：active 对上才确认
        XCTAssertTrue(
            ToolsetReadback.isBackendConfirmed(
                backends, name: "local"
            )
        )
        XCTAssertFalse(
            ToolsetReadback.isBackendConfirmed(
                backends, name: "docker"
            )
        )
    }
}
