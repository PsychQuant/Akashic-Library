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
    /// **這段在 #415 重寫過**：它原本說「`referenceWorkEntry` 與 `bookChapter` 都輸出
    /// `INCOLLECTION`」——那是 #352 之前的事，該型別自 #352 起送 `INREFERENCE`。
    ///
    /// 實測當前的多對一恰三組：`ARTICLE`（`periodicalArticle`／`review`）、
    /// `ONLINE`（`webpage`／`socialMediaPost`）、`SOFTWARE`（`software`／`testInstrument`）。
    /// 下面三條斷言仍成立，但 `incollection` 那條的理由已改變——它現在是 1:1，
    /// 逆向到 `bookChapter` 不是「選較粗的原像」而是「唯一的原像」。
    func testInversePicksTheLeastRefinedPreimage() {
        XCTAssertEqual(WorkType(biblatexEntryType: "incollection"), .bookChapter,
                       "#352 起 referenceWorkEntry 送 INREFERENCE，已不是 INCOLLECTION 的原像")
        XCTAssertEqual(WorkType(biblatexEntryType: "report"), .report,
                       "#352 起 dataSet／software 各自送 DATASET／SOFTWARE，report 已是 1:1")
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

    /// #409：`wikipediaEntry` 的名字承擔不了它實際代表的東西——它自己的三個下游
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


    /// #415：**正向送出的每一個 biblatex 型別，反向都必須收得回來**——除非它出現在
    /// 下面這份「刻意有損」的顯式清單裡。
    ///
    /// 這是把「哪些是刻意有損」從**讀者自己比對兩個 switch** 變成**必須顯式宣告**。
    /// #415 立案時只指名 `INREFERENCE`；實測差集是 **6 個**（`AUDIO`／`DATASET`／
    /// `IMAGE`／`INREFERENCE`／`SOFTWARE`／`VIDEO`）——全是 #352／#356 開始送 apa.dbx
    /// 型別時新增的，反向從未跟上。一份「我們自己寫的 .bib 讀不回型別」的清單，靠人
    /// 比對兩個 switch 是發現不了的。
    func testEveryForwardBiblatexTypeSurvivesTheRoundTrip() {
        // **刻意有損的原像多對一**：同一個 biblatex 型別由多個 WorkType 送出時，
        // 反向只能回到其中一個。取**較粗**的那個（既有慣例，見
        // `testInversePicksTheLeastRefinedPreimage`）。
        let deliberatelyLossy: [String: WorkType] = [
            "ARTICLE":  .periodicalArticle,   // 亦由 .review 送出
            "ONLINE":   .webpage,             // 亦由 .socialMediaPost 送出
            "SOFTWARE": .software,            // 亦由 .testInstrument 送出
        ]
        for t in WorkType.allCases {
            let fwd = t.biblatexEntryType
            let back = WorkType(biblatexEntryType: fwd, fields: [:])
            if let coarser = deliberatelyLossy[fwd] {
                XCTAssertEqual(back, coarser,
                               "\(fwd) 是多對一，反向必須回到較粗的 \(coarser)")
            } else {
                XCTAssertEqual(back, t,
                               "\(t) 送出 \(fwd)，反向必須收得回來——"
                               + "若這是刻意有損，請加進 deliberatelyLossy 並寫下理由")
            }
        }
    }

    // MARK: - §10.5 的兩種形狀（#417 方向 2）

    /// **帶 `booktitle` 的會議記錄要送 `INPROCEEDINGS`，不是 `PRESENTATION`**（#417）。
    ///
    /// `WorkType.conferenceSession` 覆蓋 APA7 §10.5 的兩種形狀，而正向先前一律送
    /// `PRESENTATION`——那個 template 印「Conference Name, Location」，所以一筆論文集
    /// 論文的**論文集名印不出來**（資訊在庫裡、也歸了 venue，只是不出現在參考文獻）。
    ///
    /// 判準是**記錄自己有沒有 `booktitle`**，與反向 init 的兩個既有先例同形
    /// （`misc` ＋ `url` → `referenceWorkEntry`；`unpublished` ＋ `location` →
    /// `conferenceSession`）。不是猜——`booktitle` 在場就是「這筆有論文集」的直接證據。
    ///
    /// **零實例，所以零輸出變更**：實測 37 筆 conference-session 全部沒有 booktitle。
    func testConferenceRecordWithBooktitleSendsInproceedings() {
        XCTAssertEqual(WorkType.conferenceSession.biblatexEntryType(fields: ["booktitle": "Proc. X"]),
                       "INPROCEEDINGS",
                       "有論文集名 → INPROCEEDINGS，否則論文集名印不出來")
        XCTAssertEqual(WorkType.conferenceSession.biblatexEntryType(fields: [:]),
                       "PRESENTATION", "沒有論文集名 → 維持會議發表")
        XCTAssertEqual(WorkType.conferenceSession.biblatexEntryType(fields: ["booktitle": "  "]),
                       "PRESENTATION", "空白字串不算有")
    }

    /// **其餘型別不受 fields 影響**——只有 `.conferenceSession` 是兩形狀合流的那個。
    func testOnlyConferenceSessionIsFieldsDependentOnTheForwardMap() {
        for t in WorkType.allCases where t != .conferenceSession {
            XCTAssertEqual(t.biblatexEntryType(fields: ["booktitle": "X", "publisher": "Y"]),
                           t.biblatexEntryType,
                           "\(t) 的正向對映不得依賴 fields——只有 §10.5 那個格子是合流的")
        }
    }

    /// **round-trip 仍成立**：`INPROCEEDINGS` 反向也回 `.conferenceSession`。
    func testInproceedingsRoundTripsBackToConferenceSession() {
        let bt = WorkType.conferenceSession.biblatexEntryType(fields: ["booktitle": "P"])
        XCTAssertEqual(WorkType(biblatexEntryType: bt, fields: [:]), .conferenceSession)
    }
}
