import XCTest
import Foundation
import ArgumentParser
@testable import AkashicCore
@testable import AkashicStoreIO
@testable import akashic

/// 目標確認閘的裁決表（#658）：CLI 的每一個葉命令、六個逐腿命令的每一條腿，都要在
/// `DestructiveTargetGate.commandRulings`／`legRulings` 有一格。
///
/// **列舉走執行期的命令樹**（ArgumentParser 的 dump-help，與 `--experimental-dump-help` 同一份 JSON），
/// 不是文字掃描——`DestructiveTargetGateTests` 的前一代稽核只認布林 `--apply`／`--reject` 的宣告寫法，
/// 預設就寫的命令與逐 id 的寫入腿長出來時它看不到（#653 R1 verify requirements 席）。
///
/// 逐腿的裁決另用真 binary 驗：`.gated` 的腿在未指名目標 store 時真的被閘擋、其餘的沒有。
final class WriteGateRulingsTests: XCTestCase {

    // MARK: - 命令樹

    private static func arguments(of node: [String: Any]) -> [[String: Any]] {
        (node["arguments"] as? [[String: Any]]) ?? []
    }

    /// 一個節點的 `--長名`（只看 option／flag 的主名；positional 不算）。
    private static func longNames(_ node: [String: Any]) -> Set<String> {
        Set(arguments(of: node).compactMap { arg -> String? in
            guard (arg["kind"] as? String) != "positional",
                  let pn = arg["preferredName"] as? [String: Any],
                  pn["kind"] as? String == "long", let name = pn["name"] as? String else { return nil }
            return "--" + name
        })
    }

    /// 葉命令的路徑（巢狀以空白串接）→ 那個節點。根的 `help` 是 ArgumentParser 注入的，不是本 CLI 的命令。
    private static func leaves() throws -> [String: [String: Any]] {
        let obj = try JSONSerialization.jsonObject(with: Data(AkashicCLI._dumpHelp().utf8)) as? [String: Any]
        let root = try XCTUnwrap(obj?["command"] as? [String: Any], "dump-help 沒有 command")
        var out: [String: [String: Any]] = [:]
        func walk(_ node: [String: Any], _ path: [String]) {
            let subs = (node["subcommands"] as? [[String: Any]]) ?? []
            if subs.isEmpty {
                if !path.isEmpty { out[path.joined(separator: " ")] = node }
                return
            }
            for s in subs {
                guard let name = s["commandName"] as? String else { continue }
                if path.isEmpty && name == "help" { continue }
                walk(s, path + [name])
            }
        }
        walk(root, [])
        return out
    }

    /// 橫切選項（`LibraryOptions` 的 `--library`／`--yes`）與 ArgumentParser 自帶的 `--help`——不是任何一條腿。
    /// 取自 `LibraryOptions` 自己的 dump，不寫死：它長出新的橫切選項時自動排除（那一族由 `mcp-cli-parity` 的橫切表管）。
    private static func crossCutting() throws -> Set<String> {
        let obj = try JSONSerialization.jsonObject(with: Data(LibraryOptions._dumpHelp().utf8)) as? [String: Any]
        let node = try XCTUnwrap(obj?["command"] as? [String: Any])
        return longNames(node).union(["--help"])
    }

    // MARK: - 表與命令樹雙向相等

