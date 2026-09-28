import Foundation
import XCTest
@testable import AkashicCore
@testable import AkashicStoreIO
@testable import AkashicMCPKit

/// #587：查證取得的 ISSN 帶得了角色與來源進 store。
///
/// 兩個缺口，都在寫入面：(1) `add_issn`／`add_venue.issn` 記不下 medium（`ISSN.init` 把它設 nil，而來源——Crossref
/// `issn-type`、ISSN Portal——是給角色的；live store 的 9 個帶 qualifier 的號全來自遷移）；(2) venue 沒有通用的 `references`
/// 寫入面（`validateReferenceAttachment` 早有 `case "issn"`，缺的是寫入面）。
final class VenueReferenceWriteTests: XCTestCase {
    private var root: URL!
    private var store: LibraryStore!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("akashic-venue-refs-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("entities"), withIntermediateDirectories: true)
        try StoreVersion.write(root: root, format: StoreVersion.supported)
        store = LibraryStore(root: root)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    private var service: AkashicService { AkashicService(root: root) }
    private let digest = "sha256:" + String(repeating: "ab", count: 32)
    private let otherDigest = "sha256:" + String(repeating: "cd", count: 32)

    private func json(_ s: String) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: Data(s.utf8)) as? [String: Any])
    }
    private func venue(_ key: String = "ampsy") throws -> Venue {
        try XCTUnwrap(try store.load().venues.first { $0.key == key })
    }
    /// 整個 entities 目錄的位元組——「零寫入」要比位元組，不比挑出來的欄位。
    private func snapshot() throws -> [String: Data] {
        let dir = root.appendingPathComponent("entities")
        var out: [String: Data] = [:]
        for name in try FileManager.default.contentsOfDirectory(atPath: dir.path) {
            out[name] = try Data(contentsOf: dir.appendingPathComponent(name))
        }
        return out
    }
    private func seed(issn: [String]? = nil) throws {
        _ = try service.addVenue(key: "ampsy", names: ["American Psychologist"], type: "periodical",
                                 note: nil, issn: issn)
    }
    private func retrieval(field: String = "issn", value: String? = "0003-066X",
                           extra: [String: Any] = [:]) -> [String: Any] {
        var d: [String: Any] = ["field": field, "kind": "retrieval",
                                "url": "https://portal.issn.org/resource/ISSN/0003-066X",
                                "retrieved": "2026-09-29", "status": 200,
                                "media_type": "text/html", "content": digest]
        if let value { d["value"] = value }
        return d.merging(extra) { _, new in new }
    }
    private func update(addISSN: [String]? = nil, removeISSN: [String]? = nil,
                        addNames: [String]? = nil, references: [Any]? = nil) throws -> [String: Any] {
        try json(try service.updateVenue(key: "ampsy", addNames: addNames, note: nil, type: nil,
                                         addISSN: addISSN, removeISSN: removeISSN, references: references))
    }

    // MARK: - medium

    func testAddISSNRecordsTheMediumGivenInParentheses() throws {
        try seed()
        let out = try update(addISSN: ["0003-066X (print)", "1935-990X(Electronic)"])
        let v = try venue()
        XCTAssertEqual(v.issn.map(\.normalized), ["0003-066X", "1935-990X"])
        XCTAssertEqual(v.issn.map(\.medium), [.print, .electronic])
        XCTAssertEqual(v.issn.map(\.qualifierRaw), ["print", "electronic"], "角色以封閉值域的寫法入庫（live store 的 9 筆都是小寫）")
        XCTAssertEqual(out["issnAdded"] as? [String], ["0003-066X", "1935-990X"])
        XCTAssertEqual(out["issnMediumRecorded"] as? [String: String],
                       ["0003-066X": "print", "1935-990X": "electronic"], "\(out)")
    }

    func testAddVenueRecordsTheMedium() throws {
        let out = try json(try service.addVenue(key: "brm", names: ["Behavior Research Methods"], type: "periodical",
                                                note: nil, issn: ["1554-351X (Print)", "1554-3528 (linking)"]))
        let v = try venue("brm")
        XCTAssertEqual(v.issn.map(\.medium), [.print, .linking])
        XCTAssertEqual(out["issn"] as? [String], ["1554-351X", "1554-3528"])
        XCTAssertEqual(out["issnMediumRecorded"] as? [String: String], ["1554-351X": "print", "1554-3528": "linking"])
    }

    /// 已在的號沒有角色、這次帶了角色：補上（add-only——填一個缺席的格），不是新號。
    func testMediumFillsAnExistingNumberThatHadNone() throws {
        try seed(issn: ["0003-066X"])
        let out = try update(addISSN: ["0003-066x (print)"])
        XCTAssertEqual(try venue().issn.map(\.medium), [.print])
        XCTAssertEqual(out["issnAdded"] as? [String], [])
        XCTAssertEqual(out["issnMediumRecorded"] as? [String: String], ["0003-066X": "print"])
        XCTAssertEqual(out["issnAlreadyPresent"] as? [String], [], "補了角色的號不算「本來就在、什麼都沒做」")
    }

    func testAlreadyPresentNumbersAreReported() throws {
        try seed(issn: ["0003-066X (print)"])
        let out = try update(addISSN: ["0003-066X", "0003-066x (print)", "1935-990X"])
        XCTAssertEqual(out["issnAdded"] as? [String], ["1935-990X"])
        XCTAssertEqual(out["issnAlreadyPresent"] as? [String], ["0003-066X"], "冪等，但要說：\(out)")
        XCTAssertEqual(try venue().issn.first?.medium, .print, "沒帶角色不得洗掉既有角色")
    }

    /// 既有角色與這次的不同：兩句矛盾的話，整批拒絕——改寫既有角色不在本面。
    func testConflictingMediumRefusesTheWholeCall() throws {
        try seed(issn: ["0003-066X (print)"])
        let before = try snapshot()
        XCTAssertThrowsError(try update(addISSN: ["1935-990X", "0003-066X (electronic)"])) { error in
            XCTAssertTrue("\(error)".contains("print") && "\(error)".contains("electronic"), "\(error)")
        }
        XCTAssertThrowsError(try update(addISSN: ["1935-990X (print)", "1935-990X (electronic)"]), "同一次呼叫的兩個角色")
        XCTAssertEqual(try snapshot(), before, "零寫入")
    }

    /// 角色不在封閉值域、形狀不是「一個號＋至多一個緊跟的括號」：整批拒絕，不猜、不靜默丟。
    func testMalformedMediumOrShapeIsRefused() throws {
        try seed()
        let before = try snapshot()
        for bad in ["0003-066X (Online)", "(print) 0003-066X", "0003-066X (print) (electronic)",
                    "0003-066X (print", "0003-066X 1935-990X", "0003-066X, 1935-990X", "0003-066X (print)x",
                    "0003-0660 (print)"] {
            XCTAssertThrowsError(try update(addISSN: [bad]), bad) { error in
                XCTAssertTrue("\(error)".contains("ISSN") || "\(error)".contains("角色"), "\(bad)：\(error)")
            }
            XCTAssertThrowsError(try service.addVenue(key: "other", names: ["Other"], type: "periodical",
                                                      note: nil, issn: [bad]), bad)
        }
        XCTAssertEqual(try snapshot(), before, "零寫入")
    }

    /// 回歸：`ISSN.init` 本來就收的寫法（空白、無連字號）照收。
    func testBareShapesThatWereAcceptedStillAre() throws {
        try seed()
        _ = try update(addISSN: ["0003 066X", "1935990x"])
        XCTAssertEqual(try venue().issn.map(\.normalized), ["0003-066X", "1935-990X"])
        XCTAssertEqual(try venue().issn.map(\.medium), [nil, nil])
    }

    /// #556 R2 verify：空白項先前靜默略過；names／variant／authorize 各有 dropped 桶，ISSN 沒有。
    func testBlankItemsAreReportedAsDropped() throws {
        try seed()
        let out = try update(addISSN: ["", "0003-066X", "  "])
        XCTAssertEqual(out["issnDropped"] as? [String], ["", "  "], "\(out)")
        let created = try json(try service.addVenue(key: "other", names: ["Other"], type: "periodical",
                                                    note: nil, issn: [" ", "1935-990X"]))
        XCTAssertEqual(created["issnDropped"] as? [String], [" "], "\(created)")
    }

    /// 帶角色的號同時出現在 remove_issn：矛盾檢查要認得它（它不是裸號，`ISSN(_:)` 對它回 nil）。
    func testAnnotatedAddAndRemoveOfTheSameNumberIsAContradiction() throws {
        try seed(issn: ["0035-9254"])
        XCTAssertThrowsError(try update(addISSN: ["0035-9254 (print)"], removeISSN: ["0035-9254=姊妹刊"])) { error in
            XCTAssertTrue("\(error)".contains("同時在 add_issn 與 remove_issn"), "\(error)")
        }
    }

    // MARK: - references

    func testRetrievalReferenceForAnISSNIsWritten() throws {
        try seed(issn: ["0003-066X"])
        let out = try update(references: [retrieval(value: "0003-066x")])
        XCTAssertEqual(out["referencesAdded"] as? Int, 1, "\(out)")
        XCTAssertEqual(out["referencesAlreadyPresent"] as? Int, 0)
        let r = try XCTUnwrap(try venue().references.first)
        XCTAssertEqual(r.field, "issn")
        XCTAssertEqual(r.value, "0003-066X", "號以正規形當定位值（識別碼在寫入面正規化）")
        guard case .retrieval(let url, _, let status, let mt, let content) = r.kind else { return XCTFail("\(r.kind)") }
        XCTAssertEqual(url, "https://portal.issn.org/resource/ISSN/0003-066X")
        XCTAssertEqual(status, 200)
        XCTAssertEqual(mt, "text/html")
        XCTAssertEqual(content, digest)
    }

    /// 查到號的同一次呼叫就能連來源一起寫：號先落、reference 後附。
    func testNumberMediumAndProvenanceInOneCall() throws {
        try seed()
        _ = try update(addISSN: ["0003-066X (print)"], references: [retrieval()])
        let v = try venue()
        XCTAssertEqual(v.issn.first?.medium, .print)
        XCTAssertEqual(v.references.map(\.field), ["issn"])
    }

    func testJudgementReferenceOnANameIsWritten() throws {
        try seed()
        let out = try update(references: [["field": "names", "value": "American Psychologist", "kind": "judgement",
                                           "statement": "APA 的刊名頁印這個名字", "rests_on": [digest, otherDigest]]])
        XCTAssertEqual(out["referencesAdded"] as? Int, 1)
        guard case .judgement(let s, let restsOn) = try XCTUnwrap(try venue().references.first).kind else { return XCTFail() }
        XCTAssertEqual(s, "APA 的刊名頁印這個名字")
        XCTAssertEqual(restsOn, [digest, otherDigest])
    }

    /// 名字的定位值以**記錄上的拼法**入庫：只差 NFC／NFD 或空白的兩筆 reference 否則會是兩筆位元組不同的記錄——#582 的
    /// 重複 reference 掃描會把它們報成 warning，而它們指的是同一個名字。
    func testNameLocatorIsStoredInTheRecordsSpelling() throws {
        _ = try service.addVenue(key: "sankhya", names: ["Sankhy\u{0101}"], type: "periodical", note: nil)
        let judgement: (String) -> [String: Any] = { v in
            ["field": "names", "value": v, "kind": "judgement", "statement": "刊名頁", "rests_on": [self.digest]]
        }
        let first = try json(try service.updateVenue(key: "sankhya", addNames: nil, note: nil, type: nil,
                                                     references: [judgement("Sankhya\u{0304}")]))
        XCTAssertEqual(first["referencesAdded"] as? Int, 1)
        let stored = try XCTUnwrap(try venue("sankhya").references.first?.value)
        XCTAssertEqual(Array(stored.utf8), Array("Sankhy\u{0101}".utf8), "存記錄上的位元組（NFC），不是呼叫端的 NFD")
        let again = try json(try service.updateVenue(key: "sankhya", addNames: nil, note: nil, type: nil,
                                                     references: [judgement(" Sankhy\u{0101} ")]))
        XCTAssertEqual(again["referencesAlreadyPresent"] as? Int, 1, "指同一個名字的同一筆判定：\(again)")
        XCTAssertEqual(try venue("sankhya").references.count, 1)
    }

    /// append-only、位元組相同的略過（同 update_person 的 references）。同一次呼叫裡的重複也算。
    func testAppendIsIdempotentByBytes() throws {
        try seed(issn: ["0003-066X"])
        _ = try update(references: [retrieval()])
        let out = try update(references: [retrieval(), retrieval()])
        XCTAssertEqual(out["referencesAdded"] as? Int, 0)
        XCTAssertEqual(out["referencesAlreadyPresent"] as? Int, 2)
        XCTAssertEqual(try venue().references.count, 1)
        let other = try update(references: [retrieval(extra: ["retrieved": "2026-09-30"])])
        XCTAssertEqual(other["referencesAdded"] as? Int, 1, "另一次取得是另一筆")
    }

    /// verdict 只經 resolve-venues 寫、paginated 判定只經 paginated／clear_paginated 寫——通用面不收。
    func testVerdictAndPaginatedFieldsAreRefused() throws {
        try seed()
        let before = try snapshot()
        // value 取該欄位合法的形——附著驗證會放行它們，擋下它們的只能是寫入面的歸屬檢查
        for (field, value) in [("resolution-confirmed", "work:x :: X"), ("resolution-rejected", "work:x :: X"),
                               ("resolution-undecided", "work:x :: X"), ("paginated", "true")] {
            XCTAssertThrowsError(try update(references: [["field": field, "value": value, "kind": "judgement",
                                                          "statement": "s", "rests_on": [digest]]]), field) { error in
                XCTAssertTrue("\(error)".contains(field == "paginated" ? "clear_paginated" : "resolve-venues"), "\(field)：\(error)")
            }
        }
        XCTAssertEqual(try snapshot(), before)
    }

    /// 形狀驗證走 ProvenanceReference 的平面 init（唯一入口）；寫入面只多三件事：鍵名嚴格、kind 要與給的欄位一致、有界。
    /// 每一格都整批拒絕、零寫入。
    func testMalformedReferencesAreRefusedWithZeroWrite() throws {
        try seed(issn: ["0003-066X"])
        let emptyDigest = ProvenanceReference.emptyContentDigest
        var noContent = retrieval(); noContent.removeValue(forKey: "content")
        var noStatus = retrieval(); noStatus.removeValue(forKey: "status")
        // (標籤, references, 錯誤訊息要說出的片段)——只斷言「有丟錯」的話，每一格都可能是被同一個無關的錯擋下
        let cases: [(String, [Any], String)] = [
            ("缺 content", [noContent], "content"),
            ("缺 status（不預設 200）", [noStatus], "status"),
            ("status 是 boolean", [retrieval(extra: ["status": true])], "status 必須是整數"),
            ("status 不是整數", [retrieval(extra: ["status": 200.5])], "status 必須是整數"),
            ("status 是字串", [retrieval(extra: ["status": "200"])], "status 必須是整數"),
            ("digest 形狀錯", [retrieval(extra: ["content": "sha256:xyz"])], "digest 形狀"),
            ("空內容的 digest", [retrieval(extra: ["content": emptyDigest])], "0 byte"),
            ("判斷型帶 content", [retrieval(extra: ["statement": "s"])], "不得帶 content"),
            ("兩種 kind 混用", [["field": "names", "value": "American Psychologist", "kind": "judgement",
                              "url": "https://x/", "statement": "s", "rests_on": [digest]]], "不得混用"),
            ("kind 與欄位不符", [["field": "names", "value": "American Psychologist", "kind": "retrieval", "statement": "s", "rests_on": [digest]]], "給的欄位卻是另一種"),
            ("kind 不認得", [retrieval(extra: ["kind": "citation"])], "kind 必須是"),
            ("judgement 沒有 rests_on", [["field": "names", "value": "American Psychologist", "kind": "judgement", "statement": "s"]], "rests-on"),
            ("rests_on 不是字串陣列", [["field": "names", "value": "American Psychologist", "kind": "judgement",
                                   "statement": "s", "rests_on": digest]], "rests_on 必須是字串陣列"),
            ("不認得的鍵（YAML 鍵名 judgement 不是 JSON 鍵名 statement）",
             [["field": "names", "value": "American Psychologist", "kind": "judgement", "judgement": "s", "rests_on": [digest]]], "不認得的鍵"),
            ("元素不是物件", ["issn"], "必須是物件"),
            ("空陣列", [], "空陣列"),
            ("field 空白", [retrieval(field: "")], "缺 field"),
            ("通用面不收的欄位", [retrieval(field: "title", value: nil)], "通用 references 面只收 issn 與 names"),
            ("authorized 拒收（會鎖住 authorize 的換名）", [retrieval(field: "authorized", value: "American Psychologist")], "會讓 authorize 換不了對外形」＋「沒有移除面"),
            ("號不在 issn 清單", [retrieval(value: "1935-990X")], "references 附不上」＋「不在 issn 清單內"),
            ("號帶角色", [retrieval(value: "0003-066X (print)")], "不是合法的 ISSN"),
            ("issn 沒帶 value", [retrieval(value: nil)], "references 附不上」＋「必須帶 value"),
            ("name 不在 names", [["field": "names", "value": "Amer Psych", "kind": "judgement", "statement": "s", "rests_on": [digest]]], "references 附不上」＋「不在 names 內"),
            ("note 拒收（沒有寫入面）", [retrieval(field: "note", value: nil)], "venue 的 note 沒有工具寫入面"),
            ("statement 超過 4,096 位元組", [["field": "names", "value": "American Psychologist", "kind": "judgement",
                                         "statement": String(repeating: "理", count: 1_366), "rests_on": [digest]]], "statement 超過"),
            ("rests_on 超過 20 個", [["field": "names", "value": "American Psychologist", "kind": "judgement", "statement": "s",
                                   "rests_on": (0..<21).map { "sha256:" + String(format: "%064x", $0 + 1) }]], "最多 20 個 digest"),
            ("url 超過字串上限", [retrieval(extra: ["url": "https://x/" + String(repeating: "a", count: AddOnlyEnrichment.maxValueBytes)])], "url 超過"),
            ("一次超過 200 筆", Array(repeating: retrieval(), count: 201), "一次最多 200 筆"),
        ]
        let before = try snapshot()
        for (label, refs, needle) in cases {
            // 「＋」分隔的每一段都要出現——附著類的錯要說出是 references 這個參數附不上（寫入時的 canary 也會擋，但說不出參數）
            XCTAssertThrowsError(try update(references: refs), label) { error in
                for part in needle.components(separatedBy: "」＋「") {
                    XCTAssertTrue("\(error)".contains(part), "\(label)：要說出「\(part)」，實得 \(error)")
                }
            }
            // 同一次呼叫的其他參數也不寫
            XCTAssertThrowsError(try update(addNames: ["APA Journal"], references: refs), label)
        }
        XCTAssertEqual(try snapshot(), before, "零寫入")
    }

    /// #587 R1（regression 席以真 service 重現）：通用面若收 `field: authorized`，寫進去之後 `authorize` 換對外形會被那筆 reference
    /// 擋下（「移出後它們成孤兒」），而 venue 的 reference 沒有移除面——只能手改 YAML。通用面不收它，換名就不會被鎖。
    func testAuthorizedReferenceIsRefusedSoAuthorizeCanStillChangeTheDisplayForm() throws {
        _ = try service.addVenue(key: "ampsy", names: ["Alpha Journal", "Beta Journal"], type: "periodical", note: nil)
        _ = try json(try service.updateVenue(key: "ampsy", addNames: nil, note: nil, type: nil, authorize: ["Alpha Journal"]))
        XCTAssertThrowsError(try update(references: [retrieval(field: "authorized", value: "Alpha Journal")])) { error in
            XCTAssertTrue("\(error)".contains("authorize"), "\(error)")
        }
        let out = try json(try service.updateVenue(key: "ampsy", addNames: nil, note: nil, type: nil, authorize: ["Beta Journal"]))
        XCTAssertEqual(out["authorizedAdded"] as? [String], ["Beta Journal"], "換對外形沒被鎖：\(out)")
        XCTAssertEqual(try venue().authorized, ["Beta Journal"])
    }

    /// 指向同一次呼叫裡被移除的號：兩句矛盾的話，在讀 store 之前擋。
    func testReferenceToANumberBeingRemovedIsAContradiction() throws {
        try seed(issn: ["0035-9254"])
        XCTAssertThrowsError(try update(removeISSN: ["0035-9254=姊妹刊"], references: [retrieval(value: "0035-9254")])) { error in
            XCTAssertTrue("\(error)".contains("remove_issn"), "\(error)")
        }
    }

    /// 只看參數的檢查是同一個函式（CLI 的 `validate()` 用它）：不碰 store 就能拒。
    func testArgumentChecksDoNotNeedTheStore() throws {
        XCTAssertThrowsError(try AkashicService.checkUpdateVenueArguments(
            addNames: nil, type: nil, addISSN: ["0003-066X (Online)"], addVariant: nil, authorize: nil,
            paginated: nil, clearPaginated: false, judgement: nil, restsOn: nil, removeISSN: nil, references: nil))
        XCTAssertThrowsError(try AkashicService.checkUpdateVenueArguments(
            addNames: nil, type: nil, addISSN: nil, addVariant: nil, authorize: nil,
            paginated: nil, clearPaginated: false, judgement: nil, restsOn: nil, removeISSN: nil,
            references: [["field": "paginated", "value": "true", "kind": "judgement", "statement": "s", "rests_on": [digest]]]))
        XCTAssertNoThrow(try AkashicService.checkUpdateVenueArguments(
            addNames: nil, type: nil, addISSN: ["0003-066X (print)"], addVariant: nil, authorize: nil,
            paginated: nil, clearPaginated: false, judgement: nil, restsOn: nil, removeISSN: nil,
            references: [retrieval()]))
    }
}
