import Foundation
import AkashicCore
import AkashicStoreIO
import AkashicIndex

/// #675：venue `names` 的**名字段編輯面**（`update-venue --edit-name-segment`／`akashic_update_venue.edit_name_segment`）。
///
/// ## 為什麼有這一條
///
/// `names` 的每一段（`TemporalValue`）可以帶時間欄位（`start`／`end`／`ended`／`attested`）、`source`、`note`，但**沒有任何工具面能改它們**：
/// `--add-name` 只加新的名字，`--authorize` 與 `--add-variant` 只改分類。#565 起，venue 合併遇到「同名、而時間／source／note 不同、又不是可並存的
/// 沿革」的兩段會具名拒絕——出路只有手改 YAML，而那是 `replace-endnote-and-zotero` 第 4 條要記成缺口的那一種（沒有型別檢查、沒有 round-trip、沒有原子性）。
///
/// ## 它是判定，走移除面一族的裁決
///
/// 「這一段的時間是錯的」「這一段不該存在」要讀來源才知道，字串謂詞做不出來（`two-kinds-of-edits` 的 AI 欄）。套用使用者 2026-09-27 對移除面一族
/// （#588／#572／#586／#544／#673）的裁決：**理由必填、只進報告、不寫進 store、不改 store format**，改寫前要求那筆 venue 檔已在 git 裡 commit、乾淨
/// （`assertRecordsRecoverable`——改寫前的位元組只剩 git 那份副本）。與 `--remove-issn`／`--remove-reference` 一樣沒有乾跑（`update-venue` 整個命令沒有乾跑）——
/// git 閘與整批拒絕零寫入是它的退路。
///
/// ## 契約
///
/// 參數是 JSON 物件陣列（一次至多 200 筆）；每項 `{name, match?, set | remove, reason}`：
///
/// - `name`：要改的那一段的名字，**相等看 canonical**（與 `add_names`／`add_variant`／`authorize` 同一把）。
/// - `match`（選填）：同名不只一段時縮小到一段。可用的鍵同 `set`（`start`／`end`／`ended`／`attested`／`source`／`note`）；**給了的鍵都要相符**，
///   字串與陣列比 UTF-8 位元組（與 `--remove-reference` 的定位同一把——canonical 相等而位元組不同的是另一段）。**`null` 表示「要求缺席」**
///   （`"start": null` 選沒有起點的那一段；`"ended": false`、`"attested": []` 同理）——這與 `--remove-reference` 的縮小鍵刻意不同：那邊寫不出「沒有 media_type」，
///   而 #565 的拒絕形狀恰是「一段有 source、另一段沒有」，選不到沒有的那一段就修不了。
/// - `set`：要改的欄位，逐鍵覆寫、**沒給的鍵不動**。字串鍵（`start`／`end`／`source`／`note`）給字串是設定、給 `null` 是清除；`ended` 是布林
///   （`false` 是清除）；`attested` 是字串陣列（`[]` 或 `null` 是清除）。改完的時間欄位要成立：不得矛盾（`end` 與 `ended: true` 並存、`attested` 與
///   起訖並存——與 YAML 邊界同一份判準，`DateRange.contradictionDescription`）、`start`／`end` 與 `attested` 是 ISO 8601 前綴、`start` 不晚於 `end`
///   （`Venue.nameSegmentRangeIssue`）。`source`／`note` 給字串時不得是空白、至多 65,536 位元組。
/// - `remove: true`：刪掉這一段。與 `set` 擇一。
/// - `reason`：理由，必填、至多 4,096 位元組。
///
/// 全部定位在**呼叫前的記錄**上（不依陣列順序）；**定位不到、定位到多段、兩項指到同一段、位元組完全相同的重複段都具名拒絕**，多段時列出各段的
/// 區別讓呼叫端加 `match` 縮小。改完的記錄要不違反任何 store 不變式（`Venue.validate()` 的 error）——**這次造出的**違反在寫之前具名拒絕
/// （與寫入閘同一份判準，只是訊息說出是哪一項造成的）；記錄原本就有的違反不在這裡歸咎，寫入閘照舊會擋。
///
/// **各腿單獨呼叫**（Claude 代裁，同 `--remove-reference`）：不與 `update-venue` 的任何其他參數組合。`--add-name`／`--add-variant`／`--authorize` 會增減同一份
/// `names`，「定位的是哪一段」與報告、git 閘的語意會交錯；日後要放寬是可逆的，要收窄不是。
///
/// ## 不做的事（各有出路，不替人改判定）
///
/// - **移除一個名字的最後一段**時，若那個名字還在 `authorized`／`variant`／`field: names` 的 reference 裡，具名拒絕並指路：`authorized` 用
///   `--unauthorize` 撤回（#559）或 `--authorize` 換掉（不同名字的指定）、`references` 用 `--remove-reference`；`variant` 目前沒有移除面，只能手改 YAML。
///   程式不替人動那些判定（`--authorize` 遇到被 reference 指著的舊指定同一條紀律）。
/// - **移除後 venue 沒有任何名字**也拒絕：venue 至少要有一個名字（`add_venue` 同）。
/// - **時間欄位落在 `variant` 的名字上**由 `Venue.validate()` 擋（異寫法沒有生效期間）——這裡只把那句話歸因到這次編輯。
///
/// ## 誠實邊界
///
/// - `match`／`set` 的字串靠呼叫端逐字給出：讀取面（`venue`／`akashic_venue` 的 `names`）對 `source`／`note` 截在 300 字元、時間欄位截在 40，超過上限的值
///   讀取面看到的是被截的形——那種段要對照 YAML。
/// - 時間欄位的 ISO 檢查只在**這個入口**：載入端對 venue `names` 的日期不驗（#85），手改的非 ISO 值照樣載入、不在這裡歸咎。
/// - 位元組完全相同的重複段（`validate()` 的近重複檢查會報）沒有編輯路徑——`match` 分不出它們，本面不替呼叫端挑。
extension AkashicService {

