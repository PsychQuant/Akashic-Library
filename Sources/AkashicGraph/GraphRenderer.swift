import Foundation

/// Neighborhood → 文字圖格式。Mermaid（Claude artifact 原生渲染）、
/// DOT（graphviz）、GraphML（yEd / Gephi）。輸出經確定性排序，可 golden 比對。
public enum GraphRenderer {
    public static func mermaid(_ n: Neighborhood) -> String {
        // 單次 render 的 id 配發表：sanitize 撞名時掛序號，保證 raw id ↔ mermaid id 一對一。
        // （條件式 hash 後綴可被構造碰撞——R2 verify 實證，改為配發表。）
        var allocation: [String: String] = [:]
        var used = Set<String>()
        for node in n.nodes {
            var candidate = mermaidID(node.id)
            var counter = 2
            while used.contains(candidate) {
                candidate = "\(mermaidID(node.id))_\(counter)"
                counter += 1
            }
            allocation[node.id] = candidate
            used.insert(candidate)
        }
        func idOf(_ raw: String) -> String { allocation[raw] ?? mermaidID(raw) }

        var lines = ["graph LR"]
        for node in n.nodes {
            let id = idOf(node.id)
            let label = node.label
                .replacingOccurrences(of: "\\", with: "/")
                .replacingOccurrences(of: "\"", with: "'")
                .replacingOccurrences(of: "\r\n", with: " ")
                .replacingOccurrences(of: "\n", with: " ")
                .replacingOccurrences(of: "\r", with: " ")
            switch node.kind {
            case .entry: lines.append("    \(id)[\"\(label)\"]")
            case .person: lines.append("    \(id)((\"\(label)\"))")
            case .literal: lines.append("    \(id)((\"\(label)?\"))")
            case .venue: lines.append("    \(id){{\"\(label)\"}}")
            }
        }
        for edge in n.edges {
            lines.append("    \(idOf(edge.from)) -->|\(edge.kind)| \(idOf(edge.to))")
        }
        return lines.joined(separator: "\n") + "\n"
    }

    public static func dot(_ n: Neighborhood) -> String {
        var lines = ["digraph akashic {", "    rankdir=LR;"]
        for node in n.nodes {
            let shape: String
            switch node.kind {
            case .entry: shape = "box"
            case .person, .literal: shape = "ellipse"
            case .venue: shape = "hexagon"
            }
            lines.append("    \"\(dotEscape(node.id))\" [label=\"\(dotEscape(node.label))\", shape=\(shape)];")
        }
        for edge in n.edges {
            lines.append("    \"\(dotEscape(edge.from))\" -> \"\(dotEscape(edge.to))\" [label=\"\(dotEscape(edge.kind))\"];")
        }
        lines.append("}")
        return lines.joined(separator: "\n") + "\n"
    }

    /// DOT quoted string escape——label 與 id 一視同仁。
    /// 順序關鍵：先 escape 反斜線再 escape 引號，否則尾端 \ 可逃出 quoted string。
    static func dotEscape(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\r\n", with: "\\n")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\n")
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
