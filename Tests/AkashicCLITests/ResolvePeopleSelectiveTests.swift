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
        try "id: 11111111-1111-4111-8111-111111111111\nkey: cheng-che\nnames: {variant: [Che Cheng]}\n".write(
            to: root.appendingPathComponent("people/cheng-che.yaml"),
            atomically: true, encoding: .utf8)
        try "id: 11111111-1111-4111-8111-111111111111\nkey: olsson-ulf\nnames: {variant: [Ulf Olsson]}\n".write(
            to: root.appendingPathComponent("people/olsson-ulf.yaml"),
            atomically: true, encoding: .utf8)
        for (i, (ck, au)) in [("a2020a", "Che Cheng"), ("b2021b", "Ulf Olsson"),
                              ("c2022c", "Che Cheng")].enumerated() {
            try """
            id: \(String(format: "%08d", i + 1))-1111-1111-1111-111111111111
            citekey: \(ck)
            type: periodical-article
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

    /// #303 task 3.2：候選按 tier 分組列印——exact 段先於 reorder 段，
    /// initials 段標頭自帶查證義務（design D4 的 CLI 半邊）。
    func testOutputGroupsCandidatesByTier() throws {
        // 本測試自備一筆 token 重排形（不動共用 fixture）：「Cheng Che」↔ alias「Che Cheng」
        try """
        id: 00000009-1111-1111-1111-111111111111
        citekey: d2023d
        type: periodical-article
        title: TD
        authors:
          - literal: "Cheng Che"
        date: "2023"

        """.write(to: root.appendingPathComponent("entries/d2023d.yaml"),
                  atomically: true, encoding: .utf8)
        let r = try runCLI(["resolve-people"])
        XCTAssertEqual(r.status, 0, r.err)
        let exactHeader = r.out.range(of: "〔exact——alias 完全命中〕")
        let reorderHeader = r.out.range(of: "〔reorder——token 重排命中〕")
        XCTAssertNotNil(exactHeader, r.out)
        XCTAssertNotNil(reorderHeader, r.out)
        XCTAssertTrue(exactHeader!.lowerBound < reorderHeader!.lowerBound,
                      "exact 段排在 reorder 段之前（信心降冪）")
        XCTAssertTrue(r.out.contains("d2023d"), "reorder 候選要列出")
    }

    /// R1-fix B1：裸 `--apply` 在候選含寬鬆 tier 時拒絕（爆炸半徑收回）。
    func testBareApplyRefusesWhenLooseTierCandidatesPresent() throws {
        try """
        id: 00000009-1111-1111-1111-111111111111
        citekey: d2023d
        type: periodical-article
        title: TD
        authors:
          - literal: "Cheng Che"
        date: "2023"

        """.write(to: root.appendingPathComponent("entries/d2023d.yaml"),
                  atomically: true, encoding: .utf8)
        let r = try runCLI(["resolve-people", "--apply"])
        XCTAssertNotEqual(r.status, 0, "裸 --apply 面對寬鬆 tier 候選必須拒絕")
        XCTAssertTrue(r.err.contains("--tier"), r.err)
        // 什麼都沒寫
        XCTAssertTrue(try body("a2020a").contains("literal:"), "拒絕時不得有任何套用")
        XCTAssertTrue(try body("d2023d").contains("literal:"))
    }

    /// R2-fix R3-3（使用者裁決：不豁免）：`--person` 收窄照樣要 `--tier` 具名。
    func testPersonScopedApplyStillRequiresTierForLooseCandidates() throws {
        try """
        id: 00000009-1111-1111-1111-111111111111
        citekey: d2023d
        type: periodical-article
        title: TD
        authors:
          - literal: "Cheng Che"
        date: "2023"

        """.write(to: root.appendingPathComponent("entries/d2023d.yaml"),
                  atomically: true, encoding: .utf8)
        let r = try runCLI(["resolve-people", "--apply", "--person", "cheng-che"])
        XCTAssertNotEqual(r.status, 0, "--person 收窄不得豁免 tier 閘")
        XCTAssertTrue(r.err.contains("--tier"), r.err)
        XCTAssertTrue(try body("d2023d").contains("literal:"), "拒絕時零寫入")
        XCTAssertTrue(try body("a2020a").contains("literal:"))
    }

    /// `--tier exact` 只套完全命中，寬鬆列標 (skip) 不套。
    func testTierFilterAppliesOnlySelectedTier() throws {
        try """
        id: 00000009-1111-1111-1111-111111111111
        citekey: d2023d
        type: periodical-article
        title: TD
        authors:
          - literal: "Cheng Che"
        date: "2023"

        """.write(to: root.appendingPathComponent("entries/d2023d.yaml"),
                  atomically: true, encoding: .utf8)
        let r = try runCLI(["resolve-people", "--apply", "--tier", "exact"])
        XCTAssertEqual(r.status, 0, r.err)
        XCTAssertTrue(try body("a2020a").contains("key: cheng-che"), "exact 列要套用")
        XCTAssertTrue(try body("d2023d").contains("literal:"), "reorder 列不得被套用")
    }

    /// `--tier` 值域 fail-loud：typo 不得靜默變成「不篩」。
    func testTierFilterRejectsUnknownValue() throws {
        let r = try runCLI(["resolve-people", "--apply", "--tier", "exactt"])
        XCTAssertNotEqual(r.status, 0)
        XCTAssertTrue(r.err.contains("initials"), "錯誤要列合法值：\(r.err)")
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

    /// #597：不帶 --apply 時 `--citekey` 收窄列表本身，並說出全部有幾個——逐篇查證不必自己 grep 全列表，
    /// 也不會讓人以為其他候選不存在。
    func testListModeCitekeyNarrowsAndStatesTheTotal() throws {
        let r = try runCLI(["resolve-people", "--citekey", "a2020a"])
        XCTAssertEqual(r.status, 0, r.err)
        XCTAssertTrue(r.out.contains("a2020a"), r.out)
        XCTAssertFalse(r.out.contains("b2021b") || r.out.contains("c2022c"), "列表沒有收窄：\(r.out)")
        XCTAssertTrue(r.out.contains("候選 1 個（全部 3 個）"), r.out)
        XCTAssertTrue(try body("a2020a").contains("literal:"), "列表模式不得寫入")
    }

    /// #597：`--person` 在列表模式同樣生效，與 --citekey 取交集（--tier 見下一支——R1 verify 指出這支的名字曾宣稱涵蓋 --tier 而沒有）。
    func testListModePersonNarrowsAndIntersects() throws {
        let byPerson = try runCLI(["resolve-people", "--person", "olsson-ulf"])
        XCTAssertEqual(byPerson.status, 0, byPerson.err)
        XCTAssertTrue(byPerson.out.contains("b2021b") && !byPerson.out.contains("a2020a"), byPerson.out)
        let empty = try runCLI(["resolve-people", "--citekey", "a2020a", "--person", "olsson-ulf"])
        XCTAssertEqual(empty.status, 0)
        XCTAssertTrue(empty.out.contains("候選 0 個（全部 3 個）"), empty.out)
    }

    /// #597 R1 verify：`--tier` 在列表模式收窄，單獨用與和 --citekey 交集都要對。
    func testListModeTierNarrows() throws {
        try """
        id: 00000009-1111-1111-1111-111111111111
        citekey: d2023d
        type: periodical-article
        title: TD
        authors:
          - literal: "Cheng Che"
        date: "2023"

        """.write(to: root.appendingPathComponent("entries/d2023d.yaml"),
                  atomically: true, encoding: .utf8)
        let reorder = try runCLI(["resolve-people", "--tier", "reorder"])
        XCTAssertEqual(reorder.status, 0, reorder.err)
        XCTAssertTrue(reorder.out.contains("d2023d"), reorder.out)
        XCTAssertFalse(reorder.out.contains("a2020a") || reorder.out.contains("b2021b"), "--tier 沒有收窄：\(reorder.out)")
        XCTAssertTrue(reorder.out.contains("候選 1 個（全部 4 個）"), reorder.out)
        let both = try runCLI(["resolve-people", "--tier", "exact", "--citekey", "d2023d"])
        XCTAssertTrue(both.out.contains("候選 0 個（全部 4 個）"), both.out)
    }

    /// 第二個共用「Che Cheng」的 person 讓 a2020a／c2022c 變成歧義條目。
    private func seedAmbiguity() throws {
        try "id: 22222222-2222-4222-8222-222222222222\nkey: cheng-che-2\nnames: {variant: [Che Cheng]}\n".write(
            to: root.appendingPathComponent("people/cheng-che-2.yaml"), atomically: true, encoding: .utf8)
    }

    /// #597 R1 verify：歧義條目以「任一命中的 person」比 --person；不相交就不列，而總數照說。
    func testListModeNarrowsAmbiguitiesByAnyPerson() throws {
        try seedAmbiguity()
        let hit = try runCLI(["resolve-people", "--person", "cheng-che-2"])
        XCTAssertEqual(hit.status, 0, hit.err)
        XCTAssertTrue(hit.out.contains("歧義 2 筆（全部 2 筆）"), hit.out)
        let miss = try runCLI(["resolve-people", "--person", "olsson-ulf"])
        XCTAssertTrue(miss.out.contains("歧義 0 筆（全部 2 筆）"), miss.out)
        XCTAssertFalse(miss.out.contains("a2020a"), "不相交的歧義條目不得列出：\(miss.out)")
        let byCitekey = try runCLI(["resolve-people", "--citekey", "c2022c"])
        XCTAssertTrue(byCitekey.out.contains("歧義 1 筆（全部 2 筆）"), byCitekey.out)
    }

    /// #597 R1 verify DA：store 沒有唯一候選時，收窄行仍要印出，否則歧義段被靜默收窄；
    /// 也不得說「任何提名層皆無命中」——歧義就是命中了多個人。
    func testListModeNarrowingIsVisibleWhenThereAreNoUniqueCandidates() throws {
        try seedAmbiguity()
        try FileManager.default.removeItem(at: root.appendingPathComponent("entries/b2021b.yaml"))
        let r = try runCLI(["resolve-people", "--citekey", "nosuch"])
        XCTAssertEqual(r.status, 0, r.err)
        XCTAssertTrue(r.out.contains("歧義 0 筆（全部 2 筆）"), r.out)
        XCTAssertTrue(r.out.contains("無唯一候選"), r.out)
        XCTAssertFalse(r.out.contains("任何提名層皆無命中"), r.out)
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