    static let nameSegmentEditJSONKeys: Set<String> = ["name", "match", "set", "remove", "reason"]
    /// `match` 與 `set` 共用的六個鍵。鍵名同讀取面的 `names[]`（`ended` 不是 `ended_unknown`）與 YAML。
    static let nameSegmentFieldKeys: Set<String> = ["start", "end", "ended", "attested", "source", "note"]
    static let maxNameSegmentAttestedPoints = 200

    /// 一個字串欄位「給了什麼」：一個值，或明確的 `null`（`match`＝要求缺席、`set`＝清除）。沒給的鍵是外層的 nil。
    enum GivenText: Equatable {
        case text(String)
        case null
    }

    /// `match` 與 `set` 的欄位。每個欄位 nil＝沒給（`match`：不參與比對；`set`：不動）。
    struct NameSegmentFields {
        var start: GivenText?
        var end: GivenText?
        var ended: Bool?
        /// nil＝沒給；`[]`＝給了空陣列或 `null`
        var attested: [String]?
        var source: GivenText?
        var note: GivenText?

        var isEmpty: Bool { start == nil && end == nil && ended == nil && attested == nil && source == nil && note == nil }
        /// 這次動到時間欄位（要驗改完的區間）
        var touchesRange: Bool { start != nil || end != nil || ended != nil || attested != nil }
    }

    enum NameSegmentAction {
        case set(NameSegmentFields)
        case remove
    }

    /// 一筆編輯的定位、動作與理由（只看參數的解析結果，#654 的形）。
    struct NameSegmentEditSpec {
        let name: String
        let match: NameSegmentFields
        let action: NameSegmentAction
        let reason: String
    }

    // MARK: - 參數解析

    /// `edit_name_segment` 的形狀：陣列非空、上限、每項是物件、鍵封閉、`name` 與 `reason` 必填、`set` 與 `remove` 恰一個、欄位的型別。nil ＝ 這次沒給。
    static func parseNameSegmentEditSpecs(_ raw: [Any]?) throws -> [NameSegmentEditSpec] {
        guard let raw else { return [] }
        guard !raw.isEmpty else {
            throw ServiceError.invalid("edit_name_segment 是空陣列——沒有要改的名字段就不要給這個參數")
        }
        guard raw.count <= maxReferencesPerCall else {
            throw ServiceError.invalid("edit_name_segment 一次最多 \(maxReferencesPerCall) 筆（這次 \(raw.count) 筆）——分次送")   // display-safe-exempt: maxReferencesPerCall 與 raw.count 是 Int
        }
        return try raw.enumerated().map { i, item in try parseNameSegmentEditSpec(item, index: i) }
    }

    private static func strictBool(_ v: Any) -> Bool? {
        guard let n = v as? NSNumber, CFGetTypeID(n) == CFBooleanGetTypeID() else { return nil }
        return n.boolValue
    }

