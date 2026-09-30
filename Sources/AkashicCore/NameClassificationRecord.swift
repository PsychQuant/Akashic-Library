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
    public static func parse(_ statement: String) -> (action: Action, reason: String)? {
        for action in Action.allCases {
            let prefix = action.rawValue + separator
            guard statement.hasPrefix(prefix) else { continue }
            let reason = String(statement.dropFirst(prefix.count))
            guard !reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            return (action, reason)
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

    /// append-only：與既有 reference（含同一批稍早的一筆）**位元組**完全相同的不再寫（`byteExactKey`，同 `update-person` 的
    /// references）。回傳實際寫下的筆數。第二次以同一句理由確認同一個名字不會長出第二筆。
    @discardableResult
    public static func append(_ new: [ProvenanceReference], to refs: inout [ProvenanceReference]) -> Int {
        var present = Set(refs.map(\.byteExactKey))
        var written = 0
        for r in new where present.insert(r.byteExactKey).inserted {
            refs.append(r)
            written += 1
        }
        return written
    }

    /// 某個名字在某個分割上的記錄（相等看 `NameIdentity.canonical`，與寫入面定位名字同一把）。
    public static func records(in refs: [ProvenanceReference], field: String, name: String) -> [ProvenanceReference] {
        let key = NameIdentity.canonical(name)
        return refs.filter { r in
            r.field == field && isRecord(r) && r.value.map { NameIdentity.canonical($0) == key } == true
        }
    }
}
