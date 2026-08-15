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
/// ## 涵蓋的舊形狀（#227 verify R1 起——遷移是舊形狀**唯一**的進入路徑，所以它的
/// 涵蓋面必須是封閉列舉，缺一格就是一格的死路）
///
/// | 舊形狀 | 處置 |
/// |---|---|
/// | entities 佈局、`person:` 裸標籤（format ≥ 3） | 摺疊 + 重發 id + 改檔名 |
/// | entities 佈局、`type: person`（format 2） | 同上（#227 verify L7——先前靜默跳過） |
/// | legacy 佈局 `people/<key>.yaml`（format 1） | 摺疊 + 補發 id **就地寫回**（檔名即 key，
///   不改名）；佈局搬移仍由 `akashic migrate` 做（#227 verify F2——先前三方循環無出口） |
/// | 檔上缺 `id:` | 補發新 v4（spec `record-identity` 允許的 one-time backfill；
///   反正本遷移就是要重發） |
/// | `names: [a, b]` flow style | 摺疊（僅限無引號的簡單純量；其餘計入 failed 並
///   點名「無法辨識的 names 寫法」——不再讓 decoder 的泛用訊息形成循環建議，
///   #227 verify NEW-2） |
/// | 已是巢狀但 id 非 v4（半套） | 只重發 id |
/// | 已是巢狀且 id 是 v4 | 跳過（含平坦 names＋v4 id 的半套檔：**保留**其 id 只摺
///   names，#227 verify L8） |
///
/// ## 原子性（design D5）
///
/// 每筆的順序固定：發新 id → **先寫新檔** → 刪舊檔。中斷留下的是**可偵測的重複**
/// （兩個檔、同 key），不是資料遺失。**重跑收斂**（#227 verify L6）：掃描先收集
/// 已是新形的 key，舊形檔的 key 撞上即計入 failed 點名「中斷殘留的重複」，不再
/// 發第三個 id。
///
/// ## 回復路徑（design D6）
///
/// `apply: true` 要求 store 是 git 工作樹、**乾淨**、且內容**實際被追蹤**
/// （#227 verify S2：`status --porcelain` 不列 ignored 檔，`rev-parse` 對 ignored
/// 子目錄照樣回 true——兩道閘都過而 git 根本救不回來。誠實邊界與
/// `isInsideVersionedWorkTree` 同款，這裡機械檢查而不只註記）。dry-run 不受此前置。
///
/// ## 寫入邊界（#227 verify L2/S3）
///
/// 本型別繞過 `writePerson` 的 v10 gate（它**就是**規格說的舊形狀唯一進入路徑，
/// marker 還在舊值是它存在的前提；marker 的實際 bump 仍是使用者知情的動作），
/// 但**不**繞過 `Person.validate()`——`.error` 級的記錄（同書寫系統兩個 authorized、
/// 分割重疊…）計入 failed 並點名，不落盤。「每條寫入路徑都擋」對遷移同樣成立。
public enum PersonIdentityMigration {

    public struct Report: Equatable {
        /// 本輪（將）遷移的 person key，依字典序。
        public var migrated: [String] = []
        /// 已是新形狀（現行 decoder 可讀且 id 為 v4）而跳過的 key。
        public var skipped: [String] = []
        /// 處理失敗的檔與原因。單筆失敗不中止整批。
        public var failed: [(file: String, reason: String)] = []

        public static func == (a: Report, b: Report) -> Bool {
            a.migrated == b.migrated && a.skipped == b.skipped
                && a.failed.elementsEqual(b.failed, by: { $0 == $1 })
        }
    }

    public enum MigrationError: LocalizedError {
        case noRecoveryPath(detail: String)
        case dirtyWorktree(detail: String)
        case untrackedContent(detail: String)

        public var errorDescription: String? {
            switch self {
            case .noRecoveryPath(let d):
                return "store 不在可用的 git 工作樹內（\(displaySafe(d, max: 200))）"
                     + "——本遷移不可逆，git 是它的回復路徑；先把 store 納入版控再 --apply"
            case .dirtyWorktree(let d):
                // d 是 git status 的路徑列——store 衍生內容，消毒後才可見
                return "store 工作樹有未提交變更——在其上重寫檔名會讓 git checkout 救不回來。"
                     + "請先 commit（或 stash）再 --apply。未提交的路徑：\(displaySafe(d, max: 400))"
            case .untrackedContent(let d):
                return "store 的 person 檔未被 git 追蹤（\(displaySafe(d, max: 200))）——"
                     + "工作樹「乾淨」對被 ignore 的內容是空話，刪掉的舊檔 git 救不回。"
                     + "先 git add + commit（或修 .gitignore）再 --apply"
            }
        }
    }

