import Foundation
import CoreGraphics

/// force-directed 佈局（純邏輯，可測）：反平方斥力＋邊彈簧＋中心引力。
/// 固定 seed → 決定論輸出（測試鎖定）；Canvas 視圖以 TimelineView 驅動 step()。
public struct ForceLayout {
    public struct Node: Equatable {
        public var id: String
        public var position: CGPoint
        public var velocity: CGPoint = .zero
        public var pinned: Bool = false
    }

    public private(set) var nodes: [Node]
    let edges: [(Int, Int)]
    var indexOf: [String: Int]

    // 參數（實作層定；經收斂測試校準）
    let repulsion: CGFloat = 6_000
    let springLength: CGFloat = 120
    let springStiffness: CGFloat = 0.08
    let centering: CGFloat = 0.01
    let damping: CGFloat = 0.85
    // 數值穩定護欄（star-graph 測試校準）：高 degree hub 的彈簧力線性累加，
    // 無界積分會在數十步內發散至 NaN；力與速度都要 clamp。
    let maxForce: CGFloat = 500
    let maxVelocity: CGFloat = 60

    public init(nodeIDs: [String], edges: [(String, String)], seed: UInt64) {
        var rng = SplitMix64(seed: seed)
        var built: [Node] = []
        var index: [String: Int] = [:]
        for (i, id) in nodeIDs.enumerated() {
            index[id] = i
            // 決定論初始位置：seeded PRNG 撒在 400×400
            let x = CGFloat(rng.next() % 400_000) / 1000 - 200
            let y = CGFloat(rng.next() % 400_000) / 1000 - 200
            built.append(Node(id: id, position: CGPoint(x: x, y: y)))
        }
        nodes = built
        indexOf = index
        self.edges = edges.compactMap { pair in
            guard let a = index[pair.0], let b = index[pair.1] else { return nil }
            return (a, b)
        }
    }

    /// 一步模擬；回傳總位移（收斂判斷用）。
    @discardableResult
    public mutating func step() -> Double {
        var forces = [CGPoint](repeating: .zero, count: nodes.count)

        // 反平方斥力（全對；個人庫規模 n 小，O(n²) 可負擔）
        for i in 0..<nodes.count {
            for j in (i + 1)..<nodes.count {
                var dx = nodes[i].position.x - nodes[j].position.x
                var dy = nodes[i].position.y - nodes[j].position.y
                if dx == 0 && dy == 0 {
                    // 完全重合：方向向量退化為零，斥力永遠推不開（黏死）。
                    // 以 index pair 導出決定論 jitter 方向（不引入隨機性，保 seed 決定論）。
                    let angle = CGFloat((i &* 31 &+ j) % 360) * .pi / 180
                    dx = cos(angle) * 0.01
                    dy = sin(angle) * 0.01
                }
                let d2 = max(dx * dx + dy * dy, 1)
                let d = sqrt(d2)
                let f = repulsion / d2
                forces[i].x += f * dx / d
                forces[i].y += f * dy / d
                forces[j].x -= f * dx / d
                forces[j].y -= f * dy / d
            }
        }
        // 邊彈簧
        for (a, b) in edges {
            let dx = nodes[b].position.x - nodes[a].position.x
            let dy = nodes[b].position.y - nodes[a].position.y
            let d = max(hypot(dx, dy), 0.01)
            let f = springStiffness * (d - springLength)
            forces[a].x += f * dx / d
            forces[a].y += f * dy / d
            forces[b].x -= f * dx / d
            forces[b].y -= f * dy / d
        }
        // 中心引力 + clamp + 積分 + isFinite 恢復
        var movement = 0.0
        for i in 0..<nodes.count {
            guard !nodes[i].pinned else { continue }
            forces[i].x -= centering * nodes[i].position.x
            forces[i].y -= centering * nodes[i].position.y
            let fmag = hypot(forces[i].x, forces[i].y)
            if fmag > maxForce {
                forces[i].x *= maxForce / fmag
                forces[i].y *= maxForce / fmag
            }
            nodes[i].velocity.x = (nodes[i].velocity.x + forces[i].x) * damping
            nodes[i].velocity.y = (nodes[i].velocity.y + forces[i].y) * damping
            let vmag = hypot(nodes[i].velocity.x, nodes[i].velocity.y)
            if vmag > maxVelocity {
                nodes[i].velocity.x *= maxVelocity / vmag
                nodes[i].velocity.y *= maxVelocity / vmag
            }
            nodes[i].position.x += nodes[i].velocity.x
            nodes[i].position.y += nodes[i].velocity.y
            if !nodes[i].position.x.isFinite || !nodes[i].position.y.isFinite {
                // NaN/Inf 不可傳染整個佈局：決定論網格 reset（index 導出）
                nodes[i].position = CGPoint(x: CGFloat(i % 20) * 30 - 300,
                                            y: CGFloat(i / 20) * 30 - 300)
                nodes[i].velocity = .zero
            }
            movement += Double(hypot(nodes[i].velocity.x, nodes[i].velocity.y))
        }
        return movement
    }

    public mutating func pin(id: String, at point: CGPoint) {
        guard let i = indexOf[id] else { return }
        nodes[i].pinned = true
        nodes[i].position = point
        nodes[i].velocity = .zero
    }

    public mutating func unpin(id: String) {
        guard let i = indexOf[id] else { return }
        nodes[i].pinned = false
    }
}

/// 決定論 PRNG（SplitMix64）——Swift 內建 RNG 不保證跨版本穩定，不可用於測試鎖定。
struct SplitMix64 {
    var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
