import XCTest
@testable import AkashicCore
@testable import AkashicMCPKit
@testable import AkashicStoreIO
@testable import AkashicEntity

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
/// R3 只改了 authorize 一段、R3 verify 六路命中「一個函式裡兩種相等」（`add-name "X "` 種下髒條目、
/// `authorize "X"` 把它升上去；全新輸入存原樣後黏住）。R4（D6）三個名字迴圈同一組謂詞、同一條相等；
/// R4 verify 指出同一欄位還有 `addVenue`／`VenueBootstrap` 兩個寫入者。**R5（D8）不變式搬到 store 邊界
/// `Venue.validate()`**，所有寫入者存 canonical——見 `VenueNameInvariantTests` 與本檔「R4 verify（D8）」一節。
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
    /// 四次都寫進 authorized 並成為 displayName）。換行類是空白（跳過）；純標點是「沒有任何
    /// 字母或數字」→ 整批拒絕（純數字刊名 *1843* 是真的，R4 verify 第 7 列）。西里爾、假名含字母，不受影響。
    func testControlCharactersAndPunctuationAreNotNames() throws {
        XCTAssertNoThrow(try service.updateVenue(key: "some-journal", addNames: nil, note: nil,
                                                 type: nil, authorize: ["\n", "\r", "\u{2028}"]))
        XCTAssertEqual(try venue().authorized, [], "換行類是空白，跳過、零寫入")
        for bad in ["—", "…", "× ÷"] {
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

    // MARK: - R3 verify（D6）：三個名字迴圈同一條相等、同一組謂詞

    /// 私用：繞過寫入守衛，直接把記錄檔改成 store 守衛擋不住、但 decode 讀得進來的形狀。
    private func rewriteFile(_ v: Venue, _ edit: (String) -> String) throws {
        let file = root.appendingPathComponent("entities/\(v.id.uuidString).yaml")
        try edit(try String(contentsOf: file, encoding: .utf8)).write(to: file, atomically: true, encoding: .utf8)
    }

    /// **全新的輸入存 canonical**（R3 第 1 列 (a)）：空白不是名字的一部分（`NameIdentity` 的立場），
    /// 而 R3 把新條目存原樣、之後以「用 store 拼法」黏住——乾淨拼法永遠進不了 authorized。
    func testNewNameIsStoredCanonical() throws {
        _ = try service.updateVenue(key: "some-journal", addNames: nil, note: nil, type: nil,
                                    authorize: ["  New  Journal "])
        let v = try venue()
        XCTAssertEqual(v.authorized, ["New Journal"])
        XCTAssertTrue(v.names.entries.contains { $0.value == "New Journal" }, "\(v.names.entries.map(\.value))")
        XCTAssertFalse(v.names.entries.contains { $0.value.hasSuffix(" ") }, "不得存帶空白的條目")
    }

    /// **手改出來的近重複對在下一次寫入被 validate 具名擋下**（R3 第 1 列 (c) 在 D8 下重裁）：
    /// R4 讓 authorize「先精確後 canonical」去修正它，R4 verify 指出那個順序在對稱情境反而讓髒的贏、
    /// 且 Swift 沒有「精確」。D8 之後 names 內的近重複對是 store 不變式的違反——不修、不猜，
    /// 寫入面拒絕並說出是哪兩筆，修法是人改 YAML（同 dated-variant 守衛的立場）。
    func testHandMadeNearDuplicatePairIsRefusedByValidateNotRepaired() throws {
        var v = try venue()
        v.names = Timeline(v.names.entries + [TemporalValue(value: "Psychometrika"),
                                              TemporalValue(value: "Journal Z")])
        v.authorized = ["Journal Z"]
        try LibraryStore(root: root).writeVenue(v)
        try rewriteFile(v) { $0.replacingOccurrences(of: "- value: Psychometrika\n", with: "- value: 'Psychometrika '\n- value: Psychometrika\n")
                                .replacingOccurrences(of: "authorized:\n- Journal Z\n", with: "authorized:\n- 'Psychometrika '\n") }
        XCTAssertEqual(try venue().authorized, ["Psychometrika "], "fixture：髒拼法是 authorized")

        XCTAssertThrowsError(try service.updateVenue(key: "some-journal", addNames: nil, note: nil, type: nil,
                                                     authorize: ["Psychometrika"])) {
            let msg = ($0 as? LocalizedError)?.errorDescription ?? "\($0)"
            XCTAssertTrue(msg.contains("近重複") || msg.contains("canonical"), "要說出是不變式違反：\(msg)")
        }
        XCTAssertEqual(try venue().authorized, ["Psychometrika "], "零寫入")
    }

    /// `addNames` 的近重複不新增（R3 第 1 列 (b)）；全新的存 canonical。
    func testAddNameNearDuplicateIsNotAddedAndNewOnesAreStoredCanonical() throws {
        let out = try service.updateVenue(key: "some-journal", addNames: ["PSYCHOMETRIKA ", "  Brand  New "],
                                          note: nil, type: nil)
        let v = try venue()
        XCTAssertEqual(v.names.entries.map(\.value), ["PSYCHOMETRIKA", "Brand New"])
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(out.utf8)) as? [String: Any])
        XCTAssertEqual(json["namesAdded"] as? [String], ["Brand New"], out)
        // 原拼法只出現在 `namesAlreadyPresent`／`namesFolded`（R11／R12）——報告不宣稱 store 有 `"PSYCHOMETRIKA "`，也不說成 dropped
        XCTAssertEqual(json["namesAlreadyPresent"] as? [String], ["PSYCHOMETRIKA "], out)
        XCTAssertEqual(json["namesFolded"] as? [String], ["  Brand  New "], out)
    }

    /// `addVariant` 的近重複不加第二筆（R3 第 3 列的前提：variant 內兩筆近重複今天就寫得出來）。
    func testAddVariantNearDuplicateIsNotAddedTwice() throws {
        _ = try service.updateVenue(key: "some-journal", addNames: nil, note: nil, type: nil,
                                    addVariant: ["Psychometrika"])
        let out = try service.updateVenue(key: "some-journal", addNames: nil, note: nil, type: nil,
                                          addVariant: ["Psychometrika "])
        let v = try venue()
        XCTAssertEqual(v.variant, ["Psychometrika"])
        XCTAssertEqual(v.names.entries.count, 2)
        XCTAssertTrue(out.contains("\"variantAdded\" : [\n\n  ]") || out.contains("\"variantAdded\" : []"), out)
    }

    /// **同一呼叫 `add-name` 髒 ＋ `authorize` 乾淨**（R3 第 1 列 (b)，regression 席）：R3 會把髒拼法升成
    /// displayName。三個迴圈同一條相等之後：names 只有一筆乾淨的、它是 authorized。
    func testAddNameDirtyThenAuthorizeCleanInOneCallKeepsTheCleanSpelling() throws {
        _ = try service.updateVenue(key: "some-journal", addNames: ["Psychometrika "], note: nil, type: nil,
                                    authorize: ["Psychometrika"])
        let v = try venue()
        XCTAssertEqual(v.authorized, ["Psychometrika"])
        XCTAssertEqual(v.names.entries.filter { NameIdentity.same($0.value, "Psychometrika") }.count, 1)
        XCTAssertEqual(v.names.entries.filter { $0.value == "Psychometrika" }.count, 1)
    }

    /// `×`／`÷` 落在 `isLatinLetter` 的區間裡、被歸 `.latn`，R3 的 `.other &&` 合取項放它過（R3 第 5 列）：
    /// 判準改成「任何書寫系統都無字母即不是名字」。
    func testMultiplicationSignIsNotAName() throws {
        for bad in ["×", "÷", "× ÷"] {
            XCTAssertThrowsError(try service.updateVenue(key: "some-journal", addNames: nil, note: nil,
                                                         type: nil, authorize: [bad]), bad)
        }
        XCTAssertThrowsError(try service.updateVenue(key: "some-journal", addNames: ["×"], note: nil, type: nil),
                             "三個迴圈同一組謂詞")
        XCTAssertEqual(try venue().names.entries.count, 1, "零寫入")
    }

    /// bidi override／零寬字元夾在字母之間（R3 第 6 列）：整批拒絕、三個迴圈同型。ZWJ／ZWNJ 保留
    /// （波斯文與印度系文字合法使用）。
    func testBidiAndZeroWidthCharactersAreRejectedButJoinersAreNot() throws {
        let rlo = "Psychometrika\u{202E}"; let zwsp = "Psycho\u{200B}metrika"; let shy = "Psycho\u{00AD}metrika"
        for bad in [rlo, zwsp, shy] {
            XCTAssertThrowsError(try service.updateVenue(key: "some-journal", addNames: nil, note: nil,
                                                         type: nil, authorize: [bad]))
            XCTAssertThrowsError(try service.updateVenue(key: "some-journal", addNames: [bad], note: nil, type: nil))
            XCTAssertThrowsError(try service.updateVenue(key: "some-journal", addNames: nil, note: nil, type: nil,
                                                         addVariant: [bad]))
        }
        XCTAssertEqual(try venue().names.entries.count, 1, "零寫入")
        XCTAssertNoThrow(try service.updateVenue(key: "some-journal", addNames: ["نشریه\u{200C}روان\u{200D}سنجی"],
                                                 note: nil, type: nil), "ZWNJ／ZWJ 是合法的")
    }

    /// 替換**原位**（R3 第 2 列）：`[PSYCHOMETRIKA, 心理計量學]` 換 latin 對外形後，順序不變——
    /// `displayName` 取 `authorized.first`，remove＋append 會讓預設顯示名換書寫系統。
    func testReplacementKeepsTheAuthorizedOrder() throws {
        var v = try venue()
        v.names = Timeline(v.names.entries + [TemporalValue(value: "心理計量學")])
        v.authorized = ["PSYCHOMETRIKA", "心理計量學"]
        try LibraryStore(root: root).writeVenue(v)
        _ = try service.updateVenue(key: "some-journal", addNames: nil, note: nil, type: nil,
                                    authorize: ["Psychometrika"])
        XCTAssertEqual(try venue().authorized, ["Psychometrika", "心理計量學"])
    }

    /// variant 裡兩筆近重複（手改）：R3 第 3 列要「都拉回」，D8 之後那是 names 近重複對的不變式違反
    /// ——寫入面拒絕並說出是哪兩筆（不是「同時出現在兩個分割」那句指錯地方的訊息）。
    func testTwoNearDuplicateVariantsAreRefusedByValidateWithTheRightMessage() throws {
        var v = try venue()
        v.names = Timeline(v.names.entries + [TemporalValue(value: "Psychometrika")])
        v.variant = ["Psychometrika"]
        try LibraryStore(root: root).writeVenue(v)
        try rewriteFile(v) { $0.replacingOccurrences(of: "variant:\n- Psychometrika\n", with: "variant:\n- Psychometrika\n- 'Psychometrika '\n")
                                .replacingOccurrences(of: "- value: Psychometrika\n", with: "- value: Psychometrika\n- value: 'Psychometrika '\n") }
        XCTAssertEqual(try venue().variant.count, 2, "fixture")
        XCTAssertThrowsError(try service.updateVenue(key: "some-journal", addNames: nil, note: nil, type: nil,
                                                     authorize: ["Psychometrika"])) {
            let msg = ($0 as? LocalizedError)?.errorDescription ?? "\($0)"
            XCTAssertTrue(msg.contains("近重複") || msg.contains("canonical"), "訊息要指向不變式，不是分割交集：\(msg)")
            XCTAssertFalse(msg.contains("同時出現在 authorized 與 variant"), msg)
        }
        XCTAssertEqual(try venue().variant.count, 2, "零寫入")
    }

    /// 手造兩個 canonical-相等的 authorized（R3 第 1 列 (e)）：D8 之後那是不變式違反（names 近重複對＋
    /// authorized 非 canonical），寫入面拒絕並說出是哪一筆；「選了就該修好」在這個形狀上改由人改 YAML。
    func testHandMadeCanonicalEqualAuthorizedPairIsRefusedByValidate() throws {
        var v = try venue()
        v.names = Timeline(v.names.entries + [TemporalValue(value: "Psychometrika")])
        v.authorized = ["Psychometrika"]
        try LibraryStore(root: root).writeVenue(v)
        try rewriteFile(v) { $0.replacingOccurrences(of: "authorized:\n- Psychometrika\n", with: "authorized:\n- Psychometrika\n- 'Psychometrika '\n")
                                .replacingOccurrences(of: "- value: Psychometrika\n", with: "- value: Psychometrika\n- value: 'Psychometrika '\n") }
        XCTAssertEqual(try venue().authorized.count, 2, "fixture")
        XCTAssertThrowsError(try service.updateVenue(key: "some-journal", addNames: nil, note: nil, type: nil,
                                                     authorize: ["Psychometrika"])) {
            let msg = ($0 as? LocalizedError)?.errorDescription ?? "\($0)"
            XCTAssertTrue(msg.contains("Psychometrika "), "要說出是哪一筆違反：\(msg)")
        }
        XCTAssertEqual(try venue().authorized.count, 2, "零寫入")
    }

    /// 三個迴圈共用同一個「空白」（R3 第 4 列）：換行類對 addNames／addVariant 也是「沒說話」。
    func testSiblingLoopsShareTheBlankPredicate() throws {
        XCTAssertNoThrow(try service.updateVenue(key: "some-journal", addNames: ["\n", "\r"], note: nil, type: nil,
                                                 addVariant: ["\u{2028}"]))
        let v = try venue()
        XCTAssertEqual(v.names.entries.count, 1, "零寫入")
        XCTAssertEqual(v.variant, [])
    }

    // MARK: - R4 verify（D8）：不變式在 store 邊界，寫入者存 canonical

    /// **去重先於驗證會讓合法性隨順序改變**（R4 verify 第 3 列，Codex）：`["New Journal", "New\tJournal"]`
    /// 兩種順序結果要相同——tab 是空白（canonical 收斂），不是控制字元問題。
    func testVettingIsOrderIndependent() throws {
        for order in [["New Journal", "New\tJournal"], ["New\tJournal", "New Journal"]] {
            let s2 = AkashicService(root: root)
            _ = try s2.updateVenue(key: "some-journal", addNames: order, note: nil, type: nil)
            let v = try venue()
            XCTAssertEqual(v.names.entries.map(\.value).filter { $0.hasPrefix("New") }, ["New Journal"], "\(order)")
        }
    }

    /// **NFD 輸入存 NFC 位元組**（R4 verify 第 4 列，DA）：Swift `==` 是 canonical equivalence，R4 的「精確命中」
    /// 回傳呼叫端的 NFD 字串、authorized 拿到與 names 不同的位元組——非 Swift 讀者看到 `authorized ⊄ names`。
    func testNFDInputIsStoredAndReportedAsNFC() throws {
        let nfc = "Psychom\u{E9}trika"; let nfd = "Psychome\u{301}trika"
        _ = try service.updateVenue(key: "some-journal", addNames: [nfc], note: nil, type: nil)
        let out = try service.updateVenue(key: "some-journal", addNames: nil, note: nil, type: nil, authorize: [nfd])
        let v = try venue()
        XCTAssertEqual(Array(v.authorized[0].utf8), Array(nfc.utf8), "authorized 要是 NFC 位元組")
        XCTAssertTrue(v.names.entries.contains { Array($0.value.utf8) == Array(nfc.utf8) })
        XCTAssertEqual(v.names.entries.count, 2, "不得新增 NFD 條目")
        XCTAssertTrue(out.contains("\"authorizedAdded\""), out)
        let again = try service.updateVenue(key: "some-journal", addNames: nil, note: nil, type: nil, authorize: [nfd])
        XCTAssertTrue(again.contains("\"alreadyAuthorized\""), again)
        XCTAssertEqual(Array(try venue().authorized[0].utf8), Array(nfc.utf8), "no-op 不得改位元組")
    }

    /// ALM／TAG 字元（R4 verify 第 2 列：列舉漏掉的 Cf）三個迴圈都拒。
    func testArabicLetterMarkAndTagCharactersAreRejected() throws {
        for bad in ["Psycho\u{061C}metrika", "Tag\u{E0041}\u{E007F}Name", "Mvs\u{180E}Name"] {
            XCTAssertThrowsError(try service.updateVenue(key: "some-journal", addNames: [bad], note: nil, type: nil), bad)
            XCTAssertThrowsError(try service.updateVenue(key: "some-journal", addNames: nil, note: nil, type: nil, authorize: [bad]), bad)
        }
        XCTAssertEqual(try venue().names.entries.count, 1, "零寫入")
    }

    /// 純數字刊名（*1843*）三個迴圈都收（R4 verify 第 7 列）。
    func testDigitOnlyNameIsAccepted() throws {
        _ = try service.updateVenue(key: "some-journal", addNames: ["1843"], note: nil, type: nil)
        _ = try service.updateVenue(key: "some-journal", addNames: nil, note: nil, type: nil, authorize: ["1843"])
        XCTAssertEqual(try venue().authorized, ["1843"], "1843 是 .other、與 PSYCHOMETRIKA 不同書寫系統？——不：它無字母，歸 .other；PSYCHOMETRIKA 是 latn，各一")
    }

    /// **拼法修正要出聲**（R4 verify 第 6 列）：authorized 裡一筆手改成 NFD 位元組的名字（Swift `==`
    /// 看不出來、`Set` 子集檢查也看不出來）在下一次 `--authorize` 同名時被換成 canonical——這是不變式
    /// 唯一的自我修復路（新狀態 canonical、validate 過），而報告不能只說 `alreadyAuthorized`。上一版的這條測試是
    /// 空洞通過（`authorizedRemoved` 鍵永遠在），本輪自審抓到。**R10 起報在 `authorizedRewritten`**（R9 verify logic
    /// 第 23 列：同一個可見字串同時落在 `alreadyAuthorized` 與 `authorizedRemoved` 讓操作者看不出改了什麼）。
    func testHandEditedNFDAuthorizedIsRepairedAndReported() throws {
        let nfc = "Psychom\u{E9}trika"; let nfd = "Psychome\u{301}trika"
        var v = try venue()
        v.names = Timeline(v.names.entries + [TemporalValue(value: nfc)])
        v.authorized = [nfc]
        try LibraryStore(root: root).writeVenue(v)
        try rewriteFile(v) { $0.replacingOccurrences(of: "authorized:\n- \(nfc)\n", with: "authorized:\n- \(nfd)\n") }
        XCTAssertEqual(Array(try venue().authorized[0].utf8), Array(nfd.utf8), "fixture：authorized 是 NFD 位元組")
        let out = try service.updateVenue(key: "some-journal", addNames: nil, note: nil, type: nil, authorize: [nfc])
        let obj = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(out.utf8)) as? [String: Any])
        XCTAssertEqual(obj["authorizedRewritten"] as? [String], [nfc], "位元組被換掉要報在自己的桶")
        XCTAssertEqual(obj["authorizedRemoved"] as? [String], [])
        XCTAssertEqual(obj["alreadyAuthorized"] as? [String], [])
        XCTAssertEqual(Array(try venue().authorized[0].utf8), Array(nfc.utf8), "修成 canonical")
    }

    /// 第四個寫入者：`addVenue` 也存 canonical、也驗（R4 verify 第 1 列——`add-venue --names "Dirty "` 種髒種子）。
    func testAddVenueStoresCanonicalAndVets() throws {
        _ = try service.addVenue(key: "j2", names: ["  Dirty  Journal ", "Dirty Journal", " "], type: "periodical", note: nil, issn: nil)
        let v = try XCTUnwrap(LibraryStore(root: root).load().venues.first { $0.key == "j2" })
        XCTAssertEqual(v.names.entries.map(\.value), ["Dirty Journal"], "canonical、去重、空白跳過")
        XCTAssertThrowsError(try service.addVenue(key: "j3", names: ["Rlo\u{202E}Name"], type: "periodical", note: nil, issn: nil))
        XCTAssertThrowsError(try service.addVenue(key: "j4", names: ["×"], type: "periodical", note: nil, issn: nil))
        XCTAssertThrowsError(try service.addVenue(key: "j5", names: [" ", ""], type: "periodical", note: nil, issn: nil), "全空白＝沒有名字")
        XCTAssertNil(try LibraryStore(root: root).load().venues.first { ["j3","j4","j5"].contains($0.key) })
    }

    // MARK: - R5 verify（D11）：resolve-venues 的寫入順序

    /// **venue 先過閘、再寫 entry**（R5 verify 第 3 列，DA 逐一列舉 venue 寫入者找到；Claude 代裁 D11）：
    /// R5 的 apply 是 `for entry in changed { writeEntry }` 先落盤、之後 `writeVenue`（verdict）沒有 catch——
    /// 真 binary 實測手改一筆尾隨空白的 venue 後 apply：entry 已升格成 `.key`、verdict 沒落、錯誤訊息像
    /// 「什麼都沒寫」。`rename` 那條（`LibraryStore:1577`）已是「venue 先 preflight」的形狀。D8 把觸發集合
    /// 從三個罕見形狀擴到最常見的手改痕跡，所以這個撕裂不再是理論。
    func testResolveVenuesApplyWritesNothingWhenTheVenueIsUnwritable() throws {
        let store = LibraryStore(root: root)
        let v = try venue()
        try rewriteFile(v) { $0.replacingOccurrences(of: "- value: PSYCHOMETRIKA\n", with: "- value: 'PSYCHOMETRIKA '\n") }
        XCTAssertTrue(try venue().names.entries.contains { $0.value == "PSYCHOMETRIKA " }, "fixture：髒條目已在磁碟上")
        var e = Entry(id: UUID(), citekey: "x2025", type: .periodicalArticle, title: "T")
        e.venues = [.literal("Psychometrika")]
        _ = try store.writeEntry(e)
        let list = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(try service.resolveVenues(apply: nil).utf8)) as? [String: Any])
        let id = try XCTUnwrap((list["candidates"] as? [[String: Any]])?.first?["id"] as? String)
        XCTAssertThrowsError(try service.resolveVenues(apply: [id])) { err in
            XCTAssertTrue(String(describing: err).contains("PSYCHOMETRIKA "), "\(err)")
        }
        let after = try store.load()
        XCTAssertEqual(after.entries.first { $0.citekey == "x2025" }?.venues, [.literal("Psychometrika")], "entry 不得先落盤")
        XCTAssertFalse(try venue().references.contains { $0.field == "resolution-confirmed" })
    }

    /// **懸空的 from-key 要具名拒絕，不是 crash**（R6 verify 第 4／15／27 列）：`repoint` 只驗 `newKey` 存在，
    /// entry 目前指著的 `oldKey` 沒驗——venue 檔被手刪或 quarantine 後，一個格式合法的 id 會在
    /// `venuesByKey[k]!` 上 `Fatal error`（base 既有，D11 把它從「entry 已落盤再 crash」變成「零寫入再 crash」；
    /// 對 MCP 面是以合法參數殺死 server 的路徑）。`demote` 那側早就是 `guard let` 的形狀。
    func testRepointRefusesADanglingCurrentVenueKeyInsteadOfCrashing() throws {
        let store = LibraryStore(root: root)
        var e = Entry(id: UUID(), citekey: "x2025", type: .periodicalArticle, title: "T")
        e.venues = [.key("ghost-journal")]
        _ = try store.writeEntry(e)
        XCTAssertThrowsError(try service.resolveVenues(apply: nil, repoint: ["x2025:0:some-journal"])) { err in
            let s = String(describing: err)
            XCTAssertTrue(s.contains("ghost-journal"), s)
            // 指路要指得到（R7 verify 第 4 列）：`--demote` 對同一個懸空狀態也是 notFound，唯一的出路是救回檔案或手改 work 的 YAML
            XCTAssertFalse(s.contains("--demote"), s)
            XCTAssertTrue(s.contains("救回") && s.contains("YAML"), s)
        }
        XCTAssertEqual(try store.load().entries.first?.venues, [.key("ghost-journal")], "零寫入")
    }

    /// **repoint 的 verdict literal 從 from-venue 的 confirmed verdict 逐字取回，不是 work 的 title**（R7 verify 第 6 列，
    /// DA；#418 既有缺陷）：R7 之前 `let literal = byCitekey[m.citekey]!.title`——之後 `--demote` 會把 venue 邊改寫成
    /// 論文標題，比「顯示名頂替」更糟；rejected 那一側也帶著標題，`rejectedPairings` 對真正的刊名 literal 不會抑制。
    func testRepointCarriesTheOriginalLiteralNotTheTitle() throws {
        let store = LibraryStore(root: root)
        var e = Entry(id: UUID(), citekey: "x2025", type: .periodicalArticle, title: "A Paper About Nothing")
        e.venues = [.literal("Psychometrika")]
        _ = try store.writeEntry(e)
        _ = try service.resolveVenues(apply: ["x2025:0"])
        _ = try service.addVenue(key: "other-journal", names: ["Other Journal"], type: "periodical", note: nil, issn: nil)
        _ = try service.resolveVenues(apply: nil, repoint: ["x2025:0:other-journal"])
        let after = try store.load()
        let to = try XCTUnwrap(after.venues.first { $0.key == "other-journal" })
        let vs = ResolutionLedger.verdicts(references: to.references).0
        let confirmed = vs.filter { $0.kind == .confirmed }.filter { $0.holder == "x2025" }
        XCTAssertEqual(confirmed.map(\.literal), ["Psychometrika"])
        let from = try XCTUnwrap(after.venues.first { $0.key == "some-journal" })
        let fvs = ResolutionLedger.verdicts(references: from.references).0
        let rejected = fvs.filter { $0.kind == .rejected }.filter { $0.holder == "x2025" }
        XCTAssertEqual(rejected.map(\.literal), ["Psychometrika"])
        _ = try service.resolveVenues(apply: nil, demote: ["x2025:0"])
        XCTAssertEqual(try store.load().entries.first { $0.citekey == "x2025" }?.venues, [.literal("Psychometrika")])
    }

    /// from-venue 上沒有這筆 work 的 confirmed verdict（手改出來的 key 邊）→ 拒絕改指，不拿 title 頂替（同 demote 的立場）。
    func testRepointRefusesWhenTheFromVenueHasNoVerdictForTheWork() throws {
        let store = LibraryStore(root: root)
        var e = Entry(id: UUID(), citekey: "x2025", type: .periodicalArticle, title: "A Paper")
        e.venues = [.key("some-journal")]
        _ = try store.writeEntry(e)
        _ = try service.addVenue(key: "other-journal", names: ["Other Journal"], type: "periodical", note: nil, issn: nil)
        XCTAssertThrowsError(try service.resolveVenues(apply: nil, repoint: ["x2025:0:other-journal"])) { err in
            XCTAssertTrue(String(describing: err).contains("confirmed verdict"), "\(err)")
        }
        XCTAssertEqual(try store.load().entries.first { $0.citekey == "x2025" }?.venues, [.key("some-journal")], "零寫入")
    }

    /// **repoint 寫 rejected 時退役同 holder 上同一配對的 confirmed**（R8 verify 第 9／12 列；Claude 代裁 D20）：R8 讓
    /// rejected 逐字帶原 literal（對的），於是 from-venue 同時持有 `resolution-confirmed` 與 `resolution-rejected`
    /// `work:x2025 :: Psychometrika`——`akashic validate` 對每一次合法的 repoint 印一條 #486「矛盾 verdict」warning，
    /// 而它的唯一處置「刪掉另一個」沒有工具面。verdict 沒有時間戳，「後者為準」讀端判不出來，只有寫入面知道哪個是新的。
    /// 反向 repoint（undo）也要乾淨：`to` 上的舊 rejected 被新 confirmed 退役。
    func testRepointRetiresTheOppositeVerdictOnBothVenues() throws {
        let store = LibraryStore(root: root)
        var e = Entry(id: UUID(), citekey: "x2025", type: .periodicalArticle, title: "T")
        e.venues = [.literal("Psychometrika")]
        _ = try store.writeEntry(e)
        _ = try service.resolveVenues(apply: ["x2025:0"])
        _ = try service.addVenue(key: "other-journal", names: ["Other Journal"], type: "periodical", note: nil, issn: nil)
        let out = try service.resolveVenues(apply: nil, repoint: ["x2025:0:other-journal"])
        XCTAssertTrue(out.contains("\"verdictsRetired\""), "報告要說退役了幾筆：\(out)")
        func kinds(_ key: String) throws -> [ResolutionLedger.VerdictKind] {
            let v = try XCTUnwrap(store.load().venues.first { $0.key == key })
            return ResolutionLedger.verdicts(references: v.references).0.filter { $0.holder == "x2025" }.map(\.kind)
        }
        XCTAssertEqual(try kinds("some-journal"), [.rejected], "from：confirmed 退役、只剩 rejected")
        XCTAssertEqual(try kinds("other-journal"), [.confirmed])
        XCTAssertTrue(store.contradictoryVerdictIssues(in: try store.load()).isEmpty, "#486 不得對合法的 repoint 出聲")
        // undo：改回去——to 上的舊 rejected 被退役，from 上的舊 confirmed 被退役
        _ = try service.resolveVenues(apply: nil, repoint: ["x2025:0:some-journal"])
        XCTAssertEqual(try kinds("some-journal"), [.confirmed])
        XCTAssertEqual(try kinds("other-journal"), [.rejected])
        XCTAssertTrue(store.contradictoryVerdictIssues(in: try store.load()).isEmpty)
    }

    /// demote 同形（#418 既有：寫 rejected 時把 confirmed 留在原地——R8 verify 第 12 列指出 repoint＋demote 一次各留一條）。
    func testDemoteRetiresTheConfirmedVerdict() throws {
        let store = LibraryStore(root: root)
        var e = Entry(id: UUID(), citekey: "x2025", type: .periodicalArticle, title: "T")
        e.venues = [.literal("Psychometrika")]
        _ = try store.writeEntry(e)
        _ = try service.resolveVenues(apply: ["x2025:0"])
        _ = try service.resolveVenues(apply: nil, demote: ["x2025:0"])
        let v = try venue()
        let vs = ResolutionLedger.verdicts(references: v.references).0.filter { $0.holder == "x2025" }
        XCTAssertEqual(vs.map(\.kind), [.rejected])
        XCTAssertEqual(vs.map(\.literal), ["Psychometrika"])
        XCTAssertTrue(store.contradictoryVerdictIssues(in: try store.load()).isEmpty)
    }

    /// **from-venue 上同一 work 有兩個不同的 confirmed literal 時拒絕**（R8 verify 第 7／36 列，Codex；Claude 代裁 D23）：
    /// R8 用 `first(where:)` 取第一筆——同一 work 的兩條邊以不同 literal（`Psychometrika`／`PSYCHOMETRIKA`）歸到同一
    /// venue（兩次 apply，或 #553 合併把兩個攣生的 verdict 遷進同一 keeper）時，改指第二條邊仍取得第一筆的 literal，
    /// 錯的 literal 被寫進 `to` 的 confirmed 與 `from` 的 rejected，之後 demote 把邊退回另一個刊名。verdict 不帶 index，
    /// store 裡沒有東西說得出哪筆屬於哪條邊——`enrich` 對 DOI 命中 ≥2 筆的 `ambiguous` 形：具名拒絕、零寫入。
    /// live store 2026-09-12 實測：同一 work 對同一 venue 兩條 key 邊 0、同一 venue 對同一 work 兩個 confirmed literal 0。
    /// **「不同」是 ledger 的相等**（#470 `matchingKey`）：本測試第一版用 `Psychometrika`／`PSYCHOMETRIKA`，兩次 apply
    /// 只留一筆 verdict（大小寫異寫是同一個配對），所以拒絕條件從來不會觸發——兩個 literal 要在正規化後仍不同。
    /// **R11 起 `apply` 造不出這個形**（D28）——fixture 改成手改（或 #553 合併）出來的：兩條 key 邊、兩筆不同 literal 的 confirmed。
    func testRepointAndDemoteRefuseWhenTheFromVenueHoldsTwoLiteralsForTheWork() throws {
        let store = LibraryStore(root: root)
        var e = Entry(id: UUID(), citekey: "x2025", type: .periodicalArticle, title: "T")
        e.venues = [.key("some-journal"), .key("some-journal")]
        _ = try store.writeEntry(e)
        var v0 = try venue()
        for literal in ["Psychometrika", "Psychometrika Journal"] {
            v0.references.append(ResolutionLedger.record(.confirmed, holderKind: .work, holder: "x2025", literal: literal,
                                                         rule: ResolutionLedger.venueRule, statement: "手改"))
        }
        try store.writeVenue(v0)
        _ = try service.addVenue(key: "other-journal", names: ["Other Journal"], type: "periodical", note: nil, issn: nil)
        XCTAssertThrowsError(try service.resolveVenues(apply: nil, repoint: ["x2025:1:other-journal"])) { err in
            let s = String(describing: err)
            XCTAssertTrue(s.contains("「Psychometrika」") && s.contains("「Psychometrika Journal」"), "要列出兩個 literal：\(s)")
            XCTAssertTrue(s.contains("YAML"), "要說怎麼修：\(s)")
        }
        XCTAssertThrowsError(try service.resolveVenues(apply: nil, demote: ["x2025:0"]))
        let after = try store.load()
        XCTAssertEqual(after.entries.first?.venues, [.key("some-journal"), .key("some-journal")], "零寫入")
        let v = try XCTUnwrap(after.venues.first { $0.key == "some-journal" })
        XCTAssertEqual(ResolutionLedger.verdicts(references: v.references).0.filter { $0.holder == "x2025" }.count, 2, "零寫入")
    }

    /// **配對由多條邊實例化時 repoint／demote 拒絕**（R9 verify：Codex＋DA＋logic ×2＋requirements＋regression 六路命中；
    /// Claude 代裁 D25）：verdict 不帶 venue index，同一 work 兩條邊指同一 venue 時只有一筆 confirmed（`appendIfAbsent`）——
    /// D20 退役它會讓另一條邊在任何工具面上都救不回來（demote／repoint 都撞「找不到 confirmed verdict」），而且 R9 之前
    /// 這個狀態會留一條 #486 warning、R9 之後 `validate` 全綠。D23 的謂詞問的是 literal 個數不是邊的個數，剛好漏掉這格。
    /// live store 2026-09-14 實測：2,411 筆 work、3 筆有 >1 條 venue 邊、同 venue 兩條 key 邊 0、兩條 literal 邊同配對 0。
    /// **R11 起 `apply` 造不出這個形**（D28，`testApplyRefusesWhenItWouldKeyTheSameVenueTwice`）——fixture 改成手改出來的。
    /// **另一條同配對的 literal 邊：repoint 拒、demote 收**（R10 verify logic 第 7 列）：那條危害只在 repoint（to-venue 上該配對
    /// 的 rejected 可能是它的）；demote 沒有 to-venue，literal 邊在該 venue 上不可能持有 confirmed，退役不會刪掉任何別人的證據。
    func testRepointAndDemoteRefuseWhenThePairingIsInstantiatedByMoreThanOneEdge() throws {
        let store = LibraryStore(root: root)
        var e = Entry(id: UUID(), citekey: "x2025", type: .periodicalArticle, title: "T")
        e.venues = [.key("some-journal"), .key("some-journal")]
        _ = try store.writeEntry(e)
        var v0 = try venue()
        v0.references.append(ResolutionLedger.record(.confirmed, holderKind: .work, holder: "x2025", literal: "Psychometrika",
                                                     rule: ResolutionLedger.venueRule, statement: "手改"))
        try store.writeVenue(v0)
        _ = try service.addVenue(key: "other-journal", names: ["Other Journal"], type: "periodical", note: nil, issn: nil)
        for op in [{ try self.service.resolveVenues(apply: nil, demote: ["x2025:0"]) },
                   { try self.service.resolveVenues(apply: nil, repoint: ["x2025:0:other-journal"]) }] {
            XCTAssertThrowsError(try op()) { err in
                let s = String(describing: err)
                XCTAssertTrue(s.contains("2 條邊") || s.contains("兩條邊"), s)
                XCTAssertTrue(s.contains("YAML") && s.contains("#572"), "要說怎麼修、指向移除面的 issue：\(s)")
            }
        }
        XCTAssertEqual(try store.load().entries.first?.venues, [.key("some-journal"), .key("some-journal")], "零寫入")
        let v = try venue()
        XCTAssertEqual(ResolutionLedger.verdicts(references: v.references).0.filter { $0.holder == "x2025" }.map(\.kind), [.confirmed], "零寫入")
        // 第二種形：一條 key 邊 ＋ 一條同配對的 literal 邊（匯入可造出：journaltitle 與 publisher 都是同一個刊名）
        var e2 = Entry(id: UUID(), citekey: "y2025", type: .periodicalArticle, title: "T2")
        e2.venues = [.literal("Psychometrika")]
        _ = try store.writeEntry(e2)
        _ = try service.resolveVenues(apply: ["y2025:0"])
        var keyed = try XCTUnwrap(store.load().entries.first { $0.citekey == "y2025" })
        keyed.venues.append(.literal("PSYCHOMETRIKA"))
        _ = try store.writeEntry(keyed)
        XCTAssertThrowsError(try service.resolveVenues(apply: nil, repoint: ["y2025:0:other-journal"]))
        XCTAssertEqual(try store.load().entries.first { $0.citekey == "y2025" }?.venues, [.key("some-journal"), .literal("PSYCHOMETRIKA")], "零寫入")
        _ = try service.resolveVenues(apply: nil, demote: ["y2025:0"])
        XCTAssertEqual(try store.load().entries.first { $0.citekey == "y2025" }?.venues, [.literal("Psychometrika"), .literal("PSYCHOMETRIKA")],
                       "demote 收：退回這條邊自己的 literal，另一條 literal 邊不動")
        XCTAssertEqual(ResolutionLedger.verdicts(references: try venue().references).0.filter { $0.holder == "y2025" }.map(\.kind), [.rejected])
    }

    /// **repoint 不得把邊改指到本 work 已有邊的 venue**（R10 verify logic 第 2 列真 binary 重現、Codex 第 1 列；Claude 代裁 D27）：
    /// R10 的 D25 只驗**原始** entry 裡的 from 配對，newKey 完全不看——`[key alpha, key beta]` 改指 1→alpha 走成 `[alpha, alpha]`、
    /// alpha 上兩筆 confirmed、beta 的 confirmed 被退役、validate 全綠、之後兩條邊都動不了。配對的唯一性要對**改指之後**的邊集合驗，
    /// 同一批裡兩個 move 收斂到同一個 venue 是同一件事。
    func testRepointRefusesWhenTheTargetIsAlreadyKeyedByAnotherEdge() throws {
        let store = LibraryStore(root: root)
        _ = try service.addVenue(key: "beta-journal", names: ["Beta Journal"], type: "periodical", note: nil, issn: nil)
        var e = Entry(id: UUID(), citekey: "x2025", type: .periodicalArticle, title: "T")
        e.venues = [.literal("PSYCHOMETRIKA"), .literal("Beta Journal")]
        _ = try store.writeEntry(e)
        _ = try service.resolveVenues(apply: ["x2025:0", "x2025:1"])
        XCTAssertEqual(try store.load().entries.first?.venues, [.key("some-journal"), .key("beta-journal")])
        XCTAssertThrowsError(try service.resolveVenues(apply: nil, repoint: ["x2025:1:some-journal"])) { err in
            let s = String(describing: err)
            XCTAssertTrue(s.contains("some-journal") && (s.contains("2 條邊") || s.contains("兩條邊")), s)
            XCTAssertTrue(s.contains("#572"), "要指向移除面的 issue：\(s)")
        }
        let after = try store.load()
        XCTAssertEqual(after.entries.first?.venues, [.key("some-journal"), .key("beta-journal")], "零寫入")
        let beta = try XCTUnwrap(after.venues.first { $0.key == "beta-journal" })
        XCTAssertEqual(ResolutionLedger.verdicts(references: beta.references).0.filter { $0.holder == "x2025" }.map(\.kind), [.confirmed], "零寫入")
        _ = try service.addVenue(key: "gamma-journal", names: ["Gamma Journal"], type: "periodical", note: nil, issn: nil)
        XCTAssertThrowsError(try service.resolveVenues(apply: nil, repoint: ["x2025:0:gamma-journal", "x2025:1:gamma-journal"]))
        XCTAssertEqual(try store.load().entries.first?.venues, [.key("some-journal"), .key("beta-journal")], "零寫入")
    }

    /// **同一批裡兩條帶同一個 literal 的邊不得互換**（R10 verify Codex 第 1 列；D27）：verdict 以 (work, literal) 為鍵、不帶 index，
    /// 兩條邊的 literal 相同時逐 move 的退役會互相覆蓋——`[A, B]` 交換成 `[B, A]`，第二個 move 在 B 寫 rejected 時退役掉 B 的
    /// confirmed，而那筆正是第一個 move 讓邊 0 落腳的證據；留下哪一側的證據取決於輸入順序。具名拒絕、零寫入。
    /// **literal 不同時交換是對的**（本測試的後半）：每一側的 confirmed／rejected 各帶自己的 literal，退役互不干擾。
    func testRepointRefusesSwappingEdgesThatShareALiteralButAcceptsDistinctOnes() throws {
        let store = LibraryStore(root: root)
        _ = try service.addVenue(key: "beta-journal", names: ["Beta Journal"], type: "periodical", note: nil, issn: nil)
        // 手改出來的形：兩條 key 邊、兩個 venue 各持同一 literal 的 confirmed（#553 合併或兩次歧義裁決可造出）
        var e = Entry(id: UUID(), citekey: "x2025", type: .periodicalArticle, title: "T")
        e.venues = [.key("some-journal"), .key("beta-journal")]
        _ = try store.writeEntry(e)
        for key in ["some-journal", "beta-journal"] {
            var v = try XCTUnwrap(store.load().venues.first { $0.key == key })
            v.references.append(ResolutionLedger.record(.confirmed, holderKind: .work, holder: "x2025", literal: "PSYCHOMETRIKA",
                                                        rule: ResolutionLedger.venueRule, statement: "手改"))
            try store.writeVenue(v)
        }
        XCTAssertThrowsError(try service.resolveVenues(apply: nil, repoint: ["x2025:0:beta-journal", "x2025:1:some-journal"])) { err in
            let s = String(describing: err)
            XCTAssertTrue(s.contains("「PSYCHOMETRIKA」") && s.contains("同一個 literal"), s)
        }
        for key in ["some-journal", "beta-journal"] {
            let v = try XCTUnwrap(store.load().venues.first { $0.key == key })
            XCTAssertEqual(ResolutionLedger.verdicts(references: v.references).0.filter { $0.holder == "x2025" }.map(\.kind), [.confirmed], "零寫入：\(key)")
        }
        // literal 不同：交換成功，兩側各自正確，之後 demote 拿回這條邊自己的 literal
        var e2 = Entry(id: UUID(), citekey: "y2025", type: .periodicalArticle, title: "T2")
        e2.venues = [.literal("PSYCHOMETRIKA"), .literal("Beta Journal")]
        _ = try store.writeEntry(e2)
        _ = try service.resolveVenues(apply: ["y2025:0", "y2025:1"])
        _ = try service.resolveVenues(apply: nil, repoint: ["y2025:0:beta-journal", "y2025:1:some-journal"])
        let load = try store.load()
        XCTAssertEqual(load.entries.first { $0.citekey == "y2025" }?.venues, [.key("beta-journal"), .key("some-journal")])
        func kinds(_ key: String) throws -> [String: ResolutionLedger.VerdictKind] {
            let v = try XCTUnwrap(load.venues.first { $0.key == key })
            return Dictionary(ResolutionLedger.verdicts(references: v.references).0.filter { $0.holder == "y2025" }
                                  .map { ($0.literal, $0.kind) }, uniquingKeysWith: { a, _ in a })
        }
        XCTAssertEqual(try kinds("beta-journal"), ["PSYCHOMETRIKA": .confirmed, "Beta Journal": .rejected])
        XCTAssertEqual(try kinds("some-journal"), ["Beta Journal": .confirmed, "PSYCHOMETRIKA": .rejected])
        XCTAssertTrue(store.contradictoryVerdictIssues(in: load).isEmpty)
        _ = try service.resolveVenues(apply: nil, demote: ["y2025:0"])
        XCTAssertEqual(try store.load().entries.first { $0.citekey == "y2025" }?.venues.first, .literal("PSYCHOMETRIKA"))
    }

    /// **apply 對「會讓同一 work 兩條邊指向同一 venue」的候選逐筆略過、其餘照寫**（R10 verify requirements 第 5 列、regression 第 10 列
    /// → D28；R11 verify requirements 第 4 列、logic 第 9 列、regression 第 12 列、DA 第 14 列 → D33 改逐筆略過）：D25 只擋消費端，而
    /// R10 自己的測試就用 `apply` 一行造出 `[key V, key V]`；R11 整批拒絕，但一筆毒候選會讓同批無關的候選全部零寫入、每次重列都
    /// 再提一次（campaign 用法是照 listing 全量 apply），且既有的重複邊（手改／舊 binary／合併後的 literal 邊）會把同一 work 上不相干
    /// 的歸戶鎖死、訊息還把因果歸給這次 apply。store 狀態不符是「該筆略過並具名」那一類（`judge` 的先例），不是整批拒絕。
    func testApplySkipsTheCandidateThatWouldKeyTheSameVenueTwiceAndWritesTheRest() throws {
        let store = LibraryStore(root: root)
        _ = try service.addVenue(key: "other-journal", names: ["Other Journal"], type: "periodical", note: nil, issn: nil)
        var e = Entry(id: UUID(), citekey: "x2025", type: .periodicalArticle, title: "T")
        e.venues = [.literal("Psychometrika"), .literal("PSYCHOMETRIKA")]
        _ = try store.writeEntry(e)
        var y = Entry(id: UUID(), citekey: "y2025", type: .periodicalArticle, title: "T2")
        y.venues = [.literal("Other Journal")]
        _ = try store.writeEntry(y)
        let out = try service.resolveVenues(apply: ["x2025:0", "x2025:1", "y2025:0"])
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(out.utf8)) as? [String: Any])
        XCTAssertEqual(json["applied"] as? [String], ["x2025:0", "y2025:0"], out)
        let skipped = try XCTUnwrap(json["skippedDuplicateVenueEdge"] as? [[String: Any]], out)
        XCTAssertEqual(skipped.map { $0["id"] as? String }, ["x2025:1"])
        XCTAssertTrue((skipped[0]["reason"] as? String ?? "").contains("#572"), out)
        let load = try store.load()
        XCTAssertEqual(load.entries.first { $0.citekey == "x2025" }?.venues, [.key("some-journal"), .literal("PSYCHOMETRIKA")])
        XCTAssertEqual(load.entries.first { $0.citekey == "y2025" }?.venues, [.key("other-journal")], "同批無關的候選照寫")
        XCTAssertEqual(ResolutionLedger.verdicts(references: try venue().references).0.filter { $0.holder == "x2025" }.map(\.literal), ["Psychometrika"])
        // 一次一條也一樣：略過、零寫入、具名
        let again = try service.resolveVenues(apply: ["x2025:1"])
        let j2 = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(again.utf8)) as? [String: Any])
        XCTAssertEqual(j2["applied"] as? [String], [], again)
        XCTAssertEqual((j2["skippedDuplicateVenueEdge"] as? [[String: Any]])?.map { $0["id"] as? String }, ["x2025:1"], again)
        XCTAssertEqual(try store.load().entries.first { $0.citekey == "x2025" }?.venues, [.key("some-journal"), .literal("PSYCHOMETRIKA")])
        // 既有的重複邊（手改）不擋同一 work 上不相干的歸戶
        var z = Entry(id: UUID(), citekey: "z2025", type: .periodicalArticle, title: "T3")
        z.venues = [.key("some-journal"), .key("some-journal"), .literal("Other Journal")]
        _ = try store.writeEntry(z)
        _ = try service.resolveVenues(apply: ["z2025:2"])
        XCTAssertEqual(try store.load().entries.first { $0.citekey == "z2025" }?.venues, [.key("some-journal"), .key("some-journal"), .key("other-journal")])
    }

    /// **repoint 的唯一性只看被動到的邊，既有的重複不擋不相干的改指；同 literal 的兩個 move 只在 venue 集合相交時才拒**
    /// （R11 verify requirements 第 4／5 列、logic 第 17 列：venue 集合不相交的兩個 move 各在自己的檔裡退役、與順序無關，R11 的
    /// 訊息宣稱的機制在那一格為假、而它給的出路「分兩次呼叫」直接到達被拒的狀態）。
    func testRepointOnlyRefusesDuplicatesAndOverlapsThatTheMovesThemselvesCreate() throws {
        let store = LibraryStore(root: root)
        for (k, n) in [("beta-journal", "Beta Journal"), ("gamma-journal", "Gamma Journal"), ("delta-journal", "Delta Journal")] {
            _ = try service.addVenue(key: k, names: [n], type: "periodical", note: nil, issn: nil)
        }
        // 既有的重複邊（手改）＋ 一條經 apply 的 beta 邊：改指 beta 邊不被第 0／1 條的重複擋
        var z = Entry(id: UUID(), citekey: "z2025", type: .periodicalArticle, title: "T3")
        z.venues = [.key("some-journal"), .key("some-journal"), .literal("Beta Journal")]
        _ = try store.writeEntry(z)
        _ = try service.resolveVenues(apply: ["z2025:2"])
        _ = try service.resolveVenues(apply: nil, repoint: ["z2025:2:gamma-journal"])
        XCTAssertEqual(try store.load().entries.first { $0.citekey == "z2025" }?.venues, [.key("some-journal"), .key("some-journal"), .key("gamma-journal")])
        // 同 literal、venue 集合不相交：一批成功，四個 venue 各自正確
        var x = Entry(id: UUID(), citekey: "x2025", type: .periodicalArticle, title: "T")
        x.venues = [.key("some-journal"), .key("beta-journal")]
        _ = try store.writeEntry(x)
        for key in ["some-journal", "beta-journal"] {
            var v = try XCTUnwrap(store.load().venues.first { $0.key == key })
            v.references.append(ResolutionLedger.record(.confirmed, holderKind: .work, holder: "x2025", literal: "PSYCHOMETRIKA",
                                                        rule: ResolutionLedger.venueRule, statement: "手改"))
            try store.writeVenue(v)
        }
        _ = try service.resolveVenues(apply: nil, repoint: ["x2025:0:gamma-journal", "x2025:1:delta-journal"])
        let load = try store.load()
        XCTAssertEqual(load.entries.first { $0.citekey == "x2025" }?.venues, [.key("gamma-journal"), .key("delta-journal")])
        func kinds(_ key: String) throws -> [ResolutionLedger.VerdictKind] {
            let v = try XCTUnwrap(load.venues.first { $0.key == key })
            return ResolutionLedger.verdicts(references: v.references).0.filter { $0.holder == "x2025" }.map(\.kind)
        }
        XCTAssertEqual(try kinds("gamma-journal"), [.confirmed]); XCTAssertEqual(try kinds("delta-journal"), [.confirmed])
        XCTAssertEqual(try kinds("some-journal"), [.rejected]); XCTAssertEqual(try kinds("beta-journal"), [.rejected])
        XCTAssertTrue(store.contradictoryVerdictIssues(in: load).isEmpty)
    }

    /// **否決抑制與其餘三處同一把鍵**（R11 verify logic 第 8 列、regression 第 11 列：`VenueResolver` 的抑制比原始位元組，而
    /// `verdictEqualityKey`／#486 掃描／D25 一族全用 `matchingKey`——`apply → demote → apply` 三步全工具面就造出永久的矛盾對；
    /// `PersonResolver` 同一格早就修過且理由逐字寫在那裡）：demote 寫下的 rejected 也要壓住同配對的另一個拼法。
    func testRejectedPairingSuppressesNominationByNormalizedLiteral() throws {
        let store = LibraryStore(root: root)
        var e = Entry(id: UUID(), citekey: "x2025", type: .periodicalArticle, title: "T")
        e.venues = [.literal("Psychometrika"), .literal("PSYCHOMETRIKA")]
        _ = try store.writeEntry(e)
        _ = try service.resolveVenues(apply: ["x2025:0"])
        _ = try service.resolveVenues(apply: nil, demote: ["x2025:0"])
        let out = try service.resolveVenues(apply: nil)
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(out.utf8)) as? [String: Any])
        let ids = (json["candidates"] as? [[String: Any]] ?? []).compactMap { $0["id"] as? String }
        XCTAssertFalse(ids.contains { $0.hasPrefix("x2025:") }, "同配對的另一個拼法不得再被提名：\(ids)")
    }

    /// **`verdictsRetired` 迴送的 store 字串要逃脫不可見 scalar**（R11 verify security 第 10 列：它是這條路徑上第一個帶 store 字串的
    /// **成功** payload，而 `displaySafe` 的列舉不含 TAG 字元／ZWSP／變體選擇子——#569 的局部圍堵，以性質不以列舉）。
    func testVerdictsRetiredEscapesInvisibleScalars() throws {
        let store = LibraryStore(root: root)
        var e = Entry(id: UUID(), citekey: "x2025", type: .periodicalArticle, title: "T")
        e.venues = [.key("some-journal")]
        _ = try store.writeEntry(e)
        var v = try venue()
        v.references.append(ResolutionLedger.record(.confirmed, holderKind: .work, holder: "x2025", literal: "PSYCHOMETRIKA",
                                                    rule: ResolutionLedger.venueRule, statement: "手改\u{E0001}A\u{200B}B"))
        try store.writeVenue(v)
        let out = try service.resolveVenues(apply: nil, demote: ["x2025:0"])
        XCTAssertTrue(out.contains("\\\\u{E0001}") && out.contains("\\\\u{200B}"), out)
        XCTAssertFalse(out.unicodeScalars.contains { $0.value == 0xE0001 || $0.value == 0x200B }, "不得原樣迴送")
    }

    /// **no-op 早退也帶 D30 的三個鍵**（R11 verify logic 第 16 列）：同一個 tool 的 payload 形狀要一致，`truncated`／`verdictsRetiredTotal`
    /// 的 nil 與 0 語意本來就要分開。
    func testRepointNoOpPayloadCarriesTheRetiredKeys() throws {
        let store = LibraryStore(root: root)
        var e = Entry(id: UUID(), citekey: "x2025", type: .periodicalArticle, title: "T")
        e.venues = [.literal("PSYCHOMETRIKA")]
        _ = try store.writeEntry(e)
        _ = try service.resolveVenues(apply: ["x2025:0"])
        let out = try service.resolveVenues(apply: nil, repoint: ["x2025:0:some-journal"])
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(out.utf8)) as? [String: Any])
        XCTAssertEqual(json["repointed"] as? [String], [])
        XCTAssertEqual(json["verdictsRetiredTotal"] as? Int, 0, out)
        XCTAssertEqual(json["truncated"] as? Bool, false, out)
    }

    /// `add_venue` 送空陣列時說「是空的」，不說「全是空白」（R11 verify logic 第 26 列）。
    func testAddVenueDistinguishesEmptyNamesFromBlankNames() throws {
        XCTAssertThrowsError(try service.addVenue(key: "e", names: [], type: "periodical", note: nil, issn: nil)) {
            XCTAssertTrue(String(describing: $0).contains("是空的"), "\($0)")
        }
        XCTAssertThrowsError(try service.addVenue(key: "e", names: ["  "], type: "periodical", note: nil, issn: nil)) {
            XCTAssertTrue(String(describing: $0).contains("全是空白"), "\($0)")
        }
    }

    /// **`verdictsRetired` 有筆數上限與揭露**（R10 verify security 第 16 列、regression 第 19 列；Claude 代裁 D30）：它是兩個 payload
    /// 裡唯一由 store 內容而非呼叫端輸入決定體積的欄位（每項 ~520 字元；手改或 #553 合併吸收的 store 可有多筆同鍵 verdict，
    /// `supersede` 全退），而 MCP 的輸出進 LLM context——`akashic_enrich` 的既有形：截 20 筆、`verdictsRetiredTotal`／`truncated` 揭露。
    func testVerdictsRetiredIsCappedAndDisclosed() throws {
        let store = LibraryStore(root: root)
        _ = try service.addVenue(key: "beta-journal", names: ["Beta Journal"], type: "periodical", note: nil, issn: nil)
        var e = Entry(id: UUID(), citekey: "x2025", type: .periodicalArticle, title: "T")
        e.venues = [.literal("PSYCHOMETRIKA")]
        _ = try store.writeEntry(e)
        _ = try service.resolveVenues(apply: ["x2025:0"])
        var beta = try XCTUnwrap(store.load().venues.first { $0.key == "beta-journal" })
        for i in 0..<25 {
            beta.references.append(ResolutionLedger.record(.rejected, holderKind: .work, holder: "x2025", literal: "PSYCHOMETRIKA",
                                                           rule: ResolutionLedger.venueRule, statement: "手改 \(i)"))
        }
        try store.writeVenue(beta)
        let out = try service.resolveVenues(apply: nil, repoint: ["x2025:0:beta-journal"])
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(out.utf8)) as? [String: Any])
        XCTAssertEqual((json["verdictsRetired"] as? [String])?.count, 20, out)
        XCTAssertEqual(json["verdictsRetiredTotal"] as? Int, 26, "25 筆 rejected 在 to ＋ 1 筆 confirmed 在 from")
        XCTAssertEqual(json["truncated"] as? Bool, true)
        let single = try service.resolveVenues(apply: nil, demote: ["x2025:0"])
        let j2 = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(single.utf8)) as? [String: Any])
        XCTAssertEqual(j2["verdictsRetiredTotal"] as? Int, 1)
        XCTAssertEqual(j2["truncated"] as? Bool, false)
    }

    /// **`confirmedLiteral` 的去重是位元組相等，同 `matchingKey` 異位元組是拒絕不是「先到先贏」**（R9 verify DA 第 9 列）：
    /// R9 用 `matchingKey` 去重並回第一筆——`PSYCHOMETRIKA`／`Psychometrika` 兩條邊 apply 到同一 venue 後只剩一筆 verdict，
    /// `--demote` 邊 1 還回去的是邊 0 的字，正是同一則訊息承諾不做的「安靜改寫書目資料」。手改出來的同鍵異位元組 verdict
    /// 也一樣：不猜哪一筆是這條邊的。
    func testDemoteRefusesWhenTwoConfirmedVerdictsDifferOnlyInBytes() throws {
        let store = LibraryStore(root: root)
        var e = Entry(id: UUID(), citekey: "x2025", type: .periodicalArticle, title: "T")
        e.venues = [.literal("Psychometrika")]
        _ = try store.writeEntry(e)
        _ = try service.resolveVenues(apply: ["x2025:0"])
        var v = try venue()
        v.references.append(ResolutionLedger.record(.confirmed, holderKind: .work, holder: "x2025", literal: "PSYCHOMETRIKA",
                                                    rule: ResolutionLedger.venueRule, statement: "手改"))
        try store.writeVenue(v)
        XCTAssertThrowsError(try service.resolveVenues(apply: nil, demote: ["x2025:0"])) { err in
            let s = String(describing: err)
            XCTAssertTrue(s.contains("「Psychometrika」") && s.contains("「PSYCHOMETRIKA」"), s)
        }
        XCTAssertEqual(try store.load().entries.first?.venues, [.key("some-journal")], "零寫入")
    }

    /// **退役的 verdict 要具名，不只計數**（R9 verify security 第 4 列、logic 第 20 列、DA 第 29 列）：被刪的是人的判斷記錄
    /// （#553 合併會把被併 venue 的顯式 `--reject` 搬進 keeper，日後一次 repoint 就會退役它），`verdictsRetired: 1` 讓
    /// 「從未判定」與「判過、被這次刪了」在輸出上不可區分——`lossless-intake` 的「丟棄必須可見」。
    func testRetiredVerdictsAreNamedInThePayload() throws {
        let store = LibraryStore(root: root)
        var e = Entry(id: UUID(), citekey: "x2025", type: .periodicalArticle, title: "T")
        e.venues = [.literal("Psychometrika")]
        _ = try store.writeEntry(e)
        _ = try service.resolveVenues(apply: ["x2025:0"])
        let out = try service.resolveVenues(apply: nil, demote: ["x2025:0"])
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(out.utf8)) as? [String: Any])
        let retired = try XCTUnwrap(json["verdictsRetired"] as? [String], "要是清單：\(out)")
        XCTAssertEqual(retired.count, 1)
        XCTAssertTrue(retired[0].contains("some-journal") && retired[0].contains("resolution-confirmed") && retired[0].contains("Psychometrika"), retired[0])
    }

    /// **`addVenue` 回報存入的名字，不是呼叫端送的**（R9 verify logic 第 22 列）：R4 讓 `addVenue` 走 `vetVenueNames`
    /// （canonical、去空白項、近重複只留一筆），payload 卻仍回 `names` 原陣列——報告宣稱 store 沒有的字串，而且其中一個
    /// （`"Psychometrika "`）是不變式讓 store 不可能持有的。`updateVenue` 的 `namesAdded` 早就回 vetted 值。
    /// **折進 canonical 形的拼法報 `namesRewritten`，真的沒進 store 的才是 `namesDropped`**（R10 verify logic 第 14 列、regression 第 20 列、
    /// requirements 第 22 列）：R10 用位元組相等算 `namesDropped`，NFD 輸入同時出現在 `names` 與 `namesDropped`——兩個看起來一樣的字串
    /// 一個說存了一個說沒存，正是 R9 剛在 `authorizedRewritten` 修掉的歧義；鍵名說 dropped 而那個名字在 store 裡。`updateVenue` 的
    /// `add_names` 同一組欄位（先前只有 `namesAdded`，同一個入口兩種回報契約）。
    func testAddVenueReportsTheVettedNamesNotTheRawInput() throws {
        let out = try service.addVenue(key: "dup", names: ["Psychometrika", "Psychometrika ", "   ", "Sankhya\u{0304}"], type: "periodical", note: nil, issn: nil)
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(out.utf8)) as? [String: Any])
        XCTAssertEqual(json["names"] as? [String], ["Psychometrika", "Sankhyā"])
        let folded = try XCTUnwrap(json["namesFolded"] as? [String], out)
        XCTAssertEqual(folded, ["Psychometrika ", "Sankhyā"], "折進 canonical 形的拼法——store 收了那個名字，不是 dropped：\(out)")
        XCTAssertEqual(Array(folded[1].utf8).count, 9, "回報的是原拼法（NFD 位元組），不是存入的")
        XCTAssertEqual(json["namesDropped"] as? [String], ["   "], "真的沒進 store 的才叫 dropped：\(out)")
        // R11 verify 第 15／19／21 列：「已存在」（不論位元組）要自己一桶，與 `alreadyAuthorized`「冪等，但要說」同一立場；
        // `folded` 只留給這次真的存進去、而拼法被折過的
        let upd = try service.updateVenue(key: "some-journal", addNames: ["Psychometrika ", "PSYCHOMETRIKA ", "PSYCHOMETRIKA", " "], note: nil, type: nil)
        let j2 = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(upd.utf8)) as? [String: Any])
        XCTAssertEqual(j2["namesAdded"] as? [String], ["Psychometrika"])
        XCTAssertEqual(j2["namesFolded"] as? [String], ["Psychometrika "], upd)
        XCTAssertEqual(j2["namesAlreadyPresent"] as? [String], ["PSYCHOMETRIKA ", "PSYCHOMETRIKA"], upd)
        XCTAssertEqual(j2["namesDropped"] as? [String], [" "], upd)
    }

    /// **NFD 自我修復要報在自己的桶**（R9 verify logic 第 23 列）：`already` 用 canonical 相等算，手改成 NFD 的 authorized
    /// 被 `--authorize`（NFC）修正時同一個可見字串同時落在 `alreadyAuthorized` 與 `authorizedRemoved`、`authorizedAdded` 空——
    /// 操作者看不出改了什麼，正是 R4 第 6 列那道守衛要防的 no-op 宣稱。改報 `authorizedRewritten`。
    func testByteRepairOfAuthorizedIsReportedAsRewrittenNotAlready() throws {
        _ = try service.updateVenue(key: "some-journal", addNames: ["Sankhyā"], note: nil, type: nil)
        _ = try service.updateVenue(key: "some-journal", addNames: nil, note: nil, type: nil, authorize: ["Sankhyā"])
        let v = try venue()
        try rewriteFile(v) { $0.replacingOccurrences(of: "authorized:\n- Sankhyā\n", with: "authorized:\n- Sankhya\u{0304}\n") }
        XCTAssertEqual(Array(try venue().authorized[0].utf8).count, 9, "fixture：authorized 現在是 NFD 位元組")
        let out = try service.updateVenue(key: "some-journal", addNames: nil, note: nil, type: nil, authorize: ["Sankhyā"])
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(out.utf8)) as? [String: Any])
        XCTAssertEqual(json["authorizedRewritten"] as? [String], ["Sankhyā"], out)
        XCTAssertEqual(json["alreadyAuthorized"] as? [String], [])
        XCTAssertEqual(json["authorizedRemoved"] as? [String], [])
        XCTAssertEqual(Array(try venue().authorized[0].utf8).count, 8, "存回 NFC")
    }

    /// 「找不到 confirmed verdict」的拒絕要指出路（R8 verify 第 33 列，security）：與懸空 from-key 那句一樣——
    /// 手改 work 的 YAML 把這條邊改回 `- literal:`，再 `--apply` 重新歸戶（那一步會寫下 verdict）。repoint 與 demote 都要。
    func testMissingVerdictRefusalsPointToTheExit() throws {
        let store = LibraryStore(root: root)
        var e = Entry(id: UUID(), citekey: "x2025", type: .periodicalArticle, title: "A Paper")
        e.venues = [.key("some-journal")]
        _ = try store.writeEntry(e)
        _ = try service.addVenue(key: "other-journal", names: ["Other Journal"], type: "periodical", note: nil, issn: nil)
        for op in [{ try self.service.resolveVenues(apply: nil, repoint: ["x2025:0:other-journal"]) },
                   { try self.service.resolveVenues(apply: nil, demote: ["x2025:0"]) }] {
            XCTAssertThrowsError(try op()) { err in
                let s = String(describing: err)
                XCTAssertTrue(s.contains("- literal:") && s.contains("--apply"), s)
            }
        }
    }

    /// 原字串的 120 上限以 scalar 計（R7 verify 第 16 列）：`String.prefix` 數 grapheme cluster，combining-mark 密集的輸入
    /// 120 個 Character 可以是 596 個 scalar，整項再被 `displaySafe(max: 400)` 截掉——理由又不見了。
    func testRejectionKeepsTheReasonForCombiningMarkHeavyInput() throws {
        let heavy = String(repeating: "q\u{0334}\u{0335}\u{0336}\u{0337}", count: 119) + "\u{200B}"
        XCTAssertThrowsError(try service.updateVenue(key: "some-journal", addNames: [heavy], note: nil, type: nil)) { err in
            XCTAssertTrue(String(describing: err).contains("U+200B"), "理由被截掉了：\(String(describing: err).suffix(60))")
        }
    }

    /// 拒絕訊息**兩面各自正確**（R6 verify 第 45 列）：R5 讓訊息帶參數名，但 CLI 使用者看到的是 MCP 鍵名
    /// （`--add-name` 拒絕時印「add_names 的…」）。兩個名字都印。
    func testRejectionNamesBothFacesParameter() throws {
        XCTAssertThrowsError(try service.updateVenue(key: "some-journal", addNames: ["×"], note: nil, type: nil)) { err in
            let s = String(describing: err)
            XCTAssertTrue(s.contains("add_names") && s.contains("--add-name"), s)
        }
    }

    /// **原字串有自己的上限，理由不會被截掉**（R6 verify 第 7／12／25 列）：R6 的註解與 #562 comment 說
    /// 「每項 400（原字串 120 ＋ 理由）」，程式只對整項截 400——貼錯一整段摘要時操作者只看到被截斷的名字。
    func testRejectionKeepsTheReasonForAVeryLongInput() throws {
        let long = String(repeating: "x", count: 600) + "\u{200B}"
        XCTAssertThrowsError(try service.updateVenue(key: "some-journal", addNames: [long], note: nil, type: nil)) { err in
            let s = String(describing: err)
            XCTAssertTrue(s.contains("U+200B"), "理由被截掉了：\(s.suffix(80))")
            XCTAssertLessThan(s.count, 400)
        }
    }

    /// `repoint`／`demote` 同序（同一列）——這裡用 demote：先 apply 一筆乾淨的，再把 venue 弄髒，demote 必須零寫入。
    func testResolveVenuesDemoteWritesNothingWhenTheVenueIsUnwritable() throws {
        let store = LibraryStore(root: root)
        var e = Entry(id: UUID(), citekey: "x2025", type: .periodicalArticle, title: "T")
        e.venues = [.literal("Psychometrika")]
        _ = try store.writeEntry(e)
        _ = try service.resolveVenues(apply: ["x2025:0"])
        XCTAssertEqual(try store.load().entries.first?.venues, [.key("some-journal")])
        let v = try venue()
        try rewriteFile(v) { $0.replacingOccurrences(of: "- value: PSYCHOMETRIKA\n", with: "- value: 'PSYCHOMETRIKA '\n") }
        XCTAssertThrowsError(try service.resolveVenues(apply: nil, demote: ["x2025:0"]))
        XCTAssertEqual(try store.load().entries.first?.venues, [.key("some-journal")], "entry 不得先退回 literal")
    }
}
