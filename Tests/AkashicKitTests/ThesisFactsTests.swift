import XCTest
@testable import AkashicCore
@testable import AkashicExport

/// 學位論文的 APA7 §10.6 事實（#335）。
final class ThesisFactsTests: XCTestCase {

    private func entry(thesis: ThesisFacts?, fields: [String: String] = [:]) -> Entry {
        var e = Entry(id: UUID(), citekey: "probe2020thesis", type: .thesis,
                      title: "A Thesis", authors: [.literal("Probe, P.")], date: "2020",
                      thesis: thesis)
        e.fields = fields
        return e
    }

    // MARK: - 值域

    /// 學位別是**封閉三值**——§10.6 原文的值域是三層不是兩層。
    ///
    /// 數字寫死是刻意的：手冊說「doctoral dissertations and master's **and
    /// undergraduate** theses」，漏掉學士層是這個模型最容易犯的錯（多數人只想到碩博）。
    func testDegreeDomainIsExactlyThree() {
        XCTAssertEqual(Set(ThesisFacts.Degree.allCases.map(\.rawValue)),
                       ["doctoral", "masters", "undergraduate"])
    }

    /// biblatex token 由依賴指定，不是自創慣例。
    ///
    /// `APADataModel.suggestTypeUpgrade` 原文：「Use @THESIS with type={phdthesis}」／
    /// 「type={mathesis}」。`bathesis` 是 biblatex 標準 localization key，但未出現在
    /// 依賴的建議裡（零實例，尚未實測）——這條把它釘住，改動時會被看見。
    func testBiblatexTokensMatchDependencyGuidance() {
        XCTAssertEqual(ThesisFacts.Degree.doctoral.biblatexToken, "phdthesis")
        XCTAssertEqual(ThesisFacts.Degree.masters.biblatexToken, "mathesis")
        XCTAssertEqual(ThesisFacts.Degree.undergraduate.biblatexToken, "bathesis")
    }

    // MARK: - YAML 往返

    func testRoundTripsUnpublished() throws {
        let e = entry(thesis: ThesisFacts(degree: .doctoral, availability: .unpublished))
        let yaml = try EntryYAML.encode(e)
        let back = try EntryYAML.decode(yaml)
        XCTAssertEqual(back.thesis, ThesisFacts(degree: .doctoral, availability: .unpublished))
    }

    func testRoundTripsPublishedWithRepositoryAndURL() throws {
        let facts = ThesisFacts(
            degree: .masters,
            availability: .published(repository: "ProQuest Dissertations and Theses Global",
                                     url: "https://example.org/x"))
        let yaml = try EntryYAML.encode(entry(thesis: facts))
        XCTAssertEqual(try EntryYAML.decode(yaml).thesis, facts)
    }

    func testRoundTripsPublishedWithoutURL() throws {
        let facts = ThesisFacts(degree: .undergraduate,
                                availability: .published(repository: "NTU Archive", url: nil))
        let yaml = try EntryYAML.encode(entry(thesis: facts))
        XCTAssertEqual(try EntryYAML.decode(yaml).thesis, facts)
    }

    /// 只有學位別、沒查取得途徑——這是實測 store 裡 2 筆的形狀。
    func testRoundTripsDegreeOnly() throws {
        let facts = ThesisFacts(degree: .doctoral)
        let yaml = try EntryYAML.encode(entry(thesis: facts))
        XCTAssertEqual(try EntryYAML.decode(yaml).thesis, facts)
    }

    /// **空的事實在文法上不存在。**
    ///
    /// init 是 failable：兩個事實都沒查到的意思就是 `Entry.thesis == nil`。兩種寫法並存
    /// 會製造一個編碼有損的狀態（寫不出 `thesis:` 區塊、讀回來變 `nil`、與寫入的模型
    /// 不等），而 `EntryYAML.encode` 的語意自檢會**拒絕寫出**那種 entry——#335 開發時
    /// 實際撞到過。
    func testEmptyFactsCannotBeConstructed() {
        XCTAssertNil(ThesisFacts(), "兩個事實都沒給時 init 必須回 nil")
        XCTAssertNil(ThesisFacts(degree: nil, availability: nil))
        XCTAssertNotNil(ThesisFacts(degree: .doctoral))
        XCTAssertNotNil(ThesisFacts(availability: .unpublished))
    }

    /// 檔案裡有空的 `thesis:` 區塊時，讀成 `nil` 而不是空殼。
    ///
    /// 不報錯是刻意的：空區塊不矛盾，只是沒內容。報錯會讓一個無害的檔案讀不進來。
    func testEmptyThesisBlockDecodesToNil() throws {
        let yaml = """
        work:
        id: 11111111-1111-1111-1111-111111111111
        citekey: probe2020thesis
        type: thesis
        title: A Thesis
        thesis: {}
        """
        XCTAssertNil(try EntryYAML.decode(yaml).thesis)
    }

    /// 沒有 thesis 事實的記錄照舊（回歸保護：新欄位不得改變既有序列化）。
    func testAbsentThesisIsUnchanged() throws {
        let yaml = try EntryYAML.encode(entry(thesis: nil))
        XCTAssertFalse(yaml.contains("thesis:"))
    }

    // MARK: - fail-closed

    /// 未知的學位別**整檔拒讀**，同 `VenueType` 的既有立場（#324）。
    ///
    /// 靜默忽略會讓打錯的值看起來像「沒填」——而這個欄位驅動 APA7 排版。
    func testUnknownDegreeIsRejected() throws {
        let yaml = """
        work:
        id: 11111111-1111-1111-1111-111111111111
        citekey: probe2020thesis
        type: thesis
        title: A Thesis
        thesis:
          degree: phd
        """
        XCTAssertThrowsError(try EntryYAML.decode(yaml)) { error in
            XCTAssertTrue("\(error)".contains("phd"), "訊息應點名壞值：\(error)")
        }
    }

