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
///
/// **相等走 `NameIdentity.canonical`，與 store 守衛同一條**（R2 verify 第 1 列，五路獨立命中）：
/// R2 之前入口用精確 `String ==`，而 D1 讓被換下來的舊名留在未標——`Venue.validate()` 對
/// names **沒有** near-duplicate 檢查，於是 `--authorize "Psychometrika "`（尾隨空白）對既有
/// authorized `[Psychometrika]` **寫入成功**：帶空白的字串進 names、真名被移出、帶空白版成為
/// displayName。R1 report 寫的「fail-closed」是 D1 之前的量測（舊名進 variant 才有交集）。
/// 現在 x 若 canonical-命中既有 names 條目就**用 store 裡那個拼法**，不新增近重複條目。
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

    // MARK: - R2 verify：相等、輸入內容、報告的決定性

    /// **近重複撞到既有 authorized 不是替換**（R2 第 1 列的 fail-open）：尾隨空白版
    /// canonical-命中既有的對外形 → 報 `alreadyAuthorized`（用 store 拼法）、names 不多一筆、
    /// authorized 不動。
    func testNearDuplicateOfTheCurrentAuthorizedIsNotAReplacement() throws {
        var v = try venue()
        v.names = Timeline(v.names.entries + [TemporalValue(value: "Psychometrika")])
        v.authorized = ["Psychometrika"]
        try LibraryStore(root: root).writeVenue(v)

        let out = try service.updateVenue(key: "some-journal", addNames: nil, note: nil, type: nil,
                                          authorize: ["Psychometrika "])
        let after = try venue()
        XCTAssertEqual(after.authorized, ["Psychometrika"], "一個打錯的空白不得換掉呼叫端自己的對外形")
        XCTAssertEqual(after.names.entries.count, 2, "不得新增近重複的 names 條目")
        XCTAssertTrue(out.contains("\"alreadyAuthorized\"") && out.contains("\"Psychometrika\""), out)
        XCTAssertFalse(out.contains("Psychometrika "), "報告要印 store 拼法，不印帶空白的輸入：\(out)")
    }

    /// 近重複命中 variant 裡的名字 → 用 store 拼法拉回 authorized，不新增條目
    /// （R2 之前這條路在守衛被以「同時出現在兩個分割」拒絕、訊息指錯地方——Codex 席）。
    func testNearDuplicateResolvesToTheStoredSpellingWhenLifting() throws {
        var v = try venue()
        v.names = Timeline(v.names.entries + [TemporalValue(value: "Psychometrika")])
        v.authorized = ["PSYCHOMETRIKA"]
        v.variant = ["Psychometrika"]
        try LibraryStore(root: root).writeVenue(v)

        let out = try service.updateVenue(key: "some-journal", addNames: nil, note: nil, type: nil,
                                          authorize: ["Psychometrika  "])
        let after = try venue()
        XCTAssertEqual(after.authorized, ["Psychometrika"])
        XCTAssertEqual(after.variant, [])
        XCTAssertEqual(after.names.entries.count, 2)
        XCTAssertTrue(out.contains("\"liftedFromVariant\"") && out.contains("\"Psychometrika\""), out)
    }

    /// 跨參數的矛盾檢查也走 canonical：`add_variant ["X "]` ＋ `authorize ["X"]` 仍是兩句矛盾的話。
    func testNearDuplicateAcrossAddVariantAndAuthorizeIsStillAContradiction() throws {
        XCTAssertThrowsError(try service.updateVenue(key: "some-journal", addNames: nil, note: nil,
                                                     type: nil, addVariant: ["Psychometrika "],
                                                     authorize: ["Psychometrika"]))
        XCTAssertEqual(try venue().names.entries.count, 1, "零寫入")
    }

    /// **控制字元與純標點不是名字**（R2 第 4 列，security 席真 binary 實測：`\r`、`\n`、LS、`—`
    /// 四次都寫進 authorized 並成為 displayName）。換行類是空白（跳過）；純標點／純數字是
    /// `.other` 且無任何字母 → 整批拒絕。西里爾、假名含字母，不受影響。
    func testControlCharactersAndPunctuationAreNotNames() throws {
        XCTAssertNoThrow(try service.updateVenue(key: "some-journal", addNames: nil, note: nil,
                                                 type: nil, authorize: ["\n", "\r", "\u{2028}"]))
        XCTAssertEqual(try venue().authorized, [], "換行類是空白，跳過、零寫入")
        for bad in ["—", "123", "…"] {
            XCTAssertThrowsError(try service.updateVenue(key: "some-journal", addNames: nil, note: nil,
                                                         type: nil, authorize: [bad]), bad) {
                let msg = ($0 as? LocalizedError)?.errorDescription ?? "\($0)"
                XCTAssertTrue(msg.contains("不是名字"), msg)
            }
        }
        XCTAssertEqual(try venue().names.entries.count, 1, "零寫入")
        XCTAssertNoThrow(try service.updateVenue(key: "some-journal", addNames: nil, note: nil,
                                                 type: nil, authorize: ["Психометрика"]),
                         "西里爾含字母，是名字")
    }

    /// 同書寫系統衝突訊息**逐桶、依 rawValue 排序**（R2 第 7 列：`Dictionary.first(where:)` 隨
    /// hash 種子挑桶，同輸入不同 process 報不同桶——照抄 `validateWritingSystems` 的作法）。
    func testAllClashingBucketsAreReportedInStableOrder() throws {
        XCTAssertThrowsError(try service.updateVenue(
            key: "some-journal", addNames: nil, note: nil, type: nil,
            authorize: ["Psychometrika", "Psychometrica", "心理計量學", "心理測量學"])) {
            let msg = ($0 as? LocalizedError)?.errorDescription ?? "\($0)"
            let han = try? XCTUnwrap(msg.range(of: "han"), "han 桶沒報：\(msg)")
            let latn = try? XCTUnwrap(msg.range(of: "latn"), "latn 桶沒報：\(msg)")
            if let h = han, let l = latn { XCTAssertLessThan(h.lowerBound, l.lowerBound, "桶要依 rawValue 排序：\(msg)") }
        }
    }

    /// 同一字串重複送只報一次（R2 第 9 列：衝突檢查用 `Set`、迴圈用原陣列，第二輪落進
    /// `alreadyAuthorized`——同一個名字被說了「這次升」與「本來就是」兩句話）。
    func testDuplicateStringInOneCallIsReportedOnce() throws {
        let out = try service.updateVenue(key: "some-journal", addNames: nil, note: nil, type: nil,
                                          authorize: ["Psychometrika", "Psychometrika"])
        let obj = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(out.utf8)) as? [String: Any])
        XCTAssertEqual(obj["authorizedAdded"] as? [String], ["Psychometrika"])
        XCTAssertEqual(obj["alreadyAuthorized"] as? [String], [], "第二個重複不是 alreadyAuthorized：\(out)")
        XCTAssertEqual(try venue().authorized, ["Psychometrika"])
    }

    /// **確認既有對外形時仍要移出同書寫系統的另一個**（R2 第 8 列）：手改 YAML 造出兩個 latin
    /// authorized 的記錄讀得進來（decode 不驗、只在寫入驗），守衛說「請選一個」——使用者
    /// `--authorize` 其中一個就該修好，而不是被 `alreadyAuthorized` 短路後再被守衛拒一次。
    func testConfirmingAnAuthorizedNameStillRemovesItsSameScriptRival() throws {
        var v = try venue()
        v.names = Timeline(v.names.entries + [TemporalValue(value: "Psychometrika")])
        v.authorized = ["PSYCHOMETRIKA"]
        try LibraryStore(root: root).writeVenue(v)
        // 繞過寫入守衛：直接在檔案上加第二個同書寫系統 authorized
        let file = root.appendingPathComponent("entities/\(v.id.uuidString).yaml")
        var text = try String(contentsOf: file, encoding: .utf8)
        text = text.replacingOccurrences(of: "authorized:\n- PSYCHOMETRIKA\n",
                                         with: "authorized:\n- PSYCHOMETRIKA\n- Psychometrika\n")
        try text.write(to: file, atomically: true, encoding: .utf8)
        XCTAssertEqual(try venue().authorized.count, 2, "fixture：兩個 latin authorized 要讀得進來")

        let out = try service.updateVenue(key: "some-journal", addNames: nil, note: nil, type: nil,
                                          authorize: ["Psychometrika"])
        let after = try venue()
        XCTAssertEqual(after.authorized, ["Psychometrika"], "選一個之後另一個要被移出")
        XCTAssertTrue(out.contains("\"authorizedRemoved\"") && out.contains("PSYCHOMETRIKA"), out)
    }
}
