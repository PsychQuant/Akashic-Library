import XCTest
@testable import AkashicCore
@testable import AkashicStoreIO
@testable import akashic

/// #547：`bootstrap-people` 的第四段（彼此互為異寫、兩邊都還沒有記錄）與兩個出口。
///
/// **走真 binary**，經 `CLITestHarness`（不自己複製 `runCLI`——那個 harness 的檔頭
/// 記著它被複製成三份的教訓）。
///
/// 本檔測的是 model 層測不到的三件事：
/// 1. 那一段**真的被印出來**（`lossless-intake` 執行細節 3：只在 model 端加欄位而
///    沒有任何輸出讀它，與丟棄在效果上完全相同——本 repo 已在 #236 R3 踩過）
/// 2. 候選段的顯示上限**走 `AmbiguityDisplayLimit.rows` 而非寫死的 20**
/// 3. `--json` 與人可讀面**同源**
final class BootstrapPeopleMutualCLITests: XCTestCase {
    var root: URL!
    var fakeHome: URL!

    private var env: [String: String] { ["AKASHIC_HOME": fakeHome.path] }

    private func cli(_ args: [String]) throws -> (status: Int32, output: String) {
        try CLITestHarness.run(args + ["--library", root.path], env: env)
    }

    override func setUpWithError() throws {
        fakeHome = FileManager.default.temporaryDirectory
            .appendingPathComponent("akashic-home-\(UUID().uuidString)")
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("akashic-bpm-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: fakeHome, withIntermediateDirectories: true)
        let store = LibraryStore(root: root)
        try store.ensureLayout()

        // 三種 Dweck 寫法，彼此共鍵而**都還沒有 person 記錄**
        for (ck, name) in [("a2020", "Carol S Dweck"),
                           ("b2021", "Carol S. Dweck"),
                           ("c2022", "C. S. Dweck")] {
            try store.writeEntry(Entry(id: UUID(), citekey: ck, type: .periodicalArticle,
                                       title: "T", authors: [.literal(name)], date: "2020"))
        }
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
        try? FileManager.default.removeItem(at: fakeHome)
    }

    /// 第四段真的被印出來，而且三個寫法在同一列。
    func testMutualSectionIsActuallyPrinted() throws {
        let r = try cli(["bootstrap-people", "--min-occurrences", "1"])
        XCTAssertEqual(r.status, 0, r.output)
        XCTAssertTrue(r.output.contains("兩邊都還沒有記錄"),
                      "第四段沒有被印出來——只在 model 端加欄位等同丟棄：\n\(r.output)")
        XCTAssertTrue(r.output.contains("Carol S Dweck")
                        && r.output.contains("C. S. Dweck"),
                      "三個寫法要在同一組裡看得到：\n\(r.output)")
    }

    /// 扣住的成員不得同時出現在建檔候選段。
    func testWithheldMembersAreNotAlsoListedAsCandidates() throws {
        let r = try cli(["bootstrap-people", "--min-occurrences", "1"])
        XCTAssertEqual(r.status, 0, r.output)
        XCTAssertFalse(r.output.contains("dweck-carol-s"),
                       "被扣住的組不該有建檔 key 出現在候選段：\n\(r.output)")
    }

    /// 顯示上限走 `AmbiguityDisplayLimit.rows`，不是寫死的 20。
    ///
    /// **不比對數字字面**（那會在改常數時假綠），而是造 21 個彼此無關的候選：
    /// 寫死 20 時會出現截斷行，走 `rows`（50）時不會。
    func testCandidateDisplayCapFollowsAmbiguityDisplayLimit() throws {
        let store = LibraryStore(root: root)
        for i in 0..<21 {
            try store.writeEntry(Entry(id: UUID(), citekey: "z\(i)2020",
                                       type: .periodicalArticle, title: "T",
                                       authors: [.literal("Unique\(i) Surname\(i)")],
                                       date: "2020"))
        }
        let r = try cli(["bootstrap-people", "--min-occurrences", "1"])
        XCTAssertEqual(r.status, 0, r.output)
        XCTAssertGreaterThan(AmbiguityDisplayLimit.rows, 21,
                             "本測試的前提是上限 > 21；常數改小要重挑 fixture")
        XCTAssertFalse(r.output.contains("只列前 20"),
                       "候選段仍在用寫死的 20：\n\(r.output)")
    }

    /// `--json` 與人可讀面同源——四段都在，且 `pendingMutual` 有那一組。
    func testJSONCarriesAllFourSections() throws {
        let r = try cli(["bootstrap-people", "--min-occurrences", "1", "--json"])
        XCTAssertEqual(r.status, 0, r.output)
        let data = Data(r.output.utf8)
        let obj = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any],
                                "--json 的輸出不是一個 JSON object：\n\(r.output)")
        for k in ["candidates", "unkeyable", "pendingResolution", "pendingMutual"] {
            XCTAssertNotNil(obj[k], "缺少 `\(k)` 段：\(obj.keys.sorted())")
        }
        let mutual = try XCTUnwrap(obj["pendingMutual"] as? [[String: Any]])
        // 一列＝一個共鍵理由（#547 批次二）：三種 Dweck 寫法有兩個理由，所以有兩列，
        // 而其中**一列**同時涵蓋三者。斷言那一列在，不斷言只有一列。
        let names = mutual.compactMap { $0["names"] as? [String] }
        XCTAssertTrue(names.contains { Set($0) == ["Carol S Dweck", "Carol S. Dweck", "C. S. Dweck"] },
                      "必須有一列同時涵蓋三種寫法：\(mutual)")
    }

    /// **`--json` 的 `display-safe-exempt` 前提，釘住。**
    ///
    /// 那四行豁免的理由是「消毒層是序列化器 ＋ 序列化後的 `escapingUnsafeScalars`」。
    /// 豁免不能只是一句宣稱——這條測試證明它：塞一個含五類危險 scalar 的作者名，
    /// 斷言輸出裡**沒有任何裸的危險 scalar**，而且那個名字**逐字**取得回來
    /// （消毒過就取不回來，`add-person` 會建錯名字）。
    ///
    /// **判準是 scalar 集合，而且與 `displaySafe` 同源**（#547 verify V3）。上一版用
    /// `byte < 0x20`——在 UTF-8 裡只可能看到 ASCII C0，於是 U+007F、U+009B（CSI，
    /// ＝ `ESC [` 的單位元組等價形）、U+202E、U+2028、U+FEFF **一個都進不了 filter**：
    /// 它宣稱的紅燈條件不可達，而 fixture 裡也只有 ESC／BEL 兩個 C0 字元，
    /// 「通過」什麼都沒證明。
    func testJSONOutputHasNoRawUnsafeScalars() throws {
        // 五類各一個，全部落在舊判準的視線之外（除了前面的 ESC／BEL）
        let evil = "A\u{001B}[31mB\u{0007}\u{007F}\u{009B}31m\u{202E}\u{2028}\u{FEFF} Chen"
        let store = LibraryStore(root: root)
        try store.writeEntry(Entry(id: UUID(), citekey: "e2020evil", type: .periodicalArticle,
                                   title: "T", authors: [.literal(evil)], date: "2020"))

        let r = try cli(["bootstrap-people", "--min-occurrences", "1", "--json"])
        XCTAssertEqual(r.status, 0, r.output)

        // `.prettyPrinted` 在 token 之間送**裸的**換行，那是結構位置、合法且必要——
        // 所以豁免它與縮排空白。字串字面值**內**的換行由序列化器逃脫成 `\n`，
        // 不會走到這裡。
        let raw = r.output.unicodeScalars.filter {
            UnsafeToEmitScalar.contains($0) && $0 != "\n" && $0 != "\r" && $0 != "\t"
        }
        XCTAssertTrue(raw.isEmpty,
                      "JSON 輸出含裸的危險 scalar "
                        + "\(raw.map { String(format: "U+%04X", $0.value) })"
                        + " —— display-safe-exempt 的前提不成立了")

        // 逐字取回：消毒過的字串在這裡會對不上
        let obj = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(r.output.utf8))
                                  as? [String: Any])
        let all = ((obj["candidates"] as? [[String: Any]]) ?? [])
            .compactMap { $0["names"] as? [String] }.flatMap { $0 }
        XCTAssertTrue(all.contains(evil),
                      "literal 必須逐字取得回來（消費端要拿它餵 add-person）：\(all)")
    }

    /// **序列化器自己涵蓋不到的那四類，逐一釘住**——證明上一條的 fixture 不是白放的。
    ///
    /// 這一條直接量序列化器：若它哪天開始逃脫這些，本條會紅，那時
    /// `escapingUnsafeScalars` 那一層才可以重新裁決要不要留。反過來若它退步到連 C0
    /// 都不逃脫，上一條會紅。兩條各守一半。
    func testSerializerAloneDoesNotCoverTheseFourClasses() throws {
        let uncovered: [Unicode.Scalar] = ["\u{007F}", "\u{009B}", "\u{202E}", "\u{2028}", "\u{FEFF}"]
        for u in uncovered {
            let data = try JSONSerialization.data(withJSONObject: ["k": String(String.UnicodeScalarView([u]))])
            let out = String(decoding: data, as: UTF8.self)
            XCTAssertTrue(out.unicodeScalars.contains(u),
                          "U+\(String(format: "%04X", u.value)) 已被序列化器逃脫——"
                            + "escapingUnsafeScalars 的必要性要重新裁決：\(out.debugDescription)")
            XCTAssertFalse(
                UnsafeToEmitScalar.escapingUnsafeScalars(inSerializedJSON: out)
                    .unicodeScalars.contains(u),
                "後處理沒有把 U+\(String(format: "%04X", u.value)) 改寫掉")
        }
    }

    /// **`--apply` 必須說出它扣住了什麼。**（#547 verify 的 BLOCKING finding）
    ///
    /// 本檔前五個 case 全是乾跑，所以對「`--apply` 成功路徑漏印第四段」結構性地盲——
    /// 四個獨立的 review lens 同時指認了它，而測試全綠。實測當時 live store 上是
    /// 253 組／591 個寫法無聲消失：`--apply` 只印「✓ 建立 N 個 person」。
    ///
    /// 這一條走**真的 `--apply`**，斷言三件事：正常候選被建、被扣住的沒被建、
    /// 而且**數量有被說出來**。第三個斷言是重點——前兩個就算全對，靜默仍然是缺陷
    /// （`lossless-intake` §3：靜默是最糟的形式）。
    func testApplyReportsWhatItWithheld() throws {
        // setUp 已放三個 Dweck 寫法（互為異寫、會被扣住）。再加一個無關的正常候選。
        let store = LibraryStore(root: root)
        try store.writeEntry(Entry(id: UUID(), citekey: "n2023solo", type: .periodicalArticle,
                                   title: "T", authors: [.literal("Ingrid Solitary")],
                                   date: "2023"))

        let r = try cli(["bootstrap-people", "--min-occurrences", "1", "--apply"])
        XCTAssertEqual(r.status, 0, r.output)

        // (a) 正常候選被建
        let people = try LibraryStore(root: root).load().people
        let builtNames = Set(people.flatMap { $0.names.all })
        XCTAssertTrue(builtNames.contains("Ingrid Solitary"),
                      "無關的正常候選必須照常建檔：\(builtNames)")

        // (b) 被扣住的沒被建
        for held in ["Carol S Dweck", "Carol S. Dweck", "C. S. Dweck"] {
            XCTAssertFalse(builtNames.contains(held),
                           "`\(held)` 被扣住卻仍然建了檔：\(builtNames)")
        }

        // (c) **數量被說出來**——沒有這一條，(a)(b) 全對仍然是靜默扣留
        XCTAssertTrue(r.output.contains("未建檔"),
                      "--apply 沒有說出它扣住了什麼：\n\(r.output)")
        XCTAssertTrue(r.output.contains("2 組"),
                      "扣住的組數要出現在輸出裡：\n\(r.output)")
        // **3 而不是 5**：兩列合計五個名字位，但 `Carol S Dweck` 與 `Carol S. Dweck`
        // 同時出現在兩列（它們有兩個共鍵理由）。逐列相加會謊報——這一條釘住去重。
        XCTAssertTrue(r.output.contains("3 個寫法"),
                      "扣住的寫法數要去重後說出來（逐列相加會得到 5）：\n\(r.output)")
    }
}
