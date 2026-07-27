import Foundation

public enum FileWatcherError: Error, LocalizedError, Equatable {
    case noDirectoriesWatchable([String])

    public var errorDescription: String? {
        switch self {
        case .noDirectoriesWatchable(let dirs):
            return "沒有任何目錄可監看（open 全部失敗）：\(dirs.joined(separator: ", "))"
        }
    }
}

/// 目錄監看（DispatchSource）＋ debounce——CLI/MCP/git 在 App 外改動 store 時自動刷新。
///
/// 生命週期契約：
/// - fd 由各 source 的 cancel handler 關閉（GCD 契約——`cancel()` 是非同步排程，
///   呼叫端立即 `close(fd)` 會與仍在 queue 上的 handler 競態）。
/// - `pending`/`stopped` 只在 watcher serial queue 上存取（stop() 以 `queue.sync` 進入），
///   stop 之後不再有 onChange 回呼。
/// - start()/stop() 應從同一執行緒（App 內為 MainActor）呼叫。
public final class FileWatcher {
    let directories: [URL]
    let debounce: TimeInterval
    let onChange: () -> Void

    private var sources: [DispatchSourceFileSystemObject] = []
    private var pending: DispatchWorkItem?
    private var stopped = true          // queue 保護
    private let queue = DispatchQueue(label: "akashic.filewatcher")

    public init(directories: [URL], debounce: TimeInterval = 0.5,
                onChange: @escaping () -> Void) {
        self.directories = directories
        self.debounce = debounce
        self.onChange = onChange
    }

    public func start() throws {
        stop()
        var opened: [DispatchSourceFileSystemObject] = []
        var failed: [String] = []
        for dir in directories {
            let fd = open(dir.path, O_EVTONLY)
            guard fd >= 0 else {
                failed.append(dir.lastPathComponent)
                continue
            }
            let source = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: fd, eventMask: [.write, .rename, .delete], queue: queue)
            source.setEventHandler { [weak self] in
                self?.scheduleNotification()
            }
            source.setCancelHandler { close(fd) }   // fd 生命週期歸 source
            opened.append(source)
        }
        // 全部 open 失敗＝監看根本沒啟動——靜默成功會讓 App 以為有自動刷新
        guard !opened.isEmpty || directories.isEmpty else {
            throw FileWatcherError.noDirectoriesWatchable(failed)
        }
        queue.sync { stopped = false }
        sources = opened
        opened.forEach { $0.resume() }
    }

    public func stop() {
        sources.forEach { $0.cancel() }   // fd 由各自 cancel handler 關閉
        sources.removeAll()
        queue.sync {
            stopped = true
            pending?.cancel()
            pending = nil
        }
    }

    /// debounce：密集變更（如 import wave）合併為一次通知。
    /// 只會在 watcher queue 上執行（event handler 綁定本 queue）。
    private func scheduleNotification() {
        guard !stopped else { return }
        pending?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, !self.stopped else { return }
            self.onChange()
        }
        pending = work
        queue.asyncAfter(deadline: .now() + debounce, execute: work)
    }

    deinit {
        stop()
    }
}
