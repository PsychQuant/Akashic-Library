import XCTest
@testable import AkashicCore
@testable import AkashicExport

/// `booktitleCarrierTypes` 的成員資格判準有沒有程式層對應物（#414 方向 1）。
///
/// ## #414 問的是什麼
///
/// 那個集合的 doc comment 用 APA7 §11 的判準——「**它決定了哪些欄位存在**」——說明
/// 為什麼收 `.conferenceSession` 與 `.referenceWorkEntry`、不收 `.bookChapter`。
/// 跨模型審查指出：**那個判準沒有任何程式層的對應物**，集合只是一張人工列舉，
/// 成員資格只看 `type`。於是「不得依性質相似類推第三個」這條禁令**防不住它自己要防
/// 的事**——下一個線上百科／辭典型別仍只能靠人判斷「像不像」。
///
/// ## 我先前說它需要第三張表，那是錯的
///
/// 開案時的判斷是：要讓成員資格由欄位契約**推導**，得新增一張「每個 `WorkType` 的
/// 必要欄位」表，而 `apa7-is-the-work-floor` 已記過「三張必要欄位表會各自分岔」
/// （`BibValidator` 的、`APADataModel` 的、我們自己的）。
///
/// **實測推翻了那個前提**：既有的 `requiredFields(for:)` ＋ `recommendedFields(for:)`
/// 就能區辨——
///
///     bookChapter        → INCOLLECTION | req=AUTHOR,TITLE,BOOKTITLE,DATE | rec=EDITOR,PUBLISHER,PAGES
///     referenceWorkEntry → INREFERENCE  | req=TITLE,BOOKTITLE,DATE        | rec=AUTHOR,URL
///     conferenceSession  → PRESENTATION | req=AUTHOR,TITLE,DATE           | rec=EVENTTITLE,VENUE
///
/// 所以判準是可推導的，**不需要新表**。這條測試就是那個對應物。
///
/// ## 為什麼守衛住在測試而不是產品程式
///
/// `VenueDerivation` 在 `AkashicCore`，欄位契約在 `AkashicExport`（它依賴
/// `biblatex-apa`）。讓 core 去讀 export 層會把依賴方向倒過來。測試可以同時 import
/// 兩者，所以判準在這裡**可檢查**，而集合本身維持人工維護——這正是 #414 要的：
/// 判準有對應物，不是集合被自動生成。
final class BooktitleCarrierDerivationTests: XCTestCase {

    /// 由欄位契約推導的成員資格。
    ///
    /// - 契約含 `BOOKTITLE` ＝ 這個型別的書目形狀裡真的有一個容器欄位
    /// - 契約**不含** `EDITOR`／`PUBLISHER` ＝ 那個容器可以由 `Venue` 承載
    ///   （`Venue` 沒有編者欄位；出版社雖有 `VenueType.publisher`，但編著的
    ///   `BOOKTITLE + EDITOR + PUBLISHER` 三件套是 #324 明文關掉的那條路）
    /// **兩個排除子句互為冗餘，而兩者都有理由在**（#414 R2 量測）。
    ///
    /// 跨模型審查問：「這個謂詞會不會只是碰巧套上現表？」實測三個變體：
    ///
    ///     BT ∧ ¬EDITOR ∧ ¬PUBLISHER  → {referenceWorkEntry}   ← 現行
    ///     BT ∧ ¬EDITOR                → {referenceWorkEntry}   ← 同
    ///     BT ∧ ¬PUBLISHER             → {referenceWorkEntry}   ← 同
    ///     ¬EDITOR ∧ ¬PUBLISHER（不要求 BT）→ 14 個型別          ← 顯然過寬
    ///
    /// 三個要求 `BOOKTITLE` 的變體**答案相同**——因為現在只有兩個型別的契約含
    /// `BOOKTITLE`（`INCOLLECTION` 與 `INREFERENCE`），而 `INCOLLECTION` 同時含
    /// `EDITOR` 與 `PUBLISHER`，任一個子句單獨都排得掉它。
    ///
    /// **兩個子句都留著，因為它們各自對應一個真的案例**：`EDITOR` 排的是編著
    /// （#324 的原始裁決）；`PUBLISHER` 排的是**論文集**（`INPROCEEDINGS` 含
    /// `PUBLISHER` 但**不含** `EDITOR`——見 `testTheSingleExceptionPointsAtAConflation`）。
    /// 只留一個的話，另一個案例會在它出現時安靜通過。
    ///
    /// **這是「同樣合理的謂詞會得到不同答案嗎」的答案：不會**——收窄到三個合理變體
    /// 內，它們一致。差異只出現在把 `BOOKTITLE` 要求拿掉的那個，而那不合理
    /// （它會讓每個型別都變成 booktitle 載體）。
    private func derivedMembership(_ t: WorkType) -> Bool {
        let contract = BibExport.fieldContract(t.biblatexEntryType)
        return contract.contains("BOOKTITLE")
            && !contract.contains("EDITOR")
            && !contract.contains("PUBLISHER")
    }

