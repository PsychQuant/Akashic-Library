import Foundation
import AkashicCore

/// 從 literal 機構名 bootstrap organization 記錄（#70 第三題）。
///
/// 平移 `PersonBootstrap` 的機制到機構面。literal 機構名散落在兩處：
/// `person.profile.affiliations` 的 `.literal` OrgRef、`organization.parents` 的
/// `.literal`。這裡把它們按正規化分組、按門檻建 organization entity——低於門檻的
/// 留 `.literal`（`OrgRef.literal` 本來就是「未歸戶是合法長期狀態」的設計，§8）。
///
/// **同 person 側的鐵律**：只建立、不歸戶（歸戶是 `resolve-organizations` 的第二步、
/// 交人確認）。正規化只住配對鍵（`NameNormalization.matchingKey`，#81），輸出的
/// `names` 是原字串——「中央研究院」「中研院」「Academia Sinica」各自保留寫法為
/// variant，否則下次遇到那個寫法又重新分割一次。
///
/// **key 產生的定義域**（#154 verify 154-1／154-5）：key 取機構名 NFKC 後的
/// **ASCII 字母數字 token**——雙語寫法（`國立臺灣大學 National Taiwan University`，
/// 台灣機構最常見）用英文部分產 key，全形拉丁先經 NFKC 折回 ASCII。純 CJK（NFKC 後
/// 仍無任何 ASCII token）產不出 key，但**不靜默丟**：進 `result` 的 `dropped`，由
/// CLI 明列（需人工指定 key）。用 `result`（帶 dropped）而非 `candidates`（只有能
/// 建的）才看得到全貌。
///
/// **殘留**（#154 verify 154-6，誠實記錄，不在本 change 修）：
/// 1. **中文-only 機構仍需人工給 key**。這不是 bug 是設計缺口——`bootstrap` 現在
///    只能產 ASCII slug。
///
///    **實測後這一項的優先序要往上提**（#154 verify R4 Q3，唯讀量 `~/.akashic`）：
///    真實 store 有 1769 個 entity、**0 個 affiliation literal**（160 個 affiliation
///    段落全部已是 `.key`；2121 個 `literal:` 全是 entry 的 authors，與機構無關）。
///    而且**沒有任何 importer 會產生 affiliation literal**——WoS／Zotero／MCP／App
///    的寫入面全部不碰它，只能由人手寫 YAML。
///
///    所以未來的輸入分佈＝使用者的書寫習慣，而那個習慣在現存的兩筆 organization
///    裡看得到：**各語言各自成一個變體**（`中央研究院`／`Academia Sinica`／`中研院`
///    是同一筆 org 的三個 name），而不是把中英塞進同一個字串。
///
///    在這個慣例下，**每一個機構都會落進本殘留**：三個寫法被分成三組，ASCII 那組
///    建得起來、兩組中文進 dropped。這不是偶爾的邊角，是常態。所以最有價值的下一步
///    是 `--key <name>=<key>`（或互動指定）——它能讓那三行一次收成同一個 org 的三個
///    variant，正好長成現存兩筆 organization 的樣子。
/// 2. **`suggestedKey` 的 6-token 上限與去重 `-2…-99`**（#154 verify R3 實測更正）。
///    原本寫的例子是 `national-taiwan-university-2`，但**實際最常撞的形狀不是那個**：
///
///        department-of-computer-science-and-information      ← …, NCTU
///        department-of-computer-science-and-information-2    ← …, NTU
///        graduate-institute-of-epidemiology-and-preventive   ← …, NTU
///        graduate-institute-of-epidemiology-and-preventive-2 ← …, NYCU
///
///    學術 affiliation 的格式是 `[通用的系所字詞…] + [特定機構]`，而 `prefix(6)` 的
///    截斷方向**恰好相反於資訊分布**——前 6 個 token 全是通用字，**唯一能區分的
///    token 正好被截掉**。這正是 WoS／Zotero 匯出的作者 affiliation 標準寫法，也就是
///    餵給這個工具的主要資料。覆蓋率閘對此**完全無效**（這些名字 100% ASCII）。
///    誰拿到裸 key 由 matchingKey 的字典序決定，沒有語意。
///    修法方向不是調 6 這個數字，而是**截斷要保留尾端的區辨 token**（前 4 + 最後 1），
///    或撞號時改用「加入第一個相異 token」而非流水號。
/// 2b. **覆蓋率閘的誤擋**（#154 verify R3）：分母是**字元數**，而 CJK 的資訊密度
///    遠高於拉丁字元（`國立臺灣大學` 6 字 ≈ `National Taiwan University` 26 字元的
///    資訊量）。於是「CJK 全名 + 拉丁縮寫」被系統性懲罰——而那個縮寫正是想要的 key：
///
///        臺大 NTU              60%  ✅        國立臺灣大學 NTU      27%  ❌ 誤擋
///        IBM 台灣              60%  ✅        IBM 台灣分公司        37%  ❌ 誤擋
///        東京大学（ＵＴｏｋｙｏ） 50%  ✅（剛好）  中央研究院 AS         29%  ⚠ 可接受
///
///    判準跟著「中文名有多長」跑，不是跟著「拉丁部分是不是好 key」跑。失敗模式是
///    **誠實的**（進 dropped、明列、請人給 key），不是資料汙染，所以不擋 merge。
///    曾考慮加一條縮寫例外（「全大寫、長度 ≥2、在括號或名字尾端」視為通過）。
///    **實測後決定不做**（#154 verify R4 Q3）：真實 store 對這個形狀的觀測次數是
///    **0**——因為所有形狀的觀測次數都是 0（見殘留 #1），而使用者的慣例是各變體
///    分開寫，那個慣例下覆蓋率閘根本是 no-op（群組的 `sortedNames[0]` 會是純 ASCII
///    的那個變體）。為一個沒觀測到的形狀加啟發式規則，只會多一條自己也需要邊界
///    案例的規則。誤擋的失敗模式是誠實的（進 dropped、明列、請人給 key），留在
///    殘留裡是正確的處置。
/// 3. **`resolve-organizations` 的歧義判準**只看正規化後完全相等，不做子字串／
///    縮寫比對（「中研院」vs「中央研究院」配不上）。同義詞歸戶屬 alias 層，未做。
public enum OrgBootstrap {

