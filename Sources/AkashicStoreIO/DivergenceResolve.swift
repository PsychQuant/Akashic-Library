import Foundation
import AkashicCore

/// 消歧失敗的原因。全部發生在**動磁碟之前**，除了 `partialWriteFailures`。
public enum DivergenceResolveError: Error, LocalizedError {
    case recordNotFound(UUID)
    case survivorNotACandidate(survivor: String, candidates: [String])
    case candidateMissing(key: String, shape: String)
    case outsideVersionControl(root: String)
    case unsupportedShape(String)
    case legacyLayout(root: String)
    case wouldLoseFields(merged: String, survivor: String, losses: [String])
    case quarantinedPresent(files: [String])
    case candidateNotInEntities(key: String, expected: String)
    /// #73：要刪的檔案不在版控裡、或有未提交的修改——刪掉就真的沒了。
    case deletionNotRecoverable(files: [(path: String, why: String)])

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
        case let .deletionNotRecoverable(files):
            return "以下檔案刪掉之後無法從版控取回，拒絕消歧：\n"
                 + files.map { "  - \(displaySafe($0.path, max: 300))：\($0.why)" }
                        .joined(separator: "\n")
                 + "\n消歧會刪掉被併記錄與歧異記錄本身，歷史託給版控而非 store。"
                 + "先 `git add` 並 `git commit` 這些檔案（或確認 entities/ 沒被 .gitignore 擋），再重跑同一個 id。"
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
        case let .candidateNotInEntities(key, expected):
            return "候選「\(displaySafe(key, max: 200))」的記錄不在 "
                 + "\(displaySafe(expected, max: 300))——store 的佈局不一致"
                 + "（marker 說 entities，記錄卻在 legacy 目錄）。"
                 + "消歧的刪除只認 entities/<uuid>.yaml，硬跑會變成「參照全改了、"
                 + "被併檔還在、而且沒有任何訊號」。先跑 akashic migrate。"
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

