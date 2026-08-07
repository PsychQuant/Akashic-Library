import XCTest
import Foundation
@testable import AkashicCore
@testable import AkashicStoreIO

/// #100：「range 相同」有兩種成因（真的同時 vs 解析度不夠），系統要**說出來**。
///
/// 量測事實（issue）：175 組 range 相同的段**全部**是「完全沒有日期」；names／
/// fields／ranks 三個維度**從來沒有**日期。所以第一步不是「提高解析度」而是
/// 讓「這條 timeline 根本沒記過時間」變得可見——doctor 逐維度統計，對「從來
/// 沒有日期」的維度出 warning。判準自我描述、不需維護清單（#79 的形狀：讓看
/// 不見的變看見，處置留給人）。
final class DimensionDateCensusTests: XCTestCase {

    private func makeLoad(people: [Person] = [], organizations: [Organization] = []) -> LibraryLoad {
        LibraryLoad(people: people, organizations: organizations)
    }

    func testCensusCountsDatedAndUndatedPerDimension() {
        var p = Person(key: "a")
        p.profile.ranks = Timeline([
            TemporalValue(value: "研究員", range: DateRange(start: "2003")),
            TemporalValue(value: "所長", range: DateRange())])
        p.profile.fields = Timeline([
            TemporalValue(value: "統計", range: DateRange())])
        let census = makeLoad(people: [p]).timelineDateCensus()
        let ranks = census.first { $0.dimension == "person.ranks" }
        XCTAssertEqual(ranks?.dated, 1)
        XCTAssertEqual(ranks?.undated, 1)
        let fields = census.first { $0.dimension == "person.fields" }
        XCTAssertEqual(fields?.dated, 0)
        XCTAssertEqual(fields?.undated, 1)
    }

    /// 「從來沒有日期」的判準：dated == 0 且 undated > 0——空維度不報
    ///（沒有段就沒有「該不該有日期」的問題）。
    func testNeverDatedDimensionsAreIdentified() {
        var p = Person(key: "a")
        p.profile.fields = Timeline([
            TemporalValue(value: "統計", range: DateRange()),
            TemporalValue(value: "機率", range: DateRange())])
        p.profile.ranks = Timeline([
            TemporalValue(value: "研究員", range: DateRange(start: "2003"))])
        var org = Organization(key: "o")
        org.names = TimelineOf([TemporalValue(value: "舊名", range: DateRange())])
        let census = makeLoad(people: [p], organizations: [org]).timelineDateCensus()
        let never = census.filter { $0.dated == 0 && $0.undated > 0 }.map(\.dimension)
        XCTAssertEqual(never.sorted(), ["organization.names", "person.fields"],
                       "有日期的 ranks 與空維度都不在列：\(census)")
    }

    /// `endedUnknown`（#63）算**有時間資訊**：它是一等的知識狀態（「已結束」），
    /// 不是「沒記時間」。
    func testEndedUnknownCountsAsDated() {
        var p = Person(key: "a")
        p.profile.affiliations = TimelineOf([
            TemporalValue(value: OrgRef.literal("X"),
                          range: DateRange(endedUnknown: true))])
        let census = makeLoad(people: [p]).timelineDateCensus()
        XCTAssertEqual(census.first { $0.dimension == "person.affiliations" }?.dated, 1)
    }

    /// #150/#151 verify F1/F4：attested 段算 dated——「觀測到的時點」是有時間
    /// 資訊，census 不得當它沒日期而誤報「zero dates」。
    func testAttestedCountsAsDated() {
        var p = Person(key: "a")
        p.profile.affiliations = TimelineOf([
            TemporalValue(value: OrgRef.literal("X"),
                          range: DateRange(attested: ["2003", "2011"]))])
        let census = makeLoad(people: [p]).timelineDateCensus()
        let aff = census.first { $0.dimension == "person.affiliations" }
        XCTAssertEqual(aff?.dated, 1, "attested 段算有時間資訊")
        XCTAssertEqual(aff?.undated, 0)
        // 不得誤報「zero dates」
        let neverDated = census.filter { $0.dated == 0 && $0.undated > 0 }.map(\.dimension)
        XCTAssertFalse(neverDated.contains("person.affiliations"),
                       "全 attested 的維度不是「從來沒有日期」：\(neverDated)")
    }

    /// #150/#151 verify F2：organization 維度也進 census（走訪器涵蓋 org，
    /// 但先前無獨立斷言）。
    func testOrganizationDimensionsInCensus() {
        var org = Organization(key: "o")
        org.names = TimelineOf([TemporalValue(value: "舊名", range: DateRange())])
        org.parents = TimelineOf([
            TemporalValue(value: OrgRef.literal("上級"), range: DateRange(start: "1990"))])
        let census = makeLoad(organizations: [org]).timelineDateCensus()
        XCTAssertEqual(census.first { $0.dimension == "organization.names" }?.undated, 1)
        XCTAssertEqual(census.first { $0.dimension == "organization.parents" }?.dated, 1)
    }

    /// 防腐：census 與 dateFieldAnomalies 走同一個維度走訪器——新增維度時兩者
    /// 同步涵蓋（#144 R1 的教訓：兩份清單必有一份漏）。
    func testCensusAndAnomaliesShareDimensionCoverage() {
        var p = Person(key: "a")
        p.profile.administrative = Timeline([
            TemporalValue(value: "所長", range: DateRange(start: "bad-date"))])
        p.profile.appointments = Timeline([
            TemporalValue(value: "全職", range: DateRange())])
        p.profile.contacts = ["email": Timeline([
            TemporalValue(value: "x@y", range: DateRange())])]
        var org = Organization(key: "o")
        org.parents = TimelineOf([
            TemporalValue(value: OrgRef.literal("上級"), range: DateRange())])
        let load = makeLoad(people: [p], organizations: [org])
        let censusDims = Set(load.timelineDateCensus().map(\.dimension))
        for d in ["person.administrative", "person.appointments",
                  "person.contacts.email", "organization.parents"] {
            XCTAssertTrue(censusDims.contains(d), "census 漏了 \(d)：\(censusDims)")
        }
        // anomalies 也走同一走訪器（bad-date 被抓）
        XCTAssertTrue(load.dateFieldAnomalies().contains { $0.field.contains("administrative") })
    }
}
