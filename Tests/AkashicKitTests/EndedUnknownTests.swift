import XCTest
@testable import AkashicCore
@testable import AkashicExport
@testable import AkashicStoreIO

/// #63：「已結束，但結束日期未知」的一等表達。
///
/// 具體案例：43 位退休 PI 只有「已退休」的事實、沒有退休年份——`end: nil` 語意是
/// 進行中（整批被算成現職）、捏造年份是偽造資料、塞 `note` 不參與計算。
/// 依 issue 選項 3 的欄位形狀（`ended: true` + `end` 缺席）；相容性層級後經
/// 自查更正為 **non-additive（format 6）**——段內鍵是 strict，詳見 StoreVersion doc。
final class EndedUnknownTests: XCTestCase {

    // MARK: - DateRange 語意

    func testEndedUnknownRangeIsNotOpen() {
        let r = DateRange(start: "2003", endedUnknown: true)
        XCTAssertFalse(r.isOpen, "已結束（時點未知）不是進行中——isOpen 是 current 推導的根")
    }

    func testPlainOpenRangeSemanticsUnchanged() {
        XCTAssertTrue(DateRange(start: "2003").isOpen, "既有語意不變：end 缺席且未標 ended ＝ 進行中")
        XCTAssertFalse(DateRange(start: "2003", end: "2010").isOpen)
    }

    func testCurrentExcludesEndedUnknownSegments() {
        let t = Timeline([
            TemporalValue(value: "ISS", range: DateRange(start: "1990", endedUnknown: true)),
        ])
        XCTAssertNil(t.current, "退休（時點未知）的段不是 current——43 位退休 PI 不得被算成現職")
    }

    func testCurrentStillPicksTrulyOpenSegment() {
        let t = Timeline([
            TemporalValue(value: "舊單位", range: DateRange(start: "1990", endedUnknown: true)),
            TemporalValue(value: "現單位", range: DateRange(start: "2010")),
        ])
        XCTAssertEqual(t.current?.value, "現單位")
    }

    /// overlaps 的誠實選擇：無端點無從排除重疊——保守視為開放（多報不漏報）。
    func testEndedUnknownOverlapsConservatively() {
        let unknown = DateRange(start: "1990", endedUnknown: true)
        let later = DateRange(start: "2020")
        XCTAssertTrue(unknown.overlaps(later),
                      "不知何時結束＝無從排除重疊——保守判重疊，交由人工裁決")
    }

    // MARK: - YAML round-trip

    func testPersonProfileEndedRoundTrips() throws {
        var p = Person(key: "wang-old", names: ["Wang Old"])
        p.profile.affiliations = TimelineOf([
            TemporalValue(value: .literal("中研院統計所"),
                          range: DateRange(start: "1985", endedUnknown: true),
                          source: "所方網頁退休名單"),
        ])
        let yaml = try PersonYAML.encode(p)
        XCTAssertTrue(yaml.contains("ended: true"), "已結束（時點未知）必須落檔：\n\(yaml)")
        let back = try PersonYAML.decode(yaml)
        XCTAssertEqual(back.profile.affiliations.entries.first?.range.endedUnknown, true)
        XCTAssertNil(back.profile.affiliations.current, "round-trip 後仍不是 current")
    }

    func testEndedAbsentIsNotEmitted() throws {
        var p = Person(key: "wang-now", names: ["Wang Now"])
        p.profile.ranks = Timeline([
            TemporalValue(value: "研究員", range: DateRange(start: "2010")),
        ])
        let yaml = try PersonYAML.encode(p)
        XCTAssertFalse(yaml.contains("ended"), "預設值不落檔——diff 噪音與 schema 汙染")
    }

    /// `end` 有值時 `ended: true` 是矛盾——end 本身就是「已結束於此」，兩者並存
    /// 無法判斷哪個是真話。拒絕，不猜。
    func testEndWithEndedTrueIsRejected() throws {
        let yaml = """
            id: 11111111-1111-4111-8111-111111111111
            key: bad-person
            names: {variant: [Bad]}
            profile:
              ranks:
              - value: 研究員
                start: "2010"
                end: "2020"
                ended: true
            """
        XCTAssertThrowsError(try PersonYAML.decode(yaml)) { error in
            let m = (error as? LocalizedError)?.errorDescription ?? "\(error)"
            XCTAssertTrue(m.contains("矛盾"),
                          "必須是矛盾偵測在拒絕（不是 unknown-key 或其他 strict 拒絕順便擋下）：\(m)")
        }
    }

