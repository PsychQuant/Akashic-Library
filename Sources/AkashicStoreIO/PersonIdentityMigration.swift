import Foundation
import AkashicCore

/// #241／#227 的一次性遷移：對每筆 person **同時**做三件事——發新 v4 `id`、
/// 以新 id 為檔名寫新檔、把平坦的 `names` + 兄弟 `authorized` 摺成巢狀分割。
///
/// ## 為什麼是同一支遷移
///
/// 兩者都要遍歷同一批記錄、都是 non-additive（format 10）。分兩次做會讓 store
/// 經歷兩次不可逆變更（`.claude/rules/no-compat-fallback.md`：要改就一次改全部）。
///
/// ## 涵蓋的舊形狀（#227 verify R1/R2 起——遷移是舊形狀**唯一**的進入路徑，所以
/// 它的涵蓋面必須是封閉列舉，缺一格就是一格的死路）
///
/// | 形狀 | 處置 |
/// |---|---|
/// | entities 佈局、`person:` 裸標籤（format ≥ 3） | 摺疊 + 重發 id + 改檔名 |
/// | entities 佈局、`type: person`（format 2） | 同上（R1 L7——先前靜默跳過） |
/// | legacy 佈局 `people/<key>.yaml`（format 1） | 摺疊 + 補發 id **就地寫回**（檔名即 key，
///   不改名）；佈局搬移仍由 `akashic migrate` 做（R1 F2——先前三方循環無出口） |
/// | 檔上缺 `id:`（平坦或**巢狀** names 皆然） | 補一個 id 先試現行 decoder，仍敗才摺
///   （R2 C3——先摺再補會對巢狀塊誤擲「非 canonical」，補 id 程式碼不可達）。
///   補發即 spec `record-identity` 允許的 one-time backfill |
/// | `names: [a, b]` flow style | 摺疊（僅限無引號的簡單純量；其餘計入 failed 並
///   點名「無法辨識的 names 寫法」——不讓 decoder 的泛用訊息形成循環建議，R1 NEW-2） |
/// | 已是巢狀但 id 非 v4（半套） | 只重發 id（經 key 級收斂裁決，見下） |
/// | 已是巢狀且 id 是 v4 | 跳過——但先過 validate（R2 C2：error 級的「新形」記錄
///   報 failed 點名，不得謊稱「已是新形狀」；檔案不動） |
///
/// ## 收斂（R2 C1——**key 級**，不是形狀級）
///
/// 中斷留下的殘留可以是**任何**形狀組合：舊形+新形、巢狀v5+新形、甚至兩個 v4。
/// 所以收斂裁決按 key 分組做在**全部檔案分類完之後**：
///
/// - 一個 key 恰一筆 → 照形狀處置（skip／reissue／migrate）
/// - 一個 key 多筆 → **全部**計入 failed 並互相點名（唯一的 v4 例外：恰一筆 v4 +
///   其餘舊形時，v4 那筆 skipped、舊形那些 failed 點名殘留）——重複的裁決屬於人，
///   工具永不發第三個 id、永不自動刪誰
///
/// ## 原子性（design D5）
///
/// 每筆的順序固定：發新 id → **先寫新檔** → 刪舊檔。中斷留下的是可偵測的重複，
/// 不是資料遺失；重跑由上面的 key 級收斂接住。
///
/// ## 回復路徑（design D6 + R2 C4）
///
/// `apply: true` 要求：git 工作樹、乾淨、且**每個將被改寫／刪除的檔案自身被追蹤**
/// （目錄級「有東西被追蹤」不夠——部分追蹤的 store 裡，被 .gitignore 排除的那個檔
/// 對 git 零歷史，改寫即不可回復；R2 三席收斂）。未追蹤的檔計入 failed 點名，
/// 已追蹤的照常遷移。dry-run 不受此前置。
///
/// ## 寫入邊界（R1 L2/S3）
///
/// 本型別繞過 `writePerson` 的 v10 gate（它**就是**規格說的舊形狀唯一進入路徑，
/// marker 還在舊值是它存在的前提；marker 的實際 bump 仍是使用者知情的動作），
/// 但**不**繞過 `Person.validate()`——`.error` 級的記錄計入 failed 並點名，不落盤。
public enum PersonIdentityMigration {

