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

    /// **沙箱守衛的唯一構造入口**（verify F6）：構造 + 目的地斷言必須是同一個動作。
    ///
    /// 第一版只有第一個測試帶守衛，其餘三個裸構造——「有人把重複構造抽成 helper 時
    /// 弄丟 `environment:`」正是 `AppStateRegistryKeyTests` 記錄過、**實際發生過一次**的
    /// 事故形狀（key 留著 → indexURL 指向真實 `~/.akashic/index/main.sqlite`，rebuild
    /// 原子覆寫使用者的真索引）。守衛住在 helper 裡，漏不掉。
    ///
    /// keyless 也注入沙箱 home 而非 `[:]`（verify F8）：keyless 路徑今天確實不讀
    /// environment，但 `[:]` 不是安全網——`AkashicHome.directory(environment: [:])`
    /// 落到**真實** home。萬一將來哪條路徑讀了它，sentinel 要指向沙箱。
    private func sandboxStore(key: String?) throws -> LibraryStore {
        let store = LibraryStore(root: root, key: key,
                                 environment: ["AKASHIC_HOME": home.path])
        let sandboxes = [home.path, root.path]
        guard sandboxes.contains(where: { store.indexURL.path.hasPrefix($0 + "/") }) else {
            struct SandboxViolation: Error {}
            XCTFail("""
                indexURL 指向沙箱外——中止以免覆寫真實資料。
                actual: \(store.indexURL.path)
                """)
            throw SandboxViolation()
        }
        return store
    }

    // MARK: - index 路由（#101 缺陷類回歸）

    func testRebuildIndexRegisteredStoreWritesHomeIndexNotInStore() throws {
        let store = try sandboxStore(key: "main")
        // **正面斷言目的地，而且在任何重建之前**（沙箱鐵律，同 AppStateRegistryKeyTests）：
        // 只斷言「沒長出 .akashic/」抓不到「environment 沒帶、index 寫進真實 home」的事故。
        let expected = home.appendingPathComponent("index").appendingPathComponent("main.sqlite")
        XCTAssertEqual(store.indexURL.path, expected.path,
                       "帶 key 的 store：index 位置由注入的 AKASHIC_HOME 決定")

        try GraphModel(store: store).rebuildIndex()

        XCTAssertTrue(FileManager.default.fileExists(atPath: expected.path),
                      "帶 key 的 store：index 寫 <home>/index/<key>.sqlite")
        XCTAssertFalse(FileManager.default.fileExists(
                           atPath: root.appendingPathComponent(".akashic").path),
                       "帶 key 的 store 不得長出 in-store .akashic/（#101 R2 的實證缺陷類）")
    }

    func testRebuildIndexKeylessStoreFallsBackInStore() throws {
        let store = try sandboxStore(key: nil)
        try GraphModel(store: store).rebuildIndex()
        XCTAssertTrue(FileManager.default.fileExists(
                          atPath: root.appendingPathComponent(".akashic/index.sqlite").path),
                      "keyless store 回落 in-store .akashic/index.sqlite")
    }

    // MARK: - 鄰域查詢 + layout

    func testQueryNeighborhoodContainsCitedEntryAtDepthOne() throws {
        let store = try sandboxStore(key: "main")
        try GraphModel(store: store).rebuildIndex()

        let snap = try GraphModel(store: store).query(focus: "aaa2020first", depth: 1)
        // Neighborhood.focus 存的是 node id 形式（entry: 前綴），query 收的是裸 citekey
        XCTAssertEqual(snap.neighborhood.focus, "entry:aaa2020first")
        XCTAssertTrue(snap.neighborhood.nodes.contains { $0.id == "entry:aaa2020first" },
                      "焦點 entry 必在鄰域內")
        XCTAssertTrue(snap.neighborhood.nodes.contains { $0.id == "entry:bbb2021second" },
                      "depth 1 應含 cites 目標")
    }

    func testQueryLayoutNodeSetMatchesNeighborhood() throws {
        let store = try sandboxStore(key: "main")
        try GraphModel(store: store).rebuildIndex()

        let snap = try GraphModel(store: store).query(focus: "aaa2020first", depth: 1)
        XCTAssertEqual(Set(snap.layout.nodes.map(\.id)),
                       Set(snap.neighborhood.nodes.map(\.id)),
                       "layout 的節點集必須與鄰域一致——漏節點畫不出來、多節點是幽靈")
        XCTAssertFalse(snap.layout.nodes.isEmpty)
    }

    func testQueryIsDeterministicForSameSeed() throws {
        let store = try sandboxStore(key: "main")
        try GraphModel(store: store).rebuildIndex()

        let a = try GraphModel(store: store).query(focus: "aaa2020first", depth: 1)
        let b = try GraphModel(store: store).query(focus: "aaa2020first", depth: 1)
        XCTAssertEqual(a.layout.nodes, b.layout.nodes,
                       "同 seed 的初始佈局必須決定性——rebuild 不得讓圖形隨機跳動")
    }

    func testQueryPassesNeighborhoodEdgesToLayout() throws {
        // Codex M5：把 query 內的 edges 換成 [] 時整組測試仍綠——節點集斷言看不出
        // 邊有沒有進 layout。初始位置只依 (seed, 節點數)，**step 一次之後**引力才讓
        // 「帶邊」與「無邊」的佈局分岔。
        let store = try sandboxStore(key: "main")
        try GraphModel(store: store).rebuildIndex()
        let snap = try GraphModel(store: store).query(focus: "aaa2020first", depth: 1)
        XCTAssertFalse(snap.neighborhood.edges.isEmpty, "前置：fixture 必須至少有一條邊")

        let ids = snap.neighborhood.nodes.map(\.id)
        var actual = snap.layout
        var expected = ForceLayout(nodeIDs: ids,
                                   edges: snap.neighborhood.edges.map { ($0.from, $0.to) },
                                   seed: 42)
        var edgeless = ForceLayout(nodeIDs: ids, edges: [], seed: 42)
        _ = actual.step()
        _ = expected.step()
        _ = edgeless.step()
        XCTAssertEqual(actual.nodes, expected.nodes,
                       "step 後與帶邊的 expected 一致——邊真的傳進 layout 了")
        XCTAssertNotEqual(actual.nodes, edgeless.nodes,
                          "step 後必須與無邊版分岔——否則上面的相等斷言是空洞的")
    }

    func testQueryHonorsDepthAndFocusArguments() throws {
        // Codex L7：全部查詢測試都用同一 focus + depth 1——「實作把 depth 寫死成 1」
        // 或「把 focus 寫死成 fixture 的 citekey」的變異全綠。depth 0 的鄰域不含
        // cites 目標、第二個 focus 的鄰域以它自己為中心，兩個變異都被殺死。
        let store = try sandboxStore(key: "main")
        try GraphModel(store: store).rebuildIndex()

        let d0 = try GraphModel(store: store).query(focus: "aaa2020first", depth: 0)
        XCTAssertFalse(d0.neighborhood.nodes.contains { $0.id == "entry:bbb2021second" },
                       "depth 0 不含 cites 目標——depth 被寫死成 1 就會出現")

        let other = try GraphModel(store: store).query(focus: "bbb2021second", depth: 0)
        XCTAssertEqual(other.neighborhood.focus, "entry:bbb2021second",
                       "focus 參數真的被轉發——寫死 fixture citekey 就會回錯中心")
    }

    func testQueryDefaultSeedIsDocumentedValue() throws {
        // verify F4：42 從 view 的字面量變成了預設參數——「可重複」不等於「值沒變」。
        // 初始佈局只依 (seed, 節點數)，預設值被silently改掉會讓每張圖搬家而無測試變紅。
        let store = try sandboxStore(key: "main")
        try GraphModel(store: store).rebuildIndex()

        let defaulted = try GraphModel(store: store).query(focus: "aaa2020first", depth: 1)
        let explicit = try GraphModel(store: store).query(focus: "aaa2020first", depth: 1, seed: 42)
        XCTAssertEqual(defaulted.layout.nodes, explicit.layout.nodes,
                       "預設 seed 必須是文件化的 42")
        let other = try GraphModel(store: store).query(focus: "aaa2020first", depth: 1, seed: 7)
        XCTAssertNotEqual(other.layout.nodes, defaulted.layout.nodes,
                          "不同 seed 產生不同初始佈局——否則上面的相等斷言是空洞的")
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

    func testScreenPointMultipliesByScale() {
        // Codex M4：round-trip 對「除以 scale」的錯誤實作也成立（sim/scale 與
        // (screen-center)*scale 仍互逆、原點測試分不出）——zoom 語意會整個反轉。
        // 非原點、非 unit scale 的直接投影斷言才釘住「乘」這個契約。
        let screen = GraphGeometry.screenPoint(CGPoint(x: 10, y: -20),
                                               canvasSize: CGSize(width: 400, height: 400),
                                               scale: 2)
        XCTAssertEqual(screen, CGPoint(x: 220, y: 160),
                       "screen = center + sim × scale（除法實作會得 (205,190)）")
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

    func testHitTestPicksNearestWhenBothInRadius() {
        // Codex L6：上一個測試的 b 在半徑外——「回第一個在半徑內的」錯誤實作也綠。
        // 兩節點都在半徑內、較遠的排前面，nearest 與 first-inside 才分得出來。
        var l = ForceLayout(nodeIDs: ["far", "near"], edges: [], seed: 1)
        l.pin(id: "far", at: CGPoint(x: 8, y: 0))    // screen (208,200)，距 probe 8
        l.pin(id: "near", at: CGPoint(x: 2, y: 0))   // screen (202,200)，距 probe 2
        let size = CGSize(width: 400, height: 400)
        let hit = GraphGeometry.hitTest(CGPoint(x: 200, y: 200), nodes: l.nodes,
                                        canvasSize: size, scale: 1, hitRadius: 12)
        XCTAssertEqual(hit, "near", "重疊命中時取最近者，不是陣列順序在前者")
    }

    func testHitTestOutsideRadiusReturnsNil() {
        var l = ForceLayout(nodeIDs: ["a"], edges: [], seed: 1)
        l.pin(id: "a", at: .zero)
        let size = CGSize(width: 400, height: 400)
        let hit = GraphGeometry.hitTest(CGPoint(x: 250, y: 200), nodes: l.nodes,
                                        canvasSize: size, scale: 1, hitRadius: 12)
        XCTAssertNil(hit, "超出命中半徑＝點在空白處，不得選最近節點")
    }

    func testHitTestExactlyAtRadiusHits() {
        // verify F3：邊界是**含**的（<=）。恰好距 12pt 的點必須命中。
        var l = ForceLayout(nodeIDs: ["a"], edges: [], seed: 1)
        l.pin(id: "a", at: .zero)
        let size = CGSize(width: 400, height: 400)
        let hit = GraphGeometry.hitTest(CGPoint(x: 212, y: 200), nodes: l.nodes,
                                        canvasSize: size, scale: 1, hitRadius: 12)
        XCTAssertEqual(hit, "a", "距離恰等於 hitRadius 必須命中——邊界是含的")
    }

    func testHitTestDependsOnScale() {
        // verify F1：hit-test 從未在 scale ≠ 1 下被測過——「hitTest 內部把 scale
        // 寫死成 1」的變異在原測試組全綠。同一個 probe 點在不同 scale 下命中結果
        // 必須不同，這才釘住「scale 真的參與投影」。
        var l = ForceLayout(nodeIDs: ["a"], edges: [], seed: 1)
        l.pin(id: "a", at: CGPoint(x: 20, y: 0))
        let size = CGSize(width: 400, height: 400)
        let probe = CGPoint(x: 250, y: 200)
        XCTAssertEqual(GraphGeometry.hitTest(probe, nodes: l.nodes, canvasSize: size,
                                             scale: 2.5, hitRadius: 12), "a",
                       "scale 2.5：節點投影到 (250,200)，probe 距 0——命中")
        XCTAssertNil(GraphGeometry.hitTest(probe, nodes: l.nodes, canvasSize: size,
                                           scale: 1, hitRadius: 12),
                     "scale 1：節點在 (220,200)，probe 距 30 > 12——忽略 scale 就會誤命中")
    }

    func testHitTestEmptyNodesReturnsNil() {
        XCTAssertNil(GraphGeometry.hitTest(.zero, nodes: [],
                                           canvasSize: CGSize(width: 10, height: 10),
                                           scale: 1, hitRadius: 12))
    }
    /// #125 第二層：`rebuildIndex` 與 `query` 共用構造時決定的 store——「兩個呼叫
    /// 拿到不同 store」在型別上不可表達（#101 的事故形狀）。這條測試釘住的是
    /// **同一個實例的兩次呼叫指向同一份 index**；若日後有人把方法改回 static 收
    /// store 參數，這裡的寫法會編不過。
    /// **shape pin，不是回歸網**（#160 verify 160-2 的措辭下修）：它釘住
    /// 「`GraphModel` 是可實例化的、init 原樣保存 store」這個形狀，讓改回 static
    /// 或在 init 裡重造 store 都編不過／變紅。但套件層級的偵測能力沒有增加——
    /// 它殺得死的 mutation，既有的 #101 測試都殺得死。
    func testInstanceSharesStoreAcrossRebuildAndQuery() throws {
        let store = try sandboxStore(key: "main")
        let model = GraphModel(store: store)
        try model.rebuildIndex()
        let snap = try model.query(focus: "aaa2020first", depth: 1)
        XCTAssertFalse(snap.neighborhood.nodes.isEmpty,
                       "同一實例：rebuild 寫的 index 就是 query 讀的那份")
        // #160 verify 160-2：原本這裡的註解寫「store 是 let——實例存續期間不可
        // 換掉（型別層保證）」。**那是這條測試驗不了的**——`let` 是編譯器的事，
        // runtime 斷言碰不到；席位實測把 `let` 改成 `var`，954 tests 全綠。
        //
        // 它實際釘住的只有「init 有沒有把你給的 store 原樣存起來」（丟掉 key 的
        // mutation 確實會殺死它）——但同一個 mutation 也被既有的 #101 測試殺死，
        // 所以這條**沒有 unique kill**。保留為 shape pin，不宣稱是回歸網。
        XCTAssertEqual(model.store.key, "main", "init 不得改動傳入的 store（含 registry key）")
        XCTAssertEqual(model.store.indexURL, store.indexURL)
    }

}
