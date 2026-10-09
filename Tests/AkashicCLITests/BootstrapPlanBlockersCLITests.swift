import XCTest
import Foundation
@testable import AkashicCore
@testable import AkashicStoreIO

/// #709 b36 verify（MEDIUM 1、3、4）與使用者 2026-10-09 裁決：三個 bootstrap 的 `--apply` 在計畫讀到下列任一種時整批拒絕、零寫入，乾跑說出來——
///
/// 1. **person 的 legacy 拷貝**（裁決 1）。先前 `bootstrap-people` 不把它算進計畫，理由是「只會讓候選少一個」；verify 以真 binary 否掉，
///    三條反例在這裡各一支：拷貝帶的否決讓該先消歧的名字被建檔、拷貝多的名字讓 literal 安靜消失、內容相同的改名拷貝讓新 key 多 `-2`。
/// 2. **計畫來源種類中無法唯一定位的記錄**（裁決 2）：兩個 legacy 檔共用 id、或 entities/ 與 legacy 同 citekey（同 key）而 id 不同——
///    計數同樣加倍，先前乾跑沒有附註，`--apply` 寫入之後才以 index 的 UNIQUE 失敗收場（person 已落盤）。
///
/// store 是 git 工作樹、檔案都已 commit：單一份 legacy 檔本身寫得進去（可安全搬移），所以「無法唯一定位」只由要測的那一類造成（對照組釘住）。
/// 全部走真 binary。
final class BootstrapPlanBlockersCLITests: XCTestCase {
    private var base: URL!
    private var root: URL!
    private var home: URL!
    private var store: LibraryStore!

    private var env: [String: String] { ["AKASHIC_HOME": home.path] }

    private func cli(_ args: [String]) throws -> (status: Int32, output: String) {
        try CLITestHarness.run(args + ["--library", root.path], env: env)
    }

    private var scrubbedGitEnvironment: [String: String] {
        ProcessInfo.processInfo.environment.filter { !$0.key.hasPrefix("GIT_") }   // #239：hook 環境帶 GIT_DIR
    }

