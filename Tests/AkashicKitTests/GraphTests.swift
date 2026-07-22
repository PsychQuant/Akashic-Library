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

extension GraphTests {
    func testMermaidIDsDoNotCollideForPunctuationVariants() throws {
        // 只差標點的兩個 literal 不可映射到同一 Mermaid 節點 id
        let a = GraphRenderer.mermaidID("literal:J.Smith")
        let b = GraphRenderer.mermaidID("literal:J-Smith")
        XCTAssertNotEqual(a, b)
    }

    func testDotEscapesBackslashBeforeQuote() throws {
        var n = Neighborhood(focus: "entry:x")
        n.nodes = [GraphNode(id: "entry:x", kind: .entry, label: #"weird\"title"#)]
        let dot = GraphRenderer.dot(n)
        XCTAssertTrue(dot.contains(#"weird\\\"title"#), dot)
    }
}

extension GraphTests {
    // R2：mermaid id 配發表——可構造碰撞（a-b vs a_b）也必須分配到不同 id
    func testMermaidAllocationResolvesConstructedCollisions() throws {
        var n = Neighborhood(focus: "literal:a-b")
        n.nodes = [GraphNode(id: "literal:a-b", kind: .literal, label: "x"),
                   GraphNode(id: "literal:a_b", kind: .literal, label: "y")]
        let out = GraphRenderer.mermaid(n)
        let ids = out.split(separator: "\n").dropFirst().compactMap {
            $0.trimmingCharacters(in: .whitespaces).split(separator: "(").first?
                .split(separator: "[").first
        }.map(String.init)
        XCTAssertEqual(Set(ids).count, ids.count, "node ids 必須唯一：\(ids)")
    }

    // R2：DOT 的 quoted id 也要 escape
    func testDotEscapesQuotedIDs() throws {
        var n = Neighborhood(focus: "entry:x")
        n.nodes = [GraphNode(id: #"literal:A"Smith"#, kind: .literal, label: "A")]
        let dot = GraphRenderer.dot(n)
        XCTAssertTrue(dot.contains(#""literal:A\"Smith""#), dot)
    }
}

extension GraphTests {
    // R3：edge-only endpoint 也要進配發表，不得繞過碰撞解決
    func testEdgeOnlyEndpointGetsCollisionSafeID() throws {
        var n = Neighborhood(focus: "literal:a-b")
        n.nodes = [GraphNode(id: "literal:a-b", kind: .literal, label: "x")]
        n.edges = [GraphEdge(from: "literal:a-b", to: "literal:a_b", kind: "related")]
        let out = GraphRenderer.mermaid(n)
        let line = out.split(separator: "\n").last.map(String.init) ?? ""
        let parts = line.trimmingCharacters(in: .whitespaces)
            .components(separatedBy: " -->|related| ")
        XCTAssertEqual(parts.count, 2, line)
        XCTAssertNotEqual(parts[0], parts[1], "edge 兩端不可撞同一 id：\(line)")
    }
}
