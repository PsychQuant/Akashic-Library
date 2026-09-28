import Foundation
import AkashicCore

/// Akashic store → 關係式表格（#22）。
///
/// `#20` 拍板「Akashic 當 canonical，DuckDB 降為衍生」。但「衍生」需要一條實際的 export
/// 路徑——沒有它，「canonical 在 Akashic」只是宣稱，下游仍得自己爬自己組。
///
/// **方向是單向的**：Akashic → 表格。DuckDB 端不回寫，所以這裡不需要處理合併衝突，
/// 而下游可以隨時整個丟掉重建。
///
/// ## 型別設計在下游付現
///
/// `Author` 的 sum type **天然映射到 nullable FK**：
///
/// | Swift | `publication_author` |
/// |---|---|
/// | `.key(k)` | `author_kind` = `person`、`researcher_id` = 該 person 的 id、`name_full` = 顯示名 |
/// | `.organization(k)` | `author_kind` = `organization`、`organization_id` = 該機構的 id、`name_full` = 機構顯示名 |
/// | `.literal(s)` | `author_kind` = `literal`、兩個 id 都 **NULL**、`name_full` = `s` |
///
/// **`author_kind` 是必要的**（#596）：只靠 `researcher_id IS NULL` 判「未歸戶」時，已歸戶的團體作者與沒對到的人名
/// 在匯出裡同形——#378 把團體作者接到 `.organization`，到了這一層又被折回 literal 的樣子。「未歸戶」的查詢是
/// `WHERE author_kind = 'literal'`；懸空的 key（指向不存在的記錄）kind 照實、id 是 NULL，不造 id。
///
/// ## 清單欄位另立子表，不塞分隔符
///
/// `Entry.doi` 是清單（#394），`publication` 一列一筆 work。全部的 DOI 在 `publication_doi(publication_id, doi_seq, doi)`，
/// 一個 DOI 一列；`publication.doi` 只放第一個（主 DOI），等於 `doi_seq = 0` 那一列（#657）。與 `publication_author` 同一個形狀：
/// 清單進子表、以序號保留順序。
///
/// ## temporal 維度怎麼出（#20 落地後）
///
/// `PersonProfile` 的每個維度是**一條時間軸**，關係式端對應一張 **long-format** 表
/// `researcher_timeline(researcher_id, dimension, value, valid_start, valid_end, valid_end_unknown, source, note,
/// organization_id, affiliation_kind, valid_attested)`——欄位順序以 `tables(…)` 的 `columns` 與 DDL 為準（load.sql 依位置灌表）。
///
/// **不攤平成寬表**（`rank_2020`、`rank_2021`…）：維度值域是開放的（新職稱只是一個
/// 新字串），攤平會讓每個新值變成一次 schema 變更。long format 讓「歷任所長」是
/// `WHERE dimension='administrative' AND value='所長'`，而不是對欄位名做字串比對。
///
/// `researcher` 保留**現況**欄位（`rank_current` 等）作為便利視角——它們可由 timeline
/// 推出（`valid_end`、`valid_end_unknown`、`valid_attested` 三者皆 NULL 的最新一段），冗餘但常用。**冗餘是刻意的**：不放的話每個
/// 「現在誰是研究員」的查詢都要自己寫一次 window function。
public enum RelationalExport {

    /// 一張表：欄位名 + 逐行的值（`nil` ＝ SQL NULL）。
    public struct Table: Equatable {
        public let name: String
        public let columns: [String]
        public var rows: [[String?]]
    }

    public struct Tables: Equatable {
        public var researcher: Table
        public var researcherTimeline: Table
        public var publication: Table
        public var publicationAuthor: Table
        /// 一筆 work 的全部 DOI，一個 DOI 一列（#657）。
        public var publicationDOI: Table
        public var organization: Table

        public var all: [Table] {
            [organization, researcher, researcherTimeline, publication, publicationAuthor, publicationDOI]
        }
    }

