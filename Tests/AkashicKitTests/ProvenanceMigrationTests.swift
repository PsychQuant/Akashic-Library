import XCTest
import Foundation
@testable import AkashicCore
@testable import AkashicStoreIO

/// #146：`TemporalValue.source` 裡的 `sha256:` 摘要要搬進 `references:`。
///
/// ## 判準來自資料，不是來自型別
///
/// 直覺會說「有 digest 有 retrieved，那是擷取型」。真實資料（22 筆）說不是——每一筆
/// 的 `note` 都以「由…推得」開頭，那是**對證據的推理**：`note` 是斷言、digest 是
/// 依據，對應 `Kind.judgement`。而擷取型也**裝不下**它們：`retrieval` 要求 `url`
/// 與 `status`，但那些 blob 沒有 URL（「圖書館寄來的檔案」、「以 DOI 逐筆查詢
/// 多個 API」都不是單一 URL）。
///
/// **先前判斷這需要第三種 Kind，是只看 `sources/index.jsonl` 的形狀、沒讀 `note`
/// 得出的結論。** 這裡把「讀了資料就不需要新 Kind」釘住——若哪天有人為了「更一般」
/// 而加第三種 Kind，這組測試會提醒他先看看真實資料長什麼樣。
final class ProvenanceMigrationTests: XCTestCase {
    private var root: URL!
    private var store: LibraryStore!
    private let digest = "sha256:" + String(repeating: "0a", count: 32)

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("akashic-pm146-\(UUID().uuidString)")
        store = LibraryStore(root: root)
        try store.ensureLayout()
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    private func personWithDigestAffiliation(
        key: String = "chen-pao-yang",
        note: String? = "由論文作者機構字串推得：Bioinformatics Program, Institute of "
                      + "Statistical Science。統計所是該學程的 host institute；此為學程關係、"
                      + "非所內研究人員任用，未宣稱任期區間"
    ) -> Person {
        var p = Person(key: key, names: PersonNames(authorized: ["Chen, Pao-Yang"]))
        p.profile.affiliations = TimelineOf([
            TemporalValue(value: OrgRef.key("institute-of-statistical-science"),
                          source: digest, note: note)
        ])
        return p
    }

    // MARK: - 搬對地方

    /// digest + note → `judgement` reference，且 `source`／`note` 清空。
    func testDigestSourceBecomesJudgementReference() throws {
        try store.writePerson(personWithDigestAffiliation())
        let report = try ProvenanceMigration.digestSourcesToReferences(store: store, dryRun: false)
        XCTAssertEqual(report.migrated, 1)
        XCTAssertEqual(report.records, ["chen-pao-yang"])
        XCTAssertEqual(report.skipped, [])

        let p = try XCTUnwrap(try store.load().people.first)
        XCTAssertEqual(p.references.count, 1, "reference 沒建出來")
        let r = try XCTUnwrap(p.references.first)
        XCTAssertEqual(r.field, "profile.affiliations",
                       "欄位名必須帶 profile. 前綴——白名單用那個形式，否則載入被拒")
        XCTAssertEqual(r.value, "institute-of-statistical-science",
                       "collection 要以**值**定位（D2：索引在重排時失效）")
        guard case let .judgement(statement, restsOn) = r.kind else {
            return XCTFail("必須是 judgement——這些是推理不是擷取，且沒有 URL 可填：\(r.kind)")
        }
        XCTAssertTrue(statement.contains("host institute"), "note 的全文要成為斷言")
        XCTAssertEqual(restsOn, [digest])

        // 舊形式必須清乾淨，否則同一份 provenance 記在兩層——那正是本 issue 的病
        let a = try XCTUnwrap(p.profile.affiliations.entries.first)
        XCTAssertNil(a.source, "digest 留在 source 就沒有真的遷移")
        XCTAssertNil(a.note, "note 已成為 judgement 的斷言，留著會是兩份")
        XCTAssertEqual(a.value, .key("institute-of-statistical-science"), "值本身不得被動到")
    }

