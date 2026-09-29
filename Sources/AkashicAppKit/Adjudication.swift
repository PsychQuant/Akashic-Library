import Foundation
import Observation
import AkashicCore
import AkashicStoreIO
import AkashicEntity
import AkashicIndex

/// 裁決台①People：resolve 候選逐一 accept／skip（絕不批次自動套用）。
///
/// skip 集合存在 AppState（session 生命週期）而非本 model——view 以
/// `.task(id: reloadCount)` 在每次 reload 後重建 model，若集合放 model 內，
/// accept 觸發的 reload 會讓先前 skip 過的候選全部重新出現（R2 驗證抓到的回歸）。
@Observable
public final class PeopleResolveModel {
    let state: AppState
    public private(set) var candidates: [ResolutionCandidate] = []
    /// 系統**知道**自己遇到了決定點，卻無法自行決定的位置（#231）。
    ///
    /// 這一面比 CLI 與 MCP 更需要它——**人就坐在這裡**。先前 CLI 與 MCP 都被接上了，
    /// 唯獨裁決台沒有：使用者看得到唯一命中，卻不知道系統另外找到 N 個需要他判斷
    /// 的位置。那與 #231 要修的「靜默丟棄」是同一件事，只是發生在最不該發生的面。
    ///
    /// **不可 accept**——`apply` 只吃 `candidates`，型別層就寫不出來。
    public private(set) var ambiguities: [AmbiguousMatch] = []
    /// 查過未決的配對 → 未決記錄數（change `resolution-verdict-states`，#619）。裁決台是第三個面：CLI 標「查過未決 N 次」、
    /// MCP 帶 `undecidedChecks`，這裡不標的話，有人查過而判不出來的配對在人眼前與從沒查過的長得一樣（R1 verify）。
    /// accept 照常可用——它是逐筆顯式指名（同 MCP 的逐 id apply），不是篩選式批次。
    public private(set) var undecided: [ResolutionPairing: Int] = [:]

    public init(state: AppState) {
        self.state = state
        refresh()
    }

    public func refresh() {
        // #232 verify REG-3：App 面曾因 resolver 的 `rejected: = []` 預設值而
        // **完全略過否決史**——CLI/MCP 否決過的配對在裁決台照樣出現。三個面
        // 必須吃同一份 ledger；參數改必填後這裡是編譯器逼著接上的。
        let report = PersonResolver.resolve(
            entries: state.entries, people: state.people,
            rejected: ResolutionLedger.rejectedPairings(people: state.people),
            confirmed: ResolutionLedger.confirmedPairings(people: state.people))
        candidates = report.candidates
            .filter { !state.skippedPeopleCandidates.contains(id(of: $0)) }
        // 歧義**不參與 skip 集合**：skip 的語意是「這個候選我不要套用」，而歧義
        // 本來就套用不了。它是待辦事項，不是候選。
        ambiguities = report.ambiguities
        undecided = ResolutionLedger.undecidedChecks(holders: state.people.map { ($0.key, $0.references) })
    }

    /// 這個候選的配對查過未決幾次（0＝沒有未決記錄）。
    public func undecidedChecks(for c: ResolutionCandidate) -> Int {
        ResolutionLedger.undecidedChecks(in: undecided, holder: c.citekey, literal: c.literal, judgedKey: c.personKey)
    }

    /// 這個歧義位置跨全部人選的未決記錄總數。
    public func undecidedChecks(for a: AmbiguousMatch) -> Int {
        a.personKeys.reduce(0) {
            $0 + ResolutionLedger.undecidedChecks(in: undecided, holder: a.citekey, literal: a.literal, judgedKey: $1)
        }
    }

