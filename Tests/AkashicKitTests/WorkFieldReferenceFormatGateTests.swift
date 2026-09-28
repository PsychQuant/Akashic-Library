import XCTest
@testable import AkashicCore
@testable import AkashicStoreIO

/// #668：work 的 `fields.<鍵>` 來源 reference（#517）是 store format 17 的 vocabulary。
///
/// #517 早 format 17 約 1.5 小時合進來、沒有自己的 bump 也沒有寫入閘，所以停在 16 卻早於 #517 的 binary 讀到它走封閉
/// default、整檔 quarantine（rc=0），而新 binary 卻照樣把它寫進 format 13–16 的 store。與 16／17／18／20 各道閘同形。
final class WorkFieldReferenceFormatGateTests: XCTestCase {
    var root: URL!
    var store: LibraryStore!
    private let digest = "sha256:" + String(repeating: "c", count: 64)

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("akashic-668-\(UUID().uuidString)")
        store = LibraryStore(root: root)
        try store.ensureLayout()
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    private func withReference(field: String, value: String? = nil) -> Entry {
        var e = Entry(id: UUID(), citekey: "fisher1925statistical", type: .periodicalArticle, title: "T")
        e.fields["abstract"] = "a"
        e.references = [ProvenanceReference(
            field: field, value: value,
            kind: .retrieval(url: "https://x.org/y", retrieved: "2026-09-28", status: 200, mediaType: nil, content: digest))]
        return e
    }

    /// 門檻是 17，且在 binary 支援的範圍內（否則閘會擋掉自己寫得出的東西）。
    func testThresholdIsSeventeenAndSupported() {
        XCTAssertEqual(StoreVersion.workFieldReferenceFormat, 17)
        XCTAssertLessThanOrEqual(StoreVersion.workFieldReferenceFormat, StoreVersion.supported)
    }

    func testFormat16RefusesFieldsReference() throws {
        try StoreVersion.write(root: root, format: 16)
        XCTAssertThrowsError(try store.writeEntry(withReference(field: "fields.abstract"))) { error in
            // 訊息的數字與閘用的常數是同一個
            XCTAssertTrue("\(error)".contains("≥ \(StoreVersion.workFieldReferenceFormat)"), "\(error)")
            XCTAssertTrue("\(error)".contains("fields.<鍵>"), "\(error)")
        }
        XCTAssertTrue(try store.load().entries.isEmpty, "被拒的寫入零副作用")
    }

    /// 閘只擋這一格：識別碼的來源 reference 在 13 以上照收（#394 的既有門檻不變）。
    func testFormat16StillWritesIdentifierReferences() throws {
        try StoreVersion.write(root: root, format: 16)
        var e = withReference(field: "doi", value: "10.1037/0003-066X.59.1.29")
        e.doi = [try XCTUnwrap(DOI("10.1037/0003-066X.59.1.29"))]
        XCTAssertNoThrow(try store.writeEntry(e))
    }

    /// format 17：寫得進去，而且讀得回來。
    func testFormat17WritesAndLoadsFieldsReference() throws {
        try StoreVersion.write(root: root, format: 17)
        XCTAssertNoThrow(try store.writeEntry(withReference(field: "fields.abstract")))
        let load = try store.load()
        XCTAssertTrue(load.quarantined.isEmpty, "\(load.quarantined)")
        let back = try XCTUnwrap(load.entries.first { $0.citekey == "fisher1925statistical" })
        XCTAssertEqual(back.references.map(\.field), ["fields.abstract"])
    }
}

/// `AddOnlyEnrichment` 對 `fields.<鍵>` 那一格收不下時的處置（#668，同 #655 對 `date`）。
final class EnrichmentFieldsReferenceCellTests: XCTestCase {
    private let digest = "sha256:" + String(repeating: "b", count: 64)
    private func entry() -> Entry { Entry(id: UUID(), citekey: "b2020y", type: .periodicalArticle, title: "T") }
    private func proposal(fields: [String: String], date: String? = nil) -> AddOnlyEnrichment.Proposal {
        .init(citekey: "b2020y", fields: fields, date: date, sourceDigest: digest,
              sourceURL: "https://api.crossref.org/works/10.1037%2Fy", sourceRetrieved: "2026-09-28", sourceStatus: 200)
    }

    /// 值照補、每一個補進去的鍵各自具名省略，其他格（date）不受影響。
    func testUnavailableFieldsCellKeepsValuesAndNamesEachKey() throws {
        let r = try AddOnlyEnrichment.plan(entries: [entry()],
                                           proposals: [proposal(fields: ["abstract": "摘", "note": "n"], date: "2020")],
                                           fieldsReference: .unavailable(reason: "本 store 是 format 16"))
        let o = try XCTUnwrap(r.items.first).outcome
        XCTAssertEqual(o.addedFields, ["abstract": "摘", "note": "n"], "值照補——閘管的是 reference 那一格，不是值")
        XCTAssertEqual(o.addedReferences.map(\.field), ["date"], "date 那一格是另一個判斷")
        XCTAssertEqual(o.provenanceOmitted["fields.abstract"], "本 store 是 format 16")
        XCTAssertEqual(o.provenanceOmitted["fields.note"], "本 store 是 format 16")
    }

    /// 預設 `.writable`：與 #668 之前相同，每個鍵一筆。
    func testWritableFieldsCellWritesOneReferencePerKey() throws {
        let r = try AddOnlyEnrichment.plan(entries: [entry()], proposals: [proposal(fields: ["abstract": "摘", "note": "n"])])
        let o = try XCTUnwrap(r.items.first).outcome
        XCTAssertEqual(o.addedReferences.map(\.field), ["fields.abstract", "fields.note"])
        XCTAssertTrue(o.provenanceOmitted.isEmpty, "\(o.provenanceOmitted)")
    }
}