    func testEveryCLICommandHasExactlyOneRuling() throws {
        let live = Set(try Self.leaves().keys)
        let ruled = Set(DestructiveTargetGate.commandRulings.keys)
        // 空掃描不是通過（zero-instance-guards 第 3 列的形）：命令樹抽不出來時兩邊都空也會「相等」
        XCTAssertGreaterThan(live.count, 40, "dump-help 只抽出 \(live.count) 個葉命令——列舉壞了：\(live.sorted())")
        XCTAssertEqual(live.subtracting(ruled).sorted(), [],
                       "CLI 有這些命令而裁決表沒有——新增的命令要在 `commandRulings` 加一格：過閘、不閘（寫理由）或只讀（#658）")
        XCTAssertEqual(ruled.subtracting(live).sorted(), [],
                       "裁決表有這些命令而 CLI 已經沒有——退場的命令要從表拿掉")
        // `zero-instance-guards` 的量測行（grep 'WriteGateRulings：'）——`akashic --experimental-dump-help` 算不出這個數：
        // CLI 頂層對輸出逐行截 400、總行數截 200，JSON 被截斷
        let kinds = Dictionary(grouping: DestructiveTargetGate.commandRulings.values) { r -> String in
            switch r { case .gated: return "過閘"; case .notGated: return "不閘"; case .readOnly: return "不寫"; case .perLeg: return "逐腿" }
        }.mapValues(\.count)
        print("WriteGateRulings：CLI 葉命令 \(live.count)｜裁決表 \(ruled.count)｜只在 CLI \(live.subtracting(ruled).sorted())"
              + "｜只在表 \(ruled.subtracting(live).sorted())｜"
              + kinds.sorted { $0.key < $1.key }.map { "\($0.key) \($0.value)" }.joined(separator: "／"))
    }

    func testEveryLegOfPerLegCommandsHasARuling() throws {
        let leaves = try Self.leaves()
        let cross = try Self.crossCutting()
        XCTAssertTrue(cross.contains("--library") && cross.contains("--yes"), "橫切選項抽不出來：\(cross.sorted())")
        let perLeg = DestructiveTargetGate.commandRulings.filter { $0.value == .perLeg }.keys.sorted()
        XCTAssertEqual(perLeg, ["resolve-organizations", "resolve-people", "resolve-venues", "update-organization", "update-person", "update-venue"],
                       "逐腿裁決的命令是封閉的六個（#658 的三個＋#564 使用者 2026-10-05 裁決第 4 點的三個）；要加第七個就改這裡並寫出理由")
        XCTAssertEqual(Set(DestructiveTargetGate.legRulings.keys), Set(perLeg),
                       "legRulings 的命令與 commandRulings 標 .perLeg 的命令要一致")
        for cmd in perLeg {
            let node = try XCTUnwrap(leaves[cmd], "\(cmd) 不在命令樹裡")
            let live = Self.longNames(node).subtracting(cross)
            let ruled = Set((DestructiveTargetGate.legRulings[cmd] ?? [:]).keys)
            XCTAssertGreaterThan(live.count, 3, "\(cmd) 只抽出 \(live.sorted())——列舉壞了")
            XCTAssertEqual(live.subtracting(ruled).sorted(), [],
                           "\(cmd) 有這些旗標而 legRulings 沒有——新增的腿要加一格：過閘、不閘（寫理由）或不自己寫入（#658）")
            XCTAssertEqual(ruled.subtracting(live).sorted(), [],
                           "legRulings 的 \(cmd) 有這些旗標而命令已經沒有")
            print("WriteGateRulings：\(cmd) 旗標 \(live.count)｜裁決 \(ruled.count)｜差異 \(live.symmetricDifference(ruled).sorted())")
            for (leg, ruling) in DestructiveTargetGate.legRulings[cmd] ?? [:] {
                XCTAssertNotEqual(ruling, .perLeg, "\(cmd) \(leg)：.perLeg 只用在命令層")
            }
        }
    }

    func testEveryRulingThatIsNotAGateCarriesItsOwnReason() {
        func reason(_ r: WriteGateRuling) -> String? {
            switch r {
            case .notGated(let s), .readOnly(let s): return s
            case .gated, .perLeg: return nil
            }
        }
        var rows: [(String, WriteGateRuling)] = DestructiveTargetGate.commandRulings.map { ($0.key, $0.value) }
        for (cmd, legs) in DestructiveTargetGate.legRulings { rows += legs.map { ("\(cmd) \($0.key)", $0.value) } }
        for (name, r) in rows {
            if let s = reason(r) {
                XCTAssertFalse(s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, "\(name) 的裁決沒有寫理由")
            }
        }
    }

