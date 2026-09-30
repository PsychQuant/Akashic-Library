import XCTest
import CryptoKit
import Foundation
@testable import AkashicCore
@testable import AkashicMCPKit
@testable import AkashicStoreIO

/// #703 R2 verify 第 4、5、6、10、28 則的服務層（MCP 面讀的那一份 payload）：
///
/// - `akashic_store_source` 回 `bytesWritten`（這一次才存 vs 早就在），位址被佔住時具名拒絕、不寫 index；
/// - `akashic_doctor` 的 `sources` 帶 `occupantProblems`／`occupantProblemsTotal`，`strayTemporaryFiles` 每則帶 `ageSeconds` 與
///   `possiblyInProgress`（R2 之前只有 {path, bytes}，而 MCP 的讀者最可能照「stray」去刪正在進行的複製），總數在 `strayTemporaryFilesTotal`。
final class SourceAddressServiceTests: XCTestCase {
    private var root: URL!
    private var service: AkashicService!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("akashic-srcaddr-svc-\(UUID().uuidString)")
        try LibraryStore(root: root).ensureLayout()
        service = AkashicService(root: root)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    private func json(_ s: String) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: Data(s.utf8)) as? [String: Any])
    }
    private func digest(_ data: Data) -> String { "sha256:" + SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
    private func address(_ d: String) -> URL {
        let hex = String(d.dropFirst("sha256:".count))
        return root.appendingPathComponent("sources/\(hex.prefix(2))/\(hex.dropFirst(2))")
    }
    private func storeSource(_ data: Data) throws -> [String: Any] {
        let f = root.appendingPathComponent("in-\(UUID().uuidString).pdf")
        try data.write(to: f)
        defer { try? FileManager.default.removeItem(at: f) }
        return try json(try service.storeSource(path: f.path, mediaType: "application/pdf", retrieved: "2026-10-01",
                                                origin: "https://example.org/x.pdf", acquisition: "browser-download"))
    }

    func testStoreSourceTellsWhetherItWroteTheBytes() throws {
        let data = Data("%PDF-1.7 written now".utf8)
        XCTAssertEqual(try storeSource(data)["bytesWritten"] as? Bool, true)
        XCTAssertEqual(try storeSource(data)["bytesWritten"] as? Bool, false, "位址上早有大小相同的一份")
    }

    func testStoreSourceRefusesAnOccupiedAddress() throws {
        let data = Data("%PDF-1.7 occupied".utf8)
        try FileManager.default.createDirectory(at: address(digest(data)), withIntermediateDirectories: true)
        XCTAssertThrowsError(try storeSource(data)) { e in
            let msg = (e as? LocalizedError)?.errorDescription ?? "\(e)"
            XCTAssertTrue(msg.contains("目錄") && msg.contains("沒有記進 index"), msg)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("sources/index.jsonl").path),
                       "拒絕時不寫 index")
    }

    func testDoctorReportsOccupantProblemsAndTheAgeOfStrayTemporaryFiles() throws {
        // 一個位址被目錄佔住
        let held = Data("held".utf8)
        try FileManager.default.createDirectory(at: address(digest(held)), withIntermediateDirectories: true)
        // 一個剛寫的暫存檔（可能正在進行）
        let d = "sha256:" + String(repeating: "cd", count: 32)
        let name = LibraryStore.temporaryBlobName(digest: d, token: UUID().uuidString)
        let shard = root.appendingPathComponent("sources/cd")
        try FileManager.default.createDirectory(at: shard, withIntermediateDirectories: true)
        try Data(repeating: 1, count: 321).write(to: shard.appendingPathComponent(name))

        let sources = try XCTUnwrap(try json(try service.doctor())["sources"] as? [String: Any])
        let stray = try XCTUnwrap(sources["strayTemporaryFiles"] as? [[String: Any]])
        XCTAssertEqual(stray.count, 1)
        XCTAssertEqual(stray.first?["path"] as? String, "sources/cd/\(name)")
        XCTAssertEqual(stray.first?["bytes"] as? Int, 321)
        XCTAssertLessThan(try XCTUnwrap(stray.first?["ageSeconds"] as? Int), 600)
        XCTAssertEqual(stray.first?["possiblyInProgress"] as? Bool, true, "一小時內還在動：可能正在進行")
        XCTAssertEqual(sources["strayTemporaryFilesTotal"] as? Int, 1)
        let problems = try XCTUnwrap(sources["occupantProblems"] as? [[String: Any]])
        XCTAssertEqual(problems.first?["kind"] as? String, "notRegularFile")
        XCTAssertEqual(problems.first?["occupant"] as? String, "目錄")
        XCTAssertEqual(problems.first?["path"] as? String, LibraryStore.sourceRelativePath(digest: digest(held)))
        XCTAssertEqual(sources["occupantProblemsTotal"] as? Int, 1)

        // 兩小時沒動：不再是「可能正在進行」
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSinceNow: -7_200)],
                                              ofItemAtPath: shard.appendingPathComponent(name).path)
        let later = try XCTUnwrap(try json(try service.doctor())["sources"] as? [String: Any])
        let old = try XCTUnwrap((later["strayTemporaryFiles"] as? [[String: Any]])?.first)
        XCTAssertEqual(old["possiblyInProgress"] as? Bool, false)
        XCTAssertGreaterThanOrEqual(try XCTUnwrap(old["ageSeconds"] as? Int), 7_000)
    }

    /// 第 4 則：截短的 blob 不能宣告為副本（先前照連、回 sourcesAdded）。
    func testAddSourceRefusesATruncatedBlob() throws {
        let store = LibraryStore(root: root)
        try store.writeEntry(Entry(id: UUID(), citekey: "x2026y", type: .periodicalArticle, title: "T"))
        let data = Data(repeating: 9, count: 4_096)
        let d = try XCTUnwrap(try storeSource(data)["digest"] as? String)
        try Data(repeating: 9, count: 100).write(to: address(d))
        XCTAssertThrowsError(try service.addEntrySources(citekey: "x2026y", digests: [d], dryRun: true, sourcesLimit: nil)) { e in
            let msg = (e as? LocalizedError)?.errorDescription ?? "\(e)"
            XCTAssertTrue(msg.contains("100 bytes") && msg.contains("4096 bytes") && msg.contains("零寫入"), msg)
        }
    }
}
