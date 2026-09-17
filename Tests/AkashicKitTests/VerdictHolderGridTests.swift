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
    /// **work 合併的 holder 遷移也不得造出矛盾對**（R12 verify DA 第 6 列，真 binary 全工具面重現：venue alpha 持
    /// `confirmed :: work:keep :: Alpha` 與 `rejected :: work:doom :: ALPHA`，doom 併進 keep 後 `migrateHolderVerdicts` 把
    /// holder 改寫成 keep，field 進鍵所以兩筆都留下——#486 的矛盾對，而 D31 只裝在 person／venue 自己的 references 上）。
    /// 閘要裝在遷移那一步（`assertHoldersWritable`，三種 shape 共用），不是三個 `validate*Preconditions` 各補一份。
    func testWorkMergeRefusesWhenHolderMigrationWouldContradict() throws {
        try entry("keep2020a")
        let doomed = Entry(id: UUID(), citekey: "doom2020a", type: .periodicalArticle, title: "Doomed",
                           authors: [.literal("A B")], date: "2020")
        try store.writeEntry(doomed)
        var v = Venue(key: "alpha", type: .periodical, names: Timeline([TemporalValue(value: "Alpha")]), authorized: [])
        v.references = [verdict("resolution-confirmed", kind: .work, holder: "keep2020a", literal: "Alpha"),
                        verdict("resolution-rejected", kind: .work, holder: "doom2020a", literal: "ALPHA")]
        try store.writeVenue(v)
        let d = try divergence(keeper: "keep2020a", doomed: "doom2020a", shape: .work)
        GitFixture.commitAll(store.root)
        for op in [{ _ = try self.store.previewResolveDivergence(id: d.id, survivor: "keep2020a", overrideReason: nil) },
                   { _ = try self.store.resolveDivergence(id: d.id, survivor: "keep2020a") }] {
            XCTAssertThrowsError(try op()) { err in
                guard case DivergenceResolveError.wouldContradictVerdicts = err else { return XCTFail("要具名拒絕：\(err)") }
                XCTAssertTrue(err.localizedDescription.contains("alpha"), "要指名 holder：\(err)")
            }
        }
        XCTAssertEqual(try holders(ofVenue: "alpha"), ["work:keep2020a", "work:doom2020a"], "零寫入")
        XCTAssertEqual(try store.load().entries.count, 2, "零寫入")
    }

    /// **work 合併的 holder 遷移也不得留下同一 work 兩個正規化後不同的 confirmed literal**（R13 verify Codex 第 1 列、DA 第 3 列——
    /// 純工具面重現：`--apply wkeep:0 --apply wdoom:0` 把兩個刊名變體各歸戶到 alpha，`resolve-divergence` 把 wdoom 併進 wkeep，
    /// alpha 上兩筆 confirmed 都改寫成 wkeep，validate 零診斷、`--demote wkeep:0` 撞 D23；R13 只在 holder 那一步補了「相反判定」
    /// 那一半——與 keeper 路徑同一句不變式、不同的謂詞）。R14（D34）：兩條路同一個 delta 謂詞、兩半都算。
    func testWorkMergeRefusesWhenHolderMigrationWouldLeaveTwoConfirmedLiterals() throws {
        try entry("keep2020a")
        try store.writeEntry(Entry(id: UUID(), citekey: "doom2020a", type: .periodicalArticle, title: "Doomed",
                                   authors: [.literal("A B")], date: "2020"))
        var v = Venue(key: "alpha", type: .periodical, names: Timeline([TemporalValue(value: "Alpha Journal"), TemporalValue(value: "Beta Review")]),
                      authorized: [])
        v.references = [verdict("resolution-confirmed", kind: .work, holder: "keep2020a", literal: "Alpha Journal"),
                        verdict("resolution-confirmed", kind: .work, holder: "doom2020a", literal: "Beta Review")]
        try store.writeVenue(v)
        let d = try divergence(keeper: "keep2020a", doomed: "doom2020a", shape: .work)
        GitFixture.commitAll(store.root)
        for op in [{ _ = try self.store.previewResolveDivergence(id: d.id, survivor: "keep2020a", overrideReason: nil) },
                   { _ = try self.store.resolveDivergence(id: d.id, survivor: "keep2020a") }] {
            XCTAssertThrowsError(try op()) { err in
                guard case DivergenceResolveError.wouldLeaveTwoConfirmedLiterals(let record, _, let ck, _, _, _, _) = err else { return XCTFail("要具名拒絕：\(err)") }
                XCTAssertEqual(record, "alpha"); XCTAssertEqual(ck, "keep2020a")
                // 出處與**遷移前**的原值（DA 第 17 列：R13 印遷移後的 `work:keep :: …`，那個字串不在任何 YAML 裡）
                let s = err.localizedDescription
                XCTAssertTrue(s.contains("work:doom2020a :: Beta Review") && !s.contains("work:keep2020a :: Beta Review"), s)
            }
        }
        XCTAssertEqual(try holders(ofVenue: "alpha"), ["work:keep2020a", "work:doom2020a"], "零寫入")
        // 對照組：同一 literal（正規化後相等）——遷移去重成一筆，合併照常
        var v2 = try XCTUnwrap(store.load().venues.first { $0.key == "alpha" })
        v2.references[1] = verdict("resolution-confirmed", kind: .work, holder: "doom2020a", literal: "ALPHA JOURNAL")
        try store.writeVenue(v2)
        GitFixture.commitAll(store.root)
        let report = try store.resolveDivergence(id: d.id, survivor: "keep2020a")
        XCTAssertEqual(report.failures, [])
        XCTAssertEqual(try holders(ofVenue: "alpha"), ["work:keep2020a"])
    }

    /// **holder 合併前就有的矛盾對不擋不相干的合併**（R13 verify 第 6／9／13／14 列：R13 的 holder 閘掃整份遷移後的清單，一個與被併鍵
    /// 無關的既有 #486 矛盾對——warning 級、被明文容忍、沒有工具面可修——就把一次無關的合併鎖死，訊息還說「併入之後會」）。
    /// 與同一輪對 D32 的裁決同向：既有的違反不是這次合併的事。
    func testWorkMergeIgnoresAHolderContradictionThatPredatesTheMerge() throws {
        try entry("keep2020a"); try entry("other2020a")
        try store.writeEntry(Entry(id: UUID(), citekey: "doom2020a", type: .periodicalArticle, title: "Doomed",
                                   authors: [.literal("A B")], date: "2020"))
        try org("some-org", refs: [verdict("resolution-confirmed", kind: .work, holder: "other2020a", literal: "ISS"),
                                   verdict("resolution-rejected", kind: .work, holder: "other2020a", literal: "iss"),
                                   verdict("resolution-confirmed", kind: .work, holder: "doom2020a", literal: "Academia Sinica")])
        let d = try divergence(keeper: "keep2020a", doomed: "doom2020a", shape: .work)
        GitFixture.commitAll(store.root)
        let preview = try store.previewResolveDivergence(id: d.id, survivor: "keep2020a", overrideReason: nil)
        XCTAssertEqual(preview.verdictValuesRewritten, [HolderRecord(.organization, "some-org")])
        let report = try store.resolveDivergence(id: d.id, survivor: "keep2020a")
        XCTAssertEqual(report.failures, [])
        XCTAssertEqual(try holders(ofOrg: "some-org"), ["work:other2020a", "work:other2020a", "work:keep2020a"], "既有的矛盾對原封不動、被併鍵改寫")
    }

    /// **dry-run 對 #271 那一腿的丟列也要預告**（R13 verify regression 第 2 列、logic 第 8 列：R13 的 `collapsedByDedupe` 只在實跑，
    /// preview 的 `verdictsCollapsed` 被 holder 遷移那一半整個覆蓋——而 dry-run 正是還能反悔的時點）。
    func testPersonMergePreviewPredictsTheDedupeCollapsesToo() throws {
        var keeper = Person(key: "keeper-person", names: ["Keeper Person"])
        keeper.references = [verdict("resolution-confirmed", kind: .work, holder: "w2025", literal: "Cheng, C.")]
        try store.writePerson(keeper)
        var doomed = Person(key: "doomed-person", names: ["Doomed Person"])
        doomed.references = [verdict("resolution-confirmed", kind: .work, holder: "w2025", literal: "CHENG, C.")]
        try store.writePerson(doomed)
        let d = try divergence(keeper: "keeper-person", doomed: "doomed-person", shape: .person)
        GitFixture.commitAll(store.root)
        let preview = try store.previewResolveDivergence(id: d.id, survivor: "keeper-person", overrideReason: nil)
        XCTAssertEqual(preview.verdictsCollapsed.count, 1, "\(preview.verdictsCollapsed)")
        let line = preview.verdictsCollapsed.first ?? ""
        XCTAssertTrue(line.contains("CHENG, C.") && line.hasPrefix("person「doomed-person」："), line)
        let actual = try store.resolveDivergence(id: d.id, survivor: "keeper-person")
        XCTAssertEqual(actual.failures, [])
        XCTAssertEqual(preview.verdictsCollapsed, actual.verdictsCollapsed, "預告與實跑不一致就不是預告")
    }

    /// **person 合併對相反判定同樣拒、同鍵同 kind 的遷移去重**（#554 R12，D31；R11 verify DA 第 1 列指出 person 路徑有逐字
    /// 同型的程式碼與同型的假斷言「(field, value) 冪等」——它只在位元組層為真）。
    func testPersonMergeRefusesOppositeVerdictsAndDedupesMigrationByNormalizedKey() throws {
        var keeper = Person(key: "keeper-person", names: ["Keeper Person"])
        keeper.references = [verdict("resolution-confirmed", kind: .work, holder: "w2025", literal: "Cheng, C.")]
        try store.writePerson(keeper)
        var doomed = Person(key: "doomed-person", names: ["Doomed Person"])
        doomed.references = [verdict("resolution-rejected", kind: .work, holder: "w2025", literal: "CHENG, C.")]
        try store.writePerson(doomed)
        let d = try divergence(keeper: "keeper-person", doomed: "doomed-person", shape: .person)
        GitFixture.commitAll(store.root)
        XCTAssertThrowsError(try store.previewResolveDivergence(id: d.id, survivor: "keeper-person", overrideReason: nil)) { err in
            guard case DivergenceResolveError.wouldContradictVerdicts = err else { return XCTFail("要具名拒絕：\(err)") }
        }
        var doomed2 = Person(key: "doomed-two", names: ["Doomed Two"])
        doomed2.references = [verdict("resolution-confirmed", kind: .work, holder: "w2025", literal: "CHENG, C.")]
        try store.writePerson(doomed2)
        let d2 = try divergence(keeper: "keeper-person", doomed: "doomed-two", shape: .person)
        GitFixture.commitAll(store.root)
        let report = try store.resolveDivergence(id: d2.id, survivor: "keeper-person")
        XCTAssertEqual(report.verdictReferencesMigrated, [], "同鍵的重複不算遷移")
        XCTAssertEqual(try store.load().people.first { $0.key == "keeper-person" }?.references.compactMap(\.value), ["work:w2025 :: Cheng, C."])
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
        // 同一個 organization 對舊鍵持有兩筆同拼法的 verdict——改名後兩者同值、收攏成一筆（R21 起指向新鍵的那種 fixture 由 D60 拒絕）。
        try org("some-org", refs: [
            verdict("resolution-confirmed", kind: .work, holder: "old2020a", literal: "Some Org"),
            verdict("resolution-confirmed", kind: .work, holder: "old2020a", literal: "Some Org")])
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
            verdict("resolution-rejected", kind: .person, holder: "old-person", literal: "A B")])
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


    // MARK: - R15（D37）：delta 在索引層算——住在被併鍵上的既有違反不是這次合併帶進來的

    /// **合併前就住在被併鍵上的矛盾對不擋**（R14 verify logic 第 2 列 HIGH、requirements 第 4、security 第 6、regression 第 8 列：
    /// R14 拿未改寫的 before 比改寫後的 after，而配對鍵含 holder——被併鍵上的既有違反改寫後鍵變了、差集判成新；訊息自己列出的
    /// 兩筆 holder 都是 doom、末句還說既有的不擋）。D37：after 的違反是既有的，當且僅當構成它的索引裡有一組在合併前
    /// （同一筆倖存記錄、同一個 before 配對鍵）就已經構成同一類違反。
    func testWorkMergeIgnoresAHolderContradictionThatLivesOnTheDoomedKey() throws {
        try entry("keep2020a")
        try store.writeEntry(Entry(id: UUID(), citekey: "doom2020a", type: .periodicalArticle, title: "Doomed",
                                   authors: [.literal("A B")], date: "2020"))
        try org("some-org", refs: [verdict("resolution-confirmed", kind: .work, holder: "doom2020a", literal: "ISS"),
                                   verdict("resolution-rejected", kind: .work, holder: "doom2020a", literal: "iss")])
        let d = try divergence(keeper: "keep2020a", doomed: "doom2020a", shape: .work)
        GitFixture.commitAll(store.root)
        XCTAssertEqual(store.contradictoryVerdictIssues(in: try store.load()).count, 1, "合併前 validate 就報得出來")
        _ = try store.previewResolveDivergence(id: d.id, survivor: "keep2020a", overrideReason: nil)
        let report = try store.resolveDivergence(id: d.id, survivor: "keep2020a")
        XCTAssertEqual(report.failures, [])
        XCTAssertEqual(try holders(ofOrg: "some-org"), ["work:keep2020a", "work:keep2020a"], "矛盾對原封不動地改寫到倖存者")
        XCTAssertEqual(store.contradictoryVerdictIssues(in: try store.load()).count, 1, "validate 照報 warning")
    }

    /// 同一格的另一半：venue 對被併 work 早就持有兩個正規化後不同的 confirmed literal（validate 已報 D36 warning）——改寫到倖存者
    /// 後仍是那兩個、沒有新 literal 進來，不擋。
    func testWorkMergeIgnoresTwoLiteralsThatAlreadyLiveOnTheDoomedKey() throws {
        try entry("keep2020a")
        try store.writeEntry(Entry(id: UUID(), citekey: "doom2020a", type: .periodicalArticle, title: "Doomed",
                                   authors: [.literal("A B")], date: "2020"))
        var v = Venue(key: "alpha", type: .periodical, names: Timeline([TemporalValue(value: "Alpha Journal")]), authorized: [])
        v.references = [verdict("resolution-confirmed", kind: .work, holder: "doom2020a", literal: "Alpha Journal"),
                        verdict("resolution-confirmed", kind: .work, holder: "doom2020a", literal: "Beta Review")]
        try store.writeVenue(v)
        let d = try divergence(keeper: "keep2020a", doomed: "doom2020a", shape: .work)
        GitFixture.commitAll(store.root)
        _ = try store.previewResolveDivergence(id: d.id, survivor: "keep2020a", overrideReason: nil)
        let report = try store.resolveDivergence(id: d.id, survivor: "keep2020a")
        XCTAssertEqual(report.failures, [])
        XCTAssertEqual(try holders(ofVenue: "alpha"), ["work:keep2020a", "work:keep2020a"])
        let warnings = try XCTUnwrap(store.load().venues.first { $0.key == "alpha" }).validate().filter { $0.severity == .warning }
        XCTAssertEqual(warnings.filter { $0.message.contains("個正規化後不同的 confirmed literal") }.count, 1)
    }

    /// 但把既有的歧義**變大**仍擋：holder 對 doom 持 {Alpha, Beta}、對 keep 持 {Gamma}——改寫後 keep 是三個，配對 (alpha, keep)
    /// 得到它合併前沒有的歧義。訊息把遷移過來的兩筆列在「這次合併帶進來的」、倖存者既有的那筆另列（R14 verify DA 第 11 列）。
    func testWorkMergeRefusesWhenMigrationGrowsAnExistingAmbiguityAndSplitsTheMessage() throws {
        try entry("keep2020a")
        try store.writeEntry(Entry(id: UUID(), citekey: "doom2020a", type: .periodicalArticle, title: "Doomed",
                                   authors: [.literal("A B")], date: "2020"))
        var v = Venue(key: "alpha", type: .periodical, names: Timeline([TemporalValue(value: "Alpha Journal")]), authorized: [])
        v.references = [verdict("resolution-confirmed", kind: .work, holder: "keep2020a", literal: "Gamma Review"),
                        verdict("resolution-confirmed", kind: .work, holder: "doom2020a", literal: "Alpha Journal"),
                        verdict("resolution-confirmed", kind: .work, holder: "doom2020a", literal: "Beta Review")]
        try store.writeVenue(v)
        let d = try divergence(keeper: "keep2020a", doomed: "doom2020a", shape: .work)
        GitFixture.commitAll(store.root)
        XCTAssertThrowsError(try store.resolveDivergence(id: d.id, survivor: "keep2020a")) { err in
            guard case DivergenceResolveError.wouldLeaveTwoConfirmedLiterals(_, _, _, let brought, let existing, _, _) = err else { return XCTFail("要具名拒絕：\(err)") }
            XCTAssertEqual(brought.count, 2, "\(brought)"); XCTAssertEqual(existing.count, 1, "\(existing)")
            XCTAssertTrue((existing.first ?? "").contains("Gamma Review"), "\(existing)")
            // 位置以 -1 代表缺席（負控會讓標題或項目消失，斷言要紅不要 crash）
            let s = err.localizedDescription
            func pos(_ needle: String) -> Int { s.range(of: needle).map { s.distance(from: s.startIndex, to: $0.lowerBound) } ?? -1 }
            let a = pos("這次合併帶進來的"), b = pos("合併前就持有的")
            XCTAssertTrue(a >= 0 && b > a, s)
            XCTAssertTrue(pos("work:doom2020a :: Alpha Journal") > a && pos("work:doom2020a :: Alpha Journal") < b, s)
            XCTAssertTrue(pos("Gamma Review") > b, s)
            // R16（D45；R15 verify 第 20 列）：末句不得再說「含住在被併鍵上的不擋」——這兩筆正是住在被併鍵上、被本次搬到倖存配對
            XCTAssertTrue(s.contains("變大") && !s.contains("含住在被併鍵上的"), s)
        }
        XCTAssertEqual(try holders(ofVenue: "alpha"), ["work:keep2020a", "work:doom2020a", "work:doom2020a"], "零寫入")
    }

    /// keeper 路徑同型（R14 verify logic 第 2 列末句）：倖存者自己持有 `person:<被併>` 的既有矛盾對——改寫後鍵變成 survivor，
    /// R14 判成新。對照：`confirmed person:doom :: X` ＋ `rejected person:keep :: X` 是改寫後才相撞的，那才是新的。
    func testPersonMergeIgnoresTheKeepersOwnContradictionOnTheDoomedKeyButRefusesOneCreatedByRewriting() throws {
        var keeper = Person(key: "keeper-person", names: ["Keeper Person"])
        keeper.references = [verdict("resolution-confirmed", kind: .person, holder: "doomed-person", literal: "Org X"),
                             verdict("resolution-rejected", kind: .person, holder: "doomed-person", literal: "ORG X")]
        try store.writePerson(keeper)
        try store.writePerson(Person(key: "doomed-person", names: ["Doomed Person"]))
        let d = try divergence(keeper: "keeper-person", doomed: "doomed-person", shape: .person)
        GitFixture.commitAll(store.root)
        _ = try store.previewResolveDivergence(id: d.id, survivor: "keeper-person", overrideReason: nil)
        let report = try store.resolveDivergence(id: d.id, survivor: "keeper-person")
        XCTAssertEqual(report.failures, [])
        XCTAssertEqual(try holders(ofPerson: "keeper-person"), ["person:keeper-person", "person:keeper-person"])
        var k2 = Person(key: "keeper-two", names: ["Keeper Two"])
        k2.references = [verdict("resolution-confirmed", kind: .person, holder: "doomed-two", literal: "Org X"),
                         verdict("resolution-rejected", kind: .person, holder: "keeper-two", literal: "ORG X")]
        try store.writePerson(k2)
        try store.writePerson(Person(key: "doomed-two", names: ["Doomed Two"]))
        let d2 = try divergence(keeper: "keeper-two", doomed: "doomed-two", shape: .person)
        GitFixture.commitAll(store.root)
        XCTAssertThrowsError(try store.previewResolveDivergence(id: d2.id, survivor: "keeper-two", overrideReason: nil)) { err in
            guard case DivergenceResolveError.wouldContradictVerdicts = err else { return XCTFail("要具名拒絕：\(err)") }
        }
        XCTAssertEqual(try holders(ofPerson: "keeper-two"), ["person:doomed-two", "person:keeper-two"], "零寫入")
    }

    // MARK: - R15（D40）：收攏列印遷移前的原值、逐段截

    /// `verdictsCollapsed` 要印**遷移前**的原值並逐段截（R14 verify DA 第 10 列、logic 第 14 列、security 第 7 列：`describeCollapsedVerdict`
    /// 拿的是改寫後的 `r`，印出的字串不在任何 YAML 裡——而被丟掉的恆是被改寫的那一筆（勝者政策第 2 條）；且不截斷，1,400 字的
    /// judgement 在 sink 的整列上限處被整段擠掉）。preview 與實跑同源（D35）。
    func testCollapsedRowsNameTheOriginalValueAndClipEachPart() throws {
        try entry("keep2020a")
        try store.writeEntry(Entry(id: UUID(), citekey: "doom2020a", type: .periodicalArticle, title: "Doomed",
                                   authors: [.literal("A B")], date: "2020"))
        let long = String(repeating: "j", count: 1_400) + "END"
        var v = Venue(key: "alpha", type: .periodical, names: Timeline([TemporalValue(value: "Alpha Journal")]), authorized: [])
        v.references = [verdict("resolution-confirmed", kind: .work, holder: "keep2020a", literal: "Alpha Journal"),
                        ProvenanceReference(field: "resolution-confirmed",
                                            value: ProvenanceReference.VerdictPairingValue(holderKind: .work, holder: "doom2020a", literal: "ALPHA JOURNAL").encoded,
                                            kind: .judgement(statement: long, restsOn: []))]
        try store.writeVenue(v)
        let d = try divergence(keeper: "keep2020a", doomed: "doom2020a", shape: .work)
        GitFixture.commitAll(store.root)
        let preview = try store.previewResolveDivergence(id: d.id, survivor: "keep2020a", overrideReason: nil)
        let report = try store.resolveDivergence(id: d.id, survivor: "keep2020a")
        XCTAssertEqual(preview.verdictsCollapsed, report.verdictsCollapsed)
        let row = try XCTUnwrap(report.verdictsCollapsed.first, "\(report.verdictsCollapsed)")
        XCTAssertTrue(row.hasPrefix("venue「alpha」：") && row.contains("work:doom2020a :: ALPHA JOURNAL") && !row.contains("work:keep2020a :: ALPHA JOURNAL"), row)
        XCTAssertFalse(row.contains("END"), "judgement 逐段截 200 scalar：\(row.unicodeScalars.count)")
        XCTAssertLessThan(row.unicodeScalars.count, 600, row)
    }

    /// rename 那條路同一個生產者、同一個缺陷（R14 verify security 第 7 列、requirements 第 13 列）：收攏列要印舊 citekey 的原值。
    func testRenameCollapsedRowNamesTheOriginalValue() throws {
        try entry("old2020a")
        // R22（D62）起 rename 唯一的收攏路徑是「被改寫且**完全相同**（含 judgement 與 rests-on）的重複」——零資訊損失；收攏列印**遷移前**的原值（D40）。
        var v = Venue(key: "alpha", type: .periodical, names: Timeline([TemporalValue(value: "Alpha Journal")]), authorized: [])
        let same = ProvenanceReference(field: "resolution-confirmed",
                                       value: ProvenanceReference.VerdictPairingValue(holderKind: .work, holder: "old2020a", literal: "ALPHA JOURNAL").encoded,
                                       kind: .judgement(statement: "resolve apply [rule: venue-name-exact]", restsOn: []))
        v.references = [same, same]
        try store.writeVenue(v)
        let r = try store.renameEntry(from: "old2020a", to: "new2020a")
        XCTAssertEqual(r.verdictsCollapsed.count, 1, "\(r.verdictsCollapsed)")
        let row = r.verdictsCollapsed.first ?? ""
        XCTAssertTrue(row.hasPrefix("venue「alpha」：") && row.contains("work:old2020a :: ALPHA JOURNAL") && !row.contains("work:new2020a"), "印遷移前的原值：\(row)")
        XCTAssertTrue(row.contains("venue-name-exact") && !row.contains("留「"), "同拼法不說位元組：\(row)")
        let values = try XCTUnwrap(store.load().venues.first { $0.key == "alpha" }).references.compactMap(\.value)
        XCTAssertEqual(values.map { Array($0.utf8) }, [Array("work:new2020a :: ALPHA JOURNAL".utf8)], "\(values)")
    }

    // MARK: - R16（D45）：「既有」看倖存配對

    /// R15 verify 第 13 列：D37 的判準按 prior work 分區找「某一區已持有全部」——holder 對 doom 持 {Alpha, Beta}、對 keep 持 {Alpha}，
    /// doom 那一區 ⊇ {Alpha, Beta} 判為既有、放行；而 (alpha, keep) 合併前只有一個 literal、可以 demote，合併後被 D23 鎖住。
    /// D45：既有＝**倖存配對**合併前就持有整組；或倖存配對合併前一筆都沒有、整組原樣從單一被併鍵搬來（第 922 行那個測試）。
    /// 這一格兩者皆否→擋；訊息把 Beta 列在「帶進來的」、keep 自己的 Alpha 列在「合併前就持有的」。
    func testWorkMergeRefusesMovingAnAmbiguityOntoAPairingThatHeldOnlyPartOfIt() throws {
        try entry("keep2020a")
        try store.writeEntry(Entry(id: UUID(), citekey: "doom2020a", type: .periodicalArticle, title: "Doomed",
                                   authors: [.literal("A B")], date: "2020"))
        var v = Venue(key: "alpha", type: .periodical, names: Timeline([TemporalValue(value: "Alpha Journal")]), authorized: [])
        v.references = [verdict("resolution-confirmed", kind: .work, holder: "keep2020a", literal: "Alpha Journal"),
                        verdict("resolution-confirmed", kind: .work, holder: "doom2020a", literal: "Alpha Journal"),
                        verdict("resolution-confirmed", kind: .work, holder: "doom2020a", literal: "Beta Review")]
        try store.writeVenue(v)
        let d = try divergence(keeper: "keep2020a", doomed: "doom2020a", shape: .work)
        GitFixture.commitAll(store.root)
        XCTAssertThrowsError(try store.previewResolveDivergence(id: d.id, survivor: "keep2020a", overrideReason: nil)) { err in
            guard case DivergenceResolveError.wouldLeaveTwoConfirmedLiterals(_, _, let ck, let brought, let existing, _, _) = err else { return XCTFail("要具名拒絕：\(err)") }
            XCTAssertEqual(ck, "keep2020a")
            XCTAssertEqual(brought.count, 1, "\(brought)"); XCTAssertTrue((brought.first ?? "").contains("work:doom2020a :: Beta Review"), "\(brought)")
            XCTAssertEqual(existing.count, 1, "\(existing)"); XCTAssertTrue((existing.first ?? "").contains("work:keep2020a :: Alpha Journal"), "\(existing)")
            let s = err.localizedDescription
            XCTAssertTrue(s.contains("被併鍵") && s.contains("變大"), s)
        }
        XCTAssertEqual(try holders(ofVenue: "alpha"), ["work:keep2020a", "work:doom2020a", "work:doom2020a"], "零寫入")
    }

    /// 矛盾對同型：倖存配對合併前只有 confirmed，被併鍵上一組完整的矛盾對搬過來讓它變成矛盾——擋。R15 的 (a) 只問「構成它的索引裡有沒有
    /// 一組合併前就是矛盾對」，doom 那一組是，於是放行；而 (some-org, keep) 合併前是乾淨的。
    func testWorkMergeRefusesAContradictionThatLandsOnAPairingWithItsOwnVerdict() throws {
        try entry("keep2020a")
        try store.writeEntry(Entry(id: UUID(), citekey: "doom2020a", type: .periodicalArticle, title: "Doomed",
                                   authors: [.literal("A B")], date: "2020"))
        try org("some-org", refs: [verdict("resolution-confirmed", kind: .work, holder: "keep2020a", literal: "ISS"),
                                   verdict("resolution-confirmed", kind: .work, holder: "doom2020a", literal: "ISS"),
                                   verdict("resolution-rejected", kind: .work, holder: "doom2020a", literal: "iss")])
        let d = try divergence(keeper: "keep2020a", doomed: "doom2020a", shape: .work)
        GitFixture.commitAll(store.root)
        XCTAssertThrowsError(try store.previewResolveDivergence(id: d.id, survivor: "keep2020a", overrideReason: nil)) { err in
            guard case DivergenceResolveError.wouldContradictVerdicts = err else { return XCTFail("要具名拒絕：\(err)") }
            // R17（R16 verify requirements 第 4 列）：末句的括號把「住在被併鍵上的一律不擋」寫得比謂詞寬——這一格正是被擋的，訊息不得說它不擋
            let s = err.localizedDescription
            XCTAssertFalse(s.contains("也算"), s)
            XCTAssertTrue(s.contains("一筆都沒有"), "前件要寫出來：\(s)")
        }
        XCTAssertEqual(try holders(ofOrg: "some-org"), ["work:keep2020a", "work:doom2020a", "work:doom2020a"], "零寫入")
    }

    // MARK: - R17（D47）：holder 遷移不換掉倖存配對的位元組

    /// R16 verify DA 第 1 列真 binary 重現：venue 對 keep 持使用者確認的 `Vee Journal`、對 doom 持弱血統的 `VEE JOURNAL`，
    /// work 合併後只剩 `work:keep :: VEE JOURNAL`——之後 demote 把 keep 的邊改寫成不是它原本記的字。
    func testWorkMergeKeepsTheSurvivingPairingsOwnSpellingAndNamesBoth() throws {
        try entry("keep2020a")
        try store.writeEntry(Entry(id: UUID(), citekey: "doom2020a", type: .periodicalArticle, title: "Doomed",
                                   authors: [.literal("A B")], date: "2020"))
        var v = Venue(key: "vee", type: .periodical, names: Timeline([TemporalValue(value: "Vee Journal")]), authorized: [])
        v.references = [ProvenanceReference(field: "resolution-confirmed",
                                            value: ProvenanceReference.VerdictPairingValue(holderKind: .work, holder: "keep2020a", literal: "Vee Journal").encoded,
                                            kind: .judgement(statement: "使用者確認 [rule: venue-name-exact]", restsOn: [])),
                        ProvenanceReference(field: "resolution-confirmed",
                                            value: ProvenanceReference.VerdictPairingValue(holderKind: .work, holder: "doom2020a", literal: "VEE JOURNAL").encoded,
                                            kind: .judgement(statement: "merge migrate [rule: venue-name-loose]", restsOn: []))]
        try store.writeVenue(v)
        let d = try divergence(keeper: "keep2020a", doomed: "doom2020a", shape: .work)
        GitFixture.commitAll(store.root)
        let preview = try store.previewResolveDivergence(id: d.id, survivor: "keep2020a", overrideReason: nil)
        let report = try store.resolveDivergence(id: d.id, survivor: "keep2020a")
        XCTAssertEqual(report.failures, [])
        let values = try XCTUnwrap(store.load().venues.first { $0.key == "vee" }).references.compactMap(\.value)
        XCTAssertEqual(values.map { Array($0.utf8) }, [Array("work:keep2020a :: Vee Journal".utf8)], "\(values)")
        let row = try XCTUnwrap(report.verdictsCollapsed.first, "\(report.verdictsCollapsed)")
        XCTAssertTrue(row.contains("VEE JOURNAL") && row.contains("Vee Journal") && row.contains("位元組"), row)
        XCTAssertEqual(preview.verdictsCollapsed, report.verdictsCollapsed, "D35：preview 與實跑同源")
    }

    // MARK: - R18（D51）：倖存配對 ≠ 倖存邊

    /// R17 verify Codex 第 1 列 HIGH 的 person 鏡像（keeper 路徑）：work 的作者位指向被併 person，被併 person 的 confirmed 才是那條邊記錄的字；
    /// 倖存 person 對同一 work 持有另一個拼法的 confirmed 而沒有邊。D51：活著的邊那一筆勝。holder 路徑（work 合併）沒有這一格——
    /// work 合併不搬 venues／authors 邊（被併 work 的邊隨檔案消失、欄位遺失先拒），被併配對在合併後必死，D47 的「倖存配對自己的勝」在那裡就是活邊規則。
    func testPersonMergeKeeperPathKeepsTheLiveEdgesSpellingOverTheKeepersDeadVerdict() throws {
        let w = Entry(id: UUID(), citekey: "w2020a", type: .periodicalArticle, title: "T", authors: [.key("doomed-p")], date: "2020")
        var keeper = Person(key: "keeper-p", names: ["Smith, J."])
        keeper.references = [verdict("resolution-confirmed", kind: .work, holder: "w2020a", literal: "Smith, J.")]   // 沒有邊：死的
        var doomed = Person(key: "doomed-p", names: ["J. Smith"])
        doomed.references = [verdict("resolution-confirmed", kind: .work, holder: "w2020a", literal: "SMITH, J.")]
        let edges = LibraryStore.VerdictEdgeSet(snapshot: LibraryLoad(entries: [w], people: [keeper, doomed]))
        let m = LibraryStore.mergedPersonKeeper(keeper, absorbing: [doomed], edges: edges)
        let values = m.keeper.references.compactMap(\.value)
        XCTAssertEqual(values.map { Array($0.utf8) }, [Array("work:w2020a :: SMITH, J.".utf8)], "活著的邊記錄的字要留住：\(values)")
        XCTAssertEqual(m.verdictsCollapsed.count, 1, "\(m.verdictsCollapsed)")
        XCTAssertTrue(m.verdictsCollapsed[0].contains("Smith, J.") && m.verdictsCollapsed[0].contains("留「SMITH, J.」"), m.verdictsCollapsed[0])
        // 對照：沒有邊的資訊時退到「倖存配對自己的勝」（D47）
        let blind = LibraryStore.mergedPersonKeeper(keeper, absorbing: [doomed])
        XCTAssertEqual(blind.keeper.references.compactMap(\.value), ["work:w2020a :: Smith, J."])
    }

    // MARK: - R18（D53）：rename 只收攏它動到的

    /// R17 verify DA 第 10 列：rename 的收攏是「可解析 verdict 的全量」dedup，且沒有任何勝者政策——對不相干 work B 的兩筆只差位元組的
    /// confirmed（第 27 列第二類，#572 落地前沒有移除面）由 YAML 陣列順序決定留哪個，之後 demote 還回的可能不是 B 那條邊的原文。
    /// D53：rename 不決定它沒動到的東西——兩筆都沒被改寫的碰撞留著（validate 照報 warning）。
    func testUnrelatedRenameLeavesByteVariantDuplicatesOnAnotherWorkAlone() throws {
        try entry("a2020a"); try entry("b2020a")
        var v = Venue(key: "alpha", type: .periodical, names: Timeline([TemporalValue(value: "Psychometrika")]), authorized: [])
        v.references = [verdict("resolution-confirmed", kind: .work, holder: "b2020a", literal: "Psychometrika"),
                        verdict("resolution-confirmed", kind: .work, holder: "b2020a", literal: "PSYCHOMETRIKA"),
                        verdict("resolution-confirmed", kind: .work, holder: "a2020a", literal: "Alpha")]
        try store.writeVenue(v)
        let r = try store.renameEntry(from: "a2020a", to: "a2020b")
        XCTAssertEqual(r.verdictsCollapsed, [], "不相干 work 的重複不是這次 rename 的事")
        let values = try XCTUnwrap(store.load().venues.first { $0.key == "alpha" }).references.compactMap(\.value)
        XCTAssertEqual(Set(values), ["work:b2020a :: Psychometrika", "work:b2020a :: PSYCHOMETRIKA", "work:a2020b :: Alpha"], "\(values)")
    }






    // MARK: - R21（D60）：目的鍵上已有 verdict → rename 具名拒絕、零寫入

    /// R20 verify 五席同指（四席：`migratedVerdicts` 第一段後的早退讓 D58 只在 holder 另有被改寫的 verdict 時生效，只持有死 verdict 的
    /// holder 在 rename 後原樣復活；DA：D58 生效的那一半是無乾跑、無逆操作、無 git 閘的**判定刪除**——被丟的可能是人對另一筆仍存在的
    /// work 親自下的判定，正確處置是 repoint 而不是刪）。**D60**：與 merge 的 D31／D34 對齊——rename 之前掃三種 holder，任一筆 verdict 的配對
    /// 已指向新鍵（同 holderKind、不論 field 與拼法）即具名拒絕、零寫入，訊息逐筆列出 holder、欄位、value、rests-on，出路是先 repoint 或
    /// 從 YAML 刪掉再重跑。rename 自此不做任何判定的刪除（`two-kinds-of-edits`：程式編輯不得銷毀判定編輯的產物）。
    func testRenameRefusesWhenAnyHolderAlreadyHoldsAVerdictAtTheNewKey() throws {
        try entry("old2020a")
        let digest = "sha256:" + String(repeating: "a", count: 64)
        let live = verdict("resolution-confirmed", kind: .work, holder: "old2020a", literal: "Alpha Journal")
        let deadRejected = ProvenanceReference(field: "resolution-rejected",
                                               value: ProvenanceReference.VerdictPairingValue(holderKind: .work, holder: "new2020a", literal: "Alpha Journal").encoded,
                                               kind: .judgement(statement: "人親自下的否決", restsOn: [digest]))
        let deadOther = verdict("resolution-confirmed", kind: .work, holder: "new2020a", literal: "Other Journal")
        // 三種形：R19 DA（死的反向＋活的同拼法）、R20 四席（只有死的、沒有任何被改寫的）、拼法無關
        for refs in [[deadRejected, live], [deadRejected], [live, deadOther]] {
            var v = Venue(key: "alpha", type: .periodical, names: Timeline([TemporalValue(value: "Alpha Journal")]), authorized: [])
            v.references = refs
            try store.writeVenue(v)
            let before = try store.load()
            let alphaBefore = try XCTUnwrap(before.venues.first { $0.key == "alpha" }).references
            XCTAssertThrowsError(try store.renameEntry(from: "old2020a", to: "new2020a"), "\(refs.compactMap(\.value))") { error in
                let msg = (error as? LocalizedError)?.errorDescription ?? "\(error)"   // 使用者看到的那一份，不是 enum 的 debug 形
                XCTAssertTrue(msg.contains("new2020a") && msg.contains("venue「alpha」") && msg.contains("resolution-"), msg)
                XCTAssertTrue(msg.contains("改該記錄 YAML") || msg.contains("刪掉那一行"), "訊息要給走得通的出路：\(msg)")
                XCTAssertFalse(msg.contains("resolve-venues --repoint"), "R21 verify 第 3／10／25 列：repoint 對 D60 拒絕的形狀結構上不可用（目的鍵不存在，沒有邊可改指）：\(msg)")
                if refs.contains(where: { $0.value == deadRejected.value }) {
                    XCTAssertTrue(msg.contains("rests-on") && msg.contains(digest), "被拒的那筆連 rests-on 一起列出：\(msg)")
                }
            }
            let after = try store.load()
            XCTAssertNotNil(after.entries.first { $0.citekey == "old2020a" }, "零寫入：來源記錄沒被改名")
            XCTAssertNil(after.entries.first { $0.citekey == "new2020a" })
            XCTAssertEqual(try XCTUnwrap(after.venues.first { $0.key == "alpha" }).references.map { "\($0.field) \($0.value ?? "")" },
                           alphaBefore.map { "\($0.field) \($0.value ?? "")" }, "零寫入：holder 的 verdict 原封不動")
            XCTAssertEqual(store.health(from: after).deadVerdicts.count, store.health(from: before).deadVerdicts.count)
        }
    }

    /// D60 對三種 holder 都掃——person rename 時 organization 持有的 `person:<newKey>` verdict 同樣擋。
    func testRenamePersonRefusesWhenAnOrganizationHoldsAVerdictAtTheNewKey() throws {
        try store.writePerson(Person(key: "old-person", names: ["Old Person"]))
        try org("acme", refs: [verdict("resolution-confirmed", kind: .person, holder: "new-person", literal: "New Person")])
        XCTAssertThrowsError(try store.renamePerson(from: "old-person", to: "new-person")) { error in
            let msg = (error as? LocalizedError)?.errorDescription ?? "\(error)"
            XCTAssertTrue(msg.contains("organization「acme」") && msg.contains("new-person"), msg)
        }
        let after = try store.load()
        XCTAssertNotNil(after.people.first { $0.key == "old-person" }, "零寫入")
        XCTAssertNil(after.people.first { $0.key == "new-person" })
    }

    /// **D61（R22；R21 verify 第 1／8／12／16／36 列，DA 真 binary 前後對照）**：D60 的母體是 `load.people`／`venues`／`organizations`，quarantined 檔
    /// 不在裡面——一個 quarantined 的 holder 持有 `<kind>:<newKey> ::` 時 rename 照過，修好那個檔之後那筆從未對這筆記錄做過的判定生效、而且
    /// 沒有任何面會報（rename 前 validate 會報它是死 verdict，rename 後全綠）。R22 用行級文字比對；**R23 改成位元組比對**（D63，見下一條測試的理由）：
    /// 讀不到即 fail-closed，命中就拒絕並點名那個檔。斷言要分得出「命中」與「讀不到」——兩條 hit line 都含 `quarantine` 與檔名，只驗那兩個子串時
    /// needle 壞掉也綠（R22 verify 第 13 列）。
    func testRenameRefusesWhenAQuarantinedHolderHoldsAVerdictAtTheNewKey() throws {
        try entry("old2020a")
        var broken = Venue(key: "beta", type: .periodical, names: Timeline([TemporalValue(value: "Beta Review")]), authorized: [])
        broken.references = [verdict("resolution-confirmed", kind: .work, holder: "new2020a", literal: "Beta Review")]
        // 檔名 UUID 與記錄 id 不符 → 整檔 quarantine（既有手法）
        let file = "\(UUID().uuidString).yaml"
        try VenueYAML.encode(broken).write(to: store.entitiesDir.appendingPathComponent(file), atomically: true, encoding: .utf8)
        XCTAssertEqual(try store.load().quarantined.count, 1, "前提：那個檔真的被 quarantine")
        XCTAssertThrowsError(try store.renameEntry(from: "old2020a", to: "new2020a")) { error in
            let msg = (error as? LocalizedError)?.errorDescription ?? "\(error)"
            XCTAssertTrue(msg.contains(file) && msg.contains("位元組裡出現"), "要點名那個 quarantined 檔、且說是位元組命中：\(msg)")
            XCTAssertFalse(msg.contains("讀不到"), "分得出命中與讀不到（R22 verify 第 13 列）：\(msg)")
        }
        XCTAssertNotNil(try store.load().entries.first { $0.citekey == "old2020a" }, "零寫入")
    }

    /// **D63（R23；R22 verify 第 1／2／3／4 列，四席同指、DA 真 binary）**：D61 的 needle `<kind>:<newKey> ::` 含空白，而 YAML 只在空白處折行——
    /// 本 repo 的 emitter（Yams，libyaml 預設寬度 80）把長 value 折在 ` :: ` 之前，live store 2026-09-16 實測 2 筆；折行的 quarantined verdict 穿過
    /// rename，而三處通知說「已擋過」。位元組比對 `<kind>:<newKey>` 不含空白，折行打不斷它。fixture 直接寫折行的 YAML 文字（短 value 經 emitter 不會折）。
    func testRenameRefusesWhenAQuarantinedFileHoldsAFoldedVerdictAtTheNewKey() throws {
        try entry("old2020a")
        let file = "\(UUID().uuidString).yaml"   // 檔名 UUID 與記錄 id 不符 → 整檔 quarantine
        let folded = "venue:\nid: \(UUID().uuidString)\nkey: beta\ntype: periodical\nnames:\n- value: Beta Review\nreferences:\n"
            + "- field: resolution-confirmed\n  value: 'work:new2020a\n    :: Beta Review'\n  judgement: 人親自判定\n  rests-on: []\n"
        try folded.write(to: store.entitiesDir.appendingPathComponent(file), atomically: true, encoding: .utf8)
        XCTAssertEqual(try store.load().quarantined.count, 1, "前提：那個檔真的被 quarantine")
        XCTAssertThrowsError(try store.renameEntry(from: "old2020a", to: "new2020a")) { error in
            let msg = (error as? LocalizedError)?.errorDescription ?? "\(error)"
            XCTAssertTrue(msg.contains(file) && msg.contains("位元組裡出現"), "折行的 value 也要被擋、點名那個檔：\(msg)")
        }
        XCTAssertNotNil(try store.load().entries.first { $0.citekey == "old2020a" }, "零寫入")
    }

    /// D63 的 person 端（R22 verify DA 第 4 列：`rename-person` 對折行的 `person:new-person\n    :: …` 同樣 rc=0）。
    func testRenamePersonRefusesWhenAQuarantinedFileHoldsAFoldedVerdictAtTheNewKey() throws {
        try store.writePerson(Person(key: "old-person", names: ["Old Person"]))
        let file = "\(UUID().uuidString).yaml"
        let folded = "venue:\nid: \(UUID().uuidString)\nkey: beta\ntype: periodical\nnames:\n- value: Beta Review\nreferences:\n"
            + "- field: resolution-rejected\n  value: 'person:new-person\n    :: Old Person'\n  judgement: 人親自判定\n  rests-on: []\n"
        try folded.write(to: store.entitiesDir.appendingPathComponent(file), atomically: true, encoding: .utf8)
        GitFixture.commitAll(store.root)
        XCTAssertThrowsError(try store.renamePerson(from: "old-person", to: "new-person")) { error in
            let msg = (error as? LocalizedError)?.errorDescription ?? "\(error)"
            XCTAssertTrue(msg.contains(file) && msg.contains("person:new-person"), msg)
        }
        XCTAssertNotNil(try store.load().people.first { $0.key == "old-person" }, "零寫入")
    }

    /// D63 的另一半（R22 verify DA 第 4 列的偽陽性、第 33／36 列）：位元組比對會被 note 裡的字面觸發——與 merge 隔離檔閘同一種已接受的偽陽性——
    /// 但訊息**不得**說「含指向新鍵的 verdict」，只能說位元組裡出現、出路是修檔；鄰居鍵 `new2020a-2` 與 `network:new2020a` 都不得命中。
    func testRenameQuarantineByteScanIsHonestAboutFalsePositivesAndIgnoresNeighbourKeys() throws {
        try entry("old2020a")
        let neighbour = "\(UUID().uuidString).yaml"
        try ("venue:\nid: \(UUID().uuidString)\nkey: gamma\ntype: periodical\nnames:\n- value: Gamma\nreferences:\n"
             + "- field: resolution-confirmed\n  value: 'work:new2020a-2 :: Gamma'\n  judgement: x\n  rests-on: []\nnote: network:new2020a\n")
            .write(to: store.entitiesDir.appendingPathComponent(neighbour), atomically: true, encoding: .utf8)
        XCTAssertEqual(try store.load().quarantined.count, 1)
        let report = try store.renameEntry(from: "old2020a", to: "new2020a")   // 鄰居鍵與 `network:` 前綴都不是命中
        XCTAssertTrue(report.quarantinedNotScanned.contains { $0.hasSuffix(neighbour) }, "\(report.quarantinedNotScanned)")
        _ = try store.renameEntry(from: "new2020a", to: "old2020a")
        let mention = "\(UUID().uuidString).yaml"
        try "venue:\nid: \(UUID().uuidString)\nkey: delta\ntype: periodical\nnames:\n- value: Delta\nnote: 'we decided NOT to record work:new2020a here'\n"
            .write(to: store.entitiesDir.appendingPathComponent(mention), atomically: true, encoding: .utf8)
        XCTAssertThrowsError(try store.renameEntry(from: "old2020a", to: "new2020a")) { error in
            let msg = (error as? LocalizedError)?.errorDescription ?? "\(error)"
            XCTAssertTrue(msg.contains(mention) && msg.contains("位元組裡出現"), msg)
            XCTAssertFalse(msg.contains("含指向新鍵的 verdict"), "沒解析就不能說它含 verdict（偽陽性要誠實）：\(msg)")
            XCTAssertTrue(msg.contains("修好或移走"), "quarantined 命中的出路是修檔不是改 value：\(msg)")
        }
    }

    /// R22 verify DA 第 18 列（真 binary）：R22 把 quarantined 命中排在已解析的命中之後，25 筆 organization 就把它擠出 20 筆上限——而它是唯一
    /// 沒有其他面看得到的一類（`validate` 的死 verdict 掃描不掃 quarantined 記錄）。D63：quarantined 命中先列。上限走 `Entry.perRecordWarningCap`。
    func testRenameRefusalListsQuarantinedHitsBeforeTheCap() throws {
        try entry("old2020a")
        for i in 1...25 { try org("org-\(i)", refs: [verdict("resolution-confirmed", kind: .work, holder: "new2020a", literal: "Org \(i)")]) }
        let file = "\(UUID().uuidString).yaml"
        var broken = Venue(key: "beta", type: .periodical, names: Timeline([TemporalValue(value: "Beta Review")]), authorized: [])
        broken.references = [verdict("resolution-confirmed", kind: .work, holder: "new2020a", literal: "Beta Review")]
        try VenueYAML.encode(broken).write(to: store.entitiesDir.appendingPathComponent(file), atomically: true, encoding: .utf8)
        XCTAssertThrowsError(try store.renameEntry(from: "old2020a", to: "new2020a")) { error in
            let desc = (error as? LocalizedError)?.errorDescription ?? "\(error)"
            XCTAssertTrue(desc.contains(file), "quarantined 命中不得被上限擠掉：\(desc)")
            XCTAssertEqual((1...25).filter { desc.contains("organization「org-\($0)」") }.count, Entry.perRecordWarningCap - 1, desc)
            XCTAssertTrue(desc.contains("另有 6 條未列") && desc.contains("共 26 條"), desc)
        }
    }

    /// **D64（R23；R22 verify security 第 14 列）**：D62 讓 rename 把同鍵而 judgement 不同的兩筆原樣帶到新鍵——那一步零損失，但那個狀態在 R22
    /// 沒有任何面看得見（`contradictoryVerdicts` 只比 confirmed×rejected、D39 第二類以位元組相異分組），而下一次合併會收成一筆。
    /// `StoreHealth.duplicateVerdictRecords` 報它，rename 前後都報、指向當下的鍵。
    func testRenameCarriesADuplicateVerdictPairOntoTheNewKeyAndHealthReportsIt() throws {
        try entry("old2020a")
        var v = Venue(key: "alpha", type: .periodical, names: Timeline([TemporalValue(value: "Alpha Journal")]), authorized: [])
        func judged(_ s: String) -> ProvenanceReference {
            ProvenanceReference(field: "resolution-confirmed",
                                value: ProvenanceReference.VerdictPairingValue(holderKind: .work, holder: "old2020a", literal: "Alpha Journal").encoded,
                                kind: .judgement(statement: s, restsOn: []))
        }
        v.references = [judged("a"), judged("b")]
        try store.writeVenue(v)
        let before = store.health(from: try store.load())
        XCTAssertEqual(before.duplicateVerdictRecords.count, 1, before.duplicateVerdictRecords.map(\.issue.message).description)
        let msg = before.duplicateVerdictRecords.first?.issue.message ?? ""
        XCTAssertTrue(msg.contains("2 筆判定記錄") && msg.contains("彼此不同") && msg.contains("work:old2020a"), msg)
        XCTAssertEqual(before.duplicateVerdictRecords.first?.issue.severity, .warning)
        XCTAssertEqual(before.contradictoryVerdicts.count, 0, "同為 confirmed 不是矛盾")
        _ = try store.renameEntry(from: "old2020a", to: "new2020a")
        let after = store.health(from: try store.load())
        XCTAssertEqual(after.duplicateVerdictRecords.count, 1, "rename 帶過去的重複要看得見：\(after.duplicateVerdictRecords.map(\.issue.message))")
        XCTAssertTrue(after.duplicateVerdictRecords.first?.issue.message.contains("work:new2020a") == true)
        XCTAssertEqual(after.duplicateVerdictRecords.first?.owner, "alpha")
        XCTAssertEqual(after.duplicateVerdictRecords.first?.kind, "venue")
    }

    /// D64 的訊息分得出「完全相同」與「judgement／rests-on 不同」；乾淨的記錄零；三種 holder 記錄都掃。
    func testDuplicateVerdictRecordsDistinguishIdenticalFromDifferingAndScanEveryHolderKind() throws {
        let r = verdict("resolution-rejected", kind: .work, holder: "w2020a", literal: "Vee")
        try org("acme", refs: [r, r])   // 手改才寫得出的位元組相同重複
        try store.writePerson({ var p = Person(key: "pat", names: ["Pat"]); p.references = [verdict("resolution-confirmed", kind: .work, holder: "w2020a", literal: "Pat")]; return p }())
        var v = Venue(key: "alpha", type: .periodical, names: Timeline([TemporalValue(value: "Alpha Journal")]), authorized: [])
        v.references = [verdict("resolution-confirmed", kind: .work, holder: "w2020a", literal: "Alpha Journal"),
                        verdict("resolution-rejected", kind: .work, holder: "w2020a", literal: "Alpha Journal")]   // 那是矛盾對，不是重複
        try store.writeVenue(v)
        let health = store.health(from: try store.load())
        XCTAssertEqual(health.duplicateVerdictRecords.map { "\($0.kind):\($0.owner)" }, ["organization:acme"], "\(health.duplicateVerdictRecords.map(\.issue.message))")
        XCTAssertTrue(health.duplicateVerdictRecords.first?.issue.message.contains("全部完全相同") == true)
        XCTAssertEqual(health.contradictoryVerdicts.count, 1, "矛盾對走自己的家族")
    }

    /// D64 不重報第 27 列第二類已經報的那一格（venue×work 的 confirmed、只差位元組）——同一件事出兩則是雜訊；而 rejected 的只差位元組
    /// 沒有人報，D64 報它。每筆記錄至多 `Entry.perRecordWarningCap` 則、其餘一句概括（不進家族）。
    func testDuplicateVerdictRecordsDoNotDoubleReportTheVenueByteVariantClassAndAreCapped() throws {
        var v = Venue(key: "alpha", type: .periodical, names: Timeline([TemporalValue(value: "Alpha Journal")]), authorized: [])
        v.references = [verdict("resolution-confirmed", kind: .work, holder: "w1", literal: "alpha"),
                        verdict("resolution-confirmed", kind: .work, holder: "w1", literal: "ALPHA"),
                        verdict("resolution-rejected", kind: .work, holder: "w2", literal: "beta"),
                        verdict("resolution-rejected", kind: .work, holder: "w2", literal: "BETA")]
        try store.writeVenue(v)
        let health = store.health(from: try store.load())
        XCTAssertEqual(health.duplicateVerdictRecords.count, 1, health.duplicateVerdictRecords.map(\.issue.message).description)
        XCTAssertTrue(health.duplicateVerdictRecords.first?.issue.message.contains("resolution-rejected") == true)
        XCTAssertEqual(health.confirmedLiteralAmbiguities.count, 1, "confirmed 的位元組變體由第 27 列第二類報")
        let r = verdict("resolution-rejected", kind: .work, holder: "w", literal: "Vee")
        try org("acme", refs: (1...25).flatMap { i in
            [verdict("resolution-rejected", kind: .work, holder: "w\(i)", literal: "Vee"), verdict("resolution-rejected", kind: .work, holder: "w\(i)", literal: "Vee")] })
        _ = r
        let capped = store.health(from: try store.load())
        XCTAssertEqual(capped.duplicateVerdictRecords.filter { $0.owner == "acme" }.count, Entry.perRecordWarningCap)
        XCTAssertEqual(capped.cappedRecords.filter { $0.owner == "acme" }.count, 1, capped.cappedRecords.map(\.issue.message).description)
    }

    /// D65（R24；R23 verify Codex 第 1 列 HIGH）：D62 的「完全相同才折疊」必須比**位元組**。Swift `String` 的 `==`／`hashValue` 走 canonical
    /// equivalence，合成的 `Hashable` 繼承同一語意——NFC 的 `Sankhyā` 與 NFD 的 `Sankhya\u{0304}` 在 R23 被 `firstSeen` 當成同一筆折掉，
    /// 其中一種拼法永久消失（R16 D42 對第二半掃描修過同一個缺陷）。judgement 只差 NFC／NFD 同型。位元組相同的重複仍折（對照）。
    func testRenameKeepsNFCAndNFDSpellingsAsTwoVerdictsAndCollapsesNothing() throws {
        try entry("old2020a")
        let nfc = "Sankhy\u{0101}", nfd = "Sankhya\u{0304}"
        XCTAssertEqual(nfc, nfd, "前提：Swift 視兩者相等"); XCTAssertNotEqual(Array(nfc.utf8), Array(nfd.utf8))
        var v = Venue(key: "alpha", type: .periodical, names: Timeline([TemporalValue(value: "Alpha Journal")]), authorized: [])
        v.references = [verdict("resolution-confirmed", kind: .work, holder: "old2020a", literal: nfc),
                        verdict("resolution-confirmed", kind: .work, holder: "old2020a", literal: nfd)]
        try store.writeVenue(v)
        func judged(_ s: String) -> ProvenanceReference {
            ProvenanceReference(field: "resolution-rejected",
                                value: ProvenanceReference.VerdictPairingValue(holderKind: .work, holder: "old2020a", literal: "Vee").encoded,
                                kind: .judgement(statement: s, restsOn: []))
        }
        try org("acme", refs: [judged("\u{00E1}"), judged("a\u{0301}")])          // judgement 只差 NFC／NFD：兩筆都留
        let same = verdict("resolution-rejected", kind: .work, holder: "old2020a", literal: "Same")
        try org("twin", refs: [same, same])                                        // 位元組完全相同：對照，仍折成一筆
        let report = try store.renameEntry(from: "old2020a", to: "new2020a")
        XCTAssertEqual(report.verdictsCollapsed.count, 1, "只有 twin 的位元組相同重複折：\(report.verdictsCollapsed)")
        XCTAssertTrue(report.verdictsCollapsed[0].hasPrefix("organization「twin」："), report.verdictsCollapsed[0])
        let load = try store.load()
        let alpha = load.venues.first { $0.key == "alpha" }?.references.compactMap(\.value).map { Array($0.utf8) } ?? []
        XCTAssertEqual(alpha.count, 2, "NFC 與 NFD 兩筆都要在")
        let expect = [nfc, nfd].map { Array(ProvenanceReference.VerdictPairingValue(holderKind: .work, holder: "new2020a", literal: $0).encoded.utf8) }
        XCTAssertEqual(Set(alpha), Set(expect), "逐筆 UTF-8 位元組不變，只換 holder")
        let acme = load.organizations.first { $0.key == "acme" }?.references.compactMap { r -> [UInt8]? in
            if case .judgement(let s, _) = r.kind { return Array(s.utf8) } else { return nil } } ?? []
        XCTAssertEqual(Set(acme), Set([Array("\u{00E1}".utf8), Array("a\u{0301}".utf8)]), "judgement 的兩種拼法都要在")
        XCTAssertEqual(load.organizations.first { $0.key == "twin" }?.references.count, 1)
    }

    /// D65 的另一半：D64 判「全部完全相同」的鍵也是合成 `Hashable`——judgement 只差 NFC／NFD 的兩筆在 R23 被說成「全部完全相同」，
    /// 而它們的位元組不同、digest 也可能不同。同一把位元組鍵，兩處一起換。
    func testDuplicateVerdictRecordsCompareJudgementBytesNotCanonicalEquivalence() throws {
        func judged(_ s: String) -> ProvenanceReference {
            ProvenanceReference(field: "resolution-rejected",
                                value: ProvenanceReference.VerdictPairingValue(holderKind: .work, holder: "w2020a", literal: "Vee").encoded,
                                kind: .judgement(statement: s, restsOn: []))
        }
        try org("acme", refs: [judged("\u{00E1}"), judged("a\u{0301}")])
        let health = store.health(from: try store.load())
        XCTAssertEqual(health.duplicateVerdictRecords.count, 1, health.duplicateVerdictRecords.map(\.issue.message).description)
        let msg = health.duplicateVerdictRecords.first?.issue.message ?? ""
        XCTAssertTrue(msg.contains("彼此不同"), msg)
        XCTAssertFalse(msg.contains("全部完全相同"), msg)
    }

    /// D67（R25；R24 verify 第 3／11／16 列三席同指）：D64 的措辭要說出**哪一個維度**不同。分組鍵正規化 literal，所以同一組裡
    /// value 的拼法可以只差位元組；R24 用整筆 `byteExactKey` 判 sameness，把拼法差異也說成「judgement 或 rests-on 彼此不同」——
    /// 操作者會去找一個不存在的證據衝突。三種情形各出自己的話，且互不冒充。
    func testDuplicateVerdictRecordsSayWhichDimensionDiffers() throws {
        func judged(_ literal: String, _ s: String) -> ProvenanceReference {
            ProvenanceReference(field: "resolution-rejected",
                                value: ProvenanceReference.VerdictPairingValue(holderKind: .work, holder: "w2020a", literal: literal).encoded,
                                kind: .judgement(statement: s, restsOn: []))
        }
        try org("spell", refs: [judged("beta", "同一句"), judged("BETA", "同一句")])          // 只差拼法
        try org("judge", refs: [judged("beta", "a"), judged("beta", "b")])                  // 只差 judgement
        try org("both", refs: [judged("beta", "a"), judged("BETA", "b")])                   // 兩者都差
        try org("same", refs: [judged("beta", "a"), judged("beta", "a")])                   // 逐位元組相同
        let health = store.health(from: try store.load())
        func msg(_ owner: String) -> String { health.duplicateVerdictRecords.first { $0.owner == owner }?.issue.message ?? "<none>" }
        XCTAssertTrue(msg("spell").contains("拼法只差位元組") && !msg("spell").contains("judgement 或 rests-on"), msg("spell"))
        XCTAssertFalse(msg("spell").contains("即可"), "R25 verify 第 19 列：「統一拼法即可」與同一則尾端的「處置：留一筆」矛盾——sameness 只描述差異：\(msg("spell"))")
        XCTAssertTrue(msg("judge").contains("judgement 或 rests-on 彼此不同") && !msg("judge").contains("拼法"), msg("judge"))
        XCTAssertTrue(msg("both").contains("拼法只差位元組") && msg("both").contains("judgement 或 rests-on 彼此不同"), msg("both"))
        XCTAssertTrue(msg("same").contains("全部完全相同") && !msg("same").contains("彼此不同"), msg("same"))
    }

    /// D67 的第二半（R24 verify 第 8／10／18 列）：venue×work×confirmed 的排除只在「每一筆各有自己的拼法」時才成立——那時第 27 列
    /// 第二類真的報了它。混合組（`Alpha`、`Alpha`、`ALPHA`）裡位元組相同的那一對，第 27 列結構上看不到（它先以位元組去重），
    /// R24 的排除卻把整組吞掉，三個面都不出聲。
    func testDuplicateVerdictRecordsStillReportByteIdenticalDuplicatesInsideTheVenueByteVariantClass() throws {
        var v = Venue(key: "alpha", type: .periodical, names: Timeline([TemporalValue(value: "Alpha Journal")]), authorized: [])
        v.references = [verdict("resolution-confirmed", kind: .work, holder: "w1", literal: "Alpha"),
                        verdict("resolution-confirmed", kind: .work, holder: "w1", literal: "Alpha"),
                        verdict("resolution-confirmed", kind: .work, holder: "w1", literal: "ALPHA"),
                        verdict("resolution-confirmed", kind: .work, holder: "w2", literal: "Beta"),
                        verdict("resolution-confirmed", kind: .work, holder: "w2", literal: "BETA")]   // 純拼法組：仍由第 27 列報
        try store.writeVenue(v)
        let health = store.health(from: try store.load())
        XCTAssertEqual(health.duplicateVerdictRecords.map { $0.issue.message.contains("work:w1") }, [true],
                       health.duplicateVerdictRecords.map(\.issue.message).description)
        XCTAssertTrue(health.duplicateVerdictRecords.first?.issue.message.contains("3 筆判定記錄") == true)
        XCTAssertEqual(health.confirmedLiteralAmbiguities.count, 2, "第 27 列第二類照報自己的那兩格（w1 的兩種拼法、w2 的兩種拼法）——本族只補它看不到的那一對")
    }

    /// D71（R26；R25 verify 第 1／3／5／10／12／18 列，兩個 HIGH 之一）：carve-out 還要看 kind——每筆各有自己拼法、但 judgement／rests-on
    /// 彼此不同的組，第 27 列第二類結構上說不出 kind（它只看 literal），還叫人「留一筆」；D64 若沉默，一個真的證據衝突就被一句銷毀判定的指令
    /// 取代。純拼法組（kind 全同）仍只由第 27 列報。
    func testDuplicateVerdictRecordsReportJudgementConflictsEvenWhenEverySpellingIsDistinct() throws {
        func judged(_ holder: String, _ literal: String, _ s: String, _ ro: [String] = []) -> ProvenanceReference {
            ProvenanceReference(field: "resolution-confirmed",
                                value: ProvenanceReference.VerdictPairingValue(holderKind: .work, holder: holder, literal: literal).encoded,
                                kind: .judgement(statement: s, restsOn: ro))
        }
        let d1 = "sha256:" + String(repeating: "ab", count: 32), d2 = "sha256:" + String(repeating: "cd", count: 32)
        var v = Venue(key: "alpha", type: .periodical, names: Timeline([TemporalValue(value: "Alpha Journal")]), authorized: [])
        v.references = [judged("w1", "Alpha", "依據 A"), judged("w1", "ALPHA", "依據 B（相反）"),       // 拼法各異＋judgement 衝突：本族要報
                        judged("w2", "Beta", "同一句", [d1]), judged("w2", "BETA", "同一句", [d2]),  // 拼法各異＋rests-on 不同：本族要報
                        judged("w3", "Gamma", "同一句"), judged("w3", "GAMMA", "同一句")]           // 純拼法組：只由第 27 列報
        try store.writeVenue(v)
        let health = store.health(from: try store.load())
        let msgs = health.duplicateVerdictRecords.map(\.issue.message)
        XCTAssertEqual(msgs.count, 2, msgs.description)
        XCTAssertTrue(msgs.allSatisfy { $0.contains("judgement 或 rests-on 彼此不同") && $0.contains("拼法只差位元組") }, msgs.description)
        XCTAssertTrue(msgs.contains { $0.contains("work:w1，") } && msgs.contains { $0.contains("work:w2，") }, msgs.description)
        XCTAssertFalse(msgs.contains { $0.contains("work:w3，") }, "純拼法組不重報")
        XCTAssertEqual(health.confirmedLiteralAmbiguities.count, 3, "第 27 列第二類照報三格的拼法差異；kind 差異由本族補")
        let venueMsg = health.confirmedLiteralAmbiguities.first?.issue.message ?? ""
        XCTAssertTrue(venueMsg.contains("重複的判定記錄」那一族"), "第 27 列的「留一筆」要有限定詞——留一筆之前先看本族有沒有報 kind 差異：\(venueMsg)")
    }

    /// D68（R25；R24 verify security 第 13 列、DA 第 20 列真 binary：U+200B 原樣進終端）：`StoreHealth` 每一族迴送 store 字串都要走
    /// `displaySafeInvisible`——`displaySafe` 是列舉，不含 ZWSP／TAG／變體選擇子。三個 sink 都信任生產端不再消毒。
    func testStoreHealthMessagesEscapeInvisibleScalarsInStoreStrings() throws {
        let lit = "Fa\u{200B}nn"
        try org("acme", refs: [verdict("resolution-rejected", kind: .work, holder: "ghost", literal: lit),
                               verdict("resolution-rejected", kind: .work, holder: "w2020a", literal: lit),
                               verdict("resolution-rejected", kind: .work, holder: "w2020a", literal: lit)])
        try entry("w2020a")
        let health = store.health(from: try store.load())
        let dead = health.deadVerdicts.first?.issue.message ?? "<none>"
        let dup = health.duplicateVerdictRecords.first?.issue.message ?? "<none>"
        for m in [dead, dup] {
            XCTAssertTrue(m.contains("\\u{200B}"), m)
            XCTAssertFalse(m.unicodeScalars.contains { $0.value == 0x200B }, "原始 ZWSP 不得進訊息：\(m)")
        }
    }

    /// D69（R25；R24 verify 第 9／26／29 列、DA 第 39 列）：`fieldsLostByMerging` 的「倖存者身上已經有這筆 reference」要比位元組——
    /// canonical `==` 讓被併記錄的 NFD 拼法被判成「已有」，那組位元組隨檔案消失而報告說沒有遺失。D65 自己的 doc 說 `byteExactKey`
    /// 給的正是「這兩筆可以只留一筆而不丟任何位元組」那個問題。
    func testMergeLossCheckComparesReferenceBytesNotCanonicalEquivalence() throws {
        func ref(_ s: String) -> ProvenanceReference {
            ProvenanceReference(field: "doi", value: "10.1000/x", kind: .judgement(statement: s, restsOn: []))
        }
        var keeper = Entry(id: UUID(), citekey: "k2020", type: .periodicalArticle, title: "T"); keeper.references = [ref("\u{00E1}")]
        var doomed = Entry(id: UUID(), citekey: "d2020", type: .periodicalArticle, title: "T"); doomed.references = [ref("a\u{0301}")]
        let workLoss = LibraryStore.fieldsLostByMerging(doomed, into: keeper)
        XCTAssertTrue(workLoss.contains { $0.hasPrefix("references") }, "NFD 的那筆不在倖存者身上（位元組不同）——要報遺失")
        XCTAssertTrue(workLoss.contains { $0.contains("正規化後相等、位元組不同") },
                      "R25 verify 第 14 列：操作者看到兩筆長得一樣的 reference 卻被拒——訊息要說差異在位元組：\(workLoss)")
        var pk = Person(key: "pk", names: ["P"]); pk.references = [ref("\u{00E1}")]
        var pd = Person(key: "pd", names: ["P"]); pd.references = [ref("a\u{0301}")]
        let personLoss = LibraryStore.fieldsLostByMerging(pd, into: pk)
        XCTAssertTrue(personLoss.contains { $0.hasPrefix("references") } && personLoss.contains { $0.contains("正規化後相等、位元組不同") }, personLoss.description)
        var same = Entry(id: UUID(), citekey: "s2020", type: .periodicalArticle, title: "T"); same.references = [ref("\u{00E1}")]
        XCTAssertFalse(LibraryStore.fieldsLostByMerging(same, into: keeper).contains { $0.hasPrefix("references") }, "位元組相同的不報")
    }

    /// R21 verify 第 9／11／15 列（DA 真 binary）：rename 的 CLI 出口在 `displaySafeAssembled` 逐行截 400，而 R21 把 rests-on 排在行尾——一個一般長度
    /// 的 judgement 就把 digest 切成半個 sha256（比不印更糟：看起來像一個值、grep 不到）。R22：每筆命中拆成多行——holder／value 一行、judgement 一行、
    /// **每個 digest 自己一行**（71 字，永遠在 400 之內）；本測試把 description 送過與 CLI 相同的 sink 再驗。
    func testRenameRefusalKeepsEveryDigestIntactThroughTheCLISink() throws {
        try entry("old2020a")
        let digests = (1...3).map { "sha256:" + String(repeating: "\($0)", count: 64) }
        let longStatement = String(repeating: "使用者親自核對紙本刊名頁後確認；", count: 14)   // > 200 scalar
        let longLiteral = "Psychological Methods " + String(repeating: "(old series) ", count: 12)
        let dead = ProvenanceReference(field: "resolution-rejected",
                                       value: ProvenanceReference.VerdictPairingValue(holderKind: .work, holder: "new2020a", literal: longLiteral).encoded,
                                       kind: .judgement(statement: longStatement, restsOn: digests))
        var v = Venue(key: "psychological-methods", type: .periodical, names: Timeline([TemporalValue(value: "Psychological Methods")]), authorized: [])
        v.references = [dead]
        try store.writeVenue(v)
        XCTAssertThrowsError(try store.renameEntry(from: "old2020a", to: "new2020a")) { error in
            let desc = (error as? LocalizedError)?.errorDescription ?? "\(error)"
            let sunk = displaySafeAssembled(desc)   // 與 CLI.main 同一個 sink、同一個預設上限
            for d in digests { XCTAssertTrue(sunk.contains(d), "digest 要完整穿過 CLI sink：\(d) 不在\n\(sunk)") }
            // 生產端對 value／statement 的 200 截斷是合法的（那是它們自己的上限）；sink 不得再截任何一行——digest 行尤其
            let sunkLines = sunk.split(separator: "\n").map(String.init)
            XCTAssertFalse(sunkLines.contains { $0.contains("rests-on") && $0.contains("已截斷") }, "digest 行不得被截：\n\(sunk)")
            XCTAssertEqual(sunkLines.count, desc.split(separator: "\n").count, "sink 不得吞行：\n\(sunk)")
        }
    }

    /// R21 verify 第 7／17／24／28 列：拒絕訊息逐筆列出全部命中、行數無上限，與 D30／R14 的上限紀律相反。R22：至多列 20 筆命中、其餘一句揭露總數。
    func testRenameRefusalListsAtMostTwentyHitsAndDisclosesTheRest() throws {
        try entry("old2020a")
        for i in 1...25 {
            try org("org-\(i)", refs: [verdict("resolution-confirmed", kind: .work, holder: "new2020a", literal: "Org \(i)")])
        }
        XCTAssertThrowsError(try store.renameEntry(from: "old2020a", to: "new2020a")) { error in
            let desc = (error as? LocalizedError)?.errorDescription ?? "\(error)"
            let named = (1...25).filter { desc.contains("organization「org-\($0)」") }.count
            XCTAssertEqual(named, 20, "至多列 20 筆：\(desc)")
            XCTAssertTrue(desc.contains("另有 5 條未列") && desc.contains("共 25 條"), "其餘要揭露總數：\(desc)")
        }
    }

    /// R21 verify 第 4／20 列：`renameEntry` 沒有 `oldKey != newKey` 守衛（`renamePerson` 有），於是自我改名撞 D60、訊息說「目的鍵此刻不存在」——假話。
    func testRenameEntryRefusesSelfRenameBeforeAnyOtherCheck() throws {
        try entry("x2020a")
        try org("acme", refs: [verdict("resolution-confirmed", kind: .work, holder: "x2020a", literal: "Acme")])
        XCTAssertThrowsError(try store.renameEntry(from: "x2020a", to: "x2020a")) { error in
            let msg = (error as? LocalizedError)?.errorDescription ?? "\(error)"
            XCTAssertTrue(msg.contains("新舊相同"), msg)
            XCTAssertFalse(msg.contains("死 verdict"), "自我改名不得被 D60 用假話拒絕：\(msg)")
        }
    }

    /// D55 留下來的那一半：兩筆被改寫而拼法不同的**都留**（第 27 列第二類 warning 是 rename 之前就在的，rename 不替它判定），
    /// 位元組相同的被改寫重複只留一筆——三種排列同一個答案。R21 起這條 fixture 不再放死 verdict（那是 D60 的拒絕格）。
    func testRenameKeepsEveryRewrittenSpellingAndFoldsByteIdenticalOnes() throws {
        try entry("old2020a")
        var v = Venue(key: "alpha", type: .periodical, names: Timeline([TemporalValue(value: "Alpha Journal")]), authorized: [])
        let liveA = verdict("resolution-confirmed", kind: .work, holder: "old2020a", literal: "ALPHA JOURNAL")
        let liveB = verdict("resolution-confirmed", kind: .work, holder: "old2020a", literal: "alpha journal")
        let liveA2 = verdict("resolution-confirmed", kind: .work, holder: "old2020a", literal: "ALPHA JOURNAL")
        for refs in [[liveA, liveB, liveA2], [liveA, liveA2, liveB], [liveA2, liveB, liveA]] {
            let order = refs.compactMap(\.value).joined(separator: " | ")
            v.references = refs
            try store.writeVenue(v)
            let r = try store.renameEntry(from: "old2020a", to: "new2020a")
            let values = try XCTUnwrap(store.load().venues.first { $0.key == "alpha" }).references.compactMap(\.value)
            XCTAssertEqual(Set(values.map { Array($0.utf8) }),
                           [Array("work:new2020a :: ALPHA JOURNAL".utf8), Array("work:new2020a :: alpha journal".utf8)], "\(order) → \(values)")
            XCTAssertEqual(values.count, 2, "\(order) → \(values)")
            XCTAssertEqual(r.verdictsCollapsed.count, 1, "位元組相同的重複一筆：\(order) → \(r.verdictsCollapsed)")
            XCTAssertTrue(r.verdictsCollapsed.contains { $0.contains("work:old2020a :: ALPHA JOURNAL") && !$0.contains("留「") }, "同拼法的重複不說位元組：\(order) → \(r.verdictsCollapsed)")
            _ = try store.renameEntry(from: "new2020a", to: "old2020a")   // 還原給下一輪
        }
    }

    /// R21 verify DA 第 14 列（真 binary）：R20 的折疊以 (field, value, literal 位元組) 為鍵、不看 `kind`——兩筆同拼法而 judgement／rests-on 不同的
    /// verdict 被折成一筆，被丟那筆的 statement 與 digest 從 store 永久消失，而 `validate` 事前不出聲；那正是 R20 DA 用來撤掉 D58 的同一句話。
    /// **D62（R22）**：rename 只折**完全相同**（field、value、judgement、rests-on 全等）的重複——零資訊損失；judgement 不同的兩筆都留、不回報收攏。
    /// rename 自此不呼叫 `collapseWinner`（#468 的血統層只在 merge 跑）。
    func testRenameKeepsSameSpellingVerdictsWhoseJudgementsDiffer() throws {
        try entry("old2020a")
        var v = Venue(key: "alpha", type: .periodical, names: Timeline([TemporalValue(value: "Alpha Journal")]), authorized: [])
        func judged(_ statement: String) -> ProvenanceReference {
            ProvenanceReference(field: "resolution-confirmed",
                                value: ProvenanceReference.VerdictPairingValue(holderKind: .work, holder: "old2020a", literal: "Alpha Journal").encoded,
                                kind: .judgement(statement: statement, restsOn: []))
        }
        let strong = judged("resolve apply [rule: venue-name-exact]")
        let weakOne = judged("resolve apply [rule: author-name-initials]")
        for refs in [[strong, weakOne], [weakOne, strong]] {
            v.references = refs
            try store.writeVenue(v)
            let r = try store.renameEntry(from: "old2020a", to: "new2020a")
            let alpha = try XCTUnwrap(store.load().venues.first { $0.key == "alpha" })
            XCTAssertEqual(alpha.references.count, 2, "judgement 不同的兩筆都留：\(alpha.references)")
            XCTAssertEqual(Set(alpha.references.map { LibraryStore.verdictStatement($0) }),
                           ["resolve apply [rule: venue-name-exact]", "resolve apply [rule: author-name-initials]"])
            XCTAssertEqual(r.verdictsCollapsed, [], "沒有東西被丟，就不該說丟了")
            _ = try store.renameEntry(from: "new2020a", to: "old2020a")   // 還原給下一輪
        }
    }

    /// R19 verify regression 第 23 列：D55 把整組放在鍵首次出現處，夾在同鍵兩個成員之間、屬於別的鍵的 reference 被推到整組後面——
    /// 未揭露、未測、跨記錄的副作用（`references:` 陣列順序原樣序列化）。R20：在原位置收攏——留下的每一筆待在自己原來的位置，
    /// 不相干 reference 的相對順序不變。
    func testRenameKeepsTheRelativeOrderOfUntouchedReferences() throws {
        try entry("old2020a"); try entry("b2020a")
        var v = Venue(key: "alpha", type: .periodical, names: Timeline([TemporalValue(value: "Alpha Journal")]), authorized: [])
        v.references = [verdict("resolution-confirmed", kind: .work, holder: "old2020a", literal: "Alpha Journal"),
                        verdict("resolution-confirmed", kind: .work, holder: "b2020a", literal: "Alpha Journal"),
                        verdict("resolution-confirmed", kind: .work, holder: "old2020a", literal: "ALPHA JOURNAL")]
        try store.writeVenue(v)
        _ = try store.renameEntry(from: "old2020a", to: "new2020a")
        let values = try XCTUnwrap(store.load().venues.first { $0.key == "alpha" }).references.compactMap(\.value)
        XCTAssertEqual(values, ["work:new2020a :: Alpha Journal", "work:b2020a :: Alpha Journal", "work:new2020a :: ALPHA JOURNAL"], "\(values)")
    }


    // MARK: - R20：`VerdictEdgeSet` 的邊只收合法 StoreKey

    /// R19 verify security 第 19 列：`VerdictEdgeSet` 以 `|`／`:` 串鍵，而 `Entry.venues[].key`／`authors[].key` 沒有 StoreKey 約束——
    /// 一個手改的鍵可以偽造「活著的邊」去操縱 D51 的勝者。查詢側早經 `VerdictPairingValue.parse` 驗過 holder；插入側補同一道，
    /// 分隔符改用不可表示的 U+0000（與 `contradictoryVerdictIssues`／`cappedRecords` 同型）。
    func testVerdictEdgeSetIgnoresEdgesWhoseKeyIsNotAStoreKey() throws {
        var forged = Entry(id: UUID(), citekey: "x2020a", type: .periodicalArticle, title: "T", authors: [.literal("A B")], date: "2020")
        forged.venues = [.key("alpha|work:victim2020a"), .key("alpha")]
        let edges = LibraryStore.VerdictEdgeSet(snapshot: LibraryLoad(entries: [forged]))
        let forgedPairing = ProvenanceReference.VerdictPairingValue(holderKind: .work, holder: "x2020a", literal: "L")
        XCTAssertFalse(edges.isLive(recordKind: "venue", recordKey: "alpha|work:victim2020a", pairing: forgedPairing), "不是 StoreKey 的鍵不成邊")
        XCTAssertTrue(edges.isLive(recordKind: "venue", recordKey: "alpha", pairing: forgedPairing), "合法的邊照常")
        XCTAssertFalse(edges.isLive(recordKind: "venue", recordKey: "alpha", pairing: ProvenanceReference.VerdictPairingValue(holderKind: .work, holder: "victim2020a", literal: "L")))
    }
}
