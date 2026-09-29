import XCTest
@testable import AkashicCore
@testable import AkashicStoreIO
@testable import AkashicMCPKit

/// #642 的 service 面（CLI `library` 與 MCP `akashic_libraries` 共用這一條路徑）。
///
/// 使用者 2026-09-25 的裁定（Clarity row 1）：不符規則的條目**不是拒絕、也不是同意後照寫，而是改成正確的再寫**——
/// 符合的寫、不符的不寫並逐筆說出依據。查不到依據（未標性質、文件不在庫）就不寫。
final class LibraryMembershipServiceTests: XCTestCase {
    var root: URL!
    var fakeHome: URL!
    var service: AkashicService!

    override func setUpWithError() throws {
        fakeHome = FileManager.default.temporaryDirectory.appendingPathComponent("akashic-home-\(UUID().uuidString)")
        root = FileManager.default.temporaryDirectory.appendingPathComponent("akashic-lmsv-\(UUID().uuidString)")
        try LibraryStore(root: root).ensureLayout()
        service = AkashicService(root: root, environment: ["AKASHIC_HOME": fakeHome.path])
        let store = LibraryStore(root: root)
        try store.writeVenue(Venue(key: "pm", type: .periodical, names: Timeline([TemporalValue(value: "PM")])))
        for (ck, venues, cites) in [("pm2020a", [VenueRef.key("pm")], [String]()),
                                    ("pm2021a", [.key("pm")], []),
                                    ("other2020a", [.key("psychometrika")], []),
                                    ("lit2020a", [.literal("Psychological Methods")], []),
                                    ("draft2026a", [], ["pm2020a", "other2020a"])] {
            var e = Entry(id: UUID(), citekey: ck, type: .periodicalArticle, title: ck, venues: venues)
            e.akashic.relations.cites = cites
            try store.writeEntry(e)
        }
    }
    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
        try? FileManager.default.removeItem(at: fakeHome)
    }

    private func json(_ s: String) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: Data(s.utf8)) as? [String: Any])
    }
    private func membership(_ ck: String) throws -> [String] {
        try LibraryStore(root: root).load().entries.first { $0.citekey == ck }?.akashic.libraries ?? []
    }
    private func create(_ key: String, _ m: AkashicService.LibraryMembershipInput) throws {
        _ = try service.libraries(action: "create", key: key, name: key, description: nil, citekey: nil, membership: m)
    }

    // MARK: - 性質是必填的依據

    func testCreateRequiresAKind() throws {
        XCTAssertThrowsError(try service.libraries(action: "create", key: "x", name: "X", description: nil, citekey: nil)) {
            XCTAssertTrue(String(describing: $0).contains("kind"), "\($0)")
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: LibraryStore(root: root).libraryURL(key: "x").path))
        try create("reading", .init(kind: "topic"))
        let list = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(
            service.libraries(action: "list", key: nil, name: nil, description: nil, citekey: nil).utf8)) as? [[String: Any]])
        XCTAssertEqual(list.first?["kind"] as? String, "topic")
    }

    func testCreateRefusesARuleWhoseVenueOrDocumentIsNotInTheStore() {
        XCTAssertThrowsError(try create("c", .init(kind: "rule", venue: "ghost")))
        XCTAssertThrowsError(try create("d", .init(kind: "document", document: "ghost2026a")))
    }

    func testArgumentOnlyChecksRejectMalformedInput() {
        for bad: AkashicService.LibraryMembershipInput in [
            .init(kind: "catalog"), .init(kind: "rule"), .init(kind: "topic", venue: "pm"),
            .init(kind: "document"), .init(kind: "rule", venue: "pm", types: ["no-such-type"]),
            .init(kind: "rule", venue: "Bad Key"), .init(venue: "pm"),
            .init(kind: "rule", venue: "pm", source: "  "),
        ] {
            XCTAssertThrowsError(try AkashicService.parseLibraryMembership(bad), "\(bad)")
        }
        XCTAssertEqual(try AkashicService.parseLibraryMembership(.init(kind: "rule", venue: "pm", types: ["periodical-article"])),
                       .rule(LibraryRule(venue: "pm", types: [.periodicalArticle])))
        XCTAssertNil(try AkashicService.parseLibraryMembership(.init()))
    }

    // MARK: - add：改成正確的再寫

    func testUnmarkedLibraryRefusesAddWithZeroWrites() throws {
        try LibraryStore(root: root).writeLibrary(Library(key: "old", name: "舊"))
        XCTAssertThrowsError(try service.setMembership(action: "add", key: "old", citekeys: ["pm2020a"])) {
            XCTAssertTrue(String(describing: $0).contains("set-kind"), "\($0)")
        }
        XCTAssertEqual(try membership("pm2020a"), [])
        // remove 不查依據——清掉錯的成員關係永遠可以
        var e = try XCTUnwrap(try LibraryStore(root: root).load().entries.first { $0.citekey == "pm2021a" })
        e.akashic.libraries = ["old"]
        try LibraryStore(root: root).writeEntry(e)
        XCTAssertEqual(try service.setMembership(action: "remove", key: "old", citekeys: ["pm2021a"]).written, ["pm2021a"])
    }

    func testRuleLibraryWritesOnlyConformingEntriesAndNamesTheRest() throws {
        try create("pm-catalog", .init(kind: "rule", venue: "pm", source: "openalex:S45419345"))
        let report = try service.setMembership(action: "add", key: "pm-catalog",
                                               citekeys: ["pm2020a", "other2020a", "lit2020a", "pm2021a"])
        XCTAssertEqual(report.written, ["pm2020a", "pm2021a"])
        XCTAssertEqual(report.skipped.map(\.citekey), ["other2020a", "lit2020a"])
        XCTAssertTrue(report.skipped[0].reason.contains("psychometrika"), report.skipped[0].reason)
        XCTAssertTrue(report.skipped[1].reason.contains("resolve-venues"), report.skipped[1].reason)
        XCTAssertTrue(report.basis.contains("pm") && report.basis.contains("openalex"), report.basis)
        XCTAssertEqual(try membership("pm2020a"), ["pm-catalog"])
        XCTAssertEqual(try membership("other2020a"), [], "不符規則的不寫")
    }

    func testDocumentLibraryAcceptsOnlyWhatTheDocumentCites() throws {
        try create("paper", .init(kind: "document", document: "draft2026a"))
        let report = try service.setMembership(action: "add", key: "paper", citekeys: ["pm2020a", "pm2021a", "other2020a"])
        XCTAssertEqual(report.written, ["pm2020a", "other2020a"])
        XCTAssertEqual(report.skipped.map(\.citekey), ["pm2021a"])
    }

    func testTopicLibraryWritesWhatTheUserChose() throws {
        try create("reading", .init(kind: "topic"))
        let report = try service.setMembership(action: "add", key: "reading", citekeys: ["other2020a", "lit2020a"])
        XCTAssertEqual(report.written, ["other2020a", "lit2020a"])
        XCTAssertTrue(report.skipped.isEmpty)
    }

    /// MCP 的單筆 add：不符時不擲錯（沒有寫錯任何東西），回應說出沒寫與原因。
    func testSingleAddReportsASkipInsteadOfThrowing() throws {
        try create("pm-catalog", .init(kind: "rule", venue: "pm"))
        let out = try json(service.libraries(action: "add", key: "pm-catalog", name: nil, description: nil, citekey: "other2020a"))
        XCTAssertEqual(out["written"] as? Bool, false)
        XCTAssertTrue((out["skipped"] as? String)?.contains("psychometrika") ?? false, "\(out)")
        XCTAssertNotNil(out["basis"])
        let ok = try json(service.libraries(action: "add", key: "pm-catalog", name: nil, description: nil, citekey: "pm2020a"))
        XCTAssertEqual(ok["written"] as? Bool, true)
        XCTAssertEqual(ok["libraries"] as? [String], ["pm-catalog"])
    }

    func testMembershipParametersOnlyAccompanyCreateAndSetKind() throws {
        try create("reading", .init(kind: "topic"))
        XCTAssertThrowsError(try service.libraries(action: "add", key: "reading", name: nil, description: nil,
                                                   citekey: "pm2020a", membership: .init(kind: "topic")))
    }

    // MARK: - set-kind 與 check：既有的錯誤看得見

    func testSetKindMarksAnExistingLibraryAndReportsCurrentViolations() throws {
        let store = LibraryStore(root: root)
        try store.writeLibrary(Library(key: "pm-catalog", name: "PM"))
        for ck in ["pm2020a", "other2020a"] {
            var e = try XCTUnwrap(try store.load().entries.first { $0.citekey == ck })
            e.akashic.libraries = ["pm-catalog"]
            try store.writeEntry(e)
        }
        let out = try json(service.libraries(action: "set-kind", key: "pm-catalog", name: nil, description: nil,
                                             citekey: nil, membership: .init(kind: "rule", venue: "pm")))
        XCTAssertEqual(out["nonconforming"] as? Int, 1)
        XCTAssertEqual(try store.load().libraries.first?.membership, .rule(LibraryRule(venue: "pm")))
        XCTAssertEqual(try membership("other2020a"), ["pm-catalog"], "set-kind 不自動移除——移除是另一個寫入")

        let check = try json(service.libraries(action: "check", key: "pm-catalog", name: nil, description: nil, citekey: nil))
        let items = try XCTUnwrap(check["nonconforming"] as? [[String: Any]])
        XCTAssertEqual(items.map { $0["citekey"] as? String }, ["other2020a"])
        XCTAssertEqual(check["total"] as? Int, 1)
        XCTAssertThrowsError(try service.libraries(action: "check", key: "ghost", name: nil, description: nil, citekey: nil))
        XCTAssertThrowsError(try service.libraries(action: "set-kind", key: "pm-catalog", name: nil, description: nil,
                                                   citekey: nil, membership: .init(kind: "document", document: "ghost2026a")))
        XCTAssertEqual(try store.load().libraries.first?.membership, .rule(LibraryRule(venue: "pm")), "拒絕＝零寫入")
    }

    // MARK: - R1 verify：依據不明確、排除清單也是參照、set-kind 是整值替換

    private func registryBytes(_ key: String) throws -> Data {
        try Data(contentsOf: LibraryStore(root: root).libraryURL(key: key))
    }

    /// 同一個不明確的依據，設定規則時被拒絕、使用規則時就不能放行：規則建好之後 venue key 變成重複，add 三面都不寫，
    /// `check` 揭露（零成員也照說）。
    func testARuleWhoseVenueKeyBecomesDuplicatedRefusesAddAndCheckSaysSo() throws {
        try create("pm-catalog", .init(kind: "rule", venue: "pm"))
        try create("pm-empty", .init(kind: "rule", venue: "pm"))   // 零成員
        XCTAssertEqual(try service.setMembership(action: "add", key: "pm-catalog", citekeys: ["pm2020a"]).written, ["pm2020a"])
        // 手改或匯入造成同 key 的第二筆 venue
        try LibraryStore(root: root).writeVenue(Venue(key: "pm", type: .periodical, names: Timeline([TemporalValue(value: "PM again")])))
        let report = try service.setMembership(action: "add", key: "pm-catalog", citekeys: ["pm2021a"])
        XCTAssertTrue(report.written.isEmpty, "分不出規則指的是哪一筆 venue → 不寫")
        XCTAssertTrue(report.skipped.first?.reason.contains("不只一筆") ?? false, "\(report.skipped)")
        XCTAssertEqual(try membership("pm2021a"), [])
        let single = try json(service.libraries(action: "add", key: "pm-catalog", name: nil, description: nil, citekey: "pm2021a"))
        XCTAssertEqual(single["written"] as? Bool, false)
        // check：既有成員 pm2020a 也不再能被查證；basisProblem 逐字說出原因
        let check = try json(service.libraries(action: "check", key: "pm-catalog", name: nil, description: nil, citekey: nil))
        XCTAssertTrue((check["basisProblem"] as? String)?.contains("不只一筆") ?? false, "\(check)")
        XCTAssertEqual(check["total"] as? Int, 1)
        // 零成員的 library 也照樣揭露（沒有成員可列，不代表依據沒問題）
        let empty = try json(service.libraries(action: "check", key: "pm-empty", name: nil, description: nil, citekey: nil))
        XCTAssertEqual(empty["total"] as? Int, 0)
        XCTAssertTrue((empty["basisProblem"] as? String)?.contains("不只一筆") ?? false, "\(empty)")
        // doctor 的跨記錄警告也點名
        let doctor = try json(service.doctor())
        let cross = try XCTUnwrap((doctor["crossRecordIssues"] as? [String: Any])?["first"] as? [[String: Any]])
        XCTAssertTrue(cross.contains { ($0["message"] as? String)?.contains("pm-empty") ?? false }, "\(cross)")
    }

    func testSetKindAndCreateRefuseARuleWhoseVenueKeyIsDuplicated() throws {
        try LibraryStore(root: root).writeVenue(Venue(key: "pm", type: .periodical, names: Timeline([TemporalValue(value: "PM again")])))
        XCTAssertThrowsError(try create("dup-catalog", .init(kind: "rule", venue: "pm"))) {
            XCTAssertTrue(String(describing: $0).contains("不只一筆"), "\($0)")
        }
    }

    /// 排除清單的 citekey 也是參照：打錯的 citekey 讓排除無聲失效——create 與 set-kind 都要拒絕，零寫入。
    func testCreateAndSetKindRefuseAnExcludedCitekeyThatIsNotInTheStore() throws {
        XCTAssertThrowsError(try create("pm-catalog", .init(kind: "rule", venue: "pm", excluded: ["appendix2020b"]))) {
            let m = String(describing: $0)
            XCTAssertTrue(m.contains("excluded") && m.contains("appendix2020b"), m)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: LibraryStore(root: root).libraryURL(key: "pm-catalog").path))
        try create("pm-catalog", .init(kind: "rule", venue: "pm", excluded: ["other2020a"]))   // 在庫的可以
        let before = try registryBytes("pm-catalog")
        StoreGitCommit.commitAll(root)
        XCTAssertThrowsError(try service.libraries(action: "set-kind", key: "pm-catalog", name: nil, description: nil, citekey: nil,
                                                   membership: .init(kind: "rule", venue: "pm", excluded: ["other2020a", "typo2020a"])))
        XCTAssertEqual(try registryBytes("pm-catalog"), before, "拒絕＝零寫入")
    }

    /// set-kind 是整值替換：回應要說出被換掉的先前性質與規則（從未標性質也說），不然只看得到新值、舊值要去翻 git。
    func testSetKindEchoesThePreviousMembership() throws {
        try LibraryStore(root: root).writeLibrary(Library(key: "old", name: "舊"))
        let first = try json(service.libraries(action: "set-kind", key: "old", name: nil, description: nil, citekey: nil,
                                               membership: .init(kind: "rule", venue: "pm", types: ["periodical-article"],
                                                                 excluded: ["other2020a"], source: "openalex:S1")))
        XCTAssertEqual((first["previous"] as? [String: Any])?["kind"] as? String, "unmarked")
        StoreGitCommit.commitAll(root)
        let second = try json(service.libraries(action: "set-kind", key: "old", name: nil, description: nil, citekey: nil,
                                                membership: .init(kind: "topic")))
        let previous = try XCTUnwrap(second["previous"] as? [String: Any])
        XCTAssertEqual(previous["kind"] as? String, "rule")
        XCTAssertEqual(previous["venue"] as? String, "pm")
        XCTAssertEqual(previous["types"] as? [String], ["periodical-article"])
        XCTAssertEqual(previous["excluded"] as? [String], ["other2020a"])
        XCTAssertEqual(previous["source"] as? String, "openalex:S1")
        XCTAssertTrue((second["previousBasis"] as? String)?.contains("規則型") ?? false, "\(second)")
        XCTAssertEqual((second["membership"] as? [String: Any])?["kind"] as? String, "topic")
    }

    /// 替換一條**既有**的性質時，舊值只剩 git 那一份——registry 檔要 tracked 且 clean；從未標性質標成任何一種不需要。
    func testReplacingAnExistingMembershipRequiresACommittedRegistryFile() throws {
        try create("pm-catalog", .init(kind: "rule", venue: "pm", excluded: ["other2020a"]))   // 剛建：store 不在 git 裡
        let before = try registryBytes("pm-catalog")
        let toTopic = AkashicService.LibraryMembershipInput(kind: "topic")
        XCTAssertThrowsError(try service.libraries(action: "set-kind", key: "pm-catalog", name: nil, description: nil,
                                                   citekey: nil, membership: toTopic)) {
            XCTAssertTrue(String(describing: $0).contains("git 工作樹"), "\($0)")
        }
        XCTAssertEqual(try registryBytes("pm-catalog"), before, "拒絕＝零寫入：規則沒被降成 topic")
        // untracked（git 在，但這個檔沒進去）
        StoreGitCommit.run(["init", "-q"], in: root)
        XCTAssertThrowsError(try service.libraries(action: "set-kind", key: "pm-catalog", name: nil, description: nil,
                                                   citekey: nil, membership: toTopic)) {
            XCTAssertTrue(String(describing: $0).contains("pm-catalog"), "\($0)")
        }
        // tracked 且 clean：放行；舊值就在 git 裡
        StoreGitCommit.commitAll(root)
        XCTAssertNoThrow(try service.libraries(action: "set-kind", key: "pm-catalog", name: nil, description: nil,
                                               citekey: nil, membership: toTopic))
        // dirty（上一步改寫後尚未 commit）：再替換一次要拒絕
        XCTAssertThrowsError(try service.libraries(action: "set-kind", key: "pm-catalog", name: nil, description: nil,
                                                   citekey: nil, membership: .init(kind: "rule", venue: "pm")))
        // 重送**相同**的值不需要閘（沒有東西被換掉）
        XCTAssertNoThrow(try service.libraries(action: "set-kind", key: "pm-catalog", name: nil, description: nil,
                                               citekey: nil, membership: toTopic))
    }

    /// 主題型不指涉任何東西，create 不必為它讀整份 store（先前每次建 library 都 load）。
    func testCreatingATopicLibraryDoesNotReadTheStore() throws {
        // store.yaml 寫成比本 binary 新的 format：`store.load()` 會擲 tooNew——create topic 不該碰它
        try StoreVersion.write(root: root, format: StoreVersion.supported + 1)
        XCTAssertThrowsError(try LibraryStore(root: root).load(), "前提：load 在這個 marker 下會失敗")
        XCTAssertNoThrow(try create("reading", .init(kind: "topic")))
    }
}
