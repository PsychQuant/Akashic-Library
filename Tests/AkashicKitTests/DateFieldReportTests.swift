import XCTest
@testable import AkashicCore
@testable import AkashicStoreIO

/// #85：日期樣欄位的裁決 (c)——不驗證但報告。
///
/// 值域（ISO 8601 前綴三形狀）是文件契約；解碼照常收下（fail-closed 的內容驗證
/// 會讓一筆可疑的**歷史資料**變成整個 store 載入不了——#131 實測 quarantine 的
/// 同型災難）；`doctor` 把不合值域的列出來——回報而非拒絕，判斷屬使用端，與
/// `overlappingPairs()` / `recordsWithoutAuthorizedName()` 同一形狀。
final class DateFieldReportTests: XCTestCase {

    // MARK: - ISO8601Prefix.isValid 矩陣

    func testValidShapes() {
        for s in ["2003", "2003-01", "2003-12", "2003-01-15", "2003-12-31", "0912"] {
            XCTAssertTrue(ISO8601Prefix.isValid(s), s)
        }
    }

    func testInvalidShapes() {
        for s in ["2004-13-99",      // 13 月、99 日
                  "2004-00",         // 0 月
                  "2004-13",         // 13 月
                  "2004-01-00",      // 0 日
                  "2004-01-32",      // 32 日
                  "not-a-date", "tomorrow",
                  "民國九十三年",      // 民國年——真實情況，值域外（報告，不擋）
                  "2004-1",          // 月未補零
                  "2004-01-15T00:00", // 帶時間不是前綴
                  "20040115", ""] {
            XCTAssertFalse(ISO8601Prefix.isValid(s), s)
        }
    }

    /// 誠實邊界：只驗月 01–12、日 01–31 的值域，**不驗日曆**（2 月 30 日通過）。
    /// 日曆級驗證需要曆法假設（格里曆起點、閏年）——對歷史資料那是另一個裁決。
    func testCalendarLevelIsOutOfScope() {
        XCTAssertTrue(ISO8601Prefix.isValid("2004-02-30"))
    }

    // MARK: - 掃描 helper

    private func makeLoad(people: [Person] = [], organizations: [Organization] = []) -> LibraryLoad {
        LibraryLoad(people: people, organizations: organizations)
    }

    /// **11 個掃描點每個都種一個獨特壞值**（#144 verify F4：曾只種 6 點，
    /// administrative/appointments/fields/contacts/parents 五點可以整段拔掉而
    /// 完整 suite 全綠——計數斷言對它們全盲）。
    func testAnomaliesFindsBadValuesAcrossAllElevenScanPoints() {
        var p = Person(key: "bad-person")
        p.died = "2004-13-99"
        p.profile.affiliations = TimelineOf([
            TemporalValue(value: OrgRef.literal("X"),
                          range: DateRange(start: "not-a-date", end: "2010"))])
        p.profile.ranks = Timeline([
            TemporalValue(value: "研究員", range: DateRange(start: "2003", end: "tomorrow"))])
        p.profile.administrative = Timeline([
            TemporalValue(value: "所長", range: DateRange(start: "bad-admin"))])
        p.profile.appointments = Timeline([
            TemporalValue(value: "全職", range: DateRange(start: "bad-appt"))])
        p.profile.fields = Timeline([
            TemporalValue(value: "統計", range: DateRange(start: "bad-field"))])
        p.profile.contacts = ["email": Timeline([
            TemporalValue(value: "x@y", range: DateRange(start: "bad-contact"))])]
        var org = Organization(key: "bad-org")
        org.founded = "民國九十三年"
        org.dissolved = "2004-1"
        org.names = TimelineOf([
            TemporalValue(value: "舊名", range: DateRange(start: "2004-00"))])
        org.parents = TimelineOf([
            TemporalValue(value: OrgRef.literal("上級"),
                          range: DateRange(start: "bad-parent"))])

        let found = makeLoad(people: [p], organizations: [org]).dateFieldAnomalies()
        let fields = found.map(\.field)
        for expected in ["died", "affiliations", "ranks", "administrative",
                         "appointments", "fields", "contacts.email",
                         "founded", "dissolved", "names", "parents"] {
            XCTAssertTrue(fields.contains { $0.contains(expected) },
                          "掃描點 \(expected) 沒接上：\(found)")
        }
        XCTAssertEqual(found.count, 11,
            "11 個掃描點各一筆（同段的合法 start/end 不連帶）：\(found)")
        // 報告帶原值——修復需要知道原本寫了什麼
        XCTAssertTrue(found.contains { $0.value == "2004-13-99" })
    }

    /// `endedUnknown` 段的 `end` 缺席是**合法**（#63），缺席的 start 也是——
    /// 報告只看「在場但不合值域」的值，不把缺席當異常（#131 F1 的同型教訓）。
    func testAbsentDatesAndEndedUnknownAreNotAnomalies() {
        var p = Person(key: "ok-person")
        p.profile.affiliations = TimelineOf([
            TemporalValue(value: OrgRef.literal("X"),
                          range: DateRange(start: nil, endedUnknown: true)),
            TemporalValue(value: OrgRef.literal("Y"), range: DateRange())])
        XCTAssertTrue(makeLoad(people: [p]).dateFieldAnomalies().isEmpty)
    }

    func testCleanStoreReportsNothing() {
        var p = Person(key: "clean")
        p.died = "2004-11-18"
        p.profile.ranks = Timeline([
            TemporalValue(value: "研究員", range: DateRange(start: "2003", end: "2010-06"))])
        XCTAssertTrue(makeLoad(people: [p]).dateFieldAnomalies().isEmpty)
    }

    /// 防腐（同 `fieldsLostByMerging` 的反射紀律）：PersonProfile 新增 timeline
    /// 維度時，這個計數會變、提醒把新維度接進掃描——手寫清單不靠記憶維護。
    func testScanCoversAllProfileTimelineDimensions() {
        let mirror = Mirror(reflecting: PersonProfile())
        let timelineCount = mirror.children.filter {
            "\(type(of: $0.value))".hasPrefix("TimelineOf")
        }.count
        // affiliations + ranks + administrative + appointments + fields = 5
        // （contacts 是 [String: Timeline]，另計）
        XCTAssertEqual(timelineCount, 5,
            "PersonProfile 的 timeline 維度數變了——確認 dateFieldAnomalies() 是否已涵蓋新維度，然後更新此數")
    }
}
