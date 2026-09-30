import XCTest
@testable import AkashicCore
@testable import AkashicStoreIO
@testable import AkashicMCPKit

/// 跑完所有情境一次的結果——三條測試共用，不必各跑一遍（每個情境要建一份 fixture store）。
struct PayloadObservations {
    /// 工具 → 該工具全部情境的鍵（物件的頂層鍵 ∪ 陣列的元素鍵）。
    var keysByTool: [String: Set<String>] = [:]
    /// 工具 → 該工具有沒有至少一個結構化（物件或陣列）的情境。
    var structuredTools: Set<String> = []
    /// 有情境的工具。
    var scenarioTools: Set<String> = []
    /// 巢狀路徑表（`ToolPayloadNestedPaths`）每一列在各情境裡取到的鍵：工具 → 路徑 → 鍵（#700）。
    /// 回應裡沒有那條路徑的情境不貢獻；路徑出現過（即使鍵是空集合）才會有這一格。
    var nestedKeysByTool: [String: [NestedPayloadPath: Set<String>]] = [:]
    /// 情境自己出的問題：擲錯、回的形狀不是預期。守衛不得因為 fixture 漂移而悄悄少掃。
    var problems: [String] = []

    static let shared: PayloadObservations = {
        var out = PayloadObservations()
        for s in ToolPayloadScenarios.all {
            out.scenarioTools.insert(s.tool)
            do {
                let raw = try s.run(try PayloadWorld())
                let shape = PayloadShape.of(raw)
                if shape.scenarioKind != s.expects {
                    out.problems.append("\(s.tool)／\(s.leg)：預期 \(s.expects)、實際 \(shape.scenarioKind)——\(raw.prefix(160))")
                }
                out.keysByTool[s.tool, default: []].formUnion(shape.keys)
                if shape.scenarioKind != .text { out.structuredTools.insert(s.tool) }
                for row in ToolPayloadNestedPaths.rows where row.tool == s.tool {
                    switch row.path.keys(in: raw) {
                    case .absent: break
                    case .keys(let k): out.nestedKeysByTool[s.tool, default: [:]][row.path, default: []].formUnion(k)
                    case .wrongShape(let what):
                        out.problems.append("\(s.tool)／\(s.leg)：巢狀路徑 \(row.path) 的形狀不對（\(what)）——表寫錯了，或 payload 改了形狀")
                    }
                }
            } catch {
                out.problems.append("\(s.tool)／\(s.leg)：擲錯——\(error)")
            }
        }
        PayloadWorld.removeTemplate()
        return out
    }()

    /// 豁免表比對用的全部鍵：頂層鍵，加上巢狀路徑的全名（`items[].reason`）。
    func qualifiedKeys(_ tool: String) -> Set<String> {
        var out = keysByTool[tool] ?? []
        for (path, keys) in nestedKeysByTool[tool] ?? [:] { out.formUnion(keys.map(path.qualified)) }
        return out
    }
}

/// 守衛的判定本體（純函式，負控直接對它餵改過的說明）。
enum ToolPayloadKeyCheck {
    /// 工具 → 沒被說明提到、也沒被豁免的鍵。
    static func undescribed(observed: [String: Set<String>], manifest: [String: ToolManifest.Tool],
                            exemptions: [String: [String: ToolPayloadKeyExemptions.Exemption]]) -> [String: [String]] {
        var out: [String: [String]] = [:]
        for (tool, keys) in observed {
            guard let m = manifest[tool] else { continue }
            let missing = keys.filter { key in
                !mentionsIdentifier(m.searchable, key) && exemptions[tool]?[key] == nil
            }
            if !missing.isEmpty { out[tool] = missing.sorted() }
        }
        return out
    }

