import Foundation
import AkashicCore

/// 消歧失敗的原因。全部發生在**動磁碟之前**，除了 `partialWriteFailures`。
public enum DivergenceResolveError: Error, LocalizedError, Equatable {
    case recordNotFound(UUID)
    case survivorNotACandidate(survivor: String, candidates: [String])
    case candidateMissing(key: String, shape: String)
    case outsideVersionControl(root: String)
    case unsupportedShape(String)
    case legacyLayout(root: String)
    case wouldLoseFields(merged: String, survivor: String, losses: [String])
    case quarantinedPresent(files: [String])

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
        case let .legacyLayout(root):
            return "store「\(displaySafe(root, max: 300))」是 legacy 佈局（format < 2），"
                 + "歧異記錄需要 entities/ 佈局。legacy 下 person 落在 people/<key>.yaml、"
                 + "而歧異記錄的刪除只認 entities/<uuid>.yaml——寫得進去、刪不掉，"
                 + "必然停在「參照全改了、被併檔還在」的半完成狀態。先跑 akashic migrate。"
        case let .wouldLoseFields(merged, survivor, losses):
            return "拒絕合併：被併的「\(displaySafe(merged, max: 200))」帶有倖存者"
                 + "「\(displaySafe(survivor, max: 200))」沒有的資料，合併會讓它隨檔案消失——"
                 + losses.map { displaySafe($0, max: 300) }.joined(separator: "；")
                 + "。先把要保留的搬到倖存者身上（或確認可以丟棄後手動清除），再消歧。"
        case let .quarantinedPresent(files):
            return "store 有 \(files.count) 個讀不進來的檔，消歧拒絕執行——"
                 + "它們可能正指著要被刪掉的實體，而讀不到就改寫不到，刪除後會留下"
                 + "藏在工具看不見處的永久懸空參照："
                 + files.prefix(3).map { displaySafe($0, max: 200) }.joined(separator: "、")
                 + (files.count > 3 ? "…" : "")
                 + "。跑 akashic doctor 看每個檔的原因，然後手動修好或移出 store 再試"
                 + "（doctor 只診斷、不修）。"
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
    /// 倖存者是否已被改寫（別名合併已落地）。**失敗路徑也可能為 true**——它是
    /// 既成事實而非成功訊號；不說出來，`merged` 為空會讀成「什麼都沒發生」。
    public var survivorUpdated: Bool

    public var hasFailures: Bool { !failures.isEmpty }

    public init(rewritten: [String] = [], merged: [String] = [],
                removedDivergences: [String] = [], failures: [String] = [],
                survivorUpdated: Bool = false) {
        self.rewritten = rewritten
        self.merged = merged
        self.removedDivergences = removedDivergences
        self.failures = failures
        self.survivorUpdated = survivorUpdated
    }
}

extension LibraryStore {

    /// `writeDivergence` 的**全部**前置條件，抽出來讓預檢能完整鏡射。
    ///
    /// 存在的理由是一次實測的撕裂：`renameEntry` 的動磁碟前預檢只跑了
    /// `DivergenceYAML.encode`，漏掉這裡的兩道守衛，於是 entry 全部寫完之後才在
    /// `writeDivergence` 擲錯——磁碟上 rename 已完成、呼叫端收到錯誤、索引永遠不重建
    /// （#71 R2 DA 的 PROBE 3）。**預檢與寫入分別維護各自的條件清單，就是憑記憶維護
    /// 清單**；本 repo 對 `displaySafe` 已經明文拒絕過這種做法。
    func assertDivergenceWritable(_ d: Divergence) throws {
        guard usesEntitiesLayout else {
            throw DivergenceResolveError.legacyLayout(root: root.path)
        }
        // 候選鍵的 write-time 驗證，與其他每一條寫入路徑一致。**理由不是 path
        // traversal**（R1 的 DA 已證明候選鍵從未進過任何路徑），而是
        // `Divergence.validate()` 對畸形候選鍵報 error——沒有這道守衛，工具就能寫出
        // 一筆自己的 validate 永遠不會通過、而又沒有編輯入口可以修的記錄。
        for c in d.candidates where !StoreKey.isValid(c.key) {
            throw StoreIOError.invalidKey("divergence candidate key", c.key)
        }
    }

