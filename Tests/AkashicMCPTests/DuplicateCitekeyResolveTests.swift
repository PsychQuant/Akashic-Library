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

    func testSplitDropUnsplitAttributeAreRefusedWholeBatch() throws {
        assertRefused { try self.service.splitAuthors(["c2020:0: =兩個人"]) }
        assertRefused { try self.service.dropAuthors(["c2020:Che Cheng=不是人"]) }
        assertRefused { try self.service.unsplitAuthors(["c2020:Che Cheng"]) }
        assertRefused { try self.service.attributeToOrganizations(["c2020:0:moe=團體作者"]) }
        try duplicatesUntouched()
    }
}
