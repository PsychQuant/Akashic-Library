import Foundation
import AkashicCore

/// 消歧失敗的原因。全部發生在**動磁碟之前**，除了 `partialWriteFailures`。
public enum DivergenceResolveError: Error, LocalizedError, Equatable {
    case recordNotFound(UUID)
    case survivorNotACandidate(survivor: String, candidates: [String])
    case candidateMissing(key: String, shape: String)
    case outsideVersionControl(root: String)
    case unsupportedShape(String)

    public var errorDescription: String? {
        switch self {
        case let .recordNotFound(id):
            return "找不到 id 為 \(id.uuidString) 的歧異記錄"
        case let .survivorNotACandidate(survivor, candidates):
            return "倖存者「\(displaySafe(survivor, max: 200))」不在候選清單內；"
                 + "實際候選為 \(candidates.map { displaySafe($0, max: 200) }.joined(separator: "、"))"
        case let .candidateMissing(key, shape):
            return "候選「\(displaySafe(key, max: 200))」（\(shape)）在 store 內找不到對應記錄"
        case let .outsideVersionControl(root):
            return "store「\(displaySafe(root, max: 300))」不在版本控制的工作樹內，拒絕刪除。"
                 + "消歧會刪掉被併記錄與歧異記錄本身，歷史託給版本控制而非 store；"
                 + "版控之外刪掉就是真的沒了。先把 store 放進版控（或改用位於工作樹內的 store）再試。"
        case let .unsupportedShape(shape):
            return "本版的消歧只處理 person 與 work，不處理 \(shape)"
        }
    }
}

/// 消歧的結果。**失敗不是擲錯而是回報**——參照重寫途中單筆失敗時，其餘照樣寫，
/// 失敗清單留在這裡由呼叫端決定退出碼（design「失敗模式」最後一列）。
public struct ResolveReport: Equatable {
    /// 參照被改寫的記錄鍵（work 用 citekey，divergence 用 id）。
    public var rewritten: [String]
    /// 被併掉而刪除的實體鍵。
    public var merged: [String]
    /// 一併刪除的歧異記錄 id（含本次消歧的那一筆，以及因候選塌縮而失去意義的其他筆）。
    public var removedDivergences: [String]
    /// 單筆寫入失敗的訊息。非空即代表結束時該以非零碼退出。
    public var failures: [String]

    public var hasFailures: Bool { !failures.isEmpty }

    public init(rewritten: [String] = [], merged: [String] = [],
                removedDivergences: [String] = [], failures: [String] = []) {
        self.rewritten = rewritten
        self.merged = merged
        self.removedDivergences = removedDivergences
        self.failures = failures
    }
}

extension LibraryStore {

    @discardableResult
    public func writeDivergence(_ d: Divergence) throws -> URL {
        let yaml = try DivergenceYAML.encode(d)
        let dest = entityURL(id: d.id)
        try atomicWriteEntity(yaml, to: dest)
        return dest
    }

