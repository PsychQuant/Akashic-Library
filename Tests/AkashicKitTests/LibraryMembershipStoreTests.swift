import XCTest
import Foundation
@testable import AkashicCore
@testable import AkashicStoreIO

/// #642 的 store 層：registry 的改寫路徑、跨記錄 warning（既有的錯誤看得見）、以及規則指涉的 work／venue
/// 在改名與合併時不得安靜懸空（`entity-backlink-completeness` 第 16 條邊）。
final class LibraryMembershipStoreTests: XCTestCase {
    var root: URL!
    var store: LibraryStore!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("akashic-lms-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("entities"), withIntermediateDirectories: true)
        try StoreVersion.write(root: root, format: StoreVersion.supported)
        GitFixture.initRepo(root)
        store = LibraryStore(root: root)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    private func venue(_ key: String) -> Venue {
        Venue(key: key, type: .periodical, names: Timeline([TemporalValue(value: key)]))
    }
    private func work(_ ck: String, venues: [VenueRef] = [], libraries: [String] = [], cites: [String] = []) -> Entry {
        var e = Entry(id: UUID(), citekey: ck, type: .periodicalArticle, title: ck, venues: venues)
        e.akashic.libraries = libraries
        e.akashic.relations.cites = cites
        return e
    }

    // MARK: - 改寫路徑

    func testUpdateLibraryRewritesAnExistingRegistryFileOnly() throws {
        try store.writeLibrary(Library(key: "pm", name: "PM"))
        let rule = LibraryMembership.rule(LibraryRule(venue: "psychological-methods"))
        try store.updateLibrary(Library(key: "pm", name: "PM", membership: rule))
        XCTAssertEqual(try store.load().libraries.first?.membership, rule)
        XCTAssertThrowsError(try store.updateLibrary(Library(key: "ghost", name: "G", membership: .topic)),
                             "改寫路徑不得順便建檔——建檔走 writeLibrary 的 exclusive create")
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.libraryURL(key: "ghost").path))
    }

    // MARK: - validate／doctor 看得見既有的錯誤

    func testCrossRecordWarnsOnNonconformingMembersAndNamesThem() throws {
        try store.writeVenue(venue("pm"))
        try store.writeLibrary(Library(key: "pm-catalog", name: "PM", membership: .rule(LibraryRule(venue: "pm"))))
        try store.writeEntry(work("good2020a", venues: [.key("pm")], libraries: ["pm-catalog"]))
        try store.writeEntry(work("stray2020a", libraries: ["pm-catalog"]))
        try store.writeEntry(work("outside2020a"))   // 不是成員——規則不管非成員（目錄完整性不在本檢查）
        let issues = try store.load().crossRecordIssues().filter { $0.message.contains("pm-catalog") }
        XCTAssertEqual(issues.count, 1, "\(issues.map(\.message))")
        let m = issues[0].message
        XCTAssertEqual(issues[0].severity, .warning)
        XCTAssertTrue(m.contains("1 筆") && m.contains("stray2020a"), m)
        XCTAssertFalse(m.contains("good2020a") || m.contains("outside2020a"), m)
        XCTAssertTrue(m.contains("library check"), "要指路到能列出全部的面：\(m)")
    }

    func testCrossRecordWarnsWhenTheRuleVenueOrTheDocumentIsNotInTheStore() throws {
        try store.writeLibrary(Library(key: "pm-catalog", name: "PM", membership: .rule(LibraryRule(venue: "ghost-venue"))))
        try store.writeLibrary(Library(key: "paper", name: "P", membership: .document(citekey: "draft2026a")))
        let messages = try store.load().crossRecordIssues().map(\.message)
        XCTAssertTrue(messages.contains { $0.contains("pm-catalog") && $0.contains("ghost-venue") }, "\(messages)")
        XCTAssertTrue(messages.contains { $0.contains("paper") && $0.contains("draft2026a") }, "\(messages)")
    }

    func testTopicAndConformingLibrariesAreSilent() throws {
        try store.writeVenue(venue("pm"))
        try store.writeLibrary(Library(key: "pm-catalog", name: "PM", membership: .rule(LibraryRule(venue: "pm"))))
        try store.writeLibrary(Library(key: "reading", name: "R", membership: .topic))
        try store.writeEntry(work("good2020a", venues: [.key("pm")], libraries: ["pm-catalog", "reading"]))
        try store.writeEntry(work("any2020a", libraries: ["reading"]))
        let messages = try store.load().crossRecordIssues().map(\.message)
        XCTAssertFalse(messages.contains { $0.contains("pm-catalog") || $0.contains("reading") }, "\(messages)")
    }

    // MARK: - 規則指涉的鍵不得在改名與合併時安靜懸空

    func testRenameRefusesWhenALibraryRuleNamesTheCitekey() throws {
        try store.writeEntry(work("draft2026a", cites: []))
        try store.writeLibrary(Library(key: "paper", name: "P", membership: .document(citekey: "draft2026a")))
        try store.writeLibrary(Library(key: "pm-catalog", name: "PM",
                                       membership: .rule(LibraryRule(venue: "pm", excluded: ["ruled2020a"]))))
        try store.writeEntry(work("ruled2020a"))
        GitFixture.commitAll(root, message: "seed")
        for (old, lib) in [("draft2026a", "paper"), ("ruled2020a", "pm-catalog")] {
            XCTAssertThrowsError(try store.renameEntry(from: old, to: old + "x")) { error in
                let m = String(describing: error)
                XCTAssertTrue(m.contains(lib) && m.contains("set-kind"), m)
            }
            XCTAssertTrue(try store.load().entries.contains { $0.citekey == old }, "拒絕＝零寫入")
        }
    }

    func testWorkMergeRefusesWhenTheDoomedWorkIsNamedByALibraryRule() throws {
        try store.writeEntry(work("draft2026a"))
        try store.writeEntry(work("draft2026b"))
        try store.writeLibrary(Library(key: "paper", name: "P", membership: .document(citekey: "draft2026b")))
        let d = Divergence(id: UUID(), question: "同一份稿？",
                           candidates: [DivergenceCandidate(key: "draft2026a", shape: .work),
                                        DivergenceCandidate(key: "draft2026b", shape: .work)])
        try store.writeDivergence(d)
        GitFixture.commitAll(root, message: "seed")
        for attempt in [{ _ = try self.store.previewResolveDivergence(id: d.id, survivor: "draft2026a", overrideReason: nil) },
                        { _ = try self.store.resolveDivergence(id: d.id, survivor: "draft2026a") }] {
            XCTAssertThrowsError(try attempt()) { error in
                let m = String(describing: error)
                XCTAssertTrue(m.contains("paper") && m.contains("draft2026b"), m)
            }
        }
        XCTAssertEqual(try store.load().entries.count, 2, "拒絕＝零寫入")
    }

    func testVenueMergeRefusesWhenTheDoomedVenueIsARuleVenue() throws {
        try store.writeVenue(venue("pm"))
        try store.writeVenue(venue("pm-dup"))
        try store.writeLibrary(Library(key: "pm-catalog", name: "PM", membership: .rule(LibraryRule(venue: "pm-dup"))))
        let d = Divergence(id: UUID(), question: "同一本刊？",
                           candidates: [DivergenceCandidate(key: "pm", shape: .venue),
                                        DivergenceCandidate(key: "pm-dup", shape: .venue)])
        try store.writeDivergence(d)
        GitFixture.commitAll(root, message: "seed")
        XCTAssertThrowsError(try store.resolveDivergence(id: d.id, survivor: "pm")) { error in
            let m = String(describing: error)
            XCTAssertTrue(m.contains("pm-catalog") && m.contains("pm-dup"), m)
        }
        XCTAssertEqual(try store.load().venues.count, 2, "拒絕＝零寫入")
    }

    /// 反方向：倖存者就是規則的 venue → 規則仍指著活下來的那筆，放行。
    func testVenueMergeKeepingTheRuleVenueProceeds() throws {
        try store.writeVenue(venue("pm"))
        try store.writeVenue(venue("pm-dup"))
        try store.writeLibrary(Library(key: "pm-catalog", name: "PM", membership: .rule(LibraryRule(venue: "pm"))))
        let d = Divergence(id: UUID(), question: "同一本刊？",
                           candidates: [DivergenceCandidate(key: "pm", shape: .venue),
                                        DivergenceCandidate(key: "pm-dup", shape: .venue)])
        try store.writeDivergence(d)
        GitFixture.commitAll(root, message: "seed")
        _ = try store.resolveDivergence(id: d.id, survivor: "pm")
        XCTAssertEqual(try store.load().venues.map(\.key), ["pm"])
    }
}
