import XCTest
import Foundation

/// #700 b33 verify X5 第 0 列（MEDIUM）：`.gitignore` 的「先看、後寫」不是原子的。真 binary、同時跑多個程序。
///
/// b33 verify 以 c86ae785 的 binary 實測：兩個以上的 `doctor`／`file add`／`import-zotero` 同時第一次對同一個 store 建佈局時，
/// (1) 沒有 `.gitignore`：`O_EXCL` 撞上別人剛建的檔就報「檢查之後、寫入之前被換掉或改過」——區塊其實已經在了，`doctor` 印假警告、
/// `file add` 假拒絕（佈局建好、registry 沒寫）；(2) 有 UTF-8 `.gitignore`：兩個程序都在對方寫入之前通過 device／inode／大小比對、
/// 各自附加，寫出兩份區塊。舊版（整份原子替換）兩種都不會出現。現在：開檔後取 `flock(LOCK_EX)`、鎖內重讀內容再決定；`O_EXCL` 撞上
/// `EEXIST` 時重看，看到區塊已在就算成功。
///
/// 斷言「最後恰好一份、沒有假拒絕、沒有假警告」，每種形狀跑數輪（競態是機率性的：修前 6 個程序 × 10 輪，沒有 `.gitignore` 的那一種
/// 9 輪有假警告、有 `.gitignore` 的那一種 3 輪寫出兩份——2026-10-05 以 c86ae785 之後的 main 實測）。
final class GitignoreConcurrencyCLITests: XCTestCase {
    private var base: URL!
    private let processes = 6
    private let rounds = 8

