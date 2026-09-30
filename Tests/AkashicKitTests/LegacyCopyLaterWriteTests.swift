import XCTest
import Foundation
@testable import AkashicCore
@testable import AkashicStoreIO

/// #705 R2 verify 第 5／9／20 列：同一個操作稍早一步寫進 `entities/`、搬移後的 legacy 拷貝刪不掉之後，同一筆的下一次寫入被 #631 拒絕
/// （兩份並存）。先前只有 `ZoteroImporter` 自己查收集範圍、說出前一步寫了；其他多步寫入者得到泛用的「兩份並存，拒絕寫入」。
/// 現在拒絕本身（`LibraryStore` 的寫入前置）查範圍：所有寫入者同一句（`legacyCopyLeftEarlierInThisOperation`），並把「之後的寫入沒有套用」
/// 標在稍早那一筆上（`laterWriteRefused`）——與它記在同一個地方（成功那一側）。
final class LegacyCopyLaterWriteTests: XCTestCase {
    private var root: URL!
    private var store: LibraryStore!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("akashic-705r2-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        GitFixture.initRepo(root)
        try "sources/\n".write(to: root.appendingPathComponent(".gitignore"), atomically: true, encoding: .utf8)
        store = LibraryStore(root: root, key: nil, environment: [:])
        try store.ensureLayout()
        try StoreVersion.write(root: root, format: StoreVersion.supported)
        for dir in [store.entriesDir, store.peopleDir] {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }

    override func tearDownWithError() throws {
        for dir in [store.entriesDir, store.peopleDir] {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dir.path)
        }
        try? FileManager.default.removeItem(at: root)
    }

