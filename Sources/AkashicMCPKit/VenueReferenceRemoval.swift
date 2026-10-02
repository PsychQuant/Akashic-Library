import Foundation
import AkashicCore
import AkashicStoreIO
import AkashicIndex

/// #673：venue 的 `references` 的**移除面**（`update-venue --remove-reference`／`akashic_update_venue.remove_reference`），與**讀取面**
/// （`venue`／`akashic_venue` 的 `references`）。
///
/// ## 為什麼有這一條
///
/// #587 起 venue 的 `references` 寫得進去（`issn`／`names`，另有合併把被併者這兩格逐位元組搬過來），卻**刪不掉、也讀不出**：
/// 寫錯或已不再成立的 reference 唯一的出路是手改 YAML——`replace-endnote-and-zotero` 第 4 條要記成缺口的那一種；而 venue 讀取面看不到它們
/// （`verdicts` 與 `paginatedJudgements` 各有自己的鍵，其餘的沒有），定位一筆要移除的 reference 得先開 YAML。
/// 它也是 #587 R1 把 `authorized`／`note` 兩格拿出通用**寫入**面的原因（沒有移除面，每多收一格就多一個死角）。
///
/// ## 移除面一族
///
/// 套用使用者 2026-09-27 對移除面一族（#588／#572／#586／#544／#677）的裁決：**理由必填、只進報告、不寫進 store、不改 store format**，
/// 移除前要求那筆 venue 檔已在 git 裡 commit、乾淨（`assertRecordsRecoverable`——被移除的 reference 只剩 git 那份副本）。
/// 它是**判定**（`two-kinds-of-edits` 的 AI 欄）：「這筆來源記錄不成立」要讀來源才知道。與 `--remove-issn` 一樣沒有乾跑（`update-venue`
/// 整個命令沒有乾跑）——git 閘與整批拒絕零寫入是它的退路。
///
/// ## 契約
///
/// - 參數是 JSON 物件陣列（與 `--references` 同一種形狀，CLI 是一個 JSON 字串）：`{field, value?, reason, …縮小定位的鍵}`。
///   `field` 收 `names`／`authorized`／`issn`／`note`——**通用寫入面只收前兩格，移除面收全部四格**：`authorized`／`note` 的 reference 手改
///   或舊資料可能有，而其中 `authorized` 的會讓 `--authorize` 換不了對外形（訊息叫人「刪掉它們」，在此之前沒有面刪得掉）。
/// - **定位＝`field` ＋ `value`（位元組相等，與寫入面的去重同一把：canonical 相等而位元組不同的是另一筆）**，可再以與 `--references` 同名的鍵
///   （`kind`／`url`／`retrieved`／`status`／`media_type`／`content`／`statement`／`rests_on`）縮小——給了的鍵逐一位元組相等才算命中。
///   `value` 缺席時只命中沒有 value 的（`note`）。**定位不到、定位到多筆都具名拒絕**：多筆時列出各筆的區別（`kind`／`url`／…）讓呼叫端加鍵縮小；
///   位元組完全相同的重複（`byteExactKey` 相同，#582 的重複掃描報它們）不判定要移哪一筆——那是同一筆記錄的兩份，本面不替呼叫端挑。
///   兩個定位指到同一筆同樣拒絕。
/// - **不在本面**：verdict 三欄（`resolution-confirmed`／`-rejected`／`-undecided`）只經 `resolve-venues`（`--demote` 退回 literal 並處理 verdict、
///   `--reject` 寫否決）；`paginated` 的判定只經 `--paginated`／`--clear-paginated`——撤回本身是一筆帶理由與證據的**判定**、翻轉要留史
///   （#500：「丟掉全部 reference 才是刪除，而那違反翻轉留史」），移除面會讓判定與記錄的 `paginated` 值分岔。兩者都具名拒絕並指路。
/// - **縮小鍵只能指名有值的欄位**（Claude 代裁，b13f R1 verify 第 20 列）：沒給的鍵是「不參與比對」，不是「要求缺席」——所以**無法表達「沒有
///   media_type」**。同一個 `(field, value)` 有兩筆 retrieval、只差其中一筆帶 `media_type` 時，給 `media_type` 只選得到帶的那一筆；要移除沒有的那一筆，
///   先移除帶的那一筆、再對剩下的呼叫第二次（拒絕訊息在這個形狀下這樣說）。日後要放寬（例如 `"media_type": null` 表示要求缺席）是可逆的，此刻沒有實例。
/// - 理由 ≤ 4,096 位元組、一次至多 200 筆；輸入錯、定位不到、venue 不存在／無法唯一定位——整批拒絕、零寫入。
/// - **報告（MCP 面）**：`referencesRemoved` 每一筆都列（`field`／`value`／`reason`——**理由是唯一的一份，不截**），只有前 `removalDetailCap`（20）筆多帶
///   reference 的其餘內容（url／statement／rests_on…，第三方字串），其後的省略並以 `detailsTruncated`／`detailsListed` 揭露；CLI 全列。
///   寫檔之後 index 重建失敗時呼叫仍回成功、報告多 `indexRebuilt: false`（`RemovalReportSupport.swift` 說明為什麼不是擲錯）。
/// - **各腿單獨呼叫**（Claude 代裁）：不與 `update-venue` 的任何其他參數組合。其餘腿會改記錄的值、名字分割與同一批的 reference，
///   與「移除的是哪一筆」交錯（例：`--remove-issn` 會連帶刪掉指向該號的 reference，同一次再定位它就落空），而 `update-entry` 的四條腿早已是這個形；
///   日後要放寬是可逆的，要收窄不是。
/// - **只移除 reference，不動它指的值**：`issn` 的來源被移除，那個號仍在（移除號是 `--remove-issn`）；`names` 的來源被移除，那個名字仍在。
///
/// ## 誠實邊界
///
/// - **`authorized`／`note` 是否回到通用寫入面**沒有動（#673 明寫落地後重新裁決）：本面只保證有了出路，寫入面的收窄與否是使用者的裁決。
/// - 位元組完全相同的重複 reference 沒有移除路徑（上一節）。現況 live store 為零（2026-09-29 實測 485 筆 venue 帶非 verdict、非 paginated 的
///   reference 0 筆）。
/// - 定位靠呼叫端逐字給出 `value`：讀取面的 `references` 逐字消毒且有長度上限（`value` 200 字元、`url`／`statement` 300），超過上限的值讀取面看到的是被截的形——
///   那種 reference 要對照 YAML。
extension AkashicService {

