import Foundation

/// 作品類型的封閉列舉（#325 階段二）。值域**細分** APA7 手冊 ch10 的 16 節。
///
/// ## 判準（依 `.claude/rules/apa7-is-the-work-floor.md`）
///
/// 「分類權威＝**細分關係，不是相等**」：
///
/// - 每個值對映到**恰好一個** ch10 節（`apa7Section`）——保證 APA7 匯出永遠可行
/// - **多個值可以對映到同一節**：專案有權比 APA7 分得更細
/// - **更細可以，更粗不行**
///
/// 更粗不行的理由是具體的：兩個 ch10 節的欄位組不同（§9.24），混進同一個值後就無法
/// 判斷該索取哪一組。舊值域的 `unpublished` 正是那個形狀——它橫跨 10.5 與 10.8。
///
/// ## `wikipedia-entry` 是「細分」的第一個具名實例
///
/// 它在 APA7 落在 **10.3**（Edited Book Chapters and Entries in Reference Works，
/// 例 49），與 `book-chapter` 同節。但在本專案它是獨立且高頻的類型（實測 14 筆），
/// **值得自己的格子**——使用者 2026-08-19 裁定：「我們沒有必要要完全照 APA7，而是
/// 我們**包含**他」。
///
/// ## 為什麼是兩階段
///
/// `Entry.type` 曾是自由 `String` 且 decode 不驗。若直接改嚴格，937 筆現有記錄會在
/// 新 binary 上線的那一刻全部 quarantine（而 `query` 回 rc=0、無訊息）。所以
/// `migrate-work-types`（階段一）**必須先跑完**——本型別是階段二。
public enum WorkType: String, CaseIterable, Equatable, Sendable {
    // ── Textual Works ──
    /// 10.1 Periodicals——**涵蓋 journal／magazine／newspaper／newsletter／blog**。
    /// 名字不叫 `journal-article` 是刻意的：APA7 的 periodical 是那五者的**同一類**
    /// （索取同一組欄位），叫 journal 會讓下一個人以為報紙要另立一格——與 #324 對
    /// `VenueType.periodical` 的更名同一個理由。實測 Zotero 對映表把
    /// `magazineArticle`／`newspaperArticle` 都壓成 `article`，那個壓縮本來就發生了，
    /// 只是舊名字掩蓋了它。
    case periodicalArticle  = "periodical-article"   // 10.1 Periodicals
    case book                                        // 10.2 Books and Reference Works
    case bookChapter        = "book-chapter"         // 10.3 Edited Book Chapters
    case wikipediaEntry     = "wikipedia-entry"      // 10.3（細分——例 49）
    case report                                      // 10.4 Reports and Gray Literature
    case conferenceSession  = "conference-session"   // 10.5 Conference Sessions
    case thesis                                      // 10.6 Dissertations and Theses
    case review                                      // 10.7 Reviews
    case unpublishedWork    = "unpublished-work"     // 10.8 Unpublished / Informally Published
    // ── Data Sets, Software, Tests ──
    case dataSet            = "data-set"             // 10.9 Data Sets
    case software                                    // 10.10 Software / Apps / Apparatuses
    case testInstrument     = "test-instrument"      // 10.11 Tests, Scales, and Inventories
    // ── Audiovisual Media ──
    case audiovisualWork    = "audiovisual-work"     // 10.12 Audiovisual Works
    case audioWork          = "audio-work"           // 10.13 Audio Works
    case visualWork         = "visual-work"          // 10.14 Visual Works
    // ── Online Media ──
    case socialMediaPost    = "social-media-post"    // 10.15 Social Media
    case webpage                                     // 10.16 Webpages and Websites

    /// 這個值對映到的 APA7 ch10 節號。
    ///
    /// **每個值都必須有**——沒有節號的值就沒有判準，也就無從保證 APA7 匯出可行。
    /// `WorkTypeTests.testEveryCaseDeclaresItsAPA7Section` 釘住這條。
    public var apa7Section: String {
        switch self {
        case .periodicalArticle: return "10.1"
        case .book:              return "10.2"
        case .bookChapter:       return "10.3"
        case .wikipediaEntry:    return "10.3"   // 與 bookChapter 同節——細分的實例
        case .report:            return "10.4"
        case .conferenceSession: return "10.5"
        case .thesis:            return "10.6"
        case .review:            return "10.7"
        case .unpublishedWork:   return "10.8"
        case .dataSet:           return "10.9"
        case .software:          return "10.10"
        case .testInstrument:    return "10.11"
        case .audiovisualWork:   return "10.12"
        case .audioWork:         return "10.13"
        case .visualWork:        return "10.14"
        case .socialMediaPost:   return "10.15"
        case .webpage:           return "10.16"
        }
    }

    /// 這個值在 biblatex 的 entry type（`@ARTICLE` 等）。
    ///
    /// **書目分類與排版指令是兩件事**，先前被自由字串掩蓋：`article` 碰巧同時是
    /// 兩者的名字，所以沒人發現。封閉列舉一來就分開了——`journal-article` 是
    /// APA7 10.1 的**書目分類**，`@ARTICLE` 是 **LaTeX 的排版指令**。
    ///
    /// 多對一是預期的：`wikipediaEntry` 與 `bookChapter` 都輸出 `INCOLLECTION`，
    /// 因為 biblatex 沒有維基條目的專屬 entry type——那個區分活在 APA7 層。
    public var biblatexEntryType: String {
        switch self {
        case .periodicalArticle: return "ARTICLE"
        case .book:              return "BOOK"
        case .bookChapter,
             .wikipediaEntry:    return "INCOLLECTION"
        case .report,
             .dataSet,
             .software,
             .testInstrument:    return "REPORT"      // biblatex 無專屬型，REPORT 最近
        case .conferenceSession: return "INPROCEEDINGS"
        case .thesis:            return "THESIS"
        case .review,
             .unpublishedWork:   return "UNPUBLISHED"
        case .audiovisualWork,
             .audioWork,
             .visualWork,
             .socialMediaPost,
             .webpage:           return "ONLINE"
        }
    }

