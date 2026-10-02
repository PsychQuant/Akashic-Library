import XCTest
import Foundation
@testable import AkashicCore
@testable import AkashicStoreIO
@testable import AkashicZoteroImport
@testable import AkashicMCPKit

/// #611 R3 verify 第 1／5／8 列：同 id 拒絕的出路要在**每一個**使用者讀得到的出口留得住——錯誤出口逐行截 400、
/// 匯入列（`DOINomination.error`）接成一行、MCP 的 `import_zotero` 列再截 512。R2 的單行訊息約 550 字、出路從第 390 字起：
/// 兩個出口都截在出路之前（MCP 列把 `dismiss-divergence` 的 UUID 切在中途）。這裡用最長的候選描述（每個 key 在擲出端截 120）量最壞情形。
final class DOINominationRowErrorTests: XCTestCase {
    private func worstCaseRefusal() -> (StoreIOError, UUID) {
        let a = String(repeating: "a", count: 160), b = String(repeating: "b", count: 160)
        let id = DeterministicUUID.forDivergence(candidateKeys: [a, b])
        func describe(_ keys: [String]) -> String {   // 與擲出端（`recordDivergence`）同形：每個 key displaySafeInvisible 120
            keys.map { "work「\(displaySafeInvisible($0, max: 120))」" }.joined(separator: "、")
        }
        return (.divergenceIdHeldByOtherCandidates(id: id, existing: describe([a + "x", b]), requested: describe([a, b]), keysDiffer: true), id)
    }

    /// 錯誤出口（CLI 頂層、MCP per-tool 錯誤）：逐行 ≤ 400、沒有一行被截、出路在第二行。
    func testEveryLineFitsTheErrorSinkAndThePathOutIsSecond() {
        let (error, id) = worstCaseRefusal()
        let shown = displaySafeErrorMultiline(error, prefix: "Error: ")
        let lines = shown.split(separator: "\n", omittingEmptySubsequences: false)
        // 沒有一行被 sink 截：sink 的輸出就是前綴加完整描述（候選描述裡的「（已截斷）」是擲出端對 160 字 key 的截斷，不是 sink 的）
        XCTAssertEqual(shown, "Error: " + (error.errorDescription ?? ""), "sink 截掉了某一行")
        for line in lines { XCTAssertLessThanOrEqual(line.count, 400, String(line)) }
        XCTAssertTrue(lines.count > 1 && lines[1].contains("akashic dismiss-divergence \(id.uuidString) --reason")
                      && lines[1].contains("resolve-divergence") && lines[1].contains("akashic_dismiss_divergence"), shown)
    }

    /// 匯入列：接成一行（不得出現字面的 `\u{000A}`），MCP payload 的列截 512 之後出路仍完整。
    func testTheImportRowKeepsThePathOutThroughTheMCPClip() throws {
        let (error, id) = worstCaseRefusal()
        let rowError = DOINomination.errorText(error)
        XCTAssertFalse(rowError.contains("\\u{000A}") || rowError.contains("\n"), "一列一行：\(rowError)")
        var report = ImportReport()
        report.doiNominations = [DOINomination(created: "alpha2025", other: "beta2025", dois: ["10.1234/x"], status: .failed, error: rowError)]
        let rows = try XCTUnwrap(AkashicService.importReportPayload(report)["doiNominations"] as? [[String: Any]])
        let shown = try XCTUnwrap(rows.first?["error"] as? String)
        XCTAssertTrue(shown.contains("akashic dismiss-divergence \(id.uuidString) --reason"), "MCP 列截 512 之後：\(shown)")
        XCTAssertTrue(shown.contains("resolve-divergence") && shown.contains("akashic_dismiss_divergence"), shown)
    }
}
