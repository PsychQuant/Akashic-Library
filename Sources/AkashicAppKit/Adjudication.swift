import Foundation
import Observation
import AkashicCore
import AkashicStoreIO
import AkashicEntity
import AkashicIndex

/// 裁決台①People：resolve 候選逐一 accept／skip（絕不批次自動套用）。
@Observable
public final class PeopleResolveModel {
    let state: AppState
    public private(set) var candidates: [ResolutionCandidate] = []
    /// session 內 skip 的候選（不落檔）。
    private var skipped = Set<String>()

    public init(state: AppState) {
        self.state = state
        refresh()
    }

    public func refresh() {
        candidates = PersonResolver.candidates(entries: state.entries, people: state.people)
            .filter { !skipped.contains(id(of: $0)) }
    }

    public func accept(_ candidate: ResolutionCandidate) throws {
        let applied = PersonResolver.apply([candidate], to: state.entries)
        for (before, after) in zip(state.entries, applied) where before != after {
            try state.store.writeEntry(after)
        }
        try state.reindexAndReload()
        refresh()
    }

    /// skip 只影響本 session 的清單，不寫任何檔案。
    public func skip(_ candidate: ResolutionCandidate) {
        skipped.insert(id(of: candidate))
        refresh()
    }

    private func id(of c: ResolutionCandidate) -> String { "\(c.citekey):\(c.authorIndex)" }
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
        guard let entry = state.entries.first(where: { $0.citekey == citekey }) else { return }
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
