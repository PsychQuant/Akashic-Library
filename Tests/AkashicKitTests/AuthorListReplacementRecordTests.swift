import Foundation
import XCTest
@testable import AkashicCore
@testable import AkashicStoreIO

/// #742（Spectra change `reconcile-work-from-fulltext`）：作者列**替換記錄**——`field: authors` 的第三種記錄。
/// value 缺席、judgement、statement 走 `AuthorListReplacementRecordValue` 單一文法、rests-on 恰一個 digest
/// （design D2／D3）。預期值一律手寫字面量，不由被測程式算出。
final class AuthorListReplacementRecordTests: XCTestCase {

    // MARK: - 1.1 單一解析器

    /// 合法：七段、第 1 頁、理由。段內可含空白、逗號、冒號與 corporate 大括號。
    func testLegalStatementParsesAndRoundTrips() throws {
        let statement = "替換為 ⟦Stephanie M. Fullerton⟧ ⟦Nanibaa' A. Garrison⟧ ⟦key:garrison-nanibaa⟧"
            + " ⟦{Summer internship for INdigenous peoples in Genomics (SING) Consortium}⟧"
            + "；依據第 1 頁：PDF 第 1 頁 byline：團體只列一次"
        let v = try XCTUnwrap(AuthorListReplacementRecordValue.parse(statement))
        XCTAssertEqual(v.segments, [
            "Stephanie M. Fullerton", "Nanibaa' A. Garrison", "key:garrison-nanibaa",
            "{Summer internship for INdigenous peoples in Genomics (SING) Consortium}",
        ])
        XCTAssertEqual(v.page, 1)
        XCTAssertEqual(v.reason, "PDF 第 1 頁 byline：團體只列一次")
        XCTAssertEqual(v.encoded, statement, "encode 與 parse 互為反函數")

        let one = try XCTUnwrap(AuthorListReplacementRecordValue(segments: ["甲"], page: 12, reason: "r"))
        XCTAssertEqual(one.encoded, "替換為 ⟦甲⟧；依據第 12 頁：r")
        XCTAssertEqual(AuthorListReplacementRecordValue.parse("替換為 ⟦甲⟧；依據第 12 頁：r"), one)
    }

    /// 六種輸入（tasks 1.1）：合法之外的五種都回 nil。
    func testMalformedStatementsAreRejected() {
        XCTAssertNotNil(AuthorListReplacementRecordValue.parse("替換為 ⟦甲⟧ ⟦乙⟧；依據第 3 頁：理由"), "合法")
        XCTAssertNil(AuthorListReplacementRecordValue.parse("替換為 ⟦⟧ ⟦乙⟧；依據第 3 頁：理由"), "段為空")
        XCTAssertNil(AuthorListReplacementRecordValue.parse("替換為 ⟦甲⟦⟧ ⟦乙⟧；依據第 3 頁：理由"), "段含括號")
        XCTAssertNil(AuthorListReplacementRecordValue.parse("替換為 ⟦甲⟧ ⟦乙⟧：理由"), "缺頁序")
        XCTAssertNil(AuthorListReplacementRecordValue.parse("替換為 ⟦甲⟧ ⟦乙⟧；依據第 0 頁：理由"), "頁序 0")
        XCTAssertNil(AuthorListReplacementRecordValue.parse("替換為 ⟦甲⟧ ⟦乙⟧；依據第 3 頁：  "), "理由空白")
    }