    func testEndedFalseIsTolerated() throws {
        // `ended: false` 冗餘但無矛盾（等同缺席）——寬容讀入、不寫出
        let yaml = """
            id: 11111111-1111-4111-8111-111111111111
            key: ok-person
            names: {variant: [Ok]}
            profile:
              ranks:
              - value: 研究員
                start: "2010"
                ended: false
            """
        let p = try PersonYAML.decode(yaml)
        XCTAssertEqual(p.profile.ranks.entries.first?.range.endedUnknown, false)
        XCTAssertNotNil(p.profile.ranks.current, "ended: false ＝ 照常進行中")
    }

    /// boolean 慣例（#131 verify F4——本 store 格式的第一個 boolean，慣例在此建立）：
    /// 只收裸寫 true/false；引號版與 YAML 1.1 變體一律拒絕（fail-closed）。
    func testEndedBooleanFormsAreStrict() throws {
        func person(_ ended: String) -> String {
            "id: 11111111-1111-4111-8111-111111111111\nkey: b\nnames: {variant: [B]}\nprofile:\n  ranks:\n  - value: r\n    start: \"2010\"\n    ended: \(ended)\n"
        }
        XCTAssertNoThrow(try PersonYAML.decode(person("true")))
        XCTAssertNoThrow(try PersonYAML.decode(person("false")))
        for bad in ["\"true\"", "True", "TRUE", "yes", "on", "1"] {
            XCTAssertThrowsError(try PersonYAML.decode(person(bad)),
                                 "\(bad) 不是裸寫的 true/false——第一個 boolean 的慣例是 fail-closed")
        }
    }

    /// #131 verify F2：affiliations 段的 start/end null 面視為缺席（format 6 順帶
    /// 對齊——先前 ranks 已如此、affiliations 卻存成字串 "null"）。文件化 + 釘住。
    func testAffiliationStartNullFaceIsAbsence() throws {
        let yaml = """
            id: 11111111-1111-4111-8111-111111111111
            key: n-person
            names: {variant: [N]}
            profile:
              affiliations:
              - value: {literal: 某機構}
                start: null
            """
        let p = try PersonYAML.decode(yaml)
        XCTAssertNil(p.profile.affiliations.entries.first?.range.start,
                     "null 面＝缺席，不是字串 \"null\"")
    }

    /// #131 verify Codex-H1：DateRange 是公開可寫 struct——model 層可構造
    /// end+endedUnknown 的矛盾 instance；encoder 曾照寫兩鍵、同版本 decoder 再拒絕
    /// （decode(encode(m)) 不安全、canary 只報難懂的自檢失敗）。encoder 前置拒絕。
    func testEncoderRejectsContradictoryRange() {
        var p = Person(key: "c-person", names: ["C"])
        p.profile.ranks = Timeline([
            TemporalValue(value: "研究員",
                          range: DateRange(start: "2010", end: "2020", endedUnknown: true)),
        ])
        XCTAssertThrowsError(try PersonYAML.encode(p)) { error in
            let m = (error as? LocalizedError)?.errorDescription ?? "\(error)"
            XCTAssertTrue(m.contains("矛盾"), "encoder 要指明矛盾，不是 canary 自檢失敗：\(m)")
        }
    }

