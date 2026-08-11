import XCTest
import Foundation
@testable import AkashicCore
@testable import AkashicStoreIO

/// #231／#236 R1：**歧義段的 CLI 輸出面沒有任何測試**。
///
/// 為什麼單元測試不夠——這是 repo 已經記過一次的教訓（`OrgBootstrapCLITests` 檔頭）：
/// 「dropped 這個機制存在的唯一理由就是**使用者要看得到**，而唯一看得到的地方是 CLI
/// 輸出，所以判準必須落在 CLI 輸出上。」
///
/// #236 R1 實測重演了同一件事：把兩個 `printAmbiguities()` 開頭加 `if true { return }`
/// ——**1272 個測試全綠**。歧義偵測的 kit 層有測試、MCP 層有測試，而唯一給人看的那
/// 45 行沒有。作者把那條教訓套用到 MCP 卻沒套用到它原本被學到的地方。
///
/// 用真 binary（非直接呼叫 `run()`）：#101/#112 的沙箱紀律——`--library` 之外一律
/// 剝除 `AKASHIC_*`，否則開發機的 registry 會把測試導到真實 store。
final class ResolveAmbiguityCLITests: XCTestCase {
    private var root: URL!
    private var store: LibraryStore!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("akashic-ambig-\(UUID().uuidString)")
        store = LibraryStore(root: root, key: nil, environment: [:])
        try store.ensureLayout()
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    private func runCLI(_ args: [String]) throws -> (status: Int32, output: String) {
        try CLITestHarness.run(args + ["--library", root.path], env: [:])
    }

    private func writePerson(key: String, names: [String],
                             orcid: String? = nil, died: String? = nil) throws {
        var p = Person(key: key, names: names)
        p.orcid = orcid
        p.died = died
        try store.writePerson(p)
    }

    // MARK: - resolve-people

    /// 兩個人共用同一個名字 → **歧義段必須出現**，且帶得出定位與候選。
    func testResolvePeoplePrintsAmbiguitySection() throws {
        try writePerson(key: "amb-one", names: ["Ambi Guous"], orcid: "0000-0001-2345-6789")
        try writePerson(key: "amb-two", names: ["Ambi Guous"], died: "2001")
        try store.writeEntry(Entry(id: UUID(), citekey: "amb2020x", type: "article",
                                   title: "X", authors: [.literal("Ambi Guous")], date: "2020"))

        let r = try runCLI(["resolve-people"])
        XCTAssertEqual(r.status, 0, r.output)
        XCTAssertTrue(r.output.contains("歧義"), "歧義段必須被印出來：\n\(r.output)")
        XCTAssertTrue(r.output.contains("amb2020x"), "要能定位到 entry：\n\(r.output)")
        XCTAssertTrue(r.output.contains("amb-one") && r.output.contains("amb-two"),
                      "兩個候選都要列：\n\(r.output)")
    }

    /// **區辨欄位是這個報告的全部價值。**
    ///
    /// `names` 不具區辨力——它們之所以被比到一起，正是因為正規化後相同。真正能分辨
    /// 「兩個同名的人」（各自歸屬）與「同一人兩筆記錄」（該合併）的是外部識別碼與
    /// 時空不相容。#236 R1 實測：把區辨欄位塌成 `personKeys[0]`，1382 條測試零新增失敗。
    func testAmbiguityCarriesDiscriminators() throws {
        try writePerson(key: "amb-one", names: ["Ambi Guous"], orcid: "0000-0001-2345-6789")
        try writePerson(key: "amb-two", names: ["Ambi Guous"], died: "2001")
        try store.writeEntry(Entry(id: UUID(), citekey: "amb2020x", type: "article",
                                   title: "X", authors: [.literal("Ambi Guous")], date: "2020"))

        let r = try runCLI(["resolve-people"])
        XCTAssertTrue(r.output.contains("0000-0001-2345-6789"),
                      "orcid 是最強的區辨欄位，必須印：\n\(r.output)")
        XCTAssertTrue(r.output.contains("卒:2001"),
                      "died 能把兩人分開（時空不相容），必須印：\n\(r.output)")
        XCTAssertTrue(r.output.contains("各自歸屬") || r.output.contains("永不合併"),
                      "要說明兩種可能的處置相反，否則讀的人不知道要做什麼：\n\(r.output)")
    }

