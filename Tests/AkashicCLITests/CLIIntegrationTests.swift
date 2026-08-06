import XCTest

/// CLI end-to-end：跑編譯出的 akashic binary，走 temp library 全流程。
/// import-zotero 的資料邏輯已由 AkashicKitTests 覆蓋；這裡驗證 CLI 佈線。
final class CLIIntegrationTests: XCTestCase {
    var libraryRoot: URL!

    /// swift test 產物目錄（akashic binary 所在）。
    private var productsDirectory: URL {
        for bundle in Bundle.allBundles where bundle.bundlePath.hasSuffix(".xctest") {
            return bundle.bundleURL.deletingLastPathComponent()
        }
        fatalError("找不到 products directory")
    }

    override func setUpWithError() throws {
        libraryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("akashic-cli-\(UUID().uuidString)")
        let entries = libraryRoot.appendingPathComponent("entries")
        let people = libraryRoot.appendingPathComponent("people")
        try FileManager.default.createDirectory(at: entries, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: people, withIntermediateDirectories: true)

        try """
        id: 7C1F6C2E-0000-0000-0000-000000000001
        citekey: cheng2025identifiability
        type: article
        title: Identifiability of polychoric models
        authors:
          - key: cheng-che
        date: "2025"
        fields:
          journaltitle: Psychometrika
        akashic:
          relations:
            cites:
              - olsson1979maximum
        """.write(to: entries.appendingPathComponent("cheng2025identifiability.yaml"),
                  atomically: true, encoding: .utf8)

        try """
        id: 7C1F6C2E-0000-0000-0000-000000000002
        citekey: olsson1979maximum
        type: article
        title: Maximum likelihood estimation of the polychoric correlation
        authors:
          - literal: Che Cheng
        date: "1979"
        fields:
          journaltitle: Psychometrika
        """.write(to: entries.appendingPathComponent("olsson1979maximum.yaml"),
                  atomically: true, encoding: .utf8)

        try """
        key: cheng-che
        names:
          - Che Cheng
          - 鄭澈
        """.write(to: people.appendingPathComponent("cheng-che.yaml"),
                  atomically: true, encoding: .utf8)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: libraryRoot)
    }

    @discardableResult
    private func runCLI(_ args: [String],
                        env: [String: String]? = nil) throws -> (status: Int32, stdout: String, stderr: String) {
        let process = Process()
        process.executableURL = productsDirectory.appendingPathComponent("akashic")
        process.arguments = args
        // **一律先清掉所有 AKASHIC_* 再注入**（#101 verify R1/R2）。
        //
        // 只注入 `AKASHIC_HOME` 不夠：`LibraryLocator.resolveDetailed` 的順序是
        // explicit → `$AKASHIC_LIBRARY` → registry，所以省略 `--library` 的測試在**有設
        // 該變數的開發機上**會跑去打使用者的真實 store（並在那裡重建 index）。
        //
        // R2 抓到第一版把這段包在 `if let env` 裡——於是**不帶 env 的呼叫完全沒被保護**，
        // 而那正是註解描述的危險案例。剝除必須無條件；繼承父環境的其餘變數（PATH 等）仍需要。
        var childEnv = ProcessInfo.processInfo.environment.filter { !$0.key.hasPrefix("AKASHIC_") }
        for (k, v) in env ?? [:] { childEnv[k] = v }
        process.environment = childEnv
        let out = Pipe(), err = Pipe()
        process.standardOutput = out
        process.standardError = err
        try process.run()
        process.waitUntilExit()
        let stdout = String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        let stderr = String(decoding: err.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        return (process.terminationStatus, stdout, stderr)
    }

    private var lib: [String] { ["--library", libraryRoot.path] }

    func testDoctorBuildsIndexAndReports() throws {
        let result = try runCLI(["doctor"] + lib)
        XCTAssertEqual(result.status, 0, result.stderr)
        XCTAssertTrue(result.stdout.contains("entries: 2"), result.stdout)
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: libraryRoot.appendingPathComponent(".akashic/index.sqlite").path))
    }

    func testValidatePassesOnCleanLibrary() throws {
        let result = try runCLI(["validate"] + lib)
        XCTAssertEqual(result.status, 0, result.stderr)
    }

    // #23 tolerant-preserve E2E（verify R1 F5）：較新 schema 的 person 檔——
    // validate 給 warning 但 exit 0（availability 優先）、doctor 列 unknown-field files
    func testValidateToleratesFutureSchemaWithWarning() throws {
        try """
        key: future-one
        names:
          - Future One
        affiliations:
          - organization: ISS
        """.write(to: libraryRoot.appendingPathComponent("people/future-one.yaml"),
                  atomically: true, encoding: .utf8)
        let result = try runCLI(["validate"] + lib)
        XCTAssertEqual(result.status, 0, result.stderr)
        XCTAssertTrue(result.stdout.contains("未知欄位「affiliations」"), result.stdout)
        let doctor = try runCLI(["doctor"] + lib)
        XCTAssertTrue(doctor.stdout.contains("unknown-field files: 1"), doctor.stdout)
    }

    func testValidateFailsOnQuarantine() throws {
        try "not: a valid entry\n".write(
            to: libraryRoot.appendingPathComponent("entries/broken.yaml"),
            atomically: true, encoding: .utf8)
        let result = try runCLI(["validate"] + lib)
        XCTAssertNotEqual(result.status, 0)
        XCTAssertTrue((result.stdout + result.stderr).contains("broken.yaml"))
    }

    func testQueryByJournal() throws {
        _ = try runCLI(["doctor"] + lib)
        let result = try runCLI(["query", "--journal", "Psychometrika"] + lib)
        XCTAssertEqual(result.status, 0, result.stderr)
        XCTAssertTrue(result.stdout.contains("cheng2025identifiability"))
        XCTAssertTrue(result.stdout.contains("olsson1979maximum"))
    }

    func testQueryJSONOutput() throws {
        _ = try runCLI(["doctor"] + lib)
        let result = try runCLI(["query", "--cites-of", "cheng2025identifiability", "--json"] + lib)
        XCTAssertEqual(result.status, 0, result.stderr)
        let parsed = try JSONSerialization.jsonObject(with: Data(result.stdout.utf8)) as! [[String: Any]]
        XCTAssertEqual(parsed.count, 1)
        XCTAssertEqual(parsed[0]["citekey"] as? String, "olsson1979maximum")
    }

    func testGraphMermaid() throws {
        _ = try runCLI(["doctor"] + lib)
        let result = try runCLI(
            ["graph", "--focus", "cheng2025identifiability", "--depth", "1"] + lib)
        XCTAssertEqual(result.status, 0, result.stderr)
        XCTAssertTrue(result.stdout.hasPrefix("graph LR"))
        XCTAssertTrue(result.stdout.contains("cites"))
    }

    func testExportBib() throws {
        let result = try runCLI(["export-bib"] + lib)
        XCTAssertEqual(result.status, 0, result.stderr)
        XCTAssertTrue(result.stdout.contains("@ARTICLE{cheng2025identifiability,"))
        XCTAssertTrue(result.stdout.contains("AUTHOR = {Cheng, Che}"))   // key 作者經 people 還原
    }

    func testResolvePeopleListsAndApplies() throws {
        let list = try runCLI(["resolve-people"] + lib)
        XCTAssertEqual(list.status, 0, list.stderr)
        XCTAssertTrue(list.stdout.contains("olsson1979maximum"))
        XCTAssertTrue(list.stdout.contains("cheng-che"))

        let apply = try runCLI(["resolve-people", "--apply"] + lib)
        XCTAssertEqual(apply.status, 0, apply.stderr)
        let yaml = try String(contentsOf: libraryRoot
            .appendingPathComponent("entries/olsson1979maximum.yaml"), encoding: .utf8)
        XCTAssertTrue(yaml.contains("key: cheng-che"))
    }

    func testMissingLibraryFailsLoud() throws {
        let result = try runCLI(["doctor", "--library", "/nonexistent/path"])
        XCTAssertNotEqual(result.status, 0)
    }
}