    /// 巢狀路徑上沒被說明提到、也沒被豁免的鍵（#700）：工具 → 全名（`items[].reason`）。比對與頂層同一條規則——
    /// 鍵以識別字邊界出現在該工具說明的任何一處就算數（使用者裁決 (a)，不要求寫成 `items[].<鍵>` 的形式）；
    /// 豁免以全名查。
    static func undescribedNested(observed: [String: [NestedPayloadPath: Set<String>]], manifest: [String: ToolManifest.Tool],
                                  exemptions: [String: [String: ToolPayloadKeyExemptions.Exemption]]) -> [String: [String]] {
        var out: [String: [String]] = [:]
        for (tool, paths) in observed {
            guard let m = manifest[tool] else { continue }
            var missing: [String] = []
            for (path, keys) in paths {
                missing += keys.filter { key in
                    !mentionsIdentifier(m.searchable, key) && exemptions[tool]?[path.qualified(key)] == nil
                }.map(path.qualified)
            }
            if !missing.isEmpty { out[tool] = missing.sorted() }
        }
        return out
    }
}

/// #672：每個工具的說明都要跟得上它的回應鍵。設計與範圍見 `ToolManifest` 的檔頭。
///
/// **這一組測試沒有涵蓋的腿**（守衛的誠實邊界）：
/// - 只在特定 store 狀態出現的鍵：`akashic_doctor` 的 `layoutResidue`、`sourcesAuditError`；`akashic_import_zotero` 的
///   `authorsPreserved`、`quarantineConflicts`、`writeFailed`；各寫入工具在 I/O 失敗時的 `writeFailed`、`skipped` 等；
///   #705 起 13 個寫入工具在搬移後的 legacy 拷貝刪不掉時的 `writtenWithLegacyCopy`（分派層加上，說明是同一個常數
///   `legacyCopyNote`；接線由 `StdioE2ETests.testLegacyCopyLeftIsReportedOnTheSuccessSide` 走真 binary 釘住）。
/// - `akashic_files` 的 `use`（切換 session 的 active store，需要 registry）。
/// - 錯誤回應（`isError`）：那是訊息文字，不是 payload。
/// - **巢狀的鍵只看封閉表列出的路徑**（#700，使用者 2026-09-30 裁決 (a)）：`ToolPayloadNestedPaths` 的七列——`akashic_enrich` 的
///   `items[]`、`akashic_resolve_people` 的 `people[ref]`、`akashic_update_entry` 的 `sourcesAdded[]`、`akashic_update_venue` 的
///   `nameSegments[]` 與 `displayNameChanged`、`akashic_import_zotero` 的 `doiNominations[]`（#611）、`akashic_person` 的 `person`——各往下恰好一層。表外的巢狀物件與陣列不看（例如
///   `update_entry` 的 `sourcesRemoved[]`、`fieldRemovals[]`，`update_venue` 的 `issnRemoved[]`、`referencesRemoved[]`，
///   `resolve_*` 各寫入腿的逐筆清單），列入的路徑也不看第二層（`items[].provenanceOmitted` 的值、`person.unknownFields` 的內容）。
///   巢狀鍵的比對與頂層同一條規則：鍵名出現在該工具說明的任何一處就算數——`displayNameChanged` 的 `before`／`after` 是被
///   `nameSegments（action／before／after）` 那一處滿足的。
///   **預算只剩 4 bytes**（`tools/list` 51,996／52,000，2026-09-30）。列入的路徑上有兩個鍵沒有情境產生、也沒有寫進說明：
///   `items[].partial`（識別碼部分解析）與 `person.unknownFields`（#700 本文點名的那一個）——要守它們得同時加情境與說明，預算不夠，
///   數字記在 `changelog/2026-09-30-payload-guard-nested-paths.md`。
/// - **有才出現、情境沒走到的鍵**：`unknownFields`（`akashic_get_entry`／`akashic_people`／`akashic_venue`）、`provenance_additional`（`akashic_get_entry`）
///   已寫進說明，但沒有情境產生它們——說明日後拿掉它們，守衛看不到。
///   `items[].provenanceNotWritten` 同（要寫入失敗才出現）。
final class ToolPayloadKeyGuardTests: XCTestCase {
    private static let manifest: Result<[String: ToolManifest.Tool], Error> = Result { try ToolManifest.load() }

    private func loadManifest() throws -> [String: ToolManifest.Tool] { try Self.manifest.get() }

