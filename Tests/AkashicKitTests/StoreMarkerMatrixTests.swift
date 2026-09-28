import XCTest
import Foundation
@testable import AkashicCore
@testable import AkashicStoreIO

/// `store.yaml` 的 marker grammar 在 46 個具名形狀上的**裁決矩陣**（#629：由 `store-marker-parity.sh` 移植）。
///
/// ## 這張矩陣現在在驗什麼
///
/// 移植前它驗的是「普查（Python）與讀端（Swift）對同一批輸入給出同樣的裁決」——那個命題在普查改呼叫
/// `StoreVersion.read` 之後**結構上恆真**（只剩一份實作）。所以那兩份實作之間的 parity 測試、它的負控 harness、
/// 生成「`#` 後接 grapheme extender」表的生成器與漂移守衛、多 scalar 序列的證明，全部不再有東西可守，一併移除。
///
/// **矩陣本身留下來，因為它從來就不只是 parity 測試**：每一格帶著**預期的裁決**（不只比對兩邊相等），
/// 所以它同時是讀端 grammar 的一份可否證規格——特別是那些反直覺的格子：
/// 全形／天城體／阿拉伯數字是 malformed（Swift 的 `Int(String)` 只吃 ASCII）、`#` 後緊跟 combining mark 或 ZWJ 時
/// 那一行**不是**註解（`hasPrefix("#")` 是 grapheme 層比較）、U+200B 被 `CharacterSet.whitespaces` trim 掉
/// （Foundation 的空白集含 ZWSP，而 ZWSP 是 Cf 不是 Zs）、BOM 被 Foundation 吃掉所以是合法的。
/// **這些行為取決於 Swift／Unicode 的版本**：Swift 或作業系統更新讓某一格的答案變了，這裡會紅——那是這個
/// 矩陣被留下來的理由（以前由 hash-table-drift 那條路徑守著「表過期是安靜的」，現在是這裡）。
///
/// 每一格同時斷言三件事：**讀端**（`StoreVersion.check`）的裁決、**普查**（`LiteralCensus.readMarker`）歸到的態、
/// 以及兩者的一致。
final class StoreMarkerMatrixTests: XCTestCase {

    private enum Verdict: String { case accept, malformed, tooNew, unreadable }

    private struct Cell {
        let name: String
        let marker: Marker
        let expect: Verdict
    }

    private enum Marker {
        case bytes(Data)
        case absent
        case unreadablePermissions   // chmod 000
        case directory               // store.yaml 是目錄
    }

    private static func text(_ s: String) -> Marker { .bytes(Data(s.utf8)) }
    private static func raw(_ b: [UInt8]) -> Marker { .bytes(Data(b)) }