    public struct Report: Equatable {
        /// 本輪（將）遷移的 person key，依字典序。
        public var migrated: [String] = []
        /// 已是新形狀（現行 decoder 可讀、id 為 v4、validate 過）而跳過的 key。
        public var skipped: [String] = []
        /// 處理失敗的檔與原因。單筆失敗不中止整批。
        public var failed: [(file: String, reason: String)] = []
        /// store 是 legacy 佈局（就地遷移；佈局搬移與 marker bump 前還有 `akashic
        /// migrate` 一步——CLI 的下一步指示依此分流，R2 C5）。
        public var legacyLayout = false

        public static func == (a: Report, b: Report) -> Bool {
            a.migrated == b.migrated && a.skipped == b.skipped
                && a.failed.elementsEqual(b.failed, by: { $0 == $1 })
                && a.legacyLayout == b.legacyLayout
        }
    }

    public enum MigrationError: LocalizedError {
        case noRecoveryPath(detail: String)
        case dirtyWorktree(detail: String)
        case untrackedContent(detail: String)

        public var errorDescription: String? {
            switch self {
            case .noRecoveryPath(let d):
                return "store 不在可用的 git 工作樹內（\(displaySafeInvisible(d, max: 200))）"
                     + "——本遷移不可逆，git 是它的回復路徑；先把 store 納入版控再 --apply"
            case .dirtyWorktree(let d):
                // d 是 git status 的路徑列——store 衍生內容，消毒後才可見
                return "store 工作樹有未提交變更——在其上重寫檔名會讓 git checkout 救不回來。"
                     + "請先 commit（或 stash）再 --apply。未提交的路徑：\(displaySafeInvisible(d, max: 400))"
            case .untrackedContent(let d):
                return "store 的 person 檔未被 git 追蹤（\(displaySafeInvisible(d, max: 200))）——"
                     + "工作樹「乾淨」對被 ignore 的內容是空話，刪掉的舊檔 git 救不回。"
                     + "先 git add + commit（或修 .gitignore）再 --apply"
            }
        }
    }

    /// 分類結果：一個檔的解讀。
    private struct Classified {
        enum Kind {
            case newShape          // 巢狀 + v4（候選 skip）
            case reissueOnly       // 巢狀 + 非 v4 id（只重發）
            case legacy            // 經摺疊／補 id 後可讀（重發＋改形）
        }
        var kind: Kind
        var person: Person
        var url: URL
        var relFile: String
    }

