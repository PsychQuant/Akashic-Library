import Foundation
import AkashicCore
import AkashicStoreIO

public struct ImportReport: Equatable {
    public var created: [String] = []
    public var updated: [String] = []
    /// #694：**主來源**的 mapping hash 與存下的不同，而 Zotero 那一列說這個條目已同步（`synced` = 1）、`version` > 0 且與存下的相同
    /// （判準是 `ZoteroImporter.isHashOnlyDifference`，與 `secondarySourceHashOnly` 同一份）。書目欄位**照常改寫**——寫入與 `updated`
    /// 那一格完全相同（同一段程式、同一份內容），這一格只改報告的分類，不改這一趟寫不寫、寫什麼。
    ///
    /// **只說觀察到的事實、不排原因**：可能是 mapping 定義改了，也可能是子項附件的增減（子項有自己的 version，不推進父條目的）——報告分不出是哪一個。
    /// 它分出來的用處是 mapping 定義一演進，每一筆主來源不再全被列成 `updated`。
    ///
    /// 其餘一律留在 `updated`：`version` 前進或倒退；`synced` 為 0（有本機修改還沒同步——`version` 只在同步時才變）；`version` 是 0
    /// （從未同步的 library，每個條目都是 0）；資料庫沒有 `synced` 欄（無從判斷）；沒有舊 hash（pre-Phase-2，無從比較）；
    /// `version` 前進而 hash 相同也照舊改寫、列在 `updated`。
    public var updatedHashOnly: [String] = []
    public var orphaned: [String] = []
    /// Zotero 端復原、orphan 標記被清除的 entries。
    public var orphanCleared: [String] = []
    /// #605：附加來源在 Zotero 端有變（內容 hash 不同、且 Zotero 的 version 前進或倒退——或沒有舊 hash 而 version 較新），
    /// 但依「只有主來源更新書目欄位」**未套用**的 entries。不靜默——使用者要能看到群組那份被別人改過。
    ///
    /// **不含 `secondarySourceHashOnly` 那一種**（#608）：hash 不同、而 Zotero 那一列已同步且 `version` 沒變。
    /// 兩者先前報在同一格，於是 mapping 定義一演進（`ZoteroMapping.mappingHash` 的注解記著這是刻意的、可見的大批更新），
    /// 每個附加來源都被列成「有人改了」。hash 不同而 `synced` 為 0、`version` 為 0 或沒有 `synced` 欄時仍在這一格（#608 verify R1）。
    public var secondarySourceChanged: [String] = []
    /// #608：附加來源的 mapping hash 與存下的不同，而 Zotero 那一列說這個條目已同步（`synced` = 1）、`version` > 0 且與存下的相同
    /// （`ZoteroImporter.isHashOnlyDifference`，與 `updatedHashOnly` 同一份判準）。**只說觀察到的事實、不排原因**：可能是 mapping 定義改了，
    /// 也可能是它涵蓋的子項（附件）集合有增減（子項有自己的 version，不推進父條目的）。兩者在附加來源上分不開：附加來源不存附件清單，
    /// hash 是單一雜湊，舊版 mapping 與舊內容都不在手邊、無從重算舊 hash。
    ///
    /// **#608 verify R1 更正**：初版只看「version 沒變」，並把它說成「Zotero 端沒有人改這個條目」。但 Zotero 的 `version` 只在同步時才變——
    /// 還沒同步的本機修改 `synced` = 0、`version` 不動；從未同步的 library 每個條目的 `version` 都是 0——這兩種在初版都被報成「只有 hash 不同」，
    /// 而 #608 之前它們在 `secondarySourceChanged`。現在它們回到那一格。
    /// 本地的 hash 已重算存回，下一趟不會再列。書目欄位同樣**未套用**（只有主來源更新書目欄位）。
    public var secondarySourceHashOnly: [String] = []
    /// #605：附加來源在 Zotero 端已刪除、被標上 `orphaned_at` 的 entries（entry 本身與主來源不動）。
    public var secondarySourceOrphaned: [String] = []
    /// #605：附加來源在 Zotero 端恢復、`orphaned_at` 被清除的 entries。與 `orphanCleared`
    /// 分開——後者的意思是整筆 entry 的主連結恢復。
    public var secondarySourceRestored: [String] = []
    /// #610：同一個 Zotero 來源被多筆 entry 宣稱（主來源或附加來源都算）→ 宣稱它的 citekeys（排序）。
    /// 鍵是 `<library_id>:<zotero_key>`；兩筆以上**沒記 library_id** 的舊檔宣稱同一個裸 key 時是 `?:<zotero_key>`。
    /// 這些條目本趟**不更新任何一筆書目欄位、也不新建**——路由分不出是哪一筆，猜錯會把一筆的書目欄位寫進另一筆。
    /// 但 orphan 標記照常處理（#682）：Zotero 端刪除時各宣稱者都被標（偵測迴圈逐筆看每一筆自己的來源）、復原時各宣稱者的標記都清
    /// （清掉的列在 `orphanCleared`／`secondarySourceRestored`）——「item 在不在」不需要先判定哪一筆是正主。
    /// **一個保守的例外**：`?:<zotero_key>`（沒記 library_id 的舊檔）那一桶只在歸屬沒有爭議——沒有別的 library 持有同一個裸 key——時才清
    /// （與單一舊檔認領同一個條件，#607），別的 library 也持有它時標記留著。這是刻意的保守，不是比實作寬的承諾。
    public var ambiguousSourceClaims: [String: [String]] = [:]
    public var unchanged: Int = 0
    /// 解析過的作者被保留、未跟 Zotero 同步的 entries（資訊性）。只記寫入成功的那一筆（#702）。
    public var authorsPreserved: [String] = []
    /// 未映射而被捨棄的 Zotero 欄位（欄位名 → 出現次數）。不靜默流失。
    /// 以**正規化後的原名**入庫的欄位（無 canonical 對照）。
        /// #206 之前這叫 `droppedFields` 且真的丟掉；現在會入庫，名字跟著改，
        /// 否則報告會說謊（verify H2）。
        /// **計數的時機是讀進每個 Zotero 條目時**，不論這一趟有沒有寫（含未變動、被多筆宣稱而略過、寫入失敗的條目）——
        /// 它說的是「讀到的條目帶哪些未對映欄位」，對寫入失敗的那一筆「入庫」兩個字不成立（#702 R1 verify）。
        public var residualFields: [String: Int] = [:]
        /// pull 覆寫掉的**未歸戶** literal 作者（#208）。已歸戶的 `.key` 走
        /// `authorsPreserved`，永不被覆寫。只記寫入成功的那一筆——寫不進去的只在 `writeFailed`／`quarantineConflicts`（#702）。
        public var authorsOverwritten: [String] = []
        /// pull **移除**的欄位名 → 次數（#208）。成因是 `applyBiblatexFields`
        /// 整份替換 `fields`：Zotero 這次沒給的欄位會消失，包含使用者手工補的。只算寫入成功的那幾筆（#702）。
        public var fieldsRemovedByPull: [String: Int] = [:]
    /// 寫入目的檔是 quarantined 檔而被拒寫的 citekeys（損壞 store，人工處理）。
    public var quarantineConflicts: [String] = []
    /// 寫入時 encode/寫檔擲錯的 citekeys → 錯誤描述（R6 M9：encode 自 v1.3 起
    /// 可 throw——canary fail-closed；per-item 隔離，單筆失敗不中斷整趟 import、
    /// 不留半套用狀態，index 照常 rebuild）。**記的是沒有套用的那一步**：內容已寫進 `entities/`、只有搬移後的 legacy 檔沒刪掉的
    /// 那一步在 `writtenWithLegacyCopy`（#705；#702 曾讓它同時在這裡）。同一筆在同一趟之後的步驟被 #631 拒絕（兩份並存）時，
    /// 這裡另記一則、訊息說出前一步已寫入（#702 R2 verify）；同一筆有不只一則時以「；」串接，不覆寫。
    public var writeFailed: [String: String] = [:]
    /// 內容已寫進 `entities/`、#631 搬移後的 legacy 拷貝沒刪掉的 entries（#705，使用者 2026-09-30 裁決 (a)）：**寫了**，照常記在
    /// `updated`、`authorsOverwritten` 等清單；留下兩份的事實記在這裡，不進 `writeFailed`。由 `run` 自己的收集範圍收下。
    public var writtenWithLegacyCopy: [LegacyCopyLeft] = []
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

