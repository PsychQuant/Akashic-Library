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

    public init(state: AppState) {
        self.state = state
        refresh()
    }

    public func refresh() {
        candidates = PersonResolver.candidates(entries: state.entries, people: state.people)
            .filter { !state.skippedPeopleCandidates.contains(id(of: $0)) }
    }

    public func accept(_ candidate: ResolutionCandidate) throws {
        let applied = PersonResolver.apply([candidate], to: state.entries)
        // R7（R6-verify M21）：per-item 收容——先寫完能寫的、reindex 保持一致，
        // 再把第一個失敗往上拋給 UI（不留「部分改寫 + index stale」）
        var firstFailure: Error?
        for (before, after) in zip(state.entries, applied) where before != after {
            do {
                try state.store.writeEntry(after)
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

    private func id(of c: ResolutionCandidate) -> String { "\(c.citekey):\(c.authorIndex)" }
}

public enum AdjudicationError: Error, LocalizedError, Equatable {
    case entryNotFound(String)
    case notAnOrphan(String)

    public var errorDescription: String? {
        switch self {
        // #155：key 是 store 衍生（citekey，來自 Zotero 匯入等第三方來源）——
        // App 的 error 顯示在 SwiftUI，威脅模型比 MCP-直達-LLM 弱，但同 bug class
        // 的一致性值得（#142 sweep 的溢出）。
        case .entryNotFound(let key):
            return "找不到 entry「\(displaySafe(key, max: 200))」——外部變更可能已移除，請重新整理"
        case .notAnOrphan(let key):
            return "「\(displaySafe(key, max: 200))」不是 orphan——外部同步可能已恢復連結，已拒絕破壞性動作"
        }
    }
}

/// 裁決台②Orphans：等待（預設）／刪檔（垃圾桶可救回）／轉純 Akashic entry。
@Observable
public final class OrphanModel {
    let state: AppState

    public init(state: AppState) {
        self.state = state
    }

    public var orphans: [Entry] { state.orphanedEntries }

    public enum Action {
        /// 檔案進垃圾桶（FileManager.trashItem——可救回，比 CLI 寬容的 App 專屬安全網）
        case moveToTrash
        /// 抹 provenance → 轉純 Akashic entry（不再參與 Zotero pull）
        case detachFromZotero
    }

    public func resolve(citekey: String, action: Action) throws {
        // 破壞性動作當下重新讀盤驗證——確認對話框開啟期間 Zotero pull 可能
        // 已把 entry 恢復正常（TOCTOU）；記憶體清單不可作為安全邊界。
        guard let entry = try state.store.load().entries
            .first(where: { $0.citekey == citekey }) else {
            throw AdjudicationError.entryNotFound(citekey)
        }
        guard entry.provenance?.orphanedAt != nil else {
            throw AdjudicationError.notAnOrphan(citekey)
        }
        switch action {
        case .moveToTrash:
            var trashed: NSURL?
            try FileManager.default.trashItem(
                at: state.store.usesEntitiesLayout   // #35
                    ? state.store.entityURL(id: entry.id)
                    : state.store.entryURL(citekey: entry.citekey),
                resultingItemURL: &trashed)
        case .detachFromZotero:
            var detached = entry
            detached.provenance = nil
            try state.store.writeEntry(detached)
        }
        try state.reindexAndReload()
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
/// `fileURL(_:)` 需要真實檔名去組 URL——消毒過的字串會組出錯誤路徑。`reason` 更危險：
/// 它含 Yams 展開的逐字檔案內容，U+2028/U+2029 在 SwiftUI `Text` 裡就是換行，
/// C0 的 ESC 在某些 render 路徑下也會被解讀。
public extension QuarantinedFile {
    var displayFile: String { displaySafe(file, max: 300) }
    var displayReason: String { displaySafe(reason, max: 512) }
}

public extension ResolutionCandidate {
    var displayCitekey: String { displaySafe(citekey, max: 200) }
    var displayReason: String { displaySafe(reason, max: 300) }
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
