import Foundation
import AkashicCore
import AkashicStoreIO

public struct ImportReport: Equatable {
    public var created: [String] = []
    public var updated: [String] = []
    public var orphaned: [String] = []
    /// Zotero 端復原、orphan 標記被清除的 entries。
    public var orphanCleared: [String] = []
    public var unchanged: Int = 0
    /// 解析過的作者被保留、未跟 Zotero 同步的 entries（資訊性）。
    public var authorsPreserved: [String] = []
    /// 未映射而被捨棄的 Zotero 欄位（欄位名 → 出現次數）。不靜默流失。
    /// 以**正規化後的原名**入庫的欄位（無 canonical 對照）。
        /// #206 之前這叫 `droppedFields` 且真的丟掉；現在會入庫，名字跟著改，
        /// 否則報告會說謊（verify H2）。
        public var residualFields: [String: Int] = [:]
        /// pull 覆寫掉的**未歸戶** literal 作者（#208）。已歸戶的 `.key` 走
        /// `authorsPreserved`，永不被覆寫。
        public var authorsOverwritten: [String] = []
        /// pull **移除**的欄位名 → 次數（#208）。成因是 `applyBiblatexFields`
        /// 整份替換 `fields`：Zotero 這次沒給的欄位會消失，包含使用者手工補的。
        public var fieldsRemovedByPull: [String: Int] = [:]
    /// 寫入目的檔是 quarantined 檔而被拒寫的 citekeys（損壞 store，人工處理）。
    public var quarantineConflicts: [String] = []
    /// 寫入時 encode/寫檔擲錯的 citekeys → 錯誤描述（R6 M9：encode 自 v1.3 起
    /// 可 throw——canary fail-closed；per-item 隔離，單筆失敗不中斷整趟 import、
    /// 不留半套用狀態，index 照常 rebuild）。
    public var writeFailed: [String: String] = [:]
    /// date 無法正規化、保留原字串的 citekeys（#2）。
    public var unnormalizedDates: [String] = []
    /// 被略過的 linked / URL 附件數（#3，不靜默）。
    public var skippedLinkedAttachments: Int = 0

    public init() {}
}

/// Zotero → Akashic 單向 pull。
///
/// Diff 規則（spec §6.1）：
/// - 新 zotero_key → 建新 entry（citekey 生成、UUID 配發、tags seed）
/// - 已有 key 且 Zotero 版本較新 → 只更新 biblatex 欄位 + provenance；akashic 不動
/// - store 有、Zotero 已刪 → 標 orphaned（不自動刪，人工裁決）
/// - 版本相同 → unchanged
public struct ZoteroImporter {
    let store: LibraryStore

    public init(store: LibraryStore) {
        self.store = store
    }