    private func git(_ args: [String]) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        p.arguments = ["-C", root.path, "-c", "user.email=t@t", "-c", "user.name=t"] + args
        p.environment = scrubbedGitEnvironment
        p.standardOutput = Pipe(); p.standardError = Pipe()
        try? p.run(); p.waitUntilExit()
    }

    private func commit() {
        git(["add", "-A"])
        git(["commit", "-q", "--allow-empty", "-m", "fixture"])
    }

    override func setUpWithError() throws {
        base = FileManager.default.temporaryDirectory.appendingPathComponent("akashic-709-blockers-\(UUID().uuidString)")
        root = base.appendingPathComponent("store")
        home = base.appendingPathComponent("home")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        try "sources/\n".write(to: root.appendingPathComponent(".gitignore"), atomically: true, encoding: .utf8)
        store = LibraryStore(root: root)
        try store.ensureLayout()
        try StoreVersion.write(root: root, format: StoreVersion.supported)
        for dir in [store.entriesDir, store.peopleDir] {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        git(["init", "-q"])
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: base)
    }

    private func writeEntities(_ e: Entry) throws {
        try EntryYAML.encode(e).write(to: store.entityURL(id: e.id), atomically: true, encoding: .utf8)
    }

    private func writeLegacy(_ e: Entry, file: String? = nil) throws {
        try EntryYAML.encode(e).write(to: store.entriesDir.appendingPathComponent("\(file ?? e.citekey).yaml"),
                                      atomically: true, encoding: .utf8)
    }

    private func writeEntities(_ p: Person) throws {
        try PersonYAML.encode(p).write(to: store.entityURL(id: p.id), atomically: true, encoding: .utf8)
    }

    private func writeLegacy(_ p: Person) throws {
        try PersonYAML.encode(p).write(to: store.personURL(key: p.key), atomically: true, encoding: .utf8)
    }

    /// store 裡每個 YAML 檔的位元組（相對路徑 → 內容）——零寫入的量法。
    private func storeFiles() throws -> [String: Data] {
        var out: [String: Data] = [:]
        for dir in [store.entitiesDir, store.entriesDir, store.peopleDir] {
            for url in (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? [] {
                out[dir.lastPathComponent + "/" + url.lastPathComponent] = try Data(contentsOf: url)
            }
        }
        return out
    }

    private func peopleJSON() throws -> [String: Any] {
        let r = try cli(["bootstrap-people", "--json"])
        XCTAssertEqual(r.status, 0, r.output)
        return try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(r.output.utf8)) as? [String: Any], r.output)
    }

    private func names(_ obj: [String: Any], _ section: String) -> [String] {
        ((obj[section] as? [[String: Any]]) ?? []).flatMap { ($0["names"] as? [String]) ?? [] }
    }

    /// `--apply` 被拒：結束碼 1、零寫入、訊息說出命令與處置，而且**是一行**——不帶被單行出口逃成字面 `\u{000A}` 的清單（b36 verify LOW 6、8、12、14）。
    private func assertApplyRefused(_ command: String, file: StaticString = #filePath, line: UInt = #line) throws {
        let before = try storeFiles()
        let r = try cli([command, "--apply"])
        XCTAssertEqual(r.status, 1, r.output, file: file, line: line)
        XCTAssertTrue(r.output.contains("\(command) --apply") && r.output.contains("整批拒絕、零寫入")
                      && r.output.contains("乾跑（不帶 --apply）逐份列出"), r.output, file: file, line: line)
        XCTAssertFalse(r.output.contains("\\u{000A}") || r.output.contains("（已截斷）"), "拒絕訊息是完整的一行：\(r.output)", file: file, line: line)
        XCTAssertEqual(try storeFiles(), before, "零寫入", file: file, line: line)
    }

    // MARK: - 裁決 1：person 拷貝

    /// 反例一：拷貝帶 entities/ 那份沒有的否決記錄——`Doe, A.` 本該「與既有 person 寬鬆共鍵、先消歧」，拷貝的否決把它放行成建檔候選。
    func testAPersonCopyWithAnExtraRejectionBlocksBootstrapPeople() throws {
        let work = Entry(id: UUID(), citekey: "a2020cats", type: .periodicalArticle, title: "Cats",
                         authors: [.literal("Doe, A.")], date: "2020")
        try writeEntities(work)
        let person = Person(key: "doe-ab", names: PersonNames(authorized: ["Doe, Alice"]))
        try writeEntities(person)
        commit()
        let control = try peopleJSON()
        XCTAssertTrue(names(control, "pendingResolution").contains("Doe, A."), "前提：沒有拷貝時先消歧、不建檔：\(control)")
        XCTAssertFalse(names(control, "candidates").contains("Doe, A."), "\(control)")

        var leftover = person
        leftover.references = [ProvenanceReference(
            field: ProvenanceReference.resolutionRejectedField,
            value: ProvenanceReference.VerdictPairingValue(holderKind: .work, holder: "a2020cats", literal: "Doe, A.").encoded,
            kind: .judgement(statement: "測試用否決", restsOn: []))]
        try writeLegacy(leftover)
        commit()
        let withCopy = try peopleJSON()
        XCTAssertTrue(names(withCopy, "candidates").contains("Doe, A."), "反例成立：拷貝的否決讓它成為候選：\(withCopy)")
        XCTAssertEqual(withCopy["legacyCopiesInPlan"] as? Int, 1, "person 拷貝在計畫裡：\(withCopy)")

        let dry = try cli(["bootstrap-people"])
        XCTAssertEqual(dry.status, 0, dry.output)
        XCTAssertTrue(dry.output.contains("計畫含 1 份 legacy 拷貝") && dry.output.contains("people/doe-ab.yaml")
                      && dry.output.contains("否決"), dry.output)
        XCTAssertFalse(dry.output.contains("候選少一個"), dry.output)
        try assertApplyRefused("bootstrap-people")
    }

    /// 反例二：拷貝多一個名字——`Roe, B.` 被當成已存在，既不是候選也不在 pending，沒有任何提示。
    func testAPersonCopyWithAnExtraNameBlocksBootstrapPeople() throws {
        let work = Entry(id: UUID(), citekey: "r2020dogs", type: .periodicalArticle, title: "Dogs",
                         authors: [.literal("Roe, B.")], date: "2020")
        try writeEntities(work)
        let person = Person(key: "roe-zed", names: PersonNames(authorized: ["Roe, Zed"]))
        try writeEntities(person)
        commit()
        XCTAssertTrue(names(try peopleJSON(), "candidates").contains("Roe, B."), "前提：沒有拷貝時是候選")

        var leftover = person
        leftover.names = PersonNames(authorized: ["Roe, Zed"], variant: ["Roe, B."])
        try writeLegacy(leftover)
        commit()
        let withCopy = try peopleJSON()
        let everywhere = ["candidates", "pendingResolution", "pendingMutual", "unkeyable"].flatMap { names(withCopy, $0) }
        XCTAssertFalse(everywhere.contains("Roe, B."), "反例成立：拷貝的名字讓 literal 安靜消失：\(withCopy)")
        XCTAssertEqual(withCopy["legacyCopiesInPlan"] as? Int, 1, "\(withCopy)")
        let dry = try cli(["bootstrap-people"])
        XCTAssertTrue(dry.output.contains("計畫含 1 份 legacy 拷貝") && dry.output.contains("people/roe-zed.yaml"), dry.output)
        try assertApplyRefused("bootstrap-people")
    }

    /// 反例三：內容相同的改名拷貝——舊 key `doe-a` 還在已用的 key 裡，新候選的 key 變成 `doe-a-2`；拷貝刪掉之後那個後綴改不回來。
    func testARenameLeftoverPersonCopyBlocksBootstrapPeople() throws {
        let work = Entry(id: UUID(), citekey: "d2020owls", type: .periodicalArticle, title: "Owls",
                         authors: [.literal("Doe, A.")], date: "2020")
        try writeEntities(work)
        let renamed = Person(key: "doe-x", names: PersonNames(authorized: ["Doe, Xavier"]))
        try writeEntities(renamed)
        commit()
        func key(of literal: String, in obj: [String: Any]) -> String? {
            ((obj["candidates"] as? [[String: Any]]) ?? []).first { ($0["names"] as? [String])?.contains(literal) == true }?["key"] as? String
        }
        XCTAssertEqual(key(of: "Doe, A.", in: try peopleJSON()), "doe-a", "前提：沒有拷貝時 key 是 doe-a")

        var oldName = renamed
        oldName.key = "doe-a"
        try writeLegacy(oldName)
        commit()
        let withCopy = try peopleJSON()
        XCTAssertEqual(key(of: "Doe, A.", in: withCopy), "doe-a-2", "反例成立：舊 key 讓新 key 多一個後綴：\(withCopy)")
        XCTAssertEqual(withCopy["legacyCopiesInPlan"] as? Int, 1, "\(withCopy)")
        try assertApplyRefused("bootstrap-people")
    }

    /// 對照組：person 拷貝不在 `bootstrap-venues` 的計畫裡（它只讀 entries）——不印附註、`--apply` 照寫。
    func testAPersonCopyDoesNotBlockBootstrapVenues() throws {
        var work = Entry(id: UUID(), citekey: "v2020ants", type: .periodicalArticle, title: "Ants", date: "2020")
        work.fields["journaltitle"] = "Journal of Real Things"
        try writeEntities(work)
        let person = Person(key: "kim-c", names: PersonNames(authorized: ["Kim, Chris"]))
        try writeEntities(person)
        var oldName = person
        oldName.key = "old-kim"
        try writeLegacy(oldName)
        commit()
        XCTAssertEqual(try store.load().shadowedLegacyCopies.map(\.key), ["old-kim"], "前提：load 認得出這份 person 拷貝")
        let dry = try cli(["bootstrap-venues"])
        XCTAssertEqual(dry.status, 0, dry.output)
        XCTAssertFalse(dry.output.contains("legacy 拷貝") || dry.output.contains("無法唯一定位"), dry.output)
        let r = try cli(["bootstrap-venues", "--apply"])
        XCTAssertEqual(r.status, 0, r.output)
        XCTAssertTrue(try store.load().venues.contains { $0.key == "journal-of-real-things" }, "bootstrap-venues 寫入了")
    }

    // MARK: - 裁決 2：無法唯一定位的記錄

    /// 三個 bootstrap 都讀得到的一筆 work：作者 literal、團體作者 literal、刊名。
    private func sampleWork(_ citekey: String, id: UUID = UUID()) -> Entry {
        var e = Entry(id: id, citekey: citekey, type: .periodicalArticle, title: "T",
                      authors: [.literal("Doe, A."), .literal("Ghost Consortium")], date: "2020")
        e.fields["journaltitle"] = "Journal of Alpha Things"
        return e
    }

    private let commands = ["bootstrap-people", "bootstrap-venues", "bootstrap-organizations"]

    /// 兩個 legacy 檔共用同一個 id、entities/ 沒有那個 id——load 不標成拷貝（不是同一筆記錄的兩份），validate 判成 error。
    func testTwoLegacyWorkFilesSharingAnIDBlockAllThreeBootstraps() throws {
        let id = UUID()
        var beta = sampleWork("a2020beta", id: id)
        beta.title = "Other"
        try writeLegacy(sampleWork("a2020alpha", id: id))
        try writeLegacy(beta)
        commit()
        let load = try store.load()
        XCTAssertEqual(load.shadowedLegacyCopies, [], "前提：不是 load 標出的拷貝")
        XCTAssertEqual(load.entries.unlocatableCitekeys, ["a2020alpha", "a2020beta"], "前提：兩筆都無法唯一定位")
        XCTAssertEqual(try peopleJSON()["unlocatableInPlan"] as? Int, 2)

        for command in commands {
            let dry = try cli([command])
            XCTAssertEqual(dry.status, 0, "\(command)：\(dry.output)")
            XCTAssertTrue(dry.output.contains("計畫含 2 筆無法唯一定位的記錄") && dry.output.contains("work「a2020alpha」")
                          && dry.output.contains("work「a2020beta」") && dry.output.contains("--apply 會整批拒絕、零寫入"),
                          "\(command) 乾跑說出來：\(dry.output)")
            try assertApplyRefused(command)
        }
    }

    /// entities/ 與 legacy 同 citekey、id 不同——兩筆不同的記錄，load 不標成拷貝；citekey 重複。
    func testSameCitekeyDifferentIDBlocksAllThreeBootstraps() throws {
        try writeEntities(sampleWork("a2020alpha"))
        try writeLegacy(sampleWork("a2020alpha"))
        commit()
        let load = try store.load()
        XCTAssertEqual(load.shadowedLegacyCopies, [], "前提：id 不同，不是拷貝")
        XCTAssertEqual(load.entries.unlocatableCitekeys, ["a2020alpha"])

        for command in commands {
            let dry = try cli([command])
            XCTAssertEqual(dry.status, 0, "\(command)：\(dry.output)")
            XCTAssertTrue(dry.output.contains("計畫含 1 筆無法唯一定位的記錄") && dry.output.contains("work「a2020alpha」"),
                          "\(command) 乾跑說出來：\(dry.output)")
            try assertApplyRefused(command)
        }
    }

    /// person 側（`unlocatablePersonKeys`）：entities/ 與 people/ 同 key、id 不同。people 與 organizations 的計畫讀 person——擋；
    /// venues 不讀——照寫（對照組）。
    func testADuplicatedPersonKeyBlocksPeopleAndOrganizationsButNotVenues() throws {
        var work = Entry(id: UUID(), citekey: "v2020ants", type: .periodicalArticle, title: "Ants",
                         authors: [.literal("Roe, Q.")], date: "2020")
        work.fields["journaltitle"] = "Journal of Real Things"
        try writeEntities(work)
        var smith = Person(key: "smith-j", names: PersonNames(authorized: ["Smith, John"]))
        smith.profile.affiliations = TimelineOf<OrgRef>([TemporalValue(value: .literal("Institute of Real Things"))])
        try writeEntities(smith)
        var other = smith
        other.id = UUID()
        try writeLegacy(other)
        commit()
        let load = try store.load()
        XCTAssertEqual(load.shadowedLegacyCopies, [], "前提：id 不同，不是拷貝")
        XCTAssertEqual(load.people.unlocatablePersonKeys, ["smith-j"])

        for command in ["bootstrap-people", "bootstrap-organizations"] {
            let dry = try cli([command])
            XCTAssertTrue(dry.output.contains("計畫含 1 筆無法唯一定位的記錄") && dry.output.contains("person「smith-j」"),
                          "\(command)：\(dry.output)")
            try assertApplyRefused(command)
        }
        let dry = try cli(["bootstrap-venues"])
        XCTAssertFalse(dry.output.contains("無法唯一定位"), dry.output)
        let r = try cli(["bootstrap-venues", "--apply"])
        XCTAssertEqual(r.status, 0, r.output)
    }

    /// 對照組：一份 legacy 檔、已 commit、沒有 entities/ 那份——寫得進去（可安全搬移），不是無法唯一定位，三個 bootstrap 都照寫。
    func testASingleCommittedLegacyFileDoesNotBlock() throws {
        try writeLegacy(sampleWork("a2020alpha"))
        commit()
        XCTAssertEqual(try store.load().entries.unlocatableCitekeys, [], "前提：可安全搬移")
        for command in commands {
            let dry = try cli([command])
            XCTAssertFalse(dry.output.contains("無法唯一定位") || dry.output.contains("legacy 拷貝"), "\(command)：\(dry.output)")
            let r = try cli([command, "--apply"])
            XCTAssertEqual(r.status, 0, "\(command)：\(r.output)")
        }
    }

    /// 誠實邊界（裁決 2 的字面）：「無法唯一定位」的第 3 類——一份 legacy 檔、**沒有 commit**（寫入時 #631 會拒絕搬移）——不讓計數加倍，也照樣擋。
    /// 釘住它，讓日後要放寬的人看得到這是一個選擇。
    func testASingleUncommittedLegacyFileAlsoBlocks() throws {
        try writeLegacy(sampleWork("a2020alpha"))
        XCTAssertEqual(try store.load().entries.unlocatableCitekeys, ["a2020alpha"], "前提：沒有 commit，寫入時會被拒")
        let dry = try cli(["bootstrap-venues"])
        XCTAssertTrue(dry.output.contains("計畫含 1 筆無法唯一定位的記錄") && dry.output.contains("還沒處理的 legacy 殘留"), dry.output)
        try assertApplyRefused("bootstrap-venues")
    }

    /// 多份拷貝：乾跑附註逐份列出（stdout，照常分行；至多 20，其餘一行概括），`--apply` 的拒絕仍是完整的一行——先前 12 份時只點名得到兩份、
    /// 第三份在「（已截斷）」處被切斷（b36 verify LOW 8、14）。
    func testManyCopiesAreListedInTheDryRunAndTheRefusalStaysOneLine() throws {
        for i in 0..<22 {
            let e = Entry(id: UUID(), citekey: "w2020n\(i)", type: .periodicalArticle, title: "T\(i)",
                          authors: [.literal("Doe, A.")], date: "2020")
            try writeEntities(e)
            try writeLegacy(e)
        }
        commit()
        let dry = try cli(["bootstrap-people"])
        XCTAssertTrue(dry.output.contains("計畫含 22 份 legacy 拷貝") && dry.output.contains("…另 2 份"), dry.output)
        let listed = dry.output.split(separator: "\n").filter { $0.hasPrefix("    entries/w2020n") }
        XCTAssertEqual(listed.count, 20, dry.output)
        try assertApplyRefused("bootstrap-people")
    }
}
