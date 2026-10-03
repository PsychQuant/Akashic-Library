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
///   巢狀鍵的比對與頂層同一條規則（`mentionsIdentifier`，#700 R1 verify 第 8、18 則起：識別字邊界，**且不夾在連續的散文之間**）——鍵名以鍵名的
///   形式出現在該工具說明的任何一處就算數，不要求寫成 `items[].<鍵>`。`displayNameChanged` 的 `before`／`after` 另以
///   `displayNameChanged（before／after）` 寫出（第 8 則：先前只由 `nameSegments（action／before／after）` 那一處代為滿足）。
///   **收緊之後仍有的盲區**：語法區分不了「回應鍵」與「同名的輸入鍵」——`sourcesAdded[].digest`、`items[].citekey`／`sourceDigest`、
///   `nameSegments[].name`／`reason`、`person.key` 這幾個詞同時是這個工具的輸入（`{name, match?, … reason（必填…）}`、`目標 citekey（…）`），
///   輸入那一側的提及仍然在鍵名的位置上，拿掉回應那一側的說明守衛仍可能綠。這是裁決 (a) 的固有限制（通用字被別處的同一個字滿足，#672 已記），
///   不是這條規則能補的；`changelog/2026-10-01-payload-guard-r1-fixes.md` 有逐鍵的量測。
///   **表外的巢狀鍵不在守衛裡是設計，不是疏漏**（裁決 (a)，#700 R1 verify 第 29 則）：2026-10-01 以本檔的規則量，表外還有 54 條一層路徑、
///   208 個鍵，其中 94 個沒被說明以鍵名的形式提到（含 4 個以資料為鍵的字典項：`issnMediumRecorded` 的 ISSN、`ambiguousSourceClaims` 的來源鍵；
///   契約鍵約 90 個）——寫入腿的回應（`resolve_people` 的 `split[]`／`dropped[]`／`unsplit[]`、`update_entry` 的 `zoteroSourceRemovals[]`／
///   `fieldRemovals[]`、`update_venue` 的 `referencesRemoved[]`、`resolve_venues` 的 `venueEdgesRemoved[]`）、`doctor` 的 `recordIssues{}`
///   與 `sources{}`，也包括 `akashic_person` 的另外兩個容器 `publications[]`（六個鍵）與 `co_authors[]`。表內 `person` 那一列的理由
///   （「不往下看等於整筆人物資料沒有守衛」）對它們同樣成立，但每多一列就是一次 `tools/list` 的位元組預算，使用者裁決是預算只花在列入的路徑上。
///   這個量是在本檔之外（一支用完即丟的傾印）算的，沒有守衛維持它。
/// - **有才出現、情境沒走到的鍵**：`unknownFields`（`akashic_get_entry`／`akashic_people`／`akashic_venue`）、`provenance_additional`（`akashic_get_entry`）
///   已寫進說明，但沒有情境產生它們——說明日後拿掉它們，守衛看不到。
///   （#700 R1 verify 第 3、26 則關掉的四個：`items[].provenanceNotWritten`、`items[].partial`、`person.unknownFields`、`person.orcid`——
///   各有情境產生，`testTheKeysTheIssueNamedAreProducedByScenarios` 釘住它們真的被產生；先前寫的「預算只剩 4 bytes」在 03a8e729 把上限調到
///   54,000 之後不再成立，那四個鍵的說明共約 70 bytes。）
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

    /// **夾在連續散文之間的提及不算**（#700 R1 verify 第 8、18 則）：`index` 在 `indexRebuilt 說 index 有沒有重建` 裡說的是 index 的重建，
    /// 不是 `items[].index` 這個鍵；`citekey` 在 `以 citekey 或 doi 指名` 裡是輸入。兩邊都是字的才不算——任何一邊是標點、括號、反引號或文字的頭尾就算。
    func testAMentionInsideRunningProseDoesNotCount() {
        // 不算：兩邊（跳過空白之後）都是字
        XCTAssertFalse(mentionsIdentifier("indexRebuilt 說 index 有沒有重建", "index"))
        XCTAssertFalse(mentionsIdentifier("每筆提案以 citekey 或 doi 指名", "citekey"))
        XCTAssertFalse(mentionsIdentifier("該筆略過並在 skipped 具名", "skipped"))
        XCTAssertFalse(mentionsIdentifier("被截時 truncated 為 true", "truncated"))
        XCTAssertFalse(mentionsIdentifier("回新記錄的 id 與 hasJudgement", "id"))
        // 算：至少一邊是標點、括號、反引號、`＝`、`:`、`.`，或文字（行）的頭尾
        XCTAssertTrue(mentionsIdentifier("該筆略過並在 skipped（具名）", "skipped"))
        XCTAssertTrue(mentionsIdentifier("被截時 truncated＝true", "truncated"))
        XCTAssertTrue(mentionsIdentifier("回新記錄的 id／hasJudgement", "id"))
        XCTAssertTrue(mentionsIdentifier("逐筆具名在 category；index（提案序）、additions 補了什麼", "index"))
        XCTAssertTrue(mentionsIdentifier("回 digest；冪等", "digest"))
        XCTAssertTrue(mentionsIdentifier("indexEntryCreated:false", "indexEntryCreated"))
        XCTAssertTrue(mentionsIdentifier("（部分解析時原字串留在 fields，該筆帶 partial）", "partial"))
        XCTAssertTrue(mentionsIdentifier("`key` 直查", "key"))
        XCTAssertTrue(mentionsIdentifier("names.authorized", "names"))
        XCTAssertTrue(mentionsIdentifier("說明\ncitekey\n另一個說明", "citekey"), "換行是邊界：參數說明只有一個詞時就是那個詞")
        XCTAssertFalse(mentionsIdentifier("多個空白   index   之後", "index"), "跳過的是空白，不是字")
        // 同一個詞出現兩次：只要有一次在鍵名的位置就算
        XCTAssertTrue(mentionsIdentifier("以 citekey 或 doi 指名；回 citekey／type", "citekey"))
    }

    /// **別的名字的一段不算**（b26 F6 LOW 16）：`akashic.libraries`（store 的欄位路徑）不是在說回應有 `libraries`，`media-type`／`container-title`／
    /// `resolution-rejected` 不是在說 `type`／`title`／`rejected`。先前這三種都因為「點號／連字號是標點」而過關。
    /// 負控：拿掉 `mentionsIdentifier` 的 `partOfAnotherName`，這一支紅。
    func testAMentionInsideAnotherDottedOrHyphenatedNameDoesNotCount() {
        XCTAssertFalse(mentionsIdentifier("改 entry 的 akashic.libraries，指名的 work", "libraries"))
        XCTAssertFalse(mentionsIdentifier("設定／清除 entry 的 akashic.status（衍生層）", "status"))
        XCTAssertFalse(mentionsIdentifier("（container-title）", "title"))
        XCTAssertFalse(mentionsIdentifier("media-type", "type"))
        XCTAssertFalse(mentionsIdentifier("寫 resolution-rejected（entry 不動）", "rejected"))
        XCTAssertFalse(mentionsIdentifier("type-x", "type"), "連字號在鍵名後面接識別字也是別的名字")
        XCTAssertFalse(mentionsIdentifier("a.b.libraries", "libraries"))
        // 仍算：鍵在點號路徑的第一段、`]` 之後的點號、鍵名本身含連字號、一般的列表
        XCTAssertTrue(mentionsIdentifier("names.authorized", "names"))
        XCTAssertTrue(mentionsIdentifier("items[].index", "index"))
        XCTAssertTrue(mentionsIdentifier("（container-title）", "container-title"))
        XCTAssertTrue(mentionsIdentifier("回 libraries＝改後的清單", "libraries"))
        XCTAssertTrue(mentionsIdentifier("akashic.libraries、libraries（改後）", "libraries"), "同一個詞出現兩次：有一次在鍵名的位置就算")
    }

    /// 先前只靠別的字過關的鍵（b26 F6 LOW 16：三席量到 `akashic_libraries.libraries` 只靠 `akashic.libraries`、`akashic_tag.tags` 只靠參數說明的
    /// 「要加的 tags」、`akashic_resolve_venues.rejected` 只靠「留 rejected」這類講 verdict 的散文；實測多出 `akashic_set_status.status`，只靠
    /// `akashic.status`）。`status` 是回顯呼叫端剛給的值，具名豁免（`ToolPayloadKeyExemptions`；`testEveryExemptionIsLive` 守它仍是真的沒被說明提到）。
    ///
    /// **b29 V5 LOW 4、7、11**：b26 F6 的 `libraries（akashic.libraries）` 讓守衛滿足，卻是靠「改 entry 的 libraries」這句講**輸入**的散文——說的是
    /// 這一次改了什麼，不是回應有這個鍵；`tags`、`rejected` 當時以位元組預算為由沒有加字（整合後預算是 60,000，那個理由不再成立）。現在三個鍵都要出現在
    /// **工具描述本身的「回 …」子句裡**（`回` 到下一個 `。` 或 `；`）——那是讀的人也認得出「這是在列回應鍵」的寫法（`mentionsIdentifier` 的 doc 的補救）。
    /// 這仍是寫法的檢查，不是語意：它擋得住「只在輸入的散文裡提到」，擋不住「回 …」子句裡寫錯鍵的意思。
    /// 負控：把 `akashic_tag` 的「回 citekey、tags（改後清單）」拿掉，這一支紅。
    func testTheKeysThatOnlyPassedThroughOtherNamesAreDescribedInTheDescriptionItself() throws {
        let manifest = try loadManifest()
        for (tool, key) in [("akashic_libraries", "libraries"), ("akashic_tag", "tags"), ("akashic_resolve_venues", "rejected")] {
            let real = try XCTUnwrap(manifest[tool])
            XCTAssertTrue(PayloadObservations.shared.keysByTool[tool]?.contains(key) == true, "前提：\(tool) 的 payload 有 \(key)")
            XCTAssertTrue(mentionsIdentifier(real.text, key), "\(tool) 的描述（不含參數說明）要以鍵名的形式寫出 \(key)")
            XCTAssertTrue(Self.returnClauses(of: real.text).contains { mentionsIdentifier($0, key) },
                          "\(tool) 的描述要在「回 …」子句裡列出回應鍵 \(key)：\(Self.returnClauses(of: real.text))")
        }
    }

    /// 描述裡的「回 …」子句：每個 `回` 到下一個 `。` 或 `；`（不含）。
    static func returnClauses(of text: String) -> [String] {
        var out: [String] = []
        var i = text.startIndex
        while let r = text.range(of: "回", range: i..<text.endIndex) {
            let end = text[r.upperBound...].firstIndex { $0 == "。" || $0 == "；" } ?? text.endIndex
            out.append(String(text[r.upperBound..<end]))
            i = r.upperBound
        }
        return out
    }

    /// 只有鍵名形式的那一處被換成散文時守衛要紅，而**舊規則（只看識別字邊界）不會**——這就是收緊的意義。
    /// 從真的說明裡取 `akashic_enrich` 的 `index（提案序）`，換成 `以 index 是提案序`。
    func testGuardGoesRedWhenTheOnlyMentionBecomesRunningProse() throws {
        let manifest = try loadManifest()
        let observed = PayloadObservations.shared
        let tool = "akashic_enrich", key = "index", path = NestedPayloadPath.array("items")
        let real = try XCTUnwrap(manifest[tool])
        XCTAssertTrue(observed.nestedKeysByTool[tool]?[path]?.contains(key) == true, "前提：items[] 有 \(key)")
        let anchor = "index（提案序）"
        XCTAssertTrue(real.text.contains(anchor), "前提：說明用鍵名的形式寫了 \(key)")
        let clean = ToolPayloadKeyCheck.undescribedNested(observed: observed.nestedKeysByTool, manifest: manifest,
                                                          exemptions: ToolPayloadKeyExemptions.keys)
        XCTAssertNil(clean[tool]?.first { $0 == "items[].index" }, "前提：未改動時不報")

        var broken = manifest
        broken[tool] = ToolManifest.Tool(name: tool, text: real.text.replacingOccurrences(of: anchor, with: "以 index 是提案序"),
                                         parameterText: real.parameterText)
        // 舊規則：識別字邊界就算——散文裡的 `index` 與 `indexRebuilt 說 index 有沒有重建` 那一處都滿足它
        func looselyMentions(_ text: String, _ key: String) -> Bool {
            var search = text.startIndex..<text.endIndex
            while let r = text.range(of: key, options: .literal, range: search) {
                func isIdent(_ c: Character) -> Bool { c == "_" || (c.isASCII && (c.isLetter || c.isNumber)) }
                let before = r.lowerBound == text.startIndex ? nil : text[text.index(before: r.lowerBound)]
                let after = r.upperBound == text.endIndex ? nil : text[r.upperBound]
                if !(before.map(isIdent) ?? false) && !(after.map(isIdent) ?? false) { return true }
                search = r.upperBound..<text.endIndex
            }
            return false
        }
        XCTAssertTrue(looselyMentions(try XCTUnwrap(broken[tool]).searchable, key), "舊規則看不出差別")
        let gaps = ToolPayloadKeyCheck.undescribedNested(observed: observed.nestedKeysByTool, manifest: broken,
                                                         exemptions: ToolPayloadKeyExemptions.keys)
        XCTAssertEqual(gaps[tool], ["items[].index"], "新規則必須報出它：\(gaps[tool] ?? [])")
    }

    /// #700 點名、R1 verify 發現先前**沒有情境產生**的四個鍵（說明拿掉它們，守衛照綠）：每一個都要真的被產生。這是一張**點名的清單**，不是
    /// 「情境產生的鍵都算」——少一個情境（或情境退成不產生它）就紅。預算理由（「只剩 4 bytes」）在 03a8e729 之後已不成立。
    static let namedKeys: [(tool: String, path: NestedPayloadPath, key: String, how: String)] = [
        ("akashic_enrich", .array("items"), "provenanceNotWritten", "實跑、來源齊備、那一筆的目的檔寫不進去（immutable）"),
        ("akashic_enrich", .array("items"), "partial", "多值 isbn 欄位：一個解得出、一個解不出"),
        ("akashic_person", .object("person"), "unknownFields", "帶較新 schema 欄位的 person"),
        ("akashic_person", .object("person"), "orcid", "有 ORCID 的 person"),
    ]

    func testTheKeysTheIssueNamedAreProducedByScenarios() throws {
        let observed = PayloadObservations.shared
        for n in Self.namedKeys {
            XCTAssertTrue(observed.nestedKeysByTool[n.tool]?[n.path]?.contains(n.key) == true,
                          "\(n.tool) \(n.path).\(n.key) 沒有任何情境產生（\(n.how)）——守衛守不到它")
        }
        XCTAssertTrue(observed.keysByTool["akashic_enrich"]?.contains("writeFailed") == true, "寫入失敗的情境也要帶出頂層的 writeFailed")
    }

    /// 四個點名的鍵：說明拿掉任何一個，巢狀的判定都要報出它（負控）。
    func testGuardGoesRedWhenANamedKeyIsDroppedFromTheDescription() throws {
        let manifest = try loadManifest()
        let observed = PayloadObservations.shared
        let clean = ToolPayloadKeyCheck.undescribedNested(observed: observed.nestedKeysByTool, manifest: manifest,
                                                          exemptions: ToolPayloadKeyExemptions.keys)
        XCTAssertNil(clean["akashic_enrich"], "前提：未改動時不報：\(clean["akashic_enrich"] ?? [])")
        XCTAssertNil(clean["akashic_person"], "前提：未改動時不報：\(clean["akashic_person"] ?? [])")
        for n in Self.namedKeys {
            let real = try XCTUnwrap(manifest[n.tool])
            XCTAssertTrue(mentionsIdentifier(real.searchable, n.key), "前提：說明提到 \(n.key)")
            var broken = manifest
            broken[n.tool] = ToolManifest.Tool(name: n.tool, text: real.text.replacingOccurrences(of: n.key, with: "XXXXX"),
                                               parameterText: real.parameterText.replacingOccurrences(of: n.key, with: "XXXXX"))
            let gaps = ToolPayloadKeyCheck.undescribedNested(observed: observed.nestedKeysByTool, manifest: broken,
                                                             exemptions: ToolPayloadKeyExemptions.keys)
            XCTAssertEqual(gaps[n.tool], [n.path.qualified(n.key)], "說明拿掉 \(n.key) 之後必須報出它")
        }
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
