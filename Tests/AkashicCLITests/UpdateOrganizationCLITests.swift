import XCTest
import Foundation
@testable import AkashicCore
@testable import AkashicStoreIO

/// #557 的 CLI 面：`update-organization` 走真 binary——命令名、旗標、`validate()` 的參數檢查（早於開 store、用法錯誤 64）與
/// `run()` 的轉送都只有實際呼叫抓得到。也驗 issue 的動機：`doctor` 那一行修得掉了。
final class UpdateOrganizationCLITests: XCTestCase {
    private var tmp: URL!
    private var root: URL!

    override func setUpWithError() throws {
        tmp = FileManager.default.temporaryDirectory.appendingPathComponent("akashic-uporg-\(UUID().uuidString)")
        root = tmp.appendingPathComponent("store")
        let store = LibraryStore(root: root)
        try store.ensureLayout()
        try store.writeOrganization(Organization(key: "iss", names: Timeline([TemporalValue(value: "Institute of Statistical Science"),
                                                                             TemporalValue(value: "中央研究院統計科學研究所")]),
                                                 id: UUID()))
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: tmp) }

    private func run(_ args: [String], library: URL? = nil) throws -> (status: Int32, output: String) {
        try CLITestHarness.run(args + ["--library", (library ?? root).path], env: ["HOME": tmp.path, "AKASHIC_HOME": tmp.path])
    }
    private func org() throws -> Organization {
        try XCTUnwrap(try LibraryStore(root: root).load().organizations.first { $0.key == "iss" })
    }

    func testAuthorizeAndUnauthorizeThroughTheCLI() throws {
        let before = try run(["doctor"])
        XCTAssertTrue(before.output.contains("/ 1 organization"), "fixture：doctor 報 1 筆 organization 缺 authorized：\(before.output)")

        let done = try run(["update-organization", "iss", "--authorize", "Institute of Statistical Science", "中央研究院統計科學研究所"])
        XCTAssertEqual(done.status, 0, done.output)
        XCTAssertTrue(done.output.contains("authorizedAdded"), done.output)
        XCTAssertEqual(Set(try org().authorized), ["Institute of Statistical Science", "中央研究院統計科學研究所"])

        let after = try run(["doctor"])
        XCTAssertTrue(after.output.contains("/ 0 organization"), "doctor 那一行修得掉了：\(after.output)")

        let withdrawn = try run(["update-organization", "iss", "--unauthorize", "中央研究院統計科學研究所"])
        XCTAssertEqual(withdrawn.status, 0, withdrawn.output)
        XCTAssertTrue(withdrawn.output.contains("authorizedWithdrawn"), withdrawn.output)
        XCTAssertEqual(try org().authorized, ["Institute of Statistical Science"])
        XCTAssertEqual(try org().names.entries.count, 2, "名字留在 names")
    }

    /// 只看 argv 的錯誤是用法錯誤（64），早於開 store——對不存在的 store 路徑也是同一個錯誤。
    func testArgvErrorsAreUsageErrorsBeforeTheStoreIsOpened() throws {
        let nowhere = tmp.appendingPathComponent("no-such-store")
        let nothing = try run(["update-organization", "iss"], library: nowhere)
        XCTAssertEqual(nothing.status, 64, nothing.output)
        XCTAssertTrue(nothing.output.contains("沒有要改的"), nothing.output)
        let clash = try run(["update-organization", "iss", "--authorize", "A", "B"], library: nowhere)
        XCTAssertEqual(clash.status, 64, clash.output)
        XCTAssertTrue(clash.output.contains("請選一個"), clash.output)
    }
}