    /// 一筆 work 要匯出的 DOI：`canonicalDOIs` 的正規形、依 store 裡的順序、去掉重複（#657）。
    ///
    /// `publication.doi` 取這份清單的第一個、`publication_doi` 逐一列出同一份清單——**兩張表讀同一個函式**，
    /// 所以「publication.doi 等於 doi_seq 0 那一列」由構造成立，不靠兩處各自取 `.first` 碰巧一致。
    /// 去重與 `.bib` 的 `BibExport.otherDOIs` 同一條（正規形相同即同一個號，印兩次是雜訊、下游數 DOI 會多算）；
    /// 讀 `canonicalDOIs` 而不是 `doi`，是因為 `publication.doi` 從 #394 起就讀它（只有 `fields.doi` 殘留的記錄也要有列）。
    static func exportedDOIs(_ e: Entry) -> [String] {
        var seen = Set<String>()
        return e.canonicalDOIs.map(\.normalized).filter { seen.insert($0).inserted }
    }

    /// researcher.status（#661）：current／retired／undetermined，沒有隸屬資料時 nil。
    static func researcherStatus<V>(_ affiliations: TimelineOf<V>) -> String? {
        if affiliations.isEmpty { return nil }
        if affiliations.current != nil { return "current" }
        let observedOnly = affiliations.entries.contains {
            $0.range.end == nil && !$0.range.endedUnknown && !$0.range.attested.isEmpty
        }
        return observedOnly ? "undetermined" : "retired"
    }

    /// researcher_timeline.valid_attested（#661）：觀測點依序寫成 **JSON 陣列**（`["2019-05","2021"]`），沒有時 NULL。
    ///
    /// R1 用 `;` 串接，理由是「ISO 8601 前綴不含 `;`」——而 store 不驗觀測點的值域（decode 只要求 scalar），所以手改的
    /// `"2019;x"` 與兩個觀測點分不開，`attested: [""]` 串成空字串、被 CSV 寫成空欄位、被 DuckDB 讀成 NULL，那一段在 timeline
    /// 又成了「進行中」而 status 說 undetermined（#661 R1 verify）。JSON 陣列對任何字串都無歧義，`[""]` 也是非空的一格；
    /// 開頭固定是 `[`，也不會被試算表當成公式。DuckDB 以 `valid_attested::JSON` 或 `from_json` 取回。
    static func attestedCell(_ range: DateRange) -> String? {
        guard !range.attested.isEmpty,
              let data = try? JSONSerialization.data(withJSONObject: range.attested.sorted(),
                                                     options: [.withoutEscapingSlashes]) else { return nil }
        return String(decoding: data, as: UTF8.self)
    }

