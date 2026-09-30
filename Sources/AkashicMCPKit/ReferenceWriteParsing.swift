import Foundation
import AkashicCore

/// #674：references 的通用寫入面（`update_person` 的 `fields.references`、`update_venue` 的 `references`）共用的**一份**解析。
///
/// 兩個面先前各自演化：person 側（#308）`status` 預設 200、未知鍵靜默忽略、非字串的 `value`／`media_type` 靜默變成 nil、
/// `rests_on` 裡非字串的元素靜默變成空、沒有上限；venue 側（#587）刻意比它嚴，卻沒有追蹤。往 venue 那邊對齊——
/// 預設 200 會把離線掃描檔記成 HTTP 200（#542 R2 對 `enrich` 裁掉過同一個預設），靜默忽略未知鍵讓打錯的欄位名不出聲。
///
/// **這裡只放兩面共用的形狀**：鍵名、型別、上限、空陣列拒絕、`status` 必填與範圍、`url` 只收 http／https 且不含帳密、`retrieved` 是 ISO 8601、
/// `kind` 與給的欄位一致。其中 status／url／retrieved 三項（擷取型的形狀）住在 Core 的 `RetrievalWriteShape`，`enrich` 的來源欄位
/// 呼叫同一個函式（#695）。**holder 自己的政策**（哪些欄位收、value 入庫前怎麼正規化）由 `ReferenceHolderPolicy` 注入——
/// person 收 verdict 以外的欄位、venue 只收 issn 與 names——那是兩種記錄的差異，不是契約的分岔。
///
/// 形狀驗證（擷取型四欄必要、兩種互斥、判斷型 rests-on 非空、digest 形狀與空內容 digest）仍走 `ProvenanceReference` 的平面 init
/// （YAML decode 的同一個入口）——**不動 init 本身**：載入既有記錄的判準不能因為寫入面收緊而變。`url`／`retrieved`／`status`
/// 範圍的檢查（`RetrievalWriteShape`）只在寫入面，live store 的既有記錄不受影響（2026-09-29 唯讀量測：person／venue／organization 的 references 沒有任何一筆
/// 擷取型；work 的 33 筆全是 `https`、無帳密、`YYYY-MM-DD`、status 200）。
extension AkashicService {

    /// JSON 物件的鍵名——**與 `update_person` 的 references 相同**（`media_type`／`statement`／`rests_on`），不是 YAML 的
    /// `media-type`／`judgement`／`rests-on`。鍵是嚴格的：不認得的鍵整批拒絕。
    static let referenceJSONKeys: Set<String> = [
        "field", "value", "kind", "url", "retrieved", "status", "media_type", "content", "statement", "rests_on",
    ]

    /// 一次呼叫至多幾筆（與未決腿同一個量級：CLI 單批 triage）。有界拒絕，不截斷。
    static let maxReferencesPerCall = 200

    /// 兩種記錄各自的收件政策。
    struct ReferenceHolderPolicy {
        /// 這個 holder 收不收這個 field（`at` 是 `references[i]`）；不收就丟具名的參數錯誤。在 kind 與其餘鍵之前跑。
        let admitField: (_ field: String, _ at: String) throws -> Void
        /// `value` 入庫前的正規化（例：venue 的 issn 以正規形入庫）。在 holder 收下那個 field、其餘鍵都驗過之後跑。
        let normalizeValue: (_ field: String, _ value: String, _ at: String) throws -> String

        init(admitField: @escaping (_ field: String, _ at: String) throws -> Void,
             normalizeValue: @escaping (_ field: String, _ value: String, _ at: String) throws -> String = { _, v, _ in v }) {
            self.admitField = admitField
            self.normalizeValue = normalizeValue
        }
    }

