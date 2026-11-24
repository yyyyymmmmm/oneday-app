import XCTest
@testable import OneDayApp
import OneDayCore

/// §381 结构钉测：点子/目标两店实例单源把守——
/// ①两店裸构造点在生产源码（代码行，整行注释
/// 除外）中只许各一处、且必须落在 AppState 的
/// 懒建单例访问器所在文件；②AppState 单例形态
/// 在场（实例槽＋shared 访问器，与 §259 三店同
/// 形态）；③四消费面经 shared 访问器取店，不
/// 许回潮私建（第 75 条关账把守，收口本体见
/// §339 条 4）
final class StoresSingleSourceStructureTests: XCTestCase {

    private func repoRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func source(_ relative: String) throws -> String {
        try String(
            contentsOf: repoRoot()
                .appendingPathComponent(relative),
            encoding: .utf8
        )
    }

    /// 代码行视图：剔除整行注释（/// 与 //）——
    /// 历史 prose 提及不在禁列，禁的是代码本体
    private func codeLines(_ text: String) -> String {
        text.split(separator: "\n", omittingEmptySubsequences: false)
            .filter { line in
                let t = line.trimmingCharacters(
                    in: .whitespaces
                )
                return !t.hasPrefix("///") && !t.hasPrefix("//")
            }
            .joined(separator: "\n")
    }

    private func allSourceFiles() -> [URL] {
        var urls: [URL] = []
        for dir in [
            "Sources/OneDayApp",
            "Sources/OneDayCore",
            "Sources/OneDayDesign",
        ] {
            let base = repoRoot().appendingPathComponent(dir)
            guard let en = FileManager.default.enumerator(
                at: base,
                includingPropertiesForKeys: nil
            ) else { continue }
            for case let url as URL in en
            where url.pathExtension == "swift" {
                urls.append(url)
            }
        }
        return urls
    }

    /// 裸构造计数：「Token(」总出现减去
    /// 「sharedToken(」访问器口（后者是前者的
    /// 前缀命中，须扣除）
    private func bareConstructions(
        _ token: String, in code: String
    ) -> Int {
        let all = code.components(
            separatedBy: token + "("
        ).count - 1
        let shared = code.components(
            separatedBy: "shared" + token + "("
        ).count - 1
        return all - shared
    }

    /// 构造点单源：两店各只许 AppState 一处裸构造
    func testStoreConstructionOnlyInAppState() throws {
        let files = allSourceFiles()
        XCTAssertGreaterThan(
            files.count, 100,
            "源码文件数下限（防普查空过）"
        )
        var ideasTotal = 0
        var goalsTotal = 0
        for url in files {
            let text = try String(
                contentsOf: url, encoding: .utf8
            )
            let code = codeLines(text)
            let ideas = bareConstructions(
                "IdeasStore", in: code
            )
            let goals = bareConstructions(
                "GoalsStore", in: code
            )
            ideasTotal += ideas
            goalsTotal += goals
            if url.lastPathComponent == "AppState.swift" {
                XCTAssertEqual(
                    ideas, 1,
                    "AppState 内 IdeasStore 裸构造须恰 1 处"
                    + "（单例访问器内，实测 \(ideas)）"
                )
                XCTAssertEqual(
                    goals, 1,
                    "AppState 内 GoalsStore 裸构造须恰 1 处"
                    + "（单例访问器内，实测 \(goals)）"
                )
            } else {
                XCTAssertEqual(
                    ideas, 0,
                    "\(url.lastPathComponent) 私建 IdeasStore"
                    + "（实测 \(ideas) 处）——须走"
                    + " AppState.sharedIdeasStore()"
                )
                XCTAssertEqual(
                    goals, 0,
                    "\(url.lastPathComponent) 私建 GoalsStore"
                    + "（实测 \(goals) 处）——须走"
                    + " AppState.sharedGoalsStore()"
                )
            }
        }
        XCTAssertEqual(
            ideasTotal, 1,
            "IdeasStore 生产构造点须单源（实测 \(ideasTotal)）"
        )
        XCTAssertEqual(
            goalsTotal, 1,
            "GoalsStore 生产构造点须单源（实测 \(goalsTotal)）"
        )
    }

    /// AppState 单例形态在场（与 §259 三店同形态）
    func testAppStateSingletonFormPresent() throws {
        let appState = codeLines(
            try source("Sources/OneDayApp/AppState.swift")
        )
        for token in [
            "private var ideasStoreInstance",
            "func sharedIdeasStore()",
            "private var goalsStoreInstance",
            "func sharedGoalsStore()",
        ] {
            XCTAssertTrue(
                appState.contains(token),
                "AppState 单例形态缺件：\(token)"
            )
        }
    }

    /// 消费面口径：四面经 shared 访问器取店
    func testConsumerFacesUseSharedAccessors() throws {
        let ideasView = codeLines(
            try source("Sources/OneDayApp/IdeasView.swift")
        )
        XCTAssertTrue(
            ideasView.contains("sharedIdeasStore()"),
            "IdeasView 须经 sharedIdeasStore() 取店"
        )
        let goalsView = codeLines(
            try source("Sources/OneDayApp/GoalsView.swift")
        )
        XCTAssertTrue(
            goalsView.contains("sharedGoalsStore()"),
            "GoalsView 须经 sharedGoalsStore() 取店"
        )
        let feedView = codeLines(
            try source("Sources/OneDayApp/FeedView.swift")
        )
        XCTAssertTrue(
            feedView.contains("sharedIdeasStore()"),
            "FeedView 须经 sharedIdeasStore() 取店"
        )
        XCTAssertTrue(
            feedView.contains("sharedGoalsStore()"),
            "FeedView 须经 sharedGoalsStore() 取店"
        )
        let goalDetail = codeLines(
            try source(
                "Sources/OneDayApp/GoalDetailView.swift"
            )
        )
        XCTAssertTrue(
            goalDetail.contains("sharedIdeasStore()"),
            "GoalDetailView 须经 sharedIdeasStore() 取点子店"
        )
    }
}
