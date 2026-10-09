import XCTest
@testable import akashic

/// #564 b36 Y1 第 10 列：`--yes` 的說明由裁決表生成，而 `update-venue --edit-name-segment` 一條腿兩種動作、只閘帶 remove 的呼叫（使用者
/// 2026-10-05 裁決第 3 點）——生成的句子先前寫得像每一次呼叫都要 `--library`／`--yes`。限定語接在腿名後面；限定語只能掛在 `.gated` 的腿上。
final class WriteGateQualifierTests: XCTestCase {
    func testYesHelpQualifiesTheEditNameSegmentLeg() {
        XCTAssertTrue(DestructiveTargetGate.yesHelp.contains("--edit-name-segment（帶 remove 的呼叫）"), DestructiveTargetGate.yesHelp)
    }

    func testQualifiersOnlyNameGatedLegs() {
        XCTAssertFalse(DestructiveTargetGate.gatedLegQualifiers.isEmpty, "空表不是通過")
        for (command, legs) in DestructiveTargetGate.gatedLegQualifiers {
            for leg in legs.keys {
                XCTAssertEqual(DestructiveTargetGate.legRulings[command]?[leg], .gated, "\(command) \(leg) 不是過閘的腿，限定語沒有對象")
            }
        }
    }
}
