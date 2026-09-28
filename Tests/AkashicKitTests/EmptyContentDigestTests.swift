import XCTest
import Foundation
import CryptoKit
@testable import AkashicCore
@testable import AkashicStoreIO

/// #654（#546 的餘項 3）：空內容的 digest 不得被引用。
///
/// #546 在 `store-source` 擋下了 0 byte 的內容，但引用端照收 `sha256:e3b0c442…`——一筆指向「空存檔」的 reference 仍寫得進去。
/// 使用者 2026-09-28 裁決：閘放在 `ProvenanceReference.isValidDigest` 本身，所以每一個寫入面（以及載入）都經過它；
/// 位址層（`sources/` 路徑、`sources/index.jsonl` 的文法）只看形狀，因為 live store 的 index 有一列指向空 blob。
final class EmptyContentDigestTests: XCTestCase {
    private var root: URL!
    private var store: LibraryStore!
    private let empty = ProvenanceReference.emptyContentDigest
    private let ordinary = "sha256:" + String(repeating: "ab", count: 32)

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("akashic-empty-digest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root.appendingPathComponent("entities"), withIntermediateDirectories: true)
        GitFixture.initRepo(root)
        try StoreVersion.write(root: root, format: StoreVersion.supported)
        store = LibraryStore(root: root)
        try store.ensureLayout()
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    private func retrieval(_ field: String, value: String? = nil, content: String) -> ProvenanceReference {
        ProvenanceReference(field: field, value: value, kind: .retrieval(
            url: "https://example.org/\(field)", retrieved: "2026-09-28", status: 200, mediaType: nil, content: content))
    }

    private func entityFileCount() throws -> Int {
        try FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent("entities").path).count
    }

    // MARK: - 謂詞

    /// 常數本身要對：它就是 0 byte 的 SHA-256。寫錯一個字，閘就守在一個不存在的值上而全部綠燈。
    func testConstantIsTheSHA256OfZeroBytes() {
        let hex = SHA256.hash(data: Data()).map { String(format: "%02x", $0) }.joined()
        XCTAssertEqual(empty, "sha256:" + hex)
    }

    /// 形狀與可引用分成兩個謂詞：空內容的 digest 形狀合法、不可引用；其餘兩者一致。
    func testShapeAndCitabilityAreTwoPredicates() {
        XCTAssertTrue(ProvenanceReference.isWellFormedDigest(empty), "它是合法的位址——live store 有一個空 blob 住在那裡")
        XCTAssertFalse(ProvenanceReference.isValidDigest(empty), "它不指認任何存檔，不得被引用")
        XCTAssertTrue(ProvenanceReference.isWellFormedDigest(ordinary))
        XCTAssertTrue(ProvenanceReference.isValidDigest(ordinary))
        for bad in ["sha256:zz", "md5:abc", "SHA256:" + String(repeating: "ab", count: 32), "sha256:"] {
            XCTAssertFalse(ProvenanceReference.isWellFormedDigest(bad), bad)
            XCTAssertFalse(ProvenanceReference.isValidDigest(bad), bad)
        }
    }

    // MARK: - 引用端：每一種槽位都拒

    /// retrieval 的 content 與 judgement 的 rests-on 走同一個建構器（YAML decode 與寫入閘的 canary 都經過它）。
    /// 訊息要說「0 byte」而不是「形狀必須是 …」——對一個形狀合法的值說形狀錯是假話。
    func testReferenceConstructorNamesTheEmptyDigest() {
        XCTAssertThrowsError(try ProvenanceReference(
            field: "doi", value: "10.1000/x", url: "https://doi.org/10.1000/x", retrieved: "2026-09-28", status: 200,
            mediaType: nil, content: empty, judgement: nil, restsOn: [])) { error in
            XCTAssertTrue("\(error)".contains("0 byte"), "\(error)")
            XCTAssertFalse("\(error)".contains("形狀必須是"), "空內容的 digest 形狀合法：\(error)")
        }
        XCTAssertThrowsError(try ProvenanceReference(
            field: "paginated", value: "true", url: nil, retrieved: nil, status: nil,
            mediaType: nil, content: nil, judgement: "看過目錄", restsOn: [ordinary, empty])) { error in
            XCTAssertTrue("\(error)".contains("0 byte"), "\(error)")
        }
    }

    /// 寫入閘（encode 的語意 canary 走 decode）對三種持有者都拒、零寫入：person 的 reference、work 的 `akashic.sources`、
    /// divergence 的依據（`writeDivergence` 的顯式閘）。
    func testWriteGatesRefuseTheEmptyDigestWithZeroWrites() throws {
        let before = try entityFileCount()

        var p = Person(key: "p-one", names: PersonNames(variant: ["P"]))
        p.openalex = "A5000000001"   // reference 指名的欄位要在場——否則被擋下的理由是附著驗證，不是 digest
        p.references = [retrieval("openalex", content: empty)]
        XCTAssertThrowsError(try store.writePerson(p)) { XCTAssertTrue("\($0)".contains("0 byte"), "\($0)") }

        var e = Entry(id: UUID(), citekey: "a2020b", type: .periodicalArticle, title: "T")
        e.akashic.sources = [empty]
        XCTAssertThrowsError(try store.writeEntry(e)) { XCTAssertTrue("\($0)".contains("0 byte"), "\($0)") }

        XCTAssertEqual(try entityFileCount(), before, "拒寫必須零寫入")

        try store.writePerson(Person(key: "p-a", names: PersonNames(variant: ["A"])))
        try store.writePerson(Person(key: "p-b", names: PersonNames(variant: ["B"])))
        let mid = try entityFileCount()
        var d = Divergence(id: UUID(), question: "q",
                           candidates: [DivergenceCandidate(key: "p-a", shape: .person),
                                        DivergenceCandidate(key: "p-b", shape: .person)])
        d.judgement = Judgement(statement: "s", restsOn: [empty])
        XCTAssertThrowsError(try store.writeDivergence(d)) { XCTAssertTrue("\($0)".contains("0 byte"), "\($0)") }
        XCTAssertEqual(try entityFileCount(), mid, "divergence 拒寫必須零寫入")
    }

