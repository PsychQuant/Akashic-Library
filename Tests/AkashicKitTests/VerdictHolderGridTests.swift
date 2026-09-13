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
        XCTAssertEqual(report.verdictValuesRewritten, [HolderRecord(.organization, "some-org")])
    }

    // MARK: - work merge × organization

    func testWorkMergeMigratesOrganizationHeldWorkVerdict() throws {
        try entry("keeper2020a"); try entry("doomed2020a")
        try org("some-org", refs: [verdict("resolution-rejected", kind: .work, holder: "doomed2020a", literal: "Some Org")])
        let d = try divergence(keeper: "keeper2020a", doomed: "doomed2020a", shape: .work)
        GitFixture.commitAll(store.root)   // resolve 只在受 git 追蹤的檔上動刀（deletionNotRecoverable 閘）
        let report = try store.resolveDivergence(id: d.id, survivor: "keeper2020a")
        XCTAssertEqual(try holders(ofOrg: "some-org"), ["work:keeper2020a"])
        XCTAssertTrue(report.verdictValuesRewritten.contains(HolderRecord(.organization, "some-org")), "\(report)")
        XCTAssertTrue(report.failures.isEmpty, "\(report.failures)")
    }

    /// **持有被併 citekey 的 venue 要在 commit 之前過寫入閘，dry-run 也要拒**（#554 R7 verify 第 5 列，DA）：
    /// work 合併在 `commitResolution` 之後才對每個持有 `work:<被併>` verdict 的 venue 跑 `migrateWorkHolderVerdicts`
    /// → `writeVenue`，沒有 pre-commit 的 `assertVenueWritable`、preview 也不看——D8 讓「尾隨空白的名字」這種最常見
    /// 的手改痕跡能讓那一步 throw：dry-run 說 OK、apply 已刪檔、venue 留死 verdict（#139 F1 ＋ #460 的合成形）。
    func testWorkMergeRefusesUpFrontWhenAVenueHolderIsUnwritable() throws {
        try entry("keeper2020a"); try entry("doomed2020a")
        var v = Venue(key: "some-journal", type: .periodical, names: TimelineOf([TemporalValue(value: "J")]))
        v.references = [verdict("resolution-confirmed", kind: .work, holder: "doomed2020a", literal: "J")]
        _ = try store.writeVenue(v)
        let file = root.appendingPathComponent("entities/\(v.id.uuidString).yaml")
        try String(contentsOf: file, encoding: .utf8)
            .replacingOccurrences(of: "- value: J\n", with: "- value: 'J '\n")
            .write(to: file, atomically: true, encoding: .utf8)
        let d = try divergence(keeper: "keeper2020a", doomed: "doomed2020a", shape: .work)
        GitFixture.commitAll(store.root)
        XCTAssertThrowsError(try store.previewResolveDivergence(id: d.id, survivor: "keeper2020a", overrideReason: nil)) { err in
            XCTAssertTrue(String(describing: err).contains("J "), "\(err)")
        }
        XCTAssertThrowsError(try store.resolveDivergence(id: d.id, survivor: "keeper2020a"))
        XCTAssertEqual(try store.load().entries.count, 2, "零寫入：被併 work 仍在")
        XCTAssertEqual(try holders(ofVenue: "some-journal"), ["work:doomed2020a"])
    }

    // MARK: - person merge × organization ／ × person

    /// **欄位遺失的訊息先於 holder 閘**（R9 verify regression 第 9 列）：R9 把 `assertHoldersWritable` 放在 `fieldsLostByMerging`
    /// 之前，一次同時「被併者帶倖存者沒有的 ORCID」與「某個第三方 org holder 髒了」的合併，使用者先看到的是別人家 YAML 的
    /// 錯，而不是這次合併會丟什麼。兩者都是零寫入的拒絕，差別只在哪句先出——merge 專屬的那句要先。
    func testFieldLossIsReportedBeforeTheHolderGate() throws {
        try store.writePerson(Person(key: "keeper-person", names: ["Keeper Person"]))
        var doomed = Person(key: "doomed-person", names: ["Doomed Person"])
        doomed.note = "帶著倖存者沒有的東西"
        try store.writePerson(doomed)
        try org("some-org", refs: [verdict("resolution-confirmed", kind: .person, holder: "doomed-person", literal: "Some Org")])
        let o = try XCTUnwrap(store.load().organizations.first { $0.key == "some-org" })
        let file = root.appendingPathComponent("entities/\(o.id.uuidString).yaml")
        try (try String(contentsOf: file, encoding: .utf8) + "authorized:\n- Not In Names\n").write(to: file, atomically: true, encoding: .utf8)
        let d = try divergence(keeper: "keeper-person", doomed: "doomed-person", shape: .person)
        GitFixture.commitAll(store.root)
        XCTAssertThrowsError(try store.previewResolveDivergence(id: d.id, survivor: "keeper-person", overrideReason: nil)) { err in
            guard case DivergenceResolveError.wouldLoseFields = err else { return XCTFail("要先報欄位遺失：\(err)") }
        }
    }
    /// **D19 的閘要涵蓋三種 holder，不只 venue**（#554 R8 verify 第 13／14／32 列；Claude 代裁 D24）：R8 的
    /// `assertVenueHoldersWritable` doc 說「person／organization holder 沒有名字內容不變式，寫入閘對它們只有 key 與
    /// format」——假的：`assertOrganizationWritable`／`assertPersonWritable` 都跑 `validate()` 的 error 級檢查
    /// （authorized ⊆ names 自 #227 起是 error）。一筆手改成 `authorized ⊄ names` 的 organization 持有 `person:<被併>`
    /// verdict 時，person 合併的 post-commit 迴圈才撞到它——被併檔已刪、org 留死 verdict、dry-run 沉默，正是 D19 為
    /// venue 關掉的那個形，換了 holder 種類。
    func testPersonMergeRefusesUpFrontWhenAnOrganizationHolderIsUnwritable() throws {
        try store.writePerson(Person(key: "keeper-person", names: ["Keeper Person"]))
        try store.writePerson(Person(key: "doomed-person", names: ["Doomed Person"]))
        try org("some-org", refs: [verdict("resolution-confirmed", kind: .person, holder: "doomed-person", literal: "Some Org")])
        let o = try XCTUnwrap(store.load().organizations.first { $0.key == "some-org" })
        let file = root.appendingPathComponent("entities/\(o.id.uuidString).yaml")
        let yaml = try String(contentsOf: file, encoding: .utf8)
        XCTAssertFalse(yaml.contains("authorized:"), "fixture 前提：org 建檔時不寫 authorized")
        try (yaml + "authorized:\n- Not In Names\n").write(to: file, atomically: true, encoding: .utf8)
        let d = try divergence(keeper: "keeper-person", doomed: "doomed-person", shape: .person)
        GitFixture.commitAll(store.root)
        XCTAssertThrowsError(try store.previewResolveDivergence(id: d.id, survivor: "keeper-person", overrideReason: nil)) { err in
            XCTAssertTrue(String(describing: err).contains("some-org"), "\(err)")
        }
        XCTAssertThrowsError(try store.resolveDivergence(id: d.id, survivor: "keeper-person"))
        XCTAssertEqual(try store.load().people.map(\.key).sorted(), ["doomed-person", "keeper-person"], "零寫入：被併 person 仍在")
        XCTAssertEqual(try holders(ofOrg: "some-org"), ["person:doomed-person"])
    }


    func testPersonMergeMigratesPersonHoldersOnOrganizations() throws {
        try store.writePerson(Person(key: "keeper-person", names: ["Keeper Person"]))
        try store.writePerson(Person(key: "doomed-person", names: ["Doomed Person"]))
        try org("some-org", refs: [verdict("resolution-confirmed", kind: .person, holder: "doomed-person", literal: "Some Org")])
        let d = try divergence(keeper: "keeper-person", doomed: "doomed-person", shape: .person)
        GitFixture.commitAll(store.root)   // resolve 只在受 git 追蹤的檔上動刀（deletionNotRecoverable 閘）
        let report = try store.resolveDivergence(id: d.id, survivor: "keeper-person")
        XCTAssertEqual(try holders(ofOrg: "some-org"), ["person:keeper-person"])
        XCTAssertTrue(report.verdictValuesRewritten.contains(HolderRecord(.organization, "some-org")), "\(report)")
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
        XCTAssertTrue(report.verdictValuesRewritten.contains(HolderRecord(.person, "third-person")), "\(report)")
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
        XCTAssertTrue(report.verdictValuesRewritten.contains(HolderRecord(.person, "keeper-person")), "\(report)")
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
        XCTAssertTrue(report.verdictValuesRewritten.contains(HolderRecord(.venue, "some-journal")), "\(report)")
    }

    func testPersonRenameMigratesPersonHoldersOnVenues() throws {
        try store.writePerson(Person(key: "old-person", names: ["Old Person"]))
        var v = Venue(key: "some-journal", type: .periodical, names: TimelineOf([TemporalValue(value: "J")]))
        v.references = [verdict("resolution-rejected", kind: .person, holder: "old-person", literal: "V")]
        _ = try store.writeVenue(v)
        GitFixture.commitAll(store.root)
        let report = try store.renamePerson(from: "old-person", to: "new-person")
        XCTAssertEqual(try holders(ofVenue: "some-journal"), ["person:new-person"])
        XCTAssertTrue(report.verdictValuesRewritten.contains(HolderRecord(.venue, "some-journal")), "\(report)")
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

    // MARK: - commit 失敗語意（Codex R3 N1／DA-2）：揭露與遷移**都**看 keeper 寫沒寫（`survivorUpdated`）

    /// keeper 寫入後某筆 entry 寫入失敗（immutable 擋 rename，案例 B）：doomed 不刪、failures 非空，但 holder 遷移
    /// **照做**（冪等，重跑補完其餘）且 keeper 自己已改寫的 holder 是既成事實、報告**必須**揭露。
    /// 拿掉 `survivorUpdated` 閘本支照綠——它的殺手是下一支（案例 A）；本支釘的是「不得用 `failures.isEmpty` 擋」。
    func testPersonMergePartialFailureAfterKeeperWriteStillMigratesHoldersAndDisclosesKeeper() throws {
        var keeper = Person(key: "keeper-person", names: ["Keeper Person"])
        keeper.references = [verdict("resolution-confirmed", kind: .person, holder: "doomed-person", literal: "K")]
        try store.writePerson(keeper)
        try store.writePerson(Person(key: "doomed-person", names: ["Doomed Person"]))
        var third = Person(key: "third-person", names: ["Third Person"])
        third.references = [verdict("resolution-confirmed", kind: .person, holder: "doomed-person", literal: "X")]
        try store.writePerson(third)
        var blocked = Entry(id: UUID(), citekey: "blocked2020a", type: .periodicalArticle, title: "Blocked")
        blocked.authors = [.key("doomed-person")]
        try store.writeEntry(blocked)
        let d = try divergence(keeper: "keeper-person", doomed: "doomed-person", shape: .person)
        GitFixture.commitAll(store.root)
        let blockedURL = store.entityURL(id: blocked.id)
        try FileManager.default.setAttributes([.immutable: true], ofItemAtPath: blockedURL.path)
        defer { try? FileManager.default.setAttributes([.immutable: false], ofItemAtPath: blockedURL.path) }

        let report = try store.resolveDivergence(id: d.id, survivor: "keeper-person")
        XCTAssertTrue(report.hasFailures, "\(report)")
        XCTAssertTrue(report.survivorUpdated)
        XCTAssertEqual(try holders(ofPerson: "third-person"), ["person:keeper-person"], "keeper 已落地：遷移照做（C／D 兩案重跑救不回）")
        XCTAssertNotNil(try store.load().people.first { $0.key == "doomed-person" }, "失敗路徑不刪被併記錄")
        XCTAssertEqual(try holders(ofPerson: "keeper-person"), ["person:keeper-person"], "keeper 已在 commit 前改寫")
        XCTAssertTrue(report.verdictValuesRewritten.contains(HolderRecord(.person, "keeper-person")), "既成事實要揭露：\(report)")
        XCTAssertTrue(report.verdictValuesRewritten.contains(HolderRecord(.person, "third-person")), "做了的要報：\(report)")
    }

    /// commit **前**就早退（被併檔不可刪）：keeper 沒寫、holder 沒動、報告什麼都不揭露——完全的 no-op。
    func testPersonMergeUndeletableDoomedTouchesNoHolderAndDisclosesNothing() throws {
        var keeper = Person(key: "keeper-person", names: ["Keeper Person"])
        keeper.references = [verdict("resolution-confirmed", kind: .person, holder: "doomed-person", literal: "K")]
        try store.writePerson(keeper)
        var doomed = Person(key: "doomed-person", names: ["Doomed Person"])
        doomed.references = [verdict("resolution-rejected", kind: .person, holder: "doomed-person", literal: "D")]
        try store.writePerson(doomed)
        var third = Person(key: "third-person", names: ["Third Person"])
        third.references = [verdict("resolution-confirmed", kind: .person, holder: "doomed-person", literal: "X")]
        try store.writePerson(third)
        let d = try divergence(keeper: "keeper-person", doomed: "doomed-person", shape: .person)
        GitFixture.commitAll(store.root)
        let doomedURL = store.entityURL(id: doomed.id)
        try FileManager.default.setAttributes([.immutable: true], ofItemAtPath: doomedURL.path)
        defer { try? FileManager.default.setAttributes([.immutable: false], ofItemAtPath: doomedURL.path) }

        let report = try store.resolveDivergence(id: d.id, survivor: "keeper-person")
        XCTAssertTrue(report.hasFailures, "\(report)")
        XCTAssertFalse(report.survivorUpdated)
        XCTAssertEqual(try holders(ofPerson: "keeper-person"), ["person:doomed-person"], "keeper 不得被寫")
        XCTAssertEqual(try holders(ofPerson: "third-person"), ["person:doomed-person"])
        XCTAssertTrue(report.verdictValuesRewritten.isEmpty, "\(report)")
        XCTAssertTrue(report.verdictReferencesMigrated.isEmpty, "#271 的搬移沒落地就不得揭露：\(report)")
    }

    /// work-merge 側是同一道 guard 的**第二份**（謂詞沒有集中）——B 案：keeper 寫後某筆引用 doomed 的 entry 寫入失敗，
    /// person 上 `work:<doomed>` 的 holder 仍要遷移、doomed 不刪、failures 非空（Codex R4 N3）。
    func testWorkMergePartialFailureAfterKeeperWriteStillMigratesHolders() throws {
        try entry("keeper2020a"); try entry("doomed2020a")
        var p = Person(key: "holder-person", names: ["Holder"])
        p.references = [verdict("resolution-confirmed", kind: .work, holder: "doomed2020a", literal: "H")]
        try store.writePerson(p)
        var citing = Entry(id: UUID(), citekey: "citing2021a", type: .periodicalArticle, title: "Citing",
                           authors: [.literal("A B")], date: "2021")
        citing.akashic.relations.cites = ["doomed2020a"]
        try store.writeEntry(citing)
        let d = try divergence(keeper: "keeper2020a", doomed: "doomed2020a", shape: .work)
        GitFixture.commitAll(store.root)
        let citingURL = store.entityURL(id: citing.id)
        try FileManager.default.setAttributes([.immutable: true], ofItemAtPath: citingURL.path)
        defer { try? FileManager.default.setAttributes([.immutable: false], ofItemAtPath: citingURL.path) }

        let report = try store.resolveDivergence(id: d.id, survivor: "keeper2020a")
        XCTAssertTrue(report.hasFailures, "\(report)"); XCTAssertTrue(report.survivorUpdated)
        XCTAssertEqual(try holders(ofPerson: "holder-person"), ["work:keeper2020a"], "keeper 已落地：遷移照做")
        XCTAssertTrue(try store.load().entries.contains { $0.citekey == "doomed2020a" }, "失敗路徑不刪被併記錄")
        XCTAssertTrue(report.verdictValuesRewritten.contains(HolderRecord(.person, "holder-person")), "\(report)")
    }

    /// work-merge 側 A 案：被併檔不可刪 → 早退，holder 不動、什麼都不揭露。
    func testWorkMergeUndeletableDoomedTouchesNoHolder() throws {
        try entry("keeper2020a")
        let doomed = Entry(id: UUID(), citekey: "doomed2020a", type: .periodicalArticle, title: "Doomed",
                           authors: [.literal("A B")], date: "2020")
        try store.writeEntry(doomed)
        var p = Person(key: "holder-person", names: ["Holder"])
        p.references = [verdict("resolution-confirmed", kind: .work, holder: "doomed2020a", literal: "H")]
        try store.writePerson(p)
        let d = try divergence(keeper: "keeper2020a", doomed: "doomed2020a", shape: .work)
        GitFixture.commitAll(store.root)
        let doomedURL = store.entityURL(id: doomed.id)
        try FileManager.default.setAttributes([.immutable: true], ofItemAtPath: doomedURL.path)
        defer { try? FileManager.default.setAttributes([.immutable: false], ofItemAtPath: doomedURL.path) }

        let report = try store.resolveDivergence(id: d.id, survivor: "keeper2020a")
        XCTAssertTrue(report.hasFailures, "\(report)"); XCTAssertFalse(report.survivorUpdated)
        XCTAssertEqual(try holders(ofPerson: "holder-person"), ["work:doomed2020a"], "早退：holder 不得被碰")
        XCTAssertTrue(report.verdictValuesRewritten.isEmpty, "\(report)")
    }

    // MARK: - rename 側 helper 只對可解析的 verdict 收攏（Codex R3 N2）

    /// 兩筆同 (field, value)、不同來源（不同 `kind`）的非 verdict reference：與 rename 無關的記錄不得被碰，
    /// 有關的記錄改寫 verdict 之後那兩筆也要都還在。#395 的 helper 版本會把它們收成一筆並把記錄算進報告。
    func testRenameLeavesDuplicateNonVerdictReferencesAlone() throws {
        try entry("old2020a"); try entry("other2020a")
        func twice(_ name: String) -> [ProvenanceReference] {   // 同一個名字、兩份不同來源
            ["a", "b"].map { tag in
                ProvenanceReference(field: "names", value: name,
                                    kind: .retrieval(url: "https://\(tag).example/", retrieved: "2026-09-03", status: 200,
                                                     mediaType: "text/html", content: "sha256:" + String(repeating: tag, count: 64)))
            }
        }
        var unrelated = Person(key: "unrelated-person", names: ["Unrelated"])
        unrelated.references = twice("Unrelated")
        try store.writePerson(unrelated)
        var related = Person(key: "related-person", names: ["Related"])
        related.references = twice("Related") + [verdict("resolution-confirmed", kind: .work, holder: "old2020a", literal: "R")]
        try store.writePerson(related)

        let report = try store.renameEntry(from: "old2020a", to: "new2020a")
        XCTAssertEqual(report.verdictValuesRewritten, [HolderRecord(.person, "related-person")], "無關的記錄不得算進報告：\(report)")
        let load = try store.load()
        XCTAssertEqual(load.people.first { $0.key == "unrelated-person" }?.references.count, 2, "不得被收攏")
        let after = load.people.first { $0.key == "related-person" }?.references ?? []
        XCTAssertEqual(after.filter { $0.field == "names" }.count, 2, "改寫 verdict 之後兩筆 names reference 都要在")
        XCTAssertEqual(try holders(ofPerson: "related-person"), ["work:new2020a"])
    }

    // MARK: - rename 的 format 閘 lazy、讀一次共用（Codex R3 N3）

    /// `lazyStoreFormat()`：第一次呼叫才讀、之後回快取——marker 在第一次讀之後壞掉也不再碰。
    /// **誠實邊界**：這只證明 rename 的 format 閘本身不多讀；整個 rename 仍會在 `load()` 讀 marker（`StoreVersion.read(data:)`），
    /// 所以「壞掉的 store.yaml 不擋純 person rename」對 rename **不成立**——R3 N3 的前提對 `writeOrganization` 成立（它不讀佈局），
    /// 對 rename 不成立。改動的價值是與 R2 同一條紀律（不無條件讀），不是可達性。
    func testLazyStoreFormatReadsOnceAndCaches() throws {
        let provider = store.lazyStoreFormat()
        XCTAssertEqual(try provider(), StoreVersion.supported)
        try Data([0xFF, 0xFE, 0x00]).write(to: root.appendingPathComponent("store.yaml"))   // 第一次讀之後才壞
        defer { try? StoreVersion.write(root: root, format: StoreVersion.supported) }
        XCTAssertEqual(try provider(), StoreVersion.supported, "快取：不再讀 marker")
        XCTAssertThrowsError(try store.lazyStoreFormat()(), "新的 provider 才會讀到壞掉的 marker")
    }

    // MARK: - person 腿的寫入閘（DA-3）：與 org／venue 同型，format ≤ 7 的 store 上 rename 要在動 entry 之前擋

    func testRenameRefusesBeforeTouchingEntryWhenPersonGateFails() throws {
        try entry("old2020a")
        var p = Person(key: "some-person", names: ["Some Person"])
        p.references = [verdict("resolution-confirmed", kind: .work, holder: "old2020a", literal: "SP")]
        try store.writePerson(p)
        try StoreVersion.write(root: root, format: 7)   // verdict 需要 ≥ 8
        XCTAssertThrowsError(try store.renameEntry(from: "old2020a", to: "new2020a"))
        try StoreVersion.write(root: root, format: StoreVersion.supported)
        XCTAssertEqual(try store.load().entries.map(\.citekey), ["old2020a"], "entry 不得被改動")
        XCTAssertEqual(try holders(ofPerson: "some-person"), ["work:old2020a"])
    }

    /// 被改名的 person 自己**不得**觸發任何閘（空 names——v10 閘只看非空 names），否則測試在 holder 迴圈之前就短路、
    /// 殺不掉「holder 迴圈少了閘」的 mutant（Codex R4 N2）。
    func testRenamePersonRefusesBeforeTouchingPersonWhenHolderGateFails() throws {
        try store.writePerson(Person(key: "old-person", names: []))
        var h = Person(key: "holder-person", names: ["Holder"])
        h.references = [verdict("resolution-rejected", kind: .person, holder: "old-person", literal: "H")]
        try store.writePerson(h)
        try StoreVersion.write(root: root, format: 7)
        XCTAssertThrowsError(try store.renamePerson(from: "old-person", to: "new-person"))
        try StoreVersion.write(root: root, format: StoreVersion.supported)
        XCTAssertNotNil(try store.load().people.first { $0.key == "old-person" }, "被改名的 person 不得被寫")
        XCTAssertEqual(try holders(ofPerson: "holder-person"), ["person:old-person"])
    }

    // MARK: - live 形狀的回歸（DA-1）：venue 持兩條 `paginated` 判定（value 皆 nil、rests-on 不同），與 rename 無關

    /// `bmc-genomics`／`bmc-bioinformatics`／`bmc-genetics` 的真實形狀（#406 的判定＋早期窗補證）。#395 形的 helper 會把
    /// 第二條連同它的 rests-on digest 一起刪掉並印成「已遷移」——rename 與 rename-person 兩條路都要原樣。
    func testUnrelatedRenamesLeaveVenuesWithTwoPaginatedJudgementsAlone() throws {
        try entry("hayes2024a"); try store.writePerson(Person(key: "shih-chun-ming", names: ["Shih Chun-Ming"]))
        var v = Venue(key: "bmc-genomics", type: .periodical, names: TimelineOf([TemporalValue(value: "BMC Genomics")]))
        v.paginated = false   // 判定的 reference 必須指向一個存在的判定值
        v.references = [
            ProvenanceReference(field: "paginated", value: nil,
                                kind: .judgement(statement: "本刊使用文章編號", restsOn: ["sha256:" + String(repeating: "1", count: 64)])),
            ProvenanceReference(field: "paginated", value: nil,
                                kind: .judgement(statement: "早期窗補證", restsOn: ["sha256:" + String(repeating: "2", count: 64)])),
        ]
        _ = try store.writeVenue(v)
        let r1 = try store.renameEntry(from: "hayes2024a", to: "hayes2024a-zzz")
        XCTAssertTrue(r1.verdictValuesRewritten.isEmpty, "\(r1)")
        let r2 = try store.renamePerson(from: "shih-chun-ming", to: "shih-chun-ming-zzz")
        XCTAssertTrue(r2.verdictValuesRewritten.isEmpty, "\(r2)")
        let refs = try store.load().venues.first { $0.key == "bmc-genomics" }?.references ?? []
        XCTAssertEqual(refs.filter { $0.field == "paginated" }.count, 2, "兩條判定都要在：\(refs)")
    }

    // MARK: - provider 成功後只讀一次（Codex R3 N6：可殺 mutant）

    /// 一筆帶 verdict 的 organization 會經過**兩個**要 format 的閘（識別碼 reference 檢查、verdict ≥ 8）——
    /// 沒有快取時 provider 被叫兩次；拿掉 `cached` 這支測試就紅。
    func testOrganizationWritableGateReadsFormatOnce() throws {
        var gated = Organization(key: "gated-org", names: TimelineOf([TemporalValue(value: "Gated")]))
        gated.references = [verdict("resolution-confirmed", kind: .work, holder: "x2020a", literal: "G")]
        var calls = 0
        try LibraryStore.assertOrganizationWritable(gated, format: { calls += 1; return StoreVersion.supported })
        XCTAssertEqual(calls, 1, "provider 成功後只讀一次")
    }

    // MARK: - 多筆 cardinality 回歸：多個 organization 指向同一 citekey（live store 的形狀：9 條、7 個 distinct citekey）

    func testSeveralOrganizationsPointingAtOneCitekeyAllMigrateOnRename() throws {
        try entry("standards1966a")
        for k in ["org-a", "org-b", "org-c"] {
            try org(k, refs: [verdict("resolution-confirmed", kind: .work, holder: "standards1966a", literal: "Org \(k)")])
        }
        let report = try store.renameEntry(from: "standards1966a", to: "standards1966b")
        XCTAssertEqual(report.verdictValuesRewritten, [HolderRecord(.organization, "org-a"), HolderRecord(.organization, "org-b"), HolderRecord(.organization, "org-c")])
        for k in ["org-a", "org-b", "org-c"] {
            XCTAssertEqual(try holders(ofOrg: k), ["work:standards1966b"], k)
        }
    }

    // MARK: - 收攏丟列要回報（#495）

    /// rename 的 verdict 遷移**會丟列**：遷移後與既有 verdict 同 (field, value) 的那一筆被收攏。
    /// 在 #495 之前那是**靜默**的——report 沒有欄位承載它，CLI 與 App 都印不出來，而
    /// `lossless-intake` 執行細節 3 明寫「丟棄必須可見：靜默讓『沒有這個東西』與『有但沒說』
    /// 在事後完全無法區分」。merge 側自 #461 起就有，rename 側到這裡才補上。
    func testRenameCollapsingAVerdictIsReportedNotSilent() throws {
        try entry("old2020a")
        // 同一個 organization 同時持有指向舊鍵與新鍵的同 literal verdict——改名後兩者同值。
        try org("some-org", refs: [
            verdict("resolution-confirmed", kind: .work, holder: "old2020a", literal: "Some Org"),
            verdict("resolution-confirmed", kind: .work, holder: "new2020a", literal: "Some Org")])
        let report = try store.renameEntry(from: "old2020a", to: "new2020a")
        // 收攏真的發生了（兩條變一條）——沒有這一句，下面就只是在驗一個字串
        XCTAssertEqual(try holders(ofOrg: "some-org"), ["work:new2020a"])
        XCTAssertEqual(report.verdictsCollapsed.count, 1, "\(report.verdictsCollapsed)")
        let line = report.verdictsCollapsed[0]
        XCTAssertTrue(line.hasPrefix("organization「some-org」："),
                      "要說得出是哪一筆記錄丟的，否則使用者無從去看：\(line)")
        XCTAssertTrue(line.contains("resolution-confirmed"), line)
        XCTAssertTrue(line.contains("丟棄"), line)
    }

    /// person 改名側同型——兩條路徑各自執行同一條不變式，只驗其一會讓另一邊安靜退化。
    func testRenamePersonCollapsingAVerdictIsReportedNotSilent() throws {
        try store.writePerson(Person(key: "old-person", names: ["Old Person"]))
        try org("some-org", refs: [
            verdict("resolution-rejected", kind: .person, holder: "old-person", literal: "A B"),
            verdict("resolution-rejected", kind: .person, holder: "new-person", literal: "A B")])
        let report = try store.renamePerson(from: "old-person", to: "new-person")
        XCTAssertEqual(try holders(ofOrg: "some-org"), ["person:new-person"])
        XCTAssertEqual(report.verdictsCollapsed.count, 1, "\(report.verdictsCollapsed)")
        XCTAssertTrue(report.verdictsCollapsed[0].hasPrefix("organization「some-org」："),
                      report.verdictsCollapsed[0])
    }

    /// 沒有收攏時是空的——一個恆非空的欄位無法區分「丟了」與「沒丟」。
    func testRenameWithoutCollapseReportsNothingCollapsed() throws {
        try entry("old2020a")
        try org("some-org", refs: [verdict("resolution-confirmed", kind: .work, holder: "old2020a", literal: "Some Org")])
        let report = try store.renameEntry(from: "old2020a", to: "new2020a")
        XCTAssertEqual(report.verdictsCollapsed, [])
        XCTAssertEqual(report.verdictValuesRewritten, [HolderRecord(.organization, "some-org")])
    }

    // MARK: - 後置條件：一次 rename 不得新增死 verdict（#488）

    /// 三個遷移迴圈各自正確**不蘊含**整體正確。這條問結果不問機制——它不知道有幾腿，
    /// 所以新 holder 形狀第一次被走到時它就會出聲，而逐腿的測試不會（沒有測試知道那一腿存在）。
    func testVerdictsStillPointingAtNamesTheHolderAndField() {
        let stragglers = LibraryStore.verdictsStillPointingAt(
            "old2020a", holderKind: .work,
            in: [("organization", "some-org",
                  [verdict("resolution-confirmed", kind: .work, holder: "old2020a", literal: "X")]),
                 ("person", "innocent",
                  [verdict("resolution-confirmed", kind: .work, holder: "other2020a", literal: "X")]),
                 // 不同 holderKind 同名——不得誤報
                 ("venue", "vk",
                  [verdict("resolution-confirmed", kind: .person, holder: "old2020a", literal: "X")])])
        XCTAssertEqual(stragglers, ["organization「some-org」的 resolution-confirmed"])
    }

    func testAssertNoVerdictLeftBehindThrowsAndNamesThem() {
        XCTAssertNoThrow(try LibraryStore.assertNoVerdictLeftBehind([], oldKey: "k", action: "rename"))
        XCTAssertThrowsError(
            try LibraryStore.assertNoVerdictLeftBehind(["organization「some-org」的 resolution-confirmed"],
                                                       oldKey: "old2020a", action: "rename")) { e in
            let msg = "\(e)"
            XCTAssertTrue(msg.contains("some-org"), msg)
            XCTAssertTrue(msg.contains("old2020a"), msg)
            XCTAssertTrue(msg.contains("少了一腿"), "訊息要指出這是遷移缺腿，不是資料壞掉：\(msg)")
        }
    }

    /// 三種 holder 都持有指向舊鍵的 verdict 時，一次 rename 之後**一條都不剩**——
    /// 這是 #464 verify DA 在 live store 副本上實測到 4 條死 verdict 的那個情境的反面。
    func testRenameWithAllThreeHolderKindsLeavesNoDeadVerdict() throws {
        try entry("old2020a")
        var p = Person(key: "some-person", names: ["Some Person"])
        p.references = [verdict("resolution-confirmed", kind: .work, holder: "old2020a", literal: "SP")]
        try store.writePerson(p)
        var v = Venue(key: "some-venue", type: .periodical, names: TimelineOf([TemporalValue(value: "Some Venue")]))
        v.references = [verdict("resolution-confirmed", kind: .work, holder: "old2020a", literal: "SV")]
        _ = try store.writeVenue(v)
        try org("some-org", refs: [verdict("resolution-confirmed", kind: .work, holder: "old2020a", literal: "SO")])

        let report = try store.renameEntry(from: "old2020a", to: "new2020a")
        XCTAssertEqual(try holders(ofPerson: "some-person"), ["work:new2020a"])
        XCTAssertEqual(try holders(ofVenue: "some-venue"), ["work:new2020a"])
        XCTAssertEqual(try holders(ofOrg: "some-org"), ["work:new2020a"])
        XCTAssertEqual(report.verdictValuesRewritten, [HolderRecord(.organization, "some-org"), HolderRecord(.person, "some-person"), HolderRecord(.venue, "some-venue")])
        // 後置條件對改完的 store 重跑一次：零殘留
        let after = try store.load()
        XCTAssertEqual(LibraryStore.verdictsStillPointingAt(
            "old2020a", holderKind: .work,
            in: after.people.map { ("person", $0.key, $0.references) }
              + after.venues.map { ("venue", $0.key, $0.references) }
              + after.organizations.map { ("organization", $0.key, $0.references) }), [])
    }

    // MARK: - quarantine 檔對遷移網格不可見，但必須被說出來（#497）

    /// #463 verify DA-7 的 fixture：一筆被 quarantine 的 organization 持 `person:` verdict。
    /// 遷移只走 `load()` 解析得出的記錄，所以它**看不到**那條——這是既有邊界，本張不修它，
    /// 但報告不得因此宣稱「無其他記錄引用此 key」。「沒掃到」與「掃過且沒有」是兩件事。
    func testRenamePersonDisclosesUnscannedQuarantineFiles() throws {
        try store.writePerson(Person(key: "old-person", names: ["Old Person"]))
        var o = Organization(key: "broken-org", names: TimelineOf([TemporalValue(value: "Broken Org")]))
        o.references = [verdict("resolution-rejected", kind: .person, holder: "old-person", literal: "OP")]
        // 檔名 UUID 與記錄 id 不符 → 整檔 quarantine（DeadVerdictScanTests 的既有手法）
        try OrganizationYAML.encode(o).write(
            to: store.entitiesDir.appendingPathComponent("\(UUID().uuidString).yaml"),
            atomically: true, encoding: .utf8)
        XCTAssertEqual(try store.load().quarantined.count, 1, "前提：那個檔真的被 quarantine")

        let report = try store.renamePerson(from: "old-person", to: "new-person")
        XCTAssertEqual(report.verdictValuesRewritten, [],
                       "quarantine 檔不在 load 裡——遷移確實看不到它（這是缺口本身，本張不修）")
        XCTAssertEqual(report.quarantinedNotScanned.count, 1,
                       "未掃描必須說出來：\(report.quarantinedNotScanned)")
        // 缺口確實還在——磁碟上那條 verdict 仍指向已退役的鍵
        let stillThere = try FileManager.default
            .contentsOfDirectory(atPath: store.entitiesDir.path)
            .compactMap { try? String(contentsOf: store.entitiesDir.appendingPathComponent($0), encoding: .utf8) }
            .contains { $0.contains("person:old-person") }
        XCTAssertTrue(stillThere, "本張只要求可見，不要求遷移——若這裡變成 false，缺口被修了，回來更新這條")
    }

    /// citekey 側同型。
    func testRenameDisclosesUnscannedQuarantineFiles() throws {
        try entry("old2020a")
        var o = Organization(key: "broken-org", names: TimelineOf([TemporalValue(value: "Broken Org")]))
        o.references = [verdict("resolution-confirmed", kind: .work, holder: "old2020a", literal: "BO")]
        try OrganizationYAML.encode(o).write(
            to: store.entitiesDir.appendingPathComponent("\(UUID().uuidString).yaml"),
            atomically: true, encoding: .utf8)
        let report = try store.renameEntry(from: "old2020a", to: "new2020a")
        XCTAssertEqual(report.quarantinedNotScanned.count, 1, "\(report.quarantinedNotScanned)")
    }

    /// 乾淨的 store 是空的——恆非空的欄位分不出「有邊界」與「沒邊界」。
    func testCleanStoreDisclosesNoQuarantine() throws {
        try entry("old2020a")
        let report = try store.renameEntry(from: "old2020a", to: "new2020a")
        XCTAssertEqual(report.quarantinedNotScanned, [])
    }

    // MARK: - dry-run 不得對 verdict 面沉默（#467）

    /// preview 的 `verdictValuesRewritten`／`verdictsCollapsed` 在此之前**恆為空**，
    /// 實跑才出現。同檔反覆強調「dry-run 的價值是誠實預告」，而 #461 讓那個未被預告的
    /// 步驟從「只改值」升級成「會刪列」。
    func testWorkMergePreviewPredictsTheVerdictFace() throws {
        try entry("keeper2020a"); try entry("doomed2020a")
        try org("some-org", refs: [verdict("resolution-rejected", kind: .work, holder: "doomed2020a", literal: "Some Org")])
        var v = Venue(key: "some-journal", type: .periodical, names: TimelineOf([TemporalValue(value: "J")]))
        v.references = [verdict("resolution-confirmed", kind: .work, holder: "doomed2020a", literal: "J")]
        _ = try store.writeVenue(v)
        let d = try divergence(keeper: "keeper2020a", doomed: "doomed2020a", shape: .work)
        GitFixture.commitAll(store.root)

        let preview = try store.previewResolveDivergence(id: d.id, survivor: "keeper2020a",
                                                        overrideReason: nil)
        XCTAssertEqual(preview.verdictValuesRewritten,
                       [HolderRecord(.organization, "some-org"), HolderRecord(.venue, "some-journal")],
                       "dry-run 必須預告 verdict 面會改寫哪些持有記錄")

        let actual = try store.resolveDivergence(id: d.id, survivor: "keeper2020a")
        XCTAssertEqual(actual.failures, [])
        XCTAssertEqual(preview.verdictValuesRewritten, actual.verdictValuesRewritten,
                       "預告與實跑不一致就不是預告")
        XCTAssertEqual(preview.verdictsCollapsed, actual.verdictsCollapsed)
    }

    /// **收攏丟列也要被預告**——#461 之後 dry-run 沉默的那一半是「會刪掉什麼」。
    func testWorkMergePreviewPredictsTheCollapsedRows() throws {
        try entry("keeper2020a"); try entry("doomed2020a")
        // 同一個 organization 同時持有指向 keeper 與 doomed 的同 literal verdict → 合併後同值
        try org("some-org", refs: [
            verdict("resolution-confirmed", kind: .work, holder: "keeper2020a", literal: "Some Org"),
            verdict("resolution-confirmed", kind: .work, holder: "doomed2020a", literal: "Some Org")])
        let d = try divergence(keeper: "keeper2020a", doomed: "doomed2020a", shape: .work)
        GitFixture.commitAll(store.root)

        let preview = try store.previewResolveDivergence(id: d.id, survivor: "keeper2020a",
                                                        overrideReason: nil)
        XCTAssertEqual(preview.verdictsCollapsed.count, 1, "\(preview.verdictsCollapsed)")
        XCTAssertTrue(preview.verdictsCollapsed[0].hasPrefix("organization「some-org」："),
                      preview.verdictsCollapsed[0])
        let actual = try store.resolveDivergence(id: d.id, survivor: "keeper2020a")
        XCTAssertEqual(preview.verdictsCollapsed, actual.verdictsCollapsed)
    }

    /// person 合併側同型——只驗 work 側會讓另一條路徑安靜退化。
    func testPersonMergePreviewPredictsTheVerdictFace() throws {
        try store.writePerson(Person(key: "keeper-person", names: ["Keeper Person"]))
        try store.writePerson(Person(key: "doomed-person", names: ["Doomed Person"]))
        try org("some-org", refs: [verdict("resolution-confirmed", kind: .person, holder: "doomed-person", literal: "Some Org")])
        let d = try divergence(keeper: "keeper-person", doomed: "doomed-person", shape: .person)
        GitFixture.commitAll(store.root)

        let preview = try store.previewResolveDivergence(id: d.id, survivor: "keeper-person",
                                                        overrideReason: nil)
        XCTAssertEqual(preview.verdictValuesRewritten, [HolderRecord(.organization, "some-org")])
        let actual = try store.resolveDivergence(id: d.id, survivor: "keeper-person")
        XCTAssertEqual(actual.failures, [])
        XCTAssertEqual(preview.verdictValuesRewritten, actual.verdictValuesRewritten)
    }

    /// 沒有 verdict 面時預告是空的——恆非空的預告分不出「會改」與「不會改」。
    func testPreviewSaysNothingWhenThereIsNoVerdictFace() throws {
        try entry("keeper2020a"); try entry("doomed2020a")
        let d = try divergence(keeper: "keeper2020a", doomed: "doomed2020a", shape: .work)
        GitFixture.commitAll(store.root)
        let preview = try store.previewResolveDivergence(id: d.id, survivor: "keeper2020a",
                                                        overrideReason: nil)
        XCTAssertEqual(preview.verdictValuesRewritten, [])
        XCTAssertEqual(preview.verdictsCollapsed, [])
    }

    // MARK: - 會被改寫的 holder 檔也要過可回溯性閘（#469）

    /// 版控閘先前只護著要**刪**的 doomed 檔。verdict 遷移改寫的 holder 檔既不在那份名單、
    /// 寫入前也沒有 per-file 前檢——而 #461 之後那條路徑會**刪列**：被收攏掉的那一列若只
    /// 存在於未 tracked 的檔案裡，刪掉後 git 取不回。
    func testUntrackedHolderFileIsRefusedBeforeAnyWrite() throws {
        try entry("keeper2020a"); try entry("doomed2020a")
        let d = try divergence(keeper: "keeper2020a", doomed: "doomed2020a", shape: .work)
        GitFixture.commitAll(store.root)
        // **在 commit 之後**才建 holder → 它未被追蹤，而 doomed 檔仍然是乾淨的
        try org("some-org", refs: [verdict("resolution-confirmed", kind: .work, holder: "doomed2020a", literal: "SO")])

        XCTAssertThrowsError(try store.resolveDivergence(id: d.id, survivor: "keeper2020a")) { e in
            let m = "\(e)"
            XCTAssertTrue(m.contains("未被 git 追蹤"), m)
        }
        // 零寫入：doomed 還在、org 的 verdict 沒動
        XCTAssertEqual(try store.load().entries.map(\.citekey).sorted(),
                       ["doomed2020a", "keeper2020a"], "拒絕必須發生在任何寫入之前")
        XCTAssertEqual(try holders(ofOrg: "some-org"), ["work:doomed2020a"])
    }

    /// 追蹤且乾淨的 holder 檔照常通過——閘門不得把正常工作節奏擋掉。
    func testTrackedCleanHolderFilePassesTheGate() throws {
        try entry("keeper2020a"); try entry("doomed2020a")
        try org("some-org", refs: [verdict("resolution-confirmed", kind: .work, holder: "doomed2020a", literal: "SO")])
        let d = try divergence(keeper: "keeper2020a", doomed: "doomed2020a", shape: .work)
        GitFixture.commitAll(store.root)
        let report = try store.resolveDivergence(id: d.id, survivor: "keeper2020a")
        XCTAssertEqual(report.failures, [])
        XCTAssertEqual(try holders(ofOrg: "some-org"), ["work:keeper2020a"])
    }

    /// **不牽連無關的髒檔**：沒有 verdict 要遷的 holder 即使未追蹤也不進閘門名單——
    /// 「store 其他地方髒不影響這次刪除的可回溯性」是這道閘既有的立場。
    func testUnrelatedUntrackedRecordDoesNotBlock() throws {
        try entry("keeper2020a"); try entry("doomed2020a")
        let d = try divergence(keeper: "keeper2020a", doomed: "doomed2020a", shape: .work)
        GitFixture.commitAll(store.root)
        try org("innocent-org", refs: [])   // 未追蹤，但這次合併不會碰它
        XCTAssertNoThrow(try store.resolveDivergence(id: d.id, survivor: "keeper2020a"))
    }
}