    /// **裸 URL 一律不動**——#66 的 D7 Non-Goal，本次只清不屬於那個欄位的形式。
    func testPlainURLSourcesAreUntouched() throws {
        var p = Person(key: "url-person", names: PersonNames(authorized: ["N"]))
        p.profile.affiliations = TimelineOf([
            TemporalValue(value: OrgRef.literal("Academia Sinica"),
                          source: "https://www.stat.sinica.edu.tw/", note: "所網頁")
        ])
        try store.writePerson(p)
        let report = try ProvenanceMigration.digestSourcesToReferences(store: store, dryRun: false)
        XCTAssertEqual(report.migrated, 0)
        let after = try XCTUnwrap(try store.load().people.first)
        XCTAssertEqual(after.profile.affiliations.entries.first?.source,
                       "https://www.stat.sinica.edu.tw/", "URL 形式不在本次範圍")
        XCTAssertEqual(after.profile.affiliations.entries.first?.note, "所網頁")
        XCTAssertTrue(after.references.isEmpty)
        // **也不得出現在 skipped。** 這條斷言是 mutation 逼出來的：把判準從
        // `hasPrefix("sha256:")` 放寬成 `!isEmpty`，URL 會走到 digest 形狀檢查而
        // 被記成「形狀不合法」——**磁碟結果完全相同**，只有報告多一筆假警告。
        // 少了這條，那個 mutation 十條全綠。「不動它」包含「不對它有意見」。
        XCTAssertEqual(report.skipped, [],
                       "URL 不在本次範圍，不該被當成壞掉的 digest 報出來：\(report.skipped)")
    }

    /// **沒有 note 就不搬**——斷言的內容不能由遷移程式代寫。
    ///
    /// 憑空生一句（「來源為 <digest>」）會製造一筆看起來有依據、實際什麼都沒說的
    /// provenance，比留在舊形式更糟：舊形式至少誠實地顯示「這裡缺東西」。
    func testMissingNoteIsSkippedNotInvented() throws {
        try store.writePerson(personWithDigestAffiliation(key: "no-note", note: nil))
        let report = try ProvenanceMigration.digestSourcesToReferences(store: store, dryRun: false)
        XCTAssertEqual(report.migrated, 0)
        XCTAssertEqual(report.skipped.count, 1)
        XCTAssertEqual(report.skipped.first?.record, "no-note")
        XCTAssertTrue(report.skipped.first?.reason.contains("不能由遷移程式代寫") == true,
                      "理由要說清楚為什麼不代寫：\(report.skipped)")
        let p = try XCTUnwrap(try store.load().people.first)
        XCTAssertEqual(p.profile.affiliations.entries.first?.source, digest, "搬不動就留在原地")
        XCTAssertTrue(p.references.isEmpty, "不得寫出半成品 reference")
    }

    /// 形狀不合法的 digest 同樣跳過並報告——`references:` 拒收它，靜默丟棄更糟。
    ///
    /// **fixture 必須讓同一人同時有可搬與不可搬的維度**（#146 verify F3）。第一版
    /// 那個人**沒有任何可搬項**，於是 `guard !pending.isEmpty` 讓它根本不寫檔——
    /// mutation「malformed 分支順手清 source」在該 fixture 下是惰性的，1036 條全綠。
    ///
    /// 那個 mutation 的實際後果是**報告與磁碟直接矛盾**：印「搬不動 1 筆（留在
    /// 原形式）」，而磁碟上的 `source: sha256:NOTHEX` 已消失、之後 doctor 報 0。
    /// 「skip 不得動原資料」這條在**沒有 note** 的分支本來就有釘（見上一條），
    /// 在 malformed 分支沒有——既有測試的不對稱。
    func testMalformedDigestIsSkippedWithoutTouchingTheOriginal() throws {
        var p = personWithDigestAffiliation(key: "bad-digest")          // 可搬
        p.profile.ranks = TimelineOf([                                   // 不可搬
            TemporalValue(value: "研究員", source: "sha256:NOTHEX", note: "由聘書推得")])
        try store.writePerson(p)
        let report = try ProvenanceMigration.digestSourcesToReferences(store: store, dryRun: false)
        XCTAssertEqual(report.migrated, 1, "可搬的那條要搬")
        XCTAssertEqual(report.skipped.count, 1)
        XCTAssertTrue(report.skipped.first?.reason.contains("形狀不合法") == true,
                      "\(report.skipped)")
        let after = try XCTUnwrap(try store.load().people.first)
        XCTAssertEqual(after.profile.ranks.entries.first?.source, "sha256:NOTHEX",
                       "報告說「留在原形式」，磁碟就必須真的留著")
        XCTAssertEqual(after.profile.ranks.entries.first?.note, "由聘書推得", "note 同理")
    }

