import XCTest
import CryptoKit
import Foundation
import Darwin
@testable import AkashicCore
@testable import AkashicStoreIO

/// #703 的「放上位址」與「位址上已有東西」（R1 verify 之後；R2 verify 第 1、4、5、6、20、21、27 則；b26 F6 之後）：
///
/// 1. 兩條放置路都**不覆寫**：`RENAME_EXCL` → `link(2)`。兩個都不行（exFAT、FAT32）→ **每一次存檔都具名拒絕、零寫入**
///    （使用者 2026-10-02 裁決；先前的第三條路——以 `O_EXCL` 建立目的檔後逐塊複製——在 exFAT 上靠建立當下的 inode 認自己的檔，清理全部失效）。
///    拒絕在建立任何檔案**之前**由磁碟區的能力旗標擋下；磁碟區沒有回報時，寫入之前、任何分支之前（含「位址上已經有同一份」）在分片目錄裡
///    實際放一次空的探測檔（b29 V5），做不到就同一句拒絕、零寫入。
/// 2. 位址上已有東西時只有**大小相同的普通檔**算「已經在了」；目錄、symlink（含懸空的）、大小不同的普通檔具名拒絕、不寫 index
///    （R2 verify 第 4、5、6 則：R2 之前回「沒寫、但成功」並寫 index）。位址上的名字只經原子動作出現，所以讀到的永遠是完整內容。
/// 3. 存檔進行中登記的暫存檔，訊號來時刪掉（R2 verify 第 27 則）——以名字認、不比 inode；暫存檔 token 要是 UUID（第 20 則）。
/// 4. `syncFile`：`F_FULLFSYNC` 的真錯誤不被後面的 `fsync` 成功蓋掉（b26 F6）；「不支援」是封閉的六個 errno（b29 V5）。
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

    /// 真的系統呼叫，只把指定的那幾步換掉。`beforeRename` 在 `renamex_np` 之前被呼叫（看得到位址與暫存檔的狀態）。
    private func placement(renameExclusive: Int32? = nil, hardLink: Int32? = nil,
                           beforeRename: (@Sendable (String, String) -> Void)? = nil,
                           beforeHardLink: (@Sendable (String) -> Void)? = nil,
                           sync: (@Sendable (Int32, (Int32) -> Int32) -> Int32)? = nil,
                           volume: (@Sendable (String) -> Bool?)? = nil) -> LibraryStore.BlobPlacement {
        let system = LibraryStore.BlobPlacement.system
        return LibraryStore.BlobPlacement(
            renameExclusive: { from, to in beforeRename?(from, to); return renameExclusive ?? system.renameExclusive(from, to) },
            hardLink: { from, to in beforeHardLink?(to); return hardLink ?? system.hardLink(from, to) },
            sync: { fd in sync.map { $0(fd, system.sync) } ?? system.sync(fd) },
            volumeSupportsExclusivePlacement: { path in volume.map { $0(path) } ?? system.volumeSupportsExclusivePlacement(path) })
    }
    /// exFAT／FAT32 的形狀（2026-09-30 磁碟映像實測）：兩條原子放置都「不支援」，磁碟區的能力旗標也這麼說（`volumeReports: false`；
    /// 實測 exFAT 的 `VOL_CAP_FMT_HARDLINKS` 與 `VOL_CAP_INT_RENAME_EXCL` 都是有效旗標、值為 0）。`volumeReports: nil`＝磁碟區沒有回報能力，
    /// 要走到實際的呼叫才發現不支援。
    private func fatLike(volumeReports: Bool? = false,
                         sync: (@Sendable (Int32, (Int32) -> Int32) -> Int32)? = nil) -> LibraryStore.BlobPlacement {
        placement(renameExclusive: ENOTSUP, hardLink: ENOTSUP, sync: sync, volume: { _ in volumeReports })
    }
    private func store(_ data: Data, placement: LibraryStore.BlobPlacement) throws -> LibraryStore.SourceIntake {
        var src = ScriptedChunks(passes: [data])
        return try store.storeSource(chunks: &src, provenance: prov(), expectedDigest: nil,
                                     limit: LibraryStore.maxSourceBytes, placement: placement)
    }

    // MARK: 1. 兩條放置路與拒絕

    /// `RENAME_EXCL` 回 ENOTSUP——退到 `link(2)`，位元組照樣落地、暫存名刪掉。
    func testRenameExclUnsupportedFallsBackToAHardLink() throws {
        let data = Data("fallback via link".utf8)
        guard case .stored(let r) = try store(data, placement: placement(renameExclusive: ENOTSUP)) else { return XCTFail() }
        XCTAssertTrue(r.bytesWritten)
        XCTAssertEqual(try Data(contentsOf: blobURL(r.digest)), data)
        XCTAssertEqual(temporaryResidue(), [], "link 之後暫存名要刪掉")
        XCTAssertEqual(indexLineCount(), 1)
    }

    /// **b26 F6（使用者 2026-10-02 裁決）**：磁碟區做不到不覆寫的原子放置（exFAT、FAT32）→ 每一次存檔都具名拒絕、**零寫入**——分片目錄、暫存檔、
    /// blob、index 一個都沒有，兩個放置呼叫一次都沒被呼叫。訊息說要把 store 放在 APFS 或 HFS+。
    /// 負控：拿掉 `storeSource` 的 `assertSourcesVolumeCanPlace`，這一支紅（暫存檔會先被建出來、分片目錄會被建出來）。
    func testAVolumeThatCannotPlaceExclusivelyRefusesWithZeroWrites() throws {
        let data = Data("nothing may be written on this volume".utf8)
        let untouched = placement(renameExclusive: ENOTSUP, hardLink: ENOTSUP,
                                  beforeRename: { _, _ in XCTFail("磁碟區已回報做不到：不該走到放置") },
                                  beforeHardLink: { _ in XCTFail("磁碟區已回報做不到：不該走到放置") },
                                  volume: { _ in false })
        XCTAssertThrowsError(try store(data, placement: untouched)) { e in
            let msg = message(e)
            XCTAssertTrue(msg.contains("APFS") && msg.contains("HFS+") && msg.contains("沒有存任何東西"), msg)
        }
        XCTAssertEqual(sourcesResidue(), [], "連分片目錄與暫存檔都不建")
        XCTAssertEqual(indexLineCount(), 0)
    }

    /// 「每一次存檔」：位址上已經有同一份內容（先前在支援的磁碟區上存的）也一樣拒絕——不因為「已經在了」就放行。
    func testEveryStoreIsRefusedOnSuchAVolumeEvenWhenTheContentIsAlreadyThere() throws {
        let data = Data("already stored elsewhere".utf8)
        _ = try store(data, placement: .system)
        XCTAssertThrowsError(try store(data, placement: fatLike())) { e in XCTAssertTrue(message(e).contains("APFS"), message(e)) }
        XCTAssertEqual(indexLineCount(), 1, "拒絕不寫 index")
    }

    /// 批次的前置檢查（`preflightStoreSource`）同一道閘：多筆操作在第一次寫入之前就整批拒絕。
    func testPreflightRefusesWhenTheVolumeCannotPlace() throws {
        let digest = oneShot(Data("batch".utf8))
        XCTAssertNoThrow(try store.preflightStoreSource(digest: digest, temporaryToken: UUID().uuidString, placement: .system))
        XCTAssertThrowsError(try store.preflightStoreSource(digest: digest, temporaryToken: UUID().uuidString, placement: fatLike())) { e in
            XCTAssertTrue(message(e).contains("HFS+"), message(e))
        }
        XCTAssertEqual(sourcesResidue(), [])
    }

    /// 磁碟區沒有回報能力（`nil`）、兩個放置呼叫都回「不支援」：寫入之前在分片目錄裡**實際放一次**（b29 V5 MEDIUM 0）就發現。
    /// 拒絕發生在複製內容之前（同步一次都沒被呼叫）、探測的兩個暫存名都刪掉、這一步建的分片目錄也收回、不寫 index——**零寫入**，訊息與上一支同一句。
    /// 放置呼叫真的被呼叫過（證明這一支走的是「實際呼叫的結果」那條路，不是上面的閘）。
    /// 負控：拿掉 `writeBlob` 的 `assertDirectoryCanPlace`，這一支紅（內容先被複製、同步過，分片目錄留著）。
    func testWhenTheVolumeReportsNothingTheRefusalComesFromTheCallsAndLeavesNothing() throws {
        let data = Data("discovered at placement time".utf8)
        let calls = PlacementCallCounter()
        let syncs = PlacementCallCounter()
        let attempting = placement(renameExclusive: ENOTSUP, hardLink: ENOTSUP,
                                   beforeRename: { _, _ in _ = calls.next() },
                                   sync: { fd, system in _ = syncs.next(); return system(fd) }, volume: { _ in nil })
        XCTAssertThrowsError(try store(data, placement: attempting)) { e in
            let msg = message(e)
            XCTAssertTrue(msg.contains("APFS") && msg.contains("errno \(ENOTSUP)") && msg.contains("沒有存任何東西"), msg)
        }
        XCTAssertEqual(calls.next(), 1, "RENAME_EXCL 被呼叫過一次（探測）")
        XCTAssertEqual(syncs.next(), 0, "拒絕在複製之前：內容沒有被寫進暫存檔、沒有同步")
        XCTAssertFalse(FileManager.default.fileExists(atPath: blobURL(oneShot(data)).path))
        XCTAssertEqual(sourcesResidue(), [], "零寫入：探測的暫存名與這一步建的分片目錄都收回")
        XCTAssertEqual(indexLineCount(), 0)
    }

    /// **b29 V5 MEDIUM 0（Codex 的交叉情境）**：位址上已經有同一份內容（先前在支援的磁碟區上存的），而磁碟區**沒有回報能力旗標**、實際上又做不到。
    /// 先前「已經在了」那一支不經任何放置呼叫就回成功（`bytesWritten:false`），index 缺條目時還補一列——「每一次存檔都拒絕」在這裡不成立。
    /// 現在任何分支之前都實際放一次：同一句具名拒絕、不補 index、位址上的那一份不動。
    /// 負控：拿掉 `writeBlob` 的 `assertDirectoryCanPlace`，這一支紅（回成功、index 多一列）。
    func testExistingContentIsAlsoRefusedWhenTheVolumeReportsNothingAndCannotPlace() throws {
        let data = Data("already here, but the volume reports nothing".utf8)
        guard case .stored(let first) = try store(data, placement: .system) else { return XCTFail() }
        // 有條目時：拒絕、index 不變
        XCTAssertThrowsError(try store(data, placement: fatLike(volumeReports: nil))) { e in
            XCTAssertTrue(message(e).contains("APFS") && message(e).contains("沒有存任何東西"), message(e))
        }
        XCTAssertEqual(indexLineCount(), 1)
        // 缺條目時（先前的繞過會補一列）：同樣拒絕、不補
        try FileManager.default.removeItem(at: root.appendingPathComponent("sources/index.jsonl"))
        let calls = PlacementCallCounter()
        let unknown = placement(renameExclusive: ENOTSUP, hardLink: ENOTSUP,
                                beforeRename: { _, _ in _ = calls.next() }, volume: { _ in nil })
        XCTAssertThrowsError(try store(data, placement: unknown)) { e in
            XCTAssertTrue(message(e).contains("HFS+") && message(e).contains("errno \(ENOTSUP)"), message(e))
        }
        XCTAssertEqual(calls.next(), 1, "實際放了一次（探測），沒有被「已經在了」略過")
        XCTAssertEqual(indexLineCount(), 0, "拒絕不補 index")
        XCTAssertEqual(try Data(contentsOf: blobURL(first.digest)), data, "位址上的那一份不動")
        XCTAssertEqual(temporaryResidue(), [])
    }

    /// 旗標讀不到、而磁碟區其實做得到（真的系統呼叫）：探測成功、兩個探測名都刪掉，存檔照常——新內容放上位址、已在的內容回「早已在」。
    /// 探測用的兩個名字都是暫存檔的形狀（被 `SIGKILL` 留下時 doctor 報它們）。
    func testTheProbeLeavesNothingBehindWhenThePlacementWorks() throws {
        let data = Data("flags unknown, placement fine".utf8)
        let names = ProbeNames()
        let unknownButFine = placement(beforeRename: { from, to in names.record(from, to) }, volume: { _ in nil })
        guard case .stored(let r) = try store(data, placement: unknownButFine) else { return XCTFail() }
        XCTAssertTrue(r.bytesWritten)
        XCTAssertEqual(try Data(contentsOf: blobURL(r.digest)), data)
        XCTAssertEqual(names.all.count, 2, "探測一次、放上位址一次")
        let probe = try XCTUnwrap(names.all.first)
        XCTAssertTrue(LibraryStore.isTemporaryBlobName((probe.from as NSString).lastPathComponent)
                      && LibraryStore.isTemporaryBlobName((probe.to as NSString).lastPathComponent), "\(probe)")
        XCTAssertEqual(temporaryResidue(), [], "探測名與暫存名都刪掉")
        XCTAssertEqual(indexLineCount(), 1)
        guard case .stored(let again) = try store(data, placement: unknownButFine) else { return XCTFail() }
        XCTAssertFalse(again.bytesWritten, "已在的內容：探測通過之後回「早已在」")
        XCTAssertEqual(temporaryResidue(), [])
        XCTAssertEqual(indexLineCount(), 1)
    }

    /// 磁碟區能力的讀取是真的：測試用的暫存目錄所在的磁碟區（APFS）回 `true`；不存在的路徑讀不到、回 `nil`（不擋）。
    /// 另在真的 exFAT 映像上量過（2026-10-02，changelog）：兩個旗標都有效、值為 0。
    func testTheVolumeCapabilityProbeReadsTheRealFlags() {
        XCTAssertEqual(LibraryStore.volumeSupportsExclusivePlacement(at: root.path), true)
        XCTAssertNil(LibraryStore.volumeSupportsExclusivePlacement(at: root.appendingPathComponent("no-such-\(UUID().uuidString)").path))
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

    // MARK: 1a. 位址上的名字只有完整內容（b26 F6：「大小相同就算已經在了」不會讀到進行中的檔）

    /// 放置的那一刻之前：位址上沒有東西、暫存檔已經是完整大小；放置之後位址上是完整內容。位址上的名字只經 `renamex_np` 這一個原子動作出現。
    /// 負控：把放置移到同步之前、或改成先在位址上建檔再複製，這一支（與 `testTheTemporaryFileIsSyncedBeforeItIsPlaced`）紅。
    func testTheAddressOnlyAppearsInOneAtomicStepWithTheCompleteContent() throws {
        let data = Data((0..<(2 * LibraryStore.sourceChunkBytes + 5)).map { UInt8(truncatingIfNeeded: $0 &* 3) })
        let url = blobURL(oneShot(data))
        let seen = RenameObservations()
        let watching = placement(beforeRename: { from, _ in
            var st = stat()
            let size = lstat(from, &st) == 0 ? Int(st.st_size) : -1
            seen.record(addressExisted: FileManager.default.fileExists(atPath: url.path), temporaryBytes: size)
        })
        guard case .stored(let r) = try store(data, placement: watching) else { return XCTFail() }
        XCTAssertTrue(r.bytesWritten)
        XCTAssertEqual(seen.all.count, 1)
        XCTAssertEqual(seen.all.first?.addressExisted, false, "放置之前位址上沒有東西")
        XCTAssertEqual(seen.all.first?.temporaryBytes, data.count, "放置之前暫存檔已經寫完")
        XCTAssertEqual(try Data(contentsOf: url), data)
    }

    /// **同時有另一個存檔先放了同一份內容**（在這一個放置之前）：這一個以 `EEXIST` 當成「已經在了」，**位址上的檔從頭到尾沒被動過**——
    /// 先放的那一個回報成功之後，不會有任何清理把它收回（我們從不刪位址上的檔，只刪暫存名）。
    func testAConcurrentStoreThatPlacedFirstKeepsItsBlob() throws {
        let data = Data("two stores, one digest, one blob".utf8)
        let url = blobURL(oneShot(data))
        let other = PlacementResultBox()
        let racing = placement(beforeRename: { _, _ in
            if other.claim() {
                other.result = try? self.store(data, placement: .system)   // B 在 A 的放置之前放好
            }
        })
        guard case .stored(let a) = try store(data, placement: racing) else { return XCTFail() }
        guard case .stored(let b)? = other.result else { return XCTFail("B 沒有存成") }
        XCTAssertTrue(b.bytesWritten, "B 先放：它寫了位元組")
        XCTAssertFalse(a.bytesWritten, "A 撞上 EEXIST：位址上早有同一份，沒寫")
        XCTAssertEqual(try Data(contentsOf: url), data, "位址上的檔沒被動過")
        XCTAssertEqual(temporaryResidue(), [], "兩邊的暫存名都刪了")
    }

    /// 存一份大檔的期間，另一個執行緒不停地 `lstat` 位址：看到檔的時候，它一定是完整大小（暫存檔寫完、同步過之後才以原子動作出現）。
    func testPollingTheAddressNeverSeesAPartialFile() throws {
        let data = Data((0..<(12 * 1_048_576)).map { UInt8(truncatingIfNeeded: $0 &* 31 &+ ($0 >> 9)) })
        let url = blobURL(oneShot(data))
        let poll = AddressPoller(path: url.path)
        poll.start()
        let intake = try store(data, placement: .system)
        poll.stop()
        guard case .stored = intake else { return XCTFail() }
        XCTAssertGreaterThan(poll.polls, 0)
        XCTAssertEqual(poll.sizesSeen.subtracting([data.count]), [], "位址上出現過不是完整大小的檔：\(poll.sizesSeen)")
        XCTAssertEqual(try Data(contentsOf: url), data)
    }

    // MARK: 1b. 同步到裝置（R2 verify 第 21 則；b26 F6：真錯誤不被 fsync 蓋掉）

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
        XCTAssertEqual(seen.observations.count, 1, "只有暫存檔同步一次")
        XCTAssertEqual(seen.observations.first?.addressExisted, false, "同步時位址上還沒有東西")
        XCTAssertEqual(seen.observations.first?.tempExisted, true, "同步的是暫存檔")
    }

    /// 同步失敗：不放上位址、不留暫存、不寫 index，錯誤說出 errno。
    func testASyncFailureRefusesAndLeavesNothing() throws {
        let data = Data("the device refuses to sync".utf8)
        let failing = placement(sync: { _, _ in EIO })
        XCTAssertThrowsError(try store(data, placement: failing)) { e in
            XCTAssertTrue(message(e).contains("同步到裝置失敗") && message(e).contains("errno \(EIO)"), message(e))
            XCTAssertTrue(message(e).contains(String(cString: strerror(EIO))), "訊息說出那個 errno 是什麼（b29 V5）：\(message(e))")
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: blobURL(oneShot(data)).path))
        XCTAssertEqual(temporaryResidue(), [])
        XCTAssertEqual(indexLineCount(), 0)
    }

    /// **b26 F6**：`F_FULLFSYNC` 回真的 I/O 錯誤（`EIO`）而 `fsync` 成功——不得回 0（`fsync` 在 macOS 不清裝置快取，補不了失敗的 `F_FULLFSYNC`）。
    /// 負控：把 `syncFile` 改回「`F_FULLFSYNC` 失敗就試 `fsync`、成功就回 0」，這一支紅。
    func testARealFullFsyncErrorIsNotHiddenByASuccessfulFsync() {
        let plainCalls = PlacementCallCounter()
        XCTAssertEqual(LibraryStore.syncFile(0, fullFsync: { _ in EIO }, plainFsync: { _ in _ = plainCalls.next(); return 0 }), EIO)
        XCTAssertEqual(plainCalls.next(), 0, "真錯誤時不該去試 fsync")
        XCTAssertEqual(LibraryStore.syncFile(0, fullFsync: { _ in ENOSPC }, plainFsync: { _ in 0 }), ENOSPC)
    }

    /// 只有 `F_FULLFSYNC` 回「不支援」才退到 `fsync`；`fsync` 的真錯誤照樣回；`fsync` 也「不支援」是盡力而為（回 0）。
    /// b29 V5：「不支援」多三個——`ENOTTY`（verify 實測 cd9660 映像的 `F_FULLFSYNC`）、`ENODEV`（實測 devfs）、`ENOSYS`。先前只認前三個，
    /// 通過磁碟區閘而沒有 `F_FULLFSYNC` 的磁碟區上每一次存檔都在複製完之後被拒。真的錯誤（`EIO`、`ENOSPC`、`EDQUOT`、`EROFS`）仍不退。
    /// 負控：從 `syncUnsupported` 拿掉 `ENOTTY`，這一支紅。
    func testFsyncIsOnlyTheFallbackForAnUnsupportedFullFsync() {
        for real in [EIO, ENOSPC, EDQUOT, EROFS] {
            let plainCalls = PlacementCallCounter()
            XCTAssertEqual(LibraryStore.syncFile(0, fullFsync: { _ in real }, plainFsync: { _ in _ = plainCalls.next(); return 0 }), real,
                           "真的錯誤（\(real)）不退到 fsync")
            XCTAssertEqual(plainCalls.next(), 0)
        }
        for unsupported in [ENOTSUP, EOPNOTSUPP, EINVAL, ENOTTY, ENODEV, ENOSYS] {
            let plainCalls = PlacementCallCounter()
            XCTAssertEqual(LibraryStore.syncFile(0, fullFsync: { _ in unsupported }, plainFsync: { _ in _ = plainCalls.next(); return 0 }), 0)
            XCTAssertEqual(plainCalls.next(), 1, "不支援（\(unsupported)）才退到 fsync")
            XCTAssertEqual(LibraryStore.syncFile(0, fullFsync: { _ in unsupported }, plainFsync: { _ in EIO }), EIO, "fsync 的真錯誤照樣回")
            XCTAssertEqual(LibraryStore.syncFile(0, fullFsync: { _ in unsupported }, plainFsync: { _ in ENOTSUP }), 0, "沒有任何可用的同步手段：盡力而為")
        }
        XCTAssertEqual(LibraryStore.syncFile(0, fullFsync: { _ in 0 }, plainFsync: { _ in EIO }), 0, "F_FULLFSYNC 成功就不碰 fsync")
    }

    /// `EINTR`：每個呼叫重試（至多 8 次），用完仍 `EINTR` 當成錯誤回傳。
    func testSyncRetriesInterruptsAFixedNumberOfTimes() {
        let calls = PlacementCallCounter()
        XCTAssertEqual(LibraryStore.syncFile(0, fullFsync: { _ in calls.next() < 2 ? EINTR : 0 }, plainFsync: { _ in EIO }), 0)
        XCTAssertEqual(calls.next(), 3, "兩次 EINTR 之後成功")
        let stuck = PlacementCallCounter()
        XCTAssertEqual(LibraryStore.syncFile(0, fullFsync: { _ in _ = stuck.next(); return EINTR }, plainFsync: { _ in 0 }), EINTR)
        XCTAssertEqual(stuck.next(), 9, "一次加八次重試")
    }

    /// 整合：`F_FULLFSYNC` 回 `EIO`、`fsync` 成功的磁碟區上，存檔被拒絕、什麼都不留（不放位址、不留暫存、不寫 index）。
    func testAStoreIsRefusedWhenFullFsyncFailsEvenIfFsyncWouldSucceed() throws {
        let data = Data("durability matters".utf8)
        let lying = placement(sync: { fd, _ in LibraryStore.syncFile(fd, fullFsync: { _ in EIO }, plainFsync: { _ in 0 }) })
        XCTAssertThrowsError(try store(data, placement: lying)) { e in
            XCTAssertTrue(message(e).contains("同步到裝置失敗") && message(e).contains("errno \(EIO)"), message(e))
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: blobURL(oneShot(data)).path))
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
        guard case .sizeMismatch(let stored, let indexed, let entry)? = try store.sourcePresence(digests: [receipt.digest])[receipt.digest] else {
            return XCTFail("被截短的 blob 要是 .sizeMismatch")
        }
        XCTAssertEqual([stored, indexed], [100, 4_096])
        XCTAssertEqual(entry["origin"], "unit-test", "mismatch 也帶 index 那一列的取得記錄（--remove-source 要用）")
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

    /// 訊號來時刪掉登記中的暫存檔（R2 verify 第 27 則；b26 F6 起**以名字認、不比 inode**）。exFAT／FAT32 上新建檔案的 inode 在第一次寫入後會變——
    /// 登記時取的 inode 之後永遠對不上，清理全部失效；暫存檔的名字帶這一次呼叫自己的 UUID、以 `O_EXCL` 建立，名字本身就是身分。
    /// 這一支把登記的檔換成**另一個 inode**（`rename` 蓋掉同名檔，模擬 inode 漂移）：仍要被刪。訊號本身在 `SourceSignalCleanupCLITests` 以真 binary 送。
    /// 負控：登記時多取 inode、刪之前比對（R2 的寫法），這一支紅。
    func testRegisteredTemporaryFilesAreRemovedByNameWhateverTheirInode() throws {
        let mine = root.appendingPathComponent("mine.tmp")
        try Data("mine".utf8).write(to: mine)
        let id = InFlightSourceFiles.register(path: mine.path)
        defer { InFlightSourceFiles.unregister(id) }
        var before = stat()
        XCTAssertEqual(lstat(mine.path, &before), 0)
        let replacement = root.appendingPathComponent("replacement.tmp")
        try Data("same name, different inode".utf8).write(to: replacement)
        XCTAssertEqual(Darwin.rename(replacement.path, mine.path), 0)
        var after = stat()
        XCTAssertEqual(lstat(mine.path, &after), 0)
        XCTAssertNotEqual(before.st_ino, after.st_ino, "前提：inode 真的變了（exFAT 上第一次寫入之後就是這樣）")
        XCTAssertEqual(InFlightSourceFiles.removeRegistered(), 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: mine.path))
    }

    /// 登記的名字上現在不是普通檔（被換成目錄或 symlink）：不動它。
    func testARegisteredNameThatIsNoLongerARegularFileIsLeftAlone() throws {
        let asDirectory = root.appendingPathComponent("dir.tmp")
        try FileManager.default.createDirectory(at: asDirectory, withIntermediateDirectories: true)
        let target = root.appendingPathComponent("target.bin")
        try Data("not ours".utf8).write(to: target)
        let asLink = root.appendingPathComponent("link.tmp")
        try FileManager.default.createSymbolicLink(at: asLink, withDestinationURL: target)
        let a = InFlightSourceFiles.register(path: asDirectory.path)
        let b = InFlightSourceFiles.register(path: asLink.path)
        defer { InFlightSourceFiles.unregister(a); InFlightSourceFiles.unregister(b) }
        XCTAssertEqual(InFlightSourceFiles.removeRegistered(), 0)
        XCTAssertTrue(FileManager.default.fileExists(atPath: asDirectory.path))
        XCTAssertNotNil(try? FileManager.default.destinationOfSymbolicLink(atPath: asLink.path))
        XCTAssertEqual(try Data(contentsOf: target), Data("not ours".utf8))
    }

    /// 訊號來源的事件送到時要不要結束行程（b26 F6，三席同指）：只有「我們正在忽略它」或「處置是預設（我們還原之後才送到的事件）」才要；
    /// 處置是別人的 handler、或不是我們忽略的 `SIG_IGN`（主機自己的）都不歸我們管。
    func testTheSignalSourceOnlyTerminatesWhenTheDispositionIsOursOrDefault() {
        typealias F = InFlightSourceFiles
        XCTAssertTrue(F.shouldTerminate(disposition: .ignored, weAreIgnoring: true), "我們的接管：那一下 Ctrl-C")
        XCTAssertFalse(F.shouldTerminate(disposition: .ignored, weAreIgnoring: false), "主機自己的 SIG_IGN")
        XCTAssertTrue(F.shouldTerminate(disposition: .defaultAction, weAreIgnoring: false), "還原之後才送到的事件")
        XCTAssertFalse(F.shouldTerminate(disposition: .custom, weAreIgnoring: false), "主機之後裝了自己的 handler")
        XCTAssertFalse(F.shouldTerminate(disposition: .custom, weAreIgnoring: true))
    }

    /// 真的訊號（b26 F6，DA 在 XCTest 裡重現過）：一輪存檔之後（長駐的訊號來源留著），主機才裝自己的 handler 再收到那個訊號——主機的 handler 要跑、
    /// 行程不被 `SIG_DFL` ＋ `raise` 殺掉。先前以「最近一次接管時是預設處置」的旗標決定，這一支會讓整個測試行程被那個訊號結束。
    func testALingeringSourceDoesNotKillAHostThatInstalledItsOwnHandlerLater() throws {
        let f = root.appendingPathComponent("cycle.tmp")
        try Data("x".utf8).write(to: f)
        InFlightSourceFiles.unregister(InFlightSourceFiles.register(path: f.path))   // 接管、還原：訊號來源長駐
        let sig = try XCTUnwrap([SIGHUP, SIGTERM, SIGINT].first { InFlightSourceFiles.signalsWithSources.contains($0) },
                                "這個行程的三個訊號都不是預設處置——沒有長駐的訊號來源可測")
        var old = sigaction()
        XCTAssertEqual(sigaction(sig, nil, &old), 0)
        hostHandlerCalls = 0
        var host = sigaction()
        host.__sigaction_u = __sigaction_u(__sa_handler: hostSignalHandler)
        sigemptyset(&host.sa_mask)
        XCTAssertEqual(sigaction(sig, &host, nil), 0)
        defer { sigaction(sig, &old, nil) }
        kill(getpid(), sig)   // 對行程送（`raise` 只對呼叫的執行緒送，kqueue 的訊號事件看不到）
        let deadline = Date().addingTimeInterval(2)
        while hostHandlerCalls == 0 && Date() < deadline { usleep(5_000) }
        usleep(300_000)   // 讓長駐的訊號來源也有機會看到那個事件
        XCTAssertEqual(hostHandlerCalls, 1, "主機的 handler 跑了，而且行程還活著")
    }

    /// 最後一個登記撤銷時只還原**仍是我們設的忽略**的訊號：登記期間主機裝了自己的 handler 就不動它（先前無條件 `SIG_DFL`，蓋掉主機的 handler）。
    func testReleasingTheSignalsDoesNotOverwriteAHandlerInstalledMeanwhile() throws {
        let f = root.appendingPathComponent("held.tmp")
        try Data("x".utf8).write(to: f)
        let id = InFlightSourceFiles.register(path: f.path)
        let sig = try XCTUnwrap([SIGHUP, SIGTERM, SIGINT].first { InFlightSourceFiles.takenSignals.contains($0) },
                                "這個行程的三個訊號都不是預設處置——沒有接管的訊號可測")
        var old = sigaction()
        XCTAssertEqual(sigaction(sig, nil, &old), 0)
        var host = sigaction()
        host.__sigaction_u = __sigaction_u(__sa_handler: hostSignalHandler)
        sigemptyset(&host.sa_mask)
        XCTAssertEqual(sigaction(sig, &host, nil), 0)
        InFlightSourceFiles.unregister(id)
        XCTAssertEqual(InFlightSourceFiles.currentDisposition(sig), .custom, "主機的 handler 還在，沒被蓋回 SIG_DFL")
        XCTAssertEqual(sigaction(sig, &old, nil), 0)
        // 還原到我們接管時的狀態：被我們設成忽略的訊號，撤銷後回預設
        signal(sig, SIG_DFL)
    }
}