    /// 待處理項：掃描階段產出、寫入階段消費。
    private struct WorkItem {
        var key: String
        var url: URL
        var newText: String
        /// 新檔位置；與 `url` 相同代表就地覆寫（legacy 佈局）。
        var dest: URL
    }

    /// 遍歷 store 的 person 記錄，回傳報告。`apply: false`（預設）零寫入。
    @discardableResult
    public static func run(store: LibraryStore, apply: Bool = false) throws -> Report {
        var report = Report()
        let fm = FileManager.default

        // 掃描來源：entities 佈局掃 entities/、legacy 佈局掃 people/（該目錄依佈局
        // 定義只放 person，無需形狀標籤）。
        let entitiesMode = store.usesEntitiesLayout
        let dir = entitiesMode ? store.entitiesDir : store.peopleDir
        let files = ((try? fm.contentsOfDirectory(atPath: dir.path)) ?? [])
            .filter { $0.hasSuffix(".yaml") }.sorted()
        if apply {
            try assertRecoverable(root: store.root, contentDir: dir, hasFiles: !files.isEmpty)
        }

        // ── 第一段：掃描與分類（零寫入）──
        // 先收全部檔的解讀結果，才能做 key 級的收斂判斷（L6：重跑不得發第三個 id）。
        var work: [WorkItem] = []
        var newShapeKeys = Set<String>()          // 已是 v4+巢狀 的 key
        var pendingLegacy: [(file: String, url: URL, text: String)] = []

        for file in files {
            let url = dir.appendingPathComponent(file)
            let relFile = entitiesMode ? "entities/\(file)" : "people/\(file)"
            guard let text = try? String(contentsOf: url, encoding: .utf8) else {
                report.failed.append((file: relFile, reason: "讀不出 UTF-8 內容"))
                continue
            }
            if entitiesMode {
                guard isPersonShaped(text) else { continue }   // work／org／divergence 不動
            }

            if let current = try? PersonYAML.decode(text) {
                if uuidVersion(current.id) == 4 {
                    report.skipped.append(current.key)
                    newShapeKeys.insert(current.key)
                    continue
                }
                // 已是巢狀形狀但 id 仍是推導值（半套狀態）——只重發 id。
                var reissued = current
                reissued.id = UUID()
                appendValidated(reissued, url: url, relFile: relFile,
                                entitiesMode: entitiesMode, store: store,
                                work: &work, report: &report)
                continue
            }
            pendingLegacy.append((file: relFile, url: url, text: text))
        }

        for item in pendingLegacy {
            do {
                var folded = try foldLegacyNames(item.text)
                // 缺 id：補發（one-time backfill——本遷移本來就要重發 id；先給一個
                // 佔位讓 decoder 過，實際值在下方統一決定）。
                if !folded.components(separatedBy: "\n").contains(where: { $0.hasPrefix("id: ") }) {
                    folded = insertLine("id: \(UUID().uuidString)", into: folded)
                }
                var person = try PersonYAML.decode(folded)
                // L6 收斂：同 key 的新形檔已存在＝中斷殘留，不得再發 id 製造第三份。
                if newShapeKeys.contains(person.key) {
                    report.failed.append((file: item.file,
                        reason: "重複（中斷殘留）：同 key「\(person.key)」的新形檔已存在——"
                              + "請人工確認內容一致後刪除本舊檔，不自動裁決"))
                    continue
                }
                // L8：半套檔若已持有獨立 v4 id，保留之（spec：already independent →
                // left unchanged）；否則重發。
                if uuidVersion(person.id) != 4 { person.id = UUID() }
                appendValidated(person, url: item.url, relFile: item.file,
                                entitiesMode: entitiesMode, store: store,
                                work: &work, report: &report)
            } catch {
                let reason = (error as? LocalizedError)?.errorDescription ?? "\(error)"
                report.failed.append((file: item.file, reason: reason))
            }
        }

        report.migrated.sort()
        report.skipped.sort()
        report.failed.sort { $0.file < $1.file }
        guard apply else { return report }

        // ── 第二段：寫入（先寫後刪，D5）──
        for item in work {
            do {
                try store.atomicWrite(item.newText, to: item.dest,
                                      mustCreate: item.dest != item.url)
            } catch {
                // 未寫入的失敗：記錄保持原狀（spec：left in its prior state）
                if let idx = report.migrated.firstIndex(of: item.key) {
                    report.migrated.remove(at: idx)   // 只移一筆——同 key 多檔時不誤刪計數（S7）
                }
                let reason = (error as? LocalizedError)?.errorDescription ?? "\(error)"
                report.failed.append((file: item.url.lastPathComponent,
                                      reason: "寫入新檔失敗（記錄未動）：\(reason)"))
                continue
            }
            if item.dest != item.url {
                do { try fm.removeItem(at: item.url) } catch {
                    // F6：新檔已寫成、舊檔刪不掉——磁碟是「可偵測的重複」不是原狀，
                    // report 必須說清楚，不得偽稱失敗未動。
                    let reason = (error as? LocalizedError)?.errorDescription ?? "\(error)"
                    report.failed.append((file: item.url.lastPathComponent,
                        reason: "新檔已寫入（\(item.dest.lastPathComponent)）、舊檔刪除失敗"
                              + "——目前新舊並存，請手動刪除舊檔：\(reason)"))
                }
            }
        }
        return report
    }

