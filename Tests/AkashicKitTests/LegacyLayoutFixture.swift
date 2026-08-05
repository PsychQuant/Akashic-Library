import XCTest
import Foundation

/// 測試 fixture 手寫**原始檔**進 legacy 目錄時的共用前置（#101）。
///
/// 為什麼需要這個：有一批測試（quarantine、unknown-field 可見性、檔名 stem 不符…）
/// 用 `String.write(to:atomically:true)` 直接把 YAML 丟進 `entries/`／`people/`，
/// **繞過 store 的寫入 API**。`loadAll` 刻意與 legacy 佈局並存讀取，所以這是有效的
/// 覆蓋——但 Foundation 的 atomic write 會在目的目錄裡 mktemp，目錄不在就是 errno 2。
///
/// 在 #101 之前這些目錄由 `ensureLayout()` 無條件建立，fixture 於是不必宣告自己需要
/// 它們。現在 `ensureLayout` 只建 store 實際在用的目錄，需要 legacy 目錄的 fixture
/// 就得自己說——這與 `EntitiesLayoutTests.legacyStore()` 一直以來的做法一致。
///
/// **這不改變被測行為**：只是把「我要往這裡寫原始檔」這個前置條件從隱含變成明講。
extension XCTestCase {
    func makeLegacyDirectories(in root: URL) throws {
        for sub in ["entries", "people"] {
            try FileManager.default.createDirectory(
                at: root.appendingPathComponent(sub), withIntermediateDirectories: true)
        }
    }
}
