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
                ContentView()
                    .environment(state)
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

    func boot() {
        do {
            let root = try LibraryLocator.resolve(explicit: nil)
            let state = AppState(root: root)
            try state.load()
            let store = LibraryStore(root: root)
            let watcher = FileWatcher(directories: [store.entriesDir, store.peopleDir]) {
                // 外部（CLI/MCP/git）變更 → 主執行緒 reload
                Task { @MainActor in
                    try? state.load()
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
