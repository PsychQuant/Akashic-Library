import XCTest
import Foundation
@testable import AkashicCore
@testable import AkashicStoreIO

/// #709 R2 verify（requirements 與 logic 兩席各自在真 binary 上重現）：`resolve-divergence --dry-run` 對一個實跑會拒絕的合併回報成功。
///
/// 成因：第二個 #709 commit 把「同 id 的 entities／legacy 一對」從 `assertNoCrossRecordErrors`（在 `validateResolvePreconditions`，
/// preview 與實跑共用）拿掉，改由 `candidateLegacyCopies` 只看**候選**自己；而「第三筆記錄引用候選、自己又有 leftover」那一格的拒絕
/// 住在 `commitResolution` 的 `entryWritePlan` 預檢——preview 不經過它。結果 dry-run 印出「參照將改寫」，拿掉 `--dry-run` 才被 #631 擋下。
/// 那個不變式是本檔的既有紀律（`validateResolvePreconditions` doc：dry-run 與實跑必須擲一樣的錯）；使用者 2026-10-01 的裁決只讓 store 不再整個
/// 停下，沒有豁免 dry-run 的誠實。
final class ResolveDivergencePreviewLegacyCopyTests: XCTestCase {
    private var root: URL!
    private var store: LibraryStore!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("akashic-709-preview-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root.appendingPathComponent("entities"), withIntermediateDirectories: true)
        try StoreVersion.write(root: root, format: StoreVersion.supported)
        GitFixture.initRepo(root)
        store = LibraryStore(root: root)
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    // MARK: - 夾具

    private func writeEntities(_ e: Entry) throws {
        try EntryYAML.encode(e).write(to: store.entityURL(id: e.id), atomically: true, encoding: .utf8)
    }

    private func writeEntities(_ p: Person) throws {
        try PersonYAML.encode(p).write(to: store.entityURL(id: p.id), atomically: true, encoding: .utf8)
    }

    private func writeEntities(_ v: Venue) throws {
        try VenueYAML.encode(v).write(to: store.entityURL(id: v.id), atomically: true, encoding: .utf8)
    }

    /// legacy 拷貝（`entries/<citekey>.yaml`）——同一個 id，內容與 entities 那份相同。
    private func writeLegacy(_ e: Entry) throws {
        try FileManager.default.createDirectory(at: store.entriesDir, withIntermediateDirectories: true)
        try EntryYAML.encode(e).write(to: store.entriesDir.appendingPathComponent("\(e.citekey).yaml"), atomically: true, encoding: .utf8)
    }

    private func work(_ citekey: String, cites: [String] = [], authors: [Author] = [], venues: [VenueRef] = []) -> Entry {
        var e = Entry(id: UUID(), citekey: citekey, type: .periodicalArticle, title: citekey, date: "2020")
        e.akashic.relations.cites = cites
        e.authors = authors
        e.venues = venues
        return e
    }

    /// 同一組輸入、同一個 store 狀態，preview 與實跑都要擲**同一個**錯，且實跑之後磁碟逐位元不變。
    private func assertPreviewAndApplyRefuseIdentically(_ d: Divergence, survivor: String, mentions needle: String,
                                                        file: StaticString = #filePath, line: UInt = #line) throws {
        GitFixture.commitAll(root, message: "seed")
        let before = try snapshotBytes()
        var previewError: Error?
        XCTAssertThrowsError(try store.previewResolveDivergence(id: d.id, survivor: survivor, overrideReason: nil),
                             "dry-run 必須擋下實跑會擋的合併", file: file, line: line) { previewError = $0 }
        var applyError: Error?
        XCTAssertThrowsError(try store.resolveDivergence(id: d.id, survivor: survivor), "前提：實跑確實拒絕", file: file, line: line) { applyError = $0 }
        XCTAssertEqual("\(String(describing: previewError))", "\(String(describing: applyError))", "兩邊擲一樣的錯", file: file, line: line)
        XCTAssertTrue("\(String(describing: applyError))".contains(needle), "訊息要指名是哪個檔：\(String(describing: applyError))", file: file, line: line)
        XCTAssertEqual(try snapshotBytes(), before, "拒絕發生在任何寫入之前", file: file, line: line)
    }

    private func snapshotBytes() throws -> [String: Data] {
        var out: [String: Data] = [:]
        for dir in ["entities", "entries", "people"] {
            let url = root.appendingPathComponent(dir)
            for name in (try? FileManager.default.contentsOfDirectory(atPath: url.path)) ?? [] {
                out["\(dir)/\(name)"] = try Data(contentsOf: url.appendingPathComponent(name))
            }
        }
        return out
    }

    // MARK: - work 合併：第三筆記錄引用被併者、自己有 leftover

    func testWorkMergePreviewRefusesWhenACitingRecordHasALeftoverCopy() throws {
        try writeEntities(work("t2024twin"))
        try writeEntities(work("t2024btwin"))
        let citing = work("a2020alpha", cites: ["t2024btwin"])
        try writeEntities(citing)
        try writeLegacy(citing)
        let d = try store.recordDivergence(question: "同一篇？", candidates: [("t2024twin", .work), ("t2024btwin", .work)],
                                           judgement: nil, restsOn: [])
        try assertPreviewAndApplyRefuseIdentically(d, survivor: "t2024twin", mentions: "entries/a2020alpha.yaml")
    }

    /// 改名留下的拷貝（legacy 的 citekey 是舊的、id 相同）也一樣——預檢走 id，不是 citekey。
    func testWorkMergePreviewRefusesWhenTheLeftoverIsFromARename() throws {
        try writeEntities(work("t2024twin"))
        try writeEntities(work("t2024btwin"))
        let citing = work("a2020alpha", cites: ["t2024btwin"])
        try writeEntities(citing)
        var oldName = citing
        oldName.citekey = "a2020oldname"
        try writeLegacy(oldName)
        let d = try store.recordDivergence(question: "同一篇？", candidates: [("t2024twin", .work), ("t2024btwin", .work)],
                                           judgement: nil, restsOn: [])
        try assertPreviewAndApplyRefuseIdentically(d, survivor: "t2024twin", mentions: "entries/a2020oldname.yaml")
    }

    // MARK: - person／venue 合併：被改指的 entry 有 leftover

    func testPersonMergePreviewRefusesWhenAnAuthoredWorkHasALeftoverCopy() throws {
        try writeEntities(Person(key: "fann-cathy-s-j", names: PersonNames(authorized: ["Fann, Cathy S-J"])))
        try writeEntities(Person(key: "fann-cathy-s-j-2", names: PersonNames(variant: ["Fann, Cathy S. J."])))
        let authored = work("shen2015model", authors: [.key("fann-cathy-s-j-2")])
        try writeEntities(authored)
        try writeLegacy(authored)
        let d = try store.recordDivergence(question: "同一人？", candidates: [("fann-cathy-s-j", .person), ("fann-cathy-s-j-2", .person)],
                                           judgement: nil, restsOn: [])
        try assertPreviewAndApplyRefuseIdentically(d, survivor: "fann-cathy-s-j", mentions: "entries/shen2015model.yaml")
    }

    func testVenueMergePreviewRefusesWhenAnEntryOnADoomedVenueHasALeftoverCopy() throws {
        try writeEntities(Venue(key: "psychometrika", type: .periodical,
                                 names: Timeline([TemporalValue(value: "Psychometrika")]), authorized: ["Psychometrika"]))
        try writeEntities(Venue(key: "psychometrika-2", type: .periodical,
                                 names: Timeline([TemporalValue(value: "PSYCHOMETRIKA")]), authorized: ["PSYCHOMETRIKA"]))
        let onVenue = work("liu2019paper", venues: [.key("psychometrika-2")])
        try writeEntities(onVenue)
        try writeLegacy(onVenue)
        let d = try store.recordDivergence(question: "同一本刊？", candidates: [("psychometrika", .venue), ("psychometrika-2", .venue)],
                                           judgement: nil, restsOn: [])
        try assertPreviewAndApplyRefuseIdentically(d, survivor: "psychometrika", mentions: "entries/liu2019paper.yaml")
    }

    // MARK: - 沒有 leftover 時 preview 與實跑一致（預檢不能變成多擋）

    /// 對照組：引用者沒有 leftover，preview 成功、實跑成功，且 `rewritten` 逐筆一致。
    func testWorkMergeWithoutALeftoverStillPreviewsAndRuns() throws {
        try writeEntities(work("t2024twin"))
        try writeEntities(work("t2024btwin"))
        try writeEntities(work("a2020alpha", cites: ["t2024btwin"]))
        let d = try store.recordDivergence(question: "同一篇？", candidates: [("t2024twin", .work), ("t2024btwin", .work)],
                                           judgement: nil, restsOn: [])
        GitFixture.commitAll(root, message: "seed")
        let preview = try store.previewResolveDivergence(id: d.id, survivor: "t2024twin", overrideReason: nil)
        XCTAssertEqual(preview.rewritten, ["a2020alpha"], "只列一次")
        let applied = try store.resolveDivergence(id: d.id, survivor: "t2024twin")
        XCTAssertEqual(applied.rewritten, preview.rewritten)
        XCTAssertEqual(applied.merged, preview.merged)
    }

    /// 引用者在 legacy 目錄裡**只有一份**（還沒搬進 entities/）：不是 leftover，預檢放行（#631 的搬移路徑），preview 與實跑一致。
    func testWorkMergeWithASoleLegacyCitingRecordStillPreviewsAndRuns() throws {
        try writeEntities(work("t2024twin"))
        try writeEntities(work("t2024btwin"))
        try writeLegacy(work("a2020alpha", cites: ["t2024btwin"]))
        let d = try store.recordDivergence(question: "同一篇？", candidates: [("t2024twin", .work), ("t2024btwin", .work)],
                                           judgement: nil, restsOn: [])
        GitFixture.commitAll(root, message: "seed")
        let preview = try store.previewResolveDivergence(id: d.id, survivor: "t2024twin", overrideReason: nil)
        XCTAssertEqual(preview.rewritten, ["a2020alpha"])
        let applied = try store.resolveDivergence(id: d.id, survivor: "t2024twin")
        XCTAssertEqual(applied.rewritten, preview.rewritten)
    }
}
