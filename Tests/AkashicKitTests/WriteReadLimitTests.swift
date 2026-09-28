import Foundation
import XCTest
@testable import AkashicCore
@testable import AkashicEntity
@testable import AkashicMCPKit
@testable import AkashicStoreIO

/// #648：寫入的位元組上限是**讀取上限**（`AliasEventBudget.maxBytes`，8 MiB）；只有**不增長的改寫**可用到
/// `writePathMultiplier` 倍。拒絕要具名記錄與兩個位元組數，而多檔的寫入面在任何檔落盤之前就擋下。
///
/// 2026-09-28 實測的起點：issue 說「寫得進去、讀不回來」——那一半不成立。encode 的語意 canary（`decode(out)`）一直以讀取
/// 上限擋著，9 MB 的 person 丟 `fileTooLarge(bytes:limit:)`，不具名、訊息說的是「單一超大節點會讓 parser 耗盡記憶體」；
/// 真正成立的是另一半：`judge` 先寫 entry 再寫 person，person 被拒時作者位已歸戶而 verdict 沒寫（撕裂）。
final class WriteReadLimitTests: XCTestCase {
    private var root: URL!
    private var home: URL!
    private var store: LibraryStore!

    private let maxBytes = AliasEventBudget.maxBytes

    override func setUpWithError() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("akashic-648-\(UUID().uuidString)")
        root = base.appendingPathComponent("store")
        home = base.appendingPathComponent("home")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        GitFixture.initRepo(root)
        store = LibraryStore(root: root, key: nil, environment: ["AKASHIC_HOME": home.path])
        try store.ensureLayout()
        try StoreVersion.write(root: root, format: StoreVersion.supported)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root.deletingLastPathComponent())
    }

    // MARK: - 規則本身（純函數）

    /// 三段：沒有目的檔或目的檔讀得回來 → 讀取上限；目的檔在 (1 倍, 2 倍] → 目的檔的大小；目的檔超過 2 倍 → 2 倍。
    func testWriteByteLimitHasThreeSegments() {
        let m = maxBytes
        XCTAssertEqual(AliasEventBudget.writeByteLimit(replacing: nil), m, "新建：沒有寬限")
        XCTAssertEqual(AliasEventBudget.writeByteLimit(replacing: 0), m)
        XCTAssertEqual(AliasEventBudget.writeByteLimit(replacing: m - 1), m, "讀得回來的檔：上限仍是讀取上限，可以長到它為止")
        XCTAssertEqual(AliasEventBudget.writeByteLimit(replacing: m), m)
        XCTAssertEqual(AliasEventBudget.writeByteLimit(replacing: m + 1), m + 1, "已經讀不回來的檔：只能原樣或縮小改寫")
        XCTAssertEqual(AliasEventBudget.writeByteLimit(replacing: 2 * m), 2 * m)
        XCTAssertEqual(AliasEventBudget.writeByteLimit(replacing: 2 * m + 5), 2 * m, "2 倍是天花板")
        XCTAssertEqual(AliasEventBudget.writePathMultiplier, 2)
    }

    /// 「不增長」的定義逐格對照：允許 ⟺ 寫出的位元組 ≤ 讀取上限，或（有目的檔、寫出 ≤ 目的檔、寫出 ≤ 2 倍）。
    func testLimitAgreesWithTheNonGrowingDefinitionOnAGrid() {
        let m = maxBytes
        let points = [0, 1, m - 1, m, m + 1, m + 1024, 2 * m - 1, 2 * m, 2 * m + 1, 3 * m]
        for current in [nil] + points.map(Optional.some) {
            for new in points {
                let byRule = new <= AliasEventBudget.writeByteLimit(replacing: current)
                let byDefinition = new <= m || (current.map { new <= $0 && new <= 2 * m } ?? false)
                XCTAssertEqual(byRule, byDefinition, "current=\(String(describing: current)) new=\(new)")
            }
        }
    }

    // MARK: - encode 層：具名、兩個數、寬限只給不增長的改寫

    /// note 撐大的 person——它的 encode 產物比 `bytes` 多一點點（形狀標籤、id、key）。
    private func bigPerson(key: String = "big-p", bytes: Int) -> Person {
        var p = Person(key: key)
        p.note = String(repeating: "a", count: bytes)
        return p
    }

    func testEncodeOverTheReadLimitIsRefusedByNameWithBothSizes() throws {
        let p = bigPerson(bytes: maxBytes + 1)
        XCTAssertThrowsError(try PersonYAML.encode(p)) { error in
            guard case let StoreYAMLError.writeExceedsReadLimit(record, bytes, limit, current) = error else {
                return XCTFail("應是具名的 writeExceedsReadLimit，實得 \(error)")
            }
            XCTAssertEqual(record, "person「big-p」")
            XCTAssertGreaterThan(bytes, self.maxBytes)
            XCTAssertEqual(limit, self.maxBytes)
            XCTAssertNil(current)
            let message = (error as? LocalizedError)?.errorDescription ?? ""
            XCTAssertTrue(message.contains("person「big-p」"), message)
            XCTAssertTrue(message.contains("\(bytes) 位元組") && message.contains("\(self.maxBytes)"), "兩個數都要說：\(message)")
            XCTAssertTrue(message.contains("目的地沒有既有的檔"), message)
        }
    }

    /// 寬限：目的檔已經超過讀取上限時，不比它大的改寫放行（產物讀得回同一個值——canary 走寫入路徑的預算）；比它大就拒。
    func testGraceAppliesOnlyToNonGrowingRewritesOfAnAlreadyLargeFile() throws {
        let p = bigPerson(bytes: maxBytes + 4096)
        let text = try PersonYAML.encode(p, replacing: maxBytes + 1_000_000)
        let n = text.utf8.count
        XCTAssertGreaterThan(n, maxBytes, "前提：產物確實超過讀取上限")
        XCTAssertNoThrow(try PersonYAML.encode(p, replacing: n), "與目的檔同樣大：不增長")
        XCTAssertThrowsError(try PersonYAML.encode(p, replacing: n - 1)) { error in
            guard case let StoreYAMLError.writeExceedsReadLimit(_, bytes, limit, current) = error else {
                return XCTFail("\(error)")
            }
            XCTAssertEqual(bytes, n)
            XCTAssertEqual(limit, n - 1, "目的檔在 (1 倍, 2 倍] 時上限就是它的大小")
            XCTAssertEqual(current, n - 1)
            let message = (error as? LocalizedError)?.errorDescription ?? ""
            XCTAssertTrue(message.contains("目的檔目前 \(n - 1) 位元組"), message)
        }
        XCTAssertThrowsError(try PersonYAML.encode(p, replacing: maxBytes - 1), "讀得回來的檔沒有寬限")
    }

    /// 六個 encoder 都走同一道（`checkWriteSize` 在 canary 之前）——拿掉任何一個呼叫，那一族超過上限的產物會以
    /// 不具名的 `fileTooLarge` 被語意 canary 擋下（2026-09-28 之前的樣子），這支就紅。
    func testEveryEncoderRefusesByName() throws {
        let big = String(repeating: "a", count: maxBytes + 1)
        func named(_ body: () throws -> String, _ record: String, file: StaticString = #filePath, line: UInt = #line) {
            XCTAssertThrowsError(try body(), file: file, line: line) { error in
                guard case let StoreYAMLError.writeExceedsReadLimit(r, _, _, _) = error else {
                    return XCTFail("\(record)：應是具名拒絕，實得 \(error)", file: file, line: line)
                }
                XCTAssertEqual(r, record, file: file, line: line)
            }
        }
        var e = Entry(id: UUID(), citekey: "big2020", type: .periodicalArticle, title: "T")
        e.fields = ["abstract": big]
        named({ try EntryYAML.encode(e) }, "work「big2020」")
        named({ try PersonYAML.encode(bigPerson(bytes: maxBytes + 1)) }, "person「big-p」")
        var o = Organization(key: "big-org")
        o.note = big
        named({ try OrganizationYAML.encode(o) }, "organization「big-org」")
        var v = Venue(key: "big-journal", type: .periodical, names: TimelineOf([TemporalValue(value: "Big Journal")]))
        v.note = big
        named({ try VenueYAML.encode(v) }, "venue「big-journal」")
        let d = Divergence(id: UUID(uuidString: "00000000-0000-0000-0000-000000000648")!, question: big,
                               candidates: [DivergenceCandidate(key: "a-b", shape: .person),
                                            DivergenceCandidate(key: "c-d", shape: .person)])
        named({ try DivergenceYAML.encode(d) }, "divergence「00000000-0000-0000-0000-000000000648」")
        let lib = Library(key: "big-lib", name: "Big", description: big)
        named({ try LibraryYAML.encode(lib) }, "library「big-lib」")
    }

    // MARK: - store 層：拒絕零寫入；寬限只在目的檔已讀不回來時落地

    private func fileBytes(_ url: URL) throws -> Data { try Data(contentsOf: url) }

    func testStoreWriteThatGrowsPastTheReadLimitLeavesTheFileUntouched() throws {
        let url = try store.writePerson(Person(key: "small-p", names: ["Small, P."]))
        let before = try fileBytes(url)
        var grown = try XCTUnwrap(try store.load().people.first { $0.key == "small-p" })
        grown.note = String(repeating: "a", count: maxBytes)
        XCTAssertThrowsError(try store.writePerson(grown)) { error in
            guard case let StoreYAMLError.writeExceedsReadLimit(record, _, limit, current) = error else {
                return XCTFail("\(error)")
            }
            XCTAssertEqual(record, "person「small-p」")
            XCTAssertEqual(limit, self.maxBytes, "目的檔讀得回來：上限是讀取上限")
            XCTAssertEqual(current, before.count, "目的檔目前的位元組數要傳進來")
        }
        XCTAssertEqual(try fileBytes(url), before, "零寫入")
        XCTAssertThrowsError(try store.preflightWrite(grown), "preflight 與寫入同一道")
    }

    /// legacy 佈局沒有 #631 的目的檔檢查——寬限只在這裡落地：目的檔已經讀不回來時，原樣或縮小改寫放行，長大就拒。
    func testGraceLandsOnlyForAnAlreadyUnreadableLegacyFile() throws {
        try StoreVersion.write(root: root, format: 1)
        let legacy = store.personURL(key: "big-p")
        try FileManager.default.createDirectory(at: legacy.deletingLastPathComponent(), withIntermediateDirectories: true)
        let existing = try PersonYAML.encode(bigPerson(bytes: maxBytes + 200_000), replacing: 2 * maxBytes)
        try existing.write(to: legacy, atomically: true, encoding: .utf8)
        XCTAssertFalse(try store.load().people.contains { $0.key == "big-p" }, "前提：它讀不回來（載入時被隔離）")

        XCTAssertThrowsError(try store.writePerson(bigPerson(bytes: maxBytes + 300_000))) { error in
            guard case let StoreYAMLError.writeExceedsReadLimit(_, _, limit, current) = error else { return XCTFail("\(error)") }
            XCTAssertEqual(current, existing.utf8.count)
            XCTAssertEqual(limit, existing.utf8.count)
        }
        XCTAssertEqual(try String(contentsOf: legacy, encoding: .utf8).utf8.count, existing.utf8.count, "長大的改寫零寫入")

        try store.writePerson(bigPerson(bytes: maxBytes + 100_000))
        let after = try String(contentsOf: legacy, encoding: .utf8).utf8.count
        XCTAssertLessThan(after, existing.utf8.count, "縮小的改寫落地")
        XCTAssertGreaterThan(after, maxBytes, "它仍然讀不回來——寬限不把讀不回來的檔變成讀得回來，也不把讀得回來的變成讀不回來")
    }

    /// entities 佈局：目的檔讀不回來時 #631 拒絕覆寫——寬限在這個佈局不落地。
    func testGraceDoesNotLandInTheEntitiesLayout() throws {
        let p = bigPerson(bytes: maxBytes + 200_000)
        let dest = store.entityURL(id: p.id)
        try PersonYAML.encode(p, replacing: 2 * maxBytes).write(to: dest, atomically: true, encoding: .utf8)
        let before = try fileBytes(dest)
        var smaller = p
        smaller.note = String(repeating: "a", count: maxBytes + 100_000)
        XCTAssertThrowsError(try store.writePerson(smaller)) { error in
            guard case StoreIOError.destinationHoldsAnotherRecord = error else { return XCTFail("應由 #631 拒絕：\(error)") }
        }
        XCTAssertEqual(try fileBytes(dest), before)
    }

    // MARK: - 多檔寫入面：拒絕發生在任何檔落盤之前

    private func service() -> AkashicService {
        AkashicService(root: root, environment: ["AKASHIC_HOME": home.path])
    }

    /// person 檔在讀取上限之下、差一筆判定就過——judge 的 entry 與 person 都不得落盤。
    /// 2026-09-28 之前：entry 先寫（作者位歸戶），person 才被拒——撕裂。
    private func seedNearLimitPerson(key: String = "near-p", literal: String = "N. Near") throws -> URL {
        var p = Person(key: key, names: [literal])
        // 一筆判定約 4.2 KB（理由上限 4,096 ＋ value 與 rule 尾註）；留 2,000 位元組的餘裕
        p.note = String(repeating: "a", count: maxBytes - 2_000)
        let url = try store.writePerson(p)
        XCTAssertLessThan(try fileBytes(url).count, maxBytes, "前提：讀得回來")
        return url
    }

    func testJudgeThatWouldPushThePersonPastTheLimitWritesNothing() throws {
        let personURL = try seedNearLimitPerson()
        let entryURL = try store.writeEntry(Entry(id: UUID(), citekey: "w1", type: .periodicalArticle, title: "T",
                                                  authors: [.literal("N. Near")], date: "2020"))
        let (personBefore, entryBefore) = (try fileBytes(personURL), try fileBytes(entryURL))
        let reason = String(repeating: "r", count: 4_000)
        XCTAssertThrowsError(try service().resolvePeople(apply: nil, judge: ["w1:0:near-p=\(reason)"])) { error in
            guard case let StoreYAMLError.writeExceedsReadLimit(record, _, _, _) = error else { return XCTFail("\(error)") }
            XCTAssertEqual(record, "person「near-p」")
        }
        XCTAssertEqual(try fileBytes(entryURL), entryBefore, "作者位不得先歸戶（撕裂）")
        XCTAssertEqual(try fileBytes(personURL), personBefore)
    }

    func testRefuteThatWouldPushThePersonPastTheLimitWritesNothing() throws {
        let personURL = try seedNearLimitPerson()
        try store.writeEntry(Entry(id: UUID(), citekey: "w1", type: .periodicalArticle, title: "T",
                                   authors: [.literal("N. Near")], date: "2020"))
        let before = try fileBytes(personURL)
        XCTAssertThrowsError(try service().resolvePeople(apply: nil, refute: ["w1:0:near-p=\(String(repeating: "r", count: 4_000))"]))
        XCTAssertEqual(try fileBytes(personURL), before)
    }

    /// 未決腿：一次呼叫涉及兩個 person，後一個（依 key 排序）過上限——前一個也不得落盤。
    /// 未決的說明含控制字元時 YAML 跳脫成 4 倍——讀取上限的寫入閘就是擋它的那一道（不另立控制字元規則）。
    func testUndecidedBatchIsAllOrNothingAcrossHolders() throws {
        let smallURL = try store.writePerson(Person(key: "aaa-small", names: ["A. Small"]))
        let bigURL = try seedNearLimitPerson(key: "zzz-near", literal: "Z. Near")
        try store.writeEntry(Entry(id: UUID(), citekey: "w2", type: .periodicalArticle, title: "U",
                                   authors: [.literal("A. Small"), .literal("Z. Near")], date: "2021"))
        let (smallBefore, bigBefore) = (try fileBytes(smallURL), try fileBytes(bigURL))
        // 1,000 個控制字元，跳脫後約 4,000 位元組——說明本身在 4,096 的上限內
        let controlHeavy = String(repeating: "\u{01}", count: 1_000)
        XCTAssertThrowsError(try service().resolvePeople(apply: nil, undecided: [
            "w2:0:aaa-small=查過",
            "w2:1:zzz-near=\(controlHeavy)",
        ])) { error in
            guard case let StoreYAMLError.writeExceedsReadLimit(record, _, _, _) = error else { return XCTFail("\(error)") }
            XCTAssertEqual(record, "person「zzz-near」")
        }
        XCTAssertEqual(try fileBytes(smallURL), smallBefore, "排序在前的那一筆也不得落盤")
        XCTAssertEqual(try fileBytes(bigURL), bigBefore)
    }

    /// 把一筆記錄的 note 校準到「檔案恰在讀取上限之下 `headroom` 位元組」——一筆固定措辭的 verdict 就推得過去。
    /// note 是不含空白的 ASCII，emitter 不折行，檔案大小對 note 長度是線性的。
    private func calibrate(_ write: (Int) throws -> URL, headroom: Int) throws -> URL {
        let probe = maxBytes - 10_000
        let size = try fileBytes(try write(probe)).count
        let url = try write(probe + (maxBytes - headroom - size))
        XCTAssertEqual(try fileBytes(url).count, maxBytes - headroom, "前提：校準到讀取上限之下 \(headroom) 位元組")
        return url
    }

    /// venue 是 O(catalog) 的 verdict 持有者（#499）——長過讀取上限的就是它。apply 先寫 entry 再寫 venue，
    /// 在此之前 venue 的前置只驗內容閘與 #631，encode 的上限要到寫入當下才撞上：作者位已歸戶、verdict 沒落。
    func testVenueApplyThatWouldPushTheVenuePastTheLimitWritesNothing() throws {
        var v = Venue(key: "near-journal", type: .periodical, names: TimelineOf([TemporalValue(value: "Near Journal")]))
        let venueURL = try calibrate({ n in v.note = String(repeating: "a", count: n); return try self.store.writeVenue(v) },
                                     headroom: 60)
        var e = Entry(id: UUID(), citekey: "w3", type: .periodicalArticle, title: "V", date: "2022")
        e.venues = [.literal("Near Journal")]
        let entryURL = try store.writeEntry(e)
        let (venueBefore, entryBefore) = (try fileBytes(venueURL), try fileBytes(entryURL))
        XCTAssertThrowsError(try service().resolveVenues(apply: ["w3:0"])) { error in
            guard case let StoreYAMLError.writeExceedsReadLimit(record, _, _, _) = error else { return XCTFail("\(error)") }
            XCTAssertEqual(record, "venue「near-journal」")
        }
        XCTAssertEqual(try fileBytes(entryURL), entryBefore, "venue 邊不得先歸戶（撕裂）")
        XCTAssertEqual(try fileBytes(venueURL), venueBefore)
    }

    /// attribute-org 在此之前沒有任何寫入前的逐筆驗證——entry 先寫、org 在寫入當下才被拒。它的理由沒有上限
    /// （#648 (b) 只收 judge／refute），寫入閘是擋它的那一道。
    func testAttributeOrgThatWouldPushTheOrgPastTheLimitWritesNothing() throws {
        var o = Organization(key: "near-org")
        let orgURL = try calibrate({ n in o.note = String(repeating: "a", count: n); return try self.store.writeOrganization(o) },
                                   headroom: 60)
        let entryURL = try store.writeEntry(Entry(id: UUID(), citekey: "w4", type: .periodicalArticle, title: "O",
                                                  authors: [.literal("Near Org")], date: "2022"))
        let (orgBefore, entryBefore) = (try fileBytes(orgURL), try fileBytes(entryURL))
        XCTAssertThrowsError(try service().attributeToOrganizations(["w4:0:near-org=\(String(repeating: "r", count: 4_000))"])) { error in
            guard case let StoreYAMLError.writeExceedsReadLimit(record, _, _, _) = error else { return XCTFail("\(error)") }
            XCTAssertEqual(record, "organization「near-org」")
        }
        XCTAssertEqual(try fileBytes(entryURL), entryBefore, "作者位不得先改成 .organization（撕裂）")
        XCTAssertEqual(try fileBytes(orgURL), orgBefore)
    }

    /// resolve-organizations apply 寫 person（隸屬歸戶）→ org → entry → org 的 verdict；verdict 那一筆最後寫，
    /// 在此之前它在寫入當下才被拒時，person 的隸屬已經歸戶。
    func testOrgApplyThatWouldPushTheOrgPastTheLimitWritesNothing() throws {
        var o = Organization(key: "near-org")
        o.names = TimelineOf([TemporalValue(value: "Near Org", range: DateRange())])
        let orgURL = try calibrate({ n in o.note = String(repeating: "a", count: n); return try self.store.writeOrganization(o) },
                                   headroom: 40)
        var p = Person(key: "p-near", names: ["Near, P."])
        p.profile.affiliations = TimelineOf([TemporalValue(value: OrgRef.literal("Near Org"), range: DateRange())])
        let personURL = try store.writePerson(p)
        let listing = try JSONSerialization.jsonObject(with: Data(try service().resolveOrganizations(apply: nil).utf8)) as? [String: Any]
        let ids = ((listing?["candidates"] as? [[String: Any]]) ?? []).compactMap { $0["id"] as? String }
        XCTAssertEqual(ids.count, 1, "前提：恰一個候選 \(ids)")
        let (orgBefore, personBefore) = (try fileBytes(orgURL), try fileBytes(personURL))
        XCTAssertThrowsError(try service().resolveOrganizations(apply: ids)) { error in
            guard case let StoreYAMLError.writeExceedsReadLimit(record, _, _, _) = error else { return XCTFail("\(error)") }
            XCTAssertEqual(record, "organization「near-org」")
        }
        XCTAssertEqual(try fileBytes(personURL), personBefore, "隸屬不得先歸戶（撕裂）")
        XCTAssertEqual(try fileBytes(orgURL), orgBefore)
    }

    /// resolve-organizations reject 逐個 org 寫 rejected verdict——排序在前的 org 不得在後一個被拒之前落盤。
    func testOrgRejectBatchIsAllOrNothingAcrossOrgs() throws {
        var small = Organization(key: "aaa-org")
        small.names = TimelineOf([TemporalValue(value: "Small Org", range: DateRange())])
        let smallURL = try store.writeOrganization(small)
        var near = Organization(key: "zzz-org")
        near.names = TimelineOf([TemporalValue(value: "Near Org", range: DateRange())])
        let nearURL = try calibrate({ n in near.note = String(repeating: "a", count: n); return try self.store.writeOrganization(near) },
                                    headroom: 40)
        for (key, aff) in [("p-small", "Small Org"), ("p-near", "Near Org")] {
            var p = Person(key: key, names: [key])
            p.profile.affiliations = TimelineOf([TemporalValue(value: OrgRef.literal(aff), range: DateRange())])
            try store.writePerson(p)
        }
        let listing = try JSONSerialization.jsonObject(with: Data(try service().resolveOrganizations(apply: nil).utf8)) as? [String: Any]
        let ids = ((listing?["candidates"] as? [[String: Any]]) ?? []).compactMap { $0["id"] as? String }
        XCTAssertEqual(ids.count, 2, "前提：兩個候選 \(ids)")
        let (smallBefore, nearBefore) = (try fileBytes(smallURL), try fileBytes(nearURL))
        XCTAssertThrowsError(try service().resolveOrganizations(apply: nil, reject: ids)) { error in
            guard case let StoreYAMLError.writeExceedsReadLimit(record, _, _, _) = error else { return XCTFail("\(error)") }
            XCTAssertEqual(record, "organization「zzz-org」")
        }
        XCTAssertEqual(try fileBytes(smallURL), smallBefore, "排序在前的那一個 org 也不得落盤")
        XCTAssertEqual(try fileBytes(nearURL), nearBefore)
    }
}
