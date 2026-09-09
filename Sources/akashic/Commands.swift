import ArgumentParser
import Foundation
import AkashicCore
import AkashicStoreIO
import AkashicEntity
import AkashicZoteroImport
import AkashicWoSImport
import AkashicExport
import AkashicIndex
import AkashicMCPKit

struct Doctor: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "doctor", abstract: "建立/檢查 library 佈局、重建 index、一致性報告")

    @OptionGroup var options: LibraryOptions

    func run() throws {
        let store = try options.openOrCreateStore()
        let root = store.root
        let load = try store.load()
        // #504：doctor 先前是 `StoreHealth` 之外的第四條讀取路徑——自己算 cross-record、殘留、
        // sources audit 並自行渲染，而 MCP `doctor()`、CLI `validate`、App 都走 `health(from:)`。
        // #453／#464 加進 health 的掃描它一個都看不到。現在唯讀事實全部從 health 讀、這裡只渲染，
        // 且 `health(from:)` 本來就在 fatal 早退之前算得出，早退順序不變。
        let health = store.health(from: load)

        // #35：跨記錄檢查必須在 rebuild **之前**。雙佈局並存時 index 會撞
        // `UNIQUE constraint failed: entries.citekey`——使用者拿到的是 SQLite 的
        // 內部錯誤，而不是「你有兩筆同 citekey 的記錄、它們在哪」。診斷工具在這種
        // 狀態下正是最該說話的時候，不是最該掛掉的時候。
        let cross = health.crossRecordIssues
        let fatalCross = health.fatalCrossRecordIssues
        if !cross.isEmpty {
            print("cross-record: \(cross.count)")
            for i in cross { print("  \(i.severity == .error ? "✗" : "⚠") \(i.message)") }
        }
        // #107：佈局殘留——依 format/key 不該存在、且為空目錄或純衍生物的路徑。
        // **只在命中時輸出，報告不動手刪**（#79 的形狀：讓看不見的變看見，處置留給人）。
        // 判準保守：含資料的目錄永不報；sources/（#66 的被指涉內容）絕不列入。
        // **排在 fatal cross-record 早退之前**（#120 verify）：重複 citekey 的 store
        // 正是最需要看清全貌的時候，殘留報告不該被吞掉。
        // `health(from:)` 對殘留掃描失敗以 `try?` 吞掉（報告不得消失，#224 F1）——先前這裡是 throw，
        // 改後與 MCP 面同語意：殘留掃描失敗不再中止 doctor（#504）。
        let residue = health.layoutResidue
        if !residue.isEmpty {
            print("殘留：")
            residue.forEach { print("  ⚠ \(displaySafe($0, max: 300))") }
        }
        // #224：blob ↔ index 一致性（audit 邏輯單一路徑在 SourceStore；此處只渲染，
        // 與 MCP 面的 doctor 讀同一個結果）。四類皆空不出聲；有事必說、不動手刪。
        // audit 自身失敗**不得**中止 doctor（診斷工具最該說話的時候不是最該掛掉的
        // 時候）——降級為一則警告，其餘報告照出。
        if let srcAudit = health.sourcesAudit {
            if !srcAudit.orphanBlobs.isEmpty || !srcAudit.danglingEntries.isEmpty
                || !srcAudit.malformedLines.isEmpty || !srcAudit.unreadableShards.isEmpty {
                print("sources 一致性：")
                for b in srcAudit.orphanBlobs {
                    print("  ⚠ 孤兒 blob（有存檔、index.jsonl 無條目）：\(b)")
                }
                for e in srcAudit.danglingEntries {
                    print("  ⚠ 懸空條目（index.jsonl 有、存檔缺席）：\(e)")
                }
                if !srcAudit.malformedLines.isEmpty {
                    print("  ✗ index.jsonl 無法解析的行：\(srcAudit.malformedLines.map(String.init).joined(separator: ", "))")
                }
                for s in srcAudit.unreadableShards {
                    print("  ✗ 讀不到的 shard（權限／半截同步；其 blob 未參與比對）：\(displaySafe(s, max: 120))")
                }
            }
        }
        if let auditError = health.sourcesAuditError {
            print("  ✗ sources audit 無法完成：\(auditError)")   // display-safe-exempt: StoreHealth 已 displaySafe
        }
        if !fatalCross.isEmpty {
            print("library: \(displaySafe(root.path, max: 800))")
            print("entries: \(load.entries.count)（未重建 index——先修好上面的重複）")
            throw ExitCode(1)
        }

        // #130：重生之後舊 index 成為孤兒（index 檔名綁化身，新舊是不同檔案）。
        // **報告不動手刪**（#79 的形狀）——它們可能是另一台機器同步過來的、或
        // 使用者還想比對的。排在 rebuild **之前**：rebuild 會建立當下化身的 index，
        // 之後再數就把剛建好的那個也算進「同 key 的其他檔案」了。
        let orphanIdx = store.orphanedIndexFiles()

        let stats = try LibraryIndex(store: store).rebuild()

        print("library: \(displaySafe(root.path, max: 800))")
        if !orphanIdx.isEmpty {
            print("孤兒 index 檔: \(orphanIdx.count)（本 store 的化身已更換，舊 index 不再使用）")
            for f in orphanIdx.prefix(10) { print("  ⚠ \(displaySafe(f, max: 300))") }
            if orphanIdx.count > 10 { print("  …另 \(orphanIdx.count - 10) 筆") }
        }
        print("entries: \(stats.entries)")
        print("people: \(stats.people)")
        // 見上方 validate 的同一理由（#71）。index 不索引歧異記錄（它是短暫的、
        // 不被指涉），所以計數取自 load 而非 stats。
        if !load.divergences.isEmpty {   // #78-3：與 validate 對齊——有才印
            print("divergences: \(load.divergences.count)")
        }
        print("relations: \(stats.relations)")
        let orphaned = load.entries.filter { $0.provenance?.orphanedAt != nil }
        print("orphaned: \(orphaned.count)\(orphaned.isEmpty ? "" : "（" + orphaned.map { displaySafe($0.citekey, max: 200) }.joined(separator: ", ") + "）")")
        let unresolved = load.entries.flatMap { entry in
            entry.authors.compactMap { if case .literal(let s) = $0 { return s } else { return nil } }
        }
        print("unresolved author literals: \(unresolved.count)")
        // #146：`TemporalValue.source` 只放**裸 URL**，digest 屬 `references:`。
        // **報告不是錯誤**——遷移由 `akashic migrate-provenance` 執行，而這條檢查
        // 要持續存在：遷移是一次性動作，「source 只放 URL」卻是要一直成立的不變式，
        // 新寫入隨時可能再破壞它（那正是這 22 筆當初的來由）。
        let digestSources = ProvenanceMigration.residualDigestSources(load: load)
        if !digestSources.isEmpty {
            print("digest 形式的 source: \(digestSources.count)（應改記於 references:，#146）")
            for s in digestSources.prefix(10) {
                print("  ⚠ \(displaySafe(s.record, max: 200)).\(displaySafe(s.field, max: 120))")
            }
            if digestSources.count > 10 { print("  …另 \(digestSources.count - 10) 筆") }
            print("  遷移：akashic migrate-provenance --dry-run")
        }
        // #81：沒有指定對外名字的記錄。**報告不是錯誤**——修復需要的資訊無法自動取得，
        // 設成 validate 錯誤等於把不可自動化的工作變成載入的前置條件。
        let nameGaps = load.recordsWithoutAuthorizedName()
        print("no authorized name: \(nameGaps.people.count) person / \(nameGaps.organizations.count) organization"
              + (nameGaps.people.isEmpty ? "" :
                 "（前 10：" + nameGaps.people.prefix(10)
                    .map { displaySafe($0, max: 120) }.joined(separator: ", ") + "）"))
        // #81/#82：指定了、但指定的就是引用形——缺的不是指定，是名字本身。migration 把
        // 唯一候選直接採用之後，這才是真正的缺口訊號（未指定者會掉到接近 0）。
        let citationOnly = load.recordsAuthorizedOnlyByCitationForm()
        print("authorized only by citation form: \(citationOnly.count) person"
              + (citationOnly.isEmpty ? "" : "（無真正的名字，只有索引系統的變換）"))
        // #67：已記錄逝世卻仍有開放的隸屬段。**只在命中時輸出**——0 是正常狀態，
        // 每次都印一行「0」只是噪音（上面兩項是普查數字，性質不同）。
        let deceasedOpen = load.recordsDeceasedWithOpenAffiliation()
        if !deceasedOpen.isEmpty {
            print("deceased with open affiliation: \(deceasedOpen.count) person"
                  + "（隸屬的結束日與死亡只有一個是對的，需要人判斷；工具不代為關閉）")
            // **列出全部**，不截斷。這是待人處理的工作清單而非普查數字——省略第 11 筆
            // 之後等於讓操作者拿不到其餘待修記錄，而總數不等於清單。
            deceasedOpen.forEach { print("  ⚠ \(displaySafe($0, max: 120))") }
        }
        // #100：「從來沒有日期」的維度——range 相同時的 fallback 排序對它們
        // 沒有現實根據，系統要說出來（要嘛補日期，要嘛承認它不是時間軸）。
        // 命中才輸出；空維度不報（沒有段就沒有「該不該有日期」的問題）。
        let neverDated = load.timelineDateCensus().filter { $0.dated == 0 && $0.undated > 0 }
        if !neverDated.isEmpty {
            print("timeline dimensions with zero dates: \(neverDated.count)"
                  + "（range 相同時的排序對這些維度沒有時間根據——補日期，或接受它是"
                  + "無時序的集合）")
            neverDated.forEach { print("  ⚠ \($0.dimension)：\($0.undated) 段、0 個日期") }
        }
        // #85：日期樣欄位不合 ISO 8601 前綴值域——裁決 (c)：不驗證但報告。
        // **只在命中時輸出**（同 deceasedOpen：待人處理的工作清單，列全部不截斷）。
        let dateAnomalies = load.dateFieldAnomalies()
        if !dateAnomalies.isEmpty {
            print("date-like values outside ISO 8601 prefix: \(dateAnomalies.count)"
                  + "（值域是文件契約、載入不擋；民國年等真實情況請補正或留註記）")
            dateAnomalies.forEach {
                print("  ⚠ \(displaySafe($0.key, max: 120)).\(displaySafe($0.field, max: 120))："
                      + "「\(displaySafe($0.value, max: 200))」")
            }
        }
        if !load.quarantined.isEmpty {
            print("quarantined: \(load.quarantined.count)")
            load.quarantineLines.forEach { print($0) }
        }
        // #23 tolerant-preserve：較新 schema 的檔案（未知欄位已保留）——提示升級
        if !load.unknownFieldFiles.isEmpty {
            print("unknown-field files: \(load.unknownFieldFiles.count)（可能由較新版本寫入；升級 binary）")
            load.unknownFieldFiles.forEach { print("  ⚠ \(displaySafe($0, max: 200))") }
        }
    }
}

struct Validate: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "validate", abstract: "schema 驗證；quarantine 或 error 時非零退出")

    @OptionGroup var options: LibraryOptions

    func run() throws {
        let store = try options.openStore()
        let load = try store.load()
        let health = store.health(from: load)
        var failed = false
        if !load.quarantined.isEmpty {
            failed = true
            print("quarantined \(load.quarantined.count) 檔：")
            load.quarantineLines.forEach { print($0) }
        }
        // **五族的 per-record 驗證走 `StoreHealth`**（#416）。先前這裡是五個各自展開的
        // 迴圈，而 `Entry.validate()` 在全樹的唯一呼叫點就是其中之一——`doctor()` 與
        // App 面各 0。落差裡有一條是 **error** 級（citekey 不符 pattern）。
        //
        // 現在邏輯在 `LibraryStore.health(from:)`，三個面各自渲染
        // （`entity-backlink-completeness` 執行細節 2：一個讀取面只能有一條實作路徑）。
        // CLI 這一面的特徵是**逐行、無截斷**；MCP 面截斷 20 則並送 count 當分母。
        //
        // `load.organizations` / `organization.validate()` / `load.divergences` 這些
        // 走訪**沒有消失**，只是搬到 `health(from:)` 裡——`AuthorizedNameTests` 的
        // 機械守衛跟著搬（它釘的是「機構真的被驗證」這個性質，不是它住在哪個檔）。
        for owned in health.perRecordIssues {
            let mark = owned.issue.severity == .error ? "✗" : "⚠"
            let label = owned.kind == "entry" ? "" : "\(owned.kind) "
            print("\(mark) \(label)\(displaySafe(owned.owner, max: 200)): \(owned.issue.message)")
            if owned.issue.severity == .error { failed = true }
        }
        // #453：本機缺承重存檔的計數行——逐條已印在上面，這一行讓人一眼看出是整批
        // （其他 clone 上 sources/ 沒同步時會是全部）還是零星（一筆捏造）。
        if !health.danglingSources.isEmpty {
            print("本機缺承重存檔: \(health.danglingSources.count)（sources/ 不進 git；其他 clone 上的數字會不同）")
        }
        // #499：哪些 venue 的 verdict 數逼近 decode 預算——逐條已印，這一行給總數。
        if !health.venueVerdictBudgetWarnings.isEmpty {
            print("venue verdict 逼近 decode 預算: \(health.venueVerdictBudgetWarnings.count)（第 13 條邊的規模化裁決，#499）")
        }
        // #450：拆分後錨失效——逐條已印，這兩行給總數（兩種分開：一種要人重新消歧，一種只是提醒）。
        if !health.orphanedSplitVerdicts.isEmpty {
            print("拆分後的孤兒 verdict: \(health.orphanedSplitVerdicts.count)（錨 literal 已被 work 側拆分記錄退役，#450）")
        }
        if !health.contradictedRemovalRecords.isEmpty {
            print("移除記錄與作者位互相矛盾: \(health.contradictedRemovalRecords.count)（#457）")   // display-safe-exempt: Int
        }
        if !health.staleSplitRecords.isEmpty {
            print("拆分記錄各段都已不在作者位: \(health.staleSplitRecords.count)（記錄仍保留供 un-split，#450）")
        }
        // #7b：跨記錄檢查——單筆 validate() 結構上看不到的那一層
        for issue in health.crossRecordIssues {
            let mark = issue.severity == .error ? "✗" : "⚠"
            print("\(mark) [跨記錄] \(issue.message)")
            if issue.severity == .error { failed = true }
        }
        if failed {
            throw ExitCode(1)
        }
        // 歧異記錄計入摘要：承載若不可觀察就不可驗證——載入成功卻不出現在任何
        // 輸出裡，使用者無從分辨「載入了」與「被靜默忽略」（#71）。
        let divergenceNote = load.divergences.isEmpty ? "" : "、\(load.divergences.count) divergences"
        print("✓ \(load.entries.count) entries、\(load.people.count) people、\(load.libraries.count) libraries\(divergenceNote) 全部通過")
    }
}

