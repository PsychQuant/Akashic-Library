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
        var p = Person(key: key, names: PersonNames(variant: names))
        p.orcid = orcid
        p.died = died
        try store.writePerson(p)
    }

    // MARK: - resolve-people

    /// 兩個人共用同一個名字 → **歧義段必須出現**，且帶得出定位與候選。
    func testResolvePeoplePrintsAmbiguitySection() throws {
        try writePerson(key: "amb-one", names: ["Ambi Guous"], orcid: "0000-0001-2345-6789")
        try writePerson(key: "amb-two", names: ["Ambi Guous"], died: "2001")
        try store.writeEntry(Entry(id: UUID(), citekey: "amb2020x", type: .periodicalArticle,
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
    /// 時空不相容。#236 R1 實測：把區辨欄位塌成 `personKeys[0]`，零新增失敗。
    ///
    /// 那次的條數（1382）來自 **verify 席的工作樹**，含當時尚未併入本分支的工作，
    /// 與此處 `swift test` 的條數對不上——記在這裡是為了不讓後人以為那個數字應該
    /// 重現得出來。該變異**現在會被本檔抓到**（這些測試正是為此而加），所以它是
    /// 一次不可重測的歷史量測，不是可驗證的現況。
    func testAmbiguityCarriesDiscriminators() throws {
        try writePerson(key: "amb-one", names: ["Ambi Guous"], orcid: "0000-0001-2345-6789")
        try writePerson(key: "amb-two", names: ["Ambi Guous"], died: "2001")
        try store.writeEntry(Entry(id: UUID(), citekey: "amb2020x", type: .periodicalArticle,
                                   title: "X", authors: [.literal("Ambi Guous")], date: "2020"))

        let r = try runCLI(["resolve-people"])
        XCTAssertTrue(r.output.contains("0000-0001-2345-6789"),
                      "orcid 是最強的區辨欄位，必須印：\n\(r.output)")
        XCTAssertTrue(r.output.contains("卒:2001"),
                      "died 能把兩人分開（時空不相容），必須印：\n\(r.output)")
        XCTAssertTrue(r.output.contains("各自歸屬") || r.output.contains("永不合併"),
                      "要說明兩種可能的處置相反，否則讀的人不知道要做什麼：\n\(r.output)")
    }

    /// **列數上限擋不住內容**（#236 R4）。
    ///
    /// R2 給 CLI 加了列數與 ref 兩軸，都是**計數**。席位用真 binary 實測：兩軸都在的
    /// 情況下仍產出 **3,844,596 bytes**——`literal`／`key`／隸屬名各自吃滿自己的
    /// `max:`，再被 `displaySafe` 膨脹 8 倍。
    ///
    /// **必須用會膨脹的字元**：純 ASCII 不會膨脹（`displaySafe` 只逃脫 C0/C1/LS/PS/
    /// bidi/BOM/反斜線），用 `"x"` 建出來的 store 量到的數字對這條斷言毫無約束——
    /// 那是本檔 R3 踩過的坑。
    func testAmbiguitySectionIsByteBounded() throws {
        // **每列的 ref 數也要吃滿**（上限 20）：第一版只給每個名字 2 個人，無預算時
        // 只到 153,837 bytes，於是 256 KB 的斷言在變異下仍是綠的——那個界什麼都沒約束。
        // 席位的 3.8 MB 來自「列數 × 每列 ref 數 × 每個 ref 的區辨欄位」三者相乘。
        let long = String(repeating: "\u{202E}", count: 200)
        for i in 0..<20 {
            let nm = "\(long)-flood-\(i)"
            for s in 0..<20 {
                var p = Person(key: "flood-\(i)-\(s)",
                               names: PersonNames(variant: (0..<4).map { "\(long)-\(i)-\(s)-\($0)" }))
                p.names.variant.append(nm)                       // 撞在一起的那個名字
                try store.writePerson(p)
            }
            try store.writeEntry(Entry(id: UUID(), citekey: "flood\(i)", type: .periodicalArticle,
                                       title: "T", authors: [.literal(nm)], date: "2020"))
        }

        let r = try runCLI(["resolve-people"])
        XCTAssertEqual(r.status, 0, String(r.output.prefix(400)))
        // 界貼著預算（128 KB）+ 表頭表尾，不是隨手挑一個大數字——寬鬆的界會讓
        // 這條斷言在「預算被拿掉」時仍然綠（第一版就是這樣）。
        XCTAssertLessThan(r.output.utf8.count, 140 * 1024,
                          "歧義段必須有位元組界——席位實測未設限時 3,844,596 bytes。"
                          + "實際 \(r.output.utf8.count) bytes")
        // 前提：這個 store 真的撐爆了預算，否則上面那條斷言什麼都沒約束到
        XCTAssertTrue(r.output.contains("吃不下輸出預算"),
                      "被預算擋掉時要明說，而且要與『超過列數上限』分開講：\n"
                      + String(r.output.suffix(400)))
    }

    /// 異名被截斷時要**數出來**（#236 R4）。
    ///
    /// 先前是 `prefix(4)` 靜默截斷：「只有四個異名」與「有七個、你看到四個」在終端上
    /// 逐位元組相同。在歧義判斷裡特別糟——使用者正是要靠異名分辨兩個同名的人，
    /// 而被藏起來的那三個可能就是決定性的。
    func testAmbiguityCountsDroppedAliases() throws {
        try writePerson(key: "alias-one",
                        names: ["Alias Same", "A1", "A2", "A3", "A4", "A5", "A6"])
        try writePerson(key: "alias-two", names: ["Alias Same", "B1"])
        try store.writeEntry(Entry(id: UUID(), citekey: "alias2020", type: .periodicalArticle,
                                   title: "X", authors: [.literal("Alias Same")], date: "2020"))

        let r = try runCLI(["resolve-people"])
        XCTAssertEqual(r.status, 0, r.output)
        XCTAssertTrue(r.output.contains("…+3"),
                      "七個異名只印四個 → 要說出還有 3 個：\n\(r.output)")
        XCTAssertFalse(r.output.contains("…+0"),
                       "沒丟就不要印——「沒丟」與「丟了 0 個」不該變成兩件事：\n\(r.output)")
        // 只印前四個的證據：第五個之後不得出現（否則 `…+3` 是對的但截斷沒發生）
        XCTAssertFalse(r.output.contains("A5"),
                       "超出上限的異名不應出現：\n\(r.output)")
    }

    /// 一個區辨欄位都沒有時要**明說**——否則使用者以為系統沒查，其實是查了但沒東西。
    func testAmbiguityWarnsWhenNoDiscriminatorExists() throws {
        try writePerson(key: "bare-one", names: ["Bare Name"])
        try writePerson(key: "bare-two", names: ["Bare Name"])
        try store.writeEntry(Entry(id: UUID(), citekey: "bare2020", type: .periodicalArticle,
                                   title: "X", authors: [.literal("Bare Name")], date: "2020"))

        let r = try runCLI(["resolve-people"])
        XCTAssertTrue(r.output.contains("無任何區辨欄位"),
                      "沒有區辨欄位是重要資訊——不能只印 key 讓人以為系統沒查：\n\(r.output)")
    }

    /// **沒有唯一候選時歧義更該被看見**——那條路徑先前直接 `return`。
    func testAmbiguityShownEvenWhenThereAreNoCandidates() throws {
        try writePerson(key: "amb-one", names: ["Ambi Guous"])
        try writePerson(key: "amb-two", names: ["Ambi Guous"])
        try store.writeEntry(Entry(id: UUID(), citekey: "amb2020x", type: .periodicalArticle,
                                   title: "X", authors: [.literal("Ambi Guous")], date: "2020"))

        let r = try runCLI(["resolve-people"])
        XCTAssertTrue(r.output.contains("無候選"), "前提：確實沒有唯一命中：\n\(r.output)")
        XCTAssertTrue(r.output.contains("歧義"),
                      "「無候選」之後仍必須印歧義——那正是最需要人看的時候：\n\(r.output)")
    }

    /// 沒有歧義時**不得**印歧義段（不要為了修上一條讓正常情境變吵）。
    func testNoAmbiguitySectionWhenThereIsNone() throws {
        try writePerson(key: "solo", names: ["Solo Author"])
        try store.writeEntry(Entry(id: UUID(), citekey: "solo2020", type: .periodicalArticle,
                                   title: "X", authors: [.literal("Solo Author")], date: "2020"))

        let r = try runCLI(["resolve-people"])
        XCTAssertEqual(r.status, 0, r.output)
        XCTAssertFalse(r.output.contains("歧義"),
                       "沒有歧義就不該出現歧義段：\n\(r.output)")
    }

    // MARK: - resolve-organizations

    /// org 側同形，且 **`holder` 必須印**——同一個 literal 可能住在 person 的
    /// affiliations，也可能住在另一個 org 的 parents（#166）。
    /// org 側的位元組界（#236 R4：席位實測未設限時 447,377 bytes）。
    ///
    /// 分開寫而不是「相信 person 側測過了」——席位同一輪抓到「org 側的歧義顯示整片
    /// 零覆蓋：四項一起拿掉，1295 條全綠」。同型的兩個面各自需要自己的守衛。
    func testOrgAmbiguitySectionIsByteBounded() throws {
        let long = String(repeating: "\u{202E}", count: 200)
        for i in 0..<20 {
            let nm = "\(long)-org-\(i)"
            for s in 0..<20 {
                var o = Organization(key: "flood-org-\(i)-\(s)")
                o.names = TimelineOf([TemporalValue(value: nm, range: DateRange())])
                try store.writeOrganization(o)
            }
            var p = Person(key: "holder-\(i)", names: ["Holder \(i)"])
            p.profile.affiliations = TimelineOf([
                TemporalValue(value: OrgRef.literal(nm), range: DateRange())
            ])
            try store.writePerson(p)
        }

        let r = try runCLI(["resolve-organizations"])
        XCTAssertEqual(r.status, 0, String(r.output.prefix(400)))
        XCTAssertLessThan(r.output.utf8.count, 140 * 1024,
                          "org 側同樣要有位元組界。實際 \(r.output.utf8.count) bytes")
        XCTAssertTrue(r.output.contains("吃不下輸出預算"),
                      "前提：這個 store 真的撐爆預算，否則上面那條沒約束到東西：\n"
                      + String(r.output.suffix(300)))
    }

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

    /// **有候選時也要印歧義。** #236 R2：這兩個呼叫點零覆蓋——刪掉它們，整套測試
    /// 逐字不變。先前的測試只涵蓋「無候選」分支，於是突變驗證只證明了**我測到的
    /// 那條路徑**有守衛，沒證明所有路徑都有。
    ///
    /// （原文寫「1389 條」，同上一則的理由：那是 verify 席工作樹的條數，不是本分支的。）
    func testAmbiguityShownAlongsideCandidates() throws {
        try writePerson(key: "solo", names: ["Solo Author"])          // 會出候選
        try writePerson(key: "amb-one", names: ["Ambi Guous"])
        try writePerson(key: "amb-two", names: ["Ambi Guous"])
        try store.writeEntry(Entry(id: UUID(), citekey: "both2020", type: .periodicalArticle, title: "X",
                                   authors: [.literal("Solo Author"), .literal("Ambi Guous")],
                                   date: "2020"))

        let r = try runCLI(["resolve-people"])
        XCTAssertEqual(r.status, 0, r.output)
        XCTAssertTrue(r.output.contains("solo"), "前提：確實有唯一候選：\n\(r.output)")
        XCTAssertTrue(r.output.contains("歧義"),
                      "**有候選時也必須印歧義**——這條分支先前零覆蓋：\n\(r.output)")
        XCTAssertTrue(r.output.contains("amb-one") && r.output.contains("amb-two"), r.output)
    }

    /// `entryID` 要印在 **CLI** 上。重複 citekey 是被支援的損壞態，此時兩筆歧義在
    /// `(citekey, authorIndex)` 上逐位元組相同——MCP 帶了 entryID，CLI 先前沒帶，
    /// 而 CLI 才是人真正在讀的面（#236 R2）。
    func testAmbiguityPrintsEntryIdentity() throws {
        try writePerson(key: "amb-one", names: ["Ambi Guous"])
        try writePerson(key: "amb-two", names: ["Ambi Guous"])
        try store.writeEntry(Entry(id: UUID(), citekey: "amb2020x", type: .periodicalArticle,
                                   title: "X", authors: [.literal("Ambi Guous")], date: "2020"))
        let r = try runCLI(["resolve-people"])
        XCTAssertTrue(r.output.contains("entry:"),
                      "要印 entry 身分，否則重複 citekey 下兩筆報告無法區分：\n\(r.output)")
    }

    /// CLI **也要有上限**——先前只給 MCP 加。而且截斷要說出來。
    func testAmbiguityListIsCappedAndSaysSo() throws {
        try writePerson(key: "many-one", names: ["Many Same"])
        try writePerson(key: "many-two", names: ["Many Same"])
        for i in 0..<60 {
            try store.writeEntry(Entry(id: UUID(), citekey: "many\(i)", type: .periodicalArticle,
                                       title: "T", authors: [.literal("Many Same")], date: "2020"))
        }
        let r = try runCLI(["resolve-people"])
        XCTAssertTrue(r.output.contains("以下顯示前 50 筆"), "要說明只顯示了一部分：\n\(r.output)")
        XCTAssertTrue(r.output.contains("另 10 筆未顯示"),
                      "剩餘筆數要說出來——靜默截斷讓「沒有更多」與「沒給你更多」無法區分：\n\(r.output)")
    }

    /// org 側的 range 必須表示**四個**欄位。只讀 (start,end) 會把 `endedUnknown`
    /// （#63：已結束、時點未知）印成進行中——**已離職與現職逐位元組相同**。
    /// repo 對這個塌縮有明文事故紀錄（#63／#70 存在的理由）。
    func testOrgAmbiguityRangeShowsEndedUnknown() throws {
        for k in ["org-a", "org-b"] {
            var o = Organization(key: k)
            o.names = TimelineOf([TemporalValue(value: "Sinica", range: DateRange())])
            try store.writeOrganization(o)
        }
        var p = Person(key: "p-one", names: ["P One"])
        p.profile.affiliations = TimelineOf([TemporalValue(
            value: OrgRef.literal("Sinica"),
            range: DateRange(start: "2001", end: nil, endedUnknown: true))])
        try store.writePerson(p)

        let r = try runCLI(["resolve-organizations"])
        XCTAssertTrue(r.output.contains("已結束"),
                      "endedUnknown 必須顯示——否則已離職印得跟現職一樣：\n\(r.output)")
    }

    /// #236 R3 mutation (iv) 存活：`rangeLabel` 的 `attested` 分支（#70）零覆蓋。
    func testOrgAmbiguityRangeShowsAttestedPoints() throws {
        for k in ["org-a", "org-b"] {
            var o = Organization(key: k)
            o.names = TimelineOf([TemporalValue(value: "Sinica", range: DateRange())])
            try store.writeOrganization(o)
        }
        var p = Person(key: "p-one", names: ["P One"])
        p.profile.affiliations = TimelineOf([TemporalValue(
            value: OrgRef.literal("Sinica"),
            range: DateRange(attested: ["2011", "2014"]))])
        try store.writePerson(p)

        let r = try runCLI(["resolve-organizations"])
        XCTAssertTrue(r.output.contains("觀測:"),
                      "attested（#70：只有觀測點、起訖皆不明）必須顯示：\n\(r.output)")
        XCTAssertTrue(r.output.contains("2011"), r.output)
    }

    /// #236 R3 mutation (v) 存活：「曾隸屬」回退零覆蓋。
    ///
    /// 只有已結束隸屬的人，先前會被判成「⚠ 無任何區辨欄位」——**而那是假的**。
    func testFormerAffiliationIsShownWhenThereIsNoCurrentOne() throws {
        var one = Person(key: "past-one", names: ["Past Same"])
        one.profile.affiliations = TimelineOf([TemporalValue(
            value: OrgRef.literal("Old Institute"),
            range: DateRange(start: "1990", end: "1995"))])
        try store.writePerson(one)
        try writePerson(key: "past-two", names: ["Past Same"], orcid: "0000-0003-0000-0000")
        try store.writeEntry(Entry(id: UUID(), citekey: "past2020", type: .periodicalArticle,
                                   title: "X", authors: [.literal("Past Same")], date: "2020"))

        let r = try runCLI(["resolve-people"])
        XCTAssertTrue(r.output.contains("曾隸屬:Old Institute"),
                      "沒有現職時要顯示最近結束的隸屬：\n\(r.output)")
        XCTAssertFalse(r.output.contains("past-one") && r.output.contains("無任何區辨欄位"),
                       "有已結束隸屬就不是「無任何區辨欄位」：\n\(r.output)")
    }

    /// #236 R3：兩個 key 在 `displaySafe` 後可能印得**逐位元組相同**（截斷）。
    /// 列內序號讓人至少知道那是兩筆不同的記錄，而不是同一人被列了兩次。
    func testAmbiguityRowsAreNumberedSoCollidingKeysStayDistinct() throws {
        let prefix = String(repeating: "q", count: 200)
        try writePerson(key: prefix + "b", names: ["Collide Me"])
        try writePerson(key: prefix + "c", names: ["Collide Me"])
        try store.writeEntry(Entry(id: UUID(), citekey: "coll2020", type: .periodicalArticle,
                                   title: "X", authors: [.literal("Collide Me")], date: "2020"))
        let r = try runCLI(["resolve-people"])
        XCTAssertTrue(r.output.contains("1. ") && r.output.contains("2. "),
                      "列內要編號——兩個 key 截斷後可能長得一樣：\n\(r.output)")
    }
}
