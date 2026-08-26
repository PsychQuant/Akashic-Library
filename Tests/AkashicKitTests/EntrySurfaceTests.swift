import XCTest
@testable import AkashicCore
@testable import AkashicMCPKit

/// `Entry` 的每個序列化欄位都必須出現在讀取面（#425 verify HIGH）。
///
/// ## 這道守衛防的是什麼
///
/// `entryDict` 逐欄位組 payload，而 #394 新增的 `doi`／`pmid`／`isbn` **一個都沒進去**
/// ——`akashic get-entry` 與 MCP 兩面同時對 work 的識別碼失明。
///
/// 這與已修的 venue ISSN 是**同一族、換一個 entity kind**。修 venue 那次我加了
/// `VenueSurfaceTests`，但**沒有問「這一族還有誰」**——於是同一個缺口在 entry 上
/// 又存在了一輪。本檔是那個問題的答案。
///
/// ## 誠實邊界
///
/// 它查的是**服務端有沒有讀那個欄位**，不是渲染得對不對。一個把 `doi` 讀出來卻印成
/// 空字串的實作仍會通過。這是必要條件不是充分條件。
final class EntrySurfaceTests: XCTestCase {

    static func repoFile(_ rel: String) throws -> String {
        try String(contentsOf: URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent(rel), encoding: .utf8)
    }

    /// 候選路徑擇一存在者。全部都不在 → 具名列出全部候選（#394 verify R7 ③）。
    static func repoFileAny(_ candidates: [String], surface: String) throws -> String {
        for c in candidates {
            if let s = try? repoFile(c) { return s }
        }
        XCTFail("\(surface) 的原始碼在下列候選路徑都不存在——檔案搬家了？\n"
                + candidates.map { "  - \($0)" }.joined(separator: "\n")
                + "\n  **不要刪掉這一列**：那會讓三個讀取面的守衛靜靜退回兩個。"
                + "把新位置加進 alternates。")
        return ""
    }

    static func serviceSource() throws -> String {
        try repoFile("Sources/AkashicMCPKit/AkashicService.swift")
    }

    /// **三個讀取面**（#394 verify R4）。
    ///
    /// `entity-backlink-completeness` 執行細節 2 明文列 CLI／MCP／**App**——#263 特地把
    /// App 補進列舉，理由是「App 是取代 Zotero 的主要 UI，只用 App 的人永遠不會知道
    /// audit trail 正在腐爛」。
    ///
    /// 本檔的第一版**只讀 `AkashicService.swift` 一個檔**——它問「這一族還有哪個
    /// entity kind」，沒問「哪個 **surface**」。於是 App 對全部 664 筆 work 的識別碼
    /// 失明，而守衛在結構上看不到。**同一個形狀第三次重演**（venue ISSN → venue
    /// verdict → entry identifiers），每次都是「修完了沒問這一族還有誰」。
    ///
    /// 每個面的慣用寫法不同，所以判準逐面給：service 與 App 讀 `entry.<欄位>`，
    /// CLI 讀 JSON payload 的鍵。
    struct Surface {
        let name: String
        let path: String
        /// 檔案搬家時的候選路徑。**擇一存在者**——兩個都不在才是真的失敗
        /// （那時錯誤訊息要列出全部候選,而不是只說第一個不見了）。
        var alternates: [String] = []
        /// 給定欄位名，回傳「這個面若有讀到它，原始碼裡會出現的字串」候選。
        let patterns: (String) -> [String]
    }

    static let surfaces: [Surface] = [
        Surface(name: "MCP（entryDict）", path: "Sources/AkashicMCPKit/AkashicService.swift",
                patterns: { f in ["entry.\(f)"] + (canonicalAlias[f].map { ["entry.\($0)"] } ?? []) }),
        Surface(name: "CLI（get-entry）", path: "Sources/akashic/GetEntryCommand.swift",
                patterns: { f in ["\"\(f)\""] }),
        // **路徑收候選清單,不是單一字串**（#394 verify R7 ③）。
        //
        // 第六輪就抓到這條:#427 把 EntryViews.swift 從 `AkashicApp/Sources/` 搬進
        // `Sources/AkashicAppKit/`,而**兩種 merge 順序都零衝突**——git rename detection
        // 正確地把內容修改搬過去了,壞掉的只有這個**寫死的字串**,而字串不參與 rename
        // detection。第七輪實測 merge 後 `NSCocoaErrorDomain Code=260`。
        //
        // **比一條紅測試更糟的那半**:紅了之後最省事的修法是把 App 那一列刪掉,
        // 而三個讀取面的守衛就靜靜退回兩個——#263 把 App 補進列舉的理由正是
        // 「只用 App 的人永遠不會知道 audit trail 正在腐爛」。
        Surface(name: "App（EntryDetailView）", path: "AkashicApp/Sources/EntryViews.swift",
                alternates: ["Sources/AkashicAppKit/EntryViews.swift"],
                patterns: { f in ["entry.\(f)"] + (canonicalAlias[f].map { ["entry.\($0)"] } ?? []) }),
    ]