extension CLIIntegrationTests {
    func testRenameCommandMigratesReferences() throws {
        // cheng2025identifiability 被 olsson… 引用？fixture 反向：cheng cites olsson
        let result = try runCLI(["rename", "olsson1979maximum", "olsson1979bmaximum"] + lib)
        XCTAssertEqual(result.status, 0, result.stderr)
        let citing = try String(contentsOf: libraryRoot
            .appendingPathComponent("entries/cheng2025identifiability.yaml"), encoding: .utf8)
        XCTAssertTrue(citing.contains("olsson1979bmaximum"))   // cites 引用跟改
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: libraryRoot.appendingPathComponent("entries/olsson1979maximum.yaml").path))
    }
}

/// #13 多 library：CLI library 子指令 + query --library。
extension CLIIntegrationTests {
    func testLibraryLifecycleAndQueryFilter() throws {
        // create + list
        var r = try runCLI(["library", "create", "sinica", "--name", "中研院"] + lib)
        XCTAssertEqual(r.status, 0, r.stderr)
        r = try runCLI(["library", "list"] + lib)
        XCTAssertEqual(r.status, 0, r.stderr)
        XCTAssertTrue(r.stdout.contains("sinica"), r.stdout)
        XCTAssertTrue(r.stdout.contains("中研院"), r.stdout)

        // add membership + query filter
        r = try runCLI(["library", "add", "sinica", "cheng2025identifiability"] + lib)
        XCTAssertEqual(r.status, 0, r.stderr)
        r = try runCLI(["query", "--in-library", "sinica"] + lib)
        XCTAssertEqual(r.status, 0, r.stderr)
        XCTAssertTrue(r.stdout.contains("cheng2025identifiability"), r.stdout)
        XCTAssertFalse(r.stdout.contains("olsson1979maximum"), "非成員不得出現：\(r.stdout)")

        // remove membership → query 空
        r = try runCLI(["library", "remove", "sinica", "cheng2025identifiability"] + lib)
        XCTAssertEqual(r.status, 0, r.stderr)
        r = try runCLI(["query", "--in-library", "sinica"] + lib)
        XCTAssertEqual(r.status, 0, r.stderr)
        XCTAssertFalse(r.stdout.contains("cheng2025identifiability"), r.stdout)
    }

