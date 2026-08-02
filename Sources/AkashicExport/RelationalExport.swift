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
/// ## 範圍（誠實記，`#22` 的完整交付需要 #20 / #21）
///
/// `researcher` 表目前只有身分欄位（id / key / 顯示名 / ORCID）。**`status` / `rank` /
/// 任期需要 `#20` 的 `Person.affiliations`**，那個模型還不存在——現在硬塞欄位只會產生
/// 一批永遠是 NULL 的行，讓下游以為「查過了、沒有」。等 #20 落地再加。
public enum RelationalExport {

    /// 一張表：欄位名 + 逐行的值（`nil` ＝ SQL NULL）。
    public struct Table: Equatable {
        public let name: String
        public let columns: [String]
        public var rows: [[String?]]
    }

    public struct Tables: Equatable {
        public var researcher: Table
        public var publication: Table
        public var publicationAuthor: Table

        public var all: [Table] { [researcher, publication, publicationAuthor] }
    }

    /// 從一次 load 的結果產出表格。
    public static func tables(entries: [Entry], people: [Person]) -> Tables {
        // researcher：id 用 person 的 UUID（#35 之後 person 有不變身分），
        // 不是 key——key 是**稱呼**，會改；surrogate id 才適合當 FK。
        let researcherRows: [[String?]] = people
            .sorted { $0.key < $1.key }
            .map { p in
                [p.id.uuidString, p.key, p.names.first, p.orcid, p.openalex]
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
                                       people.first { $0.key == k }?.names.first ?? k])
                case let .literal(s):
                    authorRows.append([e.id.uuidString, String(i), nil, s])
                }
            }
        }

        return Tables(
            researcher: Table(name: "researcher",
                              columns: ["researcher_id", "person_key", "name_full",
                                        "orcid", "openalex"],
                              rows: researcherRows),
            publication: Table(name: "publication",
                               columns: ["publication_id", "citekey", "type", "title",
                                         "date_raw", "year", "venue", "doi", "status"],
                               rows: publicationRows),
            publicationAuthor: Table(name: "publication_author",
                                     columns: ["publication_id", "author_seq",
                                               "researcher_id", "name_full"],
                                     rows: authorRows))
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
        DROP TABLE IF EXISTS publication;
        DROP TABLE IF EXISTS researcher;

        CREATE TABLE researcher (
            researcher_id UUID PRIMARY KEY,
            person_key    TEXT NOT NULL UNIQUE,
            name_full     TEXT,
            orcid         TEXT,
            openalex      TEXT
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

        INSERT INTO researcher
            SELECT * FROM read_csv('\(csvDirectory)/researcher.csv', header = true);
        INSERT INTO publication
            SELECT * FROM read_csv('\(csvDirectory)/publication.csv', header = true);
        INSERT INTO publication_author
            SELECT * FROM read_csv('\(csvDirectory)/publication_author.csv', header = true);

        """
    }
}