    /// canonical accessor 也算讀到——它的 doc 明寫「讀取請走它」。
    /// 守衛若只認欄位名的字面，會**逼呼叫端改用較差的讀法才能過關**。
    static let canonicalAlias = ["doi": "canonicalDOIs", "pmid": "canonicalPMIDs",
                                 "isbn": "canonicalISBNs"]

    /// 括號配對取完整 body——固定長度的視窗會在函式變長時假紅
    /// （`VenueSurfaceTests` 已經踩過一次）。
    static func functionBody(of signature: String, in source: String) -> String? {
        guard let sig = source.range(of: signature) else { return nil }
        var depth = 0
        var i = source.index(before: sig.upperBound)
        let start = i
        while i < source.endIndex {
            if source[i] == "{" { depth += 1 }
            else if source[i] == "}" {
                depth -= 1
                if depth == 0 { return String(source[start...i]) }
            }
            i = source.index(after: i)
        }
        return nil
    }

    private func entryFieldNames() -> [String] {
        Mirror(reflecting: Entry(id: UUID(), citekey: "k", type: .periodicalArticle, title: "T"))
            .children.compactMap(\.label)
    }

    func testReflectionActuallySeesFields() {
        XCTAssertGreaterThanOrEqual(entryFieldNames().count, 10,
                                    "反射應看到 Entry 的全部欄位，實得 \(entryFieldNames())")
    }

    /// **守衛的守衛**：括號配對要停在函式結尾。
    func testExtractedBodyStopsAtTheFunctionEnd() throws {
        let source = try Self.serviceSource()
        guard let body = Self.functionBody(of: "func entryDict(_ entry: Entry) -> [String: Any] {",
                                           in: source)
        else { return XCTFail("找不到 entryDict") }
        XCTAssertTrue(body.contains("entry.citekey"), "body 應涵蓋整個函式")
        XCTAssertLessThan(body.count, source.count / 2, "body 不該是大半個檔案")
    }

    func testEveryFieldReachesTheReadSurface() throws {
        // **封閉豁免，附理由**——加一項就是加一列理由，不得依性質相似類推。
        let exempt: [String: String] = [
            "id": "內部 UUID 身分，任何 entity 的讀取面都不輸出它（venue／person 同）",
            "unknownFields": "tolerant-preserve 的未知鍵；`entryDict` 不逐一列舉它們"
                + "（`akashic doctor` 是它們的出口）",
        ]
        let source = try Self.serviceSource()
        guard let body = Self.functionBody(of: "func entryDict(_ entry: Entry) -> [String: Any] {",
                                           in: source)
        else { return XCTFail("找不到 entryDict —— 本測試的前提不成立") }

        // **已知缺口 ≠ 豁免**（#426）。`exempt` 說「刻意不輸出」，`knownGaps` 說
        // 「該輸出而還沒輸出」。兩者混為一談會讓守衛在下次有人問「為什麼 venues
        // 不在裡面」時給出錯的答案。兩者都早於 #394（venues #304、thesis #335），
        // 依 scope guard 不混進這個 branch。
        let knownGaps: [String: String] = [
            "venues": "#426——第 14 條邊，work 通往 venue 的唯一路徑",
            "thesis": "#426——#335 的 ThesisFacts，APA7 匯出靠它",
        ]
        for field in entryFieldNames() {
            if let gap = knownGaps[field] {
                XCTAssertTrue(gap.contains("#"), "已知缺口必須指向一張 issue")
                continue
            }
            if let why = exempt[field] {
                XCTAssertFalse(why.isEmpty, "豁免必須附理由")
                continue
            }
            // **canonical accessor 也算讀到**（#425 verify）。`canonicalDOIs` 一族的
            // doc 明寫「讀取請走它」——殘留與結構化值同時在場時它才是正典。
            // 守衛若只認 `entry.doi` 的字面，會逼呼叫端改用**較差**的讀法才能過關。
            let aliases = ["doi": "canonicalDOIs", "pmid": "canonicalPMIDs",
                           "isbn": "canonicalISBNs"]
            let reached = body.contains("entry.\(field)")
                || (aliases[field].map { body.contains("entry.\($0)") } ?? false)
            XCTAssertTrue(reached,
                          "Entry.\(field) 沒有被 entryDict 讀到——"
                          + "它會存在磁碟上而使用者兩個面都看不到，"
                          + "而那與『庫裡沒有這個值』在輸出上完全一樣")
        }
    }