    func testLibraryCreateRejectsBadKeyAndAddRejectsUnknown() throws {
        var r = try runCLI(["library", "create", "Bad Key", "--name", "X"] + lib)
        XCTAssertNotEqual(r.status, 0, "不合 StoreKey 的 key 要失敗")
        _ = try runCLI(["library", "create", "sinica", "--name", "中研院"] + lib)
        r = try runCLI(["library", "add", "sinica", "ghost2000x"] + lib)
        XCTAssertNotEqual(r.status, 0, "未知 citekey 要失敗")
        r = try runCLI(["library", "add", "ghostlib", "cheng2025identifiability"] + lib)
        XCTAssertNotEqual(r.status, 0, "未知 library 要失敗")
    }
}

/// #18 多檔案：`akashic file` 子指令（--config 注入，不碰真實 ~/.akashic）。
extension CLIIntegrationTests {
    /// `doctor` 對**已註冊**的 store 必須保留 registry key（#101）。
    ///
    /// 曾經 `doctor` 走 `resolveRoot()` 只拿 root、丟掉 key，於是它把已註冊的 store 當成
    /// 未註冊的：建一個永遠用不到的 in-store `.akashic/`，並且**重建錯的那個 index**——
    /// `<home>/index/<key>.sqlite` 從來沒被 `doctor` 更新過，使用者的查詢一直打在一份
    /// 過期的衍生資料上，而且沒有任何訊號。
    func testDoctorOnRegisteredStoreKeepsIndexOutOfStore() throws {
        let home = try tmpDir("home")
        let storeRoot = try tmpDir("registered")
        // registry 放進 fake home——`doctor` 沒有 `--config`，它從 AKASHIC_HOME 讀
        let config = home.appendingPathComponent("config.yaml").path
        let env = ["AKASHIC_HOME": home.path]

        var r = try runCLI(["file", "add", "main", storeRoot.path, "--config", config], env: env)
        XCTAssertEqual(r.status, 0, r.stderr)
        r = try runCLI(["file", "use", "main", "--config", config], env: env)
        XCTAssertEqual(r.status, 0, r.stderr)

        // 不帶 --library：走 registry，key = main
        r = try runCLI(["doctor"], env: env)
        XCTAssertEqual(r.status, 0, r.stderr)

        let fm = FileManager.default
        XCTAssertTrue(fm.fileExists(atPath: home.appendingPathComponent("index/main.sqlite").path),
                      "已註冊 store 的 index 必須寫到 <home>/index/<key>.sqlite")
        XCTAssertFalse(fm.fileExists(atPath: storeRoot.appendingPathComponent(".akashic").path),
                       "已註冊的 store 不該有 in-store 的 index 回落位置")

        // issue #101 的標題症狀：「每次 doctor 都長出 entries/ 與 people/」。
        // 上面那兩條測的是 .akashic/；這兩條才是標題講的那件事，且**必須在跑過 doctor
        // 之後**斷言——只測 file add 之後的狀態抓不到「doctor 又把它建回來」。
        for legacy in ["entries", "people"] {
            XCTAssertFalse(fm.fileExists(atPath: storeRoot.appendingPathComponent(legacy).path),
                           "當前 format 的 store 跑完 doctor 不該長出 \(legacy)/")
        }
    }

