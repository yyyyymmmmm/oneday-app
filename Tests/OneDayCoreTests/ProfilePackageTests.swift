import XCTest
@testable import OneDayCore

/// §393（台账 165）智能体成包纯逻辑钉测：包清
/// 单真解包（fixture 为真实 tar.gz：testprofile/
/// 下 SOUL.md 37B＋config.yaml 29B＋skills/demo
/// -skill/SKILL.md 13B，目录共 3、文件共 3）、坏
/// 包拒绝、文件名推断、导入名校验、装包路径口径
final class ProfilePackageTests: XCTestCase {

    /// 真包 fixture（tar -czf 生成，结构见上注）
    private let fixtureBase64 =
        "H4sIAAAAAAAAA+3WMWuEMBgGYGd/xQc3nzWaKNzcpfSgBduhY6i5QxpN0Tj03zc6ibTKUbX0+j5LggYSePMlsaqx77U5FVrdeCsJnTQN+9YZt32fidgNYokIhReyiLHYI7HWgobaxsqayKuNsVPj5v7/UXaQ/6upTsU5+JClXnSOLuAkmcg/FqP8ecRd/uGiq/jGP8+/NLnSB58oVyfZanugbkfs+8/+by8OVjes/+zh+RiU+eJzzNY/H9d/HLEU9b+FHT25HUCPqm5MJf0X05KsFcn+GCB5VpUNcA5cr2H9N2+F1s3yz8DL338xZxzvvy18kX+uSrPv+wtthcvzF1wg/01M55/d3x1//iSYvf/Z+P5PEsFw/29hR7cubsq6uHHPAwAAAAAAAAAAAABch08o9S67ACgAAA=="

    /// 坏包 fixture：两个顶层目录（alpha/＋beta/），
    /// 上游 import 同口径拒绝（archive root 不唯一）
    private let twoTopBase64 =
        "H4sIAAAAAAAAA+3VSwrCMBSF4SwlK9Ck5rGeFAQHQqVGqLs3jRPpoELxGsT/mySQDG44cJLOl1PaK1GmiNHUtViudW/9oVyysXNRGWuCc0p72bGebtecRq3VOAx57d678x+Vav5plye5180Bh7CWv13kb4P1ShuxiV78ef5T6wHQVH/M0vW/pf9d7Oj/b6j596L1v6X/3fz/0//y7q0HAAAAAAAAAAAAAAB8xAP178jUACgAAA=="

    private func fixtureData() -> Data {
        Data(base64Encoded: fixtureBase64)!
    }

    func testManifestParsesRealPackage() {
        let manifest = ProfilePackage.manifest(
            tarGz: fixtureData()
        )
        let m = try! XCTUnwrap(manifest)
        XCTAssertEqual(m.profileName, "testprofile")
        XCTAssertEqual(m.entryCount, 6)
        XCTAssertEqual(m.fileCount, 3)
        XCTAssertEqual(m.totalFileBytes, 79)
        XCTAssertTrue(m.hasSoul)
        XCTAssertTrue(m.hasConfig)
        XCTAssertEqual(m.previewEntries.first, "testprofile")
        XCTAssertTrue(
            m.previewEntries.contains(
                "testprofile/skills/demo-skill/SKILL.md"
            )
        )
    }

    func testManifestRejectsTwoTopLevels() {
        XCTAssertNil(
            ProfilePackage.manifest(
                tarGz: Data(base64Encoded: twoTopBase64)!
            )
        )
    }

    func testManifestRejectsNonGzip() {
        XCTAssertNil(
            ProfilePackage.manifest(
                tarGz: Data("not a package".utf8)
            )
        )
        XCTAssertNil(
            ProfilePackage.manifest(tarGz: Data())
        )
    }

    func testGunzipRejectsTruncated() {
        let full = fixtureData()
        XCTAssertNil(
            ProfilePackage.gunzip(Data(full.prefix(40)))
        )
        XCTAssertNotNil(ProfilePackage.gunzip(full))
    }

    func testInferredNameStripsTimestamp() {
        XCTAssertEqual(
            ProfilePackage.inferredName(
                fromFileName: "my-agent-20261123-093015.tar.gz"
            ),
            "my-agent"
        )
        XCTAssertEqual(
            ProfilePackage.inferredName(
                fromFileName: "/tmp/x/plain.tgz"
            ),
            "plain"
        )
        XCTAssertEqual(
            ProfilePackage.inferredName(
                fromFileName: "noext-20260101-000000"
            ),
            "noext"
        )
        XCTAssertNil(
            ProfilePackage.inferredName(
                fromFileName: "-20261123-093015.tar.gz"
            )
        )
    }

    func testImportNameVerdict() {
        XCTAssertEqual(
            ProfilePackage.importNameVerdict(
                "newone", existingNames: ["a"]
            ),
            .ok
        )
        XCTAssertEqual(
            ProfilePackage.importNameVerdict(
                "  ", existingNames: []
            ),
            .empty
        )
        XCTAssertEqual(
            ProfilePackage.importNameVerdict(
                "default", existingNames: []
            ),
            .reservedDefault
        )
        XCTAssertEqual(
            ProfilePackage.importNameVerdict(
                "a", existingNames: ["a", "b"]
            ),
            .alreadyExists
        )
    }

    func testUploadRelativePathSanitizes() {
        XCTAssertEqual(
            ProfilePackage.uploadRelativePath(
                fileName: "x-20261123-093015.tar.gz"
            ),
            "profile-exports/x-20261123-093015.tar.gz"
        )
        XCTAssertEqual(
            ProfilePackage.uploadRelativePath(
                fileName: "/evil/path/p.tar.gz"
            ),
            "profile-exports/p.tar.gz"
        )
    }
}
