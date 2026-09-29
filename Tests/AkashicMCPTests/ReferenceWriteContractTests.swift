import XCTest
import Foundation
@testable import AkashicCore
@testable import AkashicStoreIO
@testable import AkashicMCPKit

/// #674：`update_person` 與 `update_venue` 的 references 寫入面是**同一份契約**（同一個解析函式）。
///
/// 兩個面先前各自演化：person 側 `status` 預設 200、未知鍵靜默忽略、值的型別靜默轉成 nil、沒有上限；venue 側（#587）比它嚴。
/// 這裡的每一格都**同時**對兩個面跑同一個輸入——一個面放行、另一個拒絕，或兩個面說了不同的話，就是分岔回來了。
/// 兩面各自的欄位收哪些（person 收 orcid 等、venue 只收 issn／names）是 holder 的政策，不在這張表裡；表裡只放兩面共用的形狀。
final class ReferenceWriteContractTests: XCTestCase {
    private var root: URL!
    private var service: AkashicService!
    private let digest = "sha256:" + String(repeating: "ab", count: 32)

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("akashic-refcontract-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root.appendingPathComponent("entities"), withIntermediateDirectories: true)
        try StoreVersion.write(root: root, format: StoreVersion.supported)
        let store = LibraryStore(root: root)
        var p = Person(key: "p-one", names: PersonNames(authorized: ["Che Cheng"]))
        p.orcid = ORCID("0000-0003-4038-9439")
        try store.writePerson(p)
        service = AkashicService(root: root)
        _ = try service.addVenue(key: "ampsy", names: ["American Psychologist"], type: "periodical", note: nil, issn: ["0003-066X"])
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    // MARK: - 兩個面

    private func person(_ refs: [Any], dryRun: Bool = false) throws {
        _ = try service.updatePerson(key: "p-one", fields: ["references": refs], dryRun: dryRun)
    }
    private func venue(_ refs: [Any]) throws {
        _ = try service.updateVenue(key: "ampsy", addNames: nil, note: nil, type: nil, references: refs)
    }

    /// 兩個面的基底輸入：同一個形狀，差在 holder 的欄位（person 的 orcid 是純量、不帶 value；venue 的 issn 帶 value）。
    private func retrievalBase(person: Bool) -> [String: Any] {
        var d: [String: Any] = ["field": person ? "orcid" : "issn", "kind": "retrieval",
                                "url": "https://example.org/record/1", "retrieved": "2026-09-29", "status": 200,
                                "media_type": "text/html", "content": digest]
        if !person { d["value"] = "0003-066X" }
        return d
    }
    private func judgementBase(person: Bool) -> [String: Any] {
        person
            ? ["field": "orcid", "kind": "judgement", "statement": "官方頁面印這個號", "rests_on": [digest]]
            : ["field": "names", "value": "American Psychologist", "kind": "judgement",
               "statement": "官方頁面印這個名字", "rests_on": [digest]]
    }

    private func snapshot() throws -> [String: Data] {
        let dir = root.appendingPathComponent("entities")
        var out: [String: Data] = [:]
        for name in try FileManager.default.contentsOfDirectory(atPath: dir.path) {
            out[name] = try Data(contentsOf: dir.appendingPathComponent(name))
        }
        return out
    }

    private func message(_ error: Error) -> String {
        if case ServiceError.invalid(let why) = error { return why }
        return "\(error)"
    }

    private struct Case {
        let label: String
        let judgement: Bool
        let mutate: (inout [String: Any]) -> Void
        let needle: String
        init(_ label: String, judgement: Bool = false, needle: String, _ mutate: @escaping (inout [String: Any]) -> Void) {
            self.label = label; self.judgement = judgement; self.needle = needle; self.mutate = mutate
        }
    }

    /// 兩個面共用的拒絕格：每一格對 person 與 venue **都**要丟出含該句的參數錯誤，且零寫入。
    func testBothFacesRefuseTheSameShapesWithTheSameWords() throws {
        let cases: [Case] = [
            // #542 R2：不預設 200——離線來源會被記成 HTTP 200
            Case("缺 status（不預設 200）", needle: "status") { $0.removeValue(forKey: "status") },
            Case("status 是 boolean（JSON 的 true 不是 1）", needle: "status 必須是整數") { $0["status"] = true },
            Case("status 不是整數", needle: "status 必須是整數") { $0["status"] = 200.5 },
            Case("status 是字串", needle: "status 必須是整數") { $0["status"] = "200" },
            Case("status 低於 100", needle: "100–599") { $0["status"] = 99 },
            Case("status 高於 599", needle: "100–599") { $0["status"] = 600 },
            Case("status 是 0", needle: "100–599") { $0["status"] = 0 },
            Case("status 是負數", needle: "100–599") { $0["status"] = -5 },
            // 未知鍵：person 側先前靜默忽略——打錯的鍵名不出聲
            Case("不認得的鍵（media_type 打成 mediatype）", needle: "不認得的鍵") { $0["mediatype"] = "text/html" },
            Case("不認得的鍵（YAML 鍵名 rests-on）", judgement: true, needle: "不認得的鍵") { $0["rests-on"] = ["x"] },
            Case("不認得的鍵（YAML 鍵名 judgement）", judgement: true, needle: "不認得的鍵") { $0["judgement"] = "s" },
            // 型別：person 側先前把非字串的 value／media_type、非字串陣列的 rests_on 靜默變成 nil／空
            Case("value 不是字串", needle: "value 必須是字串") { $0["value"] = 42 },
            Case("media_type 不是字串", needle: "media_type 必須是字串") { $0["media_type"] = 5 },
            Case("rests_on 不是字串陣列", judgement: true, needle: "rests_on 必須是字串陣列") { $0["rests_on"] = [1, 2] },
            Case("rests_on 是單一字串", judgement: true, needle: "rests_on 必須是字串陣列") { $0["rests_on"] = "sha256:x" },
            // 上限：person 側先前沒有
            Case("statement 超過 4,096 位元組", judgement: true, needle: "statement 超過") { $0["statement"] = String(repeating: "理", count: 1_366) },
            Case("rests_on 超過 20 個", judgement: true, needle: "最多 20 個 digest") {
                $0["rests_on"] = (0..<21).map { "sha256:" + String(format: "%064x", $0 + 1) }
            },
            Case("url 超過字串上限", needle: "url 超過") { $0["url"] = "https://x/" + String(repeating: "a", count: AddOnlyEnrichment.maxValueBytes) },
            // #674 補充範圍：url 只收 http／https、不含帳密；retrieved 是 ISO 8601
            Case("url 是 ftp", needle: "http／https") { $0["url"] = "ftp://example.org/x" },
            Case("url 是 file（離線來源改用 judgement 型）", needle: "judgement") { $0["url"] = "file:///Users/x/scan.pdf" },
            Case("url 沒有 scheme", needle: "http／https") { $0["url"] = "u" },
            Case("url 是 javascript:", needle: "http／https") { $0["url"] = "javascript:alert(1)" },
            Case("url 缺主機", needle: "主機") { $0["url"] = "https:///path" },
            Case("url 帶帳密", needle: "帳密") { $0["url"] = "https://user:s3cret@example.org/x" },
            Case("url 帶只有 user 的 userinfo", needle: "帳密") { $0["url"] = "https://token@example.org/x" },
            Case("retrieved 不是日期", needle: "retrieved") { $0["retrieved"] = "d" },
            Case("retrieved 斜線日期", needle: "retrieved") { $0["retrieved"] = "2026/09/29" },
            Case("retrieved 月份 13", needle: "retrieved") { $0["retrieved"] = "2026-13-01" },
            Case("retrieved 只有年月", needle: "retrieved") { $0["retrieved"] = "2026-09" },
            Case("retrieved 時間 25 點", needle: "retrieved") { $0["retrieved"] = "2026-09-29T25:00:00Z" },
            Case("retrieved 時間後接垃圾", needle: "retrieved") { $0["retrieved"] = "2026-09-29T10:00:00 UTC" },
            // 兩種 kind 的一致性
            Case("kind 不認得", needle: "kind 必須是") { $0["kind"] = "citation" },
            Case("field 空白", needle: "缺 field") { $0["field"] = "  " },
        ]
        var checked = 0
        for c in cases {
            for isPerson in [true, false] {
                var item = c.judgement ? judgementBase(person: isPerson) : retrievalBase(person: isPerson)
                c.mutate(&item)
                let before = try snapshot()
                let who = isPerson ? "person" : "venue"
                XCTAssertThrowsError(try isPerson ? person([item]) : venue([item]), "\(who)：\(c.label)") { error in
                    guard case ServiceError.invalid(let why) = error else {
                        return XCTFail("\(who)：\(c.label)：應是參數錯誤，得 \(error)")
                    }
                    XCTAssertTrue(why.contains(c.needle), "\(who)：\(c.label)：要說出「\(c.needle)」，實得 \(why)")
                    XCTAssertTrue(why.contains("references"), "\(who)：\(c.label)：要指名是 references 這個參數：\(why)")
                }
                XCTAssertEqual(try snapshot(), before, "\(who)：\(c.label)：零寫入")
                checked += 1
            }
        }
        XCTAssertEqual(checked, cases.count * 2)
    }

    /// 帳密不回顯：拒絕訊息若把整個 URL 印出來，帳密就跟著進了 log 與 MCP 的對話紀錄。
    func testUserinfoIsNeverEchoedInTheRefusal() throws {
        for isPerson in [true, false] {
            var item = retrievalBase(person: isPerson)
            item["url"] = "https://alice:hunter2@example.org/x?token=abc"
            XCTAssertThrowsError(try isPerson ? person([item]) : venue([item])) { error in
                let why = message(error)
                XCTAssertFalse(why.contains("hunter2") || why.contains("alice") || why.contains("token=abc"), "\(why)")
            }
        }
    }

    /// #674 R1 verify 第 26 列：沒有合法 scheme、後面卻出現 `://` 的 url——`://` 之前那一段不是 scheme，可能正是帳密，不回顯；
    /// 真的是 scheme 形（`^[A-Za-z][A-Za-z0-9+.-]*$`）的才回顯。
    func testASchemelessURLWithCredentialsIsNotEchoedButARealSchemeIs() throws {
        for isPerson in [true, false] {
            var item = retrievalBase(person: isPerson)
            item["url"] = "alice:hunter2@example.org/?next=https://x"
            XCTAssertThrowsError(try isPerson ? person([item]) : venue([item])) { error in
                let why = message(error)
                XCTAssertTrue(why.contains("http／https"), why)
                XCTAssertFalse(why.contains("hunter2") || why.contains("alice") || why.contains("scheme 是"), "不是 scheme 就不回顯：\(why)")
            }
            item["url"] = "ftp://example.org/x"
            XCTAssertThrowsError(try isPerson ? person([item]) : venue([item])) { error in
                XCTAssertTrue(message(error).contains("scheme 是「ftp」"), "真的 scheme 照樣說出來：\(message(error))")
            }
        }
    }

    /// #674 R1 verify 第 28 列：「缺 status」先於 url／retrieved 的形狀——一筆什麼都沒給對的 retrieval，先被告知的是 #674 點名的那一項
    /// （既有測試改用合法的 url／retrieved 之後，這個先後就沒有測試釘住了）。
    func testMissingStatusIsReportedBeforeAMalformedURLOrRetrieved() throws {
        for isPerson in [true, false] {
            var item = retrievalBase(person: isPerson)
            item["status"] = nil
            item["url"] = "u"
            item["retrieved"] = "d"
            XCTAssertThrowsError(try isPerson ? person([item]) : venue([item])) { error in
                XCTAssertTrue(message(error).contains("沒有 status"), message(error))
            }
        }
    }

    /// 一次上限 200 筆，兩個面同一句。
    func testBothFacesCapTheBatchAtTwoHundred() throws {
        for isPerson in [true, false] {
            let refs = Array(repeating: retrievalBase(person: isPerson), count: 201)
            XCTAssertThrowsError(try isPerson ? person(refs) : venue(refs)) { error in
                XCTAssertTrue(message(error).contains("一次最多 200 筆"), "\(message(error))")
            }
        }
    }

    /// 兩個面都收的形狀：status 顯式給、url 是 http／https（scheme 大小寫不拘）、retrieved 是日期或帶時區的時間。
    func testBothFacesAcceptTheSameWellFormedShapes() throws {
        let urls = ["https://example.org/x", "http://example.org/x?a=b#c", "HTTPS://Example.org:8443/x", "https://[::1]/x"]
        let retrieveds = ["2026-09-29", "2026-09-29T14:30:00+08:00", "2026-09-29T06:30:00Z", "2026-09-29T14:30", "2026-09-29T14:30:00.123-05:00"]
        for isPerson in [true, false] {
            for (i, u) in urls.enumerated() {
                var item = retrievalBase(person: isPerson); item["url"] = u; item["retrieved"] = "2026-09-2\(i)"
                XCTAssertNoThrow(try isPerson ? person([item]) : venue([item]), "\(isPerson ? "person" : "venue")：\(u)")
            }
            for (i, r) in retrieveds.enumerated() {
                var item = retrievalBase(person: isPerson); item["retrieved"] = r; item["content"] = "sha256:" + String(format: "%064x", i + 100)
                XCTAssertNoThrow(try isPerson ? person([item]) : venue([item]), "\(isPerson ? "person" : "venue")：\(r)")
            }
            var status404 = retrievalBase(person: isPerson); status404["status"] = 404; status404["content"] = "sha256:" + String(repeating: "cd", count: 32)
            XCTAssertNoThrow(try isPerson ? person([status404]) : venue([status404]), "「死」也是內容：404 收")
        }
    }

    /// person 側先前的預設 200：不給 status 的 retrieval 曾被記成 HTTP 200。現在拒絕，且 dry-run 同樣拒絕（參數階段）。
    func testPersonNoLongerDefaultsStatusTo200() throws {
        var item = retrievalBase(person: true); item.removeValue(forKey: "status")
        let before = try snapshot()
        XCTAssertThrowsError(try person([item], dryRun: false)) { XCTAssertTrue(message($0).contains("status"), message($0)) }
        XCTAssertThrowsError(try person([item], dryRun: true)) { XCTAssertTrue(message($0).contains("status"), message($0)) }
        XCTAssertEqual(try snapshot(), before)
        XCTAssertTrue(try XCTUnwrap(LibraryStore(root: root).load().people.first { $0.key == "p-one" }).references.isEmpty)
    }

    /// 只看參數的檢查在讀 store 之前（#654）：CLI 的 `validate()` 呼叫 `checkUpdatePersonFields`，不需要 store。
    func testPersonReferenceShapeIsCheckedWithoutTheStore() {
        var item = retrievalBase(person: true); item.removeValue(forKey: "status")
        XCTAssertThrowsError(try AkashicService.checkUpdatePersonFields(["references": [item]])) {
            XCTAssertTrue(message($0).contains("status"), message($0))
        }
        var bad = retrievalBase(person: true); bad["mediatype"] = "x"
        XCTAssertThrowsError(try AkashicService.checkUpdatePersonFields(["references": [bad]])) {
            XCTAssertTrue(message($0).contains("不認得的鍵"), message($0))
        }
        XCTAssertNoThrow(try AkashicService.checkUpdatePersonFields(["references": [retrievalBase(person: true)]]))
    }

    /// 兩個面共用的接受路徑與位元組去重不變：合法的一筆寫得進去，同一筆再送是 no-op。
    func testValidReferenceIsWrittenAndIdempotentOnBothFaces() throws {
        try person([retrievalBase(person: true)])
        try person([retrievalBase(person: true)])
        let p = try XCTUnwrap(LibraryStore(root: root).load().people.first { $0.key == "p-one" })
        XCTAssertEqual(p.references.count, 1)
        guard case .retrieval(let url, let retrieved, let status, _, _) = try XCTUnwrap(p.references.first).kind else { return XCTFail() }
        XCTAssertEqual([url, retrieved, "\(status)"], ["https://example.org/record/1", "2026-09-29", "200"])
        try venue([retrievalBase(person: false)])
        let out = try service.updateVenue(key: "ampsy", addNames: nil, note: nil, type: nil, references: [retrievalBase(person: false)])
        XCTAssertTrue(out.contains("\"referencesAlreadyPresent\":1") || out.contains("\"referencesAlreadyPresent\" : 1"), out)
    }

    /// `retrieved` 的文法（單元）：日期，或日期加時間與可選的時區；每一格都在 store 的既有寫法或 RFC 3339 的範圍內。
    func testRetrievedInstantGrammar() {
        let ok = ["2026-09-29", "2026-09-29T00:00", "2026-09-29T23:59:59", "2026-09-29T23:59:60Z", "2026-09-29T14:30:00.5+08:00",
                  "2026-09-29T14:30:00Z", "2026-09-29T14:30-05:30", "0001-01-01"]
        let bad = ["", "2026", "2026-09", "20260929", "2026-9-29", "2026-09-29T", "2026-09-29T1:30", "2026-09-29T14",
                   "2026-09-29T14:30:", "2026-09-29T14:30:00.", "2026-09-29T14:30:00+0800", "2026-09-29T14:30:00+08",
                   "2026-09-29T14:30:00+24:00", "2026-09-29T14:30:00+08:60", "2026-09-29T24:00", "2026-09-29T14:60",
                   "2026-09-29T14:30:61Z", "2026-09-29T14:30:00Zjunk", "2026-09-29 14:30", "2026-09-29t14:30", "2026-00-10",
                   "2026-09-32", "２０２６-09-29", "2026-09-29\n", " 2026-09-29"]
        for s in ok { XCTAssertTrue(AkashicService.isValidRetrievedInstant(s), "應收：\(s)") }
        for s in bad { XCTAssertFalse(AkashicService.isValidRetrievedInstant(s), "應拒：\(s.debugDescription)") }
    }

    /// `url` 的文法（單元）：http／https、主機非空、不含 userinfo。
    func testRetrievalURLGrammar() {
        let ok = ["https://example.org", "http://example.org/", "https://example.org:8443/a?b=c#d", "HTTPS://EXAMPLE.ORG/x",
                  "https://[2001:db8::1]:80/x", "https://例え.jp/パス", "https://example.org/a@b", "https://example.org?u=a@b"]
        let bad = ["", "example.org", "//example.org", "ftp://example.org", "file:///x", "https:/example.org", "https://",
                   "https:///x", "https://:80/x", "https://user@example.org", "https://user:pw@example.org/x", "https://@example.org",
                   "http://a:b@[::1]/x", "mailto:a@b.c", "data:text/plain,hi", " https://example.org"]
        for u in ok { XCTAssertNoThrow(try AkashicService.vetRetrievalURL(u, at: "references[0]"), "應收：\(u)") }
        for u in bad { XCTAssertThrowsError(try AkashicService.vetRetrievalURL(u, at: "references[0]"), "應拒：\(u.debugDescription)") }
    }

    /// **有記錄的差異，不是遺漏**：空陣列在 venue 是獨立參數、給了卻沒東西要附是呼叫端的錯；在 person 是 `fields` 這個物件裡
    /// 被提及的一格，先前就是 no-op。#674 只對齊三個被點名的契約（status、未知鍵、上限），沒有把這個 no-op 變成錯誤。
    func testEmptyArrayIsStillANoOpForPersonAndRefusedForVenue() throws {
        let before = try snapshot()
        XCTAssertNoThrow(try person([]))
        XCTAssertEqual(try snapshot(), before)
        XCTAssertThrowsError(try venue([])) { XCTAssertTrue(message($0).contains("空陣列"), message($0)) }
    }

    /// person 的 holder 政策：verdict 欄位對仍然只經 resolve 流程寫（不因共用解析而放行）。
    func testPersonStillRefusesVerdictFields() throws {
        for field in ProvenanceReference.resolutionVerdictFields.sorted() {
            let item: [String: Any] = ["field": field, "value": "work:x :: X", "kind": "judgement",
                                       "statement": "s", "rests_on": [digest]]
            XCTAssertThrowsError(try person([item]), field) { XCTAssertTrue(message($0).contains("resolve"), message($0)) }
        }
    }
}