    /// JSON 物件陣列 → `ProvenanceReference`（逐筆；任一筆不合即整批拒絕）。
    ///
    /// 寫入面自己做的事，都是平面 init 管不到的：
    /// 1. **鍵名嚴格、型別不猜**：不認得的鍵拒收；`value`／`media_type`／`url` 等要是字串、`rests_on` 要是字串陣列、
    ///    `status` 要是整數（boolean 與 200.5 不是）；
    /// 2. **`status` 必填、不預設**，且在 100–599；
    /// 3. **`url` 只收 http／https、不含帳密**（帳密與帶 token 的 userinfo 會落進 git 追蹤的 YAML）；離線來源改用 judgement 型；
    /// 4. **`retrieved` 是 ISO 8601**（日期，或日期加時間與可選的時區）——2–4 的 status 範圍、url、retrieved 由 `RetrievalWriteShape.firstIssue` 驗；
    /// 5. **`kind` 必須與給的欄位一致**（init 從在場的欄位推 kind；呼叫端說 retrieval 卻只給了 statement，是兩句不一致的話）；
    /// 6. **有界**：一次至多 `maxReferencesPerCall` 筆、`statement` 至多 `maxStatementBytes` 位元組、`rests_on` 至多
    ///    `maxRestsOnPerCall` 個、其餘字串各至多 `AddOnlyEnrichment.maxValueBytes`（`enrich` 對來源字串的同一個上限）。
    ///
    /// **空陣列兩面都拒絕、同一句話**（#695，使用者 2026-09-30 裁決「兩面都拒絕」）：沒有要附的 reference 就不要給這個鍵——與逐 id 腿
    /// 「空陣列與 null 同拒」（#443／#635）的既有做法一致。#674 時 person 側仍是 no-op（`fields` 裡被提及的一格），venue 側是錯，
    /// 那是有記錄的差異；拒絕住在這裡，兩面自然同一句。
    static func parseReferenceObjects(_ raw: [Any], policy: ReferenceHolderPolicy) throws -> [ProvenanceReference] {
        guard !raw.isEmpty else {
            throw ServiceError.invalid("references 是空陣列——沒有要附的 reference 就不要給這個鍵")
        }
        guard raw.count <= maxReferencesPerCall else {
            throw ServiceError.invalid("references 一次最多 \(maxReferencesPerCall) 筆（這次 \(raw.count) 筆）——分次送")   // display-safe-exempt: maxReferencesPerCall 與 raw.count 是 Int
        }
        return try raw.enumerated().map { i, item in try parseReferenceObject(item, index: i, policy: policy) }
    }