    private func tmpDir(_ name: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("akashic-file-\(name)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func testFileLifecycleAddUseListRemove() throws {
        let configDir = try tmpDir("cfg")
        let config = configDir.appendingPathComponent("config.yaml").path
        let rootA = try tmpDir("rootA"), rootB = try tmpDir("rootB")

        // add：註冊 + ensureLayout（空目錄變完整 layout）
        var r = try runCLI(["file", "add", "main", rootA.path, "--config", config])
        XCTAssertEqual(r.status, 0, r.stderr)
        XCTAssertTrue(FileManager.default.fileExists(atPath: rootA.appendingPathComponent("entities").path),
                      "add 對新目錄跑 ensureLayout")
        XCTAssertFalse(FileManager.default.fileExists(atPath: rootA.appendingPathComponent("entries").path),
                       "新建的 store 是當前 format，不該有 legacy 的 entries/（#101）")
        XCTAssertFalse(FileManager.default.fileExists(atPath: rootA.appendingPathComponent(".akashic").path),
                       "file add 註冊了 key，index 住 store 之外，不該建 in-store 回落位置（#101）")
        _ = try runCLI(["file", "add", "work", rootB.path, "--config", config])

        // use：寫 current
        r = try runCLI(["file", "use", "work", "--config", config])
        XCTAssertEqual(r.status, 0, r.stderr)

        // list：current 有標記
        r = try runCLI(["file", "list", "--config", config])
        XCTAssertEqual(r.status, 0, r.stderr)
        XCTAssertTrue(r.stdout.contains("main"), r.stdout)
        let workLine = r.stdout.split(separator: "\n").first { $0.contains("work") }.map(String.init) ?? ""
        XCTAssertTrue(workLine.contains("*"), "current 檔案要有標記：\(r.stdout)")

        // remove：只除名不刪資料；remove current → current 清空
        r = try runCLI(["file", "remove", "work", "--config", config])
        XCTAssertEqual(r.status, 0, r.stderr)
        XCTAssertTrue(FileManager.default.fileExists(atPath: rootB.path), "remove 不刪資料")
        r = try runCLI(["file", "list", "--config", config])
        XCTAssertFalse(r.stdout.contains("work"), r.stdout)
    }

    func testFileAddRejectsBadKeyAndDuplicate() throws {
        let config = try tmpDir("cfg2").appendingPathComponent("config.yaml").path
        let root = try tmpDir("root2")
        XCTAssertNotEqual(try runCLI(["file", "add", "Bad_Key", root.path, "--config", config]).status, 0)
        XCTAssertEqual(try runCLI(["file", "add", "main", root.path, "--config", config]).status, 0)
        XCTAssertNotEqual(try runCLI(["file", "add", "main", root.path, "--config", config]).status, 0,
                          "重複 key 拒絕")
    }

    func testFileUseUnknownKeyFails() throws {
        let config = try tmpDir("cfg3").appendingPathComponent("config.yaml").path
        let r = try runCLI(["file", "use", "ghost", "--config", config])
        XCTAssertNotEqual(r.status, 0)
    }
}

/// #18 Codex R1：CLI file 加固（絕對路徑、重複 path、use 驗證）。
extension CLIIntegrationTests {
    func testFileAddNormalizesRelativePathAndRejectsDuplicatePath() throws {
        let configDir = try tmpDir("cfg4")
        let config = configDir.appendingPathComponent("config.yaml").path
        let rootA = try tmpDir("rootRel")
        // 相對路徑（借 CWD 無法穩定控制 process CWD——用含 .. 的路徑驗 standardize）
        let messy = rootA.path + "/../" + rootA.lastPathComponent
        var r = try runCLI(["file", "add", "main", messy, "--config", config])
        XCTAssertEqual(r.status, 0, r.stderr)
        let saved = try String(contentsOf: URL(fileURLWithPath: config), encoding: .utf8)
        XCTAssertFalse(saved.contains(".."), "入 config 的路徑必須 standardize：\(saved)")
        // 同一實體 root 換個 key 再註冊 → 拒絕
        r = try runCLI(["file", "add", "alias", rootA.path, "--config", config])
        XCTAssertNotEqual(r.status, 0, "重複 path 拒絕（互不相通）")
    }