struct ImportZotero: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "import-zotero", abstract: "Zotero → Akashic 單向 pull（zotero.sqlite 唯讀）")

    @OptionGroup var options: LibraryOptions

    @Option(name: .long, help: "zotero.sqlite 路徑（預設 ~/Zotero/zotero.sqlite）")
    var zoteroDb: String = "~/Zotero/zotero.sqlite"

    @Option(name: .long, help: "Zotero libraryID（預設全部 libraries；指定則只拉該 library，如 1＝personal）")
    var libraryId: Int?

    func run() throws {
        let store = try options.openOrCreateStore()
        let dbURL = URL(fileURLWithPath: (zoteroDb as NSString).expandingTildeInPath)
        guard FileManager.default.fileExists(atPath: dbURL.path) else {
            throw ValidationError("找不到 zotero.sqlite：\(dbURL.path)")
        }
        let report = try ZoteroImporter(store: store).run(zoteroDB: dbURL, libraryID: libraryId)
        print("created: \(report.created.count)")
        print("updated: \(report.updated.count)\(report.updated.isEmpty ? "" : "（" + report.updated.map { displaySafe($0, max: 200) }.joined(separator: ", ") + "）")")
        print("orphaned: \(report.orphaned.count)\(report.orphaned.isEmpty ? "" : "（" + report.orphaned.map { displaySafe($0, max: 200) }.joined(separator: ", ") + "）")")
        print("unchanged: \(report.unchanged)")
        if !report.orphanCleared.isEmpty {
            print("orphan cleared（Zotero 端復原）: \(report.orphanCleared.map { displaySafe($0, max: 200) }.joined(separator: ", "))")
        }
        if !report.authorsPreserved.isEmpty {
            print("authors preserved（已解析、未同步 Zotero 作者欄）: \(report.authorsPreserved.map { displaySafe($0, max: 200) }.joined(separator: ", "))")
        }
        if !report.authorsOverwritten.isEmpty {
            // #208：pull-based sync 覆寫本地的未歸戶作者，**與 import-wos 相反**
            //（後者對任何分歧一律拒絕覆寫）。至少要讓它可見。
            print("authors overwritten（未歸戶 literal 作者已改為 Zotero 版本）: "
                + "\(report.authorsOverwritten.count) 筆——"
                + "已歸戶的 person key 不受影響（見 authors preserved）")
        }
        if !report.fieldsRemovedByPull.isEmpty {
            let s = report.fieldsRemovedByPull.keys.sorted()
                .map { "\(displaySafe($0, max: 100))×\(report.fieldsRemovedByPull[$0]!)" }
                .joined(separator: ", ")
            print("fields removed by pull（Zotero 這次沒給，整份替換後消失）: \(s)")
        }
        if !report.residualFields.isEmpty {
            let summary = report.residualFields.keys.sorted()
                .map { "\($0)×\(report.residualFields[$0]!)" }.joined(separator: ", ")
            // #206：這些欄位**有入庫**（以正規化後的原名）。舊訊息寫「未入庫」，
            // 在殘餘收集落地後就成了假話。
            print("residual fields（無 canonical 對照，已以原名入庫）: \(summary)")
        }
        if !report.unnormalizedDates.isEmpty {
            print("unnormalized dates（date 保留原字串）: \(report.unnormalizedDates.count)（\(report.unnormalizedDates.prefix(8).map { displaySafe($0, max: 200) }.joined(separator: ", "))\(report.unnormalizedDates.count > 8 ? ", …" : "")）")
        }
        if report.skippedLinkedAttachments > 0 {
            print("skipped linked attachments（非 storage 附件，未入庫）: \(report.skippedLinkedAttachments)")
        }
        // R6（M9）：per-item 寫入失敗不中斷 import——照實列出，人工處理
        if !report.writeFailed.isEmpty {
            print("write failed（單筆寫入失敗，已略過續跑）: \(report.writeFailed.count)")
            for key in report.writeFailed.keys.sorted() {
                print("  ✗ \(displaySafe(key, max: 200)) — \(displaySafe(report.writeFailed[key]!, max: 512))")
            }
        }
        let stats = try LibraryIndex(store: store).rebuild()
        // #37：index 已搬出 store root，路徑不再顯而易見——doctor 必須說它在哪。
        print("index rebuilt: \(stats.entries) entries → \(store.indexURL.path)")
        // R7（R6-verify M22）：收容 ≠ 吞掉 process 層訊號——有單筆失敗仍以
        // 非零退出，自動化（cron pull、CI）才看得到
        if !report.writeFailed.isEmpty {
            throw ExitCode(1)
        }
    }
}

/// #35：legacy → entities 的一次性遷移。
struct Migrate: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "migrate",
        abstract: "把 store 從 entries/+people/ 遷移到 entities/<uuid>.yaml（#35）")

    @OptionGroup var options: LibraryOptions

    @Flag(name: .long, help: "只回報會做什麼，不動磁碟")
    var dryRun = false

    func run() throws {
        let store = try options.openStore()
        do {
            // 兩階段：先把 legacy 佈局搬進 entities/（format 2），再補形狀標籤（format 3）。
            // 已在目標格式的階段會擲 alreadyAtFormat，視為「這一階不用做」而不是失敗——
            // 使用者可能是從 format 2 直接升上來的。
            var moved = 0, people = 0, already = 0
            do {
                let r = try StoreMigration.toEntities(store: store, dryRun: dryRun)
                moved = r.entriesMoved; people = r.peopleMoved; already = r.alreadyMigrated
            } catch StoreMigration.MigrationError.alreadyAtFormat {
                // 已是 format ≥ 2，跳過第一階
            }
            let l = try StoreMigration.toShapeLabels(store: store, dryRun: dryRun)
            let prefix = dryRun ? "（dry-run）" : "✓"
            if moved + people + already > 0 {
                print("\(prefix) entries \(moved)、people \(people) 筆"
                    + (already > 0 ? "、已在 entities/ \(already) 筆" : ""))
            }
            print("\(prefix) 形狀標籤：補 \(l.labelled) 筆"
                + (l.alreadyLabelled > 0 ? "、已有標籤 \(l.alreadyLabelled) 筆" : ""))
            if dryRun {
                print("  實際執行：akashic migrate")
            } else {
                print("  store format → \(StoreVersion.supported)；舊 binary 從此會拒絕開啟這個 store（#24）")
                let stats = try LibraryIndex(store: store).rebuild()
                print("  index rebuilt: \(stats.entries) entries → \(store.indexURL.path)")
            }
        } catch {
            throw ValidationError((error as? LocalizedError)?.errorDescription ?? "\(error)")
        }
    }
}

/// #146：把 digest 形式的 `TemporalValue.source` 搬進 `references:`。
///
/// **與 `migrate` 分開是刻意的。** `migrate` 是**佈局格式**遷移——它 bump
/// `StoreVersion`，之後舊 binary 一律拒絕開啟這個 store（#24）。本指令是**內容**
/// 遷移，格式不變、舊 binary 讀得懂結果。把兩者塞進同一個指令會讓「跑了 migrate」
/// 這句話同時意味著兩件後果差很多的事。
struct MigrateProvenance: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "migrate-provenance",
        abstract: "digest 形式的 source → references:（#146；不改 store format）")

    @OptionGroup var options: LibraryOptions

    @Flag(name: .long, help: "只回報會做什麼，不動磁碟")
    var dryRun = false

    func run() throws {
        let store = try options.openStore()
        let report = try ProvenanceMigration.digestSourcesToReferences(
            store: store, dryRun: dryRun)
        let prefix = dryRun ? "（dry-run）" : "✓"

        if report.migrated == 0 && report.skipped.isEmpty {
            print("沒有 digest 形式的 source——不需要遷移")
            return
        }
        print("\(prefix) 搬進 references: \(report.migrated) 筆"
              + "，涉及 \(report.records.count) 筆記錄")
        for k in report.records.prefix(20) { print("  \(displaySafe(k, max: 200))") }
        if report.records.count > 20 { print("  …另 \(report.records.count - 20) 筆") }

        // **搬不動的要說出來。** 靜默略過會讓「遷移完成」與「遷移完成但有 N 筆
        // 還在舊形式」看起來一樣，而 `doctor` 之後仍會報那些殘留——兩份訊息
        // 對不上時，人會先懷疑 doctor 壞了。
        if !report.skipped.isEmpty {
            print("搬不動 \(report.skipped.count) 筆（留在原形式）：")
            for s in report.skipped.prefix(20) {
                print("  ⚠ \(displaySafe(s.record, max: 200)).\(displaySafe(s.field, max: 120))"
                      + "——\(displaySafe(s.reason, max: 300))")
            }
            if report.skipped.count > 20 { print("  …另 \(report.skipped.count - 20) 筆") }
        }
        // **先報失敗再說成功**（同 ResolvePeople 的紀律）：中途失敗時 store 半新
        // 半舊，不說出來的話使用者以為什麼都沒發生或全部完成。
        if !report.failures.isEmpty {
            print("寫入失敗 \(report.failures.count) 筆（其餘已落地，可修好後重跑——遷移是冪等的）：")
            for f in report.failures.prefix(20) {
                print("  ✗ \(displaySafe(f.record, max: 200)) — \(displaySafe(f.reason, max: 512))")
            }
        }
        if dryRun {
            print("  實際執行：akashic migrate-provenance")
        } else {
            // 這個遷移沒有消歧那種「tracked 且 clean」的 gate（它不刪檔），
            // 所以可回溯性由使用者的版控負責——明講，不要讓人事後才發現。
            // **印這個 store 的 format，不是 binary 的 supported**（#146 verify F5）：
            // 真實 store 是 format 5，先前印 7——這句的唯一作用是讓使用者確認格式
            // 沒變，卻報了一個這個 store 從來不是的數字。
            let fmt = (try? StoreVersion.read(root: store.root)).map(String.init) ?? "未知"
            print("  store format 不變（\(fmt)）；舊 binary 仍讀得懂")
            print("  變更未經版控 gate——用 git diff 檢查後再 commit")
        }
        // **部分失敗必須非零退出**（#146 verify G1）。我引的既有紀律有**三塊**，
        // 而本 repo 四處都是三塊一起用的（`ResolvePeople`、`ImportZotero`、
        // `FormatCommands`、`DivergenceCommands`）：per-item 收容、先報失敗、
        // **然後 throw**。我只拿了前兩塊。
        //
        // 淨效果相對於修 F4 之前：人看的輸出好很多，**機器看的訊號嚴格變差**——
        // 原本 exit 1，改完 exit 0。`&&` 串接、CI、`/loop` 會在一個半新半舊的
        // store 上看到成功。
        if !report.failures.isEmpty { throw ExitCode(1) }
    }
}

/// #241／#227：person 身分重發（v5→v4）+ names 巢狀化的一次性遷移。
///
/// **預設 dry-run**（design D6）——不可逆操作的預設是預演；`--apply` 才寫入，且
/// 要求 store 工作樹乾淨（git 是回復路徑）。輸出沿用 migrate-provenance 的呈現形狀。
struct MigratePersonIdentity: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "migrate-person-identity",
        abstract: "person 身分重發（v4）+ names 巢狀化（#227/#241；需另手動 bump format 至 10）")

    @OptionGroup var options: LibraryOptions

    @Flag(name: .long, help: "實際寫入（預設只預演；要求 store 工作樹乾淨）")
    var apply = false

    func run() throws {
        // #298：破壞性寫入前確認目標 store 已被指名。**只在 --apply 時**
        // ——dry-run 不得被擋（它不寫東西，且正是用來確認目標的手段）。
        if apply { try options.assertDestructiveTargetNamed("migrate-person-identity") }
        let store = try options.openStore()
        // 席 A NEW-3 的即時緩解：破壞性遷移**先回顯目標**——LibraryLocator 對 CWD
        // 零感知（registry current 決定目標），不印出來的話「在 scratch 目錄執行」
        // 會給人錯誤的安全感（2026-08-16 事故的根因情境）。
        print("目標 store：\(displaySafe(store.root.path, max: 300))")
        let report = try PersonIdentityMigration.run(store: store, apply: apply)
        let prefix = apply ? "✓" : "（dry-run）"

        if report.migrated.isEmpty && report.skipped.isEmpty && report.failed.isEmpty {
            print("沒有 person 記錄——不需要遷移")
        } else {
            print("\(prefix) \(apply ? "已遷移" : "將遷移") \(report.migrated.count) 筆"
                  + "，已是新形狀（跳過）\(report.skipped.count) 筆")
            for k in report.migrated.prefix(20) { print("  \(displaySafe(k, max: 200))") }
            if report.migrated.count > 20 { print("  …另 \(report.migrated.count - 20) 筆") }

            // **先報失敗**（同 migrate-provenance 的紀律）：單筆失敗不中止整批，
            // 不說出來的話使用者以為全部完成。
            if !report.failed.isEmpty {
                print("處理失敗 \(report.failed.count) 筆（其餘照常；修好後重跑——遷移是冪等的）：")
                for f in report.failed.prefix(20) {
                    print("  ⚠ \(displaySafe(f.file, max: 200))——\(displaySafe(f.reason, max: 300))")
                }
                if report.failed.count > 20 { print("  …另 \(report.failed.count - 20) 筆") }
            }
        }
        if let step = PersonIdentityMigration.nextStep(report: report, apply: apply,
                                                    current: try? StoreVersion.read(root: store.root)) {
            print(step)
        }
    }
}