    /// 一行可顯示的區辨欄位（已消毒）。
    ///
    /// **組在 model 端不在 view 端**：view 內的長字串串接會讓 Swift 型別檢查器放棄
    /// （實測 `unable to type-check this expression in reasonable time`），而
    /// `AkashicApp/` 是獨立 XcodeGen 專案、不在 `Package.swift` 內——`swift build`
    /// 與 pre-push 閘都不編它，只有 CI 會。錯誤會晚到 push 之後才浮現。
    public func discriminatorLine(for key: String) -> String {
        let d = discriminators(for: key)
        var bits: [String] = []
        if let o = d.orcid { bits.append("orcid:" + displaySafe(o, max: 40)) }
        if let o = d.openalex { bits.append("openalex:" + displaySafe(o, max: 40)) }
        if let x = d.died { bits.append("卒:" + displaySafe(x, max: 20)) }
        // 已含 隸屬:／曾隸屬:／觀測到隸屬: 前綴；混合情形是兩段，上限比單段的 80 寬（#663：觀測段不能被截掉）
        if let a = d.affiliation { bits.append(displaySafe(a, max: 160)) }
        let tail = bits.isEmpty ? "⚠ 無任何區辨欄位" : bits.joined(separator: "  ")
        return "→ " + displaySafe(key, max: 200) + "  " + tail
    }

    /// 每個歧義候選的區辨欄位——**只給 key 的話人也判不了**。
    ///
    /// `names` 不具區辨力（它們正規化後相同才會歧義）；真正能分辨「兩個同名的人」
    /// 與「同一人兩筆記錄」的是外部識別碼與時空不相容。
    ///
    /// **`orcid` 回傳 `String?` 不是 `ORCID?`**（#394 task 3.3）：這個函式的產出
    /// 全部是顯示字串（其餘四個成員本來就是 `String?`），呼叫端只拿去拼一行文字
    /// 給人看，不再需要型別化的識別碼行為（正規化、shape 驗證早在 `Person.orcid`
    /// decode 時就做完了）。型別在這個邊界降級成字串是刻意的 downcast，不是漏改。
    public func discriminators(for key: String) -> (names: [String], orcid: String?,
                                                    openalex: String?, died: String?,
                                                    affiliation: String?) {
        let p = state.people.first { $0.key == key }
        // **current 與 former 不可塌成一個欄位**（#236 R3）：「現在在 X」與
        // 「曾經在 X」對區辨的意義完全不同——後者配上時間才有辨別力，而把兩者
        // 印成同一個「隸屬:X」會讓讀的人以為那是現職。
        //
        // **三種說法各自的措辭，混合情形兩者都印**（#663）。推導只有 `TimelineOf.standing` 一份，
        // 與匯出端、CLI、MCP 讀同一個：「曾隸屬」只給宣稱已結束的段；只被觀測到的段是「觀測到隸屬」——
        // 被看到過不等於離開了，匯出端對這種人說 `undetermined`（#661）。
        var parts: [String] = []
        if let s = p?.profile.affiliations.standing {
            if let cur = s.current?.value.displayName {
                parts.append("隸屬:" + cur)
            } else {
                if let ended = s.lastEnded {
                    // **已結束的兩種時間狀態不可共用一種措辭**（#236 R4）。先前一律套 `（–X）`，
                    // 於是 `endedUnknown` 的 start 被印成終止——**那是捏造**。
                    let r = ended.range
                    let when: String
                    if let e = r.end { when = "（–\(e)）" }                       // 確實結束於 e
                    else if r.endedUnknown { when = "（已結束・時點未知）" }        // #63
                    else { when = "" }
                    parts.append("曾隸屬:" + ended.value.displayName + when)
                }
                if let seen = s.lastObserved {
                    // #70：觀測點不是終止日期——`attested:[2020]` 只是「2020 年被看到在這裡」，
                    // 印成「（–2020）」＝「2020 年結束」是捏造（#236 R4：那個人沒有任何資料主張他何時離開）。
                    let at = seen.range.attested.max().map { "（\($0)）" } ?? ""
                    parts.append("觀測到隸屬:" + seen.value.displayName + at)
                }
            }
        }
        let aff: String? = parts.isEmpty ? nil : parts.joined(separator: "  ")
        // #227：呈現面列**全部**名字（authorized + variant）——這裡是身分判斷的
        // 佐證資訊，缺一個變體就少一條線索。
        return (p?.names.all ?? [], p?.orcid?.normalized, p?.openalex, p?.died, aff)
    }