/// 主機自己的訊號 handler（C 呼叫慣例，不捕捉）。
private var hostHandlerCalls = 0
private func hostSignalHandler(_ sig: Int32) { hostHandlerCalls += 1 }

/// 放置前被呼叫時看到的狀態。
final class RenameObservations: @unchecked Sendable {
    struct Observation { let addressExisted: Bool; let temporaryBytes: Int }
    private let lock = NSLock()
    private var recorded: [Observation] = []
    var all: [Observation] { lock.lock(); defer { lock.unlock() }; return recorded }
    func record(addressExisted: Bool, temporaryBytes: Int) {
        lock.lock(); defer { lock.unlock() }
        recorded.append(Observation(addressExisted: addressExisted, temporaryBytes: temporaryBytes))
    }
}

/// 在放置之前讓另一個存檔先走完，並把它的結果留下來。
final class PlacementResultBox: @unchecked Sendable {
    private let lock = NSLock()
    private var claimed = false
    private var stored: LibraryStore.SourceIntake?
    /// 只有第一個呼叫者拿到 true。
    func claim() -> Bool { lock.lock(); defer { lock.unlock() }; if claimed { return false }; claimed = true; return true }
    var result: LibraryStore.SourceIntake? {
        get { lock.lock(); defer { lock.unlock() }; return stored }
        set { lock.lock(); defer { lock.unlock() }; stored = newValue }
    }
}

