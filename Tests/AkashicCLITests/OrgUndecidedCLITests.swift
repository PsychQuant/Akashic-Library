import XCTest
import Foundation
@testable import AkashicCore
@testable import AkashicStoreIO

/// change `org-undecided-leg`（#643）：resolve-organizations 的 CLI 未決腿與篩選式 `--apply` 的排除，走真 binary。
final class OrgUndecidedCLITests: XCTestCase {
    private var root: URL!
    private var store: LibraryStore!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("akashic-org-undecided-cli-\(UUID().uuidString)")
        store = LibraryStore(root: root, key: nil, environment: [:])
        try store.ensureLayout()
        try StoreVersion.write(root: root, format: StoreVersion.supported)
        for (key, name) in [("iss", "ISS Academia Sinica"), ("ntu", "National Taiwan University")] {
            var o = Organization(key: key)
            o.names = TimelineOf([TemporalValue(value: name, range: DateRange())])
            try store.writeOrganization(o)
        }
        for (key, aff) in [("chen-ch", "ISS Academia Sinica"), ("lin-y", "National Taiwan University")] {
            var p = Person(key: key, names: [key])
            p.profile.affiliations = TimelineOf([TemporalValue(value: OrgRef.literal(aff), range: DateRange())])
            try store.writePerson(p)
        }
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    private func runCLI(_ args: [String]) throws -> (status: Int32, output: String) {
        try CLITestHarness.run(args + ["--library", root.path], env: [:])
    }
    private func reload() throws -> LibraryLoad { try LibraryStore(root: root, key: nil, environment: [:]).load() }
    private func affiliation(_ key: String) throws -> OrgRef? {
        try reload().people.first { $0.key == key }?.profile.affiliations.entries.first?.value
    }

    func testUndecidedLegWritesAndListShowsIdAndMark() throws {
        let r = try runCLI(["resolve-organizations", "--undecided", "chen-ch::ISS Academia Sinica@iss=查了所名冊"])
        XCTAssertEqual(r.status, 0, r.output)
        let org = try XCTUnwrap(try reload().organizations.first { $0.key == "iss" })
        XCTAssertEqual(org.references.map(\.field), ["resolution-undecided"])
        let list = try runCLI(["resolve-organizations"])
        XCTAssertTrue(list.output.contains("chen-ch::ISS Academia Sinica"), "列表要印 rowID：\n\(list.output)")
        XCTAssertTrue(list.output.contains("查過未決 1 次"), "列表要標出：\n\(list.output)")
    }

    /// spec 的 Scenario「Filtered apply with one checked candidate」。
    func testFilteredApplyExcludesTheCheckedCandidate() throws {
        _ = try runCLI(["resolve-organizations", "--undecided", "chen-ch::ISS Academia Sinica@iss=查過"])
        let r = try runCLI(["resolve-organizations", "--apply", "--yes"])
        XCTAssertEqual(r.status, 0, r.output)
        XCTAssertTrue(r.output.contains("查過未決"), r.output)
        XCTAssertEqual(try affiliation("chen-ch"), .literal("ISS Academia Sinica"), "查過未決的不帶走")
        XCTAssertEqual(try affiliation("lin-y"), .key("ntu"), "其餘照套")
    }

    func testAllExcludedWritesNothingAndExitsNonZero() throws {
        _ = try runCLI(["resolve-organizations", "--undecided",
                        "chen-ch::ISS Academia Sinica@iss=查過", "lin-y::National Taiwan University@ntu=查過"])
        let r = try runCLI(["resolve-organizations", "--apply", "--yes"])
        XCTAssertNotEqual(r.status, 0, r.output)
        XCTAssertEqual(try affiliation("chen-ch"), .literal("ISS Academia Sinica"))
        XCTAssertEqual(try affiliation("lin-y"), .literal("National Taiwan University"))
    }

    func testCombinationsAreRefused() throws {
        XCTAssertNotEqual(try runCLI(["resolve-organizations", "--apply", "--yes", "--undecided",
                                      "chen-ch::ISS Academia Sinica@iss=x"]).status, 0)
        XCTAssertNotEqual(try runCLI(["resolve-organizations", "--rests-on", "sha256:" + String(repeating: "a", count: 64)]).status, 0)
        XCTAssertTrue(try reload().organizations.allSatisfy { $0.references.isEmpty })
        // R1 verify：--holder／--org 對未決腿沒有作用，靜默忽略會讓人以為收窄了範圍
        XCTAssertNotEqual(try runCLI(["resolve-organizations", "--holder", "chen-ch", "--undecided",
                                      "chen-ch::ISS Academia Sinica@iss=x"]).status, 0)
        XCTAssertTrue(try reload().organizations.allSatisfy { $0.references.isEmpty })
    }

    /// 歧義條目的未決另數一行（與 MCP 的 ambiguityUndecidedTotal 同一個定義），不混進四態計數。
    func testAmbiguityUndecidedIsCountedOnItsOwnLine() throws {
        for key in ["as", "iss-2"] {
            var o = Organization(key: key)
            o.names = TimelineOf([TemporalValue(value: "Sinica", range: DateRange())])
            try store.writeOrganization(o)
        }
        var p = Person(key: "p", names: ["p"])
        p.profile.affiliations = TimelineOf([TemporalValue(value: OrgRef.literal("Sinica"), range: DateRange())])
        try store.writePerson(p)
        XCTAssertEqual(try runCLI(["resolve-organizations", "--undecided", "p::Sinica@as=查過"]).status, 0)
        let list = try runCLI(["resolve-organizations"])
        XCTAssertTrue(list.output.contains("歧義條目中查過未決的配對：1"), list.output)
        XCTAssertTrue(list.output.contains("查過未決 0"), "四態計數只數候選：\n\(list.output)")
    }
}
