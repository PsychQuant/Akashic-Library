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
///
/// 座標契約：繪圖、hit-test、拖曳反投影三者共用同一份 `canvasSize`（GeometryReader
/// 提供的實際尺寸）與 `scale`——螢幕座標 = center + 模擬座標 × scale。
/// 併發契約：Canvas 逐幀 step 的寫回帶 generation token；rebuild／拖曳都會使
/// generation 前進，先前排隊的舊 frame 寫回一律被拒（不會蓋掉新 layout 或 pin）。
struct GraphCanvasView: View {
    @Environment(AppState.self) private var state
    @Binding var focusCitekey: String?

    @State private var layout: ForceLayout?
    @State private var neighborhood: Neighborhood?
    @State private var depth = 1.0
    @State private var scale: CGFloat = 1.0
    @State private var canvasSize: CGSize = .zero
    @State private var generation = 0
    @State private var draggedNode: String?
    @State private var selectedNode: String?
    @State private var loadError: String?

    /// 命中半徑（pt）：超出即視為點在空白處
    private let hitRadius: CGFloat = 12

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
        // 外部變更（FileWatcher/衍生層編輯後 reload）→ 索引重建一次 + 圖形重查。
        // 索引重建只綁 reloadCount，不綁 focus/depth 互動（那只需要查詢既有索引）。
        .onChange(of: state.reloadCount) { rebuildIndexThenGraph() }
        .task { rebuildIndexThenGraph() }
        .alert("載入失敗", isPresented: Binding(
            get: { loadError != nil },
            set: { if !$0 { loadError = nil } })) {
            Button("好") { loadError = nil }
        } message: { Text(loadError ?? "") }
    }

    @ViewBuilder
    private func canvas(focus: String) -> some View {
        GeometryReader { geo in
            TimelineView(.animation(minimumInterval: 1.0 / 60)) { _ in
                Canvas { context, size in
                    guard var l = layout, let n = neighborhood else { return }
                    _ = l.step()
                    let gen = generation
                    DispatchQueue.main.async {
                        // 舊 frame 的寫回不得覆蓋 rebuild／拖曳之後的新狀態
                        if generation == gen { layout = l }
                    }

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
                }
            }
            .onChange(of: geo.size, initial: true) { _, newSize in
                canvasSize = newSize
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
                    l.pin(id: id, at: simPoint(value.location))
                    generation += 1   // 排隊中的舊 frame 不得蓋掉 pin
                    layout = l
                }
            }
            .onEnded { _ in
                if let id = draggedNode, var l = layout {
                    l.unpin(id: id)
                    generation += 1
                    layout = l
                }
                draggedNode = nil
            }
    }

    /// 螢幕座標 → 模擬座標（與繪圖共用 canvasSize/scale 的逆變換）
    private func simPoint(_ screen: CGPoint) -> CGPoint {
        CGPoint(x: (screen.x - canvasSize.width / 2) / scale,
                y: (screen.y - canvasSize.height / 2) / scale)
    }

    /// 最近節點命中測試；超出 hitRadius 回 nil（點空白處不選任何節點）
    private func hitTest(_ location: CGPoint) -> String? {
        guard let l = layout, !l.nodes.isEmpty else { return nil }
        let center = CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)
        func screenDistance(_ node: ForceLayout.Node) -> CGFloat {
            hypot(center.x + node.position.x * scale - location.x,
                  center.y + node.position.y * scale - location.y)
        }
        guard let nearest = l.nodes.min(by: { screenDistance($0) < screenDistance($1) }),
              screenDistance(nearest) <= hitRadius else { return nil }
        return nearest.id
    }

    /// 外部變更後：索引重建一次（全庫掃描，不放在互動路徑上），再重查圖形。
    private func rebuildIndexThenGraph() {
        do {
            let store = LibraryStore(root: state.root)
            _ = try LibraryIndex(store: store).rebuild()
        } catch {
            loadError = (error as? LocalizedError)?.errorDescription ?? "\(error)"
            return
        }
        rebuild()
    }

    /// 互動（focus/depth 變更）：只查詢既有索引，不做全庫重建。
    private func rebuild() {
        guard let focus = focusCitekey else { return }
        do {
            let store = LibraryStore(root: state.root)
            let builder = try GraphBuilder(indexPath: store.indexURL)
            let n = try builder.neighborhood(focus: focus, depth: Int(depth))
            neighborhood = n
            layout = ForceLayout(
                nodeIDs: n.nodes.map(\.id),
                edges: n.edges.map { ($0.from, $0.to) },
                seed: 42)
            generation += 1   // 舊 frame 的寫回全部作廢
        } catch {
            loadError = (error as? LocalizedError)?.errorDescription ?? "\(error)"
        }
    }
}