    public func accept(_ candidate: ResolutionCandidate) throws {
        // #627：citekey 重複時不猜是哪一筆——具名拒絕，不靜默無作用（CLI／MCP 同語意）
        if state.entries.unlocatableCitekeys.contains(candidate.citekey) {
            throw AdjudicationError.unlocatableCitekey(candidate.citekey)
        }
        // #641：accept 寫完 work 才寫 person 的 verdict——person 檔寫入時會被拒（或 key 重複）就在任何寫入之前拒絕
        if state.people.unlocatablePersonKeys.contains(candidate.personKey) {
            throw AdjudicationError.unlocatablePerson(candidate.personKey)
        }
        let applied = PersonResolver.apply([candidate], to: state.entries)
        // R7（R6-verify M21）：per-item 收容——先寫完能寫的、reindex 保持一致，
        // 再把第一個失敗往上拋給 UI（不留「部分改寫 + index stale」）
        var firstFailure: Error?
        var entryWritten = false
        for (before, after) in zip(state.entries, applied) where before != after {
            do {
                try state.store.writeEntry(after)
                entryWritten = true
            } catch {
                if firstFailure == nil { firstFailure = error }
            }
        }
        // #232 design D6：accept 的同一動作內寫 resolution-confirmed（entry 寫入
        // 成功才寫——誇報 verdict 比漏寫更糟）。verify REG-3：App 面先前完全沒寫，
        // 裁決台的每一次 accept 在校準計數裡永遠是 pending。
        // format < 8 的 store 跳過 verdict（同 AkashicService 的降級——writePerson
        // 的 v8 gate 會拒寫，這裡先判避免把 accept 本身變成錯誤）。
        let storeFormat = (try? StoreVersion.read(root: state.store.root)) ?? 1
        if entryWritten, storeFormat >= 8,
           var p = state.people.first(where: { $0.key == candidate.personKey }) {
            ResolutionLedger.appendIfAbsent(ResolutionLedger.record(
                .confirmed, holderKind: .work,
                holder: candidate.citekey, literal: candidate.literal,
                rule: ResolutionLedger.personRule(for: candidate.tier),
                statement: "裁決台 accept：使用者確認歸戶"), to: &p.references, allowCoexistence: storeFormat >= 19)
            do {
                try state.store.writePerson(p)
            } catch {
                if firstFailure == nil { firstFailure = error }
            }
        }
        // R8（R7-verify L16）：寫入失敗優先於 reindex 失敗——不可被吞掉
        do {
            try state.reindexAndReload()
        } catch {
            if firstFailure == nil { firstFailure = error }
        }
        refresh()
        if let firstFailure { throw firstFailure }
    }

    /// skip 只影響本 session 的清單，不寫任何檔案。
    public func skip(_ candidate: ResolutionCandidate) {
        state.skippedPeopleCandidates.insert(id(of: candidate))
        refresh()
    }

    private func id(of c: ResolutionCandidate) -> String { c.pinnedID }   // 複合鍵＋pin 住型別上（#236 R4／R4-8：skip 也釘 person——同列改指後不再誤 skip）
}

