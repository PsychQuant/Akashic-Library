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
    /// 三節的達成條件（讀依賴的 `classifySection` 得出）：
    ///
    /// | 節 | 需要 | 為何不能只改型別 |
    /// |---|---|---|
    /// | 10.7 Reviews | `RELATEDTYPE = reviewof` | 只有 `ARTICLE`／`VIDEO`／`ONLINE` ＋該欄位 |
    /// | 10.11 Tests, Scales | `ENTRYSUBTYPE` 含 database／record，或 title 含 scale／inventory… | **無專屬 entry type** |
    /// | 10.15 Social Media | `EPRINT` ＝平台名，或 `ENTRYSUBTYPE` 含 tweet／status… | 只有 `ONLINE` ＋該欄位 |
    ///
    /// **為什麼不送那些欄位。** 送出去就能讓這張表清空、讓守衛全綠——但那是**為了讓
    /// 分類器高興而編造資料**。`ENTRYSUBTYPE: Database record` 對一份不是來自
    /// PsycTESTS 的量表是假的；`EPRINT: Twitter` 對一則 Mastodon 貼文是假的。這與 #340
    /// 記載的紀律同一條：「不得把 type 改成剛好讓 validator 閉嘴的值」——也不得為此編造
    /// 欄位。裁決追蹤：**#355**。
    ///
    /// 斷言是**精確相等**（見 `testDisagreementsAreExactlyTheNamedThree`）：這張表不是
    /// 豁免清單，往裡面加東西會讓另一條測試紅。
    private static let sectionDisagreementsNeedingFields: [WorkType: String] = [
        .review:          "10.7 需 RELATEDTYPE=reviewof；現送 UNPUBLISHED（算成 10.8）",
        .testInstrument:  "10.11 無專屬 entry type，需 ENTRYSUBTYPE 或 title 關鍵字；現送 SOFTWARE（算成 10.10）",
        .socialMediaPost: "10.15 需 EPRINT 平台名或 ENTRYSUBTYPE；現送 ONLINE（算成 10.16）",
    ]

    private func probe(for type: WorkType) -> BibEntry {
        var fields = OrderedDict()
        fields["title"] = "Probe Title"
        fields["author"] = "Probe, P."
        fields["date"] = "2020"
        return BibEntry(entryType: type.biblatexEntryType, key: "probe",
                        fields: fields, rawText: "", lineNumber: 0)
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

    /// 節不同意的型別**恰好**是具名的那三個——一個不多一個不少。
    ///
    /// 這條是上一個測試的另一半：那條問「有沒有新的不同意」，這條問「舊的有沒有被解決
    /// 卻沒人更新表」。少了它，那張表會腐爛成一份記錄著早已解決的問題的清單，而讀它的
    /// 人無從分辨哪些還成立。同時它也讓那張表**不能當豁免清單用**：往裡面加一個其實
    /// 已經同意的型別，這條會紅。
    func testDisagreementsAreExactlyTheNamedThree() throws {
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
}
