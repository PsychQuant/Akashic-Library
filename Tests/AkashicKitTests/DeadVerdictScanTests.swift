import Foundation
import XCTest
@testable import AkashicCore
@testable import AkashicStoreIO

/// #464：死 verdict 掃描——resolution verdict 的 value 指向沒有載入的 holder。
/// 家族的三個結構缺口（#232 person rename／#271 person merge／#460 venue）至今零守衛；#460 那一次
/// 的三個場外機制（#456 pilot 人肉 205 條、verify lens 掃出殘留 1 條、set-difference 腳本驗清理）。
/// 掃描住在 `StoreHealth`——CLI `validate` 逐行可見、MCP `doctor` 進 `recordIssues`；App 面未渲染
/// per-record warning（#487）。釘住：注入死引用 → warning；乾淨 store → 零；三種 holderKind 各自對到
/// 自己的集合（正向與錯集合碰撞）；被 quarantine 的 holder（work／person／org 三種）說「被 quarantine」
/// 而不是「不存在」；malformed value 對已載入記錄不可達（三族都在 decode 期 quarantine，第 8 列的形狀）；
/// `ProvenanceCarrying` 的 conformer 集合被源碼掃描釘住，第五個出現時測試會紅。
final class DeadVerdictScanTests: XCTestCase {
    private var root: URL!
    private var store: LibraryStore!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("akashic-dvs-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("entities"), withIntermediateDirectories: true)
        GitFixture.initRepo(root)
        try StoreVersion.write(root: root, format: StoreVersion.supported)
        store = LibraryStore(root: root)
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    private func verdict(_ field: String, kind: ProvenanceReference.VerdictHolderKind,
                         holder: String, literal: String) -> ProvenanceReference {
        ProvenanceReference(
            field: field,
            value: ProvenanceReference.VerdictPairingValue(
                holderKind: kind, holder: holder, literal: literal).encoded,
            kind: .judgement(statement: "測試用判定", restsOn: []))
    }

    private func entry(_ citekey: String) throws {
        try store.writeEntry(Entry(id: UUID(), citekey: citekey, type: .periodicalArticle,
                                   title: "T \(citekey)", authors: [.literal("A B")],
                                   date: "2020"))
    }

    private func deadVerdicts(_ health: StoreHealth) -> [StoreHealth.OwnedIssue] {
        health.deadVerdicts
    }

    /// 乾淨 store：verdict 的 holder 都活著 → 零 warning。
    func testLiveHoldersProduceNoWarning() throws {
        try entry("alive2020a")
        var p = Person(key: "some-author", names: PersonNames(variant: ["Some Author"]))
        p.references = [verdict("resolution-confirmed", kind: .work, holder: "alive2020a", literal: "Some Author")]
        try store.writePerson(p)
        let health = store.health(from: try store.load())
        XCTAssertTrue(deadVerdicts(health).isEmpty, "\(deadVerdicts(health).map(\.issue.message))")
    }

    /// person 上 `work:` holder 指向不存在的 citekey → warning，owner／kind 指得出是哪筆。
    func testDeadWorkHolderOnPersonIsAWarning() throws {
        try entry("alive2020a")
        var p = Person(key: "some-author", names: PersonNames(variant: ["Some Author"]))
        p.references = [verdict("resolution-confirmed", kind: .work, holder: "alive2020a", literal: "Some Author"),
                        verdict("resolution-rejected", kind: .work, holder: "gone2019a", literal: "Some Author")]
        try store.writePerson(p)
        let dead = deadVerdicts(store.health(from: try store.load()))
        XCTAssertEqual(dead.count, 1, "\(dead.map(\.issue.message))")
        XCTAssertEqual(dead.first?.owner, "some-author")
        XCTAssertEqual(dead.first?.kind, "person")
        XCTAssertEqual(dead.first?.issue.severity, .warning, "過期不是矛盾——warning，不進 hasFindings")
        XCTAssertTrue(dead.first?.issue.message.contains("work:gone2019a") ?? false)
        XCTAssertTrue(dead.first?.issue.message.contains("沒有任何檔宣稱它") ?? false, "真的不存在 → 說不存在")
        XCTAssertTrue(dead.first?.issue.message.hasPrefix(StoreHealth.deadVerdictPrefix) ?? false)
        XCTAssertTrue(dead.first?.issue.message.contains("更新或刪掉") ?? false, "訊息要給處置")
        XCTAssertFalse(store.health(from: try store.load()).hasFindings, "warning 級不得把 hasFindings 拉成真")
    }

    /// venue 上的 `work:` holder（#460 家族的 venue 側）同樣被掃到。
    func testDeadWorkHolderOnVenueIsAWarning() throws {
        var v = Venue(key: "some-journal", type: .periodical,
                      names: TimelineOf([TemporalValue(value: "Some Journal")]))
        v.references = [verdict("resolution-confirmed", kind: .work, holder: "gone2019a", literal: "SOME JOURNAL")]
        _ = try store.writeVenue(v)
        let dead = deadVerdicts(store.health(from: try store.load()))
        XCTAssertEqual(dead.map(\.kind), ["venue"], "\(dead.map(\.issue.message))")
        XCTAssertEqual(dead.first?.owner, "some-journal")
    }

    /// `person:`／`org:` holder 各自對到自己的集合——一個活著的 citekey 不能替一個死掉的 person key 頂替。
    func testPersonAndOrgHoldersUseTheirOwnKeySets() throws {
        try entry("some-author")   // 同名 citekey 存在，但它不是 person key
        var o = Organization(key: "some-org", names: TimelineOf([TemporalValue(value: "Some Org")]))
        o.references = [verdict("resolution-confirmed", kind: .person, holder: "some-author", literal: "Some Org"),
                        verdict("resolution-confirmed", kind: .org, holder: "parent-org", literal: "Parent")]
        try store.writeOrganization(o)
        let dead = deadVerdicts(store.health(from: try store.load()))
        XCTAssertEqual(dead.count, 2, "person:some-author 與 org:parent-org 都不存在：\(dead.map(\.issue.message))")
        XCTAssertTrue(dead.allSatisfy { $0.kind == "organization" && $0.owner == "some-org" })
    }

    // MARK: - 三個集合各自對到自己的 kind（正向 ＋ 錯集合碰撞矩陣）

    /// organization 上的 `person:`／`org:` holder **活著**時零 warning——前一版只有死的案例，
    /// 一個把三個集合接錯的實作照樣過（Codex R1）。
    func testAlivePersonAndOrgHoldersOnOrganizationProduceNoWarning() throws {
        try store.writePerson(Person(key: "some-author", names: PersonNames(variant: ["Some Author"])))
        try store.writeOrganization(Organization(key: "parent-org", names: TimelineOf([TemporalValue(value: "Parent")])))
        var o = Organization(key: "some-org", names: TimelineOf([TemporalValue(value: "Some Org")]))
        o.references = [verdict("resolution-confirmed", kind: .person, holder: "some-author", literal: "Some Org"),
                        verdict("resolution-confirmed", kind: .org, holder: "parent-org", literal: "Parent")]
        try store.writeOrganization(o)
        XCTAssertEqual(deadVerdicts(store.health(from: try store.load())).count, 0)
    }

    /// 錯集合碰撞：同一個字串只存在於**另一個** kind 的集合——`org:` holder 的 key 只是 person、
    /// `person:` holder 的 key 只是 organization、`work:` holder 的 key 只是 person——三個都要判死。
    func testAKeyLivingOnlyInAnotherKindsSetIsStillDead() throws {
        try store.writePerson(Person(key: "shared-key", names: PersonNames(variant: ["Shared"])))
        try store.writeOrganization(Organization(key: "org-only", names: TimelineOf([TemporalValue(value: "Org Only")])))
        var o = Organization(key: "some-org", names: TimelineOf([TemporalValue(value: "Some Org")]))
        o.references = [verdict("resolution-confirmed", kind: .org, holder: "shared-key", literal: "A"),      // 只是 person
                        verdict("resolution-confirmed", kind: .person, holder: "org-only", literal: "B")]      // 只是 org
        try store.writeOrganization(o)
        var v = Venue(key: "some-journal", type: .periodical, names: TimelineOf([TemporalValue(value: "J")]))
        v.references = [verdict("resolution-confirmed", kind: .work, holder: "shared-key", literal: "C")]     // 只是 person
        _ = try store.writeVenue(v)
        let dead = deadVerdicts(store.health(from: try store.load()))
        XCTAssertEqual(dead.count, 3, "\(dead.map(\.issue.message))")
        XCTAssertTrue(dead.allSatisfy { $0.issue.message.contains("沒有任何檔宣稱它") })
    }

    // MARK: - 「不在集合」的兩種意思

    /// holder 的檔仍在磁碟但被 quarantine → 訊息說「被 quarantine、先修那個檔」，不說「不存在」。
    func testQuarantinedHolderIsReportedAsQuarantinedNotAbsent() throws {
        // 檔名 UUID 與記錄 id 不符 → 整檔 quarantine（EntitiesLayoutTests 的既有形狀）；citekey 行仍在
        let e = Entry(id: UUID(), citekey: "quar2019a", type: .periodicalArticle,
                      title: "Quarantined", authors: [.literal("A B")], date: "2019")
        try EntryYAML.encode(e).write(
            to: store.entitiesDir.appendingPathComponent("\(UUID().uuidString).yaml"),
            atomically: true, encoding: .utf8)
        var p = Person(key: "some-author", names: PersonNames(variant: ["Some Author"]))
        p.references = [verdict("resolution-confirmed", kind: .work, holder: "quar2019a", literal: "Some Author")]
        try store.writePerson(p)
        let load = try store.load()
        XCTAssertEqual(load.quarantined.count, 1)
        let dead = deadVerdicts(store.health(from: load))
        XCTAssertEqual(dead.count, 1, "\(dead.map(\.issue.message))")
        XCTAssertTrue(dead[0].issue.message.contains("被 quarantine"), dead[0].issue.message)
        XCTAssertTrue(dead[0].issue.message.contains(load.quarantined[0].file), dead[0].issue.message)
        XCTAssertFalse(dead[0].issue.message.contains("沒有任何檔宣稱它"))
    }

    /// `person:` 與 `org:` holder 的檔被 quarantine 時同樣分辨得出——這兩條走新加的 org key 查詢與
    /// 既有的 person key 查詢（Codex R2：前一版只走 work 路徑）。
    func testQuarantinedPersonAndOrgHoldersAreReportedAsQuarantined() throws {
        // person 檔：檔名 UUID 與記錄 id 不符 → quarantine；`person:` 標頭與 `key:` 行仍在
        try PersonYAML.encode(Person(key: "quar-person", names: PersonNames(variant: ["Quar Person"]))).write(
            to: store.entitiesDir.appendingPathComponent("\(UUID().uuidString).yaml"),
            atomically: true, encoding: .utf8)
        try OrganizationYAML.encode(Organization(key: "quar-org", names: TimelineOf([TemporalValue(value: "Quar Org")]))).write(
            to: store.entitiesDir.appendingPathComponent("\(UUID().uuidString).yaml"),
            atomically: true, encoding: .utf8)
        var o = Organization(key: "some-org", names: TimelineOf([TemporalValue(value: "Some Org")]))
        o.references = [verdict("resolution-confirmed", kind: .person, holder: "quar-person", literal: "P"),
                        verdict("resolution-confirmed", kind: .org, holder: "quar-org", literal: "O")]
        try store.writeOrganization(o)
        let load = try store.load()
        XCTAssertEqual(load.quarantined.count, 2)
        let dead = deadVerdicts(store.health(from: load))
        XCTAssertEqual(dead.count, 2, "\(dead.map(\.issue.message))")
        XCTAssertTrue(dead.allSatisfy { $0.issue.message.contains("被 quarantine") }, "\(dead.map(\.issue.message))")
    }

    /// 縮排的同名鍵不算標頭：一個被 quarantine 的**別種**檔即使內文有縮排的 `organization:`，也不會被當成
    /// 宣稱者（Codex R2 指出的假陽性路徑）。
    func testIndentedMarkerInAnotherQuarantinedFileDoesNotClaimTheOrgKey() throws {
        let text = "entry:\n  organization:\n    nested: true\nkey: some-org\ncitekey: BAD KEY\n"
        try text.write(to: store.entitiesDir.appendingPathComponent("\(UUID().uuidString).yaml"),
                       atomically: true, encoding: .utf8)
        var v = Venue(key: "some-journal", type: .periodical, names: TimelineOf([TemporalValue(value: "J")]))
        v.references = [verdict("resolution-confirmed", kind: .org, holder: "some-org", literal: "O")]
        _ = try store.writeVenue(v)
        let load = try store.load()
        XCTAssertEqual(load.quarantined.count, 1)
        let dead = deadVerdicts(store.health(from: load))
        XCTAssertEqual(dead.count, 1)
        XCTAssertTrue(dead[0].issue.message.contains("沒有任何檔宣稱它"), dead[0].issue.message)
    }

    /// 頂層標頭的判準：第 0 欄開始、其後只剩水平空白；縮排不算（Codex R3）。換行與 BOM 由 `rawLines` 處理。
    func testTopLevelMarkerLineTolerantToTrailingSpaceButNotIndent() {
        XCTAssertTrue(LibraryStore.isTopLevelMarkerLine("organization:", marker: "organization:"))
        XCTAssertTrue(LibraryStore.isTopLevelMarkerLine("organization: \t", marker: "organization:"))
        XCTAssertFalse(LibraryStore.isTopLevelMarkerLine("  organization:", marker: "organization:"))
        XCTAssertFalse(LibraryStore.isTopLevelMarkerLine("organization: x", marker: "organization:"))
        XCTAssertFalse(LibraryStore.isTopLevelMarkerLine("organizations:", marker: "organization:"))
    }

    /// `rawLines`：三種換行都切（`\n`／`\r\n`／單獨 `\r`——Codex R4：classic Mac 的 CR 是合法 YAML 換行）；
    /// 檔首 BOM 剝一次、行中的 BOM 不剝（它不是每行的標記，Codex R4）。
    func testRawLinesSplitsAllThreeLineBreaksAndStripsOnlyTheLeadingBOM() {
        XCTAssertEqual(LibraryStore.rawLines("a\nb\r\nc\rd").map(String.init), ["a", "b", "c", "d"])
        XCTAssertEqual(LibraryStore.rawLines("\u{FEFF}organization:\r\nkey: x\r\n").map(String.init), ["organization:", "key: x", ""])
        XCTAssertEqual(LibraryStore.rawLines("a\n\u{FEFF}organization:").map(String.init), ["a", "\u{FEFF}organization:"])
        XCTAssertFalse(LibraryStore.isTopLevelMarkerLine("\u{FEFF}organization:", marker: "organization:"), "行中的 BOM 不是第 0 欄")
    }

    /// 單獨 `\r` 換行（classic Mac）的 quarantined 檔也認得——與 CRLF 同一條路。
    func testQuarantinedOrgFileWithLoneCRIsStillRecognised() throws {
        let yaml = try OrganizationYAML.encode(Organization(key: "quar-org", names: TimelineOf([TemporalValue(value: "Q")])))
        try yaml.replacingOccurrences(of: "\n", with: "\r")
            .write(to: store.entitiesDir.appendingPathComponent("\(UUID().uuidString).yaml"), atomically: true, encoding: .utf8)
        var v = Venue(key: "some-journal", type: .periodical, names: TimelineOf([TemporalValue(value: "J")]))
        v.references = [verdict("resolution-confirmed", kind: .org, holder: "quar-org", literal: "O")]
        _ = try store.writeVenue(v)
        let load = try store.load()
        XCTAssertEqual(load.quarantined.count, 1, "\(load.quarantined)")
        let dead = deadVerdicts(store.health(from: load))
        XCTAssertEqual(dead.count, 1)
        XCTAssertTrue(dead[0].issue.message.contains("被 quarantine"), dead[0].issue.message)
    }

    /// CRLF 與 BOM 的 quarantined 檔仍被認成宣稱者（不會被誤報成「沒有任何檔宣稱」）。
    func testQuarantinedOrgFileWithCRLFAndBOMIsStillRecognised() throws {
        let yaml = try OrganizationYAML.encode(Organization(key: "quar-org", names: TimelineOf([TemporalValue(value: "Q")])))
        let crlf = "\u{FEFF}" + yaml.replacingOccurrences(of: "\n", with: "\r\n")
        try crlf.write(to: store.entitiesDir.appendingPathComponent("\(UUID().uuidString).yaml"),
                       atomically: true, encoding: .utf8)
        var v = Venue(key: "some-journal", type: .periodical, names: TimelineOf([TemporalValue(value: "J")]))
        v.references = [verdict("resolution-confirmed", kind: .org, holder: "quar-org", literal: "O")]
        _ = try store.writeVenue(v)
        let load = try store.load()
        XCTAssertEqual(load.quarantined.count, 1, "\(load.quarantined)")
        let dead = deadVerdicts(store.health(from: load))
        XCTAssertEqual(dead.count, 1)
        XCTAssertTrue(dead[0].issue.message.contains("被 quarantine"), dead[0].issue.message)
    }

    /// 同一個 CRLF 陷阱在 `work:` holder 的路徑（`quarantinedFileClaiming(citekey:)`）也修了。
    func testQuarantinedEntryFileWithCRLFIsStillRecognisedForWorkHolder() throws {
        let e = Entry(id: UUID(), citekey: "quarcrlf2019a", type: .periodicalArticle,
                      title: "Q", authors: [.literal("A B")], date: "2019")
        let crlf = try EntryYAML.encode(e).replacingOccurrences(of: "\n", with: "\r\n")
        try crlf.write(to: store.entitiesDir.appendingPathComponent("\(UUID().uuidString).yaml"),
                       atomically: true, encoding: .utf8)
        var p = Person(key: "some-author", names: PersonNames(variant: ["Some Author"]))
        p.references = [verdict("resolution-confirmed", kind: .work, holder: "quarcrlf2019a", literal: "Some Author")]
        try store.writePerson(p)
        let load = try store.load()
        XCTAssertEqual(load.quarantined.count, 1, "\(load.quarantined)")
        let dead = deadVerdicts(store.health(from: load))
        XCTAssertEqual(dead.count, 1)
        XCTAssertTrue(dead[0].issue.message.contains("被 quarantine"), dead[0].issue.message)
    }

    /// 解析不了的 verdict value 對**已載入**的記錄結構上不可達：載入端把它整檔 quarantine，
    /// 掃描因此看不到它——零不是掃描的功勞，是 load 的（第 8 列的形狀：釘住為什麼是零）。
    func testMalformedVerdictValueIsUnreachableForLoadedRecords() throws {
        var p = Person(key: "some-author", names: PersonNames(variant: ["Some Author"]))
        p.references = [verdict("resolution-confirmed", kind: .work, holder: "alive2020a", literal: "Some Author")]
        try entry("alive2020a")
        let url = try store.writePerson(p)
        let text = try String(contentsOf: url, encoding: .utf8)
        let pairing = ProvenanceReference.VerdictPairingValue(holderKind: .work, holder: "alive2020a", literal: "Some Author").encoded
        XCTAssertTrue(text.contains(pairing))
        try text.replacingOccurrences(of: pairing, with: "nonsense without a separator")
            .write(to: url, atomically: true, encoding: .utf8)
        let load = try store.load()
        XCTAssertEqual(load.people.count, 0, "malformed verdict 讓整檔進 quarantine")
        XCTAssertEqual(load.quarantined.count, 1)
        XCTAssertTrue(load.quarantined[0].reason.contains("resolution-confirmed"), load.quarantined[0].reason)
        XCTAssertEqual(deadVerdicts(store.health(from: load)).count, 0)
    }

    /// 同一件事對 organization 與 venue 兩族也成立（Codex R2：前一版只釘 person）。
    func testMalformedVerdictValueIsUnreachableForLoadedOrganizationsAndVenues() throws {
        try entry("alive2020a")
        let pairing = ProvenanceReference.VerdictPairingValue(holderKind: .work, holder: "alive2020a", literal: "X").encoded
        var o = Organization(key: "some-org", names: TimelineOf([TemporalValue(value: "Some Org")]))
        o.references = [verdict("resolution-confirmed", kind: .work, holder: "alive2020a", literal: "X")]
        let ou = try store.writeOrganization(o)
        var v = Venue(key: "some-journal", type: .periodical, names: TimelineOf([TemporalValue(value: "J")]))
        v.references = [verdict("resolution-rejected", kind: .work, holder: "alive2020a", literal: "X")]
        let vu = try store.writeVenue(v)
        for url in [ou, vu] {
            let text = try String(contentsOf: url, encoding: .utf8)
            XCTAssertTrue(text.contains(pairing))
            try text.replacingOccurrences(of: pairing, with: "nonsense without a separator")
                .write(to: url, atomically: true, encoding: .utf8)
        }
        let load = try store.load()
        XCTAssertEqual(load.organizations.count, 0); XCTAssertEqual(load.venues.count, 0)
        XCTAssertEqual(load.quarantined.count, 2, "\(load.quarantined)")
        XCTAssertEqual(deadVerdicts(store.health(from: load)).count, 0)
    }

    // MARK: - owner 三族是人工列舉——釘住它與 ProvenanceCarrying 的關係

    /// `deadVerdictIssues` 逐一寫 people／organizations／venues。`ProvenanceCarrying` 有四個 conformer，
    /// 而同一個函式（`health(from:)`）已經漏過兩次族（#416 漏 organizations 與 divergences、#394 漏 venue）。
    /// 釘住：每個 conformer 要嘛被掃到，要嘛**結構上帶不了 verdict**（Entry：`validateReferenceAttachment`
    /// 對非識別碼欄位一律 throw，decode 時就拒）。work 側值域一放寬（#443 段記的「目前只收識別碼」），
    /// 本測試的第一個斷言會紅，提醒把 entries 加進掃描。
    func testEveryProvenanceCarrierIsEitherScannedOrCannotCarryAVerdict() throws {
        // 棘輪：conformer 集合由源碼掃描取得——遞迴掃整個 AkashicCore；只看**繼承子句**（型別名（含巢狀）＋
        // 可選泛型參數之後的 `:` 到 `{` 或 `where` 之前），所以 `struct Box<T: ProvenanceCarrying>` 的泛型約束與
        // `extension X where T: ProvenanceCarrying` 都不算（Codex R3／R4）。**它是詞法棘輪，不是編譯器約束**：
        // 註解與字串裡的宣告會誤入、極端排版可能漏掉——常見寫法的第五個 conformer 會讓這裡紅，這是它能承諾的。
        let dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Sources/AkashicCore")
        var files: [URL] = []
        if let it = FileManager.default.enumerator(at: dir, includingPropertiesForKeys: nil) {
            for case let u as URL in it where u.pathExtension == "swift" { files.append(u) }
        }
        XCTAssertGreaterThan(files.count, 5)
        var conformers = Set<String>()
        for f in files {
            let src = try String(contentsOf: f, encoding: .utf8)
            for m in src.matches(of: #/\b(?:extension|struct|final class|class|enum|actor)\s+([\w.]+)\s*(?:<[^>]*>)?\s*:\s*([^{]*?)\{/#) {
                let clause = String(m.2).components(separatedBy: "where").first ?? ""
                if clause.split(separator: ",").map({ $0.trimmingCharacters(in: .whitespacesAndNewlines) }).contains("ProvenanceCarrying") {
                    conformers.insert(String(m.1))
                }
            }
        }
        XCTAssertEqual(conformers, ["Entry", "Person", "Organization", "Venue"],
                       "多了一個 ProvenanceCarrying——決定它要被 deadVerdictIssues 掃、還是像 Entry 一樣帶不了 verdict")
        // 負控：泛型約束與 where 子句不得被算成 conformance（Codex R4 指出的誤入形）
        let probe = "struct Box<T: ProvenanceCarrying> {}\nextension Box where T: ProvenanceCarrying {}\nextension Real.Nested: Foo, ProvenanceCarrying {}\n"
        var found = Set<String>()
        for m in probe.matches(of: #/\b(?:extension|struct|final class|class|enum|actor)\s+([\w.]+)\s*(?:<[^>]*>)?\s*:\s*([^{]*?)\{/#) {
            let clause = String(m.2).components(separatedBy: "where").first ?? ""
            if clause.split(separator: ",").map({ $0.trimmingCharacters(in: .whitespacesAndNewlines) }).contains("ProvenanceCarrying") { found.insert(String(m.1)) }
        }
        XCTAssertEqual(found, ["Real.Nested"])
        var e = Entry(id: UUID(), citekey: "x2020a", type: .periodicalArticle, title: "X")
        e.references = [verdict("resolution-confirmed", kind: .work, holder: "gone2019a", literal: "Y")]
        XCTAssertThrowsError(try e.validateReferenceAttachment(),
                             "Entry 帶不了 verdict——掃描不掃 entries 是因為這裡擋住，不是漏掉") { error in
            guard case StoreYAMLError.invalidField(let field, _)? = error as? StoreYAMLError else {
                return XCTFail("要的是 StoreYAMLError.invalidField，得到 \(error)")
            }
            XCTAssertEqual(field, "entry.references(field: resolution-confirmed)")
        }
        var p = Person(key: "p1", names: PersonNames(variant: ["P One"]))
        p.references = [verdict("resolution-confirmed", kind: .work, holder: "gone2019a", literal: "P")]
        try store.writePerson(p)
        var o = Organization(key: "o1", names: TimelineOf([TemporalValue(value: "O One")]))
        o.references = [verdict("resolution-confirmed", kind: .work, holder: "gone2019a", literal: "O")]
        try store.writeOrganization(o)
        var v = Venue(key: "v1", type: .periodical, names: TimelineOf([TemporalValue(value: "V One")]))
        v.references = [verdict("resolution-confirmed", kind: .work, holder: "gone2019a", literal: "V")]
        _ = try store.writeVenue(v)
        let kinds = deadVerdicts(store.health(from: try store.load())).map(\.kind)
        XCTAssertEqual(kinds, ["person", "organization", "venue"], "三個能帶 verdict 的族都要被掃到，且族序固定")
    }
}
