import XCTest
import Foundation
import Yams
@testable import AkashicCore
@testable import AkashicStoreIO

/// `LiteralCensus`（#629：原 `literal-census.sh` 的 Swift 移植）。
///
/// 期望值的來歷要說清楚：**計數與版面的期望值是移植前從 shell＋Python 版量來的**（同一批 fixture 兩邊各跑一次，
/// 83 個 fixture 逐行相同，差異只有下列兩處刻意改寫的措辭：探測到的 binary 路徑、marker 問題行的說明）。
/// 所以這些斷言是「舊實作的行為」，不是「新實作自己說的話」。
final class LiteralCensusTests: XCTestCase {
    private var base: URL!

    override func setUpWithError() throws {
        base = FileManager.default.temporaryDirectory.appendingPathComponent("akashic-census-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        // chmod 000 的 fixture 要先還原權限才刪得掉
        if let e = FileManager.default.enumerator(atPath: base.path) {
            for case let p as String in e { chmod(base.appendingPathComponent(p).path, 0o755) }
        }
        try? FileManager.default.removeItem(at: base)
    }

    // MARK: - fixture

    private static let work = """
        work:
        id: 11111111-1111-1111-1111-111111111111
        citekey: t
        type: periodical-article
        title: t

        """

    private func makeStore(_ name: String = "s", files: [String: Data], marker: Data? = nil,
                           entitiesDir: Bool = true) throws -> String {
        let root = base.appendingPathComponent(name)
        if entitiesDir { try FileManager.default.createDirectory(at: root.appendingPathComponent("entities"), withIntermediateDirectories: true) }
        for (rel, data) in files {
            let url = root.appendingPathComponent(rel)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url)
        }
        if let marker { try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true); try marker.write(to: root.appendingPathComponent("store.yaml")) }
        return root.path
    }

    private func work(_ body: String) -> Data { Data((Self.work + body).utf8) }

    private struct Counts: Equatable {
        var key: Int, literal: Int, distinct: Int
        init(_ k: Int, _ l: Int, _ d: Int) { key = k; literal = l; distinct = d }
        init(_ d: LiteralCensus.Domain) { self.init(d.key, d.literal, d.distinct.count) }
    }

    private func census(_ files: [String: Data], marker: Data? = Data("format: 12\n".utf8), entitiesDir: Bool = true,
                        name: String = "s") throws -> LiteralCensus.Report {
        try LiteralCensus.run(root: makeStore(name, files: files, marker: marker, entitiesDir: entitiesDir))
    }

    // MARK: - 計數（四域）

    func testAuthorAndVenueBasicCounts() throws {
        let r = try census(["entities/x.yaml": work("authors:\n- literal: A\nvenues:\n- literal: V\n")])
        XCTAssertEqual(Counts(r.author), Counts(0, 1, 1))
        XCTAssertEqual(Counts(r.venue), Counts(0, 1, 1))
        XCTAssertEqual(Counts(r.affiliation), Counts(0, 0, 0))
        XCTAssertEqual(Counts(r.orgParents), Counts(0, 0, 0))
    }

    /// 四種寫法的同一個名字算一個 distinct（引號沒剝／尾註吃進去曾讓它們各算一個，#407 R62）。
    func testMixedAuthorFormsAreDecodedBeforeCountingDistinct() throws {
        let body = "authors:\n- key: p1\n- literal: Jacob Cohen\n- literal: \"Jacob Cohen\"\n- literal: 'Jacob Cohen'\n"
            + "- literal: Jacob Cohen  # note\n- literal: \"a \\\"q\\\" name\"\n- literal: 'it''s'\n"
            + "- literal: \"caf\\xe9\"\n- literal: \"\\u00e9\"\n- literal: \"\\U00020000\"\nvenues:\n- key: v1\n- literal: J1\n- literal: \"J1\"\n"
        let r = try census(["entities/a.yaml": work(body)])
        // key 1、literal 9、distinct 6（Jacob Cohen ×4 合一；q-name、it's、café、é、𠀀 各一——
        // `caf\xe9` 解出 café、`\u00e9` 解出 é，是兩個不同的字串）
        XCTAssertEqual(Counts(r.author), Counts(1, 9, 6))
        XCTAssertEqual(Counts(r.venue), Counts(1, 2, 1))
    }

    /// **項目的種類是封閉的**：區塊樣式只認 `- key:` 與 `- literal:`。`- organization:`（團體作者）不算 key 也不算
    /// literal，而且**終止區塊**——它後面的 `- key:` 不計（與 Python 版的樣式同；改它是語意變更）。
    func testAnOrganizationItemTerminatesTheAuthorBlock() throws {
        let r = try census(["entities/a.yaml": work("authors:\n- literal: A\n- organization: ORG\n  extra: 1\n- key: p2\n- literal: B\n")])
        XCTAssertEqual(Counts(r.author), Counts(0, 1, 1))
    }

    func testContinuationLinesBelongToTheirItemAndBlocksStopAtTheNextKey() throws {
        let r = try census(["entities/a.yaml": work("authors:\n- literal: X\n  role: first\n  foo: bar\n- key: k\n- literal: Y\nother: 1\nvenues:\n- literal: V\n  cont: 1\n- literal: W\n")])
        XCTAssertEqual(Counts(r.author), Counts(1, 2, 2))
        // venues 的樣式只認單行項目：`  cont: 1` 讓區塊在第一個項目後停下，`- literal: W` 不計
        XCTAssertEqual(Counts(r.venue), Counts(0, 1, 1))
    }

    /// 樣式要求每個項目行以換行收尾：最後一行沒有換行就不算（忠實於原樣式，見 `itemBlock`）。
    func testLastItemWithoutTrailingNewlineIsNotCounted() throws {
        let text = (Self.work + "authors:\n- literal: A\n- literal: B").data(using: .utf8)!
        let r = try census(["entities/a.yaml": text])
        XCTAssertEqual(Counts(r.author), Counts(0, 1, 1))
    }

    func testEmptyAuthorsBlockCountsNothing() throws {
        let r = try census(["entities/a.yaml": work("authors:\nvenues:\n- literal: V\n")])
        XCTAssertEqual(Counts(r.author), Counts(0, 0, 0))
        XCTAssertEqual(Counts(r.venue), Counts(0, 1, 1))
    }

    func testPersonAffiliationsCountKeyAndLiteral() throws {
        let yaml = "person:\nid: 22222222-2222-2222-2222-222222222222\nkey: p\nnames:\n- value: P\nprofile:\n  affiliations:\n  - value:\n      key: org1\n    start: 2000\n  - value:\n      literal: Some Institute\n  - value:\n      literal: \"Some Institute\"\n  - value:\n      literal: Other\n  orcid: 0000\n"
        let r = try census(["entities/p.yaml": Data(yaml.utf8)])
        XCTAssertEqual(Counts(r.affiliation), Counts(1, 3, 2))
    }

    /// 區塊到 EOF 為止、以及被 `profile` 頂層鍵截斷，兩種終止條件。
    func testAffiliationBlockTerminators() throws {
        let toEOF = try census(["entities/p.yaml": Data("person:\nkey: p\nprofile:\n  affiliations:\n  - value:\n      literal: X\n  - value:\n      key: k\n".utf8)], name: "eof")
        XCTAssertEqual(Counts(toEOF.affiliation), Counts(1, 1, 1))
        let byProfile = try census(["entities/p.yaml": Data("person:\nkey: p\nprofile:\n  affiliations:\n  - value:\n      literal: X\nprofile2: x\n".utf8)], name: "prof")
        XCTAssertEqual(Counts(byProfile.affiliation), Counts(0, 1, 1))
    }

    func testOrganizationParents() throws {
        let yaml = "organization:\nid: 33333333-3333-3333-3333-333333333333\nkey: o\nnames:\n- value: O\nparents:\n- value:\n    key: pk\n  start: 1990\n- value:\n    literal: Parent Lit\n- value:\n    literal: 'Parent Lit'\nnote: x\n"
        let r = try census(["entities/o.yaml": Data(yaml.utf8)])
        XCTAssertEqual(Counts(r.orgParents), Counts(1, 2, 1))
        XCTAssertEqual(Counts(r.author), Counts(0, 0, 0), "organization 檔不進 work／person 的計數")
    }

    /// parents 區塊到**下一個小寫字母開頭的頂層鍵**為止（`\n[a-z]`）；大寫開頭的行不終止它。
    func testOrganizationParentsBlockEndsAtTheNextLowercaseTopLevelKey() throws {
        let r = try census(["entities/o.yaml": Data("organization:\nkey: o\nparents:\n- value:\n    literal: PL\nNext: x\n- value:\n    literal: PL2\nnote: y\n- value:\n    literal: PL3\n".utf8)])
        XCTAssertEqual(Counts(r.orgParents), Counts(0, 2, 2), "大寫的 `Next:` 不終止區塊（PL2 計入）；`note:` 才終止（PL3 不計）")
    }

    /// **樣式的怪癖，釘住而不修**：空的 affiliations 緊接著兄弟鍵時，header 那一行的換行已被樣式消耗，
    /// 前瞻看不到那個兄弟鍵，區塊一路吃到下一個 `\n  [a-z]`——所以後面的 literal 被算進來。
    /// emitter 產出的實際檔案不會走到（空欄位不輸出 key）；改它是語意變更，與 Python 版一致地保留。
    func testEmptyAffiliationsBlockSwallowsTheNextSiblingsItems() throws {
        let r = try census(["entities/p.yaml": Data("person:\nkey: p\nprofile:\n  affiliations:\n  other:\n  - value:\n      literal: Q\n  aliases: 1\n".utf8)])
        XCTAssertEqual(Counts(r.affiliation), Counts(0, 1, 1))
    }

    // MARK: - 佈局

    /// legacy 佈局檔沒有形狀前綴——依目錄判 kind（entries/＝work、people/＝person）；與 entities/ 並存讀取。
    func testLegacyAndMixedLayoutsAreScannedTogether() throws {
        let r = try census([
            "entities/a.yaml": work("authors:\n- literal: A\nvenues:\n- literal: V\n"),
            "entries/b.yaml": Data("citekey: b\nauthors:\n- literal: B\n".utf8),
            "people/p.yaml": Data("key: p\nprofile:\n  affiliations:\n  - value:\n      literal: Z\n".utf8),
        ])
        XCTAssertEqual(Counts(r.author), Counts(0, 2, 2))
        XCTAssertEqual(Counts(r.venue), Counts(0, 1, 1))
        XCTAssertEqual(Counts(r.affiliation), Counts(0, 1, 1))
    }

    func testLegacyOnlyStoreNeedsNoEntitiesDirectory() throws {
        let r = try census(["entries/a.yaml": Data("citekey: a\nauthors:\n- literal: L1\n- key: k\nvenues:\n- literal: V1\n".utf8)],
                           entitiesDir: false)
        XCTAssertEqual(Counts(r.author), Counts(1, 1, 1))
        XCTAssertEqual(Counts(r.venue), Counts(0, 1, 1))
    }

    /// 檔名判準沿用 `glob("*.yaml")`：大小寫敏感、不含隱藏檔。
    func testOnlyLowercaseYamlNonHiddenFilesAreScanned() throws {
        let w = work("authors:\n- literal: A\n")
        let r = try census(["entities/.hid.yaml": w, "entities/UP.YAML": w, "entities/ok.yaml": w])
        XCTAssertEqual(r.author.literal, 1)
    }

    /// 路徑含 glob 特殊字元時不得靜默匹配零檔（輸出會與「查完歸零」無法區分）。
    func testGlobMetacharactersInRootAreLiteral() throws {
        let r = try census(["entities/x.yaml": work("authors:\n- literal: A\n")], name: "g[a]lob*?")
        XCTAssertEqual(r.author.literal, 1)
    }

    // MARK: - 文字層的隱性行為（都與 Python 版一致）

    /// Python 文字模式的 universal newlines：CRLF 與孤立 CR 都讀成 LF，計數與 LF 檔相同。
    func testCRLFAndLoneCRCountLikeLF() throws {
        let body = Self.work + "authors:\n- literal: A\nvenues:\n- literal: V\n"
        for (name, text) in [("crlf", body.replacingOccurrences(of: "\n", with: "\r\n")),
                             ("cr", body.replacingOccurrences(of: "\n", with: "\r"))] {
            let r = try census(["entities/a.yaml": Data(text.utf8)], name: name)
            XCTAssertEqual(Counts(r.author), Counts(0, 1, 1), name)
            XCTAssertEqual(Counts(r.venue), Counts(0, 1, 1), name)
        }
    }

    /// 壞位元組換成 U+FFFD、不中止（Python `errors='replace'`）。
    func testInvalidUTF8DoesNotAbortTheCensus() throws {
        var d = work("authors:\n- literal: A\nvenues:\n- literal: V\n"); d.append(Data("note: ".utf8)); d.append(contentsOf: [0xFF, 0xFE, 0x0A])
        let r = try census(["entities/a.yaml": d])
        XCTAssertEqual(r.author.literal, 1)
    }

    /// **繼承下來的怪癖，釘住而不修**：開頭的 BOM 讓 `work:` 前綴不成立，那個檔不進任何計數
    /// （Python 的 `t.startswith("work:")` 對 `\ufeffwork:` 為假）。改它是語意變更，要另案裁決。
    func testLeadingBOMDefeatsTheShapePrefix() throws {
        var d = Data([0xEF, 0xBB, 0xBF]); d.append(work("authors:\n- literal: A\n"))
        let r = try census(["entities/a.yaml": d])
        XCTAssertEqual(r.author.literal, 0)
    }

    /// 前綴比對是 code point 層，不是 grapheme 層：`work:` 後接組合符號時 Swift 的 `hasPrefix` 為假、Python 為真——
    /// 移植要跟 Python（這正是 `Array<Unicode.Scalar>.hasPrefix` 存在的理由）。
    func testShapePrefixIsCodePointLevelNotGraphemeLevel() throws {
        let text = "work:\u{0301}\n" + String((Self.work + "authors:\n- literal: A\nvenues:\n- literal: V\n").dropFirst("work:\n".count))
        let r = try census(["entities/a.yaml": Data(text.utf8)])
        XCTAssertEqual(r.author.literal, 1)
    }

    /// distinct 以 Unicode scalar 區分：NFC 與 NFD 的 é 是兩個（Swift `String` 的 `==` 會把它們併成一個）。
    func testDistinctIsByScalarsNotCanonicalEquivalence() throws {
        let r = try census(["entities/a.yaml": work("authors:\n- literal: \"\u{00E9}\"\n- literal: \"e\u{0301}\"\n- literal: \"\\u00e9\"\n")])
        XCTAssertEqual(Counts(r.author), Counts(0, 3, 2))
    }

    // MARK: - 掃不下去

    func testNotAStoreIsExit2() throws {
        let root = base.appendingPathComponent("nothing"); try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        XCTAssertThrowsError(try LiteralCensus.run(root: root.path)) {
            XCTAssertEqual($0 as? LiteralCensus.Failure, .notAStore(root: root.path))
            XCTAssertEqual(($0 as? LiteralCensus.Failure)?.exitCode, 2)
        }
    }

    func testNonEmptyEntitiesWithoutYamlIsExit3() throws {
        let root = try makeStore(files: ["entities/readme.txt": Data("x".utf8)])
        XCTAssertThrowsError(try LiteralCensus.run(root: root)) {
            XCTAssertEqual($0 as? LiteralCensus.Failure, .entitiesWithoutYAML(root: root))
            XCTAssertEqual(($0 as? LiteralCensus.Failure)?.exitCode, 3)
        }
    }

    func testEmptyEntitiesDirectoryReportsZeroesNotAnError() throws {
        let r = try census([:])
        XCTAssertEqual(r.author.total + r.venue.total + r.affiliation.total + r.orgParents.total, 0)
    }

    /// 讀不進來的記錄檔不得靜默少算（Python 版是 traceback；這裡是具名的 exit 3）。
    func testUnreadableRecordRefusesToCountRatherThanUndercount() throws {
        let root = try makeStore(files: ["entities/ok.yaml": work("authors:\n- literal: A\n")])
        try FileManager.default.createDirectory(atPath: root + "/entities/dir.yaml", withIntermediateDirectories: true)
        XCTAssertThrowsError(try LiteralCensus.run(root: root)) {
            guard case .unreadableRecord? = $0 as? LiteralCensus.Failure else { return XCTFail("\($0)") }
            XCTAssertEqual(($0 as? LiteralCensus.Failure)?.exitCode, 3)
        }
    }

    // MARK: - YAML 單行純量解碼

    private func decoded(_ raw: String) -> String {
        String(String.UnicodeScalarView(LiteralCensus.decodeScalar(Array(raw.unicodeScalars)).compactMap(Unicode.Scalar.init)))
    }

    /// 十五種單行寫法，期望值是**真的 YAML 解碼器（Yams）**給的——不是這個檔自己說的。
    /// 一份寫死的期望表會與被測實作一起錯；拿 Yams 當 oracle 是因為 store 本來就是用它讀的。
    func testScalarDecoderAgreesWithYams() throws {
        let cases = [
            "Jacob Cohen", "\"Jacob Cohen\"", "'Jacob Cohen'", "Jacob Cohen  # 尾註", "\"Jacob Cohen\"  # 尾註",
            "\"Cohen, J.\"", "\"a \\\"quoted\\\" name\"", "'it''s'",
            // #407 R63：帶變音符的人名在這個 store 很常見，而 ASCII-safe 的 YAML emitter 會把它們寫成 `\uXXXX`
            "\"Andr\\u00e9 Weil\"", "\"caf\\xe9\"", "\"a\\tb\"",
            // #407 R64：`\U` 是 8 位，非 BMP（CJK 擴充 B、emoji）
            "\"\\U00020000\"",
            // #407 R66：YAML 雙引號純量還有這些跳脫，漏掉會輸出字面的字母
            "\"a\\_b\"", "\"a\\Nb\"", "\"a\\eb\"", "\"a\\vb\"",
        ]
        for raw in cases {
            let node = try XCTUnwrap(try Yams.load(yaml: "literal: \(raw)\n") as? [String: Any], raw)
            XCTAssertEqual(decoded(raw), node["literal"] as? String, "普查的解碼與 Yams 分岔：\(raw)")
        }
    }

    /// 雙引號跳脫表的逐字元對照（`a\Xb`）——表裡漏一個，該字元會輸出字面的字母。
    func testEveryDoubleQuotedEscapeAgreesWithYams() throws {
        for c in "0abtnvfre \"/_NLP\\" {
            let raw = "\"a\\\(c)b\""
            let node = try XCTUnwrap(try Yams.load(yaml: "literal: \(raw)\n") as? [String: Any], raw)
            XCTAssertEqual(decoded(raw), node["literal"] as? String, "跳脫 \\\(c) 與 Yams 分岔")
        }
    }

    func testUnquotedValueStripsSpacesAndAnyStartingWithSpaceHashIsAComment() {
        XCTAssertEqual(decoded("  A   "), "A")
        XCTAssertEqual(decoded("A #c"), "A")
        XCTAssertEqual(decoded("A#b"), "A#b", "`#` 前沒有空白不是註解")
        XCTAssertEqual(decoded("#only comment"), "#only comment", "整個值以 # 開頭不是註解（YAML 上它是註解，但這裡的呼叫端保證值前有 `literal: `）")
        XCTAssertEqual(decoded(""), "")
    }

    /// **已知偏離，釘住而不修**：YAML 的註解前也可以是 tab，這個解碼只認空格（` #`）。與 Python 版相同；
    /// store 的 emitter 不會產出 tab 前綴的註解，所以只有手改的檔會走到。
    func testKnownDeviationTabBeforeCommentIsNotStripped() {
        XCTAssertEqual(decoded("A\t#c"), "A\t#c")
    }

    /// 超出 Unicode 範圍的 `\U` 解成 U+FFFD，不中止（Python 版整支普查 ValueError）；孤立 surrogate 原樣保留為數值。
    func testOutOfRangeAndSurrogateEscapesDoNotCrash() {
        XCTAssertEqual(LiteralCensus.decodeScalar(Array("\"\\UFFFFFFFF\"".unicodeScalars)), [0xFFFD])
        XCTAssertEqual(LiteralCensus.decodeScalar(Array("\"\\ud800\"".unicodeScalars)), [0xD800])
    }

    /// 不完整的跳脫（位數不足）落到 fallback：輸出字面的字母，與 Python 版同。
    func testIncompleteEscapesFallBackToTheLiteralLetter() {
        XCTAssertEqual(decoded("\"\\u12\""), "u12")
        XCTAssertEqual(decoded("\"\\xZ1\""), "xZ1")
        XCTAssertEqual(decoded("\"trailing\\"), "trailing\\")
    }

    // MARK: - 呈現

    private func render(_ marker: LiteralCensus.MarkerState, author: LiteralCensus.Domain = .init(),
                        venue: LiteralCensus.Domain = .init()) -> [String] {
        var r = LiteralCensus.Report(root: "/x", marker: marker, supported: 21)
        r.author = author; r.venue = venue
        return LiteralCensus.render(r, displayRoot: "~/s")
    }

    private func dom(key: Int, literal: Int) -> LiteralCensus.Domain {
        var d = LiteralCensus.Domain(); d.key = key; d.literal = literal
        for i in 0..<literal { d.distinct.insert([UInt32(i)]) }
        return d
    }

    func testRowLayout() {
        let lines = render(.read(12), author: dom(key: 1, literal: 3), venue: dom(key: 0, literal: 1))
        XCTAssertEqual(lines[0], "store: ~/s（format 12）")
        XCTAssertEqual(lines[1], "author         總邊     4｜literal 邊 3（佔 75.0%）｜key 1｜distinct literal 3")
        XCTAssertEqual(lines[2], "venue          總邊     1｜literal 邊 1（佔 100.0%）｜key 0｜distinct literal 1")
        XCTAssertEqual(lines[3], "affiliation    總邊     0｜literal 邊 0（佔 —）｜key 0｜distinct literal 0")
        XCTAssertEqual(lines[4], "org-parents    總邊     0｜literal 邊 0（佔 —）｜key 0｜distinct literal 0")
    }

    /// 缺席與零必須可區分：venue 域在版號 < 11 且零 venue 邊時印「未部署」，不是 0。
    func testVenueNotDeployedIsNotZero() {
        let fmt10 = render(.read(10), author: dom(key: 1, literal: 0))
        XCTAssertTrue(fmt10[2].hasPrefix("venue          未部署（marker 說 format 10，< 11"), fmt10[2])
        let absent = render(.absent, author: dom(key: 1, literal: 0))
        XCTAssertTrue(absent[0].contains("format 1（無 store.yaml；讀端語意：缺檔即 format 1）"))
        XCTAssertTrue(absent[2].hasPrefix("venue          未部署（無 store.yaml ＝ format 1"), absent[2])
    }

    /// 已部署（≥ 11）而零 venue 邊是真的零，照常印列。
    func testDeployedStoreWithZeroVenueEdgesPrintsARealZeroRow() {
        XCTAssertEqual(render(.read(12))[2], "venue          總邊     0｜literal 邊 0（佔 —）｜key 0｜distinct literal 0")
    }

    /// 量到就印，format 與量測不一致時把不一致報出來（不是拿推論蓋掉量測）。
    func testMeasuredVenueEdgesWithAnOlderMarkerReportTheInconsistency() {
        let l10 = render(.read(10), venue: dom(key: 0, literal: 1))
        XCTAssertTrue(l10[2].hasPrefix("venue          總邊     1"))
        XCTAssertTrue(l10[3].contains("marker 說 format 10（< 11"), l10[3])
        let absent = render(.absent, venue: dom(key: 0, literal: 1))
        XCTAssertTrue(absent[3].contains("沒有 store.yaml——讀端把這種 store 當 format 1"), "缺檔時不能說「marker 說」：\(absent[3])")
        XCTAssertFalse(absent[3].contains("marker 說"))
    }

    /// marker 壞到讀端會整體拒開時，**每一列**都掛全域警告，不只 venue（author 才是終局量測）。
    func testUnopenableStoreCarriesAGlobalWarningBeforeEveryRow() {
        for marker in [LiteralCensus.MarkerState.malformed(detail: "(未知的頂層行)"), .unreadable(detail: "(EACCES)"), .read(22)] {
            let lines = render(marker, author: dom(key: 1, literal: 1))
            XCTAssertTrue(lines[1].contains("⚠ 讀端會整體拒開此 store"), "\(marker)：\(lines[1])")
            XCTAssertTrue(lines[2].hasPrefix("author"), "警告要排在第一列之前")
        }
        XCTAssertFalse(render(.read(12))[1].contains("⚠"))
    }

    func testTooNewLabelNamesTheBinaryCeiling() {
        let first = render(.read(22))[0]
        XCTAssertTrue(first.contains("format 22——**超過你的 binary 支援上限 21**"), first)
        XCTAssertTrue(first.contains("它會整體拒開此 store"))
    }

    func testZeroVenueEdgesWithABrokenMarkerIsUnknownNotDeployedNorZero() {
        let venue = render(.malformed(detail: "(未知的頂層行)"))[3]
        XCTAssertTrue(venue.hasPrefix("venue          **未知**（"), venue)
        XCTAssertTrue(venue.contains("無法區分「未部署」與「已部署但為 0」"))
        XCTAssertTrue(render(.unreadable(detail: "(是目錄)"))[3].hasPrefix("venue          **未知**（"))
    }

    func testMeasuredVenueEdgesWithABrokenMarkerSayTheMarkerSaysNothing() {
        let lines = render(.malformed(detail: "(x)"), venue: dom(key: 0, literal: 1))
        XCTAssertTrue(lines[3].hasPrefix("venue          總邊     1"))
        XCTAssertTrue(lines[4].contains("marker 讀不出版號"), lines[4])
    }

    // MARK: - tilde

    /// 路徑縮寫比到路徑邊界，不是裸前綴：HOME=/home/ann 時 /home/anna/x 不得變成 ~a/x。
    func testTildeShrinksOnlyAtPathBoundaries() {
        XCTAssertEqual(LiteralCensus.tilde("/home/ann/.akashic", home: "/home/ann"), "~/.akashic")
        XCTAssertEqual(LiteralCensus.tilde("/home/ann", home: "/home/ann"), "~")
        XCTAssertEqual(LiteralCensus.tilde("/home/anna/x", home: "/home/ann"), "/home/anna/x")
        XCTAssertEqual(LiteralCensus.tilde("/tmp/x", home: "/home/ann/"), "/tmp/x")
        XCTAssertEqual(LiteralCensus.tilde("/home/ann/x", home: "/home/ann/"), "~/x")
    }
}