/// 另一個執行緒不停地 `lstat` 一個路徑，記下看過的檔案大小。
final class AddressPoller: @unchecked Sendable {
    private let path: String
    private let lock = NSLock()
    private var running = false
    private var finished = DispatchSemaphore(value: 0)
    private var sizes = Set<Int>()
    private var count = 0
    init(path: String) { self.path = path }
    var sizesSeen: Set<Int> { lock.lock(); defer { lock.unlock() }; return sizes }
    var polls: Int { lock.lock(); defer { lock.unlock() }; return count }
    func start() {
        lock.lock(); running = true; lock.unlock()
        Thread.detachNewThread { [self] in
            while true {
                lock.lock(); let keepGoing = running; lock.unlock()
                if !keepGoing { break }
                var st = stat()
                let seen = lstat(path, &st) == 0
                lock.lock(); count += 1; if seen { sizes.insert(Int(st.st_size)) }; lock.unlock()
            }
            finished.signal()
        }
    }
    func stop() {
        lock.lock(); running = false; lock.unlock()
        finished.wait()
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

/// 放置呼叫看到的來源與目的名（探測與真的放置都經過它）。
final class ProbeNames: @unchecked Sendable {
    struct Pair { let from: String; let to: String }
    private let lock = NSLock()
    private var pairs: [Pair] = []
    var all: [Pair] { lock.lock(); defer { lock.unlock() }; return pairs }
    func record(_ from: String, _ to: String) { lock.lock(); defer { lock.unlock() }; pairs.append(Pair(from: from, to: to)) }
}

/// 測試接縫裡用的計數器（`@Sendable` 閉包不能捕捉可變的區域變數）。
final class PlacementCallCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var n = 0
    /// 回目前的值，再加一。
    func next() -> Int { lock.lock(); defer { lock.unlock() }; defer { n += 1 }; return n }
}
