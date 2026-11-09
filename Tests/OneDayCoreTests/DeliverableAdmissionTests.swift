import OneDayCore
import XCTest

/// 交付物准入（0.22.0，视觉审计 F1 策展规格）：形态拦
/// 截＋根散白名单。拒收样本以 2026-11-10 00:12 用户实
/// 机图文件页首屏 9 个污染文件名为准钉死——它们曾靠
/// mtime 最新霸占交付物首屏，本测试保证其永不准入。
final class DeliverableAdmissionTests: XCTestCase {

    /// 00:12 实机首屏 9 个污染文件名：根散与产出根两处
    /// 都必须拒收
    func testRejectsScreenshotPollutantsEverywhere() {
        let pollutants = [
            "kanban.db-shm", "state.db-shm", "state.db-wal",
            "gateway_state.json", "kanban.db-wal",
            "channel_directory.json", "state.db",
            "models_dev_cache.etag", "models_dev_cache.json",
        ]
        for name in pollutants {
            XCTAssertFalse(
                DeliverableAdmission.isAdmitted(
                    name: name, isRootLooseFile: true
                ),
                "\(name) 不许从根目录准入"
            )
            XCTAssertFalse(
                DeliverableAdmission.isAdmitted(
                    name: name, isRootLooseFile: false
                ),
                "\(name) 不许从产出根准入"
            )
        }
    }

    /// 形态拦截的变体覆盖：后缀族与主干族各举变体，
    /// 不靠逐名名单
    func testRejectsInternalMorphologyVariants() {
        let variants = [
            "foo.sqlite", "foo.sqlite3", "x.lock", "x.pid",
            "draft.tmp", "sessions.json", "auth.json",
            "kanban.db", "state.txt", "config.json",
        ]
        for name in variants {
            XCTAssertFalse(
                DeliverableAdmission.isAdmitted(
                    name: name, isRootLooseFile: false
                ),
                "\(name) 应被形态拦截"
            )
        }
    }

    /// 隐藏文件全来源拒收（产出根内的 .DS_Store 类同理）
    func testRejectsHiddenFilesEverywhere() {
        XCTAssertFalse(
            DeliverableAdmission.isAdmitted(
                name: ".env", isRootLooseFile: true
            )
        )
        XCTAssertFalse(
            DeliverableAdmission.isAdmitted(
                name: ".DS_Store", isRootLooseFile: false
            )
        )
    }

    /// 根散白名单：以 Muse 图的交付形态为准入样本
    /// （DOCX/PPTX/HTML 等成品形态）
    func testAdmitsDeliverableExtensionsAtRoot() {
        let admitted = [
            "礼钱账本报告.docx", "AI基础培训课讲稿.pptx",
            "index.html", "报告.pdf", "数据表.xlsx",
            "截图.png", "成片.mp4", "讲稿.md", "合集.zip",
        ]
        for name in admitted {
            XCTAssertTrue(
                DeliverableAdmission.isAdmitted(
                    name: name, isRootLooseFile: true
                ),
                "\(name) 应从根目录准入"
            )
        }
    }

    /// 根散白名单的出局者：json 是数据管道非交付物、
    /// 无扩展名与未知扩展名同拒
    func testRejectsNonDeliverablesAtRoot() {
        let rejected = ["data.json", "notes", "script.py", "a.log"]
        for name in rejected {
            XCTAssertFalse(
                DeliverableAdmission.isAdmitted(
                    name: name, isRootLooseFile: true
                ),
                "\(name) 不应从根目录准入"
            )
        }
    }

    /// 产出根内不查扩展名白名单：根已是策展来源，生成
    /// 的 json 产物（如定时任务输出）在根内仍准入
    func testOutputRootsSkipExtensionWhitelist() {
        XCTAssertTrue(
            DeliverableAdmission.isAdmitted(
                name: "cron-result.json", isRootLooseFile: false
            )
        )
        XCTAssertTrue(
            DeliverableAdmission.isAdmitted(
                name: "中间稿.xyz", isRootLooseFile: false
            )
        )
    }
}
