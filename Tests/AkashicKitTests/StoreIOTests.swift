import XCTest
@testable import AkashicCore
@testable import AkashicStoreIO

final class StoreIOTests: XCTestCase {
    var root: URL!
    var store: LibraryStore!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("akashic-test-\(UUID().uuidString)")
        store = LibraryStore(root: root)
        try store.ensureLayout()
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func makeEntry(_ citekey: String = "cheng2025identifiability") -> Entry {
        Entry(id: UUID(), citekey: citekey, type: "article",
              title: "Identifiability of polychoric models",
              authors: [.literal("Che Cheng")], date: "2025")
    }

    func testEnsureLayoutCreatesDirectories() {
        for sub in ["entries", "people", "notes", ".akashic"] {
            var isDir: ObjCBool = false
            let exists = FileManager.default.fileExists(
                atPath: root.appendingPathComponent(sub).path, isDirectory: &isDir)
            XCTAssertTrue(exists && isDir.boolValue, "\(sub)/ 應存在")
        }
    }

    func testWriteAndLoadEntryRoundTrip() throws {
        let entry = makeEntry()
        let url = try store.writeEntry(entry)
        XCTAssertEqual(url.lastPathComponent, "cheng2025identifiability.yaml")
        let load = try store.load()
        XCTAssertEqual(load.entries, [entry])
        XCTAssertTrue(load.quarantined.isEmpty)
    }

    func testWriteEntryOverwritesAtomically() throws {
        var entry = makeEntry()
        _ = try store.writeEntry(entry)
        entry.title = "Updated title"
        _ = try store.writeEntry(entry)
        let load = try store.load()
        XCTAssertEqual(load.entries.first?.title, "Updated title")
        // atomic write 不留 temp 檔
        let files = try FileManager.default.contentsOfDirectory(
            at: root.appendingPathComponent("entries"), includingPropertiesForKeys: nil)
        XCTAssertEqual(files.map(\.lastPathComponent), ["cheng2025identifiability.yaml"])
    }

    func testLoadQuarantinesBadYAMLWithoutDroppingGood() throws {
        _ = try store.writeEntry(makeEntry())
        let bad = root.appendingPathComponent("entries/broken.yaml")
        try "title: no citekey here\n".write(to: bad, atomically: true, encoding: .utf8)
        let load = try store.load()
        XCTAssertEqual(load.entries.count, 1)
        XCTAssertEqual(load.quarantined.count, 1)
        XCTAssertEqual(load.quarantined.first?.file, "entries/broken.yaml")
    }

    func testWriteAndLoadPerson() throws {
        let person = Person(key: "chen-chun-houh", names: ["Chun-Houh Chen", "陳君厚"])
        let url = try store.writePerson(person)
        XCTAssertEqual(url.lastPathComponent, "chen-chun-houh.yaml")
        let load = try store.load()
        XCTAssertEqual(load.people, [person])
    }

    func testLoadEmptyLibraryIsEmpty() throws {
        let load = try store.load()
        XCTAssertTrue(load.entries.isEmpty)
        XCTAssertTrue(load.people.isEmpty)
        XCTAssertTrue(load.quarantined.isEmpty)
    }
}

extension StoreIOTests {
    // path traversal 防護：write-time 強制 key 格式（security lens HIGH）
    func testWriteEntryRejectsTraversalCitekey() {
        let entry = Entry(id: UUID(), citekey: "../../evil", type: "article", title: "T")
        XCTAssertThrowsError(try store.writeEntry(entry))
    }

    func testWritePersonRejectsBadKey() {
        XCTAssertThrowsError(try store.writePerson(Person(key: "Bad/Key", names: ["X"])))
    }
}

extension StoreIOTests {
    // R3：大小寫變體副檔名（.YAML）也要被枚舉——否則 case-insensitive FS 上
    // 它是寫入目的檔的別名，卻連 quarantine 名單都進不了
    func testUppercaseExtensionIsEnumeratedAndQuarantined() throws {
        let f = root.appendingPathComponent("entries/Broken.YAML")
        try "not: [valid\n".write(to: f, atomically: true, encoding: .utf8)
        let load = try store.load()
        XCTAssertEqual(load.quarantined.count, 1)
        XCTAssertTrue(load.quarantined.first?.file.hasSuffix("Broken.YAML") ?? false)
    }
}

