import Foundation
import AkashicCore
import AkashicStoreIO

/// #564 修正輪（使用者 2026-10-02 裁決第 2 點）：**最後一筆名字分類記錄是「撤回」的名字，可以連同它的記錄一起刪**——打錯字的名字的出路。
///
/// ## 為什麼有它
///
/// 名字分類記錄錨定 `names`（記錄說的名字要在 names 裡，撤回之後仍合法），而記錄只追加、移除面不刪它（判定史）。R1 verify（b26 F2 第 4／9／32 列）
/// 指出這個組合把一條原本走得通的路關掉了：`--authorize` 打錯字的名字（它會一併加進 names）、或 `authorize-names` 採用的錯拼法，一旦留了記錄，
/// 就沒有任何工具面能把那個名字刪掉——venue 的 `--edit-name-segment` 以「判定史不刪」拒絕，person 的 `fields.names` 替換在附著驗證失敗、訊息不給出路，
/// organization 連名字的移除面都沒有。唯一的路是手改 YAML（`replace-endnote-and-zotero` 第 4 條要記成缺口的那一種）。
///
/// ## 裁決的形狀（比照移除面一族：#573／#586／#588）
///
/// - **只收最後一筆記錄是「撤回」的名字**：人已經說過「它不是對外形（或不是異寫）」，刪它不推翻任何仍成立的判定；記錄隨名字一起刪，
///   歷史留在 git。最後一筆不是撤回（或根本沒有記錄）的具名拒絕，並指出口：**先撤回，再刪**。
/// - **理由必填、只進報告**，不寫進 store、不改 store format；**檔案要先 commit 乾淨**（`assertRecordsRecoverable`——刪之前的位元組只剩 git 那一份）。
/// - **單獨呼叫**：不與其他寫入腿組合（「刪的是哪一個名字」與報告、git 閘的語意會與其他腿交錯）。
///
/// 三種實體的入口不同、判準同一份（`nameRemovalRefusal`）：venue 走既有的 `--edit-name-segment` 的 `remove`（`Venue.nameSegmentRemovalBlocker`
/// 對最後一筆是撤回的名字放行、`planNameSegmentEdits` 一併刪記錄）；organization 與 person 各多一條腿 `--remove-name '<名字>=<理由>'`
/// （MCP `remove_names`），形狀與 `--remove-issn` 同族。
///
/// **誠實邊界**：`<名字>=<理由>` 以第一個 `=` 切，含 `=` 的名字定位不到（2026-10-02 唯讀量測 live store：person／organization／venue 的名字含 `=` 的 0 個）——
/// 那種名字只能手改 YAML。
extension AkashicService {

    /// 一筆要刪的名字與理由（只看參數的解析結果，#654 的形）。
    struct NameRemovalSpec: Equatable {
        let name: String
        let reason: String
    }

