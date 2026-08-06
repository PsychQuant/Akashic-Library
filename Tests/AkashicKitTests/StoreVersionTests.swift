import XCTest
import Foundation
@testable import AkashicCore
@testable import AkashicStoreIO

/// #24：store format version 標記與 refuse-if-newer。
final class StoreVersionTests: XCTestCase {
    var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("akashic-ver-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func writeMarker(_ body: String) throws {
        try body.write(to: StoreVersion.url(in: root), atomically: true, encoding: .utf8)
    }

    // MARK: - 讀取

    /// **缺檔 ＝ format 1**。#24 之前寫的 store 都沒這個檔，而它們就是 v1.x——
    /// 把缺檔當錯誤會讓這道防線一落地就打死所有既有 store。
    func testAbsentMarkerMeansVersionOne() throws {
        XCTAssertEqual(try StoreVersion.read(root: root), 1)
        XCTAssertNoThrow(try StoreVersion.check(root: root))
    }

    func testReadsFormatLine() throws {
        try writeMarker("format: 3\n")
        XCTAssertEqual(try StoreVersion.read(root: root), 3)
    }

    func testIgnoresCommentsAndBlankLines() throws {
        try writeMarker("# 說明\n\n#\nformat: 2\n")
        XCTAssertEqual(try StoreVersion.read(root: root), 2)
    }

    /// 值後面可以跟行尾註解——emitter 自己就會寫這種。
    func testTrailingCommentAfterValue() throws {
        try writeMarker("format: 2  # v2 家族\n")
        XCTAssertEqual(try StoreVersion.read(root: root), 2)
    }

    /// 檔案在但沒有 `format:` 行 → **不猜**。猜成 1 會讓一個壞掉的標記檔靜默降級成
    /// 「沒有防線」，正是這個機制要防的失敗。
    func testMarkerWithoutFormatLineThrows() throws {
        try writeMarker("something: else\n")
        XCTAssertThrowsError(try StoreVersion.read(root: root)) {
            guard case StoreVersionError.malformed = $0 else {
                return XCTFail("應為 malformed，實得 \($0)")
            }
        }
    }

    func testNonNumericFormatThrows() throws {
        try writeMarker("format: v2\n")
        XCTAssertThrowsError(try StoreVersion.read(root: root))
    }

    func testZeroOrNegativeFormatThrows() throws {
        try writeMarker("format: 0\n")
        XCTAssertThrowsError(try StoreVersion.read(root: root))
    }

    // MARK: - refuse-if-newer

    func testEqualVersionOpens() throws {
        try writeMarker("format: \(StoreVersion.supported)\n")
        XCTAssertNoThrow(try StoreVersion.check(root: root))
    }

    func testNewerVersionRefused() throws {
        try writeMarker("format: \(StoreVersion.supported + 1)\n")
        XCTAssertThrowsError(try StoreVersion.check(root: root)) { err in
            guard case let StoreVersionError.tooNew(found, supported) = err else {
                return XCTFail("應為 tooNew，實得 \(err)")
            }
            XCTAssertEqual(found, StoreVersion.supported + 1)
            XCTAssertEqual(supported, StoreVersion.supported)
            // 訊息必須可行動：說出兩個數字，並點名三個 binary 各自獨立。
            let msg = (err as? LocalizedError)?.errorDescription ?? ""
            XCTAssertTrue(msg.contains("\(found)") && msg.contains("\(supported)"), msg)
            XCTAssertTrue(msg.contains("akashic-mcp") && msg.contains("App"), msg)
        }
    }

    // MARK: - 與 store 生命週期整合

    func testEnsureLayoutWritesMarker() throws {
        let store = LibraryStore(root: root)
        try store.ensureLayout()
        XCTAssertEqual(try StoreVersion.read(root: root), StoreVersion.supported)
    }

    /// **不覆寫既有檔**——那可能是較新版本寫的，覆寫等於把 refuse-if-newer 的依據
    /// 自己抹掉（而且是在使用者跑一個看似無害的 `doctor` 時發生）。
    ///
    /// #106 之後契約更強：`ensureLayout` 對 too-new 的 store **直接拒絕**（先前只是
    /// 不覆寫但照樣蓋目錄）。本測試守的性質不變——marker 原封不動——外加拒絕語意。
    func testEnsureLayoutDoesNotOverwriteNewerMarker() throws {
        try writeMarker("format: 99\n")
        let store = LibraryStore(root: root)
        XCTAssertThrowsError(try store.ensureLayout()) { error in
            guard case StoreVersionError.tooNew = error else {
                return XCTFail("預期 tooNew，實得 \(error)")
            }
        }
        XCTAssertEqual(try StoreVersion.read(root: root), 99, "既有標記被覆寫＝防線自毀")
    }

    /// 防線要在**逐檔 decode 之前**——否則使用者拿到的是一堆難解的 per-file 錯誤，
    /// 而不是一句「請升級 binary」。
    func testLoadRefusesNewerStoreBeforeDecodingAnyFile() throws {
        let store = LibraryStore(root: root)
        try store.ensureLayout()
        // 放一個**本身就壞掉**的 entry：若 version 檢查沒有搶在前面，
        // 這個檔會先產生 quarantine，錯誤面就不是 version 了。
        // fixture 手寫原始檔進 legacy 的 entries/，需自己建目錄（#101）
        try FileManager.default.createDirectory(at: store.entriesDir, withIntermediateDirectories: true)
        try "這不是合法的 entry YAML: [".write(
            to: store.entriesDir.appendingPathComponent("broken.yaml"),
            atomically: true, encoding: .utf8)
        try writeMarker("format: \(StoreVersion.supported + 5)\n")

        XCTAssertThrowsError(try store.load()) { err in
            guard case StoreVersionError.tooNew = err else {
                return XCTFail("version 檢查必須先於逐檔 decode，實得 \(err)")
            }
        }
    }

    func testLoadOpensNormallyAtSupportedVersion() throws {
        let store = LibraryStore(root: root)
        try store.ensureLayout()
        try store.writeEntry(Entry(id: UUID(), citekey: "a2020b", type: "article",
                                   title: "T", authors: [.literal("X")], date: "2020"))
        let load = try store.load()
        XCTAssertEqual(load.entries.count, 1)
    }

    /// `store.yaml` 是 canonical 事實，不該被當成 entry / library 檔誤讀。
    func testMarkerFileIsNotMistakenForContent() throws {
        let store = LibraryStore(root: root)
        try store.ensureLayout()
        let load = try store.load()
        XCTAssertTrue(load.quarantined.isEmpty, "store.yaml 不該進 quarantine：\(load.quarantined)")
        XCTAssertTrue(load.entries.isEmpty)
        XCTAssertTrue(load.libraries.isEmpty)
    }
}