    func testFileUseRejectsVanishedTarget() throws {
        let configDir = try tmpDir("cfg5")
        let config = configDir.appendingPathComponent("config.yaml").path
        let root = try tmpDir("rootGone")
        _ = try runCLI(["file", "add", "main", root.path, "--config", config])
        try FileManager.default.removeItem(at: root)   // 目錄被搬走
        let r = try runCLI(["file", "use", "main", "--config", config])
        XCTAssertNotEqual(r.status, 0, "use 指向消失的庫要拒絕（與 MCP/App 驗證一致）")
    }
}

/// #18 Codex R2：真正的相對路徑（不以 / 開頭）→ 入 config 必為絕對路徑。
extension CLIIntegrationTests {
    func testFileAddTrueRelativePathBecomesAbsolute() throws {
        let configDir = try tmpDir("cfg6")
        let config = configDir.appendingPathComponent("config.yaml").path
        let relName = "akashic-rel-\(UUID().uuidString.prefix(8))"
        defer { try? FileManager.default.removeItem(
            at: URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent(relName)) }
        let r = try runCLI(["file", "add", "main", relName, "--config", config])
        XCTAssertEqual(r.status, 0, r.stderr)
        let saved = try String(contentsOf: URL(fileURLWithPath: config), encoding: .utf8)
        let valueLine = saved.split(separator: "\n").first { $0.contains("main:") }.map(String.init) ?? ""
        let value = valueLine.split(separator: ":", maxSplits: 1).last.map {
            $0.trimmingCharacters(in: .whitespaces) } ?? ""
        XCTAssertTrue(value.hasPrefix("/"), "相對路徑入 config 必為絕對路徑：\(value)")
        XCTAssertFalse(value.contains(".."), value)
    }

    // MARK: - doctor 的矛盾報告（#84；行為由 #67 引入）

    /// 寫一筆 person 到 fixture library。`affiliationEnd` 為 nil ＝ 隸屬段仍開著。
    private func writePerson(_ key: String, died: String?, affiliationEnd: String?) throws {
        var yaml = """
        key: \(key)
        names:
          - \(key)
        """
        if let died { yaml += "\ndied: '\(died)'" }
        yaml += """

        profile:
          affiliations:
          - value: Institute of Statistical Science
            start: '1990-09'
        """
        if let affiliationEnd { yaml += "\n    end: '\(affiliationEnd)'" }
        try (yaml + "\n").write(to: libraryRoot.appendingPathComponent("people/\(key).yaml"),
                                atomically: true, encoding: .utf8)
    }

    /// 從 doctor 輸出裡切出「已故卻仍有開放隸屬」那一段，回傳它列出的 key 集合。
    ///
    /// **不用 `stdout.contains(key)`**：那證明的是「這個字串出現在輸出的某處」，不是
    /// 「它出現在那份報告底下」——key 可能來自路徑、其他清單或別的診斷行。切 section
    /// 之後改斷言集合相等，同時解掉三件事：key 必須在該段內、任何 N 的截斷都會失敗
    /// （只數 11 筆的話 `prefix(11)` 仍會通過）、而 section 存在本身即證明報告有接線。
    ///
    /// 回傳 `nil` ＝ 該段整個沒出現（無命中時的正確狀態）。
    private func deceasedContradictionSection(_ stdout: String) -> Set<String>? {
        let lines = stdout.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard let head = lines.firstIndex(where: { $0.hasPrefix("deceased with open affiliation") })
        else { return nil }
        var keys = Set<String>()
        for line in lines[(head + 1)...] {
            guard let r = line.range(of: "⚠ ") else { break }   // 下一段開始 → 停
            keys.insert(String(line[r.upperBound...]).trimmingCharacters(in: .whitespaces))
        }
        return keys
    }

