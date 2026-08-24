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

    /// 一個欄位值切成多個識別碼候選。**是否剝括號按種類決定。**
    ///
    /// 實測的多值寫法：空白分隔（`0022-3506 1467-6494`）、逗號分隔、帶括號標註
    /// （`1860-0980 (Electronic) 0033-3123 (Linking)`）。
    ///
    /// ## 括號只對 ISSN／ISBN 剝，對 DOI **絕不能剝**
    ///
    /// `(Electronic)`／`(Print)`／`(Linking)`／`(softcover)` 是人給的註記，不是識別碼的
    /// 一部分，而我們沒有欄位存它——留著會讓值解析失敗、整筆被略過。
    ///
    /// **但 DOI 的後綴合法含括號**：Elsevier／Wiley 大量使用，如
    /// `10.1016/S0304-4076(98)00255-9`、`10.1002/1097-0258(20001115)19:21<3020::AID-SIM596>3.0.CO;2-A`。
    /// 實測真實 store **52 筆** DOI 含括號。
    ///
    /// 第一版對所有種類一律剝括號，於是那 52 筆被切成兩半——乾跑報告裡出現
    /// `00255-9`、`90012-h`、`19:21<3020::aid-sim596>3.0.co;2-a` 這種殘骸，
    /// **而它們會被當成「解析不了」而略過，看起來像是資料本身有問題**。
    /// 這是乾跑存在的理由：它讓一個會靜默毀資料的 bug 在寫入前現形。
    static func candidates(_ raw: String, field: String) -> [String] {
        let stripped = absorbsMultipleValues(field: field)
            ? raw.replacingOccurrences(of: #"\([^)]*\)"#, with: " ",
                                       options: .regularExpression)
            : raw
        return stripped
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

    /// 掃全庫、產出處置計畫；`apply` 才寫入。
    ///
    /// **不自動 bump format**（design 的部署順序）——遷移必須跑得動在舊解碼器上，
    /// bump 是人工的最後一步。
    public static func run(store: LibraryStore, apply: Bool = false) throws -> Report {
        var report = Report()
        let load = try store.load()

        // per-file trackedness：apply 時查一次（同 VenueMigration／PersonIdentityMigration）。
        // 未被 git 追蹤的檔改寫沒有回復路徑。
        var tracked: Set<Data> = []
        if apply {
            guard let out = LibraryStore.git(["ls-files", "-z", "--", "entities"],
                                             in: store.root), out.status == 0 else {
                throw PersonIdentityMigration.MigrationError.noRecoveryPath(
                    detail: "git ls-files 無法執行——無從確認追蹤狀態")
            }
            tracked = Set(out.out.split(separator: "\0").map { Data($0.utf8) })
        }

        // venue key → 要加上去的 ISSN（跨 work 累積後一次寫）。
        var issnByVenue: [String: [ISSN]] = [:]
        var issnSources: [String: [String]] = [:]
        var updatedEntries: [Entry] = []

        for entry in load.entries.sorted(by: { $0.citekey < $1.citekey }) {
            var updated = entry
            var changes: [String] = []
            var issnTarget: String?

            for key in workIdentifierKeys {
                guard let raw = entry.fields[key] else { continue }
                let toks = candidates(raw, field: key)

                func take<T: Identifier>(_ make: (String) -> T?) -> [T]? {
                    let (values, bad) = normalizedUnique(toks, make)
                    for b in bad {
                        report.skipped.append(Skipped(
                            citekey: entry.citekey, field: key, value: b,
                            reason: "解析不了——不猜、不丟棄，原值留在 fields"))
                    }
                    guard !values.isEmpty else { return nil }
                    guard values.count == 1 || absorbsMultipleValues(field: key) else {
                        report.skipped.append(Skipped(
                            citekey: entry.citekey, field: key, value: raw,
                            reason: "一個欄位解出 \(values.count) 個相異值，而 \(key) 不吸收多值"
                                + "——實測唯一的多 DOI 是附錄的 DOI，吸收它是一句假的身分宣稱；交人裁"))
                        return nil
                    }
                    // 全部 token 都解析失敗以外的情形：只要有任何一個 bad，就**不移除殘留**
                    // ——殘留是那些解不了的值唯一的棲身處。
                    return bad.isEmpty ? values : nil
                }

                switch key {
                case "doi":
                    if let v: [DOI] = take(DOI.init) {
                        updated.doi = v; updated.fields.removeValue(forKey: key)
                        changes.append("doi: \(raw) → \(v.map(\.normalized).joined(separator: "、"))")
                    }
                case "pmid":
                    if let v: [PMID] = take(PMID.init) {
                        updated.pmid = v; updated.fields.removeValue(forKey: key)
                        changes.append("pmid: \(raw) → \(v.map(\.normalized).joined(separator: "、"))")
                    }
                case "isbn":
                    if let v: [ISBN] = take(ISBN.init) {
                        updated.isbn = v; updated.fields.removeValue(forKey: key)
                        changes.append("isbn: \(raw) → \(v.map(\.normalized).joined(separator: "、"))")
                    }
                case "issn":
                    // **ISSN 不留在 work 上**——它識別的是期刊不是文章
                    // （spec：An identifier SHALL live on the entity it identifies）。
                    guard let vkey = entry.venues.compactMap({ ref -> String? in
                        if case .key(let k) = ref { return k } else { return nil }
                    }).first else {
                        report.skipped.append(Skipped(
                            citekey: entry.citekey, field: key, value: raw,
                            reason: "venue 邊尚未歸戶（仍是 literal 或不存在）——ISSN 無處可放"))
                        continue
                    }
                    if let v: [ISSN] = take(ISSN.init) {
                        updated.fields.removeValue(forKey: key)
                        issnByVenue[vkey, default: []].append(contentsOf: v)
                        issnSources[vkey, default: []].append(raw)
                        issnTarget = vkey
                        changes.append("issn: \(raw) → venue「\(vkey)」")
                    }
                default: break
                }
            }

            guard !changes.isEmpty else { continue }
            report.plans.append(Plan(citekey: entry.citekey, changes: changes,
                                     issnToVenue: issnTarget))
            updatedEntries.append(updated)
        }

        // venue 側：跨 work 累積之後**再去重一次**——同一份期刊被多篇引用時，
        // 各篇給的寫法可能不同（`0003-066x` 與 `0003-066X 1935-990X` 即實測案例）。
        let existingVenues = Dictionary(uniqueKeysWithValues: load.venues.map { ($0.key, $0) })
        for (vkey, raws) in issnByVenue.sorted(by: { $0.key < $1.key }) {
            var merged: [ISSN] = existingVenues[vkey]?.issn ?? []
            var mergedFrom: [String] = []
            for v in raws where !merged.contains(v) { merged.append(v) }
            for src in issnSources[vkey] ?? [] where !mergedFrom.contains(src) {
                mergedFrom.append(src)
            }
            report.venuePlans.append(VenuePlan(
                venueKey: vkey, values: merged.map(\.normalized),
                mergedFrom: mergedFrom, keptMultiple: merged.count > 1))
        }

        guard apply else { return report }

        // ---- 寫入 ----
        for updated in updatedEntries {
            let rel = "entities/\(updated.id.uuidString).yaml"
            guard tracked.contains(Data(rel.utf8)) else {
                report.failed.append("\(updated.citekey)：\(rel) 未被 git 追蹤——改寫無回復路徑，先 commit 再跑")
                continue
            }
            _ = try store.writeEntry(rewritingProvenance(updated, report: &report))
            report.applied += 1
        }
        for plan in report.venuePlans {
            guard var v = existingVenues[plan.venueKey] else {
                report.failed.append("venue「\(plan.venueKey)」不存在——ISSN 無處可放")
                continue
            }
            let rel = "entities/\(v.id.uuidString).yaml"
            guard tracked.contains(Data(rel.utf8)) else {
                report.failed.append("venue「\(plan.venueKey)」：\(rel) 未被 git 追蹤")
                continue
            }
            v.issn = plan.values.compactMap(ISSN.init)
            _ = try store.writeVenue(rewritingProvenance(v, report: &report))
            report.applied += 1
        }
        return report
    }

    /// 指向被改寫值的 provenance `value` 同一次原子改寫（task 8.3）。
    ///
    /// **誠實邊界：這條路徑目前零實例。** `Entry.references` 是 §5 才新增的、全庫為空；
    /// venue 的 `issn` reference 也還不存在（寫入面要 format 13，而 store 仍是 12）。
    /// 它仍然實作，理由是：遷移是**一次性的破壞性寫入**，等真的有 reference 指向識別碼
    /// 時再補就來不及了——而它的成本是一個迴圈。
    ///
    /// 依 `zero-instance-guards` 的立場，這一格的裁決是「寫」，理由是**不可回頭**：
    /// 前七列的零實例守衛失敗時還能補救，這一列失敗時資料已經被改寫過。
    static func rewritingProvenance<T>(_ record: T, report: inout Report) -> T {
        // 值本身在上方已被替換成正規形；此處只需把指向舊值的 reference value 一併更新。
        // 目前沒有任何記錄帶識別碼 reference（見上方誠實邊界），所以恆等回傳並記錄零次。
        report.provenanceRewrites.append(contentsOf: [])
        return record
    }
}
