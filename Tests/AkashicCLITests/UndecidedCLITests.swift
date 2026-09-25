import XCTest
import Foundation
@testable import AkashicCore
@testable import AkashicStoreIO

/// change `resolution-verdict-states`（#619）：CLI 面的未決腿與篩選式 `--apply` 的排除，走真 binary。
///
/// spec「Nomination SHALL disclose undecided checks and filtered apply SHALL exclude them」的 Filtered apply 例子：
/// 一筆 exact 候選帶未決記錄時，篩選式 `--apply` 不帶走它、另列並指向 `--judge`；全數被排除時零寫入、非零結束。
final class UndecidedCLITests: XCTestCase {
    private var root: URL!
    private var store: LibraryStore!
    private let digest = "sha256:" + String(repeating: "d", count: 64)

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("akashic-undecided-cli-\(UUID().uuidString)")
        store = LibraryStore(root: root, key: nil, environment: [:])
        try store.ensureLayout()
        try StoreVersion.write(root: root, format: StoreVersion.supported)
        try store.writePerson(Person(key: "cheng-che", names: ["Che Cheng"]))
        try store.writeEntry(Entry(id: UUID(), citekey: "a2020x", type: .periodicalArticle,
                                   title: "T", authors: [.literal("Che Cheng")], date: "2020"))
        try store.writeEntry(Entry(id: UUID(), citekey: "b2021y", type: .periodicalArticle,
                                   title: "U", authors: [.literal("Che Cheng")], date: "2021"))
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    private func runCLI(_ args: [String]) throws -> (status: Int32, output: String) {
        try CLITestHarness.run(args + ["--library", root.path], env: [:])
    }
    private func reload() throws -> LibraryLoad { try LibraryStore(root: root, key: nil, environment: [:]).load() }

    func testUndecidedLegWritesAndListMarksIt() throws {
        let r = try runCLI(["resolve-people", "--undecided", "a2020x:0:cheng-che=查了機構欄只寫 Taipei", "--rests-on", digest])
        XCTAssertEqual(r.status, 0, r.output)
        XCTAssertTrue(r.output.contains(digest), "寫入的 digest 要逐筆印出：\n\(r.output)")
        let p = try XCTUnwrap(try reload().people.first { $0.key == "cheng-che" })
        XCTAssertEqual(p.references.map(\.field), ["resolution-undecided"])
        let list = try runCLI(["resolve-people"])
        let line = list.output.split(separator: "\n").first { $0.contains("a2020x") } ?? ""
        XCTAssertTrue(line.contains("查過未決 1 次"), "列表要標出：\n\(list.output)")
        XCTAssertTrue(list.output.contains("查過未決 1"), "四態計數要渲染：\n\(list.output)")
    }

    func testFilteredApplyExcludesTheCheckedPairing() throws {
        _ = try runCLI(["resolve-people", "--undecided", "a2020x:0:cheng-che=查過"])
        let r = try runCLI(["resolve-people", "--apply", "--tier", "exact", "--yes"])
        XCTAssertEqual(r.status, 0, r.output)
        XCTAssertTrue(r.output.contains("查過未決的候選 1 筆不套用"), r.output)
        let load = try reload()
        XCTAssertEqual(load.entries.first { $0.citekey == "a2020x" }?.authors, [.literal("Che Cheng")], "查過未決的不帶走")
        XCTAssertEqual(load.entries.first { $0.citekey == "b2021y" }?.authors, [.key("cheng-che")], "其餘照套")
    }

    func testAllExcludedWritesNothingAndExitsNonZero() throws {
        _ = try runCLI(["resolve-people", "--undecided", "a2020x:0:cheng-che=查過", "b2021y:0:cheng-che=查過"])
        let r = try runCLI(["resolve-people", "--apply", "--tier", "exact", "--yes"])
        XCTAssertNotEqual(r.status, 0, r.output)
        XCTAssertTrue(try reload().entries.allSatisfy { $0.authors == [.literal("Che Cheng")] }, "零寫入")
    }

    func testRestsOnWithoutUndecidedIsRefused() throws {
        let r = try runCLI(["resolve-people", "--rests-on", digest])
        XCTAssertNotEqual(r.status, 0, r.output)
    }
}