    public struct Candidate: Equatable {
        public var key: String
        public var names: [String]
        public var occurrences: Int
        public init(key: String, names: [String], occurrences: Int) {
            self.key = key
            self.names = names
            self.occurrences = occurrences
        }
    }

    /// 產不出合法 key 而被丟棄的機構名（#154 verify 154-1）——**不能靜默丟**：
    /// 使用者看到 N 個候選，不知道其實有 N+M 個機構名、M 個因無 ASCII 可 slug
    /// 被略過。CLI 據此明列，而非讓 `無候選` 訊息誤導成「都已建好或低於門檻」。
    public struct Result: Equatable {
        public var candidates: [Candidate]
        public var dropped: [(name: String, occurrences: Int)]
        public static func == (a: Result, b: Result) -> Bool {
            a.candidates == b.candidates
                && a.dropped.map { "\($0.name)|\($0.occurrences)" }   // display-safe-exempt: Equatable 的比較鍵，不進任何輸出面
                    == b.dropped.map { "\($0.name)|\($0.occurrences)" }   // display-safe-exempt: Equatable 的比較鍵，不進任何輸出面
        }
    }

    /// 全部 literal 機構名的來源走訪：person affiliations ＋ org parents
    /// ＋ **entry 作者位的團體 literal**（#378）。
    ///
    /// ## 為什麼作者位也算一個來源
    ///
    /// `Author` 的第三態 `.organization` 存在（#323），但先前**沒有任何元件會把作者位的
    /// literal 提名成 organization**——`resolve-people` 只比人名，本型別與 `OrgResolver`
    /// 只走 affiliations／parents。於是團體作者結構上卡在 literal 態，而
    /// `literal-first-then-key` 的終局是「所有 literal 都轉成 key，**不限於人**」。
    ///
    /// ## 判準是大括號標記，不是猜
    ///
    /// `CorporateName.isMarked` ——WoS 的 `Group Authors` 欄位與 biblatex 的
    /// `author = {{Group Name}}` 共用這個**顯式**慣例（`Author` 型別的註解已載明）。
    /// 不帶標記的 author literal 是人名，歸 `bootstrap-people` 管，這裡一律不碰。
    ///
    /// 收進來的是**去標記後**的名字：`{Taiwan Cancer Moonshot Program}` →
    /// `Taiwan Cancer Moonshot Program`。標記是傳輸慣例不是名字的一部分，
    /// organization 記錄裡不該帶著它（否則 `names` 比對與 key 產生都會被大括號污染）。
    private static func literalOrgNames(people: [Person],
                                        organizations: [Organization],
                                        entries: [Entry]) -> [String] {
        var out: [String] = []
        for p in people {
            for seg in p.profile.affiliations.entries {
                if case let .literal(s) = seg.value { out.append(s) }
            }
        }
        for o in organizations {
            for seg in o.parents.entries {
                if case let .literal(s) = seg.value { out.append(s) }
            }
        }
        for e in entries {
            for a in e.authors {
                if case let .literal(s) = a, CorporateName.isMarked(s) {
                    out.append(CorporateName.unmark(s))
                }
            }
        }
        return out
    }

