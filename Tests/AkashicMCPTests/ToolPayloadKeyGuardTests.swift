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
            } catch {
                out.problems.append("\(s.tool)／\(s.leg)：擲錯——\(error)")
            }
        }
        PayloadWorld.removeTemplate()
        return out
    }()
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
}

/// #672：每個工具的說明都要跟得上它的回應鍵。設計與範圍見 `ToolManifest` 的檔頭。
///
/// **這一組測試沒有涵蓋的腿**（守衛的誠實邊界）：
/// - 只在特定 store 狀態出現的鍵：`akashic_doctor` 的 `layoutResidue`、`sourcesAuditError`；`akashic_import_zotero` 的
///   `authorsPreserved`、`quarantineConflicts`、`writeFailed`；各寫入工具在 I/O 失敗時的 `writeFailed`、`skipped` 等。
/// - `akashic_files` 的 `use`（切換 session 的 active store，需要 registry）。
/// - 錯誤回應（`isError`）：那是訊息文字，不是 payload。
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
        let gaps = ToolPayloadKeyCheck.undescribed(observed: observed.keysByTool, manifest: manifest,
                                                   exemptions: ToolPayloadKeyExemptions.keys)
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
            for (key, why) in exempt.sorted(by: { $0.key < $1.key }) {
                XCTAssertTrue(observed.keysByTool[tool]?.contains(key) == true,
                              "\(tool).\(key) 豁免了，但情境的 payload 裡沒有這個鍵（鍵改名或情境漂移）——刪掉這一列：\(why.why)")
                if let m = manifest[tool] {
                    XCTAssertFalse(mentionsIdentifier(m.searchable, key),
                                   "\(tool).\(key) 已經寫進說明了，豁免過期——刪掉這一列")
                }
                XCTAssertFalse(why.why.trimmingCharacters(in: .whitespaces).isEmpty, "\(tool).\(key) 的豁免沒有理由")
            }
        }
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
