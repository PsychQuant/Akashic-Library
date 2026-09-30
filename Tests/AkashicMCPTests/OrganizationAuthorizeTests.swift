import XCTest
@testable import AkashicCore
@testable import AkashicMCPKit
@testable import AkashicStoreIO

/// #557：organization 的 `authorized` 寫入面（`update-organization`／`akashic_update_organization`）。
///
/// 在此之前 `Organization.authorized` 零寫入面：`addOrganization` 不收、`OrgBootstrap` 不寫、`authorize-names` 只管 person——
/// `doctor` 的 `no authorized name: … organization` 恆為真且無法消除。使用者 2026-10-01 裁決：新增 `update-organization` 面，語意比照
/// `update-venue --authorize`（同書寫系統原子替換，被換下的移出 authorized、留在 names）。替換與撤回的邏輯是 `AuthorizedDesignation`
/// 那一份——本檔驗 organization 這一側的定位、寫入、報告與 store 邊界，替換細節的完整矩陣在 `VenueAuthorizedWriteTests`。
final class OrganizationAuthorizeTests: XCTestCase {
    private var root: URL!
    private var service: AkashicService!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("akashic-oau-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root.appendingPathComponent("entities"), withIntermediateDirectories: true)
        try StoreVersion.write(root: root, format: StoreVersion.supported)
        service = AkashicService(root: root)
        _ = try service.addOrganization(key: "iss", names: ["INSTITUTE OF STATISTICAL SCIENCE", "Institute of Statistical Science", "中央研究院統計科學研究所"])
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    private func org() throws -> Organization {
        try XCTUnwrap(LibraryStore(root: root).load().organizations.first { $0.key == "iss" })
    }
    private func payload(_ s: String) throws -> [String: Any] {
        try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(s.utf8)) as? [String: Any])
    }

    /// 本面存在的理由：authorized 寫得進去、讀得回來，`displayName` 跟著換。
    func testAuthorizeWritesTheDesignation() throws {
        XCTAssertEqual(try org().authorized, [], "fixture：addOrganization 不寫 authorized")
        let out = try payload(try service.updateOrganization(key: "iss", authorize: ["Institute of Statistical Science"]))
        let o = try org()
        XCTAssertEqual(o.authorized, ["Institute of Statistical Science"])
        XCTAssertEqual(o.displayName(in: .latn), "Institute of Statistical Science")
        XCTAssertEqual(out["authorizedAdded"] as? [String], ["Institute of Statistical Science"])
        XCTAssertEqual(out["namesAdded"] as? [String], [], "名字本來就在 names")
        XCTAssertEqual(out["authorizedTotal"] as? Int, 1)
    }

    /// 同書寫系統替換：舊指定移出 authorized、留在 names（organization 沒有 variant，本來就不會被標）；不同書寫系統之間是 append。
    func testSameScriptReplacesAndCrossScriptAppends() throws {
        _ = try service.updateOrganization(key: "iss", authorize: ["INSTITUTE OF STATISTICAL SCIENCE", "中央研究院統計科學研究所"])
        XCTAssertEqual(Set(try org().authorized), ["INSTITUTE OF STATISTICAL SCIENCE", "中央研究院統計科學研究所"], "跨書寫系統 append")
        let out = try payload(try service.updateOrganization(key: "iss", authorize: ["Institute of Statistical Science"]))
        let o = try org()
        XCTAssertEqual(Set(o.authorized), ["Institute of Statistical Science", "中央研究院統計科學研究所"])
        XCTAssertTrue(o.names.entries.contains { $0.value == "INSTITUTE OF STATISTICAL SCIENCE" }, "被換下的留在 names")
        XCTAssertEqual(out["authorizedRemoved"] as? [String], ["INSTITUTE OF STATISTICAL SCIENCE"])
    }

    /// 不在 names 的一併加進 names（canonical 形）——authorized 是 names 的子集（store 邊界的不變式）。
    func testNameNotInNamesIsAppendedCanonical() throws {
        let out = try payload(try service.updateOrganization(key: "iss", authorize: ["  ISS  "]))
        let o = try org()
        XCTAssertTrue(o.names.entries.contains { $0.value == "ISS" }, "\(o.names.entries.map(\.value))")
        XCTAssertEqual(o.authorized, ["ISS"])
        XCTAssertEqual(out["namesAdded"] as? [String], ["ISS"])
    }

    /// 冪等但不沉默：已是對外名稱的再指定一次報 alreadyAuthorized、不重複 append。
    func testConfirmingIsReportedNotSilent() throws {
        _ = try service.updateOrganization(key: "iss", authorize: ["Institute of Statistical Science"])
        let out = try payload(try service.updateOrganization(key: "iss", authorize: ["Institute of Statistical Science "]))
        XCTAssertEqual(out["alreadyAuthorized"] as? [String], ["Institute of Statistical Science"], "報 store 拼法")
        XCTAssertEqual(try org().authorized, ["Institute of Statistical Science"])
        XCTAssertEqual(try org().names.entries.count, 3)
    }

    /// 同一次兩個同書寫系統的名字是矛盾：整批拒絕、零寫入（訊息與 venue 同一句）。
    func testTwoSameScriptNamesAreRefused() throws {
        XCTAssertThrowsError(try service.updateOrganization(key: "iss", authorize: ["Institute of Statistical Science", "ISS"])) { e in
            XCTAssertTrue("\(e)".contains("請選一個"), "\(e)")
        }
        XCTAssertEqual(try org().authorized, [])
        XCTAssertFalse(try org().names.entries.contains { $0.value == "ISS" }, "零寫入")
    }

    /// 同一個名字既 authorize 又 unauthorize 是兩句矛盾的話（與 venue 共用 `refuseAuthorizeUnauthorizeOverlap`）——讀 store 之前就擋。
    func testSameNameToAuthorizeAndUnauthorizeIsRefused() throws {
        XCTAssertThrowsError(try AkashicService.checkUpdateOrganizationArguments(
            key: "iss", authorize: ["Institute of Statistical Science"], unauthorize: [" Institute of Statistical Science"])) { e in
            XCTAssertTrue("\(e)".contains("同時被送進 authorize 與 unauthorize"), "\(e)")
        }
        XCTAssertThrowsError(try service.updateOrganization(key: "iss", authorize: ["ISS"], unauthorize: ["ISS"]))
        XCTAssertFalse(try org().names.entries.contains { $0.value == "ISS" }, "零寫入")
    }

    /// #669／#670：兩筆 organization 持同一個 key 時寫進哪一筆是猜——整批拒絕、零寫入。
    func testDuplicateKeyIsRefused() throws {
        let store = LibraryStore(root: root)
        try store.writeOrganization(Organization(key: "dup", names: Timeline([TemporalValue(value: "Dup A")]), id: UUID()))
        try store.writeOrganization(Organization(key: "dup", names: Timeline([TemporalValue(value: "Dup A")]), id: UUID()))
        XCTAssertThrowsError(try service.updateOrganization(key: "dup", authorize: ["Dup A"])) { e in
            XCTAssertTrue("\(e)".contains("無法唯一定位"), "\(e)")
        }
        XCTAssertTrue(try store.load().organizations.filter { $0.key == "dup" }.allSatisfy { $0.authorized.isEmpty }, "零寫入")
    }

    func testUnknownKeyIsNotFound() throws {
        XCTAssertThrowsError(try service.updateOrganization(key: "no-such-org", authorize: ["X"])) { e in
            guard case ServiceError.notFound = e else { return XCTFail("要是 notFound：\(e)") }
        }
    }

    /// 沒有要改的就不寫（只看參數，早於開 store）；key 格式不合同樣早於開 store。
    func testNothingToDoAndBadKeyAreRefusedBeforeTheStore() throws {
        XCTAssertThrowsError(try AkashicService.checkUpdateOrganizationArguments(key: "iss", authorize: nil, unauthorize: nil)) { e in
            XCTAssertTrue("\(e)".contains("沒有要改的"), "\(e)")
        }
        XCTAssertThrowsError(try AkashicService.checkUpdateOrganizationArguments(key: "Not A Key", authorize: ["X"], unauthorize: nil))
    }

    /// 撤回（#559 的同一份邏輯）：移出 authorized、留在 names；非成員整批拒絕。
    func testUnauthorizeWithdraws() throws {
        _ = try service.updateOrganization(key: "iss", authorize: ["Institute of Statistical Science"])
        XCTAssertThrowsError(try service.updateOrganization(key: "iss", authorize: nil, unauthorize: ["ISS"])) { e in
            XCTAssertTrue("\(e)".contains("不是這筆 organization 目前的 authorized"), "\(e)")
        }
        let out = try payload(try service.updateOrganization(key: "iss", authorize: nil, unauthorize: ["Institute of Statistical Science"]))
        let o = try org()
        XCTAssertEqual(o.authorized, [])
        XCTAssertEqual(o.names.entries.count, 3, "名字留在 names")
        XCTAssertEqual(out["authorizedWithdrawn"] as? [String], ["Institute of Statistical Science"])
    }

    /// 被換下的舊指定被 `field: authorized` 的 reference 指著：拒絕、零寫入；organization 沒有 reference 的移除面，出路是手改 YAML。
    func testPinnedOldDesignationPointsToHandEditing() throws {
        var o = try org()
        o.authorized = ["INSTITUTE OF STATISTICAL SCIENCE"]
        o.references = [ProvenanceReference(field: "authorized", value: "INSTITUTE OF STATISTICAL SCIENCE",
                                            kind: .retrieval(url: "https://example.org/about", retrieved: "2026-10-01", status: 200,
                                                             mediaType: "text/html", content: "sha256:" + String(repeating: "ab", count: 32)))]
        try LibraryStore(root: root).writeOrganization(o)
        XCTAssertThrowsError(try service.updateOrganization(key: "iss", authorize: ["Institute of Statistical Science"])) { e in
            let m = "\(e)"
            XCTAssertTrue(m.contains("field: authorized") && m.contains("手改 YAML") && !m.contains("--remove-reference"), m)
        }
        XCTAssertEqual(try org().authorized, ["INSTITUTE OF STATISTICAL SCIENCE"], "零寫入")
    }

    /// issue 的動機：`doctor` 的 `no authorized name: … organization` 修得掉了。
    func testDoctorNameGapShrinks() throws {
        func gaps() throws -> Int? {
            let d = try payload(try service.doctor())
            return (d["noAuthorizedName"] as? [String: Any])?["organizations"] as? Int
        }
        XCTAssertEqual(try gaps(), 1)
        _ = try service.updateOrganization(key: "iss", authorize: ["Institute of Statistical Science"])
        XCTAssertEqual(try gaps(), 0)
    }
}
