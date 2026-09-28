import XCTest
@testable import AkashicCore
@testable import AkashicStoreIO

/// #581：被 per-record 上限截掉的明細的出口——單筆記錄的完整明細（`PerRecordListing.full`、`perRecordIssues(from:owner:)`）。
///
/// 釘三件事：(1) 組合式的六族在 `.full` 下每一族都列滿、沒有概括句，而 `.capped`（`health(from:)`）照舊列 20 則加一句；
/// (2) 求值上限不跟著放寬——`.full` 下觸頂仍出聲，且概括句不說「每筆記錄最多列 20 組」這句在完整明細裡是假的話；
/// (3) 定址 kind 必填、不猜：找不到、同 kind 同 key 兩筆、跨 kind 同 key 都有具名的處置。
final class PerRecordFullListingTests: XCTestCase {
    private var store: LibraryStore!
    private var root: URL!
    private let over = Entry.perRecordWarningCap + 5

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("akashic-full-listing-\(UUID().uuidString)")
        store = LibraryStore(root: root); try store.ensureLayout()
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    private func verdict(_ field: String, kind: ProvenanceReference.VerdictHolderKind,
                         holder: String, literal: String) -> ProvenanceReference {
        ProvenanceReference(field: field,
                            value: ProvenanceReference.VerdictPairingValue(holderKind: kind, holder: holder, literal: literal).encoded,
                            kind: .judgement(statement: "測試用判定", restsOn: []))
    }

    private func address(_ raw: String) throws -> RecordAddress { try RecordAddress.parse(raw) }

    private func summaries(_ xs: [StoreHealth.OwnedIssue]) -> [StoreHealth.OwnedIssue] {
        xs.filter { $0.issue.message.hasPrefix(Entry.perRecordCapSummaryPrefix) }
    }

    // MARK: - 六族逐一：.capped 截、.full 不截

    /// 重複的判定記錄（`StoreHealth` 的組合式族）：25 個配對各兩筆。
    func testDuplicateVerdictRecordsAreFullyListedForOneOwner() throws {
        var o = Organization(key: "acme", names: TimelineOf([TemporalValue(value: "Acme")]))
        o.references = (1...over).flatMap { i in
            [verdict("resolution-rejected", kind: .work, holder: "w\(i)", literal: "Vee"),
             verdict("resolution-rejected", kind: .work, holder: "w\(i)", literal: "Vee")] }
        _ = try store.writeOrganization(o)
        let load = try store.load()
        let capped = store.health(from: load).duplicateVerdictRecords.filter { $0.owner == "acme" }
        XCTAssertEqual(capped.count, Entry.perRecordWarningCap, "對照：不帶 owner 時照舊截")
        let full = try store.perRecordIssues(from: load, owner: address("organization:acme"))
        let family = full.filter { $0.issue.message.hasPrefix(StoreHealth.duplicateVerdictRecordPrefix) }
        XCTAssertEqual(family.count, over, "完整明細要逐一具名：\(family.count)")
        XCTAssertEqual(Set((1...over).filter { i in family.contains { $0.issue.message.contains("work:w\(i)，") } }).count, over)
        XCTAssertTrue(summaries(full).isEmpty, "完整明細沒有列出上限的概括句：\(summaries(full).map(\.issue.message))")
    }

