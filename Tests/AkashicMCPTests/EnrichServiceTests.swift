import XCTest
@testable import AkashicCore
@testable import AkashicStoreIO
@testable import AkashicMCPKit

/// #458：generic add-only 補值的 service 面——一次 `load`、委派 `AddOnlyEnrichment.plan`、
/// 逐筆 `writeEntry`（I/O 失敗逐筆收容）、一次 rebuild；`dryRun` 零寫入。
/// CLI `enrich` 與 MCP `akashic_enrich` 都走這一條（`entity-backlink-completeness` 執行細節 2）。
final class EnrichServiceTests: XCTestCase {
    var root: URL!
    var fakeHome: URL!
    var service: AkashicService!
    var env: [String: String] { ["AKASHIC_HOME": fakeHome.path] }
    /// 被設成 immutable 的檔——tearDown 要先解掉才刪得掉。
    var frozen: [URL] = []

    let olsson = UUID(), cheng = UUID()

    override func setUpWithError() throws {
        fakeHome = FileManager.default.temporaryDirectory
            .appendingPathComponent("akashic-home-\(UUID().uuidString)")
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("akashic-enrich-\(UUID().uuidString)")
        let store = LibraryStore(root: root)
        try store.ensureLayout()
        var e1 = Entry(id: olsson, citekey: "olsson1979maximum", type: .periodicalArticle,
                       title: "Maximum likelihood estimation of the polychoric correlation coefficient",
                       authors: [.literal("Ulf Olsson")], date: "1979",
                       doi: [DOI("10.1007/BF02293811")!])
        e1.fields["journaltitle"] = "Psychometrika"
        try store.writeEntry(e1)
        let e2 = Entry(id: cheng, citekey: "cheng2025identifiability", type: .periodicalArticle,
                       title: "Identifiability of polychoric models")
        try store.writeEntry(e2)
        service = AkashicService(root: root, environment: env)
    }

    override func tearDownWithError() throws {
        for f in frozen { try? FileManager.default.setAttributes([.immutable: false], ofItemAtPath: f.path) }
        try? FileManager.default.removeItem(at: root)
        try? FileManager.default.removeItem(at: fakeHome)
    }