    /// #608／#694：hash 不同時，能不能把它報成「只有 mapping hash 不同」——主來源（`updatedHashOnly`）與附加來源
    /// （`secondarySourceHashOnly`）共用這一份判準。四個條件都要成立：
    /// 1. 有舊 hash、且與現在不同（沒有舊 hash 無從比較）；
    /// 2. Zotero 那一列說這個條目已同步（`synced` = 1）——`version` 只在同步時才變，還沒同步的本機修改 `synced` = 0、`version` 不動；
    ///    資料庫沒有 `synced` 欄時是 nil＝無從判斷；
    /// 3. `version` > 0——從未同步的 library 每個條目都是 0，「沒變」不帶任何資訊；
    /// 4. `version` 與存下的相同——前進是有同步進來的修改，倒退時不知道發生什麼。
    ///
    /// 成立時報告**只說觀察到的事實**，不排原因（可能是 mapping 定義改了，也可能是子項附件的增減）；不成立的一律留在「有變動」那一格。
    /// 這個判準**只決定報告的分類**，不參與任何寫入的決定。
    static func isHashOnlyDifference(storedHash: String?, storedVersion: Int, item: ZoteroItem, itemHash: String) -> Bool {
        guard let old = storedHash, old != itemHash else { return false }
        return item.synced == true && item.version > 0 && item.version == storedVersion
    }

