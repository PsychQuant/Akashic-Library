import Foundation
import XCTest
@testable import AkashicCore
@testable import AkashicStoreIO

/// #455：`writeEntry` 的非 I/O 前置條件抽成 `assertEntryWritable`，`writeEntry`／`writeEntryExclusive`
/// 與批次 create 的 preflight 走**同一個函式**（#463／#494 的 `assertPersonWritable` 同形）。
/// 抽出前 `writeEntryExclusive` 只驗 citekey＋encode——rename 與批次寫入都走它，format 閘整個缺席。
final class EntryWritableGateTests: XCTestCase {
    private var root: URL!
    private var store: LibraryStore!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("akashic-ewg-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("entities"), withIntermediateDirectories: true)
        try StoreVersion.write(root: root, format: StoreVersion.supported)
        store = LibraryStore(root: root)
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    func entryWithVenue(_ citekey: String) -> Entry {
        var e = Entry(id: UUID(), citekey: citekey, type: .periodicalArticle,
                      title: "T", authors: [.literal("A B")], date: "2020")
        e.venues = [.literal("Some Journal")]
        return e
    }

    /// exclusive 路徑必須與 `writeEntry` 同一組閘：format 10 的 store 不得寫進含 venues 的 entry。
    func testExclusiveWriteEnforcesTheSameFormatGatesAsWriteEntry() throws {
        try StoreVersion.write(root: root, format: 10)   // venues 需要 ≥ 11
        XCTAssertThrowsError(try store.writeEntry(entryWithVenue("a2020t")), "writeEntry 既有的閘")
        XCTAssertThrowsError(try store.writeEntryExclusive(entryWithVenue("b2020t")), "exclusive 路徑要有同一組閘")
        XCTAssertTrue(try store.load().entries.isEmpty, "兩條路都不得寫進任何檔")
    }
}

extension EntryWritableGateTests {
    /// provider 只在某個閘真的需要 format 時才讀、成功後只讀一次（含 venues 的 entry 會經過 venues 閘一次）。
    func testAssertEntryWritableReadsFormatLazilyAndOnce() throws {
        var calls = 0
        let plain = Entry(id: UUID(), citekey: "p2020t", type: .periodicalArticle, title: "T",
                          authors: [.literal("A B")], date: "2020")
        try LibraryStore.assertEntryWritable(plain, format: { calls += 1; return StoreVersion.supported })
        XCTAssertEqual(calls, 0, "沒有 gated feature：不讀 format")
        var gated = entryWithVenue("g2020t")
        gated.akashic.sources = ["sha256:" + String(repeating: "a", count: 64)]   // 第二個要 format 的閘
        try LibraryStore.assertEntryWritable(gated, format: { calls += 1; return StoreVersion.supported })
        XCTAssertEqual(calls, 1, "兩個閘共用一次讀取")
    }
}