    /// 情境本身可靠：全部跑得起來、回的形狀是預期的、每個工具都有情境。
    func testEveryToolHasWorkingScenarios() throws {
        let manifest = try loadManifest()
        let observed = PayloadObservations.shared
        XCTAssertTrue(observed.problems.isEmpty, "情境有問題（fixture 漂移會讓守衛悄悄少掃）：\n" + observed.problems.joined(separator: "\n"))
        XCTAssertEqual(observed.scenarioTools, Set(manifest.keys),
                       "工具清單與情境不一致——新增工具要同時加情境（或在 textOnlyTools 說明為什麼沒有）。"
                       + "缺情境：\(Set(manifest.keys).subtracting(observed.scenarioTools).sorted())；"
                       + "多出的情境：\(observed.scenarioTools.subtracting(manifest.keys).sorted())")
        for tool in manifest.keys.sorted() {
            if observed.structuredTools.contains(tool) {
                XCTAssertNil(ToolPayloadKeyExemptions.textOnlyTools[tool], "\(tool) 有結構化的情境，不該再列為 textOnlyTools")
            } else {
                XCTAssertNotNil(ToolPayloadKeyExemptions.textOnlyTools[tool],
                                "\(tool) 的情境全是純文字——若它其實回結構化 payload，情境壞了；若它就是純文字，加進 textOnlyTools 並寫理由")
            }
        }
        XCTAssertGreaterThan(observed.keysByTool.values.map(\.count).reduce(0, +), 100, "掃到的鍵少得不合理——空掃描不是通過")
    }

    /// **守衛本體**：每個 payload 的鍵都要在該工具的說明裡，或被具名豁免。
    func testEveryPayloadKeyIsDescribedOrExempt() throws {
        let manifest = try loadManifest()
        let observed = PayloadObservations.shared
        var gaps = ToolPayloadKeyCheck.undescribed(observed: observed.keysByTool, manifest: manifest,
                                                   exemptions: ToolPayloadKeyExemptions.keys)
        gaps.merge(ToolPayloadKeyCheck.undescribedNested(observed: observed.nestedKeysByTool, manifest: manifest,
                                                         exemptions: ToolPayloadKeyExemptions.keys)) { $0 + $1 }
        let report = gaps.sorted { $0.key < $1.key }.map { "\($0.key)：\($0.value.joined(separator: "、"))" }.joined(separator: "\n")
        XCTAssertTrue(gaps.isEmpty,
                      "這些回應鍵不在工具說明裡：\n\(report)\n"
                      + "呼叫端讀不到 CLI --help——說明落後就等於這些欄位不存在。補進 Server.swift 的說明（只寫鍵名＋一句意思，"
                      + "守住 #578 的位元組預算），或在 ToolPayloadKeyExemptions 具名豁免並寫理由。")
    }

    /// 豁免不留過期的：豁免的鍵必須真的出現在 payload、且真的沒被說明提到。
    func testEveryExemptionIsLive() throws {
        let manifest = try loadManifest()
        let observed = PayloadObservations.shared
        for (tool, exempt) in ToolPayloadKeyExemptions.keys.sorted(by: { $0.key < $1.key }) {
            XCTAssertNotNil(manifest[tool], "豁免表列了不存在的工具 \(tool)")
            let live = observed.qualifiedKeys(tool)
            for (key, why) in exempt.sorted(by: { $0.key < $1.key }) {
                XCTAssertTrue(live.contains(key),
                              "\(tool).\(key) 豁免了，但情境的 payload 裡沒有這個鍵（鍵改名或情境漂移）——刪掉這一列：\(why.why)")
                // 巢狀的豁免以全名（`items[].reason`）列；說明比對的是最後那一段鍵名
                let bare = ToolPayloadNestedPaths.rows.first { $0.tool == tool && key.hasPrefix("\($0.path).") }
                    .map { String(key.dropFirst("\($0.path).".count)) } ?? key
                if let m = manifest[tool] {
                    XCTAssertFalse(mentionsIdentifier(m.searchable, bare),
                                   "\(tool).\(key) 已經寫進說明了，豁免過期——刪掉這一列")
                }
                XCTAssertFalse(why.why.trimmingCharacters(in: .whitespaces).isEmpty, "\(tool).\(key) 的豁免沒有理由")
            }
        }
    }

