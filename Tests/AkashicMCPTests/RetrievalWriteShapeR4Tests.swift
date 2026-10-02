import XCTest
@testable import AkashicCore
@testable import AkashicStoreIO
@testable import AkashicMCPKit

/// #695 R2 verify 第二輪（2026-10-02，MEDIUM 0 與 LOW 9、10、11、14、15、16、20、21、23、24）：
/// - 方括號裡只看字元集：`[1234]`、`[cafe:babe]`、`[....]`、`[:::::]` 都過；zone 不要求 `%25`，`[::1%hunter2]`、`[::1%]`、`[%hunter2]`、`%2` 也過；
/// - `sourceDigest` 前後的空白「只在 reference 真的會寫時才拒絕」用的判準比「真的會寫」寬（url＋status 而沒有取得日期也拒絕）；
/// - 只回顯時驗的是 trim 後的值、回顯的卻是原值；
/// - 長度上限的訊息把「整批拒絕、零寫入」說了兩次。
final class RetrievalWriteShapeR4Tests: XCTestCase {
    var root: URL!
    var fakeHome: URL!
    var env: [String: String] { ["AKASHIC_HOME": fakeHome.path] }
    let digest = "sha256:" + String(repeating: "c", count: 64)

    override func setUpWithError() throws {
        fakeHome = FileManager.default.temporaryDirectory.appendingPathComponent("akashic-home-\(UUID().uuidString)")
        root = FileManager.default.temporaryDirectory.appendingPathComponent("akashic-695r4-\(UUID().uuidString)")
        let store = LibraryStore(root: root)
        try store.ensureLayout()
        try store.writeEntry(Entry(id: UUID(), citekey: "anon2020x", type: .periodicalArticle, title: "Anon"))
        try store.writePerson(Person(key: "p-one", names: PersonNames(authorized: ["Che Cheng"])))
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
        try? FileManager.default.removeItem(at: fakeHome)
    }

    private var service: AkashicService { AkashicService(root: root, environment: env) }

    private func message(_ error: Error) -> String {
        if case ServiceError.invalid(let why) = error { return why }
        return "\(error)"
    }

    private func withSource(url: String) -> AddOnlyEnrichment.Proposal {
        .init(citekey: "anon2020x", fields: ["abstract": "摘要"], sourceDigest: digest,
              sourceURL: url, sourceRetrieved: "2026-09-30", sourceMediaType: nil, sourceStatus: 200)
    }

    private func personReference(url: String) -> [String: Any] {
        ["field": "openalex", "kind": "retrieval", "content": digest, "url": url, "retrieved": "2026-09-30", "status": 200]
    }

