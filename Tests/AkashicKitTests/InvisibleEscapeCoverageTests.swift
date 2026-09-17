import XCTest
import Foundation
@testable import AkashicCore
@testable import AkashicStoreIO

/// #554 R26（D74；R25 verify 第 8／9／13／16／22／36 列）：`perRecordIssues` 的每一個生產者——五族 `validate()` 與 `StoreHealth`——迴送
/// store 字串時都要走 `displaySafeInvisible`。R25 的 D68 只換了 `StoreHealth`，而 `Entry.validate()`／`Person.validate()`／`Venue.validate()`
/// 的其餘訊息、未知欄位鍵、`AuthorizedNames` 的名字仍走列舉式 `displaySafe`——DA 真 binary：person 名字裡的 TAG 字元（U+E0001／U+E0041）與
/// ZWSP 原樣穿過 CLI 與 MCP doctor payload。`DisplaySinkCoverageTests` 把兩個函式視為等價，所以沒有守衛認得出這個差別——本檔補那個守衛。
final class InvisibleEscapeCoverageTests: XCTestCase {
    private static let repoRoot: URL = {
        var u = URL(fileURLWithPath: #filePath)
        while u.lastPathComponent != "Tests" { u.deleteLastPathComponent() }
        return u.deletingLastPathComponent()
    }()

    /// 生產者檔案裡每一個 `displaySafe(` 的第一個引數，要嘛在允許清單（StoreKey 驗過的 key／citekey／holder、或 Int 常量），要嘛就是
    /// 未信任的 store 字串——那一類一律要 `displaySafeInvisible(`。允許清單是封閉的：加成員要在這裡加一列並寫理由。
    func testEveryDisplaySafeInPerRecordProducersTakesAValidatedKey() throws {
        let files = ["Sources/AkashicStoreIO/StoreHealth.swift", "Sources/AkashicCore/AuthorizedName.swift", "Sources/AkashicCore/Venue.swift",
                     "Sources/AkashicCore/Organization.swift", "Sources/AkashicCore/Divergence.swift"]
        // StoreKey 驗過（`[a-z0-9][a-z0-9-]*`）或程式自己組出的字串——`displaySafe` 對它們夠用
        let allowed: Set<String> = ["key", "citekey", "ownerKey", "owner", "p.holder", "e.pairing.holder", "pv.holder", "c.key", "w",
                                    "String(describing: error)", "h.slot", "h.digest"]
        var offenders: [String] = []
        for f in files {
            let text = try String(contentsOf: Self.repoRoot.appendingPathComponent(f), encoding: .utf8)
            for (n, line) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
                var s = Substring(line)
                while let r = s.range(of: "displaySafe(") {
                    let after = s[r.upperBound...]
                    // 第一個引數：掃到深度 0 的逗號或右括號為止（`String(describing: error)` 自己帶括號）
                    var depth = 0; var argChars = ""
                    for ch in after {
                        if ch == "(" { depth += 1 } else if ch == ")" { if depth == 0 { break }; depth -= 1 } else if ch == ",", depth == 0 { break }
                        argChars.append(ch)
                    }
                    let arg = argChars.trimmingCharacters(in: .whitespaces)
                    if !allowed.contains(arg) { offenders.append("\(f):\(n + 1) displaySafe(\(arg)") }
                    s = after
                }
            }
        }
        XCTAssertEqual(offenders, [], "未信任的 store 字串要走 displaySafeInvisible：\n" + offenders.joined(separator: "\n"))
    }

    /// 端到端：五族 validate() 的訊息裡不得出現原始 ZWSP——person 名字（分割重疊／近重複）、entry 未知欄位鍵、venue 孤兒 variant。
    func testValidateMessagesEscapeInvisibleScalars() throws {
        let zw = "Fa\u{200B}nn"
        let person = Person(key: "fann", names: PersonNames(authorized: ["Fann"], variant: [zw, "Fann\u{2010}\u{200B}"]))
        var venue = Venue(key: "alpha", type: .periodical, names: Timeline([TemporalValue(value: "Alpha")]), authorized: [])
        venue.variant = [zw]
        var entry = Entry(id: UUID(), citekey: "e2020a", type: .periodicalArticle, title: "T")
        entry.fields["editor"] = zw
        let msgs: [String] = person.validate().map { $0.message } + venue.validate().map { $0.message } + entry.validate().map { $0.message }
        XCTAssertFalse(msgs.isEmpty)
        for m in msgs {
            XCTAssertFalse(m.unicodeScalars.contains { $0.value == 0x200B }, "原始 ZWSP 進了訊息：\(m)")
        }
        XCTAssertTrue(msgs.contains { $0.contains("\\u{200B}") }, msgs.description)
    }
}
