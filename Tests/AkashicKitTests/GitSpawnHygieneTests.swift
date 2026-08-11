import Foundation
import XCTest

/// #239 的第二層：**架構測試**，不是 runtime 斷言。
///
/// 產品程式碼每一處 spawn git 都必須剝除 `GIT_*`——`-C <dir>` 擋不住 `GIT_DIR`，
/// 後者優先權更高。曾試圖在 `assertSourcesExcluded` 加 runtime containment 斷言，
/// 兩個探針都不可用（見該處註解）；真正的復發風險本來就是靜態的：**新增一個
/// 呼叫點時忘記剝除**。那用讀原始碼的測試驗，比在 runtime 再驗一次同一件事誠實。
///
/// 這個測試會在「有人新增 git 呼叫點」時變紅——那正是它的作用，不是誤報。
/// 修法：讓新呼叫點走既有的剝除 helper，或在該型別加自己的 `scrubbedGitEnvironment`
/// 並在此登記。
final class GitSpawnHygieneTests: XCTestCase {

    /// 從本檔位置往上找 repo root（含 `Sources/` 的那層）。
    private var sourcesDirectory: URL {
        var dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        while dir.path != "/" {
            let candidate = dir.appendingPathComponent("Sources")
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: candidate.path, isDirectory: &isDir),
               isDir.boolValue {
                return candidate
            }
            dir = dir.deletingLastPathComponent()
        }
        XCTFail("找不到 Sources/ —— 測試無法定位原始碼樹")
        return URL(fileURLWithPath: "/nonexistent")
    }

    /// 已知會 spawn git 且**已剝除環境**的檔案（封閉列舉）。
    ///
    /// 新增檔案到這裡之前，先確認它真的設了 `environment`——這份清單是「已檢視過」
    /// 的紀錄，不是豁免權。
    private let auditedFiles: Set<String> = [
        "DivergenceResolve.swift",   // 共用 helper git(_:in:)；SourceStore 與刪除閘都走它
        "Validation.swift",          // TractatusDocs 的歷史驗證（兩處）
    ]

    func testEveryGitSpawnInSourcesScrubsGitEnvironment() throws {
        let fm = FileManager.default
        let root = sourcesDirectory
        guard let walker = fm.enumerator(at: root, includingPropertiesForKeys: nil) else {
            return XCTFail("無法走訪 \(root.path)")
        }

        var offenders: [String] = []
        var found: Set<String> = []

        for case let url as URL in walker where url.pathExtension == "swift" {
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            // spawn git 的判準：arguments 陣列裡出現 "git" 這個字面 argv[0]。
            guard text.contains("\"git\",") || text.contains("[\"git\"]") else { continue }
            found.insert(url.lastPathComponent)
            if !text.contains("scrubbedGitEnvironment") {
                offenders.append(url.lastPathComponent)
            }
        }

        XCTAssertTrue(
            offenders.isEmpty,
            """
            以下檔案 spawn git 但沒有剝除 `GIT_*`（#239）：\(offenders.sorted().joined(separator: "、"))

            `-C <dir>` 擋不住 `GIT_DIR`——從 git hook 執行時，這些呼叫會對**錯的 repo**
            提問。`sources/` 排除閘的失效方向是 fail-open（放行不該放行的寫入，且外流
            不可逆）。讓新呼叫點走剝除環境的 helper。
            """
        )

        // 反向：登記過的檔案若不再 spawn git，清單就該縮——否則它會慢慢變成一份
        // 沒人維護的名單，然後某天有人以為「在清單裡＝安全」。
        let stale = auditedFiles.subtracting(found)
        XCTAssertTrue(
            stale.isEmpty,
            "以下檔案已不再 spawn git，請從 auditedFiles 移除：\(stale.sorted().joined(separator: "、"))"
        )
    }
}