    /// **`report.records` 不得誇報。** 同型的病本 repo 記過多次（「報寫入數不是
    /// 候選數——先前用 candidates.count，失敗時誇報」）。
    ///
    /// mutation 把 `records.append` 移到 `guard !pending.isEmpty` 之前 → 對真實
    /// store 的 dry-run 會印「搬進 references: 22 筆，涉及 **867** 筆記錄」，
    /// 而磁碟結果完全相同（#146 verify F3(a)）。
    func testRecordsListOnlyContainsRecordsActuallyChanged() throws {
        try store.writePerson(personWithDigestAffiliation(key: "has-digest"))
        try store.writePerson(Person(key: "untouched", names: ["N"]))
        let report = try ProvenanceMigration.digestSourcesToReferences(store: store, dryRun: false)
        XCTAssertEqual(report.records, ["has-digest"], "沒被動到的記錄不得列進去")
    }

    // MARK: - 覆蓋面：不只 affiliations

    /// **每條 timeline 都要掃。** 真實資料目前只有 `affiliations` 有 digest，
    /// 但那是今天的事實不是不變式——只處理它會留下靜默缺口。
    func testAllTimelinesAreScannedNotJustAffiliations() throws {
        var p = Person(key: "many-fields", names: PersonNames(authorized: ["N"]))
        p.profile.ranks = TimelineOf([TemporalValue(value: "研究員", source: digest, note: "由聘書推得")])
        p.profile.administrative = TimelineOf([TemporalValue(value: "所長", source: digest, note: "由公告推得")])
        p.profile.appointments = TimelineOf([TemporalValue(value: "全職", source: digest, note: "由名冊推得")])
        p.profile.fields = TimelineOf([TemporalValue(value: "統計", source: digest, note: "由著作推得")])
        p.profile.contacts = ["email": TimelineOf([
            TemporalValue(value: "a@b.invalid", source: digest, note: "由所網頁推得")])]
        try store.writePerson(p)
        let report = try ProvenanceMigration.digestSourcesToReferences(store: store, dryRun: false)
        XCTAssertEqual(report.migrated, 4, "四條可搬的 timeline 都要搬到：\(report)")
        let fields = Set(try XCTUnwrap(try store.load().people.first).references.map(\.field))
        XCTAssertEqual(fields, ["profile.ranks", "profile.administrative",
                                "profile.appointments", "profile.fields"])
        // **contacts 搬不了要報出來**——白名單沒有它，加進去會讓舊 binary 拒絕
        // 載入整個 store（需要格式 bump，不在 #146 範圍）。靜默略過會讓
        // 「遷移完成」與「遷移完成但漏了一維」看起來一樣。
        XCTAssertEqual(report.skipped.count, 1, "contacts 要進 skipped：\(report.skipped)")
        XCTAssertEqual(report.skipped.first?.field, "profile.contacts.email")
        XCTAssertTrue(report.skipped.first?.reason.contains("quarantine") == true,
                      "理由要說出為什麼不能直接加白名單，而且要說對——後果是**該人檔被"
                      + "quarantine**，不是整個 store 拒絕載入（#146 verify 實測）：\(report.skipped)")
    }

