import Foundation

/// 名字分類的判定記錄（#564，Spectra change `name-classification-judgement`）。
///
/// ## 為什麼有它
///
/// 「這個名字是對外形」「這個名字是異寫」「撤回那個指定」都是判定（`two-kinds-of-edits` 的 AI 欄：留 verdict、必附理由、可回溯）。
/// 名字分類的五個面——person 的 `authorize-names`、venue 的 `--add-variant`／`--authorize`／`--unauthorize`、organization 的
/// `--authorize`（organization 沒有撤回腿：`--unauthorize` 於 #557 R1 verify 之後拿掉，待使用者裁決）——在此之前都不留記錄；同一個 `updateVenue` 裡的 `paginated`（#406）卻留。使用者 2026-10-01 裁決：
/// 一律留，含對既有值說「確認」。合併端因此分得出人判定過的 authorized 與 bootstrap 的機械值（`DivergenceResolve`）。
///
/// ## 形狀
///
/// 一筆記錄是 `references` 裡的判斷型 reference：`field` 是它說的分割（`authorized`／`variant`）、`value` 是名字、statement 是
/// `<動作>：<理由>`。動作是**封閉三值**（指定／確認／撤回），不得類推第四個；解析只有 `parse` 一份——形狀取自作者位記錄
/// （`拆為 ⟦a⟧ ⟦b⟧：理由`／`移除：理由`，`SplitRecordValue`／`AuthorRemovalRecordValue`）：同一個 field 住多種記錄，由 statement
/// 前綴分辨。
///
/// ## 錨定在 names，不在分割
///
/// 撤回記錄與被換下的名字的記錄描述的正是已經離開分割的名字，所以附著條件是「value 是這筆記錄的名字之一」
/// （`validateReferenceAttachment` 的名字分類分支）。分類的現況仍是分割清單本身；記錄是 provenance，不是狀態。
public enum NameClassificationRecord {

    /// 兩個分割的欄位名。**封閉集合**：person 與 organization 只收 `authorized`（person 的 variant 分割是「其他名字」，沒有判定面；
    /// organization 沒有 variant），venue 兩個都收。
    public static let authorizedField = "authorized"
    public static let variantField = "variant"
    public static let fields: Set<String> = [authorizedField, variantField]

    /// 封閉三值——不得依性質相似類推第四個（`common-spec-prose-enumeration`）。
    public enum Action: String, CaseIterable, Sendable {
        /// 這個名字成為那個分割的成員
        case designate = "指定"
        /// 對已經是成員的名字再說一次（先前是無聲的 no-op，#564 的第 3 點）
        case confirm = "確認"
        /// 這個名字離開那個分割（`--unauthorize`；或被同書寫系統替換、被抬出 variant 的連帶撤回）
        case withdraw = "撤回"
    }

    /// 動作與理由之間的分隔（全形冒號，與作者位記錄的 `移除：` 同形）。
    public static let separator = "："

    public static func statement(_ action: Action, reason: String) -> String {
        action.rawValue + separator + reason
    }

    /// 單一解析器：前綴恰是三個動作之一加全形冒號、其後的理由去空白後非空，回傳動作與理由（理由原樣，不去空白）；否則 nil。
    ///
    /// **前綴比的是 Unicode scalar，不是 Character**（#564 R1 verify security 第 6 列）：`String.hasPrefix` 以 grapheme cluster 比，
    /// 理由若以 Grapheme_Extend 字元（U+0301、ZWJ／ZWNJ、CGJ、變體選擇子……）開頭，它會與全形冒號併成同一個 cluster，前綴就比不上——
    /// 寫入面回報「寫了一筆記錄」，store 裡卻是一筆一般的 `field: authorized` reference（移除面刪得掉、合併端看不見）。寫入面另外
    /// 拒收這種理由（`reasonIssue`），這裡讓已經在庫裡的那種仍被認成記錄（它對一般 reference 的附著條件更寬，不會因此被隔離）。
    public static func parse(_ statement: String) -> (action: Action, reason: String)? {
        let scalars = statement.unicodeScalars
        for action in Action.allCases {
            let prefix = (action.rawValue + separator).unicodeScalars
            guard scalars.starts(with: prefix) else { continue }
            let reason = String(String.UnicodeScalarView(scalars.dropFirst(prefix.count)))
            guard !reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            return (action, reason)
        }
        return nil
    }

