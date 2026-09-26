import XCTest
import Foundation
@testable import AkashicCore
@testable import AkashicStoreIO

/// #554 R26（D74）→ R27（D75；R26 verify DA 第 4 列 HIGH、第 26 列，security 第 18／19／20／35 列，requirements 第 9／31 列，logic 第 15／33 列，
/// regression 第 24／53 列）：`perRecordIssues`／`crossRecordIssues`／quarantine reason 的每一個生產者迴送 store 字串時都要走 `displaySafeInvisible`。
/// R26 的守衛掃五個檔、以識別字拼法為允許清單——`Models.swift`（三族 validate()）、`Identifier.swift`（四族委派的識別碼訊息）、`LibraryStore.swift`
/// （跨記錄問題、quarantine reason）都不在裡面，而允許清單的三個 `key` 站點正好是 key **沒**通過 StoreKey 才會出的訊息、兩個是死條目、
/// `displaySafeClipOnly(` 完全繞得過。現在的規則沒有允許清單：生產者檔案裡 `displaySafe(` 一律是違規（對 StoreKey 驗過的字串
/// `displaySafeInvisible` 的輸出逐字相同，所以換掉沒有代價）；`displaySafeClipOnly(` 只在同一行寫明「已消毒」的 exempt 註解時放行；
/// 三個 helper 的實作行是封閉列舉、每一行都要真的存在（死條目即紅）。
final class InvisibleEscapeCoverageTests: XCTestCase {
    private static let repoRoot: URL = {
        var u = URL(fileURLWithPath: #filePath)
        while u.lastPathComponent != "Tests" { u.deleteLastPathComponent() }
        return u.deletingLastPathComponent()
    }()

    static let producerFiles = ["Sources/AkashicStoreIO/StoreHealth.swift", "Sources/AkashicStoreIO/LibraryStore.swift",
                                "Sources/AkashicCore/AuthorizedName.swift", "Sources/AkashicCore/Venue.swift",
                                "Sources/AkashicCore/Organization.swift", "Sources/AkashicCore/Divergence.swift",
                                "Sources/AkashicCore/Models.swift", "Sources/AkashicCore/Identifier.swift"]
    /// 三個 helper 的實作行（Models.swift）——它們自己呼叫 `displaySafe(`，是唯一合法的呼叫端。
    static let helperImplementationLines: Set<String> = [
        "var safe = displaySafe(String(line), max: maxLineLength,",   // displaySafeMultiline（R30：只截支要退讓，所以是 var）
        "escapingInvisibleScalars(displaySafe(s, max: max))",          // displaySafeInvisible
        "let out = displaySafe(s, max: max, escapingBackslash: false)",   // displaySafeClipOnly（R29：截點退讓搬進來，實作行多了 let）
    ]

    /// `producerFiles` 不再只是手寫清單（R27 verify 第 15／24 列：清單今天恰好等於建構 `ValidationIssue(` 的檔案集合，但沒有東西讓它保持相等）：
    /// 與 `ByteExactKeySiteInventoryTests` 同形——expected 是封閉列舉，found 從樹上現算，多一個少一個都紅。
    func testProducerFileListMatchesTheFilesConstructingValidationIssues() throws {
        let sources = Self.repoRoot.appendingPathComponent("Sources")
        var found: Set<String> = []
        let e = try XCTUnwrap(FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil))
        for case let url as URL in e where url.pathExtension == "swift" {
            if try String(contentsOf: url, encoding: .utf8).contains("ValidationIssue(") {
                found.insert(String(url.path.dropFirst(Self.repoRoot.path.count + 1)))
            }
        }
        XCTAssertEqual(found, Set(Self.producerFiles), "多了：\(found.subtracting(Self.producerFiles))；少了：\(Set(Self.producerFiles).subtracting(found))")
    }

