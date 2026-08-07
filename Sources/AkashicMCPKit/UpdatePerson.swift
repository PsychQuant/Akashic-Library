import Foundation
import Yams
import AkashicCore
import AkashicStoreIO
import AkashicIndex

/// #68：person 的部分更新入口。
///
/// 外部 pipeline 手刻 YAML 合併是 storyline 五輪 verify 的實證病灶——合併該由
/// 既有的 decoder → 改 → encoder 走完，tolerant-preserve 與 canary 白拿。
///
/// 契約：**提及的欄位整個換、未提及一律不動**。timeline 的「只加一段」刻意不做
/// ——增量語意（同 range 段替換還是並存）是 #100/#75 的未決區，在定案前給增量
/// API 會把未決語意焊進參數形狀（diagnosis 裁決）。
public extension AkashicService {

    /// - Parameters:
    ///   - fields: 結構化欄位值（JSON object）。純量欄位收 String 或 null（null＝
    ///     清除，與「未提及」不同）；`names`/`authorized` 收字串陣列（全量替換）；
    ///     `profile` 收維度 object（**維度級**覆寫——提及的維度全量替換、未提及的
    ///     維度保留），段的形狀與 YAML 相同（value/start/end/ended/source/note）。
    ///   - dryRun: true 時零寫入，回報會改什麼 + gate 預演。
    func updatePerson(key: String, fields: [String: Any], dryRun: Bool) throws -> String {
        let load = try store.load()   // 寫前重讀（同 AppState.mutate 的防 lost-update 語意）
        guard var person = load.people.first(where: { $0.key == key }) else {
            throw ServiceError.notFound("person「\(displaySafe(key, max: 200))」")
        }
        // 白名單由 decoder 的 known keys **推導**，不手寫清單——手寫清單就是
        // 「第二份定義」：#75 的 prefers、#66 的 references 落地時自動納入，
        // 不必記得回來改這裡（diagnosis 的設計裁決）。
        let updatable = PersonYAML.updatableKeys
        var changes: [String: Any] = [:]

        for (k, raw) in fields.sorted(by: { $0.key < $1.key }) {
            guard updatable.contains(k) else {
                throw ServiceError.invalid(
                    "不認得的欄位「\(displaySafe(k, max: 120))」——可更新："
                    + updatable.sorted().joined(separator: "、")
                    + "（id／key／type 是結構性鍵，不可經部分更新改動）")
            }
            switch k {
            case "orcid":
                person.orcid = try scalarOrNull(raw, field: k)
                changes[k] = raw
            case "openalex":
                person.openalex = try scalarOrNull(raw, field: k)
                changes[k] = raw
            case "died":
                person.died = try scalarOrNull(raw, field: k)
                changes[k] = raw
            case "note":
                person.note = try scalarOrNull(raw, field: k)
                changes[k] = raw
            case "names":
                person.names = try stringList(raw, field: k)
                changes[k] = raw
            case "authorized":
                person.authorized = try stringList(raw, field: k)
                changes[k] = raw
            case "profile":
                guard let dims = raw as? [String: Any] else {
                    throw ServiceError.invalid("profile 必須是 object（維度 → 段清單）")
                }
                for (dim, segs) in dims.sorted(by: { $0.key < $1.key }) {
                    let node = try Self.jsonToNode(segs)
                    // 與 YAML decode **同一條路**：形狀驗證、ended 矛盾防線、
                    // null-face 拒收全部白拿——同一個概念只有一套判準
                    try PersonYAML.decodeProfileDimension(dim, node: node, into: &person.profile)
                    changes["profile.\(dim)"] = segs
                }
            default:
                // updatableKeys 推導自 decoder；decoder 認得而這裡沒接的欄位
                // **大聲說**，不靜默吞——推導超前實作時這是唯一的誠實出口
                throw ServiceError.invalid(
                    "欄位「\(k)」是 decoder 認得、但部分更新入口尚未支援的欄位")
            }
        }

        // #148 verify F4：names 全量替換可讓 authorized 懸空（authorized ⊆ names 的
        // 不變式只活在 Person.validate()，writePerson 不跑它）。部分更新是獨特的
        // 暴露面——替換 names 的呼叫端本來就沒在想 authorized。error 等級拒絕，
        // dry-run 一併預演。
        let validationErrors = person.validate().filter { $0.severity == .error }
        if dryRun {
            var out: [String: Any] = [
                "dryRun": true,
                "key": displaySafe(key, max: 200),
                // #156 × #158 交會後浮現：`changes` 的 key 是 `k`，而 `k` 已被
                // `guard updatable.contains(k)` + 下方 `switch k { case "orcid" … }`
                // 雙重約束成那六個**字面量**之一（`updatableKeys` 由 `knownPersonKeys`
                // 這個字面 Set 推導）。不是 store 內容。
                "wouldChange": changes.keys.sorted(),   // display-safe-exempt: key 受 updatable 白名單約束成字面量
            ]
            if !validationErrors.isEmpty {
                out["blockedByValidation"] = validationErrors.prefix(5)
                    .map { displaySafe($0.message, max: 300) }
            }
            // gate 預演（#131 的 v6 gate）：不預演的 dry-run 會說「會改」而
            // real run 被擋——dry-run 就成了謊言（diagnosis 明列的要求）
            if person.profile.usesEndedUnknown {
                let format = try StoreVersion.read(root: root)
                if format < 6 {
                    out["blockedByFormatGate"] =
                        "real run 會被拒：ended 段需要 store format ≥ 6（本 store 是 \(format)）"
                        + "——確認所有 binary 已升級後把 store.yaml 的 format: 改成 6"
                }
            }
            return try jsonString(out)
        }

        guard validationErrors.isEmpty else {
            throw ServiceError.invalid(
                "更新後的記錄無法通過驗證（error 等級），拒絕寫入：\n"
                + validationErrors.prefix(5).map { "- " + displaySafe($0.message, max: 300) }
                    .joined(separator: "\n"))
        }
        try store.writePerson(person)   // v6 gate／canary／tolerant-preserve 全在這條路上
        try LibraryIndex(store: store).rebuild()
        return try jsonString(["key": displaySafe(key, max: 200),
                               "updated": changes.keys.sorted()])   // display-safe-exempt: 同上，key 受白名單約束
    }