    /// 記下一個未決的同一性問題（#77）。
    ///
    /// #71 讓歧異成為可記錄的一級事物，`writeDivergence` 與 `resolveDivergence` 都備妥，
    /// 消歧也有 CLI 入口——但**沒有任何方式建立一筆記錄**。於是「先記下來、之後再判斷」
    /// 在使用層不成立：實務上只能手寫 YAML 繞過編碼器（位元組形式無保證），或當場把
    /// 判斷做掉而不留痕。這個入口把型別層已有的能力接到使用層。
    ///
    /// **候選必須已經存在**：對不存在的鍵記歧異沒有意義，而且 `resolveDivergence` 之後
    /// 會撞上同一個缺席——晚報不如早報。
    ///
    /// **記下判斷不等於做掉它。** 消歧是一個操作（`resolveDivergence`），不是一個欄位。
    @discardableResult
    public func recordDivergence(question: String,
                                 candidates: [(key: String, shape: EntityKind)],
                                 judgement: String?,
                                 restsOn: [String]) throws -> Divergence {
        guard candidates.count >= 2 else {
            throw StoreIOError.invalidInput(
                what: "divergence candidates", why: "需要兩個以上的候選，得到 \(candidates.count) 個")
        }
        // 「沒有依據的斷言不是判斷，沒有斷言的依據不知道在支持什麼」（#71 的不變式）。
        // 編碼器也會擋，但那時的訊息在 YAML 層——這裡擋，訊息才貼近使用者的動作。
        if (judgement != nil) != !restsOn.isEmpty {
            throw StoreIOError.invalidInput(
                what: "divergence judgement",
                why: "判斷與依據必須成對：有 judgement 就要有 rests-on（依據），反之亦然")
        }
        let load = try load()
        // **per-shape 存在檢查**（#133 verify F2）：曾用 people ∪ organizations 的
        // 合集只驗 key 不驗 shape——person 被記成 work 照樣寫入，validate 警告
        // 「無法被消歧」而 MCP 面完全看不見；真正的 work（citekey）反而不在集合裡、
        // 結構上不可用。shape 說是什麼，就到那個形狀的集合裡驗。
        let byShape: [EntityKind: Set<String>] = [
            .person: Set(load.people.map(\.key)),
            .organization: Set(load.organizations.map(\.key)),
            .work: Set(load.entries.map(\.citekey)),
        ]
        for c in candidates {
            guard let pool = byShape[c.shape] else {
                throw StoreIOError.invalidInput(
                    what: "divergence candidate",
                    why: "shape「\(c.shape.rawValue)」不可作候選——歧異記錄沒有 key，不是可被指涉的對象")
            }
            guard pool.contains(c.key) else {
                throw StoreIOError.invalidInput(
                    what: "divergence candidate",
                    why: "store 內沒有 \(c.shape.rawValue)「\(c.key)」——對不存在的鍵記歧異沒有意義（key 存在但形狀不符也算不存在：shape 說是什麼就驗什麼）")
            }
        }
        let id = DeterministicUUID.forDivergence(candidateKeys: candidates.map(\.key))
        // **補寫允許、毀損拒絕**（#133 verify F1）：同組候選＝同一筆記錄（決定性
        // UUID），re-record 是原子全替換——曾經「無判斷的新呼叫」會把既有判斷
        // **靜默抹掉**（question 也無聲換掉）。撤銷判斷是刻意動作，不是省略參數
        // 的副作用；更新判斷（有→有）與補上判斷（無→有）照常。
        if let existing = load.divergences.first(where: { $0.id == id }),
           existing.judgement != nil, judgement == nil {
            throw StoreIOError.invalidInput(
                what: "divergence（同組候選既有記錄）",
                why: "這組候選已有判斷（\(displaySafe(existing.judgement!.statement, max: 120))）——" +
                     "無判斷的重呼叫不得靜默抹掉它。要更新判斷請帶新的 judgement + rests-on；" +
                     "要撤銷判斷請直接編輯該檔（entities/\(id.uuidString).yaml）")
        }
        let d = Divergence(
            id: id,
            question: question,
            candidates: candidates.map { DivergenceCandidate(key: $0.key, shape: $0.shape) },
            judgement: judgement.map { Judgement(statement: $0, restsOn: restsOn) })
        _ = try writeDivergence(d)
        return d
    }

