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
            Section("工作台") {
                ForEach(SidebarSection.allCases) { item in
                    Label(item.rawValue, systemImage: item.systemImage)
                        .tag(item)
                }
            }
        }
        .navigationTitle("Akashic")
    }
}
