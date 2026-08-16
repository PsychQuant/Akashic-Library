import Foundation

/// 寬鬆比對鍵生成（#303 design D1）。與 `NameNormalization` 並列住 core——
/// resolver 與任何未來消費端共用**單一定義**（#140 的教訓：bootstrap 與 resolver
/// 各留一份正規化，分裂後主流程靜默掉候選）。
///
/// **鍵只用於配對，永不用於判定、永不外洩成資料**（`matchingKey` 檔頭鐵律的延伸）：
/// 同鍵只代表「值得提名給人看」，apply 仍是使用者顯式確認後的第二步。
///
/// 兩個 tier 的鍵空間（封閉列舉，spec person-resolution）：
/// - **reorder**（L1）：token 集合相等、順序無關——`Hsu, Yung-Fong` ↔ `Yung-Fong Hsu`
/// - **initials**（L2）：姓＋首字母——`Chen, Y.-H.` ↔ `Chen, Yi-Hau`
///
/// 羅馬化異拼（Hsu↔Xu）**刻意不在任何鍵空間收斂**——那是查表域，失效模式與
/// 機械正規化不同，重啟需要 spec 層的新裁決。
public enum LooseNameKey {

    /// L1：token 重排鍵。`matchingKey` 之上剝除逗號句點、token 排序。
    /// 連字號**留在 token 內**（`yung-fong` 是一個 token）——剝掉會讓
    /// `Yung-Fong` 與 `Yung Fong` 塌縮成不同 token 數，反而破壞重排等價。
    public static func reorderKey(_ s: String) -> String {
        tokens(of: s).sorted().joined(separator: " ")
    }

    /// L2：姓＋首字母鍵（0～2 個）。
    ///
    /// - **有逗號＝姓氏已標定**（逗號前是姓）→ 恰一鍵
    /// - **無逗號不猜**——姓前／姓後兩種解讀各生一鍵（可能重合，Set 去重）
    /// - **只對含拉丁字母的名字生鍵**：CJK 姓名取首字母無意義（spec scenario:
    ///   CJK name skips initials tier）；單 token 沒有 given 部分，同樣不生
    ///
    /// initials＝各 given token 逐連字號段取首字母串接（`Chun-Houh`→`ch`、
    /// `Y.-H.`→`yh`、`Mary Jane`→`mj`）。
    public static func initialsKeys(_ s: String) -> Set<String> {
        let normalized = NameNormalization.matchingKey(s)
        guard normalized.unicodeScalars.contains(where: isLatinLetter) else { return [] }

        if let comma = normalized.firstIndex(of: ",") {
            let family = cleanTokens(String(normalized[..<comma]))
            let given = cleanTokens(String(normalized[normalized.index(after: comma)...]))
            return Set([initialsKey(family: family, given: given)].compactMap { $0 })
        }
        let toks = cleanTokens(normalized)
        guard toks.count >= 2 else { return [] }
        // 姓後（西式：姓是**最後**一個 token）與姓前兩種解讀——不偏好任何一種
        // （spec: SHALL NOT guess family-name position）
        let familyLast = initialsKey(family: [toks.last!], given: Array(toks.dropLast()))
        let familyFirst = initialsKey(family: [toks.first!], given: Array(toks.dropFirst()))
        return Set([familyLast, familyFirst].compactMap { $0 })
    }

    // MARK: - 內部

    /// 逗號句點剝除後的 token 序列（保留連字號）。
    private static func tokens(of s: String) -> [String] {
        cleanTokens(NameNormalization.matchingKey(s))
    }

    /// `.` 映成 `-` 而非刪除（R1-fix B5）：刪除會把 `Y.H.` 塌成單段 `yh`、initials
    /// 只取到 `y`——與 `Y.-H.`（`y-h`→`yh`）分岔，真 store 曾因此錯提名
    /// （`L.W. Wang` 的 `l` 撞上 `Wang, Limei` 的 `wang l`）。映成 `-` 讓句點與
    /// 連字號同為分段界；隨後逐 token 收斂連續 `-` 並修剪首尾，`y.-h.` 與 `y.h.`
    /// 同歸 `y-h`——reorder 與 initials 兩個鍵空間一致受益。
    private static func cleanTokens(_ s: String) -> [String] {
        s.replacingOccurrences(of: ",", with: " ")
            .replacingOccurrences(of: ".", with: "-")
            .split(whereSeparator: \.isWhitespace)
            .compactMap { raw -> String? in
                var collapsed = ""
                for ch in raw {
                    if ch == "-", collapsed.last == "-" { continue }
                    collapsed.append(ch)
                }
                let trimmed = collapsed.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
                return trimmed.isEmpty ? nil : trimmed
            }
    }

    /// `<family> <initials>`；given 的 initials 為空（無拉丁字母）→ 不生鍵。
    private static func initialsKey(family: [String], given: [String]) -> String? {
        guard !family.isEmpty else { return nil }
        let initials = given.flatMap { token in
            token.split(separator: "-").compactMap { seg in
                seg.unicodeScalars.first(where: isLatinLetter).map(Character.init)
            }
        }
        guard !initials.isEmpty else { return nil }
        // 姓氏部分也要含拉丁字母——「鄭, Ch」這種混形不生鍵（保守側）
        guard family.joined().unicodeScalars.contains(where: isLatinLetter) else { return nil }
        return family.joined(separator: " ") + " " + String(initials)
    }

    private static func isLatinLetter(_ scalar: Unicode.Scalar) -> Bool {
        ("a"..."z").contains(scalar) || ("A"..."Z").contains(scalar)
    }
}
