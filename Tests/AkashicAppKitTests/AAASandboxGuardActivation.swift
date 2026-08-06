import XCTest
import AkashicTestGuard

/// #124：process-level 沙箱守衛的啟用點。AAA 前綴讓字母序最先跑——基線在
/// 任何真正的測試之前記錄。守衛本體與理由見 `RealHomeSandboxGuard`。
final class AAASandboxGuardActivationTests: XCTestCase {
    func testGuardIsActive() {
        RealHomeSandboxGuard.shared.activate()
    }
}
