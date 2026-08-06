import CoreGraphics
import Foundation
import AkashicGraph
import AkashicIndex
import AkashicStoreIO

/// Graph 分頁的邏輯層（#113）：索引重建、鄰域查詢、layout 建構。
///
/// 這些決策從 `GraphCanvasView` 下沉到這裡，是因為 `AkashicApp/` 不在 SwiftPM 測試
/// 範圍——#109 只把它納入 CI **build**，而「用哪個 store、寫/讀哪份 index」這類缺陷
/// （#101 R2 的實證：keyless 重建讓同一 store 長出兩份各自漂移的 index）不是編譯錯誤，
/// build-only 檢查結構上抓不到。view 層只留 SwiftUI 殼與 generation token 併發契約。
public enum GraphModel {

    /// 一次查詢的成果：鄰域（畫什麼）+ 初始佈局（畫在哪）。
    /// 兩者的節點集一致——layout 由 neighborhood 的節點/邊建構。
    public struct Snapshot {
        public let neighborhood: Neighborhood
        public let layout: ForceLayout
    }

    /// 外部變更後的索引重建（全庫掃描，不放在互動路徑上）。
    ///
    /// index 的**位置**由 `store` 的 key/environment 決定（#101：帶 key →
    /// `<home>/index/<key>.sqlite`；keyless → in-store `.akashic/index.sqlite`）。
    /// 呼叫端一律用 `AppState.store`，不得自己 `LibraryStore(root:)`。
    public static func rebuildIndex(store: LibraryStore) throws {
        _ = try LibraryIndex(store: store).rebuild()
    }

    /// 互動路徑（focus/depth 變更）：只查詢既有索引，不做全庫重建。
    ///
    /// `seed` 固定預設值——同一份鄰域的初始佈局必須決定性，rebuild 不得讓圖形隨機跳動。
    public static func query(store: LibraryStore, focus: String, depth: Int,
                             seed: UInt64 = 42) throws -> Snapshot {
        let builder = try GraphBuilder(indexPath: store.indexURL)
        let n = try builder.neighborhood(focus: focus, depth: depth)
        let layout = ForceLayout(
            nodeIDs: n.nodes.map(\.id),
            edges: n.edges.map { ($0.from, $0.to) },
            seed: seed)
        return Snapshot(neighborhood: n, layout: layout)
    }
}

/// Canvas 的座標幾何（#113）：繪圖、hit-test、拖曳反投影**共用同一組變換式**。
///
/// 座標契約：螢幕座標 = 畫布中心 + 模擬座標 × scale。三個消費者（繪圖投影、
/// `hitTest`、拖曳的 `simPoint` 反投影）從前各自內聯這條式子——任何一處改了
/// 縮放/平移語意，其餘兩處就靜默錯位。集中在這裡讓「互為逆變換」可被測試釘住。
///
/// **誠實邊界**：集中的是變換式，不是輸入。繪圖用 Canvas 閉包的 `size`、
/// hit-test 與拖曳用 view 的 `@State canvasSize`（經 `onChange(of: geo.size)` 同步）——
/// 兩者短暫不一致的視窗仍在 view 層，本型別管不到。
public enum GraphGeometry {

    /// 模擬座標 → 螢幕座標。
    public static func screenPoint(_ sim: CGPoint, canvasSize: CGSize,
                                   scale: CGFloat) -> CGPoint {
        CGPoint(x: canvasSize.width / 2 + sim.x * scale,
                y: canvasSize.height / 2 + sim.y * scale)
    }

    /// 螢幕座標 → 模擬座標（`screenPoint` 的逆變換；拖曳反投影用）。
    public static func simPoint(_ screen: CGPoint, canvasSize: CGSize,
                                scale: CGFloat) -> CGPoint {
        CGPoint(x: (screen.x - canvasSize.width / 2) / scale,
                y: (screen.y - canvasSize.height / 2) / scale)
    }

    /// 最近節點命中測試；超出 `hitRadius`（pt）回 nil——點在空白處不選任何節點。
    public static func hitTest(_ location: CGPoint, nodes: [ForceLayout.Node],
                               canvasSize: CGSize, scale: CGFloat,
                               hitRadius: CGFloat) -> String? {
        guard !nodes.isEmpty else { return nil }
        func distance(_ node: ForceLayout.Node) -> CGFloat {
            let p = screenPoint(node.position, canvasSize: canvasSize, scale: scale)
            return hypot(p.x - location.x, p.y - location.y)
        }
        guard let nearest = nodes.min(by: { distance($0) < distance($1) }),
              distance(nearest) <= hitRadius else { return nil }
        return nearest.id
    }
}