    /// 從一次 load 的結果產出表格。
    public static func tables(entries: [Entry], people: [Person],
                              organizations: [Organization] = []) -> Tables {
        // key → org id。**用實際載入的機構解析，不重算 UUID**——指向不存在的機構時
        // 回 NULL 而不是憑空造一個 id，與懸空作者同一條理由：造出來的 id 會在下游
        // 變成一筆不存在的 organization 的外鍵。
        let sortedOrgs = organizations.sorted { $0.key < $1.key }
        let orgIDByKey = Dictionary(sortedOrgs.map { ($0.key, $0.id.uuidString) },
                                    uniquingKeysWith: { a, _ in a })
        let organizationRows: [[String?]] = sortedOrgs.map { o in
            [o.id.uuidString, o.key, o.displayName, o.founded, o.dissolved,
             { () -> String? in
                 // 上級機構只有在它是 `.key` 且該機構存在時才給外鍵；
                 // 字面值與懸空參照一律 NULL，不造 id。
                 guard case .key(let k)? = o.parents.current?.value else { return nil }
                 return orgIDByKey[k]
             }()]
        }
        // researcher：id 用 person 的 UUID（#35 之後 person 有不變身分），
        // 不是 key——key 是**稱呼**，會改；surrogate id 才適合當 FK。
        let sortedPeople = people.sorted { $0.key < $1.key }
        let researcherRows: [[String?]] = sortedPeople.map { p in
            // 現況欄位由 timeline 推出（valid_end、valid_end_unknown、valid_attested 三者皆 NULL 的最新一段）——冗餘但常用
            [p.id.uuidString, p.key, p.displayName(in: .latn), p.orcid?.normalized, p.openalex,
             p.profile.affiliations.current?.value.displayName,
             p.profile.ranks.current?.value,
             p.profile.administrative.current?.value,
             p.profile.appointments.current?.value,
             // status：有開放的隸屬 ＝ current，全部結束 ＝ retired，沒資料 ＝ NULL。
             // **沒資料不猜成 current**——那會讓 43 位退休者被算成現職。
             // #661：沒有開放段、但有一段只被觀測到（attested、沒有 end、不是 ended-unknown）＝ undetermined。
             // 那一段不算現職（`isOpen` 的 #70 裁決），也不能算結束——寫 retired 就是「把被看到過誤當成離開了」。
             researcherStatus(p.profile.affiliations),
             // #67：逝世日期。**與 status 正交**——status 描述隸屬，這欄描述這個人。
             // NULL ＝ 右設限（尚未觀察到死亡），**不是**「在世」的斷言。
             p.died,
             // #656：比照 #651 的 affiliation_kind——affiliation_current 只放顯示名，字面「iss」與 key「iss」印出來一樣。
             { () -> String? in
                 guard let v = p.profile.affiliations.current?.value else { return nil }
                 if case .key = v { return "organization" } else { return "literal" }
             }(),
             { () -> String? in
                 guard case .key(let k)? = p.profile.affiliations.current?.value else { return nil }
                 return orgIDByKey[k]   // 懸空的 key 回 NULL，不造 id
             }()]
        }

        // long-format 時間軸。維度值域開放，所以不攤平成寬表。
        var timelineRows: [[String?]] = []
        for p in sortedPeople {
            // 隸屬先出（值是指涉或字面，多一個外鍵欄）
            for v in p.profile.affiliations.sorted {
                let fk: String? = {
                    if case .key(let k) = v.value { return orgIDByKey[k] }
                    return nil   // .literal ＝ 未歸戶；懸空的 .key 也回 NULL，不造 id
                }()
                // #651：kind 讓未歸戶的字面與懸空的 key 分得開（兩者的 organization_id 都是 NULL）
                let kind: String = { if case .key = v.value { return "organization" } else { return "literal" } }()
                timelineRows.append([p.id.uuidString, "affiliation", v.value.displayName,
                                     v.range.start, v.range.end,
                                     v.range.endedUnknown ? "true" : nil,
                                     v.source, v.note, fk, kind, attestedCell(v.range)])
            }
            let dims: [(String, Timeline)] = [
                ("rank", p.profile.ranks),
                ("administrative", p.profile.administrative),
                ("appointment", p.profile.appointments),
                ("field", p.profile.fields),
            ] + p.profile.contacts.keys.sorted().map { ("contact:\($0)", p.profile.contacts[$0]!) }
            for (dim, tl) in dims {
                for v in tl.sorted {
                    timelineRows.append([p.id.uuidString, dim, v.value,
                                         v.range.start, v.range.end,
                                         v.range.endedUnknown ? "true" : nil,
                                         v.source, v.note, nil, nil, attestedCell(v.range)])
                }
            }
        }

        let sortedEntries = entries.sorted { $0.citekey < $1.citekey }

        let publicationRows: [[String?]] = sortedEntries.map { e in
            [e.id.uuidString, e.citekey, e.type.rawValue, e.title,
             e.date, year(of: e.date).map(String.init),
             e.fields["journaltitle"] ?? e.fields["journal"],
             // `canonicalDOIs` 而非 `fields["doi"]`（#394 verify）——§8 的遷移把 664 筆
             // 的 `fields.doi` 移除後，這一欄對它們全為 NULL。
             //
             // **只放第一個（主 DOI）**。本表一列一筆 work，而 DOI 是清單。這一欄原本是零實例下的顯式裁決
             // （2026-08-25，#394）：裁決當時全庫帶 >1 個 DOI 的 work ＝ 0 筆，取第一個不丟任何東西；觸發條件寫的是
             // 「`akashic validate` 出現任何一筆帶兩個結構化 DOI 的 work 即重裁，正解是另立一張 publication_doi 表，
             // 不是在 CSV 欄位裡塞分隔符——那會把解析責任推給下游」。觸發條件最晚在 2026-09-09 已經成立（#543 立案時
             // 量到 196 筆），而那句是散文、沒有任何機制會叫醒人（`validate` 不報多 DOI）：這一欄一直安靜地丟掉第 2 個
             // 以後的 DOI，直到 2026-09-27 #543 R1 verify 指出（#657，當時 202 筆）。2026-09-28 依那句重裁（#657）：
             // 另立 publication_doi 表（一個 DOI 一列，見下），這一欄保留第一個——與 `.bib` 的 `DOI` 欄、csl-json 的
             // `DOI` 同一條（#543：第一個是主 DOI），既有的下游查詢不必改。要全部的號就 join publication_doi。
             exportedDOIs(e).first, e.akashic.status]
        }

        // #657：一個 DOI 一列。doi_seq 0 ＝ publication.doi（同一份清單的第一個）；沒有 DOI 的 work 沒有列。
        var doiRows: [[String?]] = []
        for e in sortedEntries {
            for (i, d) in exportedDOIs(e).enumerated() {
                doiRows.append([e.id.uuidString, String(i), d])
            }
        }

        // key → person id。**用 people 的實際內容解析，不重算 UUID**——
        // 若一個 `.key(k)` 指向不存在的 person（`#7b` 的懸空警告），這裡回 NULL 而
        // 不是憑空造一個 id：造出來的 id 會在下游變成一筆不存在的 researcher 的 FK。
        let idByKey = Dictionary(people.map { ($0.key, $0.id.uuidString) },
                                 uniquingKeysWith: { a, _ in a })

        var authorRows: [[String?]] = []
        for e in sortedEntries {
            for (i, a) in e.authors.enumerated() {
                switch a {
                case let .key(k):
                    authorRows.append([e.id.uuidString, String(i), idByKey[k],
                                       people.first { $0.key == k }?.displayName(in: .latn) ?? k,
                                       "person", nil])
                // #323：團體作者。**researcher_id 留 nil**——那一欄的外鍵指向 researcher 表，指進去會是假的外鍵。
                // #596：kind 與 organization_id 讓它與未歸戶的 literal 分得開；顯示名取自匯出集合內的機構
                //（view 閉包自 #596 起收作者位指到的機構）。
                case let .organization(k):
                    authorRows.append([e.id.uuidString, String(i), nil,
                                       organizations.first { $0.key == k }?.displayName ?? k,
                                       "organization", orgIDByKey[k]])
                case let .literal(s):
                    authorRows.append([e.id.uuidString, String(i), nil, s, "literal", nil])
                }
            }
        }

        return Tables(
            researcher: Table(name: "researcher",
                              columns: ["researcher_id", "person_key", "name_full",
                                        "orcid", "openalex", "affiliation_current",
                                        "rank_current", "administrative_current",
                                        "appointment_current", "status", "died",
                                        "affiliation_current_kind", "affiliation_current_id"],
                              rows: researcherRows),
            researcherTimeline: Table(name: "researcher_timeline",
                                      columns: ["researcher_id", "dimension", "value",
                                                "valid_start", "valid_end", "valid_end_unknown",
                                                "source", "note", "organization_id", "affiliation_kind",
                                                "valid_attested"],
                                      rows: timelineRows),
            publication: Table(name: "publication",
                               columns: ["publication_id", "citekey", "type", "title",
                                         "date_raw", "year", "venue", "doi", "status"],
                               rows: publicationRows),
            publicationAuthor: Table(name: "publication_author",
                                     columns: ["publication_id", "author_seq",
                                               "researcher_id", "name_full",
                                               "author_kind", "organization_id"],
                                     rows: authorRows),
            publicationDOI: Table(name: "publication_doi",
                                  columns: ["publication_id", "doi_seq", "doi"],
                                  rows: doiRows),
            organization: Table(name: "organization",
                                columns: ["organization_id", "org_key", "name_current",
                                          "founded", "dissolved", "parent_id"],
                                rows: organizationRows))
    }

