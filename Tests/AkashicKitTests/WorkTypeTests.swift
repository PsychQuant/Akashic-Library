import XCTest
@testable import AkashicCore

/// `WorkType` 封閉列舉（#325 階段二）。
///
/// 值域**細分** APA7 手冊 ch10 的 16 節——依 `.claude/rules/apa7-is-the-work-floor.md`
/// 的「分類權威＝細分關係」：每個值對映到**恰好一個** ch10 節（保證匯出永遠可行），
/// **多個值可以對映到同一節**（專案有權更細），但**不得更粗**。
final class WorkTypeTests: XCTestCase {

    /// 每個 `WorkType` 都必須宣告它的 APA7 節——**沒有節號的值就沒有判準**。
    func testEveryCaseDeclaresItsAPA7Section() {
        for t in WorkType.allCases {
            XCTAssertFalse(t.apa7Section.isEmpty,
                           "\(t.rawValue) 沒有 APA7 節號——那個值沒有判準")
        }
    }

    /// **細分而非相等**：允許多值對映同節（如 `reference-work-entry` 與 `book-chapter`
    /// 同屬 10.3），但每個值只能有一個節。
    func testRefinementAllowsManyValuesPerSection() {
        let bySection = Dictionary(grouping: WorkType.allCases, by: \.apa7Section)
        XCTAssertTrue(bySection["10.3"]?.count ?? 0 >= 2,
                      "10.3 應同時有 book-chapter 與 reference-work-entry（細分的實例）")
    }

    // **接縫守衛住在階段一，不在這裡。**
    //
    // 「階段一的每個遷移目標都是合法 WorkType」這條檢查需要**同時**看得到兩份值域，
    // 而階段二已把 `WorkTypeMigration` 移除（它讀不到舊值——舊值在階段二的 decode
    // 就被拒了，留著只會是個永遠無事可做卻看似可用的命令，違反 `no-compat-fallback`
    // 的「退場即刪」）。
    //
    // 所以那條守衛必須寫在**階段一**（`WorkTypeMigrationTests`），在那裡兩份值域
    // 同時在場。這是兩階段部署的固有性質：測試只驗證單一時點的快照，跨階段的一致性
    // 要放在**兩者都存在的那個時點**。

    // MARK: - biblatex 有損逆向（`.bib` 讀取路徑）

    /// 逆向對映**必須落回正向**——`WorkType(biblatex:)` 選的原像，其
    /// `biblatexEntryType` 要等於原輸入。
    ///
    /// 這條抓的是「逆向表與正向表分岔」：兩張表各自演化時，正向改了原像卻沒改逆向
    /// （或反之），讀 `.bib` 就會把 `@INPROCEEDINGS` 讀成一個輸出 `@ARTICLE` 的值。
    /// 沒有這條，分岔完全無症狀——`.bib` 進得去、出得來，只是**進出不是同一筆**。
    func testInverseRoundTripsThroughTheForwardMapping() {
        for t in WorkType.allCases {
            let bib = t.biblatexEntryType.lowercased()
            guard let back = WorkType(biblatexEntryType: bib) else {
                continue   // 多對一的非原像側沒有逆向，是預期的（見下一條）
            }
            XCTAssertEqual(back.biblatexEntryType.lowercased(), bib,
                           "\(bib) 逆向到 \(back.rawValue)，但它正向輸出的是 "
                           + "\(back.biblatexEntryType)——正逆兩表分岔了")
        }
    }

    /// **正向是多對一，所以逆向必須選一個原像**——選的是最不細分的那個。
    ///
    /// `referenceWorkEntry` 與 `bookChapter` 都輸出 `INCOLLECTION`；讀 `.bib` 時只能得到
    /// `bookChapter`。細分要靠額外訊號（`misc` + `url`），不靠猜。
    func testInversePicksTheLeastRefinedPreimage() {
        XCTAssertEqual(WorkType(biblatexEntryType: "incollection"), .bookChapter,
                       "不得逆向到 referenceWorkEntry——那需要額外訊號")
        XCTAssertEqual(WorkType(biblatexEntryType: "report"), .report,
                       "不得逆向到 dataSet／software／testInstrument")
        XCTAssertEqual(WorkType(biblatexEntryType: "online"), .webpage,
                       "不得逆向到視聽／社群媒體")
    }