/// #34：從 literal 作者 bootstrap person 記錄。
struct BootstrapPeople: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "bootstrap-people",
        abstract: "從 literal 作者建立 person 記錄（寧可分割，絕不合併）")

    @OptionGroup var options: LibraryOptions

    @Flag(name: .long, help: "實際寫入（預設只列出）")
    var apply = false

    @Option(name: .long, help: "只處理出現次數 ≥ N 的（投報率優先）")
    var minOccurrences: Int = 1

    @Option(name: .long, help: "最多處理前 N 個")
    var limit: Int?

    /// #547：完整清單的機器可讀出口。
    ///
    /// 人可讀面有顯示上限（`AmbiguityDisplayLimit.rows`），而消歧迴圈的消費端是
    /// 「把組別餵給 `add-person`」——需要的是完整清單與**逐字的** literal，
    /// 不是印給人看的截斷版。所以本旗標**不套用 `--limit`**（那是處理／顯示上限），
    /// 也**不套用 `displaySafe` 消毒**（消毒是終端機的需要；JSON 由序列化器逃脫，
    /// 而呼叫端需要原字串才能正確傳給 `add-person`）。`--min-occurrences` 照樣生效。
    @Flag(name: .long, help: "輸出完整四段的 JSON（唯讀，不與 --apply 併用；不套用 --limit）")
    var json = false

    func run() throws {
        // #298：破壞性寫入前確認目標 store 已被指名。**只在 --apply 時**
        // ——dry-run 不得被擋（它不寫東西，且正是用來確認目標的手段）。
        if apply { try options.assertDestructiveTargetNamed("bootstrap-people") }
        let store = try options.openStore()
        let load = try store.load()
        // R1-fix B4：否決史決定 pending literal 何時回到可建檔
        let report = PersonBootstrap.resolve(
            entries: load.entries, existing: load.people,
            rejected: ResolutionLedger.rejectedPairings(people: load.people),
            confirmed: ResolutionLedger.confirmedPairings(people: load.people))
        if json {
            // 唯讀出口——與 `--apply` 併用沒有意義且會讓「輸出的是寫入前還是寫入後」有歧義。
            guard !apply else {
                throw ValidationError("--json 是唯讀輸出，不與 --apply 併用")
            }
            // **消毒層是 `JSONSerialization` 自己，不是 `displaySafe`。** 實測（2026-09-09）：
            // 一個含裸 ESC／BEL／換行／引號的名字序列化後是 ``／``／`\n`／`\"`，
            // 輸出裡**裸控制位元組 0**——終端機注入（#165 的威脅模型）在這條路上不成立。
            // 而 `displaySafe` 會**破壞消費端需要的東西**：本出口的用途是把 literal 逐字餵回
            // `add-person`，消毒過的字串傳回去會建出一個名字不對的 person。
            // 前提有測試釘住：`BootstrapPeopleMutualCLITests.testJSONOutputHasNoRawControlBytes`。
            let payload: [String: Any] = [
                "candidates": report.candidates
                    .filter { $0.occurrences >= minOccurrences }
                    .map { ["key": $0.key, "names": $0.names, "occurrences": $0.occurrences] },   // display-safe-exempt: JSONSerialization 逃脫全部控制字元（實測裸位元組 0）；消毒會破壞餵回 add-person 的逐字 literal
                "unkeyable": report.unkeyable
                    .filter { $0.occurrences >= minOccurrences }
                    .map { ["names": $0.names, "occurrences": $0.occurrences, "reason": $0.reason] },   // display-safe-exempt: 同上——JSON 面的消毒層是序列化器
                "pendingResolution": report.pendingResolution
                    .filter { $0.occurrences >= minOccurrences }
                    .map { ["names": $0.names, "occurrences": $0.occurrences,   // display-safe-exempt: 同上——JSON 面的消毒層是序列化器
                            "matchedKeys": $0.matchedKeys] },   // display-safe-exempt: 同上
                "pendingMutual": report.pendingMutual
                    .filter { $0.occurrences >= minOccurrences }
                    .map { ["names": $0.names, "occurrences": $0.occurrences,   // display-safe-exempt: 同上——JSON 面的消毒層是序列化器
                            "sharedKeys": $0.sharedKeys] },   // display-safe-exempt: 同上
            ]
            let data = try JSONSerialization.data(
                withJSONObject: payload,
                options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
            print(String(decoding: data, as: UTF8.self))
            return
        }
        var cands = report.candidates.filter { $0.occurrences >= minOccurrences }
        let total = cands.count
        if let limit { cands = Array(cands.prefix(limit)) }

        /// 產不出 ASCII key 的那些**必須被印出來**（#238）。
        ///
        /// 舊版把它們 `compactMap` 掉——實測真實 store 有 49 個作者位置就這樣消失，
        /// 使用者以為那些作者不存在。**回報而非丟棄**，而回報的前提是真的有人印它：
        /// 只在 model 端加欄位而沒有任何輸出讀它，與丟棄在效果上完全相同（#236 R3
        /// 在 App 面踩過這個坑，位置更難察覺）。
        /// 寬鬆鍵命中既有 person 的群（R1-fix B4）——先消歧、不建檔。同 unkeyable
        /// 的理由：model 端有欄位而沒人印＝效果上的丟棄。
        func printPendingResolution() {
            let shown = report.pendingResolution.filter { $0.occurrences >= minOccurrences }
            guard !shown.isEmpty else { return }
            print("")
            print("與既有 person 寬鬆共鍵、**先消歧再說**（\(shown.count)）——建檔會鑄造重複身分：")
            for g in shown.prefix(AmbiguityDisplayLimit.rows) {
                let aliases = g.names.map { displaySafe($0, max: 200) }.joined(separator: " ≡ ")
                print("  ×\(g.occurrences)  \(aliases)  ↔ 既有：\(g.matchedKeys.map { displaySafe($0, max: 200) }.joined(separator: "、"))")
            }
            if shown.count > AmbiguityDisplayLimit.rows {
                print("  …另 \(shown.count - AmbiguityDisplayLimit.rows) 筆未顯示")
            }
            print("  處置：跑 akashic resolve-people 看候選／歧義。查證後——是清單中某人 → "
                  + "補 variant alias（帶 provenance；update-person 的 names 整組回寫，先讀再附加）"
                  + "升 exact 再 apply；是第三個人 → add-person 以該寫法為 name 建檔（exact 單命中"
                  + "優先於寬鬆碰撞）再 apply；配對確定錯誤 → reject。候選全數出清後名字回到本命令。")
        }

        /// #547：彼此寬鬆共鍵、而**兩邊都還沒有記錄**的群——同樣先消歧、不建檔。
        ///
        /// 與 `printPendingResolution` 是同一件事的兩半：那一半問「跟既有 person 撞了嗎」，
        /// 這一半問「跟本批的其他候選撞了嗎」。只在 model 端加欄位而沒有任何輸出讀它，
        /// 與丟棄在效果上完全相同（#236 R3 在 App 面踩過，位置更難察覺）。
        func printPendingMutual() {
            let shown = report.pendingMutual.filter { $0.occurrences >= minOccurrences }
            guard !shown.isEmpty else { return }
            print("")
            print("彼此寬鬆共鍵、**兩邊都還沒有記錄**（\(shown.count)）——建檔會鑄造重複身分：")
            for g in shown.prefix(AmbiguityDisplayLimit.rows) {
                let aliases = g.names.map { displaySafe($0, max: 200) }.joined(separator: " ≡ ")
                print("  ×\(g.occurrences)  \(aliases)")
                print("      共鍵：\(g.sharedKeys.map { displaySafe($0, max: 200) }.joined(separator: "、"))")
            }
            if shown.count > AmbiguityDisplayLimit.rows {
                print("  …另 \(shown.count - AmbiguityDisplayLimit.rows) 筆未顯示（完整清單用 --json）")
            }
            print("  處置：同鍵只代表**值得看**，不代表同一人——寬鬆層的縮寫／重排共鍵"
                  + "經常是不同的人（實例：Chien-Hsun Wang／Chung-Ho Wang／Chih-Hsiung Wang）。"
                  + "查證後——是同一人 → add-person <key> --name <寫法1> --name <寫法2> …（一次帶齊）；"
                  + "是不同人 → 各自 add-person 指定不同 key。兩者都讓這些寫法成為 exact alias，"
                  + "下次本命令即隱形、交由 resolve-people 歸戶。判不出來就不建——"
                  + "literal 留在誠實狀態是合法終點。")
            print("  ⚠ 本段**不涵蓋羅馬化異拼**（Hsu↔Xu 這類）：那是查表域，"
                  + "LooseNameKey 刻意不在任何鍵空間收斂。看不到不等於沒有。")
        }

        func printUnkeyable() {
            let shown = report.unkeyable.filter { $0.occurrences >= minOccurrences }
            guard !shown.isEmpty else { return }
            print("")
            print("產不出 key、**需要你指定**（\(shown.count)）——不是不存在，是機器不該猜：")
            for u in shown.prefix(AmbiguityDisplayLimit.rows) {
                let aliases = u.names.map { displaySafe($0, max: 200) }.joined(separator: " ≡ ")
                print("  ×\(u.occurrences)  \(aliases)")
                print("      \(displaySafe(u.reason, max: 200))")
            }
            if shown.count > AmbiguityDisplayLimit.rows {
                print("  …另 \(shown.count - AmbiguityDisplayLimit.rows) 筆未顯示")
            }
            print("  處置：用 akashic add-person <key> --name <名> 指定 key（例如羅馬化或機構慣用寫法）。")
        }

        guard !cands.isEmpty else {
            print("無建檔候選（可能：literal 已有對應 person／低於 --min-occurrences 門檻／"
                  + "與既有 person 寬鬆共鍵而在下方 pending 清單）")
            printPendingResolution()   // R2-fix R3-8：零建檔候選時 pending 更該被看見
            printPendingMutual()       // #547：同上——零候選時它更該被看見
            printUnkeyable()   // 沒有候選時，這些**更**該被看見
            return
        }
        // #547：顯示上限改用 `AmbiguityDisplayLimit.rows`。此前是寫死的 `20`，
        // 而同一個檔案裡 pending／unkeyable 兩段用的是 `rows`（50）——同一個概念
        // （一份 bootstrap 報告印幾列）兩個數字、兩個來源，正是
        // `no-compat-fallback` §「同一件事只能有一份描述」的形狀。
        for c in cands.prefix(apply ? 0 : AmbiguityDisplayLimit.rows) {
            let aliases = c.names.map { displaySafe($0, max: 200) }.joined(separator: " ≡ ")
            print("  \(displaySafe(c.key, max: 200))  ×\(c.occurrences)  \(aliases)")
        }
        if !apply {
            if total > AmbiguityDisplayLimit.rows {
                print("  …共 \(total) 個（只列前 \(AmbiguityDisplayLimit.rows)；完整清單用 --json）")
            }
        printPendingResolution()
            printPendingMutual()
            printUnkeyable()
            print("（只列候選；要建立加 --apply）")
            return
        }
        var written = 0
        var skippedExisting: [String] = []
        for p in PersonBootstrap.personsFor(cands) {
            // quarantine 覆寫防護（#232 verify NEW-3）：決定性 UUID 讓「同 key 再
            // bootstrap」落到**同一個檔名**。被舊 binary quarantine 的記錄不在
            // load.people 裡，其 literal 因此會被再次提名——直接覆寫會安靜銷毀
            // 原記錄的全部內容（含判定史），退出狀態還是 ✓。既有檔不歸 bootstrap
            // 管：跳過並報告（同 addPerson「不覆寫 quarantined 檔」的既有立場）。
            let dest = store.usesEntitiesLayout
                ? store.entityURL(id: p.id) : store.personURL(key: p.key)
            guard !FileManager.default.fileExists(atPath: dest.path) else {
                skippedExisting.append(p.key)
                continue
            }
            try store.writePerson(p)
            written += 1
        }
        if !skippedExisting.isEmpty {
            print("⚠ 跳過 \(skippedExisting.count) 個：目的檔已存在（可能是 quarantined 記錄"
                  + "——先看 doctor 報告處理，不覆寫）")
            for k in skippedExisting.prefix(10) { print("  ⚠ \(displaySafe(k, max: 200))") }
        }
        _ = try LibraryIndex(store: store).rebuild()
        print("✓ 建立 \(written) 個 person（共 \(total) 個候選）、index 已重建")
        printPendingResolution()
        printUnkeyable()
        print("  下一步：akashic resolve-people 把 entries 的 literal 歸戶")
        // 跳過（目的檔已存在）＝有事要人處理——exit 1 讓 && chain 不若無其事往下走
        if !skippedExisting.isEmpty { throw ExitCode(1) }
    }
}

/// #70 第三題：從 literal 機構名建立 organization 記錄（門檻同 bootstrap-people）。
struct BootstrapOrganizations: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "bootstrap-organizations",
        abstract: "從 literal 機構名（affiliations／parents）建立 organization 記錄")

    @OptionGroup var options: LibraryOptions
    @Flag(name: .long, help: "實際寫入（預設只列出）") var apply = false
    @Option(name: .long, help: "只處理出現次數 ≥ N 的（投報率優先）") var minOccurrences: Int = 1
    @Option(name: .long, help: "最多處理前 N 個") var limit: Int?

    func run() throws {
        // #298：破壞性寫入前確認目標 store 已被指名。**只在 --apply 時**
        // ——dry-run 不得被擋（它不寫東西，且正是用來確認目標的手段）。
        if apply { try options.assertDestructiveTargetNamed("bootstrap-organizations") }
        let store = try options.openStore()
        let load = try store.load()
        // #378：作者位的團體 literal 也是機構名的來源
        let result = OrgBootstrap.result(people: load.people,
                                         organizations: load.organizations,
                                         entries: load.entries)
        var cands = result.candidates.filter { $0.occurrences >= minOccurrences }
        let total = cands.count
        if let limit { cands = Array(cands.prefix(limit)) }

        // #154 verify 154-1：產不出合法 key 的機構名**不靜默丟**——含 CJK 的名字
        // （台灣機構的雙語寫法最常見）無 ASCII token 時無法 slug，要明列，否則
        // 使用者以為「都建好了」。過濾門檻同 candidates。
        let dropped = result.dropped.filter { $0.occurrences >= minOccurrences }
        func reportDropped() {
            guard !dropped.isEmpty else { return }
            print("另有 \(dropped.count) 個機構名無法自動產生 key（含非 ASCII、需人工指定）：")
            for d in dropped.prefix(20) {
                print("  ⚠ 「\(displaySafe(d.name, max: 200))」 ×\(d.occurrences)")
            }
            if dropped.count > 20 { print("  …共 \(dropped.count) 個") }
        }

        guard !cands.isEmpty else {
            if dropped.isEmpty {
                print("無候選（literal 機構名皆已有對應 organization，或全部低於門檻）")
            } else {
                print("無可自動建立的候選——但有機構名產不出 key（見下）")
                reportDropped()
            }
            return
        }
        for c in cands.prefix(apply ? 0 : 20) {
            let aliases = c.names.map { displaySafe($0, max: 200) }.joined(separator: " ≡ ")
            print("  \(displaySafe(c.key, max: 200))  ×\(c.occurrences)  \(aliases)")
        }
        if !apply {
            if total > 20 { print("  …共 \(total) 個（只列前 20）") }
            reportDropped()
            print("（只列候選；要建立加 --apply）")
            return
        }
        // #154 verify 154-8：per-item 收容（同 ResolveOrganizations 與 ResolvePeople
        // 的既有紀律）——中途失敗不得讓其餘候選連試都沒試，也不得吞掉已建立的清單。
        var written = 0
        var failed: [(key: String, why: String)] = []
        var skippedExisting: [String] = []
        for o in OrgBootstrap.organizationsFor(cands) {
            // quarantine 覆寫防護（#232 verify NEW-3）——同 bootstrap-people
            guard !FileManager.default.fileExists(atPath: store.entityURL(id: o.id).path) else {
                skippedExisting.append(o.key)
                continue
            }
            do {
                try store.writeOrganization(o)
                // #154 verify 附帶：apply 時列出建了什麼（先前一筆都不印）
                print("  ✓ \(displaySafe(o.key, max: 200))  "
                      + o.names.entries.map { displaySafe($0.value, max: 200) }.joined(separator: " ≡ "))
                written += 1
            } catch {
                failed.append((key: o.key, why: "\(error)"))
            }
        }
        if !skippedExisting.isEmpty {
            print("⚠ 跳過 \(skippedExisting.count) 個：目的檔已存在（可能是 quarantined 記錄"
                  + "——先看 doctor 報告處理，不覆寫）")
            for k in skippedExisting.prefix(10) { print("  ⚠ \(displaySafe(k, max: 200))") }
        }
        if !failed.isEmpty {
            print("write failed（單筆寫入失敗，已略過續跑）: \(failed.count)")
            for f in failed {
                print("  ✗ \(displaySafe(f.key, max: 200)) — \(displaySafe(f.why, max: 512))")
            }
        }
        _ = try LibraryIndex(store: store).rebuild()
        if failed.isEmpty, skippedExisting.isEmpty {
            print("✓ 建立 \(written) 個 organization（共 \(total) 個候選）、index 已重建")
        } else if failed.isEmpty {
            print("⚠ 部分完成：建立 \(written) 個、跳過 \(skippedExisting.count) 個既有檔、index 已重建")
        } else {
            print("⚠ 部分完成：建立 \(written) 個、\(failed.count) 個失敗、index 已重建")
        }
        // exit code 見下方 reportDropped 之後——**不能在這裡 throw**，否則會吞掉
        // dropped 清單與「下一步」提示（#154 verify 154-13）
        // #154 verify 154-9：**這個呼叫點先前零測試覆蓋**——刪掉它全套 965 綠。
        // `--apply` 是使用者最容易認定「做完了」的時刻，也是唯一留下永久痕跡的路徑。
        reportDropped()
        print("  下一步：akashic resolve-organizations 把 affiliations 與 parents 的 literal 歸戶")
        // #154 verify 154-13：部分失敗時 exit 1，與 `resolve-organizations` 對齊。
        // 先前只有 resolve 側 throw——而 `--apply` 正是最常被 chain 的一步（輸出
        // 自己就寫著「下一步：…」），bootstrap 半途失敗時
        // `bootstrap-organizations --apply && resolve-organizations --apply`
        // 會若無其事往下走。**放在 reportDropped 與「下一步」之後**，否則會吞掉它們。
        if !failed.isEmpty || !skippedExisting.isEmpty { throw ExitCode(1) }
    }
}

/// #70 第二題：literal 機構名 → organization key 的高信心歸戶（絕不自動合併）。
/// CLI 歧義段的顯示上限（#236 R2）。
///
/// **兩個面都要有**——先前只給 MCP 加。終端機灌爆與 LLM context 灌爆是同一類威脅
/// （`TerminalOutputSafetyTests` 明文：「MCP/LLM context 的無上限灌注同型」），而
/// 「修一個面就宣稱這一類關掉了」正是本 PR 前一輪被抓到的形狀。
///
/// 超出時**說出來**（印剩餘筆數）——靜默截斷會讓「沒有更多」與「沒給你更多」
/// 無法區分。
enum AmbiguityDisplayLimit {
    static let rows = 50
    /// 單筆歧義的候選數也無上界（同名的人可以有任意多個）。
    static let refs = 20
    /// 每人印幾個異名。丟掉的必須數出來——見 `namesLabel`。
    static let names = 4
    /// 歧義段的**位元組**上限（#236 R4）。
    ///
    /// 列數（`rows`）與 ref 數（`refs`）都是計數，而 `literal`／`key`／隸屬名各自
    /// 可以吃滿自己的 `max:`，再被 `displaySafe` 膨脹 8 倍——席位實測列數與 ref 上限
    /// 都在的情況下仍產出 **3,844,596 bytes**（org 側 447,377）。
    ///
    /// 128 KB：終端機可捲、但不會把 scrollback 沖掉。與 MCP 的 48 KB 不同值是刻意的
    /// ——那邊的消費端是 LLM context（更貴），這邊是人的終端機。
    static let bytes = 128 * 1024
}

/// 印一個人的異名，**丟掉的要說出來**（#236 R4）。
///
/// 先前是 `prefix(4)` 直接截，於是「這人只有四個異名」與「有七個、你看到四個」
/// 在終端上長得一模一樣。這在歧義判斷的情境特別糟：使用者正是要靠異名分辨兩個
/// 同名的人，而被藏起來的那三個可能就是決定性的那個。
///
/// 與 MCP 的 `namesTotal` 同一個決定、不同的表達：那邊送分母讓程式判斷，這邊
/// 印差額讓人一眼看到。
func namesLabel(_ names: [String]) -> String {
    let shown = names.prefix(AmbiguityDisplayLimit.names).map { displaySafe($0, max: 80) }
    let dropped = names.count - shown.count
    return shown.joined(separator: "、") + (dropped > 0 ? " …+\(dropped)" : "")
}