    /// 消歧：合併別名 → 全庫參照重寫 → 刪除被併記錄與歧異記錄。
    ///
    /// **三者是一個操作**（design D3）。被併掉的候選很可能已被其他記錄引用；只刪檔
    /// 會留下指向不存在鍵的參照，佈局檢查的孤兒計數會跳，但那時已經壞了。
    ///
    /// 順序刻意如此：**所有拒絕條件（含版控前提）都在動磁碟之前**。合併與參照重寫
    /// 已發生卻無法刪除，是比整個拒絕更難修的半完成狀態。
    ///
    /// 沿用 `renameEntry` 的兩條紀律：改寫前跑 `assertNoCrossRecordErrors`（雙佈局並存
    /// 時刪錯檔）、以及**動磁碟前先 encode 全部要寫的記錄**（canary 失敗不該留下撕裂）。
    ///
    /// **刻意沒有 `@discardableResult`**：回傳值裡有 `failures`，而部分失敗是
    /// **不擲錯**的正常回傳（見 `ResolveReport`）。若允許隱式丟棄，`try resolve(…)`
    /// 這一行就會讀起來像成功而實際上吞掉了失敗清單。要丟得自己寫 `_ =`。
    public func resolveDivergence(id: UUID, survivor: String) throws -> ResolveReport {
        guard StoreKey.isValid(survivor) else {
            throw StoreIOError.invalidKey("survivor key", survivor)
        }
        // 區域變數不叫 `load`——那會遮蔽 `load()` 方法本身（`renameEntry` 用
        // `store_loadForRename()` 繞開的是同一件事）。
        let snapshot = try load()
        try assertNoCrossRecordErrors(snapshot, action: "resolve-divergence")

        guard let record = snapshot.divergences.first(where: { $0.id == id }) else {
            throw DivergenceResolveError.recordNotFound(id)
        }
        let candidateKeys = record.candidates.map(\.key)
        guard candidateKeys.contains(survivor) else {
            throw DivergenceResolveError.survivorNotACandidate(
                survivor: survivor, candidates: candidateKeys.sorted())
        }
        guard let shape = record.shape else {
            throw DivergenceResolveError.recordNotFound(id)
        }
        // 版控前提在**任何寫入之前**驗（design D4 + tasks 4.2）。
        guard Self.isInsideVersionedWorkTree(root) else {
            throw DivergenceResolveError.outsideVersionControl(root: root.path)
        }
        let mergedKeys = candidateKeys.filter { $0 != survivor }

        switch shape {
        case .person:
            return try resolvePersonDivergence(record: record, survivor: survivor,
                                               mergedKeys: mergedKeys, snapshot: snapshot)
        case .work:
            return try resolveWorkDivergence(record: record, survivor: survivor,
                                             mergedKeys: mergedKeys, snapshot: snapshot)
        case .organization, .divergence:
            throw DivergenceResolveError.unsupportedShape(shape.rawValue)
        }
    }

    // MARK: - person

    private func resolvePersonDivergence(record: Divergence, survivor: String,
                                         mergedKeys: [String],
                                         snapshot: LibraryLoad) throws -> ResolveReport {
        guard var keeper = snapshot.people.first(where: { $0.key == survivor }) else {
            throw DivergenceResolveError.candidateMissing(key: survivor, shape: "person")
        }
        var doomed: [Person] = []
        for key in mergedKeys {
            guard let p = snapshot.people.first(where: { $0.key == key }) else {
                throw DivergenceResolveError.candidateMissing(key: key, shape: "person")
            }
            doomed.append(p)
        }
        // 別名併入倖存者：被併者的寫法保留，否則下次遇到那個寫法又會重新分割一次。
        keeper.names = dedupePreservingOrder(keeper.names + doomed.flatMap(\.names))

        let merged = Set(mergedKeys)
        var entriesToWrite: [Entry] = []
        for var e in snapshot.entries {
            let rewritten = dedupeAuthors(e.authors.map { author -> Author in
                if case let .key(k) = author, merged.contains(k) { return .key(survivor) }
                return author
            })
            if rewritten != e.authors {
                e.authors = rewritten
                entriesToWrite.append(e)
            }
        }
        let keeperFinal = keeper
        return try commitResolution(record: record,
                                    keeperWrite: { try self.writePerson(keeperFinal) },
                                    keeperEncode: { _ = try PersonYAML.encode(keeperFinal) },
                                    entriesToWrite: entriesToWrite,
                                    doomedIDs: doomed.map(\.id), mergedKeys: mergedKeys,
                                    snapshot: snapshot, survivor: survivor)
    }

    // MARK: - work