    /// organization 的 `names` / `parents` 同樣要掃。
    func testOrganizationTimelinesAreScanned() throws {
        var o = Organization(key: "iss", names: TimelineOf([
            TemporalValue(value: "統計科學研究所", source: digest, note: "由所史推得")]))
        o.parents = TimelineOf([
            TemporalValue(value: OrgRef.key("academia-sinica"), source: digest, note: "由組織圖推得")])
        try store.writeOrganization(o)
        let report = try ProvenanceMigration.digestSourcesToReferences(store: store, dryRun: false)
        XCTAssertEqual(report.migrated, 2)
        XCTAssertEqual(Set(try XCTUnwrap(try store.load().organizations.first).references.map(\.field)),
                       ["names", "parents"])
    }

    // MARK: - dry-run 與殘留檢查

    /// dry-run 回報一樣，但**不得動磁碟**。
    func testDryRunReportsWithoutWriting() throws {
        try store.writePerson(personWithDigestAffiliation())
        let dry = try ProvenanceMigration.digestSourcesToReferences(store: store, dryRun: true)
        XCTAssertEqual(dry.migrated, 1)
        let p = try XCTUnwrap(try store.load().people.first)
        XCTAssertEqual(p.profile.affiliations.entries.first?.source, digest, "dry-run 寫了磁碟")
        XCTAssertTrue(p.references.isEmpty, "dry-run 寫了磁碟")
        // 真跑之後才變
        _ = try ProvenanceMigration.digestSourcesToReferences(store: store, dryRun: false)
        XCTAssertNil(try store.load().people.first?.profile.affiliations.entries.first?.source)
    }

    /// **殘留檢查與遷移分開存在**：遷移是一次性動作，「source 只放裸 URL」是要
    /// 持續成立的不變式——新寫入隨時可能再破壞它（那正是這 22 筆當初的來由）。
    func testResidualCheckGoesToZeroAfterMigrationAndCatchesNewBreakage() throws {
        try store.writePerson(personWithDigestAffiliation())
        XCTAssertEqual(ProvenanceMigration.residualDigestSources(load: try store.load()).count, 1)
        _ = try ProvenanceMigration.digestSourcesToReferences(store: store, dryRun: false)
        XCTAssertEqual(ProvenanceMigration.residualDigestSources(load: try store.load()), [],
                       "遷移之後殘留必須歸零")
        // 之後有人又寫了一筆舊形式 → 檢查要抓到
        try store.writePerson(personWithDigestAffiliation(key: "later-breakage"))
        XCTAssertEqual(ProvenanceMigration.residualDigestSources(load: try store.load()).count, 1,
                       "不變式要持續守，不是遷移完就結束")
    }

    /// **寫入失敗不得計入 `migrated`／`records`**（#146 verify G2/N4）。
    ///
    /// 席位 build mutated binary 實跑，同一份輸出**自相矛盾**：
    ///
    ///     ✓ 搬進 references: 22 筆，涉及 22 筆記錄
    ///     寫入失敗 1 筆（…）
    ///       實際成功寫入: 21 筆
    ///
    /// 而 1038 條全綠。這正是本 change 上一輪剛修好的病（報告誇報）在**新開的
    /// 失敗路徑**上原樣復發——修的是 `guard` 那條，新的 `catch` 沒有對應的釘子。
    func testWriteFailureIsNotCountedAsMigrated() throws {
        try store.writePerson(personWithDigestAffiliation(key: "will-fail"))
        try store.writePerson(personWithDigestAffiliation(key: "will-succeed"))
        // 讓其中一筆寫不進去：把該檔設成 immutable
        let load = try store.load()
        let target = try XCTUnwrap(load.people.first { $0.key == "will-fail" })
        let f = root.appendingPathComponent("entities/\(target.id.uuidString).yaml")
        _ = try? Process.run(URL(fileURLWithPath: "/usr/bin/chflags"),
                             arguments: ["uchg", f.path]).waitUntilExit()
        defer {
            _ = try? Process.run(URL(fileURLWithPath: "/usr/bin/chflags"),
                                 arguments: ["nouchg", f.path]).waitUntilExit()
        }
        let report = try ProvenanceMigration.digestSourcesToReferences(store: store, dryRun: false)
        guard !report.failures.isEmpty else {
            throw XCTSkip("chflags 沒生效（容器／檔案系統不支援）——這條要真的寫失敗才驗得到")
        }
        XCTAssertEqual(report.migrated, 1, "只有成功的那筆算數：\(report)")
        XCTAssertEqual(report.records, ["will-succeed"], "失敗的不得列進 records")
        XCTAssertEqual(report.failures.count, 1)
        XCTAssertFalse(report.failures[0].reason.contains("NSCocoaErrorDomain"),
                       "訊息要是 localizedDescription 不是 NSError dump（G3）：\(report.failures)")
    }

