import SwiftUI
import AkashicAppKit

enum SidebarSection: String, CaseIterable, Identifiable {
    case library = "文獻列表"
    case people = "裁決台：人物解析"
    case orphans = "裁決台：Orphans"
    case quarantine = "裁決台：Quarantine"
    case graph = "關係圖"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .library: return "books.vertical"
        case .people: return "person.2"
        case .orphans: return "questionmark.folder"
        case .quarantine: return "exclamationmark.triangle"
        case .graph: return "point.3.connected.trianglepath.dotted"
        }
    }
}

struct ContentView: View {
    @Environment(AppState.self) private var state
    @State private var section: SidebarSection = .library
    @State private var selectedCitekey: String?

    var body: some View {
        NavigationSplitView {
            SidebarView(section: $section)
        } content: {
            switch section {
            case .library:
                EntryListView(selectedCitekey: $selectedCitekey)
            case .people:
                PeopleResolveView()
            case .orphans:
                OrphanView()
            case .quarantine:
                QuarantineView()
            case .graph:
                GraphControlView(selectedCitekey: $selectedCitekey)
            }
        } detail: {
            if section == .graph {
                GraphCanvasView(focusCitekey: $selectedCitekey)
            } else if let citekey = selectedCitekey {
                EntryDetailView(citekey: citekey, selectedCitekey: $selectedCitekey)
            } else {
                ContentUnavailableView("選一筆文獻", systemImage: "doc.text.magnifyingglass")
            }
        }
        .frame(minWidth: 1000, minHeight: 640)
    }
}

/// Library 健康總覽（doctor 的視覺版）+ 區塊切換。
struct SidebarView: View {
    @Environment(AppState.self) private var state
    @Binding var section: SidebarSection

    var body: some View {
        List(selection: $section) {
            Section("總覽") {
                LabeledContent("Entries", value: "\(state.entries.count)")
                LabeledContent("People", value: "\(state.people.count)")
                LabeledContent("未解析作者", value: "\(state.unresolvedLiteralCount)")
                LabeledContent("Orphans", value: "\(state.orphanedEntries.count)")
                LabeledContent("Quarantined", value: "\(state.quarantined.count)")
            }
            // 外部變更同步提示（spec §6 的 write-through 落地：沒有草稿緩衝可遺失，
            // 但外部剛更新畫面時要讓使用者知道）
            if let syncedAt = state.lastExternalSyncAt {
                Section {
                    Label("外部變更已同步 \(syncedAt.formatted(date: .omitted, time: .shortened))",
                          systemImage: "arrow.triangle.2.circlepath")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            // #13 多 library：具名成員集合視角切換（store 是全集，view 只過濾）
            Section("Libraries") {
                Button {
                    state.filterLibrary = nil
                } label: {
                    Label("全部（\(state.entries.count)）", systemImage: "infinity")
                        .fontWeight(state.filterLibrary == nil ? .semibold : .regular)
                }
                .buttonStyle(.plain)
                ForEach(state.libraries, id: \.key) { library in
                    Button {
                        state.filterLibrary = library.key
                    } label: {
                        Label("\(library.name)（\(memberCount(library.key))）",
                              systemImage: "books.vertical.circle")
                            .fontWeight(state.filterLibrary == library.key ? .semibold : .regular)
                    }
                    .buttonStyle(.plain)
                }
            }
            Section("工作台") {
                ForEach(SidebarSection.allCases) { item in
                    Label(item.rawValue, systemImage: item.systemImage)
                        .tag(item)
                }
            }
        }
        .navigationTitle("Akashic")
    }

    private func memberCount(_ key: String) -> Int {
        state.entries.filter { $0.akashic.libraries.contains(key) }.count
    }
}
