import XCTest
@testable import AkashicCore
@testable import AkashicStoreIO
@testable import AkashicIndex
@testable import AkashicGraph

final class GraphTests: XCTestCase {
    var root: URL!
    var store: LibraryStore!
    var builder: GraphBuilder!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("akashic-graph-\(UUID().uuidString)")
        store = LibraryStore(root: root)
        try store.ensureLayout()
        try QueryFixture.populate(store)
        _ = try LibraryIndex(store: store).rebuild()
        builder = try GraphBuilder(indexPath: store.indexURL)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    func testDepthZeroIsFocusOnly() throws {
        let n = try builder.neighborhood(focus: "cheng2025identifiability", depth: 0)
        XCTAssertEqual(n.nodes.map(\.id), ["entry:cheng2025identifiability"])
        XCTAssertTrue(n.edges.isEmpty)
    }

    func testDepthOneCoversAllEdgeKinds() throws {
        let n = try builder.neighborhood(focus: "cheng2025identifiability", depth: 1)
        let ids = Set(n.nodes.map(\.id))
        XCTAssertTrue(ids.contains("entry:cheng2025identifiability"))
        XCTAssertTrue(ids.contains("person:cheng-che"))
        XCTAssertTrue(ids.contains("literal:Hau-Hung Yang"))
        XCTAssertTrue(ids.contains("venue:Psychometrika"))
        XCTAssertTrue(ids.contains("entry:olsson1979maximum"))      // cites
        XCTAssertTrue(ids.contains("entry:foldnes2019bivariate"))   // related
        let kinds = Set(n.edges.map(\.kind))
        XCTAssertEqual(kinds, ["authored-by", "published-in", "cites", "related"])
    }

    func testDepthTwoReachesCoauthoredEntryViaPerson() throws {
        let depth1 = try builder.neighborhood(focus: "chen2004matrix", depth: 1)
        XCTAssertFalse(depth1.nodes.map(\.id).contains("entry:chen2010gap"))
        let depth2 = try builder.neighborhood(focus: "chen2004matrix", depth: 2)
        XCTAssertTrue(depth2.nodes.map(\.id).contains("entry:chen2010gap"))
    }

    func testCitedByAppearsAsIncomingCitesEdge() throws {
        let n = try builder.neighborhood(focus: "olsson1979maximum", depth: 1)
        XCTAssertTrue(n.edges.contains(GraphEdge(
            from: "entry:cheng2025identifiability", to: "entry:olsson1979maximum", kind: "cites")))
    }

    func testMermaidOutput() throws {
        let n = try builder.neighborhood(focus: "cheng2025identifiability", depth: 1)
        let mermaid = GraphRenderer.mermaid(n)
        XCTAssertTrue(mermaid.hasPrefix("graph LR"))
        XCTAssertTrue(mermaid.contains("-->|cites|"))
        XCTAssertTrue(mermaid.contains("Psychometrika"))
        // 同一 neighborhood render 兩次結果一致（確定性排序）
        XCTAssertEqual(mermaid, GraphRenderer.mermaid(n))
    }

    func testDotOutput() throws {
        let n = try builder.neighborhood(focus: "cheng2025identifiability", depth: 1)
        let dot = GraphRenderer.dot(n)
        XCTAssertTrue(dot.hasPrefix("digraph akashic"))
        XCTAssertTrue(dot.contains("label=\"cites\""))
    }

    func testGraphMLOutput() throws {
        let n = try builder.neighborhood(focus: "cheng2025identifiability", depth: 1)
        let xml = GraphRenderer.graphml(n)
        XCTAssertTrue(xml.contains("<graphml"))
        XCTAssertTrue(xml.contains("</graphml>"))
        XCTAssertTrue(xml.contains("entry:cheng2025identifiability"))
    }
}
