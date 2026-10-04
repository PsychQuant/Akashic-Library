import Foundation
import XCTest
@testable import AkashicStoreIO
@testable import AkashicAppKit

/// b31 W5 LOW 3、8、15（#703）：App 健康區塊的「sources 殘留暫存檔」以 `isStale()` 計數——它也數修改時間不可信的檔（在未來、讀不到），
/// 先前說明寫「被中斷留下的檔……只數一小時沒動的」，對那些檔兩句都不成立。CLI 的 doctor 對同一個檔說「判不出是中斷的存檔留下的、
/// 還是正在進行的存檔」。這裡釘住說明與計數一致、與 CLI 同義。
final class StrayTemporaryHelpTests: XCTestCase {
    func testHelpCoversUntrustworthyTimesAndDoesNotClaimTheFileWasInterrupted() {
        let help = ContentView.strayTemporaryFilesHelp
        XCTAssertTrue(help.contains("修改時間不可信"), help)
        XCTAssertTrue(help.contains("不斷言它們是中斷留下的"), help)
        XCTAssertFalse(help.contains("只數一小時沒動的"), help)
        // 計數那一側的事實：修改時間在未來的檔 isStale 為 true（被數進去），所以說明必須涵蓋它
        let future = LibraryStore.StrayTemporaryFile(path: "sources/ab/.x.incoming-y", bytes: 1,
                                                     modified: Date().addingTimeInterval(365 * 86_400))
        XCTAssertTrue(future.isStale())
        XCTAssertTrue(future.possiblyInProgress())
    }
}
