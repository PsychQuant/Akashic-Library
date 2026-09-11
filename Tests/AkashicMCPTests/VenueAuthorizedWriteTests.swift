import XCTest
@testable import AkashicCore
@testable import AkashicMCPKit
@testable import AkashicStoreIO

/// `authorized` 的寫入面（#554）——#471 修了 `variant` 那一半，這是另一半。
///
/// 在此之前 venue 的 `authorized` **沒有判定型寫入面**：唯一的寫入者是 `VenueBootstrap`
/// 的 `authorized: [c.names[0]]`（建檔時取第一個名字）。實測全部是那個形狀——立案時
/// 479/479（494 筆 venue，#553 合併前）、#553 併掉 9 組後 470/470（485 筆）；兩個數字
/// 是同一件事在兩個時點，不是「9 筆非拉丁 authorized」（R1 verify 第 6 列抓到並列不註）。
/// #553 的攣生合併會把被併記錄的 authorized 降成倖存者的 variant，而**沒有面能改回來**
/// ——本面是那個降級在 A 這一個名字上的逆操作（不是「精確」逆操作：#553 改一個名字的
/// 分類，`authorize A` 改兩個——A 升、同書寫系統的 S 被移出）。
///
/// 形狀照 `VenueVariantWriteTests`——**但語意不是 append，這是端到端測出來的**：
/// `AuthorizedNames.validate` 對 authorized 有「每書寫系統至多一個」的內容約束，實測
/// 470 筆 venue 已有一個 latin authorized（bootstrap 的機械值），append 第二個必被擋。
/// 要換掉那個機械值需要**替換**：X 成為對外形、同一個 `WritingSystem` 的舊指定 Y
/// **移出 authorized、留在 names、不標 variant**（R1 verify D1，使用者 2026-09-12 裁決）
/// ——呼叫端只說了「X 是對外形」，程式不替它多說一句「Y 是異寫」；`venue-entity` spec
/// 的未標就是那個「不作任何宣稱」的誠實狀態。所以參數叫 `authorize` 不叫 `add_authorized`
/// ——叫 add 會說謊。不同 `WritingSystem`（han／latn／other）之間仍是 append。
/// 「不重造互斥檢查」的立場不變；**同一次呼叫兩個同 `WritingSystem` 的名字是輸入矛盾**
/// （R1 verify 第 1 列：迴圈會讓陣列順序決勝），在入口整批拒絕。
final class VenueAuthorizedWriteTests: XCTestCase {
    private var root: URL!
    private var service: AkashicService!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("akashic-vaw-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("entities"), withIntermediateDirectories: true)
        try StoreVersion.write(root: root, format: StoreVersion.supported)
        service = AkashicService(root: root)
        // **`addVenue` 不寫 authorized**（實測：本測試第一版假設它照 `VenueBootstrap`
        // 的慣例寫 `[names[0]]`，紅在 `[]`）。兩個建檔面對 authorized 的處置不同：
        // bootstrap 機械取第一個名字、`addVenue` 留空（#227 的「建檔不機械偽造」語意）。
        // 所以 479/479 筆 `[names[0]]` 全來自 bootstrap——那正是 #554 的立案事實。
        // 這裡刻意給 WoS 全大寫形，讓「補正式對外形」是本測試的自然動作。
        _ = try service.addVenue(key: "some-journal", names: ["PSYCHOMETRIKA"],
                                 type: "periodical", note: nil, issn: nil)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    private func venue() throws -> Venue {
        try XCTUnwrap(LibraryStore(root: root).load().venues.first { $0.key == "some-journal" })
    }

    /// 不在 `names` 的一併 append 進 `names`——兩個分割都是對 names 的標記，標一個 names
    /// 沒有的字串會造出孤兒，而孤兒 authorized 自始是 error（寫不進去）。
    func testAddAuthorizedAlsoAppendsToNames() throws {
        _ = try service.updateVenue(key: "some-journal", addNames: nil, note: nil, type: nil,
                                    authorize: ["Psychometrika"])
        let v = try venue()
        XCTAssertEqual(v.names.entries.map(\.value), ["PSYCHOMETRIKA", "Psychometrika"])
        XCTAssertTrue(v.authorized.contains("Psychometrika"), "authorized 沒有加上：\(v.authorized)")
    }

    /// 冪等：同一個名字指定兩次不會變成兩筆、names 也不重複 append。（不是 append 語意
    /// ——是替換語意下「X 已是對外形」的 no-op；R1 verify 第 7 列抓到本註解寫反。）
    func testAddAuthorizedIsIdempotent() throws {
        for _ in 0..<2 {
            _ = try service.updateVenue(key: "some-journal", addNames: nil, note: nil, type: nil,
                                        authorize: ["Psychometrika"])
        }
        let v = try venue()
        XCTAssertEqual(v.authorized.filter { $0 == "Psychometrika" }.count, 1)
        XCTAssertEqual(v.names.entries.count, 2, "names 也不得重複 append")
    }

    /// 同一次呼叫把同一個字串送進兩個分割要整個拒絕、零寫入。**擋它的是入口的輸入驗證**
    /// （`ServiceError.invalid`「兩句矛盾的話」），**不是** `Venue.validate()`——logic 席
    /// 追過：沒有入口檢查時 authorize 段會把 X 從 variant 拉回、`validateDisjointPartitions`
    /// 找不到交集、寫入**成功**。所以本測試釘的是那道入口檢查（負控：拿掉它就紅）。
    /// 分割互斥本身仍由 `Venue.validate()` 擋、寫入面不重造（#471），那是另一件事——
    /// `VenueVariantWriteTests.testMarkingAnAuthorizedNameAsVariantIsRefused` 釘的才是它。
    func testSameStringToBothPartitionsIsRefused() throws {
        XCTAssertThrowsError(try service.updateVenue(key: "some-journal", addNames: nil,
                                                     note: nil, type: nil,
                                                     addVariant: ["Psychometrika"],
                                                     authorize: ["Psychometrika"]))
        let v = try venue()
        XCTAssertFalse(v.variant.contains("Psychometrika"), "拒絕後 variant 不得有它：\(v.variant)")
        XCTAssertFalse(v.authorized.contains("Psychometrika"), "拒絕後 authorized 不得有它：\(v.authorized)")
        XCTAssertEqual(v.names.entries.count, 1, "拒絕後 names 也不得動")
    }

    /// **同書寫系統替換——本面存在的理由。** bootstrap 給的是 WoS 全大寫形，`--authorize`
    /// 正式刊名之後：正式刊名成為 authorized、全大寫形**移出 authorized、留在 names、
    /// 不進 variant**（D1：程式不替呼叫端判定「它是異寫」），報告兩個都印。
    func testAuthorizeReplacesSameScriptAndLeavesTheOldUnclassified() throws {
        var v = try venue()
        v.authorized = ["PSYCHOMETRIKA"]              // 模擬 bootstrap 的機械值
        try LibraryStore(root: root).writeVenue(v)

        let out = try service.updateVenue(key: "some-journal", addNames: nil, note: nil, type: nil,
                                          authorize: ["Psychometrika"])
        let after = try venue()
        XCTAssertEqual(after.authorized, ["Psychometrika"], "latin 只能有一個，且是新的那個")
        XCTAssertEqual(after.variant, [], "舊指定不進 variant——那是程式替人多說的一句話")
        XCTAssertEqual(after.names.entries.map(\.value), ["PSYCHOMETRIKA", "Psychometrika"],
                       "舊指定留在 names，不刪")
        XCTAssertTrue(out.contains("\"authorizedRemoved\"") && out.contains("PSYCHOMETRIKA"),
                      "報告要說出誰被移出 authorized：\(out)")
        XCTAssertTrue(out.contains("\"authorizedAdded\""), "delta 鍵與兄弟鍵同型 *Added：\(out)")
        XCTAssertFalse(out.contains("demotedToVariant"), "R1 的鍵名說謊（沒有東西進 variant）：\(out)")
    }

    /// **#553 降級的逆操作**：一個被合併降成 variant 的名字，`authorize` 它要從 variant
    /// 移出、進 authorized——一個名字不能同時在兩個分割。
    func testAuthorizeLiftsANameOutOfVariant() throws {
        var v = try venue()
        v.authorized = ["PSYCHOMETRIKA"]
        v.names = Timeline(v.names.entries + [TemporalValue(value: "Psychometrika")])
        v.variant = ["Psychometrika"]                  // 被 #553 降過去的
        try LibraryStore(root: root).writeVenue(v)

        let out = try service.updateVenue(key: "some-journal", addNames: nil, note: nil, type: nil,
                                          authorize: ["Psychometrika"])
        let after = try venue()
        XCTAssertEqual(after.authorized, ["Psychometrika"])
        XCTAssertEqual(after.variant, [], "新的從 variant 升上去；舊的移出 authorized 後未標，不對調進 variant")
        XCTAssertTrue(out.contains("\"liftedFromVariant\"") && out.contains("Psychometrika"),
                      "variant → authorized 是本面的主要用途，報告要看得出它原本是 variant：\(out)")
    }

    /// **跨書寫系統是 append**：已有 latin authorized 時加一個中文刊名，兩個都在。
    func testAuthorizeAcrossScriptsAppends() throws {
        var v = try venue()
        v.authorized = ["PSYCHOMETRIKA"]
        try LibraryStore(root: root).writeVenue(v)

        _ = try service.updateVenue(key: "some-journal", addNames: nil, note: nil, type: nil,
                                    authorize: ["心理計量學"])
        let after = try venue()
        XCTAssertEqual(Set(after.authorized), ["PSYCHOMETRIKA", "心理計量學"])
        XCTAssertEqual(after.variant, [], "跨書寫系統沒有東西被降級")
    }

    /// 空白字串跳過（同 addNames／addVariant）。
    func testSkipsBlankStrings() throws {
        _ = try service.updateVenue(key: "some-journal", addNames: nil, note: nil, type: nil,
                                    authorize: ["  ", ""])
        let v = try venue()
        XCTAssertEqual(v.authorized, [], "addVenue 不寫 authorized，空白字串也不得寫")
        XCTAssertEqual(v.names.entries.count, 1)
    }

    /// **同一次呼叫兩個同 `WritingSystem` 的名字是輸入矛盾，整批拒絕零寫入**（R1 verify
    /// 第 1 列，四席各自在真 binary 重現）：迴圈逐一處理時第 N+1 輪會把第 N 輪剛升上去的
    /// 當舊指定移出——陣列順序決勝，而 `validateWritingSystems` 對這個形狀的既有裁決是
    /// 「未決的問題，不是指定；請選一個」。與 add_variant／authorize 矛盾檢查同型的輸入驗證。
    func testTwoSameScriptNamesInOneCallAreRefused() throws {
        var v = try venue()
        v.authorized = ["PSYCHOMETRIKA"]
        try LibraryStore(root: root).writeVenue(v)

        XCTAssertThrowsError(try service.updateVenue(key: "some-journal", addNames: nil, note: nil,
                                                     type: nil,
                                                     authorize: ["Psychometrika", "Psychometrica"])) {
            let msg = ($0 as? LocalizedError)?.errorDescription ?? "\($0)"
            XCTAssertTrue(msg.contains("請選一個"), "訊息要沿用 validateWritingSystems 的裁決：\(msg)")
        }
        let after = try venue()
        XCTAssertEqual(after.authorized, ["PSYCHOMETRIKA"], "零寫入")
        XCTAssertEqual(after.names.entries.count, 1, "零寫入——names 也不得動")
    }

    /// **沿革前身不會被本面堵死**（R1 verify 第 3 列 DA 實測：R1 把舊指定降成 variant，而
    /// variant 不得帶時間欄位，於是 `--authorize` 後繼刊名整個被拒且無出路）。D1 之後舊指定
    /// 只是移出 authorized、留在 names——它的時間欄位原封不動。
    func testDemotedDatedPredecessorKeepsItsDates() throws {
        var v = try venue()
        v.names = Timeline([TemporalValue(value: "PSYCHOMETRIKA",
                                          range: DateRange(start: "1936", end: "1999"))])
        v.authorized = ["PSYCHOMETRIKA"]
        try LibraryStore(root: root).writeVenue(v)

        _ = try service.updateVenue(key: "some-journal", addNames: nil, note: nil, type: nil,
                                    authorize: ["Psychometrika"])
        let after = try venue()
        XCTAssertEqual(after.authorized, ["Psychometrika"])
        let old = try XCTUnwrap(after.names.entries.first { $0.value == "PSYCHOMETRIKA" })
        XCTAssertEqual(old.range.start, "1936")
        XCTAssertEqual(old.range.end, "1999")
        XCTAssertEqual(after.variant, [], "帶時間的名字不能是 variant，本面也不會試著把它標成 variant")
    }

    /// 確認既有的對外形是 no-op，但報告要說出「它已經是」——與「空白被跳過」的報告形狀
    /// 分得開（R1 verify 第 10 列）。留 judgement 的義務另裁（#564），本面不寫記錄。
    func testConfirmingTheExistingAuthorizedIsReportedNotSilent() throws {
        var v = try venue()
        v.authorized = ["PSYCHOMETRIKA"]
        try LibraryStore(root: root).writeVenue(v)

        let out = try service.updateVenue(key: "some-journal", addNames: nil, note: nil, type: nil,
                                          authorize: ["PSYCHOMETRIKA"])
        XCTAssertTrue(out.contains("\"alreadyAuthorized\"") && out.contains("PSYCHOMETRIKA"), out)
        XCTAssertEqual(try venue().authorized, ["PSYCHOMETRIKA"])
    }

    /// 空白在兩個參數裡都是「沒說話」，不是矛盾（R1 verify 第 11 列：矛盾檢查曾跑在空白
    /// 過濾之前，`add_variant [" "]` + `authorize [" "]` 被當成兩句矛盾的話拒絕）。
    func testBlankInBothParametersIsNotAContradiction() throws {
        XCTAssertNoThrow(try service.updateVenue(key: "some-journal", addNames: nil, note: nil,
                                                 type: nil, addVariant: [" "], authorize: [" "]))
        XCTAssertEqual(try venue().names.entries.count, 1, "零寫入")
    }

    /// 呼叫端**自己**在同一次呼叫說了兩句話——`add_variant Y` 與 `authorize X`——那 Y 進
    /// variant 是呼叫端說的，不是程式替它說的；報告兩個事實各印一次（`variantAdded` 與
    /// `authorizedRemoved` 是兩件不同的事，不是同一件事印兩次）。
    func testCallerMayDemoteIntoVariantExplicitlyInTheSameCall() throws {
        var v = try venue()
        v.authorized = ["PSYCHOMETRIKA"]
        try LibraryStore(root: root).writeVenue(v)

        let out = try service.updateVenue(key: "some-journal", addNames: nil, note: nil, type: nil,
                                          addVariant: ["PSYCHOMETRIKA"], authorize: ["Psychometrika"])
        let after = try venue()
        XCTAssertEqual(after.authorized, ["Psychometrika"])
        XCTAssertEqual(after.variant, ["PSYCHOMETRIKA"], "這次是呼叫端明說的")
        XCTAssertTrue(out.contains("\"variantAdded\"") && out.contains("\"authorizedRemoved\""), out)
    }
}