public enum AdjudicationError: Error, LocalizedError, Equatable, SanitizedErrorDescription {
    case entryNotFound(String)
    case notAnOrphan(String)
    /// #605：主來源已刪除，但附加來源（例如群組 library 那份）仍在 Zotero 裡。
    case hasLiveAdditionalSource(String)
    /// #627：候選所在的 citekey 在 store 裡不只一筆、或該 work 與另一筆共用 id——以 citekey 定位會猜是哪一筆、以 id 寫檔會寫到兄弟的檔，拒絕。
    /// #641 起也含 load 判定它的檔案寫入時會被拒的 work（`unlocatableCitekeys` 的第 3 類）。
    case unlocatableCitekey(String)
    /// #641：候選指名的 person 無法唯一定位（key 重複，或 load 判定它的檔案寫入時會被拒）——accept 寫完 work
    /// 才寫 person 的 verdict，那一格在寫入當下被拒會留下已升格而沒有 verdict 的作者位，拒絕。
    case unlocatablePerson(String)
    /// #609：「拿掉已刪除的附加來源」只作用在主連結仍在、至少一個附加來源已刪除的 entry——動作當下重新讀盤已不是這個形狀。
    case noOrphanedAdditionalSource(String)
    /// #609：移除面要理由（移除面一族的使用者裁決，2026-09-27）——理由只進報告，不寫進 store。
    case reasonRequired
    /// 理由上限（`LibraryStore.maxStatementBytes`，與 resolve 族的說明上限同一個值，#683）——超過整筆拒絕、不截斷。
    case reasonTooLong(bytes: Int)
    /// #609：移除之前那筆記錄檔要在 git 裡有副本（同一族裁決）。**整句取自 `LibraryStore.recordRecoverability` 的拒絕**（#683——
    /// 與 `AkashicService.assertRecordsRecoverable` 同一份判斷與同一份措辭，兩面對同一個 store 說同一句話）：`refusal` 在擲出端已消毒
    /// （動作句與標籤逐項 `displaySafeInvisible`、原因是 `filesNotSafelyRecoverable` 的固定句），描述端只截。
    case notRecoverable(refusal: String)
    /// #609 R1 verify：使用者確認的那一組已刪除來源，與動作當下磁碟上的那一組不同（外部匯入又標了新的、或有一個已恢復）——
    /// 拿掉的只能是使用者看到並確認的那一組，所以拒絕。`seen`／`now` 是排序過、以「、」相接的來源鍵（`<library_id>:<zotero_key>`，
    /// store 字串）：**擲出端消毒一次**（描述端原樣印出，不再逃一次）；空的一組寫「（無）」。
    case orphanedSourcesChanged(citekey: String, seen: String, now: String)
    /// #609 R1 verify：git 閘通過之後、寫入之前，那筆記錄又被外部改過——閘的結論不再適用於現在的內容，拒絕（不用閘之前的快照整檔寫回）。
    case changedDuringCheck(String)

    public var errorDescription: String? {
        switch self {
        // #155：key 是 store 衍生（citekey，來自 Zotero 匯入等第三方來源）——
        // App 的 error 顯示在 SwiftUI，威脅模型比 MCP-直達-LLM 弱，但同 bug class
        // 的一致性值得（#142 sweep 的溢出）。
        case .entryNotFound(let key):
            return "找不到 entry「\(displaySafeInvisible(key, max: 200))」——外部變更可能已移除，請重新整理"
        case .notAnOrphan(let key):
            return "「\(displaySafeInvisible(key, max: 200))」不是 orphan——外部同步可能已恢復連結，已拒絕破壞性動作"
        case .hasLiveAdditionalSource(let key):
            return "「\(displaySafeInvisible(key, max: 200))」只有主來源在 Zotero 端被刪除，另一個 library 的附加來源仍在——丟垃圾桶會連它一起丟掉，已拒絕；請改用「與 Zotero 脫鉤」（拿掉已刪除的來源、保留另一個 library 的紀錄，欄位不再被 Zotero 改寫）"
        case .unlocatableCitekey(let key):
            return "citekey「\(displaySafeInvisible(key, max: 200))」無法唯一定位（\(UnlocatableReason.work)）——已拒絕歸戶；請先修好（#627／#641）"
        case .unlocatablePerson(let key):
            return "person「\(displaySafeInvisible(key, max: 200))」無法唯一定位（\(UnlocatableReason.person)）——已拒絕歸戶；請先修好（#641）"
        case .noOrphanedAdditionalSource(let key):
            return "「\(displaySafeInvisible(key, max: 200))」已不是「主連結仍在、附加來源已刪除」的形狀——外部同步可能已恢復來源；"
                + "整筆 orphan 請改用「與 Zotero 脫鉤」。已拒絕（#609）"
        case .orphanedSourcesChanged(let key, let seen, let now):
            return "「\(displaySafeInvisible(key, max: 200))」已刪除的附加來源與你確認時看到的不同——"
                + "確認的：\(seen)；現在：\(now)。"   // display-safe-exempt: seen／now 在擲出端已消毒
                + "外部匯入可能又標了新的來源、或有一個已恢復；拿掉的只能是你確認的那一組，已拒絕、零寫入。請重新檢視清單再確認（#609）"
        case .changedDuringCheck(let key):
            return "「\(displaySafeInvisible(key, max: 200))」的記錄在檢查 git 副本的期間被外部改動——檢查的結論不再適用，已拒絕、零寫入。請重新整理再做（#609）"
        case .reasonRequired:
            return "拿掉來源要寫理由——理由只出現在這次的結果裡、不寫進 store，請寫進 commit message（#609）"
        case .reasonTooLong(let bytes):
            return "理由 \(bytes) 位元組，上限 \(LibraryStore.maxStatementBytes)——已拒絕、零寫入，不截斷（#609）"   // display-safe-exempt: bytes 與 LibraryStore.maxStatementBytes 是 Int
        case .notRecoverable(let refusal):
            return displaySafeClipOnly(refusal, max: 1_200)   // display-safe-exempt: refusal 在擲出端已消毒（recordRecoverability 的整句：動作句與標籤逐項消毒、原因是固定句），只截
        }
    }
}

