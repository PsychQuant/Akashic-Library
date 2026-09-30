import XCTest
@testable import AkashicCore
@testable import AkashicStoreIO
@testable import AkashicSQLite
@testable import AkashicZoteroImport

/// Zotero 匯入新建的 work 與另一筆 work 共用 DOI 時照建，並記一筆沒有判斷的歧異提名（#611，使用者 2026-10-01 裁決）。
///
/// DOI 相等只是提名：勘誤與原文共用 DOI、一筆作品可有多個 DOI（#394）。所以這裡每一條都同時釘兩件事——提名寫了，
/// 而且**只是**提名（兩筆都還在、沒有合併、沒有掛附加來源、記錄沒有判斷）。
final class ZoteroDOINominationTests: XCTestCase {
    var dir: URL!
    var store: LibraryStore!
    var fixture: ZoteroFixture!
    /// `ZoteroFixture.seedStandard` 裡那篇 article（KEYART01，library 1）的 DOI。
    let doi = "10.1017/psy.2025.1"

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("akashic-zdoi-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        store = LibraryStore(root: dir.appendingPathComponent("library"))
        try store.ensureLayout()
        fixture = try ZoteroFixture(dir: dir)
        try fixture.seedStandard()
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    private func runImport(at t: TimeInterval = 1_753_000_000) throws -> ImportReport {
        try ZoteroImporter(store: store).run(zoteroDB: fixture.dbURL, now: Date(timeIntervalSince1970: t))
    }

    /// Zotero 端另一個條目：不同的 key（預設在群組 library 5），可帶 DOI。
    private func addItem(_ item: Int, key: String, library: Int = 5, title: String, doi: String?) throws {
        try fixture.db.execute("INSERT INTO items VALUES (?,1,?,3,?)", bind: [item, key, library])
        try fixture.addField(item: item, field: 1, value: title, valueID: item * 10)
        if let doi { try fixture.addField(item: item, field: 6, value: doi, valueID: item * 10 + 1) }
    }

    private func entry(zoteroKey: String) throws -> Entry {
        try XCTUnwrap(try store.load().entries.first { $0.provenance?.zoteroKey == zoteroKey }, zoteroKey)
    }

    private func onlyDivergence() throws -> Divergence {
        let all = try store.load().divergences
        XCTAssertEqual(all.count, 1, "\(all.map(\.question))")
        return try XCTUnwrap(all.first)
    }

    // MARK: - (a) 跨 library、同 DOI

    /// 既有的 work（library 1）與群組 library 以另一個 key 出現的同一篇：照建新的一筆，記一筆候選是這兩筆的歧異提名。
    func testNewWorkSharingADOIWithAnExistingWorkIsCreatedAndNominated() throws {
        let first = try runImport()
        XCTAssertEqual(first.doiNominations, [], "只有一筆帶這個 DOI 時沒有提名")
        let article = try entry(zoteroKey: "KEYART01")
        try addItem(31, key: "KEYGRP01", title: "Identifiability of polychoric models (group copy)", doi: doi)

        let report = try runImport(at: 1_753_100_000)

        let group = try entry(zoteroKey: "KEYGRP01")
        XCTAssertEqual(report.created, [group.citekey], "照建：DOI 相等不是同一性證據")
        let d = try onlyDivergence()
        XCTAssertEqual(report.doiNominations, [DOINomination(created: group.citekey, other: article.citekey, dois: [doi],
                                                             status: .recorded, divergenceID: d.id)])
        XCTAssertEqual(d.candidates.map(\.key).sorted(), [article.citekey, group.citekey].sorted())
        XCTAssertEqual(Set(d.candidates.map(\.shape)), [.work])
        XCTAssertNil(d.judgement, "只是提名：判斷與傾向屬 resolve-divergence")
        XCTAssertEqual(d.id, DeterministicUUID.forDivergence(candidateKeys: [article.citekey, group.citekey]))
        XCTAssertTrue(d.question.contains(doi) && d.question.contains("resolve-divergence"), d.question)
        let after = try entry(zoteroKey: "KEYART01")
        XCTAssertEqual(after, article, "既有那一筆一個位元組都不動——不合併、不掛附加來源")
        XCTAssertEqual(after.additionalProvenance, [])
    }

    // MARK: - (b) 再匯入

    /// 再匯入不新建，所以不再提名；既有的記錄一個位元組都不動。
    func testReimportDoesNotRecordThePairAgain() throws {
        _ = try runImport()
        try addItem(31, key: "KEYGRP01", title: "Group copy", doi: doi)
        _ = try runImport(at: 1_753_100_000)
        let d = try onlyDivergence()
        let file = store.entityURL(id: d.id)
        let bytes = try Data(contentsOf: file)

        let again = try runImport(at: 1_753_200_000)

        XCTAssertEqual(again.created, [])
        XCTAssertEqual(again.doiNominations, [], "不新建就不提名——被 dismiss 的一對不會被下一趟重記")
        XCTAssertEqual(try store.load().divergences.count, 1)
        XCTAssertEqual(try Data(contentsOf: file), bytes)
    }

    /// 新建時已有一筆同一組候選的記錄（新建的那一筆被刪掉後重建，citekey 相同）：報 alreadyRecorded、指向那一筆，不重寫——
    /// 重寫會換掉 question，而那筆記錄可能已經帶著人補上的判斷。
    func testRecreatedWorkFindsItsExistingRecordAndLeavesItAlone() throws {
        _ = try runImport()
        let article = try entry(zoteroKey: "KEYART01")
        try addItem(31, key: "KEYGRP01", title: "Group copy", doi: doi)
        _ = try runImport(at: 1_753_100_000)
        let group = try entry(zoteroKey: "KEYGRP01")
        let d = try onlyDivergence()
        let bytes = try Data(contentsOf: store.entityURL(id: d.id))
        try FileManager.default.removeItem(at: store.entityURL(id: group.id))

        let report = try runImport(at: 1_753_200_000)

        XCTAssertEqual(report.created, [group.citekey], "前提：同一個 citekey 重建")
        XCTAssertEqual(report.doiNominations, [DOINomination(created: group.citekey, other: article.citekey, dois: [doi],
                                                             status: .alreadyRecorded, divergenceID: d.id)])
        XCTAssertEqual(try store.load().divergences.count, 1)
        XCTAssertEqual(try Data(contentsOf: store.entityURL(id: d.id)), bytes, "既有的記錄不重寫")
    }

    /// 更大的一組已經涵蓋這一對時同樣算已記錄；更小的一組不存在（一對已是最小的候選組）。同一組優先於更大的一組；別的形狀不算。
    func testCoveringRecordPrefersTheExactPairThenASuperset() {
        func record(_ keys: [String], _ shape: EntityKind = .work) -> Divergence {
            Divergence(id: DeterministicUUID.forDivergence(candidateKeys: keys), question: "q",
                       candidates: keys.map { DivergenceCandidate(key: $0, shape: shape) })
        }
        let superset = record(["a", "b", "c"])
        let exact = record(["a", "b"])
        let person = record(["a", "b", "d"], .person)
        XCTAssertEqual(DOITwinNomination.coveringRecord(["a", "b"], in: [superset])?.id, superset.id)
        XCTAssertEqual(DOITwinNomination.coveringRecord(["a", "b"], in: [superset, exact])?.id, exact.id)
        XCTAssertNil(DOITwinNomination.coveringRecord(["a", "b"], in: [person]), "別的形狀不涵蓋 work 的一對")
        XCTAssertNil(DOITwinNomination.coveringRecord(["a", "b"], in: [record(["a", "c"])]))
    }

    // MARK: - (c) 同一趟新建兩筆

    /// 同一趟新建的兩筆共用 DOI：記一筆，只從一邊記（created 是 citekey 較小的那一筆）。
    func testTwoNewWorksSharingADOIInOneImportAreNominatedOnce() throws {
        try addItem(31, key: "KEYGRP01", title: "Group copy", doi: doi)

        let report = try runImport()

        let article = try entry(zoteroKey: "KEYART01")
        let group = try entry(zoteroKey: "KEYGRP01")
        XCTAssertEqual(Set(report.created), [article.citekey, group.citekey, "chen2004matrix"])
        let d = try onlyDivergence()
        let pair = [article.citekey, group.citekey].sorted()
        XCTAssertEqual(report.doiNominations, [DOINomination(created: pair[0], other: pair[1], dois: [doi],
                                                             status: .recorded, divergenceID: d.id)])
        XCTAssertNil(d.judgement)
    }

    // MARK: - (d) 勘誤與原文共用 DOI

    /// 勘誤在同一個 library 以另一個 key 出現、帶著原文的 DOI：兩筆都在、只記提名，不合併、不判定。
    func testErratumSharingItsOriginalsDOIIsOnlyNominated() throws {
        _ = try runImport()
        let original = try entry(zoteroKey: "KEYART01")
        try addItem(40, key: "KEYERR01", library: 1, title: "Correction to: Identifiability of polychoric models", doi: doi)

        let report = try runImport(at: 1_753_100_000)

        let erratum = try entry(zoteroKey: "KEYERR01")
        XCTAssertEqual(report.doiNominations.map(\.status), [.recorded])
        let withDOI = try store.load().entries.filter { $0.canonicalDOIs.map(\.normalized).contains(doi) }
        XCTAssertEqual(Set(withDOI.map(\.citekey)), [original.citekey, erratum.citekey], "兩筆都在")
        XCTAssertEqual(try entry(zoteroKey: "KEYART01"), original, "原文不動")
        XCTAssertEqual(erratum.title, "Correction to: Identifiability of polychoric models", "勘誤保有自己的書目欄位")
        let d = try onlyDivergence()
        XCTAssertNil(d.judgement, "提名不帶判斷")
    }

    // MARK: - (e) 無法唯一定位的既有候選

    /// 既有那一筆的 citekey 重複（#627）：不點名它、報 unlocatable；同一個 DOI 的另一筆可定位的照常提名。
    func testUnlocatableExistingWorkIsReportedNotNamed() throws {
        _ = try runImport()
        let article = try entry(zoteroKey: "KEYART01")
        var twin = article
        twin.id = UUID()
        twin.provenance = nil
        try store.writeEntry(twin)   // 同 citekey、另一個 id
        var wos = Entry(id: UUID(), citekey: "wos2025identifiability", type: .periodicalArticle, title: "From WoS")
        wos.doi = [try XCTUnwrap(DOI(doi))]
        try store.writeEntry(wos)
        try addItem(31, key: "KEYGRP01", title: "Group copy", doi: doi)

        let report = try runImport(at: 1_753_100_000)

        let group = try entry(zoteroKey: "KEYGRP01")
        XCTAssertEqual(report.doiNominations.map { "\($0.other):\($0.status.rawValue)" },
                       ["\(article.citekey):unlocatable", "wos2025identifiability:recorded"].sorted())
        XCTAssertNil(report.doiNominations.first { $0.status == .unlocatable }?.divergenceID)
        let d = try onlyDivergence()
        XCTAssertEqual(d.candidates.map(\.key).sorted(), [group.citekey, "wos2025identifiability"].sorted(),
                       "無法唯一定位的那一筆不得出現在候選裡")
    }

    // MARK: - (f) 沒有 DOI／DOI 不同

    func testNoDOIOrADifferentDOINominatesNothing() throws {
        _ = try runImport()
        try addItem(31, key: "KEYGRP01", title: "Identifiability of polychoric models", doi: nil)
        try addItem(32, key: "KEYGRP02", title: "Identifiability of polychoric models", doi: "10.1017/psy.2025.2")

        let report = try runImport(at: 1_753_100_000)

        XCTAssertEqual(report.created.count, 2, "兩筆都新建")
        XCTAssertEqual(report.doiNominations, [])
        XCTAssertEqual(try store.load().divergences, [])
    }

    // MARK: - 多個 DOI

    /// 既有那一筆有兩個 DOI、新建的只帶其中一個：一對、列出共用的那一個。
    func testWorkWithSeveralDOIsPairsOnTheSharedOne() throws {
        var multi = Entry(id: UUID(), citekey: "multi2025identifiability", type: .periodicalArticle, title: "Two DOIs")
        multi.doi = [try XCTUnwrap(DOI("10.9999/jstor.1")), try XCTUnwrap(DOI(doi))]
        try store.writeEntry(multi)

        let report = try runImport()

        let article = try entry(zoteroKey: "KEYART01")
        XCTAssertEqual(report.doiNominations.map { [$0.created, $0.other] + $0.dois },
                       [[article.citekey, "multi2025identifiability", doi]])
        XCTAssertEqual(report.doiNominations.first?.status, .recorded)
    }

    // MARK: - 比的是這一趟寫完的樣子

    /// pull 把既有那一筆的 DOI 改成新值、同一趟新建的條目帶著新值：比對的是寫完之後的 DOI，不是載入時的。
    func testComparisonSeesDOIsWrittenEarlierInTheSameImport() throws {
        _ = try runImport()
        let article = try entry(zoteroKey: "KEYART01")
        let newDOI = "10.1017/psy.2025.99"
        try fixture.db.execute("UPDATE items SET version = 6 WHERE itemID = 10")
        try fixture.db.execute("UPDATE itemDataValues SET value = ? WHERE valueID = 105", bind: [newDOI])
        try addItem(31, key: "KEYGRP01", title: "Group copy", doi: newDOI)

        let report = try runImport(at: 1_753_100_000)

        XCTAssertEqual(report.updated, [article.citekey], "前提：既有那一筆這一趟改了 DOI")
        XCTAssertEqual(report.doiNominations.map { [$0.other] + $0.dois }, [[article.citekey, newDOI]])
    }

    // MARK: - 寫不進去

    /// legacy 佈局的 store 寫不了歧異記錄：那一對報 failed 與原因，匯入照建、不中止。
    func testNominationThatCannotBeWrittenIsReportedAndTheImportStillCreates() throws {
        try makeLegacyDirectories(in: store.root)
        try StoreVersion.write(root: store.root, format: 1)
        var wos = Entry(id: UUID(), citekey: "wos2025identifiability", type: .periodicalArticle, title: "From WoS")
        wos.doi = [try XCTUnwrap(DOI(doi))]
        try store.writeEntry(wos)

        let report = try runImport()

        XCTAssertEqual(report.created.count, 2, "匯入照建：\(report.writeFailed)")
        let row = try XCTUnwrap(report.doiNominations.first)
        XCTAssertEqual(report.doiNominations.count, 1)
        XCTAssertEqual(row.status, .failed)
        XCTAssertNil(row.divergenceID)
        XCTAssertFalse((row.error ?? "").isEmpty, "失敗要說原因")
        XCTAssertEqual(try store.load().divergences, [])
    }
}
