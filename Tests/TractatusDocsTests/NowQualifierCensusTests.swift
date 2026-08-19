import XCTest

/// `docs/tractatus/README.md` 裡「目前」那一節的**實測數字**必須與 corpus 一致（#321）。
///
/// ## 為什麼需要這條
///
/// 那一節的價值在於它**把「沒有機制在追蹤」從隱性變成顯性**，而它是靠四個實測數字支撐的
/// （353 樣板否定／30 論述式否定／3 其他 status／356 合計）。
///
/// **寫死的數字會安靜過期。** 這個 repo 已經記過同一形狀多次：
///
/// - `entity-backlink-completeness` 的封閉列舉**兩次**宣稱窮盡、兩次是錯的
/// - 同檔的引言曾寫死「8 條」，表格改成 11 條時沒跟著改 —— 同一份規則裡兩個計數
/// - `BibExport` 手維護的 `apa7CheckedTypes` 鏡像，doc 自己寫著「會隨 dependency 演進而
///   過期」，而它就是那樣過期的（#353）
///
/// 一節「用數字證明我們看過了」的文字，若數字停在過去，它證明的就變成相反的事。
///
/// ## 這條守的是**一致性**不是數字本身
///
/// corpus 增刪 claim 是正常的。變紅時該做的是**更新 README 的數字並重讀那一節的判準**
/// （新增的 claim 帶不帶「目前」是否正確），而不是改這條測試。
final class NowQualifierCensusTests: XCTestCase {

