import XCTest
@testable import AkashicCore
@testable import AkashicExport
import BiblatexAPA

/// `WorkType` 的兩個下游對映必須互相同意（#352）。
///
/// `WorkType` 同時宣稱兩件事：
///
/// - `apa7Section` —— 這個型別在 APA7 手冊 ch10 的哪一節
/// - `biblatexEntryType` —— 匯出 `.bib` 時寫哪個 entry type
///
/// 而 `biblatex-apa` **自己也會從 entry type 算節**（`APADataModel.classifySection`，
/// 邏輯來自 `apa.dbx`）。所以我們送出去的 entry type 隱含了一個節，那個節必須與我們
/// 自己宣稱的節相同。
///
/// ## 為什麼這條守衛比「檢查必要欄位」更基本
///
/// 節決定 biblatex-apa 用哪一組排版規則。送錯 entry type 不只是欄位需求對不上——是
/// **整筆參考文獻被當成另一個類別排版**，而那個錯誤在 `.bib` 語法層完全合法、在
/// 必要欄位檢查裡也可能通過。
///
/// 實測（#352 開立時）：`dataSet` 與 `software` 都對映到 `REPORT`，於是依賴算出
/// **10.4**（Reports and Gray Literature），而它們自己宣稱 10.9／10.10；`review`
/// 對映到 `UNPUBLISHED` → **10.8**，而它宣稱 10.7。原始碼註解寫「biblatex 無專屬型，
/// REPORT 最近」——那句話是錯的，`DATASET`／`SOFTWARE` 都在 `apa.dbx` 的型別清單裡。
///
/// ## 這條守衛的邊界（誠實記錄）
///
/// 依賴的分類器對某些型別是**欄位相依**的（`SOFTWARE` 走 `classifySoftware`、`ONLINE`
/// 走 `classifyOnline`、`VIDEO` 在有 `RELATED`／`RELATEDTYPE` 時歸 10.7）。所以本測試
/// 餵的是**最小欄位**的探針 entry——它驗的是「預設路徑同意」，不是「所有欄位組合都同意」。
/// 後者需要每個型別的欄位矩陣，屬更大的題。
final class WorkTypeSectionAgreementTests: XCTestCase {

    /// **具名的節不同意**：這些型別送不出能讓依賴算對節的 entry type，因為那些節在
    /// `apa.dbx` 的模型裡**不是由 entry type 決定**的。
    ///
    /// ## #355 的裁決：判準是「這個值對這個型別是不是定義上為真」
    ///
    /// 三節都需要一個欄位配合，而問題從來不是「送不送得出欄位」，是**送出去會不會說謊**。
    /// 逐個裁決之後，三個變成兩個：
    ///
    /// | 型別 | 需要的欄位 | 裁決 |
    /// |---|---|---|
    /// | `review` | `RELATEDTYPE = reviewof` | ✅ **送**——定義上為真 |
    /// | `testInstrument` | `ENTRYSUBTYPE` 含 database／record，或 title 關鍵字 | ❌ 不送 |
    /// | `socialMediaPost` | `EPRINT` ＝平台名，或 `ENTRYSUBTYPE` 含 tweet／status… | ❌ 不送 |
    ///
    /// **`review` 為什麼可以送**：`.review` 這個型別的意思就是「這是一篇評論」，而
    /// 「評論某物」是它的**定義**，不是某筆記錄碰巧具備的性質。所以無條件補上
    /// `RELATEDTYPE = reviewof` 不是編造，是把型別已經聲明的事實寫進 `.bib`——與
    /// `not_applicable` 的 claim 限定詞「逐字取自 rationale 已經寫下的字」同型。
    /// 同時 `biblatexEntryType` 從 `UNPUBLISHED` 改成 `ARTICLE`（10.7 的條件是
    /// `ARTICLE`／`VIDEO`／`ONLINE` ＋該欄位）。
    ///
    /// **另兩個為什麼不能送**：它們斷言的是記錄的**出處**，而出處會錯。
    /// `ENTRYSUBTYPE: Database record` 對一份不是來自 PsycTESTS 的量表是假的；
    /// `EPRINT: Twitter` 對一則 Mastodon／Threads 貼文是假的。這與 #340 記載的紀律
    /// 同一條：「不得把 type 改成剛好讓 validator 閉嘴的值」——也不得為此編造欄位。
    ///
    /// ## 那兩個的達成路徑仍然存在，只是不由我們偽造
    ///
    /// `fields` 在 `BibExport.bibEntry` 是**原樣轉出**的。所以：
    ///
    /// - 一份 store 裡真的持有 `eprint = Mastodon` 的 `socialMediaPost`，其 `.bib`
    ///   會帶著它，依賴自然算出 10.15——**不需要我們做任何事**
    /// - 一份標題真的含 `Scale`／`Inventory` 的 `testInstrument`（實務上多數量表如此），
    ///   依賴的 title 啟發式會自然命中 10.11
    ///
    /// **同一個 `WorkType` 的記錄會依標題文字落到不同節**——這是依賴的分類器行為，
    /// 不是我們的選擇。我們既不偽造訊號，也不替它二次猜測；能做的是如實轉寫，
    /// 並把這個限制記在這裡。要根治需要上游給 10.11 一個專屬 entry type（#355 記載）。
    ///
    /// 斷言是**精確相等**（見 `testDisagreementsAreExactlyTheNamedTwo`）：這張表不是
    /// 豁免清單，往裡面加東西會讓另一條測試紅。
    private static let sectionDisagreementsNeedingFields: [WorkType: String] = [
        .testInstrument:  "10.11 無專屬 entry type；達成只能靠 title 關鍵字或 PsycTESTS 專屬欄位——後者對非該來源的量表為假，故不送。送 SOFTWARE（預設算成 10.10）",
        .socialMediaPost: "10.15 需 EPRINT 平台名；平台是**事實**不是型別的定義，store 持有時原樣轉出即可命中，我們不代填。送 ONLINE（預設算成 10.16）",
    ]

