import SwiftUI

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

/// **App 的根 view,唯一跨 module 公開的表面**（#427）。
///
/// 本檔與另外三個 view 檔於 #427 從 `AkashicApp/Sources/` 搬進本 target,理由是
/// `AkashicApp/` 是獨立的 Xcode 專案、**不在任何一道防線的視野內**——`swift build`／
/// `pre-push`／`ci.yml`／14 支 plugin 守衛全部只認 SPM target。#325 把 `Entry.type`
/// 改成 enum 之後 `EntryViews.swift` 就編不過,而那個錯誤存活了一個月沒有人知道。
///
/// **public 只給這一個型別與這一個 init**:app 殼唯一用到的就是
/// `ContentView(onSwitchFile:)`。其餘 view 維持 internal——公開面越小,
/// 日後改動越不會被迫維持相容。
public struct ContentView: View {
    @Environment(AppState.self) private var state
    @State private var section: SidebarSection = .library
    @State private var selectedCitekey: String?
    /// #18：切換檔案（root view 注入,LaunchState 同步 rebind watcher）
    var onSwitchFile: (String) -> Void = { _ in }

    /// memberwise init 是 internal,跨 module 用不到——所以顯式給一個。
    public init(onSwitchFile: @escaping (String) -> Void = { _ in }) {
        self.onSwitchFile = onSwitchFile
    }

    public var body: some View {
        NavigationSplitView {
            SidebarView(section: $section, onSwitchFile: { key in
                selectedCitekey = nil   // 舊 universe 的選取無意義
                onSwitchFile(key)
            })
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
    /// #18：切換檔案（由 root view 注入——需要同時 rebind FileWatcher）
    var onSwitchFile: (String) -> Void = { _ in }

    var body: some View {
        List(selection: $section) {
            Section("總覽") {
                LabeledContent("Entries", value: "\(state.entries.count)")
                LabeledContent("People", value: "\(state.people.count)")
                LabeledContent("未解析作者", value: "\(state.unresolvedLiteralCount)")
                LabeledContent("Orphans", value: "\(state.orphanedEntries.count)")
                LabeledContent("Quarantined", value: "\(state.quarantined.count)")
                // #31：與 Quarantined 並列但語意相反——這些檔**正常載入且完整保留**，
                // 只是本 binary 看不懂其中一部分。0 時不顯示，避免噪音。
                if !state.unknownFieldFiles.isEmpty {
                    LabeledContent("較新欄位", value: "\(state.unknownFieldFiles.count)")
                        .help("這些檔含本 binary 不認得的欄位。內容已完整保留，"
                              + "但升級 CLI / akashic-mcp / App 才看得到它們。")
                }
            }
            // #263：健康總覽走**同一條路徑**（`AppState.health` ← `StoreHealth`）。
            //
            // 先前這裡的六個數字全由 `AppState` 自行推導、**完全不呼叫**
            // `AkashicService.doctor()`——那是第三條獨立實作路徑，會與 doctor **分岔**
            // （App 顯示健康而 doctor 報問題，使用者無線索知道哪個對）。App 是取代
            // Zotero 的主要 UI，只用 App 的人先前永遠不會知道 audit trail 正在腐爛。
            //
            // **沉默即健康**：`hasFindings` 為 false 時整段不出現，避免噪音（同上方
            // 「較新欄位」0 時不顯示的既有慣例）。
            if let health = state.health, health.hasFindings {
                Section("健康") {
                    if !health.crossRecordIssues.isEmpty {
                        LabeledContent("跨記錄問題", value: "\(health.crossRecordIssues.count)")
                            .help("重複 citekey／person key 等。含 severity=error 時 index "
                                  + "無法重建——那是最該先修的。")
                    }
                    if !health.layoutResidue.isEmpty {
                        LabeledContent("佈局殘留", value: "\(health.layoutResidue.count)")
                            .help("依 format／key 不該存在的檔案。")
                    }
                    if let audit = health.sourcesAudit {
                        let n = audit.orphanBlobs.count + audit.danglingEntries.count
                            + audit.malformedLines.count + audit.unreadableShards.count
                        if n > 0 {
                            LabeledContent("sources 不一致", value: "\(n)")
                                .help("blob 與 index 對不上。audit sidecar 的腐爛只會從"
                                      + "這裡看得到——它不會自己修好。")
                        }
                    }
                    if let err = health.sourcesAuditError {
                        LabeledContent("sources audit 失敗", value: "!")
                            .help(err)
                    }
                }
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
            // #18 多檔案：實體庫切換（互不相通——切換即整個 universe 換掉）
            if !state.availableFiles.isEmpty {
                Section("檔案") {
                    ForEach(state.availableFiles) { file in
                        Button {
                            onSwitchFile(file.key)
                        } label: {
                            Label(file.key, systemImage:   // display-safe-exempt: registry key，AkashicConfig decode 驗 StoreKey
                                    state.root.path == (file.path as NSString).expandingTildeInPath
                                    ? "externaldrive.fill" : "externaldrive")
                        }
                        .buttonStyle(.plain)
                    }
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
                        // 同 181-2：`displayName` 與 `memberCount` 拆行，否則整行
                        // exempt 會把前者也蓋掉（實測：換回 `library.name` 全綠）。
                        Label {
                            let n = memberCount(library.key)   // display-safe-exempt: 回傳 Int，key 只是引數
                            Text("\(library.displayName)（\(n)）")
                        } icon: {
                            Image(systemName: "books.vertical.circle")
                        }
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
