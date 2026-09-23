import SwiftUI
import AkashicCore
import AkashicStoreIO

struct EntryListView: View {
    @Environment(AppState.self) private var state
    @Binding var selectedCitekey: String?

    var body: some View {
        @Bindable var state = state
        List(state.filteredEntries, id: \.citekey, selection: $selectedCitekey) { entry in
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.displayTitleOrCitekey)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(entry.citekey)   // display-safe-exempt: citekey 過 load 端 quarantine（StoreKey）
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
                    // #605：同一作品在其他 Zotero library 也有一份。
                    if !entry.additionalProvenance.isEmpty {
                        Text("＋\(entry.additionalProvenance.count) 來源")
                            .font(.caption2)
                            .padding(.horizontal, 4)
                            .background(.blue.opacity(0.15), in: Capsule())
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
    /// #465：改名後的回執（舊 key、新 key、遷移報告）——非 nil 即彈出摘要。
    @State private var renameOutcome: RenameOutcome?

    struct RenameOutcome {
        let from: String
        let to: String
        let report: RenameReport
        /// 部分成功（#492）：改名已落盤，但索引重建／重載失敗。非 nil 即在同一個回執上加標。
        ///
        /// **成功與部分成功用同一個回執**，不是兩條路：兩者的共同事實是「全庫已經被改寫了
        /// 這些東西」，而那正是使用者需要看到的。差別只在索引跟上了沒有。
        var reloadFailure: String? = nil
    }

    private var entry: Entry? {
        state.entries.first { $0.citekey == citekey }
    }

    var body: some View {
        // 三個 alert 掛在 Group 上（if／else 兩個分支之外）：回執「看不看得到」不該綁在
        // 「記錄找不找得到」上（verify DA-4／regression #4）。
        Group {
        if let entry {
            Form {
                Section("書目（唯讀——過渡期歸 Zotero pull 管）") {
                    LabeledContent("Citekey") {
                        HStack {
                            Text(entry.citekey).font(.body.monospaced())   // display-safe-exempt: 同上
                            Button("改名…") {
                                renameTarget = entry.citekey
                                showRename = true
                            }
                        }
                    }
                    LabeledContent("Type", value: entry.type.rawValue)
                    LabeledContent("Title", value: entry.displayTitle)
                    // `Author.displayName` 不消毒（#161 verify 181-4）——走投影
                    LabeledContent("Authors", value: entry.displayAuthors)
                    if let date = entry.date { LabeledContent("Date", value: date) }
                    // **識別碼**（#394 verify R4）。App 是 `entity-backlink-completeness`
                    // 執行細節 2 明文列舉的**第三個**讀取面（#263 特地把它補進列舉，
                    // 理由是「App 是取代 Zotero 的主要 UI，只用 App 的人永遠不會知道
                    // audit trail 正在腐爛」）。
                    //
                    // **這不是 pre-existing**：§8 遷移**之前** DOI 住 `fields.doi`，
                    // 下面那個泛用迴圈自動印得出來；遷移把 664 筆搬進結構化欄位之後，
                    // 這一面就再也印不出任何一筆——而 CLI／MCP 同時印得出來，
                    // 於是同一個 store 的兩個面對「這筆有沒有 DOI」給出相反的答案。
                    //
                    // 讀 `canonical*`：遷移略過的記錄仍把值放在 `fields` 殘留裡，
                    // 而使用者要看的是「這筆有沒有 DOI」不是「它存在哪一層」。
                    if !entry.canonicalDOIs.isEmpty {
                        LabeledContent("DOI",
                                       value: entry.canonicalDOIs.map(\.normalized)
                                           .joined(separator: ", "))
                    }
                    if !entry.canonicalPMIDs.isEmpty {
                        LabeledContent("PMID",
                                       value: entry.canonicalPMIDs.map(\.normalized)
                                           .joined(separator: ", "))
                    }
                    if !entry.canonicalISBNs.isEmpty {
                        LabeledContent("ISBN",
                                       value: entry.canonicalISBNs.map(\.normalized)
                                           .joined(separator: ", "))
                    }
                    // **載體**（第 14 條邊，#304）與**學位論文事實**（#335）——App 是
                    // 第三個讀取面，而 #426 之前三面同時看不到這兩者。
                    //
                    // 這裡是獨立的第三條實作路徑（CLI 與 MCP 共用 `entryDict`），
                    // 所以要分別改。那正是 `entity-backlink-completeness` 執行細節 2
                    // 說的「一個 entity kind 的讀取面只能有一條實作路徑」對 entry
                    // **尚未成立**的地方——venue 那面已收斂，entry 這面還沒有。
                    //
                    // 二態 ref 標出未歸戶而不冒充 identity（執行細節 3）：`.literal`
                    // 加註記，讓使用者一眼看得出哪些還沒歸戶。
                    if !entry.venues.isEmpty {
                        LabeledContent("Venues",
                                       value: entry.venues.map { v in
                                           switch v {
                                           // key 過 load 端 quarantine（StoreKey），
                                           // literal 是 WoS／Zotero 的第三方原文——
                                           // 與 `authors` 的 literal 同源，要消毒。
                                           case .key(let k):
                                               return k   // display-safe-exempt: StoreKey quarantine
                                           case .literal(let s):
                                               return "\(displaySafe(s, max: 400))（未歸戶）"
                                           }
                                       }.joined(separator: ", "))
                    }
                    if let thesis = entry.thesis {
                        if let degree = thesis.degree {
                            LabeledContent("Degree", value: degree.rawValue)
                        }
                        switch thesis.availability {
                        case .unpublished:
                            LabeledContent("Availability", value: "unpublished")
                        case .published(let repository, let url):
                            LabeledContent("Availability",
                                           value: [ "published", repository, url ]
                                               .compactMap { $0 }.joined(separator: " · "))
                        case nil:
                            EmptyView()   // 未查——不顯示，缺席即「不知道」
                        }
                    }
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
            .navigationTitle(entry.citekey)   // display-safe-exempt: 同上
        } else {
            ContentUnavailableView("找不到 \(citekey)", systemImage: "questionmark.circle")   // display-safe-exempt: citekey 過 load 端 quarantine（LibraryStore.swift 的 StoreKey.isValid 檢查）
        }
        }
        .alert("改名 citekey", isPresented: $showRename) {
            TextField("新 citekey", text: $renameTarget)
                .font(.body.monospaced())
            // 沒改就不執行：不然一次不編輯的點擊會得到「已改名／0／0／0」，與真改名同形（verify DA-2）。
            // `.disabled` 在各版 macOS 的 alert 按鈕上不保證生效，`performRename` 一定再擋一次。
            Button("改名（搬檔＋全庫引用遷移）") { performRename(from: citekey) }
                .disabled(renameTarget.isEmpty || renameTarget == citekey)
            Button("取消", role: .cancel) {}
        } message: {
            Text("UUID 不變；引用此 citekey 的 relations 會一併改寫。")
        }
        // 「已改名」是在上面那個 alert 的按鈕閉包裡被要求呈現的（同一次更新內關一個、開一個）。
        // 本 repo 兩個既有先例同形（同檔的「操作失敗」自 #11 起、AdjudicationViews 的 dialog→alert），
        // 且這裡用衍生 binding（`renameOutcome != nil`）——呈現若被丟棄，下次 body 求值會重新算出
        // 「想呈現」，比儲存的 Bool 耐用。**未實機量測**；量到負結果時才把設定延到下一個 runloop。
        // 標題隨部分成功變（#492）：同一個回執，但「索引沒跟上」要在標題就看得到——
        // 使用者可能只看標題就按「好」。
        .alert(Text(EntryDetailView.renameAlertTitle(renameOutcome)),
               isPresented: Binding(
            get: { renameOutcome != nil },
            set: { if !$0 { renameOutcome = nil } })) {
            Button("好") { renameOutcome = nil }
        } message: {
            Text(renameOutcome.map(EntryDetailView.renameMessage) ?? "")   // display-safe-exempt: RenameReportSummary 對每個 key 套 displaySafe(max: 200)（與 CLI rename 同立場）；underlying 在下方 renameMessage 內過 displaySafe
        }
        .alert("操作失敗", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } })) {
            Button("好") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
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
                            Button(lib.name.isEmpty ? lib.key : "\(lib.displayName)（\(lib.key)）") {   // display-safe-exempt: lib.key 過 load 端 quarantine（key 不符 StoreKey 即整筆隔離）
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
        // 與按鈕的 disabled 同一條件再擋一次（alert 按鈕的 disabled 在各版 macOS 上不保證生效）——
        // 所以承諾是「沒改就不執行」，不是「不能按」。
        guard !renameTarget.isEmpty, renameTarget != oldKey else {
            errorMessage = "新 citekey 與現在的相同（或為空），沒有改名"
            return
        }
        // **rename 刻意不走 `attempt`**（#492）。它是同檔唯一「失敗時仍有東西要呈現」的
        // 操作——`attempt` 的契約是「錯誤就是一句話」，而部分成功時錯誤裡帶著一份報告。
        // #492 的另一個候選是改 `attempt` 的簽名，但那要動同檔 8 個呼叫點去服務一個操作：
        // 成本放在錯的地方，而且會讓其餘 7 個呼叫點帶著一個它們永遠用不到的參數。
        do {
            // #465：`RenameReport` 不再丟掉——CLI 面印三類連帶改寫，App 面先前一句不說
            // （`entity-backlink-completeness` 執行細節 2：三面同一條路徑，App 這面把輸出丟了）。
            let report = try state.rename(from: oldKey, to: renameTarget)
            selectedCitekey = renameTarget
            renameOutcome = RenameOutcome(from: oldKey, to: renameTarget, report: report)
        } catch AppStateError.renamedButReloadFailed(let report, let underlying) {
            // 磁碟上改名**已經完成**。選新 key：清單是舊快照所以會顯示「找不到記錄」，
            // 而那正是實情（App 的視圖過期了）；停在舊 key 則會顯示一筆磁碟上已不存在的
            // 記錄——那是說謊。回執本身掛在 if／else 之外，兩種情況都看得到（#465 DA-4）。
            selectedCitekey = renameTarget
            renameOutcome = RenameOutcome(from: oldKey, to: renameTarget, report: report,
                                          reloadFailure: underlying)
        } catch {
            errorMessage = displaySafeErrorMultiline(error)
        }
    }

    // 摘要住在 `RenameReportSummary`（View 之外的 nonisolated formatter）——`AppStateError` 也用它。

    /// 回執標題。抽成 static 是為了**可測**——「標題會變」若只寫在 View 的行內三元式裡，
    /// 就只是一句斷言（`assertions-must-be-measured`）。
    nonisolated static func renameAlertTitle(_ o: RenameOutcome?) -> String {
        o?.reloadFailure == nil ? "已改名" : "已改名，但索引未重建"
    }

    /// 回執本文。成功與部分成功共用，後者在**最前面**加一段——放最後會被下面四行摘要
    /// 推下去、在短 alert 裡看不到。`static` 讓它在 View 之外可測。
    nonisolated static func renameMessage(_ o: RenameOutcome) -> String {
        let receipt = RenameReportSummary.receipt(o.report, from: o.from, to: o.to)
        guard let failure = o.reloadFailure else { return receipt }
        return "⚠ 改名已寫入磁碟，但索引重建或重載失敗：\(displaySafeClipOnly(failure, max: 2_400))\n"   // display-safe-exempt: 已消毒（displaySafeError 產出，R29 D81），只截
             + "重新開啟檔案或跑 akashic doctor 重建索引。\n\n" + receipt
    }

    private func attempt(_ action: () throws -> Void) {
        do {
            try action()
        } catch {
            errorMessage = displaySafeErrorMultiline(error)
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
            errorMessage = displaySafeErrorMultiline(error)
        }
    }
}
