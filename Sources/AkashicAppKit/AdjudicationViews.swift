import SwiftUI
import AkashicCore

/// 裁決台①：resolve-people 候選逐一 accept／skip。
struct PeopleResolveView: View {
    @Environment(AppState.self) private var state
    @State private var model: PeopleResolveModel?
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if let model {
                if model.candidates.isEmpty && model.ambiguities.isEmpty {
                    ContentUnavailableView("沒有待解析候選", systemImage: "person.crop.circle.badge.checkmark")
                } else {
                    List {
                    // #231／#236 R3：**歧義要被看見**。裁決台是唯一有人能解決它的地方，
                    // 而先前它是三個面裡唯一還在靜默丟棄的。
                    //
                    // 也是本 PR 自己踩過的坑的最後一格：R3 先在 model 加了 `ambiguities`，
                    // **卻沒有任何 view 讀它**——機制存在、沒有人看得到，與原本的
                    // `continue` 在效果上完全相同，只是位置更難察覺。
                    if !model.ambiguities.isEmpty {
                        Section("需要你判斷（\(model.ambiguities.count)）") {
                            ForEach(model.ambiguities, id: \.rowID) { a in
                                VStack(alignment: .leading, spacing: 2) {
                                    // R1-fix B6：碰撞層可見（tier.rawValue 封閉 enum）
                                    Text("〔\(a.tier.rawValue)〕「\(displaySafe(a.literal, max: 200))」 對到 \(a.personKeys.count) 個人")   // display-safe-exempt: tier.rawValue 封閉 enum；literal 已消毒
                                        .font(.callout.weight(.medium))
                                    Text(displaySafe(a.citekey, max: 200)
                                         + "［作者 #\(a.authorIndex)］")
                                        .font(.caption).foregroundStyle(.secondary)
                                    ForEach(a.personKeys, id: \.self) { k in
                                        // 區辨欄位——只給 key 的話人也判不了。`names` 不具
                                        // 區辨力（它們正規化後相同才會歧義）。
                                        //
                                        // **組字串在 model 端**：先前寫成 view 內的長串
                                        // 接，Swift 型別檢查器直接放棄
                                        // （「unable to type-check this expression in
                                        // reasonable time」）。而 `AkashicApp/` 是獨立的
                                        // XcodeGen 專案、**不在 `Package.swift` 內**，
                                        // `swift build` 與 pre-push 閘都不編它——只有 CI
                                        // 會。本機 `xcodegen + xcodebuild` 才抓到。
                                        Text(model.discriminatorLine(for: k))   // display-safe-exempt: model 端已逐欄消毒
                                            .font(.caption.monospaced())
                                    }
                                    // R1-fix B6：指引依碰撞層分開——exact 的兩難框架
                                    // 對縮寫／重排共鍵是錯誤指引（那通常是不同的人）
                                    Text(a.tier == .exact
                                         ? "同名的不同人＝各自歸屬（永不合併）；同一人兩筆＝該合併。"
                                           + "**這裡不提供套用**——歧義套用不了。"
                                         : "縮寫／重排共鍵通常是不同的人——不歸戶也不合併；"
                                           + "查證後：清單中某人→補 variant alias（帶 provenance；names 整組回寫）"
                                           + "；第三人→add-person 建檔。**這裡不提供套用**。")
                                        .font(.caption2).foregroundStyle(.tertiary)
                                }
                                .padding(.vertical, 2)
                            }
                        }
                    }
                    Section("可套用候選（\(model.candidates.count)）") {
                    ForEach(model.candidates, id: \.rowID) { candidate in
                        HStack {
                            VStack(alignment: .leading) {
                                // **exempt 是整行生效**（#161 verify 181-2）：先前
                                // 這一行同時有 `displayLiteral`（靠投影保護的自由
                                // 字串）與 `personKey`（安全），而 exempt 理由只講
                                // personKey 卻把兩者一起蓋掉——**保留 exempt、把
                                // `displayLiteral` 換回 `literal`，守衛全綠**。
                                // 那是本 change 造成的覆蓋倒退：修之前這行看得見。
                                // 拆成兩行，各自只承載一種。
                                Text("「\(candidate.displayLiteral)」 →")
                                    + Text(" \(candidate.personKey)")   // display-safe-exempt: person.key，load 端 quarantine 驗過 StoreKey
                                // #303：tier 標示（信心層）。`tier.rawValue` 是封閉 enum 的
                                // 固定字面（exact/confirmed-elsewhere/reorder/initials），
                                // 非 store 衍生——同 `personKey` 的理由不給 display* 投影，
                                // 免得「有投影＝危險」的訊號失真。
                                Text("\(candidate.displayCitekey)［作者 #\(candidate.authorIndex)］·\(candidate.tier.rawValue)·\(candidate.displayReason)")   // display-safe-exempt: tier.rawValue 封閉 enum；其餘欄位已投影
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Accept") {
                                do { try model.accept(candidate) } catch {
                                    errorMessage = displaySafeErrorMultiline(error)
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            Button("Skip") { model.skip(candidate) }
                        }
                        .padding(.vertical, 4)
                    }
                    }
                    }
                }
            }
        }
        .navigationTitle("人物解析（\(model?.candidates.count ?? 0)"
                         + ((model?.ambiguities.count ?? 0) > 0
                            ? "＋\(model!.ambiguities.count) 待判斷" : "") + "）")
        // 綁 reloadCount：外部變更（FileWatcher reload）後重算候選，
        // 不讓 stale 候選被 accept 到已變更的 entry 上
        .task(id: state.reloadCount) { model = PeopleResolveModel(state: state) }
        .alert("操作失敗", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } })) {
            Button("好") { errorMessage = nil }
        } message: { Text(errorMessage ?? "") }
    }
}

