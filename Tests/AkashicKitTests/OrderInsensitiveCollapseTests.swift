import Foundation
import XCTest
@testable import AkashicCore
@testable import AkashicStoreIO

/// #461：merge 側 verdict 收攏必須與 reference 排列無關（二階段修法），
/// 且**只**收攏本次遷移觸及的 (field, value)——與遷移無關的既有重複一筆不動
/// （「消歧不是清理工具」，#71 的裁決由觸及集合守住）。
/// venue 側的 doomed-first 案在 `VenueVerdictMigrationTests`；本檔補 person 側
/// 與「無關重複保留」的負向案。
final class OrderInsensitiveCollapseTests: XCTestCase {
    private var root: URL!
    private var store: LibraryStore!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("akashic-oic-\(UUID().uuidString)")
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

    private func verdict(_ field: String, holder: String, literal: String) -> ProvenanceReference {
        ProvenanceReference(
            field: field,
            value: ProvenanceReference.VerdictPairingValue(
                holderKind: .work, holder: holder, literal: literal).encoded,
            kind: .judgement(statement: "測試用判定", restsOn: []))
    }

    private func mergeDivergence(keeper: String, doomed: String) throws -> Divergence {
        let d = Divergence(
            id: UUID(), question: "\(keeper) 與 \(doomed) 是同一篇嗎",
            candidates: [DivergenceCandidate(key: keeper, shape: .work),
                         DivergenceCandidate(key: doomed, shape: .work)])
        _ = try store.writeDivergence(d)
        return d
    }

    /// person 側的 doomed-first 排列——#461 之前與 venue 同病（#271 起）。
    func testPersonMergeDoomedFirstAlsoCollapses() throws {
        try entry("pkeeper2020a")
        try entry("pdoomed2020a")
        var p = Person(key: "some-author", names: PersonNames(variant: ["Some Author"]))
        p.references = [verdict("resolution-confirmed", holder: "pdoomed2020a", literal: "Some Author"),
                        verdict("resolution-confirmed", holder: "pkeeper2020a", literal: "Some Author")]
        try store.writePerson(p)
        let d = try mergeDivergence(keeper: "pkeeper2020a", doomed: "pdoomed2020a")

        GitFixture.commitAll(store.root)
        _ = try store.resolveDivergence(id: d.id, survivor: "pkeeper2020a")

        let after = try store.load().people.first { $0.key == "some-author" }
        XCTAssertEqual(after?.references.count, 1,
                       "person 側 doomed-first 排列也必須收攏成一筆（#461）")
        XCTAssertTrue(after?.references.first?.value?.contains("work:pkeeper2020a") ?? false)
    }

    /// 與本次遷移**無關**的既有重複不得被收攏——觸及集合的邊界（#461 Risks 釘住：
    /// 觸及集合若過寬會退化成全量 dedup，重演被否決的方案 (a)）。
    func testUnrelatedExistingDuplicatesAreUntouched() throws {
        try entry("ukeeper2020a")
        try entry("udoomed2020a")
        try entry("bystander2020a")
        var v = Venue(key: "untouched-journal", type: .periodical)
        v.names = TimelineOf([TemporalValue(value: "U", range: DateRange())])
        v.references = [
            // 與 merge 無關的既有重複 ×2（bystander 的 verdict）
            verdict("resolution-confirmed", holder: "bystander2020a", literal: "U Journal"),
            verdict("resolution-confirmed", holder: "bystander2020a", literal: "U Journal"),
            // 本次要遷移的
            verdict("resolution-confirmed", holder: "udoomed2020a", literal: "U Journal"),
        ]
        try store.writeVenue(v)
        let d = try mergeDivergence(keeper: "ukeeper2020a", doomed: "udoomed2020a")

        GitFixture.commitAll(store.root)
        _ = try store.resolveDivergence(id: d.id, survivor: "ukeeper2020a")

        let after = try store.load().venues.first { $0.key == "untouched-journal" }
        let vals = after?.references.compactMap(\.value) ?? []
        XCTAssertEqual(vals.filter { $0.contains("bystander2020a") }.count, 2,
                       "與遷移無關的既有重複必須原樣保留（消歧不是清理工具）：\(vals)")
        XCTAssertEqual(vals.filter { $0.contains("ukeeper2020a") }.count, 1,
                       "遷移目標正常改寫")
    }
}