    // MARK: - JSON 邊界

    private func scalarOrNull(_ v: Any, field: String) throws -> String? {
        if v is NSNull { return nil }
        guard let s = v as? String else {
            throw ServiceError.invalid("欄位「\(field)」必須是字串或 null")   // display-safe-exempt: field 是呼叫端已過 updatable/switch 白名單的字面量，非 store 內容
        }
        return s
    }

    private func stringList(_ v: Any, field: String) throws -> [String] {
        guard let arr = v as? [Any], let strings = arr as? [String] else {
            throw ServiceError.invalid("欄位「\(field)」必須是字串陣列（全量替換）")   // display-safe-exempt: 同上
        }
        return strings
    }

    /// JSON 值 → Yams Node（遞迴）。**Bool 判定先於 Int**：JSON 的 true/false 進
    /// `[String: Any]` 後是 NSNumber，`as? Int` 對它也成立——順序反了 `ended: true`
    /// 會變成 `ended: 1` 被 decode 拒收。
    ///
    /// **深度上限 64**（#148 verify F3）：fields 是本 MCP 面唯一收任意巢狀 JSON 的
    /// 參數，200–700 層的巢狀會炸掉遞迴堆疊、整個 server 進程無聲死亡——而 SDK 的
    /// transport 守衛（~800 層才擋）比這裡鬆。合法 profile 段深度 ≤ 4，64 綽綽有餘。
    static func jsonToNode(_ v: Any, depth: Int = 0) throws -> Node {
        guard depth <= 64 else {
            throw ServiceError.invalid("fields 的巢狀深度超過 64——合法欄位結構深度 ≤ 4，"
                + "這不是任何可更新欄位的形狀")
        }
        if v is NSNull { return Node("null", Tag(.null)) }
        if let num = v as? NSNumber {
            if CFGetTypeID(num) == CFBooleanGetTypeID() {
                // style 顯式 .plain：ended 的 decode 只收裸寫 true/false（#131 F4 慣例）
                return .scalar(.init(num.boolValue ? "true" : "false", Tag(.bool), .plain))
            }
            if let i = v as? Int { return Node("\(i)", Tag(.int)) }
            return Node("\(num)", Tag(.float))
        }
        if let s = v as? String { return Node(s) }
        if let arr = v as? [Any] { return try Node(arr.map { try jsonToNode($0, depth: depth + 1) }) }
        if let dict = v as? [String: Any] {
            return try Node(dict.sorted { $0.key < $1.key }
                .map { (Node($0.key), try jsonToNode($0.value, depth: depth + 1)) })
        }
        throw ServiceError.invalid("無法轉換的 JSON 值型別：\(type(of: v))")   // display-safe-exempt: Swift 型別名，非資料
    }
}
