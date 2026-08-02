import SwiftUI
import AkashicAppKit
import AkashicCore

struct EntryListView: View {
    @Environment(AppState.self) private var state
    @Binding var selectedCitekey: String?

    var body: some View {
        @Bindable var state = state
        List(state.filteredEntries, id: \.citekey, selection: $selectedCitekey) { entry in
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.title.isEmpty ? entry.citekey : entry.title)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(entry.citekey)
                        .font(.caption.monospaced())
                    if let date = entry.date {
                        Text(date)
                            .font(.caption)
                    }
                    if entry.provenance?.orphanedAt != nil {
                        Text("orphan")
                            .font(.caption2)
                            .padding(.horizontal, 4)
                            .background(.orange.opacity(0.3), in: Capsule())
                    }
                }
                .foregroundStyle(.secondary)
            }
            .padding(.vertical, 2)
        }
        .searchable(text: $state.searchText, placement: .sidebar, prompt: "搜尋 citekey/標題/作者")
        .navigationTitle("文獻（\(state.filteredEntries.count)）")
    }
}

struct EntryDetailView: View {
    @Environment(AppState.self) private var state
    let citekey: String
    @Binding var selectedCitekey: String?

    @State private var newTag = ""
    @State private var renameTarget = ""
    @State private var showRename = false
    @State private var errorMessage: String?

    private var entry: Entry? {
        state.entries.first { $0.citekey == citekey }
    }