/// #609 R1 verify：「拿掉已刪除的來源」對話框裡的理由草稿。
///
/// 兩件事：動作失敗（最可能是記錄檔還沒 commit）之後使用者重開同一筆，已打的理由還在，不必重打；
/// 理由是空的時候破壞性按鈕不能按（先前只在按下之後才被 `reasonRequired` 拒絕）。
/// 抽成值型別是為了能在沒有 SwiftUI 的測試裡驗——view 只綁 `text` 與 `isSubmittable`。
public struct RemovalReasonDraft: Equatable {
    public private(set) var citekey: String?
    public var text: String = ""

    public init() {}

    /// 開對話框：同一筆再開（上一次失敗）保留理由，換另一筆就清空。
    public mutating func open(for citekey: String) {
        if self.citekey != citekey { text = "" }
        self.citekey = citekey
    }

    /// 動作成功之後清掉——理由已經進了結果報告。
    public mutating func clearAfterSuccess() {
        text = ""
        citekey = nil
    }

    /// 理由非空（去掉前後空白之後）才可送出。
    public var isSubmittable: Bool { !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
}

/// 裁決台②Orphans：等待（預設）／刪檔（垃圾桶可救回）／轉純 Akashic entry。
@Observable
public final class OrphanModel {
    let state: AppState

    public init(state: AppState) {
        self.state = state
    }

    public var orphans: [Entry] { state.orphanedEntries }
    /// 主連結仍在、至少一個附加來源已在 Zotero 端刪除（#609）——與 `orphans` 不相交。
    public var orphanedAdditionalSourceEntries: [Entry] { state.entriesWithOrphanedAdditionalSource }

    public enum Action {
        /// 檔案進垃圾桶（FileManager.trashItem——可救回，比 CLI 寬容的 App 專屬安全網）
        case moveToTrash
        /// 抹 provenance → 轉純 Akashic entry（不再參與 Zotero pull）
        case detachFromZotero
    }

