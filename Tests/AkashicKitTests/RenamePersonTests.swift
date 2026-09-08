import XCTest
@testable import AkashicCore
@testable import AkashicStoreIO

/// #395：person key 改名。
///
/// **每個遷移面各一條測試。** 這不是覆蓋率儀式——遷移面漏一格的後果是**安靜的**：
/// 檔案照樣載入，只是某些邊指向一個不存在的 key。#232 verify NEW-1 就是這個形狀
/// （`rename` 不遷移 verdict value → 一次否決安靜變回待判）。
final class RenamePersonTests: XCTestCase {
    private var root: URL!
    private var store: LibraryStore!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("akashic-rp-\(UUID().uuidString)")
        store = LibraryStore(root: root, key: nil, environment: [:])
        try store.ensureLayout()
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    private func person(_ key: String, names: [String] = ["N N"]) throws -> Person {
        let p = Person(key: key, names: PersonNames(variant: names))
        try store.writePerson(p)
        return p
    }

    // MARK: - 主體

    func testRenamesTheRecordItself() throws {
        _ = try person("old-key")
        _ = try store.renamePerson(from: "old-key", to: "new-key")
        let load = try store.load()
        XCTAssertNil(load.people.first { $0.key == "old-key" }, "舊 key 不該還在")
        XCTAssertNotNil(load.people.first { $0.key == "new-key" }, "新 key 該存在")
    }

    /// UUID 不變——改的是「稱呼」，不是身分（同 `rename` 之於 citekey）。
    func testIdentityIsPreserved() throws {
        let before = try person("old-key")
        _ = try store.renamePerson(from: "old-key", to: "new-key")
        let after = try store.load().people.first { $0.key == "new-key" }
        XCTAssertEqual(after?.id, before.id, "改名不得重發身分")
    }

    // MARK: - 遷移面 1：作品的 authors 邊（封閉列舉第 1 條）

    func testMigratesAuthorEdges() throws {
        _ = try person("old-key")
        try store.writeEntry(Entry(id: UUID(), citekey: "w1", type: .periodicalArticle,
                                   title: "T", authors: [.key("old-key"), .literal("Someone Else")],
                                   date: "2020"))
        try store.writeEntry(Entry(id: UUID(), citekey: "w2", type: .periodicalArticle,
                                   title: "T", authors: [.literal("X"), .key("old-key")],
                                   date: "2020"))
        let report = try store.renamePerson(from: "old-key", to: "new-key")

        XCTAssertEqual(report.authorEdgesRewritten, ["w1", "w2"])
        let load = try store.load()
        for ck in ["w1", "w2"] {
            let e = load.entries.first { $0.citekey == ck }
            XCTAssertTrue(e?.authors.contains(.key("new-key")) ?? false,
                          "\(ck) 的作者邊該指向新 key")
            XCTAssertFalse(e?.authors.contains(.key("old-key")) ?? true,
                           "\(ck) 不該還有舊 key")
        }
        // 其他作者位不得被動到
        XCTAssertTrue(load.entries.first { $0.citekey == "w1" }?
            .authors.contains(.literal("Someone Else")) ?? false)
    }

    // MARK: - 遷移面 2：verdict value 的 `person:<key>`（第 13 條）

    /// verdict 的 holder kind 是 `person` 時，value 內嵌 person key——
    /// **而它掛在 organization 上**（org-resolution：被判定的是機構，
    /// holder 是持有 affiliation literal 的那個人）。
    func testMigratesPersonHolderVerdictOnOrganization() throws {
        _ = try person("old-key")
        var org = Organization(key: "some-org")
        org.names = TimelineOf([TemporalValue(value: "Some Org", range: DateRange())])
        org.references = [ProvenanceReference(
            field: "resolution-confirmed",
            value: ProvenanceReference.VerdictPairingValue(
                holderKind: .person, holder: "old-key", literal: "Some Org").encoded,
            kind: .judgement(statement: "測試用判定", restsOn: []))]
        try store.writeOrganization(org)

        let report = try store.renamePerson(from: "old-key", to: "new-key")
        XCTAssertEqual(report.verdictValuesRewritten, [HolderRecord(.organization, "some-org")],
                       "掛在 organization 上的 person-holder verdict 必須遷移")
        let after = try store.load().organizations.first { $0.key == "some-org" }
        let v = after?.references.first?.value ?? ""
        XCTAssertTrue(v.contains("person:new-key"), "verdict value 未遷移：\(v)")
        XCTAssertFalse(v.contains("old-key"), "舊 key 殘留：\(v)")
    }

