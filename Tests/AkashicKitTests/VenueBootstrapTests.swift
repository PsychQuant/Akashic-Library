import XCTest
@testable import AkashicCore
@testable import AkashicEntity

/// 從 literal 刊名批次建 venue（#367）。
final class VenueBootstrapTests: XCTestCase {

    private func entry(_ citekey: String, type: WorkType = .periodicalArticle,
                       fields: [String: String]) -> Entry {
        var e = Entry(id: UUID(), citekey: citekey, type: type, title: "T",
                      authors: [.literal("A, A.")], date: "2020")
        e.fields = fields
        // `venues:` 由 VenueDerivation 推導；這裡不預先塞，讓 bootstrap 自己走同一條路。
        return e
    }

    // MARK: - type 由來源欄位判定

    /// `journaltitle` → **`.periodical`**，不是 `.journal`。
    ///
    /// #324 把 journal 併進 periodical（APA7 的 periodical 涵蓋 journal／magazine／
    /// newspaper／newsletter／blog，索取同一組欄位）。biblatex 的欄位名與我們的值域
    /// **不是同一套詞彙**，照字面對映會錯。
    func testJournaltitleYieldsPeriodicalNotJournal() {
        let r = VenueBootstrap.result(
            entries: [entry("a2020", fields: ["journaltitle": "Psychometrika"])],
            existing: [])
        XCTAssertEqual(r.candidates.map(\.type), [.periodical])
        XCTAssertEqual(r.candidates.first?.evidence, "journaltitle")
    }

    func testPublisherYieldsPublisher() {
        let r = VenueBootstrap.result(
            entries: [entry("b2020", type: .book, fields: ["publisher": "Wiley"])],
            existing: [])
        XCTAssertEqual(r.candidates.map(\.type), [.publisher])
    }

    /// `booktitle` 只在會議發表時才是載體（`VenueDerivation` 的 `booktitleCarrierTypes`）。
    func testBooktitleYieldsConferenceOnlyForConferenceSessions() {
        let conf = VenueBootstrap.result(
            entries: [entry("c2020", type: .conferenceSession,
                            fields: ["booktitle": "Proceedings of X"])],
            existing: [])
        XCTAssertEqual(conf.candidates.map(\.type), [.conference])

        // 編著章節的 booktitle 是**書名**，不是載體——不該產生候選。
        let chapter = VenueBootstrap.result(
            entries: [entry("d2020", type: .bookChapter,
                            fields: ["booktitle": "An Edited Book"])],
            existing: [])
        XCTAssertTrue(chapter.candidates.isEmpty,
                      "編著章節的 booktitle 不是載體：\(chapter.candidates)")
    }

    /// **來源欄位表必須是 `VenueDerivation` 的鏡像。**
    ///
    /// 兩者漂移時這條會紅：`VenueDerivation` 決定哪些欄位產生 literal，而本型別要能
    /// 把每個 literal 對回產生它的欄位。少一個欄位就會有 literal 找不到來源、
    /// 靜默不建檔。
    func testSourceFieldsMirrorVenueDerivation() {
        let all = entry("e2020", type: .conferenceSession, fields: [
            "journaltitle": "A Journal",
            "booktitle": "A Proceedings",
            "publisher": "A Publisher",
        ])
        let derived = VenueDerivation.literals(for: all).compactMap { ref -> String? in
            if case let .literal(s) = ref { return s }
            return nil
        }
        let withSource = VenueBootstrap.literalsWithSource(all).map(\.name)
        XCTAssertEqual(Set(withSource), Set(derived),
                       "每個 VenueDerivation 產生的 literal 都必須能對回來源欄位。"
                       + "差集：\(Set(derived).symmetricDifference(Set(withSource)))")
    }

    // MARK: - 分組：保留原字串，正規化只住配對鍵

    /// 大小寫變體收成同一筆，**所有寫法都留著**。
    ///
    /// WoS 匯出常見全大寫形（`PSYCHOMETRIKA`）。若只留一個寫法，下次遇到另一個寫法
    /// 又會重新分割一次——`OrgBootstrap` 已記過這個教訓。
    func testCaseVariantsGroupTogetherAndAllNamesSurvive() {
        let r = VenueBootstrap.result(entries: [
            entry("a", fields: ["journaltitle": "Psychometrika"]),
            entry("b", fields: ["journaltitle": "PSYCHOMETRIKA"]),
            entry("c", fields: ["journaltitle": "psychometrika"]),
        ], existing: [])
        XCTAssertEqual(r.candidates.count, 1, "三個寫法應收成一筆")
        XCTAssertEqual(r.candidates.first?.occurrences, 3)
        XCTAssertEqual(Set(r.candidates.first?.names ?? []),
                       ["Psychometrika", "PSYCHOMETRIKA", "psychometrika"],
                       "所有寫法都要留著")
    }