    /// 巢狀路徑表的每一列都活著（#700）：工具存在、在至少一個情境的回應裡以宣稱的形狀出現、取得到鍵、寫了理由。
    /// 一列取不到任何鍵＝那一層沒有被守——空掃描不是通過。
    func testEveryNestedPathIsLive() throws {
        let manifest = try loadManifest()
        let observed = PayloadObservations.shared
        var seen = Set<String>()
        for row in ToolPayloadNestedPaths.rows {
            let id = "\(row.tool) \(row.path)"
            XCTAssertTrue(seen.insert(id).inserted, "巢狀路徑表重複列了 \(id)")
            XCTAssertNotNil(manifest[row.tool], "巢狀路徑表列了不存在的工具 \(row.tool)")
            XCTAssertFalse(row.why.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, "\(id) 沒有寫理由")
            let keys = observed.nestedKeysByTool[row.tool]?[row.path] ?? []
            XCTAssertFalse(keys.isEmpty,
                           "\(id)：沒有任何情境的回應在這條路徑上取得到鍵——加一個會產生它的情境，或這一列已經過期（鍵改名、形狀改了）")
        }
        let nestedKeyCount = observed.nestedKeysByTool.values.flatMap(\.values).map(\.count).reduce(0, +)
        print("ToolPayloadNestedPaths：\(ToolPayloadNestedPaths.rows.count) 列｜往下一層取到的鍵 \(nestedKeyCount) 個｜"
              + ToolPayloadNestedPaths.rows.map { row in
                  let keys = (observed.nestedKeysByTool[row.tool]?[row.path] ?? []).sorted()
                  return "\(row.tool) \(row.path) \(keys.count)（\(keys.joined(separator: ","))）"
              }.joined(separator: "、"))
    }

    // MARK: - 負控（守衛會紅）

    /// 從真的說明裡拿掉一個鍵名 → 判定函式要報出它。
    func testGuardGoesRedWhenADescriptionDropsAKey() throws {
        let manifest = try loadManifest()
        let observed = PayloadObservations.shared
        // 挑一個現在有被說明的、非豁免的鍵：`akashic_enrich` 的 `itemsTotal`
        let tool = "akashic_enrich", key = "itemsTotal"
        let real = try XCTUnwrap(manifest[tool])
        XCTAssertTrue(observed.keysByTool[tool]?.contains(key) == true, "前提：payload 有 \(key)")
        XCTAssertTrue(mentionsIdentifier(real.searchable, key), "前提：說明提到 \(key)")
        let cleanGaps = ToolPayloadKeyCheck.undescribed(observed: observed.keysByTool, manifest: manifest,
                                                        exemptions: ToolPayloadKeyExemptions.keys)
        XCTAssertNil(cleanGaps[tool]?.first { $0 == key }, "前提：未改動時不報 \(key)")

        let mutated = ToolManifest.Tool(name: tool, text: real.text.replacingOccurrences(of: key, with: "XXXXX"),
                                        parameterText: real.parameterText.replacingOccurrences(of: key, with: "XXXXX"))
        var broken = manifest
        broken[tool] = mutated
        let gaps = ToolPayloadKeyCheck.undescribed(observed: observed.keysByTool, manifest: broken,
                                                   exemptions: ToolPayloadKeyExemptions.keys)
        XCTAssertTrue(gaps[tool]?.contains(key) == true, "說明拿掉 \(key) 之後守衛必須報出它：\(gaps[tool] ?? [])")
    }

