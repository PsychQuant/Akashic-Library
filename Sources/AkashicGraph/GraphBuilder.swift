import Foundation
import AkashicSQLite

public struct GraphNode: Equatable {
    public enum Kind: String, Equatable {
        case entry, person, literal, venue
    }

    public var id: String
    public var kind: Kind
    public var label: String

    public init(id: String, kind: Kind, label: String) {
        self.id = id
        self.kind = kind
        self.label = label
    }
}

public struct GraphEdge: Equatable, Hashable {
    public var from: String
    public var to: String
    public var kind: String

    public init(from: String, to: String, kind: String) {
        self.from = from
        self.to = to
        self.kind = kind
    }
}

public struct Neighborhood: Equatable {
    public var focus: String
    public var nodes: [GraphNode]
    public var edges: [GraphEdge]

    public init(focus: String, nodes: [GraphNode] = [], edges: [GraphEdge] = []) {
        self.focus = focus
        self.nodes = nodes
        self.edges = edges
    }
}

public enum GraphError: Error, LocalizedError {
    case unknownCitekey(String)

    public var errorDescription: String? {
        switch self {
        case .unknownCitekey(let key): return "index 中找不到 citekey：\(key)"
        }
    }
}

/// 以某節點為中心的 N 度鄰域展開（BFS）。
/// 節點：entry / person（已解析）/ literal（未解析作者）/ venue（期刊字串）。
/// 邊：authored-by / published-in / cites / related。
public struct GraphBuilder {
    let db: SQLiteDB

    public init(indexPath: URL) throws {
        db = try SQLiteDB(path: indexPath.path, readOnly: true)
    }

    public func neighborhood(focus citekey: String, depth: Int) throws -> Neighborhood {
        guard let focusRow = try db.query(
            "SELECT * FROM entries WHERE citekey = ?", bind: [citekey]).first else {
            throw GraphError.unknownCitekey(citekey)
        }

        var nodes: [String: GraphNode] = [:]
        var edges = Set<GraphEdge>()
        let focusID = "entry:\(citekey)"
        nodes[focusID] = entryNode(focusRow)

        var frontier: [String] = [focusID]
        for _ in 0..<max(depth, 0) {
            var next: [String] = []
            for nodeID in frontier {
                let discovered = try expand(nodeID: nodeID, nodes: &nodes, edges: &edges)
                next.append(contentsOf: discovered)
            }
            frontier = next
            if frontier.isEmpty { break }
        }

        return Neighborhood(
            focus: focusID,
            nodes: nodes.values.sorted { $0.id < $1.id },
            edges: edges.sorted {
                ($0.from, $0.kind, $0.to) < ($1.from, $1.kind, $1.to)
            })
    }