/// 裁決台②：orphan 三選（等待／垃圾桶／轉純 Akashic）。
struct OrphanView: View {
    @Environment(AppState.self) private var state
    @State private var model: OrphanModel?
    @State private var pendingTrash: String?
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if let model {
                if model.orphans.isEmpty {
                    ContentUnavailableView("沒有 orphan", systemImage: "checkmark.seal")
                } else {
                    List(model.orphans, id: \.citekey) { entry in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(entry.displayTitleOrCitekey).lineLimit(1)
                                Text("\(entry.citekey) — Zotero 端已刪除")   // display-safe-exempt: citekey 過 load 端 quarantine（StoreKey）
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("轉純 Akashic") {
                                attempt { try model.resolve(citekey: entry.citekey, action: .detachFromZotero) }
                            }
                            Button("刪除…", role: .destructive) { pendingTrash = entry.citekey }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
        .navigationTitle("Orphans（\(model?.orphans.count ?? 0)）")
        .task(id: state.reloadCount) { model = OrphanModel(state: state) }
        .confirmationDialog("刪除這筆 entry？檔案會移到垃圾桶（可救回）。",
                            isPresented: Binding(
                                get: { pendingTrash != nil },
                                set: { if !$0 { pendingTrash = nil } }),
                            titleVisibility: .visible) {
            Button("移到垃圾桶", role: .destructive) {
                if let citekey = pendingTrash, let model {
                    // resolve 動作當下會重新讀盤驗證 orphan 狀態（TOCTOU 守衛在 kit 層）
                    attempt { try model.resolve(citekey: citekey, action: .moveToTrash) }
                }
                pendingTrash = nil
            }
            Button("取消", role: .cancel) { pendingTrash = nil }
        }
        .alert("操作失敗", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } })) {
            Button("好") { errorMessage = nil }
        } message: { Text(errorMessage ?? "") }
    }

    private func attempt(_ action: () throws -> Void) {
        do { try action() } catch {
            errorMessage = displaySafeErrorMultiline(error)
        }
    }
}

/// 裁決台③：quarantine 展示與重新驗證。
struct QuarantineView: View {
    @Environment(AppState.self) private var state
    @State private var model: QuarantineModel?
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if let model {
                if model.items.isEmpty {
                    ContentUnavailableView("沒有 quarantined 檔案", systemImage: "checkmark.shield")
                } else {
                    List(model.items, id: \.file) { item in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(item.displayFile).font(.body.monospaced())
                                Spacer()
                                Button("在 Finder 開啟") {
                                    NSWorkspace.shared.activateFileViewerSelecting([model.fileURL(item)])
                                }
                            }
                            Text(item.displayReason)
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
        .navigationTitle("Quarantine（\(model?.items.count ?? 0)）")
        .toolbar {
            Button("重新驗證") { refresh() }
        }
        .task(id: state.reloadCount) {
            let m = QuarantineModel(state: state)
            model = m
        }
        .alert("重新驗證失敗", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } })) {
            Button("好") { errorMessage = nil }
        } message: { Text(errorMessage ?? "") }
    }

    private func refresh() {
        do { try model?.refresh() } catch {
            // 驗證失敗不得被 try? 吞掉——使用者要知道 library 現在讀不動
            errorMessage = displaySafeErrorMultiline(error)
        }
    }
}