    public func resolve(citekey: String, action: Action) throws {
        // 破壞性動作當下重新讀盤驗證——確認對話框開啟期間 Zotero pull 可能
        // 已把 entry 恢復正常（TOCTOU）；記憶體清單不可作為安全邊界。
        let load = try state.store.load()
        guard let entry = load.entries.first(where: { $0.citekey == citekey }) else {
            throw AdjudicationError.entryNotFound(citekey)
        }
        // 三個寫入動作的定位守衛一致（#609 R1 verify）：citekey 重複、或與另一筆共用 id 時 `first(where:)` 會猜是哪一筆——
        // 垃圾桶丟的可能是兄弟的檔、脫鉤寫進猜出來的那筆，而兩者都是不可逆的來源刪除。與 `removeOrphanedAdditionalSources`、
        // `AppState.mutate` 同一條（`unlocatableCitekeys`，#628／#641）。
        if load.entries.unlocatableCitekeys.contains(citekey) { throw AdjudicationError.unlocatableCitekey(citekey) }
        // 整筆 orphan 的判準只有一份（`Entry.zoteroLinkState`，#609）：「只有附加來源、全部已刪除」也在內——
        // 先前這裡只看主來源，那種 entry 列不進清單、也動不了。
        guard entry.zoteroLinkState == .orphaned else {
            throw AdjudicationError.notAnOrphan(citekey)
        }
        // #605：附加來源若仍活著，作品在另一個 library 還在。
        let liveAdditional = entry.additionalProvenance.firstIndex { $0.orphanedAt == nil }
        switch action {
        case .moveToTrash:
            if liveAdditional != nil { throw AdjudicationError.hasLiveAdditionalSource(citekey) }
            var trashed: NSURL?
            try FileManager.default.trashItem(
                at: state.store.usesEntitiesLayout   // #35
                    ? state.store.entityURL(id: entry.id)
                    : state.store.entryURL(citekey: entry.citekey),
                resultingItemURL: &trashed)
        case .detachFromZotero:
            var detached = entry
            // 真的脫鉤（#605 R1 verify #2，使用者裁決）：拿掉已刪除的主來源，**不**把活著的
            // 附加來源升為主來源——升格會把欄位改寫權交給另一個 library（典型是共享群組那份）。
            // 已 orphan 的附加來源一併拿掉（R1 verify #4）；活著的留著，只記錄、不改欄位。
            // 結果可能是「沒有主來源、只有附加來源」——那是合法狀態：這筆的欄位不再被任何
            // Zotero 條目改寫。
            detached.provenance = nil
            detached.additionalProvenance.removeAll { $0.orphanedAt != nil }
            try state.store.writeEntry(detached)
        }
        try state.reindexAndReload()
    }

    /// 拿掉已在 Zotero 端刪除的附加來源（#609）——作用在主連結仍在的 entry；主來源與活著的附加來源不動，書目欄位不動。
    ///
    /// 移除面一族的使用者裁決（2026-09-27）：理由必填、只進回傳的報告（不寫進 store）；移除前要求那筆記錄檔已 commit、乾淨
    /// （被拿掉的來源只剩 git 裡那一份）。動作當下重新讀盤驗證形狀（TOCTOU，同 `resolve`）。回傳給人看的報告。
    ///
    /// `seen` 是使用者在清單與對話框上看到並確認的那一組（`Entry.orphanedAdditionalSourceKeys`）：動作當下磁碟上的那一組
    /// 若與它不同就拒絕，不猜「使用者大概也想拿掉新出現的」——拿掉的只能是他確認的那一組（#609 R1 verify）。
    public func removeOrphanedAdditionalSources(citekey: String, reason: String, seen: [String]) throws -> String {
        let trimmed = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw AdjudicationError.reasonRequired }
        let byteCount = trimmed.utf8.count
        guard byteCount <= LibraryStore.maxStatementBytes else { throw AdjudicationError.reasonTooLong(bytes: byteCount) }   // display-safe-exempt: byteCount 是 Int
        let load = try state.store.load()
        guard let entry = load.entries.first(where: { $0.citekey == citekey }) else {
            throw AdjudicationError.entryNotFound(citekey)
        }
        if load.entries.unlocatableCitekeys.contains(citekey) { throw AdjudicationError.unlocatableCitekey(citekey) }
        guard entry.zoteroLinkState == .additionalSourceOrphaned else {
            throw AdjudicationError.noOrphanedAdditionalSource(citekey)
        }
        let now = entry.orphanedAdditionalSourceKeys
        guard Set(seen) == Set(now) else {
            throw AdjudicationError.orphanedSourcesChanged(
                citekey: citekey,
                seen: displaySafeInvisible(seen.isEmpty ? "（無）" : seen.sorted().joined(separator: "、"), max: 600),
                now: displaySafeInvisible(now.isEmpty ? "（無）" : now.sorted().joined(separator: "、"), max: 600))
        }
        let removed = entry.additionalProvenance.filter { $0.orphanedAt != nil }
        try assertRecordFileRecoverable(entry, removing: removed.count)
        try afterRecoverabilityGate?()
        // 閘是多個子程序、有時間窗：閘通過之後那筆記錄若又被外部改過，閘的結論就不適用於現在的內容，而下面要寫回的是閘之前的快照——
        // 重讀一次，不一致就拒絕，不整檔覆寫（#609 R1 verify，security）。
        guard try state.store.load().entries.first(where: { $0.citekey == citekey }) == entry else {
            throw AdjudicationError.changedDuringCheck(citekey)
        }
        var updated = entry
        updated.additionalProvenance.removeAll { $0.orphanedAt != nil }
        try state.store.writeEntry(updated)
        try state.reindexAndReload()
        let sources = removed.map { p in
            "\(p.libraryID.map(String.init) ?? "?"):\(displaySafeInvisible(p.zoteroKey, max: 120))"
        }.joined(separator: "、")
        return "已從「\(displaySafeInvisible(citekey, max: 200))」拿掉 \(removed.count) 個已在 Zotero 端刪除的附加來源：\(sources)。"   // display-safe-exempt: Int；sources 已逐項消毒
            + "理由：\(displaySafeInvisible(trimmed, max: LibraryStore.maxStatementBytes))。"
            + "移除前的版本在 git 裡；理由不寫進 store，要留下請寫進 commit message（#609）"
    }