    /// 已建檔的 venue 不重造（比對走 `names` 的所有寫法）。
    func testExistingVenuesAreNotRecreated() {
        let existing = Venue(key: "psychometrika", type: .periodical,
                             names: Timeline([TemporalValue(value: "Psychometrika")]))
        let r = VenueBootstrap.result(
            entries: [entry("a", fields: ["journaltitle": "PSYCHOMETRIKA"])],
            existing: [existing])
        XCTAssertTrue(r.candidates.isEmpty,
                      "既有 venue 的其他寫法不該產生新候選：\(r.candidates)")
    }

    // MARK: - 不靜默丟

    /// 產不出 ASCII key 的**必須進 `dropped`**，不是消失。
    ///
    /// 實測真實 store 有 5 筆（`天下雜誌出版`／`太平書局`／`管理學報`…）。model 端有
    /// 欄位而沒有任何輸出讀它，與丟棄在效果上完全相同（#238 的教訓）。
    func testPureCJKNamesLandInDroppedNotSilence() {
        let r = VenueBootstrap.result(
            entries: [entry("a", fields: ["journaltitle": "管理學報"])],
            existing: [])
        XCTAssertTrue(r.candidates.isEmpty)
        XCTAssertEqual(r.dropped.map(\.name), ["管理學報"])
    }

    // MARK: - 型別衝突（零實例守衛）

    /// 同名來自不同種類的來源欄位 → **不建檔，進 `conflicts`**。
    ///
    /// 目前零實例（實測 441 個 literal 全部只對應一個欄位種類），但取任一個 type 都
    /// 可能讓整組欄位需求錯（#324：`VenueType` 決定哪些欄位存在），而那個錯**不會有
    /// 任何跡象**。裁決見 `.claude/rules/zero-instance-guards.md` 第 4 列。
    func testSameNameFromDifferentFieldKindsIsAConflictNotAGuess() {
        let r = VenueBootstrap.result(entries: [
            entry("a", fields: ["journaltitle": "Ambiguous Name"]),
            entry("b", type: .book, fields: ["publisher": "Ambiguous Name"]),
        ], existing: [])
        XCTAssertTrue(r.candidates.isEmpty, "衝突者不得建檔：\(r.candidates)")
        XCTAssertEqual(r.conflicts.map(\.name), ["Ambiguous Name"])
        XCTAssertEqual(r.conflicts.first?.types, [.periodical, .publisher])
    }

    // MARK: - 只建立、不歸戶

    /// `makeVenues` 產出的記錄帶所有寫法，且 `authorized` 取第一個。
    func testMakeVenuesKeepsAllWritingsAndSetsAuthorized() {
        let r = VenueBootstrap.result(entries: [
            entry("a", fields: ["journaltitle": "Psychometrika"]),
            entry("b", fields: ["journaltitle": "PSYCHOMETRIKA"]),
        ], existing: [])
        let venues = VenueBootstrap.makeVenues(r.candidates)
        XCTAssertEqual(venues.count, 1)
        XCTAssertEqual(Set(venues[0].names.entries.map(\.value)),
                       ["Psychometrika", "PSYCHOMETRIKA"])
        XCTAssertEqual(venues[0].authorized.count, 1)
        XCTAssertEqual(venues[0].type, .periodical)
    }

    /// **id 是 v4 隨機，不由名字重算**（#241 doctrine；venue 從第一天就沒有 v5 遺產）。
    ///
    /// 同名建兩次要得到不同 id——否則兩個同名不同刊會在合併時熔成一筆。
    func testVenueIdsAreRandomNotDerivedFromName() {
        let cand = VenueBootstrap.Candidate(
            key: "psychometrika", names: ["Psychometrika"], type: .periodical,
            occurrences: 1, evidence: "journaltitle")
        let a = VenueBootstrap.makeVenues([cand])[0]
        let b = VenueBootstrap.makeVenues([cand])[0]
        XCTAssertNotEqual(a.id, b.id,
                          "venue id 必須是 v4 隨機——由名字推導會讓同名不同刊熔成一筆")
    }
}

