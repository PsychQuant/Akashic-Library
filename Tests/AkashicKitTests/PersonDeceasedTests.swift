import XCTest
import Foundation
@testable import AkashicCore
@testable import AkashicExport
@testable import AkashicStoreIO

/// 人的終結（#67）。
///
/// 缺陷重現：`Organization` 有 `founded` / `dissolved`，`Person` **沒有任何生平欄位**。
/// 於是「隸屬在 2004-11 結束」與「2004-11 在職過世」在 store 裡是同一件事——
/// 魏慶榮的 `end` 記的其實是死亡（Statistica Sinica 16(3) 紀念專輯載明 2004-11-18），
/// 而資料裡看不出來。
///
/// **`died` 缺席的語意是右設限（censoring），不是「在世」。** 死亡是必然事件，所以缺席
/// 永遠不是「不適用」，只是「尚未觀察到」。因此本組測試從不斷言「沒有 `died` ＝ 活著」。
final class PersonDeceasedTests: XCTestCase {
    var root: URL!
    var store: LibraryStore!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("akashic-deceased-\(UUID().uuidString)")
        store = LibraryStore(root: root)
        try store.ensureLayout()
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    // MARK: - (a) 記錄得下來，且讀得回來

    func testARecordedDeathSurvivesAStoreRoundTrip() throws {
        _ = try store.writePerson(Person(key: "ching-zong-wei",
                                         names: ["魏慶榮", "Ching-Zong Wei"],
                                         authorized: ["魏慶榮", "Ching-Zong Wei"],
                                         died: "2004-11-18"))
        let load = try store.load()
        XCTAssertEqual(load.quarantined.count, 0, "\(load.quarantined)")
        XCTAssertEqual(load.people.first?.died, "2004-11-18")
    }

    // MARK: - (b) 精度就是區間寬度——不得被補齊

    /// `2004` 說的是「2004 年的某個時候」（區間設限）。補成 `2004-01-01` 等於斷言了一個
    /// 沒有任何來源說過的日子。
    func testEachAdmissiblePrecisionIsPreservedByteForByte() throws {
        for value in ["2004", "2004-11", "2004-11-18"] {
            let p = Person(key: "k", names: ["N"], authorized: ["N"], died: value)
            let back = try PersonYAML.decode(try PersonYAML.encode(p))
            XCTAssertEqual(back.died, value, "精度被改動：寫入 \(value)，讀回 \(back.died ?? "nil")")
        }
    }

    func testYearPrecisionIsNotCompletedIntoAFullDate() throws {
        let p = Person(key: "k", names: ["N"], authorized: ["N"], died: "2004")
        let back = try PersonYAML.decode(try PersonYAML.encode(p))
        XCTAssertEqual(back.died, "2004")
        XCTAssertNotEqual(back.died, "2004-01-01", "補上一個沒有來源說過的日")
    }

    // MARK: - 缺席不留痕跡

    /// 右設限不是一個「有內容的觀測」，所以檔案裡不該有它的位置。空字串或 `null`
    /// 佔位會讓「尚未觀察到」看起來像「觀察到了一個空值」。
    func testAnUnrecordedDeathWritesNoKeyAtAll() throws {
        let yaml = try PersonYAML.encode(Person(key: "k", names: ["N"], authorized: ["N"]))
        XCTAssertFalse(yaml.contains("died"), yaml)
    }

    // MARK: - 形狀錯誤要點名欄位

    func testANonScalarValueIsRejectedByFieldName() throws {
        let yaml = """
        person:
        id: \(DeterministicUUID.forPerson(key: "k").uuidString)
        key: k
        names:
          - N
        died:
          - 2004
        """
        XCTAssertThrowsError(try PersonYAML.decode(yaml)) { e in
            XCTAssertTrue("\(e)".contains("person.died"), "訊息要點名欄位：\(e)")
        }
    }

    // MARK: - known-keys 登記（回歸）