    /// 遍歷 store 的 person 記錄，回傳報告。`apply: false`（預設）零寫入。
    @discardableResult
    public static func run(store: LibraryStore, apply: Bool = false) throws -> Report {
        var report = Report()
        let fm = FileManager.default

        // 掃描來源：entities 佈局掃 entities/、legacy 佈局掃 people/（該目錄依佈局
        // 定義只放 person，無需形狀標籤）。
        let entitiesMode = store.usesEntitiesLayout
        report.legacyLayout = !entitiesMode
        let dir = entitiesMode ? store.entitiesDir : store.peopleDir
        let dirName = dir.lastPathComponent
        // R3 NEW-4／R4 NEW-R4-2：列舉錯誤不得偽裝成「空 store 成功」。直接列舉、
        // 只在 underlying error 確為「不存在」時視為合法空（legacy 空 store 可能沒建
        // people/）；其餘（EACCES、I/O…）原樣 throw。不用 fileExists probe——它把
        // 一切查詢錯誤折成 false，且與列舉之間有 TOCTOU。
        let files: [String]
        do {
            files = try fm.contentsOfDirectory(atPath: dir.path)
                .filter { $0.hasSuffix(".yaml") }.sorted()
        } catch let e as NSError
            where e.domain == NSCocoaErrorDomain && e.code == NSFileReadNoSuchFileError {
            files = []
        }
        if apply {
            try assertWorktreeUsable(root: store.root)
        }
        // per-file trackedness 集合（R2 C4／R3 NEW-2）：apply 時查一次，寫入階段
        // 逐檔以 **UTF-8 位元組** 比對——Swift String 相等是 canonical equivalence，
        // NFC/NFD 雙生檔名會讓未追蹤檔冒充 tracked 檔。查詢失敗 throw（fail-safe
        // 但原因要對：查不到 ≠ 未追蹤）。
        let trackedRelPaths: Set<Data> = apply
            ? try trackedFiles(root: store.root, dirName: dirName) : []

        // ── Pass A：逐檔解讀（零寫入、零裁決）──
        var classified: [Classified] = []
        var unparsedKeys: [String: [String]] = [:]   // 解不開但取得到 key 的檔（R3 NEW-1）
        var keylessUnparsed: [String] = []           // 連 key 都取不到的檔（→ 抑制全部重發）
        for file in files {
            let url = dir.appendingPathComponent(file)
            let relFile = "\(dirName)/\(file)"
            guard let text = try? String(contentsOf: url, encoding: .utf8) else {
                report.failed.append((file: relFile, reason: "讀不出 UTF-8 內容"))
                continue
            }
            if entitiesMode {
                guard isPersonShaped(text) else { continue }   // work／org／divergence 不動
            }

            if let current = try? PersonYAML.decode(text) {
                let kind: Classified.Kind = uuidVersion(current.id) == 4 ? .newShape : .reissueOnly
                classified.append(Classified(kind: kind, person: current, url: url, relFile: relFile))
                continue
            }
            // R2 C3：缺 id 的檔**先補 id 再試現行 decoder**——巢狀+缺id 的半遷移檔
            // 走摺疊會被誤擲「非 canonical」。補的 id 即 backfill（本來就要發新 id）。
            if !text.components(separatedBy: "\n").contains(where: { $0.hasPrefix("id: ") }) {
                let withID = insertLine("id: \(UUID().uuidString)", into: text)
                if let backfilled = try? PersonYAML.decode(withID) {
                    classified.append(Classified(kind: .legacy, person: backfilled,
                                                 url: url, relFile: relFile))
                    continue
                }
            }
            // 舊形：摺疊 → 確保 id → 現行 decoder 驗證。
            do {
                var folded = try foldLegacyNames(text)
                if !folded.components(separatedBy: "\n").contains(where: { $0.hasPrefix("id: ") }) {
                    folded = insertLine("id: \(UUID().uuidString)", into: folded)
                }
                let person = try PersonYAML.decode(folded)
                classified.append(Classified(kind: .legacy, person: person,
                                             url: url, relFile: relFile))
            } catch {
                let reason = (error as? LocalizedError)?.errorDescription ?? "\(error)"
                report.failed.append((file: relFile, reason: reason))
                // R3 NEW-1：解不開的檔仍可能與別的檔同 key——它必須**參與**裁決，
                // 否則隱藏重複會讓 singleton 誤判、照樣重發 id。文字層取頂層 key；
                // 連 key 都取不到 → 記入「盲區」，抑制本輪**全部**重發（保守：
                // 無法排除任何 key 的隱藏重複）。
                if let k = extractTopLevelKey(text) {
                    unparsedKeys[k, default: []].append(relFile)
                } else {
                    keylessUnparsed.append(relFile)
                }
            }
        }

        // ── Pass B：key 級收斂裁決（R2 C1）──
        var byKey: [String: [Classified]] = [:]
        for c in classified { byKey[c.person.key, default: []].append(c) }

        var work: [WorkItem] = []
        for (key, group) in byKey.sorted(by: { $0.key < $1.key }) {
            // R3 NEW-1：同 key 有解不開的檔 → 整組不得重發（隱藏重複無法排除），
            // 可讀的那些也計入 failed 互相點名。
            if let blind = unparsedKeys[key] {
                for c in group {
                    report.failed.append((file: c.relFile,
                        reason: "同 key「\(key)」另有無法解讀的檔（\(blind.joined(separator: "、"))）"
                              + "——修復該檔前不重發 id（隱藏重複無法排除）"))
                }
                continue
            }
            if group.count > 1 {
                adjudicateDuplicates(key: key, group: group, report: &report)
                continue
            }
            let c = group[0]
            switch c.kind {
            case .newShape:
                // R2 C2：skip 也要先過 validate——error 級的「新形」記錄謊稱
                // 「已是新形狀」會讓操作者以為 store 乾淨。檔案不動（非本遷移
                // 的形狀問題），failed 點名交給人。
                let errors = c.person.validate().filter { $0.severity == .error }
                if errors.isEmpty {
                    report.skipped.append(key)
                } else {
                    let msgs = errors.prefix(3).map(\.message).joined(separator: "；")
                    report.failed.append((file: c.relFile,
                        reason: "已是新形狀但驗證失敗（檔案不動，請手動修復）：\(msgs)"))
                }
            case .reissueOnly:
                var reissued = c.person
                reissued.id = UUID()
                scheduleWrite(reissued, from: c, entitiesMode: entitiesMode,
                              store: store, work: &work, report: &report)
            case .legacy:
                var person = c.person
                // R1 L8：半套檔若已持有獨立 v4 id（含剛 backfill 的），保留；否則重發。
                if uuidVersion(person.id) != 4 { person.id = UUID() }
                scheduleWrite(person, from: c, entitiesMode: entitiesMode,
                              store: store, work: &work, report: &report)
            }
        }

        // R3 NEW-1（保守全域抑制）：有 person 形但連 key 都取不到的檔在——
        // 任何重發都可能撞上它的隱藏 key。撤回全部排程，逐筆點名原因。
        if !keylessUnparsed.isEmpty {
            let blind = keylessUnparsed.joined(separator: "、")
            for item in work {
                if let idx = report.migrated.firstIndex(of: item.key) {
                    report.migrated.remove(at: idx)
                }
                report.failed.append((file: item.relFile,
                    reason: "store 有無法解讀且取不到 key 的 person 檔（\(blind)）——"
                          + "修復它之前不重發任何 id（隱藏重複無法排除）"))
            }
            work.removeAll()
        }
        report.migrated.sort()
        report.skipped.sort()
        report.failed.sort { $0.file < $1.file }
        guard apply else { return report }

        // ── Pass C：寫入（先寫後刪，D5；per-file trackedness，R2 C4）──
        for item in work {
            // R2 C4：**這個檔自己**必須被 git 追蹤——目錄級非空放行會讓被
            // .gitignore 排除的檔（git 零歷史）被靜默改寫，不可回復。
            guard trackedRelPaths.contains(Data(item.relFile.utf8)) else {
                if let idx = report.migrated.firstIndex(of: item.key) {
                    report.migrated.remove(at: idx)
                }
                report.failed.append((file: item.relFile,
                    reason: "未被 git 追蹤（可能被 .gitignore 排除）——改寫後 git 救不回，"
                          + "先 git add + commit 這個檔再重跑"))
                continue
            }
            do {
                try store.atomicWrite(item.newText, to: item.dest,
                                      mustCreate: item.dest != item.url)
            } catch {
                // 未寫入的失敗：記錄保持原狀（spec：left in its prior state）
                if let idx = report.migrated.firstIndex(of: item.key) {
                    report.migrated.remove(at: idx)   // 只移一筆——同 key 計數不誤刪（R1 S7）
                }
                let reason = (error as? LocalizedError)?.errorDescription ?? "\(error)"
                report.failed.append((file: item.relFile,
                                      reason: "寫入新檔失敗（記錄未動）：\(reason)"))
                continue
            }
            if item.dest != item.url {
                do { try fm.removeItem(at: item.url) } catch {
                    // R1 F6：新檔已寫成、舊檔刪不掉——磁碟是「可偵測的重複」不是
                    // 原狀，report 必須說清楚，不得偽稱失敗未動。
                    let reason = (error as? LocalizedError)?.errorDescription ?? "\(error)"
                    report.failed.append((file: item.relFile,
                        reason: "新檔已寫入（\(item.dest.lastPathComponent)）、舊檔刪除失敗"
                              + "——目前新舊並存，請手動刪除舊檔：\(reason)"))
                }
            }
        }
        return report
    }