    /// 讀取面 `references` 至多列幾筆。**25 是選的數字，沒有量測依據**：live store 的通用 reference 是 0 筆（2026-09-29 唯讀量測 485 筆 venue），沒有分布可依；
    /// 量級考量是一本刊的 ISSN（通常不超過 3 個）與名字各有幾筆來源記錄，25 留一個數量級的餘裕（推估）。超過的以 `referencesTotal`／`referencesTruncated` 揭露
    /// （CLI 與 MCP 同一條路徑，沒有有記錄的差異）。
    ///
    /// **它限的是筆數，不保證輸出位元組**（b13f R1 verify 第 19／23／27 列——首版寫成「單筆約 1.4 KB、25 筆約 35 KB、在 48 KiB 之內」，三處錯）：
    /// (1) 1.4 KB 是把各字串的**字元**上限相加（value 200、url／statement 各 300、retrieved／media_type 各 60、digest 71、`rests_on` 前 5 個），拿字元當位元組——
    /// CJK 一個字元 3 位元組；`displaySafe` 在逃脫模式數輸入 scalar，一個控制字元逃成 `\u{XXXX}`（8 字元）、JSON 序列化再把反斜線加倍，最壞（retrieval：value 200＋url 300＋retrieved 與 media_type 各 60 個 scalar 全是控制字元，每個約 9 個輸出位元組）每筆約 6 KB、
    /// 25 筆約 150 KB（推估）。(2) 48 KiB 是 `tools/list` 與 `candidateByteBudget`（resolve 候選、doctor 的 per-record 清單）的預算，**`akashic_venue` 沒有單一輸出預算**——
    /// 同一個 payload 的 `works` 編年清單本來就無界（live：`psychological-methods` 1,352 筆、每筆標題至多 500 字元）。所以這個上限不是位元組界線，
    /// 只是不讓 `references` 這一段跟著一本異常刊無限長。要限位元組得另設預算（如 `candidateByteBudget` 的形），此刻沒有實例。
    public static let venueReferencesCap = 25