    /// **具名的例外，只有一個**——不得依性質相似類推第二個。
    ///
    /// `.conferenceSession` 的契約（`PRESENTATION`）**完全沒有 `BOOKTITLE`**，所以
    /// 謂詞說它不是成員，而表說它是。這個不合**不是謂詞壞了**，它指向一個真的建模
    /// 缺口，見下方 `testTheSingleExceptionPointsAtAConflation`。
    private let namedException: Set<WorkType> = [.conferenceSession]

    /// **判準與表逐型別一致**（例外除外）。
    ///
    /// 這是 #414 要的東西：判準從一句散文變成一個可以跑的謂詞。日後有人加第三個成員
    /// 而它的欄位契約不支持，這條會紅。
    func testDerivedMembershipAgreesWithTheHandMaintainedTable() {
        var mismatches: [String] = []
        for t in WorkType.allCases where !namedException.contains(t) {
            let derived = derivedMembership(t)
            let actual = VenueDerivation.booktitleCarrierTypes.contains(t)
            if derived != actual {
                mismatches.append("\(t)（\(t.biblatexEntryType)）：推導=\(derived) 表=\(actual)"
                                  + " 契約=\(BibExport.fieldContract(t.biblatexEntryType).sorted())")
            }
        }
        XCTAssertEqual(mismatches, [],
                       "欄位契約與 booktitleCarrierTypes 不一致——"
                       + "要嘛表錯了，要嘛這是一個新的例外（那要在 namedException 具名並寫下理由）")
    }

    /// **例外清單不得空轉**：具名的例外必須真的是例外，否則它是一個沒人發現已經失效的豁免。
    ///
    /// 這道自檢是必要的——若 `PRESENTATION` 的契約日後加上 `BOOKTITLE`，上面那條會照樣
    /// 綠（因為 `.conferenceSession` 被跳過），而豁免已經沒有理由存在。
    func testTheNamedExceptionIsStillAnException() {
        for t in namedException {
            XCTAssertNotEqual(derivedMembership(t),
                              VenueDerivation.booktitleCarrierTypes.contains(t),
                              "\(t) 已不再是例外——請從 namedException 移除，"
                              + "上面那條測試會接手")
        }
    }

    /// 那個例外指向什麼：`.conferenceSession` 把 APA7 §10.5 的兩種形狀併成一個型別。
    ///
    /// §10.5 同時涵蓋「會議發表」（有 eventtitle／venue，**沒有** booktitle）與
    /// 「論文集中的論文」（**有** booktitle）。`WorkType` 只有一個格子給它們，正向
    /// 一律送 `PRESENTATION`，而 `PRESENTATION` 的欄位契約沒有 `BOOKTITLE`。
    ///
    /// 兩個實測互相印證：
    ///
    /// - 契約層：`PRESENTATION` 的 req ∪ rec 不含 `BOOKTITLE`（本測試斷言）
    /// - 資料層：37 筆 `conference-session` **零筆**帶 booktitle（#414 R1 量測），
    ///   它們用的是 `eventtitle`(33)／`venue`(12)／`location`(24)
    ///
    /// 也就是說 `.conferenceSession` 在本表裡的成員資格**目前對任何一筆記錄都不生效**。
    ///
    /// ## 而它在「論文集那一種形狀」下**也不成立**（2026-08-24 量測，比原本的說法更尖）
    ///
    /// 我先前寫「它留著是為了論文集那一種形狀」。量了才知道那個理由也站不住：
    ///
    ///     INPROCEEDINGS 的契約 = AUTHOR, BOOKTITLE, DATE, PUBLISHER, TITLE
    ///
    /// **含 `PUBLISHER`** ——所以在本檔的推導謂詞下它一樣不合格，理由與 #324 排除
    /// `INCOLLECTION` 的完全相同：容器規格索取的欄位 venue 持不住。
    ///
    /// 換句話說 `.conferenceSession` 的成員資格在**兩種讀法下都不成立**：
    ///
    /// | 讀法 | 契約 | 謂詞 |
    /// |---|---|---|
    /// | 現行（送 `PRESENTATION`）| 沒有 `BOOKTITLE` | ❌ 成員資格空轉 |
    /// | 假想（論文集送 `INPROCEEDINGS`）| 有 `BOOKTITLE` **但也有 `PUBLISHER`** | ❌ 與 `INCOLLECTION` 同理被排除 |
    ///
    /// **這條仍不主張該怎麼改**——把它從表裡拿掉是行為變更（雖然當下零實例），
    /// 而那是 #417 的裁決。它只把「兩種讀法都不成立」這件事釘住，讓那個豁免不再
    /// 讀起來像「暫時保留給一個合理的未來形狀」。
    func testTheSingleExceptionPointsAtAConflation() {
        let contract = BibExport.fieldContract(WorkType.conferenceSession.biblatexEntryType)
        XCTAssertFalse(contract.contains("BOOKTITLE"),
                       "PRESENTATION 的契約若已含 BOOKTITLE，這個 conflation 就消失了——"
                       + "請一併更新 namedException 與這段說明：\(contract.sorted())")
        XCTAssertTrue(contract.contains("EVENTTITLE"),
                      "會議發表的容器是 eventtitle 不是 booktitle：\(contract.sorted())")
        XCTAssertTrue(VenueDerivation.booktitleCarrierTypes.contains(.conferenceSession),
                      "它仍在表裡——裁決在 #417")

        // **論文集那條路也不合格**——這是上面那張表的第二列，釘住它免得日後有人
        // 拿「留給論文集」當理由把豁免延長下去。
        let proceedings = BibExport.fieldContract("INPROCEEDINGS")
        XCTAssertFalse(proceedings.isEmpty,
                       "依賴應該認得 INPROCEEDINGS——不認得的話這個對照就無從做起")
        XCTAssertTrue(proceedings.contains("BOOKTITLE"), "\(proceedings.sorted())")
        XCTAssertTrue(proceedings.contains("PUBLISHER"),
                      "INPROCEEDINGS 含 PUBLISHER，所以論文集論文在本謂詞下與 INCOLLECTION "
                      + "同樣不是 booktitle 載體：\(proceedings.sorted())")
    }