    /// `died` 若沒登記進 `knownPersonKeys`，它會**同時**被結構欄位讀走、又被
    /// tolerant-preserve 當成未知欄位保留——寫回時輸出兩次。編碼器的語意 canary 抓不到
    /// 這種情況（兩邊的 `died` 值相同），只有數鍵才看得見。
    func testTheFieldIsRegisteredSoItIsNotEmittedTwice() throws {
        let yaml = """
        person:
        id: \(DeterministicUUID.forPerson(key: "k").uuidString)
        key: k
        names:
          - N
        died: 2004-11-18
        """
        let out = try PersonYAML.encode(try PersonYAML.decode(yaml))
        let occurrences = out.components(separatedBy: "died:").count - 1
        XCTAssertEqual(occurrences, 1, "`died` 出現 \(occurrences) 次：\n\(out)")
    }

    // MARK: - 合併不得讓它靜默消失

    /// 被併者記著死亡而倖存者沒有——合併會讓那個事實蒸發。這類遺失沒有錯誤訊息、
    /// 只有資料變少，是最難事後發現的一種。
    func testMergingThatWouldDropADeathDateIsReportedAsALoss() {
        let losses = LibraryStore.fieldsLostByMerging(
            Person(key: "a", names: ["N"], died: "2004-11-18"),
            into: Person(key: "b", names: ["N"]))
        XCTAssertTrue(losses.contains { $0.contains("died") }, "\(losses)")
    }

    /// 兩個**不同**的死亡日期不是排版差異——它是對「這兩筆是不是同一個人」的反證，
    /// 或至少是必須有人裁決的來源衝突。
    func testTwoDifferentDeathDatesAreReportedRatherThanSilentlyPicked() {
        let losses = LibraryStore.fieldsLostByMerging(
            Person(key: "a", names: ["N"], died: "2004-11-18"),
            into: Person(key: "b", names: ["N"], died: "2005"))
        XCTAssertTrue(losses.contains { $0.contains("died") }, "\(losses)")
    }

    /// 同值不算遺失——否則每次合併都會被自己的資料擋住。
    func testAnIdenticalDeathDateIsNotALoss() {
        let losses = LibraryStore.fieldsLostByMerging(
            Person(key: "a", names: ["N"], died: "2004-11-18"),
            into: Person(key: "b", names: ["N"], died: "2004-11-18"))
        XCTAssertFalse(losses.contains { $0.contains("died") }, "\(losses)")
    }

    // MARK: - 死亡與隸屬正交（characterization）

    private func person(_ key: String, died: String? = nil,
                        affiliation: DateRange) -> Person {
        var profile = PersonProfile()
        profile.affiliations = TimelineOf([
            TemporalValue(value: OrgRef.literal("Institute of Statistical Science"),
                          range: affiliation)])
        return Person(key: key, names: [key], authorized: [key], died: died, profile: profile)
    }

    private func status(of p: Person) -> String? {
        let t = RelationalExport.tables(entries: [], people: [p])
        guard let i = t.researcher.columns.firstIndex(of: "status") else { return nil }
        return t.researcher.rows[0][i]
    }

    /// 在職過世的所長。隸屬**確實**結束了，所以 `retired` 是對的——它描述的是隸屬，
    /// 不是這個人。加上 `died` 不得改變這個推導。
    func testADeathDateDoesNotChangeTheAffiliationDerivedStatus() {
        XCTAssertEqual(status(of: person("ching-zong-wei", died: "2004-11-18",
                                         affiliation: DateRange(start: "1990-09", end: "2004-11"))),
                       "retired")
    }

    /// 沒有 `died`（右設限）＋ 開放的隸屬 → 仍是 `current`。缺席不參與推導。
    func testAnUnrecordedDeathLeavesAnOpenAffiliationCurrent() {
        XCTAssertEqual(status(of: person("living", affiliation: DateRange(start: "2010-01"))),
                       "current")
    }

    // MARK: - 矛盾要被看見，但不被代為裁決

    /// 已故卻仍有開放的隸屬段：兩者只有一個是對的，而**哪一個對無法自動判斷**——
    /// 可能是死於任內而漏記結束日，也可能是離職多年後過世、開放段只是資料缺漏。
    private func seedContradictionFixture() throws {
        _ = try store.writePerson(person("dead-but-open", died: "2004-11-18",
                                         affiliation: DateRange(start: "1990-09")))
        _ = try store.writePerson(person("properly-closed", died: "2004-11-18",
                                         affiliation: DateRange(start: "1990-09", end: "2004-11")))
        _ = try store.writePerson(person("living-and-open",
                                         affiliation: DateRange(start: "2010-01")))
    }

