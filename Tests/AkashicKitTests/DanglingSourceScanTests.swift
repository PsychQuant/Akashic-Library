import Foundation
import XCTest
@testable import AkashicCore
@testable import AkashicStoreIO

/// #453：承重 digest 的完整性檢查盲區。`missingSourceDigests` 先前不掃 venues（#406 起承重證據第一次
/// 住在 venue 記錄上）也不掃 `Entry.references`（#394 的第 15 條邊），而且它零 production 呼叫端——
/// doctor／`StoreHealth` 接的是 `auditSourceIndex()`，只比 blob↔index，捏造的 digest 兩邊都不在、
/// 兩邊一致、doctor 沉默（#251 形狀第三次）。修法：逐 holder 回報 → 以 warning 級 `OwnedIssue` 併入
/// `perRecordIssues`（#464 死 verdict 的同一形），CLI `validate` 逐行、MCP `doctor` 進 `recordIssues`。
///
/// 用詞是「本機缺」不是「偽造」：`sources/` 不進 git，本機分不出「從未存在」與「沒同步」。
final class DanglingSourceScanTests: XCTestCase {
    private var root: URL!
    private var store: LibraryStore!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("akashic-dss-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("entities"), withIntermediateDirectories: true)
        GitFixture.initRepo(root)
        try StoreVersion.write(root: root, format: StoreVersion.supported)
        store = LibraryStore(root: root)
        // `storeSource` 的 fail-closed 閘要求 store 的 .gitignore 排除 sources/（#224）；
        // ensureLayout 寫入那個標記區塊。
        try store.ensureLayout()
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    private func absent(_ byte: String) -> String { "sha256:" + String(repeating: byte, count: 32) }

    private func present(_ text: String) throws -> String {
        try store.storeSource(Data(text.utf8), provenance: LibraryStore.SourceProvenance(
            mediaType: "text/plain", retrieved: "2026-09-03", origin: "unit-test",
            acquisition: "file", note: nil)).digest
    }

    private func retrieval(_ field: String, value: String? = nil, content: String) -> ProvenanceReference {
        ProvenanceReference(field: field, value: value, kind: .retrieval(
            url: "https://example.org/\(field)", retrieved: "2026-09-03", status: 200,
            mediaType: nil, content: content))
    }

    /// 六個 holder 家族各注入一筆本機不存在的 digest：person／organization／venue 的 `references`
    /// （第 11 條邊三形）、divergence 的 `judgement.restsOn`（第 12 條）、entry 的 `akashic.sources`
    /// （#223 記錄側副本）、entry 的 `references`（第 15 條）。每一筆都要有自己的 warning，owner／kind
    /// 指得出是哪筆記錄——「哪一筆記錄的哪個 digest 本機缺」本來就是 per-record 事實。
    func testFabricatedDigestOnEachHolderFamilyIsReported() throws {
        let dPerson = absent("aa"), dOrg = absent("bb"), dVenue = absent("cc")
        let dDiv = absent("dd"), dSources = absent("ee"), dEntryRef = absent("ff")

        var p = Person(key: "chen-h-y", names: PersonNames(variant: ["Chen, H-Y."]))
        p.orcid = ORCID("0000-0003-4038-9439")
        p.references = [retrieval("orcid", content: dPerson)]
        try store.writePerson(p)

        var o = Organization(key: "iss",
                             names: TimelineOf([TemporalValue(value: "Institute of Statistical Science")]))
        o.references = [retrieval("names", value: "Institute of Statistical Science", content: dOrg)]
        try store.writeOrganization(o)

        var v = Venue(key: "psychometrika", type: .periodical,
                      names: TimelineOf([TemporalValue(value: "Psychometrika")]))
        v.references = [retrieval("names", value: "Psychometrika", content: dVenue)]
        try store.writeVenue(v)

        try store.writePerson(Person(key: "p-one", names: ["P"]))
        try store.writePerson(Person(key: "p-two", names: ["P2"]))
        var d = Divergence(id: UUID(), question: "q",
                           candidates: [DivergenceCandidate(key: "p-one", shape: .person),
                                        DivergenceCandidate(key: "p-two", shape: .person)])
        d.judgement = Judgement(statement: "s", restsOn: [dDiv])
        try store.writeDivergence(d)

        var e = Entry(id: UUID(), citekey: "a2020b", type: .periodicalArticle, title: "T",
                      doi: [try XCTUnwrap(DOI("10.1000/x"))])
        e.akashic.sources = [dSources]
        e.references = [retrieval("doi", value: "10.1000/x", content: dEntryRef)]
        try store.writeEntry(e)

        let load = try store.load()
        XCTAssertEqual(load.quarantined.count, 0, "缺席 digest 不阻擋載入（#223 的既有契約）")

        let report = store.missingSourceDigests(load)
        let byDigest = Dictionary(uniqueKeysWithValues: report.holders.map { ($0.digest, $0) })
        XCTAssertEqual(report.holders.count, 6, "\(report.holders)")
        XCTAssertEqual(byDigest[dPerson]?.owner, "chen-h-y");      XCTAssertEqual(byDigest[dPerson]?.kind, "person")
        XCTAssertEqual(byDigest[dOrg]?.owner, "iss");              XCTAssertEqual(byDigest[dOrg]?.kind, "organization")
        XCTAssertEqual(byDigest[dVenue]?.owner, "psychometrika");  XCTAssertEqual(byDigest[dVenue]?.kind, "venue")
        XCTAssertEqual(byDigest[dDiv]?.owner, d.id.uuidString);    XCTAssertEqual(byDigest[dDiv]?.kind, "divergence")
        XCTAssertEqual(byDigest[dSources]?.owner, "a2020b");       XCTAssertEqual(byDigest[dSources]?.kind, "entry")
        XCTAssertEqual(byDigest[dEntryRef]?.owner, "a2020b");      XCTAssertEqual(byDigest[dEntryRef]?.kind, "entry")
        XCTAssertEqual(byDigest[dSources]?.slot, "akashic.sources")
        XCTAssertEqual(byDigest[dEntryRef]?.slot, "doi")
        XCTAssertEqual(byDigest[dDiv]?.slot, "judgement.restsOn")
        XCTAssertEqual(report.missing, [dPerson, dOrg, dVenue, dDiv, dSources, dEntryRef].sorted(),
                       "既有的 `missing` 語意不變：distinct digest、排序")

        // health 真的呼叫掃描——拿掉 `health(from:)` 裡的 append 這裡就紅
        let health = store.health(from: load)
        let dangling = health.danglingSources
        XCTAssertEqual(dangling.count, 6, "\(dangling.map(\.issue.message))")
        XCTAssertTrue(dangling.allSatisfy { $0.issue.severity == .warning },
                      "記錄合法可載入，缺的是位元組——warning，不是 error")
        XCTAssertTrue(dangling.allSatisfy { $0.issue.message.hasPrefix(StoreHealth.danglingSourcePrefix) })
        XCTAssertTrue(dangling.allSatisfy { $0.issue.message.contains("sources/ 不進 git") },
                      "訊息要說出為什麼其他 clone 上的數字會不同")
        XCTAssertEqual(Set(dangling.map(\.owner)),
                       ["chen-h-y", "iss", "psychometrika", d.id.uuidString, "a2020b"])
    }

    /// 真的存進 `sources/` 的 digest 不報——六個 slot 各放一筆真的。
    func testPresentDigestIsNotReported() throws {
        let real = try present("kept")
        var p = Person(key: "chen-h-y", names: PersonNames(variant: ["Chen, H-Y."]))
        p.orcid = ORCID("0000-0003-4038-9439")
        p.references = [retrieval("orcid", content: real)]
        try store.writePerson(p)
        var v = Venue(key: "psychometrika", type: .periodical,
                      names: TimelineOf([TemporalValue(value: "Psychometrika")]))
        v.references = [retrieval("names", value: "Psychometrika", content: real)]
        try store.writeVenue(v)
        var e = Entry(id: UUID(), citekey: "a2020b", type: .periodicalArticle, title: "T",
                      doi: [try XCTUnwrap(DOI("10.1000/x"))])
        e.akashic.sources = [real]
        e.references = [retrieval("doi", value: "10.1000/x", content: real)]
        try store.writeEntry(e)

        let load = try store.load()
        XCTAssertTrue(store.missingSourceDigests(load).holders.isEmpty)
        XCTAssertTrue(store.health(from: load).danglingSources.isEmpty)
    }

    /// 不是 `sha256:` 形的值（live store 2026-09-04 實測：一筆 divergence 的 `judgement.restsOn` 裝的是
    /// `https://doi.org/…`）——它**無從在本機查找**，訊息不能說「找不到」（那暗示同步就會有），要說
    /// 「不是合法的 digest」。既有的 `missing` 語意把它算缺席不變；per-record 訊息分開說。
    func testMalformedDigestSaysMalformedNotMissing() throws {
        try store.writePerson(Person(key: "p-one", names: ["P"]))
        try store.writePerson(Person(key: "p-two", names: ["P2"]))
        var d = Divergence(id: UUID(), question: "q",
                           candidates: [DivergenceCandidate(key: "p-one", shape: .person),
                                        DivergenceCandidate(key: "p-two", shape: .person)])
        d.judgement = Judgement(statement: "s", restsOn: ["https://doi.org/10.1038/x"])
        try store.writeDivergence(d)
        let load = try store.load()
        let report = store.missingSourceDigests(load)
        XCTAssertEqual(report.holders.count, 1)
        XCTAssertEqual(report.holders.first?.wellFormed, false)
        XCTAssertEqual(report.missing, ["https://doi.org/10.1038/x"], "既有 `missing` 語意：不合法也算缺席")
        let dangling = store.health(from: load).danglingSources
        XCTAssertEqual(dangling.count, 1)
        let msg = try XCTUnwrap(dangling.first?.issue.message)
        XCTAssertTrue(msg.contains("不是合法的 digest"), msg)
        XCTAssertFalse(msg.contains("找不到這份存檔"), "不合法的值不該被說成「同步就會有」：\(msg)")
    }

    /// #265 的既有語意不動：shard 目錄存在但列不出來 → 不判缺席、不出 warning，shard 進
    /// `unreadableShards`——「讀不到」與「缺席」在其他 clone 上是兩件事。
    func testUnreadableShardIsNotAWarning() throws {
        let real = try present("locked")
        var v = Venue(key: "psychometrika", type: .periodical,
                      names: TimelineOf([TemporalValue(value: "Psychometrika")]))
        v.references = [retrieval("names", value: "Psychometrika", content: real)]
        try store.writeVenue(v)
        // 把 blob 拿走、再把 shard 目錄鎖成不可列
        let blob = try XCTUnwrap(store.sourceURL(digest: real))
        try FileManager.default.removeItem(at: blob)
        let shard = blob.deletingLastPathComponent()
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: shard.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: shard.path) }