    /// `destructiveCommands` 由表現算：命令本身 `.gated`，或至少一條腿 `.gated`。
    func testDestructiveCommandsIsDerivedFromTheRulings() {
        var expected = Set(DestructiveTargetGate.commandRulings.filter { $0.value == .gated }.keys)
        for (cmd, legs) in DestructiveTargetGate.legRulings where legs.values.contains(.gated) { expected.insert(cmd) }
        XCTAssertEqual(DestructiveTargetGate.destructiveCommands, expected)
        // #658 的兩格
        XCTAssertTrue(DestructiveTargetGate.destructiveCommands.contains("import-zotero"))
        XCTAssertEqual(DestructiveTargetGate.legRulings["resolve-people"]?["--drop-author"], .gated)
    }

    /// 閘的呼叫點與表一致：原始碼裡每一個 `assertDestructiveTargetNamed` 的命令名都在 `destructiveCommands`，反之亦然。
    /// 表說過閘而程式沒呼叫＝沒有閘；程式呼叫了而表說不閘＝表在說謊。
    func testGateCallSitesMatchTheRulings() throws {
        var dir = URL(fileURLWithPath: #filePath)
        for _ in 0..<3 { dir.deleteLastPathComponent() }
        let src = dir.appendingPathComponent("Sources/akashic")
        let files = try FileManager.default.contentsOfDirectory(at: src, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "swift" }
        XCTAssertFalse(files.isEmpty)
        let re = try NSRegularExpression(pattern: #"assertDestructiveTargetNamed\(\s*"([^"]+)""#)
        var called = Set<String>()
        for f in files {
            let s = try String(contentsOf: f, encoding: .utf8)
            let ns = s as NSString
            for m in re.matches(in: s, range: NSRange(location: 0, length: ns.length)) {
                called.insert(ns.substring(with: m.range(at: 1)))
            }
        }
        XCTAssertGreaterThan(called.count, 10, "只找到 \(called.sorted()) 個呼叫點——掃描壞了")
        XCTAssertEqual(called.subtracting(DestructiveTargetGate.destructiveCommands).sorted(), [],
                       "這些命令呼叫了閘，而裁決表說它們不閘")
        XCTAssertEqual(DestructiveTargetGate.destructiveCommands.subtracting(called).sorted(), [],
                       "裁決表說這些命令過閘，而原始碼沒有呼叫閘")
    }

    /// **表一格一行、以字面值寫成**（#700）：原始碼裡每一行 `"名字": .裁決` 與編譯後的兩張表（多重集合）完全一致。
    ///
    /// `ToolPayloadLegTests`（AkashicMCPTests）以原始碼讀這張表——那個 target 不能 import `akashic` 執行檔模組——並要求
    /// 每條寫入腿都有 payload 情境。這條測試保證它讀到的就是編譯後的表：若有人把某一格改成由函式或另一個字典合成，
    /// 編譯後的表有它、逐行讀不到它，這裡紅。
    func testTheTableIsWrittenOneEntryPerLine() throws {
        var dir = URL(fileURLWithPath: #filePath)
        for _ in 0..<3 { dir.deleteLastPathComponent() }
        let text = try String(contentsOf: dir.appendingPathComponent("Sources/akashic/WriteGateRulings.swift"), encoding: .utf8)
        let re = try NSRegularExpression(pattern: #"^\s*"([^"]+)"\s*:\s*\.(gated|notGated|readOnly|perLeg)\b"#)
        var written: [String: Int] = [:]
        for line in text.components(separatedBy: .newlines) {
            let ns = line as NSString
            guard let m = re.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)) else { continue }
            written["\(ns.substring(with: m.range(at: 1))) \(ns.substring(with: m.range(at: 2)))", default: 0] += 1
        }
        func kind(_ r: WriteGateRuling) -> String {
            switch r { case .gated: return "gated"; case .notGated: return "notGated"; case .readOnly: return "readOnly"; case .perLeg: return "perLeg" }
        }
        var compiled: [String: Int] = [:]
        for (name, r) in DestructiveTargetGate.commandRulings { compiled["\(name) \(kind(r))", default: 0] += 1 }
        for legs in DestructiveTargetGate.legRulings.values {
            for (flag, r) in legs { compiled["\(flag) \(kind(r))", default: 0] += 1 }
        }
        XCTAssertGreaterThan(written.values.reduce(0, +), 60, "逐行只讀出 \(written.count) 格——讀法壞了")
        XCTAssertEqual(written, compiled,
                       "WriteGateRulings.swift 逐行讀出來的格子與編譯後的表不一致——每一格要寫成一行 `\"名字\": .裁決`，"
                       + "ToolPayloadLegTests 靠這個讀法要求每條寫入腿都有 payload 情境（#700）")
    }

    // MARK: - 逐腿的裁決對真 binary 成立

    private var root: URL!
    private var home: URL!

    override func setUpWithError() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("akashic-gate-rulings-\(UUID().uuidString)")
        root = base.appendingPathComponent("store")
        home = base.appendingPathComponent("home")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        try LibraryStore(root: root, key: nil, environment: [:]).ensureLayout()
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root.deletingLastPathComponent())
    }

