import XCTest
import Foundation
@testable import AkashicCore
@testable import AkashicStoreIO
@testable import AkashicIndex
@testable import AkashicQuery

/// venue 的 store 層：寫入 gate（format 11）、load、index 反向編年。
final class VenueStoreTests: XCTestCase {
    var root: URL!
    var store: LibraryStore!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("akashic-venue-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("entities"), withIntermediateDirectories: true)
        try StoreVersion.write(root: root, format: StoreVersion.supported)
        store = LibraryStore(root: root)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    private func sampleVenue() -> Venue {
        var v = Venue(key: "jcgs", type: .journal)
        v.names = Timeline([TemporalValue(value: "Journal of Computational and Graphical Statistics")])
        return v
    }

    // MARK: - format gate（task 2.2）

    func testVenueWriteRefusedOnFormat10() throws {
        try StoreVersion.write(root: root, format: 10)
        XCTAssertThrowsError(try store.writeVenue(sampleVenue())) { err in
            guard case StoreIOError.invalidInput(_, let why) = err else {
                return XCTFail("預期 invalidInput，實得 \(err)")
            }
            XCTAssertTrue(why.contains("11"), "訊息要指向 format 11：\(why)")
        }
        // 拒寫即零副作用：entities/ 只有 0 檔
        let files = try FileManager.default.contentsOfDirectory(
            atPath: root.appendingPathComponent("entities").path)
        XCTAssertTrue(files.isEmpty)
    }

    func testEntryVenuesRefusedOnFormat10() throws {
        try StoreVersion.write(root: root, format: 10)
        var e = Entry(id: UUID(), citekey: "x2025", type: "article", title: "T")
        e.venues = [.literal("Some Journal")]
        XCTAssertThrowsError(try store.writeEntry(e)) { err in
            guard case StoreIOError.invalidInput = err else {
                return XCTFail("預期 invalidInput，實得 \(err)")
            }
        }
        // 無 venues 的 entry 照常可寫（additive 契約）
        let plain = Entry(id: UUID(), citekey: "y2025", type: "article", title: "U")
        XCTAssertNoThrow(try store.writeEntry(plain))
    }

    // MARK: - 寫入與 load（task 2.2 / 形狀整合）

    func testVenueWriteAndLoadRoundTrip() throws {
        let v = sampleVenue()
        let url = try store.writeVenue(v)
        XCTAssertEqual(url.deletingPathExtension().lastPathComponent, v.id.uuidString,
                       "檔名即 id")
        let load = try store.load()
        XCTAssertEqual(load.venues.count, 1)
        XCTAssertEqual(load.venues.first, v)
        XCTAssertTrue(load.quarantined.isEmpty)
    }

    func testVenueBadKeyRefused() throws {
        XCTAssertThrowsError(try store.writeVenue(Venue(key: "Bad Key!", type: .journal)))
    }

    // MARK: - 反向編年（task 2.3）

    func testVenueChronologicalWorksFromIndex() throws {
        let v = sampleVenue()
        _ = try store.writeVenue(v)
        var e1 = Entry(id: UUID(), citekey: "b2020", type: "article", title: "後")
        e1.venues = [.key("jcgs")]; e1.date = "2020"
        var e2 = Entry(id: UUID(), citekey: "a2015", type: "article", title: "前")
        e2.venues = [.key("jcgs")]; e2.date = "2015"
        var e3 = Entry(id: UUID(), citekey: "c2018", type: "article", title: "他刊")
        e3.venues = [.literal("Other Journal")]; e3.date = "2018"
        for e in [e1, e2, e3] { _ = try store.writeEntry(e) }

        _ = try LibraryIndex(store: store).rebuild()
        let engine = try QueryEngine(indexPath: store.indexURL)
        let works = try engine.venueWorks(key: "jcgs")
        XCTAssertEqual(works.map(\.citekey), ["a2015", "b2020"], "依年升冪")
        // 零篇 ≠ 查無：空集合是合法答案
        let none = try engine.venueWorks(key: "empty-venue")
        XCTAssertEqual(none.count, 0)
    }
}
