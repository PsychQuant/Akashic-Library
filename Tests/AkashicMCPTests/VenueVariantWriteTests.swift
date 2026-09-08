import XCTest
@testable import AkashicCore
@testable import AkashicMCPKit
@testable import AkashicStoreIO

/// `variant` 的寫入面（#471）。
///
/// 在此之前 variant **兩面都沒有寫入面**，唯一的寫入者是 `migrate-venue-variants`——而它
/// 用的是「`authorized` 的補集」。**一個不做判定的操作成了唯一的判定寫入者**，正面撞上
/// `identity-is-judged-not-matched`：「這個名字是那個名字的異寫」是判定，不是「不在對外
/// 清單裡」的推論。
final class VenueVariantWriteTests: XCTestCase {
    private var root: URL!
    private var service: AkashicService!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("akashic-vvw-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("entities"), withIntermediateDirectories: true)
        try StoreVersion.write(root: root, format: StoreVersion.supported)
        service = AkashicService(root: root)
        _ = try service.addVenue(key: "some-journal", names: ["PLOS ONE"],
                                 type: "periodical", note: nil, issn: nil)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    private func venue() throws -> Venue {
        try XCTUnwrap(LibraryStore(root: root).load().venues.first { $0.key == "some-journal" })
    }

    /// 不在 `names` 的一併 append 進 `names`——兩個分割都是對 names 的標記，標一個 names
    /// 沒有的字串會造出孤兒，而孤兒 variant 自 #473 起是 error（寫不進去）。
    func testAddVariantAlsoAppendsToNames() throws {
        _ = try service.updateVenue(key: "some-journal", addNames: nil, note: nil, type: nil,
                                    addVariant: ["PLoS One"])
        let v = try venue()
        XCTAssertEqual(v.names.entries.map(\.value), ["PLOS ONE", "PLoS One"])
        XCTAssertEqual(v.variant, ["PLoS One"])
    }

    /// append 語意、冪等：同一個名字標兩次不會變成兩筆。
    func testAddVariantIsIdempotent() throws {
        for _ in 0..<2 {
            _ = try service.updateVenue(key: "some-journal", addNames: nil, note: nil, type: nil,
                                        addVariant: ["PLoS One"])
        }
        let v = try venue()
        XCTAssertEqual(v.variant, ["PLoS One"])
        XCTAssertEqual(v.names.entries.count, 2, "names 也不得重複 append")
    }

    /// **分割互斥由 `Venue.validate()` 擋，寫入面不重造一份**——標一個已在 `authorized`
    /// 的名字要整個拒絕、零寫入。
    func testMarkingAnAuthorizedNameAsVariantIsRefused() throws {
        var v = try venue()
        v.authorized = ["PLOS ONE"]
        try LibraryStore(root: root).writeVenue(v)
        XCTAssertThrowsError(try service.updateVenue(key: "some-journal", addNames: nil,
                                                     note: nil, type: nil,
                                                     addVariant: ["PLOS ONE"]))
        XCTAssertEqual(try venue().variant, [], "拒絕必須是零寫入")
    }

    /// 空字串與空白被略過——不得把一個空名字寫進 names。
    func testBlankVariantsAreIgnored() throws {
        _ = try service.updateVenue(key: "some-journal", addNames: nil, note: nil, type: nil,
                                    addVariant: ["", "   "])
        let v = try venue()
        XCTAssertEqual(v.variant, [])
        XCTAssertEqual(v.names.entries.count, 1)
    }
}
