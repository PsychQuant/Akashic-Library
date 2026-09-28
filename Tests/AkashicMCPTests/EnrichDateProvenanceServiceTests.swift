import XCTest
@testable import AkashicCore
@testable import AkashicStoreIO
@testable import AkashicMCPKit

/// #655 的 service 面：`enrich` 在寫入前讀 marker，format ≥ 20 時 `date` 寫 reference、低於時值照補而 reference 省略
/// 並具名；`authors` 一律省略並具名。CLI `enrich` 與 MCP `akashic_enrich` 都走這一條，所以 payload 就是兩面的契約。
final class EnrichDateProvenanceServiceTests: XCTestCase {
    var root: URL!
    var fakeHome: URL!
    var env: [String: String] { ["AKASHIC_HOME": fakeHome.path] }
    let digest = "sha256:" + String(repeating: "f", count: 64)

    override func setUpWithError() throws {
        fakeHome = FileManager.default.temporaryDirectory.appendingPathComponent("akashic-home-\(UUID().uuidString)")
        root = FileManager.default.temporaryDirectory.appendingPathComponent("akashic-655-svc-\(UUID().uuidString)")
        let store = LibraryStore(root: root)
        try store.ensureLayout()
        try store.writeEntry(Entry(id: UUID(), citekey: "anon2020x", type: .periodicalArticle, title: "Anon"))
    }
    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
        try? FileManager.default.removeItem(at: fakeHome)
    }

    private func proposal(date: String? = "2020", authors: [String] = []) -> AddOnlyEnrichment.Proposal {
        .init(citekey: "anon2020x", date: date, authors: authors, sourceDigest: digest,
              sourceURL: "https://api.crossref.org/works/10.1037%2Fx", sourceRetrieved: "2026-09-28", sourceStatus: 200)
    }
    private func item(_ payload: String) throws -> [String: Any] {
        let obj = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(payload.utf8)) as? [String: Any])
        return try XCTUnwrap((obj["items"] as? [[String: Any]])?.first, payload)
    }
    private func entry() throws -> Entry {
        try XCTUnwrap(LibraryStore(root: root).load().entries.first { $0.citekey == "anon2020x" })
    }

    /// 新建的 store 在 supported（≥ 20）：dry-run 說會寫、apply 真的寫，store 裡有那一筆。
    func testCurrentFormatPlansAndWritesTheDateReference() throws {
        let svc = AkashicService(root: root, environment: env)
        let dry = try item(try svc.enrich(proposals: [proposal()], dryRun: true, includeAbsentAuthors: false))
        XCTAssertEqual(dry["provenancePlanned"] as? [String], ["date"])
        XCTAssertNil(dry["provenanceOmitted"])
        let applied = try item(try svc.enrich(proposals: [proposal()], dryRun: false, includeAbsentAuthors: false))
        XCTAssertEqual(applied["provenanceWritten"] as? [String], ["date"])
        let e = try entry()
        XCTAssertEqual(e.date, "2020")
        XCTAssertEqual(e.references.map(\.field), ["date"])
    }

    /// format 19：**值照補、寫入不失敗**、reference 省略，理由說出 format 與門檻，dry-run 就看得到。
    func testFormat19KeepsTheValueAndSaysWhyTheReferenceIsOmitted() throws {
        try StoreVersion.write(root: root, format: 19)
        let svc = AkashicService(root: root, environment: env)
        let dryPayload = try svc.enrich(proposals: [proposal()], dryRun: true, includeAbsentAuthors: false)
        let dry = try item(dryPayload)
        XCTAssertNil(dry["provenancePlanned"], "format 19 收不下，dry-run 不得說「會寫」：\(dryPayload)")
        let why = try XCTUnwrap((dry["provenanceOmitted"] as? [String: String])?["date"], dryPayload)
        XCTAssertTrue(why.contains("format 19") && why.contains("≥ \(StoreVersion.workDateReferenceFormat)"), why)

        let payload = try svc.enrich(proposals: [proposal()], dryRun: false, includeAbsentAuthors: false)
        let obj = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(payload.utf8)) as? [String: Any])
        XCTAssertNil(obj["writeFailed"], "省略 reference 是為了不讓整筆寫入失敗：\(payload)")
        XCTAssertEqual(obj["written"] as? [String], ["anon2020x"])
        let e = try entry()
        XCTAssertEqual(e.date, "2020")
        XCTAssertTrue(e.references.isEmpty, "\(e.references)")
    }

    /// `authors`：payload 帶省略理由，兩面讀到的是同一句。
    func testAuthorsOmissionIsInThePayload() throws {
        let svc = AkashicService(root: root, environment: env)
        let one = try item(try svc.enrich(proposals: [proposal(date: nil, authors: ["Some One"])],
                                          dryRun: true, includeAbsentAuthors: true))
        let omitted = try XCTUnwrap(one["provenanceOmitted"] as? [String: String])
        XCTAssertEqual(omitted["authors"], displaySafe(AddOnlyEnrichment.authorsProvenanceOmittedReason, max: 600))
        XCTAssertNil(one["provenancePlanned"], "只補了作者——沒有任何 reference 要寫")
    }
}