    public func run(zoteroDB: URL, libraryID: Int? = nil, now: Date = Date()) throws -> ImportReport {
        let readResult = try ZoteroReader.readItems(dbPath: zoteroDB.path, libraryID: libraryID)
        let items = readResult.items
        let load = try store.load()
        // #304：venue 派生 gate——format < 11 的 store 表達不了 `venues`（writeEntry
        // 會拒），匯入不派生。**這不是有損**：journaltitle 等字串照樣進 `fields`，
        // bump 後 `migrate-venues` 從那裡冪等回填。讀不到 format 視同不具備（保守側）。
        let venueCapable = ((try? StoreVersion.read(root: store.root)) ?? 0) >= 11

        var report = ImportReport()
        report.skippedLinkedAttachments = readResult.skippedLinkedAttachments
        // 身分＝(libraryID, zoteroKey) 複合鍵（#3）；legacy 檔（library_id 缺）另建裸 key 索引，
        // 首次匹配時 backfill libraryID。
        var byCompositeKey: [String: Entry] = [:]
        var legacyByBareKey: [String: Entry] = [:]
        var existingCitekeys = Set<String>()
        for entry in load.entries {
            existingCitekeys.insert(entry.citekey)
            guard let prov = entry.provenance else { continue }
            if let lid = prov.libraryID {
                byCompositeKey["\(lid):\(prov.zoteroKey)"] = entry
            } else {
                legacyByBareKey[prov.zoteroKey] = entry
            }
        }
        // quarantined 檔的 basename 佔住 citekey——否則新 entry 生成同名 key
        // 時會覆寫使用者的（暫時損壞的）檔案。這是 canonical data-loss 防線。
        // lowercase 比對：macOS 檔案系統常見 case-insensitive，大寫 basename
        // 與 lowercase citekey 仍指向同一檔案。
        var quarantinedBasenames = Set<String>()
        for q in load.quarantined where q.file.hasPrefix("entries/") {
            // 整個檔名先 lowercase 再判斷副檔名——`.YAML`/`.YaMl` 變體同樣是
            // 寫入目的檔在 case-insensitive FS 上的別名
            let basename = String(q.file.dropFirst("entries/".count)).lowercased()
            if basename.hasSuffix(".yaml") {
                let stem = String(basename.dropLast(".yaml".count))
                quarantinedBasenames.insert(stem)
                existingCitekeys.insert(stem)
            }
        }
        // 每一次寫入前的 destination guard：目的檔屬 quarantined 集合 → 拒寫、報告。
        // 不能只靠 citekey allocator——update/orphan 路徑不經 allocator。
        // R6（M9）：寫入擲錯（encode canary fail-closed、I/O 失敗）→ 記入
        // writeFailed、續跑下一筆——不讓單一病態檔把整趟 import 打斷成
        // 「部分套用 + index 未重建」的撕裂狀態。
        func guardedWrite(_ entry: Entry, report: inout ImportReport) -> Bool {
            if quarantinedBasenames.contains(entry.citekey.lowercased()) {
                if !report.quarantineConflicts.contains(entry.citekey) {
                    report.quarantineConflicts.append(entry.citekey)
                }
                return false
            }
            do {
                try store.writeEntry(entry)
                return true
            } catch {
                report.writeFailed[entry.citekey] = String(describing: error)
                return false
            }
        }

        let importedComposite = Set(items.map { "\($0.libraryID):\($0.key)" })
        let importedBare = Set(items.map(\.key))
        var legacyMatched = Set<String>()   // 已被 item 認領的 legacy 裸 key

        for item in items {
            for residual in ZoteroMapping.residualFields(of: item) {
                report.residualFields[residual, default: 0] += 1
            }
            let itemHash = ZoteroMapping.mappingHash(of: item)
            var matched = byCompositeKey["\(item.libraryID):\(item.key)"]
            if matched == nil, let legacy = legacyByBareKey[item.key], !legacyMatched.contains(item.key) {
                // 歧義防線：同 bare key 已被「其他 library」的 composite entry 持有
                // → legacy 檔歸屬不明，scoped/全量都不認領（留待人工或全量 backfill 釐清）
                let claimedByOtherLibrary = byCompositeKey.keys.contains {
                    $0.hasSuffix(":\(item.key)") && $0 != "\(item.libraryID):\(item.key)"
                }
                if !claimedByOtherLibrary {
                    matched = legacy
                    legacyMatched.insert(item.key)
                }
            }
            if var existing = matched {
                guard let prov = existing.provenance else { continue }
                // Zotero 端存在＝非 orphan：不論版本，先清 orphan 標記（存在性獨立於版本比較）
                var orphanWasCleared = false
                var restoreWasBlocked = false
                if prov.orphanedAt != nil {
                    var restored = existing
                    restored.provenance?.orphanedAt = nil
                    if guardedWrite(restored, report: &report) {
                        existing = restored
                        report.orphanCleared.append(existing.citekey)
                        orphanWasCleared = true
                    } else {
                        restoreWasBlocked = true   // 需要變更但被擋 ≠ 無需變更
                    }
                }
                // update 條件（Phase 2）：version 較新 OR mapping hash 不同
                // （hash 缺席＝pre-Phase-2 舊檔 → 視為不同、補建一次）
                if item.version > prov.zoteroVersion || prov.zoteroHash != itemHash {
                    let hadResolvedAuthors = existing.authors.contains {
                        if case .key = $0 { return true } else { return false }
                    }
                    // **記下 pull 會蓋掉什麼**（#208）。`applyBiblatexFields` 整份
                    // 替換 `fields`，所以 Zotero **這次沒給**的欄位會消失——包含
                    // 使用者手工補的、或別的 importer 寫的。Zotero 對它沒給的欄位
                    // 沒有意見，卻因為整份替換而等同刪除了它們。
                    //
                    // 這個行為不是本 change 引入的，但 #206 讓 update 分支大範圍
                    // 觸發，於是它從「偶爾」變成「下一次匯入就會發生」。
                    // 先讓它**可見**——靜默才是真正的問題。
                    let fieldsBefore = Set(existing.fields.keys)
                    // **識別碼的移除也要可見**（#394 verify R4 ④）。
                    //
                    // 它們自 §4 起住結構化欄位，於是下面那個 `fields` 的減法看不到它們
                    // ——同一件事（Zotero 這次沒給、pull 因此清掉）從**有回報**變成**零回報**。
                    // 本輪 4 個修復裡，那是唯一拆掉既有回報通道的一個。這裡把它接回來。
                    let identifiersBefore = Set(["doi", "pmid", "isbn"].filter {
                        !(existing.identifierList($0)?.isEmpty ?? true)
                    })
                    let authorsBefore = existing.authors
                    ZoteroMapping.applyBiblatexFields(from: item, to: &existing)
                    if !venueCapable { existing.venues = [] }
                    let removed = fieldsBefore.subtracting(existing.fields.keys).sorted()
                    for k in removed { report.fieldsRemovedByPull[k, default: 0] += 1 }
                    let identifiersAfter = Set(["doi", "pmid", "isbn"].filter {
                        !(existing.identifierList($0)?.isEmpty ?? true)
                    })
                    for k in identifiersBefore.subtracting(identifiersAfter).sorted() {
                        report.fieldsRemovedByPull[k, default: 0] += 1
                    }
                    if hadResolvedAuthors {
                        // 解析成果（person key）是使用者確認過的衍生知識，pull 不摧毀
                        report.authorsPreserved.append(existing.citekey)
                    } else {
                        let after = item.authors.map { AkashicCore.Author.literal($0.display) }
                        // 未歸戶的 literal 作者會被 Zotero 版本覆寫。那是 pull-based
                        // sync 的正常語意（Zotero 是上游），但**與 import-wos 相反**
                        // ——後者對任何內容分歧一律拒絕覆寫。使用者跑兩個命令會得到
                        // 相反的資料保護等級，所以至少要說出來。
                        if after != authorsBefore { report.authorsOverwritten.append(existing.citekey) }
                        existing.authors = after
                    }
                    existing.provenance = Provenance(
                        zoteroKey: item.key, zoteroVersion: item.version,
                        libraryID: item.libraryID, zoteroHash: itemHash,
                        importedAt: now, orphanedAt: nil)
                    if guardedWrite(existing, report: &report) {
                        report.updated.append(existing.citekey)
                        if let raw = item.fields["date"], DateNormalizer.normalize(raw) == nil {
                            report.unnormalizedDates.append(existing.citekey)
                        }
                    }
                } else if !orphanWasCleared && !restoreWasBlocked {
                    report.unchanged += 1
                }
            } else {
                let citekey = Citekey.generate(
                    familyName: item.authors.first?.family,
                    year: item.fields["date"],
                    title: item.fields["title"],
                    existing: existingCitekeys)
                existingCitekeys.insert(citekey)
                var entry = Entry(id: UUID(), citekey: citekey, type: .webpage, title: "")
                ZoteroMapping.applyBiblatexFields(from: item, to: &entry)
                if !venueCapable { entry.venues = [] }
                entry.authors = item.authors.map { .literal($0.display) }
                entry.provenance = Provenance(
                    zoteroKey: item.key, zoteroVersion: item.version,
                    libraryID: item.libraryID, zoteroHash: itemHash, importedAt: now)
                entry.akashic.tags = item.tags   // 只在建檔時 seed；後續 pull 不動
                if guardedWrite(entry, report: &report) {
                    report.created.append(citekey)
                    if let raw = item.fields["date"], DateNormalizer.normalize(raw) == nil {
                        report.unnormalizedDates.append(citekey)
                    }
                }
            }
        }

        // Orphan 偵測（library-scoped，#3）：只在「本次 import 的視野涵蓋該 entry 的 library」
        // 時才可判 orphan——部分 import（指定 libraryID）絕不動其他 library 的 entries；
        // legacy 檔（library_id 缺）只在全庫 import（libraryID=nil）時以裸 key 判定。
        for entry in load.entries {
            guard var prov = entry.provenance, prov.orphanedAt == nil else { continue }
            if let lid = prov.libraryID {
                if let wanted = libraryID, lid != wanted { continue }   // 視野外，不動
                if importedComposite.contains("\(lid):\(prov.zoteroKey)") { continue }
            } else {
                if libraryID != nil { continue }   // 部分 import 不裁決 legacy 檔
                if importedBare.contains(prov.zoteroKey) { continue }
            }
            var orphan = entry
            prov.orphanedAt = now
            orphan.provenance = prov
            if guardedWrite(orphan, report: &report) {
                report.orphaned.append(orphan.citekey)
            }
        }

        report.created.sort()
        report.updated.sort()
        report.orphaned.sort()
        report.orphanCleared.sort()
        report.authorsPreserved.sort()
        report.authorsOverwritten.sort()
        report.quarantineConflicts.sort()
        report.unnormalizedDates.sort()
        return report
    }
}
