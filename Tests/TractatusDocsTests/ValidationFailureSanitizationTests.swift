import XCTest
import AkashicCore
@testable import TractatusDocs

/// #554 R32（R31 verify 第 11／41 列）：`TractatusValidationFailure` 自 R31 起宣告 `SanitizedErrorDescription`，所以它的 `errorDescription`
/// **整個**都要逃過一次——`incompleteness`（`ConstructionGap.formatted`）那一半在 R31 原樣拼接，守衛因 `diagnostics.map(\.formatted)` 那一半就綠。
final class ValidationFailureSanitizationTests: XCTestCase {
    func testBothHalvesOfTheDescriptionAreEscapedOnce() {
        let d = CorpusDiagnostic(path: "vol\u{200B}1.yaml", recordID: "1.1", code: "bad\u{7}", message: "msg\u{202E}")
        let f = TractatusValidationFailure(diagnostics: [d], incompleteness: ["incomplete: missing-proposition 1.2\u{200B}"])
        let text = f.errorDescription ?? ""
        XCTAssertTrue(text.contains("1.2\\u{200B}"), text)
        XCTAssertTrue(text.contains("vol\\u{200B}1.yaml") && text.contains("bad\\u{0007}") && text.contains("msg\\u{202E}"), text)
        XCTAssertFalse(text.unicodeScalars.contains { $0.value == 0x200B || $0.value == 0x7 || $0.value == 0x202E }, text)
        XCTAssertFalse(text.contains("\\u{005C}"), "二次逃脫：\(text)")
        XCTAssertTrue((f as Error) is SanitizedErrorDescription)
        XCTAssertEqual(displaySafeErrorMultiline(f), text, "自帶消毒：Error → 文字只截、不再逃")
    }
}
