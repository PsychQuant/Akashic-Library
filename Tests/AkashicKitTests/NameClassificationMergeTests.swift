import XCTest
import Foundation
@testable import AkashicCore
@testable import AkashicStoreIO

/// #564（Spectra change `name-classification-judgement`）：venue 合併分得出人判定過的 authorized——
/// spec `divergence-record`「A venue merge SHALL NOT demote an authorized name that carries a name-classification record」。
///
/// - 被併者帶名字分類記錄的 authorized 會被降級：preview 與實跑都拒絕（`wouldDemoteJudgedAuthorized`），零寫入。
/// - 機械值（沒有記錄）：照舊合併、提醒。
/// - 其餘名字分類記錄：名字在合併後的倖存者上分類與被併者相同才逐位元組搬（`referencesCarried`），不同就以 `wouldLoseFields` 拒絕。
final class NameClassificationMergeTests: XCTestCase {
    var root: URL!
    var store: LibraryStore!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("akashic-ncm-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("entities"), withIntermediateDirectories: true)
        try StoreVersion.write(root: root, format: StoreVersion.supported)
        GitFixture.initRepo(root)
        store = LibraryStore(root: root)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    private func record(_ field: String, _ name: String, _ action: NameClassificationRecord.Action, _ reason: String) -> ProvenanceReference {
        NameClassificationRecord.make(field: field, name: name, action: action, reason: reason, restsOn: [])
    }
    private func venue(_ key: String, names: [String], authorized: [String] = [], variant: [String] = [],
                       refs: [ProvenanceReference] = []) -> Venue {
        var v = Venue(key: key, type: .periodical, names: Timeline(names.map { TemporalValue(value: $0) }), authorized: authorized)
        v.variant = variant
        v.references = refs
        return v
    }
    @discardableResult
    private func seed(keeper: Venue, doomed: [Venue]) throws -> Divergence {
        try store.writeVenue(keeper)
        for d in doomed { try store.writeVenue(d) }
        let d = Divergence(id: UUID(), question: "同一本刊嗎",
                           candidates: ([keeper] + doomed).map { DivergenceCandidate(key: $0.key, shape: .venue) })
        try store.writeDivergence(d)
        GitFixture.commitAll(root, message: "seed")
        return d
    }
    private func message(_ e: Error) -> String { (e as? LocalizedError)?.errorDescription ?? "\(e)" }

    /// spec「A judged authorized name would be demoted」：preview 拒絕並說出名字與最後一筆記錄；實跑同樣拒絕、零寫入。
    func testJudgedAuthorizedDemotionIsRefusedInPreviewAndApply() throws {
        let keeper = venue("k", names: ["Keeper Journal"], authorized: ["Keeper Journal"])
        let doomed = venue("d", names: ["Doomed Journal"], authorized: ["Doomed Journal"],
                           refs: [record("authorized", "Doomed Journal", .designate, "官網刊頭")])
        let d = try seed(keeper: keeper, doomed: [doomed])
        XCTAssertThrowsError(try store.previewResolveDivergence(id: d.id, survivor: "k", overrideReason: nil)) { e in
            guard case DivergenceResolveError.wouldDemoteJudgedAuthorized = e else { return XCTFail("\(e)") }
            let m = message(e)
            XCTAssertTrue(m.contains("Doomed Journal") && m.contains("指定：官網刊頭"), m)
            XCTAssertTrue(m.contains("--unauthorize") && m.contains("--authorize") && m.contains("--judgement"), "出路要寫出來：\(m)")
        }
        XCTAssertThrowsError(try store.resolveDivergence(id: d.id, survivor: "k"))
        XCTAssertEqual(Set(try store.load().venues.map(\.key)), ["k", "d"], "零寫入")
    }

    /// 判準是「有任何記錄」：最後一筆是撤回卻仍在 authorized（只可能是手改）也拒。
    func testAnyRecordOnTheDemotedNameRefuses() throws {
        let keeper = venue("k", names: ["Keeper Journal"], authorized: ["Keeper Journal"])
        let doomed = venue("d", names: ["Doomed Journal"], authorized: ["Doomed Journal"],
                           refs: [record("authorized", "Doomed Journal", .withdraw, "手改")])
        let d = try seed(keeper: keeper, doomed: [doomed])
        XCTAssertThrowsError(try store.previewResolveDivergence(id: d.id, survivor: "k", overrideReason: nil)) { e in
            guard case DivergenceResolveError.wouldDemoteJudgedAuthorized = e else { return XCTFail("\(e)") }
        }
    }

    /// spec「A mechanical authorized name would be demoted」：沒有記錄的降級照舊合併、提醒。
    func testMechanicalDemotionStillMergesWithAWarning() throws {
        let keeper = venue("k", names: ["Keeper Journal"], authorized: ["Keeper Journal"])
        let doomed = venue("d", names: ["Doomed Journal"], authorized: ["Doomed Journal"])
        let d = try seed(keeper: keeper, doomed: [doomed])
        let report = try store.resolveDivergence(id: d.id, survivor: "k")
        XCTAssertFalse(report.hasFailures, report.failures.joined(separator: "\n"))
        XCTAssertTrue(report.warnings.contains { $0.contains("Doomed Journal") && $0.contains("authorized") }, "\(report.warnings)")
        XCTAssertEqual(Set(try store.load().venues.map(\.key)), ["k"])
    }

    /// 兩邊都指定同一個名字：沒有降級，記錄隨合併逐位元組搬到倖存者。
    func testRecordOnANameBothSidesAuthorizeIsCarried() throws {
        let rec = record("authorized", "Psychometrika", .designate, "官網刊頭")
        let keeper = venue("k", names: ["Psychometrika"], authorized: ["Psychometrika"])
        let doomed = venue("d", names: ["Psychometrika", "PSYCHOMETRIKA"], authorized: ["Psychometrika"], refs: [rec])
        let d = try seed(keeper: keeper, doomed: [doomed])
        let preview = try store.previewResolveDivergence(id: d.id, survivor: "k", overrideReason: nil)
        XCTAssertEqual(preview.referencesCarried.count, 1, "\(preview.referencesCarried)")
        let report = try store.resolveDivergence(id: d.id, survivor: "k")
        XCTAssertFalse(report.hasFailures, report.failures.joined(separator: "\n"))
        XCTAssertEqual(report.referencesCarried, preview.referencesCarried)
        let k = try XCTUnwrap(store.load().venues.first { $0.key == "k" })
        XCTAssertEqual(k.references.map(\.byteExactKey), [rec.byteExactKey])
    }

    /// spec「A withdrawal record whose classification agrees is carried」：被併者上已撤回（未標）的名字，合併後在倖存者上也是未標——搬。
    func testWithdrawalRecordWithAgreeingClassificationIsCarried() throws {
        let designated = record("authorized", "Old Title", .designate, "舊刊頭")
        let withdrawn = record("authorized", "Old Title", .withdraw, "刊名已改")
        let keeper = venue("k", names: ["Keeper Journal"], authorized: ["Keeper Journal"])
        let doomed = venue("d", names: ["Doomed Journal", "Old Title"], refs: [designated, withdrawn])
        let d = try seed(keeper: keeper, doomed: [doomed])
        let report = try store.resolveDivergence(id: d.id, survivor: "k")
        XCTAssertFalse(report.hasFailures, report.failures.joined(separator: "\n"))
        let k = try XCTUnwrap(store.load().venues.first { $0.key == "k" })
        XCTAssertEqual(k.references.map(\.byteExactKey), [designated.byteExactKey, withdrawn.byteExactKey], "逐位元組、順序不變")
        XCTAssertFalse(k.authorized.contains("Old Title"))
        XCTAssertTrue(k.names.entries.contains { $0.value == "Old Title" })
        XCTAssertNoThrow(try k.validateReferenceAttachment())
    }

    /// variant 的記錄：名字隨合併被標 variant（被併者原本就在 variant）——分類一致，搬。
    func testVariantRecordFollowsTheVariantIntoTheKeeper() throws {
        let rec = record("variant", "DOOMED J", .designate, "縮寫")
        let keeper = venue("k", names: ["Keeper Journal"], authorized: ["Keeper Journal"])
        let doomed = venue("d", names: ["Doomed Journal", "DOOMED J"], variant: ["DOOMED J"], refs: [rec])
        let d = try seed(keeper: keeper, doomed: [doomed])
        let report = try store.resolveDivergence(id: d.id, survivor: "k")
        XCTAssertFalse(report.hasFailures, report.failures.joined(separator: "\n"))
        let k = try XCTUnwrap(store.load().venues.first { $0.key == "k" })
        XCTAssertTrue(k.variant.contains("DOOMED J"))
        XCTAssertEqual(k.references.map(\.byteExactKey), [rec.byteExactKey])
    }

    /// 分類不一致：被併者說「它是異寫」，倖存者已有這個名字而且未標——搬過去會說一句倖存者的分類不承認的話，以 wouldLoseFields 拒絕，
    /// 訊息說出名字與兩邊的分類。
    func testDisagreeingClassificationRefusesTheMerge() throws {
        let rec = record("variant", "Shared Name", .designate, "被併者認為是異寫")
        let keeper = venue("k", names: ["Keeper Journal", "Shared Name"], authorized: ["Keeper Journal"])
        let doomed = venue("d", names: ["Doomed Journal", "Shared Name"], variant: ["Shared Name"], refs: [rec])
        let d = try seed(keeper: keeper, doomed: [doomed])
        XCTAssertThrowsError(try store.previewResolveDivergence(id: d.id, survivor: "k", overrideReason: nil)) { e in
            guard case DivergenceResolveError.wouldLoseFields = e else { return XCTFail("\(e)") }
            let m = message(e)
            XCTAssertTrue(m.contains("名字分類的判定記錄") && m.contains("Shared Name") && m.contains("variant") && m.contains("未標"), m)
            XCTAssertFalse(m.contains("references（"), "不要再被當成一般 reference 說一次：\(m)")
        }
        XCTAssertEqual(Set(try store.load().venues.map(\.key)), ["k", "d"], "零寫入")
    }

    /// person 合併維持現狀（design「person 合併維持現狀」）：被併者有、倖存者沒有的 authorized 本來就拒絕；名字分類記錄屬於「被併者有、
    /// 倖存者沒有的非 verdict reference」，子集判準照舊擋；倖存者持有位元組相同的一筆時不擋。
    func testPersonMergeKeepsItsOwnRefusals() {
        let rec = record("authorized", "Doomed, Person", .designate, "本人署名")
        var doomed = Person(key: "d-person", names: PersonNames(authorized: ["Doomed, Person"], variant: []))
        doomed.references = [rec]
        let keeper = Person(key: "k-person", names: PersonNames(authorized: ["Keeper, Person"], variant: []))
        let losses = LibraryStore.fieldsLostByMerging(doomed, into: keeper)
        XCTAssertTrue(losses.contains { $0.hasPrefix("authorized:") && $0.contains("Doomed, Person") }, "\(losses)")
        XCTAssertTrue(losses.contains { $0.hasPrefix("references（1 筆") && $0.contains("authorized") }, "\(losses)")

        var sameKeeper = Person(key: "k2-person", names: PersonNames(authorized: ["Doomed, Person"], variant: []))
        sameKeeper.references = [rec]
        XCTAssertTrue(LibraryStore.fieldsLostByMerging(doomed, into: sameKeeper).isEmpty,
                      "倖存者有位元組相同的記錄、也指定同一個名字：沒有東西會失去")
    }
}