/// 把 `DateRange` 的**四個**欄位都表示出來（#236 R2）。
///
/// `start`/`end` 之外還有 `endedUnknown`（#63：已結束但時點未知——43 位退休 PI 的
/// 實際狀態）與 `attested`（#70：只有觀測點）。只讀前兩者會讓**已離職**與**現職**
/// 印得逐位元組相同，而那正是 #63 被加進來要解決的事。
///
/// 回傳空字串代表「沒有任何時間資訊」——呼叫端據此決定要不要印括號。
/// **消毒在這裡，呼叫端不得再包一次**——`displaySafe` 逃脫反斜線自身、**不冪等**
/// （二次呼叫把 `\u{0009}` 變成 `\u{005C}u{0009}`），兩層會毀掉輸出。
func rangeLabel(_ r: DateRange) -> String {
    // **內聯 `displaySafe`，不用區域別名**——`DisplaySinkCoverageTests` 是文字掃描，
    // 別名會讓它認不出消毒已經發生，於是守衛失效而程式看起來沒問題。
    if !r.attested.isEmpty {
        let pts = r.attested.prefix(4).map { displaySafe($0, max: 24) }.joined(separator: "、")
        return "觀測:\(pts)\(r.attested.count > 4 ? "…" : "")"
    }
    switch (r.start, r.end, r.endedUnknown) {
    case (nil, nil, false):     return ""
    case (nil, nil, true):      return "已結束・時點未知"
    case let (s?, nil, false):  return "\(displaySafe(s, max: 24))–"
    case let (s?, nil, true):   return "\(displaySafe(s, max: 24))–已結束・時點未知"
    case let (nil, e?, _):      return "–\(displaySafe(e, max: 24))"
    case let (s?, e?, _):       return "\(displaySafe(s, max: 24))–\(displaySafe(e, max: 24))"
    }
}

struct ResolveOrganizations: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "resolve-organizations",
        abstract: "列出 literal→organization 高信心候選；--apply 才寫入")

    @OptionGroup var options: LibraryOptions
    @Flag(name: .long, help: "套用候選（顯式人工確認）；可用 --holder / --org 收窄") var apply = false
    /// #166：`--person` 更名為 `--holder`——候選的持有者現在可能是 organization
    /// （parents 側），叫 `--person` 會讓「篩掉了什麼」與旗標名字不符。
    /// **舊名保留為 alias**：它是既有使用者手上的指令，靜默移除會讓腳本壞掉。
    /// **兩個命名空間混用**（#166 verify MEDIUM）：person key 與 org key 可以同名
    /// （`Divergence.swift` 的 candidate doc 明載那是刻意的）。`--holder ntu` 會同時
    /// 命中 person `ntu` 與 organization `ntu` 的候選。輸出區分得出（`person X` /
    /// `org X`），旗標選不出來——help 明講，不假裝它能。
    @Option(name: [.customLong("holder"), .customLong("person")], parsing: .upToNextOption,
            help: "只套用這些持有者 key 的候選（person 或 organization；--person 為舊名）⚠ 兩個命名空間混用：同名的 person 與 organization 會一起命中")
    var holder: [String] = []
    @Option(name: .long, parsing: .upToNextOption,
            help: "只套用指向這些 organization key 的候選") var org: [String] = []

    /// #232 design D6 的 org 族。person 面用 rowID（citekey:authorIndex），這裡沒有
    /// 對應的穩定把手（候選定位是 holder × timeline 段），所以沿用**本命令既有的**
    /// 選取機制：--reject 對收窄後的候選寫 verdict，且**必須**帶收窄條件——
    /// 全庫盲掃否決是把一次判斷放大成批次動作。
    @Flag(name: .long,
          help: "否決收窄後的候選（寫 resolution-rejected verdict 到被判定的 organization；必須帶 --holder / --org）")
    var reject = false

    func run() throws {
        // #298：破壞性寫入前確認目標 store 已被指名。**只在 --apply 時**
        // ——dry-run 不得被擋（它不寫東西，且正是用來確認目標的手段）。
        if apply { try options.assertDestructiveTargetNamed("resolve-organizations") }
        if apply, reject {
            throw ValidationError("--apply 與 --reject 不可同用（相反的 verdict）——分兩次呼叫")
        }
        if reject, holder.isEmpty, org.isEmpty {
            throw ValidationError("--reject 必須帶 --holder / --org 收窄——否決是逐配對的判斷，不是批次動作")
        }
        let store = try options.openStore()
        let load = try store.load()
        // #232 design D5：已否決配對從 organization 的 verdict references 現算
        let orgRejected = ResolutionLedger.rejectedPairings(organizations: load.organizations)
        let orgReport = OrgResolver.resolve(people: load.people, organizations: load.organizations,
                                            rejected: orgRejected, entries: load.entries)
        let all = orgReport.candidates
        let hkSet = Set(holder), okSet = Set(org)
        let candidates = all.filter {
            (hkSet.isEmpty || hkSet.contains($0.holder.key))
                && (okSet.isEmpty || okSet.contains($0.orgKey))
        }
        // 持有者可能是 person 或 organization——**標出來**。少了它，兩類候選在
        // 輸出裡長得一樣，而它們寫進的是不同記錄的不同欄位（#166）。
        func label(_ h: OrgResolutionCandidate.Holder) -> String {
            switch h {
            case let .person(k): return "person \(displaySafe(k, max: 200))"
            case let .organization(k): return "org \(displaySafe(k, max: 200))"
            // #378：作者位——**帶索引**，因為同一筆可能有多個團體作者，
            // 而少了它使用者無法知道要看哪一個位置。
            case let .work(citekey, i): return "work \(displaySafe(citekey, max: 200))[\(i)]"   // display-safe-exempt: i 是 Int 陣列索引、非 store 字串；citekey 已消毒
            }
        }
        // Holder → verdict 的 kind token（#232：kind 屬配對身分——person/org key
        // 可合法同名，見 ResolutionPairing 的 doc）
        func pairingKind(_ h: OrgResolutionCandidate.Holder)
            -> ProvenanceReference.VerdictHolderKind {
            switch h {
            case .person: return .person
            case .organization: return .org
            // #378：`VerdictHolderKind` 已有 `.work`（person-resolution 的 holder
            // 就是 entry citekey），值域不必動——作者位的 holder 本來就是 work。
            case .work: return .work
            }
        }

        /// #231：歧義不再靜默丟棄。每個候選 org 帶當前名稱，讓人能分辨
        /// 「兩個真的不同的機構同名」與「同一機構兩筆記錄」。
        func printOrgAmbiguities() {
            guard !orgReport.ambiguities.isEmpty else { return }
            let byKey = Dictionary(load.organizations.map { ($0.key, $0) },
                                   uniquingKeysWith: { a, _ in a })
            print("")
            // 位元組預算，同 person 側（#236 R4：org 側實測 447,377 bytes）
            let cappedOrg = Array(orgReport.ambiguities.prefix(AmbiguityDisplayLimit.rows))
            var orgLines: [String] = []
            var orgBytes = 0
            var orgBudgetDropped = 0
            for a in cappedOrg {
                // **段的效期要印**——同一 holder 的多段同名 literal 否則長得一模一樣，
                // 使用者無法按時段分別判給不同機構（#236 R1）。
                // **四個欄位都要看**（#236 R2，5 個 finding 命中同一處）。只讀
                // (start, end) 會把 `endedUnknown`（#63：已結束、時點未知）印成
                // 「x–」＝進行中，把**已離職**的隸屬顯示得與現職**逐位元組相同**。
                // `attested`（#70：只有觀測點、起訖皆不明）同樣被吃掉。
                // repo 對這個塌縮有明文事故紀錄——那正是 #63／#70 存在的理由。
                let span = rangeLabel(a.range)   // display-safe-exempt: rangeLabel 內部已消毒；displaySafe 不冪等，不得再包
                var row: [String] = []
                row.append("  \(label(a.holder)) 「\(displaySafe(a.literal, max: 200))」\(span)")
                if a.orgKeys.count > AmbiguityDisplayLimit.refs {
                    row.append("      （\(a.orgKeys.count) 個候選，以下顯示前 \(AmbiguityDisplayLimit.refs) 個）")
                }
                for (n, k) in a.orgKeys.prefix(AmbiguityDisplayLimit.refs).enumerated() {
                    let o = byKey[k]
                    let founded = o?.founded.map { "  成立:\(displaySafe($0, max: 20))" } ?? ""
                    let dissolved = o?.dissolved.map { "  解散:\(displaySafe($0, max: 20))" } ?? ""
                    let name = o?.displayName ?? k
                    row.append("      \(n + 1). \(displaySafe(k, max: 200))  [\(displaySafe(name, max: 200))]\(founded)\(dissolved)")
                }
                let cost = row.reduce(0) { $0 + $1.utf8.count + 1 }
                if orgBytes + cost <= AmbiguityDisplayLimit.bytes {
                    orgBytes += cost
                    orgLines.append(contentsOf: row)
                } else {
                    orgBudgetDropped += 1   // 吃不下的整列不印，不留半截
                }
            }
            let orgShownCount = cappedOrg.count - orgBudgetDropped
            let orgHeadline: String   // 同 person 側：預算跳過過大的列時，顯示的不是前綴
            if orgReport.ambiguities.count <= orgShownCount { orgHeadline = "" }
            else if orgBudgetDropped > 0 { orgHeadline = "，以下顯示 \(orgShownCount) 筆（非前綴：過大的整筆略過）" }
            else { orgHeadline = "，以下顯示前 \(orgShownCount) 筆" }
            print("歧義（\(orgReport.ambiguities.count)\(orgHeadline)）"
                  + "——同一個 literal 對到 2+ 個 org，**需要人判斷**：")
            for l in orgLines { print(l) }
            let orgHidden = orgReport.ambiguities.count - orgShownCount
            if orgHidden > 0 {
                let byRows = orgReport.ambiguities.count - cappedOrg.count
                var why: [String] = []
                if byRows > 0 { why.append("\(byRows) 筆超過列數上限") }
                if orgBudgetDropped > 0 { why.append("\(orgBudgetDropped) 筆內容過大、吃不下輸出預算") }
                print("  …另 \(orgHidden) 筆未顯示（\(why.joined(separator: "；"))）")
            }
            print("  兩種可能，處置相反：同名的不同機構＝各自歸戶（永不合併）；同一機構兩筆＝該合併。")
        }

        // #232 design D7：三態計數與已否決沉底——名單與計數同 MCP 來源
        // （ResolutionLedger），CLI 只排版。
        func printOrgCountsAndSunk() {
            // holder 的 kind 來自 verdict value 的 kind token（verify C-3——
            // 同名 person／org 各自的配對各自呈現，不再「先猜 person」）
            for s in ResolutionLedger.observedRejections(organizations: load.organizations,
                                                         people: load.people) {
                print("  (已否決) \(s.holderKind.rawValue) \(displaySafe(s.holder, max: 200)) 「\(displaySafe(s.literal, max: 200))」 ↛ \(displaySafe(s.judgedKey, max: 200))")
            }
            for m in ResolutionLedger.malformedVerdicts(people: [],
                                                        organizations: load.organizations)
                .prefix(20) {
                print("  ⚠ malformed verdict（不計數、不抑制）：\(displaySafe(m, max: 300))")
            }
            let triples = all.map {
                ResolutionPairing(holderKind: pairingKind($0.holder),
                                  holder: $0.holder.key, literal: $0.literal,
                                  judgedKey: $0.orgKey)
            }
            let c = ResolutionLedger.counts(organizations: load.organizations,
                                            candidatePairings: triples)[
                ResolutionLedger.orgRule] ?? (0, 0, 0)
            print("三態計數（\(ResolutionLedger.orgRule)）：已確認 \(c.confirmed)／已否決 \(c.rejected)／未處理 \(c.pending)")
        }

        // reject（#232 design D6）：對收窄後的候選寫 verdict，holder 記錄**不動**
        // （reject 不是套用）。寫入落被判定的 organization，per-item 收容同 apply。
        if reject {
            if candidates.isEmpty {
                throw ValidationError("--holder / --org 的篩選條件沒有命中任何候選"
                    + "（共 \(all.count) 個候選）——先不帶 --reject 列出候選確認 key")
            }
            let orgByKey = Dictionary(load.organizations.map { ($0.key, $0) },
                                      uniquingKeysWith: { a, _ in a })
            var grouped: [String: Organization] = [:]
            for c in candidates {
                guard var o = grouped[c.orgKey] ?? orgByKey[c.orgKey] else { continue }
                // appendIfAbsent：同 holder 兩段同名 affiliation 產出兩筆相同候選時，
                // verdict 只落一筆——計數不灌水（verify F(a)）
                ResolutionLedger.appendIfAbsent(ResolutionLedger.record(
                    .rejected, holderKind: pairingKind(c.holder),
                    holder: c.holder.key, literal: c.literal,
                    rule: ResolutionLedger.orgRule,
                    statement: "resolve reject：使用者否決此配對"), to: &o.references)
                grouped[c.orgKey] = o
            }
            var wrote = 0
            var failed: [(String, String)] = []
            for key in grouped.keys.sorted() {
                do { try store.writeOrganization(grouped[key]!); wrote += 1 }
                catch { failed.append((key, "\(error)")) }
            }
            // 先報失敗再 rebuild（R9/M8 紀律）：rebuild 擲錯不得吞掉清單
            if !failed.isEmpty {
                print("write failed（單筆寫入失敗，已略過續跑）: \(failed.count)")
                for (k, why) in failed { print("  ✗ org \(displaySafe(k, max: 200)) — \(displaySafe(why, max: 512))") }
            }
            _ = try LibraryIndex(store: store).rebuild()
            if failed.isEmpty {
                print("✓ 否決 \(candidates.count) 筆配對、改寫 \(wrote) 個 organization、index 已重建")
            } else {
                print("⚠ 部分完成：改寫 \(wrote) 個 organization、\(failed.count) 個失敗、index 已重建")
                throw ExitCode(1)
            }
            return
        }

        guard !all.isEmpty else {
            print("無候選（affiliation／parents 的 literal 皆無 org name 完全命中）")
            printOrgCountsAndSunk()   // 沒有候選 ≠ 沒有歷史——已否決與計數照樣要看得見
            printOrgAmbiguities()   // 沒有唯一候選時，歧義**更**該被看見
            return
        }
        let selected = Set(candidates.map { "\($0.holder)#\($0.literal)" })   // display-safe-exempt: 內部 Set 的成員判定鍵，不進輸出面
        for c in all {
            let mark = (apply && !selected.contains("\(c.holder)#\(c.literal)")) ? "  (skip) " : "  "
            print("\(mark)\(label(c.holder)) 「\(displaySafe(c.literal, max: 200))」 → \(displaySafe(c.orgKey, max: 200))（\(displaySafe(c.reason, max: 300))）")
        }
        printOrgCountsAndSunk()
        printOrgAmbiguities()
        if apply {
            if !(holder.isEmpty && org.isEmpty), candidates.isEmpty {
                throw ValidationError("--holder / --org 的篩選條件沒有命中任何候選")
            }
            // #154 verify 154-8：per-item 收容 + 先報告再 rebuild + `✓` 只在全綠。
            //
            // 原本 `try store.writePerson(p)` 直接往外擲，實測（三人命中同一 org、
            // 中間那個檔案設 `uchg`）：第一個寫入、第二個失敗、第三個**從未被嘗試**、
            // index 從未重建，而使用者只拿到一句 Foundation 原始錯誤，看不到哪些已經
            // 落地。同一個檔案的 `ResolvePeople` 早為此修過三輪（R7/M21 per-item
            // 收容、R9/M8 先印再 rebuild、R8/L29 `✓` 只在全綠）——org 側三條全沒
            // 帶過來。這不是新設計，是把既有紀律平移。
            let updated = OrgResolver.apply(candidates, to: load.people,
                                            organizations: load.organizations,
                                            entries: load.entries)
            // **person 與 organization 分開計數**（#166 verify）：`written` 現在同時
            // 累計兩者，而訊息仍寫「N 個 person」——沙箱實測「一個 person 都沒有」
            // 時照樣印「改寫 1 個 person」。本 change 之前 `written` 只數 person，
            // 那時是對的。同一個 block 的相鄰註解自己就寫著「報寫入數不是候選數
            // ——先前用 candidates.count，失敗時誇報」。
            var wroteP = 0, wroteO = 0
            // 失敗清單也要**標類別**：person key 與 org key 可以同名，而這正是本
            // change 在 30 行之上剛替候選列表修好的東西。
            var failed: [(kind: String, key: String, why: String)] = []
            for p in updated.people where !load.people.contains(where: { $0 == p }) {
                do {
                    try store.writePerson(p)
                    wroteP += 1
                } catch {
                    failed.append((kind: "person", key: p.key, why: "\(error)"))
                }
            }
            // entry 側（#378 的作者位歸戶）走**同一套** per-item 收容。
            // #154 verify 154-8 的教訓是「org 側三條全沒帶過來」；新增第三種寫入
            // 目標時同樣不能漏——所以這裡不是新設計，是第三次平移同一套紀律。
            var wroteE = 0
            for e in updated.entries where !load.entries.contains(where: { $0 == e }) {
                do {
                    try store.writeEntry(e)
                    wroteE += 1
                } catch {
                    failed.append((kind: "work", key: e.citekey, why: "\(error)"))
                }
            }
            // organization 側走**同一套** per-item 收容（#154 verify 154-8 的紀律；
            // 那一輪的教訓正是「org 側三條全沒帶過來」——這次不要再漏一次）
            var updatedOrgs = updated.organizations
            for o in updatedOrgs where !load.organizations.contains(where: { $0 == o }) {
                do {
                    try store.writeOrganization(o)
                    wroteO += 1
                } catch {
                    failed.append((kind: "org", key: o.key, why: "\(error)"))
                }
            }
            // #232 design D6 對稱：apply 的**同一動作**內寫 resolution-confirmed
            // verdict 到被判定的 organization——但**只寫 holder 記錄改寫成功的那些**
            // （verify C-2：誇報 verdict 比漏寫更糟，person 面在 AkashicService 有
            // 同一道閘）。第二輪獨立寫入、獨立回報，排在 rebuild 之前。
            let failedHolderKeys = Set(failed.map { "\($0.kind):\($0.key)" })   // display-safe-exempt: 內部 Set 的成員判定鍵，不進輸出面
            func holderFailed(_ h: OrgResolutionCandidate.Holder) -> Bool {
                switch h {
                case let .person(k): return failedHolderKeys.contains("person:\(k)")
                case let .organization(k): return failedHolderKeys.contains("org:\(k)")
                case let .work(citekey, _): return failedHolderKeys.contains("work:\(citekey)")
                }
            }
            let orgIdx = Dictionary(updatedOrgs.enumerated().map { ($0.element.key, $0.offset) },
                                    uniquingKeysWith: { a, _ in a })
            var confirmTargets = Set<String>()
            for c in candidates where !holderFailed(c.holder) {
                guard let i = orgIdx[c.orgKey] else { continue }
                if ResolutionLedger.appendIfAbsent(ResolutionLedger.record(
                    .confirmed, holderKind: pairingKind(c.holder),
                    holder: c.holder.key, literal: c.literal,
                    rule: ResolutionLedger.orgRule,
                    statement: "resolve apply：使用者確認歸戶"),
                    to: &updatedOrgs[i].references) {
                    confirmTargets.insert(c.orgKey)
                }
            }
            var confirmFailed: [(String, String)] = []
            for key in confirmTargets.sorted() {
                guard let i = orgIdx[key] else { continue }
                do { try store.writeOrganization(updatedOrgs[i]) }
                catch { confirmFailed.append((key, "\(error)")) }
            }
            // **先報失敗**：rebuild 可能自己再擲一次，那會把上面的清單吞掉
            if !failed.isEmpty {
                print("write failed（單筆寫入失敗，已略過續跑）: \(failed.count)")
                for f in failed {
                    print("  ✗ \(f.kind) \(displaySafe(f.key, max: 200)) — \(displaySafe(f.why, max: 512))")
                }
            }
            if !confirmFailed.isEmpty {
                print("confirmed verdict 寫入失敗（歸戶已落地、verdict 未落地）: \(confirmFailed.count)")
                for (k, why) in confirmFailed {
                    print("  ✗ org \(displaySafe(k, max: 200)) — \(displaySafe(why, max: 512))")
                }
            }
            _ = try LibraryIndex(store: store).rebuild()
            // `✓` 只在全綠。報**寫入數**不是候選數——先前用 candidates.count，失敗時誇報
            if failed.isEmpty, confirmFailed.isEmpty {
                // #378：**三種寫入目標都要報**。少報一種就是 `lossless-intake`
                // 執行細節 3 的靜默形式——實測第一次跑時 4 筆 entry 已寫入，
                // 而訊息印「改寫 0 個 person / 0 個 organization」，看起來什麼都沒做。
                print("✓ 歸戶 \(candidates.count) 筆、改寫 \(wroteP) 個 person / "
                      + "\(wroteO) 個 organization / \(wroteE) 個 work、index 已重建")
            } else if failed.isEmpty {
                print("⚠ 歸戶完成但 \(confirmFailed.count) 筆 confirmed verdict 未落地、index 已重建")
                throw ExitCode(1)
            } else {
                print("⚠ 部分完成：改寫 \(wroteP) 個 person / \(wroteO) 個 organization / "
                      + "\(wroteE) 個 work、\(failed.count) 個失敗、index 已重建")
                // **throw 必須在本次執行所有該印的東西之後**（#154 verify R4 Q2）。
                // 這裡 `if apply` 區塊尾端目前沒有其他 print，所以就地 throw 成立；
                // 但**下一次可能被違反的正是這裡**——有人在區塊尾端加一行 print
                // 就會被這個 throw 吞掉，而且不會有任何東西提醒他。
                // （bootstrap-organizations 那邊因為 throw 之後還有 reportDropped 與
                // 「下一步」，所以 throw 放在函式最後。同一個不變式、不同位置。）
                throw ExitCode(1)
            }
        } else {
            print("（只列候選；要套用加 --apply）")
        }
    }
}