// MARK: - #548：與既有記錄寬鬆共鍵——先消歧，不建檔

extension VenueBootstrapTests {

    private func e(_ ck: String, journal: String) -> Entry {
        var x = Entry(id: UUID(), citekey: ck, type: .periodicalArticle, title: "T",
                      authors: [.literal("A, A.")], date: "2020")
        x.fields = ["journaltitle": journal]
        return x
    }

    /// **只差標點的刊名不再變成第二筆記錄。**
    ///
    /// 缺陷已經發生過：live store 有三筆 JRSS-B，只差 `:` ／ `(` ／ `-`
    /// （key 分別是 `…-society`、`…-society-2`、`…-society-3`——`-2`／`-3` 正是
    /// 本命令撞號時自己加的後綴）。`NameNormalization.matchingKey` 不摺標點，
    /// 所以 `known` 那道精確比對看不到它們。
    func testPunctuationOnlyVariantLandsInPendingResolution() {
        let existing = Venue(
            key: "jrss-b", type: .periodical,
            names: Timeline([TemporalValue(
                value: "Journal of the Royal Statistical Society Series B: Statistical Methodology")]))
        let r = VenueBootstrap.result(
            entries: [e("a", journal:
                "Journal of the Royal Statistical Society Series B (Statistical Methodology)")],
            existing: [existing])
        XCTAssertTrue(r.candidates.isEmpty, "不得建成第二筆：\(r.candidates)")
        XCTAssertEqual(r.pendingResolution.map(\.matchedKeys), [["jrss-b"]])
    }

    /// 前導冠詞與 `&`／`and`——另外兩個實測到的形狀。
    func testLeadingArticleAndAmpersandAlsoCollide() {
        for (existingName, literal) in [
            ("The Guilford Press", "Guilford Press"),
            ("British Journal of Mathematical and Statistical Psychology",
             "British Journal of Mathematical & Statistical Psychology"),
        ] {
            let v = Venue(key: "v", type: .periodical,
                          names: Timeline([TemporalValue(value: existingName)]))
            let r = VenueBootstrap.result(entries: [e("a", journal: literal)], existing: [v])
            XCTAssertTrue(r.candidates.isEmpty, "\(literal) 不該建檔")
            XCTAssertEqual(r.pendingResolution.first?.matchedKeys, ["v"], "\(literal)")
        }
    }

    /// **不同的刊不得被收攏。** 這是判準的另一半——寬鬆鍵存在的理由是找重複，
    /// 不是把目錄壓扁。
    func testDifferentJournalsStillBecomeSeparateCandidates() {
        let existing = Venue(key: "jap", type: .periodical,
                             names: Timeline([TemporalValue(value: "Journal of Applied Psychology")]))
        let r = VenueBootstrap.result(
            entries: [e("a", journal: "Journal of Educational Psychology")],
            existing: [existing])
        XCTAssertEqual(r.candidates.count, 1)
        XCTAssertTrue(r.pendingResolution.isEmpty)
    }

    /// **`LooseNameKey` 的 reorder 語意刻意不套用到刊名。**
    ///
    /// 人名會被索引系統重排（`Hsu, Yung-Fong`），刊名不會；而 token 集合相等對刊名
    /// 是誤判來源。這條測試釘住那個裁決——若哪天有人「順手統一」成 `LooseNameKey`，
    /// 它會紅。
    func testTokenReorderIsNotTreatedAsTheSameJournal() {
        // **這一對是構造的**：`Statistics and Computing` 是真的刊，
        // `Computing and Statistics` 不是。用它釘住的是**裁決本身**（LooseTitleKey
        // 不做 reorder），不是宣稱這個判準今天在擋什麼——真實刊名裡零實例。
        XCTAssertNotEqual(LooseTitleKey.key("Statistics and Computing"),
                          LooseTitleKey.key("Computing and Statistics"),
                          "token 集合相等對刊名不構成同一本")
        XCTAssertEqual(LooseNameKey.reorderKey("Statistics and Computing"),
                       LooseNameKey.reorderKey("Computing and Statistics"),
                       "對照：人名的 reorder 鍵會把它們視為同鍵——所以不能拿它來比刊名")
    }

    /// 空鍵不算共鍵——否則兩個純標點的名字會配成一對。
    func testEmptyKeyIsNotAMatch() {
        XCTAssertEqual(LooseTitleKey.key("—"), "")
        XCTAssertFalse(LooseTitleKey.matches("—", "···"))
    }
}

