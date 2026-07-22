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
