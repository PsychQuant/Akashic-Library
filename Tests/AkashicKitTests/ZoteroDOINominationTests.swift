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
    /// 門檻寫成字面值、不引用常數：測試若引用 `DOINomination.maxGroupSize`，把常數改大時固定的群組大小跟著變大，變異就存活（負控 M3 實測）。
    let threshold = 10

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

    /// 更大的一組已經涵蓋這一對時同樣算已記錄；更小的一組不存在（一對已是最小的候選組）。同一組優先於更大的一組；別的形狀不算——
    /// **包括同一個 id 的那一筆**：歧異記錄的 id 只雜湊候選 key、不含形狀，person 的 `{a, b}` 與 work 的 `{a, b}` 同 id
    /// （#611 R1 verify 第 1／21 列：先前「同一組」那個分支只比 id，把別種形狀的記錄當成已涵蓋這一對 work）。
    func testCoveringRecordPrefersTheExactPairThenASuperset() {
        func record(_ keys: [String], _ shape: EntityKind = .work) -> Divergence {
            Divergence(id: DeterministicUUID.forDivergence(candidateKeys: keys), question: "q",
                       candidates: keys.map { DivergenceCandidate(key: $0, shape: shape) })
        }
        func covering(_ pair: [String], _ records: [Divergence]) -> UUID? { WorkDivergenceIndex(records).covering(pair)?.id }
        let superset = record(["a", "b", "c"])
        let exact = record(["a", "b"])
        let person = record(["a", "b", "d"], .person)
        let samePairPerson = record(["a", "b"], .person)
        XCTAssertEqual(covering(["a", "b"], [superset]), superset.id)
        XCTAssertEqual(covering(["a", "b"], [superset, exact]), exact.id)
        XCTAssertNil(covering(["a", "b"], [person]), "別的形狀不涵蓋 work 的一對")
        XCTAssertNil(covering(["a", "b"], [samePairPerson]), "同一個 id、別的形狀：不是已涵蓋（第 1／21 列）")
        XCTAssertNil(covering(["a", "b"], [samePairPerson, person]))
        XCTAssertEqual(covering(["a", "b"], [samePairPerson, superset]), superset.id, "id 被別種形狀占用，但更大的一組 work 記錄仍涵蓋這一對")
        XCTAssertNil(covering(["a", "b"], [record(["a", "c"])]))
        XCTAssertEqual(covering(["b", "a"], [exact]), exact.id, "這一對的順序不影響")
        // 多筆更大的一組：依 id 排序取第一筆，不隨載入順序變
        let other = record(["a", "b", "e"])
        let first = [superset, other].min { $0.id.uuidString < $1.id.uuidString }!
        XCTAssertEqual(covering(["a", "b"], [superset, other]), first.id)
        XCTAssertEqual(covering(["a", "b"], [other, superset]), first.id)
    }

    /// 索引隨寫隨加：同一趟稍後的一對要看得到前面寫的。
    func testIndexSeesRecordsAddedLater() {
        var index = WorkDivergenceIndex([])
        XCTAssertNil(index.covering(["a", "b"]))
        let d = Divergence(id: DeterministicUUID.forDivergence(candidateKeys: ["a", "b", "c"]), question: "q",
                           candidates: ["a", "b", "c"].map { DivergenceCandidate(key: $0, shape: .work) })
        index.add(d)
        XCTAssertEqual(index.covering(["a", "b"])?.id, d.id)
        XCTAssertEqual(index.covering(["b", "c"])?.id, d.id)
        XCTAssertNil(index.covering(["a", "z"]))
    }

    /// 同一個 id 已被別種形狀的歧異記錄占用（person 的 `{a, b}` 與 work 的 `{a, b}` 同 id）：這一對**不算已涵蓋**，記錄路徑拒絕覆寫——
    /// 報 `failed`、原因說出形狀，原記錄一個位元組都不動（#611 R1 verify 第 1／21 列）。
    func testAnIdOccupiedByAnotherShapeIsFailedNotCoveredAndNotOverwritten() throws {
        _ = try runImport()
        let article = try entry(zoteroKey: "KEYART01")
        try addItem(31, key: "KEYGRP01", title: "Group copy", doi: doi)
        _ = try runImport(at: 1_753_100_000)
        let group = try entry(zoteroKey: "KEYGRP01")
        let work = try onlyDivergence()
        // 把那筆 work 記錄換成同一個 id、別種形狀（person）的記錄；刪掉新建的那一筆，讓下一趟以同一個 citekey 重建
        let occupant = Divergence(id: work.id, question: "人的提問",
                                  candidates: [article.citekey, group.citekey].map { DivergenceCandidate(key: $0, shape: .person) })
        _ = try store.writeDivergence(occupant)
        let bytes = try Data(contentsOf: store.entityURL(id: work.id))
        try FileManager.default.removeItem(at: store.entityURL(id: group.id))

        let report = try runImport(at: 1_753_200_000)

        XCTAssertEqual(report.created, [group.citekey], "前提：同一個 citekey 重建")
        let row = try XCTUnwrap(report.doiNominations.first)
        XCTAssertEqual(report.doiNominations.count, 1)
        XCTAssertEqual(row.status, .failed, "別種形狀占用的 id 不是已涵蓋：\(row)")
        XCTAssertNil(row.divergenceID)
        XCTAssertTrue((row.error ?? "").contains("person") && (row.error ?? "").contains("work"), "原因要說出兩邊的形狀：\(row.error ?? "")")
        XCTAssertEqual(try Data(contentsOf: store.entityURL(id: work.id)), bytes, "原記錄不得被覆寫")
        XCTAssertEqual(try store.load().divergences.first?.shape, .person)
    }

    /// 記錄路徑自己的守衛（不只 nominate）：同一個 id、別種候選形狀的重錄被拒絕，原記錄不動——`record-divergence` 與 MCP 同走這一條。
    func testRecordDivergenceRefusesToOverwriteAnotherShapesRecordWithTheSameId() throws {
        try store.writeEntry(Entry(id: UUID(), citekey: "alpha2025", type: .periodicalArticle, title: "A"))
        try store.writeEntry(Entry(id: UUID(), citekey: "beta2025", type: .periodicalArticle, title: "B"))
        _ = try store.writePerson(Person(key: "alpha2025", names: PersonNames(authorized: ["Alpha"], variant: [])))
        _ = try store.writePerson(Person(key: "beta2025", names: PersonNames(authorized: ["Beta"], variant: [])))
        let person = try store.recordDivergence(question: "同一人嗎", candidates: [("alpha2025", .person), ("beta2025", .person)],
                                                judgement: nil, restsOn: [])
        let bytes = try Data(contentsOf: store.entityURL(id: person.id))

        XCTAssertThrowsError(try store.recordDivergence(question: "同一篇嗎", candidates: [("alpha2025", .work), ("beta2025", .work)],
                                                        judgement: nil, restsOn: [])) { error in
            guard case .divergenceIdHeldByOtherCandidates(_, _, _, let keysDiffer) = error as? StoreIOError else { return XCTFail("\(error)") }
            XCTAssertFalse(keysDiffer, "兩邊 key 相同、只有形狀不同")
        }
        XCTAssertEqual(try Data(contentsOf: store.entityURL(id: person.id)), bytes)
    }

    /// R2 verify 第 12／31／37 列：id 被占用的原因是**候選的 key 不同**（citekey 改名之後歧異記錄的候選被改寫、id 還是舊的）時，
    /// 訊息要點名現有那一筆的候選 key、說原因是 key 不同（先前一律說「形狀」，兩邊都是 work 時是假話），
    /// 而且出路指向 `dismiss-divergence`／`resolve-divergence`（先前叫人「看那個檔、修好、移走」——那是給被 quarantine 的記錄的；
    /// 而 `record-divergence` 本身撞同一個拒絕，指它手記是循環）。原記錄不得被覆寫。
    func testRefusalForRenamedCandidatesNamesTheKeysAndThePathOutNotTheShape() throws {
        for key in ["alpha2025", "alpha2025x", "beta2025"] {
            try store.writeEntry(Entry(id: UUID(), citekey: key, type: .periodicalArticle, title: key))
        }
        // rename 之後的形狀（`renameEntry` 就地改寫候選、不重算 id）：id 是 H({alpha2025, beta2025})，候選卻已被改寫成 {alpha2025x, beta2025}
        let id = DeterministicUUID.forDivergence(candidateKeys: ["alpha2025", "beta2025"])
        _ = try store.writeDivergence(Divergence(id: id, question: "已改名的一組",
                                                 candidates: [("alpha2025x", EntityKind.work), ("beta2025", .work)]
                                                    .map { DivergenceCandidate(key: $0.0, shape: $0.1) }))
        let bytes = try Data(contentsOf: store.entityURL(id: id))

        XCTAssertThrowsError(try store.recordDivergence(question: "又一次", candidates: [("alpha2025", .work), ("beta2025", .work)],
                                                        judgement: nil, restsOn: [])) { error in
            guard case let .divergenceIdHeldByOtherCandidates(gotID, existing, requested, keysDiffer) = error as? StoreIOError else {
                return XCTFail("\(error)")
            }
            XCTAssertEqual(gotID, id)
            XCTAssertTrue(keysDiffer, "key 不同、形狀相同")
            XCTAssertTrue(existing.contains("alpha2025x") && existing.contains("beta2025"), "現有那一筆的候選：\(existing)")
            XCTAssertTrue(requested.contains("「alpha2025」"), "這次要記的候選：\(requested)")
            let text = error.localizedDescription
            XCTAssertTrue(text.contains("key 不同") && !text.contains("只有形狀不同"), "原因是 key，不是形狀：\(text)")
            XCTAssertTrue(text.contains("akashic dismiss-divergence \(id.uuidString)") && text.contains("resolve-divergence"), "出路：\(text)")
            XCTAssertFalse(text.contains("akashic validate 會列出被 quarantine"), "那是給被 quarantine 的記錄的出路：\(text)")
        }
        XCTAssertEqual(try Data(contentsOf: store.entityURL(id: id)), bytes, "原記錄不得被覆寫")
    }

    /// R2 verify 第 36 列：匯入進行期間別的程序記下了這一對、而且帶著判斷。匯入不是要重錄它，是要確認它在：
    /// 記錄路徑拒絕「無判斷的重錄」（不得抹掉判斷）是對的，但那不是匯入的失敗——報 failed 會讓 CLI 以 1 結束、摘要叫人手記一筆已經存在的記錄。
    /// 這裡用建在判斷出現之前的 load 快照直接呼叫 `nominate`（`run` 沒有可注入的縫），磁碟上的記錄逐位元不動。
    func testAJudgedRecordWrittenDuringTheImportIsAlreadyRecordedNotFailed() throws {
        var a = Entry(id: UUID(), citekey: "alpha2025", type: .periodicalArticle, title: "A")
        a.doi = [try XCTUnwrap(DOI(doi))]
        var b = Entry(id: UUID(), citekey: "beta2025", type: .periodicalArticle, title: "B")
        b.doi = [try XCTUnwrap(DOI(doi))]
        try store.writeEntry(a); try store.writeEntry(b)
        let staleLoad = try store.load()   // 這一刻還沒有任何歧異記錄
        let digest = "sha256:" + String(repeating: "a1", count: 32)
        let written = try store.recordDivergence(question: "人寫的", candidates: [("alpha2025", .work), ("beta2025", .work)],
                                                 judgement: "同一篇", restsOn: [digest])
        let bytes = try Data(contentsOf: store.entityURL(id: written.id))

        let rows = DOITwinNomination.nominate(store: store, load: staleLoad,
                                              current: Dictionary(uniqueKeysWithValues: staleLoad.entries.map { ($0.id, $0) }),
                                              createdIDs: [b.id], legacyCopyCitekeys: [])

        XCTAssertEqual(rows.map(\.status), [.alreadyRecorded], "\(rows)")
        XCTAssertEqual(rows.first?.divergenceID, written.id)
        XCTAssertEqual(rows.first?.error, nil)
        XCTAssertTrue(DOITwinNomination.nominate(store: store, load: staleLoad, current: [:], createdIDs: [], legacyCopyCitekeys: []).isEmpty)
        XCTAssertEqual(try Data(contentsOf: store.entityURL(id: written.id)), bytes, "判斷不得被抹掉")
    }

    /// R2 verify 第 46 列：涵蓋判斷看**每一個**候選的形狀，不只第一個。第一個是 work、後面混著 person 的記錄，key 恰好相同時不算涵蓋 work 這一對。
    func testCoverageRequiresEveryCandidateToBeAWork() {
        // id 取這一對的決定性 id：`covering` 的「同一組」那一支就是從 id 找到它、再問 `covers`——id 隨機的話它根本不在那一支裡，測試量不到被改的謂詞
        let mixed = Divergence(id: DeterministicUUID.forDivergence(candidateKeys: ["alpha2025", "beta2025"]), question: "混合",
                               candidates: [DivergenceCandidate(key: "alpha2025", shape: .work), DivergenceCandidate(key: "beta2025", shape: .person)])
        let allWork = Divergence(id: UUID(), question: "全是 work",
                                 candidates: ["alpha2025", "beta2025", "gamma2025"].map { DivergenceCandidate(key: $0, shape: .work) })
        XCTAssertNil(WorkDivergenceIndex([mixed]).covering(["alpha2025", "beta2025"]))
        XCTAssertEqual(WorkDivergenceIndex([mixed, allWork]).covering(["alpha2025", "beta2025"])?.id, allWork.id, "更大的一組 work 記錄涵蓋這一對")
    }

    // MARK: - 這一趟寫入後留下 legacy 拷貝的 work（#705）不得被點名

    /// R2 verify 第 13／30 列：`ZoteroImporter.run` 把 `LegacyCopyLedger.collected` 交給 `nominate`，讓這一趟更新後留下 legacy 拷貝的 work 報成 `unlocatable`、
    /// 不被點名進歧異記錄（兩份並存，key 指不到唯一一筆）。這條接線在整合時掉過一次（bb574141），當時沒有任何測試變紅。
    /// 造法同 `ZoteroImportReportAfterWriteTests`：把文章搬回 legacy 佈局、讓 `entries/` 唯讀，pull 更新它之後 legacy 檔刪不掉；
    /// 再加一筆群組 library 的新條目共用它的 DOI。
    func testAWorkThatLeftALegacyCopyThisRunIsReportedUnlocatableNotNamed() throws {
        _ = try runImport()
        GitFixture.initRepo(store.root)
        let article = try entry(zoteroKey: "KEYART01")
        try FileManager.default.createDirectory(at: store.entriesDir, withIntermediateDirectories: true)
        let legacy = store.entriesDir.appendingPathComponent("\(article.citekey).yaml")
        try EntryYAML.encode(article).write(to: legacy, atomically: true, encoding: .utf8)
        try FileManager.default.removeItem(at: store.entityURL(id: article.id))
        GitFixture.commitAll(store.root)
        try fixture.db.execute("UPDATE items SET version = 9 WHERE itemID = 10")
        try addItem(31, key: "KEYGRP01", title: "Group copy", doi: doi)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: store.entriesDir.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: store.entriesDir.path) }
        let probe = store.entriesDir.appendingPathComponent("probe-\(UUID().uuidString)")
        if FileManager.default.createFile(atPath: probe.path, contents: Data()) {
            try? FileManager.default.removeItem(at: probe)
            throw XCTSkip("這個環境的權限擋不住刪檔（以 root 執行？），造不出「寫完之後刪 legacy 失敗」")
        }

        let report = try runImport(at: 1_753_100_000)

        XCTAssertEqual(report.writtenWithLegacyCopy.map(\.key), [article.citekey], "前提：這一趟留下了 legacy 拷貝：\(report)")
        let group = try entry(zoteroKey: "KEYGRP01")
        XCTAssertEqual(report.doiNominations.map { "\($0.created)↔\($0.other):\($0.status.rawValue)" },
                       ["\(group.citekey)↔\(article.citekey):unlocatable"], "留下拷貝的那一筆不點名：\(report.doiNominations)")
        XCTAssertEqual(try store.load().divergences, [], "沒有任何歧異記錄")
    }

    /// 寫入當下重新讀磁碟（#611 R1 verify 第 25／31 列）：呼叫端手上的 pool 只管「候選存在」；同一組候選的既有記錄若在 pool 建好之後
    /// 被別的程序補上了判斷，無判斷的重錄不得把它抹掉——即使呼叫端給的是建在判斷出現之前的 pool。
    func testRecordAgainstAPoolStillProtectsAJudgementWrittenAfterThePoolWasBuilt() throws {
        for key in ["alpha2025", "beta2025"] {
            try store.writeEntry(Entry(id: UUID(), citekey: key, type: .periodicalArticle, title: key))
        }
        let pool = DivergenceCandidatePool(try store.load())   // 這一刻還沒有任何歧異記錄
        // 「別的程序」在 pool 建好之後寫下一筆帶判斷的記錄
        let digest = "sha256:" + String(repeating: "a1", count: 32)
        _ = try store.recordDivergence(question: "人寫的", candidates: [("alpha2025", .work), ("beta2025", .work)],
                                       judgement: "同一篇", restsOn: [digest])
        let id = DeterministicUUID.forDivergence(candidateKeys: ["alpha2025", "beta2025"])
        let bytes = try Data(contentsOf: store.entityURL(id: id))

        XCTAssertThrowsError(try store.recordDivergence(question: "提名", candidates: [("alpha2025", .work), ("beta2025", .work)],
                                                        judgement: nil, restsOn: [], against: pool)) { error in
            XCTAssertTrue("\(error)".contains("已有判斷"), "\(error)")
        }
        XCTAssertEqual(try Data(contentsOf: store.entityURL(id: id)), bytes, "判斷不得被抹掉")
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

    // MARK: - 群組過大（#611 R1 verify 第 5／10／30／35 列）

    /// 門檻是 10 筆（最多 45 對）：live store 的 16 個共用組全部恰好 2 筆，離門檻很遠；這一支把值釘住，改門檻要改這裡並說明理由。
    func testThresholdIsTen() {
        XCTAssertEqual(DOINomination.maxGroupSize, threshold)
    }

    /// `count` 筆既有的 work 帶同一個 DOI（WoS 那一類，不經 Zotero）。
    private func writeWorks(_ count: Int, doi: String, prefix: String = "wos2025n") throws {
        for n in 1...count {
            var e = Entry(id: UUID(), citekey: "\(prefix)\(String(format: "%02d", n))", type: .periodicalArticle, title: "WoS \(n)")
            e.doi = [try XCTUnwrap(DOI(doi))]
            try store.writeEntry(e)
        }
    }

    /// 共用一個 DOI 的 work 超過門檻（這一趟新建的加上其餘的）：**一對都不記**，改報一列 `groupTooLarge`——一個 DOI 一列、
    /// 帶共用它的 work 數；匯入照建。一對一筆會寫 C(k,2) 筆記錄（DA 實測 k=80 → 3,160 筆、10 秒）。
    func testAGroupOverTheThresholdRecordsNoPairAndIsReportedOnce() throws {
        try writeWorks(threshold, doi: doi)   // 加上這一趟新建的 article ＝ 門檻 + 1

        let report = try runImport()

        let article = try entry(zoteroKey: "KEYART01")
        XCTAssertTrue(report.created.contains(article.citekey), "照建")
        XCTAssertEqual(try store.load().divergences, [], "一對都沒記")
        let row = try XCTUnwrap(report.doiNominations.first)
        XCTAssertEqual(report.doiNominations.count, 1, "一個 DOI 一列：\(report.doiNominations)")
        XCTAssertEqual(row.status, .groupTooLarge)
        XCTAssertEqual(row.groupSize, threshold + 1)
        XCTAssertEqual(row.dois, [doi])
        XCTAssertEqual(row.other, "", "群組過大的列沒有「另一筆」")
        XCTAssertEqual(row.created, article.citekey, "這一趟新建的 citekey 最小的一筆")
        XCTAssertNil(row.divergenceID)
        XCTAssertEqual(report.unrecordedDOINominations, [row], "沒記下來的列：重新匯入不會再提名")
    }

    /// 恰好在門檻上（這一趟新建的加上其餘的 ＝ 門檻）仍逐對提名：新建的一筆與其餘每一筆各一對。
    func testAGroupExactlyAtTheThresholdIsStillPairedOneByOne() throws {
        try writeWorks(threshold - 1, doi: doi)

        let report = try runImport()

        XCTAssertEqual(report.doiNominations.count, threshold - 1)
        XCTAssertEqual(Set(report.doiNominations.map(\.status)), [.recorded])
        XCTAssertEqual(try store.load().divergences.count, threshold - 1)
        XCTAssertEqual(report.unrecordedDOINominations, [])
    }

    /// 同一趟新建很多筆共用同一個 DOI：同樣是一列，`created` 是其中 citekey 最小的一筆。
    func testManyNewWorksSharingOneDOIAreOneGroupRow() throws {
        for n in 1...threshold + 1 {
            try addItem(100 + n, key: "KEYGRP\(String(format: "%02d", n))", title: "Copy \(n)", doi: doi)
        }

        let report = try runImport()

        XCTAssertEqual(try store.load().divergences, [])
        let row = try XCTUnwrap(report.doiNominations.first)
        XCTAssertEqual(report.doiNominations.count, 1)
        XCTAssertEqual(row.status, .groupTooLarge)
        XCTAssertEqual(row.groupSize, threshold + 2, "前 11 筆加上 seedStandard 那一篇")
        let citekeys = try store.load().entries.filter { $0.canonicalDOIs.map(\.normalized).contains(doi) }.map(\.citekey)
        XCTAssertEqual(row.created, citekeys.min())
    }

    /// 沒有這一趟新建的 work 的組不觸發：既有的過大群組不會在每次匯入時被重報。
    func testAnOversizedGroupWithoutANewWorkIsNotReported() throws {
        try writeWorks(threshold + 1, doi: "10.5555/big.1")   // 另一個 DOI、沒有新建的

        let report = try runImport()

        XCTAssertEqual(report.doiNominations, [])
    }

    /// 只報過大的那個 DOI：同一趟另一個 DOI 的一對照常記。
    func testOnlyTheOversizedDOIIsSkipped() throws {
        try writeWorks(threshold, doi: doi)
        let other = "10.7777/small.1"
        var small = Entry(id: UUID(), citekey: "small2025one", type: .periodicalArticle, title: "Small")
        small.doi = [try XCTUnwrap(DOI(other))]
        try store.writeEntry(small)
        try addItem(32, key: "KEYGRP02", title: "Small group copy", doi: other)

        let report = try runImport()

        XCTAssertEqual(Set(report.doiNominations.map(\.status)), [.groupTooLarge, .recorded])
        XCTAssertEqual(report.doiNominations.first { $0.status == .recorded }?.dois, [other])
        XCTAssertEqual(try store.load().divergences.count, 1)
    }

    /// 合成一個 50 筆共用同一個 DOI 的群組：**沒有記任何一對，也不把涵蓋判斷的成本乘上對數**（量測見 changelog）。
    func testAFiftyWorkGroupWritesNothingAndIsFast() throws {
        try writeWorks(50, doi: doi)
        let start = Date()
        let report = try runImport()
        XCTAssertLessThan(Date().timeIntervalSince(start), 30, "群組過大時不逐對處理")
        XCTAssertEqual(report.doiNominations.map(\.status), [.groupTooLarge])
        XCTAssertEqual(try store.load().divergences, [])
    }
}
