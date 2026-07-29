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
