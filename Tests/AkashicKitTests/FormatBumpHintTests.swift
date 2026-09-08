import XCTest
@testable import AkashicCore
@testable import AkashicStoreIO

/// 遷移的「下一步」不得印降級指示（#472）。
///
/// 三支遷移各自寫死自己那一代的目標（10／11／14）而**從不讀 marker**。store 今天是 16，
/// 所以無條件印「手動把 format 改成 14」是一道降級指示：format-14 binary 讀到帶
/// `field: paginated` 的 venue 會**整檔 quarantine**（#422 verify DA 6 實測 406 → 373、
/// rc=0）——照做等於手動重新開啟 format 15 存在的理由所要防的那個安靜失敗。
final class FormatBumpHintTests: XCTestCase {

    func testTellsYouToBumpOnlyWhenTheStoreIsBehind() {
        let s = StoreVersion.bumpHint(target: 14, current: 13)
        XCTAssertTrue(s.contains("改成 14"), s)
    }

    /// **核心**：現況已達或超過時，不得出現任何「改成 <目標>」的字樣。
    func testNeverTellsYouToDowngrade() {
        for current in [14, 15, 16, 99] {
            let s = StoreVersion.bumpHint(target: 14, current: current)
            XCTAssertFalse(s.contains("改成 14"),
                           "current=\(current) 時不得出現降級指示：\(s)")
            XCTAssertTrue(s.contains("不要"), s)
        }
    }

    /// marker 讀不到時**不猜**——把決定交回人，而不是預設「該升」或「不必升」。
    func testUnknownMarkerRefusesToDecide() {
        let s = StoreVersion.bumpHint(target: 14, current: nil)
        XCTAssertFalse(s.contains("改成 14"), s)
        XCTAssertTrue(s.contains("讀不到"), s)
    }

    /// 三支遷移的目標各自是常數，且**都低於現行 supported**——這正是缺陷的前提，
    /// 釘住它讓「哪天某支的目標追上 supported」時有人看到（那時本族的提示會自然變成
    /// 「要升」，而不是靜默地繼續正確）。
    func testEveryMigrationTargetIsBehindSupportedToday() {
        for (name, t) in [("person-identity", PersonIdentityMigration.targetFormat),
                          ("venues", VenueMigration.targetFormat),
                          ("venue-variants", VenueVariantMigration.targetFormat)] {
            XCTAssertLessThan(t, StoreVersion.supported,
                              "\(name) 的目標 \(t) 已追上 supported \(StoreVersion.supported)"
                              + "——本族的前提變了，回來重讀 #472")
            XCTAssertFalse(StoreVersion.bumpHint(target: t, current: StoreVersion.supported)
                            .contains("改成 \(t)"),
                           "\(name)：在今天的 store 上不得印降級指示")
        }
    }
}

/// 孤兒 `variant` 是 error，不是 warning（#473）。
///
/// 先前是 warning 而註解宣稱「同 `authorized` 的既有立場」——`authorized` 那邊是
/// `.error`。第二個理由更硬：`VenueResolver.resolve` 的提名**只從 `names.entries` 建
/// aliasMap**，所以提名正確性依賴 `variant ⊆ names`；而 `writeVenue` 只擋 error，
/// warning 級的話孤兒 variant 寫得進去、提名靜默少一個候選。
final class OrphanVariantSeverityTests: XCTestCase {

    // `variant` 不在 init 的參數列（它是 var，遷移與寫入面各自設）——所以先建再設。
    private func venue(names: [String], variant: [String]) -> Venue {
        var v = Venue(key: "some-journal", type: .periodical,
                      names: TimelineOf(names.map { TemporalValue(value: $0) }))
        v.variant = variant
        return v
    }

    func testOrphanVariantIsAnError() {
        let issues = venue(names: ["Journal A"], variant: ["Journal  A"]).validate()
        let orphan = issues.filter { $0.message.contains("不在 names 裡") }
        XCTAssertEqual(orphan.count, 1, "\(issues.map(\.message))")
        XCTAssertEqual(orphan[0].severity, .error,
                       "提名正確性依賴 variant ⊆ names，而 writeVenue 只擋 error")
    }

    /// **寫入面真的擋得住**——只驗 severity 不夠，錯的是「寫得進去」。
    func testWriteVenueRefusesAnOrphanVariant() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("akashic-ov-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("entities"), withIntermediateDirectories: true)
        try StoreVersion.write(root: root, format: StoreVersion.supported)
        let store = LibraryStore(root: root)
        defer { try? FileManager.default.removeItem(at: root) }
        XCTAssertThrowsError(try store.writeVenue(venue(names: ["Journal A"], variant: ["Journal  A"])))
        XCTAssertNoThrow(try store.writeVenue(venue(names: ["Journal A", "Journal  A"],
                                                   variant: ["Journal  A"])),
                         "名字在 names 裡就照常寫得進去——提級不得誤傷合法記錄")
    }
}

/// `authorized` 為空時的顯示名回退順序（#475）。
///
/// `TimelineOf.current` 在全段無 `start` 時取的是**序列化最後一筆**——那是實作細節，
/// 沒有人裁決過它該當顯示名。實測三筆 unclassified venue 因此顯示成「維基百科」
/// 「SEP」「…Academia Sinica NEW SERIES」。
final class VenueDisplayNameFallbackTests: XCTestCase {

    private func venue(_ names: [TemporalValue<String>], authorized: [String] = []) -> Venue {
        Venue(key: "some-journal", type: .periodical,
              names: TimelineOf(names), authorized: authorized)
    }

    /// authorized 在就用它——第一階不變。
    func testAuthorizedStillWins() {
        let v = venue([TemporalValue(value: "A"), TemporalValue(value: "B")], authorized: ["B"])
        XCTAssertEqual(v.displayName, "B")
    }

    /// **不帶時間宣稱時取序列化第一筆**，不是最後一筆。
    func testUndatedTimelineTakesTheFirstName() {
        let v = venue([TemporalValue(value: "The Stanford Encyclopedia of Philosophy"),
                       TemporalValue(value: "SEP")])
        XCTAssertEqual(v.displayName, "The Stanford Encyclopedia of Philosophy",
                       "序列化最後一筆是實作細節，第一筆是使用者先寫的那個")
    }

    /// **時間軸真的帶沿革時仍走 `current`**——那時「當前有效名稱」是關於世界的事實。
    func testDatedTimelineStillUsesCurrent() {
        let v = venue([TemporalValue(value: "舊刊名", range: DateRange(start: "1950", end: "1990")),
                       TemporalValue(value: "新刊名", range: DateRange(start: "1991"))])
        XCTAssertEqual(v.displayName, "新刊名", "有沿革時要用當前有效的那個")
    }

    /// 全空退到 key——最後一階不變。
    func testEmptyNamesFallsBackToKey() {
        XCTAssertEqual(venue([]).displayName, "some-journal")
    }
}
