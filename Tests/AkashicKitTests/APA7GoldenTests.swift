import XCTest
@testable import AkashicCore
@testable import AkashicExport
import BiblatexAPA

/// APA7 手冊 ch10 的編號例當 golden 矩陣（#327）。
///
/// **這批 fixture 的權威來源是手冊本身**——每一筆都是 APA 官方印出來的正確參考文獻，
/// 所以「我們的模型接不住它」時，錯的是我們不是它。這與一般 fixture 的方向相反：
/// 通常 fixture 是我們寫的、測試驗實作；這裡 fixture 是外部權威、測試驗**我們的模型
/// 夠不夠**（`apa7-is-the-work-floor`：「一筆 work 的資訊下限是能產出正確的 APA7
/// 參考文獻」，而 ch10 的編號例就是那條規則指定的驗收矩陣）。
///
/// ## 為什麼是「複製檔案」而不是「抄成 Swift 陣列」
///
/// 第一批（10.1 的 10 筆）是手抄進 Swift 常數的。那個做法有兩個問題，而且都**安靜**：
/// 手抄會掉欄位（抄的人只抄他認為必要的），而且 fixture 一旦離開來源檔就再也對不回去。
/// 現在改成把來源 `.bib` **整檔收進 `Tests/Fixtures/apa7-ch10/`**，測試時用專案自己的
/// `BibParser` 解析——provenance 明確、零手抄誤差，順帶讓 parser 吃自己的狗糧。
///
/// 手冊編號直接編碼在來源的 citekey 裡（`10.2:20` ＝ 節號:例號），所以對映關係
/// **住在資料中**，不靠註解維持。
///
/// ## 這個測試實際在驗什麼（往返，不是單向）
///
/// ```
/// fixture 的 BibEntry ──→ 我們的 Entry ──→ bibEntry(for:) ──→ BibValidator
///        （手冊）          （受測的模型）      （匯出路徑）        （書目正確性）
/// ```
///
/// 中間那一步是重點：手冊的資料先進我們的模型，再從模型走匯出路徑出來。**模型持有不了
/// 的東西會在這裡掉**，然後 validator 報缺欄位。所以紅燈的意思是「Akashic 的 work 模型
/// 不足以產出這一筆」，不是「validator 有 bug」。
///
/// ## 覆蓋率有結構性上界（不是偷懶）
///
/// `BibValidator.requiredFields` 只涵蓋 7 個 biblatex type，而 `WorkType` 送出的型別比
/// 那 7 個多——不在表內的節**驗不出東西**，只會落進 `uncheckedCitekeys`。本矩陣
/// **把這件事斷言出來**（見 `testUncoveredSectionsAreReportedUnchecked`）而不是省略
/// 它們：省略的話，日後有人補了必要欄位表，矩陣不會有任何反應。
///
/// ### #352 之後覆蓋數字**下降**了，而那是改善
///
/// 修正型別對映（#352）後，可驗證的例子從 **85 降到 68**（−17）：10.9（6 筆）與
/// 10.10（11 筆）從 `REPORT` 改對映到 `DATASET`／`SOFTWARE`，而後兩者不在
/// `BibValidator` 的表內。
///
/// **先前那 17 筆是假覆蓋。** 它們被拿 `REPORT`（＝APA7 10.4 Reports and Gray
/// Literature）的欄位需求去驗，而它們是資料集與軟體（10.9／10.10）。用錯的類別規則
/// 通過檢查不算被檢查過——它只是沒被正確地檢查而看起來像通過。
///
/// 覆蓋率這個數字因此**不能單獨當進度指標**：它同時受「對映對不對」與「表夠不夠大」
/// 影響，而兩者的改善方向相反。#353（改用 `APADataModel` 的 15 型表，它有 `DATASET`
/// 與 `SOFTWARE`）會恢復這 17 筆的**真**覆蓋。
final class APA7GoldenTests: XCTestCase {

    // MARK: - 節 → WorkType

