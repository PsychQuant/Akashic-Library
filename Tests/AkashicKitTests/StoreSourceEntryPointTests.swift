import XCTest
@testable import AkashicCore
@testable import AkashicMCPKit
@testable import AkashicStoreIO

/// `storeSource` 的使用者入口（#264）。
///
/// `SourceStore.storeSource` 的寫入面防護在 #224 就完成了，但**全樹零 production
/// 呼叫端**——實測 `grep -rn storeSource Sources/` 只命中宣告本身。這批測試釘住的是
/// **入口的契約**，不是那個函式的行為（後者已有 23 個既有測試）。
final class StoreSourceEntryPointTests: XCTestCase {
    var root: URL!
    var service: AkashicService!
    var payloadFile: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("akashic-storesource-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        // `sources/` 必須被 git 忽略，否則 SourceStore 的 fail-closed 閘會拒寫
        // （`replace-endnote-and-zotero`：那道閘是承重的，測試不繞過它）。
        GitFixture.initRepo(root)
        try "sources/\n".write(to: root.appendingPathComponent(".gitignore"),
                               atomically: true, encoding: .utf8)
        GitFixture.commitAll(root)
        try LibraryStore(root: root).ensureLayout()
        service = AkashicService(root: root)

        payloadFile = root.appendingPathComponent("payload.txt")
        try "the bytes of a source document\n".write(to: payloadFile,
                                                    atomically: true, encoding: .utf8)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func store(note: String?) throws -> [String: Any] {
        let json = try service.storeSource(
            path: payloadFile.path, mediaType: "text/plain", retrieved: "2026-08-19",
            origin: "https://example.org/doc", acquisition: "browser-download", note: note)
        return (try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any]) ?? [:]
    }

    /// 首次存入：回 digest、報告已建 index 條目、報告排除已驗證。
    func testFirstStoreReportsDigestAndIndexEntryCreated() throws {
        let d = try store(note: "first")
        XCTAssertTrue((d["digest"] as? String)?.hasPrefix("sha256:") ?? false,
                      "digest 必須是 sha256 形式：\(d["digest"] ?? "nil")")
        XCTAssertEqual(d["indexEntryCreated"] as? Bool, true)
        XCTAssertEqual(d["exclusionVerified"] as? Bool, true,
                       "sources/ 已在 .gitignore，排除應驗證通過")
        XCTAssertNil(d["discardedProvenance"], "首次存入沒有丟棄任何敘述")
    }

    /// **冪等早退時，這次交來卻沒被寫入的敘述必須可見**。
    ///
    /// 依 `lossless-intake` 執行細節 3：靜默是最糟的形式——它讓「早已記過」與
    /// 「你這份敘述沒被寫入」變成同一個觀察，而那兩件事事後完全無法區分。
    ///
    /// 回的必須是**這次交來**的內容，不是既有條目的——後者無法讓呼叫端分辨兩者。
    func testResubmitSurfacesDiscardedProvenance() throws {
        _ = try store(note: "first description")
        let second = try store(note: "second description")

        XCTAssertEqual(second["indexEntryCreated"] as? Bool, false,
                       "同 digest 不得重複建 index 條目")
        let discarded = second["discardedProvenance"] as? [String: Any]
        XCTAssertNotNil(discarded, "冪等早退必須回報被丟棄的敘述")
        XCTAssertEqual(discarded?["note"] as? String, "second description",
                       "回的必須是**這次**交來的敘述，不是既有條目的")
    }

    /// 必填欄位為空時**具名**拒絕——「參數不足」不告訴呼叫端該補哪個。
    func testEmptyRequiredFieldIsRefusedByName() throws {
        let cases: [(String, () throws -> String)] = [
            ("mediaType", { try self.service.storeSource(
                path: self.payloadFile.path, mediaType: "  ", retrieved: "2026-08-19",
                origin: "o", acquisition: "a") }),
            ("retrieved", { try self.service.storeSource(
                path: self.payloadFile.path, mediaType: "text/plain", retrieved: "",
                origin: "o", acquisition: "a") }),
            ("origin", { try self.service.storeSource(
                path: self.payloadFile.path, mediaType: "text/plain", retrieved: "2026-08-19",
                origin: "", acquisition: "a") }),
            ("acquisition", { try self.service.storeSource(
                path: self.payloadFile.path, mediaType: "text/plain", retrieved: "2026-08-19",
                origin: "o", acquisition: " ") }),
        ]
        for (field, call) in cases {
            XCTAssertThrowsError(try call(), field) { error in
                let msg = (error as? LocalizedError)?.errorDescription ?? "\(error)"
                XCTAssertTrue(msg.contains(field),
                              "訊息必須具名欄位「\(field)」，實得：\(msg)")
            }
        }
    }

