import XCTest
import CryptoKit
import Foundation
import Darwin
@testable import AkashicCore
@testable import AkashicStoreIO

/// #703 的「放上位址」與「位址上已有東西」（R1 verify 之後；R2 verify 第 1、4、5、6、20、21、27 則）：
///
/// 1. 三條放置路都**不覆寫**：`RENAME_EXCL` → `link(2)` → 以 `O_EXCL` 建立目的檔後逐塊複製、同步、讀回驗證。R1 的第三條是 `lstat` 之後一般
///    `rename(2)`，兩步之間出現的檔會被取代（R2 verify 第 1 則）。
/// 2. 位址上已有東西時只有**大小相同的普通檔**算「已經在了」；目錄、symlink（含懸空的）、大小不同的普通檔具名拒絕、不寫 index
///    （R2 verify 第 4、5、6 則：R2 之前回「沒寫、但成功」並寫 index）。
/// 3. 存檔進行中登記的檔，訊號來時刪掉（R2 verify 第 27 則）；暫存檔 token 要是 UUID（第 20 則）。
final class SourcePlacementTests: XCTestCase {
    var root: URL!
    var store: LibraryStore!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("akashic-placement-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root.appendingPathComponent("entities"), withIntermediateDirectories: true)
        try StoreVersion.write(root: root, format: StoreVersion.supported)
        store = LibraryStore(root: root)
        GitFixture.initRepo(root)
        try store.ensureLayout()
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    private func prov() -> LibraryStore.SourceProvenance {
        LibraryStore.SourceProvenance(mediaType: "application/pdf", retrieved: "2026-10-01", origin: "unit-test", acquisition: "file")
    }
    private func oneShot(_ data: Data) -> String { "sha256:" + SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
    private func blobURL(_ digest: String) -> URL {
        let hex = String(digest.dropFirst("sha256:".count))
        return root.appendingPathComponent("sources/\(hex.prefix(2))/\(hex.dropFirst(2))")
    }
    private func sourcesResidue() -> [String] {
        let dir = root.appendingPathComponent("sources")
        return ((try? FileManager.default.subpathsOfDirectory(atPath: dir.path)) ?? []).filter { $0 != "index.jsonl" }.sorted()
    }
    private func temporaryResidue() -> [String] { sourcesResidue().filter { $0.contains(".incoming-") } }
    private func indexLineCount() -> Int {
        let text = (try? String(contentsOf: root.appendingPathComponent("sources/index.jsonl"), encoding: .utf8)) ?? ""
        return text.split(separator: "\n").count
    }
    private func message(_ e: Error) -> String { (e as? LocalizedError)?.errorDescription ?? "\(e)" }

    /// 真的系統呼叫，只把指定的那幾步換掉。`create`／`write` 包住系統的那一步（可以在它之前做事、或改它的結果）。
    private func placement(renameExclusive: Int32? = nil, hardLink: Int32? = nil,
                           beforeHardLink: (@Sendable (String) -> Void)? = nil,
                           create: (@Sendable (String, (String) -> Int32) -> Int32)? = nil,
                           write: (@Sendable (Int32, Data, (Int32, Data) -> Int32) -> Int32)? = nil,
                           sync: (@Sendable (Int32, (Int32) -> Int32) -> Int32)? = nil) -> LibraryStore.BlobPlacement {
        let system = LibraryStore.BlobPlacement.system
        return LibraryStore.BlobPlacement(
            renameExclusive: { from, to in renameExclusive ?? system.renameExclusive(from, to) },
            hardLink: { from, to in beforeHardLink?(to); return hardLink ?? system.hardLink(from, to) },
            createExclusive: { path in create.map { $0(path, system.createExclusive) } ?? system.createExclusive(path) },
            writeChunk: { fd, chunk in write.map { $0(fd, chunk, system.writeChunk) } ?? system.writeChunk(fd, chunk) },
            sync: { fd in sync.map { $0(fd, system.sync) } ?? system.sync(fd) })
    }
    /// exFAT／FAT32 的形狀（2026-09-30 磁碟映像實測）：前兩條都「不支援」，只剩第三條
    private func fatLike(create: (@Sendable (String, (String) -> Int32) -> Int32)? = nil,
                         write: (@Sendable (Int32, Data, (Int32, Data) -> Int32) -> Int32)? = nil,
                         sync: (@Sendable (Int32, (Int32) -> Int32) -> Int32)? = nil) -> LibraryStore.BlobPlacement {
        placement(renameExclusive: ENOTSUP, hardLink: ENOTSUP, create: create, write: write, sync: sync)
    }
    private func store(_ data: Data, placement: LibraryStore.BlobPlacement) throws -> LibraryStore.SourceIntake {
        var src = ScriptedChunks(passes: [data])
        return try store.storeSource(chunks: &src, provenance: prov(), expectedDigest: nil,
                                     limit: LibraryStore.maxSourceBytes, placement: placement)
    }

    // MARK: 1. 三條放置路

    /// `RENAME_EXCL` 回 ENOTSUP——退到 `link(2)`，位元組照樣落地、暫存名刪掉。
    func testRenameExclUnsupportedFallsBackToAHardLink() throws {
        let data = Data("fallback via link".utf8)
        guard case .stored(let r) = try store(data, placement: placement(renameExclusive: ENOTSUP)) else { return XCTFail() }
        XCTAssertTrue(r.bytesWritten)
        XCTAssertEqual(try Data(contentsOf: blobURL(r.digest)), data)
        XCTAssertEqual(temporaryResidue(), [], "link 之後暫存名要刪掉")
        XCTAssertEqual(indexLineCount(), 1)
    }

    /// link 也不支援：排他建立目的檔、逐塊複製、讀回驗證，位元組落地、暫存名刪掉、登記清空。
    func testLinkAlsoUnsupportedFallsBackToAnExclusiveCopy() throws {
        let data = Data((0..<(3 * LibraryStore.sourceChunkBytes + 17)).map { UInt8(truncatingIfNeeded: $0 &* 7) })
        guard case .stored(let r) = try store(data, placement: fatLike()) else { return XCTFail() }
        XCTAssertTrue(r.bytesWritten)
        XCTAssertEqual(try Data(contentsOf: blobURL(r.digest)), data, "跨塊邊界逐位元組相同")
        XCTAssertEqual(temporaryResidue(), [])
        XCTAssertEqual(indexLineCount(), 1)
        XCTAssertEqual(InFlightSourceFiles.count, 0, "放完之後不再登記")
    }

    /// **R2 verify 第 1 則**：第三條路的窗——在最後那一步之前別人在位址上放了一份**不同**的檔。它必須一個位元組都不變；這一份具名拒絕
    /// （大小不同）、不寫 index、不留暫存。R1 的 `lstat` → `rename(2)` 會把它取代（負控：把第三條改回一般 rename，這一支紅）。
    func testAFileThatAppearsInTheLastStepWindowSurvivesUntouched() throws {
        let data = Data("the content being stored".utf8)
        let theirs = Data("someone else's different file".utf8)
        let url = blobURL(oneShot(data))
        let early = fatLike(create: { path, system in
            FileManager.default.createFile(atPath: path, contents: theirs)
            return system(path)
        })
        XCTAssertThrowsError(try store(data, placement: early)) { e in
            XCTAssertTrue(message(e).contains("不覆寫") && message(e).contains("\(theirs.count) bytes"), message(e))
        }
        XCTAssertEqual(try Data(contentsOf: url), theirs, "窗內出現的檔一個位元組都不動")
        XCTAssertEqual(temporaryResidue(), [])
        XCTAssertEqual(indexLineCount(), 0)
    }

    /// 排他建立回 `EEXIST`、位址上是同一份內容（同時有另一個存檔先放了）：當成「已經在了」，不重寫、照樣記 index。
    func testExclusiveCreateEEXISTWithTheSameContentIsAlreadyThere() throws {
        let data = Data("two processes, one digest".utf8)
        let url = blobURL(oneShot(data))
        let raced = fatLike(create: { path, _ in
            FileManager.default.createFile(atPath: path, contents: data)
            return -EEXIST
        })
        guard case .stored(let r) = try store(data, placement: raced) else { return XCTFail() }
        XCTAssertFalse(r.bytesWritten)
        XCTAssertEqual(try Data(contentsOf: url), data)
        XCTAssertEqual(temporaryResidue(), [])
        XCTAssertEqual(indexLineCount(), 1)
    }

    /// 複製到一半寫入失敗：刪掉**這一次建立的**目的檔，同一個分片目錄裡別的檔不動；不留暫存、不寫 index、錯誤說出 errno。
    func testAFailureMidCopyRemovesOnlyTheFileThisCallCreated() throws {
        let data = Data((0..<(2 * LibraryStore.sourceChunkBytes)).map { UInt8(truncatingIfNeeded: $0) })
        let url = blobURL(oneShot(data))
        let neighbour = url.deletingLastPathComponent().appendingPathComponent(String(repeating: "0", count: 62))
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("a neighbouring blob".utf8).write(to: neighbour)
        let writes = PlacementCallCounter()
        let broken = fatLike(write: { fd, chunk, system in
            guard writes.next() == 0 else { return EIO }   // 第一塊寫進去，第二塊失敗
            return system(fd, chunk)
        })
        XCTAssertThrowsError(try store(data, placement: broken)) { e in
            XCTAssertTrue(message(e).contains("errno \(EIO)") && message(e).contains("沒有存"), message(e))
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path), "寫到一半的目的檔要刪掉")
        XCTAssertEqual(try Data(contentsOf: neighbour), Data("a neighbouring blob".utf8), "只刪自己建立的那一個")
        XCTAssertEqual(temporaryResidue(), [])
        XCTAssertEqual(indexLineCount(), 0)
        XCTAssertEqual(InFlightSourceFiles.count, 0)
    }

    /// 複製期間名字被別人換掉（它取代了我們的檔），接著我們失敗：刪之前比過裝置與 inode，換進來的那一份不動。
    func testWhenOurFileIsReplacedDuringTheCopyTheReplacementSurvives() throws {
        let data = Data("replaced while copying".utf8)
        let url = blobURL(oneShot(data))
        let replacement = root.appendingPathComponent("replacement.bin")
        let swapped = fatLike(write: { fd, chunk, system in
            _ = system(fd, chunk)
            try? Data("REPLACEMENT".utf8).write(to: replacement)
            _ = Darwin.rename(replacement.path, url.path)
            return EIO
        })
        XCTAssertThrowsError(try store(data, placement: swapped))
        XCTAssertEqual(try Data(contentsOf: url), Data("REPLACEMENT".utf8), "名字上已經是別人的檔：不刪")
        XCTAssertEqual(temporaryResidue(), [])
    }

    /// 寫進去的不是暫存檔的內容（裝置或檔案系統出錯）：讀回驗證看得出來，刪掉目的檔、具名擲出。
    func testACorruptedCopyIsCaughtByReadingItBack() throws {
        let data = Data("verify what landed".utf8)
        let url = blobURL(oneShot(data))
        let corrupting = fatLike(write: { fd, chunk, system in
            var bad = chunk
            bad[bad.startIndex] ^= 0xFF
            return system(fd, bad)
        })
        XCTAssertThrowsError(try store(data, placement: corrupting)) { e in
            XCTAssertTrue(message(e).contains("讀回"), message(e))
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        XCTAssertEqual(temporaryResidue(), [])
        XCTAssertEqual(indexLineCount(), 0)
    }

    /// 三條路都走不通：具名擲出（說出不支援排他改名與三個 errno），不留 blob、不留暫存、不寫 index。
    func testWhenEveryPlacementFailsTheErrorNamesTheFileSystemLimitation() throws {
        let data = Data("nowhere to go".utf8)
        XCTAssertThrowsError(try store(data, placement: fatLike(create: { _, _ in -EACCES }))) { e in
            let msg = message(e)
            XCTAssertTrue(msg.contains("不支援排他改名") && msg.contains("errno \(ENOTSUP)") && msg.contains("errno \(EACCES)"), msg)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: blobURL(oneShot(data)).path))
        XCTAssertEqual(temporaryResidue(), [])
        XCTAssertEqual(indexLineCount(), 0)
    }

    /// `RENAME_EXCL` 的其他失敗（不是「不支援」）不退：直接具名擲出，不去試 link。
    func testOtherRenameFailuresDoNotFallBack() throws {
        let data = Data("permission problem".utf8)
        let noLink = placement(renameExclusive: EACCES, beforeHardLink: { _ in XCTFail("不該退到 link") })
        XCTAssertThrowsError(try store(data, placement: noLink)) { e in
            XCTAssertTrue(message(e).contains("RENAME_EXCL") && message(e).contains("errno \(EACCES)"), message(e))
        }
        XCTAssertEqual(temporaryResidue(), [])
    }

    // MARK: 1b. 同步到裝置（R2 verify 第 21 則）

    /// 暫存檔在**放上位址之前**同步到裝置：同步被呼叫時位址上還沒有東西、暫存檔在。負控：拿掉 `placement.sync` 那一呼叫，這一支紅。
    func testTheTemporaryFileIsSyncedBeforeItIsPlaced() throws {
        let data = Data("synced before the name appears".utf8)
        let url = blobURL(oneShot(data))
        let calls = PlacementCallCounter()
        let seen = SyncObservations()
        let watching = placement(sync: { fd, system in
            _ = calls.next()
            seen.record(addressExisted: FileManager.default.fileExists(atPath: url.path),
                        tempExisted: !self.temporaryResidue().isEmpty)
            return system(fd)
        })
        guard case .stored(let r) = try store(data, placement: watching) else { return XCTFail() }
        XCTAssertTrue(r.bytesWritten)
        XCTAssertEqual(seen.observations.count, 1, "RENAME_EXCL 那條路：只有暫存檔同步一次")
        XCTAssertEqual(seen.observations.first?.addressExisted, false, "同步時位址上還沒有東西")
        XCTAssertEqual(seen.observations.first?.tempExisted, true, "同步的是暫存檔")
    }

    /// 同步失敗：不放上位址、不留暫存、不寫 index，錯誤說出 errno。
    func testASyncFailureRefusesAndLeavesNothing() throws {
        let data = Data("the device refuses to sync".utf8)
        let failing = placement(sync: { _, _ in EIO })
        XCTAssertThrowsError(try store(data, placement: failing)) { e in
            XCTAssertTrue(message(e).contains("同步到裝置失敗") && message(e).contains("errno \(EIO)"), message(e))
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: blobURL(oneShot(data)).path))
        XCTAssertEqual(temporaryResidue(), [])
        XCTAssertEqual(indexLineCount(), 0)
    }