final class LibraryLocatorTests: XCTestCase {
    var tmp: URL!

    override func setUpWithError() throws {
        tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("akashic-locator-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tmp)
    }

    func testExplicitPathWins() throws {
        let url = try LibraryLocator.resolve(explicit: "/some/lib",
                                             environment: ["AKASHIC_LIBRARY": "/env/lib"],
                                             configURL: tmp.appendingPathComponent("none.yaml"))
        XCTAssertEqual(url.path, "/some/lib")
    }

    func testEnvironmentFallback() throws {
        let url = try LibraryLocator.resolve(explicit: nil,
                                             environment: ["AKASHIC_LIBRARY": "/env/lib"],
                                             configURL: tmp.appendingPathComponent("none.yaml"))
        XCTAssertEqual(url.path, "/env/lib")
    }

    func testConfigFileFallback() throws {
        let config = tmp.appendingPathComponent("config.yaml")
        try "library: /cfg/lib\n".write(to: config, atomically: true, encoding: .utf8)
        let url = try LibraryLocator.resolve(explicit: nil, environment: [:], configURL: config)
        XCTAssertEqual(url.path, "/cfg/lib")
    }

    func testUnconfiguredThrows() {
        XCTAssertThrowsError(try LibraryLocator.resolve(
            explicit: nil, environment: [:],
            configURL: tmp.appendingPathComponent("none.yaml")))
    }
}

final class RenameTests: XCTestCase {
    var root: URL!
    var store: LibraryStore!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("akashic-rename-\(UUID().uuidString)")
        store = LibraryStore(root: root)
        try store.ensureLayout()
        var e1 = Entry(id: UUID(), citekey: "old2020key", type: "article", title: "T1",
                       authors: [.literal("A")], date: "2020")
        e1.akashic.relations.cites = ["other2019ref"]
        try store.writeEntry(e1)
        var e2 = Entry(id: UUID(), citekey: "citing2021paper", type: "article", title: "T2")
        e2.akashic.relations.cites = ["old2020key"]          // 引用即將被 rename 的 entry
        e2.akashic.relations.related = ["old2020key"]
        try store.writeEntry(e2)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    func testRenameMovesFileMigratesRelationsKeepsUUID() throws {
        let before = try store.load().entries.first { $0.citekey == "old2020key" }!
        let report = try store.renameEntry(from: "old2020key", to: "new2020key")
        XCTAssertEqual(report.relationsRewritten, ["citing2021paper"])

        let load = try store.load()
        XCTAssertNil(load.entries.first { $0.citekey == "old2020key" })
        let renamed = load.entries.first { $0.citekey == "new2020key" }!
        XCTAssertEqual(renamed.id, before.id)                                   // UUID 不變
        XCTAssertEqual(renamed.akashic.relations.cites, ["other2019ref"])       // 自身 relations 不動
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: store.entryURL(citekey: "old2020key").path))                // 舊檔已刪
        let citing = load.entries.first { $0.citekey == "citing2021paper" }!
        XCTAssertEqual(citing.akashic.relations.cites, ["new2020key"])          // 引用端跟改
        XCTAssertEqual(citing.akashic.relations.related, ["new2020key"])
    }

    func testRenameRejectsBadOrTakenTarget() throws {
        XCTAssertThrowsError(try store.renameEntry(from: "old2020key", to: "Bad/Key"))
        XCTAssertThrowsError(try store.renameEntry(from: "old2020key", to: "citing2021paper"))
        XCTAssertThrowsError(try store.renameEntry(from: "nope", to: "x2020y"))
    }

    func testRenameRejectsQuarantinedTarget() throws {
        try "broken: [yaml\n".write(to: store.entriesDir.appendingPathComponent("qtarget.yaml"),
                                    atomically: true, encoding: .utf8)
        XCTAssertThrowsError(try store.renameEntry(from: "old2020key", to: "qtarget"))
    }
}