    private func lock(_ dir: URL) throws {
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: dir.path)
        let probe = dir.appendingPathComponent("probe-\(UUID().uuidString)")
        if FileManager.default.createFile(atPath: probe.path, contents: Data()) {
            try? FileManager.default.removeItem(at: probe)
            throw XCTSkip("這個環境的權限擋不住刪檔（以 root 執行？），造不出「寫完之後刪 legacy 失敗」")
        }
    }

    private func legacyWork() throws -> Entry {
        let e = Entry(id: UUID(), citekey: "cheng2025identifiability", type: .periodicalArticle,
                      title: "Identifiability of polychoric models", authors: [.literal("Che Cheng")], date: "2025")
        try EntryYAML.encode(e).write(to: store.entriesDir.appendingPathComponent("\(e.citekey).yaml"),
                                      atomically: true, encoding: .utf8)
        GitFixture.commitAll(root)
        try lock(store.entriesDir)
        return e
    }

    private func legacyPerson() throws -> Person {
        let p = Person(key: "yang-hau-hung", names: PersonNames(variant: ["Hau-Hung Yang"]))
        try PersonYAML.encode(p).write(to: store.personURL(key: p.key), atomically: true, encoding: .utf8)
        GitFixture.commitAll(root)
        try lock(store.peopleDir)
        return p
    }

    private func assertEarlierStepRefusal(_ error: Error, id: UUID, file: StaticString = #filePath, line: UInt = #line) {
        guard case StoreIOError.legacyCopyLeftEarlierInThisOperation(let refusedID, _) = error else {
            return XCTFail("應是 legacyCopyLeftEarlierInThisOperation，得 \(error)", file: file, line: line)
        }
        XCTAssertEqual(refusedID, id, file: file, line: line)
        let text = (error as? LocalizedError)?.errorDescription ?? ""
        XCTAssertTrue(text.hasPrefix("同一個操作稍早已寫入這一筆（見 writtenWithLegacyCopy）"), text, file: file, line: line)
        XCTAssertTrue(text.contains("這一步的改動沒有套用"), text, file: file, line: line)
    }

    /// work：同一個範圍裡寫兩次。第一次寫了、legacy 留著；第二次被拒絕，拒絕說出前一步寫了；那一筆標上 `laterWriteRefused`。
    func testAWorkWrittenTwiceInOneScopeSaysTheEarlierStepWrote() throws {
        var e = try legacyWork()
        let (result, written) = LegacyCopyLedger.collecting { () throws -> Void in
            try store.writeEntry(e)
            e.title = "Second step"
            XCTAssertThrowsError(try store.writeEntry(e)) { assertEarlierStepRefusal($0, id: e.id) }
        }
        XCTAssertNoThrow(try result.get())
        XCTAssertEqual(written.map(\.key), [e.citekey])
        XCTAssertEqual(written.map(\.laterWriteRefused), [true], "之後的寫入沒有套用，標在同一筆上")
        let line = try XCTUnwrap(LegacyCopyLeft.reportLines(written).last)
        XCTAssertTrue(line.hasSuffix("；" + LegacyCopyLeft.laterWriteRefusedNote), line)
        let onDisk = try EntryYAML.decode(try String(contentsOf: store.entityURL(id: e.id), encoding: .utf8))
        XCTAssertNotEqual(onDisk.title, "Second step", "第二步沒有套用")
    }

    /// person：同一句話、同一個標記（`writePerson` 走同一個前置）。
    func testAPersonWrittenTwiceInOneScopeSaysTheEarlierStepWrote() throws {
        var p = try legacyPerson()
        let (_, written) = LegacyCopyLedger.collecting { () throws -> Void in
            try store.writePerson(p)
            p.note = "second"
            XCTAssertThrowsError(try store.writePerson(p)) { assertEarlierStepRefusal($0, id: p.id) }
        }
        XCTAssertEqual(written.map(\.laterWriteRefused), [true])
    }

    /// 外層稍早記下、之後開的內層範圍又寫同一筆：拒絕沿範圍鏈找到外層那一筆、標在它上面。
    func testAnInnerScopeSeesTheOuterScopesEarlierWrite() throws {
        let e = try legacyWork()
        let (_, outer) = LegacyCopyLedger.collecting { () throws -> Void in
            try store.writeEntry(e)
            let (_, inner) = LegacyCopyLedger.collecting { () throws -> Void in
                XCTAssertThrowsError(try store.writeEntry(e)) { assertEarlierStepRefusal($0, id: e.id) }
            }
            XCTAssertEqual(inner, [], "內層沒有新記下的")
        }
        XCTAssertEqual(outer.map(\.laterWriteRefused), [true])
    }

    /// 沒有範圍：第一次擲 `legacyCopyNotRemoved`（#702），第二次是泛用的兩份並存——沒有「稍早」可以說。
    func testOutsideAnyScopeTheSecondWriteGetsTheGenericRefusal() throws {
        let e = try legacyWork()
        XCTAssertThrowsError(try store.writeEntry(e)) {
            guard case StoreIOError.legacyCopyNotRemoved = $0 else { return XCTFail("\($0)") }
        }
        XCTAssertThrowsError(try store.writeEntry(e)) {
            guard case StoreIOError.legacyCopyPresent = $0 else { return XCTFail("\($0)") }
        }
    }

    /// load 的標註（#641）也說同一句，但**不**標記——load 不是一次寫入，只有寫入路徑標「之後的寫入沒有套用」。
    func testTheLoadAnnotationUsesTheSameSentenceWithoutMarking() throws {
        let e = try legacyWork()
        let (_, written) = LegacyCopyLedger.collecting { () throws -> Void in
            try store.writeEntry(e)
            let loaded = try XCTUnwrap(try store.load().entries.first { $0.id == e.id })
            let why = try XCTUnwrap(loaded.fileSituation.unwritableReason)
            XCTAssertTrue(why.contains("同一個操作稍早已寫入這一筆"), why)
        }
        XCTAssertEqual(written.map(\.laterWriteRefused), [false], "load 沒有嘗試寫入")
    }

    /// 人可讀報告的上限（MCP 的錯誤回應用）：標題是完整筆數，列前 `limit` 筆，多出的一行說筆數與去哪裡找；nil＝全列（CLI）。
    func testReportLinesCapWithADisclosure() {
        let items = (1...25).map { i in
            LegacyCopyLeft(kind: .work, key: String(format: "k%02d", i), id: UUID(), legacyFile: "entries/k.yaml", detail: "d")
        }
        let capped = LegacyCopyLeft.reportLines(items, limit: 20)
        XCTAssertTrue(capped.first?.hasSuffix(": 25") == true, capped.first ?? "")
        XCTAssertEqual(capped.filter { $0.hasPrefix("  ⚠ ") }.count, 20)
        XCTAssertTrue(capped.last?.contains("另有 5 筆未列出") == true && capped.last?.contains("akashic validate") == true, capped.last ?? "")
        XCTAssertEqual(LegacyCopyLeft.reportLines(items).count, 26, "沒給上限＝全列、沒有揭露行")
        XCTAssertEqual(LegacyCopyLeft.reportLines(Array(items.prefix(3)), limit: 20).count, 4, "上限之內沒有揭露行")
    }
}