/// #21：WoS 匯出 → entries。
struct ImportWoS: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "import-wos",
        abstract: "匯入 Web of Science 的 tab-delimited 匯出（作者一律不自動歸戶）")

    @OptionGroup var options: LibraryOptions

    @Argument(help: "WoS 匯出檔（tab-delimited；xlsx 請先另存為 TSV）")
    var path: String

    @Flag(name: .long, help: "只回報會做什麼，不寫檔")
    var dryRun = false

    @Flag(name: .long, help: "來源是逗號分隔（CSV）而非 tab")
    var csv = false

    func run() throws {
        let store = try options.openStore()
        let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        let text = try String(contentsOf: url, encoding: .utf8)
        let r = try WoSImport.run(text: text, store: store,
                                  separator: csv ? "," : "\t", dryRun: dryRun)
        let prefix = dryRun ? "（dry-run）" : "✓"
        print("\(prefix) created \(r.created.count)、unchanged \(r.unchanged.count)"
            + (r.enriched.isEmpty ? "" : "、enriched \(r.enriched.count)（既有記錄補上缺的欄位）"))
        if !r.conflicts.isEmpty {
            // **不覆寫**：citekey 撞號且內容不同，可能是使用者手動改過的資料，
            // 而 WoS 的欄位比 store 的窄——覆寫會把人工補的資訊洗掉。
            print("conflicts（citekey 相同但內容不同，未覆寫）: \(r.conflicts.count)")
            for c in r.conflicts.prefix(10) { print("  ! \(displaySafe(c, max: 200))") }
        }
        if !r.skippedRows.isEmpty {
            print("skipped: \(r.skippedRows.count)")
            for s in r.skippedRows.prefix(5) { print("  - \(displaySafe(s, max: 300))") }
        }
        if !r.droppedColumns.isEmpty {
            // #206 規則 §3：丟棄必須可見。這兩種成因（欄位名不可表達、正規化後
            // 撞鍵）是殘餘收集**唯一**會漏掉東西的地方——不印就等於靜默。
            let s = r.droppedColumns.keys.sorted()
                .map { "\(displaySafe($0, max: 120))×\(r.droppedColumns[$0]!)" }
                .joined(separator: ", ")
            print("dropped columns（欄位名不可表達或撞鍵，未入庫）: \(s)")
        }
        if !r.aliasGroups.isEmpty {
            // 這是本 importer 的真正價值：兩欄同 index 對齊，免費得到每位作者的兩種寫法
            print("alias 配對: \(r.aliasGroups.count) 組（可餵給 people 的 names[]）")
            for g in r.aliasGroups.prefix(3) {
                print("  \(g.map { displaySafe($0, max: 200) }.joined(separator: " ≡ "))")
            }
        }
        if !dryRun, !r.created.isEmpty {
            _ = try LibraryIndex(store: store).rebuild()
            print("  index 已重建；作者全部為 .literal——用 akashic resolve-people 歸戶")
        }
    }
}

/// #22：Akashic → 關係式表格（DuckDB 為衍生）。
struct ExportTables: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "export-tables",
        abstract: "匯出 CSV + DuckDB 載入腳本（單向衍生；DuckDB 端不回寫）")

    @OptionGroup var options: LibraryOptions

    @Option(name: .shortAndLong, help: "輸出目錄")
    var output: String

    @Option(name: .long, help: "只匯出這個 view 的外延（判準在 ~/.akashic/config.yaml；被引用的合著者與機構閉包一併保留，維持外鍵完整）")
    var view: String?

    func run() throws {
        let store = try options.openStore()
        let load = try store.load()
        let dir = URL(fileURLWithPath: (output as NSString).expandingTildeInPath)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        var entries = load.entries
        var people = load.people
        var organizations = load.organizations
        if let viewKey = view {
            let config = try AkashicConfig.read(from: AkashicHome.configURL())
            guard let def = config.views[viewKey] else {
                throw ValidationError("config.yaml 沒有 view「\(displaySafe(viewKey, max: 200))」"
                                      + "（`akashic view list` 看有哪些）")
            }
            let ext = def.extension_(in: load)
            (entries, people, organizations) = ext.scope(load)
            // 空外延是合法結果（判準無人命中），不是錯誤——照常匯出空表
            print("view \(displaySafe(viewKey, max: 200))：person \(ext.people.count)、"
                  + "work \(ext.works.count)（researcher 表另含被引用的合著者 "
                  + "\(people.count - ext.people.count) 位）")
        }
        let tables = RelationalExport.tables(entries: entries, people: people,
                                            organizations: organizations)
        for t in tables.all {
            let url = dir.appendingPathComponent("\(t.name).csv")
            try RelationalExport.csv(t).write(to: url, atomically: true, encoding: .utf8)
            print("\(t.name): \(t.rows.count) 列 → \(url.lastPathComponent)")  // display-safe-exempt: t.name 是編譯期常數（RelationalExport 內寫死的表名），不含 store 衍生內容
        }
        let sql = dir.appendingPathComponent("load.sql")
        try RelationalExport.duckDBScript(csvDirectory: dir.path)
            .write(to: sql, atomically: true, encoding: .utf8)
        print("載入腳本 → \(sql.path)")
        print("  duckdb akashic.db -c \".read \(sql.path)\"")
        // 未歸戶作者是**狀態**不是缺漏，但值得說出數量——它是 resolve-people 的工作量
        let unresolved = tables.publicationAuthor.rows.filter { $0[2] == nil }.count
        if unresolved > 0 {
            print("  （\(unresolved) 筆作者未歸戶 → publication_author.researcher_id IS NULL）")
        }
    }
}

struct ExportBib: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "export-bib", abstract: ".bib 匯出（編譯產物；經 biblatex-apa-swift）")

    @OptionGroup var options: LibraryOptions

    @Option(name: .long, help: "輸出檔（預設 stdout）")
    var output: String?

    @Option(name: .long, help: "只匯出這些 citekeys（逗號分隔）")
    var citekeys: String?

    @Flag(name: .long, help: "改輸出 CSL-JSON")
    var cslJson = false

    func run() throws {
        let store = try options.openStore()
        let load = try store.load()
        var entries = load.entries
        if let filter = citekeys {
            let wanted = Set(filter.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) })
            entries = entries.filter { wanted.contains($0.citekey) }
            let missing = wanted.subtracting(entries.map(\.citekey))
            guard missing.isEmpty else {
                throw ValidationError("citekeys 不存在：\(missing.sorted().joined(separator: ", "))")
            }
        }
        let content: String = cslJson
            ? try CSLExport.cslJSON(entries: entries, people: load.people, venues: load.venues)
            : BibExport.bibFile(entries: entries, people: load.people,
                                venues: load.venues)
        // #326：APA7 完整性報告（warn-only，不改變匯出內容）。走 stderr，讓 stdout
        // 的 `.bib` 仍可被管線直接吃。CSL 路徑不跑——`BibValidator` 驗的是 biblatex
        // 欄位名。
        if !cslJson {
            let report = BibExport.apa7Report(entries: entries, people: load.people, venues: load.venues)
            for issue in report.issues {
                FileHandle.standardError.write(Data(
                    "[\(issue.severity.rawValue.uppercased())] \(displaySafe(issue.citekey, max: 200)): \(displaySafe(issue.message, max: 300))\n".utf8))
            }
            if !report.uncheckedCitekeys.isEmpty {
                // **「沒被檢查」必須說出來**——否則零 issue 會被讀成「已驗過」。
                FileHandle.standardError.write(Data(
                    "note: \(report.uncheckedCitekeys.count) 筆的 entry type 不在 APA7 必要欄位表內，未經檢查（見 #325）\n".utf8))
            }
        }
        if let output {
            // **寫檔不消毒**（#165）：匯出檔是**資料**不是顯示——消毒會破壞 .bib／
            // CSL-JSON 的正確性（下游 BibTeX 引擎讀到被截斷或跳脫過的內容會壞）。
            // 這條路徑的原始位元組保真是刻意的。
            try content.write(toFile: (output as NSString).expandingTildeInPath,
                              atomically: true, encoding: .utf8)
            print("寫出 \(entries.count) entries → \(displaySafe(output, max: 300))")
        } else {
            // **stdout 是顯示，要消毒**（#165）。verify 席行為探針實測：`title`／
            // `authors`／`fields` 裡的 raw ESC、U+202E、U+2028 **原樣通過** biblatex
            // 層——biblatex 跳脫的是 TeX specials（`{}` `\` `%` `&`），與 C0／bidi／
            // LS-PS 是兩組不相干的字元集。「跳脫由 biblatex 層負責」字面成立、實質全假。
            //
            // **用 `documentSafe` 不用 `displaySafe`**（#171 verify 171-2）：後者
            // 跳脫反斜線（反偽造），而反斜線在 .bib 與 JSON 裡**是內容語法**。
            // `export-bib > refs.bib`／`| pbcopy`／`| bibtool` 全走 stdout，而
            // stdout 是**預設**（`--output` 才是選項）——消毒破壞語法等於預設路徑
            // 產出壞檔。Zotero 匯入的書目帶 LaTeX 跳脫是常態，不是攻擊面。
            //
            // **不設行長上限**（171-3）：`BibWriter` 一個欄位一行，abstract 是
            // 常態欄位，4000 上限會把它截成大括號不閉合的無效 .bib，且靜默。
            // 截斷一份文件永遠產生壞掉的文件；終端的量由 store 大小自然界定，
            // 而那是使用者自己要的。MCP 側因為下游是 LLM context，改為拒絕。
            print(documentSafe(content), terminator: "")
        }
    }
}

