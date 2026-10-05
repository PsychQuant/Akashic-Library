import XCTest
@testable import AkashicCore
@testable import AkashicMCPKit
@testable import AkashicStoreIO

/// #564 b33 X1 與使用者 2026-10-05 的裁決（第 1–3 點）：person `fields.names` 的替換。
///
/// - 對外形不得整個離開 names（有沒有記錄都一樣）：移出 authorized 要寫「撤回：理由」，記錄錨定 names——放在 variant。R2 讓沒有記錄的
///   對外形一步離開、理由不入庫，而且因為沒有記錄要寫，format < 22 的寫入閘沒觸發（b33 X1 第 0／2／3／8／11／13／18／23 列）。
/// - 只替有變動的名字寫記錄；給了理由而沒有名字進出 authorized，拒絕（不靜默丟掉理由）。只動 variant 的不必理由。
/// - 替換不把 person 刪到沒有名字（第 19／40 列）。
/// - 刪名字的拒絕在 format < 22 說出寫入閘（第 17／30 列）；最後一個名字、canonical 孿生拼法的拒絕說出工具面的出口（第 26／28 列）。
/// - organization 刪名字的報告只列有內容的段、有上限（第 22／27／34 列）。
final class NameClassificationB34Tests: XCTestCase {
    private var root: URL!
    private var service: AkashicService!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("akashic-ncb34-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root.appendingPathComponent("entities"), withIntermediateDirectories: true)
        try StoreVersion.write(root: root, format: StoreVersion.supported)
        service = AkashicService(root: root)
        try write(Person(key: "pw", names: PersonNames(authorized: ["Wes W"], variant: ["Other Name"])))
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    private func write(_ p: Person) throws { _ = try LibraryStore(root: root).writePerson(p) }
    private func person(_ key: String = "pw") throws -> Person {
        try XCTUnwrap(LibraryStore(root: root).load().people.first { $0.key == key })
    }
    private func payload(_ s: String) throws -> [String: Any] {
        try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(s.utf8)) as? [String: Any])
    }
    private func msg(_ e: Error) -> String { (e as? LocalizedError)?.errorDescription ?? "\(e)" }
    @discardableResult
    private func names(_ key: String = "pw", authorized: [String], variant: [String], judgement: String? = nil,
                       dryRun: Bool = false) throws -> [String: Any] {
        try payload(try service.updatePerson(key: key, fields: ["names": ["authorized": authorized, "variant": variant]],
                                             dryRun: dryRun, judgement: judgement))
    }
    private func statements(_ refs: [ProvenanceReference]) -> [String] {
        refs.filter(NameClassificationRecord.isRecord).compactMap { r in
            guard case .judgement(let statement, _) = r.kind else { return nil }
            return (r.value ?? "") + " " + statement
        }
    }

    // MARK: - 裁決第 1 點

    /// format 18 的 store（live store 的形）：無記錄的對外形整個離開 names，R2 放行而且沒碰到寫入閘、理由不入庫。現在拒絕，說出要留在
    /// variant、說出寫入閘；乾跑同樣拒絕，零寫入。
    func testDroppingAnUnrecordedAuthorizedNameIsRefusedAtAnOldFormat() throws {
        try StoreVersion.write(root: root, format: 18)
        let before = try person()
        for dry in [true, false] {
            XCTAssertThrowsError(try names(authorized: [], variant: ["Other Name"], judgement: "x", dryRun: dry)) { e in
                let m = msg(e)
                XCTAssertTrue(m.contains("整個離開 names") && m.contains("Wes W") && m.contains("variant"), m)
                XCTAssertTrue(m.contains("format 18") && m.contains("22"), "format < 22 要說出寫入閘：\(m)")
                // 兩面的錯誤出口逐行截 400：寫入閘那句自成一行，升級路徑不被長拒絕擠掉（真 binary 曾印到「…（已截斷）」為止）
                let shown = displaySafeErrorMultiline(e)
                XCTAssertTrue(shown.contains("format: 改成 22") && !shown.contains("已截斷"), shown)
            }
        }
        XCTAssertEqual(try person(), before, "零寫入")
    }

    /// 移到 variant（寫撤回）在 format 18 被寫入閘擋下——乾跑預告、實跑拒絕。所以 format < 22 時 person 的 authorized 確實改不了（裁決第 1 點：
    /// 與其他分類寫入一樣被閘擋下）。
    func testMovingAnUnrecordedAuthorizedNameToVariantIsGatedBelow22() throws {
        try StoreVersion.write(root: root, format: 18)
        let preview = try names(authorized: [], variant: ["Other Name", "Wes W"], judgement: "不是對外形", dryRun: true)
        XCTAssertEqual(preview["judgementsToRecord"] as? Int, 1)
        XCTAssertNotNil(preview["blockedByNameClassificationGate"], "\(preview)")
        XCTAssertThrowsError(try names(authorized: [], variant: ["Other Name", "Wes W"], judgement: "不是對外形"))
        XCTAssertEqual(try person().names.authorized, ["Wes W"], "零寫入")
    }

    /// format ≥ 22：同一個呼叫寫一筆撤回，理由入庫。
    func testMovingAnUnrecordedAuthorizedNameToVariantRecordsTheReason() throws {
        let out = try names(authorized: [], variant: ["Other Name", "Wes W"], judgement: "不是對外形")
        XCTAssertEqual(out["judgementsRecorded"] as? Int, 1)
        XCTAssertEqual(statements(try person().references), ["Wes W 撤回：不是對外形"])
    }

    // MARK: - 裁決第 2、3 點

    /// 只動 variant：不必理由。附了理由而沒有名字進出 authorized：拒絕、零寫入（先前寫一筆「確認」到每個對外形上）。
    func testAReasonWithoutAnAuthorizedChangeIsRefused() throws {
        XCTAssertNoThrow(try names(authorized: ["Wes W"], variant: ["Other Name", "W. Wes"]))
        let before = try person()
        XCTAssertThrowsError(try names(authorized: ["Wes W"], variant: ["Other Name"], judgement: "查過")) { e in
            XCTAssertTrue(msg(e).contains("沒有讓任何名字進出") && msg(e).contains("不必附理由"), msg(e))
        }
        XCTAssertEqual(try person(), before, "零寫入")
    }

    // MARK: - 第 19／40 列：替換不把 person 刪到沒有名字

    func testReplacementCannotLeaveAPersonWithoutNames() throws {
        try write(Person(key: "pv", names: PersonNames(authorized: [], variant: ["Only V"])))
        XCTAssertThrowsError(try names("pv", authorized: [], variant: [])) { e in
            XCTAssertTrue(msg(e).contains("沒有任何名字"), msg(e))
        }
        XCTAssertEqual(try person("pv").names.all, ["Only V"], "零寫入")
        // 原本就沒有名字的不擋（不是這次造成的）
        try write(Person(key: "p0", names: PersonNames(authorized: [], variant: [])))
        XCTAssertNoThrow(try names("p0", authorized: [], variant: []))
    }

    // MARK: - 刪名字的拒絕（第 17／26／28／30 列）

    /// 還在 authorized 的名字：出口是先移到 variant（寫撤回）；format < 22 時那一步會被寫入閘擋，訊息先說。
    func testRemoveNameRefusalForAnAuthorizedNameNamesTheGateAtAnOldFormat() throws {
        try StoreVersion.write(root: root, format: 18)
        XCTAssertThrowsError(try service.updatePerson(key: "pw", fields: [:], dryRun: true, fieldsGiven: false, removeNames: ["Wes W=打錯"])) { e in
            let m = msg(e)
            XCTAssertTrue(m.contains("還在 authorized") && m.contains("移到 variant") && m.contains("format 18"), m)
        }
        try StoreVersion.write(root: root, format: StoreVersion.supported)
        XCTAssertThrowsError(try service.updatePerson(key: "pw", fields: [:], dryRun: true, fieldsGiven: false, removeNames: ["Wes W=打錯"])) { e in
            XCTAssertFalse(msg(e).contains("format 18"), msg(e))
        }
    }

    /// 刪到沒有名字的拒絕說出口（先加一個正確的名字）。
    func testLastNameRefusalNamesTheWayOut() throws {
        var p = Person(key: "pl", names: PersonNames(authorized: [], variant: ["Lone L"]))
        p.references = [NameClassificationRecord.make(field: "authorized", name: "Lone L", action: .withdraw, reason: "不是他", restsOn: [])]
        try write(p)
        XCTAssertThrowsError(try service.updatePerson(key: "pl", fields: [:], dryRun: true, fieldsGiven: false, removeNames: ["Lone L=打錯"])) { e in
            XCTAssertTrue(msg(e).contains("沒有任何名字") && msg(e).contains("加一個正確的名字"), msg(e))
        }
    }

    /// canonical 孿生拼法：沒有記錄的有工具面（整份替換），不是一律「手改 YAML」——照出口走得通。
    func testCanonicalTwinRefusalPointsAtTheReplacement() throws {
        try write(Person(key: "pt", names: PersonNames(authorized: [], variant: ["Foo Bar", "Foo  Bar", "Keep"])))
        XCTAssertThrowsError(try service.updatePerson(key: "pt", fields: [:], dryRun: true, fieldsGiven: false, removeNames: ["Foo Bar=dup"])) { e in
            XCTAssertTrue(msg(e).contains("整份替換"), msg(e))
        }
        XCTAssertNoThrow(try names("pt", authorized: [], variant: ["Foo Bar", "Keep"]))
        XCTAssertEqual(try person("pt").names.variant, ["Foo Bar", "Keep"])
    }

    // MARK: - organization 的段（第 22／27／34 列）

    /// 沒有時間、source、note 的段不回 `{}`；段數有上限，總數在 segmentsRemoved。
    func testOrganizationRemovalListsOnlySegmentsWithContentAndCapsThem() throws {
        var segments: [TemporalValue<String>] = [TemporalValue(value: "Keep Inst")]
        for i in 0..<30 { segments.append(TemporalValue(value: "Typo Inc", range: DateRange(), note: i < 25 ? "n\(i)" : nil)) }
        segments.append(TemporalValue(value: "Typo Inc"))
        var org = Organization(key: "og", names: Timeline(segments))
        org.authorized = []
        org.references = [NameClassificationRecord.make(field: "authorized", name: "Typo Inc", action: .withdraw, reason: "x", restsOn: [])]
        try LibraryStore(root: root).writeOrganization(org)
        let out = try payload(try service.committed(root).updateOrganization(key: "og", authorize: [], removeNames: ["Typo Inc=打錯"]))
        let row = try XCTUnwrap((out["namesRemoved"] as? [[String: Any]])?.first)
        XCTAssertEqual(row["segmentsRemoved"] as? Int, 31)
        let listed = try XCTUnwrap(row["segments"] as? [[String: Any]])
        XCTAssertEqual(listed.count, AkashicService.segmentsListedCap)
        XCTAssertFalse(listed.contains { $0.isEmpty }, "空的段不列")
    }
}