    /// 探針**走真正的匯出路徑**（`BibExport.bibEntry`），不是自己組一個 `BibEntry`。
    ///
    /// 先前是後者：只填 title／author／date 再直接帶上 `type.biblatexEntryType`。
    /// 那驗的是**型別對映**，不是**出貨的東西**——而 `bibEntry` 會補欄位（#335 的
    /// 學位論文事實、#355 的 `RELATEDTYPE`），補的欄位正好會改變依賴算出的節。
    /// 兩者分岔時，這條守衛會對著一個沒人會匯出的形狀報平安。
    ///
    /// 這與 #353 修掉的 `apa7CheckedTypes` 鏡像是同一種病：**測試自己造了一份與
    /// production 平行的資料**。
    private func probe(for type: WorkType) -> BibEntry {
        var entry = Entry(id: UUID(), citekey: "probe", type: type, title: "Probe Title")
        entry.date = "2020"
        entry.authors = [.literal("Probe, P.")]
        return BibExport.bibEntry(for: entry, people: [:])
    }

    /// **核心守衛**：每個 `WorkType` 送出的 entry type，經依賴自己的分類器算回來的節，
    /// 必須等於該型別宣稱的 `apa7Section`——除了上表具名的三個。
    func testEveryWorkTypeAgreesWithDependencySectionClassifier() throws {
        var unexpected: [String] = []
        for type in WorkType.allCases {
            let computed = APADataModel.classifySection(entry: probe(for: type)).number
            guard computed != type.apa7Section else { continue }
            guard Self.sectionDisagreementsNeedingFields[type] == nil else { continue }
            unexpected.append(
                "  \(type.rawValue): 宣稱 \(type.apa7Section)，"
                + "但 \(type.biblatexEntryType) 被依賴算成 \(computed)")
        }
        XCTAssertTrue(unexpected.isEmpty,
                      "以下 \(unexpected.count) 個型別的兩個下游對映互相矛盾，"
                      + "且**未列入**具名不同意表——送出去的 entry type 會讓 biblatex-apa "
                      + "用錯的類別排版：\n"
                      + unexpected.sorted().joined(separator: "\n"))
    }

