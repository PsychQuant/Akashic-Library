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
/// | `.key(k)` | `researcher_id` = 該 person 的 id、`name_full` = 顯示名 |
/// | `.literal(s)` | `researcher_id` = **NULL**、`name_full` = `s` |
///
/// 不需要「是否已歸戶」的旗標欄位——**缺席本身就是資訊**，而且 SQL 的 `IS NULL`
/// 直接就是「未歸戶」的查詢。
///
/// ## temporal 維度怎麼出（#20 落地後）
///
/// `PersonProfile` 的每個維度是**一條時間軸**，關係式端對應一張 **long-format** 表
/// `researcher_timeline(researcher_id, dimension, value, start, end, end_unknown, source)`。
///
/// **不攤平成寬表**（`rank_2020`、`rank_2021`…）：維度值域是開放的（新職稱只是一個
/// 新字串），攤平會讓每個新值變成一次 schema 變更。long format 讓「歷任所長」是
/// `WHERE dimension='administrative' AND value='所長'`，而不是對欄位名做字串比對。
///
/// `researcher` 保留**現況**欄位（`rank_current` 等）作為便利視角——它們可由 timeline
/// 推出（`end IS NULL` 的最新一段），冗餘但常用。**冗餘是刻意的**：不放的話每個
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
        public var organization: Table

        public var all: [Table] {
            [organization, researcher, researcherTimeline, publication, publicationAuthor]
        }
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
            // 現況欄位由 timeline 推出（`end IS NULL` 的最新一段）——冗餘但常用
            [p.id.uuidString, p.key, p.displayName(in: .latn), p.orcid, p.openalex,
             p.profile.affiliations.current?.value.displayName,
             p.profile.ranks.current?.value,
             p.profile.administrative.current?.value,
             p.profile.appointments.current?.value,
             // status：有開放的隸屬 ＝ current，全部結束 ＝ retired，沒資料 ＝ NULL。
             // **沒資料不猜成 current**——那會讓 43 位退休者被算成現職。
             p.profile.affiliations.isEmpty ? nil
                : (p.profile.affiliations.current != nil ? "current" : "retired"),
             // #67：逝世日期。**與 status 正交**——status 描述隸屬，這欄描述這個人。
             // NULL ＝ 右設限（尚未觀察到死亡），**不是**「在世」的斷言。
             p.died]
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
                timelineRows.append([p.id.uuidString, "affiliation", v.value.displayName,
                                     v.range.start, v.range.end,
                                     v.range.endedUnknown ? "true" : nil,
                                     v.source, v.note, fk])
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
                                         v.source, v.note, nil])
                }
            }
        }

        let sortedEntries = entries.sorted { $0.citekey < $1.citekey }

        let publicationRows: [[String?]] = sortedEntries.map { e in
            [e.id.uuidString, e.citekey, e.type, e.title,
             e.date, year(of: e.date).map(String.init),
             e.fields["journaltitle"] ?? e.fields["journal"],
             e.fields["doi"], e.akashic.status]
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
                                       people.first { $0.key == k }?.displayName(in: .latn) ?? k])
                case let .literal(s):
                    authorRows.append([e.id.uuidString, String(i), nil, s])
                }
            }
        }

        return Tables(
            researcher: Table(name: "researcher",
                              columns: ["researcher_id", "person_key", "name_full",
                                        "orcid", "openalex", "affiliation_current",
                                        "rank_current", "administrative_current",
                                        "appointment_current", "status", "died"],
                              rows: researcherRows),
            researcherTimeline: Table(name: "researcher_timeline",
                                      columns: ["researcher_id", "dimension", "value",
                                                "valid_start", "valid_end", "valid_end_unknown",
                                                "source", "note", "organization_id"],
                                      rows: timelineRows),
            publication: Table(name: "publication",
                               columns: ["publication_id", "citekey", "type", "title",
                                         "date_raw", "year", "venue", "doi", "status"],
                               rows: publicationRows),
            publicationAuthor: Table(name: "publication_author",
                                     columns: ["publication_id", "author_seq",
                                               "researcher_id", "name_full"],
                                     rows: authorRows),
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

    /// DuckDB 可直接 `.read` 的建表 + 載入腳本。
    ///
    /// **不內嵌資料**——資料走 CSV，這裡只給 schema 與 `read_csv` 呼叫。把 536 筆資料
    /// 灌成 INSERT 字面值會讓腳本變成一個難以檢查的巨檔，而 CSV 可以用任何工具打開。
    public static func duckDBScript(csvDirectory: String = ".") -> String {
        """
        -- Akashic → DuckDB（#22）。**單向衍生**：這些表可隨時整個丟掉重建，
        -- canonical 永遠是 Akashic store 的 YAML 檔。
        --
        -- 用法：akashic export-tables --output <dir> && duckdb x.db -c ".read <dir>/load.sql"

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
            -- 且 valid_end_unknown IS NULL 的
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
            -- current / retired / NULL。**沒有隸屬資料時是 NULL，不猜成 current**。
            status        TEXT CHECK (status IS NULL OR status IN ('current', 'retired')),
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
            died          TEXT
        );

        -- #20 的 valid-time 歷史。**long format**：維度值域是開放的（新職稱只是一個
        -- 新字串），攤平成寬表會讓每個新值變成一次 schema 變更。
        -- 「歷任所長」＝ WHERE dimension='administrative' AND value='所長'
        CREATE TABLE researcher_timeline (
            researcher_id UUID NOT NULL REFERENCES researcher(researcher_id),
            dimension     TEXT NOT NULL,
            value         TEXT NOT NULL,
            valid_start   TEXT,   -- ISO 8601 前綴，保留來源精度（2003 / 2003-01 / 2003-01-15）
            -- 「進行中」的判準是 valid_end IS NULL **且** valid_end_unknown IS NULL——
            -- 只看 valid_end 會把「已結束、時點未知」（#63 的退休 PI）拉回現職。
            valid_end     TEXT,   -- NULL 且 valid_end_unknown 也 NULL ＝ 仍在進行中
            valid_end_unknown BOOLEAN,  -- TRUE ＝ 已結束、時點未知（#63）；NULL ＝ 不適用
            source        TEXT,
            -- source 的另外半條命（#91）。source 分得出「名冊認證 vs 論文推得」，
            -- 但同一個來源底下的性質差異——學程關係 vs 所轄中心人員——只寫在這裡。
            -- 丟掉它，下游就只能 parse 散文或放棄該區分。
            note          TEXT,
            -- 只有 dimension='affiliation' 且該筆已歸戶時非空。
            -- **NULL ＝ 未歸戶**，與 publication_author.researcher_id 同語意——
            -- 不加「是否已歸戶」旗標欄位，缺席本身就是資訊，而且 IS NULL 直接就是查詢。
            organization_id UUID REFERENCES organization(organization_id)
        );

        CREATE TABLE publication (
            publication_id UUID PRIMARY KEY,
            citekey        TEXT NOT NULL UNIQUE,
            type           TEXT NOT NULL,
            title          TEXT,
            date_raw       TEXT,
            year           INTEGER,
            venue          TEXT,
            doi            TEXT,
            status         TEXT
        );

        -- researcher_id 為 NULL ＝ **未歸戶的作者**（Akashic 的 `.literal`）。
        -- 這不是缺漏，是狀態——`WHERE researcher_id IS NULL` 就是「還沒歸戶的」。
        CREATE TABLE publication_author (
            publication_id UUID    NOT NULL REFERENCES publication(publication_id),
            author_seq     INTEGER NOT NULL,
            researcher_id  UUID    REFERENCES researcher(researcher_id),
            name_full      TEXT    NOT NULL,
            PRIMARY KEY (publication_id, author_seq)
        );

        -- organization 分兩步載入（#92）。`parent_id` 是**自我參照**外鍵，而 DuckDB
        -- 對 FK 的檢查針對「statement 開始前的表狀態」——同一個 bulk INSERT 裡，後面
        -- 的列看不到前面的列，所以把母機構排在 CSV 前面也不救。先插骨架、再回填，
        -- 保留 FK 約束（拿掉約束會讓下游再也擋不住懸空 parent）。
        INSERT INTO organization (organization_id, org_key, name_current, founded, dissolved)
            SELECT organization_id, org_key, name_current, founded, dissolved
            FROM read_csv('\(csvDirectory)/organization.csv', header = true);
        UPDATE organization SET parent_id = c.parent_id
            FROM read_csv('\(csvDirectory)/organization.csv', header = true) c
            WHERE organization.organization_id = c.organization_id
              AND c.parent_id IS NOT NULL;
        INSERT INTO researcher
            SELECT * FROM read_csv('\(csvDirectory)/researcher.csv', header = true);
        INSERT INTO researcher_timeline
            SELECT * FROM read_csv('\(csvDirectory)/researcher_timeline.csv', header = true);
        INSERT INTO publication
            SELECT * FROM read_csv('\(csvDirectory)/publication.csv', header = true);
        INSERT INTO publication_author
            SELECT * FROM read_csv('\(csvDirectory)/publication_author.csv', header = true);

        """
    }
}
