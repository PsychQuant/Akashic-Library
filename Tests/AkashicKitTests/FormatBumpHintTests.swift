import XCTest
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
