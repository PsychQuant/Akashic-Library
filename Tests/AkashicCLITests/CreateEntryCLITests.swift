import XCTest
@testable import AkashicCore
@testable import AkashicStoreIO
@testable import akashic

/// #206：CLI 的無損建檔入口。
///
/// **走真 binary**。這個 change 的價值全部在**出口面**——「CLI 使用者能不能無損
/// 匯入」是關於 `akashic create-entry` 這支命令存不存在、吃不吃得下那兩種格式。
/// 只測 library 層等於沒測到那句主張。
final class CreateEntryCLITests: XCTestCase {
    var root: URL!

    private var productsDirectory: URL {
        for bundle in Bundle.allBundles where bundle.bundlePath.hasSuffix(".xctest") {
            return bundle.bundleURL.deletingLastPathComponent()
        }
        fatalError("找不到 products directory")
    }

    private func runCLI(_ args: [String], stdin: String? = nil) throws -> (status: Int32, out: String) {
        let p = Process()
        p.executableURL = productsDirectory.appendingPathComponent("akashic")
        p.arguments = args + ["--library", root.path]
        // AKASHIC_* 無條件剝除——沙箱紀律，不得讀到開發機的真實 store
        p.environment = ProcessInfo.processInfo.environment.filter { !$0.key.hasPrefix("AKASHIC_") }
        let o = Pipe(), e = Pipe()
        p.standardOutput = o; p.standardError = e
        if let stdin {
            let i = Pipe()
            p.standardInput = i
            try p.run()
            i.fileHandleForWriting.write(Data(stdin.utf8))
            i.fileHandleForWriting.closeFile()
        } else {
            try p.run()
        }
        let od = o.fileHandleForReading.readDataToEndOfFile()
        let ed = e.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return (p.terminationStatus,
                String(decoding: od, as: UTF8.self) + String(decoding: ed, as: UTF8.self))
    }

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("akashic-ce-\(UUID().uuidString)")
        try LibraryStore(root: root).ensureLayout()
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func loadedEntries() throws -> [Entry] {
        try LibraryStore(root: root).load().entries
    }

    // MARK: - JSON

    func testJSONKeepsEveryField() throws {
        let json = """
        {"type":"conference-session","title":"Validity Evidence for the Joint Thurstonian Models",
         "authors":["Che Cheng","Hau-Hung Yang"],"date":"2026",
         "fields":{"eventtitle":"IMPS 2026","venue":"Seoul, South Korea",
                   "eventdate":"2026-07-20/2026-07-24","titleaddon":"Oral presentation"}}
        """
        let r = try runCLI(["create-entry", "--format", "json"], stdin: json)
        XCTAssertEqual(r.status, 0, r.out)
        let e = try XCTUnwrap(loadedEntries().first)
        XCTAssertEqual(e.type.rawValue, "conference-session")
        // **四個欄位一個都不能少**——這正是 import-wos 會丟掉的那一族
        XCTAssertEqual(e.fields["eventtitle"], "IMPS 2026")
        XCTAssertEqual(e.fields["venue"], "Seoul, South Korea")
        XCTAssertEqual(e.fields["eventdate"], "2026-07-20/2026-07-24")
        XCTAssertEqual(e.fields["titleaddon"], "Oral presentation")
        XCTAssertEqual(e.authors.count, 2)
    }

    /// 陣列形式：一次多筆。
    func testJSONArrayCreatesAll() throws {
        let json = """
        [{"type":"report","title":"A","fields":{"institution":"NSTC"}},
         {"type":"thesis","title":"B","fields":{"institution":"NTU"}}]
        """
        let r = try runCLI(["create-entry", "--format", "json"], stdin: json)
        XCTAssertEqual(r.status, 0, r.out)
        XCTAssertEqual(try loadedEntries().count, 2)
    }

    // MARK: - .bib

    func testBibKeepsEveryField() throws {
        let bib = """
        @PRESENTATION{cheng_imps_2026,
          AUTHOR = {Cheng, Che and Yang, Hau-Hung},
          TITLE = {Validity Evidence},
          EVENTTITLE = {IMPS 2026},
          VENUE = {Seoul, South Korea},
          EVENTDATE = {2026-07-20/2026-07-24},
          DATE = 2026,
        }
        """
        let r = try runCLI(["create-entry", "--format", "bib"], stdin: bib)
        XCTAssertEqual(r.status, 0, r.out)
        let e = try XCTUnwrap(loadedEntries().first)
        XCTAssertEqual(e.fields["eventtitle"], "IMPS 2026")
        XCTAssertEqual(e.fields["venue"], "Seoul, South Korea")
        XCTAssertEqual(e.fields["eventdate"], "2026-07-20/2026-07-24")
        XCTAssertNil(e.fields["title"], "title 抽成一級欄位，不得在 fields 重複")
        XCTAssertNil(e.fields["author"], "author 同上")
    }