    /// 掃描階段的共同尾段：validate（L2/S3——遷移不繞過寫入不變式）→ encode → 排程。
    private static func appendValidated(_ person: Person, url: URL, relFile: String,
                                        entitiesMode: Bool, store: LibraryStore,
                                        work: inout [WorkItem], report: inout Report) {
        let errors = person.validate().filter { $0.severity == .error }
        guard errors.isEmpty else {
            let msgs = errors.prefix(3).map(\.message).joined(separator: "；")
            report.failed.append((file: relFile,
                reason: "記錄無法通過驗證（error 級），不落盤：\(msgs)"))
            return
        }
        do {
            let newText = try PersonYAML.encode(person)
            // entities 佈局：檔名 = id → 改名；legacy 佈局：檔名 = key → 就地覆寫。
            let dest = entitiesMode ? store.entityURL(id: person.id) : url
            work.append(WorkItem(key: person.key, url: url, newText: newText, dest: dest))
            report.migrated.append(person.key)
        } catch {
            let reason = (error as? LocalizedError)?.errorDescription ?? "\(error)"
            report.failed.append((file: relFile, reason: "re-encode 失敗：\(reason)"))
        }
    }

    // MARK: - 前置：git 回復路徑（乾淨 + 實際被追蹤）

    private static func assertRecoverable(root: URL, contentDir: URL, hasFiles: Bool) throws {
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
        // S2：乾淨 ≠ 可回復。被 ignore 的內容不出現在 porcelain，刪了 git 也救不回
        // ——有檔案卻零追蹤即拒絕。
        if hasFiles {
            let dirName = contentDir.lastPathComponent
            guard let tracked = LibraryStore.git(["ls-files", "--", dirName], in: root),
                  tracked.status == 0, !tracked.out.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw MigrationError.untrackedContent(detail: "git ls-files \(dirName) 為空")
            }
        }
    }

    // MARK: - 形狀判定與摺疊

    /// person 檔判定：format ≥ 3 的裸 `person:` 標籤，或 format 2 的 `type: person`
    /// （#227 verify L7——只認裸標籤會把 format-2 檔靜默跳過，操作者 bump 後整批
    /// quarantine）。
    static func isPersonShaped(_ text: String) -> Bool {
        text.split(separator: "\n").contains { $0 == "person:" || $0 == "type: person" }
    }

    /// 把 encoder-canonical 的平坦 `names:` 塊與兄弟 `authorized:` 塊摺成巢狀。
    ///
    /// 認兩種形：block sequence（頂格 `- ` 項目）與**簡單** flow（`names: [a, b]`，
    /// 無引號、無巢狀——#227 verify NEW-2）。其餘擲「無法辨識的寫法」並點名，
    /// 不讓 decoder 的泛用訊息形成循環建議。結果一律再過現行 decoder，錯的摺疊
    /// 到不了磁碟。
    static func foldLegacyNames(_ text: String) throws -> String {
        var lines = text.components(separatedBy: "\n")

        func extractBlock(_ key: String) throws -> [String]? {
            // flow style：`key: [a, b]` 單行
            if let idx = lines.firstIndex(where: { $0.hasPrefix("\(key): [") }) {
                let raw = lines[idx].dropFirst("\(key): ".count)
                guard raw.hasSuffix("]"), !raw.contains("\""), !raw.contains("'"),
                      !raw.dropFirst().dropLast().contains("["), !raw.dropFirst().dropLast().contains("]") else {
                    throw StoreYAMLError.invalidField(
                        "person.\(key)",
                        "無法辨識的 \(key) 寫法（帶引號或巢狀的 flow style）——"
                        + "請手動改為 block 形（每行一個「- 名字」）後重跑")
                }
                let items = raw.dropFirst().dropLast()
                    .components(separatedBy: ",")
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }
                guard !items.isEmpty else {
                    throw StoreYAMLError.invalidField(
                        "person.\(key)", "flow style 的 \(key) 是空的——無法摺疊，請手動修復")
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
                    "person.\(key)",
                    "無法辨識的 \(key) 寫法（非 canonical 塊形）——請手動改為每行一個"
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
