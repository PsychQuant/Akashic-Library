import Foundation
import AkashicCore

/// `Entry.fields` 裡的識別碼殘留 → 結構化欄位；work 的 `issn` → 它的 venue（#394 §8）。
///
/// ## 為什麼要遷移，而不是讓兩邊並存
///
/// §3 讓結構化欄位與 `fields` 殘留並存是**過渡**：`canonicalDOIs` 一族在兩者都在場時
/// 取結構化值，所以並存期間讀取面是對的。但並存久了會出現第二個真相來源——有人改了
/// `fields.doi` 而結構化欄位沒動，兩邊分岔且**沒有任何跡象**。`no-compat-fallback`
/// 記過這個形狀：留著的相容路徑不會保護任何東西，它只是在等一個新的呼叫端誤入。
///
/// ## 三件事，一次寫入
///
/// 1. `doi`／`pmid`／`isbn` 自 `fields` 升格為結構化欄位，並移除殘留。
/// 2. `issn` **移位到 venue**——ISSN 識別的是期刊不是文章（spec 的 requirement
///    「An identifier SHALL live on the entity it identifies」）。實測 64 筆帶 `issn`
///    的 work **全部**已歸戶 venue，所以全部搬得動。
/// 3. 指向被改寫值的 provenance `value` 同一次原子改寫。
///
/// ## 誠實邊界：第 3 件事目前是零實例
///
/// `Entry.references` 是 §5 才新增的、全庫為空；venue 的 `issn` reference 也還不存在
/// （寫入面要 format 13，而 store 仍是 12）。所以改寫 provenance 的那條路徑**現在一定
/// 走不到**。它仍然實作並測試，理由是：遷移是一次性的破壞性寫入，等到真的有 reference
/// 指向識別碼時再補，那時已經來不及——而它的成本是一個迴圈。
///
/// **不自動 bump format。** 遷移必須跑在舊解碼器上（design 的部署順序），bump 是人工的
/// 最後一步。
public enum IdentifierMigration {

    /// 一筆記錄的處置。
    public struct Plan: Equatable {
        public var citekey: String
        /// `<欄位>: <原值> → <正規形>`，逐個識別碼一行。
        public var changes: [String]
        /// 這筆的 `issn` 要搬到哪個 venue（`nil` ＝ 沒有 issn）。
        public var issnToVenue: String?
    }

    /// 無法解析而**略過**的——不猜、不丟棄，原值留在 `fields` 裡。
    public struct Skipped: Equatable {
        public var citekey: String
        public var field: String
        public var value: String
        public var reason: String
    }

    /// venue 側的 ISSN 落點。`merged` 與 `keptMultiple` **分開列**（task 8.2）——
    /// 前者是異寫法收斂，後者是 print／electronic 兩個真的號，人要分辨得出來。
    public struct VenuePlan: Equatable {
        public var venueKey: String
        public var values: [String]
        public var mergedFrom: [String]
        public var keptMultiple: Bool
    }

    public struct Report: Equatable {
        public var plans: [Plan] = []
        public var venuePlans: [VenuePlan] = []
        public var skipped: [Skipped] = []
        public var provenanceRewrites: [String] = []
        public var failed: [String] = []
        public var applied: Int = 0

        /// 會被改動的識別碼總數——dry-run 的頭條數字。
        public var identifierCount: Int { plans.reduce(0) { $0 + $1.changes.count } }
    }

    /// `fields` 裡承載識別碼的鍵。**封閉列舉**——`url` 不在其中（它是位置不是身分，
    /// `identity-is-judged-not-matched` 的例外節具名排除過）。
    static let workIdentifierKeys = ["doi", "pmid", "isbn", "issn"]

    /// 一個欄位值切成多個識別碼候選。
    ///
    /// 實測的三種多值寫法都在這裡收斂：空白分隔（`0022-3506 1467-6494`）、逗號分隔、
    /// 以及帶括號標註（`1860-0980 (Electronic) 0033-3123 (Linking)`）。**括號整段丟掉**
    /// ——`(Electronic)`／`(Print)`／`(Linking)` 是人給的註記不是識別碼的一部分，而我們
    /// 沒有欄位可以存它；保留它會讓值解析失敗，等於把整筆略過。
    static func candidates(_ raw: String) -> [String] {
        raw.replacingOccurrences(of: #"\([^)]*\)"#, with: " ",
                                 options: .regularExpression)
            .split(whereSeparator: { $0 == "," || $0.isWhitespace })
            .map(String.init)
            .filter { !$0.isEmpty }
    }

    /// 正規化 ＋ **去重**（task 8.2：先正規化再去重，去重後仍 >1 者才是真多號）。
    static func normalizedUnique<T: Identifier>(_ raws: [String], _ make: (String) -> T?)
        -> (values: [T], unparseable: [String]) {
        var out: [T] = []
        var bad: [String] = []
        for r in raws {
            guard let v = make(r) else { bad.append(r); continue }
            if !out.contains(v) { out.append(v) }
        }
        return (out, bad)
    }

    /// 這個欄位的多值該吸收，還是交給人？**按種類分，而分法是量出來的。**
    ///
    /// | 種類 | 一個欄位解出 >1 相異值 | 那些多值是什麼 | 裁決 |
    /// | --- | --- | --- | --- |
    /// | PMID | 0 筆 | — | 不吸收（無實例，且一篇一個 PMID） |
    /// | ISBN | 5 筆 | 精裝／電子版、ISBN-10 與 ISBN-13——**同一本書的兩個號** | 吸收 |
    /// | ISSN | 25 筆 | print 與 electronic——**同一份期刊的兩個號** | 吸收 |
    /// | DOI | **1 筆** | `10.1037/amp0000794` ＋ `….supp (Supplemental)`——**附錄的 DOI** | 不吸收 |
    ///
    /// DOI 那一筆是決定性的：吸收它等於讓該記錄宣稱自己是另一個物件，而識別碼**終結
    /// 指涉**（`identity-is-judged-not-matched`）——那是一句假的身分宣稱，不是多一筆資料。
    ///
    /// **spec 給 DOI 是清單的證據不支持吸收**：它寫「37 組 work 記錄同題同年而 DOI 不同」
    /// ——那是**跨記錄**的重複，不是一筆記錄需要兩個 DOI。型別仍然是清單（真的多 DOI 存在
    /// 且遷移之後可以人工加），但遷移不從一個自由字串裡**發明**多值。
    ///
    /// 不吸收 ≠ 丟棄：那一筆會出現在報告的 `skipped` 裡、原值留在 `fields`，交人裁。
    public static func absorbsMultipleValues(field: String) -> Bool {
        field == "issn" || field == "isbn"
    }
}
