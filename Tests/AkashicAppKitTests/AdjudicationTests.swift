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
}
