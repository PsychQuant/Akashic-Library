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
///
/// **持有單一 store 的實例**（#125 第二層）：`rebuildIndex` 與 `query` 從前是
/// 兩個各收一個 `LibraryStore` 的 static func——「兩個呼叫必須拿到同一個 store」
/// 只寫在註解裡，型別不擋。#101 的事故形狀（keyless 重建寫進另一份 index、query
/// 讀不到）因此在型別上仍可重演，而 `AkashicApp/` 不在測試範圍、編得過就過。
///
/// 改成實例後，**API 允許**把 store 綁定一次、兩個方法共用。
///
/// **誠實邊界（下修過的宣稱——#160 verify 兩席獨立指出原文過度）**：
///
/// 1. **「在型別上不可表達」只對單一實例的兩次呼叫成立，而生產程式碼沒有採用
///    那個模式。** `GraphView.swift:199` 與 `:211` 各自 `GraphModel(store: state.store)`
///    ——兩個獨立實例、分屬兩個函式。席位把 #125 issue body 的事故程式碼逐字
///    翻成新 API，**編得過而且重現同一個事故**（keyless 重建在已註冊 store 裡長出
///    `.akashic/index.sqlite`、query 開不了檔）。
///
///    **今天沒事靠兩條腿，而承重的是第一條**（#160 verify 160-8）：
///    (a) 兩個站點都傳 `state.store`——全 `AkashicApp/Sources/` 的 `LibraryStore(`
///        出現 **0 次**。但這條**只有註解在擋**（`// #101：一律走 state.store`），
///        正是 #125 要取代的那種擋法。
///    (b) 兩個呼叫在 `rebuildIndexThenGraph()` 內 MainActor 同步相鄰，
///        `root`/`storeKey` 來不及被 `switchFile` 改——**時序上確定**（呼叫鏈是
///        同步的，不是巧合）。
///
///    先前只寫了 (b)，會讓讀者以為剩下的風險是時序問題（聽起來像併發細節）；
///    真正的風險是**構造紀律**，也就是 #125 本體。這一層提供了機制，事故現場
///    尚未啟用它。
/// 2. ~~**它擋不住 `GraphModel(store: LibraryStore(root:))`**~~ ——**#125 已修**：
///    本型別的 init 只收 `ResolvedStore`，那行現在編不過。
///
///    先前的估計是「動 170 個構造點（production 12、tests 158）」——那是全 repo
///    的 `LibraryStore(` 總數。**實際只需要動 `GraphModel` 的 21 個**（production 2、
///    tests 19），因為收工判準只關乎這一個型別。把 `ResolvedStore` 推廣到其他
///    消費端仍是另案，但**那不是本判準要的東西**。
///
///    估計偏高 8 倍的原因值得記：它量的是「有多少地方建 store」，而要回答的是
///    「有多少地方**把 store 交給會誤用它的東西**」。
///
/// 為什麼不直接 hoist 成單一 binding（那才會讓保證生效）：`AppState.store` 是
/// **computed property**，每次存取用當下的 `root`/`storeKey` 現造一顆，而那兩個是
/// `private(set) var`（`switchFile` 會改）。被持有的實例切檔後會指著舊 library
/// （席位實測 `stale=true`）。要 hoist 就得連同重建契約一起做——`FileWatcher` 已有
/// 正確範本（`AkashicApp.swift:53-82` 的 `switchFile` 負責重建 watcher），但那是
/// 另一個改動的體量。#125 追蹤。
public struct GraphModel {

    /// 一次查詢的成果：鄰域（畫什麼）+ 初始佈局（畫在哪）。
    /// 兩者的節點集一致——layout 由 neighborhood 的節點/邊建構。
    public struct Snapshot {
        public let neighborhood: Neighborhood
        public let layout: ForceLayout
    }

    /// 構造時決定 store——之後的所有操作都用它（見型別 doc 的誠實邊界）。
    ///
    /// **插入位置紀律**（#160 verify 160-4（正典計數與三次機械化失敗的量測在 `docs/design-principles-and-philosophy.md` §16——**不要在原始碼裡各自重新計數**，那正是它一直過期的原因））：
    /// 這個 property 當初被插進 `rebuildIndex` 的 doc comment 與它的宣告
    /// 之間，於是那段 doc 掛到了 property 上、方法自己零註解。被孤兒化的正是
    /// 「呼叫端一律用 `AppState.store`，不得自己 `LibraryStore(root:)`」——本型別
    /// 誠實邊界第 2 條所依賴的那句話。**新成員不得插進既有 API 的 doc 與宣告之間。**
    public let store: LibraryStore

    /// **只收 `ResolvedStore`**（#125 第三層）。
    ///
    /// `GraphModel(store: LibraryStore(root: x))` 現在**編不過**——那正是 #125
    /// issue body 那段事故程式碼的形狀，而它在 #160 之後仍然編得過、逐字重現同一個
    /// 事故（keyless 重建在已註冊 store 裡長出 in-store index，query 開不了檔）。
    ///
    /// #101 之後靠的是一句註解（「呼叫端一律用 `AppState.store`」）。註解擋不住新的
    /// 呼叫點，也擋不住重構。這個 init 把它變成型別事實。
    public init(store: ResolvedStore) {
        self.store = store.store
    }

    /// 外部變更後的索引重建（全庫掃描，不放在互動路徑上）。
    ///
    /// index 的**位置**由 `store` 的 key/environment 決定（#101：帶 key →
    /// `<home>/index/<key>.sqlite`；keyless → in-store `.akashic/index.sqlite`）。
    /// 呼叫端一律用 `AppState.store`，不得自己 `LibraryStore(root:)`。
    public func rebuildIndex() throws {
        _ = try LibraryIndex(store: store).rebuild()
    }

    /// 互動路徑（focus/depth 變更）：只查詢既有索引，不做全庫重建。
    ///
    /// `seed` 固定預設值——同一份鄰域的初始佈局必須決定性，rebuild 不得讓圖形隨機跳動。
    public func query(focus: String, depth: Int, seed: UInt64 = 42) throws -> Snapshot {
        // #130 交叉引用：這裡直接開 index、不驗身分（App 是三面中唯一如此的）
        // ——身分驗證屬 #130 的值域（incarnation id + isCurrent），不在本層修。
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