    /// **殘留檢查要掃到每一個維度。**
    ///
    /// 席位實測：residual 不掃 `ranks`／`administrative`／`appointments`／`fields`、
    /// 不掃整個 organization 迴圈、不掃 `contacts`——**三個 mutation 全部存活**，
    /// 因為既有測試只覆蓋 `profile.affiliations` 一個維度。doctor 會漏報而沒有訊號。
    func testResidualCheckCoversEveryDimension() throws {
        var p = Person(key: "all-dims", names: ["N"])
        p.profile.affiliations = TimelineOf([
            TemporalValue(value: OrgRef.key("x"), source: digest, note: "n")])
        p.profile.ranks = TimelineOf([TemporalValue(value: "研究員", source: digest, note: "n")])
        p.profile.administrative = TimelineOf([TemporalValue(value: "所長", source: digest, note: "n")])
        p.profile.appointments = TimelineOf([TemporalValue(value: "全職", source: digest, note: "n")])
        p.profile.fields = TimelineOf([TemporalValue(value: "統計", source: digest, note: "n")])
        p.profile.contacts = ["email": TimelineOf([
            TemporalValue(value: "a@b.invalid", source: digest, note: "n")])]
        try store.writePerson(p)
        var o = Organization(key: "org-dims", names: TimelineOf([
            TemporalValue(value: "O", source: digest, note: "n")]))
        o.parents = TimelineOf([TemporalValue(value: OrgRef.key("y"), source: digest, note: "n")])
        try store.writeOrganization(o)

        let fields = Set(ProvenanceMigration.residualDigestSources(load: try store.load())
                            .map(\.field))
        XCTAssertEqual(fields, ["profile.affiliations", "profile.ranks", "profile.administrative",
                                "profile.appointments", "profile.fields",
                                "profile.contacts.email", "names", "parents"],
                       "少掃任何一個維度，doctor 就會漏報而沒有訊號")
    }

    /// **冪等**：跑第二次不得重複建 reference。
    func testMigrationIsIdempotent() throws {
        try store.writePerson(personWithDigestAffiliation())
        _ = try ProvenanceMigration.digestSourcesToReferences(store: store, dryRun: false)
        let second = try ProvenanceMigration.digestSourcesToReferences(store: store, dryRun: false)
        XCTAssertEqual(second.migrated, 0, "第二次不該再搬")
        XCTAssertEqual(try store.load().people.first?.references.count, 1, "reference 被重複建了")
    }

    /// **格式不變**——`references:` 自 #66 起就在 format 7 的契約內。
    ///
    /// `§5.0` 的 bump 判準是「舊 binary 會不會誤讀」，不是「後果多嚴重」。遷移後的
    /// 檔案舊 binary 讀得懂，所以不 bump。
    func testMigrationDoesNotBumpStoreFormat() throws {
        let before = try StoreVersion.read(root: root)
        try store.writePerson(personWithDigestAffiliation())
        _ = try ProvenanceMigration.digestSourcesToReferences(store: store, dryRun: false)
        XCTAssertEqual(try StoreVersion.read(root: root), before, "內容遷移不得 bump 格式")
    }
}
