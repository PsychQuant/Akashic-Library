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
    /// #159 verify §6：記錄裡有本 binary 不理解的欄位——不可逆操作不在讀不懂的
    /// 記錄上執行。
    case recordHasUnknownFields(id: String, fields: [String])
    /// #168：候選遷移後兩筆記錄會是同一組候選，但內容不同。
    case migrationCollision(details: [String])
    /// #75 對一：記錄的判斷傾向另一個候選——消歧不對已寫下的判斷惰性。
    case contradictsJudgement(prefers: String, survivor: String, statement: String)
    /// #75 對一：`--force` 覆寫判斷但沒給理由——判斷的變更也是判斷。
    case overrideNeedsReason(prefers: String, survivor: String)

    public var errorDescription: String? {
        switch self {
        case let .recordNotFound(id):
            return "找不到 id 為 \(id.uuidString) 的歧異記錄"   // display-safe-exempt: UUID.uuidString 是 hex+dash
        case let .survivorNotACandidate(survivor, candidates):
            return "倖存者「\(displaySafe(survivor, max: 200))」不在候選清單內；"
                 + "實際候選為 \(candidates.map { displaySafe($0, max: 200) }.joined(separator: "、"))"
        case let .candidateMissing(key, shape):
            return "候選「\(displaySafe(key, max: 200))」（\(shape)）在 store 內找不到對應記錄"   // display-safe-exempt: shape 是呼叫端字面量（"person"/"work"）
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
        case let .migrationCollision(details):
            return "拒絕消歧：候選遷移後會有兩筆記錄指向同一組候選，而它們內容不同"
                + "——「同一組候選＝同一筆記錄」是 judgement 與 prefers 三道守衛的"
                + "共同前提，自動挑一邊活下來就是靜默毀損（#168）。\n"
                + details.map { "  • " + $0 }.joined(separator: "\n")
                + "\n先處理其中一筆（合併判斷、或刪掉不要的那筆）再重跑。"
        case let .recordHasUnknownFields(id, fields):
            return "歧異記錄 \(displaySafe(id, max: 80)) 帶有本 binary 不認得的欄位，"
                 + "消歧拒絕執行——這是**不可逆**操作（合併＋改寫參照＋刪檔），"
                 + "而那些欄位可能正是一道本版讀不到的限制："
                 + fields.prefix(5).map { displaySafe($0, max: 120) }.joined(separator: "、")
                 + (fields.count > 5 ? "…" : "")
                 + "。升級 binary；或確認該欄位可忽略後，從記錄檔手動移除再重跑。"
        case let .contradictsJudgement(prefers, survivor, statement):
            return "這筆歧異已有判斷、且傾向「\(displaySafe(prefers, max: 200))」，"
                 + "但你選了「\(displaySafe(survivor, max: 200))」作為倖存者——"
                 + "判斷內容：\(displaySafe(statement, max: 300))。"
                 + "若判斷本身錯了，用 --override-reason 說明為什麼"
                 + "（判斷的變更也是判斷，不能無聲蓋過）。"
        case let .overrideNeedsReason(prefers, survivor):
            return "覆寫判斷（傾向「\(displaySafe(prefers, max: 200))」、"
                 + "你選「\(displaySafe(survivor, max: 200))」）需要 --override-reason："
                 + "為什麼原判斷不成立。"
        case let .unsupportedShape(shape):
            return "本版的消歧只處理 person 與 work，不處理 \(shape)"   // display-safe-exempt: shape 是 EntityKind.rawValue（enum）
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
            let listed = files.prefix(3).map { displaySafe($0, max: 200) }
                .joined(separator: "、") + (files.count > 3 ? "…" : "")
            var msg = "store 有 \(files.count) 個讀不進來的檔，消歧拒絕執行——"
            msg += "它們可能正指著要被刪掉的實體，而讀不到就改寫不到，刪除後會留下"
            msg += "藏在工具看不見處的永久懸空參照：\(listed)"
            msg += "。跑 akashic doctor 看每個檔的原因，然後手動修好或移出 store 再試"
            msg += "（doctor 只診斷、不修）。若這些是未遷移的舊形狀 person 檔"
            msg += "（#227/#241 之後每個未遷移 store 的常態），先跑 "
            msg += "akashic migrate-person-identity。"
            return msg
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
    /// **使用者沒有指名**卻被連帶刪除的塌縮記錄（#78-2）：只印裸 UUID 使用者無從
    /// 知道被刪掉的是哪個問題——id + question 成對攜帶，CLI 據以呈現。
    public var collapsedDetails: [(id: String, question: String)]
    /// 單筆寫入失敗的訊息。非空即代表結束時該以非零碼退出。
    public var failures: [String]
    /// #271：person merge 時自動遷移到倖存者的 verdict（pairing value 清單）。
    public var verdictReferencesMigrated: [String] = []
    /// #271：holder 退役（work merge 的 citekey、#463 起 person merge 的 person key）時 value 被改寫的
    /// **持有記錄 key（person／venue／organization——#460 起 venue、#463 起 organization）**清單
    /// （鏡射 rename 的 `verdictValuesRewritten`）。
    public var verdictValuesRewritten: [String] = []
    /// #461：merge 收攏（work merge，#463 起也含 person merge）時被**丟棄**的 verdict 列（「持有記錄：field value——丟棄
    /// 判定「…」」）。丟棄不靜默（`lossless-intake` 執行細節 3）。與
    /// `verdictValuesRewritten` 同樣不進 `==`——preview 側目前不算 verdict 面
    /// （#271／#460 起的既有缺口，#461 verify follow-up 追蹤）。
    public var verdictsCollapsed: [String] = []
    /// **不擋、但要說**的提醒（#75 對一）：有判斷卻沒有結構化的 `prefers` 時，
    /// 消歧無從機械比對——提醒人自行核對，而不是靜默當作沒有判斷。
    public var warnings: [String]
    /// #169 verify F3：work 側算出的內容提醒，**暫存**到 `resolveDivergence` 於
    /// `judgementWarnings` 之後接上——preview 的順序是「judgement 先、content 後」，
    /// 在 work 函式內直接 append 會得到相反的順序，而 `==` 對 `warnings` 是順序
    /// 敏感的陣列比較。回傳前一律清空，所以它不出現在任何對外的比較裡。
    var pendingContentWarnings: [String] = []
    /// 倖存者是否已被改寫（別名合併已落地）。**失敗路徑也可能為 true**——它是
    /// 既成事實而非成功訊號；不說出來，`merged` 為空會讀成「什麼都沒發生」。
    public var survivorUpdated: Bool

    public var hasFailures: Bool { !failures.isEmpty }

    public init(rewritten: [String] = [], merged: [String] = [],
                removedDivergences: [String] = [], failures: [String] = [],
                warnings: [String] = [],
                collapsedDetails: [(id: String, question: String)] = [],
                survivorUpdated: Bool = false) {
        self.warnings = warnings
        self.rewritten = rewritten
        self.merged = merged
        self.removedDivergences = removedDivergences
        self.failures = failures
        self.collapsedDetails = collapsedDetails
        self.survivorUpdated = survivorUpdated
    }

    public static func == (a: ResolveReport, b: ResolveReport) -> Bool {
        a.rewritten == b.rewritten && a.merged == b.merged
            && a.removedDivergences == b.removedDivergences && a.failures == b.failures
            && a.warnings == b.warnings
            && a.collapsedDetails.map { "\($0.id)|\($0.question)" }   // display-safe-exempt: Equatable 的比較鍵，不進任何輸出面
                == b.collapsedDetails.map { "\($0.id)|\($0.question)" }   // display-safe-exempt: Equatable 的比較鍵，不進任何輸出面
            && a.survivorUpdated == b.survivorUpdated
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
        // **divergence 的 format gate**（#74，歸屬回填 5——使用者拍板 2026-08-07）：
        // 形狀標籤是 strict（#131 判準），format ≤ 4 世代的 binary 讀到 `divergence:`
        // 即整檔 quarantine——在 format < 5 的 store 寫入等於替舊 binary 埋地雷。
        // 拒絕而非自動 bump：升 marker 會讓其餘 binary（MCP/App）整庫拒開，
        // 必須是使用者知情的動作（同 writePerson 的 ended gate，#131 Codex-H2）。
        let format = try StoreVersion.read(root: root)
        guard format >= 5 else {
            throw StoreIOError.invalidInput(
                what: "divergence 記錄（需要 store format ≥ 5；本 store 是 \(format)）",
                why: "divergence 形狀標籤對 format \(format) 世代的 binary 是整檔 "
                    + "quarantine。確認會碰這個 store 的 CLI/MCP/App 都已升級後，"
                    + "把 store.yaml 的 format: 改成 5（或更高）再寫入")
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
    /// - Parameter prefers: 判斷傾向的候選（#75 對一，選填）——消歧會據以比對，
    ///   但**不代選**（survivor 仍須人工輸入）。
    public func recordDivergence(question: String,
                                 candidates: [(key: String, shape: EntityKind)],
                                 judgement: String?,
                                 restsOn: [String],
                                 prefers: String? = nil) throws -> Divergence {
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
                // #149 R2：invalidInput 的 errorDescription 已消毒 why（sink 策略）——
                // 此處預先消毒是雙重 escape（反斜線被跳脫兩次）。傳原字串。
                why: "這組候選已有判斷（\(existing.judgement!.statement)）——" +
                     "無判斷的重呼叫不得靜默抹掉它。要更新判斷請帶新的 judgement + rests-on；" +
                     "要撤銷判斷請直接編輯該檔（entities/\(id.uuidString).yaml）")
        }
        // #159 verify 159-4（**與上面那道守衛對稱**——同一個 bug class 在新欄位上
        // 重演）：既有記錄已指定 `prefers`，重錄時省略它會**靜默抹掉**它。而 prefers
        // 正是本 change 唯一能機械執法的東西——抹掉它，`resolve-divergence` 就退回
        // 「只警告不擋」，整個 #75 對一被一個省略的選填參數關掉。實測（席位 P5 +
        // MCP e2e 雙路）：re-record 帶新 judgement、省略 prefers → 欄位消失 → 接著
        // 選原判斷反對的那一邊 **成功**，只留一句 warning。
        //
        // 在 #133 的前提下（判斷由 LLM 經 MCP 寫入），「更新 judgement 時忘了帶
        // prefers」是很順的一條路徑，不是邊角。
        if let existing = load.divergences.first(where: { $0.id == id }),
           let existingPrefers = existing.judgement?.prefers,
           judgement != nil, prefers == nil {
            throw StoreIOError.invalidInput(
                what: "divergence（同組候選既有記錄）",
                // 同上：invalidInput 的 errorDescription 已消毒 why，此處傳原字串
                why: "這組候選已指定傾向「\(existingPrefers)」——" +
                     "重錄時省略 prefers 不得靜默抹掉它。要沿用請再帶一次相同的 prefers；" +
                     "要改傾向請帶新的值；要撤銷請直接編輯該檔（entities/\(id.uuidString).yaml）")
        }
        if let p = prefers, !candidates.contains(where: { $0.key == p }) {
            throw StoreIOError.invalidInput(
                what: "divergence prefers",
                why: "「\(p)」不是本次的候選之一——判斷傾向的對象必須在候選清單內")
        }
        if prefers != nil && judgement == nil {
            throw StoreIOError.invalidInput(
                what: "divergence prefers",
                why: "prefers 需與 judgement 成對——沒有判斷的傾向不知道依據什麼")
        }
        let d = Divergence(
            id: id,
            question: question,
            candidates: candidates.map { DivergenceCandidate(key: $0.key, shape: $0.shape) },
            judgement: judgement.map {
                Judgement(statement: $0, restsOn: restsOn, prefers: prefers)
            })
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
    /// - Parameter overrideReason: `prefers` 與 `survivor` 不一致時的覆寫理由
    ///   （#75 對一）。非 nil ＝ 使用者主張原判斷錯了；**空字串不接受**——判斷的
    ///   變更也是判斷，不能無聲蓋過。
    public func resolveDivergence(id: UUID, survivor: String,
                                  overrideReason: String? = nil) throws -> ResolveReport {
        let (record, shape, mergedKeys, snapshot, migration) =
            try validateResolvePreconditions(id: id, survivor: survivor,
                                             overrideReason: overrideReason)
        var report: ResolveReport
        switch shape {
        case .person:
            report = try resolvePersonDivergence(record: record, survivor: survivor,
                                                 mergedKeys: mergedKeys, snapshot: snapshot)
        case .work:
            report = try resolveWorkDivergence(record: record, survivor: survivor,
                                               mergedKeys: mergedKeys, snapshot: snapshot)
        case .organization, .divergence, .venue:
            throw DivergenceResolveError.unsupportedShape(shape.rawValue)
        }
        report.warnings += Self.judgementWarnings(
            record: record, survivor: survivor, overrideReason: overrideReason,
            collapsed: migration.collapsed)
        // #169 verify F3：content warnings 排在 judgement **之後**——與 preview 同序。
        report.warnings += report.pendingContentWarnings
        report.pendingContentWarnings = []
        return report
    }

    /// 判斷相關的**不擋提醒**（#75 對一）：有判斷卻無 `prefers` 時無從機械比對——
    /// 說出來，而不是靜默當作沒有判斷。覆寫時記下理由（審計軌跡留在 CLI 輸出與
    /// 版控的 commit message；記錄本身隨消歧刪除，這是 #71 的設計）。
    ///
    /// **也掃被連帶刪除的記錄**（#159 verify R4-1）：`collapsed` 那些記錄同樣被這個
    /// 操作刪掉，而它們可能帶著與所選 survivor 相反的判斷。席位實測一條全部由正常
    /// 操作組成的鏈：消歧不只沒被判斷擋下，還把**寫著那個判斷的記錄一起刪掉**，
    /// 然後把判斷指名為正確的那個候選合併掉，dry-run 與實跑都 exit=0、一個字都沒提。
    ///
    /// **只警告不拒絕**：那筆記錄不是使用者指名的操作對象，硬擋會讓一個沒人指名的
    /// 記錄癱瘓別人的消歧（同 quarantine blast radius 的顧慮）。
    static func judgementWarnings(record: Divergence, survivor: String,
                                  overrideReason: String?,
                                  // **不給預設值**（#173）：那正是 159-1 為
                                  // `overrideReason` 拿掉的形狀，理由寫在同一個檔案
                                  // 裡——省略一個選填參數就靜默關掉一整條警告，而
                                  // 呼叫端不會有任何訊號。#157×#159 merge 時，拿掉
                                  // 預設值讓編譯器抓出一個兩個 PR 各自開發時誰都不
                                  // 知道的呼叫點；那是它第一次兌現。
                                  collapsed: [Divergence]) -> [String] {
        var out: [String] = []
        for c in collapsed {
            guard let cj = c.judgement else { continue }
            let prefersNote = cj.prefers.map { "（傾向「\(displaySafe($0, max: 200))」）" } ?? ""
            out.append("將**連帶刪除**的歧異記錄 \(c.id.uuidString) 帶有判斷"
                       + "\(prefersNote)：\(displaySafe(cj.statement, max: 300))"
                       + "——它不是你指名的對象，但會隨這次消歧一起消失，請確認不衝突")
        }
        guard let j = record.judgement else { return out }
        if j.prefers == nil {
            out.append("這筆歧異有判斷但未指定 prefers，無法機械核對——"
                       + "請自行確認倖存者與判斷一致：\(displaySafe(j.statement, max: 300))")
        }
        if let r = overrideReason, let p = j.prefers, p != survivor {
            out.append("已覆寫判斷（原傾向「\(displaySafe(p, max: 200))」→ 實選"
                       + "「\(displaySafe(survivor, max: 200))」）：\(displaySafe(r, max: 300))")
        }
        return out
    }

    /// `resolveDivergence` 與 `previewResolveDivergence` 共用的拒絕條件（#78-2）。
    /// **兩邊必須擲一樣的錯**——dry-run 的價值是誠實預告，preview 放行而實跑被擋
    /// （或反過來）都是在騙人，所以驗證只能有這一份。
    ///
    /// **`overrideReason` 刻意沒有預設值**（#159 verify 159-1）：共用一份驗證還是分岔
    /// 了，因為 `previewResolveDivergence` 沒收這個參數、於是**靜默吃到 `nil` 預設**
    /// ——preview 擲 `contradictsJudgement`、實跑帶 reason 成功，dry-run 比實跑還嚴。
    /// 「共用同一個函式」擋不住這種分岔，「參數沒有預設值」才擋得住：少傳就編不過。
    private func validateResolvePreconditions(id: UUID, survivor: String,
                                              overrideReason: String?)
        throws -> (record: Divergence, shape: EntityKind,
                   mergedKeys: [String], snapshot: LibraryLoad,
                   migration: DivergenceMigration) {
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
        guard let record = snapshot.divergences.first(where: { $0.id == id }) else {
            throw DivergenceResolveError.recordNotFound(id)
        }
        let candidateKeys = record.candidates.map(\.key)
        guard candidateKeys.contains(survivor) else {
            throw DivergenceResolveError.survivorNotACandidate(
                survivor: survivor, candidates: candidateKeys.sorted())
        }
        // #75 對一：消歧不對已寫下的判斷惰性——`prefers` 與 survivor 不一致即拒絕。
        // **不代選**：不會照 prefers 自動執行（#133 起判斷可由 LLM 經 MCP 寫入，
        // 自動採信＝把「當場判斷」換成「延遲自動判斷」，繞過人工確認底線）。
        // 判斷本身可能錯——`overrideReason` 是知情的覆寫通道，但要求說出理由。
        if let j = record.judgement, let prefers = j.prefers, prefers != survivor {
            if let reason = overrideReason {
                guard !reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    throw DivergenceResolveError.overrideNeedsReason(
                        prefers: prefers, survivor: survivor)
                }
            } else {
                throw DivergenceResolveError.contradictsJudgement(
                    prefers: prefers, survivor: survivor, statement: j.statement)
            }
        }
        guard let shape = record.shape else {
            throw DivergenceResolveError.recordNotFound(id)
        }
        // 版控前提在**任何寫入之前**驗（design D4 + tasks 4.2）。
        guard Self.isInsideVersionedWorkTree(root) else {
            throw DivergenceResolveError.outsideVersionControl(root: root.path)
        }
        let mergedKeys = candidateKeys.filter { $0 != survivor }

        // **讀不到的檔可能正指著要被刪掉的東西。** spec 要求改寫「store 內每一個」
        // 指名被併實體的參照，而 quarantined 檔根本沒進 `snapshot.entries`——它的
        // 參照永遠不會被改寫，卻擋不住刪除，留下一筆藏在工具讀不到的檔案裡、
        // `crossRecordIssues()` 也掃不到的永久懸空參照。這與本檔對 legacy 佈局採取的
        // 立場（拒絕比部分支援誠實）是同一條理由，不該一邊拒絕一邊靜默放行。
        //
        // ## 為什麼判準是「位元組含不含被刪的 key」而不是目錄前綴（#295）
        //
        // 舊版按目錄前綴過濾（擋 `entities/`／`entries/`，放行 `people/`／
        // `libraries/`），註解說後兩者「結構上不可能指向被併實體」。**那個理由是為
        // legacy 佈局寫的**——佈局遷移（#227／#241）把 person 檔搬進 `entities/` 之後，
        // 目錄名與該性質的對應就斷了：person 檔正住在明確被擋的前綴下，而放行清單
        // 指向的兩個目錄在新佈局幾乎是空的。**保護範圍實質反轉**，gate 從罕見邊角
        // 變成常態摩擦（#71 R2 DA 已註記過寬，#227 cluster verify DA NEW-1 實測重現）。
        //
        // 收窄後的判準直接對應 gate 自己的理由。**封閉定義**：
        //
        // > 本次消歧的引用集合 ＝ 所有 quarantined 檔中，**原始位元組含有任一
        // > `mergedKeys` 之字面**的那些。
        //
        // 依據：對 key K 的參照必然把 K 的字面序列化進檔案某處（`StoreKey.pattern`
        // 是 `[a-z0-9][a-z0-9-]*`，純 ASCII，本專案的 encoder 從不對它逃脫）。
        // 位元組裡沒有 K，就不可能有指向 K 的參照。
        //
        // 方向是 fail-closed 的那一側：字面比對會有**偽陽性**（K 出現在 note 裡也算，
        // 於是多擋一筆），但**不可能偽陰性**——不會放行一個真的持有懸空參照的檔。
        //
        // **已知且接受的限制**：YAML 允許雙引號字串用 `\x` / `\u` 逃脫，所以手工
        // 構造的檔可以寫成 `"\x63he-cheng"` 而躲過字面比對。不加「見到反斜線就擋」
        // 的保守規則，因為那會把大量含 LaTeX 標題／路徑的合法檔重新擋回來——正是
        // 本次要修的過寬。對單人本機 store 而言，能手工構造逃脫序列的人也能直接
        // 改 survivor，這道 gate 本來就不是對抗惡意的防線。
        let doomedKeyBytes = mergedKeys.map { Array($0.utf8) }
        let blocking = snapshot.quarantined.filter { q in
            guard let data = try? Data(contentsOf: root.appendingPathComponent(q.file))
            else {
                // 連讀都讀不到（權限／競態）——**擋**。判不準時選比較嚴的那邊。
                return true
            }
            let bytes = Array(data)
            return doomedKeyBytes.contains { needle in
                bytes.indices.contains { i in
                    i + needle.count <= bytes.count
                        && Array(bytes[i..<(i + needle.count)]) == needle
                }
            }
        }
        guard blocking.isEmpty else {
            throw DivergenceResolveError.quarantinedPresent(files: blocking.map(\.file).sorted())
        }

        // #159 verify §6 + 159-12：**不可逆操作不在自己讀不懂的記錄上執行。**
        //
        // 這是 verify 席在駁回「為 `prefers` bump format」時提出的替代方案，比 bump
        // 好三點：(1) 版本無關——是本 binary 對自己無知的紀律，不需 store 級協商；
        // (2) 一次保護**所有**未來欄位；(3) 代價侷限在該筆記錄，不像 bump 是整庫拒開。
        //
        // 觸發它的實驗：塞一個叫 `future-veto` 的未知欄位，新 binary 的 `validate`
        // **會印出**「未知欄位（已保留）」——它知道自己讀不懂——然後照樣把記錄連同
        // 那個欄位一起刪掉。與上游「quarantined 檔讀不到就改寫不到」是同一條理由的
        // 另一面：**讀不懂**與**讀不到**在不可逆操作前該同樣保守。
        //
        // **涵蓋三類記錄，封閉列舉**（159-12——第一版只守目標那一筆，而席位實測
        // 另外兩類同樣被這個操作親手摧毀／改寫）：
        //
        //   1. **目標**——使用者指名的那筆，刪除
        //   2. **塌縮連帶刪除**（`collapsed`）——候選遷移後與目標重複，一併刪除。
        //      席位實測：帶 `future-veto` 的 D2 被連同欄位一起刪掉、exit=0
        //   3. **候選遷移改寫**（`toWrite`）——read-modify-write。席位實測產出
        //      **自相矛盾**的檔案：候選被改寫成 `fann-b`，而未知欄位
        //      `future-candidate-meta: fann-a-is-primary` 原樣保留、仍指著全庫已無的
        //      `fann-a`。tolerant-preserve 保證位元組不變，但候選被改寫時「不變」
        //      剛好就是錯的。這正是 §5.0 用來定義 non-additive 的那個危險樣式，
        //      由**新** binary 重演一次。
        //
        // **不得依性質相似類推第四類**：這三類是「本次操作會刪除或改寫的全部
        // divergence 記錄」的完整枚舉，由 `migrateOtherDivergences` 的回傳值界定。
        //
        // 位置在共用驗證段（而非兩個呼叫端各補一次）——分兩邊補會複製 159-1 的病。
        let affectedMigration = migrateOtherDivergences(
            record: record, survivor: survivor, mergedKeys: mergedKeys, snapshot: snapshot)
        for d in [record] + affectedMigration.collapsed + affectedMigration.toWrite
        where !d.unknownFields.isEmpty {
            throw DivergenceResolveError.recordHasUnknownFields(
                id: d.id.uuidString, fields: d.unknownFields.map(\.key).sorted())
        }
        // #168：id 重算後的碰撞。**位置在這裡而非 `commitResolution`**——它是
        // 「所有拒絕條件都在動磁碟之前」的一員，而且 dry-run 必須看得到它
        // （這條共用驗證段正是 preview 與實跑的共同入口）。
        guard affectedMigration.collisions.isEmpty else {
            throw DivergenceResolveError.migrationCollision(
                details: affectedMigration.collisions)
        }

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
        // **把已經算好的那份交出去**（#173）。`migrateOtherDivergences` 先前在這條
        // 路徑上被呼叫**三次**：這裡（unknown-field gate）、`judgementWarnings` 的
        // 呼叫點、`commitResolution`。
        //
        // 第 1 與第 3 值得保留——「gate 的輸入與實際執行的輸入各自獨立算出、結果
        // 必須相同」是一個隱含自檢。**第 2 沒有增加任何檢查**：它是同一份四參數
        // 呼叫**逐字抄在 preview 與實跑各一處**，而那正是 159-1 的形狀（兩邊各自
        // 準備輸入、各自可能改壞）。今天沒事靠
        // `testPreviewCarriesJudgementWarnings` 的 `XCTAssertEqual`——**那是測試在
        // 補結構的洞**。
        return (record, shape, mergedKeys, snapshot, affectedMigration)
    }

    /// dry-run（#78-2）：跑與 `resolveDivergence` **相同的**拒絕條件、算出會發生什麼，
    /// 不動任何檔案。使用者要能在消歧前看到「候選塌縮的連帶刪除」——那些記錄他沒有
    /// 指名，事後才看到只剩裸 UUID 已經來不及了。
    ///
    /// 回傳值是**預測**：`merged`／`rewritten`／`collapsedDetails` 填入將發生的事；
    /// `removedDivergences`／`survivorUpdated` 留空——那兩個欄位回報的是既成事實，
    /// preview 沒有事實可報。命中判準與 `resolvePersonDivergence`／
    /// `resolveWorkDivergence` 的改寫迴圈一致（命中被併鍵 ⇒ 必有改寫），塌縮判準
    /// 直接共用 `migrateOtherDivergences`——一致性由 `DivergenceResolveTests` 的
    /// preview-vs-actual 測試釘住。
    ///
    /// **`overrideReason` 必須傳**（#159 verify 159-1）：不收這個參數的舊簽章讓
    /// preview 靜默吃到 `nil`，於是 `--dry-run --override-reason …` 被拒、拿掉
    /// `--dry-run` 卻成功——**dry-run 比實跑還嚴**，而且方向是壞的那個：先跑
    /// dry-run 的謹慎使用者被告知這件事做不到，唯一能知道它會做什麼的方法是真的
    /// 做下去，在一個會刪檔的操作上。`judgementWarnings` 同理併入報告——「有判斷
    /// 但無 prefers、無從機械核對」正是人最需要在按下去之前看到的那一條。
    public func previewResolveDivergence(id: UUID, survivor: String,
                                         overrideReason: String?) throws -> ResolveReport {
        let (record, shape, mergedKeys, snapshot, migration) =
            try validateResolvePreconditions(id: id, survivor: survivor,
                                             overrideReason: overrideReason)
        let merged = Set(mergedKeys)
        var report = ResolveReport()
        report.warnings += Self.judgementWarnings(
            record: record, survivor: survivor, overrideReason: overrideReason,
            collapsed: migration.collapsed)
        report.merged = mergedKeys.sorted()
        switch shape {
        case .person:
            // shape 專屬拒絕與實跑共用（#139 verify F1）：wouldLoseFields／
            // candidateMissing／assertAllInEntities 在 preview 也要擲——dry-run
            // 對最高頻的 wouldLoseFields 沉默，就是在最需要預告的場景上失效
            _ = try validatePersonPreconditions(
                survivor: survivor, mergedKeys: mergedKeys, snapshot: snapshot)
            for e in snapshot.entries where e.authors.contains(where: {
                if case let .key(k) = $0 { return merged.contains(k) }
                return false
            }) { report.rewritten.append(e.citekey) }
        case .work:
            report.warnings += try validateWorkPreconditions(
                survivor: survivor, mergedKeys: mergedKeys, snapshot: snapshot).warnings
            // 與實跑同：keeper 與被併記錄不進 rewritten（keeper 走獨立寫回、
            // doomed 走刪除）。
            let doomedIDs = Set(snapshot.entries
                .filter { merged.contains($0.citekey) }.map(\.id))
            for e in snapshot.entries
            where e.citekey != survivor && !doomedIDs.contains(e.id) {
                guard e.akashic.relations.cites.contains(where: { merged.contains($0) })
                    || e.akashic.relations.related.contains(where: { merged.contains($0) })
                else { continue }
                report.rewritten.append(e.citekey)
            }
        case .organization, .divergence, .venue:
            throw DivergenceResolveError.unsupportedShape(shape.rawValue)
        }
        // #173：preview 裡的**第四次**呼叫，同樣改用共用點的回傳值。
        report.rewritten.append(contentsOf: migration.toWrite.map { $0.id.uuidString })
        report.collapsedDetails = migration.collapsed
            .map { (id: $0.id.uuidString, question: $0.question) }
        report.rewritten.sort()
        return report
    }

    // MARK: - person

    /// person 側的 shape 專屬拒絕條件（#139 verify F1）：keeper／doomed 查找、
    /// `assertAllInEntities`、`fieldsLostByMerging`——**preview 與實跑共用這一份**。
    /// 曾經只在實跑路徑內：dry-run 對最高頻的 `wouldLoseFields`（兩筆各帶一半
    /// 識別碼）完全沉默，「跑同樣的拒絕條件」的宣稱是假的。
    func validatePersonPreconditions(survivor: String, mergedKeys: [String],
                                     snapshot: LibraryLoad) throws
        -> (keeper: Person, doomed: [Person]) {
        guard let keeper = snapshot.people.first(where: { $0.key == survivor }) else {
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
        return (keeper, doomed)
    }

    /// work 側的 shape 專屬拒絕條件（#139 verify F1，與 person 側對稱）。
    /// work 側的欄位遺失比對就在下方 body（#75 對二已落地）——與 person 側對稱。
    /// **warnings 也從這裡回傳**（#169）：preview 與實跑都經過本函式，把提醒接在
    /// 這個共用點上，兩邊自然一致——不必在兩個呼叫端各算一次（那是 159-1 的形狀：
    /// 兩邊各自準備輸入、各自可能改壞）。
    func validateWorkPreconditions(survivor: String, mergedKeys: [String],
                                   snapshot: LibraryLoad) throws
        -> (keeper: Entry, doomed: [Entry], warnings: [String]) {
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
        // #75 對二：欄位遺失比對放在**前置**（preview 與實跑共用——#139 F1 的教訓：
        // 拒絕條件只有一份，dry-run 對它沉默是在騙人）。被併 work 帶有倖存者沒有的
        // 欄位／附件／標籤／出向參照／來源 → 拒絕並指名（子集才放行）。
        for e in doomed {
            let losses = Self.fieldsLostByMerging(e, into: keeper)
            guard losses.isEmpty else {
                throw DivergenceResolveError.wouldLoseFields(
                    merged: e.citekey, survivor: survivor, losses: losses)
            }
        }
        // #169：**不擋但要說**——`type`／`title` 刻意不比相等（見
        // `contentWarningsForMerging` 的 doc），但倖存者的版本較短時要在**還能反悔
        // 的時點**說出來。
        let warnings = doomed.flatMap { Self.contentWarningsForMerging($0, into: keeper) }
        return (keeper, doomed, warnings)
    }

    private func resolvePersonDivergence(record: Divergence, survivor: String,
                                         mergedKeys: [String],
                                         snapshot: LibraryLoad) throws -> ResolveReport {
        var (keeper, doomed) = try validatePersonPreconditions(
            survivor: survivor, mergedKeys: mergedKeys, snapshot: snapshot)
        // 別名併入倖存者：被併者的寫法保留，否則下次遇到那個寫法又會重新分割一次。
        // #227：併入的一律進 **variant**——被併者的 authorized 指定不能靠聯集救回來
        // （兩邊各指定同書寫系統時聯集會違反「每書寫系統至多一個」）。防護在**前置**：
        // `validatePersonPreconditions` 的 `fieldsLostByMerging` 對「被併者有、倖存者
        // 沒有的 authorized」直接拒絕合併（`wouldLoseFields`）——走到這行時被併者的
        // 指定已確認是倖存者 authorized 的子集，折進 variant 不失去任何指定。
        // （verify R1 曾抓到本註解點名不存在的 contentWarnings——那是 work 路徑的
        // 機制名，person 的防護是上面那道拒絕，不是警告。）
        // #296：判定用 `NameIdentity`，不用精確 `String ==`——去重是**判定**
        // （斷言同一並丟棄），而 `"Li  Ming"` 與 `"Li Ming"` 只差重複空白。
        let keeperKeys = Set(keeper.names.all.map(NameIdentity.canonical))
        let incoming = doomed.flatMap { $0.names.all }
            .filter { !keeperKeys.contains(NameIdentity.canonical($0)) }
        keeper.names.variant = dedupePreservingOrder(keeper.names.variant + incoming)

        // #271：被併者的 verdict references 自動遷移——判定史不隨檔案消失。
        // (field, value) 冪等（寫入邊界的鏡射：store 永不持有重複 verdict）。
        var verdictsMigrated: [String] = []
        for d in doomed {
            for r in d.references
            where ProvenanceReference.resolutionVerdictFields.contains(r.field) {
                guard !keeper.references.contains(where: {
                    $0.field == r.field && $0.value == r.value }) else { continue }
                keeper.references.append(r)
                verdictsMigrated.append(r.value ?? "")
            }
        }

        let merged = Set(mergedKeys)
        // #463：keeper **自己**持有的 `person:<被併鍵>` holder（含剛由 #271 從 doomed 搬來的）在 **commit 之前**
        // 就改寫——commit 之後拿 pre-commit 快照寫 keeper，會把合併別名與搬來的 references 整個蓋掉
        // （Codex R1）。survivor 因此**不進**下方 post-commit 的 snapshot 迴圈。
        let keeperMigration = Self.migrateHolderVerdicts(
            keeper.references, merged: merged, survivor: survivor, holderKind: .person)
        if keeperMigration.changed { keeper.references = keeperMigration.refs }
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
        var report = try commitResolution(record: record,
                                    keeperWrite: { try self.writePerson(keeperFinal) },
                                    keeperEncode: { _ = try PersonYAML.encode(keeperFinal) },
                                    entriesToWrite: entriesToWrite,
                                    doomedIDs: doomed.map(\.id), mergedKeys: mergedKeys,
                                    snapshot: snapshot, survivor: survivor,
                                    survivorNote: "倖存者的別名合併已經落地（磁碟上不是原狀）")
        // 同 resolveWorkDivergence：commit 早退或失敗時，下方的 holder 遷移不得再寫檔（verify logic L2）。
        guard report.failures.isEmpty else { return report }
        // #271 的清單記的是搬移**當下**的值；keeper 上的 `person:<被併鍵>` 已在 commit 前改寫（見上），
        // 揭露值要跟著改，否則 CLI 印出一個 store 裡不存在的 value（verify requirements #5）。
        report.verdictReferencesMigrated = verdictsMigrated.map { v in
            guard let p = ProvenanceReference.VerdictPairingValue.parse(v),
                  p.holderKind == .person, merged.contains(p.holder) else { return v }
            return ProvenanceReference.VerdictPairingValue(holderKind: .person, holder: survivor, literal: p.literal).encoded
        }
        if keeperMigration.changed {
            report.verdictValuesRewritten.append(survivor)
            report.verdictsCollapsed.append(   // display-safe-exempt: report 是資料面；CLI 印出時逐列過 displaySafe（DivergenceCommands）
                contentsOf: keeperMigration.collapsed.map { "person「\(survivor)」：\($0)" })   // display-safe-exempt: 同上
        }
        // #463（網格的 person-merge 兩格）：person key 退役＝改名的一種——organization（與 person）記錄上
        // `person:<被併鍵>` holder 的 verdict 不遷移就安靜變 stale。#395 已補 rename 側，merge 側在此之前
        // **零 holder 遷移**（上面 #271 搬的是 doomed 自己的 references，不是指向 doomed 的 holder）。
        // 機制鏡射 resolveWorkDivergence 的三個迴圈，holderKind 換成 `.person`。
        for var org in snapshot.organizations {
            let (migrated, changed, collapsed) = Self.migrateHolderVerdicts(
                org.references, merged: merged, survivor: survivor, holderKind: .person)
            guard changed else { continue }
            org.references = migrated
            do {
                _ = try writeOrganization(org)
                report.verdictValuesRewritten.append(org.key)
                report.verdictsCollapsed.append(   // display-safe-exempt: report 是資料面；CLI 印出時逐列過 displaySafe(c, max: 300)（DivergenceCommands），與 failures 同一條消毒點
                    contentsOf: collapsed.map { "organization「\(org.key)」：\($0)" })   // display-safe-exempt: 同上
            } catch {
                report.failures.append(
                    "organization「\(org.key)」的 verdict value 遷移寫入失敗：\(error)")
            }
        }
        // venue 同型（#463 verify security 席）：`person:` holder 的 producer 今天只寫 organization，但寫入閘收任何
        // holderKind——與 person 迴圈同一個理由，同型兩格不該處置相反。
        for var venue in snapshot.venues {
            let (migrated, changed, collapsed) = Self.migrateHolderVerdicts(
                venue.references, merged: merged, survivor: survivor, holderKind: .person)
            guard changed else { continue }
            venue.references = migrated
            do {
                _ = try writeVenue(venue)
                report.verdictValuesRewritten.append(venue.key)
                report.verdictsCollapsed.append(   // display-safe-exempt: 同上
                    contentsOf: collapsed.map { "venue「\(venue.key)」：\($0)" })   // display-safe-exempt: 同上
            } catch {
                report.failures.append(
                    "venue「\(venue.key)」的 verdict value 遷移寫入失敗：\(error)")
            }
        }
        // 排除 merged（已刪檔，寫回等於復活）**與 survivor**（commit 已改寫它，快照是舊的——它的遷移在上面 commit 前做）
        for var person in snapshot.people where !merged.contains(person.key) && person.key != survivor {
            let (migrated, changed, collapsed) = Self.migrateHolderVerdicts(
                person.references, merged: merged, survivor: survivor, holderKind: .person)
            guard changed else { continue }
            person.references = migrated
            do {
                try writePerson(person)
                report.verdictValuesRewritten.append(person.key)
                report.verdictsCollapsed.append(   // display-safe-exempt: 同上
                    contentsOf: collapsed.map { "person「\(person.key)」：\($0)" })   // display-safe-exempt: 同上
            } catch {
                report.failures.append(
                    "person「\(person.key)」的 verdict value 遷移寫入失敗：\(error)")
            }
        }
        return report
    }

    // MARK: - work

    /// merge 側 `work:` holder verdict 的遷移＋收攏（#461——順序無關的二階段）。
    ///
    /// Pass 1 先全部遷移並記下**本次觸及**的 (field, value)；Pass 2 只對被觸及的
    /// 鍵保首見收攏。survivor 原版與遷移版同 (field, value) 時**不論排列**都收成
    /// 一筆——#460 verify 實證舊形（guard-else 無條件 append）在 doomed-first 排列
    /// 寫出兩筆 byte-identical。
    ///
    /// **收攏的邊界是「鍵」不是「來歷」**（#461 verify R1，六席收斂）：(field, value)
    /// **不等於任一遷移輸出**的既有重複一筆不動——bystander 的重複、不同 literal 的
    /// 重複都在觸及集合外，這是「消歧不是清理工具」（#71）守住的那條線
    /// （`testUnrelatedExistingDuplicatesAreUntouched`）。但**落在觸及鍵上**的既有
    /// 重複（keeper 自己已有兩筆同 value、doomed 遷移後撞上）會一併收攏成一筆——
    /// 這是刻意的：#271 起 `resolvePersonDivergence` 的遷移就以同樣方式折疊 doomed
    /// 自己的重複，遷移相鄰的收攏在本 repo 有先例；且這種輸入在正常寫入面
    /// （`appendIfAbsent`）產生不了，唯一的自然來源正是本函式修掉的那個 bug
    /// （`testTouchedKeyCollapsesKeeperPreexistingDuplicatesDeliberately` 釘住）。
    ///
    /// **丟棄不靜默**（`lossless-intake` 執行細節 3）：被收攏掉的每一列以 `collapsed`
    /// 回報（value ＋ 被丟的判定原文），呼叫端寫進 `ResolveReport.verdictsCollapsed`。
    /// 留存者是**首見**：doomed-first 時留下 doomed 側的 kind、keeper-first 時留下
    /// keeper 側的。這在 #461 之前的 doomed-first 排列**不會發生**（兩筆並存、零丟棄），
    /// 所以是本修法引入的、不是既有觀察；留存者選擇政策（首見／keeper 優先／last-wins）
    /// 屬顯式裁決，由 verify follow-up 追蹤。
    ///
    /// **前提與自保**：生產呼叫端的 `merged` 恆不含 `survivor`（`resolveDivergence`
    /// 的 `candidateKeys.filter { $0 != survivor }`）。helper 另以
    /// `pairing.holder != survivor` 自保——指向 survivor 的 verdict 不是遷移對象；
    /// 若把它算成「本次觸及」，觸及集合會退化成全量 dedup（被否決的方案 (a)）且
    /// `changed` 恆真造成空寫。#463 複用本函式的是 merge 側的四格（org×work-merge 是 drop-in；person-merge 的
    /// organization／person／venue 三格傳 `.person`）；rename 側走 `LibraryStore.migratedVerdicts`（全量 dedup，
    /// 語意刻意不同）。
    /// merge 側 holder verdict 的遷移＋收攏，**holderKind 參數化**（#463）：`.work`（work merge，
    /// #461 的原形）與 `.person`（person merge——`person:<被併 key>` holder 住在 organization 記錄上，
    /// 是 org-resolution 的判定；#395 rename 側已遷、merge 側漏了，#232→#271 的不對稱在 person-key 軸重演）。
    /// 語意與 `migrateWorkHolderVerdicts` 完全相同，只多一個 kind 篩選——那個函式現在是本函式的 `.work` 特例。
    static func migrateHolderVerdicts(
        _ refs: [ProvenanceReference], merged: Set<String>, survivor: String,
        holderKind: ProvenanceReference.VerdictHolderKind
    ) -> (refs: [ProvenanceReference], changed: Bool, collapsed: [String]) {
        func dedupKey(_ r: ProvenanceReference) -> String { "\(r.field)\u{0}\(r.value ?? "")" }
        var touched = Set<String>()
        var changed = false
        let rewritten: [ProvenanceReference] = refs.map { r in
            guard ProvenanceReference.resolutionVerdictFields.contains(r.field),
                  let v = r.value,
                  let pairing = ProvenanceReference.VerdictPairingValue.parse(v),
                  pairing.holderKind == holderKind,
                  pairing.holder != survivor,
                  merged.contains(pairing.holder) else { return r }
            let out = ProvenanceReference(
                field: r.field,
                value: ProvenanceReference.VerdictPairingValue(
                    holderKind: holderKind, holder: survivor,
                    literal: pairing.literal).encoded,
                kind: r.kind)
            changed = true
            touched.insert(dedupKey(out))
            return out
        }
        guard changed else { return (refs, false, []) }
        var seen = Set<String>()
        var deduped: [ProvenanceReference] = []
        var collapsed: [String] = []
        for r in rewritten {
            let k = dedupKey(r)
            if touched.contains(k), !seen.insert(k).inserted {
                collapsed.append(Self.describeCollapsedVerdict(r))
                continue
            }
            deduped.append(r)
        }
        return (deduped, true, collapsed)
    }

    /// `migrateHolderVerdicts` 的 `.work` 特例——#461 的原名，語意逐字不變（該 issue 的測試打這個名字）。
    static func migrateWorkHolderVerdicts(
        _ refs: [ProvenanceReference], merged: Set<String>, survivor: String
    ) -> (refs: [ProvenanceReference], changed: Bool, collapsed: [String]) {
        migrateHolderVerdicts(refs, merged: merged, survivor: survivor, holderKind: .work)
    }

    /// 收攏丟掉的那一列，說得出來的形：field ＋ value ＋ 被丟的判定原文（擷取型印 URL）。
    private static func describeCollapsedVerdict(_ r: ProvenanceReference) -> String {
        let reason: String
        switch r.kind {
        case .judgement(let statement, _): reason = "判定「\(statement)」"
        case .retrieval(let url, _, _, _, _): reason = "擷取 \(url)"
        }
        return "\(r.field) \(r.value ?? "")——丟棄 \(reason)"
    }

    private func resolveWorkDivergence(record: Divergence, survivor: String,
                                       mergedKeys: [String],
                                       snapshot: LibraryLoad) throws -> ResolveReport {
        let (keeper, doomed, contentWarnings) = try validateWorkPreconditions(
            survivor: survivor, mergedKeys: mergedKeys, snapshot: snapshot)
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
        var report = try commitResolution(record: record,
                                    keeperWrite: { try self.writeEntry(keeperFinal) },
                                    keeperEncode: { _ = try EntryYAML.encode(keeperFinal) },
                                    entriesToWrite: entriesToWrite,
                                    doomedIDs: doomed.map(\.id), mergedKeys: mergedKeys,
                                    snapshot: snapshot, survivor: survivor,
                                    survivorNote: "倖存者的記錄已被重寫"
                                        + "（work 消歧不搬欄位，見 #75）")
        // #463 verify logic L2：commit 早退（不可刪檔、記錄仍在等）或部分失敗時，下方的 holder 遷移**不得再寫檔**
        // ——否則一個回報「未動任何檔案」的失敗實際改寫了 person／venue／organization。此時 `report.failures`
        // 只可能含 commit 階段的失敗（遷移迴圈還沒跑）。這條閘同時涵蓋 #271／#460 的既有迴圈。
        guard report.failures.isEmpty else { return report }
        // #271（下半）：citekey 退役＝改名的一種——person 身上 `work:<被併鍵>` 的
        // verdict value 不遷移就安靜變 stale（rename 已修 #232、merge 漏了同型）。
        // 文法與 renameEntry 同源（VerdictPairingValue）；**收攏範圍刻意不同**——
        // rename 側全量 dedup（#232），merge 側只收本次觸及的鍵（#461／#71）。
        for var person in snapshot.people {
            let (migrated, changed, collapsed) = Self.migrateWorkHolderVerdicts(
                person.references, merged: merged, survivor: survivor)
            guard changed else { continue }
            person.references = migrated
            do {
                try writePerson(person)
                report.verdictValuesRewritten.append(person.key)
                report.verdictsCollapsed.append(   // display-safe-exempt: report 是資料面；CLI 印出時逐列過 displaySafe(c, max: 300)（DivergenceCommands），與 failures 同一條消毒點
                    contentsOf: collapsed.map { "person「\(person.key)」：\($0)" })   // display-safe-exempt: 同上——在此消毒會讓 CLI 二次消毒（displaySafe 不冪等）
            } catch {
                report.failures.append(
                    "person「\(person.key)」的 verdict value 遷移寫入失敗：\(error)")
            }
        }
        // venue 同型（#460）：#304 之後 venue 持 `work:` holder 的 verdict
        // （resolve-venues 落在被判定 venue 的 confirmed／rejected，第 13 條邊）
        // ——#271 補 person 側時它尚不存在。漏掉的實測後果（#456 pilot）：
        // 合併後 venue 留著指向已刪 citekey 的死 verdict，rejected stale 則讓
        // 否決抑制安靜失效。機制完全鏡射上方 person 迴圈：同文法、同冪等。
        for var venue in snapshot.venues {
            let (migrated, changed, collapsed) = Self.migrateWorkHolderVerdicts(
                venue.references, merged: merged, survivor: survivor)
            guard changed else { continue }
            venue.references = migrated
            do {
                _ = try writeVenue(venue)
                report.verdictValuesRewritten.append(venue.key)
                report.verdictsCollapsed.append(   // display-safe-exempt: report 是資料面；CLI 印出時逐列過 displaySafe(c, max: 300)（DivergenceCommands），與 failures 同一條消毒點
                    contentsOf: collapsed.map { "venue「\(venue.key)」：\($0)" })   // display-safe-exempt: 同上——在此消毒會讓 CLI 二次消毒（displaySafe 不冪等）
            } catch {
                report.failures.append(
                    "venue「\(venue.key)」的 verdict value 遷移寫入失敗：\(error)")
            }
        }
        // organization 同型（#463，網格的 merge×org 格）：#443 的團體作者升格面與 OrgResolver 會在
        // organization 記錄上落 `work:` holder 的 verdict（live store 實測 9 條）。#460 補 venue 時漏了
        // 它——同一個缺口第三次以同一形狀出現，機制完全鏡射上方兩個迴圈。
        for var org in snapshot.organizations {
            let (migrated, changed, collapsed) = Self.migrateWorkHolderVerdicts(
                org.references, merged: merged, survivor: survivor)
            guard changed else { continue }
            org.references = migrated
            do {
                _ = try writeOrganization(org)
                report.verdictValuesRewritten.append(org.key)
                report.verdictsCollapsed.append(   // display-safe-exempt: report 是資料面；CLI 印出時逐列過 displaySafe(c, max: 300)（DivergenceCommands），與 failures 同一條消毒點
                    contentsOf: collapsed.map { "organization「\(org.key)」：\($0)" })   // display-safe-exempt: 同上——在此消毒會讓 CLI 二次消毒（displaySafe 不冪等）
            } catch {
                report.failures.append(
                    "organization「\(org.key)」的 verdict value 遷移寫入失敗：\(error)")
            }
        }
        // #169：與 preview 側取自**同一個** validateWorkPreconditions 回傳值。
        //
        // **不在這裡 append**（#169 verify F3）：`judgementWarnings` 是在
        // `resolveDivergence` 於本函式**回傳之後**加的，所以在這裡加會得到
        // 「content, judgement」而 preview 是「judgement, content」——`ResolveReport ==`
        // 對 `warnings` 是順序敏感的陣列比較，兩邊在帶 judgement 的輸入上不相等。
        // 存到 `pendingContentWarnings` 由呼叫端在 judgement 之後接上。
        report.pendingContentWarnings = contentWarnings
        return report
    }

    /// 其他歧異記錄的候選遷移計算（`commitResolution` 與 dry-run preview 共用）。
    ///
    /// spec 說的是「store 內**每一個**指名被併實體的參照」——其他歧異記錄若也指名
    /// 被併的鍵，同樣要遷移。遷移後候選塌縮到少於兩個的，那筆記錄已被本次消歧回答，
    /// 一併刪除；留著會寫出一份 decode 拒收的檔（<2 候選），那是靜默的損壞。
    ///
    /// **比 key 也要比 shape。** 鍵在不同形狀之間可以同名（organization spec 明載
    /// 「key 與 person 同名是刻意的」），`shape:` 存進記錄的唯一理由就是這個。只比
    /// key 會把一筆機構歧異的候選改寫成指向 person 鍵，甚至讓它塌縮後被整筆刪除
    /// ——一個使用者從未回答、也與本次消歧無關的問題就這樣消失（#71 R1 verify）。
    struct DivergenceMigration {
        /// 遷移後要寫的記錄，**id 已重算**。
        var toWrite: [Divergence] = []
        /// 候選塌縮到 <2，本次消歧已回答它們，刪。
        var collapsed: [Divergence] = []
        /// 因 id 重算而要刪的**舊**檔（改名 = 刪舊建新）。
        var renamedFrom: [UUID] = []
        /// 重算後撞上另一筆內容不同的記錄——**必須由人裁決**，見下方 doc。
        var collisions: [String] = []
    }

    /// 其他歧異記錄的候選遷移。
    ///
    /// ## id 必須跟著候選走（#168）
    ///
    /// README 明寫「id 由候選鍵的集合推出，**同一組候選＝同一筆記錄**」，而
    /// #168 之前這裡改寫候選卻**保留舊 id**，於是記錄與它的候選集脫鉤。
    ///
    /// 聽起來像潔癖，實際後果是 **#75 的整套護欄可以被一串正常操作繞過**——
    /// `contradictsJudgement`、#133 F1「無判斷的重呼叫不得抹掉判斷」、159-4
    /// 「重錄不得抹掉 prefers」**三道全部 key 在那個不變式上**。席位五步實測
    /// （record → resolve → 再 record → resolve）：帶著判斷與 `prefers` 的那筆
    /// 記錄被連帶刪除、判斷指名為正確的那個實體被合併掉，dry-run 與實跑
    /// **只警告不擋**，exit 0。（issue body 寫「兩次都沒有一個字提到有判斷存在」
    /// ——那在 `cfe19c7` 上為真，在本 change 的 merge base 上**已經不是**：#159 補了
    /// 「連帶刪除的記錄帶有判斷」的警告。實質沒變：沒被擋、判斷指名為正確的實體
    /// 被摧毀、exit 0。量詞照抄自 issue 是本 change 一度犯的錯，席位實測抓到。）
    ///
    /// ## 重算會撞上三種碰撞，兩種是這個修法新引入的
    ///
    /// 1. **撞既有記錄**（原本的 bug 場景）：遷移後的候選集已經有一筆記錄。
    /// 2. **兩筆遷移記錄互撞**：`{a, x}` 與 `{a, y}` 在 x、y 都併入 z 之後同為
    ///    `{a, z}`。只比對既有記錄會漏掉這一種。
    /// 3. 撞正在被消歧的 `record` 本身——**結構上不可能**：`record` 的候選集必含
    ///    至少一個被併鍵，而任何遷移後的集合都不含被併鍵。仍在下方一併處理，
    ///    因為那個論證依賴 `mergedKeys` 非空，而那是別處的前提。
    ///
    /// 碰撞時**只有零損失才靜默合併**（question 與 judgement 皆相同）；否則
    /// 收進 `collisions` 由呼叫端拒絕整個消歧。自動挑一邊的判斷活下來，正是
    /// 本 issue 要修的那種靜默毀損。
    func migrateOtherDivergences(record: Divergence, survivor: String,
                                 mergedKeys: [String], snapshot: LibraryLoad)
        -> DivergenceMigration {
        let merged = Set(mergedKeys)
        let mergedShape = record.shape
        var out = DivergenceMigration()

        /// 除了 id 以外等值——**零損失才可靜默合併**。
        ///
        /// **`candidates` 必須在內**（#180 verify CRITICAL）。`forDivergence` 只雜湊
        /// 候選的 **key**、不含 shape，而 key 跨形狀同名是明文允許的
        /// （`Divergence.swift` 的 candidate doc）。少了這一項，一筆 person 歧異
        /// 遷移後會撞上「候選 key 相同但 shape 不同」的既有記錄、被判成零損失而
        /// **整筆丟掉**——席位實測：org 歧異 `{alice,bob}` 原封不動，而 person 歧異
        /// 「alice 與 bob 是同一人？」消失，exit 0、無任何訊息。
        ///
        /// **那是本 change 引入的**：base 上那筆只是 id 漂移（可見、可修）。把
        /// 「id 漂移」換成「記錄被靜默摧毀」是嚴格的退步。
        ///
        /// 加進來之後跨形狀情形轉成 `migrationCollision` 拒絕——仍礙事，但不毀資料。
        /// 根治要把 shape 納入 `forDivergence`，那是 format 級變更，不屬本 change。
        func sameContent(_ a: Divergence, _ b: Divergence) -> Bool {
            // **排序後比**（#168 verify HIGH）。Array `==` 是逐位置比較，而
            // `Divergence.==` 自己的 doc 第一行就寫「相等性**不看** `candidates` 的
            // 儲存順序」——先前這裡比型別自己宣告的相等性還嚴格。
            //
            // 而順序**真的會不同**：`DivergenceYAML.encode` 寫檔時把候選按
            // `(shape, key)` 排序，但遷移是「既有位置上做鍵替換」，替換後就不再排序。
            // 席位掃過三個鍵的全部 6 種相對順序：**2/6 被誤拒**（M 與 S 跨在 X
            // 兩側的那兩種），而錯誤訊息說「內容不同」——那句在該路徑上確定為假。
            // 候選愈多誤拒率愈高。
            //
            // shape 進排序鍵，所以跨形狀的 CRITICAL 仍然被擋。
            func norm(_ d: Divergence) -> [[String]] {
                d.candidates.map { [$0.shape.rawValue, $0.key] }
                    .sorted { ($0[0], $0[1]) < ($1[0], $1[1]) }
            }
            return norm(a) == norm(b) && a.question == b.question
                && a.judgement == b.judgement && a.unknownFields == b.unknownFields
        }
        // #381：這段的產物經 `out.collisions` → `migrationCollision(details:)` →
        // `errorDescription` 直達使用者。**store 內容要在這裡消毒**——相鄰的
        // `deletionNotRecoverable` 對 `$0.path` 就是這麼做的，本條先前漏了，
        // 而守衛看不見它（隱式 return，#381 的盲區）。
        func describe(_ d: Divergence) -> String {
            let j = d.judgement.map { "判斷「\(displaySafe($0.statement, max: 800))」"
                + ($0.prefers.map { p in "、傾向「\(displaySafe(p, max: 200))」" } ?? "") }
                ?? "無判斷"
            return "\(d.id.uuidString)（\(j)）"   // display-safe-exempt: uuidString 是 UUID 的正規形，不含 store 內容
        }

        // 不參與遷移、也不會被刪的既有記錄——碰撞的對照組。
        var claimed: [UUID: Divergence] = [:]
        var migratingIDs: Set<UUID> = []

        var pending: [(old: UUID, migrated: Divergence)] = []
        for var other in snapshot.divergences where other.id != record.id {
            let migrated = dedupeCandidates(other.candidates.map { c in
                (merged.contains(c.key) && c.shape == mergedShape)
                    ? DivergenceCandidate(key: survivor, shape: c.shape) : c
            })
            guard migrated != other.candidates else { continue }
            migratingIDs.insert(other.id)
            if migrated.count < 2 {
                out.collapsed.append(other)
            } else {
                let old = other.id
                other.candidates = migrated
                other.id = DeterministicUUID.forDivergence(candidateKeys: migrated.map(\.key))
                pending.append((old: old, migrated: other))
            }
        }
        // 對照組：沒在遷移、也沒塌縮的既有記錄（含 `record` 本身——見上方第 3 點）
        let collapsedIDs = Set(out.collapsed.map(\.id))
        for d in snapshot.divergences
        where !migratingIDs.contains(d.id) && !collapsedIDs.contains(d.id) {
            claimed[d.id] = d
        }

        // **依舊 id 排序後依序處理**：兩筆互撞時留下哪一筆必須是決定性的，不隨
        // `load()` 的回傳順序而變。
        for (old, m) in pending.sorted(by: { $0.old.uuidString < $1.old.uuidString }) {
            if let existing = claimed[m.id] {
                guard sameContent(existing, m) else {
                    out.collisions.append(
                        "遷移後 \(describe(m))（原 \(old.uuidString)）與 \(describe(existing)) "
                        + "會是同一組候選，但內容不同")
                    continue
                }
                // 零損失：既有那筆留著，這筆只需刪掉舊檔
                out.renamedFrom.append(old)
                continue
            }
            claimed[m.id] = m
            out.toWrite.append(m)
            if m.id != old { out.renamedFrom.append(old) }
        }
        return out
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
        let migration = migrateOtherDivergences(record: record, survivor: survivor,
                                                mergedKeys: mergedKeys, snapshot: snapshot)
        let otherToWrite = migration.toWrite
        let collapsed = migration.collapsed
        // #168：id 跟著候選走 ⇒ 改名 = 刪舊建新。舊檔進刪除清單，與塌縮／本次記錄
        // 同一批處理——它們的可刪性預檢、失敗收容、順序保證都該是同一套。
        let renamedFrom = migration.renamedFrom

        // 動磁碟前的 encode 預檢（沿用 renameEntry 的紀律）：可預期的失敗全部先擋掉，
        // 剩下的只有磁碟層錯誤——那才是下面逐筆收容要處理的。
        try keeperEncode()
        for e in entriesToWrite { _ = try EntryYAML.encode(e) }
        // #147 verify F1：預檢必須**完整鏡射**寫入條件（本 helper 存在的理由）——
        // 曾只 encode 不跑 assertDivergenceWritable，format gate 加入後 format < 5
        // store 上的消歧走到寫入才失敗：倖存者已改寫、參照已改、刪除被跳過的撕裂。
        for d in otherToWrite {
            try assertDivergenceWritable(d)
            _ = try DivergenceYAML.encode(d)
        }

        var report = ResolveReport()
        // #78-1（#139 verify F5 上移）：可預期的刪除失敗在**動任何磁碟之前**檢查
        // ——放在 keeperWrite 之後只能得到「別名已併、參照已改寫、什麼都沒刪」；
        // 放在這裡，immutable／不可刪的情況是**完全的 no-op**，與 resolveDivergence
        // doc「所有拒絕條件都在動磁碟之前」一致。TOCTOU 與真 I/O 錯誤仍由下方
        // 收容路徑處理。
        let allDoomedURLs = doomedIDs.map { entityURL(id: $0) }
            + (collapsed + [record]).map { entityURL(id: $0.id) }
            + renamedFrom.map { entityURL(id: $0) }
        let undeletable = allDoomedURLs.filter {
            FileManager.default.fileExists(atPath: $0.path) && !Self.isDeletableUpfront($0)
        }
        guard undeletable.isEmpty else {
            report.failures.append(
                "以下檔案不可刪（immutable flag 或目錄權限），未動任何檔案"
                + "（修好後可重跑同一個 id）："
                + undeletable.map(\.lastPathComponent).sorted().joined(separator: ", "))
            return report
        }
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
        // #139 verify F4：塌縮記錄**先**刪、全部成功**才**刪主記錄。順序反了或
        // 收容後繼續，主記錄會在塌縮記錄刪失敗時被刪掉——重跑同一個 id 只得
        // recordNotFound，而失敗的塌縮記錄留在磁碟上、候選還是未遷移的舊鍵，
        // §5.8 的「歧異記錄 MUST 保留」變成假話。
        // #168：id 重算 = 改名，舊檔要刪。**排在塌縮之前**是因為它與塌縮同屬
        // 「歧異記錄的清理」，而下面那道 `hasFailures` 閘要能一起攔住它們。
        //
        // **不得刪到剛寫好的新檔**：A 從 X 改名到 Y、而 B 的舊 id 剛好是 Y 時，
        // `renamedFrom = [X, Y]` 而 `toWrite` 裡有 id=Y 的 A——盲目刪 Y 會把
        // 才寫進去的 A 毀掉。寫入永遠先於刪除。
        //
        // **現行不可達**（mutation 實測：拿掉 `!writtenIDs.contains` 九條全綠）。
        // 論證：B 的舊 id 等於 A 的新 id ⇒ B 的原候選集等於 A 的遷移後候選集 ⇒
        // B 不含任何被併鍵 ⇒ **B 不遷移**，於是 B 走的是碰撞路徑（`claimed`）
        // 而不是改名路徑，`renamedFrom` 裡不會有它。
        //
        // 保留而非刪除，因為它釘的是「不遷移的記錄一定走碰撞路徑」這個前提；
        // 日後若讓某些記錄同時走兩條路（例如塌縮後又改名），它就會活起來。
        // **測試不得宣稱在驗它**——見 `DivergenceIDDriftTests` 對應那條的歸因。
        let writtenIDs = Set(otherToWrite.map(\.id))
        for old in renamedFrom.sorted(by: { $0.uuidString < $1.uuidString })
        where !writtenIDs.contains(old) {
            guard FileManager.default.fileExists(atPath: entityURL(id: old).path) else { continue }
            do {
                try FileManager.default.removeItem(at: entityURL(id: old))
                report.removedDivergences.append(old.uuidString)
            } catch {
                report.failures.append("刪除改名前的歧異記錄 \(old.uuidString) 失敗："
                    + ((error as? LocalizedError)?.errorDescription ?? String(describing: error)))
            }
        }
        for d in collapsed {
            guard FileManager.default.fileExists(atPath: entityURL(id: d.id).path) else { continue }
            do {
                try FileManager.default.removeItem(at: entityURL(id: d.id))
                report.removedDivergences.append(d.id.uuidString)
                // #78-2：使用者沒指名的塌縮刪除，帶 question
                report.collapsedDetails.append((id: d.id.uuidString, question: d.question))
            } catch {
                report.failures.append("刪除塌縮的歧異記錄 \(d.id.uuidString) 失敗："
                    + ((error as? LocalizedError)?.errorDescription ?? String(describing: error)))
            }
        }
        guard !report.hasFailures else {
            report.failures.append(
                "因塌縮記錄刪除失敗，主歧異記錄保留（修好後可重跑同一個 id）")
            report.rewritten.sort()
            report.removedDivergences.sort()
            return report
        }
        // 檔案不在 = 先前已刪。不回報成本輪的成果——回報一件沒做的事，與靜默同樣誤導。
        if FileManager.default.fileExists(atPath: entityURL(id: record.id).path) {
            do {
                try FileManager.default.removeItem(at: entityURL(id: record.id))
                report.removedDivergences.append(record.id.uuidString)
            } catch {
                report.failures.append("刪除歧異記錄 \(record.id.uuidString) 失敗："
                    + ((error as? LocalizedError)?.errorDescription ?? String(describing: error)))
            }
        }
        report.rewritten.sort()
        report.removedDivergences.sort()
        return report
    }

    /// 刪除前的可刪檢查（#78-1）：父目錄可寫 + 無 user-immutable flag。
    /// 只涵蓋**可預期**的失敗——回傳 true 不保證 removeItem 成功（TOCTOU），
    /// 但回傳 false 幾乎保證它會失敗，那正是值得前移的部分。
    static func isDeletableUpfront(_ url: URL) -> Bool {
        guard FileManager.default.isDeletableFile(atPath: url.path) else { return false }
        let immutable = ((try? FileManager.default
            .attributesOfItem(atPath: url.path)[.immutable]) as? Bool) ?? false
        return !immutable
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
    /// `DivergenceHardeningTests.testPersonFieldCoverageOfMergeCheck`：它用反射數 `Person` 的儲存屬性，與本函式聲明涵蓋的
    /// 數量不符就紅。加欄位而忘了這裡，測試會說話——不是靠註解提醒，也不是靠記憶。
    ///
    /// 涵蓋 `Person` 的 **10** 個儲存屬性（#227 起 `authorized` 併入 `names` 的
    /// `PersonNames` 分割，屬性數 11 → 10；#157 verify 157-10 曾抓到 doc 寫 8 而
    /// 常數是 11 的長期不一致）：`key` / `id`（身分，不隨合併移動）、
    /// `names`（別名聯集由合併搬移；authorized 分割的損失另行檢查）、以及下列各項。
    ///
    /// **插入位置紀律**（#157 verify 157-4（正典計數與三次機械化失敗的量測在 `docs/design-principles-and-philosophy.md` §16——**不要在原始碼裡各自重新計數**，那正是它一直過期的原因））：
    /// 新成員 **不得**插進既有 API 的 doc comment／attribute 與其宣告之間。那會讓兩份文件
    /// 對調——這段論證曾經整段掛到 Entry 版頭上，而它對 Entry 每一句都是假的
    /// （不是 Person、沒有那 8 個屬性、也不受 DivergenceHardeningTests.testPersonFieldCoverageOfMergeCheck 保護）。
    static func fieldsLostByMerging(_ p: Person, into keeper: Person) -> [String] {
        var losses: [String] = []
        func check(_ label: String, mine: String?, theirs: String?) {
            guard let theirs, !theirs.isEmpty else { return }  // 沒帶 → 不會失去
            guard mine != theirs else { return }               // 倖存者已有同值 → 不會失去
            losses.append("\(label): \(theirs)")
        }
        check("orcid", mine: keeper.orcid?.normalized, theirs: p.orcid?.normalized)
        check("openalex", mine: keeper.openalex, theirs: p.openalex)
        // #67：逝世日期。兩邊給出**不同**日期時尤其要擋——那不是排版差異，是對
        // 「這兩筆是不是同一個人」的反證，或至少是一個必須有人裁決的來源衝突。
        check("died", mine: keeper.died, theirs: p.died)
        check("note", mine: keeper.note, theirs: p.note)

        // #81：對外可稱呼的名字是**集合**不是純量——被併者指定過而倖存者沒指定的名字
        // 會消失。`names` 本身由既有的合併流程處理（別名聯集），但「哪個名字對外」是
        // 一個判斷，不能靠聯集救回來：兩邊各指定一個同書寫系統的名字時，聯集會違反
        // 「每個書寫系統至多一個」的不變式，所以必須讓人看見並選一個。
        let lostAuthorized = p.names.authorized.filter { !keeper.names.authorized.contains($0) }
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
        // #271：verdict references **不計入 loss**——它們的 value 是配對（work:citekey
        // :: literal），不屬於任何 record collection（#232 規格明文），搬到倖存者不會
        // 產生孤兒；person merge 會自動遷移（見 resolvePersonDivergence）。上面那段
        // 「搬過去可能指到倖存者沒有的值」的理由只對 field references 成立，維持不動。
        let lostRefs = p.references.filter {
            !keeper.references.contains($0)
                && !ProvenanceReference.resolutionVerdictFields.contains($0.field)
        }
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

    /// work 消歧的欄位遺失比對（#75 對二，與 person 側 `fieldsLostByMerging` 對稱）。
    ///
    /// work 消歧只搬「別人指向被併者」的參照，被併者自己帶的內容隨檔案消失而使用者
    /// 只看到「✓ 併入」。同 person 鐵律：**子集才放行**，被併者帶有倖存者沒有的
    /// 內容 → 拒絕並指名將失去什麼（搬欄位是人的判斷，不自動合併）。
    ///
    /// **出向 relations 特別要比**：`resolveWorkDivergence` 的遷移迴圈跳過 doomed
    /// 本身，所以 doomed 自己 cites/related 的東西不會搬到 keeper——實測確認會隨
    /// 檔案消失（#75 diagnosis 的「relations 出向遷移實況」）。
    static func fieldsLostByMerging(_ e: Entry, into keeper: Entry) -> [String] {
        var losses: [String] = []
        // **三態判定的單一實作**（#157 verify 157-12）：缺席／同值／衝突。
        //
        // 157-6 修的是這條規則的**一個實例**（date 的 keeper 側），不是規則本身。
        // 席位實測同一個函式裡還有三處展開、兩處錯，而且真 binary 會在**一則訊息裡
        // 吐兩句假話**：
        //
        //     doomed.fields["doi"] = ""，keeper 無 doi
        //       → 報 `fields.doi: `                    ← 空值＝缺席，卻報成遺失
        //     keeper.fields["doi"] = ""，doomed 有真值
        //       → 報 `fields.doi（兩邊都有但不同…）`     ← 「兩邊都有」是假的
        //
        // 後者與 157-6 修掉的「與倖存者的  互斥」是**同一句謊、同一個函式、隔壁欄位**。
        // 根因：person 側靠一個 `check()` helper 把三態一次做對，Entry 版是逐處展開
        // ——於是逐處寫錯。抽同一個 helper 共用。
        func check(_ label: String, mine: String?, theirs: String?,
                   conflictSuffix: String = "（兩邊都有但不同，需選一個）") {
            guard let theirs, !theirs.isEmpty else { return }   // 缺席（含空值）→ 不會失去
            guard let mine, !mine.isEmpty else {                // 倖存者沒有 → 失去
                losses.append("\(label): \(theirs)")
                return
            }
            guard mine != theirs else { return }                // 同值 → 不會失去
            losses.append("\(label)\(conflictSuffix)")
        }
        for (k, v) in e.fields.sorted(by: { $0.key < $1.key }) {
            check("fields.\(k)", mine: keeper.fields[k], theirs: v)
        }
        // attachments／tags／libraries：被併者有而倖存者沒有的（差集）
        // #157 verify 157-18：**指名**。整條閘的語意是「拒絕並指名將失去什麼」，
        // 而訊息結尾寫著「先把要保留的搬到倖存者身上」——只說「1 筆」的話那句話
        // 不可執行。同函式的 tags／cites／related／fields 全部指名，person 側的
        // `references` 也指名（附 field 清單）。同一個 feature 的兩半又不對稱。
        let lostAttach = e.attachments.filter { !keeper.attachments.contains($0) }
        if !lostAttach.isEmpty {
            losses.append("attachments: " + lostAttach.prefix(3).map(\.path)
                .joined(separator: "、") + (lostAttach.count > 3 ? "…" : ""))
        }
        let lostTags = e.akashic.tags.filter { !keeper.akashic.tags.contains($0) }
        if !lostTags.isEmpty { losses.append("tags: " + lostTags.joined(separator: "、")) }
        let lostLibs = e.akashic.libraries.filter { !keeper.akashic.libraries.contains($0) }
        if !lostLibs.isEmpty { losses.append("libraries: " + lostLibs.joined(separator: "、")) }
        // 副本引用（#223）：同 attachments／tags 的差集判準。被併者指向的已儲存內容
        // 若不在倖存者身上，那份副本就**失去了唯一指向它的記錄**——blob 還在
        // `sources/`，但沒有任何 work 說得出它是誰的副本（反向是現算的，記錄沒了就
        // 算不出來）。digest 完整列出不截斷：截半的 digest 無法貼去查，訊息叫人
        // 「把要保留的搬到倖存者身上」就不可執行。
        let lostSources = e.akashic.sources.filter { !keeper.akashic.sources.contains($0) }
        if !lostSources.isEmpty {
            losses.append("akashic.sources: " + lostSources.prefix(3).joined(separator: "、")
                + (lostSources.count > 3 ? "…（共 \(lostSources.count) 筆）" : ""))
        }
        // 出向 relations（doomed 自己指出去的）——遷移迴圈不搬 doomed 的出向
        let lostCites = e.akashic.relations.cites.filter { !keeper.akashic.relations.cites.contains($0) }
        if !lostCites.isEmpty { losses.append("cites: " + lostCites.joined(separator: "、")) }
        let lostRel = e.akashic.relations.related.filter { !keeper.akashic.relations.related.contains($0) }
        if !lostRel.isEmpty { losses.append("related: " + lostRel.joined(separator: "、")) }
        // venues（#304）：同 authors 的理由——doomed 的 `.key(...)` 是 resolve-venues
        // 歸戶的**產物**，合併不搬 venues，丟掉的是人做過的判斷；`.literal` 是待消歧
        // 的觀察，消失即「這篇的載體查過沒」永久不可判定。差集判準、指名。
        let lostVenues = e.venues.filter { !keeper.venues.contains($0) }
        if !lostVenues.isEmpty {
            losses.append("venues: " + lostVenues.map { ref -> String in
                switch ref {
                case .key(let k): return "key:\(displaySafe(k, max: 200))"
                case .literal(let l): return displaySafe(l, max: 200)
                }
            }.joined(separator: "、"))
        }
        // status：被併有、倖存無或不同
        if let s = e.akashic.status, !s.isEmpty, keeper.akashic.status != s {
            losses.append("status: \(s)")
        }
        // 作品識別碼（#394）：差集判準、指名——同 attachments／tags／venues 的形狀。
        //
        // **為什麼不是「同值就算了」而要逐個指名**：識別碼終結指涉。被併者帶著一個
        // 倖存者沒有的 DOI，意思是「這筆記錄曾經被認定指向那個作品」——丟掉它不是
        // 丟掉重複資料，是丟掉一個**身分判定**（`identity-is-judged-not-matched` 的
        // 六種封閉例外之一）。而且它不可由名字重算：DOI 不是標題的函數。
        //
        // 這裡讀的是**結構化欄位**不是 `canonicalDOIs`——殘留在 `fields` 裡的那份
        // 已經由上面的 `check("fields.\(k)"…)` 迴圈涵蓋，走 canonical 會讓同一個值
        // 被報兩次。
        func lostIdentifiers<T: Identifier>(_ mine: [T], _ theirs: [T], label: String) {
            let lost = theirs.filter { !mine.contains($0) }
            guard !lost.isEmpty else { return }
            losses.append("\(label): " + lost.map(\.normalized).joined(separator: "、"))
        }
        lostIdentifiers(keeper.doi, e.doi, label: "doi")
        lostIdentifiers(keeper.pmid, e.pmid, label: "pmid")
        lostIdentifiers(keeper.isbn, e.isbn, label: "isbn")
        // 欄位層級 provenance（#394 §5）：差集判準、指名——同上。
        //
        // **為什麼不能只靠上面的識別碼檢查涵蓋**：兩者會分開。倖存者與被併者帶著
        // **同一個** DOI 時上面那三行不報任何東西（差集為空），但被併者可能是唯一
        // 記著「這個號是從哪裡查到的」的那一筆。丟掉它不會讓任何識別碼消失，只會讓
        // 一個有來源的值變成沒來源的值——而那是安靜的：合併後的記錄看起來完全正常。
        //
        // 這正是 provenance-reference spec 那句「不能攜帶 reference 的識別碼不算
        // 記錄的一等公民」在合併面的對偶：能攜帶但在合併時被靜默丟掉，等於沒有。
        let lostRefs = e.references.filter { !keeper.references.contains($0) }
        if !lostRefs.isEmpty {
            losses.append("references: " + lostRefs.map {
                "\($0.field)" + ($0.value.map { v in "（\(displaySafe(v, max: 80))）" } ?? "")
            }.joined(separator: "、"))
        }
        // 學位論文事實（#335）：整塊當一個值比，不逐欄位拆。
        //
        // 理由是那兩個事實**互相依賴**——`availability: published` 帶著典藏庫，
        // 而 `unpublished` 依 §10.6 沒有典藏庫可帶。逐欄位比會產生「取 doomed 的
        // availability ＋ keeper 的 degree」這種**沒人裁決過的混合**，而那個組合
        // 可能在 APA7 上是錯的（例如把碩論的取得途徑掛到博論上）。
        //
        // 整塊比 ＋ 指名（訊息結尾叫人「把要保留的搬到倖存者身上」，只說「不同」
        // 不可執行）。判準同 `check`：缺席／同值／衝突三態。
        if let th = e.thesis, keeper.thesis != th {
            var parts: [String] = []
            if let d = th.degree { parts.append("degree=\(d.rawValue)") }
            switch th.availability {
            case nil: break
            case .unpublished: parts.append("availability=unpublished")
            case .published(let repository, let url):
                parts.append("availability=published")
                if let repository { parts.append("repository=\(displaySafe(repository, max: 200))") }
                if let url { parts.append("repository_url=\(displaySafe(url, max: 200))") }
            }
            let suffix = keeper.thesis == nil ? "" : "（兩邊都有但不同，需選一個）"
            losses.append("thesis: " + parts.joined(separator: "、") + suffix)
        }
        // Canonical authorship completeness 是 truth-bearing claim，不是可由 keeper-wins
        // 靜默捨棄的同步狀態。實際 work 消歧中兩筆合法 witness 的 work UUID 必然
        // 不同，因此 keeper 缺席與兩邊不同都要交回人工裁決；同值才是不會遺失。
        if let witness = e.akashic.authorListCompleteness,
           keeper.akashic.authorListCompleteness != witness {
            if keeper.akashic.authorListCompleteness == nil {
                losses.append("author-list-completeness（倖存者缺席 canonical witness）")
            } else {
                losses.append("author-list-completeness（兩邊都有但不同，需選一個）")
            }
        }
        // authors（#157 verify 157-1）：doomed 的 `.key(...)` 是 resolve-people 歸戶的
        // **產物**——person 側的 names 由合併搬移，但 work 的 authors **不搬**（實測
        // keeper 併完是 0 作者）。丟掉的是人做過的判斷，不是重複資料。
        //
        // **identity 用 exhaustive `switch`、無 `default`**（#157 verify 157-15）：
        // 原本三處都是 `if case … else if case … else { "" }`／`else { "?" }` 的兜底。
        // 今天 `Author` 只有兩個 case 所以兜底不可達，但**一旦加第三個 case，全部的
        // 新作者都會塌成 `""` 互相遮蔽**——那是靜默的資料遺失，而席位 mutation 實測
        // 966 條測試**一條都不會響**。exhaustive switch 讓「加 case」變成編譯錯誤，
        // 比 157-9 剛加的 Mirror 計數守衛更強（編譯期 vs 執行期），理由完全同源。
        // `identity` 的回傳值**只當比對鍵**（進 Set / 相等比較），不進任何輸出面。
        func identity(_ a: Author) -> String {
            switch a {
            case let .key(k): return "key:\(k)"       // display-safe-exempt: 比對鍵，不進輸出
            case let .organization(k): return "org:\(k)"  // display-safe-exempt: 同上（#323）
            case let .literal(s): return "literal:\(s)"   // display-safe-exempt: 同上
            }
        }
        // `display` 的回傳值會進 `losses`，而 `losses` 的**每一項**在下游
        // （`wouldLoseFields` 的 errorDescription）都過 `displaySafe($0, max: 300)`
        // ——與同函式其他所有 losses 條目同一條保險。
        func display(_ a: Author) -> String {
            switch a {
            case let .key(k): return "已歸戶 \(k)"     // display-safe-exempt: 進 losses，下游整批 displaySafe
            case let .organization(k): return "已歸戶團體 \(k)"  // display-safe-exempt: 同上（#323）
            case let .literal(s): return s
            }
        }
        let keeperAuthors = Set(keeper.authors.map(identity))
        let lostAuthors = e.authors.filter { !keeperAuthors.contains(identity($0)) }
        if !lostAuthors.isEmpty {
            losses.append("authors（\(lostAuthors.count) 個，含 "
                + lostAuthors.prefix(3).map(display)
                    .joined(separator: "、") + (lostAuthors.count > 3 ? "…" : "") + "）")
        }
        // **順序也比**（#157 verify 157-19）：先前只比集合，`[A,B]` vs `[B,A]` → 無 loss。
        // 採「比順序」而非「寫進封閉列舉說明為何不比」，理由是 codebase 自己會區分
        // 這件事——`Person.names` 的 doc 明寫「順序不帶語意（#81）」，`Entry.authors`
        // **沒有**對應聲明，而 work 的作者順序在學術慣例上帶語意（第一作者、通訊作者）。
        // 同集合不同序＝需要人裁決，不自動選一邊。
        // **比對前先 dedupe**（#157 verify 157-21）：`else if` 的 `Set(…) == keeperAuthors`
        // 擋得住集合差異，擋不住**重數**差異。keeper 帶既存重複作者時：
        //
        //     keeper = [a, a]、doomed = [a]  → 報「順序不同」
        //
        // 順序**沒有**不同（dedupe 後兩邊都是 `[a]`），而且 doomed 是 keeper 的子集、
        // **什麼都不會失去**——訊息宣稱的理由不成立，與這幾輪一直在收的「訊息說假話」
        // 同類。而 keeper 帶既存重複是本 repo **明文保護**的狀態
        //（`testUnrelatedRecordWithDuplicateAuthorsLeftAlone`：「既存的重複不該被順手
        // 折疊——消歧不是清理工具」），所以可達性不是理論的。
        else if dedupePreservingOrder(keeper.authors.map(identity))
                    != dedupePreservingOrder(e.authors.map(identity)),
                Set(e.authors.map(identity)) == keeperAuthors {
            losses.append("authors（同一組作者但**順序不同**，work 的作者順序帶語意，需人確認）")
        }
        // date（#157 verify 157-6／157-8）：判準是**前綴相容**，不是「只比在場與否」。
        //
        // 第一版寫成 `if let d = e.date, !d.isEmpty, keeper.date == nil`，兩個獨立錯誤：
        //
        // 1. **`keeper.date == nil` 讓空字串遮蔽真實日期**（157-6）。YAML `date: ""`
        //    decode 成 `Optional("")` 且不 quarantine——席位真 binary 實測：keeper
        //    `date: ""`、doomed `date: "2020-03-15"` → 閘不報、合併成功、日期永久消失。
        //    專案內明文慣例（`LibraryStore.swift:997`）：「空值視同缺席……同一個概念
        //    不該有兩套判準」。
        // 2. **「只比在場與否」矯正過頭**（157-8）：`2019` vs `2021` 靜默通過。原本
        //    要避免的是 `2020` vs `2020-03-15` 這種**精度**差異被當成衝突——那只證成
        //    前綴相容的放行，不證成「值不同也放行」。person 側結構相同的 `died` 對
        //    同一組輸入會報，其 doc 說得很清楚：不同日期「是對『這兩筆是不是同一個
        //    人』的反證，或至少是一個必須有人裁決的來源衝突」。
        // **title 只比缺席方向**（#157 verify 157-22）——這一格不是純排除。
        //
        // 排除 `type`/`title` 的理由明寫是「keeper 的寫法**就是人選的 canonical
        // form**」，而 `""` **不是任何人選的 form，它是缺席**。實測 fail-open：
        //
        //     keeper.title = ""、doomed.title = "The Only Real Title"
        //     → losses == []  → exit=0 → 唯一的真標題消失，零訊息
        //
        // 這是這幾輪唯一一個 **fail-open**（其餘 finding 都是 fail-closed 的誤拒 +
        // 錯訊息）。而且結構與 157-7 同構：`validate` 已經印過「⚠ title 為空」，
        // 系統早就知道，合併閘卻不看。
        //
        // **兩邊都非空的 title 差異仍刻意不擋**（#71 R2 DA 的誤拒教訓），只補缺席方向。
        if keeper.title.isEmpty, !e.title.isEmpty { losses.append("title: \(e.title)") }
        // #325 階段二：`type` 是封閉列舉，**沒有「缺席」這個態**——原本的
        // 「keeper 缺 type 就從對方補」隨自由字串一起退場。兩邊 type 不同時
        // 仍不擋（同 title 的 #71 R2 DA 誤拒教訓：只補缺席、不判衝突）。
        // date 用同一個三態骨架，但衝突判定換成前綴相容（見 ISO8601Prefix.compatible）。
        // **訊息不宣稱「互斥」**（#157 verify 157-12）：`2003/2004` 是 EDTF 區間、
        // 包含 2003，`2020-03-15T10:00` 是同一時點的更高精度——`compatible` 對它們
        // 回 false 是因為**判不出關係**，不是因為它們互斥。`ISO8601Prefix` 自己的
        // 型別 doc 就明寫 `Entry.date` 的值域屬 biblatex 契約、不屬本判定。
        let doomedDate = e.date.flatMap { $0.isEmpty ? nil : $0 }
        let keeperDate = keeper.date.flatMap { $0.isEmpty ? nil : $0 }
        if let d = doomedDate {
            if let k = keeperDate {
                if !ISO8601Prefix.compatible(d, k) {
                    losses.append("date: \(d)（與倖存者的 \(k) 無法機械判定是否同一日期"
                        + "——非 ISO 前綴相容，需人裁決）")
                }
            } else {
                losses.append("date: \(d)")
            }
        }
        // unknownFields（#157 verify 157-1／157-7，**最強的一項**）：#23
        // tolerant-preserve 的整個前提是「較新版本寫入、本版不認識的欄位不得被本版
        // 破壞」。本 binary **依定義無法判斷**它重不重要——唯一安全的預設是拒絕。
        //
        // **三分不是二分**（157-7，照抄 person 版）：key 缺席＝遺失、raw 相同＝不
        // 遺失、**raw 不同＝衝突**。第一版只比 key 在不在，於是「兩邊都有同名欄位
        // 但內容不同」整條漏掉——席位真 binary 實測 doomed 的
        // `peer_review_status: accepted-with-major-revisions-2026-03` 被 keeper 的
        // `pending` 靜默覆蓋，而 `validate` 兩行都印過「未知欄位（已保留）」。
        // 系統已經知道兩邊都有，合併閘卻不看值。
        func unknownLosses(_ theirs: [UnknownField], _ mine: [UnknownField],
                           label: String) {
            for f in theirs {
                guard let same = mine.first(where: { $0.key == f.key }) else {
                    losses.append("\(label)\(f.key)（較新版本寫入、本 binary 不認識）")
                    continue
                }
                if same.raw != f.raw {
                    losses.append("\(label)\(f.key)（兩邊都有但內容不同，需要選一個）")
                }
            }
        }
        unknownLosses(e.unknownFields, keeper.unknownFields, label: "未知欄位 ")
        unknownLosses(e.akashic.unknownFields, keeper.akashic.unknownFields,
                      label: "akashic 的未知欄位 ")
        // provenance（#157 verify 157-2）：Zotero 記錄的身分是 **(libraryID, zoteroKey)**
        // 這個對，不是 zoteroKey 單獨——不同 library 的同 key 是不同記錄。
        // orphanedAt 是「Zotero 端已刪除、待人工裁決」的標記，屬一般遺失。
        if let ep = e.provenance {
            if let kp = keeper.provenance {
                if ep.zoteroKey != kp.zoteroKey {
                    losses.append("zotero-key（\(ep.zoteroKey) ≠ \(kp.zoteroKey)，來源衝突）")
                } else if let el = ep.libraryID, el != kp.libraryID {
                    // #157 verify 157-12：**只在被併者有值時比**。`Provenance` 自己的
                    // doc 明寫「缺欄位＝pre-Phase-2 舊檔，**合法**」——`nil` 不是
                    // 「不同 library」，是「未記錄」。而且被併者為 nil 時這個方向
                    // **什麼都不會失去**（倖存者已有較完整的值），卻擋下合併且
                    // 「搬到倖存者身上」無物可搬。
                    losses.append("zotero library（\(el) ≠ "
                        + "\(kp.libraryID.map(String.init) ?? "未記錄")，同 key 不同 library＝不同記錄）")
                }
                if ep.orphanedAt != nil && kp.orphanedAt == nil {
                    losses.append("orphaned 標記（Zotero 端已刪除、待人工裁決）")
                }
            } else {
                losses.append("zotero-key: \(ep.zoteroKey)（倖存者無 provenance）")
            }
        }
        return losses
    }

    /// work 合併**不擋、但要說**的內容差異（#169）。
    ///
    /// 與 `fieldsLostByMerging` 是**互補的兩份清單**，不是它的延伸：
    ///
    /// | | 問的問題 | 後果 |
    /// |---|---|---|
    /// | `fieldsLostByMerging` | 被併者帶有倖存者**沒有**的內容嗎 | 拒絕 |
    /// | 本函式 | 兩邊**都有**但倖存者的比較少嗎 | 提醒 |
    ///
    /// `type`／`title` 刻意不擋（要求相等會重演 #71 R2 DA 的誤拒——同一篇的兩筆
    /// 記錄 title 大小寫／副標題本來就會不同，而 keeper 的寫法**就是人選的
    /// canonical form**）。但**「不擋」不蘊含「不說」**：
    ///
    ///     keeper: "Short"
    ///     doomed: "Short: A Much Longer Subtitle That Only This Record Has"
    ///     → 合併後副標題無聲消失，exit 0，`✓ 併入`
    ///
    /// 被刪檔在版控裡（gate 自己強制 tracked + clean），所以內容**可回溯**——這降低
    /// 了嚴重度，但不改變「使用者在當下看不到」。提醒放在 preview 與實跑兩邊，
    /// 讓它出現在**還能反悔的時點**。
    ///
    /// **判準：被併者的值是否嚴格包含倖存者的**（前綴或包含關係），而不是「兩者
    /// 不同」。後者會對每一組大小寫／標點差異都出聲，把提醒變成噪音——而噪音會
    /// 讓人停止讀它，那比不提醒更糟。
    static func contentWarningsForMerging(_ e: Entry, into keeper: Entry) -> [String] {
        // **只管 `title`。`type` 那一半已拿掉**（#169 verify F1）。
        //
        // `type` 是**封閉 token 集合**，字串包含與「完整度」零相關。窮舉 26 個常見
        // biblatex type，**13 對**滿足嚴格包含（`book ⊂ inbook`／`collection ⊂
        // incollection`／`proceedings ⊂ inproceedings`…），而真 store 裡 `book`(58)、
        // `incollection`(6)、`inproceedings`(4) 都在——不是理論風險。訊息本身也是
        // 假的：`inbook` 不是 `book` 的較長版本，是**不同的 entry type**，合併後
        // 沒有任何「較長版本」消失。而且單向（keeper=`inbook` 時靜默）。
        //
        // `longer()` 的論證（包含關係＝倖存者的版本較不完整）對自由文字的 title
        // 說得通，對封閉集合不成立。沒有替代判準——`type` 不同就是不同，那屬
        // 「這兩筆是不是同一篇」的問題，不是內容遺失。
        guard !keeper.title.isEmpty, !e.title.isEmpty else { return [] }
        let k = keeper.title, d = e.title
        // **`hasPrefix` 不是 `contains`**（#169 verify F9）。守衛用 `contains`
        // （任意位置）而 `extra` 用 `dropFirst(k.count)` 算——那只在 `k` 是前綴時
        // 正確。席位實測七種形狀，六種訊息在說假話：
        //
        //     Nature / The Nature of Space and Time  → 宣稱多了「ture of Space and Time」
        //     Core   / The Core of It                → 把 keeper **已經有的** Core 報成「多了」
        //     Learning / [Learning]                  → WARN（純標點，正是 F2 要消掉的那類）
        //
        // D/E/F（引號、方括號、前導標點）是 F2 修法的漏網：詞字元 guard 檢查的是
        // **切歪之後**的字串，剛好含字母就過。而這個 feature 的全部價值就是「告訴
        // 你什麼會消失」——訊息說假話比不提醒更糟。
        //
        // 代價講清楚：`hasPrefix` 同時放掉「keeper 在中間／尾端而 doomed 真的多了
        // 內容」的情形。取**窄而正確**——判準與訊息一致；寬而正確要算真正的前後
        // 兩段差異，那是另一個形狀的改動。
        // **前綴比對走 case-fold**（#169 verify F5，席位的論據比我原本的強）。
        //
        // 真 corpus 上 15/15 有差異的候選對**都是大小寫差異**（`A Mixture Model
        // Combining…` vs `A mixture model combining…`）——也就是說這份 store 裡
        // 「同一篇的兩筆記錄」幾乎必然在大小寫上不同。當一組**真的**帶副標題遺失
        // 的配對出現時，它**同時**帶大小寫差異的機率高於不帶，而那組會被
        // case-sensitive 判準整個漏掉。
        //
        // 而 case-fold 幾乎不帶進噪音：純大小寫差異等長 → `count >` 擋掉；
        // 大小寫差異 ＋ 尾端句點 → extra 只有 `.` → 詞字元 guard 擋掉。
        //
        // **`extra` 必須從原始的 `d` 切**，不能從折疊後的字串切，否則訊息會印出
        // 小寫化的內容——那是席位特別點名的實作陷阱。
        guard d.lowercased().hasPrefix(k.lowercased()), d.count > k.count else { return [] }

        // **多出來的部分必須含詞字元**（#169 verify F2）。
        //
        // 席位在真 store 上量：78 組候選重複對、156 次判定，「兩者不同」觸發 32 次、
        // 「嚴格包含」觸發 5 次——6 倍差距證實了噪音的顧慮。**但那 5 次全部是
        // 「doomed 只多一個句點」**（APA 式句末句點），真實遺失 0 筆。
        //
        // 「嚴格包含沒有排除標點噪音——尾端標點正好就是嚴格包含的形狀。」原本的
        // doc 寫「排除大小寫／標點差異」，實際只排除了大小寫。判準把自己論證要
        // 避免的失敗模式製造了出來。
        let extra = String(d.dropFirst(k.count))
        guard extra.contains(where: { $0.isLetter || $0.isNumber }) else { return [] }

        return ["title：被併的「\(displaySafe(e.citekey, max: 200))」比倖存者多了"
                + "「\(displaySafe(extra, max: 300))」——合併後那段會消失"
                + "（不擋；確認 keeper 的寫法是你要的 canonical form）"]
    }

    /// work 合併比對**刻意排除**的欄位（#157 verify 157-1 的取捨，明寫讓「排除」與
    /// 「忘記」可分辨）：
    ///
    /// - `type` / `title`：**部分比對，不是純排除**（#157 verify 157-22）。
    ///   要求**相等**會直接重演 #71 R2 DA 的誤拒——同一篇的兩筆記錄 title 大小寫／
    ///   副標題本來就會不同，而 keeper 的寫法**就是人選的 canonical form**。合併的
    ///   語意是「keeper 的表述勝出」，不是「兩邊必須一致」。
    ///   **但 `""` 不是任何人選的 form，它是缺席**——所以只比缺席方向（keeper 空、
    ///   被併者非空 → 報）。這與本函式其他欄位的「空值＝缺席」是同一條規則，
    ///   先前漏了這一格，造成本函式唯一的 **fail-open**（唯一的真標題靜默消失）。
    /// - `id` / `citekey`：身分，不隨合併移動（同 person 側的 key/id）。
    ///
    /// **逐一對到 `Entry` 的 16 個儲存屬性**（#157 verify 157-10：原本寫「這五個 +
    /// 上方的六類 = 11」，兩個數都錯，只是 5+6 湊巧等於 11——排除項是 4 個、比對
    /// 的是 7 個。湊得出總數不代表對得上）：
    ///
    /// | 比對（12） | **部分比對**（2） | 排除（2） |
    /// |---|---|---|
    /// | `fields`、`attachments`、`akashic`（tags／libraries／status／relations／authorListCompleteness／unknownFields 六個子欄位都在裡面，**收合成一個屬性算**）、`authors`、`venues`（#304，差集判準同 authors 的理由）、`date`、`unknownFields`、`provenance`、`thesis`（#335，**整塊比不逐欄位拆**——兩個事實互相依賴，逐欄位比會產生沒人裁決過的混合）、`doi`／`pmid`／`isbn`（#394，差集判準；丟掉一個識別碼是丟掉一次**身分判定**，且它不可由名字重算）、`references`（#394 §5，差集判準；**與識別碼檢查不重疊**——兩邊帶同一個 DOI 時識別碼差集為空，但被併者可能是唯一記著那個號從哪查到的，丟掉它會讓一個有來源的值安靜地變成沒來源的值） | `type`、`title`——**只比缺席方向**（見下） | `id`、`citekey` |
    ///
    /// 13 + 2 + 2 = 17，由 `testEntryFieldCoverageOfMergeCheck` 以反射釘住。
    ///
    /// **反射只釘頂層**（#157 verify 157-9）：`AkashicMeta`／`Relations`／`Provenance`
    /// 的巢狀屬性另有各自的計數斷言——歷史上 schema 演化正是發生在 `akashic` 那層
    /// （`Models.swift` 自己這麼寫，#13 的 `libraries` 即是），只釘頂層等於對最會
    /// rot 的地方失明。
    static let entryFieldsCoveredByMergeCheck = 17

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

    /// 本函式涵蓋的 `Person` 儲存屬性數。`DivergenceHardeningTests.testPersonFieldCoverageOfMergeCheck` 拿它與反射比對。
    static let personFieldsCoveredByMergeCheck = 10

    // MARK: - 小工具

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
            case .organization, .divergence, .venue:
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

    /// 子程序環境：**剝除全部 `GIT_*`**（#239）。
    ///
    /// 本型別的每一處 git 呼叫問的都是「**`dir` 自己的** repo 怎麼說」，答案不該被
    /// 呼叫者的環境改變。而 `-C <dir>` **擋不住 `GIT_DIR`**——後者優先權更高。任何
    /// 從 git hook 執行的路徑（`.githooks/pre-push` 跑測試、或使用者在 hook 裡呼叫
    /// CLI）都會讓這些檢查對**錯的 repo** 提問。
    ///
    /// 用前綴剝除而非列舉具名變數：git 版本會新增變數，列舉會隨時間漏掉。
    static var scrubbedGitEnvironment: [String: String] {
        ProcessInfo.processInfo.environment.filter { !$0.key.hasPrefix("GIT_") }
    }

    /// 在 `dir` 跑一次 git。回傳 nil = 根本執行不起來（沒有 git、或 spawn 失敗）。
    ///
    /// 刻意**不**用 shell：參數直接進 `arguments`，路徑含空白或引號都不會被重新解析。
    static func git(_ args: [String], in dir: URL) -> (status: Int32, out: String)? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        p.arguments = ["git", "-C", dir.path] + args
        p.environment = scrubbedGitEnvironment
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = Pipe()
        do { try p.run() } catch { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return (p.terminationStatus, String(data: data, encoding: .utf8) ?? "")
    }

    /// store 是否位於版本控制的工作樹內。
    ///
    /// **本函式的 doc 曾經孤兒化**（#170，插入位置紀律的**第六例**，且是 pre-existing）：
    /// 下面這整段——含「88% CPU 加 29 GB RSS」那個效能論證——曾經無空行地接在
    /// `doomedRelativePaths` 頭上，而本宣告零註解。讀那段的人會以為它在講另一個函式。
    ///
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