    /// 測試接縫：git 閘通過之後、寫入之前呼叫。只給測試模擬「閘的時間窗裡記錄被外部改動」；正式程式路徑不設。
    var afterRecoverabilityGate: (() throws -> Void)?

    /// 那筆記錄檔在 git 裡有 tracked、clean 的副本——**與 `AkashicService.assertRecordsRecoverable` 同一支**（`LibraryStore.recordRecoverability`，#683）：
    /// 路徑取自磁碟上的實際檔名、找不到檔就拒絕、拒絕的整句同一份措辭。這裡只做兩件 service 沒有的事：(1) legacy 佈局（format < 2）的 store
    /// 開得起來，記錄檔是 `entries/<citekey>.yaml`（與 `writeEntry` 選目的地的同一個判準）；(2) 把整句包成 App 這一層的錯誤型別。
    private func assertRecordFileRecoverable(_ entry: Entry, removing count: Int) throws {
        let label = displaySafeInvisible(entry.citekey, max: 200)
        let check = LibraryStore.recordRecoverability(
            root: state.store.root,
            items: [(entry.id, "work「\(label)」")],
            legacyPaths: state.store.usesEntitiesLayout ? [:] : [entry.id: "entries/\(entry.citekey).yaml"],
            action: "這次會從 work「\(label)」拿掉 \(count) 個已在 Zotero 端刪除的附加來源",   // display-safe-exempt: label 已消毒；count 是 Int
            issue: "#609")
        if let refusal = check.refusal { throw AdjudicationError.notRecoverable(refusal: refusal) }   // display-safe-exempt: refusal 由 recordRecoverability 組裝——動作句與標籤在上面逐項 displaySafeInvisible、原因是 filesNotSafelyRecoverable 的固定句
    }
}

/// 裁決台③Quarantine：錯誤原因展示 + 重新驗證。
@Observable
public final class QuarantineModel {
    let state: AppState
    public private(set) var items: [QuarantinedFile] = []

    public init(state: AppState) {
        self.state = state
        items = state.quarantined
    }

    /// 重新載入 library（修好的檔案會離開 quarantine 清單）。
    public func refresh() throws {
        try state.load()
        items = state.quarantined
    }

    public func fileURL(_ item: QuarantinedFile) -> URL {
        state.root.appendingPathComponent(item.file)
    }
}