    private struct WorkItem {
        var key: String
        var url: URL
        var relFile: String
        var newText: String
        var dest: URL
    }

    /// 同 key 多筆的裁決（R2 C1）：恰一筆 v4 → 它 skipped（仍過 validate）、其餘
    /// failed 點名殘留；否則全部 failed 互相點名。工具永不發第三個 id、永不自動刪誰。
    /// R3 NEW-2：檔案身分用**陣列 index**，不用 relFile 字串比對（String 相等是
    /// canonical equivalence，NFC/NFD 雙生檔名會被誤判為同一檔）。
    private static func adjudicateDuplicates(key: String, group: [Classified],
                                             report: inout Report) {
        let othersOf = { (me: Int) in
            group.indices.filter { $0 != me }.map { group[$0].relFile }.joined(separator: "、")
        }
        let v4Indices = group.indices.filter { group[$0].kind == .newShape }
        if v4Indices.count == 1 {
            let ki = v4Indices[0]
            let keeper = group[ki]
            let errors = keeper.person.validate().filter { $0.severity == .error }
            if errors.isEmpty {
                report.skipped.append(key)
            } else {
                // R3 NEW-5：keeper 自己也要交叉點名同 key 的其他檔——multi-file
                // group 的互相點名規則對它同樣成立。
                let msgs = errors.prefix(3).map(\.message).joined(separator: "；")
                report.failed.append((file: keeper.relFile,
                    reason: "已是新形狀但驗證失敗（檔案不動，請手動修復）：\(msgs)"
                          + "（另有同 key 檔：\(othersOf(ki))）"))
            }
            for i in group.indices where i != ki {
                report.failed.append((file: group[i].relFile,
                    reason: "重複（中斷殘留）：同 key「\(key)」的新形檔已存在"
                          + "（\(keeper.relFile)）——請人工確認內容一致後刪除本檔，不自動裁決"))
            }
        } else {
            for i in group.indices {
                report.failed.append((file: group[i].relFile,
                    reason: "同 key「\(key)」有 \(group.count) 個檔（另：\(othersOf(i))）"
                          + "——重複的裁決屬於人；不發新 id、不自動刪任何一個"))
            }
        }
    }

