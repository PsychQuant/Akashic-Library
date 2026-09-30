import Foundation
import XCTest

/// #706：workflow 裡的每一個 `uses:` 都釘到 commit SHA，行尾註解寫它對應的版本標籤。
///
/// 版本標籤可以被移動，SHA 不行。更新是手動的（使用者 2026-09-30 裁決：不加 Dependabot），
/// 所以沒有任何機制會在有人改回 `@v4` 時出聲——這支測試就是那個機制。
final class WorkflowActionPinningTests: XCTestCase {

    func testEveryWorkflowActionIsPinnedToACommitSHA() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let dir = root.appendingPathComponent(".github/workflows")
        let files = try FileManager.default.contentsOfDirectory(atPath: dir.path)
            .filter { $0.hasSuffix(".yml") || $0.hasSuffix(".yaml") }
            .sorted()
        XCTAssertFalse(files.isEmpty, "找不到任何 workflow——掃描空集合不是通過")

        let pinned = try NSRegularExpression(
            pattern: #"^\s*-?\s*uses:\s*[A-Za-z0-9_.\-]+/[A-Za-z0-9_.\-/]+@[0-9a-f]{40}\s+#\s*v\d+(\.\d+)*\s*$"#)
        var uses = 0
        var unpinned: [String] = []
        for name in files {
            let text = try String(contentsOf: dir.appendingPathComponent(name), encoding: .utf8)
            for (i, line) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
                let s = String(line)
                guard s.range(of: #"^\s*-?\s*uses:"#, options: .regularExpression) != nil else { continue }
                uses += 1
                if pinned.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) == nil {
                    unpinned.append("\(name):\(i + 1): \(s.trimmingCharacters(in: .whitespaces))")
                }
            }
        }
        XCTAssertGreaterThan(uses, 0, "沒有掃到任何 uses: 行——判準寫錯了，不是全部都釘好了")
        XCTAssertEqual(unpinned, [], "這些 action 沒有釘到 40 位 commit SHA（或行尾缺版本註解）")
    }
}