    private var cells: [Cell] {
        let sup = StoreVersion.supported
        let zeros = String(repeating: "0", count: 5000)
        return [
            // ── 合法 ──
            Cell(name: "format: 12", marker: Self.text("format: 12\n"), expect: .accept),
            Cell(name: "缺檔（讀端：即 format 1）", marker: .absent, expect: .accept),
            Cell(name: "值後帶註解（讀端明文允許）", marker: Self.text("format: 12  # v12\n"), expect: .accept),
            Cell(name: "前後有註解與空行", marker: Self.text("# hdr\n\nformat: 12\n\n# tail\n"), expect: .accept),
            Cell(name: "縮排的註解（允許）", marker: Self.text("  # indented comment\nformat: 12\n"), expect: .accept),
            Cell(name: "CRLF 換行", marker: Self.text("format: 12\r\n"), expect: .accept),
            // ── 讀端拒絕 ──
            Cell(name: "無 format: 行", marker: Self.text("current: main\n"), expect: .malformed),
            Cell(name: "空檔", marker: Self.text(""), expect: .malformed),
            Cell(name: "第二個 format: 行（歧義）", marker: Self.text("format: 12\nformat: 3\n"), expect: .malformed),
            Cell(name: "未知頂層行 meta: {（#112 繞法）", marker: Self.text("meta: {\nformat: 12\n"), expect: .malformed),
            Cell(name: "縮排的非註解行", marker: Self.text("format: 12\n  indented: x\n"), expect: .malformed),
            // 這一格是縮排守衛的**唯一**鑑別點：拿掉守衛後上一格仍會落到「未知的頂層行」而照樣被拒，
            // 只有縮排的 *format* 行會被錯誤接受。
            Cell(name: "縮排的 format 行", marker: Self.text("  format: 12\n"), expect: .malformed),
            Cell(name: "format: 0（版號須 >= 1）", marker: Self.text("format: 0\n"), expect: .malformed),
            Cell(name: "format: 2.5（值後不是註解）", marker: Self.text("format: 2.5\n"), expect: .malformed),
            Cell(name: "format: 12 garbage", marker: Self.text("format: 12 garbage\n"), expect: .malformed),
            Cell(name: "非 UTF-8", marker: Self.raw(Array("format: ".utf8) + [0xFF, 0xFE] + Array("12\n".utf8)), expect: .malformed),
            Cell(name: "讀不到（chmod 000）", marker: .unreadablePermissions, expect: .unreadable),
            Cell(name: "store.yaml 是目錄", marker: .directory, expect: .unreadable),
            Cell(name: "版號太新（tooNew）", marker: Self.text("format: \(sup + 1)\n"), expect: .tooNew),
            // ── 數值解析：Swift 的 Int(String) 只吃 ASCII 數字且超出 Int64 回 nil ──
            Cell(name: "全形數字 format: １２", marker: Self.text("format: １２\n"), expect: .malformed),
            Cell(name: "天城體數字 format: १२", marker: Self.text("format: १२\n"), expect: .malformed),
            Cell(name: "阿拉伯數字 format: ١٢", marker: Self.text("format: ١٢\n"), expect: .malformed),
            Cell(name: "Int64 上界 9223372036854775807", marker: Self.text("format: 9223372036854775807\n"), expect: .tooNew),
            Cell(name: "Int64 溢位 9223372036854775808", marker: Self.text("format: 9223372036854775808\n"), expect: .malformed),
            Cell(name: "超大版號（26 位）", marker: Self.text("format: 99999999999999999999999999\n"), expect: .malformed),
            // ── grapheme vs code point：`#` 後緊跟 grapheme extender 時該行不是註解（兩個方向都要有格子）──
            Cell(name: "# + combining acute（註解行）", marker: Self.raw([0x23, 0xCC, 0x81] + Array(" c\nformat: 12\n".utf8)), expect: .malformed),
            Cell(name: "# + VS16（註解行）", marker: Self.raw([0x23, 0xEF, 0xB8, 0x8F] + Array(" c\nformat: 12\n".utf8)), expect: .malformed),
            Cell(name: "# + ZWJ（註解行）", marker: Self.raw([0x23, 0xE2, 0x80, 0x8D] + Array(" c\nformat: 12\n".utf8)), expect: .malformed),
            Cell(name: "#️⃣ keycap 序列（註解行）", marker: Self.raw([0x23, 0xEF, 0xB8, 0x8F, 0xE2, 0x83, 0xA3] + Array(" s\nformat: 12\n".utf8)), expect: .malformed),
            Cell(name: "值後註解 # + combining acute", marker: Self.raw(Array("format: 12 ".utf8) + [0x23, 0xCC, 0x81] + Array("c\n".utf8)), expect: .malformed),
            // 這五格各取一個代表：前四個是 general category 近似會漏掉的（讀端拒開卻被報成健康），最後一個是
            // 近似會多含的（Unicode 把某些 Mc 排除在 GCB=SpacingMark 之外，讀端不併入 cluster，好檔被說壞）。
            Cell(name: "# + U+200C ZWNJ（Cf，終端機看不見）", marker: Self.raw([0x23, 0xE2, 0x80, 0x8C] + Array(" x\nformat: 12\n".utf8)), expect: .malformed),
            Cell(name: "# + U+0E33 泰文 SARA AM（Lo）", marker: Self.raw([0x23, 0xE0, 0xB8, 0xB3] + Array(" x\nformat: 12\n".utf8)), expect: .malformed),
            Cell(name: "# + U+1F3FB emoji modifier（Sk）", marker: Self.raw([0x23, 0xF0, 0x9F, 0x8F, 0xBB] + Array(" x\nformat: 12\n".utf8)), expect: .malformed),
            Cell(name: "# + U+FF9E 半形濁音（Lm）", marker: Self.raw([0x23, 0xEF, 0xBE, 0x9E] + Array(" x\nformat: 12\n".utf8)), expect: .malformed),
            Cell(name: "# + U+102B 緬甸文 Mc（GCB=Other）", marker: Self.raw([0x23, 0xE1, 0x80, 0xAB] + Array(" x\nformat: 12\n".utf8)), expect: .accept),
            Cell(name: "值後 # + U+200C", marker: Self.raw(Array("format: 12 ".utf8) + [0x23, 0xE2, 0x80, 0x8C] + Array("x\n".utf8)), expect: .malformed),
            Cell(name: "值後 # + U+102B", marker: Self.raw(Array("format: 12 ".utf8) + [0x23, 0xE1, 0x80, 0xAB] + Array("x\n".utf8)), expect: .accept),
            // ── 前導零：Python 3.11+ 的 int() 有位數上限，Swift 逐位解析不受影響 ──
            Cell(name: "5000 個前導零 + 1", marker: Self.text("format: \(zeros)1\n"), expect: .accept),
            Cell(name: "前導零 + Int64 上界", marker: Self.text("format: 000009223372036854775807\n"), expect: .tooNew),
            Cell(name: "前導零 + Int64 上界加一", marker: Self.text("format: 000009223372036854775808\n"), expect: .malformed),
            // ── U+200B ZWSP：Foundation 的 CharacterSet.whitespaces 含它（Cf，不是 Zs），五種位置讀端全部接受 ──
            Cell(name: "ZWSP 在 format: 之後", marker: Self.raw(Array("format:".utf8) + [0xE2, 0x80, 0x8B] + Array(" 12\n".utf8)), expect: .accept),
            Cell(name: "ZWSP 在值之後", marker: Self.raw(Array("format: 12".utf8) + [0xE2, 0x80, 0x8B, 0x0A]), expect: .accept),
            Cell(name: "ZWSP 在 # 註解行之前", marker: Self.raw([0xE2, 0x80, 0x8B] + Array("# c\nformat: 12\n".utf8)), expect: .accept),
            Cell(name: "ZWSP 夾在值與註解之間", marker: Self.raw(Array("format: 12".utf8) + [0xE2, 0x80, 0x8B] + Array(" # c\n".utf8)), expect: .accept),
            Cell(name: "只有 ZWSP 的一行", marker: Self.raw([0xE2, 0x80, 0x8B, 0x0A] + Array("format: 12\n".utf8)), expect: .accept),
            // ── BOM：讀端吃掉 BOM 正常開啟 ──
            Cell(name: "UTF-8 BOM + format: 12", marker: Self.raw([0xEF, 0xBB, 0xBF] + Array("format: 12\n".utf8)), expect: .accept),
        ]
    }

