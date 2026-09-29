import XCTest
@testable import AkashicZoteroImport

/// #606：`ZoteroStorageFile`——把附件記錄的 `storage/<KEY>/<檔名>` 解成 Zotero 資料目錄裡的一個普通檔，或具名拒絕。
///
/// 路徑取自 store 的 YAML（`attachments` 的 path 只驗是字串，任何人手改都能寫成 `../../etc/passwd`），所以這是**未信任輸入**：
/// 複製它的位元組進 `sources/` 之前，要先確認它真的是資料目錄的 `storage/` 底下的一個普通檔。
final class ZoteroStorageFileTests: XCTestCase {
    var dir: URL!
    var storage: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("akashic-zsf-\(UUID().uuidString)")
        storage = dir.appendingPathComponent("storage")
        try FileManager.default.createDirectory(at: storage.appendingPathComponent("ABCD1234"), withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: dir) }

    private func put(_ rel: String, _ text: String) throws {
        let url = dir.appendingPathComponent(rel)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
    }

    private func refusal(_ path: String) -> ZoteroStorageFile.Refusal? {
        if case .refused(let r) = ZoteroStorageFile.locate(dataDir: dir, attachmentPath: path) { return r }
        return nil
    }

    func testARegularFileUnderStorageIsLocated() throws {
        try put("storage/ABCD1234/paper.pdf", "%PDF-1.7 hello")
        guard case .found(let f) = ZoteroStorageFile.locate(dataDir: dir, attachmentPath: "storage/ABCD1234/paper.pdf") else {
            return XCTFail("普通檔應該定位得到")
        }
        XCTAssertEqual(f.bytes, 14)
        XCTAssertEqual(f.url.lastPathComponent, "paper.pdf")
        XCTAssertNotNil(f.modified)
    }

    func testMissingFileIsNamedNotThrown() {
        XCTAssertEqual(refusal("storage/ABCD1234/absent.pdf"), .missing)
        XCTAssertEqual(refusal("storage/NOSUCHKEY/paper.pdf"), .missing)
    }

    func testEmptyFileIsRefused() throws {
        try put("storage/ABCD1234/empty.pdf", "")
        XCTAssertEqual(refusal("storage/ABCD1234/empty.pdf"), .empty)
    }

    /// 路徑形狀：恰好 `storage/<KEY>/<檔名>` 三段，沒有 `..`、`.`、空段、絕對路徑、NUL。任何一種都不進檔案系統。
    func testPathsThatAreNotStorageKeyFilenameAreRefusedBeforeTouchingTheFilesystem() throws {
        try put("secret.txt", "outside storage")
        for bad in ["../secret.txt", "storage/../secret.txt", "storage/ABCD1234/../../secret.txt", "/etc/hosts",
                    "storage/ABCD1234", "storage//paper.pdf", "storage/ABCD1234/", "storage/./paper.pdf",
                    "attachments/ABCD1234/paper.pdf", "storage/ABCD1234/sub/paper.pdf", "", "storage/AB\u{0}CD/paper.pdf"] {
            XCTAssertEqual(refusal(bad), .badPath, "「\(bad)」不是 storage/<KEY>/<檔名>")
        }
    }

    func testADirectoryInPlaceOfTheFileIsRefused() throws {
        try FileManager.default.createDirectory(at: storage.appendingPathComponent("ABCD1234/folder.pdf"), withIntermediateDirectories: true)
        XCTAssertEqual(refusal("storage/ABCD1234/folder.pdf"), .notRegularFile("目錄"))
    }

    /// symlink 不跟：Zotero 不在 `storage/` 底下建 symlink，出現一個就是有人動過——它可以指到任何地方（`~/.ssh/id_rsa`），
    /// 跟著走等於把資料目錄外的檔案位元組讀進 `sources/`。
    func testASymlinkIsRefusedEvenWhenItPointsInsideStorage() throws {
        try put("storage/ABCD1234/real.pdf", "%PDF real")
        try FileManager.default.createSymbolicLink(at: storage.appendingPathComponent("ABCD1234/link.pdf"),
                                                   withDestinationURL: storage.appendingPathComponent("ABCD1234/real.pdf"))
        XCTAssertEqual(refusal("storage/ABCD1234/link.pdf"), .notRegularFile("symlink"))
    }

    /// 整個 KEY 目錄是指向資料目錄外的 symlink：檔案本身是普通檔，但它的真實位置在 `storage/` 之外。
    func testAKeyDirectorySymlinkedOutsideStorageIsRefused() throws {
        try put("elsewhere/paper.pdf", "%PDF elsewhere")
        try FileManager.default.createSymbolicLink(at: storage.appendingPathComponent("LINKKEY1"),
                                                   withDestinationURL: dir.appendingPathComponent("elsewhere"))
        XCTAssertEqual(refusal("storage/LINKKEY1/paper.pdf"), .outsideStorage)
    }

    /// `storage/` 本身是 symlink（把 Zotero 儲存區放到別的磁碟是常見用法）：合法，內容要讀得到。
    func testStorageDirectoryItselfBeingASymlinkIsFine() throws {
        let real = dir.appendingPathComponent("realstorage")
        try FileManager.default.createDirectory(at: real.appendingPathComponent("KEYAAAA1"), withIntermediateDirectories: true)
        try Data("%PDF via linked storage".utf8).write(to: real.appendingPathComponent("KEYAAAA1/x.pdf"))
        let data2 = dir.appendingPathComponent("data2")
        try FileManager.default.createDirectory(at: data2, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: data2.appendingPathComponent("storage"), withDestinationURL: real)
        guard case .found(let f) = ZoteroStorageFile.locate(dataDir: data2, attachmentPath: "storage/KEYAAAA1/x.pdf") else {
            return XCTFail("storage/ 本身是 symlink 時仍要讀得到")
        }
        XCTAssertEqual(f.bytes, 23)
    }

    // MARK: 讀（#606 R1 verify）：定位之後、讀取之前被換掉的東西不跟

    private func located(_ path: String) throws -> ZoteroStorageFile.Located {
        guard case .found(let f) = ZoteroStorageFile.locate(dataDir: dir, attachmentPath: path) else {
            XCTFail("前提：\(path) 要定位得到")
            throw CocoaError(.fileNoSuchFile)
        }
        return f
    }

    func testReadReturnsTheBytesOfALocatedFile() throws {
        try put("storage/ABCD1234/paper.pdf", "%PDF-1.7 hello")
        let f = try located("storage/ABCD1234/paper.pdf")
        XCTAssertEqual(ZoteroStorageFile.read(dataDir: dir, located: f), .data(Data("%PDF-1.7 hello".utf8)))
    }

    /// 定位之後檔案被換成 symlink（指到資料目錄外）：以路徑重讀會跟過去；從 descriptor 讀的版本以 `O_NOFOLLOW` 拒絕。
    func testAFileSwappedForASymlinkAfterLocateIsRefused() throws {
        try put("storage/ABCD1234/paper.pdf", "%PDF-1.7 hello")
        try put("secret.txt", "outside storage")
        let f = try located("storage/ABCD1234/paper.pdf")
        try FileManager.default.removeItem(at: f.url)
        try FileManager.default.createSymbolicLink(at: f.url, withDestinationURL: dir.appendingPathComponent("secret.txt"))
        XCTAssertEqual(ZoteroStorageFile.read(dataDir: dir, located: f), .refused(.notRegularFile("symlink")))
    }

    /// 定位之後 KEY 目錄被換成指出去的 symlink（裡面有同名的檔）：最後一段是普通檔、`O_NOFOLLOW` 擋不到，
    /// 要靠 kernel 回報的真實位置擋。
    func testAKeyDirectorySwappedOutsideStorageAfterLocateIsRefused() throws {
        try put("storage/ABCD1234/paper.pdf", "%PDF-1.7 hello")
        try put("elsewhere/paper.pdf", "%PDF elsewhere")
        let f = try located("storage/ABCD1234/paper.pdf")
        try FileManager.default.removeItem(at: storage.appendingPathComponent("ABCD1234"))
        try FileManager.default.createSymbolicLink(at: storage.appendingPathComponent("ABCD1234"),
                                                   withDestinationURL: dir.appendingPathComponent("elsewhere"))
        XCTAssertEqual(ZoteroStorageFile.read(dataDir: dir, located: f), .refused(.outsideStorage))
    }

    /// 換進來的是 FIFO：開啟不能卡住（`O_NONBLOCK`），以種類拒絕。
    func testAFifoSwappedInIsRefusedWithoutBlocking() throws {
        try put("storage/ABCD1234/paper.pdf", "%PDF-1.7 hello")
        let f = try located("storage/ABCD1234/paper.pdf")
        try FileManager.default.removeItem(at: f.url)
        XCTAssertEqual(mkfifo(f.url.path, 0o644), 0)
        XCTAssertEqual(ZoteroStorageFile.read(dataDir: dir, located: f), .refused(.notRegularFile("特殊檔案")))
    }

    /// 定位之後被清空：不存 0 byte 的內容。
    func testAFileTruncatedAfterLocateIsRefusedAsEmpty() throws {
        try put("storage/ABCD1234/paper.pdf", "%PDF-1.7 hello")
        let f = try located("storage/ABCD1234/paper.pdf")
        try Data().write(to: f.url)
        XCTAssertEqual(ZoteroStorageFile.read(dataDir: dir, located: f), .refused(.empty))
    }

    /// `storage/` 本身是 symlink 時，兩邊都經 kernel 問真實位置，仍讀得到。
    func testReadThroughALinkedStorageDirectory() throws {
        let real = dir.appendingPathComponent("realstorage")
        try FileManager.default.createDirectory(at: real.appendingPathComponent("KEYAAAA1"), withIntermediateDirectories: true)
        try Data("%PDF via linked storage".utf8).write(to: real.appendingPathComponent("KEYAAAA1/x.pdf"))
        let data2 = dir.appendingPathComponent("data2")
        try FileManager.default.createDirectory(at: data2, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: data2.appendingPathComponent("storage"), withDestinationURL: real)
        guard case .found(let f) = ZoteroStorageFile.locate(dataDir: data2, attachmentPath: "storage/KEYAAAA1/x.pdf") else {
            return XCTFail("前提：定位得到")
        }
        XCTAssertEqual(ZoteroStorageFile.read(dataDir: data2, located: f), .data(Data("%PDF via linked storage".utf8)))
    }

    func testMediaTypeFollowsTheExtensionAndFallsBackToOctetStream() {
        XCTAssertEqual(ZoteroStorageFile.mediaType(forFilename: "Paper.PDF"), "application/pdf")
        XCTAssertEqual(ZoteroStorageFile.mediaType(forFilename: "snapshot.html"), "text/html")
        XCTAssertEqual(ZoteroStorageFile.mediaType(forFilename: "book.epub"), "application/epub+zip")
        XCTAssertEqual(ZoteroStorageFile.mediaType(forFilename: "noext"), "application/octet-stream")
        XCTAssertEqual(ZoteroStorageFile.mediaType(forFilename: "weird.zzz"), "application/octet-stream")
    }
}