    /// `work:` holder 的 verdict **不得**被 person 改名動到——那是另一個命名空間。
    func testDoesNotTouchWorkHolderVerdicts() throws {
        _ = try person("old-key")
        var other = try person("bystander")
        other.references = [ProvenanceReference(
            field: "resolution-rejected",
            value: ProvenanceReference.VerdictPairingValue(
                holderKind: .work, holder: "old-key", literal: "Some Name").encoded,
            kind: .judgement(statement: "測試用否決", restsOn: []))]
        try store.writePerson(other)

        _ = try store.renamePerson(from: "old-key", to: "new-key")
        let after = try store.load().people.first { $0.key == "bystander" }
        XCTAssertTrue(after?.references.first?.value?.contains("work:old-key") ?? false,
                      "work holder 恰好同名時不得被 person 改名波及——那是不同命名空間")
    }

    // MARK: - 遷移面 3：divergence 的候選與 prefers（第 9、10 條）

    func testMigratesDivergenceCandidates() throws {
        _ = try person("old-key")
        _ = try person("other-key")
        let d = Divergence(id: UUID(), question: "同一人？",
                           candidates: [DivergenceCandidate(key: "old-key", shape: .person),
                                        DivergenceCandidate(key: "other-key", shape: .person)])
        try store.writeDivergence(d)

        let report = try store.renamePerson(from: "old-key", to: "new-key")
        XCTAssertEqual(report.divergencesRewritten, [d.id.uuidString])
        let after = try store.load().divergences.first
        XCTAssertTrue(after?.candidates.contains(DivergenceCandidate(key: "new-key", shape: .person)) ?? false)
    }

    /// **`prefers` 是 `renameEntry` 漏掉的那一格**（#395 發現）。
    ///
    /// 漏掉的後果是安靜的：`resolve-divergence` 用 `prefers != survivor` 擋下不一致，
    /// 而 `prefers` 指著一個已不存在的 key 時，**任何** survivor 都不等於它——
    /// 那筆歧異永遠消不掉，而改名什麼都沒說。
    func testMigratesJudgementPrefers() throws {
        _ = try person("old-key")
        _ = try person("other-key")
        var d = Divergence(id: UUID(), question: "同一人？",
                           candidates: [DivergenceCandidate(key: "old-key", shape: .person),
                                        DivergenceCandidate(key: "other-key", shape: .person)])
        d.judgement = Judgement(statement: "傾向前者",
                                          restsOn: ["sha256:c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3"],
                                          prefers: "old-key")
        try store.writeDivergence(d)

        _ = try store.renamePerson(from: "old-key", to: "new-key")
        let after = try store.load().divergences.first
        XCTAssertEqual(after?.judgement?.prefers, "new-key",
                       "prefers 未遷移——那筆歧異會永遠消不掉")
    }

    // MARK: - 守衛

    func testRefusesWhenTargetKeyIsTaken() throws {
        _ = try person("old-key")
        _ = try person("taken-key")
        XCTAssertThrowsError(try store.renamePerson(from: "old-key", to: "taken-key")) { e in
            XCTAssertTrue("\(e)".contains("已被其他記錄使用"), "\(e)")
        }
    }

    func testRefusesWhenSourceMissing() throws {
        XCTAssertThrowsError(try store.renamePerson(from: "nope", to: "new-key")) { e in
            XCTAssertTrue("\(e)".contains("來源不存在"), "\(e)")
        }
    }

    func testRefusesIdenticalKeys() throws {
        _ = try person("same")
        XCTAssertThrowsError(try store.renamePerson(from: "same", to: "same"))
    }

    /// 候選塌縮成一個時拒絕——改名沒有合併語意，不替使用者刪記錄（同 `rename`）。
    ///
    /// **`new-key` 必須是懸空候選**（指向不存在的記錄）才走得到這裡：若它是真的
    /// person，上面的「已被其他記錄使用」守衛會先擋。這正是 `renameEntry` 的
    /// 錯誤訊息寫的那句「能走到這裡代表新 key 是該記錄的一個懸空候選」——
    /// 而懸空候選連消歧都做不到，所以只能請使用者直接編輯那個檔。
    func testRefusesWhenDivergenceCandidatesWouldCollapse() throws {
        _ = try person("old-key")
        _ = try person("third-key")
        let d = Divergence(id: UUID(), question: "同一人？",
                           candidates: [DivergenceCandidate(key: "old-key", shape: .person),
                                        // 懸空：store 裡沒有 new-key 這個 person
                                        DivergenceCandidate(key: "new-key", shape: .person)])
        try store.writeDivergence(d)
        XCTAssertThrowsError(try store.renamePerson(from: "old-key", to: "new-key")) { e in
            XCTAssertTrue("\(e)".contains("塌縮"), "\(e)")
        }
    }

    /// 沒有任何其他記錄引用時，三個清單都空——而 CLI 會把「無副作用」明說出來
    /// （「沒有副作用」與「有副作用但沒印」在終端上不該長得一樣）。
    func testReportIsEmptyWhenNothingReferencesTheKey() throws {
        _ = try person("lonely")
        let report = try store.renamePerson(from: "lonely", to: "still-lonely")
        XCTAssertEqual(report, PersonRenameReport())
    }
}
