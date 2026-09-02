import Foundation
import XCTest
@testable import AkashicCore
@testable import AkashicStoreIO

/// #464：死 verdict 掃描——resolution verdict 的 value 指向已不存在的 holder。
/// #232／#271／#460 三次都是同一族的 stale，至今零守衛（205 條靠人肉、殘留 1 條靠 verify
/// lens 全庫掃、清理完整性靠腳本）。掃描住在 `StoreHealth`，CLI `validate` 與 App 兩面
/// 自動繼承。釘住：注入死引用 → warning；乾淨 store → 零；三種 holderKind 各自對到自己的集合。
final class DeadVerdictScanTests: XCTestCase {
    private var root: URL!
    private var store: LibraryStore!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("akashic-dvs-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("entities"), withIntermediateDirectories: true)
        GitFixture.initRepo(root)
        try StoreVersion.write(root: root, format: StoreVersion.supported)
        store = LibraryStore(root: root)
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    private func verdict(_ field: String, kind: ProvenanceReference.VerdictHolderKind,
                         holder: String, literal: String) -> ProvenanceReference {
        ProvenanceReference(
            field: field,
            value: ProvenanceReference.VerdictPairingValue(
                holderKind: kind, holder: holder, literal: literal).encoded,
            kind: .judgement(statement: "測試用判定", restsOn: []))
    }

    private func entry(_ citekey: String) throws {
        try store.writeEntry(Entry(id: UUID(), citekey: citekey, type: .periodicalArticle,
                                   title: "T \(citekey)", authors: [.literal("A B")],
                                   date: "2020"))
    }

    private func deadVerdicts(_ health: StoreHealth) -> [StoreHealth.OwnedIssue] {
        health.perRecordIssues.filter { $0.issue.message.hasPrefix("死 verdict") }
    }

    /// 乾淨 store：verdict 的 holder 都活著 → 零 warning。
    func testLiveHoldersProduceNoWarning() throws {
        try entry("alive2020a")
        var p = Person(key: "some-author", names: PersonNames(variant: ["Some Author"]))
        p.references = [verdict("resolution-confirmed", kind: .work, holder: "alive2020a", literal: "Some Author")]
        try store.writePerson(p)
        let health = store.health(from: try store.load())
        XCTAssertTrue(deadVerdicts(health).isEmpty, "\(deadVerdicts(health).map(\.issue.message))")
    }

    /// person 上 `work:` holder 指向不存在的 citekey → warning，owner／kind 指得出是哪筆。
    func testDeadWorkHolderOnPersonIsAWarning() throws {
        try entry("alive2020a")
        var p = Person(key: "some-author", names: PersonNames(variant: ["Some Author"]))
        p.references = [verdict("resolution-confirmed", kind: .work, holder: "alive2020a", literal: "Some Author"),
                        verdict("resolution-rejected", kind: .work, holder: "gone2019a", literal: "Some Author")]
        try store.writePerson(p)
        let dead = deadVerdicts(store.health(from: try store.load()))
        XCTAssertEqual(dead.count, 1, "\(dead.map(\.issue.message))")
        XCTAssertEqual(dead.first?.owner, "some-author")
        XCTAssertEqual(dead.first?.kind, "person")
        XCTAssertEqual(dead.first?.issue.severity, .warning, "過期不是矛盾——warning，不進 hasFindings")
        XCTAssertTrue(dead.first?.issue.message.contains("work:gone2019a") ?? false)
        XCTAssertFalse(store.health(from: try store.load()).hasFindings, "warning 級不得把 hasFindings 拉成真")
    }

    /// venue 上的 `work:` holder（#460 家族的 venue 側）同樣被掃到。
    func testDeadWorkHolderOnVenueIsAWarning() throws {
        var v = Venue(key: "some-journal", type: .periodical,
                      names: TimelineOf([TemporalValue(value: "Some Journal")]))
        v.references = [verdict("resolution-confirmed", kind: .work, holder: "gone2019a", literal: "SOME JOURNAL")]
        _ = try store.writeVenue(v)
        let dead = deadVerdicts(store.health(from: try store.load()))
        XCTAssertEqual(dead.map(\.kind), ["venue"], "\(dead.map(\.issue.message))")
        XCTAssertEqual(dead.first?.owner, "some-journal")
    }

    /// `person:`／`org:` holder 各自對到自己的集合——一個活著的 citekey 不能替一個死掉的 person key 頂替。
    func testPersonAndOrgHoldersUseTheirOwnKeySets() throws {
        try entry("some-author")   // 同名 citekey 存在，但它不是 person key
        var o = Organization(key: "some-org", names: TimelineOf([TemporalValue(value: "Some Org")]))
        o.references = [verdict("resolution-confirmed", kind: .person, holder: "some-author", literal: "Some Org"),
                        verdict("resolution-confirmed", kind: .org, holder: "parent-org", literal: "Parent")]
        try store.writeOrganization(o)
        let dead = deadVerdicts(store.health(from: try store.load()))
        XCTAssertEqual(dead.count, 2, "person:some-author 與 org:parent-org 都不存在：\(dead.map(\.issue.message))")
        XCTAssertTrue(dead.allSatisfy { $0.kind == "organization" && $0.owner == "some-org" })
    }
}
