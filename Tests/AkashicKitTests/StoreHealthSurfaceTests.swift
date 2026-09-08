import XCTest
@testable import AkashicCore
@testable import AkashicStoreIO

/// `StoreHealth` 的每個欄位都必須被消費，不得只存在型別裡（#263）。
///
/// ## 這道守衛防的是什麼
///
/// #263 的修法把健康事實收斂成單一來源，但那只解決了**已知的**欄位。真正的風險是
/// **下一個**：有人加一項檢查到 `StoreHealth`，只在 `doctor()` 渲染、忘了 App
/// ——第三條路徑沒了，卻換成「同一條路徑但只有一面顯示」。
///
/// 那個失敗**安靜**：型別編譯得過、測試全綠、doctor 照樣報問題，只有 App 使用者
/// 看不到。而 App 是取代 Zotero 的主要 UI（`replace-endnote-and-zotero`）。
///
/// ## 為什麼用反射而非人工清單
///
/// 人工清單會與型別分岔——那正是 `entity-backlink-completeness` 的表錯過三次的形狀。
/// 反射問的是型別自己：「你有哪些欄位」，然後逐一要求兩個消費面都提到它。
final class StoreHealthSurfaceTests: XCTestCase {

    /// 用一個真實的 `StoreHealth` 值取欄位名——不寫死清單。
    private func healthFieldNames() throws -> [String] {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("akashic-health-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = LibraryStore(root: root)
        try store.ensureLayout()
        let health = store.health(from: try store.load())
        return Mirror(reflecting: health).children.compactMap(\.label)
    }

    /// 欄位不得為空——反射拿不到東西時，下面兩條會 vacuous pass。
    func testReflectionActuallySeesFields() throws {
        let names = try healthFieldNames()
        XCTAssertGreaterThanOrEqual(names.count, 10,
                                    "反射應看到 StoreHealth 的全部欄位，實得 \(names)")
    }

    /// **每個欄位都必須被 `doctor()` 提到**。
    func testEveryFieldIsConsumedByDoctor() throws {
        let source = try repoFile("Sources/AkashicMCPKit/AkashicService.swift")
        // 只看 doctor() 那一段——整檔搜尋會讓別處偶然提到某個名字就算通過。
        guard let start = source.range(of: "public func doctor() throws -> String {") else {
            return XCTFail("找不到 doctor() —— 本測試的前提不成立")
        }
        let body = String(source[start.lowerBound...].prefix(6000))
        for field in try healthFieldNames() {
            XCTAssertTrue(body.contains("health.\(field)"),
                          "doctor() 沒有消費 StoreHealth.\(field) —— "
                          + "加了欄位卻只有一面渲染，那是 #263 修掉的分岔換個形狀回來")
        }
    }

    /// **每個欄位都必須經由 `AppState` 到得了 App 面**。
    ///
    /// 這裡驗的是**上游那一段**：`AppState` 必須持有整份 `health`，讓 UI 拿得到
    /// 每個欄位。持有整份而非逐欄位複製，正是讓「加欄位」不需要改 `AppState` 的原因。
    /// 下游那一段（UI 真的提到每個欄位）由 `testEveryFieldIsRenderedByTheApp` 驗。
    func testAppStateHoldsTheWholeHealthValue() throws {
        let source = try repoFile("Sources/AkashicAppKit/AppState.swift")
        XCTAssertTrue(source.contains("var health: StoreHealth?"),
                      "AppState 必須持有整份 StoreHealth——逐欄位複製會讓新欄位漏掉")
        XCTAssertTrue(source.contains("store.health(from:"),
                      "AppState 必須走 LibraryStore.health(from:)，不得自行推導")
    }

    /// 一行去掉行註解之後剩下的東西（`//` 之後全部丟掉）。
    ///
    /// **這道掃描必須分得出程式碼與註解**（#484）：判準是「原始碼裡有沒有呼叫
    /// 這三個方法」，而整檔 `contains` 連**解釋為什麼不該呼叫它們的那段註解**
    /// 也會命中。實地踩到——本輪替 `unresolvedLiteralCount` 寫的註解逐字提到
    /// 那三個名字，三條斷言當場全紅。同一個形狀本 repo 今天另外踩過兩次
    /// （workflow 的 `run:` vs 註解、`TriggerCoverage` 的 `codeOnly()`）。
    ///
    /// 只剝行註解，不處理 `/* */`——`AppState.swift` 沒有區塊註解，而寫一個
    /// 半吊子的區塊剝除器會製造新的靜默失效面。真的出現時再擴。
    private func codeOnly(_ source: String) -> String {
        source.split(separator: "\n", omittingEmptySubsequences: false)
            .map { line -> Substring in
                guard let i = line.range(of: "//") else { return line }
                return line[line.startIndex..<i.lowerBound]
            }
            .joined(separator: "\n")
    }

    /// `AppState` **不得**自行重算健康事實——那會讓單一路徑失效。
    func testAppStateDoesNotRederiveHealthFacts() throws {
        let source = codeOnly(try repoFile("Sources/AkashicAppKit/AppState.swift"))
        XCTAssertFalse(source.contains("crossRecordIssues()"),
                       "AppState 不得自己算 crossRecordIssues——走 health")
        XCTAssertFalse(source.contains("auditSourceIndex()"),
                       "AppState 不得自己算 sources audit——走 health")
        XCTAssertFalse(source.contains("layoutResidue()"),
                       "AppState 不得自己算 layoutResidue——走 health")
    }

    /// **每個欄位都必須在 App 的渲染層被提到**（#484）。
    ///
    /// 這條先前不存在，而它的檔頭寫著理由：「App 的 UI（`AkashicApp/Sources/ContentView.swift`）
    /// 不在 SwiftPM target 內、本測試建置不到它」。**那個前提已經過期**——UI 現在在
    /// `Sources/AkashicAppKit/`，而 `AkashicAppKit` 是 SwiftPM target，守衛掃得到卻沒掃。
    ///
    /// 代價是實的：#464 verify 實測 `perRecordIssues` 在整個 `Sources/AkashicAppKit/`
    /// 出現 **0 次**而守衛全綠——「App 面看不到 per-record warning」這個缺口因此一直
    /// 是綠的。加上這條之後又立刻抓到四格，其中兩格是 `AppState` 自己重算了 `health`
    /// 已經算過的東西（未解析作者、orphans），另外兩格從未被渲染（致命跨記錄問題、
    /// 未決歧異）。
    ///
    /// **掃整個目錄不只 `ContentView`**：渲染散在 `ContentView`／`RecordIssuesSummary`／
    /// `RecordIssuesSection`／`AdjudicationViews`／`AppState`。只掃一個檔會讓「搬到隔壁檔」
    /// 變成靜默通過。
    func testEveryFieldIsRenderedByTheApp() throws {
        var dir = URL(fileURLWithPath: #filePath)
        var appKit: URL?
        for _ in 0..<10 {
            dir.deleteLastPathComponent()
            let candidate = dir.appendingPathComponent("Sources/AkashicAppKit")
            if FileManager.default.fileExists(atPath: candidate.path) { appKit = candidate; break }
        }
        guard let appKit else { throw XCTSkip("找不到 Sources/AkashicAppKit —— 跳過") }
        let files = try FileManager.default.contentsOfDirectory(atPath: appKit.path)
            .filter { $0.hasSuffix(".swift") }
        XCTAssertFalse(files.isEmpty, "AkashicAppKit 沒有 .swift —— 斷言會空跑")
        // **剝掉註解**——否則一段解釋「為什麼這個欄位不渲染」的註解就能讓斷言通過，
        // 而那正是本輪在 `testAppStateDoesNotRederiveHealthFacts` 剛修掉的同一個病。
        var corpus = ""
        for f in files {
            corpus += codeOnly(try String(contentsOf: appKit.appendingPathComponent(f), encoding: .utf8))
        }

        for field in try healthFieldNames() {
            XCTAssertTrue(corpus.contains(field),
                          "App 的渲染層沒有提到 StoreHealth.\(field) —— "
                          + "只用 App 的人看不到這個事實，而 doctor 面看得到（#263 的分岔換個形狀）。"
                          + "補渲染，或若那個欄位刻意不進 App，在這裡加一列具名豁免並寫理由。")
        }
    }

    private func repoFile(_ rel: String) throws -> String {
        var dir = URL(fileURLWithPath: #filePath)
        for _ in 0..<10 {
            dir.deleteLastPathComponent()
            let candidate = dir.appendingPathComponent(rel)
            if FileManager.default.fileExists(atPath: candidate.path) {
                return try String(contentsOf: candidate, encoding: .utf8)
            }
        }
        throw XCTSkip("找不到 \(rel) —— 跳過來源掃描")
    }

    // MARK: - per-entry 檢查的三面可見性（#416）

    /// **per-entry 驗證不得只有 CLI 看得到**（#416）。
    ///
    /// 量測（2026-08-23）：`Entry.validate()` 在全樹只有一個呼叫點——
    /// `Sources/akashic/Commands.swift`，也就是 CLI 的 `validate`。`doctor()` 與
    /// App 面各 0。而 `mcp-cli-parity` 對 `validate` 是 CLI-only 的裁決，理由寫著
    /// 「讀取檢查由 `akashic_doctor` 覆蓋（**功能重疊**）」——那句話被這個量測否掉：
    /// doctor 覆蓋的是**跨記錄**檢查，per-entry 一條都不做。
    ///
    /// 落差裡有一條是 **error** 級（citekey 不符 pattern），而 MCP／App 的使用者
    /// 拿不到它。App 又是取代 Zotero 的主要 UI（`replace-endnote-and-zotero`）。
    ///
    /// 修法沿用 #263 已建立的形狀：per-entry 驗證是**唯讀**的，所以抽進 `StoreHealth`
    /// ——兩個消費面就都拿得到，且由上面那兩條反射守衛自動釘住。
    func testPerRecordIssuesAreInStoreHealth() throws {
        XCTAssertTrue(try healthFieldNames().contains("perRecordIssues"),
                      "per-entry 驗證要進 StoreHealth 才會被兩面消費（#416）")
    }

    /// **error 不得被截斷吃掉**——而實測顯示這是一個**零實例**守衛（#416 R1）。
    ///
    /// MCP 面取 `prefix(20)`，順序是 entry → person → library → organization →
    /// divergence。按族序排的話，一個有 25 筆 warning 的 store 會把後面族別的 error
    /// **整個截掉**——`errors` 計數說「有一個」而 `first` 裡看不到是哪一個。
    ///
    /// 修法是 `StoreHealth.errorsFirst`（stable partition，族內順序不變）。
    /// 依 `zero-instance-guards` 加了一列裁決（第 8 列）。
    func testErrorsFirstPutsErrorsBeforeWarningsAndKeepsFamilyOrder() {
        func w(_ o: String) -> StoreHealth.OwnedIssue {
            .init(owner: o, kind: "entry", issue: .init(severity: .warning, message: "w"))
        }
        func e(_ o: String) -> StoreHealth.OwnedIssue {
            .init(owner: o, kind: "divergence", issue: .init(severity: .error, message: "e"))
        }
        let sorted = StoreHealth.errorsFirst([w("a"), w("b"), e("x"), w("c"), e("y")])
        XCTAssertEqual(sorted.map(\.owner), ["x", "y", "a", "b", "c"],
                       "error 要在前，且**兩組內部各自保持原順序**（stable）")
    }

    /// **沒有任何 per-record 的 error 到得了載入後的 store**——這是一個量出來的事實，
    /// 不是設計意圖，所以要釘住：它變假的那天，上面那條就從零實例變成真的在防東西。
    ///
    /// 五族的 `validate()` 裡所有 error 級檢查**都是 key 合法性檢查**，而 load 對
    /// 每一族都做同樣的檢查並**quarantine 整個檔**——於是那些 error 分支對載入後的
    /// 記錄結構上不可達。實測兩例（其餘三族同型，由本測試逐一驗）：
    ///
    ///     entry      citekey: BAD_KEY  → quarantined「citekey「BAD_KEY」不符合 …」
    ///     divergence 候選 key BAD_KEY  → quarantined「候選 key「BAD_KEY」不符合 …」
    ///
    /// **這更正了 #416 的一句敘述**：我當時寫「落差裡有一條是 **error** 級（citekey
    /// 不符 pattern），而 MCP／App 的使用者拿不到它」。前半為假——那條 error 對載入後
    /// 的 entry 到不了，quarantine 才是它實際走的路，而 quarantine **本來就在
    /// `StoreHealth` 裡、doctor 也渲染**。真正的落差是 warning 一族，不是 error。
    func testNoPerRecordErrorIsReachableFromALoadedStore() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("akashic-reach-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = LibraryStore(root: root)
        try store.ensureLayout()

        // 每一族各放一筆「合法寫入後、文字層改壞 key」的記錄。
        func corrupt(_ url: URL, _ from: String) throws {
            try String(contentsOf: url, encoding: .utf8)
                .replacingOccurrences(of: from, with: "BAD_KEY")
                .write(to: url, atomically: true, encoding: .utf8)
        }
        try corrupt(store.writeEntry(Entry(id: UUID(), citekey: "placeholderone",
                                           type: .book, title: "T")), "placeholderone")
        try corrupt(store.writePerson(Person(key: "placeholdertwo")), "placeholdertwo")
        let divID = UUID()
        try store.writeDivergence(
            Divergence(id: divID, question: "同一人？",
                       candidates: [DivergenceCandidate(key: "placeholderthree", shape: .person),
                                    DivergenceCandidate(key: "placeholderfour", shape: .person)]))
        try corrupt(store.entityURL(id: divID), "placeholderthree")

        let load = try store.load()
        XCTAssertEqual(load.quarantined.count, 3,
                       "三筆都該在 load 就被擋下：\(load.quarantined.map(\.reason))")
        let errs = store.health(from: load).perRecordIssues
            .filter { $0.issue.severity == .error }
        XCTAssertTrue(errs.isEmpty,
                      "若這裡開始有 error，`errorsFirst` 就不再是零實例守衛——"
                      + "請更新 `zero-instance-guards` 第 8 列與上面那段說明：\(errs)")
    }

    /// **要帶 severity 與是哪一筆**——只給訊息的話，消費端無法分辨 error 與 warning，
    /// 也無法指出哪一筆記錄。CLI 面兩者都有，MCP 面就不能丟（#138 verify F3 的既有立場）。
    func testPerRecordIssuesCarrySeverityAndOwner() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("akashic-perrec-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = LibraryStore(root: root)
        try store.ensureLayout()
        var e = Entry(id: UUID(), citekey: "x2025", type: .conferenceSession, title: "")
        e.fields["editor"] = "Someone"
        try store.writeEntry(e)
        let health = store.health(from: try store.load())
        let mine = health.perRecordIssues.filter { $0.owner == "x2025" }
        XCTAssertFalse(mine.isEmpty, "空 title ＋ 載體型別帶 editor 應各出一則")
        XCTAssertTrue(mine.contains { $0.issue.message.contains("title 為空") }, "\(mine)")
        XCTAssertTrue(mine.contains { $0.issue.message.contains("booktitle 載體列舉") }, "\(mine)")
        XCTAssertTrue(mine.allSatisfy { $0.issue.severity == .warning },
                      "本例兩則都是 warning——severity 必須逐則攜帶而非丟掉")
    }
}