    /// **要求 entities 佈局**。legacy store 上寫得進去卻刪不掉——見
    /// `DivergenceResolveError.legacyLayout`。拒絕比部分支援誠實。
    @discardableResult
    public func writeDivergence(_ d: Divergence) throws -> URL {
        try assertDivergenceWritable(d)
        let yaml = try DivergenceYAML.encode(d)
        let dest = entityURL(id: d.id)
        try FileManager.default.createDirectory(at: entitiesDir, withIntermediateDirectories: true)
        try atomicWrite(yaml, to: dest)
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
        // 佈局前提比版控前提更早——legacy 上連寫都不該發生。
        guard usesEntitiesLayout else {
            throw DivergenceResolveError.legacyLayout(root: root.path)
        }
        // 區域變數不叫 `load`——那會遮蔽 `load()` 方法本身（`renameEntry` 用
        // `store_loadForRename()` 繞開的是同一件事）。
        let snapshot = try load()
        try assertNoCrossRecordErrors(snapshot, action: "resolve-divergence")
        // **讀不到的檔可能正指著要被刪掉的東西。** spec 要求改寫「store 內每一個」
        // 指名被併實體的參照，而 quarantined 檔根本沒進 `snapshot.entries`——它的
        // 參照永遠不會被改寫，卻擋不住刪除，留下一筆藏在工具讀不到的檔案裡、
        // `crossRecordIssues()` 也掃不到的永久懸空參照。這與本檔對 legacy 佈局採取的
        // 立場（拒絕比部分支援誠實）是同一條理由，不該一邊拒絕一邊靜默放行。
        guard snapshot.quarantined.isEmpty else {
            throw DivergenceResolveError.quarantinedPresent(
                files: snapshot.quarantined.map(\.file).sorted())
        }

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
        // **合併只搬別名，所以別名以外的東西不許有。** 被併者若帶著倖存者沒有的
        // 識別碼或時間軸，那些資料會隨檔案一起消失而使用者只看到「✓ 併入」。歧異的
        // 典型來源正是「兩個聚合器對同一位作者的比對結果不一致」——那種情況下兩筆
        // 各帶一半識別碼的機率很高。所以拒絕並指名將失去什麼，讓人先搬再消歧。
        for p in doomed {
            let losses = Self.fieldsLostByMerging(p, into: keeper)
            guard losses.isEmpty else {
                throw DivergenceResolveError.wouldLoseFields(
                    merged: p.key, survivor: survivor, losses: losses)
            }
        }
        // 別名併入倖存者：被併者的寫法保留，否則下次遇到那個寫法又會重新分割一次。
        keeper.names = dedupePreservingOrder(keeper.names + doomed.flatMap(\.names))

        let merged = Set(mergedKeys)
        var entriesToWrite: [Entry] = []
        for var e in snapshot.entries {
            // **只碰真的指名被併鍵的記錄。** 先判斷有沒有命中，再改寫——否則
            // `dedupeAuthors` 會順手把**既存的**重複作者折疊掉，改動一筆與本次消歧
            // 毫無關係的記錄，還把它算進 `rewritten`。消歧不是清理工具。
            guard e.authors.contains(where: {
                if case let .key(k) = $0 { return merged.contains(k) }
                return false
            }) else { continue }
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
        // **倖存者自己的參照要再濾掉 survivor**：keeper 原本引用的是「另一筆作品」，
        // 合併之後那筆就是 keeper 自己。`renameEntry` 做同樣的自我參照遷移是對的
        // （同一筆記錄換稱呼），但合併的語意不同——留著會產生引用自己的記錄，而
        // `crossRecordIssues()` 既不查自我引用也不查 relations 懸空，沒人會發現。
        //
        // **同樣只在真的命中時才動。** 這兩行原本無條件跑，於是 keeper 既存的重複
        // 參照與既存的自我參照都被靜默折掉——而且因為 keeper 一定會被寫回，連
        // `rewritten` 都不會提它，比誤報還糟（#71 R2 DA PROBE 8）。
        func migrateOwn(_ keys: [String]) -> [String] {
            guard keys.contains(where: { merged.contains($0) }) else { return keys }
            return migrate(keys).filter { $0 != survivor }
        }
        keeperRewritten.akashic.relations.cites = migrateOwn(keeper.akashic.relations.cites)
        keeperRewritten.akashic.relations.related = migrateOwn(keeper.akashic.relations.related)
        for var e in snapshot.entries where e.id != keeper.id && !doomedIDs.contains(e.id) {
            // 同 person 側：沒指名被併鍵就別碰它，否則 `dedupePreservingOrder` 會把
            // 既存的重複參照順手折疊掉，改動與本次消歧無關的記錄。
            guard e.akashic.relations.cites.contains(where: { merged.contains($0) })
                || e.akashic.relations.related.contains(where: { merged.contains($0) })
            else { continue }
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
        // **比 key 也要比 shape。** 鍵在不同形狀之間可以同名（organization spec 明載
        // 「key 與 person 同名是刻意的」），`shape:` 存進記錄的唯一理由就是這個。只比
        // key 會把一筆機構歧異的候選改寫成指向 person 鍵，甚至讓它塌縮後被整筆刪除
        // ——一個使用者從未回答、也與本次消歧無關的問題就這樣消失（#71 R1 verify）。
        let mergedShape = record.shape
        var otherToWrite: [Divergence] = []
        var collapsed: [Divergence] = []
        for var other in snapshot.divergences where other.id != record.id {
            let migrated = dedupeCandidates(other.candidates.map { c in
                (merged.contains(c.key) && c.shape == mergedShape)
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
        // **倖存者已經被改寫了，這是既成事實。** 之後任何失敗路徑退出時，若不說出
        // 這件事，`merged=[]` 讀起來像「什麼都沒發生」，而使用者手上的 store 已經
        // 不是他以為的那個（#71 R2 DA 的 PROBE 12）。重跑碰巧冪等，但那是
        // `dedupePreservingOrder` 的副作用而非設計，不該當成保證。
        report.survivorUpdated = true
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
            report.failures.append(
                "因上述失敗，被併記錄與歧異記錄都未刪除；"
                + "但倖存者的別名合併**已經落地**（磁碟上不是原狀）")
            report.rewritten.sort()
            return report
        }
        for id in doomedIDs {
            // 檔案已不存在 = 這一步先前已完成。重跑必須冪等，否則「修好後重跑」
            // 這句話對部分完成的狀態是假的。
            guard FileManager.default.fileExists(atPath: entityURL(id: id).path) else { continue }
            do {
                try FileManager.default.removeItem(at: entityURL(id: id))
            } catch {
                report.failures.append("刪除 \(id.uuidString) 失敗："
                    + ((error as? LocalizedError)?.errorDescription ?? String(describing: error)))
            }
        }
        // **被併實體沒全刪掉就不刪歧異記錄。** 歧異記錄是唯一記得「這兩筆可能是同
        // 一個」的東西，也是重跑的唯一依據；先刪它再讓被併檔留著，使用者只能手工
        // 比對 git 才知道發生過什麼——正是本函式開頭宣稱要避免的半完成狀態。
        // `report.merged` 同樣要等真的刪成功才填，否則 CLI 會同時印「✓ 併入」與失敗。
        guard !report.hasFailures else {
            report.failures.append("因刪除失敗，歧異記錄保留（修好後可重跑同一個 id）")
            report.rewritten.sort()
            return report
        }
        report.merged = mergedKeys.sorted()
        for d in collapsed + [record] {
            guard FileManager.default.fileExists(atPath: entityURL(id: d.id).path) else {
                report.removedDivergences.append(d.id.uuidString)
                continue
            }
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

    // MARK: - 合併會失去什麼

    /// 把 `p` 併進 `keeper` 會讓哪些內容隨檔案消失。空陣列 = 什麼都不會失去。
    ///
    /// **問的是子集關係，不是相等。** 「被併者帶著倖存者缺少或衝突的東西」無法用整體
    /// 相等表達——曾經寫成「被併者要嘛與倖存者相同、要嘛全預設」，那會誤拒**最常見**
    /// 的形狀：使用者把資料較完整的那筆選為倖存者（消歧的常態），而被併者只要帶任何
    /// 一個非預設欄位就被擋死，儘管它沒有任何東西會消失（#71 R2 DA 實測）。
    ///
    /// **所以逐欄是必要的，防腐不能靠結構比較。** 靠的是
    /// `PersonFieldCoverageTests`：它用反射數 `Person` 的儲存屬性，與本函式聲明涵蓋的
    /// 數量不符就紅。加欄位而忘了這裡，測試會說話——不是靠註解提醒，也不是靠記憶。
    ///
    /// 涵蓋 `Person` 的 8 個儲存屬性：`key` / `id`（身分，不隨合併移動）、
    /// `names`（別名，由合併搬移）、以及下列五個。
    static func fieldsLostByMerging(_ p: Person, into keeper: Person) -> [String] {
        var losses: [String] = []
        func check(_ label: String, mine: String?, theirs: String?) {
            guard let theirs, !theirs.isEmpty else { return }  // 沒帶 → 不會失去
            guard mine != theirs else { return }               // 倖存者已有同值 → 不會失去
            losses.append("\(label): \(theirs)")
        }
        check("orcid", mine: keeper.orcid, theirs: p.orcid)
        check("openalex", mine: keeper.openalex, theirs: p.openalex)
        check("note", mine: keeper.note, theirs: p.note)
        if p.profile != PersonProfile(), p.profile != keeper.profile {
            losses.append("profile（隸屬等時間軸）")
        }
        let extra = p.unknownFields.filter { !keeper.unknownFields.contains($0) }
        if !extra.isEmpty {
            losses.append("未知欄位 " + extra.map(\.key).joined(separator: "、"))
        }
        return losses
    }

    /// 本函式涵蓋的 `Person` 儲存屬性數。`PersonFieldCoverageTests` 拿它與反射比對。
    static let personFieldsCoveredByMergeCheck = 8

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