    /// **`Family, Given` 要翻成 `Given Family`**，否則 citekey 取到名字當姓。
    /// 實測：不翻的話 `Terada, Yoshikazu` 會產出 `yoshikazu…`。
    func testBibAuthorOrderIsFlippedSoCitekeyUsesFamilyName() throws {
        let bib = """
        @ARTICLE{t,
          AUTHOR = {Terada, Yoshikazu},
          TITLE = {Statistical Something},
          DATE = 2024,
        }
        """
        let r = try runCLI(["create-entry", "--format", "bib"], stdin: bib)
        XCTAssertEqual(r.status, 0, r.out)
        let e = try XCTUnwrap(loadedEntries().first)
        XCTAssertTrue(e.citekey.hasPrefix("terada"),
                      "citekey 應以姓開頭，實際 \(e.citekey)")
        if case let .literal(n) = e.authors[0] {
            XCTAssertEqual(n, "Yoshikazu Terada")
        } else { XCTFail("作者應為 literal") }
    }

    /// 機構名的 `{...}` 標記不得被當成 `Family, Given` 切開（#6 的既有約定）。
    func testCorporateAuthorIsNotFlipped() throws {
        let bib = """
        @REPORT{w,
          AUTHOR = {{World Health Organization, Europe}},
          TITLE = {A Report},
          DATE = 2020,
        }
        """
        let r = try runCLI(["create-entry", "--format", "bib"], stdin: bib)
        XCTAssertEqual(r.status, 0, r.out)
        let e = try XCTUnwrap(loadedEntries().first)
        if case let .literal(n) = e.authors[0] {
            XCTAssertTrue(n.contains("World Health Organization"),
                          "機構名不得被切開重組，實際 \(n)")
            XCTAssertFalse(n.hasPrefix("Europe"), "被當成 Given 提前了：\(n)")
        } else { XCTFail("作者應為 literal") }
    }

    // MARK: - 邊界

    /// **零筆不得靜默。**「解析成功但一筆都沒有」與「格式沒被辨識」是兩件事，
    /// 而使用者從 exit 0 + 無輸出分不出來。
    func testZeroParsedIsAnError() throws {
        let r = try runCLI(["create-entry", "--format", "bib"], stdin: "not a bib file at all")
        XCTAssertNotEqual(r.status, 0, "零筆必須非零退出：\(r.out)")
        XCTAssertTrue(r.out.contains("0 筆"), r.out)
    }

    /// `--dry-run` 零寫入。
    func testDryRunWritesNothing() throws {
        let json = #"{"type":"webpage","title":"X","fields":{"note":"n"}}"#
        let r = try runCLI(["create-entry", "--format", "json", "--dry-run"], stdin: json)
        XCTAssertEqual(r.status, 0, r.out)
        XCTAssertTrue(r.out.contains("dry-run"), r.out)
        XCTAssertEqual(try loadedEntries().count, 0, "dry-run 不得寫入")
    }

    // MARK: - verify 找到的洞（#206 verify C1/C2/C3/H3/M3/M5/M6）

    /// **C1**：JSON 路徑的鍵沒過 `FieldKey`，於是帶空格／數字開頭的鍵原樣落進
    /// store，`export-bib` 產出的整份 `.bib` biber 解析不了（一筆壞鍵 → 完全不
    /// 產出檔）。修在 `AkashicService.createEntry`——那是 CLI 與 MCP 唯一的交會點，
    /// 補在任一呼叫端都會留下另一個洞。
    func testIllegalFieldKeyIsRejectedNotStored() throws {
        let json = #"{"type":"periodical-article","title":"K","fields":{"Research Areas":"Psychology"}}"#
        let r = try runCLI(["create-entry", "--format", "json"], stdin: json)
        // 拒寫或正規化都可接受；**原樣存進去不行**
        let stored = try loadedEntries().first?.fields.keys.sorted() ?? []
        XCTAssertFalse(stored.contains("Research Areas"),
                       "帶空格的鍵不得原樣入庫（會讓整份 export-bib 解析不了）：\(stored) / \(r.out)")
    }

