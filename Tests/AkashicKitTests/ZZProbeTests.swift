import XCTest
import Foundation
import Yams

/// TEMPORARY REVIEW PROBE — delete after review. Yams-only.
final class ZZProbeTests: XCTestCase {
    func testProbeComposeCostOfPayloadFiles() throws {
        for name in ["control", "wrapped", "crlf"] {
            let path = "/tmp/abtest/\(name).yaml"
            guard let text = try? String(contentsOfFile: path, encoding: .utf8) else { continue }
            let t0 = Date()
            _ = try? Yams.compose(yaml: text)
            print("PROBE-FILE \(name) bytes=\(text.utf8.count) compose=\(String(format: "%.2f", Date().timeIntervalSince(t0)))s")
        }
    }
}
