import SwiftUI
import AkashicAppKit
import AkashicCore

/// 裁決台①：resolve-people 候選逐一 accept／skip。
struct PeopleResolveView: View {
    @Environment(AppState.self) private var state
    @State private var model: PeopleResolveModel?
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if let model {
                if model.candidates.isEmpty {
                    ContentUnavailableView("沒有待解析候選", systemImage: "person.crop.circle.badge.checkmark")
                } else {
                    List(model.candidates, id: \.citekey) { candidate in
                        HStack {
                            VStack(alignment: .leading) {
                                Text("「\(candidate.literal)」 → \(candidate.personKey)")
                                Text("\(candidate.displayCitekey)［作者 #\(candidate.authorIndex)］·\(candidate.displayReason)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Accept") {
                                do { try model.accept(candidate) } catch {
                                    errorMessage = (error as? LocalizedError)?.errorDescription ?? "\(error)"
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
        .navigationTitle("人物解析（\(model?.candidates.count ?? 0)）")
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
                                Text(entry.title.isEmpty ? entry.citekey : entry.title).lineLimit(1)
                                Text("\(entry.citekey) — Zotero 端已刪除")
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
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "\(error)"
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
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "\(error)"
        }
    }
}