        let load = try store.load()
        let report = store.missingSourceDigests(load)
        XCTAssertTrue(report.holders.isEmpty, "\(report.holders)")
        XCTAssertEqual(report.unreadableShards.count, 1)
        XCTAssertTrue(store.health(from: load).danglingSources.isEmpty,
                      "讀不到不是缺席——那是 auditSourceIndex 的 unreadableShards 在報的事")
    }

    /// 兩個消費面都要提到 `danglingSources`：`StoreHealthSurfaceTests` 的反射只看**儲存**屬性，
    /// 計算屬性（`deadVerdicts` 亦然）落在它的視野外——所以這裡用源碼掃描釘住，第三面（App）
    /// 未渲染 per-record 是 #416 起的既有缺口（#487），不在本測試內。
    func testBothFacesMentionDanglingSources() throws {
        let repo = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let service = try String(contentsOf: repo.appendingPathComponent("Sources/AkashicMCPKit/AkashicService.swift"),
                                 encoding: .utf8)
        let cli = try String(contentsOf: repo.appendingPathComponent("Sources/akashic/Commands.swift"),
                             encoding: .utf8)
        guard let start = service.range(of: "public func doctor() throws -> String {") else {
            return XCTFail("找不到 doctor()——本測試的前提不成立")
        }
        let doctorBody = String(service[start.lowerBound...].prefix(8000))
        XCTAssertTrue(doctorBody.contains("health.danglingSources"),
                      "MCP doctor() 沒有消費 danglingSources——一面有計數另一面沒有，就是 #263 修掉的分岔")
        XCTAssertTrue(cli.contains("health.danglingSources"),
                      "CLI validate 沒有消費 danglingSources")
    }
}
