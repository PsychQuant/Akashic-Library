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

/// marker 解析只認**頂層**的 `format:` 行（#112 verify DA A1）。
///
/// `read` 曾是「逐行 trim 後前綴比對、第一個匹配勝出」——於是巢狀在別的 mapping
/// 底下的 `format:`（例如外來 store 的 `meta:\n  format: 1`）會贏過頂層的真值。
/// 實測後果：`format: 5` 的 store 被讀成 1 → doctor exit 0 並安靜建出雙佈局——
/// 這正是 #106 宣稱關掉的症狀，被一個 5 行的 YAML 檔繞回來。
extension StoreVersionTests {
    /// **語意演進（#112 → #117）**：#112 的修法是「巢狀鍵不得贏過頂層」（讀 5）；
    /// #117 的 grammar 定案更進一步——marker 裡**根本不允許**巢狀結構，任何未知
    /// 頂層行（`meta:`）即 malformed。fail-silent 的殘餘可能性就此關閉。
    func testNestedStructureIsMalformed() throws {
        try writeMarker("meta:\n  format: 1\nformat: 5\n")
        XCTAssertThrowsError(try StoreVersion.read(root: root)) { error in
            guard case StoreVersionError.malformed = error else {
                return XCTFail("預期 malformed（meta: 是未知頂層行），實得 \(error)")
            }
        }
        try writeMarker("meta:\n\u{00A0}\u{00A0}format: 1\nformat: 5\n")
        XCTAssertThrowsError(try StoreVersion.read(root: root),
                             "NBSP 縮排版同理——#112 曾要求「不遮蔽」，#117 收緊為「非法」")
        try writeMarker("meta:\n\u{3000}format: 1\nformat: 5\n")
        XCTAssertThrowsError(try StoreVersion.read(root: root), "全形空格縮排同理")
    }

    func testOnlyNestedFormatKeyIsMalformed() throws {
        try writeMarker("meta:\n  format: 5\n")
        XCTAssertThrowsError(try StoreVersion.read(root: root)) { error in
            guard case StoreVersionError.malformed = error else {
                return XCTFail("預期 malformed，實得 \(error)")
            }
        }
    }
}

/// #117：marker grammar 定案——合法 marker ＝ 註解行/空行 + **恰好一個**頂格
/// `format:` 行；換行接受全部 Unicode 變體。其餘一律 malformed（fail-loud）。
extension StoreVersionTests {
    /// flow-mapping 毒化是 #112 修掉縮排類之後**僅存的 fail-silent 繞法**：
    /// `meta: {` 換行後的 `format: 1,` 落在第 0 欄，行解析器曾把它當頂層——
    /// format 5 的 store 讀成 1，靜默降版。新 grammar 下 `meta: {` 本身就是
    /// 未知頂層行，整檔 malformed。
    func testFlowMappingPoisonIsMalformed() throws {
        try writeMarker("meta: {\nformat: 1, note: x}\nformat: 5\n")
        XCTAssertThrowsError(try StoreVersion.read(root: root)) { error in
            guard case StoreVersionError.malformed = error else {
                return XCTFail("預期 malformed（fail-loud），實得 \(error)——讀成任何數字都是 fail-silent")
            }
        }
    }

    /// CRLF：`split(separator: "\n")` 對 CRLF 檔完全不分行（`\r\n` 是單一
    /// Character）——多行模板整檔被當一行註解、報「找不到 format: 行」。
    /// 換行符變體不是語意歧義，grammar 接受全部 Unicode 換行。
    func testCRLFMarkerReads() throws {
        try writeMarker("# 說明\r\nformat: 4\r\n")
        XCTAssertEqual(try StoreVersion.read(root: root), 4, "CRLF 模板要正常解析")
    }

    func testCROnlyAndUnicodeNewlinesRead() throws {
        try writeMarker("# c\rformat: 3\r")
        XCTAssertEqual(try StoreVersion.read(root: root), 3, "CR-only（classic Mac）")
        try writeMarker("# c\u{2028}format: 2\u{2028}")
        XCTAssertEqual(try StoreVersion.read(root: root), 2,
                       "LS 分隔同理——displaySafe 也把 LS/PS 視為換行，立場一致")
    }

    func testUnknownTopLevelKeyIsMalformed() throws {
        try writeMarker("format: 2\ncreated: 2026-08-06\n")
        XCTAssertThrowsError(try StoreVersion.read(root: root),
                             "未知頂層行不再被容忍——additive key 需要連解析器一起設計")
    }

    /// 兩個 `format:` 行＝歧義。first-wins 是猜；歧義不猜（同 #121 的
    /// duplicateRegistration 哲學）。
    func testDuplicateFormatLineIsMalformed() throws {
        try writeMarker("format: 2\nformat: 3\n")
        XCTAssertThrowsError(try StoreVersion.read(root: root))
    }

    /// 縮排的**註解**照樣容忍（grammar：註解與空行任意縮排；只有 format 行必須頂格）。
    func testIndentedCommentIsTolerated() throws {
        try writeMarker("  # 縮排註解\nformat: 2\n   \n")
        XCTAssertEqual(try StoreVersion.read(root: root), 2)
    }