    /// 已記錄逝世、卻仍有開放的隸屬段——`doctor` 要把它報出來，並點名是哪一筆。
    ///
    /// 這條測的是**使用者跑指令會看到什麼**。#67 當初只在 `PersonDeceasedTests` 用
    /// 原始碼字串斷言代替（`commands.contains("recordsDeceasedWithOpenAffiliation()")`），
    /// 那種斷言即使呼叫在註解裡、或有呼叫但沒印出結果，一樣會通過。
    func testDoctorReportsADeceasedPersonWithAnOpenAffiliation() throws {
        try writePerson("dead-but-open", died: "2004-11-18", affiliationEnd: nil)
        try writePerson("properly-closed", died: "2004-11-18", affiliationEnd: "2004-11")
        let r = try runCLI(["doctor"] + lib)
        XCTAssertEqual(r.status, 0, r.stderr)
        // 恰好一筆，且**就是**開放那筆——同時證明「有報」與「沒錯報」。
        XCTAssertEqual(deceasedContradictionSection(r.stdout), ["dead-but-open"], r.stdout)
    }

    /// 無命中時**整項不出現**。0 是這項報告的正常狀態，每次印一行「0」只是噪音——
    /// 這個設計要求只有在真的跑一次 CLI 才驗得到。
    func testDoctorOmitsTheContradictionReportEntirelyWhenThereIsNoHit() throws {
        try writePerson("properly-closed", died: "2004-11-18", affiliationEnd: "2004-11")
        try writePerson("no-death-recorded", died: nil, affiliationEnd: nil)
        let r = try runCLI(["doctor"] + lib)
        XCTAssertEqual(r.status, 0, r.stderr)
        // 先確認 fixture 真的被載入（setUp 的 cheng-che ＋ 上面兩筆）。
        // 少了這一步，YAML 寫壞導致 people: 0 時本測試會**因為錯的理由**通過——
        // 「沒有矛盾」與「根本沒有人」在輸出上長得一樣。
        XCTAssertTrue(r.stdout.contains("people: 3"),
                      "fixture 未如預期載入，下面的斷言會是空的：\n\(r.stdout)")
        XCTAssertNil(deceasedContradictionSection(r.stdout), r.stdout)
    }

    /// **全列，不截斷。** 這是待人處理的工作清單而非普查數字——省略第 11 筆之後，
    /// 操作者就拿不到其餘待修記錄，而總數不等於清單。
    ///
    /// 這個缺陷實際發生過（`prefix(10)`），且**原始碼字串斷言在結構上抓不到它**：
    /// 呼叫確實存在、報告確實印出，只是少了幾行。
    func testDoctorListsEveryContradictionWithoutTruncating() throws {
        let expected = Set((1...11).map { String(format: "person-%02d", $0) })
        for key in expected {
            try writePerson(key, died: "2004-11-18", affiliationEnd: nil)
        }
        let r = try runCLI(["doctor"] + lib)
        XCTAssertEqual(r.status, 0, r.stderr)
        // **集合相等**而非逐筆 `contains`。它證明的是：key 都在該報告段落內（不是輸出
        // 別處的路徑或清單）、沒有少列（截斷）、也沒有多列（誤報）。
        //
        // **它證明不了的**：`prefix(N)` 中 N ≥ 11 的截斷——實測 `prefix(11)` 通過。
        // 要抓那個需要無界的 fixture 數；11 筆是針對**實際發生過**的 `prefix(10)` 的
        // 回歸（已實測：注入 `prefix(10)` 本測試失敗）。名稱說「不截斷」，範圍以此註解為準。
        XCTAssertEqual(deceasedContradictionSection(r.stdout), expected, r.stdout)
    }
}

/// `AkashicConfig.defaultURL` 寫死真實家目錄、不認 `AKASHIC_HOME`（#110）。
///
/// 後果：設了 `AKASHIC_HOME` 時，`doctor`（env-aware 的 `AkashicHome.configURL`）與
/// `file list/add/use`（fallback 到 `defaultURL`）讀**不同的 registry**——`file add`
/// 寫進真實 registry 而 doctor 永遠看不到。
final class ConfigHomeConsistencyTests: XCTestCase {
    /// `file list` 未帶 `--config` 時必須讀 `$AKASHIC_HOME/config.yaml`，
    /// 而非寫死的真實 `~/.akashic/config.yaml`。
    func testFileListHonorsAkashicHome() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("akashic-cfghome-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tmp) }
        let home = tmp.appendingPathComponent("home")
        let store = tmp.appendingPathComponent("store")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: store, withIntermediateDirectories: true)
        try "files:\n  fakekey: \(store.path)\ncurrent: fakekey\n"
            .write(to: home.appendingPathComponent("config.yaml"), atomically: true, encoding: .utf8)