    /// 路徑讀不到時拒絕，訊息含路徑（讓使用者知道是哪一個檔）。
    func testUnreadablePathIsRefused() throws {
        XCTAssertThrowsError(try service.storeSource(
            path: root.appendingPathComponent("no-such-file.bin").path,
            mediaType: "text/plain", retrieved: "2026-08-19",
            origin: "o", acquisition: "a")) { error in
            guard case ServiceError.invalid = error else {
                return XCTFail("錯誤類型應為 invalid，實得 \(error)")
            }
            let msg = (error as? LocalizedError)?.errorDescription ?? ""
            XCTAssertTrue(msg.contains("no-such-file.bin"), "訊息應含路徑：\(msg)")
        }
    }

    /// #703：超過 256 MB 的檔整個拒絕、不截斷、零寫入，訊息說出是哪一個檔、多大、上限多少（CLI 與 MCP 同一個函式）。
    /// sparse 檔：大小以 stat 判斷，不讀、不佔磁碟。
    func testAFileOverTheCapIsRefusedByNameWithItsSize() throws {
        let huge = root.appendingPathComponent("huge-scan.pdf")
        XCTAssertTrue(FileManager.default.createFile(atPath: huge.path, contents: nil))
        let w = try FileHandle(forWritingTo: huge)
        try w.truncate(atOffset: UInt64(LibraryStore.maxSourceBytes + 1))
        try w.close()
        XCTAssertThrowsError(try service.storeSource(
            path: huge.path, mediaType: "application/pdf", retrieved: "2026-09-30",
            origin: "o", acquisition: "scan")) { error in
            guard case ServiceError.invalid = error else { return XCTFail("錯誤類型應為 invalid，實得 \(error)") }
            let msg = (error as? LocalizedError)?.errorDescription ?? ""
            XCTAssertTrue(msg.contains("huge-scan.pdf"), "要說出是哪一個檔：\(msg)")
            XCTAssertTrue(msg.contains("\(LibraryStore.maxSourceBytes + 1)"), "要說出檔案大小：\(msg)")
            XCTAssertTrue(msg.contains("256 MB"), "要說出上限：\(msg)")
        }
        let shards = ((try? FileManager.default.contentsOfDirectory(
            atPath: root.appendingPathComponent("sources").path)) ?? []).filter { $0.count == 2 }
        XCTAssertEqual(shards, [], "不存")
    }

    /// 入口的上限可注入（測試接縫）：恰好等於上限的收、多一個 byte 的拒絕——拒絕時訊息說出兩個數字。
    func testTheEntryPointCapIsInclusive() throws {
        let path = payloadFile.path
        let size = try XCTUnwrap(FileManager.default.attributesOfItem(atPath: path)[.size] as? Int)
        XCTAssertNoThrow(try service.storeSource(path: path, mediaType: "text/plain", retrieved: "2026-09-30",
                                                 origin: "o", acquisition: "a", limit: size))
        XCTAssertThrowsError(try service.storeSource(path: path, mediaType: "text/plain", retrieved: "2026-09-30",
                                                     origin: "o", acquisition: "a", limit: size - 1)) { error in
            let msg = (error as? LocalizedError)?.errorDescription ?? ""
            XCTAssertTrue(msg.contains("\(size) bytes") && msg.contains("\(size - 1) bytes"), msg)
        }
    }

    /// 目錄與 FIFO 不是一份內容：拒絕、訊息含路徑；FIFO 不能讓開檔卡住（以前 `Data(contentsOf:)` 會等一個寫入者）。
    func testDirectoriesAndFifosAreRefusedWithoutBlocking() throws {
        let dir = root.appendingPathComponent("a-directory")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let fifo = root.appendingPathComponent("a-fifo")
        XCTAssertEqual(mkfifo(fifo.path, 0o644), 0)
        for url in [dir, fifo] {
            XCTAssertThrowsError(try service.storeSource(path: url.path, mediaType: "text/plain", retrieved: "2026-09-30",
                                                         origin: "o", acquisition: "a")) { error in
                let msg = (error as? LocalizedError)?.errorDescription ?? ""
                XCTAssertTrue(msg.contains(url.lastPathComponent), msg)
            }
        }
    }

    /// 相同位元組經**兩次呼叫**得到相同 digest——兩面同源的前提。
    ///
    /// 這條不驗「MCP 與 CLI 產出相同」（那需要跑兩個 binary），而是驗它們共用的
    /// service 對相同輸入是決定性的——兩面既然都只呼叫它，決定性就是同源的充分條件。
    func testSameBytesYieldSameDigestAcrossCalls() throws {
        let first = try store(note: "a")
        let second = try store(note: "b")
        XCTAssertEqual(first["digest"] as? String, second["digest"] as? String)
    }
}