    /// 這個值在 CSL（Citation Style Language）的 item type。
    ///
    /// **第三套類型系統**——APA7 ch10（模型）／biblatex entry type（LaTeX 排版）／
    /// CSL item type（樣式引擎）。三者各有分法，但都是 `WorkType` 的**下游對照**，
    /// 彼此不耦合。這是「按它是什麼建模、按樣式需要渲染」的具體形狀：日後要支援
    /// Chicago／Vancouver 時加的是新對照，不是重新建模。
    public var cslType: String {
        switch self {
        case .periodicalArticle: return "article-journal"
        case .book:              return "book"
        case .bookChapter:       return "chapter"
        case .wikipediaEntry:    return "entry-encyclopedia"
        case .report:            return "report"
        case .conferenceSession: return "paper-conference"
        case .thesis:            return "thesis"
        case .review:            return "review"
        case .unpublishedWork:   return "manuscript"
        case .dataSet:           return "dataset"
        case .software:          return "software"
        case .testInstrument:    return "standard"
        case .audiovisualWork:   return "motion_picture"
        case .audioWork:         return "song"
        case .visualWork:        return "graphic"
        case .socialMediaPost:   return "post"
        case .webpage:           return "webpage"
        }
    }

    /// 從 biblatex entry type 讀回 `WorkType`——**有損逆向**，只用於讀取 `.bib` 檔。
    ///
    /// ## 為什麼需要它（而不是要求使用者寫 WorkType）
    ///
    /// `.bib` 是 **biblatex 的檔案格式**，`@ARTICLE` 是它的詞彙。要求使用者把
    /// `.bib` 改寫成 `@periodical-article`（那根本不是合法 biblatex type）是荒謬的。
    /// 所以讀 `.bib` 時必須從排版詞彙讀回模型詞彙。`--json` 路徑則相反：那是
    /// Akashic 自己的詞彙，維持嚴格要求 `WorkType` 值。
    ///
    /// ## 這張表不是新發明的
    ///
    /// 它與 `WorkTypeMigration.mapping`（#325 階段一）**是同一張表**——階段一遷移的
    /// 來源值域就是 biblatex entry type，因為舊的自由字串 `Entry.type` 裝的正是那些。
    /// 那張表已由 937 筆真實記錄驗證（937/937 可對映、0 未對映），所以這裡是把一個
    /// **已驗證的事實**搬到它該住的地方：緊鄰正向的 `biblatexEntryType`，讓正逆兩向
    /// 並列，分岔看得見。
    ///
    /// ## 有損在哪裡（明寫，不假裝是雙射）
    ///
    /// 正向是多對一（`bookChapter` 與 `wikipediaEntry` 都輸出 `INCOLLECTION`），所以
    /// 逆向必須**選一個原像**。選的一律是**最不細分的那個**——細分要靠額外訊號：
    ///
    /// - `incollection` → `bookChapter`（**不是** `wikipediaEntry`）
    /// - `report` → `report`（不是 `dataSet` / `software` / `testInstrument`）
    /// - `unpublished`（無 `location`）→ `unpublishedWork`（不是 `review`）
    /// - `online` → `webpage`（不是視聽／社群媒體）
    ///
    /// 兩個**條件式**細分沿用階段一經驗證的判準（同一組 `fields` 訊號）：
    /// `misc` 帶 `url` → `wikipediaEntry`；`unpublished` 帶 `location` →
    /// `conferenceSession`。
    ///
    /// ## 對映不到就回 `nil`，**不猜**
    ///
    /// 呼叫端必須把它變成一個列出值域的拒絕訊息。這與 `lossless-intake` 的
    /// 「真的要丟就必須報出來」同向：靜默塞一個 `webpage` 會讓使用者事後無法
    /// 分辨「我沒給」與「系統猜的」。
    public init?(biblatexEntryType: String, fields: [String: String] = [:]) {
        switch biblatexEntryType.lowercased() {
        case "article":       self = .periodicalArticle   // 10.1
        case "book":          self = .book                // 10.2
        case "incollection":  self = .bookChapter         // 10.3（不細分到 wikipediaEntry）
        case "report":        self = .report              // 10.4
        case "inproceedings",
             "presentation":  self = .conferenceSession   // 10.5（APA7 不分這兩者）
        case "thesis":        self = .thesis              // 10.6
        case "online":        self = .webpage             // 10.16
        // ── 條件式細分（判準與階段一同源）──
        case "misc":
            guard fields["url"] != nil else { return nil }
            self = .wikipediaEntry
        case "unpublished":
            self = fields["location"] != nil ? .conferenceSession : .unpublishedWork
        default: return nil
        }
    }

    /// 給錯誤訊息用的值域字串。**從 `allCases` 生成，不得寫死**——#324 的教訓：
    /// 三處訊息各自寫死舊值域，值域改了訊息還在報舊值。
    public static var domainDescription: String {
        allCases.map(\.rawValue).sorted().joined(separator: " / ")
    }
}
