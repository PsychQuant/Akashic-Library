import SwiftUI
import AkashicAppKit
import AkashicGraph
import AkashicIndex
import AkashicStoreIO

/// Graph 區塊的控制欄（content column）：focus 選擇 + depth。
struct GraphControlView: View {
    @Environment(AppState.self) private var state
    @Binding var selectedCitekey: String?
    @State private var query = ""

    var body: some View {
        List {
            Section("Focus") {
                TextField("搜尋 citekey", text: $query)
                ForEach(matches, id: \.self) { citekey in
                    Button(citekey) { selectedCitekey = citekey }
                        .buttonStyle(.plain)
                        .font(.body.monospaced())
                        .foregroundStyle(citekey == selectedCitekey ? Color.accentColor : .primary)
                }
            }
        }
        .navigationTitle("關係圖")
    }

    private var matches: [String] {
        let q = query.lowercased()
        let keys = state.entries.map(\.citekey)
        return q.isEmpty ? Array(keys.prefix(30)) : keys.filter { $0.contains(q) }.prefix(30).map { $0 }
    }
}

/// 原生 Canvas force-directed 關係圖。
struct GraphCanvasView: View {
    @Environment(AppState.self) private var state
    @Binding var focusCitekey: String?

    @State private var layout: ForceLayout?
    @State private var neighborhood: Neighborhood?
    @State private var depth = 1.0
    @State private var scale: CGFloat = 1.0
    @State private var draggedNode: String?
    @State private var selectedNode: String?
    @State private var loadError: String?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Slider(value: $depth, in: 0...3, step: 1) {
                    Text("Depth")
                } minimumValueLabel: {
                    Text("0")
                } maximumValueLabel: {
                    Text("3")
                }
                .frame(maxWidth: 240)
                Text("depth \(Int(depth))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if let selectedNode {
                    Text(selectedNode)
                        .font(.caption.monospaced())
                }
            }
            .padding(8)

            if let focus = focusCitekey {
                canvas(focus: focus)
            } else {
                ContentUnavailableView("左欄選一個 focus citekey", systemImage: "point.3.connected.trianglepath.dotted")
            }
        }
        .onChange(of: focusCitekey) { rebuild() }
        .onChange(of: depth) { rebuild() }
        .task { rebuild() }
        .alert("載入失敗", isPresented: .constant(loadError != nil)) {
            Button("好") { loadError = nil }
        } message: { Text(loadError ?? "") }
    }

    @ViewBuilder
    private func canvas(focus: String) -> some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60)) { _ in
            Canvas { context, size in
                guard var l = layout, let n = neighborhood else { return }
                _ = l.step()
                DispatchQueue.main.async { layout = l }   // step 結果寫回 state

                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                func screen(_ p: CGPoint) -> CGPoint {
                    CGPoint(x: center.x + p.x * scale, y: center.y + p.y * scale)
                }
                let positions = Dictionary(uniqueKeysWithValues: l.nodes.map { ($0.id, screen($0.position)) })

                for edge in n.edges {
                    guard let a = positions[edge.from], let b = positions[edge.to] else { continue }
                    var path = Path()
                    path.move(to: a)
                    path.addLine(to: b)
                    context.stroke(path, with: .color(.secondary.opacity(0.5)), lineWidth: 1)
                }
                for node in n.nodes {
                    guard let p = positions[node.id] else { continue }
                    let rect = CGRect(x: p.x - 6, y: p.y - 6, width: 12, height: 12)
                    let shape: Path
                    let color: Color
                    switch node.kind {
                    case .entry:
                        shape = Path(rect)
                        color = node.id == "entry:\(focus)" ? .accentColor : .blue
                    case .person, .literal:
                        shape = Path(ellipseIn: rect)
                        color = node.kind == .person ? .green : .gray
                    case .venue:
                        shape = Path(ellipseIn: rect.insetBy(dx: -2, dy: 2))
                        color = .orange
                    }
                    context.fill(shape, with: .color(node.id == selectedNode ? .red : color))
                    context.draw(Text(node.label).font(.caption2),
                                 at: CGPoint(x: p.x, y: p.y + 14))
                }
            }
            .gesture(dragGesture)
            .gesture(MagnifyGesture().onChanged { value in
                scale = min(max(value.magnification, 0.3), 3)
            })
            .onTapGesture(count: 2) { location in
                if let id = hitTest(location), id.hasPrefix("entry:") {
                    focusCitekey = String(id.dropFirst("entry:".count))   // 雙擊展開鄰域
                }
            }
            .onTapGesture { location in
                selectedNode = hitTest(location)
                if let id = selectedNode, id.hasPrefix("entry:") {
                    // 單擊 entry 節點：右欄詳情走 focus 綁定的 selectedCitekey 由父視圖處理
                }
            }
        }
    }

    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                if draggedNode == nil {
                    draggedNode = hitTest(value.startLocation)
                }
                if let id = draggedNode, var l = layout {
                    l.pin(id: id, at: canvasPoint(value.location))
                    layout = l
                }
            }
            .onEnded { _ in
                if let id = draggedNode, var l = layout {
                    l.unpin(id: id)
                    layout = l
                }
                draggedNode = nil
            }
    }

    private func canvasPoint(_ screen: CGPoint) -> CGPoint {
        // 反投影（近似：以視窗中心 600×400 為基準）
        CGPoint(x: (screen.x - 300) / scale, y: (screen.y - 200) / scale)
    }

    private func hitTest(_ location: CGPoint) -> String? {
        guard let l = layout else { return nil }
        let center = CGPoint(x: 300, y: 200)
        return l.nodes.min { a, b in
            let da = hypot(center.x + a.position.x * scale - location.x,
                           center.y + a.position.y * scale - location.y)
            let db = hypot(center.x + b.position.x * scale - location.x,
                           center.y + b.position.y * scale - location.y)
            return da < db
        }?.id
    }

    private func rebuild() {
        guard let focus = focusCitekey else { return }
        do {
            let store = LibraryStore(root: state.root)
            _ = try LibraryIndex(store: store).rebuild()
            let builder = try GraphBuilder(indexPath: store.indexURL)
            let n = try builder.neighborhood(focus: focus, depth: Int(depth))
            neighborhood = n
            layout = ForceLayout(
                nodeIDs: n.nodes.map(\.id),
                edges: n.edges.map { ($0.from, $0.to) },
                seed: 42)
        } catch {
            loadError = (error as? LocalizedError)?.errorDescription ?? "\(error)"
        }
    }
}
