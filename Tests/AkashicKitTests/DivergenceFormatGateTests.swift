import XCTest
import Foundation
@testable import AkashicCore
@testable import AkashicStoreIO

/// #74：divergence 形狀的 format 歸屬（回填 5，使用者拍板 2026-08-07）＋
/// `writeDivergence` 的 format gate。
///
/// 判準（#131 教訓）：形狀標籤是 strict——舊 binary（format ≤ 4 世代）讀到
/// `divergence:` 標籤即整檔 quarantine，所以它是 **non-additive**、必須有版本
/// 歸屬。gate 關掉「後果一的生成路徑」：新 binary 不可能在舊 format store 裡
/// 埋下讓舊 binary quarantine 的檔。拒絕而非自動 bump——升 marker 會讓其餘
/// binary 整庫拒開，必須是使用者知情的動作。
final class DivergenceFormatGateTests: XCTestCase {

    private func makeStore(format: Int) throws -> LibraryStore {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("akashic-divgate-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: dir.appendingPathComponent("entities"), withIntermediateDirectories: true)
        try StoreVersion.write(root: dir, format: format)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        return LibraryStore(root: dir)
    }

    private var record: Divergence {
        Divergence(id: UUID(), question: "是否為同一人",
                   candidates: [DivergenceCandidate(key: "a-key", shape: .person),
                                DivergenceCandidate(key: "b-key", shape: .person)])
    }

    func testWriteRefusedBelowFormat5WithGuidance() throws {
        let store = try makeStore(format: 4)
        XCTAssertThrowsError(try store.writeDivergence(record),
                             "format 4 store 寫 divergence＝替舊 binary 埋 quarantine 地雷") { error in
            let msg = (error as? LocalizedError)?.errorDescription ?? "\(error)"
            XCTAssertTrue(msg.contains("format") && msg.contains("5"),
                          "錯誤必須指名需要的 format：\(msg)")
            XCTAssertTrue(msg.contains("store.yaml"), "錯誤必須指路怎麼升：\(msg)")
        }
        // 拒絕發生在動磁碟之前
        let files = try FileManager.default.contentsOfDirectory(
            atPath: store.root.appendingPathComponent("entities").path)
        XCTAssertTrue(files.isEmpty, "拒寫不得留檔案：\(files)")
    }

    func testWriteAllowedAtFormat5AndAbove() throws {
        for f in [5, 6] {
            let store = try makeStore(format: f)
            XCTAssertNoThrow(try store.writeDivergence(record),
                             "format \(f) 應放行")
        }
    }
}
