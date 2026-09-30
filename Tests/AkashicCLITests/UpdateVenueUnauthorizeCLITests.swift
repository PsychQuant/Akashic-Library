import XCTest
import Foundation
@testable import AkashicCore
@testable import AkashicStoreIO

/// #559 的 CLI 面：`update-venue --unauthorize` 走真 binary。
///
/// 旗標名、`validate()` 的參數檢查（早於開 store、用法錯誤 exit 64）與 `run()` 的轉送都只有實際呼叫抓得到。
final class UpdateVenueUnauthorizeCLITests: XCTestCase {
    private var tmp: URL!
    private var root: URL!

    override func setUpWithError() throws {
        tmp = FileManager.default.temporaryDirectory.appendingPathComponent("akashic-uvun-\(UUID().uuidString)")
        root = tmp.appendingPathComponent("store")
        try LibraryStore(root: root).ensureLayout()
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: tmp) }

    private func run(_ args: [String]) throws -> (status: Int32, output: String) {
        try CLITestHarness.run(args + ["--library", root.path], env: ["HOME": tmp.path, "AKASHIC_HOME": tmp.path])
    }
    private func venue(_ key: String) throws -> Venue {
        try XCTUnwrap(try LibraryStore(root: root).load().venues.first { $0.key == key })
    }

    func testUnauthorizeThroughTheCLI() throws {
        XCTAssertEqual(try run(["add-venue", "ampsy", "--names", "AMERICAN PSYCHOLOGIST", "American Psychologist", "--type", "periodical"]).status, 0)
        XCTAssertEqual(try run(["update-venue", "ampsy", "--authorize", "American Psychologist"]).status, 0)
        XCTAssertEqual(try venue("ampsy").authorized, ["American Psychologist"], "fixture")

        let done = try run(["update-venue", "ampsy", "--unauthorize", "American Psychologist"])
        XCTAssertEqual(done.status, 0, done.output)
        XCTAssertTrue(done.output.contains("authorizedWithdrawn") && done.output.contains("American Psychologist"), done.output)
        let v = try venue("ampsy")
        XCTAssertEqual(v.authorized, [])
        XCTAssertEqual(Set(v.names.entries.map(\.value)), ["AMERICAN PSYCHOLOGIST", "American Psychologist"], "名字留在 names")
        XCTAssertEqual(v.variant, [])

        // 不是成員：執行期拒絕（要讀 store 才判得出來），非零、零寫入
        let notMember = try run(["update-venue", "ampsy", "--unauthorize", "AMERICAN PSYCHOLOGIST"])
        XCTAssertNotEqual(notMember.status, 0, notMember.output)
        XCTAssertTrue(notMember.output.contains("不是這筆 venue 目前的 authorized"), notMember.output)
    }

    /// 兩句矛盾的話只看 argv：用法錯誤（64），早於開 store——對一個不存在的 store 路徑也是同一個錯誤，不是「開不了 store」。
    func testContradictionIsAUsageErrorBeforeTheStoreIsOpened() throws {
        let r = try CLITestHarness.run(["update-venue", "ampsy", "--authorize", "X", "--unauthorize", "X",
                                        "--library", tmp.appendingPathComponent("no-such-store").path],
                                       env: ["HOME": tmp.path, "AKASHIC_HOME": tmp.path])
        XCTAssertEqual(r.status, 64, r.output)
        XCTAssertTrue(r.output.contains("同時被送進 authorize 與 unauthorize"), r.output)
    }
}