    /// 展開一個節點，回傳新發現的節點 id。
    private func expand(nodeID: String, nodes: inout [String: GraphNode],
                        edges: inout Set<GraphEdge>) throws -> [String] {
        var discovered: [String] = []

        func addNode(_ node: GraphNode) {
            if nodes[node.id] == nil {
                nodes[node.id] = node
                discovered.append(node.id)
            }
        }

        if nodeID.hasPrefix("entry:") {
            let citekey = String(nodeID.dropFirst("entry:".count))
            guard let row = try db.query(
                "SELECT * FROM entries WHERE citekey = ?", bind: [citekey]).first,
                let uuid = row["uuid"] as? String else { return discovered }

            // authored-by
            for a in try db.query(
                "SELECT person_key, literal FROM authors WHERE entry_uuid = ? ORDER BY position",
                bind: [uuid]) {
                if let key = a["person_key"] as? String {
                    addNode(GraphNode(id: "person:\(key)", kind: .person, label: personLabel(key)))
                    edges.insert(GraphEdge(from: nodeID, to: "person:\(key)", kind: "authored-by"))
                } else if let literal = a["literal"] as? String {
                    addNode(GraphNode(id: "literal:\(literal)", kind: .literal, label: literal))
                    edges.insert(GraphEdge(from: nodeID, to: "literal:\(literal)", kind: "authored-by"))
                }
            }
            // published-in
            if let journal = row["journal"] as? String, !journal.isEmpty {
                addNode(GraphNode(id: "venue:\(journal)", kind: .venue, label: journal))
                edges.insert(GraphEdge(from: nodeID, to: "venue:\(journal)", kind: "published-in"))
            }
            // cites（出向）＋ related（出向）
            for r in try db.query(
                "SELECT kind, target FROM relations WHERE from_uuid = ?", bind: [uuid]) {
                guard let kind = r["kind"] as? String, let target = r["target"] as? String else { continue }
                if let targetID = try resolveEntryNode(target, addNode: addNode) {
                    edges.insert(GraphEdge(from: nodeID, to: targetID, kind: kind))
                }
            }
            // cites（入向：誰引用我）＋ related（入向）
            for r in try db.query("""
                SELECT r.kind AS kind, e.citekey AS fromCitekey FROM relations r
                JOIN entries e ON e.uuid = r.from_uuid
                WHERE r.target = ? OR r.target = ?
                """, bind: [citekey, uuid]) {
                guard let kind = r["kind"] as? String,
                      let fromCitekey = r["fromCitekey"] as? String else { continue }
                if let fromRow = try db.query(
                    "SELECT * FROM entries WHERE citekey = ?", bind: [fromCitekey]).first {
                    addNode(entryNode(fromRow))
                    edges.insert(GraphEdge(from: "entry:\(fromCitekey)", to: nodeID, kind: kind))
                }
            }
        } else if nodeID.hasPrefix("person:") {
            let key = String(nodeID.dropFirst("person:".count))
            for row in try db.query("""
                SELECT e.* FROM entries e JOIN authors a ON a.entry_uuid = e.uuid
                WHERE a.person_key = ?
                """, bind: [key]) {
                guard let citekey = row["citekey"] as? String else { continue }
                addNode(entryNode(row))
                edges.insert(GraphEdge(from: "entry:\(citekey)", to: nodeID, kind: "authored-by"))
            }
        } else if nodeID.hasPrefix("venue:") {
            let journal = String(nodeID.dropFirst("venue:".count))
            for row in try db.query(
                "SELECT * FROM entries WHERE lower(journal) = lower(?)", bind: [journal]) {
                guard let citekey = row["citekey"] as? String else { continue }
                addNode(entryNode(row))
                edges.insert(GraphEdge(from: "entry:\(citekey)", to: nodeID, kind: "published-in"))
            }
        }
        // literal 節點不展開（未解析作者無反向索引語意——升格 person 後才有）
        return discovered
    }

    private func resolveEntryNode(_ target: String,
                                  addNode: (GraphNode) -> Void) throws -> String? {
        if let row = try db.query(
            "SELECT * FROM entries WHERE citekey = ? OR uuid = ?",
            bind: [target, target]).first,
            let citekey = row["citekey"] as? String {
            addNode(entryNode(row))
            return "entry:\(citekey)"
        }
        // 庫外引用：以 citekey 佔位節點呈現（library 還沒有這篇）
        let id = "entry:\(target)"
        addNode(GraphNode(id: id, kind: .entry, label: target))
        return id
    }

    private func entryNode(_ row: [String: Any]) -> GraphNode {
        let citekey = row["citekey"] as? String ?? "?"
        let title = row["title"] as? String ?? ""
        let truncated = title.count > 40 ? String(title.prefix(37)) + "…" : title
        return GraphNode(id: "entry:\(citekey)", kind: .entry,
                         label: truncated.isEmpty ? citekey : "\(citekey)：\(truncated)")
    }

    private func personLabel(_ key: String) -> String {
        if let row = try? db.query("SELECT names FROM people WHERE key = ?", bind: [key]).first,
           let names = row["names"] as? String,
           let first = names.split(separator: "\n").first {
            return String(first)
        }
        return key
    }
}