struct ResolvePeople: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "resolve-people",
        abstract: "列出 literal→person 高信心候選；--apply 才寫入（絕不自動合併）")

    @OptionGroup var options: LibraryOptions

    @Flag(name: .long, help: "套用候選（顯式人工確認）；可用 --citekey / --person 收窄範圍")
    var apply = false

    /// #5：alias 完全命中**仍可能同名不同人**——people 庫還沒記錄第二個人時，
    /// 歧義偵測不會觸發。所以「全套用」對這種情境是危險的預設，必須能逐項挑。
    @Option(name: .long, parsing: .upToNextOption,
            help: "只套用這些 citekey 的候選（可重複；與 --person 取交集）")
    var citekey: [String] = []

    @Option(name: .long, parsing: .upToNextOption,
            help: "只套用指向這些 person key 的候選（可重複；與 --citekey 取交集）")
    var person: [String] = []

    /// R1-fix B1：#303 之後候選含四個信心層，裸 `--apply` 的爆炸半徑從
    /// exact-only 擴到全部——`--tier` 是把它收回來的把手。
    @Option(name: .long, parsing: .upToNextOption,
            help: "只套用這些提名層（exact / confirmed-elsewhere / reorder / initials，可重複；與其他篩選取交集）")
    var tier: [String] = []

    /// #232 design D6：reject 是顯式人為動作。rowID 同 MCP（citekey:authorIndex）。
    @Option(name: .long, parsing: .upToNextOption,
            help: "否決這些候選（三段形 citekey:authorIndex:personKey——釘 person，提名改指時顯式拒絕；兩段 legacy 形僅當該位置提名仍唯一時等價）——寫 resolution-rejected verdict 到該 person，entry 不動；之後該配對不再被提名（同 literal 他 entry 照提）")
    var reject: [String] = []

    /// 逐篇判定（change `per-work-judged-authorship`）。
    ///
    /// **單旗標兩段**而非兩個成對旗標：後者靠位置配對，數量不符會**靜默錯配**
    /// ——把 A 的理由掛到 B 的判定上。單旗標讓「配對沒有自己的 judgement」在語法上
    /// 寫不出來。
    ///
    /// **刻意不提供篩選式批次**（沒有 `--judge-all` 之類）：judgement 必填形成自然摩擦，
    /// 而批次會讓它退化成罐頭字串——罐頭 judgement 等於沒有判定。同 `mcp-cli-parity`
    /// 已載明的既有不對稱（tier 閘只加在 CLI 的篩選式批次）。
    @Option(name: .long, parsing: .upToNextOption,
            help: "逐篇判定（可重複）：citekey:authorIndex:personKey=判定理由。理由必填且逐字寫進 verdict；literal 由 store 讀。歧義列也適用——歧義的意思是提名器分不出來，不是人分不出來。不提供批次形式")
    var judge: [String] = []

    /// **團體作者的升格**（#443）：`.literal` → `.organization`。
    ///
    /// 與 `--judge` 同型（per-id 顯式指名、judgement 必填、不提供批次），差別只在
    /// 升格的目標是 organization 而不是 person。放在同一個命令是因為**作用對象相同**
    /// ——都是 work 的一個作者位；`Author` 的三態裡只有兩態接得起來，這條補第三態。
    ///
    /// **不是消歧**：org key 由呼叫端顯式給，不經提名，所以沒有 tier 也沒有候選清單。
    @Option(name: .customLong("attribute-org"), parsing: .upToNextOption,
            help: "把作者位歸給團體作者（可重複）：citekey:authorIndex:orgKey=判定理由。理由必填；org 需已存在（絕不自動建）；已歸戶的位置拒絕；整批驗證通過才寫")
    var attributeOrg: [String] = []

    /// **把黏在一起的作者位拆開**（#443）：一個 literal 裝了兩個人。
    ///
    /// **收分隔符而不是拆好的名字**——後者等於讓呼叫端編造，打錯一個字就寫進 store。
    /// 收分隔符則讓拆出的每一段必然是原文的子字串。切出空段即拒絕（分隔符選錯了）。
    ///
    /// 拆出來的仍是 `.literal`——拆是**形狀**修正不是身分判定，每一段各自走既有的消歧路徑。
    @Option(name: .customLong("split-author"), parsing: .upToNextOption,
            help: "把一個作者位拆成多個（可重複）：citekey:authorIndex:分隔符=理由。理由必填；分隔符不得含 =（第一個 = 之後一律是理由）、必須在該 literal 裡且切不出空段；只作用於未歸戶的位置；同一個作者位一次只能拆一次；同一筆 work 的多個位置一起拆時 index 位移由實作處理。原文與理由只進報告不進 store。不與其他腿組合")
    var splitAuthor: [String] = []

    /// `--split-author` 的具名逆操作（#513）。以值定位（citekey:原literal），還原後刪掉那筆記錄。
    @Option(name: .customLong("un-split"), parsing: .upToNextOption,
            help: "把拆分合回原 literal（可重複）：citekey:原literal。以值定位——原 literal 逐字取自 store 的拆分記錄（akashic get-entry 看得到）；還原後那筆記錄會被刪掉（理由見 service 的裁決 ②）。任一段已升格為 .key／.organization、各段不連續、或同 value 多筆記錄即整批拒絕、零寫入。不與其他腿組合")
    var unSplit: [String] = []

    /// **把一個作者位移除**（#457）：那一格裝的不是作者。
    ///
    /// 三態（`.key`／`.organization`／`.literal`）都假設背後有一個作者，而 PsycInfo 的
    /// `No authorship indicated` 不是——它今天在 `.bib` 裡是 `AUTHOR = {indicated, No authorship}`，
    /// 一個被捏造出來的人。以值定位（同 `--un-split`），理由必填，記錄留在 work 側。
    @Option(name: .customLong("drop-author"), parsing: .upToNextOption,
            help: "把一個作者位移除（可重複）：citekey:literal=理由。理由必填；以值定位（不用索引）；只作用於未歸戶的 .literal；同一筆 work 的作者位裡出現多次即拒絕不判定。移除記錄（field: authors、`移除：理由`）與作者位改寫同一次寫入，需要 store format ≥ 17。**沒有具名逆操作**——記錄留著被移除的字串，但不留位置。不與其他腿組合")
    var dropAuthor: [String] = []

    /// 判定式否決（#386 的鏡像）：查證後說「**不是他**」。
    ///
    /// 與既有 `--reject` 的差別：那個只吃 resolver 提名出來的**候選**，歧義列一律 notFound。
    /// 而對共用 literal 來說「不是他」才是絕大多數的答案——實測 69 筆歧義裡 22 筆已確定
    /// 答案不在候選裡。**entry 不動**（否決不歸戶），只寫 verdict。
    @Option(name: .long, parsing: .upToNextOption,
            help: "判定式否決（可重複）：citekey:authorIndex:personKey=否決理由。理由必填。歧義列也適用——既有 --reject 只吃候選。entry 不動，只寫 resolution-rejected verdict；之後該配對不再被提名")
    var refute: [String] = []

    /// 歧義段的列數上限（#388）。
    ///
    /// **加旋鈕不等於拆掉防線**：真正與內容無關的界是 `AmbiguityDisplayLimit.bytes`
    /// （128 KB），列數只是次級上限。所以放寬列數仍受位元組預算保護——超出時照樣
    /// 逐列略過並在結尾說出丟了幾筆。
    ///
    /// 缺這個旋鈕的代價實測過：#383 那輪為了拿完整的 100／73／71 筆清單，**三次**用
    /// 「暫時把常數改成 500、量完還原」的手法。那不是使用者做得到的事，正是
    /// `mcp-cli-parity` 所說「能不能做到，不該取決於使用者會不會改原始碼」。
    @Option(name: .long,
            help: "歧義段最多列出幾筆（預設 50）。位元組預算仍生效——放寬列數不保證全部印得出來")
    var rows: Int?

    /// 生效的列數上限：旗標優先，缺席退回預設。
    var rowLimit: Int { rows ?? AmbiguityDisplayLimit.rows }

    func run() throws {
        if let rows, rows < 1 {
            throw ValidationError("--rows 必須 ≥ 1（給了 \(rows)）——要看完整清單就給一個夠大的數；"
                                  + "位元組預算（\(AmbiguityDisplayLimit.bytes / 1024) KB）仍會擋住過大的內容")
        }
        try runResolve()
    }

    private func runResolve() throws {
        // #298：破壞性寫入前確認目標 store 已被指名。**只在 --apply 時**
        // ——dry-run 不得被擋（它不寫東西，且正是用來確認目標的手段）。
        if apply { try options.assertDestructiveTargetNamed("resolve-people") }
        // 同一次呼叫不可同時 apply 與 reject——那是兩個相反的 verdict
        if apply, !reject.isEmpty {
            throw ValidationError("--apply 與 --reject 不可同用（相反的 verdict）——分兩次呼叫")
        }
        // **兩個結構修正腿各自單獨呼叫，顯式拒絕組合**（R1 verify）：先前只有文件宣稱
        // 「不與其餘腿組合」而實作靠分支順序隱含達成——其餘腿被**靜默忽略**，呼叫端
        // 會以為兩腿都跑了。同型契約在 resolve-venues 是顯式 throw（#418），對齊。
        // #513：`--un-split` 加入這組——它同樣改作者位的**數量**（N → 1），與 `--split-author`
        // 是同一個理由的同一族。三者互斥且都不與其他腿組合。
        // #457：`--drop-author` 同族——它把作者位的數量改成 N-1（可到 0），與前三者同一個理由。
        let structuralLegs = [!splitAuthor.isEmpty, !attributeOrg.isEmpty, !unSplit.isEmpty,
                              !dropAuthor.isEmpty]
        if structuralLegs.contains(true) {
            let otherLegs = apply || !reject.isEmpty || !judge.isEmpty || !refute.isEmpty
            if structuralLegs.filter({ $0 }).count > 1 || otherLegs {
                throw ValidationError("--split-author／--attribute-org／--un-split／--drop-author 各自單獨呼叫"
                    + "（不得與其他腿或彼此組合）——它們改作者位的數量或值域，"
                    + "混在一批裡會讓其他腿的意義改變")
            }
        }
        let store = try options.openStore()

        // verdict 寫入走 **AkashicService**——與 MCP `akashic_resolve_people` 同一條
        // 實作路徑（mcp-cli-parity：兩條各自寫會分岔）。`key:` 不可省（#220 HIGH：
        // keyless 會分岔出第二份 index）。
        // 把黏在一起的作者位拆開（#443）——與其餘寫入腿同走 service。
        if !splitAuthor.isEmpty {
            let service = AkashicService(root: store.root, key: store.key,
                                         environment: ProcessInfo.processInfo.environment)
            let out = try service.splitAuthors(splitAuthor)
            let parsed = (try? JSONSerialization.jsonObject(with: Data(out.utf8))) as? [String: Any]
            let rows = (parsed?["split"] as? [[String: Any]]) ?? []
            print("✓ 拆開 \(rows.count) 個作者位、index 已重建")   // display-safe-exempt: Int
            for r in rows {
                let into = (r["into"] as? [String] ?? []).joined(separator: "、")
                // 逐筆印出「原文、用什麼切、切成什麼、為什麼」——分隔符與原文都被
                // 丟棄，而丟棄必須可見（R1 verify：先前只揭露了分隔符的丟棄，
                // 原文與理由不進 store、只在這份報告裡）。
                let line = "  \(r["citekey"] as? String ?? "")[\(r["authorIndex"] as? Int ?? -1)] "
                    + "「\(r["original"] as? String ?? "")」以「\(r["separator"] as? String ?? "")」切 → \(into)"   // display-safe-exempt: 值取自 splitAuthors（已逐欄位 displaySafe），二次消毒非冪等
                print(line)   // display-safe-exempt: 同上
                print("    理由：\(r["judgement"] as? String ?? "")（只進報告，不進 store）")   // display-safe-exempt: 值取自 splitAuthors（已 displaySafe），二次消毒非冪等
            }
            return
        }
        // 把拆分合回去（#513）——`--split-author` 的具名逆操作，同走 service。
        if !unSplit.isEmpty {
            let service = AkashicService(root: store.root, key: store.key,
                                         environment: ProcessInfo.processInfo.environment)
            let out = try service.unsplitAuthors(unSplit)
            let parsed = (try? JSONSerialization.jsonObject(with: Data(out.utf8))) as? [String: Any]
            let rows = (parsed?["unsplit"] as? [[String: Any]]) ?? []
            print("✓ 合回 \(rows.count) 個作者位、index 已重建")   // display-safe-exempt: Int
            for r in rows {
                let from = (r["from"] as? [String] ?? []).joined(separator: "、")
                print("  \(r["citekey"] as? String ?? "")[\(r["authorIndex"] as? Int ?? -1)] "   // display-safe-exempt: 值取自 unsplitAuthors（已逐欄位 displaySafe），二次消毒非冪等
                    + "\(from) → 「\(r["restored"] as? String ?? "")」")   // display-safe-exempt: 同上
                // 被刪掉的拆分理由要說出來——丟棄必須可見（lossless-intake 執行細節 3）
                print("    已刪掉的拆分記錄，理由：\(r["droppedReason"] as? String ?? "")（完整原值在 git 歷史）")   // display-safe-exempt: 同上
            }
            return
        }
        // 移除一個作者位（#457）——同走 service，兩面一條路徑。
        if !dropAuthor.isEmpty {
            let service = AkashicService(root: store.root, key: store.key,
                                         environment: ProcessInfo.processInfo.environment)
            let out = try service.dropAuthors(dropAuthor)
            let parsed = (try? JSONSerialization.jsonObject(with: Data(out.utf8))) as? [String: Any]
            let rows = (parsed?["dropped"] as? [[String: Any]]) ?? []
            print("✓ 移除 \(rows.count) 個作者位、index 已重建")   // display-safe-exempt: Int
            for r in rows {
                let left = r["authorsLeft"] as? Int ?? -1
                // 剩 0 個要**明說**——那是 APA7 §9.12 的無署名形，不是「壞掉的記錄」。
                let tail = left == 0 ? "（此後無署名：APA7 §9.12 以標題起首）" : "（尚餘 \(left) 個作者位）"   // display-safe-exempt: Int
                let line = "  \(r["citekey"] as? String ?? "")[\(r["authorIndex"] as? Int ?? -1)] "
                    + "移除「\(r["removed"] as? String ?? "")」\(tail)"   // display-safe-exempt: 值取自 dropAuthors（已逐欄位 displaySafe），二次消毒非冪等
                print(line)   // display-safe-exempt: 同上
                print("    理由：\(r["judgement"] as? String ?? "")（逐字記在 work 側的移除記錄裡）")   // display-safe-exempt: 同上
            }
            return
        }
        // 團體作者的升格（#443）——與 judge／refute 同走 service，兩面一條路徑。
        if !attributeOrg.isEmpty {
            let service = AkashicService(root: store.root, key: store.key,
                                         environment: ProcessInfo.processInfo.environment)
            let out = try service.attributeToOrganizations(attributeOrg)
            let parsed = (try? JSONSerialization.jsonObject(with: Data(out.utf8))) as? [String: Any]
            let rows = (parsed?["attributed"] as? [[String: Any]]) ?? []
            print("✓ 歸給團體作者 \(rows.count) 個作者位、index 已重建")   // display-safe-exempt: Int
            for r in rows {
                // service 回傳的欄位已 displaySafe（見 attributeToOrganizations）
                // **標記必須與被標記的那一行同行**——多行運算式只有最後一行帶標記時，
                // 前面幾行仍會被守衛看見（本 session 第三次踩，前兩次在 EntryViews
                // 與 AkashicService）。組完再印，讓整個運算式落在一行上。
                let line = "  \(r["citekey"] as? String ?? "")[\(r["authorIndex"] as? Int ?? -1)] "
                    + "\(r["literal"] as? String ?? "") → @\(r["organization"] as? String ?? "")"   // display-safe-exempt: 值取自 attributeToOrganizations（已逐欄位 displaySafe），二次消毒非冪等
                print(line)   // display-safe-exempt: 值取自 attributeToOrganizations（已逐欄位 displaySafe），二次消毒非冪等
            }
            return
        }
        if !judge.isEmpty || !refute.isEmpty {
            let service = AkashicService(root: store.root, key: store.key,
                                         environment: ProcessInfo.processInfo.environment)
            let confirming = !judge.isEmpty
            let out = confirming
                ? try service.resolvePeople(apply: nil, judge: judge)
                : try service.resolvePeople(apply: nil, refute: refute)
            let parsed = (try? JSONSerialization.jsonObject(with: Data(out.utf8))) as? [String: Any]
            let rows = (parsed?[confirming ? "judged" : "refuted"] as? [[String: Any]]) ?? []
            print("✓ \(confirming ? "判定" : "否決") \(rows.count) 個作者位、改寫 \(parsed?["entriesRewritten"] as? Int ?? 0) 筆 work、"
                  + "\(parsed?["personsRewritten"] as? Int ?? 0) 筆 person 記錄、index 已重建")
            for r in rows {
                // service 回傳的欄位已經 displaySafe 過（見 judgeAuthorships），
                // 這裡原樣轉印——二次消毒會逃脫自己的反斜線（displaySafe 不冪等）
                print("  \(r["id"] as? String ?? "?")  「\(r["literal"] as? String ?? "?")」")   // display-safe-exempt: service 已消毒，displaySafe 不冪等
                print("      \(r["judgement"] as? String ?? "")")   // display-safe-exempt: 同上
            }
            // 略過**必須具名**——靜默略過會讓「沒判到」與「判了但沒生效」在輸出上
            // 完全一樣（lossless-intake 執行細節 3 的同一條理由）。
            let skipped = (parsed?["skipped"] as? [[String: Any]]) ?? []
            if !skipped.isEmpty {
                print("")
                print("略過 \(skipped.count) 筆（store 狀態不符；其餘已落地）：")
                for sk in skipped {
                    print("  \(sk["id"] as? String ?? "?")  ——\(sk["why"] as? String ?? "")")   // display-safe-exempt: service 已消毒
                }
            }
            return
        }

        if !reject.isEmpty {
            let service = AkashicService(root: store.root, key: store.key,
                                         environment: ProcessInfo.processInfo.environment)
            let out = try service.resolvePeople(apply: nil, reject: reject)
            let parsed = (try? JSONSerialization.jsonObject(with: Data(out.utf8))) as? [String: Any]
            let n = (parsed?["rejected"] as? [Any])?.count ?? reject.count
            print("✓ 否決 \(n) 個配對、改寫 \(parsed?["personsRewritten"] as? Int ?? 0) 筆 person 記錄、index 已重建")
            return
        }

        let load = try store.load()
        // #232 design D5：已否決配對從 verdict references 現算，resolver 不再提名
        let rejectedSet = ResolutionLedger.rejectedPairings(people: load.people)
        let confirmedSet = ResolutionLedger.confirmedPairings(people: load.people)
        let report = PersonResolver.resolve(entries: load.entries, people: load.people,
                                            rejected: rejectedSet, confirmed: confirmedSet)
        let all = report.candidates
        // 篩選只影響 **--apply**，列表一律顯示全部——否則使用者用 --citekey 收窄後
        // 會以為其他候選不存在。
        let ckSet = Set(citekey), pkSet = Set(person)
        // --tier 值域驗證（fail-loud：typo 靜默變成「不篩」比失敗糟——#205 同判準）
        let tierSet = try Set(tier.map { raw -> ResolutionTier in
            guard let t = ResolutionTier(rawValue: raw) else {
                throw ValidationError("--tier「\(raw)」不是提名層——合法值：" +
                    ResolutionTier.allCases.map(\.rawValue).joined(separator: " / "))
            }
            return t
        })
        let candidates = all.filter {
            (ckSet.isEmpty || ckSet.contains($0.citekey))
                && (pkSet.isEmpty || pkSet.contains($0.personKey))
                && (tierSet.isEmpty || tierSet.contains($0.tier))
        }
        // R1-fix B1＋R2-fix R3-3（使用者裁決：不豁免）：套用集含寬鬆 tier 時，
        // **不論怎麼收窄**都要 `--tier` 具名——`--person` 恰是同名碰撞問題最糟的
        // 收窄軸（它選中的正是同鍵列；R2 live probe：--person 一發寫 5 筆 initials
        // verdict、4 筆錯配），`--citekey` 收窄也不代表你知道那列是弱證據層。
        if apply, tierSet.isEmpty,
           candidates.contains(where: { $0.tier != .exact }) {
            let breakdown = Dictionary(grouping: candidates, by: \.tier)
                .map { "\($0.key.rawValue) \($0.value.count)" }.sorted().joined(separator: "、")   // display-safe-exempt: $0.key 是封閉 enum ResolutionTier，rawValue 是程式字面量；count 是數量
            throw ValidationError(
                "--apply 拒絕：套用集含寬鬆提名層（\(breakdown)）。"
                + "寬鬆層一律要 --tier 具名——用 --tier exact 只套完全命中，"
                + "或顯式列出要套的層（--tier reorder 等；initials 層 apply 前必查證）。"
                + "收窄（--citekey／--person）不豁免此要求。")
        }

        /// #231：歧義**不再靜默丟棄**。它與「沒人匹配」語意不同——後者是 `.literal`
        /// 的合法長期狀態，前者是系統知道自己遇到了決定點。
        ///
        /// 每個候選一併印區辨欄位（names／orcid），否則讀的人分不出兩種需要**相反
        /// 行動**的情況：(a) 兩個真的不同的人剛好同名（各自歸屬，永不合併）
        /// vs (b) 同一個人有兩筆記錄（該合併）。
        func printAmbiguities() {
            guard !report.ambiguities.isEmpty else { return }
            let byKey = Dictionary(load.people.map { ($0.key, $0) }, uniquingKeysWith: { a, _ in a })
            print("")
            // **CLI 也要有上限**（#236 R2）。先前只給 MCP 加，而終端機灌爆的威脅
            // repo 自己有明文（`TerminalOutputSafetyTests`）——修一個面就宣稱這一類
            // 關掉了，正是本 PR 前一輪被抓的形狀。
            let capped = Array(report.ambiguities.prefix(rowLimit))
            // **列數上限擋不住內容**（#236 R4）。R2 加了列數與 ref 兩軸，實測仍可產出
            // **3,844,596 bytes**——`literal`／`key`／隸屬名各自可到 `max:` 上限，而
            // `displaySafe` 是 8 倍膨脹器。與 MCP 那半同一個結論：計數上限追不上內容，
            // **位元組預算是唯一與內容無關的界**。
            //
            // 逐列累加：吃不下的整列不印（不留半截的歧義），並在結尾說出丟了幾筆。
            var lines: [String] = []
            var bytes = 0
            var budgetDropped = 0
            func emit(_ rows: [String]) -> Bool {
                let cost = rows.reduce(0) { $0 + $1.utf8.count + 1 }
                guard bytes + cost <= AmbiguityDisplayLimit.bytes else {
                    budgetDropped += 1
                    return false
                }
                bytes += cost
                lines.append(contentsOf: rows)
                return true
            }
            for a in capped {
                // **印 entryID**（#236 R2）：重複 citekey 是被支援的損壞態，此時兩筆
                // 歧義在 `(citekey, authorIndex)` 上逐位元組相同。MCP 帶了它、CLI 沒帶
                // ——而 CLI 才是人真正在讀的那個面。
                var row: [String] = []
                // R1-fix B6：碰撞層可見——initials 碰撞（縮寫共鍵）≠ exact 同名
                row.append("  〔\(a.tier.rawValue)〕\(displaySafe(a.citekey, max: 200))[\(a.authorIndex)] 「\(displaySafe(a.literal, max: 200))」"   // display-safe-exempt: tier.rawValue 封閉 enum；其餘已消毒
                           + "  entry:\(a.entryID.uuidString.prefix(8))")
                if a.personKeys.count > AmbiguityDisplayLimit.refs {
                    row.append("      （\(a.personKeys.count) 個候選，以下顯示前 \(AmbiguityDisplayLimit.refs) 個）")
                }
                // **加列內序號**（#236 R3）：`displaySafe` 會截斷，兩個共用長前綴的
                // 合法 key 可以印得**逐位元組相同**。序號讓人至少知道這是兩個不同的
                // 記錄——不然報告會看起來像同一個人被列了兩次。
                for (n, k) in a.personKeys.prefix(AmbiguityDisplayLimit.refs).enumerated() {
                    let p = byKey[k]
                    // **`names` 不具區辨力**——它們之所以被比到一起，正是因為正規化後
                    // 相同。真正能分辨的是外部識別碼與時空不相容，所以那些一定要印。
                    var bits: [String] = []
                    if let o = p?.orcid { bits.append("orcid:\(displaySafe(o.normalized, max: 40))") }
                    if let o = p?.openalex { bits.append("openalex:\(displaySafe(o, max: 40))") }
                    if let x = p?.died { bits.append("卒:\(displaySafe(x, max: 20))") }
                    // **不是只看 current**（#236 R2）。`isOpen` 正確地把
                    // `endedUnknown`（#63）與 `attested`（#70）排除在「現職」外，
                    // 但只印 current 會讓「只有已結束隸屬」的人看起來**毫無隸屬
                    // 資訊**——甚至被判成「無任何區辨欄位」，而那是假的。
                    // 沒有現職就退到最近一段，並把時間狀態標出來。
                    if let cur = p?.profile.affiliations.current?.value {
                        bits.append("隸屬:\(displaySafe(cur.displayName, max: 60))")
                    } else if let last = p?.profile.affiliations.latestPastSegment {
                        let when = rangeLabel(last.range)
                        bits.append("曾隸屬:\(displaySafe(last.value.displayName, max: 60))"
                                    + (when.isEmpty ? "" : "（\(when)）"))   // display-safe-exempt: rangeLabel 內部已消毒（不冪等，不得再包）
                    }
                    let names = namesLabel(p?.names.all ?? [])   // display-safe-exempt: namesLabel 內部已消毒（displaySafe 不冪等，不得再包）
                    let extra = bits.isEmpty ? "  ⚠ 無任何區辨欄位" : "  " + bits.joined(separator: "  ")
                    row.append("      \(n + 1). \(displaySafe(k, max: 200))  [\(names)]\(extra)")
                }
                _ = emit(row)
            }
            let shownCount = capped.count - budgetDropped
            // **「前 N 筆」與「N 筆」不是同一句話。** 只有列數上限生效時，顯示的確實
            // 是前綴；位元組預算會**跳過**過大的列而繼續收後面較小的，那時它不是前綴，
            // 說「前 N 筆」就是假的。（不改成「遇到第一筆放不下就停」是因為：單獨一筆
            // 就超過整個預算時，那會讓報告變成空的。）
            let headline: String
            if report.ambiguities.count <= shownCount { headline = "" }
            else if budgetDropped > 0 { headline = "，以下顯示 \(shownCount) 筆（非前綴：過大的整筆略過）" }
            else { headline = "，以下顯示前 \(shownCount) 筆" }
            print("歧義（\(report.ambiguities.count)\(headline)）"
                  + "——同一個 literal 對到 2+ 個 person，**需要人判斷**：")
            for l in lines { print(l) }
            let hidden = report.ambiguities.count - shownCount
            if hidden > 0 {
                // **兩種丟棄要分開講**：超過列數上限，與內容吃爆位元組預算，對使用者
                // 的意義不同——後者表示「就算提高列數也看不到，那幾筆本身太大」。
                let byRows = report.ambiguities.count - capped.count
                var why: [String] = []
                if byRows > 0 { why.append("\(byRows) 筆超過列數上限") }
                if budgetDropped > 0 { why.append("\(budgetDropped) 筆內容過大、吃不下輸出預算") }
                // **不要指不存在的旋鈕**（#236 R3）：指路只能指呼叫端真的有的東西
                // ——假的建議比沒有建議更糟。#388 起列數上限有 `--rows`，所以現在指得
                // 出來；但**只在列數是原因時才指它**——被位元組預算擋下的那些，調大
                // 列數一樣看不到，指它就是把使用者送去撞同一面牆。
                var how: [String] = []
                if byRows > 0 { how.append("--rows \(report.ambiguities.count) 可列出全部") }
                if budgetDropped > 0 {
                    how.append("內容過大的那 \(budgetDropped) 筆調大列數也看不到，"
                               + "用 --citekey／--person 收窄範圍")
                }
                print("  …另 \(hidden) 筆未顯示（\(why.joined(separator: "；"))；"
                      + "\(how.joined(separator: "；"))）")
            }
            // R1-fix B6：指引依碰撞層分開——exact 的兩難框架對縮寫共鍵是錯誤指引
            let shownTiers = Set(capped.map(\.tier))
            if shownTiers.contains(.exact) {
                print("  〔exact〕兩種可能，處置相反：同名的不同人＝各自歸屬（永不合併）；同一人兩筆＝該合併。")
            }
            if !shownTiers.subtracting([.exact]).isEmpty {
                // R2-fix R3-2（DA probe：補 ORCID／隸屬對 resolver 無效——鍵空間只有
                // names）。設計的出口：查證後把正確寫法補成 variant alias（帶
                // provenance），該列升 exact 候選再顯式 apply。
                print("  〔寬鬆層〕縮寫／重排共鍵通常是**不同的人**——不歸戶也不合併。"
                      + "出口：查證後——是清單中某人 → 補 variant alias（帶 provenance；"
                      + "⚠ update-person 的 names 是整組替換，先讀出現有 names 附加後回寫）"
                      + "→ 該列升 exact 再 apply；是第三個人 → add-person 以該寫法為 name 建檔"
                      + "（exact 單命中優先於寬鬆碰撞）再 apply。")
            }
        }

        // #232 design D7：三態計數（derived）與已否決沉底——名單與計數都來自
        // ResolutionLedger（與 MCP 同一來源），CLI 只負責排版。
        func printCountsAndSunk() {
            // 同 entry 同 literal 的每個位置各一列（verify C-4）；malformed verdict
            // 一併報出（lossless-intake：丟棄必須可見）
            for s in ResolutionLedger.observedRejections(people: load.people,
                                                         entries: load.entries) {
                print("  (已否決) \(displaySafe(s.citekey, max: 200))[\(s.authorIndex)] 「\(displaySafe(s.literal, max: 200))」 ↛ \(displaySafe(s.judgedKey, max: 200))")
            }
            for m in ResolutionLedger.malformedVerdicts(people: load.people).prefix(20) {
                print("  ⚠ malformed verdict（不計數、不抑制）：\(displaySafe(m, max: 300))")
            }
            let triples = all.map { c in
                (pairing: ResolutionPairing(holderKind: .work, holder: c.citekey,
                                            literal: c.literal, judgedKey: c.personKey),
                 rule: ResolutionLedger.personRule(for: c.tier))
            }
            // R1-fix B2＋R2-fix R3-8：逐 rule 一行——四 tier 校準史各自可見。
            // exact **恆印**（歷史基線；R2 抓到 guard-let 綁定短路讓這個意圖失效）；
            // 名單之外的 rule（手改／外庫匯入）殿後照印——靜默消失＝計數說謊。
            let byRule = ResolutionLedger.counts(people: load.people, candidates: triples)
            let personRules = [ResolutionTier.exact, .confirmedElsewhere, .reorder, .initials]
                .map { ResolutionLedger.personRule(for: $0) }
            let foreign = byRule.keys.filter { !personRules.contains($0) }.sorted()
            for rule in personRules + foreign {
                let c = byRule[rule] ?? (confirmed: 0, rejected: 0, pending: 0)
                let nonZero = c.confirmed + c.rejected + c.pending > 0
                guard nonZero || rule == ResolutionLedger.personRule else { continue }
                // R5：標籤過文法夾（同 resolver reason 的夾法）——rule 尾註是 store
                // 衍生自由文字，不夾的話手改 verdict 可在標籤裡偽造整行計數樣式
                let label = rule.range(of: "^[a-z][a-z-]{0,60}$",
                                       options: .regularExpression) != nil
                    ? rule : "非標準rule（\(displaySafe(rule, max: 60))）"
                // 計數不報比率（分母含 censoring，比率會邀請錯誤推論）——未處理量必須可見
                print("三態計數（\(label)）：已確認 \(c.confirmed)／已否決 \(c.rejected)／未處理 \(c.pending)")
            }
        }

        guard !all.isEmpty else {
            print("無候選（literal 作者 \(load.entries.flatMap(\.authors).filter { if case .literal = $0 { return true } else { return false } }.count) 個，任何提名層皆無命中）")
            printCountsAndSunk()   // 沒有候選 ≠ 沒有歷史——已否決與計數照樣要看得見
            printAmbiguities()   // 沒有唯一候選時，歧義**更**該被看見
            return
        }
        let selected = Set(candidates.map { "\($0.citekey)#\($0.authorIndex)" })   // display-safe-exempt: 內部 Set 的成員判定鍵，不進輸出面
        // #303 design D4：按 tier 分組列印（resolver 已依信心降冪排序，分組只加標頭）。
        // tier 越低證據越弱——initials 段的標頭直接把查證義務講出來，讀的人不必翻文件。
        let tierHeadline: [ResolutionTier: String] = [
            .exact: "exact——alias 完全命中",
            .confirmedElsewhere: "confirmed-elsewhere——同 literal 已於他處 confirmed",
            .reorder: "reorder——token 重排命中",
            .initials: "initials——姓＋首字母命中（證據最弱，apply 前必查證）",
        ]
        var printedTier: ResolutionTier? = nil
        for c in all {
            if c.tier != printedTier {
                print("〔\(tierHeadline[c.tier] ?? c.tier.rawValue)〕")   // display-safe-exempt: 封閉 enum 的固定字面
                printedTier = c.tier
            }
            // 被篩掉的候選仍列出，但標明不會套用——收窄範圍不等於「其他不存在」
            let mark = (apply && !selected.contains("\(c.citekey)#\(c.authorIndex)")) ? "  (skip) " : "  "
            print("\(mark)\(displaySafe(c.citekey, max: 200))[\(c.authorIndex)] 「\(displaySafe(c.literal, max: 200))」 → \(displaySafe(c.personKey, max: 200))（\(displaySafe(c.reason, max: 300))）")
        }
        printCountsAndSunk()
        printAmbiguities()
        if apply {
            // 篩選條件寫了卻一個都沒中——多半是打錯 key，別靜默什麼都不做。
            // R4-8：--tier 也算篩選條件（R3 抓到 --tier reorder 零命中印 ✓ exit 0）
            if !(citekey.isEmpty && person.isEmpty && tier.isEmpty), candidates.isEmpty {
                throw ValidationError(
                    "--citekey / --person / --tier 的篩選條件沒有命中任何候選"
                    + "（共 \(all.count) 個候選）——請對照上面的清單確認 key 是否正確")
            }
            // #232：apply 改走 **AkashicService**（與 MCP 同一條實作路徑）——
            // service 端做 per-item 收容（R7/M21）、先報失敗再 rebuild（R9/M8）、
            // applied 不誇報（R8/L15），並在**同一動作**內寫 resolution-confirmed
            // verdict（design D6）。CLI 只把 JSON 排成人可讀。
            let service = AkashicService(root: store.root, key: store.key,
                                         environment: ProcessInfo.processInfo.environment)
            let ids = candidates.map(\.pinnedID)   // R3-5：CLI 也釘 person——與 service 列表同一個型別定義   // 複合鍵住在型別上（#236 R4）——不手拼第四份
            // **`--tier` 同時是篩選與承認。** service 端對寬鬆層要求 `confirmTiers`
            // 顯式承認，而 CLI 端的閘（上方 ValidationError）要求的正是 `--tier` 具名
            // ——兩者是同一個「你知道自己在套什麼層」的要求，只是先前沒接上線：CLI
            // 從不傳 confirmTiers，於是 `--tier reorder --apply` **結構上不可能成功**
            // （CLI 閘放行、service 閘拒絕）。`mcp-cli-parity` 記的「tier-acknowledgment
            // 參數列 follow-up」就是這條線。
            //
            // 不另加一個 `--confirm-tier` 旗標：那會要求使用者把同一組 tier 打兩次，
            // 而兩次不一致時的語意沒有人想得出來。
            let out = try service.resolvePeople(apply: ids, confirmTiers: tier.isEmpty ? nil : tier)
            let parsed = (try? JSONSerialization.jsonObject(with: Data(out.utf8))) as? [String: Any]
            let written = parsed?["entriesRewritten"] as? Int ?? 0
            let writeFailed = parsed?["writeFailed"] as? [String: String] ?? [:]
            let confirmFailed = parsed?["confirmWriteFailed"] as? [String: String] ?? [:]
            if !writeFailed.isEmpty {
                print("write failed（單筆寫入失敗，已略過）: \(writeFailed.count)")
                // service 的輸出已逐值 displaySafe——不再包一次（displaySafe 不冪等）
                for (key, msg) in writeFailed.sorted(by: { $0.key < $1.key }) { print("  ✗ \(key) — \(msg)") }
            }
            if !confirmFailed.isEmpty {
                print("confirmed verdict 寫入失敗（entry 已改寫、verdict 未落地）: \(confirmFailed.count)")
                for (key, msg) in confirmFailed.sorted(by: { $0.key < $1.key }) { print("  ✗ \(key) — \(msg)") }
            }
            // format < 8 的 store：verdict 被跳過必須說出來（service 已揭露，CLI 轉印）
            if let note = parsed?["verdictsSkipped"] as? String { print("⚠ \(note)") }   // service 端常數模板，已安全
            // 成功行不誇報（R8）：✓ 只在全數成功時
            if writeFailed.isEmpty, confirmFailed.isEmpty {
                print("✓ 套用 \(candidates.count) 個候選、改寫 \(written) 檔、index 已重建")
            } else {
                print("部分套用：改寫 \(written) 檔、失敗 \(writeFailed.count + confirmFailed.count) 筆、index 已重建")
                throw ExitCode(1)
            }
        } else {
            print("（只列候選；要套用加 --apply）")
        }
    }
}