/// #28：App 的顯示層消毒投影。
///
/// **View 一律用這裡的 `display*`，不要直接綁 `file` / `reason`。** 原始欄位保留是因為
/// `fileURL(_:)` 需要真實檔名去組 URL——消毒過的字串會組出錯誤路徑。`reason` 曾含 Yams 展開的
/// 逐字檔案內容（U+2028/U+2029 在 SwiftUI `Text` 裡就是換行）——**自 R27 D75／R28 D80 起它在建構時
/// 已消毒一次**，這裡只截：再逃一次會把 `StoreKey.pattern` 打成 `\u{005C}A…`（R27 verify 第 11／16 列，
/// 第三個 sink 漏掉）。`file` 仍是原始檔名，這裡逃脫。
public extension QuarantinedFile {
    var displayFile: String { displaySafeInvisible(file, max: 300) }
    var displayReason: String { displaySafeClipOnly(reason, max: 4_096) }   // display-safe-exempt: 已消毒（QuarantinedFile 生產端，R28 D80），只截
}

public extension ResolutionCandidate {
    var displayCitekey: String { displaySafe(citekey, max: 200) }
    var displayReason: String { displaySafeInvisible(reason, max: 300) }   // display-safe-exempt: 未消毒——resolver 的 reason 是程式文字加 rule 名（R28 D80：原始載體，sink 逃一次）
    /// #161：**`literal` 缺投影是 #28 那條規矩最尷尬的漏洞**——規矩寫在上面
    /// （「View 一律用 `display*`」），而 `AdjudicationViews.swift:20` 直接綁
    /// `literal` 的那一行，**下一行**就在用 `displayCitekey` / `displayReason`。
    /// 規矩存在、對象不存在。
    ///
    /// `literal` 是 Zotero 匯入的作者原文——整個 store 裡最第三方的欄位之一，
    /// 而且它出現的畫面正是**破壞性動作的確認畫面**（合併／丟垃圾桶）。
    /// U+202E 能讓「人看著畫面按下去」這道最後防線本身被攻擊。
    var displayLiteral: String { displaySafe(literal, max: 300) }
    // `personKey` 刻意**不給**投影：它是 `person.key`，load 端 quarantine 驗過
    // `StoreKey`（`^[a-z0-9][a-z0-9-]*$`），結構上不可能含控制字元。給它一個
    // 投影會讓「有投影＝危險」這個訊號失真。
}

/// #161：`Entry` 的顯示投影。`title` 是自由字串（Zotero／出版商／網頁），
/// `citekey` 則過 load 端的 `StoreKey` quarantine——**只有前者需要**。
public extension Entry {
    /// #609：已在 Zotero 端刪除的附加來源，`<library_id>:<zotero_key>`（zotero key 是 store 字串，消毒）。
    var displayOrphanedAdditionalSources: String {
        additionalProvenance.filter { $0.orphanedAt != nil }
            .map { "\($0.libraryID.map(String.init) ?? "?"):\(displaySafeInvisible($0.zoteroKey, max: 120))" }
            .joined(separator: "、")
    }
    var displayTitle: String { displaySafe(title, max: 800) }
    /// 清單常見的「有標題用標題、沒有就退回 citekey」。退回值不需消毒，
    /// 但包成一個投影可以讓 View 端不必自己判斷哪一半危險。
    var displayTitleOrCitekey: String { title.isEmpty ? citekey : displaySafe(title, max: 800) }
}

/// #161 verify 181-4：`Author.displayName` 是**一個 `display*` 前綴、卻不消毒**的
/// 屬性——它對 `.literal` 原樣回傳 Zotero 作者原文，與裁決台上包起來的
/// `ResolutionCandidate.literal` 同源。它不能就地改成消毒版（有非顯示的消費端），
/// 所以給 View 一個明確的消毒投影，並在 `DisplayProjectionTests` 釘住那個矛盾。
public extension Entry {
    /// 作者清單的顯示形式。**不要在 View 裡寫 `authors.map(\.displayName)`**——
    /// 那個 `displayName` 名字裡有 `display` 卻不消毒。
    var displayAuthors: String {
        authors.map { displaySafe($0.displayName, max: 300) }.joined(separator: "; ")
    }
}

/// #161：`Library` 的 `name` 是自由字串（load 只驗 `key`）。
public extension Library {
    var displayName: String { displaySafe(name, max: 300) }
    var displayNameOrKey: String { name.isEmpty ? key : displaySafe(name, max: 300) }
}
