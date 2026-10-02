import XCTest
@testable import AkashicCore
@testable import AkashicMCPKit
@testable import AkashicStoreIO

/// #557：organization 的 `authorized` 寫入面（`update-organization`／`akashic_update_organization`）。
///
/// 在此之前 `Organization.authorized` 零寫入面：`addOrganization` 不收、`OrgBootstrap` 不寫、`authorize-names` 只管 person——
/// `doctor` 的 `no authorized name: … organization` 恆為真且無法消除。使用者 2026-10-01 裁決：新增 `update-organization` 面，語意比照
/// `update-venue --authorize`（同書寫系統原子替換，被換下的移出 authorized、留在 names）。替換的邏輯是 `AuthorizedDesignation`
/// 那一份——本檔驗 organization 這一側的定位、寫入、報告與 store 邊界，替換細節的完整矩陣在 `VenueAuthorizedWriteTests`。
/// **沒有撤回面**（R1 verify 之後拿掉：裁決只說先提供 `--authorize`，而 organization 的 names 只增不減，撤回會讓剛加進 names 的名字成為
/// fallback 顯示名；見 `OrganizationUpdate.swift` 的檔頭）。
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
        let out = try payload(try service.updateOrganization(key: "iss", authorize: ["Institute of Statistical Science"], judgement: "fixture"))
        let o = try org()
        XCTAssertEqual(o.authorized, ["Institute of Statistical Science"])
        XCTAssertEqual(o.displayName(in: .latn), "Institute of Statistical Science")
        XCTAssertEqual(out["authorizedAdded"] as? [String], ["Institute of Statistical Science"])
        XCTAssertEqual(out["namesAdded"] as? [String], [], "名字本來就在 names")
        XCTAssertEqual(out["authorizedTotal"] as? Int, 1)
    }

    /// 同書寫系統替換：舊指定移出 authorized、留在 names（organization 沒有 variant，本來就不會被標）；不同書寫系統之間是 append。
    func testSameScriptReplacesAndCrossScriptAppends() throws {
        _ = try service.updateOrganization(key: "iss", authorize: ["INSTITUTE OF STATISTICAL SCIENCE", "中央研究院統計科學研究所"], judgement: "fixture")
        XCTAssertEqual(Set(try org().authorized), ["INSTITUTE OF STATISTICAL SCIENCE", "中央研究院統計科學研究所"], "跨書寫系統 append")
        let out = try payload(try service.updateOrganization(key: "iss", authorize: ["Institute of Statistical Science"], judgement: "fixture"))
        let o = try org()
        XCTAssertEqual(Set(o.authorized), ["Institute of Statistical Science", "中央研究院統計科學研究所"])
        XCTAssertTrue(o.names.entries.contains { $0.value == "INSTITUTE OF STATISTICAL SCIENCE" }, "被換下的留在 names")
        XCTAssertEqual(out["authorizedRemoved"] as? [String], ["INSTITUTE OF STATISTICAL SCIENCE"])
    }

    /// 不在 names 的一併加進 names（canonical 形）——authorized 是 names 的子集（store 邊界的不變式）。
    func testNameNotInNamesIsAppendedCanonical() throws {
        let out = try payload(try service.updateOrganization(key: "iss", authorize: ["  ISS  "], judgement: "fixture"))
        let o = try org()
        XCTAssertTrue(o.names.entries.contains { $0.value == "ISS" }, "\(o.names.entries.map(\.value))")
        XCTAssertEqual(o.authorized, ["ISS"])
        XCTAssertEqual(out["namesAdded"] as? [String], ["ISS"])
    }

    /// 冪等但不沉默：已是對外名稱的再指定一次報 alreadyAuthorized、不重複 append。
    func testConfirmingIsReportedNotSilent() throws {
        _ = try service.updateOrganization(key: "iss", authorize: ["Institute of Statistical Science"], judgement: "fixture")
        let out = try payload(try service.updateOrganization(key: "iss", authorize: ["Institute of Statistical Science "], judgement: "fixture"))
        XCTAssertEqual(out["alreadyAuthorized"] as? [String], ["Institute of Statistical Science"], "報 store 拼法")
        XCTAssertEqual(try org().authorized, ["Institute of Statistical Science"])
        XCTAssertEqual(try org().names.entries.count, 3)
    }

    /// 同一次兩個同書寫系統的名字是矛盾：整批拒絕、零寫入（訊息與 venue 同一句）。
    func testTwoSameScriptNamesAreRefused() throws {
        XCTAssertThrowsError(try service.updateOrganization(key: "iss", authorize: ["Institute of Statistical Science", "ISS"], judgement: "fixture")) { e in
            XCTAssertTrue("\(e)".contains("請選一個"), "\(e)")
        }
        XCTAssertEqual(try org().authorized, [])
        XCTAssertFalse(try org().names.entries.contains { $0.value == "ISS" }, "零寫入")
    }

    /// #669／#670：兩筆 organization 持同一個 key 時寫進哪一筆是猜——整批拒絕、零寫入。
    func testDuplicateKeyIsRefused() throws {
        let store = LibraryStore(root: root)
        try store.writeOrganization(Organization(key: "dup", names: Timeline([TemporalValue(value: "Dup A")]), id: UUID()))
        try store.writeOrganization(Organization(key: "dup", names: Timeline([TemporalValue(value: "Dup A")]), id: UUID()))
        XCTAssertThrowsError(try service.updateOrganization(key: "dup", authorize: ["Dup A"], judgement: "fixture")) { e in
            XCTAssertTrue("\(e)".contains("無法唯一定位"), "\(e)")
        }
        XCTAssertTrue(try store.load().organizations.filter { $0.key == "dup" }.allSatisfy { $0.authorized.isEmpty }, "零寫入")
    }

    func testUnknownKeyIsNotFound() throws {
        XCTAssertThrowsError(try service.updateOrganization(key: "no-such-org", authorize: ["X"], judgement: "fixture")) { e in
            guard case ServiceError.notFound = e else { return XCTFail("要是 notFound：\(e)") }
        }
    }

    /// 沒有要改的就不寫（只看參數，早於開 store）；key 格式不合同樣早於開 store。
    /// 「沒有要改的」看**過了 vetting 的結果**：沒給、空陣列、全是空白項是同一件事（R1 verify 第 13／16／26／28 列：MCP 的 `[]` 與 `[" "]`
    /// 曾走完寫檔與重建 index，而 CLI 把空陣列轉成 nil 早就擋了）。
    func testNothingToDoAndBadKeyAreRefusedBeforeTheStore() throws {
        for empty in [[], [" "], ["\t", ""]] as [[String]] {
            XCTAssertThrowsError(try AkashicService.checkUpdateOrganizationArguments(key: "iss", authorize: empty), "\(empty)") { e in
                XCTAssertTrue("\(e)".contains("沒有要改的"), "\(e)")
            }
        }
        XCTAssertThrowsError(try AkashicService.checkUpdateOrganizationArguments(key: "Not A Key", authorize: ["X"]))
    }

    /// 服務層（MCP 與 CLI 共用的入口）對空陣列與全空白項同樣整批拒絕，而且**沒有動那個檔**——人手編過的排版不被重新序列化。
    func testEmptyOrBlankAuthorizeDoesNotTouchTheFile() throws {
        let url = LibraryStore(root: root).entityURL(id: try org().id)
        try (String(contentsOf: url, encoding: .utf8) + "\n# hand-edited marker\n").write(to: url, atomically: true, encoding: .utf8)
        let before = try Data(contentsOf: url)
        for empty in [[], [" "]] as [[String]] {
            XCTAssertThrowsError(try service.updateOrganization(key: "iss", authorize: empty)) { e in
                XCTAssertTrue("\(e)".contains("沒有要改的"), "\(e)")
            }
        }
        XCTAssertEqual(try Data(contentsOf: url), before, "零寫入：檔案位元組不變")
    }

    /// 給的名字都已是對外名稱、而且同一句理由的記錄已經在：成功、報告 alreadyAuthorized，但**不寫檔、不重建 index**（R1 verify 第 28 列）。
    /// #564 起對已是對外名稱的名字說「確認」也留一筆記錄，所以第一次說確認是會寫的（`judgementsRecorded` 1）；位元組完全相同的第二次才是 no-op。
    /// 對照：真的有改動時同一個標記會被重新序列化掉——證明上面的「沒動」不是標記本來就寫不進去。
    func testAlreadyAuthorizedOnlyDoesNotRewriteTheFile() throws {
        _ = try service.updateOrganization(key: "iss", authorize: ["Institute of Statistical Science"], judgement: "fixture")
        let first = try payload(try service.updateOrganization(key: "iss", authorize: ["Institute of Statistical Science"], judgement: "fixture"))
        XCTAssertEqual(first["judgementsRecorded"] as? Int, 1, "第一次確認寫一筆「確認」記錄——不是 no-op")
        let url = LibraryStore(root: root).entityURL(id: try org().id)
        let marked = try String(contentsOf: url, encoding: .utf8) + "\n# hand-edited marker\n"
        try marked.write(to: url, atomically: true, encoding: .utf8)
        let out = try payload(try service.updateOrganization(key: "iss", authorize: ["Institute of Statistical Science", " "], judgement: "fixture"))
        XCTAssertEqual(out["alreadyAuthorized"] as? [String], ["Institute of Statistical Science"])
        XCTAssertEqual(out["authorizeDropped"] as? [String], [" "])
        XCTAssertEqual(out["judgementsRecorded"] as? Int, 0, "同一句確認已經記過")
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), marked, "沒有變動、沒有新記錄就不寫")
        // 對照：真的換了一個名字，檔案被重新序列化（標記消失）
        _ = try service.updateOrganization(key: "iss", authorize: ["ISS"], judgement: "fixture")
        XCTAssertFalse(try String(contentsOf: url, encoding: .utf8).contains("hand-edited marker"), "有變動時才寫")
    }

    /// 指定一個在 names 裡各段都已結束的名字（退役名）：不拒絕，但報 `authorizedNotCurrent`（R1 verify 第 6／17 列）——
    /// `Organization.authorized` 的「從當前有效的名稱中指定」是慣例、`validate` 不擋，而本面是第一個寫得進它的面，`displayName` 會變成退役名。
    func testRetiredNameIsAcceptedButReported() throws {
        let store = LibraryStore(root: root)
        try store.writeOrganization(Organization(key: "old", names: Timeline([
            TemporalValue(value: "Institute of Statistics", range: DateRange(start: "1960", end: "1993")),
            TemporalValue(value: "Institute of Statistical Science", range: DateRange(start: "1993"))]), id: UUID()))
        let retired = try payload(try service.updateOrganization(key: "old", authorize: ["Institute of Statistics"], judgement: "fixture"))
        XCTAssertEqual(retired["authorizedNotCurrent"] as? [String], ["Institute of Statistics"])
        XCTAssertEqual(retired["authorizedAdded"] as? [String], ["Institute of Statistics"], "不拒絕：照寫")
        let written = try XCTUnwrap(try store.load().organizations.first { $0.key == "old" })
        XCTAssertEqual(written.authorized, ["Institute of Statistics"])
        XCTAssertEqual(written.displayName, "Institute of Statistics", "displayName 確實變成退役名——所以要說")
        // 已在的退役名再說一次也報（狀態不是一次性事件）；當前有效的名字、新加進 names 的名字（沒有時間欄位＝開放段）不報
        let again = try payload(try service.updateOrganization(key: "old", authorize: ["Institute of Statistics"], judgement: "fixture"))
        XCTAssertEqual(again["authorizedNotCurrent"] as? [String], ["Institute of Statistics"])
        XCTAssertNil(try payload(try service.updateOrganization(key: "old", authorize: ["Institute of Statistical Science"], judgement: "fixture"))["authorizedNotCurrent"])
        XCTAssertNil(try payload(try service.updateOrganization(key: "old", authorize: ["中央研究院統計科學研究所"], judgement: "fixture"))["authorizedNotCurrent"])
    }

    /// 所有名字都沒有開放段的機構（已解散）：沒有現行名稱可退，指定它最後的名字是讓顯示名不再是裸 key 的做法——不報 `authorizedNotCurrent`
    /// （#557 R2 verify 第 10／22／35 列）。只有觀測點（attested）的段不是「已結束」（#661）；機構另有開放段時它仍算不是現行，照報。
    func testNotCurrentIsOnlyReportedWhenTheOrganizationHasACurrentName() throws {
        let store = LibraryStore(root: root)
        try store.writeOrganization(Organization(key: "defunct", names: Timeline([
            TemporalValue(value: "Defunct Institute", range: DateRange(start: "1960", end: "1993"))]), id: UUID()))
        let dissolved = try payload(try service.updateOrganization(key: "defunct", authorize: ["Defunct Institute"], judgement: "fixture"))
        XCTAssertNil(dissolved["authorizedNotCurrent"], "沒有現行名稱的機構不報：\(dissolved)")
        try store.writeOrganization(Organization(key: "obs", names: Timeline([
            TemporalValue(value: "Obs Institute", range: DateRange(attested: ["2003", "2011"])),
            TemporalValue(value: "Current Institute")]), id: UUID()))
        let observed = try payload(try service.updateOrganization(key: "obs", authorize: ["Obs Institute"], judgement: "fixture"))
        XCTAssertEqual(observed["authorizedNotCurrent"] as? [String], ["Obs Institute"], "\(observed)")
    }

    /// 同名而位元組不同（NFD）的舊指定：報 `authorizedRewritten` 並真的改寫位元組；第二次（已是 canonical）才走不寫檔的路（#557 R2 verify 第 7 列）。
    func testNFDOldDesignationIsRewrittenAndReported() throws {
        let store = LibraryStore(root: root)
        let nfd = "Institut für Statistik".decomposedStringWithCanonicalMapping
        // names 是 canonical 形、authorized 是手改成 NFD 的舊指定（`String ==` 看不出差別，子集檢查照過）
        try store.writeOrganization(Organization(key: "nfd", names: Timeline([TemporalValue(value: "Institut für Statistik")]),
                                                 authorized: [nfd], id: UUID()))
        let out = try payload(try service.updateOrganization(key: "nfd", authorize: ["Institut für Statistik"], judgement: "fixture"))
        XCTAssertEqual(out["authorizedRewritten"] as? [String], ["Institut für Statistik"], "\(out)")
        let written = try XCTUnwrap(try store.load().organizations.first { $0.key == "nfd" })
        XCTAssertEqual(written.authorized.map { Array($0.utf8) }, [Array("Institut für Statistik".precomposedStringWithCanonicalMapping.utf8)],
                       "位元組真的換成 canonical")
        let url = store.entityURL(id: written.id)
        let marked = try String(contentsOf: url, encoding: .utf8) + "\n# marker\n"
        try marked.write(to: url, atomically: true, encoding: .utf8)
        let again = try payload(try service.updateOrganization(key: "nfd", authorize: ["Institut für Statistik"], judgement: "fixture"))
        XCTAssertEqual(again["alreadyAuthorized"] as? [String], ["Institut für Statistik"])
        XCTAssertEqual(again["judgementsRecorded"] as? Int, 0)
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), marked, "沒有變動、沒有新記錄就不寫")
    }

    /// 寫檔成功之後 index 重建失敗：呼叫回成功、報告多 `indexRebuilt: false`（R1 verify 第 1 列）——檔案已經落盤，擲錯會讓報告消失、
    /// 而重試只會得到 alreadyAuthorized。做法同移除面一族（`RemovalReportSupport.swift`）。
    /// 強迫重建失敗：service 帶 registry key、`AKASHIC_HOME` 指向一個**普通檔**（同 `RemovalIndexRebuildFailureTests`）。
    func testIndexRebuildFailureAfterTheWriteIsReportedNotThrown() throws {
        let blocker = FileManager.default.temporaryDirectory.appendingPathComponent("akashic-oau-home-\(UUID().uuidString)")
        try Data("not a directory".utf8).write(to: blocker)
        defer { try? FileManager.default.removeItem(at: blocker) }
        let failing = AkashicService(root: root, key: "rebuildfail", environment: ["AKASHIC_HOME": blocker.path])
        XCTAssertThrowsError(try FileManager.default.createDirectory(
            at: failing.store.indexURL.deletingLastPathComponent(), withIntermediateDirectories: true), "前提：這個 service 的 index 重建真的會失敗")

        let out = try payload(try failing.updateOrganization(key: "iss", authorize: ["Institute of Statistical Science"], judgement: "fixture"))
        XCTAssertEqual(out["authorizedAdded"] as? [String], ["Institute of Statistical Science"], "報告沒有消失")
        XCTAssertEqual(out["indexRebuilt"] as? Bool, false, "\(out)")
        XCTAssertNotNil(out["indexRebuildError"] as? String)
        let note = out["indexNote"] as? String ?? ""
        XCTAssertTrue(note.contains("報告") && note.contains("akashic doctor") && note.contains("alreadyAuthorized"), note)
        // #557 R2 verify 第 30／38 列：#564 之後以同一句理由重試會多寫一筆「確認」——note 不能再說「只會得到 alreadyAuthorized」
        XCTAssertTrue(note.contains("確認"), note)
        XCTAssertFalse(note.contains("只會得到"), note)
        XCTAssertEqual(try org().authorized, ["Institute of Statistical Science"], "寫入已經落盤")
        // 重試：名字已是對外名稱，只會得到 alreadyAuthorized——報告說的是真的。#564 起第一次重試會多寫一筆「確認」記錄（index 仍重建失敗）；
        // 位元組完全相同的再一次重試才是沒有變動、沒有新記錄：不寫、不重建，所以不多出 index 鍵
        let retry = try payload(try failing.updateOrganization(key: "iss", authorize: ["Institute of Statistical Science"], judgement: "fixture"))
        XCTAssertEqual(retry["alreadyAuthorized"] as? [String], ["Institute of Statistical Science"])
        XCTAssertEqual(retry["judgementsRecorded"] as? Int, 1)
        let again = try payload(try failing.updateOrganization(key: "iss", authorize: ["Institute of Statistical Science"], judgement: "fixture"))
        XCTAssertEqual(again["alreadyAuthorized"] as? [String], ["Institute of Statistical Science"])
        XCTAssertEqual(again["judgementsRecorded"] as? Int, 0)
        XCTAssertNil(again["indexRebuilt"])
        // 成功路徑的 payload 不多出 index 鍵
        XCTAssertNil(try payload(try service.updateOrganization(key: "iss", authorize: ["ISS"], judgement: "fixture"))["indexRebuilt"])
    }

    /// 被換下的舊指定被 `field: authorized` 的 reference 指著：拒絕、零寫入；organization 沒有 reference 的移除面，出路是手改 YAML。
    func testPinnedOldDesignationPointsToHandEditing() throws {
        var o = try org()
        o.authorized = ["INSTITUTE OF STATISTICAL SCIENCE"]
        o.references = [ProvenanceReference(field: "authorized", value: "INSTITUTE OF STATISTICAL SCIENCE",
                                            kind: .retrieval(url: "https://example.org/about", retrieved: "2026-10-01", status: 200,
                                                             mediaType: "text/html", content: "sha256:" + String(repeating: "ab", count: 32)))]
        try LibraryStore(root: root).writeOrganization(o)
        XCTAssertThrowsError(try service.updateOrganization(key: "iss", authorize: ["Institute of Statistical Science"], judgement: "fixture")) { e in
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
        _ = try service.updateOrganization(key: "iss", authorize: ["Institute of Statistical Science"], judgement: "fixture")
        XCTAssertEqual(try gaps(), 0)
    }
}