    /// 目標經 `AKASHIC_LIBRARY` 解析到 scratch store——沒有 `--library`、也沒有 `--yes`，正是閘要擋的形狀；
    /// registry 住在 scratch 的 `AKASHIC_HOME`（`HOME` 不算數）。
    private var unnamedEnv: [String: String] {
        ["AKASHIC_LIBRARY": root.path, "AKASHIC_HOME": home.path, "HOME": home.path]
    }

    private static let digest = "sha256:" + String(repeating: "0", count: 64)

    /// 每一條腿一個會走到那條腿的 argv。與 `legRulings` 的鍵比對——新腿沒有樣本也會紅。
    private static let samples: [String: [String: [String]]] = [
        "resolve-people": [
            "--apply": ["--apply"],
            "--drop-author": ["--drop-author", "x2020y:No authorship indicated=不是作者"],
            "--reject": ["--reject", "x2020y:0:p"],
            "--refute": ["--refute", "x2020y:0:p=r"],
            "--undecided": ["--undecided", "x2020y:0:p=r"],
            "--judge": ["--judge", "x2020y:0:p=r"],
            "--attribute-org": ["--attribute-org", "x2020y:0:o=r"],
            "--split-author": ["--split-author", "x2020y:0:&=r"],
            "--un-split": ["--un-split", "x2020y:A & B"],
            "--citekey": ["--citekey", "x2020y"],
            "--person": ["--person", "p"],
            "--tier": ["--tier", "exact"],
            "--rests-on": ["--rests-on", digest],
            "--rows": ["--rows", "5"],
        ],
        "resolve-venues": [
            "--apply": ["--apply", "x2020y:0"],
            "--reject": ["--reject", "x2020y:0"],
            "--repoint": ["--repoint", "x2020y:0:v"],
            "--demote": ["--demote", "x2020y:0"],
            "--undecided": ["--undecided", "x2020y:0:v=r"],
            "--drop-venue": ["--drop-venue", "x2020y:0=r"],
            "--rests-on": ["--rests-on", digest],
        ],
        // #564 使用者 2026-10-05 裁決第 4 點：--remove-name 過閘、其餘腿不閘
        "update-person": [
            "--remove-name": ["--key", "p", "--remove-name", "X=r"],
            "--fields": ["--key", "p", "--fields", #"{"note":"x"}"#],
            "--judgement": ["--key", "p", "--fields", "{}", "--judgement", "r"],
            "--rests-on": ["--key", "p", "--fields", "{}", "--rests-on", digest],
            "--dry-run": ["--key", "p", "--fields", "{}", "--dry-run"],
            "--key": ["--key", "p", "--fields", "{}"],
        ],
        // #564 使用者 2026-10-05 裁決第 4 點：三條移除腿過閘（--edit-name-segment 用帶 remove 的樣本；只有 set 的另一條測試）
        "update-venue": [
            "--remove-issn": ["v", "--remove-issn", "0317-8471=r"],
            "--remove-reference": ["v", "--remove-reference", #"[{"field":"issn","value":"0317-8471","reason":"r"}]"#],
            "--edit-name-segment": ["v", "--edit-name-segment", #"[{"name":"X","remove":true,"reason":"r"}]"#],
            "--add-name": ["v", "--add-name", "X"],
            "--add-issn": ["v", "--add-issn", "0317-8471"],
            "--add-variant": ["v", "--add-variant", "X", "--judgement", "r"],
            "--authorize": ["v", "--authorize", "X", "--judgement", "r"],
            "--unauthorize": ["v", "--unauthorize", "X", "--judgement", "r"],
            "--paginated": ["v", "--paginated", "true", "--judgement", "r", "--rests-on", digest],
            "--clear-paginated": ["v", "--clear-paginated", "--judgement", "r", "--rests-on", digest],
            "--references": ["v", "--references", #"[{"field":"issn","value":"0317-8471","kind":"retrieval","url":"https://portal.issn.org/","retrieved":"2026-10-05","status":200,"content":"\#(digest)"}]"#],
            "--note": ["v", "--note", "n"],
            "--type": ["v", "--type", "periodical"],
            "--judgement": ["v", "--judgement", "r"],
            "--rests-on": ["v", "--rests-on", digest],
        ],
        "update-organization": [
            "--remove-name": ["o", "--remove-name", "X=r"],
            "--authorize": ["o", "--authorize", "X", "--judgement", "r"],
            "--judgement": ["o", "--judgement", "r"],
            "--rests-on": ["o", "--rests-on", digest],
        ],
        "resolve-organizations": [
            "--apply": ["--apply"],
            "--reject": ["--reject", "--org", "o"],
            "--undecided": ["--undecided", "x@o=r"],
            "--judge": ["--judge", "x@o=r"],
            "--holder": ["--holder", "p"],
            "--org": ["--org", "o"],
            "--rests-on": ["--rests-on", digest],
        ],
    ]

    func testLegRulingsHoldAgainstTheRealBinary() throws {
        XCTAssertEqual(Set(Self.samples.keys), Set(DestructiveTargetGate.legRulings.keys))
        var checked = 0
        for (cmd, legs) in DestructiveTargetGate.legRulings.sorted(by: { $0.key < $1.key }) {
            XCTAssertEqual(Set((Self.samples[cmd] ?? [:]).keys), Set(legs.keys),
                           "\(cmd)：每一條腿要有一個樣本 argv")
            for (leg, ruling) in legs.sorted(by: { $0.key < $1.key }) {
                guard let argv = Self.samples[cmd]?[leg] else { continue }
                let r = try CLITestHarness.run([cmd] + argv, env: unnamedEnv)
                checked += 1
                switch ruling {
                case .gated:
                    XCTAssertNotEqual(r.status, 0, "\(cmd) \(leg)：\(r.output)")
                    XCTAssertTrue(r.output.contains("\(cmd) \(leg) 拒絕執行：未指名目標 store"),
                                  "\(cmd) \(leg) 裁決為過閘，未指名目標時要被擋、且拒絕訊息點名這條腿：\n\(r.output)")
                case .notGated(_), .readOnly(_):
                    XCTAssertFalse(r.output.contains("未指名目標 store"),
                                   "\(cmd) \(leg) 裁決為不閘，卻被閘擋了——表或程式有一邊錯：\n\(r.output)")
                    // 不閘的寫入腿，樣本要走到閘會在的位置之後（開 store、進 service）：在參數檢查就被擋下的樣本
                    // 證不到「這條腿沒有閘」——日後有人替它加了閘而沒改表，這一格照綠。參數檢查的錯誤一律帶 Usage（#549）。
                    // `.readOnly` 的腿不要求：`--rests-on` 這類伴隨參數單獨出現本來就該被參數檢查擋下。
                    if case .notGated = ruling {
                        XCTAssertFalse(r.output.contains("Usage:"),
                                       "\(cmd) \(leg) 的樣本在參數檢查就被擋下，走不到閘的位置——換一個走得到 store 的樣本：\n\(r.output)")
                    }
                case .perLeg:
                    XCTFail("\(cmd) \(leg)：腿不能是 .perLeg")
                }
            }
        }
        XCTAssertGreaterThan(checked, 20)
    }

    // MARK: - #564 使用者 2026-10-05 裁決第 4 點

    /// `update-person --remove-name` 過閘、乾跑不擋；`update-organization --remove-name` 沒有乾跑、一律擋，拒絕訊息說它沒有乾跑；
    /// 指名目標之後通過閘（之後是 store 狀態的事）。
    func testRemoveNameLegsAreGatedButThePersonDryRunIsNot() throws {
        let dry = try CLITestHarness.run(["update-person", "--key", "p", "--remove-name", "X=r", "--dry-run"], env: unnamedEnv)
        XCTAssertFalse(dry.output.contains("未指名目標 store"), dry.output)
        let org = try CLITestHarness.run(["update-organization", "o", "--remove-name", "X=r"], env: unnamedEnv)
        XCTAssertNotEqual(org.status, 0)
        XCTAssertTrue(org.output.contains("update-organization --remove-name 拒絕執行：未指名目標 store") && org.output.contains("這條腿沒有 dry-run"),
                      org.output)
        let named = try CLITestHarness.run(["update-person", "--key", "p", "--remove-name", "X=r", "--library", root.path], env: unnamedEnv)
        XCTAssertFalse(named.output.contains("未指名目標 store"), named.output)
    }

    /// `update-venue --edit-name-segment`：一條腿兩種動作——帶 remove 的過閘（拒絕訊息點名這條腿、說它沒有乾跑），只有 set 的不閘
    /// （走到 store、被「找不到 venue」擋下）；`--yes` 之後帶 remove 的也通過閘。
    func testVenueEditNameSegmentIsGatedOnlyWhenItRemoves() throws {
        let remove = try CLITestHarness.run(["update-venue", "v", "--edit-name-segment", #"[{"name":"X","set":{"note":"n"},"reason":"r"},{"name":"Y","remove":true,"reason":"r"}]"#],
                                            env: unnamedEnv)
        XCTAssertNotEqual(remove.status, 0)
        XCTAssertTrue(remove.output.contains("update-venue --edit-name-segment 拒絕執行：未指名目標 store") && remove.output.contains("這條腿沒有 dry-run"),
                      remove.output)
        let set = try CLITestHarness.run(["update-venue", "v", "--edit-name-segment", #"[{"name":"X","set":{"note":"n"},"reason":"r"}]"#], env: unnamedEnv)
        XCTAssertFalse(set.output.contains("未指名目標 store"), set.output)
        XCTAssertFalse(set.output.contains("Usage:"), "樣本要走到 store：\(set.output)")
        let yes = try CLITestHarness.run(["update-venue", "v", "--edit-name-segment", #"[{"name":"Y","remove":true,"reason":"r"}]"#, "--yes"], env: unnamedEnv)
        XCTAssertFalse(yes.output.contains("未指名目標 store"), yes.output)
    }

    // MARK: - #658 的兩格

    /// `import-zotero` 未指名目標就拒絕，而且拒絕在建佈局**之前**——它走 `openOrCreateStore`，
    /// 若閘放在後面，一次被擋的呼叫仍會在錯的地方長出一個 store。
    func testImportZoteroRefusesBeforeCreatingAnything() throws {
        let fresh = root.deletingLastPathComponent().appendingPathComponent("not-yet-a-store")
        var env = unnamedEnv
        env["AKASHIC_LIBRARY"] = fresh.path
        let missingDB = ["--zotero-db", root.deletingLastPathComponent().appendingPathComponent("absent.sqlite").path]
        let refused = try CLITestHarness.run(["import-zotero"] + missingDB, env: env)
        XCTAssertNotEqual(refused.status, 0, refused.output)
        XCTAssertTrue(refused.output.contains("import-zotero 拒絕執行：未指名目標 store"), refused.output)
        XCTAssertTrue(refused.output.contains("這個命令沒有 dry-run"), "出路要說它沒有乾跑：\n\(refused.output)")
        XCTAssertFalse(FileManager.default.fileExists(atPath: fresh.path), "被擋的呼叫不得建出佈局")

        // 指名之後照常往下走（在這裡止於 zotero.sqlite 不存在）
        for named in [["--yes"], ["--library", fresh.path]] {
            let r = try CLITestHarness.run(["import-zotero"] + missingDB + named, env: env)
            XCTAssertFalse(r.output.contains("未指名目標 store"), "\(named)：\(r.output)")
            XCTAssertTrue(r.output.contains("找不到 zotero.sqlite"), "\(named)：\(r.output)")
        }
    }

    /// `resolve-people --drop-author` 未指名目標就拒絕、作者位不動；指名之後照常移除。
    func testDropAuthorRefusesWithoutANamedTargetAndLeavesTheSlot() throws {
        let store = LibraryStore(root: root, key: nil, environment: [:])
        try store.writeEntry(Entry(id: UUID(), citekey: "x2020y", type: .periodicalArticle, title: "T",
                                   authors: [.literal("No authorship indicated")], date: "2020"))
        let arg = ["resolve-people", "--drop-author", "x2020y:No authorship indicated=PsycInfo 的無署名佔位字串"]
        let refused = try CLITestHarness.run(arg, env: unnamedEnv)
        XCTAssertNotEqual(refused.status, 0, refused.output)
        XCTAssertTrue(refused.output.contains("resolve-people --drop-author 拒絕執行：未指名目標 store"), refused.output)
        XCTAssertTrue(refused.output.contains("這個寫入沒有 dry-run"), refused.output)
        let before = try store.load().entries.first { $0.citekey == "x2020y" }
        XCTAssertEqual(before?.authors, [.literal("No authorship indicated")], "被擋的呼叫不得動作者位")

        let done = try CLITestHarness.run(arg + ["--library", root.path], env: unnamedEnv)
        XCTAssertEqual(done.status, 0, done.output)
        let after = try LibraryStore(root: root, key: nil, environment: [:]).load().entries.first { $0.citekey == "x2020y" }
        XCTAssertEqual(after?.authors, [], "指名之後照常移除：\(done.output)")
    }

    /// `dismiss-divergence` 實跑未指名目標就拒絕；乾跑不擋；指名之後照常往下走（#586 R1 verify）。
    /// 歧異記錄的 UUID 由候選 key 決定，錯的 store 上照樣對得上——#580 的判準。
    func testDismissDivergenceRefusesWithoutANamedTargetButNotOnDryRun() throws {
        let id = UUID().uuidString
        let arg = ["dismiss-divergence", id, "--reason", "記錯的一筆"]
        let refused = try CLITestHarness.run(arg, env: unnamedEnv)
        XCTAssertNotEqual(refused.status, 0, refused.output)
        XCTAssertTrue(refused.output.contains("dismiss-divergence 拒絕執行：未指名目標 store"), refused.output)
        XCTAssertTrue(refused.output.contains("加 --dry-run 可以先看到會改什麼"), "預覽提示要指向乾跑旗標：\n\(refused.output)")
        // 乾跑、`--library`、`--yes` 都走過閘，止於這個 id 不存在
        for extra in [["--dry-run"], ["--library", root.path], ["--yes"]] {
            let r = try CLITestHarness.run(arg + extra, env: unnamedEnv)
            XCTAssertFalse(r.output.contains("未指名目標 store"), "\(extra)：\(r.output)")
            XCTAssertTrue(r.output.contains("找不到：歧異記錄"), "\(extra)：\(r.output)")
        }
    }
}
