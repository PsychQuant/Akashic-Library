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
    private func runCLI(_ args: [String]) throws -> (status: Int32, stdout: String, stderr: String) {
        let process = Process()
        process.executableURL = productsDirectory.appendingPathComponent("akashic")
        process.arguments = args
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
        XCTAssertTrue(FileManager.default.fileExists(atPath: rootA.appendingPathComponent("entries").path),
                      "add 對新目錄跑 ensureLayout")
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
}
