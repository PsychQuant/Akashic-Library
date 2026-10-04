import XCTest
import CryptoKit
import Foundation
@testable import AkashicCore
@testable import AkashicMCPKit
@testable import AkashicStoreIO

/// #703 R2 verify 第 4、5、6、10、28 則的服務層（MCP 面讀的那一份 payload）：
///
/// - `akashic_store_source` 回 `bytesWritten`（這一次才存 vs 早就在），位址被佔住時具名拒絕、不寫 index；
/// - `akashic_doctor` 的 `sources` 帶 `occupantProblems`／`occupantProblemsTotal`，`strayTemporaryFiles` 每則帶 `ageSeconds` 與
///   `possiblyInProgress`（R2 之前只有 {path, bytes}，而 MCP 的讀者最可能照「stray」去刪正在進行的複製），總數在 `strayTemporaryFilesTotal`。
final class SourceAddressServiceTests: XCTestCase {
    private var root: URL!
    private var service: AkashicService!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("akashic-srcaddr-svc-\(UUID().uuidString)")
        try LibraryStore(root: root).ensureLayout()
        service = AkashicService(root: root)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    private func json(_ s: String) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: Data(s.utf8)) as? [String: Any])
    }
    private func digest(_ data: Data) -> String { "sha256:" + SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
    private func address(_ d: String) -> URL {
        let hex = String(d.dropFirst("sha256:".count))
        return root.appendingPathComponent("sources/\(hex.prefix(2))/\(hex.dropFirst(2))")
    }
    private func storeSource(_ data: Data) throws -> [String: Any] {
        let f = root.appendingPathComponent("in-\(UUID().uuidString).pdf")
        try data.write(to: f)
        defer { try? FileManager.default.removeItem(at: f) }
        return try json(try service.storeSource(path: f.path, mediaType: "application/pdf", retrieved: "2026-10-01",
                                                origin: "https://example.org/x.pdf", acquisition: "browser-download"))
    }

    func testStoreSourceTellsWhetherItWroteTheBytes() throws {
        let data = Data("%PDF-1.7 written now".utf8)
        XCTAssertEqual(try storeSource(data)["bytesWritten"] as? Bool, true)
        XCTAssertEqual(try storeSource(data)["bytesWritten"] as? Bool, false, "位址上早有大小相同的一份")
    }

    /// b29 V5 LOW 3、8：說明先前寫「exclusionVerified=false 時拒絕」，實際照存（store 不在 git 工作樹內時排除沒驗，回 false、位元組照存）。
    /// 呼叫端只讀得到這一句：它會以為成功的回應必然是 exclusionVerified:true。這一支把說明與行為釘在一起（這個 store 不是 git 工作樹）。
    func testTheStoreSourceDescriptionSaysWhatExclusionVerifiedFalseMeans() throws {
        let out = try storeSource(Data("%PDF-1.7 not in git".utf8))
        XCTAssertEqual(out["exclusionVerified"] as? Bool, false, "前提：store 不在 git 工作樹內")
        XCTAssertEqual(out["bytesWritten"] as? Bool, true, "false 時照存")
        let text = try XCTUnwrap(try ToolManifest.load()["akashic_store_source"]).text
        XCTAssertFalse(text.contains("false 時拒絕"), "說明不得說 false 時拒絕：\(text)")
        XCTAssertTrue(text.contains("exclusionVerified:false＝不在 git 內") && text.contains("照存"), text)
    }

    func testStoreSourceRefusesAnOccupiedAddress() throws {
        let data = Data("%PDF-1.7 occupied".utf8)
        try FileManager.default.createDirectory(at: address(digest(data)), withIntermediateDirectories: true)
        XCTAssertThrowsError(try storeSource(data)) { e in
            let msg = (e as? LocalizedError)?.errorDescription ?? "\(e)"
            XCTAssertTrue(msg.contains("目錄") && msg.contains("沒有記進 index"), msg)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("sources/index.jsonl").path),
                       "拒絕時不寫 index")
    }

    func testDoctorReportsOccupantProblemsAndTheAgeOfStrayTemporaryFiles() throws {
        // 一個位址被目錄佔住
        let held = Data("held".utf8)
        try FileManager.default.createDirectory(at: address(digest(held)), withIntermediateDirectories: true)
        // 一個剛寫的暫存檔（可能正在進行）
        let d = "sha256:" + String(repeating: "cd", count: 32)
        let name = LibraryStore.temporaryBlobName(digest: d, token: UUID().uuidString)
        let shard = root.appendingPathComponent("sources/cd")
        try FileManager.default.createDirectory(at: shard, withIntermediateDirectories: true)
        try Data(repeating: 1, count: 321).write(to: shard.appendingPathComponent(name))

        let sources = try XCTUnwrap(try json(try service.doctor())["sources"] as? [String: Any])
        let stray = try XCTUnwrap(sources["strayTemporaryFiles"] as? [[String: Any]])
        XCTAssertEqual(stray.count, 1)
        XCTAssertEqual(stray.first?["path"] as? String, "sources/cd/\(name)")
        XCTAssertEqual(stray.first?["bytes"] as? Int, 321)
        XCTAssertLessThan(try XCTUnwrap(stray.first?["ageSeconds"] as? Int), 600)
        XCTAssertEqual(stray.first?["possiblyInProgress"] as? Bool, true, "一小時內還在動：可能正在進行")
        XCTAssertEqual(sources["strayTemporaryFilesTotal"] as? Int, 1)
        let problems = try XCTUnwrap(sources["occupantProblems"] as? [[String: Any]])
        XCTAssertEqual(problems.first?["kind"] as? String, "notRegularFile")
        XCTAssertEqual(problems.first?["occupant"] as? String, "目錄")
        XCTAssertEqual(problems.first?["path"] as? String, LibraryStore.sourceRelativePath(digest: digest(held)))
        XCTAssertEqual(sources["occupantProblemsTotal"] as? Int, 1)

        // 兩小時沒動：不再是「可能正在進行」
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSinceNow: -7_200)],
                                              ofItemAtPath: shard.appendingPathComponent(name).path)
        let later = try XCTUnwrap(try json(try service.doctor())["sources"] as? [String: Any])
        let old = try XCTUnwrap((later["strayTemporaryFiles"] as? [[String: Any]])?.first)
        XCTAssertEqual(old["possiblyInProgress"] as? Bool, false)
        XCTAssertGreaterThanOrEqual(try XCTUnwrap(old["ageSeconds"] as? Int), 7_000)

        // b29 V5 LOW 10、15：修改時間在未來（時鐘被往回撥、備份還原）——ageSeconds 是 null，possiblyInProgress 是 true（判不出，不要刪）。
        // 先前是 false：疑問被讀成「可以刪」。負控：改回 `!isStale()`，這一段紅。
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSinceNow: 3 * 365 * 86_400)],
                                              ofItemAtPath: shard.appendingPathComponent(name).path)
        let future = try XCTUnwrap((try XCTUnwrap(try json(try service.doctor())["sources"] as? [String: Any])["strayTemporaryFiles"]
                                    as? [[String: Any]])?.first)
        XCTAssertTrue(future["ageSeconds"] is NSNull, "\(future)")
        XCTAssertEqual(future["possiblyInProgress"] as? Bool, true)
    }

    /// b26 F6 LOW 17：`akashic_doctor` 的 `sources{}` 在 `ToolPayloadNestedPaths` 之外（使用者裁決 (a)：表外不守），所以守衛看不到這一層的鍵——
    /// 說明拿掉 `occupantProblems`、`storedBytes` 之類，`ToolPayloadKeyGuardTests` 全綠。這一支釘住它：造出 `sources` 的**每一種**問題，
    /// 取 payload 的全部鍵（`sources` 本身、兩個陣列的元素），逐一要求它們出現在說明的 `sources（…）` 那一段裡。
    /// 負控：從說明拿掉 `storedBytes／indexedBytes`（或整段 `sources（…）`），這一支紅。
    func testTheDoctorDescriptionNamesEveryKeyOfTheSourcesPayload() throws {
        let store = LibraryStore(root: root)
        // sizeMismatch：存一份、之後截短（index 記著原本的大小）
        let truncated = try XCTUnwrap(try storeSource(Data(repeating: 7, count: 4_096))["digest"] as? String)
        try Data(repeating: 7, count: 100).write(to: address(truncated))
        // notRegularFile：位址被目錄佔住
        let held = Data("held".utf8)
        try FileManager.default.createDirectory(at: address(digest(held)), withIntermediateDirectories: true)
        // 孤兒 blob：位址上有普通檔、index 沒有條目
        let orphan = Data("orphan blob".utf8)
        try FileManager.default.createDirectory(at: address(digest(orphan)).deletingLastPathComponent(), withIntermediateDirectories: true)
        try orphan.write(to: address(digest(orphan)))
        // 暫存檔
        let d = "sha256:" + String(repeating: "cd", count: 32)
        let name = LibraryStore.temporaryBlobName(digest: d, token: UUID().uuidString)
        let tmpShard = root.appendingPathComponent("sources/cd")
        try FileManager.default.createDirectory(at: tmpShard, withIntermediateDirectories: true)
        try Data(repeating: 1, count: 12).write(to: tmpShard.appendingPathComponent(name))
        // 懸空條目與壞行：直接 append index（`storeSource` 在有壞行時拒寫，所以放在最後）
        let missing = digest(Data("indexed but gone".utf8))
        let handle = try FileHandle(forWritingTo: store.sourceIndexURL)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data("{\"content\": \"\(missing)\", \"bytes\": 16}\nnot json at all\n".utf8))
        try handle.close()
        // 讀不到的分片目錄
        let locked = root.appendingPathComponent("sources/ee")
        try FileManager.default.createDirectory(at: locked, withIntermediateDirectories: true)
        XCTAssertEqual(chmod(locked.path, 0o000), 0)
        defer { _ = chmod(locked.path, 0o755) }

        let sources = try XCTUnwrap(try json(try service.doctor())["sources"] as? [String: Any])
        func elementKeys(_ k: String) -> Set<String> {
            ((sources[k] as? [[String: Any]]) ?? []).reduce(into: Set<String>()) { $0.formUnion($1.keys) }
        }
        XCTAssertEqual(Set(sources.keys), ["orphanBlobs", "danglingIndexEntries", "malformedIndexLines", "unreadableShards",
                                           "strayTemporaryFiles", "strayTemporaryFilesTotal", "occupantProblems", "occupantProblemsTotal"],
                       "新增或改名了 sources 的鍵——說明要跟上，這一支的清單也要")
        XCTAssertEqual(elementKeys("occupantProblems"), ["path", "kind", "occupant", "storedBytes", "indexedBytes"])
        XCTAssertEqual(elementKeys("strayTemporaryFiles"), ["path", "bytes", "ageSeconds", "possiblyInProgress"])
        let kinds = Set(((sources["occupantProblems"] as? [[String: Any]]) ?? []).compactMap { $0["kind"] as? String })
        XCTAssertEqual(kinds, ["notRegularFile", "sizeMismatch"])

        let text = try XCTUnwrap(try ToolManifest.load()["akashic_doctor"]).text
        let span = try XCTUnwrap(Self.parenthesizedSpan(in: text, after: "sources（"), "說明裡要有 sources（…）那一段")
        let everyKey = Set(sources.keys).union(elementKeys("occupantProblems")).union(elementKeys("strayTemporaryFiles")).union(kinds)
        // 沒有逐一寫出的鍵：兩個 `*Total` 以速記 `*Total` 涵蓋。四個舊鍵（`orphanBlobs` 等，R2 之前就沒有說明）b26 F6 以位元組預算為由
        // 不寫；預算整合後是 60,000，那個理由不再成立，b29 V5 起寫進說明、在這裡沒有豁免。逐一列出，不留「差不多」。
        let shorthand: Set<String> = ["occupantProblemsTotal", "strayTemporaryFilesTotal"]
        XCTAssertTrue(span.contains("*Total"), "兩個 Total 以 *Total 速記涵蓋：\(span)")
        for key in everyKey.subtracting(shorthand).sorted() {
            XCTAssertTrue(mentionsIdentifier(span, key), "akashic_doctor 的 sources（…）說明沒有寫 \(key)：\(span)")
        }
        // b31 W5 LOW 14：四個舊鍵是不截的完整陣列、沒有 *Total——上限那一句只說後兩列（occupantProblems、strayTemporaryFiles 排在四個舊鍵之後）。
        // 先前寫「各列 20 則」，四個舊鍵補在同一個括號的開頭之後，讀起來涵蓋六列。
        for legacy in ["orphanBlobs", "danglingIndexEntries", "malformedIndexLines", "unreadableShards"] {
            XCTAssertNil(sources[legacy + "Total"], "\(legacy) 不截，沒有 Total")
        }
        XCTAssertTrue(span.contains("後兩列各 20 則"), span)
        XCTAssertFalse(span.contains("；各列 20 則"), span)
        let order = ["unreadableShards", "occupantProblems[]", "strayTemporaryFiles[]", "後兩列各 20 則"].compactMap { span.range(of: $0)?.lowerBound }
        XCTAssertEqual(order.count, 4, span)
        XCTAssertEqual(order, order.sorted(), "「後兩列」要指 occupantProblems 與 strayTemporaryFiles：\(span)")
        // b31 W5 LOW 3、15：判不出時不斷言是中斷留下的——說明不寫「中斷存檔的暫存檔」
        XCTAssertFalse(span.contains("中斷存檔"), span)
    }

    /// `text` 裡 `marker` 之後、與它的開括號配對的那一段（含巢狀的全形與半形括號）。
    private static func parenthesizedSpan(in text: String, after marker: String) -> String? {
        guard let r = text.range(of: marker) else { return nil }
        var depth = 1
        var i = r.upperBound
        while i < text.endIndex {
            let c = text[i]
            if c == "（" || c == "(" { depth += 1 }
            if c == "）" || c == ")" { depth -= 1; if depth == 0 { return String(text[r.upperBound..<i]) } }
            i = text.index(after: i)
        }
        return nil
    }

    /// 第 4 則：截短的 blob 不能宣告為副本（先前照連、回 sourcesAdded）。
    func testAddSourceRefusesATruncatedBlob() throws {
        let store = LibraryStore(root: root)
        try store.writeEntry(Entry(id: UUID(), citekey: "x2026y", type: .periodicalArticle, title: "T"))
        let data = Data(repeating: 9, count: 4_096)
        let d = try XCTUnwrap(try storeSource(data)["digest"] as? String)
        try Data(repeating: 9, count: 100).write(to: address(d))
        XCTAssertThrowsError(try service.addEntrySources(citekey: "x2026y", digests: [d], dryRun: true, sourcesLimit: nil)) { e in
            let msg = (e as? LocalizedError)?.errorDescription ?? "\(e)"
            XCTAssertTrue(msg.contains("100 bytes") && msg.contains("4096 bytes") && msg.contains("零寫入"), msg)
        }
    }
}