    /// 條件式細分的判準與階段一同源（同一組 `fields` 訊號）。
    func testConditionalRefinementUsesTheSameSignalsAsMigration() {
        XCTAssertEqual(WorkType(biblatexEntryType: "misc",
                                fields: ["url": "https://x"]), .referenceWorkEntry)
        XCTAssertNil(WorkType(biblatexEntryType: "misc"),
                     "沒有 url 的 misc **不猜**——回 nil 讓呼叫端拒絕並列出值域")
        XCTAssertEqual(WorkType(biblatexEntryType: "unpublished",
                                fields: ["location": "Taipei"]), .conferenceSession)
        XCTAssertEqual(WorkType(biblatexEntryType: "unpublished"), .unpublishedWork)
    }

    /// 對映不到就回 `nil`，**不塞預設值**。
    ///
    /// 靜默塞一個 `webpage` 會讓使用者事後無法分辨「我沒給」與「系統猜的」——
    /// 與 `lossless-intake` 的「真的要丟就必須報出來」同向。
    func testUnmappableBiblatexTypeReturnsNilRatherThanGuessing() {
        for unknown in ["patent", "artwork", "standard", "letter", "mvbook"] {
            XCTAssertNil(WorkType(biblatexEntryType: unknown),
                         "「\(unknown)」沒有對映，必須回 nil 而不是猜一個")
        }
    }

    /// 大小寫不敏感——`.bib` 檔寫 `@ARTICLE` 與 `@article` 都常見。
    func testInverseIsCaseInsensitive() {
        XCTAssertEqual(WorkType(biblatexEntryType: "ARTICLE"), .periodicalArticle)
        XCTAssertEqual(WorkType(biblatexEntryType: "InProceedings"), .conferenceSession)
    }

    /// 舊自由字串**不得**還原成 `WorkType`——階段二的 decode 是嚴格的。
    func testLegacyFreeStringsAreRejected() {
        for legacy in ["article", "misc", "unpublished", "presentation",
                       "inproceedings", "incollection", "online"] {
            XCTAssertNil(WorkType(rawValue: legacy),
                         "「\(legacy)」是階段一遷移前的舊值，階段二不得接受")
        }
    }

    /// #409：`referenceWorkEntry` 的名字承擔不了它實際代表的東西——它自己的三個下游
    /// 對照（APA7 §10.3「Entries in **Reference Works**」／biblatex `INREFERENCE`／
    /// CSL `entry-encyclopedia`）沒有一個說 Wikipedia，而 Zotero 的
    /// `encyclopediaArticle` 也對映進來。改名為 `referenceWorkEntry`。
    ///
    /// **不用 `referenceEntry`**：`reference` 在本 repo 已是「參考文獻」的意思
    /// （`Person.references`／`ProvenanceReference`），`referenceEntry` 會讀成
    /// 「一筆參考文獻條目」——而那是**每一筆** work。
    func testReferenceWorkEntryReplacesWikipediaEntry() {
        XCTAssertEqual(WorkType(rawValue: "reference-work-entry"), .referenceWorkEntry)
        // **舊值不得留下雙讀路徑**（`no-compat-fallback`）。
        //
        // 這一行在實作時被全域改名誤傷過（`"wikipedia-entry"` 被一併換成新值，
        // 於是斷言變成「新值必須是 nil」而紅）——**測試自己抓到了機械改名的誤傷**。
        // 保留這段記錄：舊值字面在這裡是**被測資料**，不是待改的引用。
        XCTAssertNil(WorkType(rawValue: "wikipedia-entry"),
                     "改名後舊值必須整個消失，不得同時解析——那是相容 fallback")
    }

    /// #409／#339：參考工具書的 `booktitle` 是**載體**不是書名，所以它要在
    /// `booktitleCarrierTypes` 裡。改名不得把這個成員弄丟。
    func testReferenceWorkEntryIsABooktitleCarrier() {
        XCTAssertTrue(VenueDerivation.booktitleCarrierTypes.contains(.referenceWorkEntry))
        XCTAssertFalse(VenueDerivation.booktitleCarrierTypes.contains(.bookChapter),
                       "編著章節索取 EDITOR + PUBLISHER，venue 持不住——#324 的裁決")
    }

}
