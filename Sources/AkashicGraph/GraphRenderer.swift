import Foundation

/// Neighborhood → 文字圖格式。Mermaid（Claude artifact 原生渲染）、
/// DOT（graphviz）、GraphML（yEd / Gephi）。輸出經確定性排序，可 golden 比對。
public enum GraphRenderer {
    public static func mermaid(_ n: Neighborhood) -> String {
        var lines = ["graph LR"]
        for node in n.nodes {
            let id = mermaidID(node.id)
            let label = node.label.replacingOccurrences(of: "\"", with: "'")
            switch node.kind {
            case .entry: lines.append("    \(id)[\"\(label)\"]")
            case .person: lines.append("    \(id)((\"\(label)\"))")
            case .literal: lines.append("    \(id)((\"\(label)?\"))")
            case .venue: lines.append("    \(id){{\"\(label)\"}}")
            }
        }
        for edge in n.edges {
            lines.append("    \(mermaidID(edge.from)) -->|\(edge.kind)| \(mermaidID(edge.to))")
        }
        return lines.joined(separator: "\n") + "\n"
    }

    public static func dot(_ n: Neighborhood) -> String {
        var lines = ["digraph akashic {", "    rankdir=LR;"]
        for node in n.nodes {
            let label = node.label.replacingOccurrences(of: "\"", with: "\\\"")
            let shape: String
            switch node.kind {
            case .entry: shape = "box"
            case .person, .literal: shape = "ellipse"
            case .venue: shape = "hexagon"
            }
            lines.append("    \"\(node.id)\" [label=\"\(label)\", shape=\(shape)];")
        }
        for edge in n.edges {
            lines.append("    \"\(edge.from)\" -> \"\(edge.to)\" [label=\"\(edge.kind)\"];")
        }
        lines.append("}")
        return lines.joined(separator: "\n") + "\n"
    }

    public static func graphml(_ n: Neighborhood) -> String {
        var lines = [
            "<?xml version=\"1.0\" encoding=\"UTF-8\"?>",
            "<graphml xmlns=\"http://graphml.graphdrawing.org/xmlns\">",
            "  <key id=\"label\" for=\"node\" attr.name=\"label\" attr.type=\"string\"/>",
            "  <key id=\"kind\" for=\"all\" attr.name=\"kind\" attr.type=\"string\"/>",
            "  <graph id=\"akashic\" edgedefault=\"directed\">",
        ]
        for node in n.nodes {
            lines.append("    <node id=\"\(xmlEscape(node.id))\">")
            lines.append("      <data key=\"label\">\(xmlEscape(node.label))</data>")
            lines.append("      <data key=\"kind\">\(node.kind.rawValue)</data>")
            lines.append("    </node>")
        }
        for (i, edge) in n.edges.enumerated() {
            lines.append("    <edge id=\"e\(i)\" source=\"\(xmlEscape(edge.from))\" target=\"\(xmlEscape(edge.to))\">")
            lines.append("      <data key=\"kind\">\(xmlEscape(edge.kind))</data>")
            lines.append("    </edge>")
        }
        lines.append("  </graph>")
        lines.append("</graphml>")
        return lines.joined(separator: "\n") + "\n"
    }

    static func mermaidID(_ raw: String) -> String {
        raw.unicodeScalars.map { scalar -> String in
            if CharacterSet.alphanumerics.contains(scalar) { return String(scalar) }
            return "_"
        }.joined()
    }

    static func xmlEscape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