    /// 同一 work 多個 confirmed literal（`Venue.validate()`）與同一 venue 多條 key 邊（`Entry.validate()`）。
    func testVenueConfirmedLiteralAndEntryDuplicateEdgeFamiliesAreFullyListed() throws {
        var v = Venue(key: "alpha", type: .periodical, names: Timeline([TemporalValue(value: "Alpha Journal")]), authorized: [])
        v.references = (1...over).flatMap { i in
            [verdict("resolution-confirmed", kind: .work, holder: "w\(i)", literal: "alpha"),
             verdict("resolution-confirmed", kind: .work, holder: "w\(i)", literal: "ALPHA")] }
        var e = Entry(id: UUID(), citekey: "multi2020", type: .periodicalArticle, title: "T", authors: [.literal("A B")], date: "2020")
        e.venues = (1...over).flatMap { i in [VenueRef.key("v\(i)"), .key("v\(i)")] }
        let load = LibraryLoad(entries: [e], venues: [v])
        let cappedVenue = store.perRecordIssues(from: load, listing: .capped, only: nil).filter { $0.kind == "venue" }
        XCTAssertEqual(cappedVenue.filter { $0.issue.message.hasPrefix(Venue.confirmedLiteralAmbiguityPrefix) }.count, Entry.perRecordWarningCap)
        let fullVenue = try store.perRecordIssues(from: load, owner: address("venue:alpha"))
        XCTAssertEqual(fullVenue.filter { $0.issue.message.hasPrefix(Venue.confirmedLiteralAmbiguityPrefix) }.count, over)
        XCTAssertTrue(summaries(fullVenue).isEmpty, summaries(fullVenue).map(\.issue.message).description)
        let fullEntry = try store.perRecordIssues(from: load, owner: address("work:multi2020"))
        XCTAssertEqual(fullEntry.filter { $0.issue.message.hasPrefix(Entry.duplicateVenueEdgePrefix) }.count, over)
        XCTAssertTrue(summaries(fullEntry).isEmpty, summaries(fullEntry).map(\.issue.message).description)
        XCTAssertTrue(fullEntry.allSatisfy { $0.kind == "entry" && $0.owner == "multi2020" }, "work:<citekey> 對的是 entry 族")
    }

    /// venue 名字內容與 names 近重複（`Venue.validate()` 的兩個 error 族）。寫入閘擋得住這種記錄，所以直接組 `LibraryLoad`——
    /// 手改或舊 binary 寫進來的就是這個形。
    func testVenueNameContentAndNearDuplicateFamiliesAreFullyListed() throws {
        let bad = (1...over).map { "Bad \($0) " }                     // 尾隨空白：不是 canonical 形
        let dupPairs = (1...over).flatMap { ["Dup \($0)", "Dup \($0)"] }  // canonical 相等、無時間 → 近重複
        let v = Venue(key: "beta", type: .periodical,
                      names: Timeline((bad + dupPairs).map { TemporalValue(value: $0) }), authorized: [])
        let load = LibraryLoad(venues: [v])
        let capped = store.perRecordIssues(from: load, listing: .capped, only: nil)
        XCTAssertEqual(capped.filter { $0.issue.message.contains("canonical 形") }.count, Entry.perRecordWarningCap)
        XCTAssertEqual(capped.filter { $0.issue.message.contains("有兩筆近重複") }.count, Entry.perRecordWarningCap)
        let full = try store.perRecordIssues(from: load, owner: address("venue:beta"))
        XCTAssertEqual(full.filter { $0.issue.message.contains("canonical 形") }.count, over)
        XCTAssertEqual(full.filter { $0.issue.message.contains("有兩筆近重複") }.count, over)
        XCTAssertTrue(summaries(full).isEmpty, summaries(full).map(\.issue.message).description)
    }

    /// person 近重複（`AuthorizedNames.validateNearDuplicates`）：25 組、每組兩個 matchingKey 相同而 `NameIdentity` 不同的名字。
    func testPersonNearDuplicateGroupsAreFullyListed() throws {
        let names = (1...over).flatMap { ["Fann-C\($0)", "Fann\u{2010}C\($0)"] }
        let capped = AuthorizedNames.validateNearDuplicates(names: names, ownerKey: "fann")
        XCTAssertEqual(capped.filter { $0.message.contains("近重複") && !$0.message.hasPrefix(Entry.perRecordCapSummaryPrefix) }.count,
                       Entry.perRecordWarningCap)
        let full = AuthorizedNames.validateNearDuplicates(names: names, ownerKey: "fann", listing: .full)
        XCTAssertEqual(full.count, over, "一組一則、全部列出、沒有概括句：\(full.count)")
        XCTAssertFalse(full.contains { $0.message.hasPrefix(Entry.perRecordCapSummaryPrefix) })
    }

    // MARK: - 求值上限不跟著放寬

