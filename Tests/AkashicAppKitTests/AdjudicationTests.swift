import XCTest
@testable import AkashicCore
@testable import AkashicStoreIO
@testable import AkashicAppKit

final class AdjudicationTests: XCTestCase {
    var root: URL!
    var state: AppState!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("akashic-adj-\(UUID().uuidString)")
        let store = LibraryStore(root: root)
        try store.ensureLayout()
        // fixture 手寫壞掉的原始檔進 entries/，需自己宣告 legacy 目錄（#101）
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("entries"), withIntermediateDirectories: true)
        try store.writeEntry(Entry(id: UUID(), citekey: "a2020paper", type: "article",
                                   title: "T", authors: [.literal("Che Cheng")]))
        var orphan = Entry(id: UUID(), citekey: "b2019gone", type: "article", title: "Gone")
        orphan.provenance = Provenance(zoteroKey: "K", zoteroVersion: 1,
                                       orphanedAt: Date(timeIntervalSince1970: 1))
        try store.writeEntry(orphan)
        try store.writePerson(Person(key: "cheng-che", names: ["Che Cheng"]))
        state = AppState(root: root)
        try state.load()
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    func testPeopleResolveAcceptAppliesSingleCandidate() throws {
        let model = PeopleResolveModel(state: state)
        XCTAssertEqual(model.candidates.count, 1)
        try model.accept(model.candidates[0])
        let entry = state.entries.first { $0.citekey == "a2020paper" }!
        XCTAssertEqual(entry.authors, [.key("cheng-che")])
        XCTAssertTrue(model.candidates.isEmpty)
    }

    func testPeopleResolveSkipIsSessionOnly() throws {
        let model = PeopleResolveModel(state: state)
        model.skip(model.candidates[0])
        XCTAssertTrue(model.candidates.isEmpty)
        let entry = state.entries.first { $0.citekey == "a2020paper" }!
        XCTAssertEqual(entry.authors, [.literal("Che Cheng")])   // 檔案未動
    }

    func testPeopleResolveSkipSurvivesModelRecreation() throws {
        // R2 抓到的回歸：view 以 .task(id: reloadCount) 重建 model，
        // skip 集合若存在 model 內，每次 accept 觸發 reload 後就歸零
        let model = PeopleResolveModel(state: state)
        model.skip(model.candidates[0])
        try state.load()                                   // 模擬 reload
        let recreated = PeopleResolveModel(state: state)   // 模擬 view 重建
        XCTAssertTrue(recreated.candidates.isEmpty,
                      "session 內 skip 過的候選在 model 重建後不得重新出現")
    }

    func testOrphanResolveRefusesNonOrphanAndMissing() throws {
        let model = OrphanModel(state: state)
        // a2020paper 不是 orphan——兩種動作都必須拒絕（確認對話框開啟期間
        // entry 可能已被 Zotero pull 恢復正常，動作當下要重新驗證）
        XCTAssertThrowsError(try model.resolve(citekey: "a2020paper", action: .detachFromZotero))
        XCTAssertThrowsError(try model.resolve(citekey: "a2020paper", action: .moveToTrash))
        // 找不到的 citekey 也要擲錯，不得靜默成功
        XCTAssertThrowsError(try model.resolve(citekey: "ghost2000x", action: .moveToTrash))
        // 檔案毫髮無傷。**用 load() 而非固定路徑判斷**——#35 之後檔案位置由 store
        // format 決定（`entities/<uuid>.yaml` vs `entries/<citekey>.yaml`），
        // 而這個測試要驗的是「記錄還在」，不是「記錄在哪個路徑」。
        let store = LibraryStore(root: root)
        XCTAssertNotNil(try store.load().entries.first { $0.citekey == "a2020paper" })
    }

    func testOrphanResolveRevalidatesFromDiskAtActionTime() throws {
        let model = OrphanModel(state: state)
        // 確認對話框開啟期間：外部把 b2019gone 恢復為正常（清掉 orphanedAt）
        let store = LibraryStore(root: root)
        var restored = try store.load().entries.first { $0.citekey == "b2019gone" }!
        restored.provenance?.orphanedAt = nil
        try store.writeEntry(restored)
        // App 記憶體仍認為它是 orphan；動作當下必須以磁碟真相拒絕
        XCTAssertThrowsError(try model.resolve(citekey: "b2019gone", action: .moveToTrash))
        // 同上：驗「記錄還在」而非「路徑是哪個」（#35 之後位置由 store format 決定）
        XCTAssertNotNil(try store.load().entries.first { $0.citekey == "b2019gone" })
    }

    func testOrphanDetachClearsProvenance() throws {
        let model = OrphanModel(state: state)
        XCTAssertEqual(model.orphans.map(\.citekey), ["b2019gone"])
        try model.resolve(citekey: "b2019gone", action: .detachFromZotero)
        let entry = try LibraryStore(root: root).load().entries.first { $0.citekey == "b2019gone" }!
        XCTAssertNil(entry.provenance)          // 轉純 Akashic entry
        XCTAssertTrue(model.orphans.isEmpty)
    }

    func testOrphanDeleteMovesToTrash() throws {
        let model = OrphanModel(state: state)
        try model.resolve(citekey: "b2019gone", action: .moveToTrash)
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: LibraryStore(root: root).entryURL(citekey: "b2019gone").path))
        XCTAssertNil(state.entries.first { $0.citekey == "b2019gone" })
    }

    func testQuarantineListAndRevalidate() throws {
        let bad = LibraryStore(root: root).entriesDir.appendingPathComponent("broken.yaml")
        try "not: [valid\n".write(to: bad, atomically: true, encoding: .utf8)
        let model = QuarantineModel(state: state)
        try model.refresh()
        XCTAssertEqual(model.items.count, 1)
        // 修好檔案 → revalidate 消失
        try FileManager.default.removeItem(at: bad)
        try model.refresh()
        XCTAssertTrue(model.items.isEmpty)
    }

    /// #236 R2：**裁決台是唯一還在靜默丟棄歧義的面**——而人就坐在這裡。
    ///
    /// CLI 與 MCP 都被接上了，唯獨這裡沒有：使用者看得到唯一命中，卻不知道系統
    /// 另外找到 N 個**它知道需要人判斷**的位置。這與 #231 要修的是同一件事，
    /// 只是發生在最不該發生的面。
    func testAdjudicationSurfacesAmbiguities() throws {
        let store = LibraryStore(root: root)
        try store.writePerson(Person(key: "amb-one", names: ["Ambi Guous"]))
        var two = Person(key: "amb-two", names: ["Ambi Guous"])
        two.orcid = "0000-0002-0000-0000"
        try store.writePerson(two)
        try store.writeEntry(Entry(id: UUID(), citekey: "amb2020x", type: "article",
                                   title: "X", authors: [.literal("Ambi Guous")]))
        try state.load()

        let model = PeopleResolveModel(state: state)
        XCTAssertEqual(model.ambiguities.count, 1,
                       "裁決台必須看得到歧義——它是唯一有人能解決它的地方")
        XCTAssertEqual(model.ambiguities.first?.personKeys, ["amb-one", "amb-two"])

        // 區辨欄位要拿得到，否則人也判不了
        let d = model.discriminators(for: "amb-two")
        XCTAssertEqual(d.orcid, "0000-0002-0000-0000")
        XCTAssertEqual(d.names, ["Ambi Guous"])

        // 歧義**不得**混進可 accept 的候選
        XCTAssertFalse(model.candidates.contains { $0.citekey == "amb2020x" },
                       "歧義套用不了——型別層就吃不進 apply")
    }

    /// #236 R4：**觀測點不是終止日期**。裁決台先前對三種時間狀態一律套 `（–X）`，
    /// 於是「2020 年被看到在這裡」被印成「2020 年結束」——那是捏造，而且捏造的正是
    /// 使用者要拿來判斷「這兩個同名的人是不是同一個」的那個欄位。
    ///
    /// CLI（`rangeLabel`）與 MCP（`formerAffiliationAttested`）都分得開，只有這一面沒有。
    func testAdjudicationDistinguishesThreePastTimeStates() throws {
        var seq = 0
        func aff(_ range: DateRange) throws -> String {
            seq += 1
            let key = "past-person-\(seq)"
            var p = Person(key: key, names: ["Past Person \(seq)"])
            p.profile.affiliations = TimelineOf([
                TemporalValue(value: OrgRef.literal("Some Lab"), range: range)
            ])
            try LibraryStore(root: root).writePerson(p)
            try state.load()
            return PeopleResolveModel(state: state).discriminators(for: key).affiliation ?? ""
        }

        let ended = try aff(DateRange(start: "2005", end: "2015"))
        XCTAssertTrue(ended.contains("–2015"), "確實結束 → 印終止日期：\(ended)")

        var unknown = DateRange(start: "2005")
        unknown.endedUnknown = true
        let u = try aff(unknown)
        XCTAssertTrue(u.contains("時點未知"), "#63 已結束但不知何時 → 明說未知：\(u)")
        XCTAssertFalse(u.contains("–2005"), "start 不是 end，不得印成終止：\(u)")

        let observed = try aff(DateRange(attested: ["2020"]))
        XCTAssertTrue(observed.contains("觀測"), "#70 只有觀測點 → 標成觀測：\(observed)")
        XCTAssertFalse(observed.contains("–2020"),
                       "**不得**印成終止——沒有任何資料主張他 2020 年離開：\(observed)")
    }

    /// #236 R4：**一篇文獻可以有多個歧義作者／多個候選作者**，所以 `entryID` 與
    /// `citekey` 單獨都不是唯一識別。
    ///
    /// 裁決台的 `ForEach(id:)` 先前分別綁 `\.entryID` 與 `\.citekey`——SwiftUI 對重複
    /// 識別的行為是掉列或錯配，而錯配的那半是**帶 Accept 按鈕的**：按鈕可能套用到
    /// 不是畫面上那一列的候選。
    func testRowIDsAreUniqueWhenOneEntryHasSeveralAmbiguousAuthors() throws {
        let store = LibraryStore(root: root)
        for k in ["dup-a1", "dup-a2"] { try store.writePerson(Person(key: k, names: ["Dup One"])) }
        for k in ["dup-b1", "dup-b2"] { try store.writePerson(Person(key: k, names: ["Dup Two"])) }
        try store.writePerson(Person(key: "solo-x", names: ["Solo X"]))
        try store.writePerson(Person(key: "solo-y", names: ["Solo Y"]))
        // 一筆 entry：兩個歧義作者 + 兩個唯一命中的候選作者
        try store.writeEntry(Entry(id: UUID(), citekey: "multi2020", type: "article", title: "T",
                                   authors: [.literal("Dup One"), .literal("Dup Two"),
                                             .literal("Solo X"), .literal("Solo Y")]))
        try state.load()
        let model = PeopleResolveModel(state: state)

        let ambIDs = model.ambiguities.map(\.rowID)
        XCTAssertEqual(ambIDs.count, 2, "前提：同一筆 entry 要有兩個歧義作者")
        XCTAssertEqual(Set(ambIDs).count, 2, "兩列同 ID → SwiftUI 掉列：\(ambIDs)")

        let candIDs = model.candidates.filter { $0.citekey == "multi2020" }.map(\.rowID)
        XCTAssertEqual(candIDs.count, 2, "前提：同一筆 entry 要有兩個候選作者")
        XCTAssertEqual(Set(candIDs).count, 2,
                       "候選那半更危險——錯配的列帶著 Accept 按鈕：\(candIDs)")
    }
}
