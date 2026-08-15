import Foundation

/// 對外可稱呼的名字（#81）。
///
/// store 的 `names` 曾以**位置**表達「哪個名字對外」——`docs/store-format.md` §3 的
/// 「第一個是顯示名」。那個約定沒有型別、沒有驗證，任何寫入者重排就會無聲改掉一個人
/// 對外的名字；實測全 store 868 位 person 的第一個名字有 84.6% 是索引系統產生的引用形。
///
/// 這裡把它換成顯式的指定：`authorized` 是 `names` 的**子集**，每個書寫系統至多一個。

/// 名字的書寫系統。
///
/// **只有三個成員，而且刻意不對應 ISO 15924。** 這個型別的用途是切分**同一個實體的**
/// 名字——沒有人同時擁有中文名與日文名，所以 `Jpan` 與 `Hant` 的區別在這裡不存在；
/// 硬要區分只會讓集合變開放、重演「往封閉集合加成員」的相容性問題（#74）。
public enum WritingSystem: String, Equatable, Hashable, CaseIterable, Sendable {
    /// 表意文字（漢字；中日韓共用區塊不再細分，理由見型別註解）。
    case han
    /// 拉丁字母。
    case latn
    /// 兩者皆非——含空字串、純標點、以及本型別尚未刻畫的書寫系統。
    case other

    /// 從字串推導書寫系統。**推導，不儲存**——存下來就多一個可能與值不一致的欄位，
    /// 而本 change 的整個論點就是不要讓表述承擔它承擔不了的語意。
    ///
    /// 判準的優先序有意義：含表意文字即為 `han`（混合字串如「陳素雲 Su-Yun Huang」在
    /// 名冊裡真的存在，而它是一個漢字名而非拉丁名）。
    public static func of(_ name: String) -> WritingSystem {
        var sawLatin = false
        for scalar in name.unicodeScalars {
            if isIdeograph(scalar) { return .han }
            if isLatinLetter(scalar) { sawLatin = true }
        }
        return sawLatin ? .latn : .other
    }

    /// CJK 統一表意文字與其擴展區、相容區。**不含**假名與諺文——那些是拼音文字，
    /// 若日後需要區分會是另一個成員，不是把它們塞進 `han`。
    private static func isIdeograph(_ s: Unicode.Scalar) -> Bool {
        switch s.value {
        case 0x3400...0x4DBF,     // 擴展 A
             0x4E00...0x9FFF,     // 基本區
             0xF900...0xFAFF,     // 相容表意文字
             0x20000...0x2A6DF,   // 擴展 B
             0x2A700...0x2EBEF,   // 擴展 C–F
             0x2F800...0x2FA1F:   // 相容補充
            return true
        default:
            return false
        }
    }

    /// 基本拉丁與拉丁補充的字母（含變音符號）。數字、標點、空白不算——`"—"` 與 `"123"`
    /// 都不是名字，歸 `other` 讓它們在報告裡看得見。
    private static func isLatinLetter(_ s: Unicode.Scalar) -> Bool {
        switch s.value {
        case 0x41...0x5A, 0x61...0x7A,   // A–Z a–z
             0xC0...0x24F:               // Latin-1 補充 + 擴展 A/B
            return true
        default:
            return false
        }
    }
}

/// 名字的形態分類。
///
/// **這裡的結果不進 store。** 它是字串上的純函數，存下來就多一個會過期的事實；而
/// 「哪個名字對外」是**指定**不是推導——分類只負責提名候選（migration）與報告缺口
/// （doctor），指定仍然由人做。
public enum NameForm {

    /// 這個字串是不是索引系統產生的**引用形**（`姓, 名` / `姓, 縮寫`）。
    ///
    /// 判準是逗號兩側都有內容。理由：沒有人以 `Guan, Yongtao` 的形式自稱——那是 WoS 的
    /// `Author Full Names` 欄與 Crossref 作者欄對名字做的變換。實測全 store 1144 個
    /// names 條目中 872 筆（76.2%）是這個形態。
    ///
    /// 逗號只在一側（`", Yongtao"` / `"Guan,"`）**不**算引用形：那是髒資料，不該被
    /// 悄悄降級，該讓它留在「仍然歧義」那一類被人看見。
    public static func isCitationForm(_ name: String) -> Bool {
        guard let comma = name.firstIndex(of: ",") else { return false }
        let surname = name[name.startIndex..<comma]
        let given = name[name.index(after: comma)...]
        return !surname.trimmingCharacters(in: .whitespaces).isEmpty
            && !given.trimmingCharacters(in: .whitespaces).isEmpty
    }
}

