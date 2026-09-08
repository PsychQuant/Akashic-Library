import XCTest
import Foundation

/// #62：doc comment 與 attribute 的**歸屬**在「兩個函式之間插入新函式」時會靜默轉移。
///
/// Swift 把 attribute 與 doc comment 綁到「跳過 trivia 後的下一個宣告」，中間夾幾段
/// 註解都不影響。所以在 doc block 中間插入函式 = 靜默轉移：
///
/// ```
/// /// doc for A          ← 插入 B 之後綁到 B
/// @discardableResult     ← 也綁到 B
/// func B() -> Y
/// func A() -> X          ← 兩者都失去
/// ```
///
/// 這個錯誤**已經發生兩次**（`1f9bacf`／#35 的 `renameEntry`、PR #55 的 `writePerson`），
/// 兩次都只有編譯 warning、沒有測試失敗，而 review 在 diff 上看只是「新增一個函式」。
///
/// ## 這個測試涵蓋哪一半
///
/// 只涵蓋**接收方回傳 Void** 的那一半——`@discardableResult` 貼在不回傳值的函式上是
/// 自我矛盾的，那個條件自我描述、不需要維護一份會過期的函式清單。事故一正是這個形狀
/// （`assertNoCrossRecordErrors` 回傳 Void）。
///
/// 事故二（`writeOrganization` 回傳 `URL`）**這個測試抓不到**，由 CI 的
/// `-warnings-as-errors` 補上：受害者 `writePerson` 失去 attribute 後，14 個站點變成
/// unused-result warning。兩個守衛各補一半，都不是全稱保證。
///
/// 曾評估但**否決**的第三個方案：「每個 public func 都要有 doc comment」——那能同時
/// 抓到兩次事故（受害者失去 doc），但實測 147 個 public func 裡 69 個（46%）沒有 doc，
/// 所以它不是這個 repo 的既有慣例；當成守衛就得先補 69 份文件，那是另一件事。
final class AttributeBindingTests: XCTestCase {

    private func sourceFiles() throws -> [URL] {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()      // AkashicKitTests
            .deletingLastPathComponent()      // Tests
            .deletingLastPathComponent()      // repo root
            .appendingPathComponent("Sources")
        var out: [URL] = []
        let e = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)
        while let u = e?.nextObject() as? URL {
            if u.pathExtension == "swift" { out.append(u) }
        }
        XCTAssertFalse(out.isEmpty, "掃不到任何原始碼——路徑推導壞了，這個測試會空洞地通過")
        return out
    }

    /// `@discardableResult` 貼在回傳 Void 的函式上 = 這個 attribute 綁錯了對象。
    func testNoDiscardableResultOnVoidFunction() throws {
        var offenders: [String] = []
        for url in try sourceFiles() {
            let lines = try String(contentsOf: url, encoding: .utf8)
                .components(separatedBy: "\n")
            for (i, line) in lines.enumerated()
            where line.trimmingCharacters(in: .whitespaces) == "@discardableResult" {
                // 往下跳過其他 attribute 行，找宣告
                var j = i + 1
                while j < lines.count,
                      lines[j].trimmingCharacters(in: .whitespaces).hasPrefix("@") { j += 1 }
                guard j < lines.count else { continue }
                let decl = lines[j]
                guard decl.contains("func ") else { continue }
                // 多行簽章：往下併到出現 `{` 或 `->` 為止（上限保守）
                var sig = decl
                var k = j
                while !sig.contains("{"), !sig.contains("->"), k + 1 < lines.count, k - j < 8 {
                    k += 1; sig += " " + lines[k]
                }
                let returnsVoid = !sig.contains("->")
                    || sig.contains("-> Void") || sig.contains("-> ()")
                if returnsVoid {
                    offenders.append("\(url.lastPathComponent):\(j + 1) "
                        + decl.trimmingCharacters(in: .whitespaces))
                }
            }
        }
        XCTAssertTrue(offenders.isEmpty,
            "@discardableResult 貼在不回傳值的函式上——那個 attribute 綁錯了對象"
            + "（很可能是有人在 doc comment 與原函式之間插入了新宣告，見 #62）：\n"
            + offenders.joined(separator: "\n"))
    }

    /// **`@discardableResult` 後面不得直接接 `///`**（#491）。
    ///
    /// 上面那條自己寫著它「只涵蓋**接收方回傳 Void** 的那一半」。#491 落在另一半：
    /// 插進來的新函式**回傳 `String?`**，所以 attribute 綁得「合法」——沒有 warning、
    /// 沒有 build 失敗、上面那條也不紅——而原本的 `renameEntry` 靜靜地掉了 attribute。
    /// 那是**第三度**被夾在中間的新函式奪走（#11 加入 → #35 奪走 → #59 復原 → 再次）。
    ///
    /// 這一半用**形狀**抓而不是型別：正常寫法是 `/// doc` → `@attribute` → `decl`。
    /// attribute 後面若跟著 `///`，那段 doc 只可能屬於**下一個宣告**——也就是說
    /// attribute 與它原本要修飾的宣告之間被插進了東西。實測全樹恰好兩處，兩處都是
    /// 真的漂移（一處是 #491 本身，一處是 `recordDivergence` 的 `- Parameter` 被
    /// attribute 從它的 doc comment 切開），修完為 **0**。
    func testNoDiscardableResultFollowedByDocComment() throws {
        var offenders: [String] = []
        for url in try sourceFiles() {
            let lines = try String(contentsOf: url, encoding: .utf8)
                .components(separatedBy: "\n")
            for (i, line) in lines.enumerated()
            where line.trimmingCharacters(in: .whitespaces) == "@discardableResult" {
                var j = i + 1
                while j < lines.count, lines[j].trimmingCharacters(in: .whitespaces).isEmpty { j += 1 }
                guard j < lines.count,
                      lines[j].trimmingCharacters(in: .whitespaces).hasPrefix("///") else { continue }
                offenders.append("\(url.lastPathComponent):\(i + 1) → 下一行是 "
                    + lines[j].trimmingCharacters(in: .whitespaces).prefix(60))
            }
        }
        XCTAssertTrue(offenders.isEmpty,
            "@discardableResult 後面直接接 `///`——那段 doc 屬於下一個宣告，"
            + "表示 attribute 與它原本要修飾的宣告之間被插進了東西。"
            + "attribute 仍會綁到下一個宣告上，所以**編譯器不會抱怨**，"
            + "而原本的 API 靜靜地掉了它（#491，第三度）：\n"
            + offenders.joined(separator: "\n"))
    }
}