    private func repoRoot() throws -> URL {
        var dir = URL(fileURLWithPath: #filePath)
        for _ in 0..<10 {
            dir.deleteLastPathComponent()
            if FileManager.default.fileExists(
                atPath: dir.appendingPathComponent("Package.swift").path) { return dir }
        }
        throw XCTSkip("找不到 repo root")
    }

    /// corpus 的實測普查：`(樣板否定, 論述式否定, 其他 status 帶「目前」)`。
    ///
    /// 判準與 README 那一節一致：`not_applicable` 且 claim 含「目前」＝樣板否定
    /// （斷言現有能力不足以證成，能力增長可能改變）；不含＝論述式否定（斷言概念上的
    /// 不同一，**不會**隨能力增長而改變，加「目前」反而是錯的）。
    private func census() throws -> (template: Int, discursive: Int, otherWithNow: Int) {
        let dir = try repoRoot().appendingPathComponent("docs/tractatus/corpus")
        let files = try FileManager.default.contentsOfDirectory(at: dir,
                                                               includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "yaml" }
        XCTAssertFalse(files.isEmpty, "corpus 目錄是空的")

        var template = 0, discursive = 0, otherWithNow = 0
        for file in files {
            let text = try String(contentsOf: file, encoding: .utf8)
            // 逐個 relation：`status: X` 之後到下一個條目之間的文字即該條的 claim 區。
            let pattern = #"status: (\w+)\n(.*?)(?=\n\s*- |\n\w|\Z)"#
            let re = try NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators])
            let ns = text as NSString
            for m in re.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
                let status = ns.substring(with: m.range(at: 1))
                let body = ns.substring(with: m.range(at: 2))
                // **只看 `claim` 欄位，不看整個 body。** README 那一節說的是
                // 「356 條 **claim** 帶『Akashic 目前不…』」，而同一個 relation 的
                // `rationale` 也可能出現「目前」——那是論證的措辭，不是 claim 的時間限定。
                //
                // 第一版數整個 body，得到 7 而非 3（多算了 4 條 rationale 裡的「目前」）。
                // 守衛抓到的是**它自己的**不精確：判準寫在 README 裡是「claim」，
                // 而實作放寬成「body」，於是兩邊量的不是同一件事。
                let claim = Self.claimText(in: body)
                let hasNow = claim.contains("目前")
                if status == "not_applicable" {
                    hasNow ? (template += 1) : (discursive += 1)
                } else if hasNow {
                    otherWithNow += 1
                }
            }
        }
        return (template, discursive, otherWithNow)
    }

    /// 從一個 relation 的 body 取出 `claim` 欄位的文字。
    ///
    /// YAML 的 block scalar（`claim: |` / `claim: >-`）與單行形式都要吃。取到下一個
    /// 同層鍵為止。
    private static func claimText(in body: String) -> String {
        guard let r = body.range(of: #"claim[a-z_]*:\s*[|>]?-?\s*"#,
                                 options: .regularExpression) else { return "" }
        let rest = String(body[r.upperBound...])
        // 下一個同層鍵（行首若干空白 + 識別字 + 冒號）即結束
        if let end = rest.range(of: #"\n\s{0,8}[a-z_]+:"#, options: .regularExpression) {
            return String(rest[..<end.lowerBound])
        }
        return rest
    }

    /// README 那一節寫死的四個數字必須與 corpus 一致。
    ///
    /// 數字寫在測試裡是刻意的（同本 repo 其他「一格不多一格不少」的守衛）：它讓
    /// **兩邊必須一起改**，而不是讓其中一邊偷偷漂走。
    func testReadmeCensusMatchesCorpus() throws {
        let c = try census()
        XCTAssertEqual(c.template, 353,
                       "樣板否定（not_applicable 且帶「目前」）的條數變了。"
                       + "請更新 docs/tractatus/README.md 的表格，"
                       + "並重讀那一節的判準確認新增的 claim 帶不帶「目前」是對的")
        XCTAssertEqual(c.discursive, 30,
                       "論述式否定（not_applicable 但不帶「目前」）的條數變了。"
                       + "那 30 條斷言的是**概念上的不同一**，不會隨能力增長而改變"
                       + "——新增時要確認它真的屬於這一類，不是漏寫「目前」")
        XCTAssertEqual(c.otherWithNow, 3,
                       "其他 status 帶「目前」的條數變了。那 3 條的「目前」是**句子的"
                       + "自然語意**（「所有目前 entity」），不是時間限定修辭")
        XCTAssertEqual(c.template + c.otherWithNow, 356, "帶「目前」的合計變了")
    }

    // MARK: - #267／#302 的裁決存續守衛

    /// #267 的裁決節必須**還在**，而且仍保留三個承重句。
    ///
    /// 那一節裁定「具名的第二讀者」為承載機制，並明寫另兩個候選為什麼不是。
    /// 三個句子各自不可省：
    ///
    /// - 「都只降低機率、都不保證」——沒有它，本節自己會變成錯誤安全感的來源
    /// - 「不能靠作者自己再讀一遍」——這是否決 (a) 的全部理由（跨模型盲驗的實測）
    /// - 「沒有那次量測就不該動手」——這是否決 (c) 的重啟條件，刪掉就變成永久否決
    func testReadmeKeepsThePhilosophicalConsistencyRuling() throws {
        let readme = try String(
            contentsOf: try repoRoot().appendingPathComponent("docs/tractatus/README.md"),
            encoding: .utf8)
        XCTAssertTrue(readme.contains("哲學一致性由誰守"), "#267 的裁決節標題不見了")
        XCTAssertTrue(readme.contains("三個候選都只降低機率、都不保證"),
                      "「不保證」這句必須留著——沒有它，本節會被讀成「已經有機制了」")
        XCTAssertTrue(readme.contains("不能靠作者自己再讀一遍"),
                      "否決作者自審 checklist 的理由必須留著，否則下一個人會把它加回來"
                      + "當成承重機制")
        XCTAssertTrue(readme.contains("沒有那個數字就"),
                      "機械化的重啟條件（先量假陽性率）必須留著——刪掉會讓 (c) 從"
                      + "「條件未滿足」變成「已永久否決」")
    }

    /// #302 的裁決：`analogy_only` 記在 5.632，且規則檔只加「另見」、**不是第七條理由**。
    ///
    /// 這條守的是**劃界措辭本身**。`entity-backlink-completeness` 的六條理由是封閉列舉；
    /// 一條哲學呼應若被讀成第七條，就是 #300 同案明文禁止的「升格為規範判準」。
    /// 而那個升格的發生方式很安靜：只要有人把「另見」那段的免責句刪掉，剩下的文字
    /// 讀起來就像第七條。
    func testAuthorshipOntologyStaysAnAnalogyNotASeventhReason() throws {
        let root = try repoRoot()
        let corpus = try String(
            contentsOf: root.appendingPathComponent("docs/tractatus/corpus/5.yaml"),
            encoding: .utf8)
        XCTAssertTrue(corpus.contains("持有著作清單的實體"),
                      "5.632 的 analogy_only relation 不見了（#302 的產出）")
        XCTAssertTrue(corpus.contains("呼應與證成是兩件事"),
                      "該 relation 的劃界句必須留著——它是 analogy_only 與 spec 的分界")

        let rule = try String(
            contentsOf: root.appendingPathComponent(
                ".claude/rules/entity-backlink-completeness.md"),
            encoding: .utf8)
        XCTAssertTrue(rule.contains("這不是第七條理由"),
                      "「另見」指標的免責句不見了——沒有它，那段會被讀成第七條理由，"
                      + "而那正是 #300 裁定不得發生的升格")
    }

    /// README 那一節必須**還在**，而且仍明說「沒有機制在追蹤」。
    ///
    /// 這一節是本 issue 的全部產出：它把一個沉默的事實變成記錄下來的事實。若有人「精簡」
    /// 掉那句話，措辭的承諾感會回來而機制仍然不在——正是 #321 開立時的狀態。
    func testReadmeStillSaysThereIsNoTrackingMechanism() throws {
        let readme = try String(
            contentsOf: try repoRoot().appendingPathComponent("docs/tractatus/README.md"),
            encoding: .utf8)
        XCTAssertTrue(readme.contains("「目前」是語氣，不是承諾"),
                      "那一節的標題不見了")
        XCTAssertTrue(readme.contains("沒有任何機制在世界改變時重新檢視它們"),
                      "「沒有機制在追蹤」這句必須留著——它是本節存在的理由")
        XCTAssertTrue(readme.contains("不要因為鄰居帶了就帶"),
                      "新增 claim 時的判準必須留著，否則下一個人只會照抄鄰居")
    }
}