    private func resolveWorkDivergence(record: Divergence, survivor: String,
                                       mergedKeys: [String],
                                       snapshot: LibraryLoad) throws -> ResolveReport {
        guard let keeper = snapshot.entries.first(where: { $0.citekey == survivor }) else {
            throw DivergenceResolveError.candidateMissing(key: survivor, shape: "work")
        }
        var doomed: [Entry] = []
        for key in mergedKeys {
            guard let e = snapshot.entries.first(where: { $0.citekey == key }) else {
                throw DivergenceResolveError.candidateMissing(key: key, shape: "work")
            }
            doomed.append(e)
        }
        let merged = Set(mergedKeys)
        let doomedIDs = Set(doomed.map(\.id))
        func migrate(_ keys: [String]) -> [String] {
            dedupePreservingOrder(keys.map { merged.contains($0) ? survivor : $0 })
        }
        var entriesToWrite: [Entry] = []
        var keeperRewritten = keeper
        keeperRewritten.akashic.relations.cites = migrate(keeper.akashic.relations.cites)
        keeperRewritten.akashic.relations.related = migrate(keeper.akashic.relations.related)
        for var e in snapshot.entries where e.id != keeper.id && !doomedIDs.contains(e.id) {
            let cites = migrate(e.akashic.relations.cites)
            let related = migrate(e.akashic.relations.related)
            if cites != e.akashic.relations.cites || related != e.akashic.relations.related {
                e.akashic.relations.cites = cites
                e.akashic.relations.related = related
                entriesToWrite.append(e)
            }
        }
        let keeperFinal = keeperRewritten
        return try commitResolution(record: record,
                                    keeperWrite: { try self.writeEntry(keeperFinal) },
                                    keeperEncode: { _ = try EntryYAML.encode(keeperFinal) },
                                    entriesToWrite: entriesToWrite,
                                    doomedIDs: doomed.map(\.id), mergedKeys: mergedKeys,
                                    snapshot: snapshot, survivor: survivor)
    }

    // MARK: - 共用的落地

    /// 兩種形狀共用的收尾：其他歧異記錄的候選遷移 → 動磁碟前 encode 預檢 → 寫 → 刪。
    private func commitResolution(record: Divergence,
                                  keeperWrite: () throws -> URL,
                                  keeperEncode: () throws -> Void,
                                  entriesToWrite: [Entry],
                                  doomedIDs: [UUID], mergedKeys: [String],
                                  snapshot: LibraryLoad, survivor: String) throws -> ResolveReport {
        // 其他歧異記錄若也指名被併的鍵，同樣要遷移——spec 說的是「store 內**每一個**
        // 指名被併實體的參照」。遷移後若候選塌縮到少於兩個，那筆記錄已被本次消歧回答，
        // 一併刪除；留著會寫出一份 decode 拒收的檔（<2 候選），那是靜默的損壞。
        let merged = Set(mergedKeys)
        var otherToWrite: [Divergence] = []
        var collapsed: [Divergence] = []
        for var other in snapshot.divergences where other.id != record.id {
            let migrated = dedupeCandidates(other.candidates.map { c in
                merged.contains(c.key)
                    ? DivergenceCandidate(key: survivor, shape: c.shape) : c
            })
            guard migrated != other.candidates else { continue }
            if migrated.count < 2 {
                collapsed.append(other)
            } else {
                other.candidates = migrated
                otherToWrite.append(other)
            }
        }

        // 動磁碟前的 encode 預檢（沿用 renameEntry 的紀律）：可預期的失敗全部先擋掉，
        // 剩下的只有磁碟層錯誤——那才是下面逐筆收容要處理的。
        try keeperEncode()
        for e in entriesToWrite { _ = try EntryYAML.encode(e) }
        for d in otherToWrite { _ = try DivergenceYAML.encode(d) }

        var report = ResolveReport()
        do {
            _ = try keeperWrite()
        } catch {
            // 倖存者寫不進去就沒有「合併」可言，後面的刪除會直接造成資料遺失。
            throw error
        }
        for e in entriesToWrite {
            do {
                try writeEntry(e)
                report.rewritten.append(e.citekey)
            } catch {
                report.failures.append("寫入 \(displaySafe(e.citekey, max: 200)) 失敗："
                    + ((error as? LocalizedError)?.errorDescription ?? String(describing: error)))
            }
        }
        for d in otherToWrite {
            do {
                try writeDivergence(d)
                report.rewritten.append(d.id.uuidString)
            } catch {
                report.failures.append("寫入歧異記錄 \(d.id.uuidString) 失敗："
                    + ((error as? LocalizedError)?.errorDescription ?? String(describing: error)))
            }
        }

        // 刪除：被併實體 → 塌縮的歧異記錄 → 本次的歧異記錄。
        // **參照重寫有失敗時不刪**——那正是「部分改寫且索引過期」的撕裂狀態，
        // 刪掉被併記錄會讓還沒改寫的參照永久懸空。
        guard !report.hasFailures else {
            report.failures.append("因上述失敗，被併記錄與歧異記錄都未刪除（可修好後重跑）")
            return report
        }
        for id in doomedIDs {
            do {
                try FileManager.default.removeItem(at: entityURL(id: id))
            } catch {
                report.failures.append("刪除 \(id.uuidString) 失敗："
                    + ((error as? LocalizedError)?.errorDescription ?? String(describing: error)))
            }
        }
        report.merged = mergedKeys.sorted()
        for d in collapsed + [record] {
            do {
                try FileManager.default.removeItem(at: entityURL(id: d.id))
                report.removedDivergences.append(d.id.uuidString)
            } catch {
                report.failures.append("刪除歧異記錄 \(d.id.uuidString) 失敗："
                    + ((error as? LocalizedError)?.errorDescription ?? String(describing: error)))
            }
        }
        report.rewritten.sort()
        report.removedDivergences.sort()
        return report
    }

