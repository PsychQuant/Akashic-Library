import Foundation
import AkashicCore

/// #587：venue 的 ISSN 帶得了角色、venue 的 `references` 有通用寫入面。
///
/// 兩個缺口都在寫入面：store 早有 `issn[].qualifier`（format 13）與 `Venue.validateReferenceAttachment` 的 `case "issn"`
/// （#394 §5），缺的是收得下它們的參數。本檔只放**只看參數**的解析（CLI 的 `validate()` 與服務在讀 store 之前共用），
/// 落到記錄上的那一半在 `updateVenue`／`addVenue`。
extension AkashicService {

    // MARK: - ISSN 的角色

    /// `add_issn`／`add_venue.issn` 解析後的結果。
    struct ParsedISSNItems {
        /// 去重後（相等看正規形；同一個號一個帶角色、一個不帶時留帶角色的）
        let issns: [ISSN]
        /// 整項空白的原字串——不寫，回報（#556 R2 verify：先前靜默略過）
        let dropped: [String]
    }

    /// 一項是 `NNNN-NNNN`，或 `NNNN-NNNN (print|electronic|linking)`（#587）。
    ///
    /// **為什麼是括號寫法、不是另一個參數**：它就是遷移讀的那種寫法（`1939-1455(Electronic)`，`IdentifierTokenizer` 的同一套
    /// 切法），也是 Crossref／Zotero 給角色的樣子；`add_issn` 因此仍是一個字串陣列，兩面都不必長出第二個參數。
    ///
    /// **比遷移嚴**：`IdentifierTokenizer.singleQualified` 要求恰好一個號、至多一個緊跟的註記；角色必須是 ISSN 標準的三個角色之一
    /// ——遷移對認不出的寫法（`Online`）保留原值並在 validate 報 warning，那是讀別人資料的寬容；寫入面收的是呼叫端這一次說的話，
    /// 認不出就拒絕，不寫一個 validate 會報的值。入庫寫封閉值域的寫法（`print`），不寫呼叫端的大小寫。
    ///
    /// **既有寫法照收**：整串先試 `ISSN(_:)`——它本來就收空白與無連字號（`0003 066X`），那些不得因為多了括號的解析而改判。
    /// 邊界（#587 R1 verify regression 第 67 列）：那句只對**沒有角色**的形成立——`0003 066X (print)`（空白分隔又帶角色）會被拒：
    /// 整串的 `ISSN(_:)` 因為多了括號而不是 8 個字元，`IdentifierTokenizer.singleQualified` 又把空白切成兩個 token。
    /// 無連字號的 `1935990x (electronic)` 是一個 token，可行。拒絕是具名、整批零寫入；要帶角色就寫 `NNNN-NNNN (角色)`。
    static func parseISSNItems(_ raws: [String]?, parameter: String) throws -> ParsedISSNItems? {
        guard let raws else { return nil }
        var out: [ISSN] = []
        var dropped: [String] = []
        for r in raws {
            let trimmed = r.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { dropped.append(r); continue }
            let one: ISSN
            if let bare = ISSN(trimmed) {
                one = bare
            } else {
                guard let pair = IdentifierTokenizer.singleQualified(trimmed, field: "issn"),
                      let number = ISSN(pair.value) else {
                    throw ServiceError.invalid(
                        "\(parameter)「\(displaySafeInvisible(r, max: 80))」不是合法的 ISSN——形狀是 NNNN-NNNN（末位可為大寫 X），"   // display-safe-exempt: parameter 是呼叫端參數名的編譯期常量
                        + "可緊跟一個角色：NNNN-NNNN (print)；一項一個號。拒絕整個呼叫，零寫入")
                }
                if let q = pair.qualifier {
                    guard let medium = ISSNMedium(loose: q) else {
                        throw ServiceError.invalid(
                            "\(parameter)「\(displaySafeInvisible(r, max: 80))」的角色「\(displaySafeInvisible(q, max: 40))」"   // display-safe-exempt: parameter 是編譯期常量
                            + "不是 ISSN 標準的三個角色（print／electronic／linking）——例：Online 寫 electronic。拒絕整個呼叫，零寫入")
                    }
                    one = number.withQualifier(medium.rawValue)
                } else {
                    one = number
                }
            }
            // 同一次呼叫同一個號兩個不同角色：兩句矛盾的話
            if let prior = out.first(where: { $0 == one }), let a = prior.medium, let b = one.medium, a != b {
                throw ServiceError.invalid(
                    "\(parameter) 對 ISSN「\(one.normalized)」說了兩個角色（\(a.rawValue)、\(b.rawValue)）——請只說一個")   // display-safe-exempt: parameter 是編譯期常量；one.normalized 只含 [0-9X-]；a／b 的 rawValue 是 enum 常數
            }
            IdentifierTokenizer.mergePreferringQualified(one, into: &out)
        }
        return ParsedISSNItems(issns: out, dropped: dropped)
    }