    /// person：一組 102 個名字（5,151 對 > 組內 5,000 對）——`.full` 下照樣只評估 5,000 對，概括句仍出現，而且不說
    /// 「每筆記錄最多列 20 組」（完整明細沒有那一層，照抄是假話）。
    func testEvaluationBudgetStillAppliesAndTheSummaryDoesNotClaimAListingCap() throws {
        let hyphens = ["-", "\u{2010}", "\u{2011}", "\u{2012}", "\u{2013}", "\u{2014}", "\u{2212}"]
        var names: [String] = []
        outer: for z in 0..<40 { for h in hyphens { names.append("Fann" + h + "C" + String(repeating: "\u{200B}", count: z)); if names.count == 102 { break outer } } }
        let full = AuthorizedNames.validateNearDuplicates(names: names, ownerKey: "fann", listing: .full)
        let listed = try XCTUnwrap(full.first { !$0.message.hasPrefix(Entry.perRecordCapSummaryPrefix) })
        XCTAssertTrue(listed.message.contains("5000"), "組內求值上限照舊：\(listed.message)")
        let summary = try XCTUnwrap(full.first { $0.message.hasPrefix(Entry.perRecordCapSummaryPrefix) }, "求值觸頂仍要出聲")
        XCTAssertTrue(summary.message.contains("單筆完整明細不套每筆 \(Entry.perRecordWarningCap) 組的列出上限"), summary.message)
        XCTAssertFalse(summary.message.contains("每筆記錄最多列"), "完整明細裡這句是假話：\(summary.message)")
        XCTAssertTrue(summary.message.contains("整筆至多 100000 對"), summary.message)
        let capped = AuthorizedNames.validateNearDuplicates(names: names, ownerKey: "fann")
        XCTAssertTrue(capped.contains { $0.message.contains("每筆記錄最多列 \(Entry.perRecordWarningCap) 組") }, "對照：預設模式照舊這樣說")
    }

    // MARK: - 與全庫路徑同一份組裝

    /// 沒有任何記錄被截時，單筆明細＝全庫 per-record 問題依 (族名, key) 篩出來的那一段，逐則同序（error 先排）。
    /// 兩份組裝清單會分岔——這一條讓分岔出聲。
    func testOwnerSliceEqualsTheWholeStoreSliceWhenNothingIsCapped() throws {
        try store.writeEntry(Entry(id: UUID(), citekey: "a2020a", type: .periodicalArticle, title: " ", authors: [.literal("A B")], date: "2020"))
        var o = Organization(key: "acme", names: TimelineOf([TemporalValue(value: "Acme")]))
        o.references = [verdict("resolution-confirmed", kind: .work, holder: "gone", literal: "Acme")]   // 死 verdict：跨記錄掃描
        _ = try store.writeOrganization(o)
        let load = try store.load()
        let all = store.health(from: load).perRecordIssues
        XCTAssertTrue(store.health(from: load).cappedRecords.isEmpty)
        for (raw, kind, key) in [("work:a2020a", "entry", "a2020a"), ("organization:acme", "organization", "acme")] {
            let slice = all.filter { $0.kind == kind && $0.owner == key }.map { "\($0.issue.severity)|\($0.issue.message)" }
            let mine = try store.perRecordIssues(from: load, owner: address(raw)).map { "\($0.issue.severity)|\($0.issue.message)" }
            XCTAssertFalse(slice.isEmpty, "fixture 要真的有問題：\(raw)")
            XCTAssertEqual(mine, slice, raw)
        }
    }

    // MARK: - 定址：kind 必填、不猜

