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
/// ## 原子性（design D5）
///
/// 每筆的順序固定：發新 id → **先寫新檔** → 刪舊檔。中斷留下的是**可偵測的重複**
/// （兩個檔、load 會報 key 重複），不是資料遺失；反過來先刪後寫，中斷即遺失。
///
/// ## 回復路徑（design D6）
///
/// 這次遷移不可逆（新 id 無法推回舊 id），所以 `apply: true` 要求 store 是 git
/// 工作樹**且乾淨**——git 即回復路徑；在 398 個未提交變更之上重寫 869 個檔名，
/// `git checkout` 救不回來。dry-run 不受此前置（report-only 沒有要回復的東西）。
///
/// ## 這裡繞過 `writePerson` 的 v10 gate——刻意的
///
/// gate 擋的是**日常寫入**把新形狀寫進舊 marker 的 store；本型別**就是**規格說的
/// 「舊形狀唯一的進入路徑」，寫入時 marker 還在舊值是它存在的前提。marker 的實際
/// bump 仍是使用者知情的動作（design Out of scope；遷移完成後依 store-format.md
/// v10 列的升級前置手動改）。
///
/// ## 誠實邊界
///
/// - 只支援 entities 佈局（format ≥ 2）。legacy 佈局先跑 `akashic migrate` 升佈局。
/// - 摺疊是**文字層**的（只認 encoder 產出的 canonical 塊形）：真 store 的 869 筆
///   全部由 encoder 寫出，塊形固定。手改成其他形（flow style、異常縮排）的檔案
///   會摺不動——**計入 failed 並點名**，不猜、不吞（轉換結果一律過現行 decoder
///   驗證，錯的摺疊到不了磁碟）。
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
        case legacyLayout
        case noRecoveryPath(detail: String)
        case dirtyWorktree(detail: String)

        public var errorDescription: String? {
            switch self {
            case .legacyLayout:
                return "store 是 legacy 佈局（people/<key>.yaml）——先跑 akashic migrate 升佈局，再跑本遷移"
            case .noRecoveryPath(let d):
                return "store 不在可用的 git 工作樹內（\(displaySafe(d, max: 200))）"
                     + "——本遷移不可逆，git 是它的回復路徑；先把 store 納入版控再 --apply"
            case .dirtyWorktree(let d):
                // d 是 git status 的路徑列——store 衍生內容，消毒後才可見
                return "store 工作樹有未提交變更——在其上重寫檔名會讓 git checkout 救不回來。"
                     + "請先 commit（或 stash）再 --apply。未提交的路徑：\(displaySafe(d, max: 400))"
            }
        }
    }

    /// 遍歷 store 的 person 記錄，回傳報告。`apply: false`（預設）零寫入。
    @discardableResult
    public static func run(store: LibraryStore, apply: Bool = false) throws -> Report {
        guard store.usesEntitiesLayout else { throw MigrationError.legacyLayout }
        if apply { try assertCleanWorktree(root: store.root) }

        var report = Report()
        let fm = FileManager.default
        let dir = store.entitiesDir
        let files = (try? fm.contentsOfDirectory(atPath: dir.path)) ?? []
        var work: [(key: String, url: URL, newText: String)] = []

        for file in files.sorted() where file.hasSuffix(".yaml") {
            let url = dir.appendingPathComponent(file)
            guard let text = try? String(contentsOf: url, encoding: .utf8) else {
                report.failed.append((file: "entities/\(file)", reason: "讀不出 UTF-8 內容"))
                continue
            }
            guard isPersonShaped(text) else { continue }   // work／org／divergence 不動

            if let current = try? PersonYAML.decode(text) {
                if uuidVersion(current.id) == 4 {
                    report.skipped.append(current.key)
                    continue
                }
                // 已是巢狀形狀但 id 仍是推導值（半套狀態）——只重發 id。
                var reissued = current
                reissued.id = UUID()
                do {
                    work.append((key: current.key, url: url,
                                 newText: try PersonYAML.encode(reissued)))
                    report.migrated.append(current.key)
                } catch {
                    report.failed.append((file: "entities/\(file)",
                                          reason: "re-encode 失敗：\(error)"))
                }
                continue
            }

            // 舊形狀：文字層摺疊 → 現行 decoder 驗證 → 重發 id → canonical encode。
            do {
                let folded = try foldLegacyNames(text)
                var person = try PersonYAML.decode(folded)
                person.id = UUID()
                work.append((key: person.key, url: url,
                             newText: try PersonYAML.encode(person)))
                report.migrated.append(person.key)
            } catch {
                let reason = (error as? LocalizedError)?.errorDescription ?? "\(error)"
                report.failed.append((file: "entities/\(file)", reason: reason))
            }
        }

        report.migrated.sort()
        report.skipped.sort()
        report.failed.sort { $0.file < $1.file }
        guard apply else { return report }

        for item in work {
            do {
                // 新檔名 = 新 id（decode 一定成功——newText 是剛 encode 的）
                let newID = try PersonYAML.decode(item.newText).id
                let dest = store.entityURL(id: newID)
                // 先寫後刪（D5）：中斷留下可偵測的重複，不是遺失
                try store.atomicWrite(item.newText, to: dest, mustCreate: true)
                if item.url != dest { try fm.removeItem(at: item.url) }
            } catch {
                report.migrated.removeAll { $0 == item.key }
                let reason = (error as? LocalizedError)?.errorDescription ?? "\(error)"
                report.failed.append((file: item.url.lastPathComponent, reason: reason))
            }
        }
        return report
    }

    // MARK: - 前置：git 回復路徑

    private static func assertCleanWorktree(root: URL) throws {
        guard let inside = LibraryStore.git(["rev-parse", "--is-inside-work-tree"],
                                                 in: root),
              inside.status == 0 else {
            // git 不可用或不在工作樹內——不可逆操作 fail-closed（同 #73 的方向）
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

    // MARK: - 形狀判定與摺疊

    /// 頂層是否有裸 `person:` 標籤（entities 佈局的形狀標示，format ≥ 3）。
    private static func isPersonShaped(_ text: String) -> Bool {
        text.split(separator: "\n").contains { $0 == "person:" }
    }

    /// 把 encoder-canonical 的平坦 `names:` 塊與兄弟 `authorized:` 塊摺成巢狀。
    ///
    /// 只認 canonical 塊形（頂格鍵、`- ` 項目頂格）：真 store 全部由 encoder 寫出。
    /// 其他形直接擲錯——結果一律再過現行 decoder，錯的摺疊到不了磁碟。
    static func foldLegacyNames(_ text: String) throws -> String {
        var lines = text.components(separatedBy: "\n")

        func extractBlock(_ key: String) throws -> [String]? {
            guard let start = lines.firstIndex(of: "\(key):") else { return nil }
            var items: [String] = []
            var end = start + 1
            while end < lines.count, lines[end].hasPrefix("- ") {
                items.append(String(lines[end].dropFirst(2)))
                end += 1
            }
            guard !items.isEmpty else {
                throw StoreYAMLError.invalidField(
                    "person.\(key)", "舊形狀的 \(key) 不是 canonical 塊形，無法自動摺疊——請手動修復後重跑")
            }
            lines.removeSubrange(start..<end)
            return items
        }

        guard let names = try extractBlock("names") else { return text }   // 無 names：交給 decoder 裁決
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
        // 摺疊後的塊放回原 names 的位置之後最靠近的頂層位置——直接 append 到 key 行後：
        // canonical decode → encode 會重排成正典順序，這裡只需合法即可。
        if let keyLine = lines.firstIndex(where: { $0.hasPrefix("key: ") }) {
            lines.insert(contentsOf: nested, at: keyLine + 1)
        } else {
            lines.insert(contentsOf: nested, at: min(1, lines.count))
        }
        return lines.joined(separator: "\n")
    }

    private static func uuidVersion(_ id: UUID) -> Int {
        Int(id.uuid.6 >> 4)
    }
}
