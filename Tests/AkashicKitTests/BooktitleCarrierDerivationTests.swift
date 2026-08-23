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
    /// 它留著是為了論文集那一種形狀——而那種形狀在 store 裡還沒有實例。
    ///
    /// **這條不主張該怎麼改**（拆成兩個型別？讓正向依 fields 選 `INPROCEEDINGS`？）
    /// ——那是建模裁決。它只把這個事實釘住，讓它不再是「沒人注意到的一致」。
    func testTheSingleExceptionPointsAtAConflation() {
        let contract = BibExport.fieldContract(WorkType.conferenceSession.biblatexEntryType)
        XCTAssertFalse(contract.contains("BOOKTITLE"),
                       "PRESENTATION 的契約若已含 BOOKTITLE，這個 conflation 就消失了——"
                       + "請一併更新 namedException 與這段說明：\(contract.sorted())")
        XCTAssertTrue(contract.contains("EVENTTITLE"),
                      "會議發表的容器是 eventtitle 不是 booktitle：\(contract.sorted())")
        XCTAssertTrue(VenueDerivation.booktitleCarrierTypes.contains(.conferenceSession),
                      "它仍在表裡——為了論文集那一種形狀（store 裡目前零實例）")
    }
}
