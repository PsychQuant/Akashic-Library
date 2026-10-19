import XCTest
import Foundation
@testable import AkashicStoreIO

/// #700 b42 verify INFO 20：`.gitignore` 只把 `sources/index.jsonl` 放回來（內容形的規則加 `!sources/index.jsonl`）時，存檔與它的子目錄仍被排除、
/// index 沒有。修前 `store-source` 先寫存檔、到附加 index 那一步才問 index 被不被排除——拒絕了，存檔卻已經在磁碟上（孤兒，`auditSourceIndex` 才看得到）。
/// 匯入那一句「sources/ 沒被排除之前 store-source 拒絕寫入」對這一格不成立。現在要附加 index 時，寫存檔之前先問。
final class SourcesIndexExclusionOrderTests: XCTestCase {
    private var root: URL!
    private var store: LibraryStore!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("akashic-index-exclusion-\(UUID().uuidString)")
        store = LibraryStore(root: root)
        try store.ensureLayout()
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    private func prov() -> LibraryStore.SourceProvenance {
        LibraryStore.SourceProvenance(mediaType: "text/plain", retrieved: "2026-10-20", origin: "unit-test", acquisition: "file")
    }

    /// `sources/` 底下所有的一般檔（相對路徑）。
    private func filesUnderSources() -> [String] {
        let dir = root.appendingPathComponent("sources")
        guard let walker = FileManager.default.enumerator(at: dir, includingPropertiesForKeys: [.isRegularFileKey]) else { return [] }
        return walker.compactMap { item -> String? in
            guard let url = item as? URL, (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else { return nil }
            return String(url.path.dropFirst(dir.path.count + 1))
        }.sorted()
    }

    func testOnlyTheIndexPutBackIsRefusedBeforeTheBlobIsWritten() throws {
        let gitignore = "# BEGIN akashic sources\nsources/*\n# END akashic sources\n!sources/index.jsonl\n"
        try Data(gitignore.utf8).write(to: root.appendingPathComponent(".gitignore"))
        GitFixture.initRepo(root)
        XCTAssertThrowsError(try store.storeSource(Data("third-party bytes".utf8), provenance: prov())) { error in
            XCTAssertTrue("\(error)".contains("index.jsonl") || (error as? LocalizedError)?.errorDescription?.contains("未被版控忽略") == true, "\(error)")
        }
        XCTAssertEqual(filesUnderSources(), [], "拒絕時不留存檔")
    }

    /// 同一份內容已經記在 index 裡時不附加 index：只寫（或認出）存檔，不因 index 被放回來而拒絕——先問 index 只在要附加時。
    func testAnAlreadyIndexedDigestIsNotRefusedForTheIndex() throws {
        let receipt = try store.storeSource(Data("third-party bytes".utf8), provenance: prov())
        let gitignore = "# BEGIN akashic sources\nsources/*\n# END akashic sources\n!sources/index.jsonl\n"
        try Data(gitignore.utf8).write(to: root.appendingPathComponent(".gitignore"))
        GitFixture.initRepo(root)
        let again = try store.storeSource(Data("third-party bytes".utf8), provenance: prov())
        XCTAssertEqual(again.digest, receipt.digest)
        XCTAssertFalse(again.indexEntryCreated)
    }
}