    private func items(_ proposal: AddOnlyEnrichment.Proposal) throws -> [[String: Any]] {
        let out = try service.enrich(proposals: [proposal], dryRun: true, includeAbsentAuthors: false)
        let obj = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(out.utf8)) as? [String: Any], out)
        return try XCTUnwrap(obj["items"] as? [[String: Any]], out)
    }

    // MARK: - 方括號 IPv6

    func testBracketsThatAreNotAnIPv6AddressAreRefusedOnBothFaces() {
        let longZone = String(repeating: "e", count: RetrievalWriteShape.maxZoneIDBytes + 1)
        for url in ["https://[::1%]/x", "https://[::1%2]/x", "https://[::1%25]/x", "https://[fe80::1%hunter2]/x",
                    "https://[fe80::1%en0]/x", "https://[fe80::1%26en0]/x", "https://[fe80::1%25en%2]/x", "https://[fe80::1%25en%zz]/x",
                    "https://[fe80::1%25\(longZone)]/x", "https://[%hunter2]/x", "https://[%25en0]/x",
                    "https://[1234]/x", "https://[cafe:babe]/x", "https://[....]/x", "https://[:::::]/x", "https://[:]/x",
                    "https://[deadbeef]/x", "https://[0123456789abcdef0123456789abcdef01234567]/x",
                    "https://[1:2:3:4:5:6:7:8:9]/x", "https://[::1::2]/x"] {
            var e = "", p = ""
            XCTAssertThrowsError(try service.enrich(proposals: [withSource(url: url)], dryRun: true, includeAbsentAuthors: false),
                                 "enrich 應拒絕 \(url)") { e = message($0) }
            XCTAssertThrowsError(try service.updatePerson(key: "p-one", fields: ["references": [personReference(url: url)]], dryRun: true),
                                 "person references 應拒絕 \(url)") { p = message($0) }
            for (face, why) in [("enrich", e), ("person", p)] {
                XCTAssertTrue(why.contains("不是 IPv6 位址"), "\(face)：\(url)：\(why)")
                XCTAssertFalse(why.contains("hunter2") || why.contains("deadbeef") || why.contains("cafe:babe"), "\(face)：不回顯原值：\(why)")
            }
        }
    }

    func testRealIPv6LiteralsAndZoneIDsAreAccepted() {
        let maxZone = String(repeating: "e", count: RetrievalWriteShape.maxZoneIDBytes)
        for ok in ["https://[::1]/x", "https://[fe80::1%25en0]/x", "https://[2001:db8::1]/x", "https://[2001:db8::1]:8443/x",
                   "https://[FE80::1%25en0]/", "https://[fe80::1%25%65n0]/x", "https://[fe80::1%25\(maxZone)]/x",
                   "https://[::ffff:192.0.2.1]/x", "https://[1:2:3:4:5:6:7:8]/x"] {
            XCTAssertNoThrow(try service.enrich(proposals: [withSource(url: ok)], dryRun: true, includeAbsentAuthors: false), ok)
            XCTAssertNoThrow(try service.updatePerson(key: "p-one", fields: ["references": [personReference(url: ok)]], dryRun: true), ok)
        }
    }

    // MARK: - digest 的空白：只在 reference 真的會寫時嚴格

    /// 四欄（digest、url、取得日期、status）不齊時 reference 不寫——帶換行的 digest 不拒絕、回顯 trim 後的值。
    func testAPaddedDigestIsAcceptedWheneverNoReferenceWouldBeWritten() throws {
        let padded = "\(digest)\n"
        let shapes: [AddOnlyEnrichment.Proposal] = [
            .init(citekey: "anon2020x", fields: ["abstract": "摘要"], sourceDigest: padded,
                  sourceURL: "https://example.org/a", sourceStatus: 200),                       // 沒有取得日期
            .init(citekey: "anon2020x", fields: ["abstract": "摘要"], sourceDigest: padded,
                  sourceMediaType: "application/pdf", sourceStatus: 200),                       // 沒有 url
            .init(citekey: "anon2020x", fields: ["abstract": "摘要"], sourceDigest: padded,
                  sourceRetrieved: "2026-09-30", sourceStatus: 200),                            // 沒有 url
            .init(citekey: "anon2020x", fields: ["abstract": "摘要"], sourceDigest: " \(digest) "),  // 只給 digest
        ]
        for p in shapes {
            let item = try XCTUnwrap(try items(p).first)
            XCTAssertEqual(item["sourceDigest"] as? String, digest, "回顯的是驗過的那個值（trim 之後）：\(item)")
            XCTAssertNil(item["provenancePlanned"], "這幾格都不寫 reference：\(item)")
        }
    }

    func testAWhitespaceOnlyDigestIsTreatedAsNotGivenInTheReportToo() throws {
        let item = try XCTUnwrap(try items(.init(citekey: "anon2020x", fields: ["abstract": "摘要"], sourceDigest: "   ")).first)
        XCTAssertNil(item["sourceDigest"], "只有空白視同沒給，報告也不回顯：\(item)")
        XCTAssertNil(item["provenanceSkipped"], "沒給來源就沒有「只給了 sourceDigest」這句：\(item)")
    }

    /// 四欄齊備時 reference 會寫，照舊驗原值。
    func testAPaddedDigestIsStillRefusedWhenTheReferenceWouldBeWritten() {
        var p = withSource(url: "https://example.org/a")
        p.sourceDigest = "\(digest)\n"
        XCTAssertThrowsError(try service.enrich(proposals: [p], dryRun: true, includeAbsentAuthors: false)) {
            XCTAssertTrue(message($0).contains("sourceDigest 前後有空白或換行"), message($0))
        }
    }

    // MARK: - 長度上限的訊息

    func testTheLengthRefusalSaysTheBatchSentenceOnce() {
        let p = AddOnlyEnrichment.Proposal(citekey: "anon2020x", fields: ["abstract": String(repeating: "a", count: 70_000)])
        XCTAssertThrowsError(try service.enrich(proposals: [p], dryRun: true, includeAbsentAuthors: false)) {
            let m = message($0)
            XCTAssertTrue(m.contains("超過上限"), m)
            XCTAssertEqual(m.components(separatedBy: "零寫入").count - 1, 1, "「零寫入」只說一次：\(m)")
        }
    }
}
