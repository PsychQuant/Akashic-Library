import XCTest
import Foundation
@testable import AkashicCore
@testable import AkashicStoreIO

/// #642 的 store 層：registry 的改寫路徑、跨記錄 warning（既有的錯誤看得見）、以及規則指涉的 work／venue
/// 在改名與合併時不得安靜懸空（`entity-backlink-completeness` 第 16 條邊）。
final class LibraryMembershipStoreTests: XCTestCase {
    var root: URL!
    var store: LibraryStore!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("akashic-lms-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("entities"), withIntermediateDirectories: true)
        try StoreVersion.write(root: root, format: StoreVersion.supported)
        GitFixture.initRepo(root)
        store = LibraryStore(root: root)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    private func venue(_ key: String) -> Venue {
        Venue(key: key, type: .periodical, names: Timeline([TemporalValue(value: key)]))
    }
    private func work(_ ck: String, venues: [VenueRef] = [], libraries: [String] = [], cites: [String] = []) -> Entry {
        var e = Entry(id: UUID(), citekey: ck, type: .periodicalArticle, title: ck, venues: venues)
        e.akashic.libraries = libraries
        e.akashic.relations.cites = cites
        return e
    }

    // MARK: - 改寫路徑

    func testUpdateLibraryRewritesAnExistingRegistryFileOnly() throws {
        try store.writeLibrary(Library(key: "pm", name: "PM"))
        let rule = LibraryMembership.rule(LibraryRule(venue: "psychological-methods"))
        try store.updateLibrary(Library(key: "pm", name: "PM", membership: rule))
        XCTAssertEqual(try store.load().libraries.first?.membership, rule)
        XCTAssertThrowsError(try store.updateLibrary(Library(key: "ghost", name: "G", membership: .topic)),
                             "改寫路徑不得順便建檔——建檔走 writeLibrary 的 exclusive create")
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.libraryURL(key: "ghost").path))
    }

    // MARK: - validate／doctor 看得見既有的錯誤

    func testCrossRecordWarnsOnNonconformingMembersAndNamesThem() throws {
        try store.writeVenue(venue("pm"))
        try store.writeLibrary(Library(key: "pm-catalog", name: "PM", membership: .rule(LibraryRule(venue: "pm"))))
        try store.writeEntry(work("good2020a", venues: [.key("pm")], libraries: ["pm-catalog"]))
        try store.writeEntry(work("stray2020a", libraries: ["pm-catalog"]))
        try store.writeEntry(work("outside2020a"))   // 不是成員——規則不管非成員（目錄完整性不在本檢查）
        let issues = try store.load().crossRecordIssues().filter { $0.message.contains("pm-catalog") }
        XCTAssertEqual(issues.count, 1, "\(issues.map(\.message))")
        let m = issues[0].message
        XCTAssertEqual(issues[0].severity, .warning)
        XCTAssertTrue(m.contains("1 筆") && m.contains("stray2020a"), m)
        XCTAssertFalse(m.contains("good2020a") || m.contains("outside2020a"), m)
        XCTAssertTrue(m.contains("library check"), "要指路到能列出全部的面：\(m)")
    }

    func testCrossRecordWarnsWhenTheRuleVenueOrTheDocumentIsNotInTheStore() throws {
        try store.writeLibrary(Library(key: "pm-catalog", name: "PM", membership: .rule(LibraryRule(venue: "ghost-venue"))))
        try store.writeLibrary(Library(key: "paper", name: "P", membership: .document(citekey: "draft2026a")))
        let messages = try store.load().crossRecordIssues().map(\.message)
        XCTAssertTrue(messages.contains { $0.contains("pm-catalog") && $0.contains("ghost-venue") }, "\(messages)")
        XCTAssertTrue(messages.contains { $0.contains("paper") && $0.contains("draft2026a") }, "\(messages)")
    }

    func testTopicAndConformingLibrariesAreSilent() throws {
        try store.writeVenue(venue("pm"))
        try store.writeLibrary(Library(key: "pm-catalog", name: "PM", membership: .rule(LibraryRule(venue: "pm"))))
        try store.writeLibrary(Library(key: "reading", name: "R", membership: .topic))
        try store.writeEntry(work("good2020a", venues: [.key("pm")], libraries: ["pm-catalog", "reading"]))
        try store.writeEntry(work("any2020a", libraries: ["reading"]))
        let messages = try store.load().crossRecordIssues().map(\.message)
        XCTAssertFalse(messages.contains { $0.contains("pm-catalog") || $0.contains("reading") }, "\(messages)")
    }

    /// 排除清單指向不在庫的 citekey：排除對不到任何 work（打錯、或那筆已刪除）——validate 要看得見。
    func testCrossRecordWarnsWhenTheExcludedListPointsAtAWorkThatIsNotInTheStore() throws {
        try store.writeVenue(venue("pm"))
        try store.writeLibrary(Library(key: "pm-catalog", name: "PM",
                                       membership: .rule(LibraryRule(venue: "pm", excluded: ["appendix2020b", "here2020a"]))))
        try store.writeEntry(work("here2020a"))
        let messages = try store.load().crossRecordIssues().filter { $0.message.contains("pm-catalog") }
        XCTAssertEqual(messages.count, 1, "\(messages.map(\.message))")
        XCTAssertEqual(messages[0].severity, .warning)
        XCTAssertTrue(messages[0].message.contains("appendix2020b") && !messages[0].message.contains("here2020a"), messages[0].message)
        XCTAssertTrue(messages[0].message.contains("排除清單"), messages[0].message)
    }

    /// 規則的 venue key 有不只一筆記錄：依據不明確——說一次，不逐筆重報；零成員的 library 也看得到。
    func testCrossRecordSaysOnceThatTheRuleVenueIsAmbiguous() throws {
        try store.writeVenue(venue("pm"))
        try store.writeVenue(venue("pm"))
        try store.writeLibrary(Library(key: "pm-catalog", name: "PM", membership: .rule(LibraryRule(venue: "pm"))))
        let empty = try store.load().crossRecordIssues().filter { $0.message.contains("pm-catalog") }
        XCTAssertEqual(empty.count, 1, "零成員也要說：\(empty.map(\.message))")
        XCTAssertTrue(empty[0].message.contains("依據不明確") && empty[0].message.contains("不只一筆"), empty[0].message)
        try store.writeEntry(work("a2020a", venues: [.key("pm")], libraries: ["pm-catalog"]))
        try store.writeEntry(work("b2020a", venues: [.key("pm")], libraries: ["pm-catalog"]))
        let withMembers = try store.load().crossRecordIssues().filter { $0.message.contains("pm-catalog") }
        XCTAssertEqual(withMembers.count, 1, "成員再多也只說一次：\(withMembers.map(\.message))")
    }

    /// MCP doctor 把每則跨記錄訊息截在 300 字：指路句放在前段，點名 ≥3 筆時也不會被切掉。
    func testThePointerToLibraryCheckSurvivesAThreeHundredCharacterClip() throws {
        try store.writeVenue(venue("psychological-methods"))
        try store.writeLibrary(Library(key: "psychological-methods-catalog", name: "PM", membership: .rule(LibraryRule(
            venue: "psychological-methods", types: [.periodicalArticle], excluded: (0..<12).map { "excluded-work-\($0)-2020" },
            source: "openalex:S45419345"))))
        for i in 0..<6 { try store.writeEntry(work("stray\(i)2020a", libraries: ["psychological-methods-catalog"])) }
        for i in 0..<12 { try store.writeEntry(work("excluded-work-\(i)-2020")) }
        let m = try XCTUnwrap(try store.load().crossRecordIssues().first { $0.message.contains("成員不符規則") }).message
        let clipped = String(m.prefix(300))
        XCTAssertTrue(clipped.contains("akashic library check psychological-methods-catalog"), "指路句在前 300 字內：\(clipped)")
        XCTAssertTrue(clipped.contains("akashic_libraries action check"), clipped)
        XCTAssertTrue(m.contains("6 筆"), m)
    }

    // MARK: - 規則指涉的鍵：改名同批遷移，合併拒絕並給出做得到的出路

    /// 使用者看到的訊息（`errorDescription`），不是 enum 的傾印。
    private func shown(_ error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? String(describing: error)
    }

    private func registryText(_ key: String) throws -> String {
        try String(contentsOf: store.libraryURL(key: key), encoding: .utf8)
    }

    /// 改名不改身分，規則是 library 的屬性（第 16 條邊）——遷移它，不是拒絕它。文件型的文件與規則型的排除清單各走一遍。
    func testRenameMigratesTheDocumentAndTheExcludedCitekeyInTheSameBatch() throws {
        try store.writeVenue(venue("pm"))
        try store.writeEntry(work("draft2026a", cites: ["pm2020a"]))
        try store.writeEntry(work("ruled2020a", venues: [.key("pm")]))   // 被排除的那筆不是成員
        try store.writeEntry(work("pm2020a", venues: [.key("pm")], libraries: ["pm-catalog", "paper"]))
        try store.writeLibrary(Library(key: "paper", name: "P", membership: .document(citekey: "draft2026a")))
        try store.writeLibrary(Library(key: "pm-catalog", name: "PM",
                                       membership: .rule(LibraryRule(venue: "pm", types: [.periodicalArticle],
                                                                     excluded: ["other2020a", "ruled2020a"], source: "openalex:S1"))))
        try store.writeEntry(work("other2020a"))
        GitFixture.commitAll(root, message: "seed")

        let doc = try store.renameEntry(from: "draft2026a", to: "draft2026final")
        XCTAssertEqual(doc.libraryRulesRewritten, [LibraryRuleRewrite(library: "paper", role: .document,
                                                                     from: "draft2026a", to: "draft2026final")])
        XCTAssertEqual(try store.load().libraries.first { $0.key == "paper" }?.membership,
                       .document(citekey: "draft2026final"))

        GitFixture.commitAll(root, message: "after first rename")
        let ex = try store.renameEntry(from: "ruled2020a", to: "ruled2020b")
        XCTAssertEqual(ex.libraryRulesRewritten.map(\.describedSafely), ["library「pm-catalog」的排除：ruled2020a → ruled2020b"])
        let rule = try XCTUnwrap(try store.load().libraries.first { $0.key == "pm-catalog" }?.membership)
        XCTAssertEqual(rule, .rule(LibraryRule(venue: "pm", types: [.periodicalArticle],
                                               excluded: ["other2020a", "ruled2020b"], source: "openalex:S1")),
                       "位置、type、來歷都不動，只換那一個 citekey")
        // 遷移完整：沒有任何 library 警告（既有成員仍符合、排除沒有懸空）
        let messages = try store.load().crossRecordIssues().map(\.message)
        XCTAssertFalse(messages.contains { $0.contains("paper") || $0.contains("pm-catalog") }, "\(messages)")
    }

    /// 新 citekey 已被某條規則指涉（懸空的排除或文件）→ 拒絕：否則改名之後那條規則會「復活」成指向另一筆 work。零寫入。
    func testRenameRefusesWhenTheNewCitekeyIsAlreadyNamedByARule() throws {
        try store.writeEntry(work("old2020a"))
        try store.writeLibrary(Library(key: "pm-catalog", name: "PM",
                                       membership: .rule(LibraryRule(venue: "pm", excluded: ["ghost2020a"]))))
        try store.writeLibrary(Library(key: "paper", name: "P", membership: .document(citekey: "ghostdoc2026")))
        GitFixture.commitAll(root, message: "seed")
        let before = try registryText("pm-catalog")
        for new in ["ghost2020a", "ghostdoc2026"] {
            XCTAssertThrowsError(try store.renameEntry(from: "old2020a", to: new)) { error in
                let m = String(describing: error)
                XCTAssertTrue(m.contains(new == "ghost2020a" ? "pm-catalog" : "paper"), m)
                XCTAssertTrue(m.contains("set-kind") && m.contains("library check"), m)
            }
        }
        XCTAssertEqual(try store.load().entries.map(\.citekey), ["old2020a"], "拒絕＝零寫入")
        XCTAssertEqual(try registryText("pm-catalog"), before)
    }

    /// registry 檔要遷移時，舊值只剩 git 那一份：未 commit（untracked／有修改）或 store 不在 git 裡都拒絕，零寫入。
    func testRenameRefusesWhenTheRegistryFileIsNotRecoverable() throws {
        try store.writeEntry(work("draft2026a"))
        try store.writeLibrary(Library(key: "paper", name: "P", membership: .document(citekey: "draft2026a")))
        // (1) 剛建、還沒 commit（untracked）
        XCTAssertThrowsError(try store.renameEntry(from: "draft2026a", to: "draft2026b")) { error in
            let m = String(describing: error)
            XCTAssertTrue(m.contains("paper") && m.contains("git"), m)
        }
        XCTAssertEqual(try store.load().entries.map(\.citekey), ["draft2026a"], "拒絕＝零寫入")
        // (2) 已 commit 但又被改過（dirty）
        GitFixture.commitAll(root, message: "seed")
        var text = try registryText("paper")
        text += "# 手改\n"
        try text.write(to: store.libraryURL(key: "paper"), atomically: true, encoding: .utf8)
        XCTAssertThrowsError(try store.renameEntry(from: "draft2026a", to: "draft2026b"))
        XCTAssertEqual(try store.load().entries.map(\.citekey), ["draft2026a"])
        // (3) commit 之後放行
        GitFixture.commitAll(root, message: "clean")
        XCTAssertNoThrow(try store.renameEntry(from: "draft2026a", to: "draft2026b"))
        // (4) 不在 git 工作樹裡
        let bare = FileManager.default.temporaryDirectory.appendingPathComponent("akashic-lms-nogit-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: bare) }
        try FileManager.default.createDirectory(at: bare.appendingPathComponent("entities"), withIntermediateDirectories: true)
        try StoreVersion.write(root: bare, format: StoreVersion.supported)
        let bareStore = LibraryStore(root: bare)
        try bareStore.writeEntry(work("draft2026a"))
        try bareStore.writeLibrary(Library(key: "paper", name: "P", membership: .document(citekey: "draft2026a")))
        XCTAssertThrowsError(try bareStore.renameEntry(from: "draft2026a", to: "draft2026b")) {
            XCTAssertTrue(String(describing: $0).contains("git 工作樹"), "\($0)")
        }
    }

    /// 不指涉這個 citekey 的規則不受影響：改名不要求 registry 檔已 commit，也不動它。
    func testRenameOfAnUnrelatedCitekeyNeedsNoGitAndLeavesRegistryAlone() throws {
        try store.writeEntry(work("a2020a"))
        try store.writeEntry(work("b2020a"))
        try store.writeLibrary(Library(key: "pm-catalog", name: "PM",
                                       membership: .rule(LibraryRule(venue: "pm", excluded: ["b2020a"]))))   // 未 commit
        let report = try store.renameEntry(from: "a2020a", to: "a2020b")
        XCTAssertTrue(report.libraryRulesRewritten.isEmpty)
        XCTAssertEqual(try store.load().libraries.first?.membership,
                       .rule(LibraryRule(venue: "pm", excluded: ["b2020a"])))
    }

    /// 同一批預檢：registry 檔的寫入前置條件（format 閘）過不了，work 也不能先改名——不撕裂。
    func testRenameTearsNothingWhenTheRegistryPreflightFails() throws {
        try store.writeEntry(work("draft2026a"))
        try store.writeLibrary(Library(key: "paper", name: "P", membership: .document(citekey: "draft2026a")))
        GitFixture.commitAll(root, message: "seed")
        try StoreVersion.write(root: root, format: LibraryMembership.requiredStoreFormat - 1)   // 手改 marker：規則型／文件型不可寫
        XCTAssertThrowsError(try store.renameEntry(from: "draft2026a", to: "draft2026b")) {
            XCTAssertTrue(String(describing: $0).contains("store format"), "\($0)")
        }
        XCTAssertEqual(try store.load().entries.map(\.citekey), ["draft2026a"], "work 也不能先改名")
        XCTAssertEqual(try store.load().libraries.first?.membership, .document(citekey: "draft2026a"))
    }

    /// 被隔離的 registry 檔（membership 形狀不合法）讀不出它的規則——提到這個 citekey 時拒絕並說出哪個檔；
    /// 不相干的改名不受影響（不會被一個壞檔永久卡住）。
    func testRenameRefusesWhenAQuarantinedRegistryFileMentionsTheCitekey() throws {
        try store.writeEntry(work("ruled2020a"))
        try store.writeEntry(work("free2020a"))
        let bad = "key: broken\nname: B\nmembership:\n  kind: catalog\n  excluded:\n  - ruled2020a\n"
        try FileManager.default.createDirectory(at: store.librariesDir, withIntermediateDirectories: true)
        try bad.write(to: store.libraryURL(key: "broken"), atomically: true, encoding: .utf8)
        XCTAssertEqual(try store.load().quarantined.map(\.file), ["libraries/broken.yaml"])
        XCTAssertThrowsError(try store.renameEntry(from: "ruled2020a", to: "ruled2020b")) { error in
            let m = String(describing: error)
            XCTAssertTrue(m.contains("libraries/broken.yaml") && m.contains("quarantine"), m)
        }
        XCTAssertNoThrow(try store.renameEntry(from: "free2020a", to: "free2020b"), "不提到那個鍵的改名不該被一個壞檔卡住")
    }

    func testAKeyTokenIsNotASubstring() {
        XCTAssertTrue(LibraryStore.containsKeyToken("excluded:\n- ruled2020a\n", "ruled2020a"))
        XCTAssertTrue(LibraryStore.containsKeyToken("document: ruled2020a", "ruled2020a"))
        XCTAssertFalse(LibraryStore.containsKeyToken("venue: ppm-catalog", "pm"), "前後是 StoreKey 字元就不算提到")
        XCTAssertFalse(LibraryStore.containsKeyToken("venue: pm-x", "pm"))
        XCTAssertTrue(LibraryStore.containsKeyToken("venue: 'pm'", "pm"))
    }

    func testWorkMergeRefusesWhenTheDoomedWorkIsNamedByALibraryRule() throws {
        try store.writeEntry(work("draft2026a"))
        try store.writeEntry(work("draft2026b"))
        try store.writeLibrary(Library(key: "paper", name: "P", membership: .document(citekey: "draft2026b")))
        let d = Divergence(id: UUID(), question: "同一份稿？",
                           candidates: [DivergenceCandidate(key: "draft2026a", shape: .work),
                                        DivergenceCandidate(key: "draft2026b", shape: .work)])
        try store.writeDivergence(d)
        GitFixture.commitAll(root, message: "seed")
        for attempt in [{ _ = try self.store.previewResolveDivergence(id: d.id, survivor: "draft2026a", overrideReason: nil) },
                        { _ = try self.store.resolveDivergence(id: d.id, survivor: "draft2026a") }] {
            XCTAssertThrowsError(try attempt()) { error in
                let m = shown(error)
                XCTAssertTrue(m.contains("paper") && m.contains("draft2026b"), m)
                // 出路要做得到：一行可直接照做的命令（指向倖存者），不經過 topic
                XCTAssertTrue(m.contains("akashic library set-kind paper --kind document --document draft2026a"), m)
                XCTAssertTrue(m.contains("不經過 topic"), m)
            }
        }
        XCTAssertEqual(try store.load().entries.count, 2, "拒絕＝零寫入")
    }

    func testVenueMergeRefusesWhenTheDoomedVenueIsARuleVenue() throws {
        try store.writeVenue(venue("pm"))
        try store.writeVenue(venue("pm-dup"))
        try store.writeLibrary(Library(key: "pm-catalog", name: "PM", membership: .rule(LibraryRule(venue: "pm-dup"))))
        let d = Divergence(id: UUID(), question: "同一本刊？",
                           candidates: [DivergenceCandidate(key: "pm", shape: .venue),
                                        DivergenceCandidate(key: "pm-dup", shape: .venue)])
        try store.writeDivergence(d)
        GitFixture.commitAll(root, message: "seed")
        XCTAssertThrowsError(try store.resolveDivergence(id: d.id, survivor: "pm")) { error in
            let m = shown(error)
            XCTAssertTrue(m.contains("pm-catalog") && m.contains("pm-dup"), m)
            XCTAssertTrue(m.contains("akashic library set-kind pm-catalog --kind rule --venue pm"), "指向倖存者的完整命令：\(m)")
        }
        XCTAssertEqual(try store.load().venues.count, 2, "拒絕＝零寫入")
    }

    /// 排除清單的出路：被併者換成倖存者（倖存者已在清單裡就直接拿掉被併者），type 與來歷不丟。
    func testWorkMergeExitForAnExcludedCitekeyKeepsTheRestOfTheRule() throws {
        try store.writeEntry(work("keep2020a"))
        try store.writeEntry(work("doom2020a"))
        try store.writeLibrary(Library(key: "pm-catalog", name: "PM", membership: .rule(LibraryRule(
            venue: "pm", types: [.periodicalArticle, .book], excluded: ["doom2020a", "z2020a"], source: "openalex:S1"))))
        let d = Divergence(id: UUID(), question: "同一篇？",
                           candidates: [DivergenceCandidate(key: "keep2020a", shape: .work),
                                        DivergenceCandidate(key: "doom2020a", shape: .work)])
        try store.writeDivergence(d)
        GitFixture.commitAll(root, message: "seed")
        XCTAssertThrowsError(try store.previewResolveDivergence(id: d.id, survivor: "keep2020a", overrideReason: nil)) { error in
            let m = shown(error)
            XCTAssertTrue(m.contains("akashic library set-kind pm-catalog --kind rule --venue pm --type periodical-article --type book"
                                     + " --exclude z2020a --exclude keep2020a"), m)
            XCTAssertTrue(m.contains("--source <來歷"), "來歷是自由文字，不內嵌、指路 library check：\(m)")
        }
    }

    /// 被隔離的 registry 檔提到被併的鍵：合併本來就拒絕（`DivergenceResolveError.quarantinedPresent`：對 quarantined 檔做位元組比對，
    /// 不分目錄，#295）——#642 R1 verify 的第 45 則說「合併守衛 fail-open」對合併不成立，只有改名缺這一半（上面那支已補）。
    /// 這支釘住合併這一側的既有行為，不讓它日後被目錄前綴過濾悄悄放行。
    func testMergeRefusesWhenAQuarantinedRegistryFileMentionsTheDoomedKey() throws {
        try store.writeVenue(venue("pm"))
        try store.writeVenue(venue("pm-dup"))
        try FileManager.default.createDirectory(at: store.librariesDir, withIntermediateDirectories: true)
        try "key: broken\nname: B\nmembership:\n  kind: catalog\n  venue: pm-dup\n"
            .write(to: store.libraryURL(key: "broken"), atomically: true, encoding: .utf8)
        let d = Divergence(id: UUID(), question: "同一本刊？",
                           candidates: [DivergenceCandidate(key: "pm", shape: .venue),
                                        DivergenceCandidate(key: "pm-dup", shape: .venue)])
        try store.writeDivergence(d)
        GitFixture.commitAll(root, message: "seed")
        XCTAssertThrowsError(try store.resolveDivergence(id: d.id, survivor: "pm")) { error in
            let m = shown(error)
            XCTAssertTrue(m.contains("libraries/broken.yaml"), m)
        }
        XCTAssertEqual(try store.load().venues.count, 2, "拒絕＝零寫入")
    }

    /// 反方向：倖存者就是規則的 venue → 規則仍指著活下來的那筆，放行。
    func testVenueMergeKeepingTheRuleVenueProceeds() throws {
        try store.writeVenue(venue("pm"))
        try store.writeVenue(venue("pm-dup"))
        try store.writeLibrary(Library(key: "pm-catalog", name: "PM", membership: .rule(LibraryRule(venue: "pm"))))
        let d = Divergence(id: UUID(), question: "同一本刊？",
                           candidates: [DivergenceCandidate(key: "pm", shape: .venue),
                                        DivergenceCandidate(key: "pm-dup", shape: .venue)])
        try store.writeDivergence(d)
        GitFixture.commitAll(root, message: "seed")
        _ = try store.resolveDivergence(id: d.id, survivor: "pm")
        XCTAssertEqual(try store.load().venues.map(\.key), ["pm"])
    }
}