struct Rename: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "rename", abstract: "citekey 改名：搬檔 + 全庫 relations 遷移（UUID 不變）")

    @OptionGroup var options: LibraryOptions

    @Argument(help: "現有 citekey") var from: String
    @Argument(help: "新 citekey") var to: String

    func run() throws {
        let store = try options.openStore()
        let report = try store.renameEntry(from: from, to: to)
        _ = try LibraryIndex(store: store).rebuild()
        print("✓ \(displaySafe(from, max: 200)) → \(displaySafe(to, max: 200))")
        if !report.relationsRewritten.isEmpty {
            print("relations 已遷移：\(report.relationsRewritten.map { displaySafe($0, max: 200) }.joined(separator: ", "))")
        }
        // rename 會改寫**別的**記錄的歧異候選——那是使用者最不會預期的副作用，
        // 不印等於沒發生過（#71 R3 DA 新 5）。
        if !report.divergenceCandidatesRewritten.isEmpty {
            print("歧異候選已遷移：\(report.divergenceCandidatesRewritten.joined(separator: ", "))")
        }
        // verdict value 同理（#232 verify NEW-1）——判定史跟著 citekey 走
        if !report.verdictValuesRewritten.isEmpty {
            print("消解判定已遷移：\(report.verdictValuesRewritten.map(\.describedSafely).joined(separator: ", "))")   // display-safe-exempt: HolderRecord.describedSafely 已對 key 套 displaySafe(max: 200)
        }
        if !report.quarantinedNotScanned.isEmpty {   // #497：未掃描不得看起來像掃過且沒有
            print("⚠ \(report.quarantinedNotScanned.count) 個 quarantine 檔未掃描——"
                  + "其中若有 verdict 指向此鍵，不會被遷移（修好那些檔後跑 akashic validate 複查）：")
            for f in report.quarantinedNotScanned { print("  · \(displaySafe(f, max: 300))") }
        }
        if !report.verdictsCollapsed.isEmpty {   // #495：收攏丟列要說出來——靜默丟棄不可稽核（lossless-intake 執行細節 3）
            print("verdict 收攏丟棄 \(report.verdictsCollapsed.count) 筆（與遷移輸出同 (field, value)，留首見）：")
            for x in report.verdictsCollapsed { print("  · \(displaySafe(x, max: 300))") }
        }
    }
}