    /// 從 literal 機構名產出候選。已存在的 organization（其 `names` variant）不重複產出。
    ///
    /// **只是 `result` 的投影**（#154 verify 154-4 附帶）：原本兩者各有一份分組邏輯
    /// ——兩份會漂移，而且漂移的方向恰好是「`candidates` 靜默丟、`result` 有記錄」，
    /// 也就是這個 issue 本來要修的病。收斂成單一來源。
    public static func candidates(people: [Person],
                                  organizations: [Organization],
                                  entries: [Entry] = []) -> [Candidate] {
        result(people: people, organizations: organizations, entries: entries).candidates
    }

    /// 候選 + 丟棄清單（#154 verify 154-1）：產不出 key 的機構名要能被 CLI 說出來，
    /// 不是靜默消失。這是分組與 key 產生的**唯一**實作。
    public static func result(people: [Person],
                              organizations: [Organization],
                              entries: [Entry] = []) -> Result {
        // 既有 org 的所有寫法（正規化）——已在 resolve 的比對範圍內，不重造
        let known = Set(organizations.flatMap { org in
            org.names.entries.map { NameNormalization.matchingKey($0.value) }
        })
        var takenKeys = Set(organizations.map(\.key))

        var groups: [String: (names: [String], count: Int)] = [:]
        for raw in literalOrgNames(people: people, organizations: organizations, entries: entries) {
            let name = CorporateName.unmark(raw).trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty else { continue }
            let id = NameNormalization.matchingKey(name)
            guard !known.contains(id) else { continue }
            var g = groups[id] ?? ([], 0)
            if !g.names.contains(name) { g.names.append(name) }
            g.count += 1
            groups[id] = g
        }

        var cands: [Candidate] = []
        var dropped: [(name: String, occurrences: Int)] = []
        for (_, g) in groups.sorted(by: {
            $0.value.count == $1.value.count ? $0.key < $1.key : $0.value.count > $1.value.count
        }) {
            let sortedNames = g.names.sorted()
            if let key = suggestedKey(from: sortedNames[0], taken: takenKeys) {
                takenKeys.insert(key)
                cands.append(Candidate(key: key, names: sortedNames, occurrences: g.count))
            } else {
                dropped.append((name: sortedNames[0], occurrences: g.count))
            }
        }
        return Result(candidates: cands, dropped: dropped)
    }

