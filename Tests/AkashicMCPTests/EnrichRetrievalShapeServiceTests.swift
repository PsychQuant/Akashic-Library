import XCTest
@testable import AkashicCore
@testable import AkashicStoreIO
@testable import AkashicMCPKit

/// #695 的 service 面：CLI `enrich --from` 與 MCP `akashic_enrich` 都走 `AkashicService.enrich`，所以這裡的拒絕就是兩面的契約。
///
/// 「同一種記錄只剩一份寫入契約」（使用者 2026-09-30 裁決）的量法：同一個形狀錯，`enrich` 的來源欄位與 person 的 `references`（#674）
/// 說出**同一句**核心訊息——差別只在前面指名的鍵（`sourceURL` 對 `references[0].url`）與離線來源的出路。一個面收緊、另一個沒跟上，就在這裡紅。
final class EnrichRetrievalShapeServiceTests: XCTestCase {
    var root: URL!
    var fakeHome: URL!
    var env: [String: String] { ["AKASHIC_HOME": fakeHome.path] }
    let digest = "sha256:" + String(repeating: "c", count: 64)
    let alpha = UUID()

    override func setUpWithError() throws {
        fakeHome = FileManager.default.temporaryDirectory.appendingPathComponent("akashic-home-\(UUID().uuidString)")
        root = FileManager.default.temporaryDirectory.appendingPathComponent("akashic-695-svc-\(UUID().uuidString)")
        let store = LibraryStore(root: root)
        try store.ensureLayout()
        try store.writeEntry(Entry(id: alpha, citekey: "anon2020x", type: .periodicalArticle, title: "Anon"))
        try store.writePerson(Person(key: "p-one", names: PersonNames(authorized: ["Che Cheng"])))
    }
    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
        try? FileManager.default.removeItem(at: fakeHome)
    }

    private var service: AkashicService { AkashicService(root: root, environment: env) }

    private func snapshot() throws -> [String: Data] {
        let dir = root.appendingPathComponent("entities")
        var out: [String: Data] = [:]
        for name in try FileManager.default.contentsOfDirectory(atPath: dir.path) {
            out[name] = try Data(contentsOf: dir.appendingPathComponent(name))
        }
        return out
    }
    private func message(_ error: Error) -> String {
        if case ServiceError.invalid(let why) = error { return why }
        return "\(error)"
    }

    /// 形狀的三個欄位；兩個面各自把它們放在自己的鍵裡。
    private struct Shape { var url: String? = "https://example.org/x"; var retrieved: String? = "2026-09-30"; var status: Int? = 200 }

    private func enrichProposal(_ s: Shape) -> AddOnlyEnrichment.Proposal {
        .init(citekey: "anon2020x", fields: ["abstract": "摘要"], sourceDigest: digest,
              sourceURL: s.url, sourceRetrieved: s.retrieved, sourceStatus: s.status)
    }
    private func personReference(_ s: Shape) -> [String: Any] {
        var d: [String: Any] = ["field": "openalex", "kind": "retrieval", "content": digest]
        if let u = s.url { d["url"] = u }
        if let r = s.retrieved { d["retrieved"] = r }
        if let st = s.status { d["status"] = st }
        return d
    }

    /// 每一格：enrich（dry-run 與 apply）與 person references 都拒絕、都零寫入，且都說出同一句核心訊息。
    func testEnrichAndPersonReferencesRefuseWithTheSameSentence() throws {
        let cases: [(String, Shape, String)] = [
            ("ftp", Shape(url: "ftp://example.org/x"), "只收 http／https 網址（scheme 是「ftp」）"),
            ("帳密", Shape(url: "https://u:p@example.org/x"), "含帳密（userinfo"),
            ("缺主機", Shape(url: "https:///x"), "缺主機"),
            ("retrieved", Shape(retrieved: "2026/09/30"), "「2026/09/30」不是 ISO 8601"),
            ("status 範圍", Shape(status: 600), "「600」不是 HTTP 狀態碼（100–599）"),
            ("缺 status", Shape(status: nil), "是擷取型卻沒有 status——HTTP 狀態碼必填、不預設 200"),
        ]
        for (label, shape, sentence) in cases {
            let before = try snapshot()
            for dryRun in [true, false] {
                XCTAssertThrowsError(try service.enrich(proposals: [enrichProposal(shape)], dryRun: dryRun, includeAbsentAuthors: false),
                                     "enrich：\(label)") { error in
                    let why = message(error)
                    XCTAssertTrue(why.contains(sentence), "enrich：\(label)：要說出「\(sentence)」，實得 \(why)")
                    XCTAssertTrue(why.contains("整批拒絕"), "enrich：\(label)：\(why)")
                }
            }
            XCTAssertThrowsError(try service.updatePerson(key: "p-one", fields: ["references": [personReference(shape)]], dryRun: false),
                                 "person：\(label)") { error in
                XCTAssertTrue(message(error).contains(sentence), "person：\(label)：要說出「\(sentence)」，實得 \(message(error))")
            }
            XCTAssertEqual(try snapshot(), before, "\(label)：零寫入")
        }
    }

    /// 合法的一筆照寫，reference 帶著送來的 url／retrieved／status。
    func testWellFormedProposalIsWrittenWithItsRetrievalReference() throws {
        let shape = Shape(url: "https://api.crossref.org/works/10.1037%2Fx", retrieved: "2026-09-30T14:30:00+08:00", status: 200)
        _ = try service.enrich(proposals: [enrichProposal(shape)], dryRun: false, includeAbsentAuthors: false)
        let e = try XCTUnwrap(try LibraryStore(root: root).load().entries.first { $0.citekey == "anon2020x" })
        XCTAssertEqual(e.fields["abstract"], "摘要")
        let ref = try XCTUnwrap(e.references.first { $0.field == "fields.abstract" })
        guard case .retrieval(let url, let retrieved, let status, _, let content) = ref.kind else { return XCTFail("\(ref)") }
        XCTAssertEqual([url, retrieved, "\(status)", content], [shape.url!, shape.retrieved!, "200", digest])
    }
}
