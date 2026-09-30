import XCTest
import Foundation
@testable import AkashicCore
@testable import AkashicStoreIO

/// #557 的 CLI 面：`update-organization` 走真 binary——命令名、旗標、`validate()` 的參數檢查（早於開 store、用法錯誤 64）與
/// `run()` 的轉送都只有實際呼叫抓得到。也驗 issue 的動機：`doctor` 那一行修得掉了。沒有 `--unauthorize`（R1 verify 之後拿掉）。
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

    func testAuthorizeThroughTheCLI() throws {
        let before = try run(["doctor"])
        XCTAssertTrue(before.output.contains("/ 1 organization"), "fixture：doctor 報 1 筆 organization 缺 authorized：\(before.output)")

        let done = try run(["update-organization", "iss", "--authorize", "Institute of Statistical Science", "中央研究院統計科學研究所", "--judgement", "所方正式名稱"])
        XCTAssertEqual(done.status, 0, done.output)
        XCTAssertTrue(done.output.contains("authorizedAdded"), done.output)
        XCTAssertEqual(Set(try org().authorized), ["Institute of Statistical Science", "中央研究院統計科學研究所"])

        let after = try run(["doctor"])
        XCTAssertTrue(after.output.contains("/ 0 organization"), "doctor 那一行修得掉了：\(after.output)")

        // 沒有撤回面：旗標不存在，不是「存在但拒絕」
        let withdraw = try run(["update-organization", "iss", "--unauthorize", "中央研究院統計科學研究所"])
        XCTAssertNotEqual(withdraw.status, 0, withdraw.output)
        XCTAssertEqual(Set(try org().authorized), ["Institute of Statistical Science", "中央研究院統計科學研究所"], "零寫入")
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
        // 只有空白項與沒給是同一件事（R1 verify 第 13／16／26／28 列：MCP 面同一句話曾走完寫檔）
        let blank = try run(["update-organization", "iss", "--authorize", " "], library: nowhere)
        XCTAssertEqual(blank.status, 64, blank.output)
        XCTAssertTrue(blank.output.contains("沒有要改的"), blank.output)
    }
}