    // MARK: - venue 的身分同一性對匯出無影響（#414 附帶項）

    /// **`.bib` 的欄位只來自 `entry.fields`，venue 記錄一律不查**。
    ///
    /// #414 附帶指出一個沒被證成過的身分假設：中文與英文 Wikipedia 被建成**同一個**
    /// venue 的兩個名稱變體，而它們是不同語言版的獨立計畫。
    ///
    /// 名字以外的證據**確實區分得出來**（`identity-is-judged-not-matched` 要的那種）：
    ///
    ///     4 筆  en.wikipedia.org  langid=en     booktitle=Wikipedia, the free encyclopedia
    ///    10 筆  zh.wikipedia.org  langid=zh-TW  booktitle=維基百科，自由的百科全書
    ///
    /// **但這個測試釘住的是：那個身分判斷對參考文獻的正確性沒有影響。**
    /// `BibExport.bibEntry` 逐鍵轉出 `entry.fields`，從不讀 `entry.venues` 指向的
    /// venue 記錄——所以一筆中文條目印出來的 `BOOKTITLE` 永遠是它自己 `fields` 裡的
    /// 「維基百科，自由的百科全書」，不論它歸戶到哪個 venue key。
    ///
    /// 這把一個開放的建模問題降級成**低風險**的：合或不合都不會印錯。真要拆的話
    /// `resolve-venues` 的 verdict 機制本來就支援，而**這條會在有人改成從 venue 取
    /// 名字時變紅**——那時身分判斷才開始有後果。
    func testExportReadsBooktitleFromFieldsNotFromTheVenueRecord() {
        var zh = Entry(id: UUID(), citekey: "zh2020a", type: .referenceWorkEntry, title: "條目")
        zh.fields["booktitle"] = "維基百科，自由的百科全書"
        zh.venues = [.key("wikipedia")]          // 歸到與英文版共用的那個 key
        let bib = BibExport.bibEntry(for: zh, people: [:], organizations: [:])
        XCTAssertEqual(bib.fields["booktitle"], "維基百科，自由的百科全書",
                       "BOOKTITLE 必須來自這一筆自己的 fields，不得由 venue 記錄決定")

        // 反向：venue key 不出現在任何欄位裡——它不是書目資料。
        XCTAssertFalse(bib.fields.pairs.contains { $0.value.contains("wikipedia") },
                       "venue key 不得洩進 .bib 欄位：\(bib.fields.pairs)")
    }

    /// **謂詞把「依賴沒有意見」當成「沒有 BOOKTITLE」**——一個安靜的合流（#414 R2）。
    ///
    /// 實測兩個型別的契約是**空的**：
    ///
    ///     unpublishedWork → UNPUBLISHED: []
    ///     visualWork      → IMAGE:       []
    ///
    /// 對它們，`contract.contains("BOOKTITLE")` 回 false ——謂詞於是給出「不是成員」
    /// 這個**有信心的答案**，而它的依據其實是「查無資料」。兩者在輸出上完全一樣。
    ///
    /// **當下兩者答案相同**（那兩個型別確實不該是 booktitle 載體），所以這不是缺陷，
    /// 是一個**已知的推理弱點**。釘住它的理由與 `zero-instance-guards` 第 3 列同源
    /// （「未涵蓋不得冒充通過」）：日後若有型別的契約是空的**而它其實該是成員**，
    /// 謂詞會安靜地說不是。
    ///
    /// 這條在空契約集合改變時變紅，逼人回來重讀這一段。
    func testThePredicateConflatesEmptyContractWithNoBooktitle() {
        let empties = WorkType.allCases.filter {
            BibExport.fieldContract($0.biblatexEntryType).isEmpty
        }
        XCTAssertEqual(Set(empties.map(\.rawValue)), ["unpublished-work", "visual-work"],
                       "空契約的型別集合變了——請重讀本段：謂詞對它們的『不是成員』"
                       + "是查無資料而非查到沒有：\(empties)")
        for t in empties {
            XCTAssertFalse(VenueDerivation.booktitleCarrierTypes.contains(t),
                           "\(t) 契約是空的卻在表裡——那個成員資格沒有任何契約依據")
        }
    }
}
