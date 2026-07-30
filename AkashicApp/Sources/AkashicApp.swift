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
                    .alert("切換檔案失敗", isPresented: Binding(
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
    /// 順序：先 start 新 watcher 再 stop 舊的——start 失敗時舊監看仍在（verify R1）。
    func switchFile(_ state: AppState, to key: String) {
        do {
            try state.switchFile(key: key)
            let store = LibraryStore(root: state.root)
            let newWatcher = FileWatcher(directories: [store.entriesDir, store.peopleDir]) {
                Task { @MainActor in
                    try? state.externalReload()
                }
            }
            try newWatcher.start()
            watcher?.stop()
            self.watcher = newWatcher
        } catch {
            // state.switchFile 已自行 rollback（root 與資料一致）；surface 給 UI
            switchFileError = (error as? LocalizedError)?.errorDescription ?? "\(error)"
        }
    }

    func boot() {
        do {
            let root = try LibraryLocator.resolve(explicit: nil)
            let state = AppState(root: root)
            try state.load()
            let store = LibraryStore(root: root)
            let watcher = FileWatcher(directories: [store.entriesDir, store.peopleDir]) {
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