        let r = try CLITestHarness.run(["file", "list"], env: ["AKASHIC_HOME": home.path])
        XCTAssertEqual(r.status, 0, r.output)
        XCTAssertTrue(r.output.contains("fakekey"),
                      "file list 該讀 $AKASHIC_HOME 的 registry（fake），實際輸出：\(r.output)")
    }
}

/// 建佈局的入口對壞掉的 store.yaml 必須 fail-loud（#106）。
///
/// 在此之前 `file add` 能成功註冊一個 format 比本 binary 新的 store、
/// `doctor` 對 malformed marker 的 store 安靜蓋出 legacy 目錄——兩者都零訊號。
///
/// （merge 收斂：原內嵌的 runCLI 已遷移到 `CLITestHarness`——#119 verify V2。）
final class EnsureLayoutStrictCLITests: XCTestCase {
    func testFileAddRefusesTooNewStore() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("akashic-toonew-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tmp) }
        let home = tmp.appendingPathComponent("home")
        let store = tmp.appendingPathComponent("store")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: store, withIntermediateDirectories: true)
        try "format: 99\n".write(to: store.appendingPathComponent("store.yaml"),
                                 atomically: true, encoding: .utf8)

        let r = try CLITestHarness.run(["file", "add", "main", store.path,
                                        "--config", home.appendingPathComponent("config.yaml").path],
                                       env: ["AKASHIC_HOME": home.path])
        XCTAssertNotEqual(r.status, 0, "too-new 的 store 不得被成功註冊")
        XCTAssertTrue(r.output.contains("升級"), "錯誤訊息要指路（請升級）：\(r.output)")
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: store.appendingPathComponent("entries").path),
            "拒絕之後不得留下猜出來的目錄")
        // **registry 必須未被寫入**（#112 verify）——「拒絕註冊」的本體是這一條，
        // 不是 exit code。現況成立靠的是 FileAdd.run 裡 ensureLayout 先於 config.write
        // 的順序，這個斷言把那個順序釘住。
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: home.appendingPathComponent("config.yaml").path),
            "拒絕之後 config 不得被建立/寫入——否則 registry 已含一個打不開的 store")
    }
}

/// #105 E2E：`doctor --library <已註冊路徑>` 必須帶 key——寫 `<home>/index/<key>.sqlite`、
/// 不建 in-store `.akashic/`（#101 R1 finding #4 的情境，當時無測試；同時終結 #120
/// verify 的 FP-4「刪掉 → --library 開一次又長回 → 無限建議循環」）。
final class RegistryLookupCLITests: XCTestCase {
    func testDoctorViaLibraryFlagOnRegisteredStoreKeepsIndexInHome() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("akashic-lookup-e2e-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tmp) }
        let home = tmp.appendingPathComponent("home")
        let store = tmp.appendingPathComponent("store")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        let env = ["AKASHIC_HOME": home.path]

        var r = try CLITestHarness.run(["file", "add", "main", store.path,
                                        "--config", home.appendingPathComponent("config.yaml").path],
                                       env: env)
        XCTAssertEqual(r.status, 0, r.output)

        // 關鍵：用 --library 直指同一個已註冊路徑
        r = try CLITestHarness.run(["doctor", "--library", store.path], env: env)
        XCTAssertEqual(r.status, 0, r.output)

        let fm = FileManager.default
        XCTAssertTrue(fm.fileExists(atPath: home.appendingPathComponent("index/main.sqlite").path),
                      "反查到 key 後 index 必須寫 home 的 index/main.sqlite")
        XCTAssertFalse(fm.fileExists(atPath: store.appendingPathComponent(".akashic").path),
                       "已註冊的 store 經 --library 開啟不得再建 in-store .akashic/")
    }
}