    /// R2 C5／R3 NEW-3：CLI 下一步指示的**唯一**成功判準是「apply 且零失敗」——
    /// migrated 非空不是條件（全 skipped 的重跑、空 store 同樣需要出口）。
    /// 純函式住這裡（executable target 不可測），CLI 只負責 print。
    /// #472：**issue 只點名兩支遷移，這是第三支同型的**（`no-compat-fallback` 記過
    /// 「同型缺陷成對出現，而 issue 只記了先被看見的那一個」）。目標是常數，提示由
    /// `StoreVersion.bumpHint` 依現況決定。
    public static let targetFormat = 10

    public static func nextStep(report: Report, apply: Bool, current: Int?) -> String? {
        guard apply else { return nil }
        if !report.failed.isEmpty {
            return "⚠ 有失敗記錄——**不得**升 store.yaml 的 format。修復上列失敗並重跑，"
                 + "failed 歸零後才進下一步"
        }
        if report.legacyLayout {
            return "下一步：本遷移是就地改寫（people/ 佈局不變）——先跑 akashic migrate "
                 + "搬移佈局到 entities（它會把 marker 設為 2），再 akashic doctor / "
                 + "validate。"
                 + StoreVersion.bumpHint(target: targetFormat, current: current)
        }
        return "下一步：akashic doctor 重建 index、akashic validate 驗證。"
             + StoreVersion.bumpHint(target: targetFormat, current: current)
    }

