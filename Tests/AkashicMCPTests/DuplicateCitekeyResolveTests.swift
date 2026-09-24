import XCTest
@testable import AkashicCore
@testable import AkashicEntity
@testable import AkashicStoreIO
@testable import AkashicMCPKit

/// #627：citekey 重複（被支援的損壞態）時，resolve-people 一族不猜是哪一筆 entry。
///
/// 每一條腿沿用自己既有的失敗語意：顯式 id 的 apply／reject 與 split／un-split／drop／
/// attribute-org 整批拒絕、零寫入；judge／refute 是 store 狀態不符，該筆略過並具名。
/// fixture 的否決直接寫進記錄——用 `--refute` 在重複 citekey 上定位會取決於排序（#624 R2）。
final class DuplicateCitekeyResolveTests: XCTestCase {
    var root: URL!
    var store: LibraryStore!
    var service: AkashicService!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("akashic-dupck-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("entities"), withIntermediateDirectories: true)
        try StoreVersion.write(root: root, format: StoreVersion.supported)
        store = LibraryStore(root: root)
        service = AkashicService(root: root, key: nil, environment: [:])
        try store.writePerson(Person(key: "cheng-che", names: ["Che Cheng"]))
        try store.writePerson(Person(key: "olsson-ulf", names: ["Ulf Olsson"]))
        try store.writeOrganization(Organization(key: "moe"))
        // c2020 重複：A[0]＝「Che Cheng」、B[0]＝「Ulf Olsson」。d2021 是正常的一筆。
        for (title, literal) in [("A", "Che Cheng"), ("B", "Ulf Olsson")] {
            try store.writeEntry(Entry(id: UUID(), citekey: "c2020", type: .periodicalArticle,
                                       title: title, authors: [.literal(literal)], date: "2020"))
        }
        try store.writeEntry(Entry(id: UUID(), citekey: "d2021", type: .periodicalArticle,
                                   title: "D", authors: [.literal("Che Cheng")], date: "2021"))
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    private func json(_ s: String) throws -> [String: Any] {
        try JSONSerialization.jsonObject(with: Data(s.utf8)) as! [String: Any]
    }

    private func duplicatesUntouched(file: StaticString = #filePath, line: UInt = #line) throws {
        let load = try store.load()
        let dups = load.entries.filter { $0.citekey == "c2020" }.sorted { $0.title < $1.title }
        XCTAssertEqual(dups.map(\.authors), [[.literal("Che Cheng")], [.literal("Ulf Olsson")]],
                       "兩筆重複 citekey 的 entry 都不得被改寫", file: file, line: line)
        for p in load.people {
            XCTAssertFalse(p.references.contains { ($0.value ?? "").contains("work:c2020") },
                           "不得替重複 citekey 寫 verdict：\(p.key) \(p.references)", file: file, line: line)
        }
    }

    /// `skipped` 是 [{id, reason|why}]——用 JSON 重新序列化成 UTF-8 字串再比對（NSArray 的
    /// description 會把中文轉成 \u 跳脫，直接 contains 永遠找不到）
    private func skippedText(_ out: [String: Any]) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: out["skipped"] ?? [])
        return String(decoding: data, as: UTF8.self)
    }

    private func assertRefused(_ body: () throws -> String,
                               file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertThrowsError(try body(), file: file, line: line) { err in
            XCTAssertTrue("\(err)".contains("citekey 重複"), "\(err)", file: file, line: line)
        }
    }

    func testApplyWithPinnedOrLegacyIDIsRefused() throws {
        assertRefused { try self.service.resolvePeople(apply: ["c2020:0:cheng-che"]) }
        assertRefused { try self.service.resolvePeople(apply: ["c2020:0"]) }
        try duplicatesUntouched()
    }

    func testRejectWithPinnedOrLegacyIDIsRefused() throws {
        assertRefused { try self.service.resolvePeople(apply: nil, reject: ["c2020:0:cheng-che"]) }
        assertRefused { try self.service.resolvePeople(apply: nil, reject: ["c2020:0"]) }
        try duplicatesUntouched()
    }

    func testJudgeSkipsDuplicateByNameAndStillWritesTheRest() throws {
        let out = try json(try service.resolvePeople(apply: nil, judge: [
            "c2020:0:cheng-che=查證：論文機構相符",
            "d2021:0:cheng-che=查證：論文機構相符"]))
        let text = try skippedText(out)
        XCTAssertTrue(text.contains("citekey 重複") && text.contains("c2020"), "要具名略過：\(text)")
        try duplicatesUntouched()
        let d = try XCTUnwrap(try store.load().entries.first { $0.citekey == "d2021" })
        XCTAssertEqual(d.authors, [.key("cheng-che")], "同一批裡正常的那筆照寫")
    }

    func testRefuteSkipsDuplicateByName() throws {
        let out = try json(try service.resolvePeople(apply: nil, refute: ["c2020:0:cheng-che=機構不符"]))
        let text = try skippedText(out)
        XCTAssertTrue(text.contains("citekey 重複") && text.contains("c2020"), "\(text)")
        try duplicatesUntouched()
    }

    /// 列表先標出重複 citekey 的候選——呼叫端不必送出 apply 才知道會被拒。
    func testCandidateListMarksDuplicatedCitekeyRows() throws {
        let out = try json(try service.resolvePeople(apply: nil))
        let rows = try XCTUnwrap(out["candidates"] as? [[String: Any]])
        let marked = Dictionary(grouping: rows, by: { $0["citekey"] as? String ?? "" })
            .mapValues { $0.map { $0["duplicatedCitekey"] as? Bool ?? false } }
        XCTAssertEqual(marked["c2020"]?.allSatisfy { $0 }, true, "\(rows)")
        XCTAssertEqual(marked["d2021"], [false], "正常的那筆不帶標記")
    }

    /// 一批裡混著一筆重複 citekey 的 id 與一筆正常的：整批拒絕，正常那筆也不寫。
    func testMixedApplyBatchIsRefusedWholeAndWritesNothing() throws {
        assertRefused { try self.service.resolvePeople(apply: ["d2021:0:cheng-che", "c2020:0:cheng-che"]) }
        try duplicatesUntouched()
        let d = try XCTUnwrap(try store.load().entries.first { $0.citekey == "d2021" })
        XCTAssertEqual(d.authors, [.literal("Che Cheng")], "整批拒絕——正常那筆也不寫")
        XCTAssertFalse(try store.load().people.contains { p in
            p.references.contains { ($0.value ?? "").contains("work:d2021") } })
    }

    func testSplitDropUnsplitAttributeAreRefusedWholeBatch() throws {
        assertRefused { try self.service.splitAuthors(["c2020:0: =兩個人"]) }
        assertRefused { try self.service.dropAuthors(["c2020:Che Cheng=不是人"]) }
        assertRefused { try self.service.unsplitAuthors(["c2020:Che Cheng"]) }
        assertRefused { try self.service.attributeToOrganizations(["c2020:0:moe=團體作者"]) }
        try duplicatesUntouched()
    }
}

