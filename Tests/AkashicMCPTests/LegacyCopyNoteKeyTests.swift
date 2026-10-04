import XCTest
@testable import AkashicMCPKit

/// #705 第三次 verify（LOW 17）：`Server.legacyCopyNote` 說「鍵名加 Total」「加 NotApplied」——組出來的名字要是回應裡真的鍵。
/// 改名任一個常數而不改那一句，這裡會紅（說明的組字由 `StdioE2ETests.testTheSharedLegacyCopyNoteNamesBothCompanionKeys` 從真 binary 釘住）。
final class LegacyCopyNoteKeyTests: XCTestCase {
    func testTheComposedKeyNamesInTheSharedNoteExist() {
        XCTAssertEqual(AkashicService.writtenWithLegacyCopyKey + "Total", AkashicService.writtenWithLegacyCopyTotalKey)
        XCTAssertEqual(AkashicService.writtenWithLegacyCopyKey + "NotApplied", AkashicService.writtenWithLegacyCopyNotAppliedKey)
    }
}