    /// 第三條路：目的檔也要同步，失敗就刪掉**這一次建立的**目的檔。
    func testTheExclusiveCopyIsSyncedAndASyncFailureRemovesOnlyOurFile() throws {
        let data = Data("third path sync".utf8)
        let url = blobURL(oneShot(data))
        let seen = SyncObservations()
        let second = PlacementCallCounter()
        let failsOnTheDestination = fatLike(sync: { fd, system in
            let n = second.next()
            seen.record(addressExisted: FileManager.default.fileExists(atPath: url.path), tempExisted: !self.temporaryResidue().isEmpty)
            return n == 0 ? system(fd) : EIO   // 第一次是暫存檔（放行），第二次是目的檔（失敗）
        })
        XCTAssertThrowsError(try store(data, placement: failsOnTheDestination)) { e in
            XCTAssertTrue(message(e).contains("目的檔同步到裝置失敗"), message(e))
        }
        XCTAssertEqual(seen.observations.count, 2, "暫存檔一次、目的檔一次")
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path), "同步失敗的目的檔不留在位址上")
        XCTAssertEqual(temporaryResidue(), [])
        XCTAssertEqual(indexLineCount(), 0)
    }

    // MARK: 2. 位址上已有東西（R2 verify 第 4、5、6 則）

    /// 位址上是**懸空 symlink**：R2 之前回成功、寫 index、位址仍是 symlink（#703 之前的 binary 會以真檔取代它——回歸）。現在具名拒絕、
    /// 不寫 index、symlink 不動。
    func testADanglingSymlinkAtTheAddressIsRefusedByName() throws {
        let data = Data("held by a dangling symlink".utf8)
        let url = blobURL(oneShot(data))
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(atPath: url.path, withDestinationPath: "/nonexistent-\(UUID().uuidString)")
        XCTAssertThrowsError(try store.storeSource(data, provenance: prov())) { e in
            XCTAssertTrue(message(e).contains("symlink") && message(e).contains("沒有記進 index"), message(e))
        }
        XCTAssertEqual(indexLineCount(), 0)
        XCTAssertNotNil(try? FileManager.default.destinationOfSymbolicLink(atPath: url.path), "只拒絕、不動那個位置")
        XCTAssertEqual(try store.checkStoredBlob(digest: oneShot(data), expectedBytes: data.count), .notRegularFile("symlink"))
    }

    /// 位址上是**目錄**：同上。
    func testADirectoryAtTheAddressIsRefusedByName() throws {
        let data = Data("held by a directory".utf8)
        let url = blobURL(oneShot(data))
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        XCTAssertThrowsError(try store.storeSource(data, provenance: prov())) { e in
            XCTAssertTrue(message(e).contains("目錄"), message(e))
        }
        XCTAssertEqual(indexLineCount(), 0)
        let audit = try store.auditSourceIndex()
        XCTAssertEqual(audit.occupantProblems.map(\.kind), [.notRegularFile("目錄")], "doctor 看得到它")
        XCTAssertEqual(audit.orphanBlobs, [], "目錄不是孤兒 blob（只在位址問題報一次）")
    }

    /// `sourcePresence` 與 audit 比對 index 記的大小：被截短的 blob 是 `.sizeMismatch`，不是 `.stored`。
    func testATruncatedBlobIsASizeMismatchForPresenceAndAudit() throws {
        let data = Data(repeating: 7, count: 4_096)
        let receipt = try store.storeSource(data, provenance: prov())
        try Data(repeating: 7, count: 100).write(to: blobURL(receipt.digest))
        XCTAssertEqual(try store.sourcePresence(digests: [receipt.digest])[receipt.digest], .sizeMismatch(stored: 100, indexed: 4_096))
        let audit = try store.auditSourceIndex()
        XCTAssertEqual(audit.occupantProblems.map(\.kind), [.sizeMismatch(stored: 100, indexed: 4_096)])
        XCTAssertEqual(audit.danglingEntries, [])
        XCTAssertEqual(audit.orphanBlobs, [])
        XCTAssertTrue(store.health(from: try store.load()).hasFindings, "要人看一眼")
        // 再存一次正確的內容：具名拒絕、不覆寫
        XCTAssertThrowsError(try store.storeSource(data, provenance: prov()))
        XCTAssertEqual(try Data(contentsOf: blobURL(receipt.digest)).count, 100)
    }

    /// 讀回（`sourceContent`）有界（R2 verify 第 12、23 則）：超過上限以 `lstat` 判、不讀、具名擲出；位址上不是普通檔也具名擲出。
    func testReadingBackIsBoundedAndRefusesANonRegularOccupant() throws {
        let data = Data(repeating: 3, count: 64)
        let receipt = try store.storeSource(data, provenance: prov())
        XCTAssertEqual(try store.sourceContent(digest: receipt.digest, limit: 64), data, "上限本身可以讀")
        XCTAssertThrowsError(try store.sourceContent(digest: receipt.digest, limit: 63)) { e in
            XCTAssertTrue(message(e).contains("超過讀回的上限"), message(e))
        }
        let other = Data("held".utf8)
        try FileManager.default.createDirectory(at: blobURL(oneShot(other)), withIntermediateDirectories: true)
        XCTAssertThrowsError(try store.sourceContent(digest: oneShot(other))) { e in
            XCTAssertTrue(message(e).contains("目錄"), message(e))
        }
    }

    // MARK: 3. token、訊號

    /// 暫存檔 token 要是 UUID（R2 verify 第 20 則）：兩個公開入口在任何讀寫之前擋下，不留任何東西。
    func testANonUUIDTemporaryTokenIsRefusedBeforeAnything() throws {
        let data = Data("token shape".utf8)
        XCTAssertThrowsError(try store.preflightStoreSource(digest: oneShot(data), temporaryToken: "../../escape")) { e in
            XCTAssertTrue(message(e).contains("UUID"), message(e))
        }
        let file = root.appendingPathComponent("in.bin")
        try data.write(to: file)
        let h = try FileHandle(forReadingFrom: file)
        defer { try? h.close() }
        XCTAssertThrowsError(try store.storeSource(contentsOf: h, provenance: prov(), temporaryToken: "not-a-uuid"))
        XCTAssertEqual(sourcesResidue(), [])
        XCTAssertEqual(indexLineCount(), 0)
    }

    /// 訊號來時刪掉登記中的檔（R2 verify 第 27 則）：只刪仍是登記時那個 inode 的。訊號本身在 `SourceSignalCleanupCLITests` 以真 binary 送。
    func testRegisteredFilesAreRemovedOnlyIfTheyAreStillTheSameInode() throws {
        let mine = root.appendingPathComponent("mine.tmp")
        let swapped = root.appendingPathComponent("swapped.tmp")
        try Data("mine".utf8).write(to: mine)
        try Data("will be swapped".utf8).write(to: swapped)
        func register(_ url: URL) -> Int {
            var st = stat()
            XCTAssertEqual(lstat(url.path, &st), 0)
            return InFlightSourceFiles.register(path: url.path, device: st.st_dev, inode: st.st_ino)
        }
        let a = register(mine)
        let b = register(swapped)
        defer { InFlightSourceFiles.unregister(a); InFlightSourceFiles.unregister(b) }
        // 換掉 swapped 的 inode（別人以同一個名字放了另一個檔）
        let other = root.appendingPathComponent("other.tmp")
        try Data("someone else".utf8).write(to: other)
        XCTAssertEqual(Darwin.rename(other.path, swapped.path), 0)
        XCTAssertEqual(InFlightSourceFiles.removeRegistered(), 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: mine.path))
        XCTAssertEqual(try Data(contentsOf: swapped), Data("someone else".utf8), "不是登記的那個 inode：不刪")
    }
}

/// 同步接縫被呼叫時看到的狀態。
final class SyncObservations: @unchecked Sendable {
    struct Observation { let addressExisted: Bool; let tempExisted: Bool }
    private let lock = NSLock()
    private var all: [Observation] = []
    var observations: [Observation] { lock.lock(); defer { lock.unlock() }; return all }
    func record(addressExisted: Bool, tempExisted: Bool) {
        lock.lock(); defer { lock.unlock() }
        all.append(Observation(addressExisted: addressExisted, tempExisted: tempExisted))
    }
}

/// 測試接縫裡用的計數器（`@Sendable` 閉包不能捕捉可變的區域變數）。
final class PlacementCallCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var n = 0
    /// 回目前的值，再加一。
    func next() -> Int { lock.lock(); defer { lock.unlock() }; defer { n += 1 }; return n }
}