/// #627 R1：同一個 UUID 被兩個檔持有——重複 citekey 最常見的來源（半遷移：entities/ 與 legacy
/// entries/ 各一份），以及兩個 citekey 共用 UUID。寫入以 UUID 定檔，所以任何「對應回輸出」的
/// 字典都會把其中一份的內容寫到另一份的檔上。
final class SharedUUIDResolveTests: XCTestCase {
    var root: URL!
    var store: LibraryStore!
    var service: AkashicService!
    let sharedID = UUID()

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("akashic-shareduuid-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("entities"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("entries"), withIntermediateDirectories: true)
        try StoreVersion.write(root: root, format: StoreVersion.supported)
        store = LibraryStore(root: root)
        service = AkashicService(root: root, key: nil, environment: [:])
        try store.writePerson(Person(key: "cheng-che", names: ["Che Cheng"]))
        try store.writeEntry(Entry(id: UUID(), citekey: "d2021", type: .periodicalArticle,
                                   title: "D", authors: [.literal("Che Cheng")], date: "2021"))
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    private var entitiesFile: URL { root.appendingPathComponent("entities/\(sharedID.uuidString).yaml") }

    /// entities/ 寫編輯過的版本；legacy entries/<legacyCitekey>.yaml 寫同 UUID 的另一份
    private func seed(legacyCitekey: String, legacyTitle: String, legacyLiteral: String) throws {
        try store.writeEntry(Entry(id: sharedID, citekey: "c2020", type: .periodicalArticle,
                                   title: "Edited", authors: [.literal("Che Cheng")], date: "2020"))
        let legacy = Entry(id: sharedID, citekey: legacyCitekey, type: .periodicalArticle,
                           title: legacyTitle, authors: [.literal(legacyLiteral)], date: "2020")
        try EntryYAML.encode(legacy).write(
            to: root.appendingPathComponent("entries/\(legacyCitekey).yaml"),
            atomically: true, encoding: .utf8)
        XCTAssertEqual(try store.load().entries.filter { $0.id == sharedID }.count, 2,
                       "前提：load 同時讀到兩份")
    }

    private func noVerdict(on citekey: String, file: StaticString = #filePath, line: UInt = #line) throws {
        XCTAssertFalse(try store.load().people.contains { p in
            p.references.contains { ($0.value ?? "").contains("work:\(citekey) ") } },
            "不得替沒有歸戶的 \(citekey) 寫 verdict", file: file, line: line)
    }

    /// 半遷移：無關的 apply（d2021）不得把 entities 那份回退成 legacy 內容。
    /// index 會因 citekey UNIQUE 重建失敗——那是既有行為，這裡只管位元組。
    func testHalfMigratedCopyIsNotRevertedByAnUnrelatedApply() throws {
        try seed(legacyCitekey: "c2020", legacyTitle: "Stale", legacyLiteral: "Che Cheng")
        let before = try Data(contentsOf: entitiesFile)
        _ = try? service.resolvePeople(apply: ["d2021:0:cheng-che"])
        XCTAssertEqual(try Data(contentsOf: entitiesFile), before, "entities 那份一個位元都不動")
        try noVerdict(on: "c2020")
    }

    /// 兩個 citekey 共用 UUID，候選正好在其中一筆：不套用、不寫 verdict、具名回報 notApplied。
    func testCandidateOnSharedUUIDIsReportedNotAppliedWithoutVerdict() throws {
        try seed(legacyCitekey: "y2019", legacyTitle: "Other", legacyLiteral: "Ulf Olsson")
        let before = try Data(contentsOf: entitiesFile)
        do {
            let out = try service.resolvePeople(apply: ["c2020:0:cheng-che"])
            let json = try JSONSerialization.jsonObject(with: Data(out.utf8)) as! [String: Any]
            XCTAssertEqual(json["notApplied"] as? [String], ["c2020:0:cheng-che"])
            XCTAssertEqual(json["applied"] as? [String], [])
        } catch {
            // index rebuild 會因 UUID 主鍵重複而失敗——錯誤訊息裡的已改寫數必須是 0
            XCTAssertTrue("\(error)".contains("本批已改寫 0 檔"), "\(error)")
        }
        XCTAssertEqual(try Data(contentsOf: entitiesFile), before)
        try noVerdict(on: "c2020")
    }
}
