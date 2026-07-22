import Foundation

/// Neighborhood → 文字圖格式。Mermaid（Claude artifact 原生渲染）、
/// DOT（graphviz）、GraphML（yEd / Gephi）。輸出經確定性排序，可 golden 比對。
public enum GraphRenderer {
    public static func mermaid(_ n: Neighborhood) -> String {
        var lines = ["graph LR"]
        for node in n.nodes {
            let id = mermaidID(node.id)
            let label = node.label
                .replacingOccurrences(of: "\\", with: "/")
                .replacingOccurrences(of: "\"", with: "'")
                .replacingOccurrences(of: "\n", with: " ")
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
            // 順序關鍵：先 escape 反斜線再 escape 引號，否則尾端 \ 可逃出 quoted label
            let label = node.label
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
                .replacingOccurrences(of: "\n", with: "\\n")
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
        let sanitized = raw.unicodeScalars.map { scalar -> String in
            if CharacterSet.alphanumerics.contains(scalar) { return String(scalar) }
            return "_"
        }.joined()
        // 只差標點的 raw id 淨化後會撞同一 sanitized 字串（J.Smith / J-Smith）。
        // 附掛原字串的確定性短 hash（FNV-1a）保證不同 raw → 不同 Mermaid id。
        if sanitized == raw { return sanitized }
        return "\(sanitized)_\(fnv1a(raw))"
    }

    /// 確定性短 hash（Swift 的 hashValue 跨執行不穩定，不可用於輸出）。
    static func fnv1a(_ s: String) -> String {
        var hash: UInt32 = 2_166_136_261
        for byte in s.utf8 {
            hash ^= UInt32(byte)
            hash = hash &* 16_777_619
        }
        return String(format: "%08x", hash)
    }

    static func xmlEscape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
