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

    /// venue 的通用 `references`（#587）——JSON 物件陣列 → `ProvenanceReference`。
    ///
    /// 解析與驗證是 `update_person` 的 references **同一個函式**（`parseReferenceObjects`，#674）：鍵名嚴格、`status` 必填、
    /// `url` 只收 http／https、有界——契約在 `ReferenceWriteParsing.swift`，這裡不重寫。本檔只留 **venue 自己的政策**：
    ///
    /// 1. **空陣列拒絕**：給了卻沒東西要附是呼叫端的錯——#695 起這一句住在 `parseReferenceObjects`，person 面同一句；
    /// 2. **欄位的歸屬**：verdict 三個欄位只經 `resolve-venues` 寫，`paginated` 判定只經 `paginated`／`clear_paginated` 寫——
    ///    那兩條路同時改記錄本身的值與判定史，通用面寫進去會讓判定與值分岔；**通用面自己只收 `issn` 與 `names`**（見 `admitVenueReferenceField`）；
    /// 3. **`field: issn` 的 `value` 以正規形入庫**（識別碼在寫入面正規化，#394）。
    ///
    /// 附著（那個號、那個名字在不在記錄上）要合進記錄才判得出來，在 `updateVenue` 裡以 `validateReferenceAttachment` 驗。
    static func parseVenueReferences(_ raw: [Any]?) throws -> [ProvenanceReference]? {
        guard let raw else { return nil }
        return try parseReferenceObjects(raw, policy: venueReferencePolicy)   // 空陣列在裡面拒絕（#695：兩面同一句）
    }

    static let venueReferencePolicy = ReferenceHolderPolicy(
        admitField: admitVenueReferenceField,
        normalizeValue: { field, value, at in
            guard field == "issn" else { return value }
            // 定位值是一個號，不是 add_issn 的一項——帶角色的寫法在這裡不合法（角色是號的屬性，走 add_issn）
            guard let n = ISSN(value) else {
                throw ServiceError.invalid(
                    "\(at).value「\(displaySafeInvisible(value, max: 80))」不是合法的 ISSN——只給號（NNNN-NNNN）；角色寫在 add_issn")   // display-safe-exempt: at 是字面＋Int
            }
            return n.normalized
        })

    private static func admitVenueReferenceField(_ field: String, at: String) throws {
        if ProvenanceReference.resolutionVerdictFields.contains(field) {
            throw ServiceError.invalid(
                "\(at) 的 field「\(displaySafeInvisible(field, max: 60))」是 resolution verdict——只經 resolve-venues 寫，不收手供")   // display-safe-exempt: at 是字面＋Int
        }
        if field == "paginated" {
            throw ServiceError.invalid(
                "\(at) 的 field「paginated」是判定——改用 paginated／clear_paginated ＋ judgement ＋ rests_on"   // display-safe-exempt: at 是字面＋Int
                + "（那條路同時改記錄的值與判定史；通用面寫進去會讓兩者分岔）")
        }
        // 通用面只收 `issn` 與 `names`（#587 R1 verify，四席指出；整合者裁定）。當時 venue 的 reference **沒有移除面**，所以每多收一格，
        // 就多一個「寫得進去、之後只能手改 YAML 才出得來」的死角。`authorized`：reference 會鎖住 `authorize` 的換名（舊指定被指著時
        // 具名拒絕），對外形之後再也換不了；`note`：note 沒有工具寫入面。issue Expected 只點名 `issn` 那一格。
        // **#673 起移除面存在**（`update-venue --remove-reference`，收 names／authorized／issn／note 四格），「沒有移除面」這個理由自此不成立；
        // `authorized`／`note` 要不要回到通用**寫入**面是使用者的裁決（#673 明寫落地後重新裁決），這裡不動——收窄的範圍維持 #587 R1 的樣子。
        switch field {
        case "issn", "names":
            break
        case "authorized":
            throw ServiceError.invalid(
                "\(at) 的 field「authorized」不收——這一格的 reference 會讓 authorize 換不了對外形（舊指定被 reference 指著時 authorize 具名拒絕），"   // display-safe-exempt: at 是字面＋Int
                + "所以這一格目前不收進通用寫入面（要不要收回是待裁的事，#673）；已存在的 authorized reference 用 update-venue --remove-reference 移除。"
                + "要記「這個名字是對外形」的來源，記在 field: names（value 是那個名字）")
        case "note":
            throw ServiceError.invalid(
                "\(at) 的 field「note」不收——venue 的 note 沒有工具寫入面，附在它上面的 reference 沒有寫入的理由（已存在的 note reference 用 update-venue --remove-reference 移除，#673）；通用面只收 issn 與 names")   // display-safe-exempt: at 是字面＋Int
        default:
            throw ServiceError.invalid(
                "\(at) 的 field「\(displaySafeInvisible(field, max: 60))」不收——通用 references 面只收 issn 與 names（其餘欄位的來源另有專屬寫入面或尚無寫入面）")   // display-safe-exempt: at 是字面＋Int
        }
    }
}
