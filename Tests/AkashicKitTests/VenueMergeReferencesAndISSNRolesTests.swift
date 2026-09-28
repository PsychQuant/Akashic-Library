import XCTest
import Foundation
@testable import AkashicCore
@testable import AkashicStoreIO

/// venue 合併與 #587 的兩個寫入面之間的耦合（#587 R1 verify）。
///
/// #587 讓 `add_issn`／`add_venue.issn` 帶得了角色、讓通用 `references` 面寫得進 `field: issn`／`names` 的來源記錄——而
/// `akashic-verify-venue` 的查證流程會對**每一個**寫進去的號附一筆來源。「查證兩筆是不是同一本刊」又正是合併的前置動作，
/// 於是兩個耦合被四席獨立指出（regression／requirements／logic／DA，含真 binary 重現）：
///
/// 1. `fieldsLostByMerging` 對非 verdict 的 reference 比位元組，兩次取得的日期或 url 必然不同——每個查證過的被併者都合併不了，
///    而拒絕訊息說「沒有工具面能搬」對 issn／names 已經是假的。現在 `field: issn`／`names` 的 reference 隨合併逐位元組搬過去。
/// 2. ISSN 的**角色**不在合併的比較裡：倖存者無角色而被併者有 → 角色靜默消失；兩邊矛盾 → 倖存者靜默贏。現在兩種都算失去，
///    具名拒絕、出路逐格寫明。
final class VenueMergeReferencesAndISSNRolesTests: XCTestCase {
    var root: URL!
    var store: LibraryStore!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("akashic-venue-merge-refs-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("entities"), withIntermediateDirectories: true)
        try StoreVersion.write(root: root, format: StoreVersion.supported)
        GitFixture.initRepo(root)
        store = LibraryStore(root: root)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    private let digest = "sha256:" + String(repeating: "ab", count: 32)
    private let otherDigest = "sha256:" + String(repeating: "cd", count: 32)

    private func issn(_ s: String, _ role: String? = nil) throws -> ISSN {
        let base = try XCTUnwrap(ISSN(s))
        return role.map { base.withQualifier($0) } ?? base
    }
    private func retrieval(_ field: String, value: String?, retrieved: String) -> ProvenanceReference {
        ProvenanceReference(field: field, value: value,
                            kind: .retrieval(url: "https://portal.issn.org/resource/ISSN/0003-066X", retrieved: retrieved,
                                             status: 200, mediaType: "text/html", content: digest))
    }
    private func judgement(_ field: String, value: String?, statement: String = "刊名頁") -> ProvenanceReference {
        ProvenanceReference(field: field, value: value, kind: .judgement(statement: statement, restsOn: [digest]))
    }

    @discardableResult
    private func seed(keeper: Venue, doomed: [Venue]) throws -> Divergence {
        try store.writeVenue(keeper)
        for d in doomed { try store.writeVenue(d) }
        var work = Entry(id: UUID(), citekey: "shih2025a", type: .periodicalArticle,
                         title: "A note", authors: [.literal("Shih, J.")], date: "2025")
        work.venues = [.key(doomed[0].key)]
        try store.writeEntry(work)
        let d = Divergence(id: UUID(), question: "同一本刊嗎",
                           candidates: ([keeper] + doomed).map { DivergenceCandidate(key: $0.key, shape: .venue) })
        try store.writeDivergence(d)
        GitFixture.commitAll(root, message: "seed")
        return d
    }

    private func venue(_ key: String, names: [String], issn: [ISSN] = [], refs: [ProvenanceReference] = []) -> Venue {
        var v = Venue(key: key, type: .periodical, names: Timeline(names.map { TemporalValue(value: $0) }),
                      authorized: [names[0]], issn: issn)
        v.references = refs
        return v
    }

    private func keeperAfter(_ key: String = "k") throws -> Venue {
        try XCTUnwrap(LibraryStore(root: root).load().venues.first { $0.key == key })
    }

    // MARK: - references 隨合併搬過去

    /// 被併者帶 `field: issn` 與 `field: names` 的來源記錄（查證流程的產物）：合併成功，兩筆逐位元組搬到倖存者，
    /// 報告與 dry-run 都說出來。R1 之前這一格整個合併被拒（除非倖存者恰好有位元組相同的一筆）。
    func testDoomedISSNAndNamesReferencesAreCarriedToTheKeeper() throws {
        let issnRef = retrieval("issn", value: "0003-066X", retrieved: "2026-09-29")
        let nameRef = judgement("names", value: "Doomed Journal")
        let keeper = venue("k", names: ["Keeper Journal"], issn: [try issn("0003-066X")])
        let doomed = venue("d", names: ["Doomed Journal"], issn: [try issn("0003-066X")], refs: [issnRef, nameRef])
        let d = try seed(keeper: keeper, doomed: [doomed])
        let preview = try store.previewResolveDivergence(id: d.id, survivor: "k", overrideReason: nil)
        XCTAssertEqual(preview.referencesCarried.count, 2, "dry-run 也要預告搬了什麼：\(preview.referencesCarried)")
        let report = try store.resolveDivergence(id: d.id, survivor: "k")
        XCTAssertFalse(report.hasFailures, report.failures.joined(separator: "\n"))
        XCTAssertEqual(report.referencesCarried, preview.referencesCarried, "dry-run 與實跑同一份")
        XCTAssertTrue(report.referencesCarried.contains { $0.contains("issn") && $0.contains("0003-066X") && $0.contains("retrieval") },
                      "\(report.referencesCarried)")
        XCTAssertTrue(report.referencesCarried.contains { $0.contains("names") && $0.contains("Doomed Journal") && $0.contains("judgement") },
                      "\(report.referencesCarried)")
        let k = try keeperAfter()
        XCTAssertEqual(Set(k.references.map(\.byteExactKey)), [issnRef.byteExactKey, nameRef.byteExactKey], "逐位元組原樣搬")
        XCTAssertEqual(Set(try LibraryStore(root: root).load().venues.map(\.key)), ["k"], "被併檔刪了")
        XCTAssertNoThrow(try k.validateReferenceAttachment(), "搬過去的不得成孤兒")
    }

    /// 倖存者已有位元組相同的一筆：不重複搬；兩個被併者各帶一份相同的：只搬一份。
    func testCarriedReferencesAreDeduplicatedByBytes() throws {
        let shared = retrieval("issn", value: "0003-066X", retrieved: "2026-09-29")
        let keeper = venue("k", names: ["Keeper Journal"], issn: [try issn("0003-066X")], refs: [shared])
        let d1 = venue("d1", names: ["D1 Journal"], issn: [try issn("0003-066X")], refs: [shared])
        let own = retrieval("issn", value: "0003-066X", retrieved: "2026-10-01")
        let d2 = venue("d2", names: ["D2 Journal"], issn: [try issn("0003-066X")], refs: [own])
        let d3 = venue("d3", names: ["D3 Journal"], issn: [try issn("0003-066X")], refs: [own])
        let d = try seed(keeper: keeper, doomed: [d1, d2, d3])
        let report = try store.resolveDivergence(id: d.id, survivor: "k")
        XCTAssertFalse(report.hasFailures, report.failures.joined(separator: "\n"))
        XCTAssertEqual(report.referencesCarried.count, 1, "倖存者已有的不算搬、兩個被併者的相同一筆只搬一份：\(report.referencesCarried)")
        XCTAssertEqual(try keeperAfter().references.count, 2)
    }

    /// `paginated` 的判定沒有工具面能搬：照舊拒絕，而訊息**只**對這一格說「沒有工具面」；同一個被併者的 issn 來源記錄不在清單裡
    /// （它會被搬）。R1 之前的訊息把 issn／names 也算進「沒有工具面」，是假話。
    func testPaginatedReferenceStillRefusesAndOnlyItIsNamed() throws {
        let paginatedRef = ProvenanceReference(field: "paginated", value: "true",
                                               kind: .judgement(statement: "出版商頁逐篇有頁碼", restsOn: [digest]))
        var doomed = venue("d", names: ["Doomed Journal"], issn: [try issn("0003-066X")],
                           refs: [retrieval("issn", value: "0003-066X", retrieved: "2026-09-29"), paginatedRef])
        doomed.paginated = true
        let keeper = venue("k", names: ["Keeper Journal"], issn: [try issn("0003-066X")])
        let d = try seed(keeper: keeper, doomed: [doomed])
        XCTAssertThrowsError(try store.previewResolveDivergence(id: d.id, survivor: "k", overrideReason: nil)) { err in
            let s = (err as? LocalizedError)?.errorDescription ?? String(describing: err)
            XCTAssertTrue(s.contains("references（1 筆，欄位：paginated"), "只有 paginated 一筆：\(s)")
            XCTAssertTrue(s.contains("沒有工具面能把它逐位元組搬到倖存者"), s)
            XCTAssertFalse(s.contains("欄位：issn"), "issn 的來源記錄會被搬，不在拒絕清單：\(s)")
        }
        XCTAssertEqual(Set(try LibraryStore(root: root).load().venues.map(\.key)), ["k", "d"], "零寫入")
    }

    /// 手改出來的 `field: authorized`／`note` reference（通用面不收，只有手改寫得出來）：合併照舊拒絕，且不說它們是 issn／names 的搬不了。
    func testHandWrittenAuthorizedReferenceRefusesTheMergeAndSaysWhy() throws {
        let doomed = venue("d", names: ["Doomed Journal"], issn: [try issn("0003-066X")],
                           refs: [judgement("authorized", value: "Doomed Journal")])
        let keeper = venue("k", names: ["Keeper Journal"], issn: [try issn("0003-066X")])
        let d = try seed(keeper: keeper, doomed: [doomed])
        XCTAssertThrowsError(try store.previewResolveDivergence(id: d.id, survivor: "k", overrideReason: nil)) { err in
            let s = (err as? LocalizedError)?.errorDescription ?? String(describing: err)
            XCTAssertTrue(s.contains("欄位：authorized") && s.contains("通用 references 面只收 issn、names"), s)
        }
    }

    // MARK: - ISSN 的角色

    private func mergeError(keeperRole: String?, doomedRole: String?) throws -> String? {
        let keeper = venue("k", names: ["Keeper Journal"], issn: [try issn("0003-066X", keeperRole)])
        let doomed = venue("d", names: ["Doomed Journal"], issn: [try issn("0003-066X", doomedRole)])
        let d = try seed(keeper: keeper, doomed: [doomed])
        do {
            _ = try store.previewResolveDivergence(id: d.id, survivor: "k", overrideReason: nil)
            return nil
        } catch {
            return (error as? LocalizedError)?.errorDescription ?? String(describing: error)
        }
    }

    /// 倖存者沒記角色、被併者記了：角色會隨檔案消失——拒絕，出路是先用 `--add-issn "號 (角色)"` 在倖存者補上（add_issn 填缺席的格）。
    func testDoomedRoleThatTheKeeperLacksRefusesTheMerge() throws {
        let s = try XCTUnwrap(try mergeError(keeperRole: nil, doomedRole: "print"))
        XCTAssertTrue(s.contains("0003-066X") && s.contains("角色 print") && s.contains("倖存者沒記角色"), s)
        XCTAssertTrue(s.contains("--add-issn \"0003-066X (print)\""), "出路要說出補角色的指令：\(s)")
    }

    /// 兩邊角色矛盾：倖存者靜默贏是最壞的形狀——拒絕，出路是 remove 再 add，並說明移除會連帶刪掉指向那個號的 reference。
    func testConflictingRolesRefuseTheMerge() throws {
        let s = try XCTUnwrap(try mergeError(keeperRole: "print", doomedRole: "electronic"))
        XCTAssertTrue(s.contains("角色兩邊不同") && s.contains("electronic") && s.contains("print"), s)
        XCTAssertTrue(s.contains("--remove-issn") && s.contains("--add-issn") && s.contains("reference"), "出路與連帶刪除都要說：\(s)")
    }

    /// 遷移留下的認不出的角色（`Online`）：add_issn 收不下，出路是手改 YAML——訊息不能叫人去用 add-issn。
    func testUnrecognisedRoleSaysTheFixIsAHandEdit() throws {
        let s = try XCTUnwrap(try mergeError(keeperRole: nil, doomedRole: "Online"))
        XCTAssertTrue(s.contains("Online") && s.contains("不是標準三值") && s.contains("手改"), s)
        XCTAssertFalse(s.contains("--add-issn \"0003-066X (Online)\""), s)
    }

    /// 不算失去的三格：角色相同、倖存者有而被併者沒有、兩邊都沒有——照常合併。
    func testEqualOrKeeperOnlyOrAbsentRolesMergeFine() throws {
        for (label, k, d) in [("相同", "print", "print"), ("倖存者有被併者無", "print", nil), ("都沒有", nil, nil)] as [(String, String?, String?)] {
            let s = try mergeError(keeperRole: k, doomedRole: d)
            XCTAssertNil(s, "\(label)：\(s ?? "")")
            // 每一輪換一份乾淨的 store
            try tearDownWithError()
            try setUpWithError()
        }
    }
}