    /// 節不同意的型別**恰好**是具名的那兩個——一個不多一個不少。
    ///
    /// 這條是上一個測試的另一半：那條問「有沒有新的不同意」，這條問「舊的有沒有被解決
    /// 卻沒人更新表」。少了它，那張表會腐爛成一份記錄著早已解決的問題的清單，而讀它的
    /// 人無從分辨哪些還成立。同時它也讓那張表**不能當豁免清單用**：往裡面加一個其實
    /// 已經同意的型別，這條會紅。
    func testDisagreementsAreExactlyTheNamedTwo() throws {
        var actual: Set<WorkType> = []
        for type in WorkType.allCases {
            let computed = APADataModel.classifySection(entry: probe(for: type)).number
            if computed != type.apa7Section { actual.insert(type) }
        }
        let named = Set(Self.sectionDisagreementsNeedingFields.keys)
        XCTAssertEqual(actual, named,
                       "具名不同意表與實際不一致。"
                       + "已解決卻仍列在表裡：\(named.subtracting(actual).map(\.rawValue).sorted())；"
                       + "實際不同意卻未列入：\(actual.subtracting(named).map(\.rawValue).sorted())")
    }

    /// 每個 `WorkType` 送出的 entry type 都必須是 `apa.dbx` 宣告過的。
    ///
    /// 抓的是「寫了一個依賴不認得的型別」——那種 `.bib` 丟進 LaTeX 會直接編譯失敗，
    /// 而在我們這一側沒有任何跡象。
    func testEveryEmittedEntryTypeIsDeclaredInApaDbx() throws {
        for type in WorkType.allCases {
            XCTAssertTrue(APADataModel.allEntryTypes.contains(type.biblatexEntryType),
                          "\(type.rawValue) 送出 \(type.biblatexEntryType)，"
                          + "但那不在 apa.dbx 的型別清單內")
        }
    }

    /// 具名不同意表的每一列都要寫出理由（非空）。
    ///
    /// 只有型別沒有理由的一列，日後讀的人無從判斷它為什麼在那裡——而那正是這張表
    /// 退化成豁免清單的第一步。
    func testEveryNamedDisagreementCarriesAReason() throws {
        for (type, reason) in Self.sectionDisagreementsNeedingFields {
            XCTAssertFalse(reason.trimmingCharacters(in: .whitespaces).isEmpty,
                           "\(type.rawValue) 列在具名不同意表裡但沒寫理由")
        }
    }

    // MARK: - #355 的三個裁決，各自的正面斷言

    /// `.review` **真的**落到 10.7，而且是靠 `RELATEDTYPE` 落過去的。
    ///
    /// **這條不能省**：把 `.review` 從具名不同意表裡拿掉，`testDisagreementsAreExactly…`
    /// 就不會再點名它——但那只證明「它不再不同意」，**不證明它同意到對的地方**。
    /// 若哪天 `biblatexEntryType` 被改回一個碰巧也算成 10.7 的型別、或 `RELATEDTYPE`
    /// 的補值被拿掉而型別剛好落對，這條會抓到；上面那兩條不會。
    func testReviewReachesSectionTenSevenThroughRelatedType() throws {
        let bib = probe(for: .review)
        XCTAssertEqual(bib.entryType.uppercased(), "ARTICLE")
        let relType = bib.fields.keys.first { $0.lowercased() == "relatedtype" }
            .flatMap { bib.fields[$0] }
        XCTAssertEqual(relType?.lowercased(), "reviewof",
                       "`.review` 必須無條件帶 RELATEDTYPE=reviewof——那是型別的定義，"
                       + "不是碰巧具備的性質")
        XCTAssertEqual(APADataModel.classifySection(entry: bib).number, "10.7")
    }

    /// 記錄自己帶的 `relatedtype` **不被覆寫**。
    ///
    /// 補值的正當性建立在「這個值對這個型別定義上為真」，而不是「我們知道得比來源多」。
    /// 來源若寫了別的（例如 `reviewof` 之外的關係詞），那是它的斷言，不是我們的。
    func testExistingRelatedTypeIsNotOverwritten() throws {
        var entry = Entry(id: UUID(), citekey: "r", type: .review, title: "T")
        entry.fields["relatedtype"] = "commenton"
        let bib = BibExport.bibEntry(for: entry, people: [:])
        let relType = bib.fields.keys.first { $0.lowercased() == "relatedtype" }
            .flatMap { bib.fields[$0] }
        XCTAssertEqual(relType, "commenton", "既有值優先——補值不得改寫來源的斷言")
    }