    public func run(zoteroDB: URL, libraryID: Int? = nil, now: Date = Date()) throws -> ImportReport {
        // #705：自己的收集範圍——「寫進 entities/、legacy 拷貝沒刪掉」的那一筆寫入照常回傳（`guardedWrite` 回 true，照常記在
        // updated、authorsOverwritten 等清單），並記進報告的 `writtenWithLegacyCopy`，不進 writeFailed。擲錯時收到的轉交外層範圍。
        let (result, written) = LegacyCopyLedger.collecting {
            try runCollected(zoteroDB: zoteroDB, libraryID: libraryID, now: now)
        }
        var report = try result.get()
        report.writtenWithLegacyCopy = written
        return report
    }

    private func runCollected(zoteroDB: URL, libraryID: Int?, now: Date) throws -> ImportReport {
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
        //
        // #610：這兩張 composite 表（與下面的 `secondaryByComposite`、`legacyByBareKey`）是「後寫覆蓋先寫」的字典——同一個
        // 來源被多筆 entry 宣稱時只會留下一筆。所以路由前先查 `claimants`：被多筆宣稱的來源不進路由，這幾張表因此只會被
        // 單一宣稱者的鍵查到。舊檔（沒記 library_id）的裸 key 是 `claimants` 裡的 `?:<key>` 桶，同一份定義。
        let claimants = ZoteroSourceClaims.claimants(load.entries)
        var byCompositeKey: [String: Entry] = [:]
        // legacy 檔（沒記 library_id 的主來源）：裸 key → entry。只在 `claimants` 說「恰好一筆」時才被取用——
        // 兩筆以上不猜，所以這張表不必自己數（#610 R1 verify：先前在這裡另有一份 legacy 的宣稱者定義）。
        var legacyByBareKey: [String: Entry] = [:]
        // #605：附加來源的 composite key → entry id。主來源優先（先查 byCompositeKey）。
        // libraryID 缺席的附加來源不進索引，也不是宣稱者（`ZoteroSourceClaims.claims(of:)`）。合併閘（`fieldsLostByMerging`）只保證合併
        // 不會把被併者的這種來源新收成附加來源（#605 R1 verify #1）；手改與舊檔裡已經有的不受它約束——這種來源對不回任何條目，再匯入時
        // 同一個 Zotero 條目在沒有別的 entry 宣稱它時會另建一筆 twin（#679）。`Entry.validate()` 對它報 warning，出路是補 library_id 或用 #680 的移除面拿掉。
        var secondaryByComposite: [String: UUID] = [:]
        // #607：裸 key → 以 composite 持有它的 library（主來源與附加來源都算）。legacy 檔只在
        // 這個集合**不含其他 library** 時才以裸 key 認領——附加來源持有的裸 key 同樣是「已被持有」。
        var claimedLibrariesByBareKey: [String: Set<Int>] = [:]
        // 本趟的「目前版本」：同一筆 entry 可能被命中兩次（主來源一次、附加來源一次），
        // 從載入快照取會讓第二次寫入蓋掉第一次的更新。每次成功寫入即更新此表。
        var current: [UUID: Entry] = [:]
        var existingCitekeys = Set<String>()
        for entry in load.entries {
            current[entry.id] = entry
            for extra in entry.additionalProvenance {
                if let lid = extra.libraryID {
                    secondaryByComposite[ZoteroSourceClaims.key(libraryID: lid, zoteroKey: extra.zoteroKey)] = entry.id
                    claimedLibrariesByBareKey[extra.zoteroKey, default: []].insert(lid)
                }
            }
            existingCitekeys.insert(entry.citekey)
            guard let prov = entry.provenance else { continue }
            if let lid = prov.libraryID {
                byCompositeKey[ZoteroSourceClaims.key(libraryID: lid, zoteroKey: prov.zoteroKey)] = entry
                claimedLibrariesByBareKey[prov.zoteroKey, default: []].insert(lid)
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
        /// 同一筆在同一趟可能有不只一步失敗：**附加、不覆寫**（#702 R2 verify：先前後一步的訊息蓋掉前一步的）。
        func recordWriteFailure(_ citekey: String, _ message: String, report: inout ImportReport) {
            if let earlier = report.writeFailed[citekey], earlier != message {
                report.writeFailed[citekey] = earlier + "；" + message   // display-safe-exempt: earlier、message：兩者都已消毒（displaySafeError 或本檔字面）
            } else {
                report.writeFailed[citekey] = message
            }
        }
        func guardedWrite(_ entry: Entry, report: inout ImportReport) -> Bool {
            if quarantinedBasenames.contains(entry.citekey.lowercased()) {
                if !report.quarantineConflicts.contains(entry.citekey) {
                    report.quarantineConflicts.append(entry.citekey)
                }
                return false
            }
            // #705（#702 R2 verify）：這一趟稍早一步對同一筆的寫入已落地、搬移後的 legacy 拷貝沒刪掉（在 `writtenWithLegacyCopy`）——
            // 兩份並存，#631 一定拒絕這一步。不再嘗試，具名說出前一步寫了、這一步的改動沒有套用；先前被拒的訊息只說「兩份都在」，
            // 讀的人會以為這一筆整個沒寫（主來源、附加來源、orphan 標記可能在同一趟各寫一次同一筆）。
            if LegacyCopyLedger.collected.contains(where: { $0.id == entry.id }) {
                recordWriteFailure(entry.citekey, "這一趟稍早已寫入這一筆（見 writtenWithLegacyCopy），搬移後的 legacy 拷貝沒刪掉、兩份並存"
                    + "——這一步的改動沒有套用。確認 entities/ 那份是新的、刪掉 legacy 那份之後重跑 import 即可補上（#631、#705）",
                    report: &report)
                return false
            }
            do {
                // #702 R1 verify／#705：#631 的搬移寫完之後刪 legacy 檔失敗時內容**已經寫進去**——`run` 的收集範圍讓這裡照常
                // 回傳，這一筆照寫入成功記（作者覆寫、欄位拿掉都真的發生了），留下兩份的事實在報告的 `writtenWithLegacyCopy`。
                try store.writeEntry(entry)
                current[entry.id] = entry
                return true
            } catch {
                recordWriteFailure(entry.citekey, displaySafeError(error, max: 4_096), report: &report)
                return false
            }
        }

        // #682：被多筆 entry 宣稱的來源，本趟不更新書目欄位、不動 version／hash，但**仍清掉各宣稱者身上這個來源的 orphan 標記**。
        // orphan 標記說的是「Zotero 那個 item 在不在」——這件事不需要判定哪一筆是正主就能確定（item 在，就是在）。標記留著的後果是
        // App 的 Orphans 頁把復原的 item 列成「已刪除」，而那一頁的動作是破壞性的（移到垃圾桶、脫鉤）。
        // 找宣稱者身上的來源用 `ZoteroSourceClaims.claims(of:)`（宣稱者的定義只有那一份）；沒有標記就不寫。
        // 報告：主來源的清除進 `orphanCleared`、附加來源的進 `secondarySourceRestored`（與 #605 的既有分工同一條）。
        func clearOrphanMarks(ofSource source: String, owners: [UUID], report: inout ImportReport) {
            for id in owners {
                guard var entry = current[id] else { continue }
                var primaryCleared = false
                var additionalCleared = false
                for claim in ZoteroSourceClaims.claims(of: entry) where claim.key == source {
                    switch claim.role {
                    case .primary:
                        if entry.provenance?.orphanedAt != nil {
                            entry.provenance?.orphanedAt = nil
                            primaryCleared = true
                        }
                    case .additional(let i):
                        if entry.additionalProvenance[i].orphanedAt != nil {
                            entry.additionalProvenance[i].orphanedAt = nil
                            additionalCleared = true
                        }
                    }
                }
                guard primaryCleared || additionalCleared else { continue }
                if guardedWrite(entry, report: &report) {
                    if primaryCleared { report.orphanCleared.append(entry.citekey) }
                    if additionalCleared { report.secondarySourceRestored.append(entry.citekey) }
                }
            }
        }

        let importedComposite = Set(items.map { ZoteroSourceClaims.key(libraryID: $0.libraryID, zoteroKey: $0.key) })
        let importedBare = Set(items.map(\.key))
        var legacyMatched = Set<String>()   // 已被 item 認領的 legacy 裸 key

        for item in items {
            for residual in ZoteroMapping.residualFields(of: item) {
                report.residualFields[residual, default: 0] += 1
            }
            let itemHash = ZoteroMapping.mappingHash(of: item)
            // **比對的優先順序**（#607）：① 主來源的 composite 完全相同 → ② 附加來源的 composite 完全相同
            // → ③ legacy 裸 key。②先於③：附加來源的比對是完全相同的身分，legacy 是歸屬不明的猜測——先前③排在②前面，
            // 群組條目會被一筆恰好同裸 key 的舊檔認領、改寫成那個 library，而真正持有它的附加來源從此不再被更新。
            // `ZoteroSourceRoutingTests` 釘住這個順序。
            let composite = ZoteroSourceClaims.key(libraryID: item.libraryID, zoteroKey: item.key)
            // #610：同一個來源被多筆 entry 宣稱 → 不更新任何一筆、不新建，報出來。猜一筆會把這個條目的書目欄位
            // 寫進可能是另一篇的記錄，而另一筆從此安靜地停在舊版。處置是人的：兩筆是同一篇就合併（合併把來源併成一份），
            // 其中一筆記錯了就拿掉那個來源。跨記錄檢查（`crossRecordIssues`）在載入時就說出同一件事。
            if let owners = claimants[composite], owners.count > 1 {
                report.ambiguousSourceClaims[composite] = owners.compactMap { current[$0]?.citekey }.sorted()
                clearOrphanMarks(ofSource: composite, owners: owners, report: &report)   // #682：書目欄位不動，orphan 標記照清
                continue
            }
            var matched = byCompositeKey[composite]
            let secondaryID = matched == nil ? secondaryByComposite[composite] : nil
            if matched == nil, secondaryID == nil, !legacyMatched.contains(item.key),
               let legacyOwners = claimants[ZoteroSourceClaims.key(libraryID: nil, zoteroKey: item.key)] {
                // #610：**先問有幾筆舊檔宣稱這個裸 key**——兩筆以上不認領、不新建、報出來（先前後讀到的那筆安靜勝出），
                // 而且不看別的 library 是否持有同一個裸 key（R1 verify：先前那個條件把這道數量檢查整個跳過，歧義的條目照走
                // 「建新 entry」、報告裡也看不到）。宣稱者的定義與 composite 同一份（`ZoteroSourceClaims`，含 `?:<裸 key>` 這一桶）。
                let legacyKey = ZoteroSourceClaims.key(libraryID: nil, zoteroKey: item.key)
                // 同 bare key 已被「其他 library」的來源持有（主來源或附加來源，#607）→ legacy 檔歸屬不明，scoped/全量都不認領
                // （留待人工或全量 backfill 釐清）
                let claimedByOtherLibrary = !(claimedLibrariesByBareKey[item.key] ?? [])
                    .subtracting([item.libraryID]).isEmpty
                guard legacyOwners.count == 1 else {
                    report.ambiguousSourceClaims[legacyKey] = legacyOwners.compactMap { current[$0]?.citekey }.sorted()
                    // #682：清 orphan 標記的條件與單一舊檔認領同一條——別的 library 也持有這個裸 key 時，這個條目在不在不能拿來證明
                    // 「這些舊檔的那個 item 在」（歸屬不明），所以不清；只有歸屬沒有爭議時才清
                    if !claimedByOtherLibrary {
                        clearOrphanMarks(ofSource: legacyKey, owners: legacyOwners, report: &report)
                    }
                    continue
                }
                // 只有唯一一筆舊檔時，才走認領
                if !claimedByOtherLibrary {
                    matched = legacyByBareKey[item.key]
                    legacyMatched.insert(item.key)
                }
            }
            // 取本趟的目前版本（#605）：同一筆可能已被本趟的附加來源分支改寫過。
            if var existing = matched.map({ current[$0.id] ?? $0 }) {
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
                    // #694：**只決定這一筆列在報告的哪一格**，不參與下面任何一個寫入的決定——兩格走同一段改寫、同一次寫入。
                    let hashOnly = Self.isHashOnlyDifference(storedHash: prov.zoteroHash, storedVersion: prov.zoteroVersion,
                                                             item: item, itemHash: itemHash)
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
                    // #702：這三件事（拿掉的欄位、保留的作者、覆寫的作者）先記在區域變數，**寫入成功之後**才進報告——
                    // 目的檔被隔離或寫入擲錯的那一筆沒有寫，報告不能說它的作者被覆寫、欄位被拿掉了（它只在失敗清單裡）。
                    let removedFields = fieldsBefore.subtracting(existing.fields.keys).sorted()
                    let identifiersAfter = Set(["doi", "pmid", "isbn"].filter {
                        !(existing.identifierList($0)?.isEmpty ?? true)
                    })
                    let removedIdentifiers = identifiersBefore.subtracting(identifiersAfter).sorted()
                    var authorsOverwritten = false
                    if !hadResolvedAuthors {
                        // 解析成果（person key）是使用者確認過的衍生知識，pull 不摧毀（寫入成功後記進 authorsPreserved）。
                        let after = item.authors.map { AkashicCore.Author.literal($0.display) }
                        // 未歸戶的 literal 作者會被 Zotero 版本覆寫。那是 pull-based
                        // sync 的正常語意（Zotero 是上游），但**與 import-wos 相反**
                        // ——後者對任何內容分歧一律拒絕覆寫。使用者跑兩個命令會得到
                        // 相反的資料保護等級，所以至少要說出來。
                        authorsOverwritten = after != authorsBefore
                        existing.authors = after
                    }
                    existing.provenance = Provenance(
                        zoteroKey: item.key, zoteroVersion: item.version,
                        libraryID: item.libraryID, zoteroHash: itemHash,
                        importedAt: now, orphanedAt: nil)
                    if guardedWrite(existing, report: &report) {
                        for k in removedFields { report.fieldsRemovedByPull[k, default: 0] += 1 }
                        for k in removedIdentifiers { report.fieldsRemovedByPull[k, default: 0] += 1 }
                        if hadResolvedAuthors { report.authorsPreserved.append(existing.citekey) }
                        if authorsOverwritten { report.authorsOverwritten.append(existing.citekey) }
                        if hashOnly { report.updatedHashOnly.append(existing.citekey) } else { report.updated.append(existing.citekey) }
                        if let raw = item.fields["date"], DateNormalizer.normalize(raw) == nil {
                            report.unnormalizedDates.append(existing.citekey)
                        }
                    }
                } else if !orphanWasCleared && !restoreWasBlocked {
                    report.unchanged += 1
                }
            } else if let sid = secondaryID,
                      var existing = current[sid],
                      let idx = existing.additionalProvenance.firstIndex(where: {
                          $0.libraryID == item.libraryID && $0.zoteroKey == item.key }) {
                // #605：附加來源命中——只更新該來源自己的 version／hash／orphan，**不動書目欄位**
                // （只有主來源能改寫欄位）。hash 變了而未套用 → secondarySourceChanged，不靜默；
                // hash 變了而 Zotero 那一列已同步、version 沒變 → secondarySourceHashOnly（#608，不宣稱原因；判準見 isHashOnlyDifference）。
                var src = existing.additionalProvenance[idx]
                var changed = false
                var cleared = false
                var contentChanged = false
                var hashOnly = false
                if src.orphanedAt != nil { src.orphanedAt = nil; changed = true; cleared = true }
                if item.version > src.zoteroVersion || src.zoteroHash != itemHash {
                    if let oldHash = src.zoteroHash {
                        if oldHash != itemHash {
                            // #608：判準只有一份（isHashOnlyDifference）；不成立的一律留在內容變動那一格——寧可多報，
                            // 不對一件沒把握的事下「只是定義變了」的結論。
                            if Self.isHashOnlyDifference(storedHash: oldHash, storedVersion: src.zoteroVersion,
                                                         item: item, itemHash: itemHash) {
                                hashOnly = true
                            } else {
                                contentChanged = true
                            }
                        }
                    } else {
                        // 沒有舊雜湊（pre-v1.1 記錄）時無從比較內容，版本前進就視為有變動——
                        // 寧可多報，不靜默（R2 verify）。
                        contentChanged = item.version > src.zoteroVersion
                    }
                    src.zoteroVersion = item.version
                    src.zoteroHash = itemHash
                    src.importedAt = now
                    changed = true
                }
                if changed {
                    existing.additionalProvenance[idx] = src
                    // 報告只在寫入成功後記錄（R1 verify #6）——寫入失敗的列在 writeFailed。
                    if guardedWrite(existing, report: &report) {
                        if contentChanged { report.secondarySourceChanged.append(existing.citekey) }
                        if hashOnly { report.secondarySourceHashOnly.append(existing.citekey) }
                        if cleared { report.secondarySourceRestored.append(existing.citekey) }
                    }
                } else {
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
        for loaded in load.entries {
            // 取本趟的目前版本——不是載入快照，否則會把本趟稍早的更新蓋掉（#605）。
            var entry = current[loaded.id] ?? loaded
            var primaryOrphaned = false
            var secondaryOrphaned = false
            if var prov = entry.provenance, prov.orphanedAt == nil {
                var isOrphan = false
                if let lid = prov.libraryID {
                    if libraryID == nil || lid == libraryID {   // 視野外，不動
                        isOrphan = !importedComposite.contains(ZoteroSourceClaims.key(libraryID: lid, zoteroKey: prov.zoteroKey))
                    }
                } else if libraryID == nil {   // 部分 import 不裁決 legacy 檔
                    isOrphan = !importedBare.contains(prov.zoteroKey)
                }
                if isOrphan {
                    prov.orphanedAt = now
                    entry.provenance = prov
                    primaryOrphaned = true
                }
            }
            // #605：附加來源逐一判定，只標該來源；視野規則同主來源。
            for i in entry.additionalProvenance.indices {
                let src = entry.additionalProvenance[i]
                guard src.orphanedAt == nil, let lid = src.libraryID else { continue }
                if let wanted = libraryID, lid != wanted { continue }
                if importedComposite.contains(ZoteroSourceClaims.key(libraryID: lid, zoteroKey: src.zoteroKey)) { continue }
                entry.additionalProvenance[i].orphanedAt = now
                secondaryOrphaned = true
            }
            guard primaryOrphaned || secondaryOrphaned else { continue }
            if guardedWrite(entry, report: &report) {
                if primaryOrphaned { report.orphaned.append(entry.citekey) }
                if secondaryOrphaned { report.secondarySourceOrphaned.append(entry.citekey) }
            }
        }

        report.created.sort()
        report.updated.sort()
        report.updatedHashOnly.sort()
        report.orphaned.sort()
        report.orphanCleared.sort()
        report.secondarySourceChanged.sort()
        report.secondarySourceHashOnly.sort()
        report.secondarySourceOrphaned.sort()
        report.secondarySourceRestored.sort()
        report.authorsPreserved.sort()
        report.authorsOverwritten.sort()
        report.quarantineConflicts.sort()
        report.unnormalizedDates.sort()
        return report
    }
}
