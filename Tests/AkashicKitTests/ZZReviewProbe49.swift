import XCTest
import Foundation
import Yams
@testable import AkashicCore

/// SCRATCH — PR #49 correctness review probe. Delete after running.
final class ZZReviewProbe49: XCTestCase {

    private func log(_ s: String) { fputs(s + "\n", stderr); fflush(stderr) }

    private func deepKeyChain(_ levels: Int) -> String {
        var s = "root: &a0 x\n"
        for i in 1...levels { s += "k\(i): &a\(i) [*a\(i-1)]\n" }
        s += "? *a\(levels)\n: 1\n"
        return s
    }

    /// Cheaper per-level construction: sequence items cost 2 estimate units per
    /// level of DEPTH instead of 3.
    private func cheapDeepChain(_ levels: Int) -> String {
        var s = "seq:\n- &a0 x\n"
        for i in 1...levels { s += "- &a\(i) [*a\(i-1)]\n" }
        s += "? *a\(levels)\n: 1\n"
        return s
    }

    func testP24_boundary() {
        let target = Int(ProcessInfo.processInfo.environment["PROBE_LEVELS"] ?? "7000")!
        let mode = ProcessInfo.processInfo.environment["PROBE_MODE"] ?? "map"
        let s = mode == "cheap" ? cheapDeepChain(target) : deepKeyChain(target)
        let est = try? AliasEventBudget.estimate(s)
        let passes = (try? AliasEventBudget.check(s, context: "t")) != nil
        log("PROBE-24 mode=\(mode) levels=\(target) bytes=\(s.utf8.count) est=\(est?.expandedNodes ?? -1) limit=\(AliasEventBudget.maxExpandedNodes) PASSES_GUARD=\(passes)")
        log("PROBE-24   would the ORIGINAL 20000 threshold have refused it? \((est?.expandedNodes ?? 0) > 20000)")
        guard passes else { log("PROBE-24 refused"); return }
        log("PROBE-24   entering EntityKind.peek…")
        do { _ = try EntityKind.peek(s); log("PROBE-24   peek OK") }
        catch { log("PROBE-24   peek threw \(type(of: error))") }
        log("PROBE-24 SURVIVED")
    }
}
