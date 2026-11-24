import XCTest
@testable import OneDayCore

/// 设置目录钉测（DESIGN §164）：清单完整性（id/目的
/// 地唯一、对账锚点齐全）与搜索口径（清单序、空查询
/// 全量、中英关键词命中、无命中为空）
final class SettingsCatalogTests: XCTestCase {

    func testIDsAndDestinationsAreUnique() {
        let ids = SettingsCatalog.entries.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count, "条目 id 必须唯一")
        let destinations = SettingsCatalog.entries.map(\.destination)
        XCTAssertEqual(
            Set(destinations).count, destinations.count,
            "每个目的地只许一个条目（点达不许双门）"
        )
    }

    func testEntriesCarrySearchMaterial() {
        for entry in SettingsCatalog.entries {
            XCTAssertFalse(entry.title.isEmpty, "\(entry.id) 缺标题")
            XCTAssertFalse(entry.summary.isEmpty, "\(entry.id) 缺副行")
            XCTAssertFalse(entry.keywords.isEmpty, "\(entry.id) 缺关键词")
        }
    }

    /// 搜索索引在清单里逐项有锚（prototype-2 索引经
    /// 结构归位 2026-11-20 修订：四个枢纽页条目退役、
    /// 子项与断开连接动作条目续存）
    func testPrototypeIndexIsCovered() {
        let ids = Set(SettingsCatalog.entries.map(\.id))
        for id in [
            "privacy", "terms",
            "identity", "profiles", "memory", "skills", "models", "cron",
            "mainSession",
            "server", "gateway", "logs", "envVars", "usage",
            "connectors", "devicePermissions",
            "voice",
            "appearance", "help", "about",
            // §503 新增两叶子页条目
            "language", "interaction",
            "disconnect",
        ] {
            XCTAssertTrue(ids.contains(id), "索引缺条目 \(id)")
        }
        // 枢纽页条目已退役、不许残留（点达不许有第二扇门）
        for id in ["agentConfig", "serverManagement", "sessionManagement", "workspace"] {
            XCTAssertFalse(ids.contains(id), "枢纽页条目 \(id) 应已退役")
        }
        // 重启网关独立页条目已退役（台账 198 收敛
        // S4：重启只走网关状态页控制组，根行不许再
        // 长第二扇门）
        XCTAssertFalse(ids.contains("restartGateway"), "重启网关条目应已退役")
        // 服务端会话条目已退役（§450，设置 IA 先行
        // 包）：目的地本体是全部对话一级面，设置深链
        // 门面属状态类重复门、整条移出（根页搜索皆无）
        XCTAssertFalse(ids.contains("serverSessions"), "服务端会话条目应已退役（§450）")
        // §493（设置 IA 审计全量落码）四条整条退役：
        // 状态（D1，内容 rehousing 网关页/各正主）、
        // 电脑（D4 甲，整面并入中枢电脑格）、服务器
        // 文件（D6，与资源库文件面重复门）、审批规
        // 则（D3，整页迁中枢审核段）
        for id in ["status", "computer", "serverFiles", "approvalRules"] {
            XCTAssertFalse(ids.contains(id), "§493 退役条目 \(id) 不许残留")
        }
    }

    /// 现行主页全部目的地在清单里有锚（零丢失对账的
    /// 机器面：目的地集合与 SettingsDestination 全集
    /// 逐一对应）
    func testEveryDestinationIsCovered() {
        let covered = Set(SettingsCatalog.entries.map(\.destination))
        let all: [SettingsDestination] = [
            .identity, .profiles, .memory, .skills, .toolsets,
            // H8 新增（总表 168，DESIGN §390）
            .delegation, .cron,
            .models, .envVars, .usage,
            .serverDetail, .connectors, .devicePermissions,
            .gateway, .logs,
            .appearance, .help, .about, .privacy, .terms,
            // §503 新增（语言/互动两叶子页）
            .language, .interaction,
            // prototype-2 叶子（枢纽目的地已退役；重启
            // 网关目的地随台账 198 收敛 S4 一并退役）
            .mainSession,
            // H1-a 新增（台账 158）
            .healthCheck,
            // H13 新增（台账 33，DESIGN §357）
            .connectionSelfCheck,
            // 结构归位新增（断开连接动作）
            .disconnect,
            // H2-a 新增（台账 159）
            .voice,
            // §385 新增（总表 162/163）
            .notifications,
            // 配对一期新增（台账 153/160）
            .addDevice,
            // H5 新增（台账 35）
            .pairingManagement,
            // 聊天诊断新增（台账 189/190）
            .chatDiagnostics,
            // 崩溃报告新增（G-14，DESIGN §384）
            .crashReports,
        ]
        XCTAssertEqual(covered, Set(all))
        // §450 口径：serverSessions 目的地本体保留
        // （activate 深链备查）但目录条目已退役——覆
        // 盖集不含它是裁定、不是丢失（见上退役钉）
        XCTAssertFalse(covered.contains(.serverSessions))
        // §493 口径：status/computer/serverFiles/
        // approvalRules 四目的地本体保留（深链/中枢
        // 直推备查）但目录条目已退役——覆盖集不含
        // 它们是裁定、不是丢失
        for dest in [
            SettingsDestination.status, .computer,
            .serverFiles, .approvalRules,
        ] {
            XCTAssertFalse(
                covered.contains(dest),
                "§493 退役条目的目的地 \(dest) 不应在覆盖集"
            )
        }
    }

    /// 结构归位：agent 组五行——原智能体配置页内三项
    /// （profiles/memory/skills）提回根组直达
    func testAgentGroupBrowseOrder() {
        XCTAssertEqual(
            SettingsCatalog.browseEntries(in: .agent).map(\.id),
            [
                "models", "profiles", "memory", "skills", "toolsets",
                // H8 委派路由（总表 168，DESIGN §390）：
                // 与工具集同组并列、居其后
                "delegation", "cron",
            ]
        )
    }

    /// 台账 198 收敛后四段序（服务器→会话→工作
    /// 区→维护）；§450（设置 IA 先行包）再收：添加
    /// 设备/设备配对收进服务器页内（仅搜索可达）、
    /// 日志/连接自检降仅搜索可达（工具型）、服务端
    /// 会话条目整条退役——组浏览行 14→9；§470
    /// （S5-11 打包改）三行再移出：状态降仅搜索可
    /// 达、用量收进网关状态页、主线对话改深链——
    /// 组浏览行 9→6
    func testServerAndWorkspaceGroupBrowseOrder() {
        // §493：工作区段（电脑/服务器文件退役）与维
        // 护段（密钥/体检收进当前服务器页）双双撤销
        // ——组浏览行只剩服务器段两行
        XCTAssertEqual(
            SettingsCatalog.browseEntries(in: .serverAndWorkspace).map(\.id),
            [
                "server", "gateway",
            ]
        )
    }

    /// 台账 198 收敛 S7：四段分组与段内序——段题与
    /// 段集是根页渲染的机器口径，不许渲染层另排
    func testServerAndWorkspaceSegments() {
        let segments = SettingsCatalog.browseSegments(in: .serverAndWorkspace)
        // 台账 199 合流对账：会话段只剩 mainSession 一行（serverSessions 当年退役出段、§450 起条目本体整条删除）；服务器段 §450 后只剩连接本体三行（配对类收进服务器页、工具类降仅搜索）；§470 后：服务器段用量收进网关页、工作区段状态降仅搜索、会话段随主线对话改深链整段撤销——段集四段→三段
        // §493：段集三段→一段（工作区段随电脑/服务
        // 器文件退役撤销、维护段随密钥/体检收纳撤销）
        XCTAssertEqual(
            segments.map(\.segment),
            [.server]
        )
        XCTAssertEqual(
            segments.map { $0.entries.map(\.id) },
            [
                ["server", "gateway"],
            ]
        )
        // 无段字段的组不分段（整组一个 Section）
        XCTAssertTrue(SettingsCatalog.browseSegments(in: .agent).isEmpty)
        XCTAssertTrue(SettingsCatalog.browseSegments(in: .preferences).isEmpty)
    }

    /// preferences 组六行（台账 198 收敛 S13：语音行
    /// 自服务器组迁入、紧随外观；§385 通知行随分级
    /// 提醒立项紧随语音）
    func testPreferencesGroupBrowseOrder() {
        XCTAssertEqual(
            SettingsCatalog.browseEntries(in: .preferences).map(\.id),
            // §493：审批规则整页迁中枢审核段（D3）——偏好组六行→五行
            // §503：语言（随外观后）/互动（随通知后）两
            // 叶子页拆出独立条目——五行→七行
            ["appearance", "language", "voice", "notifications", "interaction", "connectors", "devicePermissions"]
        )
    }

    /// 全部对话在设置内无独立条目（归位合流 2026-
    /// 11-20，纲要 D2-1／原则 6 列表只住一级面）：
    /// 目录不许长 allConversations 本体条目。台账
    /// 199 曾留「服务端会话」深链行（搜索恰命中一
    /// 条）；§450（2026-11-24 用户裁：状态类整条移
    /// 出）该深链行整条删除——设置内搜「全部对话」
    /// 自此零命中，名单只住一级面一份
    func testAllConversationsHasNoSettingsEntry() {
        XCTAssertFalse(
            SettingsCatalog.entries.contains {
                $0.id == "allConversations"
            }
        )
        XCTAssertTrue(
            SettingsCatalog.search("全部对话").isEmpty,
            "§450 后设置内无全部对话深链行"
        )
    }

    /// 侧边栏行已退役（归位合流 2026-11-20）：分区
    /// 管理面整套退役后目录不许残留 phantom 入口
    func testSidebarEntryIsRetired() {
        XCTAssertFalse(
            SettingsCatalog.entries.contains { $0.id == "sidebar" }
        )
    }

    /// 隐藏条目（不在根页显示）：身份（卡片形态单
    /// 列）、隐私/协议（关于页内二级）、断开连接（动
    /// 作条目，浏览态由根页手写行呈现）与聊天诊断
    /// （台账 198 收敛 S13：入口迁关于页内部实验节，
    /// 只进搜索索引）；§450 再加四条——添加设备/设
    /// 备配对（收进当前服务器页内）、日志/连接自检
    /// （工具型降级），四条都仅搜索可达、功能不删；
    /// §470 再加三条——状态（汇总页降仅搜索）、用
    /// 量（收进网关状态页内）、主线对话（改深链）
    func testHiddenFromBrowseEntries() {
        let hidden = SettingsCatalog.entries
            .filter { !$0.showsInBrowse }.map(\.id)
        XCTAssertEqual(
            Set(hidden),
// §493：status 整条退役（不在隐藏集、是无条目）；envVars/healthCheck 改仅搜索可达（入口收进当前服务器页「服务器管理」组）
["identity","privacy","terms","disconnect", "chatDiagnostics", "crashReports", "addDevice", "pairing", "logs", "connectionSelfCheck", "usage", "mainSession", "envVars", "healthCheck"]
        )
    }

    /// 台账 198 收敛 S13：聊天诊断根行退役后搜索仍
    /// 须点达（入口迁关于页内部实验节、搜索是第二路）
    func testChatDiagnosticsEntryIsSearchOnly() {
        let hits = SettingsCatalog.search("聊天诊断")
        XCTAssertEqual(hits.first?.id, "chatDiagnostics")
        XCTAssertEqual(hits.first?.destination, .chatDiagnostics)
        XCTAssertFalse(hits.first?.showsInBrowse ?? true)
    }

    func testSearchByChineseTitle() {
        let hits = SettingsCatalog.search("记忆")
        XCTAssertEqual(hits.first?.id, "memory")
        // 标题命中优先、且是唯一命中（枢纽页退役后无
        // 副行搭载命中）
        XCTAssertEqual(hits.map(\.id), ["memory"])
    }

    func testSearchMatchesSummaryAndKeywords() {
        // 「服务器」命中当前服务器/服务器密钥（标题）
        // 等多条，按清单序返回；§493 T9 后配置档案副
        // 行改「决定 AI 的性格与做事方式」、不再搭载
        // 「服务器」命中（旧断言随文案改判撤销）
        let hits = SettingsCatalog.search("服务器")
        XCTAssertTrue(hits.contains { $0.id == "server" })
        XCTAssertTrue(hits.contains { $0.id == "envVars" })
        XCTAssertFalse(hits.contains { $0.id == "profiles" })
        // 英文关键词大小写不敏感
        XCTAssertEqual(
            SettingsCatalog.search("MEMORY").map(\.id), ["memory"]
        )
        XCTAssertEqual(
            SettingsCatalog.search("mcp").map(\.id), ["connectors"]
        )
        // 断开连接搜索命中专设动作条目（标题直达）
        let disconnectHits = SettingsCatalog.search("断开连接")
        XCTAssertEqual(disconnectHits.first?.id, "disconnect")
    }

    func testSearchTrimsAndEmptyReturnsAll() {
        XCTAssertEqual(
            SettingsCatalog.search("  外观 ").map(\.id), ["appearance"]
        )
        XCTAssertEqual(
            SettingsCatalog.search("").count,
            SettingsCatalog.entries.count
        )
        XCTAssertEqual(
            SettingsCatalog.search("   ").count,
            SettingsCatalog.entries.count
        )
    }

    func testSearchNoHitIsEmpty() {
        XCTAssertTrue(SettingsCatalog.search("不存在的词条xyz").isEmpty)
    }

    /// H1-a（台账 158）：体检面条目——标题直搜命中；
    /// 结构归位后已提回根页服务器组浏览态直达
    func testHealthCheckEntryIsSearchable() {
        let hits = SettingsCatalog.search("体检")
        XCTAssertEqual(hits.first?.id, "healthCheck")
        XCTAssertEqual(hits.first?.destination, .healthCheck)
        XCTAssertEqual(hits.first?.group, .serverAndWorkspace)
        // §493：根页不平铺、仅搜索可达（入口正主在
        // 当前服务器页「服务器管理」组）
        XCTAssertFalse(hits.first?.showsInBrowse ?? true)
        // 英文关键词同达
        XCTAssertTrue(
            SettingsCatalog.search("doctor").contains {
                $0.id == "healthCheck"
            }
        )
    }

    /// H2-a（台账 159）：语音条目——标题直搜命中；
    /// 台账 198 收敛 S13 归组再裁：自服务器组维护尾
    /// 段迁偏好与权限组（回复呈现偏好、与外观同族），
    /// 浏览态直达不变
    func testVoiceEntryIsSearchable() {
        let hits = SettingsCatalog.search("语音")
        XCTAssertEqual(hits.first?.id, "voice")
        XCTAssertEqual(hits.first?.destination, .voice)
        XCTAssertEqual(hits.first?.group, .preferences)
        XCTAssertTrue(hits.first?.showsInBrowse ?? false)
        // 朗读关键词同达
        XCTAssertTrue(
            SettingsCatalog.search("朗读").contains {
                $0.id == "voice"
            }
        )
    }

    /// 配对一期（台账 153/160）：添加设备条目——标
    /// 题直搜命中；台账 198 收敛 S13：自维护尾段迁
    /// 服务器段（连接引导、与当前服务器同段）；扫码
    /// 关键词同达；§450 收纳：根页不再平铺（入口收
    /// 进当前服务器页内），本条目仅搜索可达
    func testAddDeviceEntryIsSearchable() {
        let hits = SettingsCatalog.search("添加设备")
        XCTAssertEqual(hits.first?.id, "addDevice")
        XCTAssertEqual(hits.first?.destination, .addDevice)
        XCTAssertEqual(hits.first?.group, .serverAndWorkspace)
        XCTAssertEqual(hits.first?.segment, .server)
        XCTAssertFalse(hits.first?.showsInBrowse ?? true)
        XCTAssertTrue(
            SettingsCatalog.search("扫码").contains {
                $0.id == "addDevice"
            }
        )
    }

    /// H5（台账 35）＋§450：设备配对条目（原名「平
    /// 台用户配对」）——新名标题直搜命中、旧名经搜
    /// 索别名同达；与添加设备管辖不同（两物分清的
    /// 机器面）；§450 收纳后仅搜索可达（入口在当前
    /// 服务器页内）；白名单关键词同达
    func testPairingEntryIsSearchable() {
        let hits = SettingsCatalog.search("设备配对")
        XCTAssertEqual(hits.first?.id, "pairing")
        XCTAssertEqual(hits.first?.destination, .pairingManagement)
        XCTAssertEqual(hits.first?.group, .serverAndWorkspace)
        XCTAssertEqual(hits.first?.segment, .server)
        XCTAssertFalse(hits.first?.showsInBrowse ?? true)
        // 旧名经搜索别名同达（§450：用户可见面全换
        // 新名、旧词只留搜索别名）
        XCTAssertTrue(
            SettingsCatalog.search("平台用户配对").contains {
                $0.id == "pairing"
            }
        )
        XCTAssertTrue(
            SettingsCatalog.search("白名单").contains {
                $0.id == "pairing"
            }
        )
        // 与添加设备分清：扫码只达设备入驻、不搭本条目
        XCTAssertFalse(
            SettingsCatalog.search("扫码").contains {
                $0.id == "pairing"
            }
        )
    }

    /// §450 改名钉（R1）：五条新题逐字在位（目录题
    /// ＝行题＝页题，一物一名）；旧名经搜索别名仍达
    /// 同一条目（用户按旧叫法搜不扑空——旧词只留
    /// 搜索别名、用户可见面全换新名）
    func testSettingsIARenamedEntries() {
        let byId = Dictionary(
            uniqueKeysWithValues: SettingsCatalog.entries.map {
                ($0.id, $0)
            }
        )
        // §493 改名三条：档案→配置档案、任务委派→
        // 子任务、密钥→服务器密钥
        XCTAssertEqual(byId["profiles"]?.title, "配置档案")
        XCTAssertEqual(byId["toolsets"]?.title, "工具")
        XCTAssertEqual(byId["delegation"]?.title, "子任务")
        XCTAssertEqual(byId["envVars"]?.title, "服务器密钥")
        XCTAssertEqual(byId["pairing"]?.title, "设备配对")
        XCTAssertEqual(byId["mainSession"]?.title, "主线对话")
        for (alias, id) in [
            ("档案", "profiles"), ("工具集", "toolsets"),
            ("任务委派", "delegation"), ("委派路由", "delegation"),
            ("密钥", "envVars"),
            ("平台用户配对", "pairing"),
            ("主线会话", "mainSession"),
        ] {
            XCTAssertTrue(
                SettingsCatalog.search(alias).contains {
                    $0.id == id
                },
                "旧名 \(alias) 应经别名达 \(id)"
            )
        }
    }

    /// §450 根行对账钉：目录条目 35→34（服务端会话
    /// 整条退役）；各组浏览行——智能体 7／服务与工
    /// 作区 14→9／偏好 6／支持 2／顶层 0，浏览行合
    /// 计 24；根页渲染行＝浏览行＋手写断开行 1＝25
    /// （改前 29，净减 4：配对收纳 2＋工具降级 2）；
    /// §470（S5-11 打包改）再减：服务与工作区 9→6
    /// （状态/用量/主线对话三行移出），浏览行合计
    /// 21、根页渲染行 22，条目总数不变（34，只移
    /// 落点不删条目）
    func testRootBrowseCountsAfterSettingsIA() {
        // §493 再减：条目 34→30（退役四条）、浏览行
        // 21→16、根页渲染行 22→17（浏览 16＋手写断
        // 开行 1）、可见段 6→5；§496：手写断开行迁
        // 出根页（住当前服务器页页末），根页渲染行
        // 17→16＝浏览行合计、与目录逐字一致（本测
        // 浏览口径不变）
        // §503 再增：条目 30→32（语言/互动两叶子页
        // 自外观页拆出独立条目）、偏好组浏览行 5→7、
        // 浏览行合计 16→18；根页渲染行＝浏览行合计
        // （§496 后无手写行、逐字一致口径不变）
        XCTAssertEqual(SettingsCatalog.entries.count, 32)
        XCTAssertEqual(
            SettingsCatalog.browseEntries(in: .top).count, 0
        )
        XCTAssertEqual(
            SettingsCatalog.browseEntries(in: .agent).count, 7
        )
        XCTAssertEqual(
            SettingsCatalog.browseEntries(
                in: .serverAndWorkspace
            ).count,
            2
        )
        XCTAssertEqual(
            SettingsCatalog.browseEntries(in: .preferences).count,
            7
        )
        XCTAssertEqual(
            SettingsCatalog.browseEntries(in: .support).count, 2
        )
    }

    /// §493（D1）：状态条目整条退役——汇总页本体
    /// 删（独有系统段 rehousing 网关页、活动/定时各
    /// 有正主）；搜「状态」达网关状态条目、无 status
    /// 条目残留；目的地本体保留备查（沿革见目录注）
    func testStatusEntryRetiredIn482() {
        XCTAssertFalse(
            SettingsCatalog.entries.contains { $0.id == "status" }
        )
        let hits = SettingsCatalog.search("状态")
        XCTAssertTrue(hits.contains { $0.id == "gateway" })
        XCTAssertFalse(hits.contains { $0.id == "status" })
    }

    /// §493（维护段撤销）：服务器密钥/体检仅搜索可
    /// 达钉——根页不平铺、搜索直达（入口正主在当前
    /// 服务器页「服务器管理」组，App 层
    /// ServerDetailView，本钉只管目录面）
    func testServerAdminEntriesAreSearchOnly() {
        let keyHits = SettingsCatalog.search("密钥")
        XCTAssertEqual(keyHits.first?.id, "envVars")
        XCTAssertEqual(keyHits.first?.title, "服务器密钥")
        XCTAssertFalse(keyHits.first?.showsInBrowse ?? true)
        let healthHits = SettingsCatalog.search("体检")
        XCTAssertEqual(healthHits.first?.id, "healthCheck")
        XCTAssertFalse(healthHits.first?.showsInBrowse ?? true)
    }

    /// §470（S5-11 打包改）：用量条目——移出根页、
    /// 仅搜索可达（入口收进网关状态页内，页内行在
    /// App 层 GatewayView，本钉只管目录面）；英文
    /// 关键词同达
    func testUsageEntryIsSearchOnly() {
        let hits = SettingsCatalog.search("用量")
        XCTAssertEqual(hits.first?.id, "usage")
        XCTAssertEqual(hits.first?.destination, .usage)
        XCTAssertEqual(hits.first?.group, .serverAndWorkspace)
        XCTAssertFalse(hits.first?.showsInBrowse ?? true)
        XCTAssertTrue(
            SettingsCatalog.search("usage").contains {
                $0.id == "usage"
            }
        )
    }

    /// §470（S5-11 打包改）：主线对话——改深链呈
    /// 现：条目保留、搜索（含旧名别名）直达详情页、
    /// 根页不平铺；「会话」段随之整段撤销（S5-06
    /// 独段问题同销）
    func testMainSessionEntryIsDeepLinkOnly() {
        let hits = SettingsCatalog.search("主线对话")
        XCTAssertEqual(hits.first?.id, "mainSession")
        XCTAssertEqual(hits.first?.destination, .mainSession)
        XCTAssertFalse(hits.first?.showsInBrowse ?? true)
        XCTAssertTrue(
            SettingsCatalog.search("主线会话").contains {
                $0.id == "mainSession"
            }
        )
        XCTAssertFalse(
            SettingsCatalog.browseSegments(in: .serverAndWorkspace)
                .contains { $0.segment == .sessions },
            "§470：根页会话段应整段撤销"
        )
    }
}
