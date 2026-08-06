import XCTest
import AkashicTestGuard

/// #124：守衛接線的回歸釘。啟用本身由 AkashicTestGuardLoader 的 C constructor
/// 在 bundle 載入時完成（--filter/--parallel 全涵蓋）——本測試只斷言接線存活：
/// loader 的 object 若被 linker 丟掉（靜態庫 dead-strip 的典型雷）、或 constructor
/// 沒跑，這裡立刻紅，而不是守衛靜默缺席。
final class AAASandboxGuardActivationTests: XCTestCase {
    func testGuardActivatedByBundleLoad() {
        XCTAssertTrue(RealHomeSandboxGuard.shared.isActive,
                      "C constructor 未啟用守衛——loader 接線斷了（見 AkashicTestGuardLoader）")
    }
}