    /// MCP 面移除報告（`referencesRemoved`）裡，前幾筆多帶 reference 的其餘內容（url／statement／rests_on…，第三方字串）；其後的只回 `field`／`value`／`reason`。
    /// **理由不截**——它只在報告裡有一份（`RemovalReportSupport.swift`／`sourcesAddedCap` 的 doc 同一條）。CLI 全列。
    public static let removalDetailCap = 20

    /// `referenceDict` 的 `rests_on` 只列前幾個 digest（同 `verdicts` 的未決記錄：前 5 個 ＋ 總數）。
    static let referenceDictRestsOnCap = 5

    /// 通用面與移除面都不涵蓋的欄位由 `parseVenueReference` 與這裡各自具名拒絕；移除面收的四格。
    static let removableVenueReferenceFields = ["names", "authorized", "issn", "note"]

    /// 這三格的 reference 必帶 value（`Venue.validateReferenceAttachment`：值要在記錄的清單內）；`note` 是純量、不帶。
    private static let valueBearingVenueReferenceFields: Set<String> = ["names", "authorized", "issn"]

    static let removeReferenceJSONKeys: Set<String> = referenceJSONKeys.union(["reason"])

    /// 一筆移除的定位與理由（只看參數的解析結果，#654 的形）。縮小定位的鍵 nil＝沒給、不參與比對。
    struct RemoveReferenceSpec {
        let field: String
        let value: String?
        let kind: String?
        let url: String?
        let retrieved: String?
        let status: Int?
        let mediaType: String?
        let content: String?
        let statement: String?
        let restsOn: [String]?
        let reason: String
    }

    // MARK: - 參數解析

    /// `remove_reference` 的形狀：陣列非空、上限、每項是物件、鍵封閉、欄位在收的四格內、value 的必帶、理由。nil ＝ 這次沒給。
    static func parseRemoveReferenceSpecs(_ raw: [Any]?) throws -> [RemoveReferenceSpec] {
        guard let raw else { return [] }
        guard !raw.isEmpty else {
            throw ServiceError.invalid("remove_reference 是空陣列——沒有要移除的 reference 就不要給這個參數")
        }
        guard raw.count <= maxReferencesPerCall else {
            throw ServiceError.invalid("remove_reference 一次最多 \(maxReferencesPerCall) 筆（這次 \(raw.count) 筆）——分次送")   // display-safe-exempt: maxReferencesPerCall 與 raw.count 是 Int
        }
        return try raw.enumerated().map { i, item in try parseRemoveReferenceSpec(item, index: i) }
    }

