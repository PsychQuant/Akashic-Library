import XCTest
import CryptoKit
import Foundation
@testable import AkashicCore
@testable import AkashicStoreIO

/// #703（使用者 2026-09-30 裁決「三件都做，上限 256 MB」）的存檔層：
///
/// 1. `sources/` 單份內容的上限是**一個**常數（`LibraryStore.maxSourceBytes`＝268,435,456 bytes）；超過的不截斷、不存、具名拒絕。
/// 2. SHA-256 逐塊計算、複製也逐塊——不再把整份內容讀進記憶體；digest 的形狀（`sha256:` + 64 個小寫 hex）與 0 byte 的拒絕（#546）不變。
/// 3. 既有 blob 與內容的比對（`checkStoredBlob`）——`copy-zotero-attachments` 補存時用它，不一致時不覆寫。
///
/// 上限用注入的小數值測（不造 256 MB 的檔）；「真的常數」那一格用 APFS 的 sparse 檔——大小以 stat 判斷，拒絕發生在讀任何一個位元組之前。
final class SourceIntakeStreamingTests: XCTestCase {
    var root: URL!
    var store: LibraryStore!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("akashic-intake-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root.appendingPathComponent("entities"), withIntermediateDirectories: true)
        try StoreVersion.write(root: root, format: StoreVersion.supported)
        store = LibraryStore(root: root)
        GitFixture.initRepo(root)
        try store.ensureLayout()
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    private func prov(_ note: String? = nil) -> LibraryStore.SourceProvenance {
        LibraryStore.SourceProvenance(mediaType: "application/pdf", retrieved: "2026-09-30",
                                      origin: "unit-test", acquisition: "file", note: note)
    }
    private func oneShot(_ data: Data) -> String { "sha256:" + SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
    private func blobURL(_ digest: String) -> URL {
        let hex = String(digest.dropFirst("sha256:".count))
        return root.appendingPathComponent("sources/\(hex.prefix(2))/\(hex.dropFirst(2))")
    }
    private func file(_ data: Data) throws -> URL {
        let url = root.appendingPathComponent("in-\(UUID().uuidString).bin")
        try data.write(to: url)
        return url
    }
    /// sources/ 底下除了 index.jsonl 之外的所有東西（含暫存檔）
    private func sourcesResidue() -> [String] {
        let dir = root.appendingPathComponent("sources")
        return ((try? FileManager.default.subpathsOfDirectory(atPath: dir.path)) ?? []).filter { $0 != "index.jsonl" }.sorted()
    }
    private func indexLineCount() -> Int {
        let text = (try? String(contentsOf: root.appendingPathComponent("sources/index.jsonl"), encoding: .utf8)) ?? ""
        return text.split(separator: "\n").count
    }
    private func pseudoRandom(_ count: Int, seed: UInt8 = 7) -> Data {
        var x = UInt32(seed) &* 2_654_435_761
        return Data((0..<count).map { _ in x = x &* 1_103_515_245 &+ 12_345; return UInt8(truncatingIfNeeded: x >> 16) })
    }

    // MARK: 1. 上限：一個常數

    func testTheCapIs256MBAndTheChunkIsSmallerThanIt() {
        XCTAssertEqual(LibraryStore.maxSourceBytes, 268_435_456, "使用者 2026-09-30 裁決：256 MB")
        XCTAssertLessThan(LibraryStore.sourceChunkBytes, LibraryStore.maxSourceBytes)
        XCTAssertEqual(LibraryStore.sourceCapDescription(LibraryStore.maxSourceBytes), "268435456 bytes（256 MB）")
    }

    /// 真的常數：sparse 檔的大小超過 256 MB，拒絕以 stat 判斷——不讀、不寫、具名大小。
    func testAHandleOverTheRealCapIsRefusedBeforeAnyWrite() throws {
        let url = root.appendingPathComponent("huge.bin")
        XCTAssertTrue(FileManager.default.createFile(atPath: url.path, contents: nil))
        let w = try FileHandle(forWritingTo: url)
        try w.truncate(atOffset: UInt64(LibraryStore.maxSourceBytes + 1))
        try w.close()
        let h = try FileHandle(forReadingFrom: url)
        defer { try? h.close() }
        let outcome = try store.storeSource(contentsOf: h, provenance: prov())
        guard case .refused(.tooLarge(let bytes)) = outcome else { return XCTFail("超過上限要拒絕：\(outcome)") }
        XCTAssertEqual(bytes, LibraryStore.maxSourceBytes + 1, "具名的是實際大小")
        XCTAssertEqual(try h.offset(), 0, "以 stat 判斷——一個位元組都沒讀")
        XCTAssertEqual(sourcesResidue(), [], "不存、不留暫存")
        XCTAssertEqual(indexLineCount(), 0)
    }

    /// 注入的上限：恰好等於上限的收、多一個 byte 的拒絕。
    func testTheLimitIsInclusive() throws {
        let at = try FileHandle(forReadingFrom: try file(Data(repeating: 0x41, count: 10)))
        defer { try? at.close() }
        guard case .stored(let r) = try store.storeSource(contentsOf: at, provenance: prov(), limit: 10) else {
            return XCTFail("恰好等於上限要收")
        }
        XCTAssertTrue(r.bytesWritten)
        let over = try FileHandle(forReadingFrom: try file(Data(repeating: 0x42, count: 11)))
        defer { try? over.close() }
        XCTAssertEqual(try store.storeSource(contentsOf: over, provenance: prov(), limit: 10), .refused(.tooLarge(bytes: 11)))
    }

    /// Data 入口（既有 API）同一條上限：超過就擲具名錯誤、零寫入。
    func testDataOverTheLimitIsANamedErrorAndWritesNothing() throws {
        XCTAssertThrowsError(try store.storeSource(Data(repeating: 1, count: 11), provenance: prov(), limit: 10)) { e in
            let msg = (e as? LocalizedError)?.errorDescription ?? "\(e)"
            XCTAssertTrue(msg.contains("11") && msg.contains("10 bytes"), "要說出實際大小與上限：\(msg)")
        }
        XCTAssertEqual(sourcesResidue(), [])
        XCTAssertEqual(indexLineCount(), 0)
    }

    /// 宣告的大小不超過、讀到的卻超過（讀的時候檔案在長）：讀到上限多一塊就停、拒絕，不寫。
    func testContentThatGrowsPastTheLimitWhileReadingIsRefused() throws {
        var src = ScriptedChunks(passes: [Data(repeating: 7, count: 25)], declared: 5)
        let outcome = try store.storeSource(chunks: &src, provenance: prov(), expectedDigest: nil, limit: 10)
        guard case .refused(.tooLarge(let n)) = outcome else { return XCTFail("\(outcome)") }
        XCTAssertGreaterThan(n, 10)
        XCTAssertEqual(sourcesResidue(), [])
    }

    // MARK: 2. 逐塊

    /// 跨塊邊界的各種大小，逐塊算出的 digest 與一次算出的完全相同（形狀、大小寫都一樣）。
    func testStreamedDigestEqualsTheOneShotDigestAcrossChunkBoundaries() throws {
        let c = LibraryStore.sourceChunkBytes
        for size in [1, 2, c - 1, c, c + 1, 3 * c + 5] {
            let data = pseudoRandom(size, seed: UInt8(size % 251))
            let h = try FileHandle(forReadingFrom: try file(data))
            defer { try? h.close() }
            XCTAssertEqual(try LibraryStore.contentDigest(reading: h), .digest(oneShot(data), bytes: size), "size \(size)")
            XCTAssertEqual(LibraryStore.contentDigest(of: data), oneShot(data), "兩個入口同一條公式")
        }
    }

    /// 存進去的位元組與原檔逐位元組相同，位址是它的 digest，index 記的大小是實際大小；不留暫存檔。
    func testStoringFromAHandleCopiesTheBytesVerbatim() throws {
        let data = pseudoRandom(2 * LibraryStore.sourceChunkBytes + 123)
        let h = try FileHandle(forReadingFrom: try file(data))
        defer { try? h.close() }
        guard case .stored(let r) = try store.storeSource(contentsOf: h, provenance: prov()) else { return XCTFail() }
        XCTAssertEqual(r.digest, oneShot(data))
        XCTAssertTrue(r.indexEntryCreated)
        XCTAssertTrue(r.exclusionVerified)
        XCTAssertEqual(try Data(contentsOf: blobURL(r.digest)), data)
        let hex = String(r.digest.dropFirst("sha256:".count))
        XCTAssertEqual(sourcesResidue(), [String(hex.prefix(2)), "\(hex.prefix(2))/\(hex.dropFirst(2))"], "只有 blob，沒有留下暫存檔")
        let line = try String(contentsOf: root.appendingPathComponent("sources/index.jsonl"), encoding: .utf8)
        XCTAssertTrue(line.contains("\"bytes\": \(data.count)"), line)
    }

    /// 記憶體與檔案大小無關的機械證據：算 digest 與複製，每一次都只要一塊，而且兩遍都是逐塊走完。
    /// （改回整份讀——一次要 `Int.max`——這一格就紅。）
    func testDigestAndCopyNeverAskForMoreThanOneChunk() throws {
        let data = pseudoRandom(3 * LibraryStore.sourceChunkBytes + 5)
        var src = ScriptedChunks(passes: [data])
        guard case .stored = try store.storeSource(chunks: &src, provenance: prov(), expectedDigest: nil,
                                                   limit: LibraryStore.maxSourceBytes) else { return XCTFail() }
        XCTAssertFalse(src.requests.isEmpty)
        XCTAssertTrue(src.requests.allSatisfy { $0 <= LibraryStore.sourceChunkBytes }, "每次至多一塊：\(Set(src.requests))")
        XCTAssertGreaterThanOrEqual(src.requests.count, 2 * 4, "digest 一遍、複製一遍，各四塊以上")
        XCTAssertEqual(src.rewinds, 2, "兩遍都從頭讀")
    }

    /// 算 digest 那一遍與複製那一遍之間內容變了：不落地、不留暫存檔、說出實際的 digest。
    func testContentChangedBetweenTheTwoPassesLeavesNothing() throws {
        var src = ScriptedChunks(passes: [Data("first pass bytes".utf8), Data("second pass other".utf8)])
        let outcome = try store.storeSource(chunks: &src, provenance: prov(), expectedDigest: nil, limit: 1_000)
        XCTAssertEqual(outcome, .refused(.changed(actual: oneShot(Data("second pass other".utf8)))))
        XCTAssertEqual(sourcesResidue().filter { $0.contains("/") }, [], "blob 與暫存檔都不留")
        XCTAssertEqual(indexLineCount(), 0)
    }

    /// 呼叫端預期的 digest（`copy-zotero-attachments` 計畫時算的）與實際內容不同：第一遍就拒絕，什麼都不寫。
    func testAnExpectedDigestThatDoesNotMatchIsRefusedBeforeWriting() throws {
        let data = Data("actual content".utf8)
        let h = try FileHandle(forReadingFrom: try file(data))
        defer { try? h.close() }
        let wrong = "sha256:" + String(repeating: "0", count: 64)
        XCTAssertEqual(try store.storeSource(contentsOf: h, provenance: prov(), expectedDigest: wrong),
                       .refused(.changed(actual: oneShot(data))))
        XCTAssertEqual(sourcesResidue(), [])
    }

    /// 0 byte（#546）照舊拒絕——handle 入口也一樣，以 stat 判斷。
    func testAnEmptyHandleIsRefused() throws {
        let h = try FileHandle(forReadingFrom: try file(Data()))
        defer { try? h.close() }
        XCTAssertEqual(try store.storeSource(contentsOf: h, provenance: prov()), .refused(.empty))
        XCTAssertEqual(sourcesResidue(), [])
    }

    /// 位址上已有東西：不覆寫（內容定址；那一份對不對由 `checkStoredBlob` 另外比）。
    func testAnExistingBlobIsNeverOverwritten() throws {
        let data = Data("the real bytes".utf8)
        let url = blobURL(oneShot(data))
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("truncated".utf8).write(to: url)
        let h = try FileHandle(forReadingFrom: try file(data))
        defer { try? h.close() }
        guard case .stored(let r) = try store.storeSource(contentsOf: h, provenance: prov()) else { return XCTFail() }
        XCTAssertFalse(r.bytesWritten)
        XCTAssertEqual(try Data(contentsOf: url), Data("truncated".utf8), "既有的那一份一個位元組都不動")
    }

    /// 暫存檔的路徑也要過版控排除閘（fail-closed）：只排除 blob 名、沒排除暫存名的規則，拒寫且什麼都不留。
    func testTheTemporaryFilePathMustAlsoBeExcluded() throws {
        try "sources/index.jsonl\nsources/??/[0-9a-f]*\n".write(to: root.appendingPathComponent(".gitignore"),
                                                               atomically: true, encoding: .utf8)
        let h = try FileHandle(forReadingFrom: try file(Data("half excluded".utf8)))
        defer { try? h.close() }
        XCTAssertThrowsError(try store.storeSource(contentsOf: h, provenance: prov())) { e in
            let msg = (e as? LocalizedError)?.errorDescription ?? "\(e)"
            XCTAssertTrue(msg.contains("sources"), msg)
        }
        XCTAssertEqual(sourcesResidue().filter { $0.contains("/") }, [], "拒寫時不留 blob、不留暫存檔")
    }

    // MARK: 3. 既有 blob 的比對

    func testCheckStoredBlobTellsMatchMismatchAbsentAndDirectoryApart() throws {
        let data = Data("zotero original".utf8)
        let d = oneShot(data)
        XCTAssertEqual(try store.checkStoredBlob(digest: d, expectedBytes: data.count), .absent)
        _ = try store.storeSource(data, provenance: prov())
        XCTAssertEqual(try store.checkStoredBlob(digest: d, expectedBytes: data.count), .matches)
        // 被截短：大小不同，不必讀就知道不符
        try Data("zotero".utf8).write(to: blobURL(d))
        XCTAssertEqual(try store.checkStoredBlob(digest: d, expectedBytes: data.count), .mismatch(bytes: 6, digest: nil))
        // 被換掉、大小相同：逐塊算 digest 才看得出來
        let swapped = Data("ZOTERO ORIGINAL".utf8)
        try swapped.write(to: blobURL(d))
        XCTAssertEqual(try store.checkStoredBlob(digest: d, expectedBytes: data.count),
                       .mismatch(bytes: swapped.count, digest: oneShot(swapped)))
        // 位置上是目錄
        try FileManager.default.removeItem(at: blobURL(d))
        try FileManager.default.createDirectory(at: blobURL(d), withIntermediateDirectories: true)
        XCTAssertEqual(try store.checkStoredBlob(digest: d, expectedBytes: data.count), .notRegularFile("目錄"))
    }
}

/// 逐遍腳本化的內容來源：第 N 次 rewind 之後讀 `passes[N-1]`（超出就沿用最後一個），並記下每次要多少。
struct ScriptedChunks: SourceChunks {
    var passes: [Data]
    var declared: Int?
    var requests: [Int] = []
    var rewinds = 0
    private var offset = 0
    init(passes: [Data], declared: Int? = nil) {
        self.passes = passes
        self.declared = declared
    }
    private var current: Data { passes[min(max(rewinds, 1), passes.count) - 1] }
    func currentSize() -> Int? { declared ?? current.count }
    mutating func rewind() throws { rewinds += 1; offset = 0 }
    mutating func next(upTo n: Int) throws -> Data? {
        requests.append(n)
        let data = current
        guard offset < data.count else { return nil }
        let end = min(offset + n, data.count)
        defer { offset = end }
        return data.subdata(in: offset..<end)
    }
}
