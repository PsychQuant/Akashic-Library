import XCTest
@testable import AkashicCore
@testable import AkashicStoreIO

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
        {"type":"presentation","title":"Validity Evidence for the Joint Thurstonian Models",
         "authors":["Che Cheng","Hau-Hung Yang"],"date":"2026",
         "fields":{"eventtitle":"IMPS 2026","venue":"Seoul, South Korea",
                   "eventdate":"2026-07-20/2026-07-24","titleaddon":"Oral presentation"}}
        """
        let r = try runCLI(["create-entry", "--format", "json"], stdin: json)
        XCTAssertEqual(r.status, 0, r.out)
        let e = try XCTUnwrap(loadedEntries().first)
        XCTAssertEqual(e.type, "presentation")
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
        let json = #"{"type":"misc","title":"X","fields":{"note":"n"}}"#
        let r = try runCLI(["create-entry", "--format", "json", "--dry-run"], stdin: json)
        XCTAssertEqual(r.status, 0, r.out)
        XCTAssertTrue(r.out.contains("dry-run"), r.out)
        XCTAssertEqual(try loadedEntries().count, 0, "dry-run 不得寫入")
    }

    /// 這支命令必須真的註冊在 CLI 上——`--help` 看得到它。
    /// （少了註冊那一行，上面所有測試會以「找不到命令」的形式失敗，但那個訊息
    /// 指向的是別的問題；這條讓根因直接可讀。）
    func testCommandIsRegistered() throws {
        let r = try runCLI(["--help"])
        XCTAssertTrue(r.out.contains("create-entry"), "create-entry 未註冊：\(r.out)")
    }
}