    /// 邊界：零段、前導零、非 ASCII 數字、括號未關、括號外有字、拆分與移除的 statement 都不是替換記錄。
    func testBoundaryStatementsAreRejected() {
        XCTAssertNil(AuthorListReplacementRecordValue.parse("替換為 ；依據第 3 頁：理由"), "零段")
        XCTAssertNil(AuthorListReplacementRecordValue.parse("替換為 ⟦甲⟧；依據第 03 頁：理由"), "前導零——同一個頁序只有一種寫法")
        XCTAssertNil(AuthorListReplacementRecordValue.parse("替換為 ⟦甲⟧；依據第 ３ 頁：理由"), "全形數字")
        XCTAssertNil(AuthorListReplacementRecordValue.parse("替換為 ⟦甲；依據第 3 頁：理由"), "括號未關")
        XCTAssertNil(AuthorListReplacementRecordValue.parse("替換為 甲 ⟦乙⟧；依據第 3 頁：理由"), "括號外有字")
        XCTAssertNil(AuthorListReplacementRecordValue.parse("替換為 ⟦甲⟧；依據第 99999999999999999999 頁：理由"), "頁序溢位")
        XCTAssertNil(AuthorListReplacementRecordValue.parse("拆為 ⟦甲⟧ ⟦乙⟧：理由"), "拆分記錄")
        XCTAssertNil(AuthorListReplacementRecordValue.parse("移除：理由"), "移除記錄")
        XCTAssertNil(AuthorListReplacementRecordValue(segments: [], page: 1, reason: "r"))
        XCTAssertNil(AuthorListReplacementRecordValue(segments: ["甲⟧"], page: 1, reason: "r"))
        XCTAssertNil(AuthorListReplacementRecordValue(segments: ["甲"], page: 0, reason: "r"))
        XCTAssertNil(AuthorListReplacementRecordValue(segments: ["甲"], page: -1, reason: "r"))
        XCTAssertNil(AuthorListReplacementRecordValue(segments: ["甲"], page: 1, reason: " \n "))
    }

    // MARK: - 1.2 附著驗證：field: authors 的第三種記錄

    private let digestA = "sha256:" + String(repeating: "ab", count: 32)
    private let digestB = "sha256:" + String(repeating: "cd", count: 32)
    private let replacementStatement = "替換為 ⟦甲⟧ ⟦乙⟧；依據第 1 頁：byline"

    private func work(_ refs: [ProvenanceReference]) -> Entry {
        var e = Entry(id: UUID(), citekey: "claw2018framework", type: .periodicalArticle, title: "T",
                      authors: [.literal("甲"), .literal("乙")])
        e.references = refs
        return e
    }
    private func replacement(restsOn: [String], value: String? = nil,
                             statement: String? = nil) -> ProvenanceReference {
        ProvenanceReference(field: "authors", value: value,
                            kind: .judgement(statement: statement ?? replacementStatement, restsOn: restsOn))
    }
    private func assertRefused(_ e: Entry, _ note: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertThrowsError(try e.validateReferenceAttachment(), note, file: file, line: line)
    }

    func testReplacementRecordIsAcceptedAndReadBack() throws {
        let e = work([replacement(restsOn: [digestA])])
        XCTAssertNoThrow(try e.validateReferenceAttachment())
        let r = try XCTUnwrap(e.authorListReplacementRecord)
        XCTAssertEqual(r.record.segments, ["甲", "乙"])
        XCTAssertEqual(r.record.page, 1)
        XCTAssertEqual(r.source, digestA)
        XCTAssertTrue(e.splitRecords.isEmpty, "替換記錄不得被讀成拆分記錄")
        XCTAssertTrue(e.authorRemovalRecords.isEmpty, "替換記錄不得被讀成移除記錄")
    }

    /// 三種記錄靠 value 在場與否在形狀上分開：value 缺席的拆分 statement、帶 value 的替換 statement 都拒。
    func testValuePresenceSeparatesTheThreeRecords() {
        assertRefused(work([ProvenanceReference(field: "authors", value: nil,
                                                kind: .judgement(statement: "拆為 ⟦甲⟧ ⟦乙⟧：黏成一格", restsOn: []))]),
                      "value 缺席的拆分 statement")
        assertRefused(work([ProvenanceReference(field: "authors", value: nil,
                                                kind: .judgement(statement: "移除：佔位字串", restsOn: []))]),
                      "value 缺席的移除 statement")
        assertRefused(work([replacement(restsOn: [digestA], value: "甲與乙")]), "帶 value 的替換 statement")
        assertRefused(work([replacement(restsOn: [digestA], statement: "替換為 ⟦甲⟧：缺頁序")]),
                      "value 缺席、文法不合")
    }