    func testAddressRequiresAKnownKindAndAWellFormedKey() {
        for raw in ["acme", "Organization:acme", "library:main", "entry:a2020a", "person:Bad Key", "person:", "divergence:not-a-uuid", ":acme"] {
            XCTAssertThrowsError(try RecordAddress.parse(raw), raw) { error in
                XCTAssertTrue(displaySafeErrorText(error).contains("owner"), displaySafeErrorText(error))
            }
        }
        XCTAssertThrowsError(try RecordAddress.parse("acme")) { error in
            let bare = displaySafeErrorText(error)
            XCTAssertTrue(bare.contains("沒有 kind") && bare.contains("不猜"), bare)
        }
        let id = UUID()
        XCTAssertEqual(try? RecordAddress.parse("divergence:" + id.uuidString.lowercased()),
                       RecordAddress(kind: .divergence, key: id.uuidString), "UUID 文法不分大小寫，正規化成大寫")
        XCTAssertEqual(try? RecordAddress.parse("work:a2020a").ownedIssueKind, "entry")
    }

    /// 不同 kind 共用一個 key（2026-09-28 live store：organization 與 venue 共用 2 個）——kind 決定是哪一筆，另一筆的問題不混進來。
    func testSameKeyInTwoKindsIsDisambiguatedByKind() throws {
        let org = Organization(key: "shared", names: TimelineOf([TemporalValue(value: "Shared Org")]),
                               unknownFields: [UnknownField(key: "org_only_field", raw: "org_only_field: x\n")])
        let venue = Venue(key: "shared", type: .periodical, names: Timeline([TemporalValue(value: "Shared ")]), authorized: [])
        let load = LibraryLoad(organizations: [org], venues: [venue])
        let asOrg = try store.perRecordIssues(from: load, owner: address("organization:shared"))
        let asVenue = try store.perRecordIssues(from: load, owner: address("venue:shared"))
        XCTAssertTrue(asOrg.allSatisfy { $0.kind == "organization" } && asOrg.contains { $0.issue.message.contains("org_only_field") }, asOrg.map(\.issue.message).description)
        XCTAssertTrue(asVenue.allSatisfy { $0.kind == "venue" } && asVenue.contains { $0.issue.message.contains("canonical 形") }, asVenue.map(\.issue.message).description)
    }

    func testNotFoundAndDuplicateKeysAreRefusedNotGuessed() throws {
        let v = Venue(key: "twin", type: .periodical, names: Timeline([TemporalValue(value: "Twin")]), authorized: [])
        let v2 = Venue(key: "twin", type: .periodical, names: Timeline([TemporalValue(value: "Twin Two")]), authorized: [])
        let load = LibraryLoad(venues: [v, v2], quarantined: [QuarantinedFile(file: "broken.yaml", reason: "壞的")])
        XCTAssertThrowsError(try store.perRecordIssues(from: load, owner: address("venue:twin"))) { error in
            let m = displaySafeErrorText(error)
            XCTAssertTrue(m.contains("有 2 筆") && m.contains("不猜"), m)
            // 重複的 key 本身指不到檔——兩筆的 UUID 都要說出來；venue 的重複 key 沒有跨記錄檢查會報，訊息不得假稱 validate 會列出
            XCTAssertTrue(m.contains(v.id.uuidString) && m.contains(v2.id.uuidString), m)
            XCTAssertTrue(m.contains("目前沒有跨記錄檢查報 venue 的重複 key"), m)
        }
        // citekey 的重複有跨記錄 error——那時訊息指路 validate
        let e1 = Entry(id: UUID(), citekey: "twin2020", type: .periodicalArticle, title: "T", authors: [.literal("A B")], date: "2020")
        let e2 = Entry(id: UUID(), citekey: "twin2020", type: .periodicalArticle, title: "U", authors: [.literal("A B")], date: "2020")
        XCTAssertThrowsError(try store.perRecordIssues(from: LibraryLoad(entries: [e1, e2]), owner: address("work:twin2020"))) { error in
            let m = displaySafeErrorText(error)
            XCTAssertTrue(m.contains("有 2 筆") && m.contains("以跨記錄 error 列出"), m)
        }
        XCTAssertThrowsError(try store.perRecordIssues(from: load, owner: address("venue:nobody"))) { error in
            let m = displaySafeErrorText(error)
            XCTAssertTrue(m.contains("找不到") && m.contains("1 個檔被 quarantine"), m)
        }
        XCTAssertThrowsError(try store.perRecordIssues(from: load, owner: address("person:twin")), "venue 有這個 key 不代表 person 有")
    }
}
