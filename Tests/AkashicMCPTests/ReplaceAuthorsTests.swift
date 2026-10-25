import XCTest
@testable import AkashicCore
@testable import AkashicMCPKit
@testable import AkashicStoreIO

/// #742（Spectra change `reconcile-work-from-fulltext`）：`update-entry --replace-authors`／`akashic_update_entry.replace_authors`
/// 的替換腿。值取自 spec `work-author-list-replacement` 的 Scenario 與觸發實例 `claw2018framework`；預期值一律手寫字面量。
final class ReplaceAuthorsTests: XCTestCase {
    private var root: URL!
    private var service: AkashicService { AkashicService(root: root) }

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("akashic-replace-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root.appendingPathComponent("entities"), withIntermediateDirectories: true)
        try StoreVersion.write(root: root, format: StoreVersion.supported)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    private func json(_ s: String) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: Data(s.utf8)) as? [String: Any])
    }
    /// 存一份「全文」進 sources/，回 digest。
    private func storedPDF(_ text: String = "%PDF-1.4 claw2018") throws -> String {
        let f = root.appendingPathComponent("in-\(UUID().uuidString).pdf")
        try Data(text.utf8).write(to: f)
        let out = try json(try service.storeSource(path: f.path, mediaType: "application/pdf",
                                                   retrieved: "2026-10-24T10:00:00+08:00",
                                                   origin: "https://www.nature.com/articles/s41467-018-05188-3.pdf",
                                                   acquisition: "browser-download", note: "version of record"))
        try FileManager.default.removeItem(at: f)
        return try XCTUnwrap(out["digest"] as? String)
    }
    @discardableResult
    private func seed(authors: [Author], sources: [String], citekey: String = "claw2018framework") throws -> Entry {
        var e = Entry(id: UUID(), citekey: citekey, type: .periodicalArticle,
                      title: "A framework for enhancing ethical genomic research with Indigenous communities",
                      authors: authors)
        e.akashic.sources = sources
        try LibraryStore(root: root).writeEntry(e)
        StoreGitCommit.commitAll(root)
        return e
    }
    private func body(_ object: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }
    private func run(_ object: [String: Any], dryRun: Bool = true, citekey: String = "claw2018framework") throws -> [String: Any] {
        try json(try service.updateEntry(citekey: citekey, removeFields: nil, replaceAuthors: try body(object), dryRun: dryRun))
    }
    private func assertRefused(_ object: [String: Any], mentions needle: String, dryRun: Bool = true,
                               file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertThrowsError(try run(object, dryRun: dryRun), file: file, line: line) { error in
            XCTAssertTrue(String(describing: error).contains(needle), "訊息要提到「\(needle)」：\(error)", file: file, line: line)
        }
    }

    private var digest: String = ""
    private func minimal(_ extra: [String: Any] = [:]) -> [String: Any] {
        var o: [String: Any] = ["source": digest, "page": 1, "reason": "PDF 第 1 頁 byline",
                                "authors": [["literal": "Katrina G. Claw"]]]
        for (k, v) in extra { o[k] = v }
        return o
    }

    private func seedDefault() throws {
        digest = try storedPDF()
        try seed(authors: [.literal("Claw, Katrina G."), .literal("Anderson, Matthew Z.")], sources: [digest])
    }

    // MARK: - 2.1 JSON 解碼與形狀驗證（每一條 failure mode 一個案例）

    func testUnknownKeysAreRefusedAtEveryLevel() throws {
        try seedDefault()
        assertRefused(minimal(["note": "x"]), mentions: "note")
        assertRefused(minimal(["authors": [["literal": "A", "role": "x"]]]), mentions: "authors[0] 有未知的鍵「role」")
        assertRefused(minimal(["authors": [["person": "A"]]]), mentions: "person")
        assertRefused(minimal(["release": [["index": 0, "reason": "r", "why": "x"]]]), mentions: "why")
        assertRefused(minimal(["groupMembers": [["group": "G", "page": 7, "members": ["A"], "extra": 1]]]), mentions: "extra")
    }

    func testMissingRequiredKeysAreRefused() throws {
        try seedDefault()
        for key in ["source", "page", "reason", "authors"] {
            var o = minimal(); o.removeValue(forKey: key)
            assertRefused(o, mentions: key)
        }
    }

    func testWrongTypesAreRefused() throws {
        try seedDefault()
        assertRefused(minimal(["page": "1"]), mentions: "page")
        assertRefused(minimal(["page": true]), mentions: "page")
        assertRefused(minimal(["page": 1.5]), mentions: "page")
        // JSONSerialization 把 Swift 的 1.0 寫成 `1`——要測「小數」必須送 JSON 原文
        let raw = #"{"source":"\#(digest)","page":1.0,"reason":"r","authors":[{"literal":"A"}]}"#
        XCTAssertThrowsError(try service.updateEntry(citekey: "claw2018framework", removeFields: nil,
                                                     replaceAuthors: Data(raw.utf8), dryRun: true)) { error in
            XCTAssertTrue(String(describing: error).contains("page"), "\(error)")
        }
        XCTAssertNoThrow(try service.updateEntry(
            citekey: "claw2018framework", removeFields: nil,
            replaceAuthors: Data(raw.replacingOccurrences(of: "1.0", with: "1").utf8), dryRun: true), "對照：整數 1 通過")
        assertRefused(minimal(["authors": "Katrina G. Claw"]), mentions: "authors")
        assertRefused(minimal(["authors": [["literal": 7]]]), mentions: "literal")
        assertRefused(minimal(["authors": [["from": "0"]]]), mentions: "from")
        assertRefused(minimal(["reason": ["r"]]), mentions: "reason")
        XCTAssertThrowsError(try service.updateEntry(citekey: "claw2018framework", removeFields: nil,
                                                     replaceAuthors: Data("[1]".utf8), dryRun: true), "頂層不是 object")
        XCTAssertThrowsError(try service.updateEntry(citekey: "claw2018framework", removeFields: nil,
                                                     replaceAuthors: Data("{".utf8), dryRun: true), "不是 JSON")
    }

    func testSourceMustBeAValidLinkedLocallyStoredDigest() throws {
        let other = try storedPDF("%PDF-1.4 another work")   // store 進 git 之前存（之後 store-source 要求 sources/ 已被版控忽略）
        try seedDefault()
        assertRefused(minimal(["source": "sha256:00"]), mentions: "source")
        assertRefused(minimal(["source": ProvenanceReference.emptyContentDigest]), mentions: "0 byte")
        assertRefused(minimal(["source": other]), mentions: "akashic.sources")
        let absent = "sha256:" + String(repeating: "cd", count: 32)
        var e = try XCTUnwrap(LibraryStore(root: root).load().entries.first)
        e.akashic.sources.append(absent)
        try LibraryStore(root: root).writeEntry(e)
        StoreGitCommit.commitAll(root)
        assertRefused(minimal(["source": absent]), mentions: "sources/")
    }

    func testPageAndReasonBounds() throws {
        try seedDefault()
        assertRefused(minimal(["page": 0]), mentions: "page")
        assertRefused(minimal(["page": -3]), mentions: "page")
        assertRefused(minimal(["reason": "  \n "]), mentions: "reason")
        assertRefused(minimal(["reason": String(repeating: "字", count: 1_366)]), mentions: "4,096")   // 4,098 bytes
        XCTAssertNoThrow(try run(minimal(["reason": String(repeating: "字", count: 1_365) + "a"])), "4,096 bytes 恰在上限")
    }

    func testAuthorItemBounds() throws {
        try seedDefault()
        assertRefused(minimal(["authors": []]), mentions: "authors")
        assertRefused(minimal(["authors": [["literal": "A", "group": "B"]]]), mentions: "恰好一個")
        assertRefused(minimal(["authors": [[String: Any]()]]), mentions: "恰好一個")
        assertRefused(minimal(["authors": [["literal": "   "]]]), mentions: "literal")
        assertRefused(minimal(["authors": [["group": " SING"]]]), mentions: "前後")
        assertRefused(minimal(["authors": [["literal": "A⟦B"]]]), mentions: "authors[0].literal 不得含 ⟦")
        assertRefused(minimal(["authors": [["group": "A⟧"]]]), mentions: "authors[0].group 不得含 ⟦")
        assertRefused(minimal(["authors": [["literal": String(repeating: "a", count: 65_537)]]]), mentions: "65,536")
        assertRefused(minimal(["authors": [["literal": "{SING Consortium}"]]]), mentions: "group")
        assertRefused(minimal(["authors": [["group": "{SING Consortium}"]]]), mentions: "大括號")
    }

    func testReleaseShapeBounds() throws {
        try seedDefault()
        assertRefused(minimal(["release": [["index": 0, "reason": " "]]]), mentions: "reason")
        assertRefused(minimal(["release": [["index": "0", "reason": "r"]]]), mentions: "index")
        assertRefused(minimal(["release": [["reason": "r"]]]), mentions: "index")
    }

    /// spec「A dry run writes nothing」：乾跑零寫入，回報前後的作者列。
    func testDryRunWritesNothingAndShowsBothLists() throws {
        try seedDefault()
        let before = try FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent("entities").path)
        let bytes = try before.map { try Data(contentsOf: root.appendingPathComponent("entities/\($0)")) }
        let out = try run(minimal(["authors": [["literal": "Katrina G. Claw"], ["group": "SING Consortium"]]]))
        XCTAssertEqual(out["dryRun"] as? Bool, true)
        XCTAssertEqual(out["authorsBefore"] as? [String], ["Claw, Katrina G.", "Anderson, Matthew Z."])
        XCTAssertEqual(out["authorsAfter"] as? [String], ["Katrina G. Claw", "{SING Consortium}"])
        let after = try before.map { try Data(contentsOf: root.appendingPathComponent("entities/\($0)")) }
        XCTAssertEqual(bytes, after, "乾跑零寫入")
    }

    /// spec「A group item is written with the corporate mark」。
    func testGroupItemIsWrittenWithTheCorporateMark() throws {
        try seedDefault()
        _ = try run(minimal(["authors": [["literal": "Katrina G. Claw"],
                                         ["group": "Summer internship for INdigenous peoples in Genomics (SING) Consortium"]]]),
                    dryRun: false)
        let e = try XCTUnwrap(LibraryStore(root: root).load().entries.first)
        XCTAssertEqual(e.authors, [.literal("Katrina G. Claw"),
                                   .literal("{Summer internship for INdigenous peoples in Genomics (SING) Consortium}")])
    }

    // MARK: - 2.2 已歸戶的位置要被沿用或明列釋放（spec「Every resolved author position SHALL be carried over or explicitly released」）

    private func seedResolved() throws {
        digest = try storedPDF()
        try seed(authors: [.literal("A"), .key("garrison-nanibaa"), .literal("B")], sources: [digest])
    }

    /// spec「A silently dropped key is refused」。
    func testSilentlyDroppedKeyIsRefusedNamingPositionAndKey() throws {
        try seedResolved()
        XCTAssertThrowsError(try run(minimal(["authors": [["literal": "A"], ["literal": "Nanibaa' A. Garrison"]]]))) { error in
            let m = String(describing: error)
            XCTAssertTrue(m.contains("第 1 位") && m.contains("garrison-nanibaa"), m)
        }
    }

    /// spec「A key is carried over by position」。
    func testKeyIsCarriedOverByPosition() throws {
        try seedResolved()
        _ = try run(minimal(["authors": [["literal": "A"], ["from": 1]]]), dryRun: false)
        XCTAssertEqual(try XCTUnwrap(LibraryStore(root: root).load().entries.first).authors,
                       [.literal("A"), .key("garrison-nanibaa")])
    }

    /// spec「A key is released with a reason」：照做、報告列出位置、值與理由；不刪任何 verdict。
    func testKeyReleasedWithReasonProceedsAndIsListed() throws {
        try seedResolved()
        var p = Person(key: "garrison-nanibaa")
        p.references = [ProvenanceReference(
            field: "resolution-confirmed",
            value: ProvenanceReference.VerdictPairingValue(holderKind: .work, holder: "claw2018framework",
                                                          literal: "Garrison, Nanibaa' A.").encoded,
            kind: .judgement(statement: "byline 對得上", restsOn: []))]
        let personURL = try LibraryStore(root: root).writePerson(p)
        StoreGitCommit.commitAll(root)
        let personBytes = try Data(contentsOf: personURL)
        let out = try run(minimal(["authors": [["literal": "A"]],
                                   "release": [["index": 1, "reason": "byline 上沒有這一位"]]]), dryRun: false)
        let released = try XCTUnwrap(out["released"] as? [[String: Any]])
        XCTAssertEqual(released.count, 1)
        XCTAssertEqual(released.first?["index"] as? Int, 1)
        XCTAssertEqual(released.first?["value"] as? String, "key:garrison-nanibaa")
        XCTAssertEqual(released.first?["reason"] as? String, "byline 上沒有這一位")
        XCTAssertEqual(try Data(contentsOf: personURL), personBytes, "釋放不刪、不改任何 verdict")
        let listed = try XCTUnwrap(out["verdictsOnRetiredLiterals"] as? [[String: Any]])
        XCTAssertEqual(listed.first?["record"] as? String, "person:garrison-nanibaa")
        XCTAssertEqual(listed.first?["literal"] as? String, "Garrison, Nanibaa' A.")
        XCTAssertEqual(listed.first?["carriedOver"] as? Bool, false)
    }

    func testReleaseAndFromMisuseIsRefused() throws {
        try seedResolved()
        assertRefused(minimal(["authors": [["from": 1]], "release": [["index": 0, "reason": "r"]]]), mentions: "literal")
        assertRefused(minimal(["authors": [["from": 1]], "release": [["index": 1, "reason": "r"]]]), mentions: "同時被 from 沿用")
        assertRefused(minimal(["authors": [["literal": "A"]],
                               "release": [["index": 1, "reason": "r"], ["index": 1, "reason": "r2"]]]), mentions: "出現兩次")
        assertRefused(minimal(["authors": [["from": 1], ["from": 1]]]), mentions: "用了兩次")
        assertRefused(minimal(["authors": [["from": 3]]]), mentions: "超出")
        assertRefused(minimal(["authors": [["literal": "A"]], "release": [["index": 9, "reason": "r"]]]), mentions: "超出")
    }

    // MARK: - 2.3 舊作者列的記錄一併移除並逐筆列出（spec「Records about the previous author list SHALL be removed and listed」）

    /// spec「A split record and a witness are removed」。
    func testSplitRecordAndWitnessAreRemovedAndListed() throws {
        digest = try storedPDF()
        var e = Entry(id: UUID(), citekey: "claw2018framework", type: .periodicalArticle, title: "T",
                      authors: [.literal("A"), .literal("B")])
        e.akashic.sources = [digest]
        e.references = [ProvenanceReference(field: "authors", value: "A與B",
                                            kind: .judgement(statement: "拆為 ⟦A⟧ ⟦B⟧：黏成一格", restsOn: []))]
        e.akashic.authorListCompleteness = try AuthorListCompletenessWitness(
            workID: e.id, fingerprint: AuthorListFingerprint(authors: e.authors), attestedAuthors: e.authors,
            references: [ProvenanceReference(field: "authors",
                                             kind: .retrieval(url: "https://www.nature.com/articles/s41467-018-05188-3",
                                                              retrieved: "2026-10-24", status: 200,
                                                              mediaType: "text/html", content: digest)),
                         ProvenanceReference(field: "authors",
                                             kind: .judgement(statement: "The PDF enumerates the complete author list.",
                                                              restsOn: [digest]))])
        try LibraryStore(root: root).writeEntry(e)
        StoreGitCommit.commitAll(root)
        let out = try run(minimal(["authors": [["literal": "A"], ["literal": "B"], ["literal": "C"]]]), dryRun: false)
        let removed = try XCTUnwrap(out["recordsRemoved"] as? [[String: Any]])
        XCTAssertEqual(removed.count, 1)
        XCTAssertEqual(removed.first?["value"] as? String, "A與B")
        XCTAssertEqual(removed.first?["statement"] as? String, "拆為 ⟦A⟧ ⟦B⟧：黏成一格")
        XCTAssertEqual(out["witnessRemoved"] as? Bool, true)
        let detail = try XCTUnwrap(out["witnessRemovedDetail"] as? [String: Any], "裁決 4：證言逐筆列出")
        XCTAssertEqual(detail["fingerprint"] as? String, AuthorListFingerprint(authors: [.literal("A"), .literal("B")]).digest)
        XCTAssertEqual(detail["attestedAuthors"] as? [String], ["A", "B"])
        XCTAssertEqual(detail["references"] as? Int, 2)
        let after = try XCTUnwrap(LibraryStore(root: root).load().entries.first)
        XCTAssertTrue(after.splitRecords.isEmpty)
        XCTAssertNil(after.akashic.authorListCompleteness)
        XCTAssertEqual(after.authorListReplacementRecord?.record.segments, ["A", "B", "C"])
        XCTAssertEqual(after.authorListReplacementRecord?.record.page, 1)
        XCTAssertEqual(after.authorListReplacementRecord?.source, digest)
    }

    /// spec「An uncommitted work file is refused」。
    func testUncommittedWorkFileIsRefusedWithZeroWrites() throws {
        try seedDefault()
        var e = try XCTUnwrap(LibraryStore(root: root).load().entries.first)
        e.title = "未 commit 的修改"
        let url = try LibraryStore(root: root).writeEntry(e)
        let bytes = try Data(contentsOf: url)
        XCTAssertThrowsError(try run(minimal(), dryRun: false))
        XCTAssertEqual(try Data(contentsOf: url), bytes, "零寫入")
        XCTAssertNoThrow(try run(minimal()), "乾跑不需要 git 閘")
    }

    // MARK: - 2.4 group-members 的寫入規則

    private let singName = "Summer internship for INdigenous peoples in Genomics (SING) Consortium"
    private let thirteen = ["Joseph M. Yracheta", "Krystal S. Tsosie", "Alice Popejoy", "Deborah A. Bolnick",
                            "Keolu Fox", "Jessica Bardill", "Rene L. Begay", "Lucas Brutus", "Jasmine Joseph",
                            "Sean Fullerton", "Paul G. Spicer", "Ripan S. Malhi", "Kim TallBear"]

    /// spec「Members are stored on the work」。
    func testThirteenMembersAreStoredInOrderAndNotInAuthors() throws {
        try seedDefault()
        _ = try run(minimal(["authors": [["literal": "Katrina G. Claw"], ["group": singName]],
                             "groupMembers": [["group": singName, "page": 7, "members": thirteen]]]), dryRun: false)
        let e = try XCTUnwrap(LibraryStore(root: root).load().entries.first)
        XCTAssertEqual(e.groupMembers.count, 1)
        XCTAssertEqual(e.groupMembers.first?.group, "{\(singName)}")
        XCTAssertEqual(e.groupMembers.first?.members, thirteen)
        XCTAssertEqual(e.groupMembers.first?.page, 7)
        XCTAssertEqual(e.groupMembers.first?.restsOn, digest)
        for m in thirteen { XCTAssertFalse(e.authors.contains(.literal(m)), m) }
    }

    /// spec「A member list for an unknown group is refused」；同一組兩次、空名單、逐字重複同樣拒絕。
    func testMemberListShapeIsRefused() throws {
        try seedDefault()
        let authors: [[String: Any]] = [["literal": "Katrina G. Claw"], ["group": singName]]
        assertRefused(minimal(["authors": authors, "groupMembers": [["group": "Other Consortium", "page": 7, "members": ["A"]]]]),
                      mentions: "對不上")
        assertRefused(minimal(["authors": authors, "groupMembers": [["group": singName, "page": 7, "members": ["A"]],
                                                                    ["group": singName, "page": 8, "members": ["B"]]]]),
                      mentions: "兩組")
        assertRefused(minimal(["authors": authors, "groupMembers": [["group": singName, "page": 7, "members": []]]]),
                      mentions: "至少")
        assertRefused(minimal(["authors": authors, "groupMembers": [["group": singName, "page": 7, "members": ["A", "A"]]]]),
                      mentions: "重複")
    }

    /// spec「Omitting groupMembers drops lists whose group is gone」；對得上的那一組留著。
    func testOmittingGroupMembersKeepsMatchingListsAndDropsTheRest() throws {
        try seedDefault()
        _ = try run(minimal(["authors": [["literal": "Katrina G. Claw"], ["group": singName], ["group": "Old Consortium"]],
                             "groupMembers": [["group": singName, "page": 7, "members": ["A"]],
                                              ["group": "Old Consortium", "page": 8, "members": ["B"]]]]), dryRun: false)
        StoreGitCommit.commitAll(root)
        let out = try run(minimal(["authors": [["literal": "Katrina G. Claw"], ["group": singName]]]), dryRun: false)
        let removed = try XCTUnwrap(out["groupMembersRemoved"] as? [[String: Any]])
        XCTAssertEqual(removed.map { $0["group"] as? String }, ["{Old Consortium}"])
        let e = try XCTUnwrap(LibraryStore(root: root).load().entries.first)
        XCTAssertEqual(e.groupMembers.map(\.group), ["{\(singName)}"])
    }

    /// 給了空陣列＝整組替換成沒有名單（與省略不同）。
    func testEmptyGroupMembersReplacesWholesale() throws {
        try seedDefault()
        _ = try run(minimal(["authors": [["group": singName]],
                             "groupMembers": [["group": singName, "page": 7, "members": ["A"]]]]), dryRun: false)
        StoreGitCommit.commitAll(root)
        _ = try run(minimal(["authors": [["group": singName]], "groupMembers": []]), dryRun: false)
        XCTAssertEqual(try XCTUnwrap(LibraryStore(root: root).load().entries.first).groupMembers, [])
    }

    /// spec「Combining with another leg is refused」。
    func testCombiningWithAnotherLegIsRefused() throws {
        try seedDefault()
        XCTAssertThrowsError(try service.updateEntry(citekey: "claw2018framework", removeFields: ["journaltitle=x"],
                                                     replaceAuthors: try body(minimal()), dryRun: true)) { error in
            XCTAssertTrue(String(describing: error).contains("replace_authors"), "\(error)")
        }
    }

    // MARK: - 7.1–7.4 第一輪 verify 之後（#742 verify 報告，2026-10-25）

    /// 替換腿層的 witness 夾具：fingerprint 綁 `authors`。
    private func witness(for e: Entry) throws -> AuthorListCompletenessWitness {
        try AuthorListCompletenessWitness(
            workID: e.id, fingerprint: AuthorListFingerprint(authors: e.authors), attestedAuthors: e.authors,
            references: [ProvenanceReference(field: "authors",
                                             kind: .retrieval(url: "https://www.nature.com/articles/s41467-018-05188-3",
                                                              retrieved: "2026-10-24", status: 200,
                                                              mediaType: "text/html", content: digest)),
                         ProvenanceReference(field: "authors",
                                             kind: .judgement(statement: "The PDF enumerates the complete author list.",
                                                              restsOn: [digest]))])
    }

    /// spec「Names are compared by bytes」：NFC 與 NFD 的 José 是兩位成員；NFD 的 group 對不上 NFC 的團體位。
    func testNamesAreComparedByBytes() throws {
        try seedDefault()
        let nfc = "Jos\u{E9}", nfd = "Jose\u{301}"
        XCTAssertEqual(nfc, nfd, "前提：Swift 的 String == 把兩者當成同一個值")
        let out = try run(minimal(["authors": [["literal": "Katrina G. Claw"], ["group": "Consortium \(nfc)"]],
                                   "groupMembers": [["group": "Consortium \(nfc)", "page": 7, "members": [nfc, nfd]]]]))
        let after = try XCTUnwrap(out["groupMembersAfter"] as? [[String: Any]])
        XCTAssertEqual((after.first?["members"] as? [String])?.count, 2, "兩種寫法是兩個值")
        assertRefused(minimal(["authors": [["literal": "Katrina G. Claw"], ["group": "Consortium \(nfc)"]],
                               "groupMembers": [["group": "Consortium \(nfd)", "page": 7, "members": ["A"]]]]),
                      mentions: "對不上")
    }

    /// 7.2：名字不得含控制字元——PDF 抽出的 byline 常把一個名字折成兩行。
    func testNamesWithControlCharactersAreRefused() throws {
        try seedDefault()
        assertRefused(minimal(["authors": [["literal": "Katrina G.\nClaw"]]]), mentions: "控制字元")
        assertRefused(minimal(["authors": [["group": "SING\tConsortium"]]]), mentions: "控制字元")
        assertRefused(minimal(["authors": [["group": singName]],
                               "groupMembers": [["group": singName, "page": 7, "members": ["Joseph M.\nYracheta"]]]]),
                      mentions: "控制字元")
    }

    /// 7.2：團體名加上 corporate 標記之後要仍是帶標記的名字。
    func testGroupWhoseBracesDoNotBalanceIsRefused() throws {
        try seedDefault()
        assertRefused(minimal(["authors": [["group": "A} {B"]]]), mentions: "大括號")
        assertRefused(minimal(["authors": [["group": "{A"]]]), mentions: "大括號")
    }

    /// 7.2：整數精確解碼——超出 Int 的數不截斷、不繞回。
    func testIntegersOutsideTheIntRangeAreRefused() throws {
        try seedDefault()
        for (label, raw) in [
            ("page", #"{"source":"\#(digest)","page":9223372036854775808,"reason":"r","authors":[{"literal":"A"}]}"#),
            ("page", #"{"source":"\#(digest)","page":18446744073709551617,"reason":"r","authors":[{"literal":"A"}]}"#),
            ("from", #"{"source":"\#(digest)","page":1,"reason":"r","authors":[{"from":18446744073709551616}]}"#),
        ] {
            XCTAssertThrowsError(try service.updateEntry(citekey: "claw2018framework", removeFields: nil,
                                                         replaceAuthors: Data(raw.utf8), dryRun: true), raw) { error in
                let m = String(describing: error)
                XCTAssertTrue(m.contains(label) && m.contains("整數範圍"), "\(raw) → \(m)")
            }
        }
    }

    /// spec「A source that is not a PDF is refused」。
    func testSourceThatIsNotAPDFIsRefused() throws {
        let f = root.appendingPathComponent("in-note.txt")
        try Data("notes about claw2018".utf8).write(to: f)
        let stored = try json(try service.storeSource(path: f.path, mediaType: "text/plain",
                                                      retrieved: "2026-10-24T10:00:00+08:00",
                                                      origin: "https://example.org/notes.txt",
                                                      acquisition: "browser-download", note: "notes"))
        try FileManager.default.removeItem(at: f)
        digest = try XCTUnwrap(stored["digest"] as? String)
        try seed(authors: [.literal("Claw, Katrina G.")], sources: [digest])
        assertRefused(minimal(), mentions: "application/pdf")
    }

    /// spec「A carried-over group position can hold a member list」（design D6）。
    func testCarriedOverGroupPositionCanHoldMembers() throws {
        digest = try storedPDF()
        try seed(authors: [.literal("Katrina G. Claw"), .literal("{SING Consortium}")], sources: [digest])
        let out = try run(minimal(["authors": [["from": 0], ["from": 1]],
                                   "groupMembers": [["group": "SING Consortium", "page": 7, "members": ["A", "B"]]]]),
                          dryRun: false)
        XCTAssertEqual((out["groupMembersAfter"] as? [[String: Any]])?.first?["group"] as? String, "{SING Consortium}")
        let e = try XCTUnwrap(LibraryStore(root: root).load().entries.first)
        XCTAssertEqual(e.groupMembers.first?.members, ["A", "B"])
    }

    /// spec「A member-list-only replacement keeps the records about the list」（design D5）。
    func testMemberListOnlyReplacementKeepsTheRecordsAboutTheList() throws {
        digest = try storedPDF()
        var e = Entry(id: UUID(), citekey: "claw2018framework", type: .periodicalArticle, title: "T",
                      authors: [.literal("A"), .literal("B"), .literal("{G}")])
        e.akashic.sources = [digest]
        e.references = [ProvenanceReference(field: "authors", value: "A與B",
                                            kind: .judgement(statement: "拆為 ⟦A⟧ ⟦B⟧：黏成一格", restsOn: []))]
        e.akashic.authorListCompleteness = try witness(for: e)
        try LibraryStore(root: root).writeEntry(e)
        StoreGitCommit.commitAll(root)
        let same: [[String: Any]] = [["literal": "A"], ["literal": "B"], ["group": "G"]]
        let first = try run(minimal(["authors": same, "groupMembers": [["group": "G", "page": 7, "members": ["X"]]]]),
                            dryRun: false)
        XCTAssertEqual((first["recordsRemoved"] as? [Any])?.count, 0, "\(first)")
        XCTAssertEqual(first["witnessRemoved"] as? Bool, false)
        XCTAssertNil(first["witnessRemovedDetail"])
        var after = try XCTUnwrap(LibraryStore(root: root).load().entries.first)
        XCTAssertEqual(after.splitRecords.count, 1, "作者列沒變，拆分記錄仍然描述它")
        XCTAssertNotNil(after.akashic.authorListCompleteness, "作者列沒變，證言仍然成立")
        XCTAssertNotNil(after.authorListReplacementRecord)
        StoreGitCommit.commitAll(root)
        let second = try run(minimal(["authors": same, "groupMembers": [["group": "G", "page": 7, "members": ["X", "Y"]]]]),
                             dryRun: false)
        let removed = try XCTUnwrap(second["recordsRemoved"] as? [[String: Any]])
        XCTAssertEqual(removed.count, 1, "只移除先前的替換記錄")
        XCTAssertTrue((removed.first?["statement"] as? String ?? "").hasPrefix("替換為"), "\(removed)")
        after = try XCTUnwrap(LibraryStore(root: root).load().entries.first)
        XCTAssertEqual(after.splitRecords.count, 1)
        XCTAssertEqual(after.groupMembers.first?.members, ["X", "Y"])
    }

    /// spec「Applying to a format-22 store is refused」「A dry run on a format-22 store still reports the plan」——在替換腿這一層。
    func testFormat22StoreDryRunReportsThePlanAndApplyIsRefused() throws {
        try seedDefault()
        try StoreVersion.write(root: root, format: 22)
        StoreGitCommit.commitAll(root)
        let entities = root.appendingPathComponent("entities")
        func bytes() throws -> [Data] {
            try FileManager.default.contentsOfDirectory(atPath: entities.path).sorted()
                .map { try Data(contentsOf: entities.appendingPathComponent($0)) }
        }
        let before = try bytes()
        let dry = try run(minimal())
        XCTAssertTrue((dry["applyRefusal"] as? String ?? "").contains("23"), "\(dry)")
        XCTAssertEqual(dry["authorsAfter"] as? [String], ["Katrina G. Claw"], "計畫照樣報出")
        assertRefused(minimal(), mentions: "23", dryRun: false)
        XCTAssertEqual(try bytes(), before, "零寫入")
    }

    /// 同一份 JSON 連跑兩次：第二次 unchanged——references 的次序不讓「沒變」看起來像變了。
    func testRerunningTheSameJSONIsUnchanged() throws {
        try seedDefault()
        let o = minimal(["authors": [["literal": "Katrina G. Claw"], ["group": singName]],
                         "groupMembers": [["group": singName, "page": 7, "members": ["A"]]]])
        _ = try run(o, dryRun: false)
        StoreGitCommit.commitAll(root)
        XCTAssertEqual(try run(o, dryRun: false)["unchanged"] as? Bool, true)
    }

    /// design Failure modes：work 無法唯一定位時拒絕。
    func testUnlocatableCitekeyIsRefused() throws {
        digest = try storedPDF()
        try seed(authors: [.literal("A")], sources: [digest])
        try seed(authors: [.literal("B")], sources: [digest])
        assertRefused(minimal(), mentions: "無法唯一定位")
    }

    // MARK: - 8.x 第二輪 verify 之後（#742 第二輪 verify 報告，2026-10-26）

    /// organization 帶一筆把本 work 與一個 literal 配對的 confirmed verdict（attribute-org 升格時留下的）。
    private func organization(_ key: String, promotedFrom literal: String? = nil) throws {
        var refs: [ProvenanceReference] = []
        if let literal {
            refs = [ProvenanceReference(field: ProvenanceReference.resolutionConfirmedField,
                                        value: ProvenanceReference.VerdictPairingValue(holderKind: .work, holder: "claw2018framework",
                                                                                       literal: literal).encoded,
                                        kind: .judgement(statement: "byline 的團體就是這個機構", restsOn: []))]
        }
        try LibraryStore(root: root).writeOrganization(Organization(key: key, references: refs))
    }

    /// spec「A promoted group position keeps its member list」（design D6）。
    func testPromotedGroupPositionKeepsItsMemberList() throws {
        digest = try storedPDF()
        try organization("sing-consortium", promotedFrom: "{SING Consortium}")
        var e = Entry(id: UUID(), citekey: "claw2018framework", type: .periodicalArticle, title: "T",
                      authors: [.literal("Katrina G. Claw"), .organization("sing-consortium")])
        e.akashic.sources = [digest]
        e.groupMembers = [try XCTUnwrap(GroupMemberList(group: "{SING Consortium}", restsOn: digest, page: 7, members: ["A", "B"]))]
        try LibraryStore(root: root).writeEntry(e)
        StoreGitCommit.commitAll(root)
        let kept = try run(minimal(["authors": [["literal": "Katrina Claw"], ["from": 1]]]), dryRun: false)
        XCTAssertEqual((kept["groupMembersRemoved"] as? [Any])?.count, 0, "\(kept)")
        XCTAssertEqual(try XCTUnwrap(LibraryStore(root: root).load().entries.first).groupMembers.first?.members, ["A", "B"])
        StoreGitCommit.commitAll(root)
        _ = try run(minimal(["authors": [["from": 0], ["from": 1]],
                             "groupMembers": [["group": "SING Consortium", "page": 7, "members": ["A", "B", "C"]]]]), dryRun: false)
        XCTAssertEqual(try XCTUnwrap(LibraryStore(root: root).load().entries.first).groupMembers.first?.members, ["A", "B", "C"])
    }

    /// 8.4：名字閘與 repo 的單一定義（`UnsafeToEmitScalar`，#569）同一份；組合記號開頭會和段括號黏在一起。
    func testNameGateMatchesTheRepositoryDefinition() throws {
        try seedDefault()
        assertRefused(minimal(["authors": [["literal": "Katrina\u{200B}Claw"]]]), mentions: "U+200B")
        assertRefused(minimal(["authors": [["literal": "Katrina G. Claw\u{E0041}"]]]), mentions: "U+E0041")
        assertRefused(minimal(["authors": [["literal": "Katrina \u{202E}Claw"]]]), mentions: "U+202E")
        assertRefused(minimal(["authors": [["literal": "\u{301}Abc"]]]), mentions: "組合記號")
        assertRefused(minimal(["authors": [["group": singName]],
                               "groupMembers": [["group": singName, "page": 7, "members": ["Joseph\u{200B}Yracheta"]]]]),
                      mentions: "U+200B")
        XCTAssertNoThrow(try run(minimal(["authors": [["literal": "علی\u{200C}رضا"]]])), "波斯文的 ZWNJ 合法")
    }

    /// 8.5：先前的替換記錄在原位換掉——它後面還有別的 reference 時，重跑同一份 JSON 仍是 unchanged、recordsRemoved 為空。
    func testRerunWithAReferenceAfterTheRecordIsUnchanged() throws {
        try seedDefault()
        let o = minimal(["authors": [["literal": "Katrina G. Claw"]]])
        _ = try run(o, dryRun: false)
        var e = try XCTUnwrap(LibraryStore(root: root).load().entries.first)
        e.fields["volume"] = "9"
        e.references.append(ProvenanceReference(field: "fields.volume", value: nil,
                                                kind: .judgement(statement: "PDF 第 1 頁", restsOn: [digest])))
        try LibraryStore(root: root).writeEntry(e)
        StoreGitCommit.commitAll(root)
        let again = try run(o, dryRun: false)
        XCTAssertEqual(again["unchanged"] as? Bool, true, "\(again)")
        XCTAssertEqual((again["recordsRemoved"] as? [Any])?.count, 0, "沒變就沒有移除")
    }

    /// 8.8：organization 位的沿用與釋放。
    func testOrganizationPositionIsCarriedOverOrReleased() throws {
        digest = try storedPDF()
        try organization("iss")
        try seed(authors: [.organization("iss"), .literal("Claw, Katrina G.")], sources: [digest])
        assertRefused(minimal(["authors": [["literal": "Katrina G. Claw"]]]), mentions: "organization:iss")
        let carried = try run(minimal(["authors": [["from": 0], ["literal": "Katrina G. Claw"]]]))
        XCTAssertEqual(carried["authorsAfter"] as? [String], ["organization:iss", "Katrina G. Claw"])
        let released = try run(minimal(["authors": [["literal": "Katrina G. Claw"]],
                                        "release": [["index": 0, "reason": "PDF byline 沒有這個機構"]]]))
        XCTAssertEqual((released["released"] as? [[String: Any]])?.first?["value"] as? String, "organization:iss")
    }
}