    /// #127 verify M1（mutation-proven 缺口）：舊版兩個縮排測試都以 `meta:` 開頭——
    /// 解析器在第 1 行就 throw，縮排守衛**根本沒被執行到**；把守衛窄化回 #112 R2
    /// 的 bug（只擋 ASCII space/tab）後 24 個測試照樣全綠。isolating 輸入：縮排行
    /// 自己就是第一個非註解行，守衛不對就會被跳過、讀出 5——fail-silent 回歸。
    func testIndentedFormatLineAloneIsMalformed() throws {
        // **輸入必須是檔內唯一的行**：若後面還跟一個頂格 format 行，窄化的守衛
        // 讓縮排行先當上 found、頂格行再觸發 duplicate——照樣 throw、理由全錯，
        // 測試就綠著放走 fail-silent（本測試第一版正是這樣被 mutation 揭穿的）。
        // 單行版本下，守衛失效＝直接讀出 1＝斷言變紅。
        for indent in [" ", "\t", "\u{00A0}", "\u{3000}"] {
            try writeMarker("\(indent)format: 1\n")
            XCTAssertThrowsError(try StoreVersion.read(root: root)) { error in
                guard case StoreVersionError.malformed = error else {
                    return XCTFail("縮排（U+\(String(indent.unicodeScalars.first!.value, radix: 16))）行未被拒——守衛失效，實得 \(error)")
                }
            }
        }
    }

    /// 合法 format 行**之後**的縮排垃圾也要拒——「先讀到值就不管後面」是順序依賴的猜。
    func testIndentedJunkAfterValidFormatLineIsMalformed() throws {
        try writeMarker("format: 5\n\u{3000}junk\n")
        XCTAssertThrowsError(try StoreVersion.read(root: root))
    }

    func testNegativeFormatThrows() throws {
        try writeMarker("format: -1\n")
        XCTAssertThrowsError(try StoreVersion.read(root: root))
    }

    /// PS 分隔與混合行尾（#127 verify L4：文件宣稱了但沒有測試釘）。
    func testPSAndMixedNewlinesRead() throws {
        try writeMarker("# a\u{2029}format: 4\u{2029}")
        XCTAssertEqual(try StoreVersion.read(root: root), 4, "PS 分隔")
        try writeMarker("# first\r\n\rformat: 4\u{2028}  # last\n")
        XCTAssertEqual(try StoreVersion.read(root: root), 4, "混合行尾（CRLF+CR+LS+LF）")
    }

    /// malformed 訊息不得原樣攜帶檔案內容（#127 verify M2）：ESC 會清螢幕偽造輸出、
    /// 超長行會灌爆 MCP context——StoreVersion 的 line payload 與 StoreIOError 同紀律。
    func testMalformedMessageSanitizesFileContent() throws {
        try writeMarker("\u{1B}[2J forged ok\nformat: 5\n")
        XCTAssertThrowsError(try StoreVersion.read(root: root)) { error in
            let msg = (error as? LocalizedError)?.errorDescription ?? ""
            XCTAssertFalse(msg.contains("\u{1B}"), "ESC 不得原樣進錯誤訊息")
        }
        try writeMarker(String(repeating: "x", count: 100_000) + "\nformat: 5\n")
        XCTAssertThrowsError(try StoreVersion.read(root: root)) { error in
            let msg = (error as? LocalizedError)?.errorDescription ?? ""
            XCTAssertLessThan(msg.count, 1_000, "超長行必須被截斷")
        }
    }

    /// 值後面只能是註解——`format: 2 garbage` 取前綴當真是另一種猜。
    func testTrailingGarbageAfterValueIsMalformed() throws {
        try writeMarker("format: 2 garbage\n")
        XCTAssertThrowsError(try StoreVersion.read(root: root))
        try writeMarker("format: 2.5\n")
        XCTAssertThrowsError(try StoreVersion.read(root: root), "小數不是「帶註解的整數」")
    }

    /// #118：malformed 的訊息要指路——對照 tooNew 有「請升級」與降級說明，
    /// malformed 曾只描述不指路，而修復入口（doctor）對它第一步就拒絕：
    /// 使用者被正確地擋下，然後不知道往哪走。
    func testMalformedMessageGivesGuidance() throws {
        try writeMarker("format: banana\n")
        XCTAssertThrowsError(try StoreVersion.read(root: root)) { error in
            let m = (error as? LocalizedError)?.errorDescription ?? "\(error)"
            XCTAssertTrue(m.contains("format:") && m.contains("正整數"),
                          "要說出合法形狀（一個頂格 format: 正整數行）：\(m)")
            XCTAssertTrue(m.contains("store-format.md"), "要指向規格：\(m)")
            XCTAssertTrue(m.contains("v1.x") || m.contains("format 1"),
                          "「刪檔=當 format 1」的前提必須說清楚——否則指引本身是降版陷阱：\(m)")
        }
    }

    /// tooNew 與 malformed 的訊息對稱性：兩個 case 都要有出口。
    func testBothErrorCasesGiveActionableGuidance() throws {
        try writeMarker("format: \(StoreVersion.supported + 1)\n")
        XCTAssertThrowsError(try StoreVersion.check(root: root)) { error in
            let m = (error as? LocalizedError)?.errorDescription ?? ""
            XCTAssertTrue(m.contains("升級"), "tooNew 的出口（既有）")
        }
        try writeMarker("format: banana\n")
        XCTAssertThrowsError(try StoreVersion.read(root: root)) { error in
            let m = (error as? LocalizedError)?.errorDescription ?? ""
            XCTAssertTrue(m.contains("修"), "malformed 也要有出口：\(m)")
        }
    }

    /// `write` 模板必須永遠合法（自產自讀的最低要求）。
    func testWriteTemplateRoundTrips() throws {
        try StoreVersion.write(root: root, format: 5)
        XCTAssertEqual(try StoreVersion.read(root: root), 5)
    }
}