extension AuthorizedNames {}

/// `authorized` 的不變式（#81）。person 與 organization **共用**內容約束——
/// 「哪個名字對外」是同一個問題，兩種實體不該有兩套答案。
public enum AuthorizedNames {

    /// 分割互斥（person 專用，#227 verify R1）：同一字串**不得**同時落在 authorized
    /// 與 variant——那讓「同時對外又不對外」成為可表達狀態，序列化出現兩次，違反
    /// spec「A name SHALL occupy exactly one partition」。
    ///
    /// **為什麼在執行期而不是結構**：兩個 `[String]` 的互斥結構表達不了（sum type
    /// 管不到跨陣列的值域），與「每書寫系統至多一個」同屬**內容**約束。與 #229 同
    /// 紀律：檢查住在 `Person.validate()` → `writePerson` 的交會處，不靠呼叫端記得
    /// ——本 change R1 verify 抓到的正是三個呼叫端手動去重、第四個忘了的形狀。
    public static func validateDisjointPartitions(authorized: [String], variant: [String],
                                                  ownerKey: String) -> [ValidationIssue] {
        let overlap = authorized.filter(Set(variant).contains)
        guard !overlap.isEmpty else { return [] }
        let listed = overlap.map { displaySafe($0, max: 80) }.joined(separator: "、")
        return [ValidationIssue(
            severity: .error,
            message: "'\(displaySafe(ownerKey, max: 120))' 的名字「\(listed)」同時出現在 "
                   + "authorized 與 variant 兩個分割——一個名字只屬於一個分割；"
                   + "指定是把名字**搬進** authorized，不是複製")]
    }

    /// **內容**約束（person + organization 共用）：每個書寫系統至多一個——
    /// 同書寫系統兩個 authorized 是**未決的問題**，不是指定。結構管不到內容，
    /// 這條永遠在執行期。
    ///
    /// `ownerKey` 只用於訊息：錯誤要說得出「是誰的哪個字串」，否則在 868 筆記錄裡
    /// 沒人找得到出問題的那一筆。
    public static func validateWritingSystems(authorized: [String],
                                              ownerKey: String) -> [ValidationIssue] {
        var issues: [ValidationIssue] = []
        var byScript: [WritingSystem: [String]] = [:]
        for a in authorized { byScript[WritingSystem.of(a), default: []].append(a) }
        for (script, candidates) in byScript.sorted(by: { $0.key.rawValue < $1.key.rawValue })
        where candidates.count > 1 {
            let listed = candidates.map { displaySafe($0, max: 80) }.joined(separator: "、")
            issues.append(ValidationIssue(
                severity: .error,
                message: "'\(displaySafe(ownerKey, max: 120))' 在書寫系統 \(script.rawValue) 有 "
                       + "\(candidates.count) 個 authorized（\(listed)）"
                       + "——那是未決的問題，不是指定；請選一個"))
        }
        return issues
    }

    /// 兩條不變式（**organization 專用**，#227 起）：
    ///
    /// 1. `authorized` ⊆ `names` —— 指定的是**已記錄的名字**，不是新引進的字串。
    ///    **person 不再走這條**：`PersonNames` 的分割讓子集關係成為結構恆真，
    ///    留一條永遠為真的檢查會讓下一個讀的人以為它還在防什麼（design D2）。
    ///    org 的 names 是**時間軸**（改名有效期），不巢狀化——把 authorized 塞進
    ///    時間軸會讓「對外名字」變成時變的——所以 org 的子集仍需執行期驗證。
    ///    **這個不對稱是刻意的**（design Non-Goals）。
    /// 2. 每個書寫系統至多一個 —— 委派 `validateWritingSystems`。
    public static func validate(authorized: [String], names: [String],
                                ownerKey: String) -> [ValidationIssue] {
        var issues: [ValidationIssue] = []
        let known = Set(names)
        for a in authorized where !known.contains(a) {
            issues.append(ValidationIssue(
                severity: .error,
                message: "'\(displaySafe(ownerKey, max: 120))' 的 authorized 含不在 names 內的名字"
                       + "「\(displaySafe(a, max: 120))」——對外名字是從已記錄的名字裡**指定**，"
                       + "不是另外引進一個字串"))
        }
        issues += validateWritingSystems(authorized: authorized, ownerKey: ownerKey)
        return issues
    }
}
