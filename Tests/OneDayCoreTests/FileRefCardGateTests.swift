import Foundation
import XCTest
@testable import OneDayCore

/// §129 文件牌 404 修复钉测（诊断 file-ref-404-
/// diagnosis-20261111）：三类坏牌样本逐类钉死——
/// 截断假路径（主因 B）、域名片段误报（主因 B
/// 之二）、拟议/设备路径成牌（主因 A/C）；成牌
/// 口（单独成行＋下载根内）与原始扫描口分层，两
/// 口各自的口径都钉住防漂移。
final class FileRefCardGateTests: XCTestCase {

    // MARK: - 主因 B：探测器截断 bug

    /// 生产实证（消息 1201/1223）：文件名中段带
    /// 「.数字-」时懒惰匹配提前收尾，真文件被截
    /// 成假路径并成一张牌——修后整条命中、两份真
    /// 文件各是一条
    func testTruncatedVersionedNamesDetectedWhole() {
        let text = """
        核实完了，两份文件都在：
        /opt/data/kimi-k3.1-pro-权重核实与补丁.md
        /opt/data/kimi-k3.1-pro-patch.txt
        """
        XCTAssertEqual(
            FileRefDetector.detect(in: text),
            [
                "/opt/data/kimi-k3.1-pro-权重核实与补丁.md",
                "/opt/data/kimi-k3.1-pro-patch.txt",
            ]
        )
        // 截断形态本身不许再单独出现
        XCTAssertFalse(
            FileRefDetector.detect(in: text)
                .contains("/opt/data/kimi-k3.1")
        )
    }

    /// 域名片段护栏：URL 写一半（无 scheme）时，
    /// 域名后的路径段不是服务端文件——前一字符是
    /// 字母/数字/. 时同样跳过，不只排冒号
    func testDomainFragmentNotDetected() {
        XCTAssertTrue(
            FileRefDetector.detect(
                in: "模型页在 huggingface.co/moonshotai/Kimi-K3.1-Pro 上"
            ).isEmpty
        )
        XCTAssertTrue(
            FileRefDetector.detectStandaloneAnchored(
                in: "huggingface.co/moonshotai/Kimi-K3.1-Pro"
            ).isEmpty
        )
    }

    /// 既有护栏不回退：版本串仍不成路径
    func testVersionStringStillNotDetected() {
        XCTAssertTrue(
            FileRefDetector.detect(in: "当前版本 1.2.3 已发布").isEmpty
        )
        XCTAssertTrue(
            FileRefDetector.detectStandaloneAnchored(
                in: "当前版本 1.2.3 已发布"
            ).isEmpty
        )
    }

    // MARK: - 成牌口：单独成行

    /// 真交付形态（SOUL 约定：路径单独成行）够格
    /// 成牌；列表符/引用符/反引号/粗体一层包裹同认
    func testStandaloneLineFormsCardCandidate() {
        let text = """
        文件已经保存好：
        /opt/data/通讯录人数口径.md
        请查收。
        """
        XCTAssertEqual(
            FileRefDetector.detectStandaloneAnchored(in: text)
                .map(\.path),
            ["/opt/data/通讯录人数口径.md"]
        )
        for wrapped in [
            "- /opt/data/报告.md",
            "> /opt/data/报告.md",
            "`/opt/data/报告.md`",
            "**/opt/data/报告.md**",
        ] {
            XCTAssertEqual(
                FileRefDetector.detectStandaloneAnchored(in: wrapped)
                    .map(\.path),
                ["/opt/data/报告.md"], wrapped
            )
        }
    }

    /// 单独成行带 #L 锚点：锚点照常单列、路径干净
    func testStandaloneAnchorPreserved() {
        let refs = FileRefDetector.detectStandaloneAnchored(
            in: "改好的脚本：\n/opt/data/tools/fix.py#L5-L9\n"
        )
        XCTAssertEqual(refs.count, 1)
        XCTAssertEqual(refs.first?.path, "/opt/data/tools/fix.py")
        XCTAssertEqual(
            refs.first?.anchor,
            FileLineAnchor(startLine: 5, endLine: 9)
        )
    }