    /// 巢狀的鍵同樣會紅（#700）：從 `akashic_resolve_people` 的說明拿掉 `observedAffiliationAt`（只住在 `people[ref]` 裡，
    /// 不是頂層鍵）→ 頂層的判定不報它、巢狀的判定要報出 `people[ref].observedAffiliationAt`。
    func testGuardGoesRedWhenADescriptionDropsANestedKey() throws {
        let manifest = try loadManifest()
        let observed = PayloadObservations.shared
        let tool = "akashic_resolve_people", key = "observedAffiliationAt", path = NestedPayloadPath.map("people")
        let real = try XCTUnwrap(manifest[tool])
        XCTAssertTrue(observed.nestedKeysByTool[tool]?[path]?.contains(key) == true, "前提：people[ref] 有 \(key)")
        XCTAssertFalse(observed.keysByTool[tool]?.contains(key) == true, "前提：\(key) 不是頂層鍵")
        XCTAssertTrue(mentionsIdentifier(real.searchable, key), "前提：說明提到 \(key)")
        let clean = ToolPayloadKeyCheck.undescribedNested(observed: observed.nestedKeysByTool, manifest: manifest,
                                                          exemptions: ToolPayloadKeyExemptions.keys)
        XCTAssertNil(clean[tool], "前提：未改動時不報")

        var broken = manifest
        broken[tool] = ToolManifest.Tool(name: tool, text: real.text.replacingOccurrences(of: key, with: "XXXXX"),
                                         parameterText: real.parameterText.replacingOccurrences(of: key, with: "XXXXX"))
        let topGaps = ToolPayloadKeyCheck.undescribed(observed: observed.keysByTool, manifest: broken,
                                                      exemptions: ToolPayloadKeyExemptions.keys)
        XCTAssertNil(topGaps[tool], "只看頂層的判定看不到它——這正是 #700 要補的盲區")
        let gaps = ToolPayloadKeyCheck.undescribedNested(observed: observed.nestedKeysByTool, manifest: broken,
                                                         exemptions: ToolPayloadKeyExemptions.keys)
        XCTAssertEqual(gaps[tool], ["people[ref].observedAffiliationAt"], "巢狀的判定必須報出它")
    }

    /// 路徑的三種形狀各取一層、不多取：表外的巢狀不看，列入的路徑不看第二層。
    func testNestedPathTakesExactlyOneLevel() {
        let raw = #"{"items":[{"a":1,"deep":{"x":1}},{"b":2}],"person":{"k":1,"sub":{"y":2}},"people":{"p0":{"c":1},"p1":{"d":2}},"other":{"z":1}}"#
        XCTAssertEqual(NestedPayloadPath.array("items").keys(in: raw), .keys(["a", "deep", "b"]))
        XCTAssertEqual(NestedPayloadPath.object("person").keys(in: raw), .keys(["k", "sub"]))
        XCTAssertEqual(NestedPayloadPath.map("people").keys(in: raw), .keys(["c", "d"]))
        XCTAssertEqual(NestedPayloadPath.array("missing").keys(in: raw), .absent)
        guard case .wrongShape = NestedPayloadPath.array("person").keys(in: raw) else {
            return XCTFail("宣稱是陣列而實際是物件：要報形狀不對，不是悄悄取零個鍵")
        }
        XCTAssertEqual(NestedPayloadPath.array("items").description, "items[]")
        XCTAssertEqual(NestedPayloadPath.map("people").description, "people[ref]")
        XCTAssertEqual(NestedPayloadPath.object("person").qualified("key"), "person.key")
        XCTAssertEqual(NestedPayloadPath.array("items").keys(in: #"{"items":[]}"#), .keys([]))
    }

    /// 子字串不算數：`namesTotal` 出現不代表 `names` 被說明了。
    func testASubstringOfAnotherIdentifierDoesNotCount() {
        XCTAssertFalse(mentionsIdentifier("回 namesTotal 與 issnTotal", "names"))
        XCTAssertFalse(mentionsIdentifier("回 namesTotal", "Total"))
        XCTAssertTrue(mentionsIdentifier("回 names、issn", "names"))
        XCTAssertTrue(mentionsIdentifier("names", "names"))
        XCTAssertTrue(mentionsIdentifier("（container-title）", "container-title"))
        XCTAssertFalse(mentionsIdentifier("", "names"))
    }

    /// 豁免表本身不得有空鍵、空理由（結構上逐鍵具名）。
    func testExemptionTableIsWellFormed() {
        for (tool, exempt) in ToolPayloadKeyExemptions.keys {
            XCTAssertTrue(tool.hasPrefix("akashic_"), tool)
            for (key, e) in exempt {
                XCTAssertFalse(key.isEmpty, "\(tool) 有空鍵")
                XCTAssertFalse(e.why.isEmpty, "\(tool).\(key) 沒有理由")
            }
        }
    }
}