    private func json(_ s: String) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: Data(s.utf8)) as? [String: Any])
    }
    private func items(_ obj: [String: Any]) throws -> [[String: Any]] {
        try XCTUnwrap(obj["items"] as? [[String: Any]])
    }
    private func bytes(_ id: UUID) throws -> Data {
        try Data(contentsOf: LibraryStore(root: root).entityURL(id: id))
    }
    private func entry(_ citekey: String) throws -> Entry {
        try XCTUnwrap(LibraryStore(root: root).load().entries.first { $0.citekey == citekey })
    }
    private func p(citekey: String? = nil, doi: String? = nil, fields: [String: String] = [:],
                   date: String? = nil, authors: [String] = [], sourceDigest: String? = nil)
        -> AddOnlyEnrichment.Proposal {
        .init(citekey: citekey, doi: doi, fields: fields, date: date, authors: authors, sourceDigest: sourceDigest)
    }

    // MARK: - dry run

    /// spec「Dry run is the default」：計畫回來了、磁碟逐位元組不變、沒有 written。
    func testDryRunWritesNothing() throws {
        let before = try bytes(olsson)
        let out = try json(try service.enrich(
            proposals: [p(citekey: "olsson1979maximum", fields: ["abstract": "An abstract"])],
            dryRun: true, includeAbsentAuthors: false))
        XCTAssertEqual(out["dryRun"] as? Bool, true)
        let it = try items(out)
        XCTAssertEqual(it.count, 1)
        XCTAssertEqual(it[0]["category"] as? String, "added")
        XCTAssertEqual(it[0]["citekey"] as? String, "olsson1979maximum")
        let adds = try XCTUnwrap(it[0]["additions"] as? [[String: Any]])
        XCTAssertEqual(adds.map { $0["key"] as? String }, ["abstract"])
        XCTAssertNil(out["written"], "dry run 沒有 written 欄位")
        XCTAssertEqual(try bytes(olsson), before, "dry run 零寫入")
    }

    // MARK: - apply

    /// 一筆以 DOI 定位、一筆以 citekey 定位；apply 後兩筆都落地、index 重建一次。
    func testApplyWritesAndRebuildsOnce() throws {
        let out = try json(try service.enrich(proposals: [
            p(doi: "10.1007/BF02293811", fields: ["abstract": "Olsson abstract"]),
            p(citekey: "cheng2025identifiability", fields: ["abstract": "Cheng abstract"], date: "2025"),
        ], dryRun: false, includeAbsentAuthors: false))
        XCTAssertEqual(out["dryRun"] as? Bool, false)
        XCTAssertEqual(out["written"] as? [String], ["cheng2025identifiability", "olsson1979maximum"])
        XCTAssertEqual(out["indexRebuilt"] as? Bool, true)
        XCTAssertNil(out["writeFailed"])
        XCTAssertEqual(try entry("olsson1979maximum").fields["abstract"], "Olsson abstract")
        let c = try entry("cheng2025identifiability")
        XCTAssertEqual(c.fields["abstract"], "Cheng abstract")
        XCTAssertEqual(c.date, "2025")
        let it = try items(out)
        XCTAssertEqual(it[0]["citekey"] as? String, "olsson1979maximum", "DOI 對回 citekey")
    }

    /// 一筆的目的檔被設成 immutable（rename 過去會被拒）：不 throw、那一筆進 writeFailed、其餘照寫、仍 rebuild。
    func testWriteFailureIsCapturedAndOthersProceed() throws {
        let doomed = LibraryStore(root: root).entityURL(id: olsson)
        try FileManager.default.setAttributes([.immutable: true], ofItemAtPath: doomed.path)
        frozen.append(doomed)
        let out = try json(try service.enrich(proposals: [
            p(citekey: "olsson1979maximum", fields: ["abstract": "will fail"]),
            p(citekey: "cheng2025identifiability", fields: ["abstract": "will land"]),
        ], dryRun: false, includeAbsentAuthors: false))
        XCTAssertEqual(out["written"] as? [String], ["cheng2025identifiability"])
        let failed = try XCTUnwrap(out["writeFailed"] as? [String: String])
        XCTAssertEqual(Array(failed.keys), ["olsson1979maximum"])
        XCTAssertFalse(failed["olsson1979maximum"]!.isEmpty, "失敗要帶原因")
        XCTAssertEqual(out["indexRebuilt"] as? Bool, true, "其餘已落地，index 要反映")
        XCTAssertEqual(try entry("cheng2025identifiability").fields["abstract"], "will land")
        XCTAssertNil(try entry("olsson1979maximum").fields["abstract"])
    }

    /// 輸入語法錯（第 2 筆兩鍵同給）→ 整批 throw、零寫入——第 1 筆合法也不寫。
    func testInputErrorRejectsWholeBatchWithZeroWrites() throws {
        let before = try bytes(cheng)
        XCTAssertThrowsError(try service.enrich(proposals: [
            p(citekey: "cheng2025identifiability", fields: ["abstract": "fine"]),
            p(citekey: "olsson1979maximum", doi: "10.1007/BF02293811", fields: ["abstract": "bad"]),
        ], dryRun: false, includeAbsentAuthors: false)) { error in
            let msg = String(describing: error)
            XCTAssertTrue(msg.contains("第 2 筆"), msg)
        }
        XCTAssertEqual(try bytes(cheng), before)
    }

    func testEmptyProposalsAreRejected() {
        XCTAssertThrowsError(try service.enrich(proposals: [], dryRun: true, includeAbsentAuthors: false))
    }

    /// 同一筆記錄在同一批被提兩次：第二筆看得到第一筆會補的鍵（`abstract` 已存在），落地一次、
    /// 兩筆的補值都在磁碟上（後寫不得洗掉先寫）。
    func testSameTargetTwiceIsAppliedInOrderAndWrittenOnce() throws {
        let out = try json(try service.enrich(proposals: [
            p(citekey: "cheng2025identifiability", fields: ["abstract": "first"]),
            p(citekey: "cheng2025identifiability", fields: ["abstract": "second", "note": "n"]),
        ], dryRun: false, includeAbsentAuthors: false))
        XCTAssertEqual(out["written"] as? [String], ["cheng2025identifiability"])
        let it = try items(out)
        XCTAssertEqual(it[1]["alreadyPresent"] as? [String], ["abstract"])
        let e = try entry("cheng2025identifiability")
        XCTAssertEqual(e.fields["abstract"], "first")
        XCTAssertEqual(e.fields["note"], "n")
    }

    /// spec「Source digests are reported, never stored」：報告回顯、`references` 不動。
    func testSourceDigestIsEchoedNotStored() throws {
        let digest = "sha256:" + String(repeating: "ab", count: 32)
        let out = try json(try service.enrich(proposals: [
            p(citekey: "cheng2025identifiability", fields: ["abstract": "x"], sourceDigest: digest),
        ], dryRun: false, includeAbsentAuthors: false))
        XCTAssertEqual(try items(out)[0]["sourceDigest"] as? String, digest)
        XCTAssertTrue(try entry("cheng2025identifiability").references.isEmpty)
    }

    /// 分類逐筆可見，且 `counts` 永遠完整——就算 items 被 itemLimit 截掉。
    func testCountsAreCompleteEvenWhenItemsAreTruncated() throws {
        let out = try json(try service.enrich(proposals: [
            p(citekey: "cheng2025identifiability", fields: ["abstract": "x"]),
            p(citekey: "nope2000z", fields: ["abstract": "x"]),
            p(citekey: "olsson1979maximum", fields: ["issn": "0033-3123"]),
        ], dryRun: true, includeAbsentAuthors: false, itemLimit: 1))
        let counts = try XCTUnwrap(out["counts"] as? [String: Int])
        XCTAssertEqual(counts["added"], 1); XCTAssertEqual(counts["notFound"], 1); XCTAssertEqual(counts["rejected"], 1)
        XCTAssertEqual(try items(out).count, 1)
        XCTAssertEqual(out["itemsTotal"] as? Int, 3)
        XCTAssertEqual(out["truncated"] as? Bool, true)
    }
}
