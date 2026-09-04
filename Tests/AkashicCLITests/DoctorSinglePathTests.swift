import Foundation
import XCTest

/// #504：CLI `doctor` 是 `StoreHealth` 之外的第四條讀取路徑——它自己算 cross-record、殘留、sources audit
/// 並自行渲染，而 MCP `doctor()`、CLI `validate`、App 都走 `health(from:)`。`entity-backlink-completeness`
/// 執行細節 2 的分岔形：#453／#464 加進 health 的掃描，CLI doctor 一個都看不到。本測試以源碼掃描釘住
/// 「`Doctor.run` 只讀 `health.*`」；輸出文字不在本測試範圍（那由既有 CLI 測試釘）。
final class DoctorSinglePathTests: XCTestCase {
    private func commandsSource() throws -> String {
        let repo = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: repo.appendingPathComponent("Sources/akashic/Commands.swift"), encoding: .utf8)
    }

    private func doctorBody() throws -> String {
        let src = try commandsSource()
        guard let start = src.range(of: "struct Doctor: ParsableCommand {"),
              let end = src.range(of: "struct Validate: ParsableCommand {") else {
            XCTFail("找不到 Doctor／Validate 的邊界——本測試的前提不成立"); return ""
        }
        return String(src[start.lowerBound..<end.lowerBound])
    }

    func testDoctorReadsHealthFactsFromStoreHealth() throws {
        let body = try doctorBody()
        for needle in ["store.health(from:", "health.crossRecordIssues", "health.fatalCrossRecordIssues",
                       "health.layoutResidue", "health.sourcesAudit", "health.sourcesAuditError"] {
            XCTAssertTrue(body.contains(needle), "Doctor.run 沒有從 StoreHealth 讀 \(needle)")
        }
    }

    func testDoctorDoesNotRecomputeWhatStoreHealthAlreadyHolds() throws {
        let body = try doctorBody()
        for forbidden in ["auditSourceIndex()", "layoutResidue()", "crossRecordIssues()"] {
            XCTAssertFalse(body.contains(forbidden),
                           "Doctor.run 仍直接呼叫 \(forbidden)——那是 health(from:) 之外的第二條路徑（#504）")
        }
    }
}