    /// 文字層取頂層 `key: ` 值（R3 NEW-1 的盲區偵測用）。
    ///
    /// **保守文法**（R4 NEW-R4-1）：只接受 canonical plain scalar——RHS 必須整段
    /// 落在 StoreKey 值域（`[a-z0-9][a-z0-9-]*`）。引號形（`"same-key"`）、行內
    /// 註解、tag、alias、任何其他 scalar 寫法一律回 nil；**多個** `key:` 行＝歧義
    /// 也回 nil。回 nil 的後果是 keyless → 全域抑制重發——寧可保守擋下，不可把
    /// 「引號包著的同 key」誤判成不同 key 而繞過裁決。CRLF 的行尾 `\r` 先剝。
    static func extractTopLevelKey(_ text: String) -> String? {
        var found: String?
        for raw in text.components(separatedBy: "\n") {
            var line = raw
            if line.hasSuffix("\r") { line = String(line.dropLast()) }
            // 候選掃描認 `key:` 前綴（**不含**空格）——R5 NEW-R5-1：空 RHS（`key:`）
            // 或 tab 分隔（`key:\t…`）的行也是頂層 key mapping，只認 `key: ` 會讓
            // 它們躲過歧義偵測、殘留 decoy 繞過。
            guard line.hasPrefix("key:") else { continue }
            let v = String(line.dropFirst(5))
            guard line.hasPrefix("key: "), StoreKey.isValid(v) else { return nil }
            if found != nil { return nil }                   // 重複 key: 行＝歧義 → keyless
            found = v
        }
        return found
    }

    /// 排程尾段：validate（R1 L2/S3）→ encode → 進 work 佇列。
    private static func scheduleWrite(_ person: Person, from c: Classified,
                                      entitiesMode: Bool, store: LibraryStore,
                                      work: inout [WorkItem], report: inout Report) {
        let errors = person.validate().filter { $0.severity == .error }
        guard errors.isEmpty else {
            let msgs = errors.prefix(3).map(\.message).joined(separator: "；")
            report.failed.append((file: c.relFile,
                reason: "記錄無法通過驗證（error 級），不落盤：\(msgs)"))
            return
        }
        do {
            let newText = try PersonYAML.encode(person)
            // entities 佈局：檔名 = id → 改名；legacy 佈局：檔名 = key → 就地覆寫。
            let dest = entitiesMode ? store.entityURL(id: person.id) : c.url
            work.append(WorkItem(key: person.key, url: c.url, relFile: c.relFile,
                                 newText: newText, dest: dest))
            report.migrated.append(person.key)
        } catch {
            let reason = (error as? LocalizedError)?.errorDescription ?? "\(error)"
            report.failed.append((file: c.relFile, reason: "re-encode 失敗：\(reason)"))
        }
    }

    // MARK: - 前置：git 回復路徑

    private static func assertWorktreeUsable(root: URL) throws {
        guard let inside = LibraryStore.git(["rev-parse", "--is-inside-work-tree"], in: root),
              inside.status == 0 else {
            throw MigrationError.noRecoveryPath(detail: "git rev-parse 失敗或非工作樹")
        }
        guard let status = LibraryStore.git(["status", "--porcelain"], in: root) else {
            throw MigrationError.noRecoveryPath(detail: "git status 無法執行")
        }
        let dirty = status.out.split(separator: "\n").prefix(5)
        guard dirty.isEmpty else {
            throw MigrationError.dirtyWorktree(detail: dirty.joined(separator: "、"))
        }
    }

    /// 被追蹤檔案集合（相對 store root，UTF-8 位元組）。R2 C4：寫入階段逐檔比對
    /// ——目錄級「有任何 tracked 檔」不構成任何**特定**檔案的回復保證。
    /// R3 NEW-2：以 Data 存（byte-exact）避開 String 的 canonical equivalence；
    /// 查詢失敗 throw——折成空集合雖 fail-safe，但會把「git 壞了」誤報成
    /// 「全部未追蹤」。
    private static func trackedFiles(root: URL, dirName: String) throws -> Set<Data> {
        guard let out = LibraryStore.git(["ls-files", "-z", "--", dirName], in: root),
              out.status == 0 else {
            throw MigrationError.noRecoveryPath(detail: "git ls-files 無法執行——無從確認追蹤狀態")
        }
        return Set(out.out.split(separator: "\0").map { Data($0.utf8) })
    }

    // MARK: - 形狀判定與摺疊

    /// person 檔判定：format ≥ 3 的裸 `person:` 標籤，或 format 2 的 `type: person`
    /// （R1 L7——只認裸標籤會把 format-2 檔靜默跳過，操作者 bump 後整批 quarantine）。
    static func isPersonShaped(_ text: String) -> Bool {
        text.split(separator: "\n").contains { $0 == "person:" || $0 == "type: person" }
    }