    /// 為每一格建一個最小 store（一筆 work，帶一條 venue literal 邊）並放好 marker。
    private func makeStore(_ index: Int, _ cell: Cell, base: URL) throws -> URL {
        let root = base.appendingPathComponent("s\(index)")
        try FileManager.default.createDirectory(at: root.appendingPathComponent("entities"), withIntermediateDirectories: true)
        try Data("work:\nid: 11111111-1111-1111-1111-111111111111\ncitekey: t\ntype: periodical-article\ntitle: t\nauthors:\n- literal: A\nvenues:\n- literal: V\n".utf8)
            .write(to: root.appendingPathComponent("entities/x.yaml"))
        let marker = root.appendingPathComponent("store.yaml")
        switch cell.marker {
        case .absent: break
        case .bytes(let d): try d.write(to: marker)
        case .unreadablePermissions:
            try Data("format: 12\n".utf8).write(to: marker)
            XCTAssertEqual(chmod(marker.path, 0o000), 0)
        case .directory: try FileManager.default.createDirectory(at: marker, withIntermediateDirectories: true)
        }
        return root
    }

    /// 讀端（`StoreVersion.check`）的裁決，歸到同一套四值詞彙。**判準是錯誤的種類，不是 exit code**：
    /// `StoreVersionError` 有兩個 case，第三類（marker 讀不進來）不經它，是 Cocoa 的檔案錯誤。
    private func readerVerdict(_ root: URL) -> Verdict {
        do { try StoreVersion.check(root: root); return .accept }
        catch StoreVersionError.tooNew { return .tooNew }
        catch StoreVersionError.malformed { return .malformed }
        catch { return .unreadable }
    }

    private func censusVerdict(_ root: URL) -> Verdict {
        switch LiteralCensus.readMarker(root: root.path) {
        case .absent: return .accept
        case .malformed: return .malformed
        case .unreadable: return .unreadable
        case .read(let n): return n > StoreVersion.supported ? .tooNew : .accept
        }
    }

    func testMatrixHasTheFortySixNamedShapes() {
        // 移植時是 46 格（含 `chmod 000` 與「store.yaml 是目錄」）；少了一格代表有人刪掉了一個具名形狀
        XCTAssertGreaterThanOrEqual(cells.count, 46)
        XCTAssertEqual(Set(cells.map(\.name)).count, cells.count, "格名不得重複")
        // 四種裁決都要有代表，否則矩陣退化成只驗其中幾類
        XCTAssertEqual(Set(cells.map(\.expect.rawValue)), Set(["accept", "malformed", "tooNew", "unreadable"]))
    }

    func testEveryShapeGetsTheExpectedVerdictFromTheReaderAndTheCensus() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("akashic-marker-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        defer {
            if let e = FileManager.default.enumerator(atPath: base.path) { for case let p as String in e { chmod(base.appendingPathComponent(p).path, 0o755) } }
            try? FileManager.default.removeItem(at: base)
        }
        try XCTSkipIf(geteuid() == 0, "root 讀得了 chmod 000 的檔——那一格在 root 下沒有意義")

        var failures: [String] = []
        for (i, cell) in cells.enumerated() {
            let root = try makeStore(i, cell, base: base)
            let reader = readerVerdict(root)
            let census = censusVerdict(root)
            _ = chmod(root.appendingPathComponent("store.yaml").path, 0o644)
            if reader == cell.expect && census == cell.expect { continue }
            if reader == census {
                failures.append("\(cell.name)：讀端與普查一致於 \(reader.rawValue)，但預期 \(cell.expect.rawValue) ← 規格與實作一起錯")
            } else {
                failures.append("\(cell.name)：讀端 \(reader.rawValue)、普查 \(census.rawValue)（預期 \(cell.expect.rawValue)）")
            }
        }
        XCTAssertTrue(failures.isEmpty, "\n" + failures.joined(separator: "\n"))
    }
}
