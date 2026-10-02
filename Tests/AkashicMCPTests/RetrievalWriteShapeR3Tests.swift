import XCTest
@testable import AkashicCore
@testable import AkashicStoreIO
@testable import AkashicMCPKit

/// #695 R2 verify 的 LOW（2026-10-02，R3 修）：
/// - 只給 digest（回顯、不寫 reference）時，前後有空白或換行的 digest 不該整批拒絕——而且拒絕的理由「reference 記的是送來的原值」在那一格是假的（三席各自重現）；
/// - 「不是 sha256」的拒絕理由不該自己帶「整批拒絕、零寫入」（`InputError` 的外框已經說了，訊息出現兩次）；
/// - 相容定界符的拒絕訊息不該含字面的反斜線（落在 CLI／MCP 的出口會被逃脫成 `\u{005C}`）；
/// - IPv6 方括號分支沒有驗結尾與內容：`https://[user:hunter2/x` 與 `https://[hunter2]/x` 繞過了 port 全數字檢查（security 席，真 binary）。
final class RetrievalWriteShapeR3Tests: XCTestCase {
    var root: URL!
    var fakeHome: URL!
    var env: [String: String] { ["AKASHIC_HOME": fakeHome.path] }
    let digest = "sha256:" + String(repeating: "c", count: 64)

    override func setUpWithError() throws {
        fakeHome = FileManager.default.temporaryDirectory.appendingPathComponent("akashic-home-\(UUID().uuidString)")
        root = FileManager.default.temporaryDirectory.appendingPathComponent("akashic-695r3-\(UUID().uuidString)")
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

    private func digestOnly(_ d: String?) -> AddOnlyEnrichment.Proposal {
        .init(citekey: "anon2020x", fields: ["abstract": "摘要"], sourceDigest: d)
    }

    private func withSource(url: String, digest d: String? = nil) -> AddOnlyEnrichment.Proposal {
        .init(citekey: "anon2020x", fields: ["abstract": "摘要"], sourceDigest: d ?? digest,
              sourceURL: url, sourceRetrieved: "2026-09-30", sourceMediaType: nil, sourceStatus: 200)
    }

    private func personReference(url: String) -> [String: Any] {
        ["field": "openalex", "kind": "retrieval", "content": digest, "url": url, "retrieved": "2026-09-30", "status": 200]
    }

    /// 兩面都拒絕；回兩面的訊息。
    private func refusals(url: String, file: StaticString = #filePath, line: UInt = #line) -> [(face: String, why: String)] {
        var e = "", p = ""
        XCTAssertThrowsError(try service.enrich(proposals: [withSource(url: url)], dryRun: true, includeAbsentAuthors: false),
                             "enrich 應拒絕 \(url)", file: file, line: line) { e = message($0) }
        XCTAssertThrowsError(try service.updatePerson(key: "p-one", fields: ["references": [personReference(url: url)]], dryRun: true),
                             "person references 應拒絕 \(url)", file: file, line: line) { p = message($0) }
        return [("enrich", e), ("person", p)]
    }

    // MARK: - digest 只回顯時不拒絕空白

    func testAPaddedDigestIsAcceptedWhenOnlyEchoedAndStillRefusedWhenAReferenceIsWritten() throws {
        for d in [" \(digest)", "\(digest)\n", "\n\(digest) \t"] {
            XCTAssertNoThrow(try service.enrich(proposals: [digestOnly(d)], dryRun: true, includeAbsentAuthors: false),
                             "回顯模式：digest 不進 store，`shasum` 的輸出帶換行是常態：\(d.debugDescription)")
        }
        // 只有空白的 digest 視同沒給（與 R2 之前同）
        XCTAssertNoThrow(try service.enrich(proposals: [digestOnly("   ")], dryRun: true, includeAbsentAuthors: false))
        // reference 真的會寫時仍驗原值
        for d in [" \(digest)", "\(digest)\n"] {
            XCTAssertThrowsError(try service.enrich(proposals: [withSource(url: "https://example.org/x", digest: d)], dryRun: true,
                                                    includeAbsentAuthors: false)) {
                XCTAssertTrue(message($0).contains("sourceDigest 前後有空白或換行"), message($0))
            }
        }
        // 回顯模式下真的壞的 digest 照舊拒絕
        XCTAssertThrowsError(try service.enrich(proposals: [digestOnly("sha256:abc")], dryRun: true, includeAbsentAuthors: false))
    }

    func testTheBadDigestRefusalDoesNotRepeatTheBatchSentence() {
        XCTAssertThrowsError(try service.enrich(proposals: [digestOnly("sha256:abc")], dryRun: true, includeAbsentAuthors: false)) {
            let m = message($0)
            XCTAssertTrue(m.contains("sourceDigest 不是 `sha256:`"), m)
            XCTAssertEqual(m.components(separatedBy: "零寫入").count - 1, 1, "「零寫入」只說一次：\(m)")
        }
    }

    // MARK: - 相容定界符訊息沒有字面反斜線

    func testTheCompatibilityDelimiterRefusalHasNoLiteralBackslash() {
        for r in refusals(url: "https://user:secret\u{FF20}example.org/a") {
            XCTAssertTrue(r.why.contains("相容形的定界符"), "\(r.face)：\(r.why)")
            XCTAssertFalse(r.why.contains("\\"), "\(r.face)：字面反斜線會在出口被逃脫成 \\u{005C}：\(r.why)")
        }
    }

    // MARK: - IPv6 方括號

    func testAnUnclosedOrNonAddressBracketIsRefusedOnBothFaces() {
        for url in ["https://[user:hunter2/x", "https://[::1", "https://[hunter2]/x", "https://[hunter2:8443]/x", "https://[::1]]/x"] {
            for r in refusals(url: url) {
                XCTAssertTrue(r.why.contains("IPv6") || r.why.contains("port 不是數字"), "\(r.face)：\(url)：\(r.why)")
                XCTAssertFalse(r.why.contains("hunter2"), "\(r.face)：不回顯原值：\(r.why)")
            }
        }
    }

    func testRealIPv6LiteralsAreStillAccepted() {
        for ok in ["https://[::1]/x", "https://[2001:db8::1]:8443/x", "https://[2001:DB8::1]/", "https://[fe80::1%25en0]/x",
                   "https://[::ffff:192.0.2.1]/x"] {
            XCTAssertNoThrow(try service.enrich(proposals: [withSource(url: ok)], dryRun: true, includeAbsentAuthors: false), ok)
            XCTAssertNoThrow(try service.updatePerson(key: "p-one", fields: ["references": [personReference(url: ok)]], dryRun: true), ok)
        }
    }
}
