import XCTest
import Foundation
@testable import AkashicCore
@testable import AkashicStoreIO

/// #648 (b)：CLI 面的 `--judge`／`--refute` 對超過 4,096 位元組的理由整批拒絕、零寫入、非零結束——走真 binary
/// （service 層的測試證不到 CLI 把錯誤帶到 exit code 與輸出）。
final class JudgeReasonCapCLITests: XCTestCase {
    private var root: URL!
    private var home: URL!

    override func setUpWithError() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("akashic-648-cli-\(UUID().uuidString)")
        root = base.appendingPathComponent("store")
        home = base.appendingPathComponent("home")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        let store = LibraryStore(root: root, key: nil, environment: [:])
        try store.ensureLayout()
        try StoreVersion.write(root: root, format: StoreVersion.supported)
        try store.writePerson(Person(key: "cheng-che", names: ["Che Cheng"]))
        try store.writeEntry(Entry(id: UUID(), citekey: "a2020x", type: .periodicalArticle,
                                   title: "T", authors: [.literal("Che Cheng")], date: "2020"))
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }

    private func runCLI(_ args: [String]) throws -> (status: Int32, output: String) {
        try CLITestHarness.run(args + ["--library", root.path], env: ["AKASHIC_HOME": home.path])
    }

    private func reload() throws -> LibraryLoad { try LibraryStore(root: root, key: nil, environment: [:]).load() }

    func testOversizedJudgeReasonExitsNonZeroAndWritesNothing() throws {
        let r = try runCLI(["resolve-people", "--judge", "a2020x:0:cheng-che=\(String(repeating: "r", count: 4_097))"])
        XCTAssertNotEqual(r.status, 0, r.output)
        XCTAssertTrue(r.output.contains("4097") && r.output.contains("4096"), "兩個數都要說：\n\(r.output)")
        let load = try reload()
        XCTAssertEqual(load.entries.first?.authors, [.literal("Che Cheng")], "零寫入")
        XCTAssertEqual(load.people.first?.references.count, 0)
    }

    func testOversizedRefuteReasonExitsNonZeroAndWritesNothing() throws {
        let r = try runCLI(["resolve-people", "--refute", "a2020x:0:cheng-che=\(String(repeating: "r", count: 4_097))"])
        XCTAssertNotEqual(r.status, 0, r.output)
        XCTAssertEqual(try reload().people.first?.references.count, 0)
    }

    func testJudgeReasonAtTheCapIsAccepted() throws {
        let r = try runCLI(["resolve-people", "--judge", "a2020x:0:cheng-che=\(String(repeating: "r", count: 4_096))"])
        XCTAssertEqual(r.status, 0, r.output)
        XCTAssertEqual(try reload().entries.first?.authors, [.key("cheng-che")])
    }
}