    func testADeceasedPersonRetainingAnOpenAffiliationIsReported() throws {
        try seedContradictionFixture()
        XCTAssertEqual(try store.load().recordsDeceasedWithOpenAffiliation(), ["dead-but-open"])
    }

    /// 報告不得修改記錄。自動把隸屬的結束日設成死亡日是**推論**，而推論可能錯。
    func testTheReportLeavesTheRecordByteIdentical() throws {
        try seedContradictionFixture()
        let file = try store.load().people.first { $0.key == "dead-but-open" }!.id
        let path = store.root.appendingPathComponent("entities/\(file.uuidString).yaml")
        let before = try Data(contentsOf: path)
        _ = try store.load().recordsDeceasedWithOpenAffiliation()
        XCTAssertEqual(try Data(contentsOf: path), before, "報告改動了記錄")
    }

    /// 這不是錯誤——不進 quarantine、不阻擋載入。
    func testTheContradictionDoesNotQuarantineOrBlockLoading() throws {
        try seedContradictionFixture()
        let load = try store.load()
        XCTAssertEqual(load.quarantined.count, 0, "\(load.quarantined)")
        XCTAssertEqual(load.people.count, 3)
    }

    // MARK: - 匯出層

    /// spec 的 Example 逐字：任期 1990-09 至 2004-11、`died` 為 2004-11-18 →
    /// status 欄 `retired`、died 欄 `2004-11-18`。
    func testTheExportCarriesTheDeathDateAlongsideTheAffiliationStatus() {
        let t = RelationalExport.tables(
            entries: [],
            people: [person("ching-zong-wei", died: "2004-11-18",
                            affiliation: DateRange(start: "1990-09", end: "2004-11"))])
        guard let s = t.researcher.columns.firstIndex(of: "status"),
              let d = t.researcher.columns.firstIndex(of: "died") else {
            return XCTFail("researcher 表缺欄位：\(t.researcher.columns)")
        }
        XCTAssertEqual(t.researcher.rows[0][s], "retired")
        XCTAssertEqual(t.researcher.rows[0][d], "2004-11-18")
    }

    /// 右設限在關聯層就是 NULL——不得填空字串或任何佔位。
    func testAnUnrecordedDeathExportsAsNull() {
        let t = RelationalExport.tables(
            entries: [], people: [person("living", affiliation: DateRange(start: "2010-01"))])
        guard let d = t.researcher.columns.firstIndex(of: "died") else {
            return XCTFail("researcher 表缺 died 欄：\(t.researcher.columns)")
        }
        XCTAssertNil(t.researcher.rows[0][d])
    }

    /// 衍生層的消費者看不到原始碼註解。「status 描述的是隸屬」必須寫在匯出的 schema 裡。
    func testTheExportedSchemaStatesWhatTheStatusColumnDescribes() {
        let sql = RelationalExport.duckDBScript()
        guard let statusLine = sql.components(separatedBy: "\n")
            .first(where: { $0.contains("status") && $0.contains("CHECK") }) else {
            return XCTFail("找不到 status 欄定義")
        }
        let idx = sql.range(of: statusLine)!.lowerBound
        let preamble = String(sql[sql.startIndex..<idx].suffix(400))
        XCTAssertTrue(preamble.contains("隸屬"),
                      "status 欄的說明沒講清楚它描述的是隸屬：\n\(preamble)")
    }

    /// 查得到卻沒有出口，等於沒查——`doctor` 必須實際呼叫它（防腐）。
    func testDoctorSurfacesTheContradiction() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let commands = try String(contentsOf: repoRoot.appendingPathComponent("Sources/akashic/Commands.swift"),
                                  encoding: .utf8)
        XCTAssertTrue(commands.contains("recordsDeceasedWithOpenAffiliation()"),
                      "報告函式存在但 doctor 沒呼叫它，矛盾永遠不會被任何人看到")
    }
}
