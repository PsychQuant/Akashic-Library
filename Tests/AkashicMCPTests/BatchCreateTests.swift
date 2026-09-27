import XCTest
@testable import AkashicCore
@testable import AkashicStoreIO
@testable import AkashicMCPKit

/// #455：批次 create 的 service 面——一次 load、批次內累積 `existing`、先全驗再寫、
/// `writeEntryExclusive`、I/O 失敗逐筆收容、一次 rebuild。失敗語意由使用者裁決（2026-09-03）：
/// **可預期的失敗整批擋、零寫入；I/O 失敗逐筆收容、其餘照寫、rebuild 照跑。**
final class BatchCreateTests: XCTestCase {
    var root: URL!
    var fakeHome: URL!
    var service: AkashicService!
    var env: [String: String] { ["AKASHIC_HOME": fakeHome.path] }

    override func setUpWithError() throws {
        fakeHome = FileManager.default.temporaryDirectory
            .appendingPathComponent("akashic-home-\(UUID().uuidString)")
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("akashic-batch-\(UUID().uuidString)")
        try LibraryStore(root: root).ensureLayout()
        service = AkashicService(root: root, environment: env)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
        try? FileManager.default.removeItem(at: fakeHome)
    }

    private func draft(_ title: String, author: String = "Some Author", type: String = "periodical-article",
                       id: UUID? = nil) -> AkashicService.EntryDraft {
        AkashicService.EntryDraft(type: type, title: title, authors: [author], date: "2024",
                                  fields: ["journaltitle": "Batch Journal"], id: id)
    }

    /// 同批三筆同作者同年同標題首詞：citekey 必須在批次內就消解碰撞（`existing` 逐筆累積）。
    func testCreateEntriesResolvesCitekeyCollisionsWithinTheBatch() throws {
        let report = try service.createEntries([draft("Manual one"), draft("Manual two"), draft("Manual three")])
        XCTAssertEqual(report.created.map(\.citekey), ["author2024manual", "author2024bmanual", "author2024cmanual"])
        XCTAssertTrue(report.writeFailures.isEmpty, "\(report.writeFailures)")
        XCTAssertEqual(Set(try LibraryStore(root: root).load().entries.map(\.citekey)),
                       ["author2024manual", "author2024bmanual", "author2024cmanual"])
    }

    /// 兩筆合法＋一筆 type 不在值域：整批拒絕、零寫入，訊息指名是第幾筆與它的 title。
    func testCreateEntriesPredictableFailureWritesNothing() throws {
        XCTAssertThrowsError(try service.createEntries([draft("Good one"), draft("Good two"),
                                                        draft("Bad type", type: "not-a-type")])) { error in
            let msg = String(describing: error)
            XCTAssertTrue(msg.contains("第 3 筆") && msg.contains("Bad type"), msg)
        }
        XCTAssertTrue(try LibraryStore(root: root).load().entries.isEmpty, "可預期的失敗：零寫入")
    }

    /// 其中一筆的目的檔位置被一個目錄占住（exclusive 寫入失敗）：不 throw、那一筆進 writeFailures、
    /// 其餘照寫、index 反映已寫的（rebuild 照跑）。
    func testCreateEntriesIOFailureIsPerRecordAndStillRebuilds() throws {
        let doomedID = UUID()
        let store = LibraryStore(root: root)
        try FileManager.default.createDirectory(at: store.entityURL(id: doomedID), withIntermediateDirectories: true)
        try Data("x".utf8).write(to: store.entityURL(id: doomedID).appendingPathComponent("occupied"))
        let report = try service.createEntries([draft("Alpha study"), draft("Beta study", id: doomedID),
                                                draft("Gamma study")])
        XCTAssertEqual(report.created.map(\.citekey), ["author2024alpha", "author2024gamma"])
        XCTAssertEqual(report.writeFailures.map(\.title), ["Beta study"])
        XCTAssertEqual(report.writeFailures.first?.index, 1)
        let found = try service.search(journal: "Batch Journal")
        XCTAssertTrue(found.contains("author2024alpha") && found.contains("author2024gamma"), found)
        XCTAssertFalse(found.contains("author2024beta"), found)
    }
}