    var body: some View {
        if let entry {
            Form {
                Section("書目（唯讀——過渡期歸 Zotero pull 管）") {
                    LabeledContent("Citekey") {
                        HStack {
                            Text(entry.citekey).font(.body.monospaced())
                            Button("改名…") {
                                renameTarget = entry.citekey
                                showRename = true
                            }
                        }
                    }
                    LabeledContent("Type", value: entry.type)
                    LabeledContent("Title", value: entry.title)
                    LabeledContent("Authors", value: entry.authors.map(\.displayName).joined(separator: "; "))
                    if let date = entry.date { LabeledContent("Date", value: date) }
                    ForEach(entry.fields.keys.sorted(), id: \.self) { key in
                        LabeledContent(key, value: entry.fields[key] ?? "")
                    }
                }
                Section("衍生層（可編輯）") {
                    libraryEditor(entry)   // #15
                    Picker("Status", selection: statusBinding(entry)) {
                        Text("（無）").tag(String?.none)
                        ForEach(["to-read", "reading", "read", "published"], id: \.self) {
                            Text($0).tag(String?.some($0))
                        }
                    }
                    tagEditor(entry)
                    RelationEditorView(citekey: entry.citekey, kind: .cites, title: "Cites",
                                       values: entry.akashic.relations.cites,
                                       selectedCitekey: $selectedCitekey,
                                       errorMessage: $errorMessage)
                    RelationEditorView(citekey: entry.citekey, kind: .related, title: "Related",
                                       values: entry.akashic.relations.related,
                                       selectedCitekey: $selectedCitekey,
                                       errorMessage: $errorMessage)
                }
            }
            .formStyle(.grouped)
            .navigationTitle(entry.citekey)
            .alert("改名 citekey", isPresented: $showRename) {
                TextField("新 citekey", text: $renameTarget)
                    .font(.body.monospaced())
                Button("改名（搬檔＋全庫引用遷移）") { performRename(from: entry.citekey) }
                Button("取消", role: .cancel) {}
            } message: {
                Text("UUID 不變；引用此 citekey 的 relations 會一併改寫。")
            }
            .alert("操作失敗", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } })) {
                Button("好") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        } else {
            ContentUnavailableView("找不到 \(citekey)", systemImage: "questionmark.circle")
        }
    }

    private func statusBinding(_ entry: Entry) -> Binding<String?> {
        Binding(get: { entry.akashic.status },
                set: { newValue in
                    attempt { try state.setStatus(citekey: entry.citekey, status: newValue) }
                })
    }

    /// #15：membership 編輯。
    ///
    /// **刻意不做成 tags 那樣的自由輸入**——library key 是**參照**，打錯會產生懸空成員
    /// 關係（entry 說它屬於某個 library，而那個 library 不存在）。改用選單，讓不合法的
    /// 輸入從一開始就不可能，而不是事後由 `doctor` 報 warning。
    @ViewBuilder
    private func libraryEditor(_ entry: Entry) -> some View {
        let available = state.availableLibraries(for: entry.citekey)
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Libraries").foregroundStyle(.secondary)
                Spacer()
                if available.isEmpty {
                    Text(state.libraries.isEmpty ? "（registry 無 library）" : "（已全部加入）")
                        .font(.caption).foregroundStyle(.tertiary)
                } else {
                    Menu("加入…") {
                        ForEach(available, id: \.key) { lib in
                            Button(lib.name.isEmpty ? lib.key : "\(lib.name)（\(lib.key)）") {
                                attempt {
                                    try state.addToLibrary(citekey: entry.citekey,
                                                           libraryKey: lib.key)
                                }
                            }
                        }
                    }
                    .menuStyle(.borderlessButton).fixedSize()
                }
            }
            if entry.akashic.libraries.isEmpty {
                Text("（未加入任何 library）").font(.caption).foregroundStyle(.tertiary)
            } else {
                HStack {
                    ForEach(entry.akashic.libraries, id: \.self) { key in
                        HStack(spacing: 2) {
                            Text(key).font(.caption)
                            Button {
                                attempt {
                                    try state.removeFromLibrary(citekey: entry.citekey,
                                                                libraryKey: key)
                                }
                            } label: {
                                Image(systemName: "xmark.circle.fill").font(.caption2)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(.quaternary, in: Capsule())
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func tagEditor(_ entry: Entry) -> some View {
        VStack(alignment: .leading) {
            HStack {
                ForEach(entry.akashic.tags, id: \.self) { tag in
                    HStack(spacing: 2) {
                        Text(tag).font(.caption)
                        Button {
                            attempt { try state.removeTag(citekey: entry.citekey, tag: tag) }
                        } label: {
                            Image(systemName: "xmark.circle.fill").font(.caption2)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.quaternary, in: Capsule())
                }
            }
            HStack {
                TextField("新 tag", text: $newTag)
                Button("加入") {
                    guard !newTag.isEmpty else { return }
                    attempt { try state.addTag(citekey: entry.citekey, tag: newTag) }
                    newTag = ""
                }
            }
        }
    }

    private func performRename(from oldKey: String) {
        attempt {
            try state.rename(from: oldKey, to: renameTarget)
            selectedCitekey = renameTarget
        }
    }

    private func attempt(_ action: () throws -> Void) {
        do {
            try action()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "\(error)"
        }
    }
}

/// Relation 編輯列。獨立 View 讓 Cites／Related 各自持有輸入框狀態——
/// 共用同一個 @State 會讓兩欄輸入互相鏡射。
struct RelationEditorView: View {
    @Environment(AppState.self) private var state
    let citekey: String
    let kind: AppState.RelationKind
    let title: String
    let values: [String]
    @Binding var selectedCitekey: String?
    @Binding var errorMessage: String?

    @State private var newRelation = ""

    var body: some View {
        VStack(alignment: .leading) {
            Text(title).font(.headline)
            ForEach(values, id: \.self) { target in
                HStack {
                    Button(target) { selectedCitekey = target }
                        .buttonStyle(.link)
                        .font(.body.monospaced())
                    Button {
                        attempt { try state.removeRelation(citekey: citekey, kind: kind, target: target) }
                    } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.plain)
                }
            }
            HStack {
                TextField("目標 citekey（可為庫外）", text: $newRelation)
                    .font(.body.monospaced())
                Button("加入 \(title)") {
                    guard !newRelation.isEmpty else { return }
                    attempt { try state.addRelation(citekey: citekey, kind: kind, target: newRelation) }
                    newRelation = ""
                }
            }
        }
    }

    private func attempt(_ action: () throws -> Void) {
        do {
            try action()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "\(error)"
        }
    }
}
