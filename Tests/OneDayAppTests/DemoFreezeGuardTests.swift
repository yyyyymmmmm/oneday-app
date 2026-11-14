import OneDayCore
import XCTest
@testable import OneDayApp

/// C-13 接口面冻结钉测（overcomplexity-audit-20261114
/// C-13；冻结面口径 demo-surface-freeze-20261111）：
/// DemoHermesClient 的种子面以 2026-11-11 冻结清单为
/// 限——清单外方法必须恒抛 HermesError.demoLimitReached
/// 统一空态信号。谁把清单外方法改成返种子（＝给 Demo
/// 扩面、恢复平行维护），本套件即红；扩面须先改冻结
/// 清单与施工单点名，再来改这里的名单。
final class DemoFreezeGuardTests: XCTestCase {

    private let client = DemoHermesClient()
    private let config = ServerConfig(rawInput: "hermes.didichou.site")

    /// 清单外方法恒抛统一空态信号（抽样钉测：管理面、
    /// 技能、定时、档案、MCP、配置、环境变量、用量、
    /// 出口、系统状态、电脑操控、文件写口、网关动作、
    /// 会话写口各取代表）
    func testOutOfFreezeListMethodsThrowDemoLimit() async {
        await assertDemoLimit { try await client.memoryStatus(config: config) }
        await assertDemoLimit { try await client.setMemoryProvider(config: config, name: "x") }
        await assertDemoLimit { try await client.skills(config: config) }
        await assertDemoLimit { try await client.cronJobs(config: config) }
        await assertDemoLimit { try await client.profiles(config: config) }
        await assertDemoLimit { try await client.mcpServers(config: config) }
        await assertDemoLimit { try await client.rawConfig(config: config) }
        await assertDemoLimit { try await client.envVars(config: config) }
        await assertDemoLimit { try await client.usageAnalytics(config: config, days: 7) }
        await assertDemoLimit { try await client.egressStatus(config: config) }
        await assertDemoLimit { try await client.systemStats(config: config) }
        await assertDemoLimit { try await client.computerUseStatus(config: config) }
        await assertDemoLimit {
            try await client.deleteFile(config: config, path: "/opt/data/x", recursive: false)
        }
        await assertDemoLimit {
            try await client.makeDirectory(config: config, path: "/opt/data/x")
        }
        await assertDemoLimit { try await client.gatewayRestart(config: config) }
        await assertDemoLimit { try await client.deleteServerSession(config: config, id: "x") }
    }

    /// 正对照：冻结清单内的连接页探活仍是活种子——证
    /// 明被测对象是种子面受限的 Demo 客户端、不是全抛
    /// 桩（防「把整个 Demo 改成全抛」式假冻结）
    func testFrozenSeedSurfaceStillAlive() async throws {
        let health = try await client.health(config: config)
        XCTAssertTrue(health.isOK)
        let models = try await client.models(config: config, apiKey: "demo-api-key")
        XCTAssertFalse(models.isEmpty)
    }

    private func assertDemoLimit<T>(
        _ operation: () async throws -> T
    ) async {
        do {
            _ = try await operation()
            XCTFail("清单外方法应抛 demoLimitReached，却返回了种子结果（Demo 扩面？）")
        } catch let error as HermesError {
            guard case .demoLimitReached = error else {
                XCTFail("清单外方法应抛 demoLimitReached，实际抛 \(error)")
                return
            }
        } catch {
            XCTFail("清单外方法应抛 HermesError.demoLimitReached，实际抛 \(error)")
        }
    }
}