    func testRestsOnMustHoldExactlyOneDigest() {
        assertRefused(work([replacement(restsOn: [digestA, digestB])]), "rests-on 兩個 digest")
        assertRefused(work([replacement(restsOn: [])]), "rests-on 空")
    }

    func testAtMostOneReplacementRecord() {
        assertRefused(work([replacement(restsOn: [digestA]), replacement(restsOn: [digestB])]), "兩筆替換記錄")
    }

    // MARK: - 1.3 group-members

    private let sing = "{Summer internship for INdigenous peoples in Genomics (SING) Consortium}"

    private func workWithMembers(_ lists: [GroupMemberList]) -> Entry {
        var e = Entry(id: UUID(uuidString: "D3060757-0000-4000-8000-000000000001")!,
                      citekey: "claw2018framework", type: .periodicalArticle, title: "T",
                      authors: [.literal("Katrina G. Claw"), .literal(sing)],
                      venues: [.literal("Nature Communications")])
        e.groupMembers = lists
        return e
    }

    func testGroupMembersRoundTripByteForByteAndSitRightAfterAuthors() throws {
        let list = try XCTUnwrap(GroupMemberList(group: sing, restsOn: digestA, page: 7,
                                                 members: ["Joseph M. Yracheta", "Krystal S. Tsosie", "Alice Popejoy"]))
        let yaml = try EntryYAML.encode(workWithMembers([list]))
        let expectedBlock = """
            group-members:
            - group: '\(sing)'
              rests-on: \(digestA)
              page: 7
              members:
              - Joseph M. Yracheta
              - Krystal S. Tsosie
              - Alice Popejoy
            """
        XCTAssertTrue(yaml.contains(expectedBlock), yaml)
        let authorsAt = try XCTUnwrap(yaml.range(of: "\nauthors:")).lowerBound
        let membersAt = try XCTUnwrap(yaml.range(of: "\ngroup-members:")).lowerBound
        let venuesAt = try XCTUnwrap(yaml.range(of: "\nvenues:")).lowerBound
        XCTAssertTrue(authorsAt < membersAt && membersAt < venuesAt, "group-members 緊接在 authors 之後")

        let back = try EntryYAML.decode(yaml)
        XCTAssertEqual(back.groupMembers, [list])
        XCTAssertEqual(try EntryYAML.encode(back), yaml, "寫出再讀回逐位元組相同")
    }

    func testNoGroupMembersWritesNoKey() throws {
        XCTAssertFalse(try EntryYAML.encode(workWithMembers([])).contains("group-members"), "既有記錄零 diff")
    }

    /// decode 拒絕：缺鍵、重複成員、空名單、頁序 0、團體名沒有 corporate 標記、同一組兩次、未知鍵、頁序非正規寫法。
    func testMalformedGroupMembersAreRefusedAtDecode() throws {
        let good = try EntryYAML.encode(workWithMembers([
            try XCTUnwrap(GroupMemberList(group: sing, restsOn: digestA, page: 7, members: ["A", "B"])),
        ]))
        func refused(_ from: String, _ to: String, _ note: String, line: UInt = #line) {
            XCTAssertTrue(good.contains(from), "fixture 要含「\(from)」", line: line)
            XCTAssertThrowsError(try EntryYAML.decode(good.replacingOccurrences(of: from, with: to)), note, line: line)
        }
        refused("  rests-on: \(digestA)\n", "", "缺 rests-on")
        refused("  page: 7\n", "", "缺 page")
        refused("  - B\n", "  - A\n", "重複成員")
        refused("  members:\n  - A\n  - B\n", "  members: []\n", "空名單")
        refused("  page: 7\n", "  page: 0\n", "頁序 0")
        refused("  page: 7\n", "  page: 07\n", "頁序非正規寫法")
        refused("- group: '\(sing)'\n", "- group: SING Consortium\n", "團體名沒有 corporate 標記")
        refused("  page: 7\n", "  page: 7\n  note: x\n", "未知鍵")
        refused("  rests-on: \(digestA)\n", "  rests-on: sha256:00\n", "digest 形狀不對")
        let twice = good.replacingOccurrences(
            of: "  - B\n", with: "  - B\n- group: '\(sing)'\n  rests-on: \(digestA)\n  page: 8\n  members:\n  - C\n")
        XCTAssertThrowsError(try EntryYAML.decode(twice), "同一組兩次")
    }