    /// ch10 的節就是 APA7 的分類本身，所以對映以**節**為準。
    ///
    /// 刻意**不**用來源 `.bib` 自己的 entry type：那個標記在同一節內並不一致
    /// （10.10 同時出現 `@SOFTWARE` 與 `@ONLINE`），拿它當分類會把同一節的例子拆到
    /// 兩個 `WorkType` 去。
    private static let sectionToType: [String: WorkType] = [
        "10.1":  .periodicalArticle,
        "10.2":  .book,
        "10.3":  .bookChapter,
        "10.4":  .report,
        "10.6":  .thesis,
        "10.9":  .dataSet,
        "10.10": .software,
        "10.12": .audiovisualWork,
        "10.13": .audioWork,
        "10.15": .socialMediaPost,
        "10.16": .webpage,
    ]

    /// ch10 有而本矩陣**沒有 fixture** 的節，以及為什麼——**封閉列舉，附理由**。
    ///
    /// 這張表存在的唯一理由是**讓缺席可見**。沒有它，「這個節沒被測」與「這個節沒有
    /// 問題」在測試輸出上完全一樣（`lossless-intake` 執行細節 3：靜默是最糟的形式）。
    private static let sectionsWithoutFixtures: [String: String] = [
        "10.5":  "會議發表（conference session）——來源 domain 無範例",
        "10.7":  "書評／影評（reviews）——來源 domain 無範例",
        "10.8":  "未刊稿與非正式出版——來源 domain 無範例",
        "10.11": "測驗、量表與問卷——來源 domain 無範例（而這正是 #325 記錄的零實例節）",
        "10.14": "視覺作品（visual works）——來源 domain 無範例",
    ]

    /// **已知的 validator 缺口**：手冊的正確例子在這裡報 error，而原因是
    /// `BibValidator` 的必要欄位表不足，**不是** Akashic 的模型持有不了。
    ///
    /// 這張表的斷言是**精確相等**（見 `testKnownValidatorGapsAreExactlyTheseFour`）：
    ///
    /// - 缺口被修好 → 測試紅，逼人把該列刪掉（否則表會腐爛成一份「曾經的缺口」清單）
    /// - 新缺口出現 → 測試紅，逼人裁決它屬於哪一類
    ///
    /// 這與永遠紅的測試不同：永紅的測試會被無視，而**精確相等**讓紅燈永遠代表
    /// 「有一件事變了」。同 `uncheckedCitekeys`（#326）的紀律：不讓「沒被檢查」冒充
    /// 「檢查過且乾淨」，這裡是不讓「已知缺口」冒充「模型不足」。
    ///
    /// 三類缺口（追蹤：#327 的 follow-up）：
    /// 1. **編者代替作者**——APA7 對編著作品的作者位置就是編者（`EDITOR`）。表只認 `AUTHOR`
    /// 2. **合法的無日期**——APA7 有 `(n.d.)`。表要求 `DATE` 存在
    /// 3. **合法的無個人作者**——維基百科條目的作者位置不是個人。表要求 `AUTHOR` 存在
    private static let knownValidatorGaps: [String: String] = [
        "apa7-10-2-24":  "編著書只有 EDITOR（APA7 的作者位置＝編者），BOOK 表只認 AUTHOR",
        "apa7-10-3-47":  "編著作品只有 EDITOR，INCOLLECTION 表只認 AUTHOR",
        "apa7-10-4-55":  "來源本身無日期（APA7 印 n.d.），REPORT 表要求 DATE 存在",
        // `apa7-10-10-76` 曾在此列（維基條目無個人作者）。**#352 之後它不再報 error，
        // 但原因不是缺口被解決**——10.10 的 `WorkType` 從 `REPORT` 改對映到 `SOFTWARE`，
        // 而 `SOFTWARE` 不在 `BibValidator` 的表內，所以它變成「未檢查」。
        // 誠實的說法是：那個假陽性消失了，代價是那一筆現在完全沒被檢查。
        // #353（換用 `APADataModel` 的表，它有 `SOFTWARE`）會讓它回到被檢查的狀態，
        // 屆時要重新判斷它是否再次落入本表。
    ]

