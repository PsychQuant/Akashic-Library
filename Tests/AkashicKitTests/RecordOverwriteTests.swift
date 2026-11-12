import Foundation
import XCTest
@testable import AkashicCore
@testable import AkashicStoreIO

/// #794：覆寫一筆既有記錄之後，記錄還在、內容是新的、沒有暫存檔殘留——兩個平台都跑。
///
/// `atomicWrite` 覆寫既有檔時走 `FileManager.replaceItemAt`。Swift 6.0.3 的 Linux corelibs 在這一步
/// 刪掉目的檔（試作量到 `dest=<missing>`），6.4.2 已修好；Linux 的工具鏈下限因此定在 6.4（`LibraryStore.swift`
/// 的 `#error`）。這支測試釘住 6.4.2 上的行為：toolchain 日後若變動而重新出現那個缺陷，它會紅。
final class RecordOverwriteTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("akashic-794-overwrite-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root.appendingPathComponent("entities"), withIntermediateDirectories: true)
        try StoreVersion.write(root: root, format: StoreVersion.supported)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    // spec-example: linux-platform-support / Record overwrite on Linux
    func testOverwritingAPersonRecordKeepsItWithTheNewContentAndNoTemporaryFile() throws {
        let store = LibraryStore(root: root)
        let original = Person(key: "doe-jane", names: ["Jane Doe"])
        let firstURL = try store.writePerson(original)
        XCTAssertEqual(try store.load().people.first { $0.key == "doe-jane" }?.names.all, ["Jane Doe"], "前提：第一次寫入")

        var rewritten = original
        rewritten.names = ["Doe, Jane"]
        let secondURL = try store.writePerson(rewritten)
        XCTAssertEqual(secondURL, firstURL, "覆寫要落在同一個檔，不是另建一筆")

        XCTAssertTrue(FileManager.default.fileExists(atPath: secondURL.path), "覆寫之後記錄檔不見了")
        let people = try store.load().people.filter { $0.key == "doe-jane" }
        XCTAssertEqual(people.count, 1)
        XCTAssertEqual(people.first?.names.all, ["Doe, Jane"])

        let entities = try FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent("entities").path)
        XCTAssertEqual(entities.filter { $0.contains(".tmp-") }, [], "暫存檔殘留：\(entities)")
    }
}
