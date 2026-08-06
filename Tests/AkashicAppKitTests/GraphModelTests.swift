import XCTest
import CoreGraphics
@testable import AkashicCore
@testable import AkashicStoreIO
@testable import AkashicAppKit

/// #113：GraphView 的邏輯層下沉到 AkashicAppKit 使其可測。
///
/// 三組測試對應下沉的三類邏輯：
/// 1. **index 路由**（#101 缺陷類）——「用哪個 store、寫/讀哪份 index」正是 #101 R2
///    在 `rebuildIndexThenGraph()` 抓到真實 bug 的地方，build-only 檢查結構上抓不到
/// 2. **鄰域查詢 + layout 建構**——focus/depth 語意與節點集一致性
/// 3. **座標幾何**——screen/sim 互為逆變換、hit-test 命中半徑
final class GraphModelTests: XCTestCase {
    private var home: URL!
    private var root: URL!

    override func setUpWithError() throws {
        home = FileManager.default.temporaryDirectory
            .appendingPathComponent("akashic-graphhome-\(UUID().uuidString)")
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("akashic-graphroot-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        let store = LibraryStore(root: root, key: "main",
                                 environment: ["AKASHIC_HOME": home.path])
        try store.ensureLayout()
        var e1 = Entry(id: UUID(), citekey: "aaa2020first", type: "article",
                       title: "First", authors: [.key("cheng-che")], date: "2020")
        e1.akashic.relations.cites = ["bbb2021second"]
        try store.writeEntry(e1)
        try store.writeEntry(Entry(id: UUID(), citekey: "bbb2021second", type: "article",
                                   title: "Second", authors: [.literal("Ulf Olsson")], date: "2021"))
        try store.writePerson(Person(key: "cheng-che", names: ["Che Cheng"]))
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
        try? FileManager.default.removeItem(at: home)
    }

    // MARK: - index 路由（#101 缺陷類回歸）

    func testRebuildIndexRegisteredStoreWritesHomeIndexNotInStore() throws {
        let store = LibraryStore(root: root, key: "main",
                                 environment: ["AKASHIC_HOME": home.path])
        // **正面斷言目的地，而且在任何重建之前**（沙箱鐵律，同 AppStateRegistryKeyTests）：
        // 只斷言「沒長出 .akashic/」抓不到「environment 沒帶、index 寫進真實 home」的事故。
        let expected = home.appendingPathComponent("index").appendingPathComponent("main.sqlite")
        guard store.indexURL.path == expected.path else {
            XCTFail("""
                indexURL 指向沙箱外——中止以免覆寫真實資料。
                expected: \(expected.path)
                actual:   \(store.indexURL.path)
                """)
            return
        }

        try GraphModel.rebuildIndex(store: store)

        XCTAssertTrue(FileManager.default.fileExists(atPath: expected.path),
                      "帶 key 的 store：index 寫 <home>/index/<key>.sqlite")
        XCTAssertFalse(FileManager.default.fileExists(
                           atPath: root.appendingPathComponent(".akashic").path),
                       "帶 key 的 store 不得長出 in-store .akashic/（#101 R2 的實證缺陷類）")
    }

    func testRebuildIndexKeylessStoreFallsBackInStore() throws {
        // keyless：environment 刻意注入空字典——keyless 路徑不得讀任何 home
        let store = LibraryStore(root: root, key: nil, environment: [:])
        try GraphModel.rebuildIndex(store: store)
        XCTAssertTrue(FileManager.default.fileExists(
                          atPath: root.appendingPathComponent(".akashic/index.sqlite").path),
                      "keyless store 回落 in-store .akashic/index.sqlite")
    }

    // MARK: - 鄰域查詢 + layout

