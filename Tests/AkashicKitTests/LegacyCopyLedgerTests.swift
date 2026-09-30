import XCTest
import Foundation
@testable import AkashicCore
@testable import AkashicStoreIO

/// #705：內容寫進 `entities/`、但 #631 搬移後的 legacy 拷貝刪不掉的那一筆——**寫了**，記在成功那一側。
///
/// 使用者 2026-09-30 裁決 (a)：各寫入者統一，這一筆列在回報面的 `writtenWithLegacyCopy`，不算失敗、不進任何失敗清單。
/// 機制是一個收集範圍（`LegacyCopyLedger.collecting`）：範圍內 `writeEntry`／`writePerson` 記下這一筆、照常回傳；範圍外照舊擲
/// `legacyCopyNotRemoved`（#702）——沒有人收集的地方不會安靜吞掉它。
///
/// 刪不掉的造法同 #702 R1 verify 的測試：legacy 檔受 git 追蹤、乾淨（寫入時會搬移它），然後讓它所在的目錄唯讀。
final class LegacyCopyLedgerTests: XCTestCase {
    private var root: URL!
    private var store: LibraryStore!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("akashic-705-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        GitFixture.initRepo(root)
        try "sources/\n".write(to: root.appendingPathComponent(".gitignore"), atomically: true, encoding: .utf8)
        store = LibraryStore(root: root, key: nil, environment: [:])
        try store.ensureLayout()
        try StoreVersion.write(root: root, format: StoreVersion.supported)
        XCTAssertTrue(store.usesEntitiesLayout, "前提：entities 佈局——legacy 目錄在這裡是殘留")
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

    // MARK: - 夾具

    /// 讓 `dir` 唯讀：裡面的檔刪不掉。以 root 執行時權限擋不住，那時造不出這個狀態——skip，不假綠。
    private func lock(_ dir: URL) throws {
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: dir.path)
        let probe = dir.appendingPathComponent("probe-\(UUID().uuidString)")
        if FileManager.default.createFile(atPath: probe.path, contents: Data()) {
            try? FileManager.default.removeItem(at: probe)
            throw XCTSkip("這個環境的權限擋不住刪檔（以 root 執行？），造不出「寫完之後刪 legacy 失敗」")
        }
    }

    /// legacy 佈局的一筆 work：只有 `entries/<citekey>.yaml` 一份，受 git 追蹤、乾淨——寫入時會搬移它（#631），而刪除會失敗。
    private func legacyWork() throws -> Entry {
        let e = Entry(id: UUID(), citekey: "cheng2025identifiability", type: .periodicalArticle,
                      title: "Identifiability of polychoric models", authors: [.literal("Che Cheng")], date: "2025")
        try EntryYAML.encode(e).write(to: store.entriesDir.appendingPathComponent("\(e.citekey).yaml"),
                                      atomically: true, encoding: .utf8)
        GitFixture.commitAll(root)
        try lock(store.entriesDir)
        return e
    }

    /// 同上，person：只有 `people/<key>.yaml` 一份。
    private func legacyPerson() throws -> Person {
        let p = Person(key: "cheng-che", names: PersonNames(variant: ["Che Cheng"]))
        try PersonYAML.encode(p).write(to: store.personURL(key: p.key), atomically: true, encoding: .utf8)
        GitFixture.commitAll(root)
        try lock(store.peopleDir)
        return p
    }

    private struct Boom: Error {}

    // MARK: - 範圍外：照舊擲錯

    func testOutsideAnyScopeTheWriteStillThrows() throws {
        var e = try legacyWork()
        e.akashic.tags = ["x"]
        XCTAssertThrowsError(try store.writeEntry(e)) { error in
            guard case StoreIOError.legacyCopyNotRemoved = error else { return XCTFail("應是 legacyCopyNotRemoved：\(error)") }
            let d = (error as? LocalizedError)?.errorDescription ?? ""
            XCTAssertTrue(d.hasPrefix("已寫入 entities/\(e.id.uuidString).yaml"), d)
            XCTAssertTrue(d.contains("entries/\(e.citekey).yaml"), d)
        }
        XCTAssertTrue(try String(contentsOf: store.entityURL(id: e.id), encoding: .utf8).contains("- x"), "擲錯之前已經寫了")
    }