    // MARK: - 小工具

    /// store 是否位於版本控制的工作樹內。
    ///
    /// 從 store root 逐層往上找 `.git`——**目錄或檔案都算**（worktree 與 submodule 的
    /// `.git` 是一個指向真正 git 目錄的檔案）。不呼叫 `git` 執行檔：這裡要回答的是
    /// spec 寫的「store 是否落在版控工作樹內」，那是檔案系統事實，不需要外部程序。
    ///
    /// **誠實邊界**：工作樹內不等於已被追蹤——被 ignore 的路徑一樣通過。這條檢查擋
    /// 的是「store 根本不在任何 repo 裡」這個真正不可逆的情況。
    ///
    /// **走字串而非 `URL.deletingLastPathComponent()`**：後者在根目錄不會停——它回傳
    /// `/..`，再一次得 `/../..`，路徑無限成長。第一版就是這樣寫的，測試跑成 88% CPU
    /// 加 29 GB RSS 的失控迴圈。`NSString` 的同名操作在 `/` 會回傳 `/`，加上明寫的
    /// 根目錄出口，兩道保險。
    static func isInsideVersionedWorkTree(_ root: URL) -> Bool {
        var path = root.resolvingSymlinksInPath().standardizedFileURL.path
        while true {
            let candidate = path.hasSuffix("/") ? path + ".git" : path + "/.git"
            if FileManager.default.fileExists(atPath: candidate) { return true }
            if path == "/" || path.isEmpty { return false }
            let parent = (path as NSString).deletingLastPathComponent
            if parent == path { return false }
            path = parent
        }
    }

    private func atomicWriteEntity(_ content: String, to dest: URL) throws {
        try FileManager.default.createDirectory(
            at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
        let tmp = dest.deletingLastPathComponent()
            .appendingPathComponent(".\(dest.lastPathComponent).tmp-\(UUID().uuidString)")
        try content.write(to: tmp, atomically: false, encoding: .utf8)
        do {
            let fm = FileManager.default
            if fm.fileExists(atPath: dest.path) {
                _ = try fm.replaceItemAt(dest, withItemAt: tmp)
            } else {
                try fm.moveItem(at: tmp, to: dest)
            }
        } catch {
            try? FileManager.default.removeItem(at: tmp)
            throw error
        }
    }
}

private func dedupePreservingOrder(_ values: [String]) -> [String] {
    var seen = Set<String>()
    return values.filter { seen.insert($0).inserted }
}

/// 作者順序有意義（第一作者不是隨便排的），所以去重保留**最先**出現的位置。
/// 只有 `.key` 會因合併而重複；`.literal` 原樣保留，兩個同字面的 literal 不合併。
private func dedupeAuthors(_ authors: [Author]) -> [Author] {
    var seen = Set<String>()
    return authors.filter { a in
        guard case let .key(k) = a else { return true }
        return seen.insert(k).inserted
    }
}

private func dedupeCandidates(_ candidates: [DivergenceCandidate]) -> [DivergenceCandidate] {
    var seen = Set<String>()
    return candidates.filter { seen.insert("\($0.shape.rawValue)\u{0}\($0.key)").inserted }
}
