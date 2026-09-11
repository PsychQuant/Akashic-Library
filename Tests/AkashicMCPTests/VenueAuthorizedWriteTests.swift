import XCTest
@testable import AkashicCore
@testable import AkashicMCPKit
@testable import AkashicStoreIO

/// `authorized` 的寫入面（#554）——#471 修了 `variant` 那一半，這是另一半。
///
/// 在此之前 venue 的 `authorized` **沒有判定型寫入面**：唯一的寫入者是 `VenueBootstrap`
/// 的 `authorized: [c.names[0]]`（建檔時取第一個名字），實測 479/479 筆恰好是那個形狀。
/// #553 的攣生合併會把被併記錄的 authorized 降成倖存者的 variant，而**沒有面能改回來**
/// ——本面是那個降級的逆操作。
///
/// 形狀照 `VenueVariantWriteTests`——**但語意不是 append，這是端到端測出來的**：
/// `AuthorizedNames.validate` 對 authorized 有「每書寫系統至多一個」的內容約束，實測
/// 470 筆 venue 已有一個 latin authorized（bootstrap 的機械值），append 第二個必被擋。
/// 要換掉那個機械值需要**替換**：X 成為對外形、同書寫系統的舊指定 Y 降成 variant。
/// 所以參數叫 `authorize` 不叫 `add_authorized`——叫 add 會說謊。跨書寫系統仍是 append。
/// 「不重造互斥檢查」的立場不變。
final class VenueAuthorizedWriteTests: XCTestCase {
    private var root: URL!
    private var service: AkashicService!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("akashic-vaw-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("entities"), withIntermediateDirectories: true)
        try StoreVersion.write(root: root, format: StoreVersion.supported)
        service = AkashicService(root: root)
        // **`addVenue` 不寫 authorized**（實測：本測試第一版假設它照 `VenueBootstrap`
        // 的慣例寫 `[names[0]]`，紅在 `[]`）。兩個建檔面對 authorized 的處置不同：
        // bootstrap 機械取第一個名字、`addVenue` 留空（#227 的「建檔不機械偽造」語意）。
        // 所以 479/479 筆 `[names[0]]` 全來自 bootstrap——那正是 #554 的立案事實。
        // 這裡刻意給 WoS 全大寫形，讓「補正式對外形」是本測試的自然動作。
        _ = try service.addVenue(key: "some-journal", names: ["PSYCHOMETRIKA"],
                                 type: "periodical", note: nil, issn: nil)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    private func venue() throws -> Venue {
        try XCTUnwrap(LibraryStore(root: root).load().venues.first { $0.key == "some-journal" })
    }

    /// 不在 `names` 的一併 append 進 `names`——兩個分割都是對 names 的標記，標一個 names
    /// 沒有的字串會造出孤兒，而孤兒 authorized 自始是 error（寫不進去）。
    func testAddAuthorizedAlsoAppendsToNames() throws {
        _ = try service.updateVenue(key: "some-journal", addNames: nil, note: nil, type: nil,
                                    authorize: ["Psychometrika"])
        let v = try venue()
        XCTAssertEqual(v.names.entries.map(\.value), ["PSYCHOMETRIKA", "Psychometrika"])
        XCTAssertTrue(v.authorized.contains("Psychometrika"), "authorized 沒有加上：\(v.authorized)")
    }

    /// append 語意、冪等：同一個名字標兩次不會變成兩筆。
    func testAddAuthorizedIsIdempotent() throws {
        for _ in 0..<2 {
            _ = try service.updateVenue(key: "some-journal", addNames: nil, note: nil, type: nil,
                                        authorize: ["Psychometrika"])
        }
        let v = try venue()
        XCTAssertEqual(v.authorized.filter { $0 == "Psychometrika" }.count, 1)
        XCTAssertEqual(v.names.entries.count, 2, "names 也不得重複 append")
    }

    /// **分割互斥由 `Venue.validate()` 擋，寫入面不重造一份**（#471 的既有裁決，同
    /// `VenueVariantWriteTests.testMarkingAnAuthorizedNameAsVariantIsRefused`）——同一次
    /// 呼叫把同一個字串送進兩個分割要整個拒絕、零寫入。
    func testSameStringToBothPartitionsIsRefused() throws {
        XCTAssertThrowsError(try service.updateVenue(key: "some-journal", addNames: nil,
                                                     note: nil, type: nil,
                                                     addVariant: ["Psychometrika"],
                                                     authorize: ["Psychometrika"]))
        let v = try venue()
        XCTAssertFalse(v.variant.contains("Psychometrika"), "拒絕後 variant 不得有它：\(v.variant)")
        XCTAssertFalse(v.authorized.contains("Psychometrika"), "拒絕後 authorized 不得有它：\(v.authorized)")
        XCTAssertEqual(v.names.entries.count, 1, "拒絕後 names 也不得動")
    }

    /// **同書寫系統替換——本面存在的理由。** bootstrap 給的是 WoS 全大寫形，`--authorize`
    /// 正式刊名之後：正式刊名成為 authorized、全大寫形降成 variant，報告兩個都印。
    func testAuthorizeReplacesSameScriptAndDemotesTheOld() throws {
        var v = try venue()
        v.authorized = ["PSYCHOMETRIKA"]              // 模擬 bootstrap 的機械值
        try LibraryStore(root: root).writeVenue(v)

        let out = try service.updateVenue(key: "some-journal", addNames: nil, note: nil, type: nil,
                                          authorize: ["Psychometrika"])
        let after = try venue()
        XCTAssertEqual(after.authorized, ["Psychometrika"], "latin 只能有一個，且是新的那個")
        XCTAssertEqual(after.variant, ["PSYCHOMETRIKA"], "舊指定降成 variant，不刪")
        XCTAssertEqual(after.names.entries.map(\.value), ["PSYCHOMETRIKA", "Psychometrika"])
        XCTAssertTrue(out.contains("demotedToVariant") && out.contains("PSYCHOMETRIKA"),
                      "報告要說出誰被降級：\(out)")
    }

    /// **#553 降級的逆操作**：一個被合併降成 variant 的名字，`authorize` 它要從 variant
    /// 移出、進 authorized——一個名字不能同時在兩個分割。
    func testAuthorizeLiftsANameOutOfVariant() throws {
        var v = try venue()
        v.authorized = ["PSYCHOMETRIKA"]
        v.names = Timeline(v.names.entries + [TemporalValue(value: "Psychometrika")])
        v.variant = ["Psychometrika"]                  // 被 #553 降過去的
        try LibraryStore(root: root).writeVenue(v)

        _ = try service.updateVenue(key: "some-journal", addNames: nil, note: nil, type: nil,
                                    authorize: ["Psychometrika"])
        let after = try venue()
        XCTAssertEqual(after.authorized, ["Psychometrika"])
        XCTAssertEqual(after.variant, ["PSYCHOMETRIKA"], "兩者對調：新的升、舊的降")
    }

    /// **跨書寫系統是 append**：已有 latin authorized 時加一個中文刊名，兩個都在。
    func testAuthorizeAcrossScriptsAppends() throws {
        var v = try venue()
        v.authorized = ["PSYCHOMETRIKA"]
        try LibraryStore(root: root).writeVenue(v)

        _ = try service.updateVenue(key: "some-journal", addNames: nil, note: nil, type: nil,
                                    authorize: ["心理計量學"])
        let after = try venue()
        XCTAssertEqual(Set(after.authorized), ["PSYCHOMETRIKA", "心理計量學"])
        XCTAssertEqual(after.variant, [], "跨書寫系統沒有東西被降級")
    }

    /// 空白字串跳過（同 addNames／addVariant）。
    func testSkipsBlankStrings() throws {
        _ = try service.updateVenue(key: "some-journal", addNames: nil, note: nil, type: nil,
                                    authorize: ["  ", ""])
        let v = try venue()
        XCTAssertEqual(v.authorized, [], "addVenue 不寫 authorized，空白字串也不得寫")
        XCTAssertEqual(v.names.entries.count, 1)
    }
}