    /// person 那一半走同一個 `removeMovedLegacy`（#702 R2 verify：先前沒有任何測試走到 `writePerson` 這一條）。
    func testOutsideAnyScopeThePersonWriteStillThrows() throws {
        var p = try legacyPerson()
        p.note = "改過"
        XCTAssertThrowsError(try store.writePerson(p)) { error in
            guard case StoreIOError.legacyCopyNotRemoved = error else { return XCTFail("應是 legacyCopyNotRemoved：\(error)") }
            let d = (error as? LocalizedError)?.errorDescription ?? ""
            XCTAssertTrue(d.hasPrefix("已寫入 entities/\(p.id.uuidString).yaml"), d)
            XCTAssertTrue(d.contains("people/\(p.key).yaml"), d)
        }
        XCTAssertTrue(try String(contentsOf: store.entityURL(id: p.id), encoding: .utf8).contains("改過"), "擲錯之前已經寫了")
    }

    /// 刪除時 legacy 檔**已經不在**（別的程序先刪了）：搬移要的終態達成，不是「兩份並存」——範圍外不擲、範圍內不記（#702 R2 verify）。
    /// 權限擋住的刪除（檔案還在）不屬於這一格。
    func testALegacyFileThatIsAlreadyGoneIsNotALeftover() throws {
        let missing = store.entriesDir.appendingPathComponent("gone2025.yaml")
        var enoent: Error?
        XCTAssertThrowsError(try FileManager.default.removeItem(at: missing)) { enoent = $0 }
        XCTAssertTrue(LibraryStore.isNoSuchFile(try XCTUnwrap(enoent)), "前提：刪一個不存在的檔擲的是「沒有這個檔」：\(String(describing: enoent))")
        XCTAssertNoThrow(try store.removeMovedLegacy(missing, kind: .work, key: "gone2025", id: UUID()), "範圍外不擲")
        let (result, written) = LegacyCopyLedger.collecting {
            try store.removeMovedLegacy(missing, kind: .work, key: "gone2025", id: UUID())
        }
        XCTAssertNoThrow(try result.get())
        XCTAssertEqual(written, [], "範圍內不記")

        _ = try legacyWork()   // entries/ 唯讀：裡面的檔刪不掉，錯誤不是「沒有這個檔」
        let locked = store.entriesDir.appendingPathComponent("cheng2025identifiability.yaml")
        var denied: Error?
        XCTAssertThrowsError(try FileManager.default.removeItem(at: locked)) { denied = $0 }
        XCTAssertFalse(LibraryStore.isNoSuchFile(try XCTUnwrap(denied)), "權限擋住的不是「已經不在」：\(String(describing: denied))")
    }

    /// 範圍結束後不殘留：之後範圍外的寫入照舊擲錯（task-local 的綁定只在 body 期間有效）。
    func testTheScopeEndsWithItsBody() throws {
        var e = try legacyWork()
        e.akashic.tags = ["x"]
        let (first, _) = LegacyCopyLedger.collecting { () }
        XCTAssertNoThrow(try first.get())
        XCTAssertThrowsError(try store.writeEntry(e), "範圍外的寫入不得被一個已經結束的範圍收走")
    }

    // MARK: - 範圍內：記下、照常回傳

