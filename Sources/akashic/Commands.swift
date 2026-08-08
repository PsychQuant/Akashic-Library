import ArgumentParser
import Foundation
import AkashicCore
import AkashicStoreIO
import AkashicEntity
import AkashicZoteroImport
import AkashicWoSImport
import AkashicExport
import AkashicIndex

struct Doctor: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "doctor", abstract: "建立/檢查 library 佈局、重建 index、一致性報告")

    @OptionGroup var options: LibraryOptions

    func run() throws {
        let store = try options.openOrCreateStore()
        let root = store.root
        let load = try store.load()

        // #35：跨記錄檢查必須在 rebuild **之前**。雙佈局並存時 index 會撞
        // `UNIQUE constraint failed: entries.citekey`——使用者拿到的是 SQLite 的
        // 內部錯誤，而不是「你有兩筆同 citekey 的記錄、它們在哪」。診斷工具在這種
        // 狀態下正是最該說話的時候，不是最該掛掉的時候。
        let cross = load.crossRecordIssues()
        let fatalCross = cross.filter { $0.severity == .error }
        if !cross.isEmpty {
            print("cross-record: \(cross.count)")
            for i in cross { print("  \(i.severity == .error ? "✗" : "⚠") \(i.message)") }
        }
        // #107：佈局殘留——依 format/key 不該存在、且為空目錄或純衍生物的路徑。
        // **只在命中時輸出，報告不動手刪**（#79 的形狀：讓看不見的變看見，處置留給人）。
        // 判準保守：含資料的目錄永不報；sources/（#66 的被指涉內容）絕不列入。
        // **排在 fatal cross-record 早退之前**（#120 verify）：重複 citekey 的 store
        // 正是最需要看清全貌的時候，殘留報告不該被吞掉。
        let residue = try store.layoutResidue()
        if !residue.isEmpty {
            print("殘留：")
            residue.forEach { print("  ⚠ \(displaySafe($0, max: 300))") }
        }
        if !fatalCross.isEmpty {
            print("library: \(displaySafe(root.path, max: 800))")
            print("entries: \(load.entries.count)（未重建 index——先修好上面的重複）")
            throw ExitCode(1)
        }

        let stats = try LibraryIndex(store: store).rebuild()

        print("library: \(displaySafe(root.path, max: 800))")
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
        var failed = false
        if !load.quarantined.isEmpty {
            failed = true
            print("quarantined \(load.quarantined.count) 檔：")
            load.quarantineLines.forEach { print($0) }
        }
        for entry in load.entries {
            let issues = entry.validate()
            for issue in issues {
                let mark = issue.severity == .error ? "✗" : "⚠"
                print("\(mark) \(displaySafe(entry.citekey, max: 200)): \(issue.message)")
                if issue.severity == .error { failed = true }
            }
        }
        // #23：person / library 層驗證（未知欄位 warning 不 fail——availability 優先，可見性保留）
        for person in load.people {
            for issue in person.validate() {
                let mark = issue.severity == .error ? "✗" : "⚠"
                print("\(mark) \(displaySafe(person.key, max: 200)): \(issue.message)")
                if issue.severity == .error { failed = true }
            }
        }
        for library in load.libraries {
            for issue in library.validate() {
                let mark = issue.severity == .error ? "✗" : "⚠"
                print("\(mark) \(displaySafe(library.key, max: 200)): \(issue.message)")
                if issue.severity == .error { failed = true }
            }
        }
        // #81：機構記錄在此之前**從未被驗證過**——`Organization.validate()` 不存在，這個
        // 迴圈也不存在。對外名字的不變式若只加在型別上，使用層不會生效。
        // `AuthorizedNameTests` 有機械守衛掃這一段，刪掉會紅。
        for organization in load.organizations {
            for issue in organization.validate() {
                let mark = issue.severity == .error ? "✗" : "⚠"
                print("\(mark) \(displaySafe(organization.key, max: 200)): \(issue.message)")
                if issue.severity == .error { failed = true }
            }
        }
        // 歧異記錄的單筆檢查（#71 R1 verify 的 DA 更正四）：`Validate` 的未知欄位提示
        // 完全來自每筆記錄的 `validate()`，不是 `load.unknownFieldFiles`（那條只餵
        // doctor 與 App）。少了這個迴圈，帶未知欄位的歧異記錄會被印成「全部通過」。
        for d in load.divergences {
            for issue in d.validate() {
                let mark = issue.severity == .error ? "✗" : "⚠"
                print("\(mark) divergence \(d.id.uuidString): \(issue.message)")
                if issue.severity == .error { failed = true }
            }
        }
        // #7b：跨記錄檢查——單筆 validate() 結構上看不到的那一層
        for issue in load.crossRecordIssues() {
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
        if !report.droppedFields.isEmpty {
            let summary = report.droppedFields.keys.sorted()
                .map { "\($0)×\(report.droppedFields[$0]!)" }.joined(separator: ", ")
            print("dropped fields（未映射的 Zotero 欄位，未入庫）: \(summary)")
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

    func run() throws {
        let store = try options.openStore()
        let load = try store.load()
        var cands = PersonBootstrap.candidates(entries: load.entries, existing: load.people)
            .filter { $0.occurrences >= minOccurrences }
        let total = cands.count
        if let limit { cands = Array(cands.prefix(limit)) }

        guard !cands.isEmpty else {
            print("無候選（literal 作者皆已有對應 person，或全部低於門檻）")
            return
        }
        for c in cands.prefix(apply ? 0 : 20) {
            let aliases = c.names.map { displaySafe($0, max: 200) }.joined(separator: " ≡ ")
            print("  \(displaySafe(c.key, max: 200))  ×\(c.occurrences)  \(aliases)")
        }
        if !apply {
            if total > 20 { print("  …共 \(total) 個（只列前 20）") }
            print("（只列候選；要建立加 --apply）")
            return
        }
        var written = 0
        for p in PersonBootstrap.personsFor(cands) {
            try store.writePerson(p)
            written += 1
        }
        _ = try LibraryIndex(store: store).rebuild()
        print("✓ 建立 \(written) 個 person（共 \(total) 個候選）、index 已重建")
        print("  下一步：akashic resolve-people 把 entries 的 literal 歸戶")
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
        let store = try options.openStore()
        let load = try store.load()
        let result = OrgBootstrap.result(people: load.people, organizations: load.organizations)
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
        for o in OrgBootstrap.organizationsFor(cands) {
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
        if !failed.isEmpty {
            print("write failed（單筆寫入失敗，已略過續跑）: \(failed.count)")
            for f in failed {
                print("  ✗ \(displaySafe(f.key, max: 200)) — \(displaySafe(f.why, max: 512))")
            }
        }
        _ = try LibraryIndex(store: store).rebuild()
        if failed.isEmpty {
            print("✓ 建立 \(written) 個 organization（共 \(total) 個候選）、index 已重建")
        } else {
            print("⚠ 部分完成：建立 \(written) 個、\(failed.count) 個失敗、index 已重建")
        }
        // exit code 見下方 reportDropped 之後——**不能在這裡 throw**，否則會吞掉
        // dropped 清單與「下一步」提示（#154 verify 154-13）
        // #154 verify 154-9：**這個呼叫點先前零測試覆蓋**——刪掉它全套 965 綠。
        // `--apply` 是使用者最容易認定「做完了」的時刻，也是唯一留下永久痕跡的路徑。
        reportDropped()
        print("  下一步：akashic resolve-organizations 把 affiliations 的 literal 歸戶")
        // #154 verify 154-13：部分失敗時 exit 1，與 `resolve-organizations` 對齊。
        // 先前只有 resolve 側 throw——而 `--apply` 正是最常被 chain 的一步（輸出
        // 自己就寫著「下一步：…」），bootstrap 半途失敗時
        // `bootstrap-organizations --apply && resolve-organizations --apply`
        // 會若無其事往下走。**放在 reportDropped 與「下一步」之後**，否則會吞掉它們。
        if !failed.isEmpty { throw ExitCode(1) }
    }
}

/// #70 第二題：literal 機構名 → organization key 的高信心歸戶（絕不自動合併）。
struct ResolveOrganizations: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "resolve-organizations",
        abstract: "列出 literal→organization 高信心候選；--apply 才寫入")

    @OptionGroup var options: LibraryOptions
    @Flag(name: .long, help: "套用候選（顯式人工確認）；可用 --person / --org 收窄") var apply = false
    @Option(name: .long, parsing: .upToNextOption,
            help: "只套用這些 person key 的候選") var person: [String] = []
    @Option(name: .long, parsing: .upToNextOption,
            help: "只套用指向這些 organization key 的候選") var org: [String] = []

    func run() throws {
        let store = try options.openStore()
        let load = try store.load()
        let all = OrgResolver.candidates(people: load.people, organizations: load.organizations)
        let pkSet = Set(person), okSet = Set(org)
        let candidates = all.filter {
            (pkSet.isEmpty || pkSet.contains($0.personKey))
                && (okSet.isEmpty || okSet.contains($0.orgKey))
        }
        guard !all.isEmpty else {
            print("無候選（affiliation literal 皆無 org name 完全命中）")
            return
        }
        let selected = Set(candidates.map { "\($0.personKey)#\($0.literal)" })
        for c in all {
            let mark = (apply && !selected.contains("\(c.personKey)#\(c.literal)")) ? "  (skip) " : "  "
            print("\(mark)\(displaySafe(c.personKey, max: 200)) 「\(displaySafe(c.literal, max: 200))」 → \(displaySafe(c.orgKey, max: 200))（\(displaySafe(c.reason, max: 300))）")
        }
        if apply {
            if !(person.isEmpty && org.isEmpty), candidates.isEmpty {
                throw ValidationError("--person / --org 的篩選條件沒有命中任何候選")
            }
            // #154 verify 154-8：per-item 收容 + 先報告再 rebuild + `✓` 只在全綠。
            //
            // 原本 `try store.writePerson(p)` 直接往外擲，實測（三人命中同一 org、
            // 中間那個檔案設 `uchg`）：第一個寫入、第二個失敗、第三個**從未被嘗試**、
            // index 從未重建，而使用者只拿到一句 Foundation 原始錯誤，看不到哪些已經
            // 落地。同一個檔案的 `ResolvePeople` 早為此修過三輪（R7/M21 per-item
            // 收容、R9/M8 先印再 rebuild、R8/L29 `✓` 只在全綠）——org 側三條全沒
            // 帶過來。這不是新設計，是把既有紀律平移。
            let updated = OrgResolver.apply(candidates, to: load.people)
            var written = 0
            var failed: [(key: String, why: String)] = []
            for p in updated where !load.people.contains(where: { $0 == p }) {
                do {
                    try store.writePerson(p)
                    written += 1
                } catch {
                    failed.append((key: p.key, why: "\(error)"))
                }
            }
            // **先報失敗**：rebuild 可能自己再擲一次，那會把上面的清單吞掉
            if !failed.isEmpty {
                print("write failed（單筆寫入失敗，已略過續跑）: \(failed.count)")
                for f in failed {
                    print("  ✗ \(displaySafe(f.key, max: 200)) — \(displaySafe(f.why, max: 512))")
                }
            }
            _ = try LibraryIndex(store: store).rebuild()
            // `✓` 只在全綠。報**寫入數**不是候選數——先前用 candidates.count，失敗時誇報
            if failed.isEmpty {
                print("✓ 歸戶 \(candidates.count) 筆、改寫 \(written) 個 person、index 已重建")
            } else {
                print("⚠ 部分完成：改寫 \(written) 個 person、\(failed.count) 個失敗、index 已重建")
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
        print("\(prefix) created \(r.created.count)、unchanged \(r.unchanged.count)")
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

    func run() throws {
        let store = try options.openStore()
        let load = try store.load()
        let dir = URL(fileURLWithPath: (output as NSString).expandingTildeInPath)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let tables = RelationalExport.tables(entries: load.entries, people: load.people,
                                            organizations: load.organizations)
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
            ? try CSLExport.cslJSON(entries: entries, people: load.people)
            : BibExport.bibFile(entries: entries, people: load.people)
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

    func run() throws {
        let store = try options.openStore()
        let load = try store.load()
        let all = PersonResolver.candidates(entries: load.entries, people: load.people)
        // 篩選只影響 **--apply**，列表一律顯示全部——否則使用者用 --citekey 收窄後
        // 會以為其他候選不存在。
        let ckSet = Set(citekey), pkSet = Set(person)
        let candidates = all.filter {
            (ckSet.isEmpty || ckSet.contains($0.citekey))
                && (pkSet.isEmpty || pkSet.contains($0.personKey))
        }
        guard !all.isEmpty else {
            print("無候選（literal 作者 \(load.entries.flatMap(\.authors).filter { if case .literal = $0 { return true } else { return false } }.count) 個，皆無 alias 完全命中）")
            return
        }
        let selected = Set(candidates.map { "\($0.citekey)#\($0.authorIndex)" })
        for c in all {
            // 被篩掉的候選仍列出，但標明不會套用——收窄範圍不等於「其他不存在」
            let mark = (apply && !selected.contains("\(c.citekey)#\(c.authorIndex)")) ? "  (skip) " : "  "
            print("\(mark)\(displaySafe(c.citekey, max: 200))[\(c.authorIndex)] 「\(displaySafe(c.literal, max: 200))」 → \(displaySafe(c.personKey, max: 200))（\(displaySafe(c.reason, max: 300))）")
        }
        if apply {
            // 篩選條件寫了卻一個都沒中——多半是打錯 key，別靜默什麼都不做
            if !(citekey.isEmpty && person.isEmpty), candidates.isEmpty {
                throw ValidationError(
                    "--citekey / --person 的篩選條件沒有命中任何候選"
                    + "（共 \(all.count) 個候選）——請對照上面的清單確認 key 是否正確")
            }
            let applied = PersonResolver.apply(candidates, to: load.entries)
            var written = 0
            var writeFailed: [(String, String)] = []
            // R7（R6-verify M21）：encode 自 v1.3 起可拒寫——多檔迴圈 per-item
            // 收容，index 照 rebuild，不留「部分改寫 + index stale」的撕裂
            for (before, after) in zip(load.entries, applied) where before != after {
                do {
                    try store.writeEntry(after)
                    written += 1
                } catch {
                    writeFailed.append((after.citekey, displaySafe(String(describing: error), max: 512)))
                }
            }
            // R9（R8-verify M8）：writeFailed 先印再 rebuild——rebuild 擲錯
            // 不得吞掉已發生的寫入失敗報告
            if !writeFailed.isEmpty {
                print("write failed（單筆寫入失敗，已略過）: \(writeFailed.count)")
                for (key, msg) in writeFailed { print("  ✗ \(displaySafe(key, max: 200)) — \(displaySafe(msg, max: 512))") }
            }
            _ = try LibraryIndex(store: store).rebuild()
            // R8（R7-verify L29/L15）：成功行不誇報（✓ 只在全數成功時）
            if writeFailed.isEmpty {
                print("✓ 套用 \(candidates.count) 個候選、改寫 \(written) 檔、index 已重建")
            } else {
                print("部分套用：改寫 \(written) 檔、失敗 \(writeFailed.count) 檔、index 已重建")
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