    func testQueryNeighborhoodContainsCitedEntryAtDepthOne() throws {
        let store = LibraryStore(root: root, key: "main",
                                 environment: ["AKASHIC_HOME": home.path])
        try GraphModel.rebuildIndex(store: store)

        let snap = try GraphModel.query(store: store, focus: "aaa2020first", depth: 1)
        // Neighborhood.focus 存的是 node id 形式（entry: 前綴），query 收的是裸 citekey
        XCTAssertEqual(snap.neighborhood.focus, "entry:aaa2020first")
        XCTAssertTrue(snap.neighborhood.nodes.contains { $0.id == "entry:aaa2020first" },
                      "焦點 entry 必在鄰域內")
        XCTAssertTrue(snap.neighborhood.nodes.contains { $0.id == "entry:bbb2021second" },
                      "depth 1 應含 cites 目標")
    }

    func testQueryLayoutNodeSetMatchesNeighborhood() throws {
        let store = LibraryStore(root: root, key: "main",
                                 environment: ["AKASHIC_HOME": home.path])
        try GraphModel.rebuildIndex(store: store)

        let snap = try GraphModel.query(store: store, focus: "aaa2020first", depth: 1)
        XCTAssertEqual(Set(snap.layout.nodes.map(\.id)),
                       Set(snap.neighborhood.nodes.map(\.id)),
                       "layout 的節點集必須與鄰域一致——漏節點畫不出來、多節點是幽靈")
        XCTAssertFalse(snap.layout.nodes.isEmpty)
    }

    func testQueryIsDeterministicForSameSeed() throws {
        let store = LibraryStore(root: root, key: "main",
                                 environment: ["AKASHIC_HOME": home.path])
        try GraphModel.rebuildIndex(store: store)

        let a = try GraphModel.query(store: store, focus: "aaa2020first", depth: 1)
        let b = try GraphModel.query(store: store, focus: "aaa2020first", depth: 1)
        XCTAssertEqual(a.layout.nodes, b.layout.nodes,
                       "同 seed 的初始佈局必須決定性——rebuild 不得讓圖形隨機跳動")
    }

    // MARK: - 座標幾何

    func testScreenSimRoundTrip() {
        let size = CGSize(width: 800, height: 600)
        let sim = CGPoint(x: 37.5, y: -21.25)
        for scale: CGFloat in [0.3, 1.0, 2.5] {
            let screen = GraphGeometry.screenPoint(sim, canvasSize: size, scale: scale)
            let back = GraphGeometry.simPoint(screen, canvasSize: size, scale: scale)
            XCTAssertEqual(back.x, sim.x, accuracy: 1e-9)
            XCTAssertEqual(back.y, sim.y, accuracy: 1e-9)
        }
    }

    func testScreenPointCentersOrigin() {
        let size = CGSize(width: 800, height: 600)
        let screen = GraphGeometry.screenPoint(.zero, canvasSize: size, scale: 2)
        XCTAssertEqual(screen, CGPoint(x: 400, y: 300), "模擬原點投影到畫布中心")
    }

    func testHitTestPicksNearestWithinRadius() {
        let layout = ForceLayout(nodeIDs: ["a", "b"], edges: [], seed: 1)
        var l = layout
        l.pin(id: "a", at: CGPoint(x: 0, y: 0))
        l.pin(id: "b", at: CGPoint(x: 100, y: 0))
        let size = CGSize(width: 400, height: 400)
        // 螢幕座標：a 在 (200,200)、b 在 (300,200)（scale 1）
        let hit = GraphGeometry.hitTest(CGPoint(x: 205, y: 202), nodes: l.nodes,
                                        canvasSize: size, scale: 1, hitRadius: 12)
        XCTAssertEqual(hit, "a")
    }

    func testHitTestOutsideRadiusReturnsNil() {
        var l = ForceLayout(nodeIDs: ["a"], edges: [], seed: 1)
        l.pin(id: "a", at: .zero)
        let size = CGSize(width: 400, height: 400)
        let hit = GraphGeometry.hitTest(CGPoint(x: 250, y: 200), nodes: l.nodes,
                                        canvasSize: size, scale: 1, hitRadius: 12)
        XCTAssertNil(hit, "超出命中半徑＝點在空白處，不得選最近節點")
    }

    func testHitTestEmptyNodesReturnsNil() {
        XCTAssertNil(GraphGeometry.hitTest(.zero, nodes: [],
                                           canvasSize: CGSize(width: 10, height: 10),
                                           scale: 1, hitRadius: 12))
    }
}