    // MARK: - references

    /// JSON 物件的鍵名——**與 `update_person` 的 references 相同**（`media_type`／`statement`／`rests_on`），不是 YAML 的
    /// `media-type`／`judgement`／`rests-on`。鍵是嚴格的：不認得的鍵整批拒絕（person 側會靜默忽略它，#587 不沿用那個寬容）。
    static let referenceJSONKeys: Set<String> = [
        "field", "value", "kind", "url", "retrieved", "status", "media_type", "content", "statement", "rests_on",
    ]

    /// 一次呼叫至多幾筆（與未決腿同一個量級：CLI 單批 triage）。有界拒絕，不截斷。
    static let maxReferencesPerCall = 200

    /// venue 的通用 `references`（#587）——JSON 物件陣列 → `ProvenanceReference`。
    ///
    /// **形狀驗證走平面 init**（`ProvenanceReference.init(field:value:url:…)`，YAML decode 的同一個入口）：擷取型四欄必要、兩種
    /// 互斥、判斷型的 rests-on 非空、digest 的形狀與「不是空內容的 digest」——那套規則只有一份，這裡不重寫。
    /// 寫入面自己只多四件事，都是 init 管不到的（#587 R1 起 field 也收窄成 `issn`／`names`，理由在下方 switch）：
    /// 1. **鍵名嚴格**、型別不猜（`status` 要是整數——boolean 與 200.5 不是，#542 R2：不預設 200）；
    /// 2. **`kind` 必須與給的欄位一致**（init 從在場的欄位推 kind；呼叫端說 retrieval 卻只給了 statement，是兩句不一致的話）；
    /// 3. **欄位的歸屬**：verdict 三個欄位只經 `resolve-venues` 寫，`paginated` 判定只經 `paginated`／`clear_paginated` 寫——
    ///    那兩條路同時改記錄本身的值與判定史，通用面寫進去會讓判定與值分岔；**通用面自己只收 `issn` 與 `names`**（R1）；
    /// 4. **有界**：一次至多 `maxReferencesPerCall` 筆、`statement` 至多 `maxStatementBytes` 位元組、`rests_on` 至多 `maxRestsOnPerCall`
    ///    個、其餘字串各至多 `AddOnlyEnrichment.maxValueBytes`（`enrich` 對來源字串的同一個上限）。
    ///
    /// `field: issn` 的 `value` 以正規形入庫（識別碼在寫入面正規化，#394）。附著（那個號、那個名字在不在記錄上）要合進記錄才判得出來，
    /// 在 `updateVenue` 裡以 `validateReferenceAttachment` 驗。
    static func parseVenueReferences(_ raw: [Any]?) throws -> [ProvenanceReference]? {
        guard let raw else { return nil }
        guard !raw.isEmpty else {
            throw ServiceError.invalid("references 是空陣列——沒有要附的 reference 就不要給這個參數")
        }
        guard raw.count <= maxReferencesPerCall else {
            throw ServiceError.invalid("references 一次最多 \(maxReferencesPerCall) 筆（這次 \(raw.count) 筆）——分次送")   // display-safe-exempt: maxReferencesPerCall 與 raw.count 是 Int
        }
        return try raw.enumerated().map { i, item in try parseVenueReference(item, index: i) }
    }

