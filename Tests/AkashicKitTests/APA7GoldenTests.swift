import XCTest
@testable import AkashicCore
@testable import AkashicExport

/// APA7 手冊 ch10 的編號例當 golden 矩陣（#327）。
///
/// **這批 fixture 的權威來源是手冊本身**——每一筆都是 APA 官方印出來的正確參考文獻，
/// 所以「我們的 validator 對它報錯」時，錯的是我們不是它。這與一般 fixture 的方向相反：
/// 通常 fixture 是我們寫的、測試驗實作；這裡 fixture 是外部權威、測試驗**我們的模型
/// 接不接得住**。
///
/// ## 目前覆蓋
///
/// 第一批只做 **10.1 Periodicals 的 10 筆**（#327 的 issue 建議按節分批，先做已有實例
/// 的節）。其餘 15 節隨 #325 的 type 值域落地再補——現在補了也只會落進
/// `uncheckedCitekeys`（那些 type 不在 `BibValidator` 的表內），測不出東西。
///
/// ## citekey 的轉寫
///
/// 來源 citekey 形如 `10.1:1`（節號:例號，**手冊對映直接編碼在資料裡**），但含 `.` 與
/// `:`，不合 `StoreKey.pattern`（`\A[a-z0-9][a-z0-9-]*\z`）。轉寫成 `apa7-10-1-1`，
/// 對映關係在下方註解與 fixture 名稱中保留——**不要把它改成連續編號**，那會把手冊對映
/// 弄丟。
final class APA7GoldenTests: XCTestCase {

    /// 10.1 Periodicals 的 10 筆（來源：`che-axiom-systems` 的 apa7-style domain，
    /// `03_citation_system/bibtex_examples/02_Reference_Types/journal_articles_basic.bib`）。
    ///
    /// 只保留 APA7 必要欄位（AUTHOR／TITLE／JOURNALTITLE／DATE）與 DOI——本測試驗的是
    /// **必要欄位的可持有性**，不是完整重現每一筆的所有欄位。
    private static let periodicals: [(id: String, manual: String, title: String,
                                      journal: String, date: String)] = [
        ("apa7-10-1-1",  "10.1:1",  "Language Learning as Language Use", "Psychological Review", "2019"),
        ("apa7-10-1-2",  "10.1:2",  "A Descriptive Review", "Journal of Postsecondary Education and Disability", "2018"),
        ("apa7-10-1-3",  "10.1:3",  "Environmental Influences", "Journal of Abnormal Psychology", "2017"),
        ("apa7-10-1-4",  "10.1:4",  "Advance Online Publication", "Journal of Experimental Psychology", "2020"),
        ("apa7-10-1-5",  "10.1:5",  "Special Section Introduction", "Developmental Psychology", "2018"),
        ("apa7-10-1-6",  "10.1:6",  "Article Number Example", "PLOS ONE", "2019"),
        ("apa7-10-1-7",  "10.1:7",  "Twenty-One Or More Authors", "Journal of Neuroscience", "2018"),
        ("apa7-10-1-8",  "10.1:8",  "Group Author Combination", "Health Psychology", "2019"),
        ("apa7-10-1-9",  "10.1:9",  "Republished In Translation", "Psychological Bulletin", "2017"),
        ("apa7-10-1-10", "10.1:10", "Reprinted From Another Source", "American Psychologist", "2016"),
    ]

    private func entry(_ f: (id: String, manual: String, title: String,
                            journal: String, date: String)) -> Entry {
        var e = Entry(id: UUID(), citekey: f.id, type: .periodicalArticle,
                      title: f.title, authors: [.literal("Author, A. A.")], date: f.date)
        e.fields = ["journaltitle": f.journal]
        return e
    }

    /// 手冊的正確範例**不得**被我們的 APA7 報告判為缺欄位。
    ///
    /// 這是 golden 矩陣的核心斷言：validator 對外部權威的正確資料報 error，代表我們的
    /// 必要欄位表或欄位對映錯了。
    func testManualPeriodicalExamplesProduceNoAPA7Errors() throws {
        let entries = Self.periodicals.map(entry)
        let report = BibExport.apa7Report(entries: entries, people: [])
        let errors = report.issues.filter { $0.severity == .error }
        XCTAssertTrue(errors.isEmpty,
                      "手冊 10.1 的範例不該有 APA7 error，實際：\(errors)")
    }

    /// 全部 10 筆都必須**真的被檢查過**，不得落進 `uncheckedCitekeys`。
    ///
    /// 沒有這條，上一個測試會被「validator 根本沒看它們」偽造成通過——
    /// 與 `testExportSurfacesTypesNotCoveredByValidator`（#326）防的是同一件事的兩面。
    func testManualPeriodicalExamplesAreActuallyChecked() throws {
        let entries = Self.periodicals.map(entry)
        let report = BibExport.apa7Report(entries: entries, people: [])
        XCTAssertTrue(report.uncheckedCitekeys.isEmpty,
                      "10.1 全是 article，必須全部被檢查，未檢查的：\(report.uncheckedCitekeys)")
    }

    /// citekey 的轉寫必須合 `StoreKey` 規則，且**保留手冊對映**。
    ///
    /// 手冊對映是這批 fixture 的價值所在——弄丟了它，這些就只是十筆隨機的假資料。
    func testCitekeysAreStoreValidAndKeepManualMapping() throws {
        for f in Self.periodicals {
            XCTAssertNotNil(f.id.range(of: "\\A[a-z0-9][a-z0-9-]*\\z",
                                       options: .regularExpression),
                            "\(f.id) 不合 StoreKey pattern")
            // `10.1:1` → `apa7-10-1-1`：節號與例號可從轉寫後的 id 還原
            let restored = f.id
                .replacingOccurrences(of: "apa7-", with: "")
                .split(separator: "-")
            XCTAssertEqual(restored.count, 3, "\(f.id) 應可還原成 節-節-例 三段")
            XCTAssertEqual("\(restored[0]).\(restored[1]):\(restored[2])", f.manual,
                           "轉寫後的 id 必須能還原回手冊編號")
        }
    }
}
