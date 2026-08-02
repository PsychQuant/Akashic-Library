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
        case .entryNotFound(let key):
            return "找不到 entry「\(key)」——外部變更可能已移除，請重新整理"
        case .notAnOrphan(let key):
            return "「\(key)」不是 orphan——外部同步可能已恢復連結，已拒絕破壞性動作"
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
                at: state.store.entryURL(citekey: entry.citekey), resultingItemURL: &trashed)
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
