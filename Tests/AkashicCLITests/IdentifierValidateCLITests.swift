import XCTest
@testable import AkashicCore
@testable import AkashicStoreIO
@testable import akashic

/// #394 task 4.3 的**驗證目標本身**：「對含 `0003-066x` 的暫時 store 執行 validate，
/// 斷言輸出含該值」。
///
/// **為什麼型別層的測試不夠。** `IdentifierCodecTests` 驗的是 `Venue.validate()` 回傳
/// 那則 diagnostic；本檔驗它**走得到 CLI 的輸出**。這兩件事會分開，而且真的分開過：
/// 同一輪實測發現 `Venue.validate()` 在全樹**零呼叫端**——`StoreHealth.perRecordIssues`
/// 收 entry／person／library／organization／divergence 五族，venue 不在裡面（#416 抽取
/// 那一族時的封閉列舉就漏了它）。也就是說在本輪之前，venue 的 key 格式錯誤、authorized
/// 與 names 不符、未知欄位警告**全部沒有任何讀取面看得到**。
///
/// 這正是 `entity-backlink-completeness` 執行細節 2 記過的形狀：一個 entity kind 在讀取
/// 面沒有路徑，而缺席不會有任何跡象。型別層的斷言對這種缺口是盲的——它會全綠。
final class IdentifierValidateCLITests: XCTestCase {
    var root: URL!
    var fakeHome: URL!

    private var env: [String: String] { ["AKASHIC_HOME": fakeHome.path] }

    private func cli(_ args: [String]) throws -> (status: Int32, output: String) {
        try CLITestHarness.run(args + ["--library", root.path], env: env)
    }

    override func setUpWithError() throws {
        fakeHome = FileManager.default.temporaryDirectory
            .appendingPathComponent("akashic-home-\(UUID().uuidString)")
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("akashic-idvalidate-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: fakeHome, withIntermediateDirectories: true)
        let store = LibraryStore(root: root)
        try store.ensureLayout()
    }


    /// 造一筆**遷移前**的 venue 記錄：磁碟上帶非正規形的 ISSN。
    ///
    /// **不能用 `writeVenue` 直接寫非正規值**——寫入面會正規化（那正是本 change 的
    /// 決策），所以經由它寫出去的檔案永遠是正規形。第一版測試就是這樣寫的，於是它
    /// 斷言的東西在結構上不可能發生。非正規形只存在於**遷移前既有的**記錄裡，所以
    /// 這裡先正常寫一筆、再改寫磁碟上的那一行，模擬那個狀態。
    @discardableResult
    private func writeLegacyVenue(key: String, rawISSN: String) throws -> URL {
        var v = Venue(key: key, type: .periodical)
        v.issn = [try XCTUnwrap(ISSN(rawISSN))]
        let url = try LibraryStore(root: root).writeVenue(v)
        let normalized = try XCTUnwrap(ISSN(rawISSN)).normalized
        let text = try String(contentsOf: url, encoding: .utf8)
            .replacingOccurrences(of: normalized, with: rawISSN)
        try text.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
        try? FileManager.default.removeItem(at: fakeHome)
    }

    /// 非正規形的 ISSN 要出現在 `akashic validate` 的輸出裡，並具名該記錄。
    func testValidateNamesTheNonNormalISSNAndItsRecord() throws {
        try writeLegacyVenue(key: "american-psychologist", rawISSN: "0003-066x")

        let r = try cli(["validate"])
        XCTAssertTrue(r.output.contains("0003-066x"),
                      "validate 必須具名該值（surfaced，不是靜默）：\(r.output)")
        XCTAssertTrue(r.output.contains("american-psychologist"),
                      "validate 必須具名該記錄，否則使用者不知道去哪改：\(r.output)")
    }

    /// 非正規形是 warning，**不得**讓 validate 非零退出——它不是腐爛，遷移會修它。
    /// （`validate` 的契約：quarantine 或 error 才非零退出。）
    func testNonNormalIdentifierDoesNotFailTheExitCode() throws {
        try writeLegacyVenue(key: "american-psychologist", rawISSN: "0003-066x")

        XCTAssertEqual(try cli(["validate"]).status, 0,
                       "warning 不得改變退出碼——否則遷移前整個 store 都無法通過 CI")
    }

    /// 正規形的 store 不出聲——沒有這一條，上面兩條可以靠「validate 永遠印一堆東西」通過。
    func testANormalStoreSaysNothingAboutIdentifiers() throws {
        var v = Venue(key: "american-psychologist", type: .periodical)
        v.issn = [try XCTUnwrap(ISSN("0003-066X"))]
        _ = try LibraryStore(root: root).writeVenue(v)

        let r = try cli(["validate"])
        XCTAssertFalse(r.output.contains("不是正規形"),
                       "正規形不得產生 diagnostic：\(r.output)")
    }
}