    private static func parseVenueReference(_ item: Any, index i: Int) throws -> ProvenanceReference {
        let at = "references[\(i)]"   // display-safe-exempt: i 是 Int
        guard let obj = item as? [String: Any] else {
            throw ServiceError.invalid("\(at) 必須是物件（{field, value?, kind, …}）")   // display-safe-exempt: at 是字面＋Int
        }
        let unknown = obj.keys.filter { !referenceJSONKeys.contains($0) }.sorted()
        if !unknown.isEmpty {
            throw ServiceError.invalid(
                "\(at) 有不認得的鍵「\(Self.listCapped(unknown) { displaySafeInvisible($0, max: 60) })」——"   // display-safe-exempt: at 是字面＋Int
                + "合法的鍵：" + referenceJSONKeys.sorted().joined(separator: "、")   // display-safe-exempt: referenceJSONKeys 是本檔的字面集合
                + "（判斷型的斷言鍵是 statement，同 update_person）")
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
        if ProvenanceReference.resolutionVerdictFields.contains(field) {
            throw ServiceError.invalid(
                "\(at) 的 field「\(displaySafeInvisible(field, max: 60))」是 resolution verdict——只經 resolve-venues 寫，不收手供")   // display-safe-exempt: at 是字面＋Int
        }
        if field == "paginated" {
            throw ServiceError.invalid(
                "\(at) 的 field「paginated」是判定——改用 paginated／clear_paginated ＋ judgement ＋ rests_on"   // display-safe-exempt: at 是字面＋Int
                + "（那條路同時改記錄的值與判定史；通用面寫進去會讓兩者分岔）")
        }
        // 通用面只收 `issn` 與 `names`（#587 R1 verify，四席指出；整合者裁定）。venue 的 reference **沒有移除面**，所以每多收一格，
        // 就多一個「寫得進去、之後只能手改 YAML 才出得來」的死角。`authorized`：reference 會鎖住 `authorize` 的換名（舊指定被指著時
        // 具名拒絕），對外形之後再也換不了；`note`：note 沒有工具寫入面。issue Expected 只點名 `issn` 那一格。
        switch field {
        case "issn", "names":
            break
        case "authorized":
            throw ServiceError.invalid(
                "\(at) 的 field「authorized」不收——這一格的 reference 會讓 authorize 換不了對外形（舊指定被 reference 指著時 authorize 具名拒絕），"   // display-safe-exempt: at 是字面＋Int
                + "而 venue 的 reference 沒有移除面，只能手改 YAML。要記「這個名字是對外形」的來源，記在 field: names（value 是那個名字）")
        case "note":
            throw ServiceError.invalid(
                "\(at) 的 field「note」不收——venue 的 note 沒有工具寫入面，附在它上面的 reference 沒有面能移除；通用面只收 issn 與 names")   // display-safe-exempt: at 是字面＋Int
        default:
            throw ServiceError.invalid(
                "\(at) 的 field「\(displaySafeInvisible(field, max: 60))」不收——通用 references 面只收 issn 與 names（其餘欄位的來源另有專屬寫入面或尚無寫入面）")   // display-safe-exempt: at 是字面＋Int
        }
        guard let kindName = try string("kind"), ["retrieval", "judgement"].contains(kindName) else {
            throw ServiceError.invalid("\(at) 的 kind 必須是 retrieval 或 judgement")   // display-safe-exempt: at 是字面＋Int
        }
        var status: Int?
        if let v = obj["status"], !(v is NSNull) {
            guard let n = v as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID(),
                  let exact = Int(exactly: n.doubleValue) else {
                throw ServiceError.invalid("\(at).status 必須是整數（HTTP 狀態碼；離線來源改用 judgement 型）")   // display-safe-exempt: at 是字面＋Int
            }
            status = exact
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
        var value = try string("value")
        if field == "issn", let v = value {
            // 定位值是一個號，不是 add_issn 的一項——帶角色的寫法在這裡不合法（角色是號的屬性，走 add_issn）
            guard let n = ISSN(v) else {
                throw ServiceError.invalid(
                    "\(at).value「\(displaySafeInvisible(v, max: 80))」不是合法的 ISSN——只給號（NNNN-NNNN）；角色寫在 add_issn")   // display-safe-exempt: at 是字面＋Int
            }
            value = n.normalized
        }
        let reference: ProvenanceReference
        do {
            reference = try ProvenanceReference(
                field: field, value: value,
                url: try string("url"), retrieved: try string("retrieved"), status: status,
                mediaType: try string("media_type"), content: try string("content"),
                judgement: try string("statement", cap: maxStatementBytes), restsOn: restsOn)
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
}