    /// **要求 entities 佈局**。legacy store 上寫得進去卻刪不掉——見
    /// `DivergenceResolveError.legacyLayout`。拒絕比部分支援誠實。
    @discardableResult
    public func writeDivergence(_ d: Divergence) throws -> URL {
        // #108/#136-F8：先問「是不是 store」再問「是不是 entities 佈局」——
        // 不存在的 root 曾被 legacyLayout 錯誤（「你的 store 是 legacy 佈局」）
        // 誤導，真正的問題是路徑根本不存在
        try assertStoreRoot()
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
        //
        // **只擋得住持有實體參照的那些目錄。** gate 的理由是「讀不到就改寫不到」，
        // 而 `people/` 與 `libraries/` 的記錄結構上不可能指向被併的 work 或 person
        // （person 不引用 person，library 只有 metadata）。把它們一起擋，理由對它們
        // 就是假的——而擋在最需要消歧的 store 狀態（多來源、半遷移）上（#71 R2 DA）。
        let blocking = snapshot.quarantined
            .filter { $0.file.hasPrefix("entities/") || $0.file.hasPrefix("entries/") }
        guard blocking.isEmpty else {
            throw DivergenceResolveError.quarantinedPresent(files: blocking.map(\.file).sorted())
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

        // #73：「在工作樹內」不等於「刪掉還找得回來」。D5 把 store 內的歷史全部
        // 拿掉（不做 tombstone、不留已解決狀態），整個回溯性押在版控上——那就必須
        // 驗到**這些檔案真的在版控裡**，而不只是「附近有個 .git」。
        //
        // 三種都不觸發舊檢查、但歷史真的會消失的情況：
        //   1. store 在 repo 內但 entities/ 被 ignore → 檔案從未進 git object
        //   2. 歧異記錄建立後尚未 commit 就被消歧（**最常見**）→ 三個欄位一起永久消失
        //   3. 被併實體有未提交的修改 → 那個版本不可回復
        //
        // 檢查的是**本次要刪的那些檔案**，不是整棵樹——store 其他地方髒不影響這次
        // 刪除的可回溯性，擋下它只會讓工具在正常工作節奏中變得難用。
        let doomedFiles = doomedRelativePaths(record: record, shape: shape,
                                              mergedKeys: mergedKeys, snapshot: snapshot)
        let unsafe = Self.filesNotSafelyRecoverable(root: root, relativePaths: doomedFiles)
        guard unsafe.isEmpty else {
            throw DivergenceResolveError.deletionNotRecoverable(files: unsafe)
        }

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
        try assertAllInEntities(([keeper] + doomed).map { ($0.key, $0.id) })
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
                                    snapshot: snapshot, survivor: survivor,
                                    survivorNote: "倖存者的別名合併已經落地（磁碟上不是原狀）")
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
        try assertAllInEntities(([keeper] + doomed).map { ($0.citekey, $0.id) })
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
                                    snapshot: snapshot, survivor: survivor,
                                    survivorNote: "倖存者的記錄已被重寫"
                                        + "（work 消歧不搬欄位，見 #75）")
    }

    // MARK: - 共用的落地

    /// 兩種形狀共用的收尾：其他歧異記錄的候選遷移 → 動磁碟前 encode 預檢 → 寫 → 刪。
    private func commitResolution(record: Divergence,
                                  keeperWrite: () throws -> URL,
                                  keeperEncode: () throws -> Void,
                                  entriesToWrite: [Entry],
                                  doomedIDs: [UUID], mergedKeys: [String],
                                  snapshot: LibraryLoad, survivor: String,
                                  survivorNote: String) throws -> ResolveReport {
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
                "因上述失敗，被併記錄與歧異記錄都未刪除；但\(survivorNote)")
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
            // 這條路徑先前完全沒提倖存者已被改寫——「歧異記錄保留」讀起來像
            // 「什麼都沒發生」（#71 R3 DA 新 4）。
            report.failures.append(
                "因刪除失敗，歧異記錄保留（修好後可重跑同一個 id）；但\(survivorNote)")
            report.rewritten.sort()
            return report
        }
        report.merged = mergedKeys.sorted()
        for d in collapsed + [record] {
            // 檔案不在 = 先前已刪。不回報成本輪的成果——回報一件沒做的事，
            // 與靜默同樣誤導。
            guard FileManager.default.fileExists(atPath: entityURL(id: d.id).path) else { continue }
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

    /// 每個候選的檔案都必須真的在 `entities/<uuid>.yaml`。
    ///
    /// **這道前置存在，下游的「冪等刪除」才成立。** `load()` 同時讀 entities/ 與
    /// legacy 目錄，所以一筆住在 `people/<key>.yaml` 的 person 照樣進得了
    /// `snapshot.people`；而刪除只組 `entityURL(id:)`。沒有這道檢查，刪除迴圈的
    /// 「檔案不存在就跳過」會把**刪不掉**當成**已刪掉**——參照全改了、被併檔原封
    /// 不動、歧異記錄被刪、`crossRecordIssues()` 一個警告都沒有、CLI 印 ✓ 並 exit 0
    /// （#71 R3 DA 的 P3 實測）。有了它，「檔案不在」就只可能是「已經刪過」。
    private func assertAllInEntities(_ pairs: [(key: String, id: UUID)]) throws {
        for (key, id) in pairs
        where !FileManager.default.fileExists(atPath: entityURL(id: id).path) {
            throw DivergenceResolveError.candidateNotInEntities(
                key: key, expected: "entities/\(id.uuidString).yaml")
        }
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
        // #67：逝世日期。兩邊給出**不同**日期時尤其要擋——那不是排版差異，是對
        // 「這兩筆是不是同一個人」的反證，或至少是一個必須有人裁決的來源衝突。
        check("died", mine: keeper.died, theirs: p.died)
        check("note", mine: keeper.note, theirs: p.note)

        // #81：對外可稱呼的名字是**集合**不是純量——被併者指定過而倖存者沒指定的名字
        // 會消失。`names` 本身由既有的合併流程處理（別名聯集），但「哪個名字對外」是
        // 一個判斷，不能靠聯集救回來：兩邊各指定一個同書寫系統的名字時，聯集會違反
        // 「每個書寫系統至多一個」的不變式，所以必須讓人看見並選一個。
        let lostAuthorized = p.authorized.filter { !keeper.authorized.contains($0) }
        if !lostAuthorized.isEmpty {
            losses.append("authorized: " + lostAuthorized.joined(separator: "、"))
        }

        // profile 同樣是**子集**而非相等。相等只放行「全空」與「完全相同」，於是
        // 「兩個聚合器各給一份隸屬時間軸、其一是另一的子集」這種常見情況被誤拒，
        // 而訊息叫人「搬到倖存者身上」時倖存者已經有了（#71 R3 DA 的 P1）。
        let profileGaps = profileDimensionsNotCovered(p.profile, by: keeper.profile)
        if !profileGaps.isEmpty {
            losses.append("profile 的 " + profileGaps.joined(separator: "、"))
        }

        // #66：provenance references 是**子集**判準（同 authorized）——被併者的每筆
        // reference 若不在倖存者身上就會隨檔案消失，而 provenance 消失比資料消失
        // 更難察覺（資料錯了看得出來，依據沒了要等下次質疑才發現）。不做自動搬移：
        // reference 的 field/value 指向被併者的欄位，搬過去可能指到倖存者沒有的值
        // ——那正是 validateReferenceAttachment 要擋的孤兒。
        let lostRefs = p.references.filter { !keeper.references.contains($0) }
        if !lostRefs.isEmpty {
            losses.append("references（\(lostRefs.count) 筆，欄位："
                + lostRefs.map(\.field).joined(separator: "、") + "）")
        }

        // 未知欄位是**三分**不是二分：key 不在 → 真的會失去；key 在且 raw 相等 → 不會
        // 失去；key 在但 raw 不同 → 那是**衝突**不是「倖存者沒有」。用 `contains($0)`
        // （key + raw 全等）會把純排版差異報成資料遺失，而訊息給的操作無事可做。
        for f in p.unknownFields {
            guard let mineSame = keeper.unknownFields.first(where: { $0.key == f.key }) else {
                losses.append("未知欄位 \(f.key)")
                continue
            }
            if mineSame.raw != f.raw {
                losses.append("未知欄位 \(f.key)（兩邊都有但內容不同，需要選一個）")
            }
        }
        return losses
    }

    /// `p` 的哪些 profile 維度**不是** `keeper` 的子集。空 = 合併不會失去任何時間軸。
    private static func profileDimensionsNotCovered(
        _ p: PersonProfile, by keeper: PersonProfile) -> [String] {
        func covered<V>(_ a: TimelineOf<V>, _ b: TimelineOf<V>) -> Bool {
            a.entries.allSatisfy { b.entries.contains($0) }
        }
        var gaps: [String] = []
        if !covered(p.affiliations, keeper.affiliations) { gaps.append("隸屬") }
        if !covered(p.ranks, keeper.ranks) { gaps.append("職級") }
        if !covered(p.administrative, keeper.administrative) { gaps.append("行政職") }
        if !covered(p.appointments, keeper.appointments) { gaps.append("聘任") }
        if !covered(p.fields, keeper.fields) { gaps.append("研究領域") }
        for (k, tl) in p.contacts.sorted(by: { $0.key < $1.key })
        where !covered(tl, keeper.contacts[k] ?? TimelineOf()) {
            gaps.append("聯絡資訊 \(k)")
        }
        return gaps
    }

    /// 本函式涵蓋的 `Person` 儲存屬性數。`PersonFieldCoverageTests` 拿它與反射比對。
    static let personFieldsCoveredByMergeCheck = 11

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
    /// 本次消歧會刪掉哪些檔案（store 相對路徑）。
    ///
    /// **只含能在此刻確定的那些**：被併實體與本次的歧異記錄。因候選塌縮而一併被刪的
    /// 其他歧異記錄要跑完合併才知道，此處看不到——那是這道檢查已知的覆蓋邊界，不是
    /// 疏漏。塌縮的那些與本記錄同批建立、同樣未 commit 的機率高，所以本記錄過關時
    /// 它們通常也過關；但這是相關性不是保證。
    func doomedRelativePaths(record: Divergence, shape: EntityKind,
                             mergedKeys: [String], snapshot: LibraryLoad) -> [String] {
        var ids: [UUID] = [record.id]
        for key in mergedKeys {
            switch shape {
            case .person:
                if let p = snapshot.people.first(where: { $0.key == key }) { ids.append(p.id) }
            case .work:
                if let e = snapshot.entries.first(where: { $0.citekey == key }) { ids.append(e.id) }
            case .organization, .divergence:
                continue                      // 上游已擋，這裡不猜
            }
        }
        return ids.map { "entities/\($0.uuidString).yaml" }
    }

    /// 這些檔案裡，哪些刪掉之後**無法**從版控取回。回傳 `(路徑, 為什麼)`。
    ///
    /// 判準（#73 方案 A：tracked + clean）——
    /// - **untracked**：從未進 git object，刪掉就沒了。含「entities/ 被 .gitignore 擋」
    ///   這種最隱蔽的情況——它在 `git status --porcelain` 裡連 `??` 都不會出現。
    /// - **有未提交的修改**：git 裡有的是舊版本，當下這個版本刪掉不可回復。
    ///
    /// **git 不可用時一律當成不安全**（fail-closed）。這與舊檢查的方向相反：舊的是
    /// 「找得到 .git 就放行」，於是任何祖先目錄下名為 `.git` 的東西（空目錄、隨手建的
    /// 檔案）都算數。不可逆刪除的預設應該是拒絕。
    static func filesNotSafelyRecoverable(root: URL,
                                          relativePaths: [String]) -> [(path: String, why: String)] {
        var bad: [(String, String)] = []
        for rel in relativePaths {
            // **不存在的檔案跳過。** 它不可能被「不可回復地刪除」——刪除迴圈對它是
            // no-op。更重要的是不搶戲：候選住在 legacy 目錄時 `entities/<uuid>.yaml`
            // 不存在，那是**佈局不一致**，由 `assertAllInEntities` 給出可行動的診斷
            // （「先跑 akashic migrate」）。這道 gate 若先開火，使用者會拿到一句
            // 「未被 git 追蹤」——正確但完全指錯方向。
            guard FileManager.default.fileExists(
                    atPath: root.appendingPathComponent(rel).path) else { continue }
            // tracked？`ls-files --error-unmatch` 對未追蹤的路徑回非零。
            let tracked = git(["ls-files", "--error-unmatch", "--", rel], in: root)
            guard tracked?.status == 0 else {
                bad.append((rel, "未被 git 追蹤（從未 commit，或被 .gitignore 擋掉）"))
                continue
            }
            // clean？`diff --quiet HEAD -- <path>` 有差異時回非零。
            guard let diff = git(["diff", "--quiet", "HEAD", "--", rel], in: root) else {
                bad.append((rel, "無法執行 git，無從確認可回溯性"))
                continue
            }
            if diff.status != 0 {
                bad.append((rel, "有未提交的修改——git 裡的是舊版本，當下這版刪掉不可回復"))
            }
        }
        return bad.map { (path: $0.0, why: $0.1) }
    }

    /// 在 `dir` 跑一次 git。回傳 nil = 根本執行不起來（沒有 git、或 spawn 失敗）。
    ///
    /// 刻意**不**用 shell：參數直接進 `arguments`，路徑含空白或引號都不會被重新解析。
    static func git(_ args: [String], in dir: URL) -> (status: Int32, out: String)? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        p.arguments = ["git", "-C", dir.path] + args
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = Pipe()
        do { try p.run() } catch { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return (p.terminationStatus, String(data: data, encoding: .utf8) ?? "")
    }

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