    /// 從 `date` 抽出 4 位數年份。
    ///
    /// **抽不到、或抽到 `0000` → nil。** `"0000"` 是真實 corpus 裡的資料（Zotero 對缺
    /// 日期的佔位，實測 536 筆中有 2 筆），忠實轉成 `0` 會讓下游得到一筆「西元 0 年的
    /// 出版品」——那不是資料，是佔位符被當成值。`date_raw` 保留原字串，所以資訊沒有
    /// 遺失：想追究的人查得到，做時間軸的人不會被 0 拉爆座標軸。
    ///
    /// 上界不設：未來年份（in press、預印本標次年）是合法的。
    static func year(of date: String?) -> Int? {
        guard let date,
              let r = date.range(of: "[0-9]{4}", options: .regularExpression),
              let y = Int(date[r]), y > 0 else { return nil }
        return y
    }

    // MARK: - 輸出格式

    /// RFC 4180 CSV。`nil` 輸出為**空欄位**（DuckDB 的 `read_csv` 預設把它讀成 NULL）。
    public static func csv(_ table: Table) -> String {
        func esc(_ v: String?) -> String {
            guard let v else { return "" }
            let needsQuote = v.contains(",") || v.contains("\"") || v.contains("\n")
                || v.contains("\r")
            return needsQuote ? "\"\(v.replacingOccurrences(of: "\"", with: "\"\""))\"" : v
        }
        var out = table.columns.joined(separator: ",") + "\n"
        for row in table.rows {
            out += row.map(esc).joined(separator: ",") + "\n"
        }
        return out
    }

    /// 機構鏈的層數（#667）：根是第 0 層，母機構是根的機構是第 1 層。`duckDBScript` 依這個數
    /// 逐層回填 `parent_id`。到不了根的列（成環）不計入——`load.sql` 尾端的檢查句會對它們出聲，
    /// 這裡不替它決定層數。
    public static func organizationParentLevels(_ organization: Table) -> Int {
        guard let idIndex = organization.columns.firstIndex(of: "organization_id"),
              let parentIndex = organization.columns.firstIndex(of: "parent_id") else { return 0 }
        var parentOf: [String: String] = [:]
        for row in organization.rows {
            if let id = row[idIndex], let parent = row[parentIndex] { parentOf[id] = parent }
        }
        var deepest = 0
        for start in parentOf.keys {
            var node = start, depth = 0, seen: Set<String> = [start]
            while let parent = parentOf[node] {
                guard seen.insert(parent).inserted else { depth = 0; break }   // 成環：不計入
                node = parent
                depth += 1
            }
            deepest = max(deepest, depth)
        }
        return deepest
    }

    /// DuckDB 可直接 `.read` 的建表 + 載入腳本。
    ///
    /// **不內嵌資料**——資料走 CSV，這裡只給 schema 與 `read_csv` 呼叫。把 536 筆資料
    /// 灌成 INSERT 字面值會讓腳本變成一個難以檢查的巨檔，而 CSV 可以用任何工具打開。
    ///
    /// 唯一從資料來的是 `organizationParentLevels`（#667）：上級機構要逐層回填，而 SQL 腳本
    /// 沒有迴圈，句數只能由匯出端算好——用 `organizationParentLevels(_:)` 從同一次匯出的
    /// organization 表算。**刻意沒有預設值**：預設一層正是 #667 之前的行為，三層鏈會中止。
    /// 層數少於 CSV 的實際深度時，腳本尾端的檢查句會中止並說出幾筆沒回填。
    public static func duckDBScript(csvDirectory: String = ".", organizationParentLevels: Int) -> String {
        let levels = max(0, organizationParentLevels)
        let levelUpdates = levels == 0 ? "-- （沒有任何機構帶上級機構）" : (1...levels).map { k in
            """
            UPDATE organization SET parent_id = l.parent_id
                    FROM akashic_organization_level l
                    WHERE organization.organization_id = l.organization_id AND l.level = \(k);
            """
        }.joined(separator: "\n        ")
        return """
        -- Akashic → DuckDB（#22）。**單向衍生**：這些表可隨時整個丟掉重建，
        -- canonical 永遠是 Akashic store 的 YAML 檔。
        --
        -- 用法：akashic export-tables --output <dir> && duckdb x.db -c ".read <dir>/load.sql"

        DROP TABLE IF EXISTS publication_doi;
        DROP TABLE IF EXISTS publication_author;
        DROP TABLE IF EXISTS organization_pending;
        DROP TABLE IF EXISTS publication;
        DROP TABLE IF EXISTS researcher_timeline;
        DROP TABLE IF EXISTS researcher;
        DROP TABLE IF EXISTS organization;

        -- 機構是第三種一級實體（形狀標籤 organization:）。
        CREATE TABLE organization (
            organization_id UUID PRIMARY KEY,
            org_key         TEXT NOT NULL UNIQUE,
            name_current    TEXT,
            founded         TEXT,
            dissolved       TEXT,   -- NULL ＝ 仍存續（**不是**未知）
            -- 上級機構（部分—整體）。**與人的隸屬是不同的 predicate**，
            -- 所以住在不同的表／不同的欄位，不合併成一張通用邊表。
            parent_id       UUID REFERENCES organization(organization_id)
        );

        CREATE TABLE researcher (
            researcher_id UUID PRIMARY KEY,
            person_key    TEXT NOT NULL UNIQUE,
            name_full     TEXT,
            orcid         TEXT,
            openalex      TEXT,
            -- 以下為**現況**便利欄位，可由 researcher_timeline 推出（valid_end IS NULL
            -- 且 valid_end_unknown IS NULL 且 valid_attested IS NULL 的
            -- 最新一段）。冗餘是刻意的：不放的話每個「現在誰是研究員」的查詢都要
            -- 自己寫一次 window function。
            affiliation_current   TEXT,
            rank_current          TEXT,
            administrative_current TEXT,
            appointment_current   TEXT,
            -- **本欄描述的是「隸屬」，不是這個人是否仍在研究、也不是是否在世。**
            -- retired ＝ 所有隸屬段都已結束，僅此而已：離開的人可能仍在別處發表
            -- （實測有 2017 / 2023 離職者的著作年表持續到 2026），也可能已經過世。
            -- 「還在發表嗎」請自己從 publication 表算（MAX(year) GROUP BY 研究者）；
            -- 「是否已知過世」看下面的 died 欄。
            -- current / retired / undetermined / NULL。**沒有隸屬資料時是 NULL，不猜成 current**。
            -- undetermined（#661）＝ 沒有進行中的段，但有一段只被觀測到過（valid_attested 非空、
            -- 沒有 valid_end、也不是 valid_end_unknown）：那個人在觀測時點在那裡，之後還在不在資料說不出來。
            -- 它不是 retired——把「被看到過」當成「離開了」是偽造的斷言。
            status        TEXT CHECK (status IS NULL OR status IN ('current', 'retired', 'undetermined')),
            -- 逝世日期（#67）。ISO 8601 前綴，保留來源精度（2004 / 2004-11 / 2004-11-18）
            -- —— 精度即區間寬度：'2004' 說的是「2004 年的某個時候」。
            -- **NULL ＝ 尚未觀察到死亡（右設限），不是「在世」的斷言**：它同時涵蓋
            -- 「真的還活著」與「已故但未記錄」，而從資料的角度那兩者是同一件事。
            -- 內容**不驗證**（同 organization.founded / dissolved 與 valid_start /
            -- valid_end 的慣例）——這裡只保證形狀，不保證是合法的 ISO 前綴。
            --
            -- **與 status 完全正交**：status 純由隸屬時間軸推導，died 不參與。所以
            -- died IS NOT NULL AND status = 'current' 是**可能出現的**——那表示隸屬段
            -- 還開著（可能是死於任內而漏記結束日，也可能是離職多年後才過世、開放段
            -- 只是資料缺漏）。哪一種為真無法自動判斷，由 akashic doctor 報告、不代為
            -- 關閉。要找這些矛盾：WHERE died IS NOT NULL AND status = 'current'
            died          TEXT,
            -- #656：affiliation_current 的三態，比照 researcher_timeline.affiliation_kind：organization（affiliation_current 是
            -- 機構的 key 字串本身，不是機構名——要名字請 join organization.name_current；含懸空的 key）／literal（未歸戶，
            -- affiliation_current 是原字串）；沒有現職隸屬時 NULL。affiliation_current_id 只在 key 對得到機構時
            -- 非空——懸空的 key 與字面都是 NULL，要分兩者看 kind。新欄加在最後：load.sql 依位置灌表。
            affiliation_current_kind TEXT,
            affiliation_current_id   UUID REFERENCES organization(organization_id)
        );

        -- #20 的 valid-time 歷史。**long format**：維度值域是開放的（新職稱只是一個
        -- 新字串），攤平成寬表會讓每個新值變成一次 schema 變更。
        -- 「歷任所長」＝ WHERE dimension='administrative' AND value='所長'
        CREATE TABLE researcher_timeline (
            researcher_id UUID NOT NULL REFERENCES researcher(researcher_id),
            dimension     TEXT NOT NULL,
            value         TEXT NOT NULL,
            valid_start   TEXT,   -- ISO 8601 前綴，保留來源精度（2003 / 2003-01 / 2003-01-15）
            -- 「進行中」的判準是 valid_end IS NULL **且** valid_end_unknown IS NULL **且** valid_attested IS NULL——
            -- 只看 valid_end 會把「已結束、時點未知」（#63 的退休 PI）拉回現職；不看 valid_attested 會把
            -- 「只被觀測到過」（#70）讀成進行中（#661）。
            valid_end     TEXT,   -- NULL 且 valid_end_unknown、valid_attested 也 NULL ＝ 仍在進行中
            valid_end_unknown BOOLEAN,  -- TRUE ＝ 已結束、時點未知（#63）；NULL ＝ 不適用
            source        TEXT,
            -- source 的另外半條命（#91）。source 分得出「名冊認證 vs 論文推得」，
            -- 但同一個來源底下的性質差異——學程關係 vs 所轄中心人員——只寫在這裡。
            -- 丟掉它，下游就只能 parse 散文或放棄該區分。
            note          TEXT,
            -- 只有 dimension='affiliation' 且該筆已歸戶、而且 key 對得到機構時非空。
            -- NULL 的意思要看 affiliation_kind：literal ＝ 未歸戶；organization ＝ key 懸空（斷掉的參照）。
            organization_id UUID REFERENCES organization(organization_id),
            -- #651：比照 publication_author.author_kind。只有 dimension='affiliation' 的列有值：
            -- organization（value 是機構的 key 字串本身，不是機構名；含懸空的 key）／literal（未歸戶）。其他維度是 NULL。
            -- 「還沒歸戶的隸屬」是 WHERE affiliation_kind = 'literal'，不是 organization_id IS NULL。
            -- 新欄加在最後：load.sql 依位置灌表。
            affiliation_kind TEXT,
            -- #661：觀測點（#70 的 attested），依序寫成 JSON 陣列（["2019-05","2021"]）；沒有時 NULL。以 valid_attested::JSON 取回。
            -- 非空而 valid_end 與 valid_end_unknown 都 NULL ＝ 只被觀測到過，不是進行中也不是已結束。
            valid_attested TEXT
        );

        CREATE TABLE publication (
            publication_id UUID PRIMARY KEY,
            citekey        TEXT NOT NULL UNIQUE,
            type           TEXT NOT NULL,
            title          TEXT,
            date_raw       TEXT,
            year           INTEGER,
            venue          TEXT,
            -- 只放第一個 DOI（主 DOI，與 .bib／csl-json 的 DOI 欄同一條，#543）。一筆 work 可以有多個 DOI，
            -- 全部在 publication_doi（#657）；這一欄等於那張表 doi_seq = 0 的列。
            doi            TEXT,
            status         TEXT
        );

        -- #657：一筆 work 的全部 DOI，一個 DOI 一列。多個 DOI 是真的（多數是 APA 一九九〇年代的 10.1037//x 與 10.1037/x
        -- 成對，兩個都是有效的號），所以不在 publication.doi 裡塞分隔符——那會把解析責任推給下游。
        -- doi_seq 0 ＝ 主 DOI ＝ publication.doi；其餘依 store 裡的順序，正規形（小寫）相同的只留一列，doi_seq 在去重之後連續。
        -- 沒有 DOI 的 work 沒有列。同一個 DOI 可以出現在兩筆 work（跨記錄的重複，#79），所以 doi 不設全域 UNIQUE。
        CREATE TABLE publication_doi (
            publication_id UUID    NOT NULL REFERENCES publication(publication_id),
            doi_seq        INTEGER NOT NULL,
            doi            TEXT    NOT NULL,
            PRIMARY KEY (publication_id, doi_seq),
            UNIQUE (publication_id, doi)
        );

        -- author_kind：person（researcher_id 指向 researcher）／organization（organization_id 指向 organization，
        -- 團體作者）／literal（**未歸戶**，兩個 id 都 NULL）。「還沒歸戶的」是 `WHERE author_kind = 'literal'`——
        -- 只看 `researcher_id IS NULL` 會把已歸戶的團體作者一起算進去（#596）。懸空的 key：kind 照實、id 為 NULL。
        CREATE TABLE publication_author (
            publication_id UUID    NOT NULL REFERENCES publication(publication_id),
            author_seq     INTEGER NOT NULL,
            researcher_id  UUID    REFERENCES researcher(researcher_id),
            name_full      TEXT    NOT NULL,
            author_kind    TEXT    NOT NULL,
            organization_id UUID   REFERENCES organization(organization_id),
            PRIMARY KEY (publication_id, author_seq)
        );

        -- organization 分兩步載入（#92）。`parent_id` 是**自我參照**外鍵，而 DuckDB
        -- 對 FK 的檢查針對「statement 開始前的表狀態」——同一個 bulk INSERT 裡，後面
        -- 的列看不到前面的列，所以把母機構排在 CSV 前面也不救。先插骨架、再回填，
        -- 保留 FK 約束（拿掉約束會讓下游再也擋不住懸空 parent）。
        INSERT INTO organization (organization_id, org_key, name_current, founded, dissolved)
            SELECT organization_id, org_key, name_current, founded, dissolved
            FROM read_csv('\(csvDirectory)/organization.csv', header = true);
        -- 回填也要逐層、由上而下（#667）。一句 UPDATE 同時設「b→a」與「c→b」，DuckDB
        -- 會對三層鏈報外鍵錯誤；逐層時第 k 層的母機構已在前一句填好、子機構仍是 NULL，
        -- 同一句裡沒有任何一列被另一列的新值參照。這份資料有 \(levels) 層。
        CREATE OR REPLACE TEMP TABLE akashic_organization_level AS
            WITH RECURSIVE lvl(organization_id, parent_id, level) AS (
                SELECT organization_id, parent_id, 0
                    FROM read_csv('\(csvDirectory)/organization.csv', header = true)
                    WHERE parent_id IS NULL
                UNION ALL
                SELECT c.organization_id, c.parent_id, lvl.level + 1
                    FROM read_csv('\(csvDirectory)/organization.csv', header = true) c
                    JOIN lvl ON c.parent_id = lvl.organization_id
            )
            SELECT organization_id, parent_id, level FROM lvl;
        \(levelUpdates)
        -- 沒回填到的上級機構（成環，或這份腳本的層數與 CSV 不符）要中止，不留下安靜的 NULL。
        -- 寫成 CREATE … AS：通過時零列、不印東西；裸 SELECT 會在 CLI 印出一個空表，看起來像出了事。
        CREATE OR REPLACE TEMP TABLE akashic_organization_check AS
            SELECT error('organization.csv 有 ' || count(*) || ' 筆的上級機構沒有回填（成環，或 load.sql 與 CSV 不是同一次匯出）') AS failure
            FROM read_csv('\(csvDirectory)/organization.csv', header = true) c
            JOIN organization o USING (organization_id)
            WHERE c.parent_id IS NOT NULL AND o.parent_id IS NULL
            HAVING count(*) > 0;
        DROP TABLE akashic_organization_check;
        DROP TABLE akashic_organization_level;
        INSERT INTO researcher
            SELECT * FROM read_csv('\(csvDirectory)/researcher.csv', header = true);
        INSERT INTO researcher_timeline
            SELECT * FROM read_csv('\(csvDirectory)/researcher_timeline.csv', header = true);
        INSERT INTO publication
            SELECT * FROM read_csv('\(csvDirectory)/publication.csv', header = true);
        INSERT INTO publication_author
            SELECT * FROM read_csv('\(csvDirectory)/publication_author.csv', header = true);
        INSERT INTO publication_doi
            SELECT * FROM read_csv('\(csvDirectory)/publication_doi.csv', header = true);

        """
    }
}
