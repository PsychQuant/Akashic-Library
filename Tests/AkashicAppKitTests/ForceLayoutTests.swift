import XCTest
@testable import AkashicAppKit

final class ForceLayoutTests: XCTestCase {
    private func makeLayout(seed: UInt64 = 42) -> ForceLayout {
        ForceLayout(nodeIDs: ["a", "b", "c", "d"],
                    edges: [("a", "b"), ("b", "c"), ("c", "a")],
                    seed: seed)
    }

    func testDeterministicWithFixedSeed() {
        var l1 = makeLayout(), l2 = makeLayout()
        for _ in 0..<50 { _ = l1.step(); _ = l2.step() }
        for (n1, n2) in zip(l1.nodes, l2.nodes) {
            XCTAssertEqual(n1.id, n2.id)
            XCTAssertEqual(n1.position.x, n2.position.x, accuracy: 1e-9)
            XCTAssertEqual(n1.position.y, n2.position.y, accuracy: 1e-9)
        }
    }

    func testDifferentSeedsDifferentLayouts() {
        var l1 = makeLayout(seed: 1), l2 = makeLayout(seed: 2)
        for _ in 0..<10 { _ = l1.step(); _ = l2.step() }
        XCTAssertNotEqual(l1.nodes[0].position, l2.nodes[0].position)
    }

    func testConvergence() {
        var layout = makeLayout()
        var movement = Double.infinity
        for _ in 0..<600 { movement = layout.step() }
        XCTAssertLessThan(movement, 1.0, "600 步後應接近收斂")
    }

    func testConnectedNodesEndCloserThanDisconnected() {
        var layout = makeLayout()
        for _ in 0..<600 { _ = layout.step() }
        let pos = Dictionary(uniqueKeysWithValues: layout.nodes.map { ($0.id, $0.position) })
        func dist(_ a: String, _ b: String) -> CGFloat {
            hypot(pos[a]!.x - pos[b]!.x, pos[a]!.y - pos[b]!.y)
        }
        XCTAssertLessThan(dist("a", "b"), dist("a", "d"))   // 有邊的比孤立點近
    }

    func testPinnedNodeStaysPut() {
        var layout = makeLayout()
        layout.pin(id: "a", at: CGPoint(x: 100, y: 100))
        for _ in 0..<50 { _ = layout.step() }
        let a = layout.nodes.first { $0.id == "a" }!
        XCTAssertEqual(a.position, CGPoint(x: 100, y: 100))
    }
}
