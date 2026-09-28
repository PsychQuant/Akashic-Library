import XCTest
@testable import AkashicCore
@testable import AkashicStoreIO
@testable import AkashicMCPKit

/// #642 的 service 面（CLI `library` 與 MCP `akashic_libraries` 共用這一條路徑）。
///
/// 使用者 2026-09-25 的裁定（Clarity row 1）：不符規則的條目**不是拒絕、也不是同意後照寫，而是改成正確的再寫**——
/// 符合的寫、不符的不寫並逐筆說出依據。查不到依據（未標性質、文件不在庫）就不寫。
final class LibraryMembershipServiceTests: XCTestCase {
    var root: URL!
    var fakeHome: URL!
    var service: AkashicService!

    override func setUpWithError() throws {
        fakeHome = FileManager.default.temporaryDirectory.appendingPathComponent("akashic-home-\(UUID().uuidString)")
        root = FileManager.default.temporaryDirectory.appendingPathComponent("akashic-lmsv-\(UUID().uuidString)")
        try LibraryStore(root: root).ensureLayout()
        service = AkashicService(root: root, environment: ["AKASHIC_HOME": fakeHome.path])
        let store = LibraryStore(root: root)
        try store.writeVenue(Venue(key: "pm", type: .periodical, names: Timeline([TemporalValue(value: "PM")])))
        for (ck, venues, cites) in [("pm2020a", [VenueRef.key("pm")], [String]()),
                                    ("pm2021a", [.key("pm")], []),
                                    ("other2020a", [.key("psychometrika")], []),
                                    ("lit2020a", [.literal("Psychological Methods")], []),
                                    ("draft2026a", [], ["pm2020a", "other2020a"])] {
            var e = Entry(id: UUID(), citekey: ck, type: .periodicalArticle, title: ck, venues: venues)
            e.akashic.relations.cites = cites
            try store.writeEntry(e)
        }
    }
    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
        try? FileManager.default.removeItem(at: fakeHome)
    }

    private func json(_ s: String) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: Data(s.utf8)) as? [String: Any])
    }
    private func membership(_ ck: String) throws -> [String] {
        try LibraryStore(root: root).load().entries.first { $0.citekey == ck }?.akashic.libraries ?? []
    }
    private func create(_ key: String, _ m: AkashicService.LibraryMembershipInput) throws {
        _ = try service.libraries(action: "create", key: key, name: key, description: nil, citekey: nil, membership: m)
    }

    // MARK: - 性質是必填的依據

    func testCreateRequiresAKind() throws {
        XCTAssertThrowsError(try service.libraries(action: "create", key: "x", name: "X", description: nil, citekey: nil)) {
            XCTAssertTrue(String(describing: $0).contains("kind"), "\($0)")
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: LibraryStore(root: root).libraryURL(key: "x").path))
        try create("reading", .init(kind: "topic"))
        let list = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(
            service.libraries(action: "list", key: nil, name: nil, description: nil, citekey: nil).utf8)) as? [[String: Any]])
        XCTAssertEqual(list.first?["kind"] as? String, "topic")
    }

    func testCreateRefusesARuleWhoseVenueOrDocumentIsNotInTheStore() {
        XCTAssertThrowsError(try create("c", .init(kind: "rule", venue: "ghost")))
        XCTAssertThrowsError(try create("d", .init(kind: "document", document: "ghost2026a")))
    }

    func testArgumentOnlyChecksRejectMalformedInput() {
        for bad: AkashicService.LibraryMembershipInput in [
            .init(kind: "catalog"), .init(kind: "rule"), .init(kind: "topic", venue: "pm"),
            .init(kind: "document"), .init(kind: "rule", venue: "pm", types: ["no-such-type"]),
            .init(kind: "rule", venue: "Bad Key"), .init(venue: "pm"),
            .init(kind: "rule", venue: "pm", source: "  "),
        ] {
            XCTAssertThrowsError(try AkashicService.parseLibraryMembership(bad), "\(bad)")
        }
        XCTAssertEqual(try AkashicService.parseLibraryMembership(.init(kind: "rule", venue: "pm", types: ["periodical-article"])),
                       .rule(LibraryRule(venue: "pm", types: [.periodicalArticle])))
        XCTAssertNil(try AkashicService.parseLibraryMembership(.init()))
    }

    // MARK: - add：改成正確的再寫

    func testUnmarkedLibraryRefusesAddWithZeroWrites() throws {
        try LibraryStore(root: root).writeLibrary(Library(key: "old", name: "舊"))
        XCTAssertThrowsError(try service.setMembership(action: "add", key: "old", citekeys: ["pm2020a"])) {
            XCTAssertTrue(String(describing: $0).contains("set-kind"), "\($0)")
        }
        XCTAssertEqual(try membership("pm2020a"), [])
        // remove 不查依據——清掉錯的成員關係永遠可以
        var e = try XCTUnwrap(try LibraryStore(root: root).load().entries.first { $0.citekey == "pm2021a" })
        e.akashic.libraries = ["old"]
        try LibraryStore(root: root).writeEntry(e)
        XCTAssertEqual(try service.setMembership(action: "remove", key: "old", citekeys: ["pm2021a"]).written, ["pm2021a"])
    }

    func testRuleLibraryWritesOnlyConformingEntriesAndNamesTheRest() throws {
        try create("pm-catalog", .init(kind: "rule", venue: "pm", source: "openalex:S45419345"))
        let report = try service.setMembership(action: "add", key: "pm-catalog",
                                               citekeys: ["pm2020a", "other2020a", "lit2020a", "pm2021a"])
        XCTAssertEqual(report.written, ["pm2020a", "pm2021a"])
        XCTAssertEqual(report.skipped.map(\.citekey), ["other2020a", "lit2020a"])
        XCTAssertTrue(report.skipped[0].reason.contains("psychometrika"), report.skipped[0].reason)
        XCTAssertTrue(report.skipped[1].reason.contains("resolve-venues"), report.skipped[1].reason)
        XCTAssertTrue(report.basis.contains("pm") && report.basis.contains("openalex"), report.basis)
        XCTAssertEqual(try membership("pm2020a"), ["pm-catalog"])
        XCTAssertEqual(try membership("other2020a"), [], "不符規則的不寫")
    }

    func testDocumentLibraryAcceptsOnlyWhatTheDocumentCites() throws {
        try create("paper", .init(kind: "document", document: "draft2026a"))
        let report = try service.setMembership(action: "add", key: "paper", citekeys: ["pm2020a", "pm2021a", "other2020a"])
        XCTAssertEqual(report.written, ["pm2020a", "other2020a"])
        XCTAssertEqual(report.skipped.map(\.citekey), ["pm2021a"])
    }

    func testTopicLibraryWritesWhatTheUserChose() throws {
        try create("reading", .init(kind: "topic"))
        let report = try service.setMembership(action: "add", key: "reading", citekeys: ["other2020a", "lit2020a"])
        XCTAssertEqual(report.written, ["other2020a", "lit2020a"])
        XCTAssertTrue(report.skipped.isEmpty)
    }

    /// MCP 的單筆 add：不符時不擲錯（沒有寫錯任何東西），回應說出沒寫與原因。
    func testSingleAddReportsASkipInsteadOfThrowing() throws {
        try create("pm-catalog", .init(kind: "rule", venue: "pm"))
        let out = try json(service.libraries(action: "add", key: "pm-catalog", name: nil, description: nil, citekey: "other2020a"))
        XCTAssertEqual(out["written"] as? Bool, false)
        XCTAssertTrue((out["skipped"] as? String)?.contains("psychometrika") ?? false, "\(out)")
        XCTAssertNotNil(out["basis"])
        let ok = try json(service.libraries(action: "add", key: "pm-catalog", name: nil, description: nil, citekey: "pm2020a"))
        XCTAssertEqual(ok["written"] as? Bool, true)
        XCTAssertEqual(ok["libraries"] as? [String], ["pm-catalog"])
    }

    func testMembershipParametersOnlyAccompanyCreateAndSetKind() throws {
        try create("reading", .init(kind: "topic"))
        XCTAssertThrowsError(try service.libraries(action: "add", key: "reading", name: nil, description: nil,
                                                   citekey: "pm2020a", membership: .init(kind: "topic")))
    }

    // MARK: - set-kind 與 check：既有的錯誤看得見

    func testSetKindMarksAnExistingLibraryAndReportsCurrentViolations() throws {
        let store = LibraryStore(root: root)
        try store.writeLibrary(Library(key: "pm-catalog", name: "PM"))
        for ck in ["pm2020a", "other2020a"] {
            var e = try XCTUnwrap(try store.load().entries.first { $0.citekey == ck })
            e.akashic.libraries = ["pm-catalog"]
            try store.writeEntry(e)
        }
        let out = try json(service.libraries(action: "set-kind", key: "pm-catalog", name: nil, description: nil,
                                             citekey: nil, membership: .init(kind: "rule", venue: "pm")))
        XCTAssertEqual(out["nonconforming"] as? Int, 1)
        XCTAssertEqual(try store.load().libraries.first?.membership, .rule(LibraryRule(venue: "pm")))
        XCTAssertEqual(try membership("other2020a"), ["pm-catalog"], "set-kind 不自動移除——移除是另一個寫入")

        let check = try json(service.libraries(action: "check", key: "pm-catalog", name: nil, description: nil, citekey: nil))
        let items = try XCTUnwrap(check["nonconforming"] as? [[String: Any]])
        XCTAssertEqual(items.map { $0["citekey"] as? String }, ["other2020a"])
        XCTAssertEqual(check["total"] as? Int, 1)
        XCTAssertThrowsError(try service.libraries(action: "check", key: "ghost", name: nil, description: nil, citekey: nil))
        XCTAssertThrowsError(try service.libraries(action: "set-kind", key: "pm-catalog", name: nil, description: nil,
                                                   citekey: nil, membership: .init(kind: "document", document: "ghost2026a")))
        XCTAssertEqual(try store.load().libraries.first?.membership, .rule(LibraryRule(venue: "pm")), "拒絕＝零寫入")
    }
}
