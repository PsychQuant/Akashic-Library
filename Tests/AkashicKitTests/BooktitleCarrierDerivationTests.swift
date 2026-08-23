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
    /// **判準只排除 `EDITOR`。曾經多一個 `¬PUBLISHER`，那是錯的**（#417 R1，被測試抓到）。
    ///
    /// 跨模型審查問「這個謂詞會不會只是碰巧套上現表」，我實測了四個變體：
    ///
    ///     BT ∧ ¬EDITOR                → {referenceWorkEntry}   ← **現行**
    ///     BT ∧ ¬EDITOR ∧ ¬PUBLISHER  → {referenceWorkEntry}   ← 曾經用這個
    ///     BT ∧ ¬PUBLISHER             → {referenceWorkEntry}
    ///     ¬EDITOR ∧ ¬PUBLISHER（不要求 BT）→ 14 個型別          ← 顯然過寬
    ///
    /// 前三個在**當前型別集合上答案相同**，因為只有 `INCOLLECTION` 與 `INREFERENCE`
    /// 的契約含 `BOOKTITLE`，而 `INCOLLECTION` 同時含 `EDITOR` 與 `PUBLISHER`。
    /// 我當時據此說「兩個子句都留著，各自對應一個真的案例」，並拿
    /// `INPROCEEDINGS`（含 `PUBLISHER` 不含 `EDITOR`）當 `¬PUBLISHER` 的正當理由。
    ///
    /// **那個理由與我自己兩輪前的量測矛盾。** `#414` 的量測已經記過：出版社**不是**
    /// 「venue 持不住」的東西——`VenueType` 就有 `.publisher`，而
    /// `VenueDerivation.literals` 的第三個分支**無條件**把 publisher 變成另一個 venue
    /// literal。論文集論文因此得到**兩個** venue（會議一個、出版社一個），而不是
    /// 「因為有出版社所以不能有 venue」。
    ///
    /// `VenueMigrationTests.testProceedingsBooktitleAndPublisher` 逐字釘住這個行為
    /// （期望 `[.literal("Proc. of Great Conf"), .literal("Some Press")]`），而它正是
    /// 抓到這個錯誤的那條測試——我依 `¬PUBLISHER` 把 `.conferenceSession` 移出表，
    /// 它立刻紅。
    ///
    /// **`EDITOR` 是唯一真的「持不住」**：`Venue` 沒有編者欄位，也沒有任何分支把編者
    /// 變成別的東西。#324 排除編著的原始理由就是這一條。
    ///
    private func derivedMembership(_ t: WorkType) -> Bool {
        let contract = BibExport.fieldContract(t.biblatexEntryType)
        return contract.contains("BOOKTITLE") && !contract.contains("EDITOR")
    }

    /// **具名的例外，只有一個**——不得依性質相似類推第二個。
    ///
    /// `.conferenceSession` 的契約（`PRESENTATION`）**完全沒有 `BOOKTITLE`**，所以
    /// 謂詞說它不是成員，而表說它是。這個不合**不是謂詞壞了**，它指向一個真的建模
    /// 缺口，見下方 `testTheSingleExceptionPointsAtAConflation`。
    /// **具名的例外，只有一個**——不得依性質相似類推第二個。
    ///
    /// `.conferenceSession` 的契約（`PRESENTATION`）**完全沒有 `BOOKTITLE`**，所以
    /// 謂詞說它不是成員，而表說它是。
    ///
    /// **這個不合是謂詞的極限，不是表的錯**（#417 R1 更正）：`WorkType.conferenceSession`
    /// 覆蓋 APA7 §10.5 的**兩種**形狀（會議發表／論文集論文），而正向只送
    /// `PRESENTATION`——那個契約只描述其中一種。模型**刻意支援**帶 `booktitle` 的
    /// conference-session 記錄（`VenueBootstrapTests` 與 `VenueMigrationTests` 各有
    /// 一條釘住），所以欄位契約對這個型別是**不完整的 oracle**。
    ///
    /// 我曾據謂詞把它移出表，兩條測試立刻紅——那是系統正常運作，記在這裡免得重犯。
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
    /// §10.5 同時涵蓋「會議發表」（有 `eventtitle`／`venue`，**沒有** booktitle）與
    /// 「論文集中的論文」（**有** booktitle）。`WorkType` 只有一個格子給它們，正向
    /// 一律送 `PRESENTATION`，而那個契約只描述前者。
    ///
    /// ## 為什麼這使欄位契約對這個型別成為不完整的 oracle
    ///
    /// 模型**刻意支援**帶 `booktitle` 的 conference-session 記錄——兩條既有測試釘住：
    ///
    /// - `VenueBootstrapTests.testBooktitleYieldsConferenceOnlyForConferenceSessions`
    ///   （`.conferenceSession` ＋ booktitle → `.conference` 候選）
    /// - `VenueMigrationTests.testProceedingsBooktitleAndPublisher`
    ///   （期望 `[.literal("Proc. of Great Conf"), .literal("Some Press")]`——
    ///   **會議與出版社各自成為一個 venue**）
    ///
    /// 第二條同時是本檔判準修正的來源：我曾以「`INPROCEEDINGS` 含 `PUBLISHER`」為由把
    /// `.conferenceSession` 移出 `booktitleCarrierTypes`，它立刻紅。出版社**不是**
    /// venue 持不住的東西——它自己就是一個 venue。
    ///
    /// 本條因此斷言**兩件都成立**：契約缺 `BOOKTITLE`（所以謂詞說不是成員），
    /// 而表**仍然**收它（因為模型支援的形狀比契約描述的多）。哪一邊變了都要回來重讀。
    func testTheExceptionIsTheContractBeingAnIncompleteOracle() {
        let contract = BibExport.fieldContract(WorkType.conferenceSession.biblatexEntryType)
        XCTAssertFalse(contract.contains("BOOKTITLE"),
                       "PRESENTATION 的契約若已含 BOOKTITLE，這個例外就消失了——"
                       + "請一併更新 namedException 與這段說明：\(contract.sorted())")
        XCTAssertTrue(contract.contains("EVENTTITLE"),
                      "會議發表的容器是 eventtitle：\(contract.sorted())")
        XCTAssertTrue(VenueDerivation.booktitleCarrierTypes.contains(.conferenceSession),
                      "它必須留在表裡——論文集論文的 booktitle 是載體，"
                      + "VenueMigrationTests.testProceedingsBooktitleAndPublisher 釘住這件事")

        // **`INPROCEEDINGS` 不含 `EDITOR`**——所以若正向哪天改送它，現行判準
        // （`BOOKTITLE ∧ ¬EDITOR`）會**自動**接受它，例外可以移除。釘住這一點，
        // 因為它是這個例外的退場條件。
        let proceedings = BibExport.fieldContract("INPROCEEDINGS")
        XCTAssertTrue(proceedings.contains("BOOKTITLE"), "\(proceedings.sorted())")
        XCTAssertFalse(proceedings.contains("EDITOR"),
                       "INPROCEEDINGS 不含 EDITOR，所以它符合現行判準——"
                       + "正向改送它的那天，namedException 可以清空：\(proceedings.sorted())")
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