    /// 寫入面收的理由有什麼問題（`nil`＝可以用）。呼叫端先去掉前後空白再問。**venue／organization／person 的名字分類腿與
    /// `authorize-names` 共用這一份**（#564 R1 verify security 第 6／19／33／34 列）：
    ///
    /// 1. **開頭不得是組合符號、格式或不可見字元**（Grapheme_Extend、Default_Ignorable、Cc／Cf／Mn／Mc／Me）——它會與動作前綴的
    ///    全形冒號併成同一個字，記錄的文法因此在只看 Character 的讀者那裡讀不出來；也是「看起來是空的理由」的開頭。
    /// 2. **至少一個字母或數字**（generalCategory 的 L／N 類，與名字不變式同一個謂詞 `NameIdentity.isLetterOrDigit`）——只有
    ///    U+2060、U+FEFF、U+3164 一類不可見字元的理由滿足了「必填」的字面、卻什麼都沒說。
    /// 3. **組成的 statement 要解析得回這句理由**（防線：`parse(statement(_, reason))` 回同一句）。
    public static func reasonIssue(_ reason: String) -> String? {
        guard let first = reason.unicodeScalars.first else { return "是空白" }
        let p = first.properties
        let leadingBad: Set<Unicode.GeneralCategory> = [.control, .format, .nonspacingMark, .spacingMark, .enclosingMark]
        if p.isGraphemeExtend || p.isDefaultIgnorableCodePoint || leadingBad.contains(p.generalCategory) {
            let h = String(first.value, radix: 16, uppercase: true)
            let code = String(repeating: "0", count: max(0, 4 - h.count)) + h
            return "以組合符號、格式或不可見字元 U+\(code) 開頭——它會與動作前綴的全形冒號併成同一個字，記錄讀不出來；刪掉它，或在前面寫字"   // display-safe-exempt: code 是十六進位碼位（[0-9A-F]+）
        }
        guard reason.unicodeScalars.contains(where: NameIdentity.isLetterOrDigit) else {
            return "沒有任何字母或數字——理由要說出為什麼"
        }
        for action in Action.allCases where parse(statement(action, reason: reason))?.reason != reason {
            return "組成的「\(action.rawValue)：理由」解析不回這句理由"   // display-safe-exempt: action.rawValue 是 enum 常數
        }
        return nil
    }

    /// 這筆 reference 是不是名字分類記錄：field 是兩個分割之一、帶 value、判斷型、statement 符合文法。
    public static func isRecord(_ r: ProvenanceReference) -> Bool {
        guard fields.contains(r.field), r.value != nil,
              case .judgement(let statement, _) = r.kind else { return false }
        return parse(statement) != nil
    }

    public static func make(field: String, name: String, action: Action, reason: String,
                            restsOn: [String]) -> ProvenanceReference {
        ProvenanceReference(field: field, value: name,
                            kind: .judgement(statement: statement(action, reason: reason), restsOn: restsOn))
    }

    /// append-only：與**同一個名字、同一個分割的最後一筆記錄**（含同一批稍早的一筆）**位元組**完全相同的不再寫（`byteExactKey`）。
    /// 回傳實際寫下的筆數。第二次以同一句理由確認同一個名字不會長出第二筆。
    ///
    /// **只比最後一筆，不比整份歷史**（#564 R1 verify：b26 F1 第 1／2／5／13 列、F2 第 3 列，五席同指）：記錄是有順序的狀態歷史，
    /// 讀它的人（與合併拒絕的「最後一筆：…」）按位置讀。先前對整份 references 去重，「指定：R → 撤回：S → 指定：R」的第三筆與第一筆
    /// 位元組相同而被丟掉——名字回到了 authorized，記錄卻以「撤回」結尾，回報還說 `judgementsRecorded: 0`；organization 的「換下再換回」
    /// 同形（換回的那筆「指定」被丟）。一個與上一筆相反的動作是一次新的轉移，不是重複。
    ///
    /// 不是名字分類記錄的不寫、不算（寫入面的理由檢查 `reasonIssue` 保證這裡收到的都是；這一道讓回報的筆數不可能與 store 不符）。
    @discardableResult
    public static func append(_ new: [ProvenanceReference], to refs: inout [ProvenanceReference]) -> Int {
        var written = 0
        for r in new {
            guard isRecord(r), let name = r.value else {
                assertionFailure("NameClassificationRecord.append 收到一筆不是名字分類記錄的 reference")
                continue
            }
            if let last = latestRecord(in: refs, field: r.field, name: name), last.byteExactKey == r.byteExactKey { continue }
            refs.append(r)
            written += 1
        }
        return written
    }

    /// 某個名字在某個分割上的最後一筆記錄（相等看 `NameIdentity.canonical`）。
    public static func latestRecord(in refs: [ProvenanceReference], field: String, name: String) -> ProvenanceReference? {
        let key = NameIdentity.canonical(name)
        return refs.last { r in
            r.field == field && isRecord(r) && r.value.map { NameIdentity.canonical($0) == key } == true
        }
    }

    /// 某個名字（不分分割）的最後一筆記錄的動作——#564 的修正輪（使用者 2026-10-02 裁決第 2 點）：最後一筆是「撤回」的名字可以連同
    /// 它的記錄一起刪（打錯字的名字的出路）。沒有記錄回 nil。相等看 `NameIdentity.canonical`。
    public static func latestAction(in refs: [ProvenanceReference], name: String) -> Action? {
        let key = NameIdentity.canonical(name)
        guard let last = refs.last(where: { r in
            fields.contains(r.field) && isRecord(r) && r.value.map { NameIdentity.canonical($0) == key } == true
        }), case .judgement(let statement, _) = last.kind else { return nil }
        return parse(statement)?.action
    }

    /// 某個名字的全部記錄（不分分割）——刪名字時一併刪的那幾筆。
    public static func allRecords(in refs: [ProvenanceReference], name: String) -> [ProvenanceReference] {
        let key = NameIdentity.canonical(name)
        return refs.filter { r in
            fields.contains(r.field) && isRecord(r) && r.value.map { NameIdentity.canonical($0) == key } == true
        }
    }

    /// 某個名字在某個分割上的記錄（相等看 `NameIdentity.canonical`，與寫入面定位名字同一把）。
    public static func records(in refs: [ProvenanceReference], field: String, name: String) -> [ProvenanceReference] {
        let key = NameIdentity.canonical(name)
        return refs.filter { r in
            r.field == field && isRecord(r) && r.value.map { NameIdentity.canonical($0) == key } == true
        }
    }
}
