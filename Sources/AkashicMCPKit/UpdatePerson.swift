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
    ///     清除，與「未提及」不同）；`names` 收 `{authorized:[…], variant:[…]}` object
    ///     （全量替換；#227 巢狀化後平坦陣列拒收）；
    ///     `profile` 收維度 object（**維度級**覆寫——提及的維度全量替換、未提及的
    ///     維度保留），段的形狀與 YAML 相同（value/start/end/ended/source/note）。
    ///   - dryRun: true 時零寫入，回報會改什麼 + gate 預演。
    /// #308：JSON 陣列 → ProvenanceReference 逐筆 append（冪等；verdict 欄位對拒收）。
    /// 回傳實際附加筆數。
    private func appendReferences(_ raw: Any, to person: inout Person) throws -> Int {
        guard let arr = raw as? [[String: Any]] else {
            throw ServiceError.invalid("references 必須是 object 陣列（append-only）")
        }
        var added = 0
        for item in arr {
            guard let field = item["field"] as? String, !field.isEmpty else {
                throw ServiceError.invalid("reference 缺 field")
            }
            guard !ProvenanceReference.resolutionVerdictFields.contains(field) else {
                throw ServiceError.invalid(
                    "欄位對「\(displaySafeInvisible(field, max: 60))」是 resolution verdict——"
                    + "只能經 resolve 流程（apply／reject）寫，不收手供")
            }
            let value = item["value"] as? String
            let kind: ProvenanceReference.Kind
            switch item["kind"] as? String {
            case "retrieval":
                guard let url = item["url"] as? String,
                      let retrieved = item["retrieved"] as? String,
                      let content = item["content"] as? String else {
                    throw ServiceError.invalid("retrieval reference 需 url／retrieved／content（sha256: digest）")
                }
                kind = .retrieval(url: url, retrieved: retrieved,
                                  status: item["status"] as? Int ?? 200,
                                  mediaType: item["media_type"] as? String,
                                  content: content)
            case "judgement":
                guard let statement = item["statement"] as? String else {
                    throw ServiceError.invalid("judgement reference 需 statement")
                }
                kind = .judgement(statement: statement,
                                  restsOn: item["rests_on"] as? [String] ?? [])
            default:
                throw ServiceError.invalid("reference kind 需 retrieval 或 judgement")
            }
            let ref = ProvenanceReference(field: field, value: value, kind: kind)
            // append-only 的去重比**位元組**（R26 D73；R25 verify 第 7／25／29 列：三個 `==` 全是 canonical，只差 NFC／NFD 的一筆曾被靜默吞掉）
            guard !person.references.contains(where: { $0.byteExactKey == ref.byteExactKey }) else { continue }
            person.references.append(ref)
            added += 1
        }
        return added
    }

    func updatePerson(key: String, fields: [String: Any], dryRun: Bool) throws -> String {
        let load = try store.load()   // 寫前重讀（同 AppState.mutate 的防 lost-update 語意）
        guard var person = load.people.first(where: { $0.key == key }) else {
            throw ServiceError.notFound("person「\(displaySafeInvisible(key, max: 200))」")
        }
        // 白名單由 decoder 的 known keys **推導**，不手寫清單——手寫清單就是
        // 「第二份定義」：#75 的 prefers、#66 的 references 落地時自動納入，
        // 不必記得回來改這裡（diagnosis 的設計裁決）。
        let updatable = PersonYAML.updatableKeys
        var changes: [String: Any] = [:]

        for (k, raw) in fields.sorted(by: { $0.key < $1.key }) {
            guard updatable.contains(k) else {
                throw ServiceError.invalid(
                    "不認得的欄位「\(displaySafeInvisible(k, max: 120))」——可更新："
                    + updatable.sorted().joined(separator: "、")
                    + "（id／key／type 是結構性鍵，不可經部分更新改動）")
            }
            switch k {
            case "orcid":
                // 寫入面驗證即拒絕（design.md 的寫入契約）：形狀不合法的值不得
                // 進 store，錯誤具名該值與預期形狀——與讀取面 fail-closed 同方向，
                // 但這裡是使用者當下能看到並修正的錯誤，不是事後才發現的 quarantine。
                if let raw = try scalarOrNull(raw, field: k) {
                    guard let o = ORCID(raw) else {
                        throw ServiceError.invalid(
                            "欄位「orcid」的值「\(displaySafeInvisible(raw, max: 120))」不是合法的 ORCID"
                            + "（\(ORCID.shapeDescription)）")   // display-safe-exempt: 型別的靜態常數（預期形狀說明），非 store 內容
                    }
                    person.orcid = o
                } else {
                    person.orcid = nil
                }
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
                // #227：巢狀形狀（{authorized:[…], variant:[…]}，全量替換）。平坦
                // 陣列是舊形狀——與 decoder 同紀律，拒絕而非靜默解讀。
                person.names = try personNames(raw, field: k)
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
            case "references":
                // #308：**append-only**——與其他欄位「提及即整換」的契約刻意不同，
                // 因為 references 同時持有 resolution verdict（封閉欄位對 #232）：
                // 全量替換等於洗掉判定史。verdict 欄位對在此拒收（只能經 resolve
                // 流程寫）；append 以 (field, value) 冪等（appendIfAbsent 同款）。
                let added = try appendReferences(raw, to: &person)
                changes[k] = "append \(added)"
            default:
                // updatableKeys 推導自 decoder；decoder 認得而這裡沒接的欄位
                // **大聲說**，不靜默吞——推導超前實作時這是唯一的誠實出口
                throw ServiceError.invalid(
                    "欄位「\(displaySafeInvisible(k, max: 200))」是 decoder 認得、但部分更新入口尚未支援的欄位")
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
                    .map { displaySafeClipOnly($0.message, max: 300) }   // display-safe-exempt: 已消毒（validate() 的訊息在生產端 displaySafeInvisible，R28 D80），只截——R27 verify 第 17 列
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
                + validationErrors.prefix(5).map { "- " + displaySafeClipOnly($0.message, max: 300) }   // display-safe-exempt: 已消毒（同上），只截
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

    /// #227：names 的巢狀形狀。平坦陣列給出**點名新形狀**的錯誤——與 YAML decoder
    /// 對平坦 `names:` 的拒絕同紀律，兩個入口不得有兩套答案。
    private func personNames(_ v: Any, field: String) throws -> PersonNames {
        if v is [Any] {
            throw ServiceError.invalid(
                "欄位「\(field)」收 object（{authorized:[…], variant:[…]}，全量替換）"   // display-safe-exempt: field 是白名單字面量
                + "——平坦字串陣列是 format < 10 的舊形狀，不靜默解讀")
        }
        guard let dict = v as? [String: Any] else {
            throw ServiceError.invalid("欄位「\(field)」必須是 object（{authorized:[…], variant:[…]}）")   // display-safe-exempt: 同上
        }
        var names = PersonNames(authorized: [], variant: [])
        for (kk, vv) in dict.sorted(by: { $0.key < $1.key }) {
            switch kk {
            case "authorized":
                names.authorized = try stringList(vv, field: "\(field).authorized")
            case "variant":
                names.variant = try stringList(vv, field: "\(field).variant")
            default:
                throw ServiceError.invalid(
                    "names 只有 authorized 與 variant 兩個分割，不認得「\(displaySafeInvisible(kk, max: 120))」")
            }
        }
        // #227 verify R1：分割互斥在入口早擋（validate 也會擋，但這裡能給更準的訊息）
        if let dup = names.authorized.first(where: Set(names.variant).contains) {
            throw ServiceError.invalid(
                "「\(displaySafeInvisible(dup, max: 120))」同時出現在 authorized 與 variant——"
                + "一個名字只屬於一個分割；指定是搬移，不是複製")
        }
        return names
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