    /// `BibValidator` 涵蓋的 biblatex type（`BibExport.apa7CheckedTypes` 的鏡像）。
    ///
    /// 這裡重述一份是刻意的：若哪天兩邊分岔，`testUncoveredSectionsAreReportedUnchecked`
    /// 會紅，逼人回來看。直接讀對方的 private 常數反而會讓分岔無聲。
    private static let checkedBiblatexTypes: Set<String> = [
        "ARTICLE", "PRESENTATION", "REPORT", "BOOK",
        "INCOLLECTION", "INPROCEEDINGS", "THESIS",
    ]

    // MARK: - Fixture 載入

    private struct Example {
        let section: String      // "10.2"
        /// 例號。**字串不是 Int**——手冊有子例（`75a`／`75b`／…，同一編號的變體），
        /// 實測 111 筆裡有 42 筆帶字母後綴。用 `Int` 解析會把它們整批靜默丟掉。
        let number: String       // "20" 或 "75a"
        let storeCitekey: String // "apa7-10-2-20" / "apa7-10-9-75a"
        let type: WorkType
        let entry: Entry
    }

    // MARK: - 10.6 的三個事實（#335）

    private static func fixtureDirectory() throws -> URL {
        var dir = URL(fileURLWithPath: #filePath)
        for _ in 0..<10 {
            dir.deleteLastPathComponent()
            let candidate = dir.appendingPathComponent("Tests/Fixtures/apa7-ch10")
            if FileManager.default.fileExists(atPath: candidate.path) { return candidate }
        }
        throw XCTSkip("找不到 Tests/Fixtures/apa7-ch10")
    }

    /// 來源 citekey `10.2:20` 轉成合 `StoreKey.pattern` 的 `apa7-10-2-20`。
    ///
    /// **不要改成連續編號**——手冊對映是這批 fixture 的全部價值，弄丟了它，這些就只是
    /// 一百多筆隨機的假資料。
    private static func storeCitekey(section: String, number: String) -> String {
        "apa7-\(section.replacingOccurrences(of: ".", with: "-"))-\(number)"
    }

    private static func loadExamples() throws -> [Example] {
        let dir = try fixtureDirectory()
        let files = try FileManager.default.contentsOfDirectory(at: dir,
                                                                includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "bib" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        XCTAssertFalse(files.isEmpty, "fixture 目錄是空的")

        var out: [Example] = []
        for file in files {
            let content = try String(contentsOf: file, encoding: .utf8)
            for bib in BibParser.parse(content: content, filePath: file.path).entries {
                // key 形如 `10.2:20`；ch11（法律）不在 ch10 範圍，跳過。
                let parts = bib.key.split(separator: ":")
                guard parts.count == 2,
                      let type = sectionToType[String(parts[0])] else { continue }
                let section = String(parts[0])
                let number = String(parts[1])
                // 例號是 `\d+` 或 `\d+[a-z]+`（子例）。形狀不合就是來源長出了新形式
                // ——寧可紅燈，不要靜默跳過（那是 42 筆消失的原因）。
                XCTAssertNotNil(number.range(of: "\\A[0-9]+[a-z]*\\z",
                                             options: .regularExpression),
                                "\(bib.key) 的例號形狀不認得")

                var fields: [String: String] = [:]
                for (key, value) in bib.fields.pairs {
                    let lower = key.lowercased()
                    // title／author／date 由 `Entry` 的具名屬性承載；再放進 `fields`
                    // 會在 `bibEntry(for:)` 裡覆寫同名鍵。
                    guard !["title", "author", "date"].contains(lower) else { continue }
                    fields[lower] = value
                }

                // 10.6 的三個事實（#335）散在來源的**兩處**：學位別在 entry type
                // （`@PHDTHESIS`／`@MASTERSTHESIS`），取得途徑在 `TYPE` 欄位的英文片語
                // （`Unpublished doctoral dissertation` vs `Doctoral dissertation`）
                // ——那正是 §10.6 兩張 template 的差別。不接上去就等於把 fixture 攜帶的
                // 資訊丟掉，矩陣也就測不到 `ThesisFacts`。
                var thesisFacts: ThesisFacts?
                if type == .thesis {
                    let degree: ThesisFacts.Degree? = {
                        switch bib.normalizedType {
                        case "PHDTHESIS":     return .doctoral
                        case "MASTERSTHESIS": return .masters
                        default:              return nil
                        }
                    }()
                    let typePhrase = bib.fields.caseInsensitiveValue(forKey: "TYPE") ?? ""
                    let url = bib.fields.caseInsensitiveValue(forKey: "URL")
                    let availability: ThesisFacts.Availability? = {
                        if typePhrase.lowercased().hasPrefix("unpublished") { return .unpublished }
                        // 已出版：手冊例 65／66 有典藏 URL 但**沒有典藏庫名**——所以
                        // `repository` 傳 nil 而不是編一個。這正是那個欄位可選的原因。
                        if url != nil { return .published(repository: nil, url: url) }
                        return nil
                    }()
                    thesisFacts = ThesisFacts(degree: degree, availability: availability)
                }

                var entry = Entry(id: UUID(),
                                  citekey: storeCitekey(section: section, number: number),
                                  type: type,
                                  title: bib.title ?? "",
                                  authors: (bib.authors ?? "")
                                      .components(separatedBy: " and ")
                                      .map { $0.trimmingCharacters(in: .whitespaces) }
                                      .filter { !$0.isEmpty }
                                      .map { .literal($0) },
                                  date: bib.date,
                                  thesis: thesisFacts)
                entry.fields = fields
                out.append(Example(section: section, number: number,
                                   storeCitekey: entry.citekey, type: type, entry: entry))
            }
        }
        return out.sorted { ($0.storeCitekey) < ($1.storeCitekey) }
    }

    private func examples(inCheckedSections checked: Bool) throws -> [Example] {
        try Self.loadExamples().filter {
            Self.checkedBiblatexTypes.contains($0.type.biblatexEntryType) == checked
        }
    }

    // MARK: - 斷言

    /// fixture 真的載進來了，而且節分布符合來源。
    ///
    /// 沒有這條，下面每一個「零錯誤」斷言都可以被空陣列偽造成通過——與
    /// `testManualExamplesAreActuallyChecked` 防的是同一件事的兩面。
    func testFixturesLoadAndCoverTheExpectedSections() throws {
        let all = try Self.loadExamples()
        XCTAssertGreaterThan(all.count, 100, "ch10 fixture 應有一百筆以上，實際 \(all.count)")
        let sections = Set(all.map(\.section))
        XCTAssertEqual(sections, Set(Self.sectionToType.keys),
                       "載入的節與對映表不一致——多出或少掉的節："
                       + "\(sections.symmetricDifference(Set(Self.sectionToType.keys)))")
    }

    /// **矩陣的核心斷言**：手冊的正確範例，經我們的模型往返之後，不得產生 APA7 error。
    ///
    /// 紅燈代表 Akashic 的 work 模型持有不了那筆所需的資訊——那正是
    /// `apa7-is-the-work-floor` 定義的「跌破下限」。
    func testManualExamplesInCoveredSectionsProduceNoAPA7Errors() throws {
        let covered = try examples(inCheckedSections: true)
        XCTAssertFalse(covered.isEmpty, "可驗證的節不該是空的")
        let report = BibExport.apa7Report(entries: covered.map(\.entry), people: [])
        let errors = report.issues.filter { $0.severity == .error }
        let unexpected = errors.filter { Self.knownValidatorGaps[$0.citekey] == nil }
        XCTAssertTrue(unexpected.isEmpty,
                      "手冊範例產生了**未列入已知缺口**的 APA7 error（共 \(unexpected.count) 筆）"
                      + "——這代表 Akashic 的 work 模型持有不了那筆所需的資訊，"
                      + "或是又發現了一類 validator 缺口：\n"
                      + unexpected.map { "  \($0.citekey): \($0.message)" }
                                  .sorted().joined(separator: "\n"))
    }

    /// 已知缺口**恰好**是那四筆——一筆不多一筆不少。
    ///
    /// 這條是上一個測試的另一半：那條問「有沒有新的壞掉」，這條問「舊的有沒有被修好
    /// 卻沒人更新表」。少了這條，`knownValidatorGaps` 會慢慢腐爛成一份記錄著早已修好的
    /// 缺口的清單，而讀它的人無從分辨哪些還成立。
    func testKnownValidatorGapsAreExactlyTheseFour() throws {
        let covered = try examples(inCheckedSections: true)
        let report = BibExport.apa7Report(entries: covered.map(\.entry), people: [])
        let failing = Set(report.issues.filter { $0.severity == .error }.map(\.citekey))
        XCTAssertEqual(failing, Set(Self.knownValidatorGaps.keys),
                       "已知缺口表與實際失敗不一致。"
                       + "已修好卻仍列在表裡：\(Set(Self.knownValidatorGaps.keys).subtracting(failing).sorted())；"
                       + "實際失敗卻未列入：\(failing.subtracting(Set(Self.knownValidatorGaps.keys)).sorted())")
    }

    /// 可驗證的節必須**真的被檢查過**，不得落進 `uncheckedCitekeys`。
    ///
    /// 沒有這條，上一個測試會被「validator 根本沒看它們」偽造成通過。
    func testManualExamplesInCoveredSectionsAreActuallyChecked() throws {
        let covered = try examples(inCheckedSections: true)
        let report = BibExport.apa7Report(entries: covered.map(\.entry), people: [])
        XCTAssertTrue(report.uncheckedCitekeys.isEmpty,
                      "這些節的 type 應在 validator 的表內，未被檢查的："
                      + "\(report.uncheckedCitekeys.sorted())")
    }

    /// 對映到 `UNPUBLISHED`／`ONLINE` 的節**必須**被報成 unchecked。
    ///
    /// 這條看起來像在斷言一個缺陷，實際上是在**釘住缺口的位置**：日後有人替那兩個
    /// biblatex type 補了必要欄位表，這條會紅，逼人回來把那些節移進上面的可驗證組
    /// ——而不是讓覆蓋率默默改變卻沒人發現。
    func testUncoveredSectionsAreReportedUnchecked() throws {
        let uncovered = try examples(inCheckedSections: false)
        XCTAssertFalse(uncovered.isEmpty,
                       "若這裡空了，代表 validator 的涵蓋範圍變了——請更新本矩陣的分組")
        let report = BibExport.apa7Report(entries: uncovered.map(\.entry), people: [])
        XCTAssertEqual(Set(report.uncheckedCitekeys), Set(uncovered.map(\.storeCitekey)),
                       "對映到 UNPUBLISHED／ONLINE 的節應全數落在 uncheckedCitekeys")
        XCTAssertTrue(report.issues.isEmpty,
                      "未涵蓋的 type 不該產生 issue（那會是假陽性）：\(report.issues)")
    }

    /// ch10 的 16 個節，每一個都必須**有 fixture**或**在缺席表裡具名**。
    ///
    /// 這是本矩陣的封閉性檢查：不允許一個節既沒有測試也沒有記錄——那正是
    /// 「沒被檢查」與「檢查過且乾淨」無法區分的形狀。
    func testEveryCh10SectionIsEitherCoveredOrDeclaredMissing() throws {
        let allSections = (1...16).map { "10.\($0)" }
        for section in allSections {
            let hasFixture = Self.sectionToType[section] != nil
            let declaredMissing = Self.sectionsWithoutFixtures[section] != nil
            XCTAssertTrue(hasFixture != declaredMissing,
                          "\(section) 必須恰好落在其中一邊："
                          + "有 fixture=\(hasFixture)、已具名缺席=\(declaredMissing)")
        }
    }

    /// citekey 的轉寫必須合 `StoreKey` 規則，且**可還原回手冊編號**。
    func testCitekeysAreStoreValidAndReversible() throws {
        for example in try Self.loadExamples() {
            XCTAssertNotNil(example.storeCitekey.range(of: "\\A[a-z0-9][a-z0-9-]*\\z",
                                                      options: .regularExpression),
                            "\(example.storeCitekey) 不合 StoreKey pattern")
            let parts = example.storeCitekey
                .replacingOccurrences(of: "apa7-", with: "")
                .split(separator: "-")
            XCTAssertEqual(parts.count, 3, "\(example.storeCitekey) 應可還原成 節-節-例 三段")
            XCTAssertEqual("\(parts[0]).\(parts[1])", example.section)
            XCTAssertEqual(String(parts[2]), example.number)
        }
    }

    /// 10.6 的 fixture 必須攜帶學位別，且輸出成依賴指定的 biblatex token（#335）。
    ///
    /// 這條把 fixture 與 `ThesisFacts` 綁在一起：來源用 `@PHDTHESIS`／`@MASTERSTHESIS`
    /// 編碼學位別，若 loader 丟掉它（第一版就是這樣），這條會紅。
    func testSection106FixturesCarryDegreeAndEmitBiblatexToken() throws {
        let theses = try Self.loadExamples().filter { $0.section == "10.6" }
        XCTAssertFalse(theses.isEmpty, "10.6 應有 fixture")
        for example in theses {
            let degree = example.entry.thesis?.degree
            XCTAssertNotNil(degree, "\(example.storeCitekey) 應有學位別"
                            + "（來源以 @PHDTHESIS／@MASTERSTHESIS 編碼）")
            guard let degree else { continue }
            let bib = BibExport.bibEntry(for: example.entry, people: [:])
            XCTAssertEqual(bib.fields.caseInsensitiveValue(forKey: "type"),
                           degree.biblatexToken,
                           "\(example.storeCitekey) 的 type 欄位應是依賴指定的 token")
        }
    }

    /// 10.6 的取得途徑必須從 `TYPE` 片語推出，且**兩種形態都要出現在 fixture 裡**。
    ///
    /// §10.6 的兩張 template 就是照這條軸分的，所以只覆蓋一邊等於沒測到那條軸。
    func testSection106CoversBothAvailabilityForms() throws {
        let theses = try Self.loadExamples().filter { $0.section == "10.6" }
        let forms = theses.compactMap { $0.entry.thesis?.availability }
        XCTAssertTrue(forms.contains(.unpublished),
                      "fixture 應含未出版形態（例 64 的 TYPE 以 Unpublished 開頭）")
        XCTAssertTrue(forms.contains { if case .published = $0 { return true } else { return false } },
                      "fixture 應含已出版形態（例 65／66 有典藏 URL）")
        // 已出版的例子**沒有典藏庫名**——記在測試裡，因為那是 `repository` 可選的理由。
        for form in forms {
            if case .published(let repository, let url) = form {
                XCTAssertNil(repository,
                             "手冊例 65／66 沒有典藏庫名；有值代表 loader 編造了東西")
                XCTAssertNotNil(url, "已出版形態是靠 URL 判定的")
            }
        }
    }

    /// 每個 `WorkType` 的 `apa7Section` 必須與它在本矩陣被指派到的節一致。
    ///
    /// 抓的是「對映表寫錯節」——例如把 10.13 的例子掛到 `audiovisualWork`（10.12）。
    /// 那種錯誤不會讓任何欄位檢查失敗，只會讓矩陣的分節悄悄失真。
    func testSectionAssignmentAgreesWithWorkTypeMapping() throws {
        for (section, type) in Self.sectionToType {
            // 相等而非 hasPrefix——`"10.16".hasPrefix("10.1")` 為真，用前綴比對
            // 會讓 10.16 的例子誤判成通過 10.1 的指派。
            XCTAssertEqual(type.apa7Section, section,
                           "\(type) 的 apa7Section 是 \(type.apa7Section)，"
                           + "但矩陣把它指派給 \(section)")
        }
    }
}