    /// 機構名 → key slug。機構名不做 `Last, First` 重排（那是人名的慣例）。
    ///
    /// **只取 ASCII token**（#154 verify 154-1）：台灣機構最常見的寫法是雙語
    /// （`國立臺灣大學 National Taiwan University`），英文名就在同一字串裡——slug
    /// 全名會因 CJH 字元讓 `StoreKey.isValid` 失敗、整個候選被丟。改成濾出**純
    /// ASCII 字母數字的 token**（CJK token 略過），雙語名用英文部分產 key。
    ///
    /// **先 NFKC 相容正規化**（#154 verify 154-5）：全形拉丁（`Ｎａｔｉｏｎａｌ`）
    /// 在 Unicode 上不是 ASCII，逐字元判斷會整串濾掉、機構被誤丟。全形英數在 CJK
    /// 輸入法下是**常見**產物，不是邊角。這與配對鍵的做法一致——`NameNormalization`
    /// `matchingKey` 第一步就是 NFKC；key 產生沿用同一個正規化階梯才不會出現
    /// 「配得上但建不出來」的錯位。正規化只用於**產 key**，`names` 仍存原字串。
    ///
    /// **殘留限制**：純 CJK（NFKC 後仍無任何 ASCII token）產不出 key → 回 nil，由
    /// `result` 的 `dropped` 回報、CLI 明列（不再靜默）。中文-only 機構需人先給 key。
    static func suggestedKey(from name: String, taken: Set<String>) -> String? {
        // token 內只保留 ASCII 字母數字；含 CJK 的 token slug 後為空、被濾掉
        func asciiSlug(_ s: String) -> String {
            String(s.lowercased().map { ($0.isASCII && ($0.isLetter || $0.isNumber)) ? $0 : "-" })
                .split(separator: "-").joined(separator: "-")
        }
        let name = name.precomposedStringWithCompatibilityMapping
        let asciiTokens = name.split(whereSeparator: \.isWhitespace)
            .map { asciiSlug(String($0)) }.filter { !$0.isEmpty }
        guard !asciiTokens.isEmpty else { return nil }
        let base = asciiTokens.prefix(6).joined(separator: "-")
        guard !base.isEmpty, StoreKey.isValid(base) else { return nil }
        // **ASCII 產出要有實質內容**（#154 verify 154-7——NFKC 引入的回歸）。
        //
        // NFKC 會把符號殘渣折成 ASCII：`℡`→`tel`、`™`→`tm`、`Ⅲ`→`iii`、`①`→`1`、
        // `（Ａ）`→`(a)`。於是純 CJK 機構名突然「產得出 key」——席位實測 8 個名字
        // 有 6 個從**誠實列進 dropped** 變成產出垃圾 key，而且已用 `--apply` 實際
        // 寫進 store：
        //
        //     中央研究院℡   → tel        國家衛生研究院℡ → tel-2
        //     榮總２院區     → 2          第２醫院         → 2-2
        //     臺大醫院２院區 → 2-3        長庚２院區       → 2-4
        //
        // 兩個毫不相干的機構被一個符號殘渣綁進同一個 key 家族，誰拿到 `tel`、誰拿到
        // `tel-2` 只取決於分組排序。這**正好推翻 154-1 的目的**：判準本是「產不出
        // key 就要說出來」，變成「產得出一個**假的** key 就不說了」——使用者失去的
        // 資訊比靜默丟棄更多，因為 store 裡多了永久識別碼。
        //
        // 判準是 **ASCII 覆蓋率**，不是長度。第一版用「≥3 字元且含字母」——`tel`
        // 剛好通過（3 個字母），沒修到。覆蓋率才貼根因：符號殘渣**依定義**只佔名字
        // 的一小部分，真正的雙語名則以拉丁為主。實測分佈乾淨分開：
        //
        //     37% 中央研究院℡    28% 中央研究院™     25% 中研院①
        //     25% 第２醫院       20% 榮總２院區      12% 中央研究院（Ａ）
        //     33% 國立臺灣大學Ⅲ  ← 以上全是殘渣
        //     ─────────────────────── 門檻 50% ───────────────────────
        //     60% 臺大 NTU      73% 中央研究院 Academia Sinica
        //     80% 國立臺灣大學 National Taiwan University
        //    100% Ｎａｔｉｏｎａｌ…（全形拉丁）  100% ﬁnance Institute（ligature）
        //
        // 上下之間有 23 個百分點的空隙，門檻不敏感。另要求至少一個 ASCII **字母**
        // ——純數字名（`2020`）的 slug 對人沒有意義。
        let nfkcChars = name.filter { !$0.isWhitespace }
        let asciiAlnum = nfkcChars.filter { $0.isASCII && ($0.isLetter || $0.isNumber) }
        guard !nfkcChars.isEmpty,
              asciiAlnum.count * 2 >= nfkcChars.count,
              asciiAlnum.contains(where: { $0.isLetter })
        else { return nil }
        if !taken.contains(base) { return base }
        for i in 2...99 where StoreKey.isValid("\(base)-\(i)") && !taken.contains("\(base)-\(i)") {
            return "\(base)-\(i)"
        }
        return nil
    }

    public static func organizationsFor(_ candidates: [Candidate]) -> [Organization] {
        candidates.map { c in
            var org = Organization(key: c.key)
            // names 是時間軸——bootstrap 的寫法無時序，各成一段無日期
            org.names = TimelineOf(c.names.map { TemporalValue(value: $0, range: DateRange()) })
            return org
        }
    }
}
