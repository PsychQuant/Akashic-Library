import XCTest
@testable import AkashicCore
@testable import AkashicStoreIO
@testable import AkashicMCPKit

/// #668 的 service 面：`enrich` 在寫入前讀 marker，format < 17 時 `fields.<鍵>` 的值照補、reference 省略並具名——
/// 不讓寫入閘在 apply 時擋下整筆（那會連同值一起 writeFailed，dry-run 還說「會寫」）。CLI `enrich` 與 MCP
/// `akashic_enrich` 走同一條，payload 就是兩面的契約。
final class EnrichFieldsReferenceFormatServiceTests: XCTestCase {
    var root: URL!
    var fakeHome: URL!
    var env: [String: String] { ["AKASHIC_HOME": fakeHome.path] }
    let digest = "sha256:" + String(repeating: "a", count: 64)

    override func setUpWithError() throws {
        fakeHome = FileManager.default.temporaryDirectory.appendingPathComponent("akashic-home-\(UUID().uuidString)")
        root = FileManager.default.temporaryDirectory.appendingPathComponent("akashic-668-svc-\(UUID().uuidString)")
        let store = LibraryStore(root: root)
        try store.ensureLayout()
        try store.writeEntry(Entry(id: UUID(), citekey: "anon2021y", type: .periodicalArticle, title: "Anon"))
    }
    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
        try? FileManager.default.removeItem(at: fakeHome)
    }

    private func proposal() -> AddOnlyEnrichment.Proposal {
        .init(citekey: "anon2021y", fields: ["abstract": "摘要"], sourceDigest: digest,
              sourceURL: "https://api.crossref.org/works/10.1037%2Fy", sourceRetrieved: "2026-09-28", sourceStatus: 200)
    }
    private func item(_ payload: String) throws -> [String: Any] {
        let obj = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(payload.utf8)) as? [String: Any])
        return try XCTUnwrap((obj["items"] as? [[String: Any]])?.first, payload)
    }

    func testFormat16KeepsTheValueAndSaysWhyTheReferenceIsOmitted() throws {
        try StoreVersion.write(root: root, format: 16)
        let svc = AkashicService(root: root, environment: env)
        let dryPayload = try svc.enrich(proposals: [proposal()], dryRun: true, includeAbsentAuthors: false)
        let dry = try item(dryPayload)
        XCTAssertNil(dry["provenancePlanned"], "format 16 收不下，dry-run 不得說「會寫」：\(dryPayload)")
        let why = try XCTUnwrap((dry["provenanceOmitted"] as? [String: String])?["fields.abstract"], dryPayload)
        XCTAssertTrue(why.contains("format 16") && why.contains("≥ \(StoreVersion.workFieldReferenceFormat)"), why)

        let payload = try svc.enrich(proposals: [proposal()], dryRun: false, includeAbsentAuthors: false)
        let obj = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(payload.utf8)) as? [String: Any])
        XCTAssertNil(obj["writeFailed"], "省略 reference 是為了不讓整筆寫入失敗：\(payload)")
        XCTAssertEqual(obj["written"] as? [String], ["anon2021y"])
        let e = try XCTUnwrap(LibraryStore(root: root).load().entries.first { $0.citekey == "anon2021y" })
        XCTAssertEqual(e.fields["abstract"], "摘要")
        XCTAssertTrue(e.references.isEmpty, "\(e.references)")
    }

    /// format 17（`workFieldReferenceFormat`）起照常寫。
    func testFormat17WritesTheFieldsReference() throws {
        try StoreVersion.write(root: root, format: 17)
        let svc = AkashicService(root: root, environment: env)
        let one = try item(try svc.enrich(proposals: [proposal()], dryRun: false, includeAbsentAuthors: false))
        XCTAssertEqual(one["provenanceWritten"] as? [String], ["fields.abstract"])
        XCTAssertNil(one["provenanceOmitted"])
    }
}