    /// 把 encoder-canonical 的平坦 `names:` 塊與兄弟 `authorized:` 塊摺成巢狀。
    ///
    /// 認兩種形：block sequence（頂格 `- ` 項目）與**簡單** flow（`names: [a, b]`，
    /// 無引號、無巢狀——R1 NEW-2）。其餘擲「無法辨識的寫法」並點名。
    /// **巢狀塊不會走到這裡**（呼叫端先以「補 id + 現行 decoder」處理，R2 C3）。
    /// 結果一律再過現行 decoder，錯的摺疊到不了磁碟。
    static func foldLegacyNames(_ text: String) throws -> String {
        var lines = text.components(separatedBy: "\n")

        func extractBlock(_ key: String) throws -> [String]? {
            // flow style：`key: [a, b]` 單行
            if let idx = lines.firstIndex(where: { $0.hasPrefix("\(key): [") }) {
                let raw = lines[idx].dropFirst("\(key): ".count)
                guard raw.hasSuffix("]"), !raw.contains("\""), !raw.contains("'"),
                      !raw.dropFirst().dropLast().contains("["), !raw.dropFirst().dropLast().contains("]") else {
                    throw StoreYAMLError.invalidField(
                        "person.\(displaySafeInvisible(key, max: 120))",
                        "無法辨識的 \(displaySafeInvisible(key, max: 120)) 寫法（帶引號或巢狀的 flow style）——"
                        + "請手動改為 block 形（每行一個「- 名字」）後重跑")
                }
                let items = raw.dropFirst().dropLast()
                    .components(separatedBy: ",")
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }
                guard !items.isEmpty else {
                    throw StoreYAMLError.invalidField(
                        "person.\(displaySafeInvisible(key, max: 120))", "flow style 的 \(displaySafeInvisible(key, max: 120)) 是空的——無法摺疊，請手動修復")
                }
                lines.remove(at: idx)
                return items
            }
            // block style：頂格鍵 + 頂格 `- ` 項目
            guard let start = lines.firstIndex(of: "\(key):") else { return nil }
            var items: [String] = []
            var end = start + 1
            while end < lines.count, lines[end].hasPrefix("- ") {
                items.append(String(lines[end].dropFirst(2)))
                end += 1
            }
            guard !items.isEmpty else {
                throw StoreYAMLError.invalidField(
                    "person.\(displaySafeInvisible(key, max: 120))",
                    "無法辨識的 \(displaySafeInvisible(key, max: 120)) 寫法（非 canonical 塊形）——請手動改為每行一個"
                    + "「- 名字」後重跑")
            }
            lines.removeSubrange(start..<end)
            return items
        }

        guard let names = try extractBlock("names") else {
            return lines.joined(separator: "\n")   // 無 names：交給 decoder 裁決
        }
        let authorized = try extractBlock("authorized") ?? []
        let variant = names.filter { !authorized.contains($0) }

        var nested = ["names:"]
        if !authorized.isEmpty {
            nested.append("  authorized:")
            nested += authorized.map { "  - \($0)" }
        }
        if !variant.isEmpty {
            nested.append("  variant:")
            nested += variant.map { "  - \($0)" }
        }
        lines = insertLines(nested, into: lines)
        return lines.joined(separator: "\n")
    }

    /// 插到 `key:` 行之後最靠近的頂層位置；canonical decode → encode 會重排成
    /// 正典順序，這裡只需合法即可。
    private static func insertLines(_ newLines: [String], into lines: [String]) -> [String] {
        var out = lines
        if let keyLine = out.firstIndex(where: { $0.hasPrefix("key: ") }) {
            out.insert(contentsOf: newLines, at: keyLine + 1)
        } else {
            out.insert(contentsOf: newLines, at: min(1, out.count))
        }
        return out
    }

    private static func insertLine(_ line: String, into text: String) -> String {
        insertLines([line], into: text.components(separatedBy: "\n")).joined(separator: "\n")
    }

    private static func uuidVersion(_ id: UUID) -> Int {
        Int(id.uuid.6 >> 4)
    }
}