    /// 同上的數字開頭形狀。WoS 真的有一欄叫 `29 Character Source Abbreviation`。
    func testDigitLeadingFieldKeyIsNotStoredRaw() throws {
        let json = #"{"type":"periodical-article","title":"K2","fields":{"29 Char Abbrev":"PSYCH"}}"#
        _ = try runCLI(["create-entry", "--format", "json"], stdin: json)
        let stored = try loadedEntries().first?.fields.keys.sorted() ?? []
        XCTAssertFalse(stored.contains(where: { $0.first?.isNumber == true }),
                       "數字開頭的鍵不得入庫：\(stored)")
    }

    /// **C2**：`as? [String]` 在任一元素非字串時整個陣列失敗 → 靜默零作者。
    /// 現在必須**報錯**，不得 exit 0 悄悄少人。
    func testMixedTypeAuthorsIsAnErrorNotSilentLoss() throws {
        let json = #"{"type":"periodical-article","title":"A","authors":["Che Cheng","Hau-Hung Yang",2025]}"#
        let r = try runCLI(["create-entry", "--format", "json"], stdin: json)
        XCTAssertNotEqual(r.status, 0, "形狀不符必須報錯：\(r.out)")
        XCTAssertEqual(try loadedEntries().count, 0, "報錯就不該寫進去")
    }

    /// CSL-JSON 的作者物件是最可能的貼上來源之一——不得靜默全滅。
    func testCSLStyleAuthorObjectsAreRejectedLoudly() throws {
        let json = #"{"type":"periodical-article","title":"A","authors":[{"family":"Cheng","given":"Che"}]}"#
        let r = try runCLI(["create-entry", "--format", "json"], stdin: json)
        XCTAssertNotEqual(r.status, 0, r.out)
        XCTAssertTrue(r.out.contains("CSL-JSON") || r.out.contains("authors"), r.out)
    }

    /// `"date": 2025`（JSON 數字）很常見——原本會靜默沒有 date，citekey 退化成 `nd`。
    func testNumericDateIsAcceptedNotDropped() throws {
        let json = #"{"type":"periodical-article","title":"Numeric Date","authors":["Che Cheng"],"date":2025}"#
        let r = try runCLI(["create-entry", "--format", "json"], stdin: json)
        XCTAssertEqual(r.status, 0, r.out)
        let e = try XCTUnwrap(loadedEntries().first)
        XCTAssertEqual(e.date, "2025")
        XCTAssertFalse(e.citekey.contains("nd"), "date 掉了會讓 citekey 變 nd：\(e.citekey)")
    }

    /// **M5**：JSON `null` 不得寫成字面 `<null>`——來源說「沒有值」，
    /// 寫進一個值是**捏造**。
    func testJSONNullIsSkippedNotFabricated() throws {
        let json = #"{"type":"periodical-article","title":"N","fields":{"note":null,"doi":"10.1/x"}}"#
        let r = try runCLI(["create-entry", "--format", "json"], stdin: json)
        XCTAssertEqual(r.status, 0, r.out)
        let e = try XCTUnwrap(loadedEntries().first)
        XCTAssertNil(e.fields["note"], "null 不得變成值")
        XCTAssertNotEqual(e.fields["note"], "<null>")
        XCTAssertEqual(e.fields["doi"], "10.1/x")
    }

    /// **C3**：`{Barnes and Noble Publishing}` 被 `" and "` 切成兩半、再各自翻面，
    /// store 裡留下不平衡的大括號。原本的測試用
    /// `{{World Health Organization, Europe}}`——**不含 `" and "`**，從沒碰到這條路。
    func testCorporateNameWithAndIsNotSplit() throws {
        let bib = """
        @BOOK{bn,
          AUTHOR = {{Barnes and Noble Publishing}},
          TITLE = {A Corporate Book},
          DATE = 2020,
        }
        """
        let r = try runCLI(["create-entry", "--format", "bib"], stdin: bib)
        XCTAssertEqual(r.status, 0, r.out)
        let e = try XCTUnwrap(loadedEntries().first)
        XCTAssertEqual(e.authors.count, 1, "機構名不得被 \" and \" 切開：\(e.authors)")
        if case let .literal(n) = e.authors[0] {
            XCTAssertTrue(n.contains("Barnes and Noble Publishing"), n)
            // 大括號必須平衡，否則 round-trip 匯出會壞
            XCTAssertEqual(n.filter { $0 == "{" }.count, n.filter { $0 == "}" }.count,
                           "大括號不平衡：\(n)")
        } else { XCTFail("作者應為 literal") }
    }

