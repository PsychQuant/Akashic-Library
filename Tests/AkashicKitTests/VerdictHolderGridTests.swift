import Foundation
import XCTest
@testable import AkashicCore
@testable import AkashicStoreIO

/// #463：verdict holder 遷移網格（4 退役操作 × 3 記錄形狀）剩下的四格——
/// rename×organization、work-merge×organization、person-merge×organization、person-merge×person。
/// 每格一支 RED→GREEN 的測試；另以 live store 的形狀（多個 organization 各持一條指向同一 citekey 的
/// `work:` verdict，實測 9 條）模擬退役。機制鏡射 #232／#271／#460 的既有迴圈，helper 以 holderKind
/// 參數化（`migrateHolderVerdicts`）。
final class VerdictHolderGridTests: XCTestCase {
    private var root: URL!
    private var store: LibraryStore!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("akashic-vhg-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("entities"), withIntermediateDirectories: true)
        GitFixture.initRepo(root)
        try StoreVersion.write(root: root, format: StoreVersion.supported)
        store = LibraryStore(root: root)
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    private func entry(_ citekey: String) throws {
        try store.writeEntry(Entry(id: UUID(), citekey: citekey, type: .periodicalArticle,
                                   title: "T \(citekey)", authors: [.literal("A B")], date: "2020"))
    }

    private func verdict(_ field: String, kind: ProvenanceReference.VerdictHolderKind,
                         holder: String, literal: String) -> ProvenanceReference {
        ProvenanceReference(
            field: field,
            value: ProvenanceReference.VerdictPairingValue(holderKind: kind, holder: holder, literal: literal).encoded,
            kind: .judgement(statement: "測試用判定", restsOn: []))
    }

    private func org(_ key: String, refs: [ProvenanceReference]) throws {
        var o = Organization(key: key, names: TimelineOf([TemporalValue(value: "Org \(key)")]))
        o.references = refs
        _ = try store.writeOrganization(o)
    }

    private func holders(ofOrg key: String) throws -> [String] {
        try store.load().organizations.first { $0.key == key }?.references
            .compactMap { $0.value }.compactMap(ProvenanceReference.VerdictPairingValue.parse)
            .map { "\($0.holderKind.rawValue):\($0.holder)" } ?? []
    }

    private func holders(ofPerson key: String) throws -> [String] {
        try store.load().people.first { $0.key == key }?.references
            .compactMap { $0.value }.compactMap(ProvenanceReference.VerdictPairingValue.parse)
            .map { "\($0.holderKind.rawValue):\($0.holder)" } ?? []
    }

    private func holders(ofVenue key: String) throws -> [String] {
        try store.load().venues.first { $0.key == key }?.references
            .compactMap { $0.value }.compactMap(ProvenanceReference.VerdictPairingValue.parse)
            .map { "\($0.holderKind.rawValue):\($0.holder)" } ?? []
    }

    private func divergence(keeper: String, doomed: String, shape: EntityKind) throws -> Divergence {
        let d = Divergence(id: UUID(), question: "\(keeper) 與 \(doomed) 是同一個嗎",
                           candidates: [DivergenceCandidate(key: keeper, shape: shape),
                                        DivergenceCandidate(key: doomed, shape: shape)])
        _ = try store.writeDivergence(d)
        return d
    }

    // MARK: - rename × organization

    func testRenameMigratesOrganizationHeldWorkVerdict() throws {
        try entry("old2020a")
        try org("some-org", refs: [verdict("resolution-confirmed", kind: .work, holder: "old2020a", literal: "Some Org")])
        let report = try store.renameEntry(from: "old2020a", to: "new2020a")
        XCTAssertEqual(try holders(ofOrg: "some-org"), ["work:new2020a"])
        XCTAssertEqual(report.verdictValuesRewritten, ["some-org"])
    }

    // MARK: - work merge × organization

    func testWorkMergeMigratesOrganizationHeldWorkVerdict() throws {
        try entry("keeper2020a"); try entry("doomed2020a")
        try org("some-org", refs: [verdict("resolution-rejected", kind: .work, holder: "doomed2020a", literal: "Some Org")])
        let d = try divergence(keeper: "keeper2020a", doomed: "doomed2020a", shape: .work)
        GitFixture.commitAll(store.root)   // resolve 只在受 git 追蹤的檔上動刀（deletionNotRecoverable 閘）
        let report = try store.resolveDivergence(id: d.id, survivor: "keeper2020a")
        XCTAssertEqual(try holders(ofOrg: "some-org"), ["work:keeper2020a"])
        XCTAssertTrue(report.verdictValuesRewritten.contains("some-org"), "\(report)")
        XCTAssertTrue(report.failures.isEmpty, "\(report.failures)")
    }

    // MARK: - person merge × organization ／ × person

    func testPersonMergeMigratesPersonHoldersOnOrganizations() throws {
        try store.writePerson(Person(key: "keeper-person", names: ["Keeper Person"]))
        try store.writePerson(Person(key: "doomed-person", names: ["Doomed Person"]))
        try org("some-org", refs: [verdict("resolution-confirmed", kind: .person, holder: "doomed-person", literal: "Some Org")])
        let d = try divergence(keeper: "keeper-person", doomed: "doomed-person", shape: .person)
        GitFixture.commitAll(store.root)   // resolve 只在受 git 追蹤的檔上動刀（deletionNotRecoverable 閘）
        let report = try store.resolveDivergence(id: d.id, survivor: "keeper-person")
        XCTAssertEqual(try holders(ofOrg: "some-org"), ["person:keeper-person"])
        XCTAssertTrue(report.verdictValuesRewritten.contains("some-org"), "\(report)")
    }

    func testPersonMergeMigratesPersonHoldersOnPeople() throws {
        try store.writePerson(Person(key: "keeper-person", names: ["Keeper Person"]))
        try store.writePerson(Person(key: "doomed-person", names: ["Doomed Person"]))
        var third = Person(key: "third-person", names: ["Third Person"])
        third.references = [verdict("resolution-confirmed", kind: .person, holder: "doomed-person", literal: "X")]
        try store.writePerson(third)
        let d = try divergence(keeper: "keeper-person", doomed: "doomed-person", shape: .person)
        GitFixture.commitAll(store.root)   // resolve 只在受 git 追蹤的檔上動刀（deletionNotRecoverable 閘）
        let report = try store.resolveDivergence(id: d.id, survivor: "keeper-person")
        XCTAssertEqual(try holders(ofPerson: "third-person"), ["person:keeper-person"])
        XCTAssertTrue(report.verdictValuesRewritten.contains("third-person"), "\(report)")
    }

    /// survivor **自己**持有的 `person:<doomed>` holder：改寫在 commit 之前、對合併後的 keeper 做——合併進來的別名
    /// 不得被舊快照蓋掉（Codex R1 的 HIGH：post-commit 用 pre-commit 快照寫 survivor 會丟掉合併結果）。
    func testPersonMergeRewritesSurvivorsOwnPersonHolderAndKeepsMergedAliases() throws {
        var keeper = Person(key: "keeper-person", names: ["Keeper Person"])
        keeper.references = [verdict("resolution-confirmed", kind: .person, holder: "doomed-person", literal: "K")]
        try store.writePerson(keeper)
        try store.writePerson(Person(key: "doomed-person", names: ["Doomed Alias"]))
        let d = try divergence(keeper: "keeper-person", doomed: "doomed-person", shape: .person)
        GitFixture.commitAll(store.root)
        let report = try store.resolveDivergence(id: d.id, survivor: "keeper-person")
        let after = try store.load().people.first { $0.key == "keeper-person" }
        XCTAssertEqual(try holders(ofPerson: "keeper-person"), ["person:keeper-person"])
        XCTAssertTrue(after?.names.all.contains("Doomed Alias") ?? false, "合併進來的別名不得被舊快照蓋掉：\(String(describing: after?.names.all))")
        XCTAssertNil(try store.load().people.first { $0.key == "doomed-person" }, "doomed 不得復活")
        XCTAssertTrue(report.verdictValuesRewritten.contains("keeper-person"), "\(report)")
    }

    /// doomed **自帶**的 `person:<doomed>` verdict 由 #271 搬到 keeper 後也要被改寫——pre-commit 的快照掃描看不到它。
    func testPersonMergeRewritesPersonHolderTransferredFromDoomed() throws {
        try store.writePerson(Person(key: "keeper-person", names: ["Keeper Person"]))
        var doomed = Person(key: "doomed-person", names: ["Doomed Person"])
        doomed.references = [verdict("resolution-rejected", kind: .person, holder: "doomed-person", literal: "D")]
        try store.writePerson(doomed)
        let d = try divergence(keeper: "keeper-person", doomed: "doomed-person", shape: .person)
        GitFixture.commitAll(store.root)
        let report = try store.resolveDivergence(id: d.id, survivor: "keeper-person")
        XCTAssertEqual(try holders(ofPerson: "keeper-person"), ["person:keeper-person"], "搬來的 verdict 也要改寫")
        // doomed 帶 references：若 post-commit 迴圈沒排除 merged，會 writePerson(doomed) 把已刪檔復活（logic L1）
        XCTAssertNil(try store.load().people.first { $0.key == "doomed-person" }, "doomed 不得復活")
        XCTAssertEqual(report.verdictReferencesMigrated, ["person:keeper-person :: D"], "揭露值要是改寫後的（requirements #5）")
    }

    // MARK: - venue 的 `person:` holder（矩陣的最後兩格：person-merge×venue、person-rename×venue）

    /// venue 記錄今天只由 resolve-venues 落 `work:` holder，但寫入閘收任何 holderKind——與 person 記錄同一個
    /// 「結構上不會有」，處置要一致（verify security 席）。
    func testPersonMergeMigratesPersonHoldersOnVenues() throws {
        try store.writePerson(Person(key: "keeper-person", names: ["Keeper Person"]))
        try store.writePerson(Person(key: "doomed-person", names: ["Doomed Person"]))
        var v = Venue(key: "some-journal", type: .periodical, names: TimelineOf([TemporalValue(value: "J")]))
        v.references = [verdict("resolution-confirmed", kind: .person, holder: "doomed-person", literal: "V")]
        _ = try store.writeVenue(v)
        let d = try divergence(keeper: "keeper-person", doomed: "doomed-person", shape: .person)
        GitFixture.commitAll(store.root)
        let report = try store.resolveDivergence(id: d.id, survivor: "keeper-person")
        XCTAssertEqual(try holders(ofVenue: "some-journal"), ["person:keeper-person"])
        XCTAssertTrue(report.verdictValuesRewritten.contains("some-journal"), "\(report)")
    }

    func testPersonRenameMigratesPersonHoldersOnVenues() throws {
        try store.writePerson(Person(key: "old-person", names: ["Old Person"]))
        var v = Venue(key: "some-journal", type: .periodical, names: TimelineOf([TemporalValue(value: "J")]))
        v.references = [verdict("resolution-rejected", kind: .person, holder: "old-person", literal: "V")]
        _ = try store.writeVenue(v)
        GitFixture.commitAll(store.root)
        let report = try store.renamePerson(from: "old-person", to: "new-person")
        XCTAssertEqual(try holders(ofVenue: "some-journal"), ["person:new-person"])
        XCTAssertTrue(report.verdictValuesRewritten.contains("some-journal"), "\(report)")
    }

    // MARK: - rename 的 org 前置閘與 writeOrganization 同一個函式

    /// format 閘沒鏡射會撕裂：entry 寫完才在 `writeOrganization` 擲錯（Codex R1）。把 store 降到 format 7 之後，
    /// rename 要在**改動 entry 之前**擲錯。
    func testRenameRefusesBeforeTouchingEntryWhenOrganizationGateFails() throws {
        try entry("old2020a")
        try org("some-org", refs: [verdict("resolution-confirmed", kind: .work, holder: "old2020a", literal: "Some Org")])
        try StoreVersion.write(root: root, format: 7)   // verdict 需要 ≥ 8：閘要在 rename 的前置段就擋
        XCTAssertThrowsError(try store.renameEntry(from: "old2020a", to: "new2020a"))
        try StoreVersion.write(root: root, format: StoreVersion.supported)
        let keys = try store.load().entries.map(\.citekey)
        XCTAssertEqual(keys, ["old2020a"], "entry 不得被改動：\(keys)")
    }

    /// `writeOrganization` 的 format 讀取是 lazy 的：一個**壞掉的** store.yaml 不得讓沒有任何 gated feature 的
    /// organization 寫不進（抽 helper 前就是按需讀——Codex R2 抓到第一版改成無條件讀）；帶 verdict 的則要擲錯。
    func testMalformedStoreVersionOnlyBlocksOrganizationsThatNeedAGate() throws {
        try Data([0xFF, 0xFE, 0x00]).write(to: root.appendingPathComponent("store.yaml"))   // 非 UTF-8 → read 擲錯
        XCTAssertNoThrow(try store.writeOrganization(Organization(key: "plain-org", names: TimelineOf([TemporalValue(value: "Plain")]))),
                         "沒有 gated feature：不該碰 store.yaml")
        var gated = Organization(key: "gated-org", names: TimelineOf([TemporalValue(value: "Gated")]))
        gated.references = [verdict("resolution-confirmed", kind: .work, holder: "x2020a", literal: "G")]
        XCTAssertThrowsError(try store.writeOrganization(gated), "verdict 需要 format 閘，壞掉的 store.yaml 要擲錯")
        try StoreVersion.write(root: root, format: StoreVersion.supported)
    }

    // MARK: - helper 的 kind 篩選

    func testHelperKindFilterLeavesOtherKindsUntouched() {
        let refs = [verdict("resolution-confirmed", kind: .work, holder: "doomed-person", literal: "A"),   // 同名 holder、不同 kind
                    verdict("resolution-confirmed", kind: .person, holder: "doomed-person", literal: "B")]
        let (out, changed, collapsed) = LibraryStore.migrateHolderVerdicts(
            refs, merged: ["doomed-person"], survivor: "keeper-person", holderKind: .person)
        XCTAssertTrue(changed); XCTAssertTrue(collapsed.isEmpty)
        XCTAssertEqual(out.map(\.value), [refs[0].value, "person:keeper-person :: B"], "`work:` 那筆不動")
    }

    // MARK: - 多筆 cardinality 回歸：多個 organization 指向同一 citekey（live store 的形狀：9 條、7 個 distinct citekey）

    func testSeveralOrganizationsPointingAtOneCitekeyAllMigrateOnRename() throws {
        try entry("standards1966a")
        for k in ["org-a", "org-b", "org-c"] {
            try org(k, refs: [verdict("resolution-confirmed", kind: .work, holder: "standards1966a", literal: "Org \(k)")])
        }
        let report = try store.renameEntry(from: "standards1966a", to: "standards1966b")
        XCTAssertEqual(report.verdictValuesRewritten, ["org-a", "org-b", "org-c"])
        for k in ["org-a", "org-b", "org-c"] {
            XCTAssertEqual(try holders(ofOrg: k), ["work:standards1966b"], k)
        }
    }
}
