import SwiftUI
import AkashicAppKit
import AkashicStoreIO

@main
struct AkashicApp: App {
    @State private var launch = LaunchState()

    var body: some Scene {
        WindowGroup {
            switch launch.phase {
            case .ready(let state):
                ContentView(onSwitchFile: { key in launch.switchFile(state, to: key) })
                    .environment(state)
                    .alert("切換檔案", isPresented: Binding(
                        get: { launch.switchFileError != nil },
                        set: { if !$0 { launch.switchFileError = nil } })) {
                        Button("好") { launch.switchFileError = nil }
                    } message: {
                        Text(launch.switchFileError ?? "")
                    }
            case .failed(let message):
                ContentUnavailableView {
                    Label("找不到 Akashic library", systemImage: "books.vertical")
                } description: {
                    Text(message)
                }
                .frame(minWidth: 480, minHeight: 320)
            case .loading:
                ProgressView("載入 library…")
                    .frame(minWidth: 480, minHeight: 320)
                    .task { launch.boot() }
            }
        }
    }
}

/// 啟動流程：LibraryLocator 解析 → AppState 載入 → FileWatcher 掛上。
@Observable
final class LaunchState {
    enum Phase {
        case loading
        case ready(AppState)
        case failed(String)
    }

    var phase: Phase = .loading
    private var watcher: FileWatcher?

    /// #18 切換失敗的 UI surface（alert 用）。
    var switchFileError: String?

    /// #18 多檔案：切換 root 後 FileWatcher 必須跟著 rebind 到新 universe 的目錄。
    func switchFile(_ state: AppState, to key: String) {
        // 兩段交易語意（R2 #1）：資料切換失敗 → state 已自行 rollback，報「切換失敗」；
        // 資料切換成功但 watcher 起不來 → 維持新 universe，報「監看降級」警告（不是失敗）。
        do {
            try state.switchFile(key: key)
        } catch {
            switchFileError = (error as? LocalizedError)?.errorDescription ?? "\(error)"
            return
        }
        watcher?.stop()   // 舊 watcher 監看舊 universe 目錄，已無意義
        watcher = nil
        do {
            let store = state.store   // #101：一律經 AppState，不自己建
            let newWatcher = FileWatcher(directories: [store.entitiesDir, store.entriesDir, store.peopleDir]) {
                Task { @MainActor in
                    try? state.externalReload()
                }
            }
            try newWatcher.start()
            self.watcher = newWatcher
        } catch {
            switchFileError = "已切換到「\(key)」，但外部變更監看未能啟動——外部編輯不會自動同步（重啟 App 可恢復）"
        }
    }

    func boot() {
        do {
            // **resolveDetailed 而非 resolve**（#101）：root-only 的 overload 會把 registry
            // key 丟掉，App 於是對已註冊的 store 也走 keyless 路徑、在 store root 內重建
            // 一份沒有任何消費者的 in-store index。key 與 root 必須一起帶。
            let resolved = try LibraryLocator.resolveDetailed(explicit: nil)
            let root = resolved.root
            let state = AppState(root: root, key: resolved.key)
            try state.load()
            let store = state.store   // #101：一律經 AppState，不自己建
            let watcher = FileWatcher(directories: [store.entitiesDir, store.entriesDir, store.peopleDir]) {
                // 外部（CLI/MCP/git）變更 → 主執行緒 reload + 同步時戳
                //（sidebar 顯示「外部變更已同步」；App 為 write-through 模型，
                //  詳見 AppState.lastExternalSyncAt 的邊界說明）
                Task { @MainActor in
                    try? state.externalReload()
                }
            }
            try watcher.start()
            self.watcher = watcher
            phase = .ready(state)
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? "\(error)"
            phase = .failed(message)
        }
    }
}