    private static func parseNameSegmentEditSpec(_ item: Any, index i: Int) throws -> NameSegmentEditSpec {
        let at = "edit_name_segment[\(i)]"   // display-safe-exempt: i 是 Int
        guard let obj = item as? [String: Any] else {
            throw ServiceError.invalid("\(at) 必須是物件（{name, match?, set 或 remove, reason}）")   // display-safe-exempt: at 是字面＋Int
        }
        let unknown = obj.keys.filter { !nameSegmentEditJSONKeys.contains($0) }.sorted()
        if !unknown.isEmpty {
            throw ServiceError.invalid(
                "\(at) 有不認得的鍵「\(Self.listCapped(unknown) { displaySafeInvisible($0, max: 60) })」——"   // display-safe-exempt: at 是字面＋Int
                + "合法的鍵：" + nameSegmentEditJSONKeys.sorted().joined(separator: "、"))   // display-safe-exempt: nameSegmentEditJSONKeys 是本檔的字面集合
        }
        guard let nameValue = obj["name"], let name = nameValue as? String,
              !NameIdentity.canonical(name).isEmpty else {
            throw ServiceError.invalid("\(at) 缺 name（要改哪一段的名字；字串、不得是空白）")   // display-safe-exempt: at 是字面＋Int
        }
        guard name.utf8.count <= AddOnlyEnrichment.maxValueBytes else {
            throw ServiceError.invalid("\(at).name 超過 \(AddOnlyEnrichment.maxValueBytes) 位元組（實得 \(name.utf8.count)）——拒絕，不截斷")   // display-safe-exempt: at 是字面＋Int；AddOnlyEnrichment.maxValueBytes 是 Int 常量；name.utf8.count 是 Int
        }
        guard let reasonValue = obj["reason"], let reason = reasonValue as? String,
              !reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ServiceError.invalid(
                "\(at) 缺理由（reason）或理由是空白——改寫名字段是判定，要寫為什麼這一段不成立；報告與 commit 靠它")   // display-safe-exempt: at 是字面＋Int
        }
        guard reason.utf8.count <= maxStatementBytes else {
            throw ServiceError.invalid("\(at).reason 超過 \(maxStatementBytes) 位元組（實得 \(reason.utf8.count)）——精簡它")   // display-safe-exempt: at 是字面＋Int；maxStatementBytes 是 Int 常量；reason.utf8.count 是 Int
        }
        // match：選填；null 當沒給
        var match = NameSegmentFields()
        if let m = obj["match"], !(m is NSNull) {
            guard let mobj = m as? [String: Any] else {
                throw ServiceError.invalid("\(at).match 必須是物件（\(nameSegmentFieldKeys.sorted().joined(separator: "、"))）")   // display-safe-exempt: at 是字面＋Int；nameSegmentFieldKeys 是本檔的字面集合
            }
            match = try parseNameSegmentFields(mobj, at: "\(at).match", forSet: false)   // display-safe-exempt: at 是字面＋Int
        }
        // set 與 remove 恰一個
        var setFields: NameSegmentFields?
        if let s = obj["set"], !(s is NSNull) {
            guard let sobj = s as? [String: Any] else {
                throw ServiceError.invalid("\(at).set 必須是物件（\(nameSegmentFieldKeys.sorted().joined(separator: "、"))）")   // display-safe-exempt: at 是字面＋Int；nameSegmentFieldKeys 是本檔的字面集合
            }
            setFields = try parseNameSegmentFields(sobj, at: "\(at).set", forSet: true)   // display-safe-exempt: at 是字面＋Int
        }
        var remove = false
        if let r = obj["remove"], !(r is NSNull) {
            guard let b = strictBool(r) else {
                throw ServiceError.invalid("\(at).remove 必須是布林（true＝刪掉這一段）")   // display-safe-exempt: at 是字面＋Int
            }
            remove = b
        }
        switch (setFields, remove) {
        case (.some, true):
            throw ServiceError.invalid("\(at) 的 set 與 remove 不得同時給——一次改一件事；改欄位用 set，刪掉這一段用 remove: true")   // display-safe-exempt: at 是字面＋Int
        case (.some(let f), false):
            guard !f.isEmpty else {
                throw ServiceError.invalid("\(at).set 是空物件——沒有要改的欄位；刪掉這一段用 remove: true")   // display-safe-exempt: at 是字面＋Int
            }
            return NameSegmentEditSpec(name: name, match: match, action: .set(f), reason: reason)
        case (nil, true):
            return NameSegmentEditSpec(name: name, match: match, action: .remove, reason: reason)
        case (nil, false):
            throw ServiceError.invalid("\(at) 缺 set（要改的欄位）或 remove: true（刪掉這一段）")   // display-safe-exempt: at 是字面＋Int
        }
    }

    /// `match`／`set` 的六個鍵。`forSet`：字串值不得是空白（空白不是值；要清除給 null）、`source`／`note` 有上限；
    /// `match` 的字串可以是任何值（比位元組，空白不會命中任何有意義的段，也不必替它多拒一次）。
    private static func parseNameSegmentFields(_ obj: [String: Any], at: String, forSet: Bool) throws -> NameSegmentFields {
        let unknown = obj.keys.filter { !nameSegmentFieldKeys.contains($0) }.sorted()
        if !unknown.isEmpty {
            throw ServiceError.invalid(
                "\(at) 有不認得的鍵「\(Self.listCapped(unknown) { displaySafeInvisible($0, max: 60) })」——"   // display-safe-exempt: at 是字面＋Int
                + "合法的鍵：" + nameSegmentFieldKeys.sorted().joined(separator: "、"))   // display-safe-exempt: nameSegmentFieldKeys 是本檔的字面集合
        }
        func text(_ key: String) throws -> GivenText? {
            guard let v = obj[key] else { return nil }
            if v is NSNull { return .null }
            guard let s = v as? String else {
                throw ServiceError.invalid("\(at).\(key) 必須是字串或 null（時間請寫成字串：\"1933\"，不是 1933）")   // display-safe-exempt: at 是字面＋Int；key 取自封閉鍵集合
            }
            guard s.utf8.count <= AddOnlyEnrichment.maxValueBytes else {
                throw ServiceError.invalid("\(at).\(key) 超過 \(AddOnlyEnrichment.maxValueBytes) 位元組（實得 \(s.utf8.count)）——拒絕，不截斷")   // display-safe-exempt: at 是字面＋Int；key 取自封閉鍵集合；AddOnlyEnrichment.maxValueBytes 是 Int 常量；s.utf8.count 是 Int
            }
            if forSet, s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                throw ServiceError.invalid("\(at).\(key) 是空白——空白不是值；要清除這個欄位給 null")   // display-safe-exempt: at 是字面＋Int；key 取自封閉鍵集合
            }
            // source／note 是散文，寫進 YAML 後在 git diff 與編輯器裡看不出控制、格式、方向與不可見字元（NUL、RLO……）。
            // 危險 scalar 的定義只有一份（`UnsafeToEmitScalar`，名字閘與輸出閘同一份）：人可讀輸出要逃脫的集合（ZWJ／ZWNJ 放行——散文不看脈絡）
            // 扣掉私用區（名字閘同一個取捨）。TAB、換行、NBSP 也在集合裡：寫成一般空白。match 不擋——修一個手改進來的髒值要逐字比對到它。
            if forSet, key == "source" || key == "note",
               let bad = s.unicodeScalars.first(where: { UnsafeToEmitScalar.escapesInDisplay($0) && $0.properties.generalCategory != .privateUse }) {
                let code = String(format: "%04X", bad.value)
                throw ServiceError.invalid(
                    "\(at).\(key) 含控制、格式或不可見字元 U+\(code)——寫進 YAML 後看不出它；改用一般空白或刪掉它（#675）")   // display-safe-exempt: at 是字面＋Int；key 取自封閉鍵集合；code 是十六進位碼位（[0-9A-F]+），不是 store 字串
            }
            return .text(s)
        }
        var f = NameSegmentFields()
        f.start = try text("start")
        f.end = try text("end")
        f.source = try text("source")
        f.note = try text("note")
        if let v = obj["ended"] {
            guard let b = strictBool(v) else {
                throw ServiceError.invalid("\(at).ended 必須是布林（true＝已結束、時點未知；false＝不是）")   // display-safe-exempt: at 是字面＋Int
            }
            f.ended = b
        }
        if let v = obj["attested"] {
            if v is NSNull {
                f.attested = []
            } else {
                guard let arr = v as? [Any], let strs = arr as? [String], strs.count == arr.count else {
                    throw ServiceError.invalid("\(at).attested 必須是字串陣列或 null（觀測點，例如 [\"1950\", \"2005\"]）")   // display-safe-exempt: at 是字面＋Int
                }
                guard strs.count <= maxNameSegmentAttestedPoints else {
                    throw ServiceError.invalid("\(at).attested 最多 \(maxNameSegmentAttestedPoints) 個觀測點（這次 \(strs.count) 個）")   // display-safe-exempt: at 是字面＋Int；maxNameSegmentAttestedPoints 是 Int 常量；strs.count 是 Int
                }
                if let long = strs.firstIndex(where: { $0.utf8.count > AddOnlyEnrichment.maxValueBytes }) {
                    throw ServiceError.invalid("\(at).attested[\(long)] 超過 \(AddOnlyEnrichment.maxValueBytes) 位元組——拒絕，不截斷")   // display-safe-exempt: at 是字面＋Int；long 是 Int；AddOnlyEnrichment.maxValueBytes 是 Int 常量
                }
                if forSet {
                    guard Set(strs.map { Array($0.utf8) }).count == strs.count else {
                        throw ServiceError.invalid("\(at).attested 有重複的觀測點——每個觀測點只寫一次")   // display-safe-exempt: at 是字面＋Int
                    }
                }
                f.attested = strs
            }
        }
        return f
    }

    // MARK: - 定位

    private static func bytes(_ s: String) -> [UInt8] { Array(s.utf8) }

    private static func textMatches(_ given: GivenText?, _ actual: String?) -> Bool {
        guard let given else { return true }
        switch given {
        case .null: return actual == nil
        case .text(let s): return actual.map { bytes($0) == bytes(s) } ?? false
        }
    }

    /// 這一段是不是被 `match` 命中：給了的鍵逐一相符（字串與陣列比位元組）；`match` 是空的命中同名的每一段。
    private static func segmentMatches(_ seg: TemporalValue<String>, _ m: NameSegmentFields) -> Bool {
        guard textMatches(m.start, seg.range.start), textMatches(m.end, seg.range.end),
              textMatches(m.source, seg.source), textMatches(m.note, seg.note) else { return false }
        if let e = m.ended, e != seg.range.endedUnknown { return false }
        if let a = m.attested, a.map(bytes) != seg.range.attested.map(bytes) { return false }
        return true
    }

    /// 兩段是不是逐位元組相同（名字本身也比位元組——canonical 相等而位元組不同的兩段是兩段）。
    private static func sameSegment(_ a: TemporalValue<String>, _ b: TemporalValue<String>) -> Bool {
        func opt(_ x: String?) -> [UInt8]? { x.map(bytes) }
        return bytes(a.value) == bytes(b.value) && opt(a.range.start) == opt(b.range.start) && opt(a.range.end) == opt(b.range.end)
            && a.range.endedUnknown == b.range.endedUnknown && a.range.attested.map(bytes) == b.range.attested.map(bytes)
            && opt(a.source) == opt(b.source) && opt(a.note) == opt(b.note)
    }

    /// 一段的時間欄位、`source`、`note` 的一行描述（已消毒）——拒絕訊息列出各段時用。
    private static func describeSegment(_ s: TemporalValue<String>) -> String {
        var parts: [String] = []
        if let x = s.range.start { parts.append("start \(displaySafeInvisible(x, max: 40))") }
        if let x = s.range.end { parts.append("end \(displaySafeInvisible(x, max: 40))") }
        if s.range.endedUnknown { parts.append("ended: true") }
        if !s.range.attested.isEmpty {
            parts.append("attested " + s.range.attested.prefix(5).map { displaySafeInvisible($0, max: 40) }.joined(separator: "／")
                         + (s.range.attested.count > 5 ? "…" : ""))   // display-safe-exempt: Int 比較與字面
        }
        if let x = s.source { parts.append("source \(displaySafeInvisible(x, max: 80))") }
        if let x = s.note { parts.append("note \(displaySafeInvisible(x, max: 80))") }
        return parts.isEmpty ? "不帶時間、source、note" : parts.joined(separator: "、")
    }

    /// 每個項目恰好命中一段（回傳 `venue.names.entries` 的位置）；定位不到、多段、兩項指到同一段、位元組完全相同的重複段都具名拒絕。
    static func locateNameSegments(_ specs: [NameSegmentEditSpec], in venue: Venue, venueKey: String) throws -> [Int] {
        let entries = venue.names.entries
        var byName: [String: [Int]] = [:]
        for (i, e) in entries.enumerated() { byName[NameIdentity.canonical(e.value), default: []].append(i) }
        let listed = 5
        var located: [Int] = []
        var claimedBy: [Int: Int] = [:]
        for (n, s) in specs.enumerated() {
            let at = "edit_name_segment[\(n)]"   // display-safe-exempt: n 是 Int
            let sameName = byName[NameIdentity.canonical(s.name)] ?? []
            let venueLabel = "venue「\(displaySafeInvisible(venueKey, max: 200))」"
            guard !sameName.isEmpty else {
                let present = entries.prefix(10).map { "「" + displaySafeInvisible($0.value, max: 80) + "」" }.joined(separator: "、")
                    + (entries.count > 10 ? "…（共 \(entries.count) 個）" : "")   // display-safe-exempt: Int 比較與字面
                throw ServiceError.invalid(
                    "\(at)：\(venueLabel)的 names 沒有「\(displaySafeInvisible(s.name, max: 120))」（相等看 canonical）——現有的名字：\(present)；整批拒絕、零寫入")   // display-safe-exempt: at 與 venueLabel 已消毒；present 逐項消毒
            }
            let hits = sameName.filter { segmentMatches(entries[$0], s.match) }
            let named = "「\(displaySafeInvisible(s.name, max: 120))」"
            guard !hits.isEmpty else {
                let list = sameName.prefix(listed).map { "· " + describeSegment(entries[$0]) }.joined(separator: "\n")
                throw ServiceError.invalid(
                    "\(at)：\(venueLabel)有 \(sameName.count) 段\(named)，但沒有一段符合 match（給了的鍵都要相符，字串比位元組；null 是要求缺席）——現有各段：\n"   // display-safe-exempt: at 與 venueLabel 已消毒；named 已消毒；sameName.count 是 Int
                    + list + (sameName.count > listed ? "\n…（共 \(sameName.count) 段）" : "") + "\n整批拒絕、零寫入")   // display-safe-exempt: list 的每一行已逐項消毒；sameName.count 是 Int
            }
            guard hits.count == 1 else {
                let identical = hits.dropFirst().allSatisfy { sameSegment(entries[hits[0]], entries[$0]) }
                let list = hits.prefix(listed).map { "· " + describeSegment(entries[$0]) }.joined(separator: "\n")
                if identical {
                    throw ServiceError.invalid(
                        "\(at)：\(venueLabel)有 \(hits.count) 段逐位元組完全相同的\(named)——match 分不出它們，本面不替呼叫端挑哪一段"   // display-safe-exempt: at 與 venueLabel 已消毒；named 已消毒；hits.count 是 Int
                        + "（`validate` 的近重複檢查會報這種 venue；要處理只能手改 YAML）；整批拒絕、零寫入")
                }
                throw ServiceError.invalid(
                    "\(at)：\(venueLabel)的\(named)定位到 \(hits.count) 段——加 match 縮小到一段（用各段不同的欄位，例如 match 給既有的 start 值；"   // display-safe-exempt: at 與 venueLabel 已消毒；named 已消毒；hits.count 是 Int
                    + "沒有起點的那一段給 start: null）：\n"
                    + list + (hits.count > listed ? "\n…（共 \(hits.count) 段）" : "") + "\n整批拒絕、零寫入")   // display-safe-exempt: list 的每一行已逐項消毒；hits.count 是 Int
            }
            let idx = hits[0]
            if let prior = claimedBy[idx] {
                let hitDescription = describeSegment(entries[idx])   // 已逐項消毒
                throw ServiceError.invalid(
                    "edit_name_segment[\(prior)] 與 [\(n)] 指到同一段（\(venueLabel)的\(named)：\(hitDescription)）——一段一次只改一件事；整批拒絕、零寫入")   // display-safe-exempt: prior 與 n 是 Int；venueLabel 與 named 已消毒；hitDescription 是 describeSegment 逐項消毒後的字串
            }
            claimedBy[idx] = n
            located.append(idx)
        }
        return located
    }

    // MARK: - 編輯

    /// 一項編輯的結果（報告用）。
    struct NameSegmentEditOutcome {
        enum Kind: String { case set, remove, unchanged }
        let kind: Kind
        let reason: String
        let before: TemporalValue<String>
        /// `remove` 沒有改完的樣子
        let after: TemporalValue<String>?
    }

    private static func apply(_ f: NameSegmentFields, to seg: TemporalValue<String>) -> TemporalValue<String> {
        var out = seg
        func value(_ g: GivenText?, _ current: String?) -> String? {
            switch g {
            case nil: return current
            case .null?: return nil
            case .text(let s)?: return s
            }
        }
        out.range.start = value(f.start, out.range.start)
        out.range.end = value(f.end, out.range.end)
        if let e = f.ended { out.range.endedUnknown = e }
        if let a = f.attested { out.range.attested = a }
        out.source = value(f.source, out.source)
        out.note = value(f.note, out.note)
        return out
    }

    /// 編輯之後的記錄與每一項的結果。**只算不寫**：改完要成立的檢查都在這裡（時間欄位、名字不消失得沒有出路、`Venue.validate()` 的 error 沒有新增），
    /// 任何一項不成立即擲——`editVenueNameSegments` 在它之後才過 git 閘與寫入。
    static func planNameSegmentEdits(_ specs: [NameSegmentEditSpec], located: [Int], venue: Venue, venueKey: String) throws
        -> (venue: Venue, outcomes: [NameSegmentEditOutcome]) {
        var entries = venue.names.entries
        var removed = Set<Int>()
        var outcomes: [NameSegmentEditOutcome] = []
        let venueLabel = "venue「\(displaySafeInvisible(venueKey, max: 200))」"
        for (n, (spec, idx)) in zip(specs, located).enumerated() {
            let before = entries[idx]
            switch spec.action {
            case .remove:
                removed.insert(idx)
                outcomes.append(NameSegmentEditOutcome(kind: .remove, reason: spec.reason, before: before, after: nil))
            case .set(let fields):
                let after = apply(fields, to: before)
                if fields.touchesRange, let why = Venue.nameSegmentRangeIssue(after.range) {
                    throw ServiceError.invalid(
                        "edit_name_segment[\(n)]：改完之後\(venueLabel)的「\(displaySafeInvisible(before.value, max: 120))」這一段的時間欄位不成立——\(why)。"   // display-safe-exempt: n 是 Int；venueLabel 已消毒；before 已消毒；why 由 Venue.nameSegmentRangeIssue 逐項消毒
                        + "set 逐鍵覆寫、沒給的鍵不動——要同時清掉別的欄位，在同一個 set 裡給 null（例如 end: null、attested: null）；整批拒絕、零寫入")
                }
                if sameSegment(before, after) {
                    outcomes.append(NameSegmentEditOutcome(kind: .unchanged, reason: spec.reason, before: before, after: after))
                } else {
                    entries[idx] = after
                    outcomes.append(NameSegmentEditOutcome(kind: .set, reason: spec.reason, before: before, after: after))
                }
            }
        }
        var edited = venue
        edited.names = Timeline(entries.enumerated().filter { !removed.contains($0.offset) }.map(\.element))
        if !removed.isEmpty { try assertRemovalLeavesNoOrphan(original: venue, removed: removed, venueLabel: venueLabel) }
        // 這次編輯造出的 store 不變式違反（`Venue.validate()` 的 error）：與寫入閘同一份判準，這裡只把它歸因到這次呼叫。原本就有的違反不歸咎——
        // 寫入閘照舊會擋。訊息取自 validate（逐項已消毒）。
        let existing = Set(venue.validate().filter { $0.severity == .error }.map(\.message))
        let introduced = edited.validate().filter { $0.severity == .error && !existing.contains($0.message) }.map(\.message)
        if !introduced.isEmpty {
            let introducedList = Self.listCapped(introduced) { $0 }   // 項目是 Venue.validate() 的訊息（逐項已消毒）；listCapped 只負責項數上限
            throw ServiceError.invalid(
                "edit_name_segment 改完之後\(venueLabel)會違反 store 的不變式——" + introducedList   // display-safe-exempt: venueLabel 已消毒；introducedList 是 Venue.validate() 的訊息（逐項已消毒）
                + "；整批拒絕、零寫入（調整這次的 set，或在同一次呼叫裡一併處理與它衝突的那一段——例如把兩段的時間改成互不相交）")
        }
        return (edited, outcomes)
    }

    /// 移除讓一個名字**整個消失**（它的每一段都被移除）時：不得留下指著它的 `authorized`／`variant`／`field: names` reference，也不得讓 venue 沒有任何名字。
    /// 程式不替人動那些判定——具名拒絕並指路。判準是 `Venue.nameSegmentRemovalBlocker`（#565 合併拒絕訊息推不推薦 remove 也問它），這裡只負責訊息。
    private static func assertRemovalLeavesNoOrphan(original: Venue, removed: Set<Int>, venueLabel: String) throws {
        guard let blocker = original.nameSegmentRemovalBlocker(removing: removed) else { return }
        switch blocker {
        case .noNamesLeft:
            throw ServiceError.invalid("這次移除之後\(venueLabel)沒有任何名字——venue 至少要有一個名字（add_venue 同）；整批拒絕、零寫入")   // display-safe-exempt: venueLabel 已消毒
        case .authorized(let name):
            throw ServiceError.invalid(
                "移除「\(displaySafeInvisible(name, max: 120))」的最後一段會讓它在\(venueLabel)的 authorized 裡成孤兒——程式不替人改對外形的判定；"   // display-safe-exempt: venueLabel 已消毒；name 已消毒
                + "先用 --unauthorize（MCP unauthorize）把它移出 authorized、或用 --authorize（MCP authorize）把同書寫系統的對外形換成別的名字（這個名字會留在 names），再重跑；整批拒絕、零寫入")
        case .variant(let name):
            throw ServiceError.invalid(
                "移除「\(displaySafeInvisible(name, max: 120))」的最後一段會讓它在\(venueLabel)的 variant 裡成孤兒（分割是對 names 的標記，孤兒 variant 是 error）——程式不替人改異寫法的判定；"   // display-safe-exempt: name 與 venueLabel 已消毒
                + "variant 目前沒有移除面，只能手改 YAML 把它從 variant 拿掉，再重跑；整批拒絕、零寫入")
        case .pinnedByReferences(let name, let count):
            throw ServiceError.invalid(
                "移除「\(displaySafeInvisible(name, max: 120))」的最後一段會讓\(venueLabel)有 \(count) 筆 `field: names` 的 reference 成孤兒（值被改寫後 provenance 成了孤兒、寫入會被拒）——"   // display-safe-exempt: name 與 venueLabel 已消毒；count 是 Int
                + "先用 --remove-reference（MCP remove_reference）移除它們，再重跑；整批拒絕、零寫入")
        }
    }

    // MARK: - 寫入與報告

    /// `update-venue` 的入口在確認參數合法、且沒有其他腿之後呼叫。載入、定位、驗、git 閘、寫入、重建 index；回報。
    ///
    /// `afterRecoverabilityGate` 是測試接縫（git 閘通過之後、重讀之前呼叫，模擬閘的時間窗裡記錄被外部改動）；正式路徑不設。
    func editVenueNameSegments(key: String, specs: [NameSegmentEditSpec], detailLimit: Int? = AkashicService.removalDetailCap,
                               afterRecoverabilityGate: (() throws -> Void)? = nil) throws -> String {
        let load = try store.load()
        // #670：key 重複時寫進哪一筆是猜——整批拒絕、零寫入（同 #627 對 citekey）
        guard !load.venues.unlocatableVenueKeys.contains(key) else {
            throw ServiceError.invalid("venue「\(displaySafeInvisible(key, max: 200))」無法唯一定位（\(UnlocatableReason.venue)）——整批拒絕、零寫入；先改掉其中一筆的 key")
        }
        guard let venue = load.venues.first(where: { $0.key == key }) else {
            throw ServiceError.notFound("venue「\(displaySafeInvisible(key, max: 200))」")
        }
        let located = try Self.locateNameSegments(specs, in: venue, venueKey: key)
        let plan = try Self.planNameSegmentEdits(specs, located: located, venue: venue, venueKey: key)
        let changed = plan.outcomes.filter { $0.kind != .unchanged }.count
        var written = false
        var rebuildFailure: Error?
        if changed > 0 {
            let paths = try assertRecordsRecoverable([(venue.id, "venue「\(displaySafeInvisible(key, max: 200))」")],
                                                     action: "這次會改寫 venue「\(displaySafeInvisible(key, max: 200))」的 \(changed) 段名字（時間欄位、source、note 或移除）",   // display-safe-exempt: changed 是 Int
                                                     issue: "#675")
            try afterRecoverabilityGate?()
            // 閘證的是「此刻磁碟上的檔已 commit、乾淨」，不是「它還等於這次讀到的記錄」：重讀閘回傳的那個檔，不同就不寫（#675 R1 verify；#606 同一條）
            guard let path = paths[venue.id], try store.rereadVenue(atRelativePath: path) == venue else {
                throw ServiceError.invalid(
                    "venue「\(displaySafeInvisible(key, max: 200))」的記錄檔在檢查期間被改過（與這次讀到的不同）——不以讀到的舊內容覆寫它；"
                    + "重跑（會對新的內容重新定位）；整批拒絕、零寫入")
            }
            try store.writeVenue(plan.venue)
            written = true
            rebuildFailure = rebuildIndexCapturingFailure()
        }
        // MCP 面只有前 `detailLimit` 項帶改寫前後的內容（第三方字串）；其後的只回 name／action／reason（理由只在報告裡有一份，不截）。CLI 傳 nil 全列
        let items: [[String: Any]] = plan.outcomes.enumerated().map { n, o in
            var item: [String: Any] = ["name": displaySafe(o.before.value, max: 200), "action": o.kind.rawValue]   // display-safe-exempt: o.kind.rawValue 是本檔的字面 enum 值
            if detailLimit.map({ n < $0 }) ?? true {
                item["before"] = Self.nameSegmentFieldsDict(o.before)
                if let after = o.after { item["after"] = Self.nameSegmentFieldsDict(after) }
            }
            // 理由不進 store，報告是它唯一的一份——不截在入口上限之下（#588 R1 verify 的同一條）
            item["reason"] = displaySafe(o.reason, max: Self.maxStatementBytes)   // display-safe-exempt: reason 是呼叫端原文、在這裡消毒一次
            return item
        }
        var payload: [String: Any] = [
            "key": displaySafe(key, max: 200),
            "nameSegments": items,
            "written": written,   // display-safe-exempt: Bool
            "namesTotal": plan.venue.names.entries.count,   // display-safe-exempt: Int
            "reasonNote": "理由只在這份報告裡——要留在 git，寫進接下來的 commit message（#675，使用者 2026-09-27 對移除面一族的裁決）",
        ]
        if !written { payload["writeNote"] = "沒有任何一段有變動（每一項改完與現在逐位元組相同）——沒有寫檔、沒有過 git 閘" }
        // 沒有 authorized 的 venue，顯示名在時間軸帶時間宣稱時改走現行的那一段——只編時間欄位也會換掉它（R1 verify 第 35 列）；變了要說出來
        if written, venue.displayName != plan.venue.displayName {
            payload["displayNameChanged"] = ["before": displaySafe(venue.displayName, max: 200), "after": displaySafe(plan.venue.displayName, max: 200)]
        }
        if let limit = detailLimit, specs.count > limit {
            payload["detailsTruncated"] = true   // display-safe-exempt: Bool
            payload["detailsListed"] = limit   // display-safe-exempt: Int
        }
        if let rebuildFailure { Self.noteIndexRebuildFailure(rebuildFailure, in: &payload, written: "改寫已經寫入磁碟——理由與改寫前後的內容都在這份報告裡，重試會因為那一段已經不是原來的樣子而被拒，先把報告存下來。") }
        return try jsonString(payload)
    }

    // MARK: - 讀取面與報告共用的一段名字

    /// 一段名字的時間欄位、`source`、`note` 的輸出形（不含名字本身）：讀取面（`venue`／`akashic_venue` 的 `names[]`）與編輯報告共用——
    /// 讀取面看到的鍵就是 `match`／`set` 收的鍵。字串逐一消毒且有長度上限（超過上限的形只用來認得，定位仍以 YAML 的逐字值為準）。
    static func nameSegmentFieldsDict(_ seg: TemporalValue<String>) -> [String: Any] {
        var n: [String: Any] = [:]
        if let st = seg.range.start { n["start"] = displaySafe(st, max: 40) }
        if let en = seg.range.end { n["end"] = displaySafe(en, max: 40) }
        if seg.range.endedUnknown { n["ended"] = true }   // display-safe-exempt: Bool
        if !seg.range.attested.isEmpty {
            n["attested"] = seg.range.attested.map { displaySafe($0, max: 40) }
        }
        if let s = seg.source { n["source"] = displaySafe(s, max: 300) }
        if let note = seg.note { n["note"] = displaySafe(note, max: 300) }
        return n
    }
}