    func testProducersNeverCallTheEnumeratedEscapeOrTheClipOnlyPathOnStoreStrings() throws {
        var offenders: [String] = []
        var seenHelperLines: Set<String> = []
        for f in Self.producerFiles {
            let text = try String(contentsOf: Self.repoRoot.appendingPathComponent(f), encoding: .utf8)
            for (n, raw) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
                let line = String(raw); let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("//") || trimmed.hasPrefix("public func ") || trimmed.hasPrefix("func ") { continue }
                if line.contains("displaySafe(") {
                    if Self.helperImplementationLines.contains(trimmed) { seenHelperLines.insert(trimmed); continue }
                    offenders.append("\(f):\(n + 1) displaySafe( — 生產者對 store 字串要 displaySafeInvisible")
                }
                if line.contains("displaySafeClipOnly("), !(line.contains("display-safe-exempt:") && line.contains("已消毒")) {
                    offenders.append("\(f):\(n + 1) displaySafeClipOnly( 沒有「已消毒」的 exempt 註解")
                }
            }
        }
        XCTAssertEqual(offenders, [], offenders.joined(separator: "\n"))
        XCTAssertEqual(seenHelperLines, Self.helperImplementationLines, "helper 實作行的封閉列舉有死條目或漏了一行：\(Self.helperImplementationLines.symmetricDifference(seenHelperLines))")
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

    /// 第六個生產者（R26 verify DA 第 4 列）：識別碼不是正規形的訊息迴送原樣值與正規形。
    /// 原本的 fixture 是 doi 裡的 ZWSP 與 TAG 字元——#589 R2 起 `DOI.init` 直接拒收它們，那個形狀在
    /// store 裡已經造不出來（下面第一段斷言釘住）。訊息的逃脫仍要驗：私用區字元（Co）進得了 DOI 後綴，
    /// 而 `escapingInvisibleScalars` 會逃它。
    func testIdentifierDiagnosticsEscapeInvisibleScalars() throws {
        XCTAssertNil(DOI("10.1037/A\u{200B}B\u{E0001}C"), "#589：不可見字元在建構時就拒收")
        var entry = Entry(id: UUID(), citekey: "e2020a", type: .periodicalArticle, title: "T")
        entry.doi = [try XCTUnwrap(DOI("10.1037/A\u{E000}B"))]
        let msgs = entry.validate().map(\.message).filter { $0.contains("不是正規形") }
        XCTAssertEqual(msgs.count, 1, entry.validate().map(\.message).description)
        XCTAssertFalse(msgs[0].unicodeScalars.contains { $0.value == 0xE000 }, msgs[0])
        XCTAssertTrue(msgs[0].contains("\\u{E000}"), msgs[0])
    }

    /// 第七個生產者（R26 verify DA 第 26 列）：跨記錄問題迴送 work 的 title——全庫最自由的欄位；quarantine reason（security 第 18 列、DA 第 44 列）
    /// 迴送 key 與 decode error 全文，且 `StoreKey.pattern` 的反斜線要原樣（修法指示不得被逃成 `\u{005C}A`）。
    func testCrossRecordAndQuarantineReasonsAreSanitizedOnceAtTheProducer() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("akashic-esc-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = LibraryStore(root: root); try store.ensureLayout()
        let title = "zero width\u{E0001}tag study"
        for (ck, doi) in [("a2020x", "10.1000/one"), ("b2020x", "10.1000/two")] {
            var e = Entry(id: UUID(), citekey: ck, type: .periodicalArticle, title: title, date: "2020")
            e.fields["doi"] = doi
            try store.writeEntry(e)
        }
        let person = Person(key: "fann", names: PersonNames(authorized: ["Fann"]))
        let yaml = try PersonYAML.encode(person).replacingOccurrences(of: "key: fann", with: "key: \"fa\u{200B}nn\"")
        XCTAssertTrue(yaml.contains("\u{200B}"), "fixture：替換要命中")
        try yaml.write(to: root.appendingPathComponent("entities/\(person.id.uuidString).yaml"), atomically: true, encoding: .utf8)
        let load = try store.load()
        let cross = store.health(from: load).crossRecordIssues.map(\.message).filter { $0.contains("標題與年份相同但 DOI 不同") }
        XCTAssertEqual(cross.count, 1, store.health(from: load).crossRecordIssues.map(\.message).description)
        XCTAssertFalse(cross[0].unicodeScalars.contains { $0.value == 0xE0001 }, cross[0])
        XCTAssertTrue(cross[0].contains("\\u{E0001}"), cross[0])
        let reason = try XCTUnwrap(load.quarantined.first?.reason, "壞 key 的 person 要被 quarantine")
        XCTAssertFalse(reason.unicodeScalars.contains { $0.value == 0x200B }, reason)
        XCTAssertTrue(reason.contains("\\u{200B}"), reason)
        XCTAssertTrue(reason.contains(StoreKey.pattern), "修法指示裡的正則要原樣：\(reason)")
        XCTAssertFalse(reason.contains("\\u{005C}"), "生產端只消毒一次、不得逃脫程式自己寫的反斜線：\(reason)")
    }
}
