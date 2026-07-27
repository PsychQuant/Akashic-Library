import XCTest
@testable import AkashicCore
@testable import AkashicStoreIO
@testable import AkashicAppKit

final class AppStateTests: XCTestCase {
    var root: URL!
    var state: AppState!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("akashic-app-\(UUID().uuidString)")
        let store = LibraryStore(root: root)
        try store.ensureLayout()
        var e1 = Entry(id: UUID(), citekey: "cheng2025identifiability", type: "article",
                       title: "Identifiability of polychoric models",
                       authors: [.key("cheng-che")], date: "2025")
        e1.fields["journaltitle"] = "Psychometrika"
        e1.akashic.tags = ["identifiability"]
        try store.writeEntry(e1)
        var e2 = Entry(id: UUID(), citekey: "olsson1979maximum", type: "article",
                       title: "Maximum likelihood estimation",
                       authors: [.literal("Ulf Olsson")], date: "1979")
        e2.provenance = Provenance(zoteroKey: "K", zoteroVersion: 1,
                                   orphanedAt: Date(timeIntervalSince1970: 1))
        try store.writeEntry(e2)
        try store.writePerson(Person(key: "cheng-che", names: ["Che Cheng"]))
        state = AppState(root: root)
        try state.load()
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    func testMutatePatchesFreshDiskStateNotStaleSnapshot() throws {
        // 模擬外部工具（CLI/MCP/Zotero pull）在 App 尚未 reload 時改了 biblatex face
        let store = LibraryStore(root: root)
        var external = try store.load().entries.first { $0.citekey == "cheng2025identifiability" }!
        external.title = "Updated externally"
        try store.writeEntry(external)
        // App 記憶體仍是舊 title；此時做一次衍生層編輯
        try state.addTag(citekey: "cheng2025identifiability", tag: "keeper")
        // 外部的 title 更新不得被舊快照蓋回去，衍生層編輯也要到位
        let after = try store.load().entries.first { $0.citekey == "cheng2025identifiability" }!
        XCTAssertEqual(after.title, "Updated externally",
                       "衍生層編輯不可用記憶體舊快照覆寫外部剛寫入的書目層")
        XCTAssertTrue(after.akashic.tags.contains("keeper"))
    }

    func testLoadBumpsReloadCount() throws {
        let before = state.reloadCount
        try state.load()
        XCTAssertEqual(state.reloadCount, before + 1,
                       "reloadCount 供 App 層 model 對外部變更重建之用")
    }

    func testLoadCountsMatchDoctorSemantics() {
        XCTAssertEqual(state.entries.count, 2)
        XCTAssertEqual(state.people.count, 1)
        XCTAssertEqual(state.unresolvedLiteralCount, 1)
        XCTAssertEqual(state.orphanedEntries.map(\.citekey), ["olsson1979maximum"])
        XCTAssertTrue(state.quarantined.isEmpty)
    }

    func testSearchAndTypeFilter() {
        state.searchText = "polychoric"
        XCTAssertEqual(state.filteredEntries.map(\.citekey), ["cheng2025identifiability"])
        state.searchText = ""
        state.filterTag = "identifiability"
        XCTAssertEqual(state.filteredEntries.count, 1)
    }

    func testDerivedLayerEditPersists() throws {
        try state.setStatus(citekey: "olsson1979maximum", status: "reading")
        try state.addTag(citekey: "olsson1979maximum", tag: "classic")
        let reloaded = try LibraryStore(root: root).load()
            .entries.first { $0.citekey == "olsson1979maximum" }!
        XCTAssertEqual(reloaded.akashic.status, "reading")
        XCTAssertEqual(reloaded.akashic.tags, ["classic"])
    }

    func testRenameThroughState() throws {
        try state.rename(from: "olsson1979maximum", to: "olsson1979bmaximum")
        XCTAssertNotNil(state.entries.first { $0.citekey == "olsson1979bmaximum" })
        XCTAssertNil(state.entries.first { $0.citekey == "olsson1979maximum" })
    }
}