    /// 主因 A（生产消息 1268）：句中拟议路径——
    /// 「我打算存成 X，你确认我就保存」——行内提及
    /// 不成牌，哪怕路径在下载根内、形态完全合法
    func testInlineProposedPathDoesNotFormCard() {
        let text = "保存位置：本机没有装笔记软件，我打算存成 "
            + "**/opt/data/notes/通讯录-总人数.md** 这个纯文本文件。"
            + "你回复“可以”，我就按这段保存。"
        XCTAssertTrue(
            FileRefDetector.detectStandaloneAnchored(in: text)
                .isEmpty
        )
        // 原始扫描口仍如实报出（分层口径：扫描归扫
        // 描、成牌归成牌，坏牌死在成牌口而非扫描口）
        XCTAssertEqual(
            FileRefDetector.detect(in: text),
            ["/opt/data/notes/通讯录-总人数.md"]
        )
    }

    /// 一行里两条路径、或路径后还跟着说明字：都
    /// 不是「单独成行」，不成牌
    func testCrowdedLineDoesNotFormCard() {
        XCTAssertTrue(
            FileRefDetector.detectStandaloneAnchored(
                in: "/opt/data/a.md /opt/data/b.md"
            ).isEmpty
        )
        XCTAssertTrue(
            FileRefDetector.detectStandaloneAnchored(
                in: "- /opt/data/a.md（先看这份）"
            ).isEmpty
        )
    }

    /// 成牌口去重与排除表与扫描口同口径
    func testStandaloneDedupAndExcluding() {
        let text = "/opt/data/a.md\n/opt/data/a.md\n/opt/data/b.txt"
        XCTAssertEqual(
            FileRefDetector.detectStandaloneAnchored(in: text)
                .map(\.path),
            ["/opt/data/a.md", "/opt/data/b.txt"]
        )
        XCTAssertEqual(
            FileRefDetector.detectStandaloneAnchored(
                in: text, excluding: ["/opt/data/a.md"]
            ).map(\.path),
            ["/opt/data/b.txt"]
        )
    }

    // MARK: - 主因 C：下载根收紧

    /// 设备路径（生产消息 1012）哪怕单独成行也
    /// 不成牌：不在服务端下载根内、天然不可下载
    func testStandaloneDevicePathRejectedByRoot() {
        let devicePath = "/private/var/containers/Bundle/"
            + "Application/ABC123/com.apple.MobileGestalt.plist"
        XCTAssertTrue(
            FileRefDetector.detectStandaloneAnchored(in: devicePath)
                .isEmpty
        )
        XCTAssertTrue(
            FileRefDetector.detectStandaloneAnchored(
                in: "路径是 \(devicePath)，在手机上。"
            ).isEmpty
        )
    }

    func testDownloadRootPredicate() {
        XCTAssertTrue(
            FileRefDetector.isInDownloadRoot("/opt/data/a.md")
        )
        XCTAssertTrue(
            FileRefDetector.isInDownloadRoot(
                "/opt/data/notes/通讯录-总人数.md"
            )
        )
        // 根外、根的兄弟目录（前缀陷阱）、穿越段
        XCTAssertFalse(FileRefDetector.isInDownloadRoot("/opt/data"))
        XCTAssertFalse(
            FileRefDetector.isInDownloadRoot("/opt/database/a.md")
        )
        XCTAssertFalse(
            FileRefDetector.isInDownloadRoot("/private/var/x.plist")
        )
        XCTAssertFalse(
            FileRefDetector.isInDownloadRoot("/opt/data/../secret.md")
        )
    }

    /// 拟议路径若真单独成行，Core 成牌口放行——
    /// 它死不死由 App 层存在性校验判（分层钉死：
    /// 本案 1268 是行内提及死在成牌口；单独成行
    /// 的未落盘路径死在存在性校验，不许 Core 越
    /// 权假装知道文件在不在）
    func testStandaloneRootPathIsCandidateForExistenceGate() {
        XCTAssertEqual(
            FileRefDetector.detectStandaloneAnchored(
                in: "/opt/data/notes/通讯录-总人数.md"
            ).map(\.path),
            ["/opt/data/notes/通讯录-总人数.md"]
        )
    }

    // MARK: - 重新发预填

    func testResendPrefillContent() {
        let text = FileResendPrefill.make(
            name: "通讯录-总人数.md",
            path: "/opt/data/notes/通讯录-总人数.md"
        )
        XCTAssertTrue(text.contains("《通讯录-总人数.md》"))
        XCTAssertTrue(
            text.contains("/opt/data/notes/通讯录-总人数.md")
        )
        XCTAssertTrue(text.contains("单独写一行"))
        XCTAssertTrue(text.contains("确认真的存在"))
    }
}
