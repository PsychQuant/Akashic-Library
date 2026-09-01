import Foundation
import XCTest
@testable import AkashicCore
@testable import AkashicStoreIO

/// #460：venue 身上的 `work:` holder verdict 必須隨 work 的 citekey 退役（rename／merge）
/// 遷移——#232 修 rename、#271 修 merge 時都只掃 people，#304 之後 venue 也持這種
/// verdict（`entity-backlink-completeness` 第 13 條邊），兩處都漏。
/// 實測後果（#456 pilot）：合併後 venue 留著指向已刪 citekey 的死 verdict。
final class VenueVerdictMigrationTests: XCTestCase {
    private var root: URL!
    private var store: LibraryStore!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("akashic-vvm-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("entities"), withIntermediateDirectories: true)
        GitFixture.initRepo(root)
        try StoreVersion.write(root: root, format: StoreVersion.supported)
        store = LibraryStore(root: root)
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    private func entry(_ citekey: String) throws {
        try store.writeEntry(Entry(id: UUID(), citekey: citekey, type: .periodicalArticle,
                                   title: "T \(citekey)", authors: [.literal("A B")],
                                   date: "2020"))
    }

    private func venue(_ key: String, verdicts: [(field: String, holder: String, literal: String)]) throws {
        var v = Venue(key: key, type: .periodical)
        v.names = TimelineOf([TemporalValue(value: "V", range: DateRange())])
        v.references = verdicts.map {
            ProvenanceReference(
                field: $0.field,
                value: ProvenanceReference.VerdictPairingValue(
                    holderKind: .work, holder: $0.holder, literal: $0.literal).encoded,
                kind: .judgement(statement: "測試用判定", restsOn: []))
        }
        try store.writeVenue(v)
    }

    private func mergeDivergence(keeper: String, doomed: String) throws -> Divergence {
        let d = Divergence(
            id: UUID(), question: "\(keeper) 與 \(doomed) 是同一篇嗎",
            candidates: [DivergenceCandidate(key: keeper, shape: .work),
                         DivergenceCandidate(key: doomed, shape: .work)])
        _ = try store.writeDivergence(d)
        return d
    }

    // MARK: - merge 側（resolveWorkDivergence）

    func testMergeMigratesVenueWorkVerdictToSurvivor() throws {
        try entry("keeper2020a")
        try entry("doomed2020a")
        try venue("some-journal", verdicts: [
            ("resolution-confirmed", "doomed2020a", "Some Journal")])
        let d = try mergeDivergence(keeper: "keeper2020a", doomed: "doomed2020a")

        GitFixture.commitAll(store.root)
        let report = try store.resolveDivergence(id: d.id, survivor: "keeper2020a")

        XCTAssertTrue(report.verdictValuesRewritten.contains("some-journal"),
                      "venue 的 verdict 遷移必須回報：\(report.verdictValuesRewritten)")
        let after = try store.load().venues.first { $0.key == "some-journal" }
        let v = after?.references.first?.value ?? ""
        XCTAssertTrue(v.contains("work:keeper2020a"), "verdict 未遷移到 survivor：\(v)")
        XCTAssertFalse(v.contains("doomed2020a"), "已併 citekey 殘留：\(v)")
    }

    /// doomed 與 keeper 的 verdict 在遷移後同 (field, value) → 收攏成一筆
    /// （#461 起與排列無關——doomed-first 見下一支測試）。
    func testMergeCollapsesDuplicateVenueVerdictIdempotently() throws {
        try entry("keeper2020b")
        try entry("doomed2020b")
        try venue("dup-journal", verdicts: [
            ("resolution-confirmed", "keeper2020b", "Dup Journal"),
            ("resolution-confirmed", "doomed2020b", "Dup Journal")])
        let d = try mergeDivergence(keeper: "keeper2020b", doomed: "doomed2020b")

        GitFixture.commitAll(store.root)
        _ = try store.resolveDivergence(id: d.id, survivor: "keeper2020b")

        let after = try store.load().venues.first { $0.key == "dup-journal" }
        XCTAssertEqual(after?.references.count, 1,
                       "遷移後同 (field,value) 必須收攏成一筆：\(after?.references.count ?? -1)")
        XCTAssertTrue(after?.references.first?.value?.contains("work:keeper2020b") ?? false)
    }

    /// doomed 的 verdict 排在 keeper 原版之前也收攏（#461 的二階段修法）——
    /// 本測試曾是斷言現況 count == 2 的 pin（#460 verify），#461 修復後翻轉為
    /// 正向斷言：收攏與排列無關。
    func testMergeDoomedFirstArrangementAlsoCollapses() throws {
        try entry("keeper2020c")
        try entry("doomed2020c")
        try venue("ord-journal", verdicts: [
            ("resolution-confirmed", "doomed2020c", "Ord Journal"),
            ("resolution-confirmed", "keeper2020c", "Ord Journal")])
        let d = try mergeDivergence(keeper: "keeper2020c", doomed: "doomed2020c")

        GitFixture.commitAll(store.root)
        _ = try store.resolveDivergence(id: d.id, survivor: "keeper2020c")

        let after = try store.load().venues.first { $0.key == "ord-journal" }
        XCTAssertEqual(after?.references.count, 1,
                       "doomed-first 排列也必須收攏成一筆（#461）")
        XCTAssertTrue(after?.references.first?.value?.contains("work:keeper2020c") ?? false)
    }

    // MARK: - rename 側（renameEntry）

    func testRenameMigratesVenueWorkVerdictToNewKey() throws {
        try entry("old2020key")
        try venue("ren-journal", verdicts: [
            ("resolution-confirmed", "old2020key", "Ren Journal")])

        _ = try store.renameEntry(from: "old2020key", to: "new2020key")

        let after = try store.load().venues.first { $0.key == "ren-journal" }
        let v = after?.references.first?.value ?? ""
        XCTAssertTrue(v.contains("work:new2020key"), "verdict 未遷移到 newKey：\(v)")
        XCTAssertFalse(v.contains("old2020key"), "舊 citekey 殘留：\(v)")
    }

    /// 否決 verdict 同樣要遷移——rejected stale 會讓否決抑制安靜失效，
    /// 同一配對被重新提名（#232「Rejection SHALL be distinct from absence」的 venue 側）。
    func testRenameMigratesRejectedVenueVerdict() throws {
        try entry("old2020rej")
        try venue("rej-journal", verdicts: [
            ("resolution-rejected", "old2020rej", "Not This Journal")])

        _ = try store.renameEntry(from: "old2020rej", to: "new2020rej")

        let after = try store.load().venues.first { $0.key == "rej-journal" }
        let v = after?.references.first?.value ?? ""
        XCTAssertTrue(v.contains("work:new2020rej"), "rejected verdict 未遷移：\(v)")
        XCTAssertEqual(after?.references.first?.field, "resolution-rejected")
    }
}