    /// 一個區辨欄位都沒有時要**明說**——否則使用者以為系統沒查，其實是查了但沒東西。
    func testAmbiguityWarnsWhenNoDiscriminatorExists() throws {
        try writePerson(key: "bare-one", names: ["Bare Name"])
        try writePerson(key: "bare-two", names: ["Bare Name"])
        try store.writeEntry(Entry(id: UUID(), citekey: "bare2020", type: "article",
                                   title: "X", authors: [.literal("Bare Name")], date: "2020"))

        let r = try runCLI(["resolve-people"])
        XCTAssertTrue(r.output.contains("無任何區辨欄位"),
                      "沒有區辨欄位是重要資訊——不能只印 key 讓人以為系統沒查：\n\(r.output)")
    }

    /// **沒有唯一候選時歧義更該被看見**——那條路徑先前直接 `return`。
    func testAmbiguityShownEvenWhenThereAreNoCandidates() throws {
        try writePerson(key: "amb-one", names: ["Ambi Guous"])
        try writePerson(key: "amb-two", names: ["Ambi Guous"])
        try store.writeEntry(Entry(id: UUID(), citekey: "amb2020x", type: "article",
                                   title: "X", authors: [.literal("Ambi Guous")], date: "2020"))

        let r = try runCLI(["resolve-people"])
        XCTAssertTrue(r.output.contains("無候選"), "前提：確實沒有唯一命中：\n\(r.output)")
        XCTAssertTrue(r.output.contains("歧義"),
                      "「無候選」之後仍必須印歧義——那正是最需要人看的時候：\n\(r.output)")
    }

    /// 沒有歧義時**不得**印歧義段（不要為了修上一條讓正常情境變吵）。
    func testNoAmbiguitySectionWhenThereIsNone() throws {
        try writePerson(key: "solo", names: ["Solo Author"])
        try store.writeEntry(Entry(id: UUID(), citekey: "solo2020", type: "article",
                                   title: "X", authors: [.literal("Solo Author")], date: "2020"))

        let r = try runCLI(["resolve-people"])
        XCTAssertEqual(r.status, 0, r.output)
        XCTAssertFalse(r.output.contains("歧義"),
                       "沒有歧義就不該出現歧義段：\n\(r.output)")
    }

    // MARK: - resolve-organizations

    /// org 側同形，且 **`holder` 必須印**——同一個 literal 可能住在 person 的
    /// affiliations，也可能住在另一個 org 的 parents（#166）。
    func testResolveOrganizationsPrintsAmbiguitySectionWithHolder() throws {
        for k in ["org-a", "org-b"] {
            var o = Organization(key: k)
            o.names = TimelineOf([TemporalValue(value: "Sinica", range: DateRange())])
            try store.writeOrganization(o)
        }
        var p = Person(key: "p-one", names: ["P One"])
        p.profile.affiliations = TimelineOf([TemporalValue(value: OrgRef.literal("Sinica"),
                                                           range: DateRange())])
        try store.writePerson(p)

        let r = try runCLI(["resolve-organizations"])
        XCTAssertEqual(r.status, 0, r.output)
        XCTAssertTrue(r.output.contains("歧義"), "org 側也必須印歧義段：\n\(r.output)")
        XCTAssertTrue(r.output.contains("person p-one"),
                      "holder 要標明是 person 還是 org：\n\(r.output)")
        XCTAssertTrue(r.output.contains("org-a") && r.output.contains("org-b"),
                      "兩個候選都要列：\n\(r.output)")
    }
}