    /// 手寫進 YAML 的空 digest 在載入時被隔離，理由說 0 byte（`zero-instance-guards` 第 41 列：live store 0 筆，所以隔離不影響既有資料）。
    func testHandWrittenEmptyDigestIsQuarantinedAtLoad() throws {
        var p = Person(key: "p-one", names: PersonNames(variant: ["P"]))
        p.openalex = "A5000000001"
        p.references = [retrieval("openalex", content: ordinary)]
        let url = try store.writePerson(p)
        let text = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(text.contains(ordinary), "前提：digest 逐字寫在檔裡")
        try text.replacingOccurrences(of: ordinary, with: empty).write(to: url, atomically: true, encoding: .utf8)

        let load = try store.load()
        XCTAssertEqual(load.people.count, 0)
        XCTAssertEqual(load.quarantined.count, 1, "\(load.quarantined)")
        XCTAssertTrue(load.quarantined.first?.reason.contains("0 byte") == true, "\(load.quarantined)")
    }

    /// `enrich` 的 `sourceDigest`——#546 changelog 列出的第二個危害、本 issue 的直接起因。整批拒絕、訊息說 0 byte。
    func testEnrichRefusesTheEmptySourceDigest() {
        let e = Entry(id: UUID(), citekey: "a2020b", type: .periodicalArticle, title: "T")
        let prop = AddOnlyEnrichment.Proposal(citekey: "a2020b", doi: nil, fields: ["abstract": "x"], date: nil,
                                              authors: [], sourceDigest: empty)
        XCTAssertThrowsError(try AddOnlyEnrichment.plan(entries: [e], proposals: [prop])) { error in
            guard case AddOnlyEnrichment.InputError.invalidProposal(let i, let reason) = error else {
                return XCTFail("應是 invalidProposal，得 \(error)")
            }
            XCTAssertEqual(i, 1)
            XCTAssertTrue(reason.contains("0 byte"), reason)
            XCTAssertTrue(reason.contains("sourceDigest"), "要指名是哪個欄位：\(reason)")
        }
    }

    /// 舊形式（timeline 的 `source:`）搬成 reference 時同一道閘；略過的理由說 0 byte，原資料不動。
    func testProvenanceMigrationSkipsTheEmptyDigestWithItsOwnReason() throws {
        var p = Person(key: "p-one", names: PersonNames(authorized: ["P"]))
        p.profile.affiliations = TimelineOf([
            TemporalValue(value: OrgRef.literal("Academia Sinica"), source: empty, note: "由某頁推得")])
        try store.writePerson(p)
        let report = try ProvenanceMigration.digestSourcesToReferences(store: store, dryRun: false)
        XCTAssertEqual(report.migrated, 0)
        XCTAssertEqual(report.skipped.count, 1, "\(report.skipped)")
        XCTAssertTrue(report.skipped.first?.reason.contains("0 byte") == true, "\(report.skipped)")
        let after = try XCTUnwrap(try store.load().people.first)
        XCTAssertEqual(after.profile.affiliations.entries.first?.source, empty, "略過的就留在原地")
    }

    // MARK: - 位址層：只看形狀

    /// live store 的形狀：index 有一列指向空 blob（#546 之前兩次失敗抓取留下的），blob 也在。
    /// 這一列不得被判成無法解析——index 有無法解析的行時 `store-source` 對**所有**新內容 fail-closed。
    func testIndexRowForTheEmptyBlobStaysParseableAndStoreSourceKeepsWorking() throws {
        let hex = String(empty.dropFirst("sha256:".count))
        let shard = root.appendingPathComponent("sources").appendingPathComponent(String(hex.prefix(2)))
        try FileManager.default.createDirectory(at: shard, withIntermediateDirectories: true)
        try Data().write(to: shard.appendingPathComponent(String(hex.dropFirst(2))))
        let row = "{\"content\": \"\(empty)\", \"bytes\": 0, \"media-type\": \"application/json\", "
            + "\"retrieved\": \"2026-09-09T16:15:00+08:00\", \"origin\": \"https://example.org/429\", \"acquisition\": \"api\"}\n"
        try row.write(to: store.sourceIndexURL, atomically: true, encoding: .utf8)

        let audit = try store.auditSourceIndex()
        XCTAssertEqual(audit.malformedLines, [], "指向空 blob 的列是合法的位址，不是無法解析的行")
        XCTAssertEqual(audit.orphanBlobs, [])
        XCTAssertEqual(audit.danglingEntries, [])

        let receipt = try store.storeSource(Data("real bytes".utf8), provenance: LibraryStore.SourceProvenance(
            mediaType: "text/plain", retrieved: "2026-09-28", origin: "unit-test", acquisition: "file"))
        XCTAssertTrue(receipt.indexEntryCreated)
        XCTAssertEqual(try store.sourceContent(digest: empty), Data(), "位址層讀得到那個空 blob")
    }

    /// `AuthorListFingerprint` 的持久形只看形狀：空內容的 digest 不可能是 fingerprint，由比對時的 mismatch 說出來。
    func testFingerprintParserIsShapeOnly() {
        XCTAssertNoThrow(try AuthorListFingerprint(digest: empty))
        XCTAssertNotEqual(AuthorListFingerprint(authors: []).digest, empty, "domain-separated：空作者清單也不是空內容的雜湊")
    }
}