    func testGroupMemberListInitRejectsTheSameShapes() {
        XCTAssertNil(GroupMemberList(group: sing, restsOn: digestA, page: 7, members: []))
        XCTAssertNil(GroupMemberList(group: sing, restsOn: digestA, page: 7, members: ["A", "A"]))
        XCTAssertNil(GroupMemberList(group: sing, restsOn: digestA, page: 7, members: [" A"]))
        XCTAssertNil(GroupMemberList(group: sing, restsOn: digestA, page: 7, members: [""]))
        XCTAssertNil(GroupMemberList(group: sing, restsOn: digestA, page: 0, members: ["A"]))
        XCTAssertNil(GroupMemberList(group: "SING", restsOn: digestA, page: 7, members: ["A"]))
        XCTAssertNil(GroupMemberList(group: sing, restsOn: ProvenanceReference.emptyContentDigest,
                                     page: 7, members: ["A"]), "空內容的 digest")
    }

    // MARK: - 1.4 store format 23（spec「The new shapes SHALL be governed by store format 23」）

    private func scratchStore(format: Int) throws -> (URL, LibraryStore) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("akashic-alr-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root.appendingPathComponent("entities"),
                                                withIntermediateDirectories: true)
        try StoreVersion.write(root: root, format: format)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return (root, LibraryStore(root: root))
    }

    func testSupportedIs23() {
        XCTAssertEqual(StoreVersion.supported, 23)
        XCTAssertEqual(StoreVersion.authorListReplacementFormat, 23)
    }

    func testFormat22RefusesBothNewShapesAndNamesFormat23() throws {
        let (root, store) = try scratchStore(format: 22)
        let withRecord = work([replacement(restsOn: [digestA])])
        let withMembers = workWithMembers([
            try XCTUnwrap(GroupMemberList(group: sing, restsOn: digestA, page: 7, members: ["A"])),
        ])
        for (what, e) in [("替換記錄", withRecord), ("成員名單", withMembers)] {
            XCTAssertThrowsError(try store.writeEntry(e), what) { error in
                XCTAssertTrue(String(describing: error).contains("23"), "\(what)：\(error)")
            }
        }
        let entities = try FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent("entities").path)
        XCTAssertTrue(entities.isEmpty, "零寫入：\(entities)")
        XCTAssertEqual(try StoreVersion.read(root: root), 22, "marker 不動")
    }

    func testFormat22StillWritesWorksWithoutTheNewShapes() throws {
        let (_, store) = try scratchStore(format: 22)
        XCTAssertNoThrow(try store.writeEntry(work([])))
    }

    func testFormat23WritesAndReloadsBothShapes() throws {
        let (_, store) = try scratchStore(format: 23)
        var e = workWithMembers([
            try XCTUnwrap(GroupMemberList(group: sing, restsOn: digestA, page: 7, members: ["A", "B"])),
        ])
        e.references = [replacement(restsOn: [digestA],
                                    statement: "替換為 ⟦Katrina G. Claw⟧ ⟦\(sing)⟧；依據第 1 頁：byline")]
        try store.writeEntry(e)
        let load = try store.load()
        XCTAssertEqual(load.quarantined.count, 0, "\(load.quarantined)")
        let back = try XCTUnwrap(load.entries.first { $0.citekey == "claw2018framework" })
        XCTAssertEqual(back.groupMembers.first?.members, ["A", "B"])
        XCTAssertEqual(back.authorListReplacementRecord?.record.segments, ["Katrina G. Claw", sing])
    }

    // MARK: - 1.5 work 合併的遺失檢查

    /// 兩筆攣生 work（同一篇的兩次匯入）＋一筆 work 歧異記錄，在 git 裡 commit 好（合併要求檔案可取回）。
    private func seedTwins(keeper: Entry, doomed: Entry) throws -> (LibraryStore, Divergence) {
        let (root, store) = try scratchStore(format: StoreVersion.supported)
        GitFixture.initRepo(root)
        try store.writeEntry(keeper)
        try store.writeEntry(doomed)
        let d = Divergence(id: UUID(), question: "是否同一篇",
                           candidates: [DivergenceCandidate(key: keeper.citekey, shape: .work),
                                        DivergenceCandidate(key: doomed.citekey, shape: .work)])
        try store.writeDivergence(d)
        GitFixture.commitAll(root, message: "seed")
        return (store, d)
    }
    private func twin(_ citekey: String) -> Entry {
        Entry(id: UUID(), citekey: citekey, type: .periodicalArticle, title: "T",
              authors: [.literal("Katrina G. Claw"), .literal(sing)])
    }

    func testMergeRefusesWhenOnlyTheDoomedTwinCarriesGroupMembers() throws {
        var doomed = twin("claw2018frameworkb")
        doomed.groupMembers = [try XCTUnwrap(GroupMemberList(group: sing, restsOn: digestA, page: 7,
                                                             members: ["Joseph M. Yracheta"]))]
        let (store, d) = try seedTwins(keeper: twin("claw2018framework"), doomed: doomed)
        for run in [{ try store.previewResolveDivergence(id: d.id, survivor: "claw2018framework", overrideReason: nil) },
                    { try store.resolveDivergence(id: d.id, survivor: "claw2018framework") }] {
            XCTAssertThrowsError(try run()) { error in
                guard case DivergenceResolveError.wouldLoseFields(_, _, let losses) = error else {
                    return XCTFail("預期 wouldLoseFields，實得 \(error)")
                }
                XCTAssertTrue(losses.contains { $0.contains("group-members") && $0.contains("SING") }, "\(losses)")
            }
        }
    }

    func testMergeLossCheckUsesTheDifferenceOfMemberLists() throws {
        let list = try XCTUnwrap(GroupMemberList(group: sing, restsOn: digestA, page: 7, members: ["A"]))
        var keeper = twin("k"), doomed = twin("d")
        keeper.groupMembers = [list]; doomed.groupMembers = [list]
        XCTAssertFalse(LibraryStore.fieldsLostByMerging(doomed, into: keeper).contains { $0.contains("group-members") },
                       "兩邊同一組名單：沒有東西會遺失")
        doomed.groupMembers = [try XCTUnwrap(GroupMemberList(group: sing, restsOn: digestA, page: 7, members: ["A", "B"]))]
        XCTAssertTrue(LibraryStore.fieldsLostByMerging(doomed, into: keeper).contains { $0.contains("group-members") },
                      "名單不同：被併者那一組不在倖存者身上")
    }

    /// 被併者的替換記錄照 references 的既有差集判準報出（不另寫一條）。
    func testMergeLossCheckReportsTheDoomedReplacementRecord() {
        let keeper = twin("k")
        var doomed = twin("d")
        doomed.references = [replacement(restsOn: [digestA])]
        XCTAssertTrue(LibraryStore.fieldsLostByMerging(doomed, into: keeper).contains { $0.hasPrefix("references") && $0.contains("authors") },
                      "\(LibraryStore.fieldsLostByMerging(doomed, into: keeper))")
    }

    // MARK: - 3.1 替換記錄失效的 warning（spec「A stale replacement record SHALL be reported as a warning」）

    /// spec Example「Matching a record against the current list」四列逐字。
    func testStaleReplacementRecordMatchesTheSpecExampleTable() throws {
        let rows: [(authors: [Author], warns: Bool)] = [
            ([.literal("A"), .literal("B")], false),
            ([.literal("A"), .key("b-person")], false),
            ([.literal("A"), .literal("B2")], true),
            ([.literal("A"), .literal("B1"), .literal("B2")], true),
        ]
        for (i, row) in rows.enumerated() {
            let (_, store) = try scratchStore(format: StoreVersion.supported)
            var e = Entry(id: UUID(), citekey: "claw2018framework", type: .periodicalArticle, title: "T", authors: row.authors)
            e.references = [replacement(restsOn: [digestA], statement: "替換為 ⟦A⟧ ⟦B⟧；依據第 1 頁：byline")]
            try store.writeEntry(e)
            let health = try store.health(from: store.load())
            XCTAssertEqual(health.staleReplacementRecords.count, row.warns ? 1 : 0, "第 \(i + 1) 列")
            XCTAssertTrue(health.staleReplacementRecords.allSatisfy { $0.issue.severity == .warning && $0.owner == "claw2018framework" })
            XCTAssertFalse(health.perRecordIssues.contains { $0.issue.severity == .error }, "warning 不讓 validate 變紅（第 \(i + 1) 列）")
        }
    }

    /// 7.1：失效判定比位元組——literal 換成 NFD 寫法，Swift 的 `==` 看不出差別，store 存的值卻已不同。
    func testStaleReplacementRecordComparesBytes() throws {
        let (_, store) = try scratchStore(format: StoreVersion.supported)
        var e = Entry(id: UUID(), citekey: "claw2018framework", type: .periodicalArticle, title: "T",
                      authors: [.literal("A"), .literal("Jose\u{301}")])
        e.references = [replacement(restsOn: [digestA], statement: "替換為 ⟦A⟧ ⟦Jos\u{E9}⟧；依據第 1 頁：byline")]
        try store.writeEntry(e)
        XCTAssertEqual(try store.health(from: store.load()).staleReplacementRecords.count, 1)
    }

    /// 沒有替換記錄的 work 不會出這一族（零實例的空掃描不是通過——前一個測試證明它會響）。
    func testNoReplacementRecordNoWarning() throws {
        let (_, store) = try scratchStore(format: StoreVersion.supported)
        try store.writeEntry(work([]))
        XCTAssertTrue(try store.health(from: store.load()).staleReplacementRecords.isEmpty)
    }

    // MARK: - 6.6 entity-backlink 第 18 條邊：group-members 的 rests-on 是內容指標

    /// 名單依據的那份全文不在本機時，「本機缺承重存檔」要報出它——與 `akashic.sources`、`references` 的 digest 同一條路徑。
    func testGroupMembersDigestCountsAsAReferencedSource() throws {
        let (_, store) = try scratchStore(format: StoreVersion.supported)
        try store.writeEntry(workWithMembers([
            try XCTUnwrap(GroupMemberList(group: sing, restsOn: digestB, page: 7, members: ["A"])),
        ]))
        let report = try store.missingSourceDigests(store.load())
        XCTAssertTrue(report.holders.contains { $0.digest == digestB && $0.slot == "group-members.rests-on"
                                                && $0.owner == "claw2018framework" }, "\(report.holders)")
        let health = try store.health(from: store.load())
        XCTAssertTrue(health.danglingSources.contains { $0.owner == "claw2018framework" }, "\(health.danglingSources)")
    }

    /// 替換記錄與拆分記錄可以並存（拆分發生在替換之後——D8 的失效 warning 管它，decode 不擋）。
    func testReplacementCoexistsWithASplitRecord() {
        let split = ProvenanceReference(field: "authors", value: "甲乙",
                                        kind: .judgement(statement: "拆為 ⟦甲⟧ ⟦乙⟧：黏成一格", restsOn: []))
        XCTAssertNoThrow(try work([replacement(restsOn: [digestA]), split]).validateReferenceAttachment())
    }
}