    /// **不得**為了讓分類器算出 10.11／10.15 而自動補欄位。
    ///
    /// 這條斷言的是**缺席**，而缺席正是 #355 兩個「不送」裁決的全部內容。沒有它，
    /// 下一個想讓守衛全綠的人只要在 `bibEntry` 加兩行就過了，而那兩行送出去的是假話。
    func testNoFabricatedFieldsForTestInstrumentOrSocialMediaPost() throws {
        for type in [WorkType.testInstrument, .socialMediaPost] {
            let bib = probe(for: type)
            let keys = Set(bib.fields.keys.map { $0.uppercased() })
            XCTAssertFalse(keys.contains("ENTRYSUBTYPE"),
                           "\(type.rawValue)：ENTRYSUBTYPE 斷言的是記錄的出處，"
                           + "對非該來源的記錄為假——不得自動補")
            XCTAssertFalse(keys.contains("EPRINT"),
                           "\(type.rawValue)：EPRINT 是平台**事實**，store 持有時原樣"
                           + "轉出即可，不得代填")
        }
    }

    /// 反面：store **真的**持有平台事實時，原樣轉出就會落到 10.15——**不需要我們做任何事**。
    ///
    /// 這條與上一條合起來才完整：上一條說「不偽造」，這條說「不偽造不等於做不到」。
    /// 少了它，那兩個裁決讀起來像放棄。
    func testSocialMediaPostReachesTenFifteenWhenTheStoreHoldsThePlatform() throws {
        var entry = Entry(id: UUID(), citekey: "s", type: .socialMediaPost, title: "T")
        entry.fields["eprint"] = "Twitter"
        let bib = BibExport.bibEntry(for: entry, people: [:])
        XCTAssertEqual(APADataModel.classifySection(entry: bib).number, "10.15",
                       "平台事實在場時，如實轉寫就足以落到 10.15")
    }

    /// **但「如實轉寫就夠」只對依賴認得的平台成立。**
    ///
    /// 依賴的 `classifyOnline` 用一份**寫死的封閉平台清單**
    /// （twitter／facebook／instagram／reddit／tumblr／linkedin／tiktok）。
    /// 一則 Mastodon／Threads／Bluesky 貼文即使 `eprint` 完全屬實，仍落 10.16。
    ///
    /// 這條斷言**現況**（同 #359 的 `testRemovingEventTitleIsOnlyAWarningToday` 形式）：
    /// 它會在上游擴充清單時變紅，提醒回來更新裁決。
    ///
    /// **這個發現強化了「不送」的裁決**：連如實轉寫都不保證命中，那麼為了命中而編造
    /// `EPRINT: Twitter` 就更不可接受——那會讓一則 Mastodon 貼文的參考文獻**說它來自
    /// Twitter**，錯誤從分類層下沉到內容層。
    func testAPlatformOutsideTheDependencyListStillMissesTenFifteenToday() throws {
        var entry = Entry(id: UUID(), citekey: "s2", type: .socialMediaPost, title: "T")
        entry.fields["eprint"] = "Mastodon"
        let bib = BibExport.bibEntry(for: entry, people: [:])
        XCTAssertEqual(APADataModel.classifySection(entry: bib).number, "10.16",
                       "現況：依賴的平台清單是封閉的寫死列舉，Mastodon 不在其中。"
                       + "**這條變紅代表上游擴充了清單** —— 那時請更新 #355 的裁決記載")
    }

    /// 同上，`testInstrument` 走依賴的 title 啟發式——實務上多數量表的標題含
    /// `Scale`／`Inventory`，所以「部分達成」在真實資料上覆蓋率不低。
    func testTestInstrumentReachesTenElevenWhenTheTitleSaysSo() throws {
        var entry = Entry(id: UUID(), citekey: "t", type: .testInstrument,
                          title: "Beck Depression Inventory")
        entry.date = "1996"
        let bib = BibExport.bibEntry(for: entry, people: [:])
        XCTAssertEqual(APADataModel.classifySection(entry: bib).number, "10.11",
                       "標題真的說了它是 inventory —— 依賴的啟發式自然命中，"
                       + "我們沒有補任何欄位")
    }
}
