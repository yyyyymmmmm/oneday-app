import XCTest
@testable import OneDayCore

/// 0.36.29（文件真发送，契约 file-upload-contract-
/// 20261111 冻结口径）：拼装纯逻辑钉死——落点相对
/// 路径、data_url、@file 引用（含空格/括号引号规
/// 则）、文本尾多文件顺序拼接
final class FileSendAssemblyTests: XCTestCase {

    func testUploadPathUnderAttachments() {
        XCTAssertEqual(
            FileSendAssembly.uploadPath(fileName: "报告.pdf"),
            "attachments/报告.pdf"
        )
    }

    func testUploadPathStripsDirectoryPrefix() {
        XCTAssertEqual(
            FileSendAssembly.uploadPath(fileName: "a/b/notes.txt"),
            "attachments/notes.txt"
        )
    }

    func testDataURLCarriesMimeAndBase64() {
        let url = FileSendAssembly.dataURL(
            fileName: "notes.txt", data: Data("hi".utf8)
        )
        XCTAssertEqual(url, "data:text/plain;base64,aGk=")
    }

    func testFileRefPlainPathUnquoted() {
        XCTAssertEqual(
            FileSendAssembly.fileRef(
                serverPath: "/opt/data/attachments/a.txt"
            ),
            "@file:/opt/data/attachments/a.txt"
        )
    }

    func testFileRefQuotesSpaceAndParens() {
        XCTAssertEqual(
            FileSendAssembly.fileRef(
                serverPath: "/opt/data/attachments/my file.txt"
            ),
            "@file:\"/opt/data/attachments/my file.txt\""
        )
        XCTAssertEqual(
            FileSendAssembly.fileRef(
                serverPath: "/opt/data/attachments/a(1).txt"
            ),
            "@file:\"/opt/data/attachments/a(1).txt\""
        )
    }

    func testAppendingRefsKeepsOrderAndText() {
        let text = FileSendAssembly.appendingFileRefs(
            to: "看一下这两个文件",
            serverPaths: [
                "/opt/data/attachments/a.txt",
                "/opt/data/attachments/b.pdf",
            ]
        )
        XCTAssertEqual(
            text,
            "看一下这两个文件\n"
                + "@file:/opt/data/attachments/a.txt\n"
                + "@file:/opt/data/attachments/b.pdf"
        )
    }

    func testAppendingRefsEmptyTextHasNoLeadingBlank() {
        let text = FileSendAssembly.appendingFileRefs(
            to: "",
            serverPaths: ["/opt/data/attachments/a.txt"]
        )
        XCTAssertEqual(text, "@file:/opt/data/attachments/a.txt")
    }

    func testAppendingRefsNoFilesLeavesText() {
        XCTAssertEqual(
            FileSendAssembly.appendingFileRefs(
                to: "原文", serverPaths: []
            ),
            "原文"
        )
    }

    func testAppendingRefsToMultimodalTailKeepsImages() {
        let tail = ChatMessage(
            role: "user", text: "看图和文件",
            imageDataURLs: ["data:image/jpeg;base64,aGk="]
        )
        let assembled = FileSendAssembly.appendingFileRefs(
            to: tail,
            serverPaths: ["/opt/data/attachments/a.txt"]
        )
        XCTAssertEqual(
            assembled.content,
            "看图和文件\n@file:/opt/data/attachments/a.txt"
        )
        XCTAssertEqual(assembled.parts?.count, 2)
    }

    func testUploadReceiptPrefersEntryPath() throws {
        let json = """
        {"ok":true,
         "entry":{"name":"a.txt",
                  "path":"/opt/data/attachments/a.txt",
                  "is_directory":false,"size":3,
                  "mtime":1794342429.0,"mime_type":"text/plain"},
         "path":"/opt/data/attachments/a.txt"}
        """
        let receipt = try JSONDecoder().decode(
            ManagedFileUploadReceipt.self,
            from: Data(json.utf8)
        )
        XCTAssertEqual(
            receipt.serverPath, "/opt/data/attachments/a.txt"
        )
    }
}
