import XCTest
@testable import AkashicMCPKit

/// #700：每條寫入腿都要有 payload 情境——擋住「既有工具長出新腿而沒有情境」（#675 的 `edit_name_segment` 那一類：
/// 描述守衛只看情境產生的鍵，沒有情境的腿，它的回應鍵就沒有人看）。設計見 `ToolPayloadLegs` 的檔頭。
///
/// **誠實邊界**：
/// - 情境宣告的參數（`PayloadScenario.params`）是宣告：情境直接呼叫 `AkashicService`、不經 MCP 的引數解碼，
///   這裡驗得到參數名在真 binary 的 schema 裡、驗不到情境真的傳了它。
/// - 覆蓋的單位是參數，不是參數的每一個值：`akashic_files` 的 `action` 有 list 的情境就算有情境，`use` 仍然沒有
///   （值層只在 `ToolPayloadLegs.commands` 點名的地方檢查，例如 `library add` → `action=add`）。
/// - 裁決表讀原始碼（`WriteGateRulingSource`）；它與編譯後的表一致由 AkashicCLITests 釘住。
final class ToolPayloadLegTests: XCTestCase {
    private static let manifest: Result<[String: ToolManifest.Tool], Error> = Result { try ToolManifest.load() }
    private func loadManifest() throws -> [String: ToolManifest.Tool] { try Self.manifest.get() }

    /// 工具 → 情境宣告的參數（原樣，含 `=值`）。
    private static func declared(_ scenarios: [PayloadScenario] = ToolPayloadScenarios.all) -> [String: Set<String>] {
        scenarios.reduce(into: [:]) { $0[$1.tool, default: []].formUnion($1.params) }
    }

    private static func base(_ p: String) -> String {
        p.firstIndex(of: "=").map { String(p[..<$0]) } ?? p
    }

    // MARK: - MCP 工具的每一個參數