    /// 真人作者與機構名混在同一個 AUTHOR 欄。
    func testMixedHumanAndCorporateAuthors() throws {
        let bib = """
        @REPORT{m,
          AUTHOR = {Cheng, Che and {Ministry of Health and Welfare}},
          TITLE = {Mixed},
          DATE = 2021,
        }
        """
        let r = try runCLI(["create-entry", "--format", "bib"], stdin: bib)
        XCTAssertEqual(r.status, 0, r.out)
        let names = try loadedEntries().first!.authors.map { a -> String in
            if case let .literal(n) = a { return n } else { return "" }
        }
        XCTAssertEqual(names.count, 2, "應為 2 位（人 + 機構）：\(names)")
        XCTAssertEqual(names[0], "Che Cheng")
        XCTAssertTrue(names[1].contains("Ministry of Health and Welfare"), names[1])
    }

    /// **M6**：`Family, Suffix, Given` — biblatex 的 `{Smith, Jr., John}`
    /// 意思是「John Smith Jr.」。原本 `maxSplits: 1` 讀成 `Jr., John` + `Smith`。
    func testFamilySuffixGivenIsReorderedCorrectly() {
        XCTAssertEqual(CreateEntryCmd.flipFamilyGiven("Smith, Jr., John"), "John Smith Jr.")
        XCTAssertEqual(CreateEntryCmd.flipFamilyGiven("Cheng, Che"), "Che Cheng")
        XCTAssertEqual(CreateEntryCmd.flipFamilyGiven("Che Cheng"), "Che Cheng")
        // 四段以上不猜——原樣比重組錯誤好
        XCTAssertEqual(CreateEntryCmd.flipFamilyGiven("a, b, c, d"), "a, b, c, d")
    }

    /// **H3**：全部寫入失敗仍 exit 0——`create-entry … && next` 會照常往下走。
    /// 同一支命令對「解析出 0 筆」刻意非零退出，理由正是 script 分不出成功與沉默。
    func testAllWritesFailingExitsNonZero() throws {
        // type 空字串 → service 拒絕；解析得出 1 筆但寫成 0 筆
        let json = #"[{"type":"","title":"X"}]"#
        let r = try runCLI(["create-entry", "--format", "json"], stdin: json)
        XCTAssertNotEqual(r.status, 0, "寫成 0 筆必須非零退出：\(r.out)")
    }

    /// **M3**：`.bib` 路徑的 `FieldKey` 整合原本零覆蓋——所有 fixture 都用已合法的
    /// 鍵（`EVENTTITLE`／`VENUE`），拿掉那次正規化呼叫，1169 條全綠。
    func testBibPathNormalizesIllegalKeys() throws {
        let bib = """
        @ARTICLE{k,
          TITLE = {T},
          AUTHOR = {Cheng, Che},
          DATE = 2025,
          RESEARCH_AREAS = {Psychology},
        }
        """
        let r = try runCLI(["create-entry", "--format", "bib"], stdin: bib)
        XCTAssertEqual(r.status, 0, r.out)
        let keys = try XCTUnwrap(loadedEntries().first).fields.keys.sorted()
        XCTAssertTrue(keys.allSatisfy { $0.first?.isLetter == true },
                      "所有鍵必須字母開頭：\(keys)")
        XCTAssertTrue(keys.allSatisfy { !$0.contains(" ") }, "鍵不得含空格：\(keys)")
    }

    // MARK: - #207 未終止的 entry

    /// **半筆比缺欄位更糟**：它讓「這筆記錄只有兩個欄位」與「這個檔案壞了」
    /// 變成同一個觀察。`BibParser` 的收集迴圈在 EOF 時退出但仍呼叫 `parseEntry`，
    /// 於是截斷檔靜默產出半筆、exit 0。
    func testUnterminatedEntryIsRefused() throws {
        let bib = """
        @ARTICLE{complete2025,
          AUTHOR = {Cheng, Che},
          TITLE = {A Complete Entry},
          DATE = 2025,
        }

        @PRESENTATION{truncated2026,
          AUTHOR = {Cheng, Che},
          TITLE = {Cut Off Halfway},
          EVENTTITLE = {IMPS 2026},
        """
        let r = try runCLI(["create-entry", "--format", "bib"], stdin: bib)
        XCTAssertNotEqual(r.status, 0, "截斷檔必須被拒絕：\(r.out)")
        XCTAssertTrue(r.out.contains("truncated2026"), "訊息要指出是哪一筆：\(r.out)")
        XCTAssertEqual(try loadedEntries().count, 0, "**拒絕整份**——不得只收前面完整的那筆")
    }