/// person key 改名（#395）。
///
/// **與 `rename` 是兩個命令而不是一個帶旗標的命令**：兩者的遷移面不同
/// （見 `LibraryStore.renamePerson` 的對照表），合成一個會逼出「這個旗標對另一邊
/// 是什麼意思」這種答不出來的問題。
///
/// 名字是 `rename-person` 而非 `rename --person`——同 `mcp-cli-parity` CLI-only 表的
/// 其他遷移命令，動詞在前、對象在後。
struct RenamePerson: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "rename-person",
        abstract: "person key 改名：全庫 authors 邊 + 消解判定 + 歧異候選遷移（UUID 不變）")

    @OptionGroup var options: LibraryOptions

    @Argument(help: "現有 person key") var from: String
    @Argument(help: "新 person key") var to: String

    func run() throws {
        // #298：改名是破壞性寫入——目標 store 未指名時要求顯式確認
        try options.assertDestructiveTargetNamed("rename-person")
        let store = try options.openStore()
        let report = try store.renamePerson(from: from, to: to)
        _ = try LibraryIndex(store: store).rebuild()
        print("✓ \(displaySafe(from, max: 200)) → \(displaySafe(to, max: 200))")
        // **三個副作用都要印。** 改名會動到**別的**記錄，那是使用者最不會預期的
        // 部分——不印等於沒發生過（#71 R3 DA 的既有教訓）。
        if !report.authorEdgesRewritten.isEmpty {
            print("作品的作者邊已遷移（\(report.authorEdgesRewritten.count)）："
                  + report.authorEdgesRewritten.map { displaySafe($0, max: 200) }.joined(separator: ", "))
        }
        if !report.verdictValuesRewritten.isEmpty {
            print("消解判定已遷移："   // display-safe-exempt: 同上，消毒在 describedSafely 內
                  + report.verdictValuesRewritten.map(\.describedSafely).joined(separator: ", "))
        }
        if !report.divergencesRewritten.isEmpty {
            print("歧異記錄已遷移（候選或 prefers）：\(report.divergencesRewritten.joined(separator: ", "))")
        }
        if !report.quarantinedNotScanned.isEmpty {   // #497：未掃描不得看起來像掃過且沒有
            print("⚠ \(report.quarantinedNotScanned.count) 個 quarantine 檔未掃描——"
                  + "其中若有 verdict 指向此鍵，不會被遷移（修好那些檔後跑 akashic validate 複查）：")
            for f in report.quarantinedNotScanned { print("  · \(displaySafe(f, max: 300))") }
        }
        if !report.verdictsCollapsed.isEmpty {   // #495：收攏丟列要說出來——靜默丟棄不可稽核（lossless-intake 執行細節 3）
            print("verdict 收攏丟棄 \(report.verdictsCollapsed.count) 筆（與遷移輸出同 (field, value)，留首見）：")
            for x in report.verdictsCollapsed { print("  · \(displaySafe(x, max: 300))") }
        }
        if report.authorEdgesRewritten.isEmpty && report.verdictValuesRewritten.isEmpty
            && report.divergencesRewritten.isEmpty && report.verdictsCollapsed.isEmpty {
            // 「沒有副作用」與「有副作用但沒印」在終端上不該長得一樣。
            // 而有 quarantine 檔時**兩者都不能說**——那句話是全稱斷言，而我們沒掃過那些檔（#497）。
            print(report.quarantinedNotScanned.isEmpty
                  ? "（無其他記錄引用此 key）"
                  : "（已載入的記錄中無其他引用；未掃描的 quarantine 檔見上）")
        }
    }
}

/// 為既有記錄補上對外可稱呼的名字（#81）。
///
/// **預設只報告不寫**——`authorized` 是指定不是推導，機械提名的結果要人看過才算數。
struct AuthorizeNames: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "authorize-names",
        abstract: "提名對外可稱呼的名字（#81）；預設 dry-run，--apply 才寫入")

    @OptionGroup var options: LibraryOptions

    @Flag(name: .long, help: "實際寫入（預設只報告）")
    var apply: Bool = false

    func run() throws {
        let store = try options.openStore()
        let r = try AuthorizedNameMigration.run(store: store, apply: apply)
        print("person 總數: \(r.total)")
        print("  已指定（不動）: \(r.alreadyDesignated)")
        print("  採用（該書寫系統唯一候選）: \(r.adopted)")
        print("  提名（多候選中恰一個非引用形）: \(r.nominated)")
        print("  留空（仍然歧義，需人工判斷）: \(r.undecided)")
        // 上面三個是**逐書寫系統**的計數（雙語的人同時貢獻採用與提名），不能直接相加成
        // 總人數。可相加的是下面這三個逐人計數。
        let perPerson = r.peopleFullyDesignated + r.peopleUndecided
                      + r.peopleWithoutNames + r.alreadyDesignated
        print("逐人（互斥且窮盡）：全部指定完 \(r.peopleFullyDesignated) ＋ 仍有歧義 \(r.peopleUndecided)"
              + " ＋ 無可用名字 \(r.peopleWithoutNames) ＋ 原本已指定 \(r.alreadyDesignated)"
              + " = \(perPerson)\(perPerson == r.total ? "" : "（≠ \(r.total)，分類有漏）")")
        if !r.undecidedKeys.isEmpty {
            print("  歧異記錄: " + r.undecidedKeys.prefix(20)
                .map { displaySafe($0, max: 120) }.joined(separator: ", ")
                + (r.undecidedKeys.count > 20 ? " …（共 \(r.undecidedKeys.count) 筆）" : ""))
        }
        print(apply ? "✓ 已寫入" : "未寫入。確認上面的計畫後加 --apply 執行。")
    }
}

/// 記下一個未決的同一性問題（#77）。
///
/// `resolve-divergence` 早有入口而**建立**沒有——於是「先記下來、之後再判斷」在使用層
/// 不成立，只能手寫 YAML 繞過編碼器，或當場把判斷做掉而不留痕。
struct RecordDivergence: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "record-divergence",
        abstract: "記下未決的同一性問題（#77）；記下判斷**不等於**消歧，消歧用 resolve-divergence")

    @OptionGroup var options: LibraryOptions

    @Option(name: .long, help: "未決的是什麼，一句話")
    var question: String

    @Option(name: .long, parsing: .upToNextOption,
            help: "候選，形如 `key:shape`（shape 為 person / organization / work）；需要兩個以上")
    var candidate: [String]

    @Option(name: .long, help: "已經形成的判斷（選填；給了就必須同時給 --rests-on）")
    var judgement: String?

    @Option(name: .long, parsing: .upToNextOption,
            help: "判斷的依據（來源 URL 或 sha256: 存檔摘要）；可多個")
    var restsOn: [String] = []

    /// #159 verify 159-3：先前**只有 MCP** 能寫 `prefers`——LLM 寫得了、人寫不了。
    /// 那讓 CLI 使用者記下的判斷永遠落在「只警告不擋」那條路，`resolve-divergence`
    /// 的機械執法對他們結構上不可達；而 #75 對一的立論恰恰是「別讓 LLM 的判斷被
    /// 自動採信」——工具卻只給了 LLM 執法權。
    @Option(name: .long,
            help: "判斷傾向哪個候選（選填；須是候選之一、與 --judgement 成對）。指定後 resolve-divergence 選別人會拒絕，而非只警告")
    var prefers: String?

    func run() throws {
        let store = try options.openStore()
        let parsed: [(key: String, shape: EntityKind)] = try candidate.map { spec in
            let parts = spec.split(separator: ":", maxSplits: 1).map(String.init)
            guard parts.count == 2, let shape = EntityKind(rawValue: parts[1]) else {
                throw ValidationError(
                    "候選格式為 `key:shape`（shape ∈ \(EntityKind.allCases.filter { $0 != .divergence }.map(\.rawValue).joined(separator: " / "))），得到「\(displaySafe(spec, max: 120))」")
            }
            return (key: parts[0], shape: shape)
        }
        let d = try store.recordDivergence(question: question, candidates: parsed,
                                           judgement: judgement, restsOn: restsOn,
                                           prefers: prefers)
        print("✓ 已記錄 divergence \(d.id.uuidString)")
        print("  候選: " + d.candidates.map { displaySafe($0.key, max: 120) }.joined(separator: " / "))
        if d.judgement == nil {
            print("  尚無判斷——之後可再跑一次本命令補上 --judgement 與 --rests-on（同一組候選＝同一筆記錄）")
        } else {
            print("  已附判斷。**記下判斷不等於消歧**——要合併請跑 akashic resolve-divergence \(d.id.uuidString) --survivor <key>")
            // #159 verify 159-3：說出這筆判斷會不會被機械執法。有 judgement 沒
            // prefers 時 resolve 只警告不擋——那個差別對使用者是不可見的，除非說。
            if let p = d.judgement?.prefers {
                print("  傾向「\(displaySafe(p, max: 120))」——選別的候選會被**拒絕**（除非帶 --override-reason）")
            } else {
                print("  未指定 --prefers——消歧時只會提醒、不會擋。要機械執法請補 --prefers <key>")
            }
        }
    }
}