// MARK: - library membership 的批次形（#455 同族：add／remove 一次 load、整批驗、逐筆寫、一次 rebuild）

extension BatchCreateTests {
    private func seedTwoEntriesAndALibrary() throws {
        _ = try service.createEntries([draft("Alpha study"), draft("Gamma study")])
        _ = try service.libraries(action: "create", key: "reading", name: "Reading", description: nil, citekey: nil)
    }

    /// 兩個 citekey 其中一個不存在：整批拒絕、零寫入（存在的那筆 membership 不變）。
    func testSetMembershipRejectsUnknownCitekeyWithZeroWrites() throws {
        try seedTwoEntriesAndALibrary()
        XCTAssertThrowsError(try service.setMembership(action: "add", key: "reading",
                                                       citekeys: ["author2024alpha", "no-such-key"]))
        let alpha = try LibraryStore(root: root).load().entries.first { $0.citekey == "author2024alpha" }
        XCTAssertEqual(alpha?.akashic.libraries, [], "整批拒絕：存在的那筆也不得被寫")
    }

    /// 兩個都存在：兩筆都加進 library，報告列出兩筆；remove 同路徑。
    func testSetMembershipWritesAllCitekeysInOneBatch() throws {
        try seedTwoEntriesAndALibrary()
        let added = try service.setMembership(action: "add", key: "reading",
                                              citekeys: ["author2024alpha", "author2024gamma"])
        XCTAssertEqual(added.written, ["author2024alpha", "author2024gamma"])
        let load = try LibraryStore(root: root).load()
        XCTAssertEqual(load.entries.filter { $0.akashic.libraries == ["reading"] }.count, 2)
        let removed = try service.setMembership(action: "remove", key: "reading", citekeys: ["author2024gamma"])
        XCTAssertEqual(removed.written, ["author2024gamma"])
        XCTAssertEqual(try LibraryStore(root: root).load().entries.first { $0.citekey == "author2024gamma" }?.akashic.libraries, [])
    }
}

// MARK: - #637：DOI 已在庫時具名回報（只回報、不拒絕）

extension BatchCreateTests {
    private func doiDraft(_ title: String, _ doi: String) -> AkashicService.EntryDraft {
        AkashicService.EntryDraft(type: "periodical-article", title: title, authors: ["Some Author"], date: "2024",
                                  fields: ["journaltitle": "Batch Journal"], doi: [doi])
    }

    /// 已在庫的 DOI：照常建（DOI 相同只是提名），回報命中的 citekey；DOI 不同的那筆不回報。
    func testCreateEntriesReportsDOIAlreadyInStore() throws {
        _ = try service.createEntries([doiDraft("Original study", "10.1037/abc")])
        let report = try service.createEntries([doiDraft("Original study again", "10.1037/ABC"),
                                                doiDraft("Unrelated study", "10.1037/xyz")])
        XCTAssertEqual(report.created.count, 2, "只回報、不拒絕")
        XCTAssertEqual(report.doiHits.map(\.index), [0])
        XCTAssertEqual(report.doiHits.first?.existing, ["author2024original"])
        XCTAssertEqual(report.doiHits.first?.doi, "10.1037/abc", "比對走正規形")
    }

    /// 同一批兩筆用同一個 DOI：第二筆回報第一筆。
    func testCreateEntriesReportsDOIRepeatedWithinTheBatch() throws {
        let report = try service.createEntries([doiDraft("First copy", "10.1037/dup"), doiDraft("Second copy", "10.1037/dup")])
        XCTAssertEqual(report.doiHits.map(\.index), [1])
        XCTAssertEqual(report.doiHits.first?.existing, ["author2024first"])
    }

    /// MCP 的單筆面：回應帶 doiHits。
    func testSingleCreateEntryPayloadCarriesDOIHits() throws {
        _ = try service.createEntries([doiDraft("Original study", "10.1037/abc")])
        let out = try service.createEntry(type: "periodical-article", title: "Copy", authors: ["Some Author"],
                                          date: "2024", fields: [:], doi: ["10.1037/abc"])
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(out.utf8)) as? [String: Any])
        let hits = try XCTUnwrap(json["doiHits"] as? [[String: Any]], out)
        XCTAssertEqual(hits.first?["existing"] as? [String], ["author2024original"])
    }
}
