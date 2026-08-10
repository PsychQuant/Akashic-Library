import Foundation
import ArgumentParser
import AkashicCore
import AkashicMCPKit

/// #218：person 的**讀取面**（CLI）。與 MCP 的 `akashic_person` 共用
/// `AkashicService.person` ——同 `update-person`（#68）與 `create-entry`（#206）的作法。
///
/// ## 為什麼這個命令需要存在
///
/// 「這個人寫了什麼」的衍生鏈本來就是完整的：
///
///     LibraryIndex  authors(person_key) + idx_authors_key
///       → QueryEngine.personPublications(key:library:)
///         → AkashicService.person()      ← MCP 面到此為止
///
/// 但那條鏈**只有 MCP 接上去**。CLI 能用 `update-person` **改寫**一筆 person
/// 記錄，卻沒有任何入口**讀出**一筆——能力可用性取決於使用者走哪個面，正是
/// #206 已經裁決過的那個不對稱（其餘同族缺口見 #219）。
///
/// **不要把這句話講過頭**（verify #220 LOW）：`akashic query --author <key>` 本來
/// 就列得出那個人的著作。缺的不是「著作清單」，是**聚合檢視**——記錄本身
/// （names／orcid／隸屬）＋ 著作 ＋ 合著者在同一個回應裡，也就是 MCP 的
/// `akashic_person` 一直有、CLI 一直沒有的那個形狀。
///
/// ## 著作不在記錄裡，而且不該在
///
/// `Person` 沒有、也不會有 `works:` 欄位。`work.authors` 已經是正典；在 person
/// 再存一份就是**第二份 canonical state**，歸戶／改名／刪除都要兩邊同步而它們會
/// 分岔。方向是**衍生而非儲存**——`entity-backlink-completeness` 規則寫的就是這件事。
///
/// 這也不是一個 view：view 的成員資格由**判準**定義（住 `config.yaml`，見
/// `ViewDefinition`），而「某人的著作」沒有判準可設，它就是把既有的邊反過來讀。
///
/// ## 為什麼人可讀輸出要繞一趟 JSON
///
/// 兩種輸出都從 `service.person(...)` 的**同一個回應**產生：`--json` 原樣轉印，
/// 人可讀則解析後排版。看起來繞，但這是刻意的——若人可讀分支自己去問
/// `QueryEngine`，CLI 與 MCP 就變成兩條會分岔的路徑，而那正是本 issue 在修的病。
/// `testHumanReadableAgreesWithServiceOnPublications` 與
/// `testJSONIsServiceResponseVerbatim` 是機械防線。
///
/// ## 兩種模式的 exit code 刻意不同
///
/// `person <key>` 查不到 → **exit 1**（`ServiceError.notFound`）：指名一個 key 卻不
/// 存在，那是錯誤。`person --name <needle>` 無命中 → **exit 0** 並印「（無候選）」：
/// 搜尋沒結果是正常結果，不是錯誤。腳本要偵測「這個人不在庫裡」請用 key 模式。
struct PersonCmd: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "person",
        abstract: "看一個人：記錄 + 著作 + 合著者（著作由反向邊算出，不存在記錄裡）")

    @OptionGroup var options: LibraryOptions

    @Argument(help: "person key（與 --name 互斥）")
    var key: String?

    @Option(name: .long, help: "模糊名，回候選清單（絕不自動選；與 key 互斥）")
    var name: String?

    @Option(name: .customLong("in-library"),
            help: "只算這個 library 內的著作（僅 key 模式；與 --name 併用會被拒絕）")
    var inLibrary: String?

    @Flag(name: .long, help: "原樣輸出 service JSON（與 MCP akashic_person 逐欄位相同）")
    var json: Bool = false

    func run() throws {
        // `--in-library` 只在 key 模式生效：service 的 name 分支根本沒讀 library
        // 參數（`AkashicService.swift` 的 `if let name` 段掃全庫算 publication 計數）。
        // 靜默忽略會給出**看起來被過濾過、實際沒有**的數字，所以明確拒絕——與
        // key/name 互斥同一個處置（verify #220 MEDIUM）。
        if name != nil, inLibrary != nil {
            throw ValidationError("--in-library 只在 key 模式有效（--name 的候選計數是全庫的）")
        }
        // key/name 互斥、空白拒絕、not-found 都由 service 判——CLI 不重寫一份判準
        let store = try options.openStore()
        // **`key:` 不可省**（verify #220 HIGH，4 個 lens 獨立命中）。省略它 →
        // service 內的 store 是 keyless → `indexURL` 從 `$AKASHIC_HOME/index/<key>-<tag>.sqlite`
        // 回落到 in-store 的 `<root>/.akashic/index-<tag>.sqlite`，於是：
        //
        // - `akashic person` 與 `akashic query` / MCP 讀**兩份不同的 index**，
        //   對同一個 store 同時給出矛盾答案（實測：query「（無結果）」、person「著作（1）」），
        //   且不自癒——query 走 `ensureCurrent()` 不看 mtime，永遠停在舊答案
        // - 對已註冊的 store 寫入 `.akashic/`，而 `doctor` 對那個目錄的判詞是「可刪」；
        //   預設組態下 store root 就是 `~/.akashic`（git + Dropbox 同步樹裡的 live SQLite）
        //
        // `LibraryLocator.swift` 早就寫過這條：「同一個 store 不因開法不同而有兩份
        // 會漂移的 index（#101 實測過的病）」。MCP 側一直是對的（`Server.swift` 傳了 key）。
        let service = AkashicService(root: store.root, key: store.key,
                                     environment: ProcessInfo.processInfo.environment)
        let payload = try service.person(key: key, name: name, library: inLibrary)
        if json {
            print(payload)   // service 的輸出已 displaySafe，原樣轉印
            return
        }
        try PersonCmd.render(payload)
    }

    /// 把 service 的 JSON 排成人可讀。欄位分隔沿用 `query` 的 TSV 慣例。
    ///
    /// `internal` 而非 `private`：測試要能對照同一份 JSON 的兩種輸出。
    ///
    /// ## 為什麼這裡不再 `displaySafe`（#193 守衛的 exemption 理由）
    ///
    /// 本函式的輸入是 `AkashicService.person()` 的回應，那裡**已經逐欄位消毒**
    /// （`summaryDict` 的 citekey／type／title／authors／journal、`personDict` 的
    /// key／names／orcid／unknownFields、co_authors 的 name／person_key、
    /// candidates 的 person_key／names／literal——`AkashicService.swift` 全部
    /// 包在 `displaySafe(` 內）。本函式不從 store 另外讀任何東西。
    ///
    /// 而 **`displaySafe` 不冪等**：它把反斜線自身也逃脫（`Models.swift`
    /// 「`v == 0x5C`」那條）。對已消毒的字串再呼叫一次，會把第一次產生的
    /// `\u{0009}` 變成 `\u{005C}u{0009}`——**輸出反而壞掉**。
    ///
    /// 兩句都可否證：前者 grep `AkashicService.swift` 的 `summaryDict`／`personDict`
    /// 看有沒有裸送；後者 grep `Models.swift` 的 `0x5C`。
    ///
    /// **守衛的覆蓋範圍要說清楚**（verify #220 MEDIUM）：`DisplaySinkCoverageTests`
    /// 的豁免是**行級**的，而它只會對插值裡出現 tainted token（`citekey`／`authors`
    /// 等）的行報警。本函式其餘 print 的區域變數名（`ident`／`who`／`names`…）不在
    /// 那份 token 清單裡，**是靠守衛的盲區過關，不是靠守衛核可**。所以每一條插值
    /// print 都手動標了 marker：不是為了讓守衛閉嘴（它本來就沒說話），而是讓
    /// 「這一行的值來自哪裡」對日後讀的人可見。新增欄位時照樣要標。
    static func render(_ payload: String) throws {
        guard let obj = try JSONSerialization.jsonObject(with: Data(payload.utf8))
                as? [String: Any] else {
            throw ValidationError("service 回應不是 JSON object")
        }

        // 模糊名分支：候選清單。**不自動選**——與 service 同一個立場
        if let candidates = obj["candidates"] as? [[String: Any]] {
            guard !candidates.isEmpty else {
                print("（無候選）")
                return
            }
            print("候選（\(candidates.count)）")
            for c in candidates {
                // **`key` 與名字分兩欄，不折成一欄**（verify #220 MEDIUM）。
                // 第一版把 `person_key ?? literal` 印在同一欄，於是未歸戶的 literal
                // 佔了 identity 的位置——使用者照著複製回去會撞 notFound，而 JSON 面
                // 明明保留了區分。同一個檔案的合著者區段做對了，這裡沒有。
                //
                // 「第三欄空白＝未歸戶」不是可靠判準：`names` 為空的**已歸戶**候選
                // 印出的第三欄逐字元相同。所以 key 要有自己的欄位，缺席即資訊。
                let n = (c["publications"] as? Int).map(String.init) ?? "?"
                if let pk = c["person_key"] as? String {
                    let names = (c["names"] as? [String])?.joined(separator: "; ") ?? ""
                    print("\(n)\t\(names)\t\(pk)")   // display-safe-exempt: 見本函式 doc（值取自 AkashicService，已逐欄位 displaySafe）
                } else {
                    // 未歸戶：只有字面，**沒有 key 欄** — 與合著者區段同一個形狀
                    print("\(n)\t\((c["literal"] as? String) ?? "?")")   // display-safe-exempt: 同上
                }
            }
            if obj["truncated"] as? Bool == true {
                print("（已截斷至 50 筆——用更精確的名字，或直接給 key）")
            }
            return
        }

        // key 分支：記錄 + 著作 + 合著者
        if let person = obj["person"] as? [String: Any] {
            print((person["key"] as? String) ?? "?")   // display-safe-exempt: 見本函式 doc
            if let names = person["names"] as? [String], !names.isEmpty {
                print("  names: \(names.joined(separator: "; "))")   // display-safe-exempt: 見本函式 doc
            }
            if let orcid = person["orcid"] as? String { print("  orcid: \(orcid)") }   // display-safe-exempt: 見本函式 doc
            if let unknown = person["unknownFields"] as? [String], !unknown.isEmpty {
                // #31：未知欄位是被保留而非丟棄的——讀取面要說出來，否則
                // 「保留了」這件事對 CLI 使用者不可見
                print("  unknownFields: \(unknown.joined(separator: ", "))")   // display-safe-exempt: 見本函式 doc
            }
            // **隸屬**（verify #220 HIGH）。它是 `entity-backlink-completeness` 封閉
            // 列舉第 7 條、且**存在 person 自己身上**——漏掉它等於本 PR 新訂的規則
            // 被同一個 PR 的命令當天違反。README 的「隸屬哪裡」也靠這一段才成立。
            if let affs = person["affiliations"] as? [[String: Any]], !affs.isEmpty {
                print("  affiliations:")
                for a in affs {
                    let span = [a["start"] as? String, a["end"] as? String]
                    let period = span.contains(where: { $0 != nil })
                        ? "  [\(span[0] ?? "?")–\(span[1] ?? "")]" : ""
                    // 已歸戶標 key，未歸戶只給字面——同候選與合著者的處置
                    if let ok = a["organization_key"] as? String {
                        print("    \(ok)\(period)")   // display-safe-exempt: 見本函式 doc
                    } else {
                        print("    \((a["literal"] as? String) ?? "?")\(period)   （未歸戶）")   // display-safe-exempt: 見本函式 doc
                    }
                }
            }
        }

        let pubs = (obj["publications"] as? [[String: Any]]) ?? []
        print("")
        print("著作（\(pubs.count)）")
        if pubs.isEmpty {
            // 空集合要說出來。person 記錄存在但一篇都沒有，與「查不到這個人」
            // 是兩件事——後者由 service 擲 notFound
            print("（無）")
        } else {
            for p in pubs {
                let year = (p["year"] as? Int).map(String.init) ?? "----"
                let authors = (p["authors"] as? [String])?.joined(separator: "; ") ?? ""
                let citekey = (p["citekey"] as? String) ?? "?"
                let title = (p["title"] as? String) ?? ""
                print("\(citekey)\t\(year)\t\(authors)\t\(title)")   // display-safe-exempt: 值取自 AkashicService.summaryDict，該處已逐欄位 displaySafe；再呼叫一次會二次逃脫（displaySafe 逃脫 0x5C，不冪等）——見本函式 doc
            }
        }

        let co = (obj["co_authors"] as? [[String: Any]]) ?? []
        print("")
        print("合著者（\(co.count)）")
        if co.isEmpty {
            // **空集合要說出來**（verify #220 LOW）。第一版是 `if !co.isEmpty`，於是
            // 獨著者的輸出裡完全沒有「合著者」這個字——分辨不出「這個人沒有合著者」
            // 與「這一段掉了 / `co_authors` 欄位消失了」。而 `--json` 那側特地有測試
            // 釘住 `co_authors` 不得消失；人可讀面卻讓它消失。同一份規則的執行細節 4。
            print("（無）")
        } else {
            for c in co {
                let n = (c["count"] as? Int).map(String.init) ?? "?"
                let who = (c["name"] as? String) ?? "?"
                // 已歸戶的另外標 key——讓使用者看得出哪些合著者還沒歸戶
                let k = (c["person_key"] as? String).map { "\t\($0)" } ?? ""
                print("\(n)\t\(who)\(k)")   // display-safe-exempt: 見本函式 doc
            }
        }
    }
}