    /// 完整檔不得誤擋。含大括號的合法值（保護大小寫、機構名）照常通過。
    func testCompleteFileWithBracesIsNotFalselyRefused() throws {
        let bib = """
        @ARTICLE{ok2025,
          AUTHOR = {{World Health Organization}},
          TITLE = {A Study of {DNA} Sequencing},
          DATE = 2025,
        }
        """
        let r = try runCLI(["create-entry", "--format", "bib"], stdin: bib)
        XCTAssertEqual(r.status, 0, r.out)
        XCTAssertEqual(try loadedEntries().count, 1)
    }

    /// 註解行不參與大括號計數。
    ///
    /// **這是防禦性的，不是對已觀察資料的回應**——實測真實 CV（43 筆）的註解行
    /// **0 條**大括號不平衡（檔頭那些 `% - Journal Articles (type = {Journal Article})`
    /// 都是平衡的，計不計都一樣）。
    ///
    /// 所以 fixture 用一條**刻意不平衡**的註解：那是這個 skip 唯一會起作用的
    /// 形狀，也是唯一能讓 mutation 見紅的形狀。用平衡的註解寫這條測試（第一版
    /// 的作法）看起來合理，但拿掉 skip 之後照樣全綠——測不到它要測的東西。
    func testUnbalancedBraceInCommentDoesNotCauseFalseRefusal() throws {
        let bib = """
        % TODO: 這裡原本想寫 { 但沒寫完
        @ARTICLE{ok,
          TITLE = {T},
          AUTHOR = {Cheng, Che},
          DATE = 2025,
        }
        """
        let r = try runCLI(["create-entry", "--format", "bib"], stdin: bib)
        XCTAssertEqual(r.status, 0, "註解裡的大括號不得造成誤擋：\(r.out)")
        XCTAssertEqual(try loadedEntries().count, 1)
    }

    /// 這支命令必須真的註冊在 CLI 上——`--help` 看得到它。
    /// （少了註冊那一行，上面所有測試會以「找不到命令」的形式失敗，但那個訊息
    /// 指向的是別的問題；這條讓根因直接可讀。）
    func testCommandIsRegistered() throws {
        let r = try runCLI(["--help"])
        XCTAssertTrue(r.out.contains("create-entry"), "create-entry 未註冊：\(r.out)")
    }
}

// MARK: - 批次語意（#455）：陣列一次呼叫 createEntries；可預期的失敗整批擋、零寫入

extension CreateEntryCLITests {
    /// 三筆陣列：三行 JSON＋`✓ created 3`，三筆都落地。
    func testJSONArrayCreatesAllInOneBatch() throws {
        let json = """
        [{"type":"periodical-article","title":"Batch one","authors":["Some Author"],"date":"2024"},
         {"type":"periodical-article","title":"Batch two","authors":["Some Author"],"date":"2024"},
         {"type":"periodical-article","title":"Batch three","authors":["Some Author"],"date":"2024"}]
        """
        let r = try runCLI(["create-entry", "--format", "json"], stdin: json)
        XCTAssertEqual(r.status, 0, r.out)
        XCTAssertTrue(r.out.contains("✓ created 3"), r.out)
        XCTAssertEqual(Set(try loadedEntries().map(\.citekey)),
                       ["author2024batch", "author2024bbatch", "author2024cbatch"], r.out)
    }

    /// 兩筆合法＋一筆 type 不在值域：exit 非零、**零檔案**（先前逐筆迴圈會把前兩筆寫進去）。
    func testJSONArrayWithOnePredictableFailureWritesNothing() throws {
        let json = """
        [{"type":"periodical-article","title":"Good one","authors":["Some Author"],"date":"2024"},
         {"type":"periodical-article","title":"Good two","authors":["Some Author"],"date":"2024"},
         {"type":"not-a-type","title":"Bad type","authors":["Some Author"],"date":"2024"}]
        """
        let r = try runCLI(["create-entry", "--format", "json"], stdin: json)
        XCTAssertNotEqual(r.status, 0, r.out)
        XCTAssertTrue(r.out.contains("第 3 筆") && r.out.contains("Bad type"), r.out)
        let keys = try loadedEntries().map(\.citekey)
        XCTAssertTrue(keys.isEmpty, "可預期的失敗：整批零寫入。實際：\(keys)")
    }
}