    private static func parseReferenceObject(_ item: Any, index i: Int, policy: ReferenceHolderPolicy) throws -> ProvenanceReference {
        let at = "references[\(i)]"   // display-safe-exempt: i 是 Int
        guard let obj = item as? [String: Any] else {
            throw ServiceError.invalid("\(at) 必須是物件（{field, value?, kind, …}）")   // display-safe-exempt: at 是字面＋Int
        }
        let unknown = obj.keys.filter { !referenceJSONKeys.contains($0) }.sorted()
        if !unknown.isEmpty {
            throw ServiceError.invalid(
                "\(at) 有不認得的鍵「\(Self.listCapped(unknown) { displaySafeInvisible($0, max: 60) })」——"   // display-safe-exempt: at 是字面＋Int
                + "合法的鍵：" + referenceJSONKeys.sorted().joined(separator: "、")   // display-safe-exempt: referenceJSONKeys 是本檔的字面集合
                + "（判斷型的斷言鍵是 statement）")
        }
        func string(_ key: String, cap: Int = AddOnlyEnrichment.maxValueBytes) throws -> String? {
            guard let v = obj[key], !(v is NSNull) else { return nil }
            guard let s = v as? String else {
                throw ServiceError.invalid("\(at).\(key) 必須是字串")   // display-safe-exempt: at 是字面＋Int；key 取自上方的封閉鍵集合
            }
            guard s.utf8.count <= cap else {
                throw ServiceError.invalid("\(at).\(key) 超過 \(cap) 位元組（實得 \(s.utf8.count)）——拒絕，不截斷")   // display-safe-exempt: at 是字面＋Int；key 取自封閉鍵集合；cap 與 s.utf8.count 是 Int
            }
            return s
        }
        guard let field = try string("field"),
              !field.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ServiceError.invalid("\(at) 缺 field（這筆 reference 支持哪個欄位）")   // display-safe-exempt: at 是字面＋Int
        }
        try policy.admitField(field, at)
        guard let kindName = try string("kind"), ["retrieval", "judgement"].contains(kindName) else {
            throw ServiceError.invalid("\(at) 的 kind 必須是 retrieval 或 judgement")   // display-safe-exempt: at 是字面＋Int
        }
        let url = try string("url"), retrieved = try string("retrieved")
        let mediaType = try string("media_type"), content = try string("content")
        let statement = try string("statement", cap: maxStatementBytes)
        var status: Int?
        if let v = obj["status"], !(v is NSNull) {
            guard let n = v as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID(),
                  let exact = Int(exactly: n.doubleValue) else {
                throw ServiceError.invalid("\(at).status 必須是整數（HTTP 狀態碼；離線來源改用 judgement 型）")   // display-safe-exempt: at 是字面＋Int
            }
            status = exact   // 範圍（100–599）在下面的 `RetrievalWriteShape.firstIssue`，與 enrich 的來源欄位同一個函式（#695）
        }
        var restsOn: [String] = []
        if let v = obj["rests_on"], !(v is NSNull) {
            guard let arr = v as? [Any], let strs = arr as? [String], strs.count == arr.count else {
                throw ServiceError.invalid("\(at).rests_on 必須是字串陣列（sha256: digest）")   // display-safe-exempt: at 是字面＋Int
            }
            guard strs.count <= maxRestsOnPerCall else {
                throw ServiceError.invalid("\(at).rests_on 最多 \(maxRestsOnPerCall) 個 digest（這次 \(strs.count) 個）")   // display-safe-exempt: at 是字面＋Int；maxRestsOnPerCall 與 strs.count 是 Int
            }
            restsOn = strs
        }
        // 擷取型的形狀（status 範圍、缺 status 不預設 200、url、retrieved、media_type）：`RetrievalWriteShape`，與 enrich 的來源欄位同一個函式（#695）。
        // 「缺 status」只看「純擷取型」：同時帶判斷側欄位的（兩種混用）留給平面 init 的「不得混用」，沒有任何擷取側欄位的
        // （例如 kind 寫 retrieval 卻只給 statement）留給下面的 kind 一致性檢查——那兩句話都比「缺 status」更準。
        let statusRequired = statement == nil && restsOn.isEmpty
            && (url != nil || retrieved != nil || mediaType != nil || content != nil)
        if let why = RetrievalWriteShape.firstIssue(url: url, retrieved: retrieved, status: status, mediaType: mediaType, statusRequired: statusRequired,
                                                    names: referenceRetrievalNames(at: at), echo: { displaySafeInvisible($0, max: 80) }) {
            throw ServiceError.invalid(why)   // display-safe-exempt: why 由 RetrievalWriteShape 組成——回顯的值經 echo（displaySafeInvisible）逃一次，其餘是字面、Int 與 at（字面＋Int）
        }
        var value = try string("value")
        if let v = value { value = try policy.normalizeValue(field, v, at) }
        let reference: ProvenanceReference
        do {
            reference = try ProvenanceReference(
                field: field, value: value, url: url, retrieved: retrieved, status: status,
                mediaType: mediaType, content: content, judgement: statement, restsOn: restsOn)
        } catch let e as ServiceError {
            throw e
        } catch {
            throw ServiceError.invalid("\(at)：\(displaySafeError(error, max: 600))")   // display-safe-exempt: at 是字面＋Int
        }
        switch (kindName, reference.kind) {
        case ("retrieval", .retrieval), ("judgement", .judgement):
            return reference
        default:
            throw ServiceError.invalid(
                "\(at) 的 kind 是 \(kindName)，給的欄位卻是另一種——retrieval 用 url／retrieved／status／content（media_type 選填），"   // display-safe-exempt: at 是字面＋Int；kindName 已限定為兩個字面之一
                + "judgement 用 statement／rests_on")
        }
    }

    // MARK: - 擷取型的形狀（#695 起住在 Core）

    /// references 面怎麼稱呼一筆擷取型記錄與它的三個鍵（`RetrievalWriteShape.Names`）：訊息指名 `references[i].url` 這種路徑；
    /// 離線來源的出路是判斷型（statement＋rests_on 指向存檔）。enrich 的來源欄位有自己的一組（`AddOnlyEnrichment`）。
    static func referenceRetrievalNames(at: String) -> RetrievalWriteShape.Names {
        RetrievalWriteShape.Names(record: at, url: "\(at).url", retrieved: "\(at).retrieved", status: "\(at).status", mediaType: "\(at).media_type",
                                  offlineRemedy: "離線來源（本機檔案、掃描檔）改用 judgement 型（statement＋rests_on 指向存檔）")
    }
}
