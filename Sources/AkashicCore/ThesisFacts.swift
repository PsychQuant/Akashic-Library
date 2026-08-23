import Foundation

/// APA7 §10.6 渲染一筆學位論文所需的、模型先前裝不下的事實（#335）。
///
/// ## 為什麼是欄位而不是 `WorkType` 的細分值
///
/// `apa7-is-the-work-floor` 給了判準：「這個區分改變的是**索取哪組欄位**，還是只改變
/// **渲染字串**」。逐條套：
///
/// | 事實 | 改變什麼 | 裁決 |
/// |---|---|---|
/// | **學位別** | 只改變方括號內的字串（`[Unpublished doctoral dissertation]` vs `[Unpublished master's thesis]`）。author／title／institution／date 一模一樣 | 欄位 |
/// | **已出版與否** | 該規則的「不進值域」封閉列舉第 1 類**逐字點名了「出版狀態」** | 欄位 |
///
/// 第二列不是我推導的，是規則原文寫著的——它把 ch10 的四條軸（Author／Date／Title／
/// Source Variations）歸為「欄位值、**出版狀態**與關係」，並說「存成類型會把封閉列舉炸成
/// 113 個值」。這裡的具體形式就是笛卡兒積：3 學位 × 2 出版狀態 ＝ 6 個值，而它們索取的
/// 欄位組只有兩種。
///
/// 對照 `referenceWorkEntry` 為什麼**可以**細分（同一條規則允許「更細」）：那是「獨立且高頻
/// 的類型（實測 14 筆）」，且它與 `bookChapter` 索取的欄位組確實不同。學位別不是。
///
/// ## 為什麼 `availability` 帶關聯值
///
/// 「典藏庫」只在**已出版**時存在——未出版的論文依 §10.6 是「必須直接向該校索取」，
/// 沒有資料庫可指。把 `repository` 做成獨立的可選欄位，就讓「未出版但有典藏庫」這個
/// **不可能的事態**變成可寫的；用關聯值則它在文法上寫不出來。
///
/// 這是 `entity-backlink-completeness` 已引用過的同一條紀律（《邏輯哲學論》3.325 的工程
/// 類比）：好的記法讓矛盾**無處可寫**，而不是寫得出來再靠檢查擋。
///
/// ## 為什麼兩個欄位都可以是 `nil`
///
/// 實測（2026-08-19）store 的 5 筆 `thesis`：學位別 2 筆有（且三種寫法）／3 筆沒有；
/// 已出版與否 **5 筆全無**。
///
/// 所以「未查」必須可表達，而且**不得折成預設值**。若把缺席的 `availability` 當成
/// `.unpublished`，渲染出的 `[Unpublished doctoral dissertation]` 是一個**可能為假的
/// 斷言**——那不是缺資訊，是印出錯的東西。同 `lossless-intake` 執行細節 4：「還沒查」
/// 與「確實沒有」折成同一個觀察，事後完全無法區分。
public struct ThesisFacts: Equatable, Sendable {

    /// 學位別。**封閉三值**——§10.6 原文的值域是三層不是兩層：
    /// 「doctoral dissertations and master's **and undergraduate** theses」。
    public enum Degree: String, CaseIterable, Sendable {
        case doctoral
        case masters
        case undergraduate

        /// biblatex 的 `type` 欄位值。
        ///
        /// 前兩個是依賴**自己指定**的（`APADataModel.suggestTypeUpgrade`：
        /// 「Use @THESIS with type={phdthesis}」／「type={mathesis}」），不是我們發明的慣例。
        ///
        /// `bathesis` 是 biblatex 的標準 localization key，但**未出現在依賴的
        /// `suggestTypeUpgrade` 裡**，且 store 目前零實例——所以它是依 biblatex 慣例的
        /// 合理選擇，尚未被實測驗證過。
        public var biblatexToken: String {
            switch self {
            case .doctoral:      return "phdthesis"
            case .masters:       return "mathesis"
            case .undergraduate: return "bathesis"
            }
        }
    }

    /// 取得途徑。§10.6 的兩張 template 就是照這條軸分的。
    ///
    /// **關聯值不是為了方便，是為了讓「未出版但有典藏庫」寫不出來。**
    public enum Availability: Equatable, Sendable {
        /// 未出版——依 §10.6「必須直接向該校以紙本索取」，沒有典藏庫可指。
        /// 授予機構落在 source element（句末）。
        case unpublished
        /// 已出版——授予機構落在標題後的方括號內，典藏庫落在 source element。
        ///
        /// **`repository` 是可選的**，而這一點是被 ch10 的 fixture 逼出來的：手冊例 65／66
        /// 是已出版的論文（有典藏 URL）卻**沒有典藏庫名**。原本的設計要求 published 必帶
        /// repository，於是遇到那種記錄只剩兩條路——丟掉「已出版」這個**已知**事實，或
        /// **編造**一個典藏庫名。兩者都是 `lossless-intake` 禁止的折疊。
        ///
        /// 放寬它**不弱化真正要防的那件事**：`unpublished` 仍然沒有帶 repository 的形式，
        /// 所以「未出版卻有典藏庫」照舊在文法上寫不出來。
        case published(repository: String?, url: String?)
    }

    /// `nil` ＝ 未查。**不得折成任何預設值**（見型別 doc）。
    public var degree: Degree?
    /// `nil` ＝ 未查。同上。
    public var availability: Availability?

    /// **failable**：兩個事實都沒查到的 `ThesisFacts` 不存在——那個狀態的意思就是
    /// `Entry.thesis == nil`，兩種寫法並存會製造一個編碼有損的狀態
    /// （寫不出 `thesis:` 區塊，讀回來變 `nil`，與寫入的模型不等）。
    ///
    /// 這不是理論顧慮：`EntryYAML.encode` 的語意自檢會**拒絕寫出**那種 entry
    /// （實測，#335 開發時撞到）。與其在 writer 加一個 `isEmpty` 分支繞過，不如讓
    /// 那個狀態在文法上不存在——同 `availability` 用關聯值的理由。
    public init?(degree: Degree? = nil, availability: Availability? = nil) {
        guard degree != nil || availability != nil else { return nil }
        self.degree = degree
        self.availability = availability
    }
}