    /// `remove_names`（`--remove-name`）的形狀：非空陣列、一次至多 `maxNamesPerClassificationCall`、每項 `<名字>=<理由>`、名字非空白、理由非空白且
    /// 至多 `maxStatementBytes`、同一個名字（canonical）不重複。nil＝這次沒給。
    static func parseNameRemovalSpecs(_ raw: [String]?, parameter: String) throws -> [NameRemovalSpec] {
        guard let raw else { return [] }
        guard !raw.isEmpty else {
            throw ServiceError.invalid("\(parameter) 是空陣列——沒有要刪的名字就不要給這個參數")   // display-safe-exempt: parameter 是呼叫端的字面參數名
        }
        guard raw.count <= maxNamesPerClassificationCall else {
            throw ServiceError.invalid(
                "\(parameter) 一次最多 \(maxNamesPerClassificationCall) 個名字（這次 \(raw.count) 個）——分次送；整批拒絕、零寫入")   // display-safe-exempt: parameter 是字面參數名；maxNamesPerClassificationCall 與 raw.count 是 Int
        }
        var seen = Set<String>()
        var out: [NameRemovalSpec] = []
        for spec in raw {
            guard let eq = spec.firstIndex(of: "=") else {
                throw ServiceError.invalid(
                    "\(parameter)「\(displaySafeInvisible(spec, max: 120))」缺少 `=`——格式是 <名字>=理由（以第一個 = 切）；整批拒絕、零寫入")   // display-safe-exempt: parameter 是字面參數名
            }
            let name = String(spec[..<eq])
            let reason = String(spec[spec.index(after: eq)...]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !NameIdentity.canonical(name).isEmpty else {
                throw ServiceError.invalid("\(parameter)「\(displaySafeInvisible(spec, max: 120))」的名字是空白；整批拒絕、零寫入")   // display-safe-exempt: parameter 是字面參數名
            }
            guard !reason.isEmpty else {
                throw ServiceError.invalid(
                    "\(parameter)「\(displaySafeInvisible(name, max: 120))」的理由是空白——刪名字是判定，要寫為什麼它不該在；理由只進報告、不寫進 store；整批拒絕、零寫入")   // display-safe-exempt: parameter 是字面參數名
            }
            guard reason.utf8.count <= maxStatementBytes else {
                throw ServiceError.invalid(
                    "\(parameter)「\(displaySafeInvisible(name, max: 120))」的理由超過 \(maxStatementBytes) 位元組（實得 \(reason.utf8.count)）——精簡它；不截斷")   // display-safe-exempt: parameter 是字面參數名；maxStatementBytes 與 reason.utf8.count 是 Int
            }
            guard seen.insert(NameIdentity.canonical(name)).inserted else {
                throw ServiceError.invalid("\(parameter)「\(displaySafeInvisible(name, max: 120))」在一次呼叫裡重複（相等看 canonical）；整批拒絕、零寫入")   // display-safe-exempt: parameter 是字面參數名
            }
            out.append(NameRemovalSpec(name: name, reason: reason))
        }
        return out
    }

    /// 一個名字能不能連同記錄一起刪（`nil`＝可以）。`classifiedAs`：它現在在哪個分割（`authorized`／`variant`），nil＝未標。
    /// `withdrawHow`：這個實體上「先撤回」的做法（拒絕訊息的出口）。判準只有這一份——三種實體共用。
    static func nameRemovalRefusal(name: String, holder: String, references: [ProvenanceReference],
                                   classifiedAs: String?, withdrawHow: String) -> String? {
        let shown = "「\(displaySafeInvisible(name, max: 120))」"
        if let partition = classifiedAs {
            return "\(holder)的\(shown)還在 \(partition) 裡——刪名字只收已撤回的名字：先撤回（\(withdrawHow)），再刪"   // display-safe-exempt: holder 由呼叫端消毒；partition 是字面常量；withdrawHow 是呼叫端的字面片語
        }
        let records = NameClassificationRecord.allRecords(in: references, name: name)
        guard let last = NameClassificationRecord.latestAction(in: references, name: name) else {
            return records.isEmpty
                ? "\(holder)的\(shown)沒有名字分類的判定記錄——這條只刪最後一筆記錄是「撤回」的名字（#564 第 2 點）"   // display-safe-exempt: holder 由呼叫端消毒
                : "\(holder)的\(shown)的名字分類記錄讀不出動作——這條只刪最後一筆記錄是「撤回」的名字"   // display-safe-exempt: holder 由呼叫端消毒
        }
        guard last == .withdraw else {
            return "\(holder)的\(shown)最後一筆名字分類記錄是「\(last.rawValue)」不是「撤回」——人說過的判定還成立，刪名字只收已撤回的名字："   // display-safe-exempt: holder 由呼叫端消毒；rawValue 是 enum 常數
                + "先撤回（\(withdrawHow)），再刪"   // display-safe-exempt: withdrawHow 是呼叫端的字面片語
        }
        return nil
    }

    // MARK: - organization

    /// `update-organization --remove-name`（MCP `remove_names`）。organization 沒有一般的名字移除面（待裁，#557）——這條**只**刪最後一筆記錄是撤回的名字：
    /// 名字的每一段與它的名字分類記錄一起刪。被 `field: names` 的 reference 指著的拒絕（organization 的 reference 沒有移除面）。刪完至少要留一個名字。
    func removeOrganizationNames(key: String, specs: [NameRemovalSpec]) throws -> String {
        let load = try store.load()
        guard !load.organizations.unlocatableOrganizationKeys.contains(key) else {
            throw ServiceError.invalid("organization「\(displaySafeInvisible(key, max: 200))」無法唯一定位（\(UnlocatableReason.organization)）——整批拒絕、零寫入；先改掉其中一筆的 key")   // display-safe-exempt: UnlocatableReason.organization 是編譯期常量
        }
        guard var org = load.organizations.first(where: { $0.key == key }) else {
            throw ServiceError.notFound("organization「\(displaySafeInvisible(key, max: 200))」")
        }
        let holder = "organization「\(displaySafeInvisible(key, max: 200))」"
        var removed: [[String: Any]] = []
        for spec in specs {
            let k = NameIdentity.canonical(spec.name)
            let segments = org.names.entries.filter { NameIdentity.canonical($0.value) == k }
            guard let stored = segments.first?.value else {
                throw ServiceError.invalid("\(holder)的 names 沒有「\(displaySafeInvisible(spec.name, max: 120))」（相等看 canonical）——整批拒絕、零寫入")   // display-safe-exempt: holder 已消毒
            }
            let inAuthorized = org.authorized.contains { NameIdentity.canonical($0) == k }
            if let why = Self.nameRemovalRefusal(name: stored, holder: holder, references: org.references,
                                                 classifiedAs: inAuthorized ? "authorized" : nil,
                                                 withdrawHow: "用 --authorize 把同書寫系統的對外名稱換成別的名字，被換下的會留一筆撤回") {
                throw ServiceError.invalid(why + "；整批拒絕、零寫入")   // display-safe-exempt: why 由 nameRemovalRefusal 組裝，名字逐項消毒
            }
            let pinned = org.references.filter { $0.field == "names" && $0.value.map { NameIdentity.canonical($0) == k } == true }.count
            guard pinned == 0 else {
                throw ServiceError.invalid(
                    "\(holder)的「\(displaySafeInvisible(stored, max: 120))」有 \(pinned) 筆 `field: names` 的 reference 指著它——刪了它們會成孤兒，"   // display-safe-exempt: holder 已消毒；pinned 是 Int
                    + "而 organization 的 reference 沒有移除面：手改 YAML 刪掉那幾筆再重跑；整批拒絕、零寫入")
            }
            let records = NameClassificationRecord.allRecords(in: org.references, name: stored)
            org.names = Timeline(org.names.entries.filter { NameIdentity.canonical($0.value) != k })
            org.references.removeAll { r in records.contains { $0.byteExactKey == r.byteExactKey } }
            removed.append(["name": displaySafe(stored, max: 200), "reason": displaySafe(spec.reason, max: Self.maxStatementBytes),   // 理由只在報告裡——不截在入口上限之下
                            "segmentsRemoved": segments.count, "recordsRemoved": records.count])   // display-safe-exempt: Int
        }
        guard !org.names.entries.isEmpty else {
            throw ServiceError.invalid("這次刪完之後\(holder)沒有任何名字——organization 至少要有一個名字（add_organization 同）；整批拒絕、零寫入")   // display-safe-exempt: holder 已消毒
        }
        try assertRecordsRecoverable([(org.id, holder)],
                                     action: "這次會從\(holder)刪掉 \(specs.count) 個名字與它們的名字分類記錄",   // display-safe-exempt: holder 已消毒；Int
                                     issue: "#564")
        try store.writeOrganization(org)
        var payload: [String: Any] = ["key": displaySafe(key, max: 200), "namesRemoved": removed,
                                      "namesTotal": org.names.entries.count,   // display-safe-exempt: Int
                                      "reasonNote": Self.nameRemovalReasonNote]   // display-safe-exempt: Self.nameRemovalReasonNote 是編譯期字面常量
        if let failure = rebuildIndexCapturingFailure() { Self.noteIndexRebuildFailure(failure, in: &payload) }
        return try jsonString(payload)
    }

    static let nameRemovalReasonNote = "理由只在這份報告裡——要留在 git，寫進接下來的 commit message（#564 第 2 點，比照使用者 2026-09-27 對移除面一族的裁決）；刪之前的名字與記錄在 git 的上一版"

    // MARK: - person

    /// `update-person --remove-name`（MCP `remove_names`）：從 variant 刪掉最後一筆記錄是撤回的名字，連同它的名字分類記錄。還在 authorized 的拒絕
    /// （出口：`fields.names` 把它移到 variant、附 `--judgement`，寫撤回）；被 `field: names` 的 reference 指著的拒絕（person 的 reference 沒有移除面）。
    /// 有 `--dry-run`：預告會刪什麼、不過 git 閘、不寫。
    func removePersonNames(key: String, specs: [NameRemovalSpec], dryRun: Bool) throws -> String {
        let load = try store.load()
        guard !load.people.unlocatablePersonKeys.contains(key) else {
            throw ServiceError.invalid("person「\(displaySafeInvisible(key, max: 200))」無法唯一定位（\(UnlocatableReason.person)）——整批拒絕、零寫入")   // display-safe-exempt: UnlocatableReason.person 是編譯期常量
        }
        guard var person = load.people.first(where: { $0.key == key }) else {
            throw ServiceError.notFound("person「\(displaySafeInvisible(key, max: 200))」")
        }
        let holder = "person「\(displaySafeInvisible(key, max: 200))」"
        var removed: [[String: Any]] = []
        for spec in specs {
            let k = NameIdentity.canonical(spec.name)
            let hits = Array(Set(person.names.all.filter { NameIdentity.canonical($0) == k }))
            guard hits.count <= 1 else {
                throw ServiceError.invalid("\(holder)有 \(hits.count) 個 canonical 相等、拼法不同的名字——定位不到唯一一個，手改 YAML；整批拒絕、零寫入")   // display-safe-exempt: holder 已消毒；Int
            }
            guard let stored = hits.first else {
                throw ServiceError.invalid("\(holder)的 names 沒有「\(displaySafeInvisible(spec.name, max: 120))」（相等看 canonical）——整批拒絕、零寫入")   // display-safe-exempt: holder 已消毒
            }
            if let why = Self.nameRemovalRefusal(name: stored, holder: holder, references: person.references,
                                                 classifiedAs: person.names.authorized.contains(stored) ? "authorized" : nil,
                                                 withdrawHow: "update-person --fields 的 names 把它從 authorized 移到 variant、附 --judgement，會寫一筆撤回") {
                throw ServiceError.invalid(why + "；整批拒絕、零寫入")   // display-safe-exempt: why 由 nameRemovalRefusal 組裝，名字逐項消毒
            }
            let pinned = person.references.filter { $0.field == "names" && $0.value.map { NameIdentity.canonical($0) == k } == true }.count
            guard pinned == 0 else {
                throw ServiceError.invalid(
                    "\(holder)的「\(displaySafeInvisible(stored, max: 120))」有 \(pinned) 筆 `field: names` 的 reference 指著它——刪了它們會成孤兒，"   // display-safe-exempt: holder 已消毒；pinned 是 Int
                    + "而 person 的 reference 沒有移除面：手改 YAML 刪掉那幾筆再重跑；整批拒絕、零寫入")
            }
            let records = NameClassificationRecord.allRecords(in: person.references, name: stored)
            person.names.variant.removeAll { $0 == stored }
            person.references.removeAll { r in records.contains { $0.byteExactKey == r.byteExactKey } }
            removed.append(["name": displaySafe(stored, max: 200), "reason": displaySafe(spec.reason, max: Self.maxStatementBytes),
                            "recordsRemoved": records.count])   // display-safe-exempt: Int
        }
        var payload: [String: Any] = ["key": displaySafe(key, max: 200), "namesRemoved": removed,
                                      "namesTotal": person.names.all.count,   // display-safe-exempt: Int
                                      "reasonNote": Self.nameRemovalReasonNote]   // display-safe-exempt: Self.nameRemovalReasonNote 是編譯期字面常量
        if dryRun {
            payload["dryRun"] = true   // display-safe-exempt: Bool
            return try jsonString(payload)
        }
        try assertRecordsRecoverable([(person.id, holder)],
                                     action: "這次會從\(holder)刪掉 \(specs.count) 個名字與它們的名字分類記錄",   // display-safe-exempt: holder 已消毒；Int
                                     issue: "#564")
        try store.writePerson(person)
        if let failure = rebuildIndexCapturingFailure() { Self.noteIndexRebuildFailure(failure, in: &payload) }
        return try jsonString(payload)
    }
}