    override func setUpWithError() throws {
        base = FileManager.default.temporaryDirectory.appendingPathComponent("akashic-gitignore-race-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: base) }

    /// 同時啟動 `argsFor(i)` 的每一個程序，等全部結束；回每一個的結束碼與輸出。
    private func runConcurrently(_ argsFor: (Int) -> [String], home: URL) throws -> [(status: Int32, output: String)] {
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        var running: [(Process, URL)] = []
        for i in 0..<processes {
            let p = Process()
            p.executableURL = CLITestHarness.productsDirectory.appendingPathComponent("akashic")
            p.arguments = argsFor(i)
            p.environment = ["AKASHIC_HOME": home.path, "PATH": "/usr/bin:/bin"]
            let out = base.appendingPathComponent("out-\(UUID().uuidString)")
            FileManager.default.createFile(atPath: out.path, contents: nil)
            let h = try FileHandle(forWritingTo: out)
            p.standardOutput = h; p.standardError = h
            running.append((p, out))
        }
        for (p, _) in running { try p.run() }
        return running.map { p, out in
            p.waitUntilExit()
            return (p.terminationStatus, (try? String(contentsOf: out, encoding: .utf8)) ?? "")
        }
    }

    private func markerCount(_ dir: URL) throws -> Int {
        let bytes = try Data(contentsOf: dir.appendingPathComponent(".gitignore"))
        return String(decoding: bytes, as: UTF8.self).components(separatedBy: "# BEGIN akashic sources").count - 1
    }

    /// `doctor`（`.report`）：沒有 `.gitignore`、與有一個 UTF-8 `.gitignore` 兩種起點。
    func testConcurrentDoctorsLeaveExactlyOneBlockAndNoFalseWarning() throws {
        for start in ["none", "utf8"] {
            for round in 0..<rounds {
                let dir = base.appendingPathComponent("\(start)-\(round)")
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                let original = Data("*.srt\n".utf8)
                if start == "utf8" { try original.write(to: dir.appendingPathComponent(".gitignore")) }
                let results = try runConcurrently({ _ in ["doctor", "--library", dir.path] }, home: base.appendingPathComponent("home-\(start)-\(round)"))
                // 結束碼要是 0（b36 verify：先前不斷言，因為同時重建 index 時改名會撞上別人剛放好的 index 檔——6 個程序 × 15 輪有 2–4 輪；
                // `LibraryIndex.rebuild` 改用 rename(2) 原子取代之後不再出現）
                for r in results {
                    XCTAssertEqual(r.status, 0, "\(start) 第 \(round) 輪：\(r.output)")
                    XCTAssertFalse(r.output.contains("⚠ .gitignore"), "\(start) 第 \(round) 輪：區塊已由另一個程序加上，不得報假警告：\(r.output)")
                }
                XCTAssertEqual(try markerCount(dir), 1, "\(start) 第 \(round) 輪：區塊恰好一份")
                if start == "utf8" {
                    XCTAssertTrue(try Data(contentsOf: dir.appendingPathComponent(".gitignore")).starts(with: original), "原有位元組不動")
                }
            }
        }
    }

    /// `import-zotero`（`.report`，MCP 的兩個匯入走同一條；2026-10-05 的裁決之前是 `.refuse`）：`.gitignore` 那一步在讀 zotero.sqlite 之前，
    /// 所以給一個不存在的 db 也走得到（之後以「找不到 zotero.sqlite」結束，那不是這裡要看的）。沒有一個被 `.gitignore` 假拒絕、也沒有假警告。
    func testConcurrentImportsAreNotRefusedOverTheGitignore() throws {
        for round in 0..<rounds {
            let dir = base.appendingPathComponent("import-\(round)")
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            if round % 2 == 1 { try Data("*.srt\n".utf8).write(to: dir.appendingPathComponent(".gitignore")) }
            let results = try runConcurrently({ _ in
                ["import-zotero", "--library", dir.path, "--zotero-db", self.base.appendingPathComponent("nope.sqlite").path]
            }, home: base.appendingPathComponent("home-import-\(round)"))
            for r in results {
                XCTAssertFalse(r.output.contains("這次不能替你加"), "第 \(round) 輪：\(r.output)")
                XCTAssertFalse(r.output.contains("⚠ .gitignore"), "第 \(round) 輪：區塊已由另一個程序加上，不得報假警告：\(r.output)")
                XCTAssertTrue(r.output.contains("找不到 zotero.sqlite"), "第 \(round) 輪：要走到 db 那一步：\(r.output)")
            }
            XCTAssertEqual(try markerCount(dir), 1, "第 \(round) 輪：區塊恰好一份")
        }
    }

    /// 先看也要等持鎖的寫入者（b34 修正輪：先看的判讀與鎖內重看是同一個判斷）。測試程序持 `LOCK_EX`、檔裡是寫到一半的區塊（只有標記），
    /// 啟動 `file add` 與 `doctor`；兩秒後補上規則再放鎖。先看若不等鎖，會讀到「有標記沒有規則」——`file add` 在建立任何東西之前假拒絕、
    /// `doctor` 報假警告——而區塊在放鎖時已經完整。
    func testTheFirstLookWaitsForAWriterHoldingTheLock() throws {
        let half = Data("*.srt\n# BEGIN akashic sources\n".utf8)
        let rest = Data("sources/\n# END akashic sources\n".utf8)
        for command in ["file-add", "doctor"] {
            let dir = base.appendingPathComponent("held-\(command)")
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let gi = dir.appendingPathComponent(".gitignore")
            try half.write(to: gi)
            let fd = open(gi.path, O_RDWR | O_APPEND)
            XCTAssertGreaterThanOrEqual(fd, 0)
            XCTAssertEqual(flock(fd, LOCK_EX), 0)
            let home = base.appendingPathComponent("home-held-\(command)")
            try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
            let p = Process()
            p.executableURL = CLITestHarness.productsDirectory.appendingPathComponent("akashic")
            p.arguments = command == "doctor" ? ["doctor", "--library", dir.path]
                                              : ["file", "add", "held", dir.path, "--config", home.appendingPathComponent("config.yaml").path]
            p.environment = ["AKASHIC_HOME": home.path, "PATH": "/usr/bin:/bin"]
            let out = Pipe()
            p.standardOutput = out; p.standardError = out
            try p.run()
            Thread.sleep(forTimeInterval: 2)
            XCTAssertEqual(rest.withUnsafeBytes { write(fd, $0.baseAddress, $0.count) }, rest.count)
            flock(fd, LOCK_UN)
            close(fd)
            p.waitUntilExit()
            let output = String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            if command == "doctor" {
                XCTAssertFalse(output.contains("⚠ .gitignore"), output)
            } else {
                XCTAssertEqual(p.terminationStatus, 0, output)
            }
            XCTAssertEqual(try Data(contentsOf: gi), half + rest, "\(command)：區塊恰好一份、不改寫")
        }
    }

    /// `file add`（`.refuse`）：同時註冊同一個 store 目錄（各自的 key 與 registry），沒有一個被假拒絕。
    func testConcurrentFileAddsAreNotRefusedSpuriously() throws {
        for round in 0..<rounds {
            let dir = base.appendingPathComponent("add-\(round)")
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try Data("node_modules/\n".utf8).write(to: dir.appendingPathComponent(".gitignore"))
            let home = base.appendingPathComponent("home-add-\(round)")
            let results = try runConcurrently({ i in
                ["file", "add", "k\(i)", dir.path, "--config", home.appendingPathComponent("config-\(i).yaml").path]
            }, home: home)
            for r in results { XCTAssertEqual(r.status, 0, "第 \(round) 輪：\(r.output)") }
            XCTAssertEqual(try markerCount(dir), 1, "第 \(round) 輪：區塊恰好一份")
        }
    }
}
