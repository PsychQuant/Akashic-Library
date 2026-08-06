import XCTest

/// #5：`resolve-people --apply` 的逐項選擇。
///
/// 為什麼需要：alias 完全命中**仍可能同名不同人**——people 庫還沒記錄第二個人時，
/// 歧義偵測不會觸發。「全套用」對這種情境是危險的預設。
final class ResolvePeopleSelectiveTests: XCTestCase {
    var root: URL!

    private var productsDirectory: URL {
        for bundle in Bundle.allBundles where bundle.bundlePath.hasSuffix(".xctest") {
            return bundle.bundleURL.deletingLastPathComponent()
        }
        fatalError("找不到 products directory")
    }

    private func runCLI(_ args: [String]) throws -> (status: Int32, out: String, err: String) {
        let p = Process()
        p.executableURL = productsDirectory.appendingPathComponent("akashic")
        p.arguments = args + ["--library", root.path]
        // AKASHIC_* 無條件剝除（#105 之後 --library 會反查 registry——不剝除的話
        // 這個 harness 會讀開發機的真實 config.yaml；#101/#112 的沙箱紀律同款）
        p.environment = ProcessInfo.processInfo.environment.filter { !$0.key.hasPrefix("AKASHIC_") }
        let o = Pipe(), e = Pipe()
        p.standardOutput = o; p.standardError = e
        try p.run()
        let od = o.fileHandleForReading.readDataToEndOfFile()
        let ed = e.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return (p.terminationStatus, String(decoding: od, as: UTF8.self),
                String(decoding: ed, as: UTF8.self))
    }

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("akashic-rp-\(UUID().uuidString)")
        let fm = FileManager.default
        for d in ["entries", "people", "libraries"] {
            try fm.createDirectory(at: root.appendingPathComponent(d),
                                   withIntermediateDirectories: true)
        }
        try "key: cheng-che\nnames: [Che Cheng]\n".write(
            to: root.appendingPathComponent("people/cheng-che.yaml"),
            atomically: true, encoding: .utf8)
        try "key: olsson-ulf\nnames: [Ulf Olsson]\n".write(
            to: root.appendingPathComponent("people/olsson-ulf.yaml"),
            atomically: true, encoding: .utf8)
        for (i, (ck, au)) in [("a2020a", "Che Cheng"), ("b2021b", "Ulf Olsson"),
                              ("c2022c", "Che Cheng")].enumerated() {
            try """
            id: \(String(format: "%08d", i + 1))-1111-1111-1111-111111111111
            citekey: \(ck)
            type: article
            title: T\(i)
            authors:
              - literal: "\(au)"
            date: "2020"

            """.write(to: root.appendingPathComponent("entries/\(ck).yaml"),
                      atomically: true, encoding: .utf8)
        }
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    private func body(_ ck: String) throws -> String {
        try String(contentsOf: root.appendingPathComponent("entries/\(ck).yaml"), encoding: .utf8)
    }

    /// 不加 --apply 時只列候選（既有行為，不得回歸）。
    func testListOnlyByDefault() throws {
        let r = try runCLI(["resolve-people"])
        XCTAssertEqual(r.status, 0)
        XCTAssertTrue(r.out.contains("a2020a") && r.out.contains("b2021b") && r.out.contains("c2022c"))
        XCTAssertTrue(try body("a2020a").contains("literal:"), "未加 --apply 不得寫入")
    }

    /// `--citekey` 只套那一筆，其他原封不動。
    func testCitekeyFilterAppliesOnlySelected() throws {
        let r = try runCLI(["resolve-people", "--apply", "--citekey", "a2020a"])
        XCTAssertEqual(r.status, 0, r.err)
        XCTAssertTrue(try body("a2020a").contains("key: cheng-che"), "選中的沒被套用")
        XCTAssertTrue(try body("b2021b").contains("literal:"), "未選中的被誤套")
        XCTAssertTrue(try body("c2022c").contains("literal:"), "同名的另一筆被誤套")
    }

    /// `--person` 套用所有指向該 person 的候選（跨 entry）。
    func testPersonFilterAppliesAcrossEntries() throws {
        let r = try runCLI(["resolve-people", "--apply", "--person", "cheng-che"])
        XCTAssertEqual(r.status, 0, r.err)
        XCTAssertTrue(try body("a2020a").contains("key: cheng-che"))
        XCTAssertTrue(try body("c2022c").contains("key: cheng-che"))
        XCTAssertTrue(try body("b2021b").contains("literal:"), "不同 person 的被誤套")
    }

    /// 兩個篩選取**交集**。
    func testFiltersIntersect() throws {
        let r = try runCLI(["resolve-people", "--apply",
                            "--citekey", "a2020a", "--person", "olsson-ulf"])
        XCTAssertNotEqual(r.status, 0, "交集為空應 fail-loud")
        XCTAssertTrue(try body("a2020a").contains("literal:"))
    }

    /// 篩選寫了卻一個都沒中 → **fail-loud**，不靜默什麼都不做。
    /// 靜默成功會讓使用者以為套用了，而 key 其實打錯。
    func testUnmatchedFilterFailsLoudly() throws {
        let r = try runCLI(["resolve-people", "--apply", "--citekey", "nosuchkey"])
        XCTAssertNotEqual(r.status, 0)
        XCTAssertTrue(r.err.contains("沒有命中任何候選"), r.err)
    }

    /// 被篩掉的候選**仍要列出並標示 skip**——收窄範圍不等於「其他候選不存在」。
    func testFilteredOutCandidatesAreStillListedAsSkipped() throws {
        let r = try runCLI(["resolve-people", "--apply", "--citekey", "a2020a"])
        XCTAssertTrue(r.out.contains("(skip)"), r.out)
        XCTAssertTrue(r.out.contains("b2021b"), "被篩掉的候選消失了：\(r.out)")
    }

    /// 無篩選時維持既有的全套用行為。
    func testNoFilterAppliesAll() throws {
        let r = try runCLI(["resolve-people", "--apply"])
        XCTAssertEqual(r.status, 0, r.err)
        for ck in ["a2020a", "b2021b", "c2022c"] {
            XCTAssertTrue(try body(ck).contains("key: "), "\(ck) 未被套用")
        }
    }
}
