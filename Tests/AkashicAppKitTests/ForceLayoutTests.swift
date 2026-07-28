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

    /// 高 degree hub（star graph）數值穩定：300 步後所有座標必須 finite 且有界。
    func testStarGraphStaysFiniteAndBounded() {
        let leaves = (0..<200).map { "leaf\($0)" }
        var layout = ForceLayout(nodeIDs: ["hub"] + leaves,
                                 edges: leaves.map { ("hub", $0) },
                                 seed: 7)
        for _ in 0..<300 { _ = layout.step() }
        for node in layout.nodes {
            XCTAssertTrue(node.position.x.isFinite && node.position.y.isFinite,
                          "\(node.id) 座標發散：\(node.position)")
            XCTAssertLessThan(abs(node.position.x), 10_000, "\(node.id) x 超界")
            XCTAssertLessThan(abs(node.position.y), 10_000, "\(node.id) y 超界")
        }
    }

    /// 完全重合的節點必須被決定論 jitter 分離，不得永遠黏住。
    func testCoincidentNodesSeparate() {
        var layout = ForceLayout(nodeIDs: ["a", "b"], edges: [], seed: 3)
        // 用 pin/unpin 把 b 疊到 a 的位置上（模擬拖曳重合）
        let aPos = layout.nodes.first { $0.id == "a" }!.position
        layout.pin(id: "b", at: aPos)
        layout.unpin(id: "b")
        for _ in 0..<50 { _ = layout.step() }
        let pos = Dictionary(uniqueKeysWithValues: layout.nodes.map { ($0.id, $0.position) })
        let d = hypot(pos["a"]!.x - pos["b"]!.x, pos["a"]!.y - pos["b"]!.y)
        XCTAssertGreaterThan(d, 1.0, "重合節點 50 步後必須分離（dx=dy=0 時斥力零向量會永遠卡住）")
    }

    func testPinnedNodeStaysPut() {
        var layout = makeLayout()
        layout.pin(id: "a", at: CGPoint(x: 100, y: 100))
        for _ in 0..<50 { _ = layout.step() }
        let a = layout.nodes.first { $0.id == "a" }!
        XCTAssertEqual(a.position, CGPoint(x: 100, y: 100))
    }
}