    /// 判定本體（純函式，負控直接對它餵改過的輸入）：工具 → 問題。
    static func parameterGaps(manifest: [String: ToolManifest.Tool], declared: [String: Set<String>],
                              unexercised: [String: [String: String]]) -> [String: [String]] {
        var out: [String: [String]] = [:]
        for (tool, m) in manifest {
            let names = Set((declared[tool] ?? []).map(base))
            let rows = unexercised[tool] ?? [:]
            var problems: [String] = []
            for p in m.parameters.subtracting(names).subtracting(rows.keys).sorted() {
                problems.append("參數 \(p) 沒有情境宣告它，也沒有在 ToolPayloadLegs.unexercised 寫理由")
            }
            for p in names.subtracting(m.parameters).sorted() {
                problems.append("情境宣告了 \(p)，但 tools/list 的 schema 沒有這個參數（改名了，或打錯）")
            }
            for p in Set(rows.keys).intersection(names).sorted() {
                problems.append("\(p) 已經有情境宣告，unexercised 的那一列過期——刪掉")
            }
            for p in Set(rows.keys).subtracting(m.parameters).sorted() {
                problems.append("unexercised 列了 \(p)，但 schema 沒有這個參數——刪掉那一列")
            }
            for (p, why) in rows where why.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                problems.append("unexercised 的 \(p) 沒有理由")
            }
            if !problems.isEmpty { out[tool] = problems }
        }
        for tool in Set(unexercised.keys).subtracting(manifest.keys) { out[tool, default: []].append("unexercised 列了不存在的工具") }
        return out
    }

    func testEveryToolParameterIsExercisedOrNamed() throws {
        let manifest = try loadManifest()
        let total = manifest.values.map(\.parameters.count).reduce(0, +)
        XCTAssertGreaterThan(total, 100, "tools/list 只抽出 \(total) 個參數——列舉壞了（空掃描不是通過）")
        let gaps = Self.parameterGaps(manifest: manifest, declared: Self.declared(), unexercised: ToolPayloadLegs.unexercised)
        XCTAssertTrue(gaps.isEmpty,
                      "MCP 參數與情境對不上——新的參數（新腿）要同時加一個會走它的情境並在 params 宣告，或在 unexercised 寫理由：\n"
                      + gaps.sorted { $0.key < $1.key }.map { "\($0.key)：\($0.value.joined(separator: "；"))" }.joined(separator: "\n"))
        let covered = manifest.map { tool, m in m.parameters.intersection(Set((Self.declared()[tool] ?? []).map(Self.base))).count }.reduce(0, +)
        print("ToolPayloadLegs：MCP 參數 \(total)｜有情境 \(covered)｜寫理由 \(ToolPayloadLegs.unexercised.values.map(\.count).reduce(0, +))")
    }

    // MARK: - CLI 裁決表的每一條寫入腿

    /// 判定本體：裁決表的每一個寫入命令／寫入腿 → 問題清單（空＝全部有對應、對到的參數有情境）。
    static func rulingGaps(source: WriteGateRulingSource, manifest: [String: ToolManifest.Tool], scenarios: [PayloadScenario],
                           commands: [String: ToolPayloadLegs.MCPLeg], legs: [String: [String: ToolPayloadLegs.MCPLeg]]) -> [String] {
        var problems: [String] = []
        let declared = Self.declared(scenarios)
        let scenarioTools = Set(scenarios.map(\.tool))
        func check(_ name: String, _ leg: ToolPayloadLegs.MCPLeg) {
            switch leg {
            case .cliOnly(let why):
                if why.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { problems.append("\(name)：cliOnly 沒有寫理由") }
            case .tool(let tool, let parameter):
                guard let m = manifest[tool] else { return problems.append("\(name)：對到的 MCP 工具 \(tool) 不存在") }
                guard let parameter else {
                    if !scenarioTools.contains(tool) { problems.append("\(name)：\(tool) 沒有任何情境") }
                    return
                }
                if !m.parameters.contains(base(parameter)) {
                    problems.append("\(name)：\(tool) 的 schema 沒有參數 \(base(parameter))——這條腿在 MCP 面到不了；"
                                    + "若它只有 CLI，在 ToolPayloadLegs 寫一列 cliOnly 並說明為什麼")
                } else if !(declared[tool] ?? []).contains(parameter) {
                    problems.append("\(name)：\(tool) 沒有情境宣告 \(parameter)（只在 unexercised 寫理由不算——寫入腿要有 payload 情境）")
                }
            }
        }
        for (command, kind) in source.commands.sorted(by: { $0.key < $1.key }) where kind != .readOnly {
            if kind == .perLeg {
                guard let rulings = source.legs[command] else { problems.append("\(command)：標了逐腿、legRulings 卻沒有它"); continue }
                for (flag, legKind) in rulings.sorted(by: { $0.key < $1.key }) where legKind != .readOnly {
                    if let row = legs[command]?[flag] { check("\(command) \(flag)", row); continue }
                    guard let tool = ToolPayloadLegs.mechanicalTool(command) else {
                        problems.append("\(command) \(flag)：命令沒有機械對應的 MCP 工具，ToolPayloadLegs.legs 也沒有這一格"); continue
                    }
                    check("\(command) \(flag)", .tool(tool, parameter: ToolPayloadLegs.mechanicalParameter(flag)))
                }
                continue
            }
            if let row = commands[command] { check(command, row); continue }
            guard let tool = ToolPayloadLegs.mechanicalTool(command), manifest[tool] != nil else {
                problems.append("\(command)：會寫 store，但沒有同名的 MCP 工具，ToolPayloadLegs.commands 也沒有這一格——"
                                + "寫出它對到哪個工具（與參數值），或 cliOnly 並說明為什麼")
                continue
            }
            check(command, .tool(tool, parameter: nil))
        }
        let writing = Set(source.commands.filter { $0.value != .readOnly && $0.value != .perLeg }.keys)
        for stale in Set(commands.keys).subtracting(writing).sorted() {
            problems.append("ToolPayloadLegs.commands 列了 \(stale)，但裁決表裡它不是會寫 store 的命令——刪掉那一列")
        }
        for (command, flags) in legs {
            for flag in flags.keys where !(source.legs[command]?[flag].map { $0 != .readOnly } ?? false) {
                problems.append("ToolPayloadLegs.legs 列了 \(command) \(flag)，但它不是裁決表裡的寫入腿——刪掉那一列")
            }
        }
        return problems
    }

    func testEveryWriteLegInTheRulingTableHasAPayloadScenario() throws {
        let manifest = try loadManifest()
        let source = try WriteGateRulingSource.load()
        XCTAssertEqual(source.unparsed, [], "WriteGateRulings.swift 有讀不出來的行——表的寫法變了，讀法要跟著改")
        XCTAssertGreaterThan(source.commands.count, 40, "只讀出 \(source.commands.count) 個命令——讀法壞了")
        let perLeg = Set(source.commands.filter { $0.value == .perLeg }.keys)
        XCTAssertEqual(perLeg, ["resolve-organizations", "resolve-people", "resolve-venues"], "逐腿命令讀出來不是那三個——讀法壞了")
        XCTAssertEqual(Set(source.legs.keys), perLeg)
        for (cmd, legs) in source.legs { XCTAssertGreaterThan(legs.count, 3, "\(cmd) 只讀出 \(legs.keys.sorted())") }

        let problems = Self.rulingGaps(source: source, manifest: manifest, scenarios: ToolPayloadScenarios.all,
                                       commands: ToolPayloadLegs.commands, legs: ToolPayloadLegs.legs)
        XCTAssertEqual(problems, [], "CLI 裁決表的寫入腿在 MCP 面沒有 payload 情境：\n" + problems.joined(separator: "\n"))

        let writing = source.commands.filter { $0.value != .readOnly && $0.value != .perLeg }.count
        let writeLegs = source.legs.values.flatMap(\.values).filter { $0 != .readOnly }.count
        let cliOnly = ToolPayloadLegs.commands.values.filter { if case .cliOnly = $0 { return true } else { return false } }.count
        print("ToolPayloadLegs：裁決表寫入命令 \(writing)（只有 CLI \(cliOnly)）｜逐腿命令的寫入腿 \(writeLegs)｜問題 \(problems.count)")
    }

    // MARK: - 負控

    /// 刪掉一條寫入腿的情境 → 兩個判定都紅（`drop_venue` 只有一個情境宣告它）。
    func testDeletingTheOnlyScenarioOfAWriteLegGoesRed() throws {
        let manifest = try loadManifest()
        let source = try WriteGateRulingSource.load()
        let kept = ToolPayloadScenarios.all.filter { !($0.tool == "akashic_resolve_venues" && $0.params.contains("drop_venue")) }
        XCTAssertEqual(ToolPayloadScenarios.all.count - kept.count, 1, "前提：drop_venue 恰有一個情境")
        let gaps = Self.parameterGaps(manifest: manifest, declared: Self.declared(kept), unexercised: ToolPayloadLegs.unexercised)
        XCTAssertTrue(gaps["akashic_resolve_venues"]?.contains { $0.contains("drop_venue") } == true, "\(gaps)")
        let problems = Self.rulingGaps(source: source, manifest: manifest, scenarios: kept,
                                       commands: ToolPayloadLegs.commands, legs: ToolPayloadLegs.legs)
        XCTAssertTrue(problems.contains { $0.hasPrefix("resolve-venues --drop-venue") }, "\(problems)")
    }

    /// 裁決表多一條沒有情境的腿 → 紅。兩種：MCP 面沒有這個參數（機械對應不到）；對到的參數只在 unexercised 寫了理由。
    func testAWriteLegWithoutAScenarioInTheRulingTableGoesRed() throws {
        let manifest = try loadManifest()
        var source = try WriteGateRulingSource.load()
        source.legs["resolve-people"]?["--fake-leg"] = .notGated
        source.legs["resolve-people"]?["--confirm-tiers"] = .gated   // 對到 confirm_tiers：只在 unexercised 有理由、沒有情境
        let problems = Self.rulingGaps(source: source, manifest: manifest, scenarios: ToolPayloadScenarios.all,
                                       commands: ToolPayloadLegs.commands, legs: ToolPayloadLegs.legs)
        XCTAssertTrue(problems.contains { $0.hasPrefix("resolve-people --fake-leg") && $0.contains("schema 沒有參數 fake_leg") }, "\(problems)")
        XCTAssertTrue(problems.contains { $0.hasPrefix("resolve-people --confirm-tiers") && $0.contains("沒有情境宣告") }, "\(problems)")

        var withCommand = try WriteGateRulingSource.load()
        withCommand.commands["frobnicate"] = .notGated   // 會寫 store、沒有同名工具、沒有一格
        let more = Self.rulingGaps(source: withCommand, manifest: manifest, scenarios: ToolPayloadScenarios.all,
                                   commands: ToolPayloadLegs.commands, legs: ToolPayloadLegs.legs)
        XCTAssertTrue(more.contains { $0.hasPrefix("frobnicate：") }, "\(more)")
    }

    /// 既有工具長出新參數（#675 的形狀）→ 紅：在 schema 加一個 `akashic_update_venue` 的參數而不加情境。
    func testANewParameterOnAnExistingToolGoesRed() throws {
        var manifest = try loadManifest()
        let tool = try XCTUnwrap(manifest["akashic_update_venue"])
        var grown = tool
        grown.parameters.insert("brand_new_leg")
        manifest["akashic_update_venue"] = grown
        let gaps = Self.parameterGaps(manifest: manifest, declared: Self.declared(), unexercised: ToolPayloadLegs.unexercised)
        XCTAssertEqual(gaps["akashic_update_venue"], ["參數 brand_new_leg 沒有情境宣告它，也沒有在 ToolPayloadLegs.unexercised 寫理由"])
    }

    /// 讀法本身：一格一行、兩張表各自收尾；讀不出來的行要報出來，不是略過。
    func testTheRulingSourceParserReportsWhatItCannotRead() {
        let text = """
            static let commandRulings: [String: WriteGateRuling] = [
                "a": .gated,   // 註解
                "b c": .notGated("理由：\\"x\\"" + suffix),
                "d": someHelper(),
                "resolve-x": .perLeg,
            ]
            static let legRulings: [String: [String: WriteGateRuling]] = [
                "resolve-x": [
                    "--apply": .gated,
                    "--rows": .readOnly("旋鈕"),
                    "--odd": .perLeg,
                ],
            ]
        """
        let s = WriteGateRulingSource.parse(text)
        XCTAssertEqual(s.commands, ["a": .gated, "b c": .notGated, "resolve-x": .perLeg])
        XCTAssertEqual(s.legs, ["resolve-x": ["--apply": .gated, "--rows": .readOnly]])
        XCTAssertEqual(s.unparsed.count, 2, "\(s.unparsed)")
        XCTAssertEqual(ToolPayloadLegs.mechanicalParameter("--drop-venue"), "drop_venue")
        XCTAssertEqual(ToolPayloadLegs.mechanicalTool("update-venue"), "akashic_update_venue")
        XCTAssertNil(ToolPayloadLegs.mechanicalTool("library add"))
    }
}