    private static func parseRemoveReferenceSpec(_ item: Any, index i: Int) throws -> RemoveReferenceSpec {
        let at = "remove_reference[\(i)]"   // display-safe-exempt: i 是 Int
        guard let obj = item as? [String: Any] else {
            throw ServiceError.invalid("\(at) 必須是物件（{field, value?, reason, …}）")   // display-safe-exempt: at 是字面＋Int
        }
        let unknown = obj.keys.filter { !removeReferenceJSONKeys.contains($0) }.sorted()
        if !unknown.isEmpty {
            throw ServiceError.invalid(
                "\(at) 有不認得的鍵「\(Self.listCapped(unknown) { displaySafeInvisible($0, max: 60) })」——"   // display-safe-exempt: at 是字面＋Int
                + "合法的鍵：" + removeReferenceJSONKeys.sorted().joined(separator: "、"))   // display-safe-exempt: removeReferenceJSONKeys 是本檔的字面集合
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
        guard let field = try string("field"), !field.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ServiceError.invalid("\(at) 缺 field（要移除哪個欄位的 reference）")   // display-safe-exempt: at 是字面＋Int
        }
        if ProvenanceReference.resolutionVerdictFields.contains(field) {
            throw ServiceError.invalid(
                "\(at) 的 field「\(displaySafeInvisible(field, max: 60))」是 resolution verdict——它們是判定，不在本面：" +   // display-safe-exempt: at 是字面＋Int
                "resolve-venues --demote 把已歸戶的邊退回 literal 並處理那筆 verdict，--reject 寫否決；記下查過未決用 --undecided")
        }
        if field == "paginated" {
            throw ServiceError.invalid(
                "\(at) 的 field「paginated」是判定——撤回用 --clear-paginated（MCP clear_paginated）：撤回本身是一筆帶理由與證據的判定、翻轉要留史，"   // display-safe-exempt: at 是字面＋Int
                + "而移除面會讓判定與記錄的 paginated 值分岔")
        }
        if field == NameClassificationRecord.variantField {
            throw ServiceError.invalid(
                "\(at) 的 field「variant」只有名字分類的判定記錄——判定史不在移除面（#564）：要改分類用 --authorize／--unauthorize／--add-variant"   // display-safe-exempt: at 是字面＋Int
                + "（MCP authorize／unauthorize／add_variant，都要理由）；要連記錄一起刪掉一個打錯的名字，先撤回它，再用 --edit-name-segment 的 remove（MCP edit_name_segment；#564 第 2 點）")
        }
        guard removableVenueReferenceFields.contains(field) else {
            throw ServiceError.invalid(
                "\(at) 的 field「\(displaySafeInvisible(field, max: 60))」不是 venue 的 reference 欄位——移除面收 "   // display-safe-exempt: at 是字面＋Int
                + removableVenueReferenceFields.joined(separator: "、"))   // display-safe-exempt: removableVenueReferenceFields 是本檔的字面
        }
        let value = try string("value")
        if valueBearingVenueReferenceFields.contains(field), value == nil {
            throw ServiceError.invalid("\(at) 的 field「\(field)」要帶 value（指名那一筆 reference 支持的值）")   // display-safe-exempt: at 是字面＋Int；field 已限定為封閉集合之一
        }
        guard let reason = try string("reason", cap: maxStatementBytes),
              !reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ServiceError.invalid(
                "\(at) 缺理由（reason）或理由是空白——移除是判定，要寫為什麼這筆 reference 不成立；報告與 commit 靠它")   // display-safe-exempt: at 是字面＋Int
        }
        var kind: String?
        if let k = try string("kind") {
            guard ["retrieval", "judgement"].contains(k) else {
                throw ServiceError.invalid("\(at) 的 kind 必須是 retrieval 或 judgement")   // display-safe-exempt: at 是字面＋Int
            }
            kind = k
        }
        var status: Int?
        if let v = obj["status"], !(v is NSNull) {
            guard let n = v as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID(), let exact = Int(exactly: n.doubleValue) else {
                throw ServiceError.invalid("\(at).status 必須是整數（HTTP 狀態碼）")   // display-safe-exempt: at 是字面＋Int
            }
            status = exact
        }
        var restsOn: [String]?
        if let v = obj["rests_on"], !(v is NSNull) {
            guard let arr = v as? [Any], let strs = arr as? [String], strs.count == arr.count else {
                throw ServiceError.invalid("\(at).rests_on 必須是字串陣列（sha256: digest）")   // display-safe-exempt: at 是字面＋Int
            }
            guard strs.count <= maxRestsOnPerCall else {
                throw ServiceError.invalid("\(at).rests_on 最多 \(maxRestsOnPerCall) 個 digest（這次 \(strs.count) 個）")   // display-safe-exempt: at 是字面＋Int；maxRestsOnPerCall 與 strs.count 是 Int
            }
            restsOn = strs
        }
        return RemoveReferenceSpec(field: field, value: value, kind: kind, url: try string("url"), retrieved: try string("retrieved"),
                                   status: status, mediaType: try string("media_type"), content: try string("content"),
                                   statement: try string("statement", cap: maxStatementBytes), restsOn: restsOn, reason: reason)
    }

    // MARK: - 定位

    private static func sameBytes(_ a: String?, _ b: String?) -> Bool {
        switch (a, b) {
        case (nil, nil): return true
        case (let x?, let y?): return Array(x.utf8) == Array(y.utf8)
        default: return false
        }
    }

    /// 這筆存下來的 reference 是不是被這個定位命中：`field` 與 `value` 位元組相等，給了的縮小鍵逐一位元組相等。
    private static func matches(_ r: ProvenanceReference, _ s: RemoveReferenceSpec) -> Bool {
        guard sameBytes(r.field, s.field), sameBytes(r.value, s.value) else { return false }
        switch r.kind {
        case .retrieval(let url, let retrieved, let status, let mediaType, let content):
            if s.kind == "judgement" || s.statement != nil || s.restsOn != nil { return false }
            if let u = s.url, !sameBytes(u, url) { return false }
            if let x = s.retrieved, !sameBytes(x, retrieved) { return false }
            if let st = s.status, st != status { return false }
            if let m = s.mediaType, !sameBytes(m, mediaType) { return false }
            if let c = s.content, !sameBytes(c, content) { return false }
        case .judgement(let statement, let restsOn):
            if s.kind == "retrieval" || s.url != nil || s.retrieved != nil || s.status != nil || s.mediaType != nil || s.content != nil { return false }
            if let st = s.statement, !sameBytes(st, statement) { return false }
            if let ro = s.restsOn, ro.map({ Array($0.utf8) }) != restsOn.map({ Array($0.utf8) }) { return false }
        }
        return true
    }

    /// 一筆 reference 的一行描述（已消毒）——「定位到多筆」時列出，讓呼叫端知道加哪個鍵縮小。
    private static func oneLine(_ r: ProvenanceReference) -> String {
        switch r.kind {
        case .retrieval(let url, let retrieved, let status, let mediaType, let content):
            let media = mediaType.map { displaySafeInvisible($0, max: 60) } ?? "（無）"
            return "retrieval url=\(displaySafeInvisible(url, max: 160)) retrieved=\(displaySafeInvisible(retrieved, max: 60)) status=\(status) media_type=\(media) content=\(content)"   // display-safe-exempt: status 是 Int；media 與 url／retrieved 已消毒；content 由 isValidDigest 保證只含 sha256: 與小寫十六進位
        case .judgement(let statement, let restsOn):
            return "judgement statement=\(displaySafeInvisible(statement, max: 160)) rests_on=\(restsOn.count) 個"   // display-safe-exempt: restsOn.count 是 Int
        }
    }

    /// 每個定位恰好命中一筆（回傳 `venue.references` 的位置）；定位不到、多筆、兩個定位指到同一筆都具名拒絕。
    static func locateVenueReferences(_ specs: [RemoveReferenceSpec], in venue: Venue, venueKey: String) throws -> [Int] {
        var located: [Int] = []
        var claimedBy: [Int: Int] = [:]
        let listed = 5
        for (n, s) in specs.enumerated() {
            let at = "remove_reference[\(n)]"   // display-safe-exempt: n 是 Int
            // #564：名字分類的判定記錄不是本面的對象（判定史不刪）——定位只看其他 reference；只命中名字分類記錄時具名拒絕並指路
            let matched = venue.references.indices.filter { matches(venue.references[$0], s) }
            let hits = matched.filter { !NameClassificationRecord.isRecord(venue.references[$0]) }
            let what = "field「\(displaySafeInvisible(s.field, max: 60))」" + (s.value.map { " value「\(displaySafeInvisible($0, max: 200))」" } ?? "（沒有 value）")
            if hits.isEmpty, !matched.isEmpty {
                throw ServiceError.invalid(
                    "\(at)：\(what) 命中的是 \(matched.count) 筆名字分類的判定記錄（「指定／確認／撤回：…」）——判定史不在移除面（#564）；"   // display-safe-exempt: at 是字面＋Int；what 已消毒；matched.count 是 Int
                    + "要改分類用 --authorize／--unauthorize（MCP authorize／unauthorize，都要理由）；要連記錄一起刪掉一個打錯的名字，先撤回它，"
                    + "再用 --edit-name-segment 的 remove（MCP edit_name_segment；最後一筆記錄要是撤回，#564 第 2 點）；整批拒絕、零寫入")
            }
            guard !hits.isEmpty else {
                let same = venue.references.filter { $0.field == s.field }
                let seen = same.isEmpty
                    ? "這筆 venue 上沒有 field「\(displaySafeInvisible(s.field, max: 60))」的 reference"
                    : "這筆 venue 上 field「\(displaySafeInvisible(s.field, max: 60))」的 reference 共 \(same.count) 筆，value："   // display-safe-exempt: same.count 是 Int
                        + same.prefix(listed).map { "「" + displaySafeInvisible($0.value ?? "（無）", max: 120) + "」" }.joined(separator: "、")
                        + (same.count > listed ? "…（共 \(same.count) 筆）" : "")   // display-safe-exempt: same.count 是 Int
                throw ServiceError.invalid(
                    "\(at)：venue「\(displaySafeInvisible(venueKey, max: 200))」沒有 \(what) 的 reference（定位用位元組相等；帶了 kind／url／…時它們也要相符）——\(seen)；整批拒絕、零寫入")   // display-safe-exempt: at 是字面＋Int；what 與 seen 各段已逐項消毒
            }
            guard hits.count == 1 else {
                let keys = Set(hits.map { venue.references[$0].byteExactKey })
                let list = hits.prefix(listed).map { "· " + oneLine(venue.references[$0]) }.joined(separator: "\n")
                if keys.count == 1 {
                    throw ServiceError.invalid(
                        "\(at)：\(what) 有 \(hits.count) 筆位元組完全相同的重複 reference——本面不替呼叫端挑哪一筆（#582 的重複掃描報它們）；整批拒絕、零寫入")   // display-safe-exempt: at 是字面＋Int；what 已消毒；hits.count 是 Int
                }
                // 縮小鍵只能指名有值的欄位——「沒有 media_type」寫不出來（檔頭〈契約〉）：命中的 retrieval 裡有帶有不帶 media_type 的，要把這件事說出來
                let mediaPresence = Set(hits.compactMap { i -> Bool? in
                    if case .retrieval(_, _, _, let m, _) = venue.references[i].kind { return m != nil }
                    return nil
                })
                let mediaHint = mediaPresence.count == 2
                    ? "\n注意：縮小鍵只能指名有值的欄位，寫不出「沒有 media_type」——想移除沒有 media_type 的那一筆，先移除帶 media_type 的那一筆（給 media_type），再對剩下的呼叫第二次"
                    : ""
                throw ServiceError.invalid(
                    "\(at)：\(what) 定位到 \(hits.count) 筆——加 kind／url／retrieved／status／media_type／content／statement／rests_on 縮小到一筆：\n"   // display-safe-exempt: at 是字面＋Int；what 已消毒；hits.count 是 Int
                    + list + (hits.count > listed ? "\n…（共 \(hits.count) 筆）" : "") + mediaHint + "\n整批拒絕、零寫入")   // display-safe-exempt: list 的每一行已逐項消毒；hits.count 是 Int；mediaHint 是字面
            }
            let idx = hits[0]
            if let prior = claimedBy[idx] {
                throw ServiceError.invalid(
                    "remove_reference[\(prior)] 與 [\(n)] 指到同一筆 reference（\(what)）——一筆只移除一次；整批拒絕、零寫入")   // display-safe-exempt: prior 與 n 是 Int；what 已消毒
            }
            claimedBy[idx] = n
            located.append(idx)
        }
        return located
    }

    // MARK: - 移除

    /// `update-venue` 的入口在確認參數合法、且沒有其他腿之後呼叫。載入、定位、git 閘、移除、寫入、重建 index；回報。
    func removeVenueReferences(key: String, specs: [RemoveReferenceSpec], detailLimit: Int? = AkashicService.removalDetailCap) throws -> String {
        let load = try store.load()
        // #670：key 重複時寫進哪一筆是猜——整批拒絕、零寫入（同 #627 對 citekey）
        guard !load.venues.unlocatableVenueKeys.contains(key) else {
            throw ServiceError.invalid("venue「\(displaySafeInvisible(key, max: 200))」無法唯一定位（\(UnlocatableReason.venue)）——整批拒絕、零寫入；先改掉其中一筆的 key")
        }
        guard var venue = load.venues.first(where: { $0.key == key }) else {
            throw ServiceError.notFound("venue「\(displaySafeInvisible(key, max: 200))」")
        }
        let located = try Self.locateVenueReferences(specs, in: venue, venueKey: key)
        try assertRecordsRecoverable([(venue.id, "venue「\(displaySafeInvisible(key, max: 200))」")],
                                     action: "這次會從 venue「\(displaySafeInvisible(key, max: 200))」移除 \(specs.count) 筆 reference",   // display-safe-exempt: specs.count 是 Int
                                     issue: "#673")
        // MCP 面只有前 `detailLimit` 筆帶 reference 的其餘內容；其後的只回 field／value／reason（理由只在報告裡有一份，不截）。CLI 傳 nil 全列
        let removedItems: [[String: Any]] = zip(specs, located).enumerated().map { n, pair in
            let (spec, idx) = pair
            var item: [String: Any]
            if detailLimit.map({ n < $0 }) ?? true {
                item = Self.referenceDict(venue.references[idx])
            } else {
                item = ["field": displaySafeInvisible(spec.field, max: 120)]
                if let v = venue.references[idx].value { item["value"] = displaySafe(v, max: 200) }
            }
            // 理由不進 store，報告是它唯一的一份——不截在入口上限之下（#588 R1 verify 的同一條）
            item["reason"] = displaySafe(spec.reason, max: Self.maxStatementBytes)   // display-safe-exempt: reason 是呼叫端原文、在這裡消毒一次
            return item
        }
        let gone = Set(located)
        venue.references = venue.references.enumerated().filter { !gone.contains($0.offset) }.map(\.element)
        try store.writeVenue(venue)
        let rebuildFailure = rebuildIndexCapturingFailure()
        var payload: [String: Any] = [
            "key": displaySafe(key, max: 200),
            "referencesRemoved": removedItems,
            "referencesTotal": venue.references.filter { Self.isGenericVenueReference($0) }.count,   // display-safe-exempt: Int
            "reasonNote": "理由只在這份報告裡——要留在 git，寫進接下來的 commit message（#673，使用者 2026-09-27 對移除面一族的裁決）",
            "valueNote": "只移除 reference：它指的號或名字仍在記錄上（移除號用 --remove-issn）",
        ]
        if let limit = detailLimit, specs.count > limit {
            payload["detailsTruncated"] = true   // display-safe-exempt: Bool
            payload["detailsListed"] = limit   // display-safe-exempt: Int
        }
        if let rebuildFailure { Self.noteIndexRebuildFailure(rebuildFailure, in: &payload) }
        return try jsonString(payload)
    }

    // MARK: - 讀取面

    /// 通用面的 reference：不是 verdict、不是 `paginated` 的判定（那兩類各有自己的讀取鍵與寫入面）。
    static func isGenericVenueReference(_ r: ProvenanceReference) -> Bool {
        !ProvenanceReference.resolutionVerdictFields.contains(r.field) && r.field != "paginated"
    }

    /// 一筆 reference 的輸出形（讀取面與移除報告共用）：鍵名同 `--references` 的輸入（`media_type`／`statement`／`rests_on`），
    /// 讀取面看到的就是移除面收的形狀。字串逐一消毒且有長度上限（超過上限的形只用來認得，定位仍以 YAML 的逐字值為準）；
    /// `rests_on` 只列前 5 個、多的以 `rests_on_total` 揭露（縮小定位可用的 `rests_on` 要給逐字的完整陣列，這裡看到的前 5 個不足以對照時看 YAML）。
    static func referenceDict(_ r: ProvenanceReference) -> [String: Any] {
        var d: [String: Any] = ["field": displaySafeInvisible(r.field, max: 120)]
        if let v = r.value { d["value"] = displaySafe(v, max: 200) }
        switch r.kind {
        case .retrieval(let url, let retrieved, let status, let mediaType, let content):
            d["kind"] = "retrieval"
            d["url"] = displaySafe(url, max: 300)
            d["retrieved"] = displaySafe(retrieved, max: 60)
            d["status"] = status   // display-safe-exempt: Int
            if let m = mediaType { d["media_type"] = displaySafe(m, max: 60) }
            d["content"] = content   // display-safe-exempt: digest 由 isValidDigest 保證只含 sha256: 與小寫十六進位
        case .judgement(let statement, let restsOn):
            d["kind"] = "judgement"
            d["statement"] = displaySafe(statement, max: 300)
            d["rests_on"] = Array(restsOn.prefix(referenceDictRestsOnCap))   // display-safe-exempt: Array 取自 restsOn（每個 digest 由 isValidDigest 保證只含 sha256: 與小寫十六進位），referenceDictRestsOnCap 是 Int
            if restsOn.count > referenceDictRestsOnCap { d["rests_on_total"] = restsOn.count }   // display-safe-exempt: Int
        }
        return d
    }
}