    func testUnknownAvailabilityIsRejected() throws {
        let yaml = """
        work:
        id: 11111111-1111-1111-1111-111111111111
        citekey: probe2020thesis
        type: thesis
        title: A Thesis
        thesis:
          availability: maybe
        """
        XCTAssertThrowsError(try EntryYAML.decode(yaml))
    }

    /// **未出版不得帶典藏庫。**
    ///
    /// 依 §10.6，未出版的論文「必須直接向該校以紙本索取」——沒有資料庫可指。這個組合
    /// 在 Swift 側因為關聯值而寫不出來，YAML 側不擋就會出現型別接不住的檔案。
    func testUnpublishedWithRepositoryIsRejected() throws {
        let yaml = """
        work:
        id: 11111111-1111-1111-1111-111111111111
        citekey: probe2020thesis
        type: thesis
        title: A Thesis
        thesis:
          availability: unpublished
          repository: ProQuest
        """
        XCTAssertThrowsError(try EntryYAML.decode(yaml))
    }

    /// **已出版但沒有典藏庫名是合法的。**
    ///
    /// 這條原本斷言它被拒絕。改掉的理由來自 ch10 的 fixture：手冊例 65／66 就是已出版
    /// （有典藏 URL）卻沒有典藏庫名的形狀。要求 published 必帶 repository，會讓遇到那種
    /// 記錄的人只剩兩條路——丟掉「已出版」這個**已知**事實，或**編造**一個典藏庫名。
    /// 兩者都是 `lossless-intake` 禁止的折疊。
    ///
    /// 放寬它不弱化真正要防的那件事：見 `testUnpublishedWithRepositoryIsRejected`。
    func testPublishedWithoutRepositoryIsAccepted() throws {
        let yaml = """
        work:
        id: 11111111-1111-1111-1111-111111111111
        citekey: probe2020thesis
        type: thesis
        title: A Thesis
        thesis:
          availability: published
        """
        let decoded = try EntryYAML.decode(yaml)
        XCTAssertEqual(decoded.thesis?.availability,
                       .published(repository: nil, url: nil))
    }

    /// 有典藏庫卻沒說是否已出版——同樣是 Swift 側寫不出來的組合。
    func testRepositoryWithoutAvailabilityIsRejected() throws {
        let yaml = """
        work:
        id: 11111111-1111-1111-1111-111111111111
        citekey: probe2020thesis
        type: thesis
        title: A Thesis
        thesis:
          repository: ProQuest
        """
        XCTAssertThrowsError(try EntryYAML.decode(yaml))
    }

    func testUnknownThesisKeyIsRejected() throws {
        let yaml = """
        work:
        id: 11111111-1111-1111-1111-111111111111
        citekey: probe2020thesis
        type: thesis
        title: A Thesis
        thesis:
          degree: doctoral
          university: NTU
        """
        XCTAssertThrowsError(try EntryYAML.decode(yaml))
    }

    // MARK: - export

    func testDegreeIsEmittedAsBiblatexType() {
        let bib = BibExport.bibEntry(for: entry(thesis: ThesisFacts(degree: .doctoral)),
                                     people: [:], venues: [:])
        XCTAssertEqual(bib.fields.caseInsensitiveValue(forKey: "type"), "phdthesis")
    }

    /// **結構化欄位勝過自由字典裡的同名殘留。**
    ///
    /// 遷移把 `fields.type` 搬進 `thesis.degree` 之後那個殘留不該存在，但若存在，
    /// 不能有兩條讀法（`no-compat-fallback`）——結構化的那個是正典。
    func testStructuredDegreeWinsOverLegacyFieldsType() {
        let bib = BibExport.bibEntry(
            for: entry(thesis: ThesisFacts(degree: .masters),
                       fields: ["type": "phdthesis"]),
            people: [:], venues: [:])
        XCTAssertEqual(bib.fields.caseInsensitiveValue(forKey: "type"), "mathesis",
                       "結構化的 degree 必須勝過 fields.type 的殘留值")
    }

    func testPublishedEmitsRepositoryAsEprint() {
        let bib = BibExport.bibEntry(
            for: entry(thesis: ThesisFacts(
                degree: .doctoral,
                availability: .published(repository: "ProQuest", url: "https://e.org/1"))),
            people: [:], venues: [:])
        XCTAssertEqual(bib.fields.caseInsensitiveValue(forKey: "eprint"), "ProQuest")
        XCTAssertEqual(bib.fields.caseInsensitiveValue(forKey: "url"), "https://e.org/1")
    }

    /// 未出版不得產生 `eprint`——沒有典藏庫這件事必須傳達到輸出。
    func testUnpublishedEmitsNoEprint() {
        let bib = BibExport.bibEntry(
            for: entry(thesis: ThesisFacts(degree: .doctoral, availability: .unpublished)),
            people: [:], venues: [:])
        XCTAssertNil(bib.fields.caseInsensitiveValue(forKey: "eprint"))
    }

    /// 一筆帶完整事實的學位論文不得產生 APA7 error（下限驗收）。
    func testFullyPopulatedThesisMeetsTheAPA7Floor() {
        var e = entry(thesis: ThesisFacts(degree: .doctoral, availability: .unpublished))
        e.fields = ["institution": "National Taiwan University"]
        let report = BibExport.apa7Report(entries: [e], people: [], venues: [])
        XCTAssertTrue(report.issues.filter { $0.severity == .error }.isEmpty,
                      "完整的學位論文不該有 APA7 error：\(report.issues)")
        XCTAssertTrue(report.uncheckedCitekeys.isEmpty, "THESIS 在 validator 表內，應被檢查")
    }
}
