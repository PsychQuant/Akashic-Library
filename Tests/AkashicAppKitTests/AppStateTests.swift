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