    /// #131 verify Codex-H2：supported=6 只是讀取上限——format 5 store 的 marker
    /// 不會自己變 6。在 format 5 store 寫含 ended 的 person，v5 binary 會 marker 5
    /// 照讀 → strict-reject → 整檔 quarantine（refuse-if-newer 沒 fire）。寫入端拒絕。
    func testWritePersonWithEndedRefusedOnFormat5Store() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("akashic-gate-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = LibraryStore(root: root, key: nil, environment: [:])
        try store.ensureLayout()
        try StoreVersion.write(root: root, format: 5)   // 模擬既有 v5 store

        var p = Person(key: "gate-person", names: ["G"])
        p.profile.ranks = Timeline([
            TemporalValue(value: "研究員", range: DateRange(start: "1990", endedUnknown: true)),
        ])
        XCTAssertThrowsError(try store.writePerson(p)) { error in
            let m = (error as? LocalizedError)?.errorDescription ?? "\(error)"
            XCTAssertTrue(m.contains("format") && m.contains("6"),
                          "訊息要指路（需要 format 6、如何升級）：\(m)")
        }
        // marker 升 6 之後照常寫入
        try StoreVersion.write(root: root, format: 6)
        XCTAssertNoThrow(try store.writePerson(p))
        // 無 ended 的 person 在 v5 store 照常寫（gate 只擋 v6-only 語法）
        try StoreVersion.write(root: root, format: 5)
        XCTAssertNoThrow(try store.writePerson(Person(key: "plain-p", names: ["P"])))
    }

    /// P0-4：純字串 timeline（rank）的 ended round-trip——先前只測了 affiliations。
    /// P1-6：ended: false 的 model encode 不寫出 key。
    func testStringTimelineEndedRoundTripsAndFalseIsDropped() throws {
        var p = Person(key: "r-person", names: ["R"])
        p.profile.ranks = Timeline([
            TemporalValue(value: "研究員", range: DateRange(start: "1990", endedUnknown: true)),
            TemporalValue(value: "副研究員", range: DateRange(start: "1980", end: "1990")),
        ])
        let yaml = try PersonYAML.encode(p)
        XCTAssertTrue(yaml.contains("ended: true"))
        XCTAssertEqual(yaml.components(separatedBy: "ended").count - 1, 1,
                       "endedUnknown=false 的段不得寫出 ended key")
        let back = try PersonYAML.decode(yaml)
        XCTAssertEqual(back.profile.ranks, p.profile.ranks)
    }

    // MARK: - format bump（#63 是 non-additive）

    /// 「看似 additive 其實不是」：tolerant-preserve 的開放層只涵蓋記錄頂層與
    /// akashic namespace——時間軸**段內**的鍵是 strict（rejectUnknownKeys），
    /// 舊 binary 讀到 `ended:` 是**整檔 quarantine**（人檔消失），不是保留。
    /// refuse-if-newer 的「請升級」遠比 per-file quarantine 誠實 → MUST bump。
    func testEndedRequiresFormatBump() {
        XCTAssertGreaterThanOrEqual(StoreVersion.supported, 6,
                                    "#63 的 ended 是段內新鍵——舊 binary quarantine 整檔，non-additive")
    }

    // MARK: - status 推導（#63 的實際案例）

    func testRetiredPIWithUnknownEndIsExportedAsRetired() throws {
        var p = Person(key: "retired-pi", names: ["Retired PI"])
        p.profile.affiliations = TimelineOf([
            TemporalValue(value: .literal("中研院統計所"),
                          range: DateRange(start: "1985", endedUnknown: true)),
        ])
        let tables = RelationalExport.tables(entries: [], people: [p])
        let statusIdx = try XCTUnwrap(tables.researcher.columns.firstIndex(of: "status"))
        XCTAssertEqual(tables.researcher.rows.first?[statusIdx], "retired",
                       "退休（時點未知）→ status=retired——#63 的 43 位 PI 場景")

        // #131 verify F1（HIGH）：researcher_timeline 曾丟掉 endedUnknown——
        // status=retired 而 timeline 行 valid_end NULL＝進行中，同一份輸出自相矛盾，
        // SQL 下游按「end IS NULL」慣例把退休 PI 拉回現職（issue 的病搬進 DuckDB 重現）。
        let tl = tables.researcherTimeline
        let unknownIdx = try XCTUnwrap(tl.columns.firstIndex(of: "valid_end_unknown"))
        let endIdx = try XCTUnwrap(tl.columns.firstIndex(of: "valid_end"))
        let row = try XCTUnwrap(tl.rows.first)
        XCTAssertEqual(row[unknownIdx], "true", "timeline 行必須攜帶「已結束、時點未知」")
        XCTAssertNil(row[endIdx])
        XCTAssertTrue(RelationalExport.duckDBScript().contains("valid_end_unknown"),
                      "load.sql 的 schema 要有這欄——匯出是全刪重建的衍生物，掉了就永遠消失")
    }
}