    /// **每個欄位 × 每個面**——不是「有一個面讀到就算」（#394 verify R4）。
    func testEveryFieldReachesEverySurface() throws {
        // App 只顯示識別碼與書目核心；attachments／provenance／akashic 屬其他 Section
        // 或另有專屬視圖，逐面豁免。
        // 全域豁免——與姊妹測試 `testEveryFieldReachesTheReadSurface` 的 `exempt` 同一組
        // （沒有任何讀取面輸出它們）。刻意不抽成共用常數:兩支測試問的是不同的命題,
        // 而共用會讓其中一支的豁免悄悄擴張到另一支。
        let globallyExempt: Set<String> = ["id", "unknownFields"]
        // 逐面豁免:那個面**在設計上**不該顯示這個欄位。
        let perSurfaceExempt: [String: Set<String>] = [
            "App（EntryDetailView）": ["attachments", "provenance", "akashic", "references"],
            "CLI（get-entry）": [],
            "MCP（entryDict）": [],
        ]
        // 逐面**已知缺口**:該面應該顯示但目前沒有。與豁免刻意分開——豁免是裁決,
        // 缺口是待辦,把兩者混在一起會讓待辦看起來像已裁決（#426 追蹤 venues/thesis）。
        let perSurfaceKnownGaps: [String: [String: String]] = [
            "App（EntryDetailView）": [
                "venues": "#426", "thesis": "#426", "citekey": "#426",
                "type": "#426", "title": "#426", "date": "#426", "authors": "#426",
                "fields": "#426", "doi": "", "pmid": "", "isbn": "",
            ].filter { !$0.value.isEmpty },
            "CLI（get-entry）": ["venues": "#426", "thesis": "#426"],
            "MCP（entryDict）": ["venues": "#426", "thesis": "#426"],
        ]
        // **反射,不是寫死清單**（#394 verify R5 ②④）。
        //
        // 第一版寫 `let identifiers = ["doi", "pmid", "isbn"]`——於是新增任何 `Entry`
        // 欄位時它零次迴圈、照樣綠,而 `perSurfaceExempt` 列的四個名字**與那三個交集為空**,
        // 一列都不曾生效。讀者看到「逐面豁免＋理由」會合理推論本測試涵蓋全部欄位。
        //
        // 那是 `zero-instance-guards` 第 5 列具名的**覆蓋率自我謊報**:守衛多印一個 ✓,
        // 而那個 ✓ 沒有對應到任何新的事實。同一個檔案裡的姊妹測試
        // （`testEveryFieldReachesTheReadSurface`）從一開始就走 `Mirror`——本測試補上
        // surface 維度時卻把 field 維度退化成寫死,**修一個維度、弄壞另一個**。
        for s in Self.surfaces {
            let src = try Self.repoFileAny([s.path] + s.alternates, surface: s.name)
            for f in entryFieldNames()
            where !globallyExempt.contains(f)
                && !(perSurfaceExempt[s.name]?.contains(f) ?? false)
                && !(perSurfaceKnownGaps[s.name]?.keys.contains(f) ?? false) {
                let reached = s.patterns(f).contains { src.contains($0) }
                XCTAssertTrue(reached,
                              "\(s.name) 讀不到 Entry.\(f)——三個讀取面必須一致，"
                              + "否則同一個 store 的兩個面會對「這筆有沒有 \(f)」"
                              + "給出相反的答案，而使用者沒有線索知道哪個對")
            }
        }
    }
}