    func testInsideAScopeTheWorkIsRecordedAsWritten() throws {
        var e = try legacyWork()
        e.akashic.tags = ["x"]
        let (result, written) = LegacyCopyLedger.collecting { try store.writeEntry(e) }
        XCTAssertNoThrow(try result.get(), "寫了，不是失敗")
        XCTAssertEqual(written.count, 1, "\(written)")
        let left = try XCTUnwrap(written.first)
        XCTAssertEqual(left.kind, .work)
        XCTAssertEqual(left.key, e.citekey)
        XCTAssertEqual(left.id, e.id)
        XCTAssertEqual(left.legacyFile, "entries/\(e.citekey).yaml")
        XCTAssertEqual(left.writtenFile, "entities/\(e.id.uuidString).yaml")
        XCTAssertFalse(left.detail.isEmpty, "刪不掉的原因要留著")
        let onDisk = try String(contentsOf: store.entityURL(id: e.id), encoding: .utf8)
        XCTAssertTrue(onDisk.contains("- x"), "內容已經寫進 entities/：\(onDisk)")
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.entriesDir.appendingPathComponent("\(e.citekey).yaml").path),
                      "前提：legacy 那份還在")
    }

    func testInsideAScopeThePersonIsRecordedAsWritten() throws {
        var p = try legacyPerson()
        p.note = "改過"
        let (result, written) = LegacyCopyLedger.collecting { try store.writePerson(p) }
        XCTAssertNoThrow(try result.get())
        XCTAssertEqual(written.map(\.kind), [.person])
        XCTAssertEqual(written.map(\.key), [p.key])
        XCTAssertEqual(written.map(\.legacyFile), ["people/\(p.key).yaml"])
        let onDisk = try String(contentsOf: store.entityURL(id: p.id), encoding: .utf8)
        XCTAssertTrue(onDisk.contains("改過"), onDisk)
    }

    /// 人可讀的一句話：具名是哪一筆、兩個檔各在哪、這一筆寫了。CLI 的尾段與 MCP 錯誤的附記都印它。
    func testMessageNamesTheRecordAndBothFiles() throws {
        var e = try legacyWork()
        e.akashic.tags = ["x"]
        let (_, written) = LegacyCopyLedger.collecting { try store.writeEntry(e) }
        let message = try XCTUnwrap(written.first?.message)
        XCTAssertTrue(message.contains("work「\(e.citekey)」"), message)
        XCTAssertTrue(message.contains("已寫入 entities/\(e.id.uuidString).yaml"), message)
        XCTAssertTrue(message.contains("entries/\(e.citekey).yaml"), message)
        let lines = LegacyCopyLeft.reportLines(written)
        XCTAssertEqual(lines.count, 2, "\(lines)")
        XCTAssertTrue(lines[0].hasPrefix("writtenWithLegacyCopy"), lines[0])
        XCTAssertTrue(lines[1].contains(message), lines[1])
        XCTAssertEqual(LegacyCopyLeft.reportLines([]), [], "沒有就不印")
    }

    // MARK: - 巢狀

    /// 最內層收下：它自己的報告（例如 `ImportReport`）列出這一筆，外層不重複。
    func testTheInnermostScopeClaimsWhatItCollected() throws {
        var e = try legacyWork()
        e.akashic.tags = ["x"]
        var inner: [LegacyCopyLeft] = []
        let (outerResult, outer) = LegacyCopyLedger.collecting {
            let (r, w) = LegacyCopyLedger.collecting { try store.writeEntry(e) }
            inner = w
            return try r.get()
        }
        XCTAssertNoThrow(try outerResult.get())
        XCTAssertEqual(inner.map(\.key), [e.citekey])
        XCTAssertEqual(outer, [], "每一筆只在一個地方被報告")
    }

    /// 內層的 body 擲錯時沒有報告可以放——收到的轉交外層，錯誤不帶走它們；回傳空陣列（仍然只報一次）。
    func testAFailedInnerScopeHandsOffToTheOuter() throws {
        var e = try legacyWork()
        e.akashic.tags = ["x"]
        var inner: [LegacyCopyLeft] = [LegacyCopyLeft(kind: .person, key: "sentinel", id: UUID(), legacyFile: "", detail: "")]
        var innerFailed = false
        let (_, outer) = LegacyCopyLedger.collecting {
            let (r, w) = LegacyCopyLedger.collecting { () throws -> Void in
                try store.writeEntry(e)
                throw Boom()
            }
            inner = w
            if case .failure = r { innerFailed = true }
        }
        XCTAssertTrue(innerFailed)
        XCTAssertEqual(inner, [], "已轉交外層")
        XCTAssertEqual(outer.map(\.key), [e.citekey], "寫進去的那一筆不能跟著錯誤一起消失")
    }
}
