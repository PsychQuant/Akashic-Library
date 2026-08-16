import XCTest
import Foundation
@testable import AkashicCore
@testable import AkashicStoreIO
@testable import AkashicExport

/// 對外可稱呼的名字（#81）。
///
/// 缺陷重現：`docs/store-format.md` §3 曾規定「`names` 的第一個是顯示名」——語意由陣列
/// 索引承擔，型別是 `[String]`，validate 不查、doctor 不報。實測全 store 868 位 person，
/// `names.first` 有 734 筆（84.6%）是索引系統產生的引用形（`Guan, Yongtao`），0 筆是自然
/// 語序。而該位置決定了 `.bib` 匯出印出的作者名。
final class AuthorizedNameTests: XCTestCase {

    // MARK: - 書寫系統推導（task 1.1）
    //
    // script 是**推導值不儲存**。它只用來切分「同一個人的」名字，所以 han / latn 的粗
    // 分割就夠——沒有人同時擁有中文名與日文名，`Jpan` 與 `Hant` 的區別在這個用途上不
    // 存在。存 script 會憑空多出一個可能與值說謊的欄位。

    func testScriptOfHanNames() {
        XCTAssertEqual(WritingSystem.of("謝叔蓉"), .han)
        XCTAssertEqual(WritingSystem.of("森元俊成"), .han,
                       "日文脈絡的漢字與中文漢字落在同一桶——同一個人不會兩者都有")
    }

    func testScriptOfLatinNames() {
        XCTAssertEqual(WritingSystem.of("Shwu-Rong Grace Shieh"), .latn)
        XCTAssertEqual(WritingSystem.of("Guan, Yongtao"), .latn,
                       "引用形仍是拉丁書寫系統——是不是引用形是另一個問題")
    }

    func testScriptOfMixedStringIsHan() {
        XCTAssertEqual(WritingSystem.of("陳素雲 Su-Yun Huang"), .han,
                       "含表意文字即歸 han；混合字串在名冊裡真的存在")
    }

    func testScriptOfEmptyAndSymbolOnlyIsOther() {
        XCTAssertEqual(WritingSystem.of(""), .other)
        XCTAssertEqual(WritingSystem.of("   "), .other)
        XCTAssertEqual(WritingSystem.of("—"), .other)
    }

    // MARK: - 引用形分類（task 2.1）
    //
    // 「引用形」是索引系統（WoS 的 Author Full Names、Crossref 的作者欄）對名字做的機械
    // 變換。判準是逗號：沒有人以 `姓, 名` 的形式自稱。分類結果**不入 store**——它是純
    // 函數，存下來就多一個會過期的事實；只用於 migration 的提名與 doctor 的報告。

    func testCitationFormsAreRecognised() {
        XCTAssertTrue(NameForm.isCitationForm("Guan, Yongtao"), "姓名倒置")
        XCTAssertTrue(NameForm.isCitationForm("Key, Timothy J."), "部分縮寫")
        XCTAssertTrue(NameForm.isCitationForm("Chang, Y-H."), "純縮寫")
    }

    func testNamesAreNotCitationForms() {
        XCTAssertFalse(NameForm.isCitationForm("Shwu-Rong Grace Shieh"))
        XCTAssertFalse(NameForm.isCitationForm("謝叔蓉"))
        XCTAssertFalse(NameForm.isCitationForm("Fushing Hsieh"))
    }

    func testCitationFormNeedsBothSides() {
        // 逗號在頭尾＝沒有兩側，不構成倒置。這類字串是髒資料，不該被當成引用形而在
        // migration 裡被降級——它應該原樣進入「仍然歧義」那一類讓人看見。
        XCTAssertFalse(NameForm.isCitationForm(", Yongtao"))
        XCTAssertFalse(NameForm.isCitationForm("Guan,"))
        XCTAssertFalse(NameForm.isCitationForm(""))
    }

    // MARK: - Person 的 authorized 分割（task 3.1；#227 巢狀化後為 names.authorized）
    //
    // 形狀是**字串序列**（names 的一個分割），不是以書寫系統為鍵的 mapping：map 的鍵可以
    // 與值的實際書寫系統不一致（有人會寫 `{latn: 謝叔蓉}`），憑空多一類不一致要驗。
    // list 形式下 script 是算出來的，不可能與值衝突。

    func testPersonDefaultsToNoAuthorizedName() {
        let p = Person(key: "guan-yongtao", names: ["Guan, Yongtao"])
        XCTAssertTrue(p.names.authorized.isEmpty, "沒有指定就是沒有指定——不預設挑第一個")
    }

    func testPersonAuthorizedIsASequenceNotAMap() {
        let p = Person(key: "shwu-rong-grace-shieh",
                       names: PersonNames(authorized: ["謝叔蓉", "Shwu-Rong Grace Shieh"],
                                          variant: ["Shieh, Grace S."]))
        XCTAssertEqual(p.names.authorized, ["謝叔蓉", "Shwu-Rong Grace Shieh"],
                       "順序保留即可——不變式保證每個書寫系統至多一個，所以順序不帶語意")
    }

