import Foundation
import AkashicStoreIO

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
/// **佈局感知 + rebind（#116）**：監看集合由 `directoryProvider` 提供（App 端用
/// `watchTargets(for:)`＝root + 實際存在的 canonical 目錄）。DispatchSource 的 vnode
/// 監看是**單層的**——監看 root 只看得到直接子項增刪，看不到子目錄內的寫入；所以
/// root 負責當「結構變化」的訊號：每次 debounced 通知前重取 provider，集合有變就
/// 重建 sources。沒有這一步，`migrate` 建出的 `entities/`（start() 時不存在、open
/// 失敗被跳過）永遠不會被監看——外部變更從此不刷新且無訊號。
///
/// 生命週期契約：
/// - fd 由各 source 的 cancel handler 關閉（GCD 契約——`cancel()` 是非同步排程，
///   呼叫端立即 `close(fd)` 會與仍在 queue 上的 handler 競態）。
/// - **全部可變狀態（sources/pending/stopped/watched）只在 watcher serial queue 上
///   存取**；start()/stop() 以 `queue.sync` 進入（#116 起 rebind 在 queue 上動
///   sources，呼叫端執行緒直接碰它就是競態）。
/// - stop 之後不再有 onChange 回呼。
public final class FileWatcher {
    let directoryProvider: () -> [URL]
    let debounce: TimeInterval
    let onChange: () -> Void

    // 以下全部只在 `queue` 上存取
    private var sources: [String: DispatchSourceFileSystemObject] = [:]
    private var pending: DispatchWorkItem?
    private var stopped = true
    private let queue = DispatchQueue(label: "akashic.filewatcher")

    public init(directoryProvider: @escaping () -> [URL], debounce: TimeInterval = 0.5,
                onChange: @escaping () -> Void) {
        self.directoryProvider = directoryProvider
        self.debounce = debounce
        self.onChange = onChange
    }

    /// 固定目錄集合的便利建構（provider 版的常量特例）。
    public convenience init(directories: [URL], debounce: TimeInterval = 0.5,
                            onChange: @escaping () -> Void) {
        self.init(directoryProvider: { directories }, debounce: debounce, onChange: onChange)
    }

    /// App 端的監看目標：root（涵蓋 `store.yaml` 變更與目錄增刪＝rebind 訊號）+
    /// 該 store **實際存在**的 canonical 目錄。不看 format 猜佈局——`migrate` 前後、
    /// 就地遷移殘留（空 legacy 目錄）都以磁碟現況為準，開不存在的目錄只會靜默缺角。
    public static func watchTargets(for store: LibraryStore) -> [URL] {
        [store.root] + [store.entitiesDir, store.entriesDir, store.peopleDir]
            .filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    /// 目前實際監看中的目錄（測試與診斷用；rebind 後反映最新集合）。
    public var watchedPaths: Set<String> {
        queue.sync { Set(sources.keys) }
    }

    public func start() throws {
        try queue.sync {
            stopLocked()
            let dirs = directoryProvider()
            var failed: [String] = []
            for dir in dirs where sources[dir.path] == nil {
                if let source = makeSource(path: dir.path) {
                    sources[dir.path] = source
                    source.resume()
                } else {
                    failed.append(dir.lastPathComponent)
                }
            }
            // 全部 open 失敗＝監看根本沒啟動——靜默成功會讓 App 以為有自動刷新
            guard !sources.isEmpty || dirs.isEmpty else {
                throw FileWatcherError.noDirectoriesWatchable(failed)
            }
            stopped = false
        }
    }

    public func stop() {
        queue.sync { stopLocked() }
    }

    // MARK: - queue 上的實作

    /// 前提：已在 `queue` 上。
    private func stopLocked() {
        sources.values.forEach { $0.cancel() }   // fd 由各自 cancel handler 關閉
        sources.removeAll()
        stopped = true
        pending?.cancel()
        pending = nil
    }

    /// 前提：已在 `queue` 上。open 失敗回 nil（呼叫端決定是靜默還是計入 failed）。
    private func makeSource(path: String) -> DispatchSourceFileSystemObject? {
        let fd = open(path, O_EVTONLY)
        guard fd >= 0 else { return nil }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd, eventMask: [.write, .rename, .delete], queue: queue)
        source.setEventHandler { [weak self] in
            self?.scheduleNotification()
        }
        source.setCancelHandler { close(fd) }   // fd 生命週期歸 source
        return source
    }

    /// 結構變化追蹤（#116）。前提：已在 `queue` 上。
    ///
    /// 集合沒變＝零成本早退（互動路徑的常態）。變了：新目錄開 fd、消失目錄的
    /// source cancel。新集合全開不起來時**保留舊集合**——把還能用的監看關掉
    /// 換一場空，比暫時監看過時集合更糟。
    private func rebindLocked() {
        let want = directoryProvider().map(\.path)
        let have = Set(sources.keys)
        guard Set(want) != have else { return }

        var next: [String: DispatchSourceFileSystemObject] = [:]
        for path in want {
            if let existing = sources[path] {
                next[path] = existing          // 沿用既有 source，fd 不重開
            } else if let source = makeSource(path: path) {
                next[path] = source
                source.resume()
            }
        }
        guard !next.isEmpty || want.isEmpty else { return }   // 全失敗 → 保留舊集合
        for (path, source) in sources where next[path] == nil {
            source.cancel()                     // 消失的目錄：殭屍 fd 不是監看
        }
        sources = next
    }

    /// debounce：密集變更（如 import wave）合併為一次通知。
    /// 只會在 watcher queue 上執行（event handler 綁定本 queue）。
    private func scheduleNotification() {
        guard !stopped else { return }
        pending?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, !self.stopped else { return }
            self.rebindLocked()   // 通知前追上結構變化——migrate 後的第一發就修好集合
            self.onChange()
        }
        pending = work
        queue.asyncAfter(deadline: .now() + debounce, execute: work)
    }

    deinit {
        stop()
    }
}