    func testPersonEqualityAccountsForAuthorized() {
        // #241：id 是隨機 v4——相等性比較必須釘同一個顯式 id，否則比的是 id 不是指定
        let id = UUID(uuidString: "11111111-1111-4111-8111-111111111111")!
        let designated = PersonNames(authorized: ["謝叔蓉"], variant: ["Shwu-Rong Grace Shieh"])
        let a = Person(key: "k", names: designated, id: id)
        let b = Person(key: "k", names: designated, id: id)
        let c = Person(key: "k", names: PersonNames(variant: ["謝叔蓉", "Shwu-Rong Grace Shieh"]),
                       id: id)
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c, "指定與不指定是不同的記錄——相等性必須看得見這件事")
    }

    // MARK: - Person 的 YAML 編解碼（task 3.2）

    func testPersonAuthorizedRoundTripsByteIdentically() throws {
        let p = Person(key: "shwu-rong-grace-shieh",
                       names: PersonNames(authorized: ["謝叔蓉", "Shwu-Rong Grace Shieh"],
                                          variant: ["Shieh, Grace S."]))
        let yaml = try PersonYAML.encode(p)
        XCTAssertTrue(yaml.contains("authorized:"), "指定必須落到檔案上，否則它不是 canonical")
        let back = try PersonYAML.decode(yaml)
        XCTAssertEqual(back, p)
        XCTAssertEqual(try PersonYAML.encode(back), yaml, "同一份資料只有一種位元組形式")
    }

    func testPersonAuthorizedAbsentDecodesToEmpty() throws {
        let yaml = """
        person:
        id: \(DeterministicUUID.v5(namespace: DeterministicUUID.personNamespace, name: "guan-yongtao").uuidString)
        key: guan-yongtao
        names:
          variant:
          - Guan, Yongtao
        """
        XCTAssertTrue(try PersonYAML.decode(yaml).names.authorized.isEmpty,
                      "authorized 分割缺席必須是良構的空集合——「還沒指定」是合法狀態")
    }

    func testPersonAuthorizedWrongShapeFailsClosed() {
        // known 欄位的形狀演化不入 tolerant 範圍（YAML.swift requireShape 的既有紀律）。
        // 靜默剝除會讓一次舊 binary 的 read-modify-write 把指定整段吃掉。
        let yaml = """
        person:
        id: \(DeterministicUUID.v5(namespace: DeterministicUUID.personNamespace, name: "k").uuidString)
        key: k
        names:
          authorized:
            han: 謝叔蓉
        """
        XCTAssertThrowsError(try PersonYAML.decode(yaml)) { error in
            XCTAssertTrue("\(error)".contains("authorized"),
                          "錯誤訊息要點名欄位，否則 quarantine 之後沒人知道是哪一欄")
        }
    }

    // MARK: - 巢狀序列化（nest-names-and-reissue-person-ids task 3.1）

    /// spec `authorized-name`「The serialized form carries each name once」的 Example：
    /// authorized 梁佑任／Yu-Jen Liang、variant Liang, Yu-Jen——各出現恰好一次，
    /// 且不跨分割重複。
    func testSerializedFormCarriesEachNameExactlyOnce() throws {
        let p = Person(key: "liang-yu-jen",
                       names: PersonNames(authorized: ["梁佑任", "Yu-Jen Liang"],
                                          variant: ["Liang, Yu-Jen"]))
        let yaml = try PersonYAML.encode(p)
        for name in ["梁佑任", "Yu-Jen Liang", "Liang, Yu-Jen"] {
            XCTAssertEqual(yaml.components(separatedBy: name).count - 1, 1,
                           "「\(name)」必須在序列化結果中恰好出現一次：\(yaml)")
        }
        XCTAssertTrue(yaml.contains("authorized:") && yaml.contains("variant:"),
                      "兩個分割各有自己的子鍵：\(yaml)")
        let back = try PersonYAML.decode(yaml)
        XCTAssertEqual(back, p)
        XCTAssertEqual(try PersonYAML.encode(back), yaml, "round-trip 位元組相同")
    }

    /// spec「The flat shape is not silently accepted」：平坦 names 陣列擲錯、訊息
    /// 點名欄位——**不得靜默視為空的 authorized**。舊形狀只能經遷移路徑進來。
    func testFlatNamesSequenceIsRefusedNamingTheField() {
        let yaml = """
        person:
        id: 11111111-1111-4111-8111-111111111111
        key: guan-yongtao
        names:
        - Guan, Yongtao
        """
        XCTAssertThrowsError(try PersonYAML.decode(yaml)) { error in
            let m = "\(error)"
            XCTAssertTrue(m.contains("person.names"), "訊息要點名欄位：\(m)")
            XCTAssertTrue(m.contains("migrate-person-identity"), "訊息要指路遷移：\(m)")
        }
    }

    /// 舊頂層 `authorized:` 同樣拒絕——把它當未知欄位保留，會讓舊指定與新分割
    /// 並存成兩個可矛盾的真相。
    func testOldTopLevelAuthorizedKeyIsRefused() {
        let yaml = """
        person:
        id: 11111111-1111-4111-8111-111111111111
        key: k
        names:
          variant:
          - 謝叔蓉
        authorized:
        - 謝叔蓉
        """
        XCTAssertThrowsError(try PersonYAML.decode(yaml)) { error in
            let m = "\(error)"
            XCTAssertTrue(m.contains("person.authorized"), "訊息要點名欄位：\(m)")
            XCTAssertTrue(m.contains("migrate-person-identity"), "訊息要指路遷移：\(m)")
        }
    }

    // MARK: - Organization 的 authorized 欄位（task 4.1 / 4.2）
    //
    // 機構的 names 是**時間軸**（改名之後舊記錄仍指向同一 identity）。改名與書寫系統是
    // 正交兩軸，兩者都要保留：authorized 從當前有效的名稱裡挑，被取代的名稱仍留著。

    private func renamedOrg() -> Organization {
        Organization(
            key: "institute-of-statistical-science",
            names: Timeline([
                TemporalValue(value: "中央研究院統計科學研究所籌備處",
                              range: DateRange(start: "1982", end: "1993")),
                TemporalValue(value: "中央研究院統計科學研究所", range: DateRange(start: "1993")),
                TemporalValue(value: "Institute of Statistical Science, Academia Sinica",
                              range: DateRange(start: "1993")),
            ]),
            authorized: ["中央研究院統計科學研究所",
                         "Institute of Statistical Science, Academia Sinica"])
    }

    func testOrganizationKeepsNameHistoryAlongsideAuthorized() {
        let o = renamedOrg()
        XCTAssertEqual(o.names.entries.count, 3, "被取代的名稱仍保有效期")
        XCTAssertEqual(o.authorized.count, 2, "當前有效的兩個書寫系統各指定一個")
        XCTAssertFalse(o.authorized.contains("中央研究院統計科學研究所籌備處"),
                       "指定的是當前名稱——時間軸與指定是正交兩軸")
    }

    func testOrganizationDefaultsToNoAuthorizedName() {
        let o = Organization(key: "academia-sinica")
        XCTAssertTrue(o.authorized.isEmpty)
    }

    func testOrganizationAuthorizedRoundTripsByteIdentically() throws {
        let o = renamedOrg()
        let yaml = try OrganizationYAML.encode(o)
        XCTAssertTrue(yaml.contains("authorized:"))
        let back = try OrganizationYAML.decode(yaml)
        XCTAssertEqual(back, o)
        XCTAssertEqual(try OrganizationYAML.encode(back), yaml)
    }

    func testOrganizationAuthorizedWrongShapeFailsClosed() {
        let yaml = """
        organization:
        id: \(DeterministicUUID.forOrganization(key: "k").uuidString)
        key: k
        authorized:
          han: 統計所
        """
        XCTAssertThrowsError(try OrganizationYAML.decode(yaml)) { error in
            XCTAssertTrue("\(error)".contains("authorized"))
        }
    }

    // MARK: - 不變式（task 5.1 / 5.2 / 5.3）

    private func errors(_ issues: [ValidationIssue]) -> [String] {
        issues.filter { $0.severity == .error }.map(\.message)
    }

    // #227（task 5.1(c)）：person 的「authorized ⊆ names」測試已**移除**而非改寫——
    // 巢狀化後該違反狀態**不可表達**（指定一個名字就是把它放進 authorized 分割），
    // 改成恆真的測試只會假裝還在防什麼。organization 未巢狀化，其子集測試保留（下方）。

    func testAtMostOneAuthorizedPerWritingSystem() {
        // 同一個書寫系統兩個 authorized ＝ 未決的問題，不是指定。
        let p = Person(key: "k",
                       names: PersonNames(authorized: ["Shwu-Rong Grace Shieh",
                                                      "Shieh, Grace S."]))
        let msgs = errors(p.validate())
        XCTAssertEqual(msgs.count, 1)
        XCTAssertTrue(msgs[0].contains("latn"), "訊息要點名書寫系統：\(msgs)")
        XCTAssertTrue(msgs[0].contains("Shwu-Rong Grace Shieh") && msgs[0].contains("Shieh, Grace S."),
                      "以及兩個候選：\(msgs)")
    }

    func testDifferentWritingSystemsAreAccepted() {
        let p = Person(key: "k",
                       names: PersonNames(authorized: ["謝叔蓉", "Shwu-Rong Grace Shieh"]))
        XCTAssertTrue(errors(p.validate()).isEmpty)
    }

    func testOrganizationEnforcesTheSameInvariants() {
        let o = Organization(key: "iss",
                             names: Timeline([TemporalValue(value: "統計所")]),
                             authorized: ["不存在的名稱"])
        let msgs = errors(o.validate())
        XCTAssertEqual(msgs.count, 1, "organization 與 person 的不變式必須一致：\(msgs)")
        XCTAssertTrue(msgs[0].contains("不存在的名稱") && msgs[0].contains("iss"))
    }

    func testEmptyAuthorizedViolatesNothing() {
        XCTAssertTrue(errors(Person(key: "k", names: ["Guan, Yongtao"]).validate()).isEmpty)
        XCTAssertTrue(errors(Organization(key: "k").validate()).isEmpty)
    }

    /// 不變式必須在 **`validate` 子命令的實際執行路徑**上生效，不只在型別層。
    ///
    /// 機械守衛而非記憶（同 `DisplaySinkCoverageTests` 的做法，#28）：機構記錄在 #81
    /// 之前從未被驗證過——`Organization.validate()` 不存在、`Validate` 也沒有走訪
    /// `load.organizations`。少了那個迴圈，這裡加的兩條不變式對機構就是死的。
    func testValidateCommandIteratesOrganizations() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // AkashicKitTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // repo root
        let src = try String(contentsOf: repoRoot
            .appendingPathComponent("Sources/akashic/Commands.swift"), encoding: .utf8)
        guard let validateBody = src.range(of: "struct Validate: ParsableCommand")
            .map({ String(src[$0.lowerBound...].prefix(3000)) }) else {
            return XCTFail("找不到 Validate 子命令")
        }
        XCTAssertTrue(validateBody.contains("load.organizations"),
                      "Validate 必須走訪 organizations，否則機構的 authorized 不變式在使用層不生效")
        XCTAssertTrue(validateBody.contains("organization.validate()"),
                      "而且要真的呼叫 validate()，不是只列舉")
    }

    // MARK: - 對外名字解析（task 6.1 / 6.2）

    func testPersonResolvesRequestedWritingSystem() {
        let p = Person(key: "shwu-rong-grace-shieh",
                       names: PersonNames(authorized: ["謝叔蓉", "Shwu-Rong Grace Shieh"],
                                          variant: ["Shieh, Grace S."]))
        XCTAssertEqual(p.displayName(in: .han), "謝叔蓉")
        XCTAssertEqual(p.displayName(in: .latn), "Shwu-Rong Grace Shieh")
    }

    func testPersonFallsBackToAnyAuthorizedWhenScriptUnavailable() {
        let p = Person(key: "k", names: PersonNames(authorized: ["Shwu-Rong Grace Shieh"]))
        XCTAssertEqual(p.displayName(in: .han), "Shwu-Rong Grace Shieh",
                       "沒有漢字名就退到任一 authorized——那仍然是他的名字")
    }

    func testPersonWithNoAuthorizedResolvesToKeyNotToACitationForm() {
        // 這是本 change 的核心行為：84.6% 的記錄目前只有引用形，退回 key 讓缺口**看得見**。
        // fallback 到 names 的任一元素就是位置式約定本身，那正是要廢除的東西。
        let p = Person(key: "guan-yongtao", names: ["Guan, Yongtao"])
        XCTAssertEqual(p.displayName(in: .latn), "guan-yongtao")
        XCTAssertNotEqual(p.displayName(in: .latn), "Guan, Yongtao")
        XCTAssertEqual(p.displayName(), "guan-yongtao", "不指定書寫系統時同樣不回引用形")
    }

    func testOrganizationResolutionHasCurrentNameBeforeKey() {
        let o = renamedOrg()
        XCTAssertEqual(o.displayName(in: .han), "中央研究院統計科學研究所")
        XCTAssertEqual(o.displayName(in: .latn),
                       "Institute of Statistical Science, Academia Sinica")

        // 沒有指定時退到**當前有效名稱**——那是對名稱歷史的查詢，不是讀取名字順序，
        // 所以它不是本 change 要廢除的東西。
        let undesignated = Organization(
            key: "iss",
            names: Timeline([
                TemporalValue(value: "舊名", range: DateRange(start: "1982", end: "1993")),
                TemporalValue(value: "現名", range: DateRange(start: "1993")),
            ]))
        XCTAssertEqual(undesignated.displayName(in: .han), "現名")
        XCTAssertEqual(Organization(key: "empty-org").displayName(in: .han), "empty-org")
    }

    // MARK: - Format marker（task 7.1）
    //
    // `names[0]` 的語意變更是 non-additive（§5.0 的 bump 準則）：舊 binary 讀新 store 會
    // 繼續把第一個名字當顯示名——**按舊語意解讀新格式**，正是 refuse-if-newer 存在的情境。

    func testSupportedFormatIsRaised() {
        XCTAssertGreaterThanOrEqual(StoreVersion.supported, 5,
                       "廢除位置式顯示名是欄位語意變更；§5.0 準則下 MUST bump（下限——後續 format 各有各的 bump 測試）")
    }

    func testNewerStoreIsRefusedAsAWhole() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("akashic-fmt-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("entities"), withIntermediateDirectories: true)
        try "format: \(StoreVersion.supported + 1)\n".write(
            to: StoreVersion.url(in: root), atomically: true, encoding: .utf8)
        XCTAssertThrowsError(try LibraryStore(root: root).load()) { error in
            let m = "\(error)"
            XCTAssertTrue(m.contains("\(StoreVersion.supported + 1)") && m.contains("\(StoreVersion.supported)"),
                          "訊息要同時點名 store 的 marker 與本 binary 的上限：\(m)")
        }
        try? FileManager.default.removeItem(at: root)
    }

    func testPreviousFormatStillLoads() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("akashic-fmt4-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("entities"), withIntermediateDirectories: true)
        try "format: 4\n".write(to: StoreVersion.url(in: root), atomically: true, encoding: .utf8)
        XCTAssertNoThrow(try LibraryStore(root: root).load(),
                         "bump 不是把既有 store 鎖在外面——format 4 仍在支援範圍內")
        try? FileManager.default.removeItem(at: root)
    }

    // MARK: - 一致性報告（task 8.1）
    //
    // 「沒有 authorized」是**報告項**不是**錯誤**：實測 734 位目前無法被稱呼，設成錯誤
    // 會讓 store 當場無法通過驗證，而修復所需的資訊（正確的對外名字）無法自動取得。
    // validate 只守形狀不變式，「有沒有」交給 doctor。

    func testDoctorListsRecordsWithoutAuthorizedName() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("akashic-doc-\(UUID().uuidString)")
        let store = LibraryStore(root: root)
        try store.ensureLayout()
        try store.writePerson(Person(key: "designated", names: PersonNames(authorized: ["謝叔蓉"])))
        try store.writePerson(Person(key: "undesignated", names: ["Guan, Yongtao"]))
        try store.writeOrganization(Organization(
            key: "org-undesignated", names: Timeline([TemporalValue(value: "統計所")])))
        let load = try store.load()

        let gaps = load.recordsWithoutAuthorizedName()
        XCTAssertEqual(gaps.people, ["undesignated"], "有指定的不該入列")
        XCTAssertEqual(gaps.organizations, ["org-undesignated"])

        // 同一個 store 的 validate 必須通過——缺口是報告，不是拒絕。
        let errs = (load.people.flatMap { $0.validate() }
                    + load.organizations.flatMap { $0.validate() })
            .filter { $0.severity == .error }
        XCTAssertTrue(errs.isEmpty, "\(errs.map(\.message))")
        try? FileManager.default.removeItem(at: root)
    }

    /// doctor 必須真的把缺口印出來——不印等於沒有報告。
    func testDoctorCommandReportsTheGap() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let src = try String(contentsOf: repoRoot
            .appendingPathComponent("Sources/akashic/Commands.swift"), encoding: .utf8)
        XCTAssertTrue(src.contains("recordsWithoutAuthorizedName"),
                      "doctor 要呼叫缺口報告，否則 734 筆無法被稱呼的記錄沒有任何清單")
    }

    // MARK: - 渲染路徑（task 9.1 / 9.2）

    private func undesignatedEntryAndPerson() -> (Entry, Person) {
        let e = Entry(id: UUID(uuidString: "7C1F6C2E-0000-0000-0000-0000000000A1")!,
                      citekey: "guan2020x", type: "article", title: "A paper",
                      authors: [.key("guan-yongtao")], date: "2020")
        return (e, Person(key: "guan-yongtao", names: ["Guan, Yongtao"]))
    }

    func testBibExportPrintsKeyNotCitationFormWhenUndesignated() {
        let (e, p) = undesignatedEntryAndPerson()
        let bib = BibExport.bibFile(entries: [e], people: [p])
        XCTAssertTrue(bib.contains("guan-yongtao"), "沒有指定就印 key，讓缺口看得見")
        XCTAssertFalse(bib.contains("Guan, Yongtao"),
                       "引用形是索引系統的產物，不該出現在對外書目上：\(bib)")
    }

    func testBibExportPrintsAuthorizedNameWhenDesignated() {
        let e = Entry(id: UUID(uuidString: "7C1F6C2E-0000-0000-0000-0000000000A2")!,
                      citekey: "shieh2020x", type: "article", title: "A paper",
                      authors: [.key("shieh")], date: "2020")
        let p = Person(key: "shieh",
                       names: PersonNames(authorized: ["謝叔蓉", "Shwu-Rong Grace Shieh"],
                                          variant: ["Shieh, Grace S."]))
        let bib = BibExport.bibFile(entries: [e], people: [p])
        // biblatex 的資料模型**要求** `Family, Given`，所以 `.bib` 裡出現逗號是格式正確，
        // 不是引用形洩漏。差別在**來源**：這裡的 "Shieh, Shwu-Rong Grace" 是由 authorized
        // 的「Shwu-Rong Grace Shieh」轉出來的，而不是照抄 WoS 給的「Shieh, Grace S.」。
        XCTAssertTrue(bib.contains("Shieh, Shwu-Rong Grace"),
                      "authorized 名字經 biblatex 格式化後的樣子：\(bib)")
        XCTAssertFalse(bib.contains("Shieh, Grace S."),
                       "索引系統給的那個字串不該成為來源：\(bib)")
    }

    func testCSLExportUsesResolution() throws {
        let (e, p) = undesignatedEntryAndPerson()
        let json = try CSLExport.cslJSON(entries: [e], people: [p])
        XCTAssertTrue(json.contains("guan-yongtao"))
        XCTAssertFalse(json.contains("Guan, Yongtao"))
    }

    func testRelationalExportUsesResolution() {
        let (_, p) = undesignatedEntryAndPerson()
        let t = RelationalExport.tables(entries: [], people: [p])
        let row = try? XCTUnwrap(t.researcher.rows.first)
        XCTAssertNotNil(row)
        XCTAssertFalse(row!.contains("Guan, Yongtao"), "CSV 也是對外輸出：\(row!)")
        XCTAssertTrue(row!.contains("guan-yongtao"))
    }

    /// 樹內不得再有任何渲染路徑以位置選取名字。
    func testNoRenderingPathReadsNamesFirst() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let paths = ["Sources/AkashicExport/BibExport.swift",
                     "Sources/AkashicExport/CSLExport.swift",
                     "Sources/AkashicExport/RelationalExport.swift",
                     "Sources/AkashicMCPKit/AkashicService.swift"]
        for rel in paths {
            let src = try String(contentsOf: repoRoot.appendingPathComponent(rel), encoding: .utf8)
            XCTAssertFalse(src.contains("names.first"),
                           "\(rel) 仍以陣列位置選名字——那正是本 change 廢除的東西")
        }
    }

    // MARK: - Migration（task 10.1）
    //
    // `authorized` 是**指定**不是推導，但提名可以機械化——判斷只在候選多於一個時發生。
    // 與既有補資料紀律一致：答案唯一就做，多選一就停下給人看。

    func testMigrationAdoptsTheOnlyCandidate() {
        // 沒有可挑的餘地，不構成判斷。實測 868 筆裡 734 筆是這一類。
        let p = Person(key: "guan-yongtao", names: ["Guan, Yongtao"])
        let plan = AuthorizedNameMigration.propose(names: p.names.all)
        XCTAssertEqual(plan.adopted, ["Guan, Yongtao"])
        XCTAssertTrue(plan.nominated.isEmpty)
        XCTAssertTrue(plan.undecided.isEmpty)
    }

    func testMigrationNominatesTheNonCitationForm() {
        let plan = AuthorizedNameMigration.propose(
            names: ["劉維中", "Wei-chung Liu", "Liu, Wei-chung"])
        XCTAssertEqual(plan.adopted, ["劉維中"], "漢字只有一個候選 → 直接採用")
        XCTAssertEqual(plan.nominated, ["Wei-chung Liu"], "拉丁兩個候選，恰一個非引用形 → 提名")
        XCTAssertTrue(plan.undecided.isEmpty)
    }

    func testMigrationLeavesGenuineAmbiguityUndecided() {
        // 兩個都不是引用形——那是真的要人判斷，不能猜。
        let plan = AuthorizedNameMigration.propose(names: ["Wei-chung Liu", "W. C. Liu"])
        XCTAssertTrue(plan.adopted.isEmpty)
        XCTAssertTrue(plan.nominated.isEmpty)
        XCTAssertEqual(plan.undecided, [.latn])
    }

    func testMigrationProposalSatisfiesTheInvariants() {
        let plan = AuthorizedNameMigration.propose(
            names: ["劉維中", "Wei-chung Liu", "Liu, Wei-chung"])
        let issues = AuthorizedNames.validate(
            authorized: plan.authorized,
            names: ["劉維中", "Wei-chung Liu", "Liu, Wei-chung"], ownerKey: "k")
        XCTAssertTrue(issues.isEmpty, "提名的結果必須自己就滿足不變式：\(issues.map(\.message))")
    }

    func testMigrationDryRunLeavesTheStoreUnchanged() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("akashic-mig-\(UUID().uuidString)")
        let store = LibraryStore(root: root)
        try store.ensureLayout()
        let url = try store.writePerson(Person(key: "guan-yongtao", names: ["Guan, Yongtao"]))
        let before = try String(contentsOf: url, encoding: .utf8)

        let report = try AuthorizedNameMigration.run(store: store, apply: false)
        XCTAssertEqual(report.adopted, 1)
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), before,
                       "沒給寫入指示就不能動 store")

        _ = try AuthorizedNameMigration.run(store: store, apply: true)
        XCTAssertEqual(try store.load().people.first?.names.authorized, ["Guan, Yongtao"])

        // 寫入後 store 帶著新語意 → marker 必須跟上，否則舊 binary 會載入它並繼續把
        // `names[0]` 當顯示名（按舊語意解讀新格式）。
        XCTAssertEqual(try StoreVersion.read(root: root), StoreVersion.supported)
        try? FileManager.default.removeItem(at: root)
    }

    /// #227 verify S1：store 有 quarantined 檔（未遷移的舊形狀）時，authorize-names
    /// **看不見**那些人——迭代 0 人、回報成功、把 marker bump 到 supported，鎖死唯一
    /// 還讀得懂資料的舊 binary。必須 fail-fast 指路遷移，marker 不得被動。
    func testAuthorizeNamesRefusesQuarantinedStoreAndDoesNotBumpMarker() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("akashic-anq-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("entities"), withIntermediateDirectories: true)
        try StoreVersion.write(root: root, format: 9)
        // 舊形狀 person 檔（平坦 names）→ 現行 decoder quarantine
        try """
        person:
        id: 11111111-1111-4111-8111-111111111111
        key: old-shape
        names:
        - Old Shape
        """.write(to: root.appendingPathComponent("entities/11111111-1111-4111-8111-111111111111.yaml"),
                  atomically: true, encoding: .utf8)
        let store = LibraryStore(root: root)

        XCTAssertThrowsError(try AuthorizedNameMigration.run(store: store, apply: true)) { e in
            let m = (e as? LocalizedError)?.errorDescription ?? "\(e)"
            XCTAssertTrue(m.contains("migrate-person-identity"), "訊息要指路遷移：\(m)")
            XCTAssertTrue(m.contains("doctor"), "先指路 doctor（quarantine 未必是 person）：\(m)")
            XCTAssertTrue(m.contains("marker"), "apply 模式要說 marker 後果：\(m)")
        }
        XCTAssertEqual(try StoreVersion.read(root: root), 9,
                       "marker 不得被 bump——那會鎖死唯一還讀得懂資料的舊 binary")
        // R2 C7：dry-run 同樣拒，但訊息說的是**它的**真實後果（報告不完整），
        // 不得聲稱「跑完會升 marker」——dry-run 不升。
        XCTAssertThrowsError(try AuthorizedNameMigration.run(store: store, apply: false)) { e in
            let m = (e as? LocalizedError)?.errorDescription ?? "\(e)"
            XCTAssertTrue(m.contains("不完整"), "dry-run 的後果是報告不完整：\(m)")
            XCTAssertFalse(m.contains("升到"), "dry-run 不得聲稱會升 marker：\(m)")
        }
    }

    /// migration 把唯一候選直接採用之後，「沒有指定」的計數會掉到接近 0——但那些人
    /// **仍然沒有真正的名字**。缺口報告必須換一個問法才看得見。
    func testDoctorSurfacesCitationFormOnlyDesignations() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("akashic-cf-\(UUID().uuidString)")
        let store = LibraryStore(root: root)
        try store.ensureLayout()
        try store.writePerson(Person(key: "guan-yongtao",
                                     names: PersonNames(authorized: ["Guan, Yongtao"])))
        try store.writePerson(Person(key: "real-name",
                                     names: PersonNames(authorized: ["Fushing Hsieh"])))
        let load = try store.load()
        XCTAssertTrue(load.recordsWithoutAuthorizedName().people.isEmpty,
                      "兩筆都有指定——舊問法看不到問題")
        XCTAssertEqual(load.recordsAuthorizedOnlyByCitationForm(), ["guan-yongtao"],
                       "新問法看得到：指定的就是索引系統的變換，缺的是名字本身")
        try? FileManager.default.removeItem(at: root)
    }

    // MARK: - v10 format gate（nest-names-and-reissue-person-ids task 5.1）

    /// spec「Writing the partitioned shape to an older store is refused」：巢狀 names
    /// 對 v9 binary 是形狀不符 → 整檔 quarantine（人檔消失）——refuse-if-newer 必須
    /// 在寫入端先 fire。訊息沿用 ended/attested/verdict gate 的形狀：說明前置條件、
    /// 指路手動升 marker（升 marker 是使用者知情的動作，不是寫入的副作用）。
    func testWritingPartitionedNamesToOlderStoreIsRefused() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("akashic-v10gate-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("entities"), withIntermediateDirectories: true)
        try "format: 9\n".write(to: StoreVersion.url(in: root), atomically: true, encoding: .utf8)
        let store = LibraryStore(root: root)

        let p = Person(key: "x-person", names: PersonNames(authorized: ["X Person"]))
        XCTAssertThrowsError(try store.writePerson(p)) { e in
            let m = "\(e)"
            XCTAssertTrue(m.contains("10") && m.contains("9"),
                          "訊息要同時點名需要的 format 與現值：\(m)")
            XCTAssertTrue(m.contains("升級"), "訊息要說明升級前置：\(m)")
        }

        // 空 names 的記錄不受此閘——檔上沒有 names 鍵，兩代 binary 都讀得懂。
        XCTAssertNoThrow(try store.writePerson(Person(key: "empty-names")))
    }

    // MARK: - 不變式住在寫入邊界（#229）

    // #227（task 5.1(c)）：person 的 write-gate 子集測試（testWritePersonRejects-
    // AuthorizedNotSubsetOfNames）已**移除**——「authorized 含 names 沒有的字串」在
    // 巢狀結構下不可表達，寫入邊界無此輸入可拒。organization 側的同型測試保留（下方
    // testWriteOrganizationRejectsAuthorizedNotSubsetOfNames）。

    /// 內容約束（結構管不到的那條）：同書寫系統兩個 authorized 是**未決的問題**，
    /// 不是指定。#229 的紀律不變——不變式住在所有寫入路徑的交會處（writePerson），
    /// 不是靠每個呼叫端記得驗。
    func testWritePersonRejectsTwoAuthorizedInSameScript() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("akashic-229b-\(UUID().uuidString)")
        let store = LibraryStore(root: root)
        try store.ensureLayout()
        defer { try? FileManager.default.removeItem(at: root) }

        let bad = Person(key: "script-violator",
                         names: PersonNames(authorized: ["Che Cheng", "C. Cheng"],   // 兩個都是 latn
                                            variant: ["鄭澈"]))
        XCTAssertThrowsError(try store.writePerson(bad))
        XCTAssertNil(try? store.load().people.first { $0.key == "script-violator" })
    }

    /// **對偶（承重）：`.warning` 不得擋寫入。**
    ///
    /// 拒絕的判準是**嚴重度**，不是「validate 回了東西」。tolerant-preserve（#23）
    /// 是明文功能：較新 schema 寫入的未知欄位必須被保留而非拒收。若這裡改成
    /// 「issues 非空就拒絕」，未知欄位的記錄會突然寫不進去——那會把一個相容性
    /// 功能靜默換成硬錯誤。
    func testWritePersonStillAcceptsWarningLevelIssues() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("akashic-229c-\(UUID().uuidString)")
        let store = LibraryStore(root: root)
        try store.ensureLayout()
        defer { try? FileManager.default.removeItem(at: root) }

        var p = Person(key: "tolerant-ok", names: PersonNames(authorized: ["Che Cheng"]))
        p.unknownFields = [UnknownField(key: "fromNewerVersion", raw: "fromNewerVersion: 42\n")]
        XCTAssertFalse(p.validate().isEmpty, "前提：這筆記錄確實有 issue（warning 等級）")
        XCTAssertTrue(p.validate().allSatisfy { $0.severity == .warning },
                      "前提：只有 warning，沒有 error")
        XCTAssertNoThrow(try store.writePerson(p), "warning 不得擋寫入——那是 tolerant-preserve")
        XCTAssertNotNil(try store.load().people.first { $0.key == "tolerant-ok" })
    }

    // MARK: - PersonNames 的分割契約（nest-names-and-reissue-person-ids task 1.1）
    //
    // `names` 巢狀化（#227）：authorized / variant 是兩個**分割**，聯集 `all` 是
    // computed——存三個欄位就是三個可互相矛盾的真相（`OrgRef` doc 的既有原則）。

    /// `all` 的順序是隱性契約：authorized 在前，`displayName` 的 fallback
    /// （取 `all.first`）才會優先拿到指定的名字，不需要另一條規則。
    func testPersonNamesAllIsAuthorizedThenVariant() {
        let n = PersonNames(authorized: ["謝叔蓉", "Shwu-Rong Grace Shieh"],
                            variant: ["Shieh, Grace S."])
        XCTAssertEqual(n.all, ["謝叔蓉", "Shwu-Rong Grace Shieh", "Shieh, Grace S."],
                       "all 是 authorized 在前、variant 在後的串接")
    }

    /// 字面量的意義是「全部是 variant，沒有指定」——這是型別轉換，不是讀舊資料的
    /// compat fallback（design D3；no-compat-fallback 的三類封閉列舉不含它）。
    func testPersonNamesArrayLiteralIsAllVariant() {
        let n: PersonNames = ["Guan, Yongtao", "Yongtao Guan"]
        XCTAssertEqual(n.authorized, [], "字面量不得偽造任何指定")
        XCTAssertEqual(n.variant, ["Guan, Yongtao", "Yongtao Guan"])
    }

    /// 同一批字串、不同分割 = 不同值。指定本身是資料，Equatable 必須看得見；
    /// 只比 `all` 會讓「已指定」與「未指定」在比較上熔成同一個東西。
    func testPersonNamesEquatableIsSensitiveToBothPartitions() {
        let a = PersonNames(authorized: ["謝叔蓉"], variant: ["Shieh, Grace S."])
        let b = PersonNames(authorized: [], variant: ["謝叔蓉", "Shieh, Grace S."])
        XCTAssertNotEqual(a, b, "分割不同即不等，即使字串聯集相同")
        XCTAssertEqual(a, PersonNames(authorized: ["謝叔蓉"], variant: ["Shieh, Grace S."]))
    }

    /// spec「A name SHALL occupy exactly one partition」／Example「no name SHALL
    /// appear in both subsections」（#227 verify R1）：同一字串同時落在兩個分割是
    /// 「同時對外又不對外」的矛盾態——validate 必須報 error（經 writePerson 的
    /// assertNoErrors 落在所有寫入路徑），decoder 對檔上矛盾同樣 fail-closed。
    func testSameNameInBothPartitionsIsRejectedEverywhere() throws {
        let p = Person(key: "dup-person",
                       names: PersonNames(authorized: ["謝叔蓉"], variant: ["謝叔蓉"]))
        let errs = p.validate().filter { $0.severity == .error }
        XCTAssertEqual(errs.count, 1, "\(errs.map(\.message))")
        XCTAssertTrue(errs[0].message.contains("謝叔蓉") && errs[0].message.contains("分割"),
                      "訊息要點名字串與分割語意：\(errs[0].message)")

        // 寫入邊界（所有路徑的交會處）
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("akashic-dup-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = LibraryStore(root: root)
        try store.ensureLayout()
        XCTAssertThrowsError(try store.writePerson(p))
        XCTAssertNil(try? store.load().people.first { $0.key == "dup-person" },
                     "拒絕就是不得落盤")

        // 讀取面：檔上矛盾 fail-closed（不得讀進來等下一次 RMW 寫回）
        let yaml = """
        person:
        id: 11111111-1111-4111-8111-111111111111
        key: dup-person
        names:
          authorized:
          - 謝叔蓉
          variant:
          - 謝叔蓉
        """
        XCTAssertThrowsError(try PersonYAML.decode(yaml)) { e in
            XCTAssertTrue("\(e)".contains("person.names"), "\(e)")
        }
    }

    /// 空分割合法：authorized 空 = 「還沒指定該怎麼稱呼他」（#81 的既有語意）。
    func testPersonNamesEmptyPartitionsAreLegal() {
        let n = PersonNames(authorized: [], variant: ["Guan, Yongtao"])
        XCTAssertEqual(n.all, ["Guan, Yongtao"])
        XCTAssertEqual(PersonNames(authorized: [], variant: []).all, [])
    }

    /// org 側同一條不變式、同一個閘。少了它，「哪個名字對外」會有兩套答案。
    func testWriteOrganizationRejectsAuthorizedNotSubsetOfNames() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("akashic-229d-\(UUID().uuidString)")
        let store = LibraryStore(root: root)
        try store.ensureLayout()
        defer { try? FileManager.default.removeItem(at: root) }

        var o = Organization(key: "org-violator")
        o.names = TimelineOf([TemporalValue(value: "Academia Sinica", range: DateRange())])
        o.authorized = ["Academia Sinca"]   // 拼錯，不在 names 內
        XCTAssertThrowsError(try store.writeOrganization(o))
    }
}
