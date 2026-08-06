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
/// `watchTargets(for:)`＝root + `store.yaml` + 實際存在的 canonical 目錄）。DispatchSource
/// 的 vnode 監看是**單層的**——監看 root 只看得到直接子項增刪，看不到子目錄內的寫入；
/// 所以 root 負責當「結構變化」的訊號：每次 debounced 通知前重取 provider，集合有變
/// 或有 source 失效就重建。沒有這一步，`migrate` 建出的 `entities/`（start() 時不存在、
/// open 失敗被跳過）永遠不會被監看——外部變更從此不刷新且無訊號。
///
/// **vnode 身分（#116 verify F1）**：fd 綁的是 inode，不是路徑字串。同路徑的目錄被
/// 刪除重建（git checkout、rm -rf + migrate、雲端同步替換）後，舊 source 還掛在**死的**
/// inode 上——路徑集合比對看不出任何變化。所以 event handler 記下 `.rename`/`.delete`
/// 的 source（`invalidated`），rebind 對它們一律 cancel + 重開（路徑還在的話拿到新
/// inode）。**已知限制**：root 本身消失且在 debounce 窗內沒有重建時，重開失敗、事件源
/// 就此斷絕——那是「store 不見了」的災難場景，App 的 boot/switchFile 都會重建 watcher。
///
/// 生命週期契約：
/// - fd 由各 source 的 cancel handler 關閉（GCD 契約——`cancel()` 是非同步排程，
///   呼叫端立即 `close(fd)` 會與仍在 queue 上的 handler 競態）。
/// - 全部可變狀態（sources/invalidated/pending/stopped）只在 watcher serial queue 上
///   存取；start()/stop()/watchedPaths 從外部經 `queue.sync` 進入，**在 queue 上
///   （例如 `onChange` 回呼內）呼叫則直接執行**——`queue.sync` 對已持有的 queue 是
///   即刻 crash（dispatch 的 non-reentrant 契約），verify F4/F5 兩個 probe 都重現過，
///   含 deinit 恰好發生在 queue 上的變體。
/// - **`onChange` 與 `directoryProvider` 都在 watcher queue 上被呼叫**——回呼內要碰
///   MainActor 狀態請自行跳轉（App 端用 `Task { @MainActor in … }`）；provider 不得
///   捕捉跨執行緒可變狀態（App 端捕捉 immutable 的 `LibraryStore` snapshot）。
/// - stop 之後不再有 onChange 回呼。
public final class FileWatcher {
    let directoryProvider: () -> [URL]
    let debounce: TimeInterval
    let onChange: () -> Void

    // 以下全部只在 `queue` 上存取
    private var sources: [String: DispatchSourceFileSystemObject] = [:]
    /// 收過 `.rename`/`.delete` 的 path——fd 已可能綁死 inode，rebind 時必須重開
    private var invalidated: Set<String> = []
    private var pending: DispatchWorkItem?
    private var stopped = true
    private let queue: DispatchQueue
    private static let queueKey = DispatchSpecificKey<ObjectIdentifier>()

    public init(directoryProvider: @escaping () -> [URL], debounce: TimeInterval = 0.5,
                onChange: @escaping () -> Void) {
        self.directoryProvider = directoryProvider
        self.debounce = debounce
        self.onChange = onChange
        self.queue = DispatchQueue(label: "akashic.filewatcher")
        // **值必須是 per-instance 的**（#126 verify 複驗缺陷 A）：static key + 常數值
        // + presence-only 檢查，會讓 watcher A 的回呼裡碰 watcher B 時，B 的
        // onQueueSync 誤判「已在自己的 queue 上」而無鎖直改 B 的 queue-confined
        // 狀態——把 loud crash 換成 silent corruption。ObjectIdentifier 比對讓
        // 「在某個 watcher 的 queue 上」≠「在**我的** queue 上」。
        queue.setSpecific(key: Self.queueKey, value: ObjectIdentifier(self))
    }

    /// 固定目錄集合的便利建構（provider 版的常量特例）。
    public convenience init(directories: [URL], debounce: TimeInterval = 0.5,
                            onChange: @escaping () -> Void) {
        self.init(directoryProvider: { directories }, debounce: debounce, onChange: onChange)
    }

    /// App 端的監看目標：root（目錄增刪＝rebind 訊號）+ `store.yaml`（format 變更；
    /// akashic 的寫入都是 atomic temp+rename，經 invalidation 機制在替換後重開新
    /// inode——**in-place 覆寫**既有檔案不保證觸發，那不是本 repo 任何寫入端的行為）
    /// + 該 store **實際存在**的 canonical 目錄。不看 format 猜佈局——`migrate` 前後、
    /// 就地遷移殘留（空 legacy 目錄）都以磁碟現況為準。
    public static func watchTargets(for store: LibraryStore) -> [URL] {
        ([store.root, StoreVersion.url(in: store.root),
          store.entitiesDir, store.entriesDir, store.peopleDir])
            .filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    /// 目前實際監看中的目錄（測試與診斷用；rebind 後反映最新集合）。
    /// 在 `onChange` 回呼內讀取是安全的（重入直接執行，不會 dispatch_sync 自死）。
    public var watchedPaths: Set<String> {
        onQueueSync { Set(sources.keys) }
    }

    public func start() throws {
        try onQueueSync { try startLocked() }
    }

    public func stop() {
        onQueueSync { stopLocked() }
    }

    // MARK: - queue 進入（重入安全）

    /// 已在 watcher queue 上（onChange/provider 回呼、deinit 恰落在 queue 的情形）
    /// 就直接執行；否則 `queue.sync` 進入。dispatch 的 `sync` 對自己持有的 queue
    /// 是 crash 不是等待——這個檢查是 watchedPaths/stop 可以從回呼內安全呼叫的原因。
    private func onQueueSync<T>(_ body: () throws -> T) rethrows -> T {
        if DispatchQueue.getSpecific(key: Self.queueKey) == ObjectIdentifier(self) {
            return try body()
        }
        return try queue.sync(execute: body)
    }

    /// 前提：已在 `queue` 上。
    private func startLocked() throws {
        stopLocked()
        let dirs = directoryProvider()
        var failed: [String] = []
        // `where`：同一次 start 內的重複 path 去重（stopLocked 剛清空，不是沿用舊 run）
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

    /// 前提：已在 `queue` 上。
    private func stopLocked() {
        sources.values.forEach { $0.cancel() }   // fd 由各自 cancel handler 關閉
        sources.removeAll()
        invalidated.removeAll()
        stopped = true
        pending?.cancel()
        pending = nil
    }

    /// 前提：已在 `queue` 上。open 失敗回 nil（呼叫端決定如何處置）。
    private func makeSource(path: String) -> DispatchSourceFileSystemObject? {
        let fd = open(path, O_EVTONLY)
        guard fd >= 0 else { return nil }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd, eventMask: [.write, .rename, .delete], queue: queue)
        source.setEventHandler { [weak self, weak source] in
            guard let self else { return }
            // vnode 身分：rename/delete 之後這個 fd 綁的 inode 與路徑可能已經分家
            //（同路徑重建拿到新 inode）——標記失效，rebind 時強制重開。
            if let source, !source.data.intersection([.rename, .delete]).isEmpty {
                self.invalidated.insert(path)
            }
            self.scheduleNotification()
        }
        source.setCancelHandler { close(fd) }   // fd 生命週期歸 source
        return source
    }

    /// 結構變化追蹤（#116）。前提：已在 `queue` 上。
    ///
    /// 集合沒變**且**無失效 source＝零成本早退（互動路徑的常態）。否則逐 path：
    /// 未失效的既有 source 沿用（fd 不重開）；失效的 cancel + 重開（拿新 inode）；
    /// 新 path 開 fd；開失敗但握有舊 source 的**保留舊的**（可能還活著，總比縮角好），
    /// 開失敗又沒有舊的（EACCES 等）只能等下一個 root event 重試——監看集合縮角，
    /// 但 root 恆在、恢復路徑存在（verify F3 的 partial-failure 場景）。
    /// 消失的目錄 cancel（殭屍 fd 不是監看）。
    private func rebindLocked() {
        let want = directoryProvider().map(\.path)
        let have = Set(sources.keys)
        guard Set(want) != have || !invalidated.isEmpty else { return }

        var next: [String: DispatchSourceFileSystemObject] = [:]
        var reopened: Set<String> = []
        for path in want where next[path] == nil {
            if let existing = sources[path], !invalidated.contains(path) {
                next[path] = existing          // 沿用既有 source，fd 不重開
            } else if let source = makeSource(path: path) {
                next[path] = source
                source.resume()
                reopened.insert(path)
            } else if let existing = sources[path] {
                next[path] = existing          // 重開失敗：舊的可能還活著，別自斷
            }
        }
        // 全滅（want 非空卻一個都留不住）→ 保留舊集合：把還能用的關掉換一場空，
        // 比暫時監看過時集合更糟。want 為空同理——rebind 不得自毀事件源（F6）。
        guard !next.isEmpty else { return }
        for (path, source) in sources where next[path] !== source {
            source.cancel()                     // 消失／被換掉的：殭屍 fd 不是監看
        }
        sources = next
        // **只清實際重開成功的**（#126 verify 複驗缺陷 B）：無條件 removeAll 會把
        // 「reopen 失敗、沿用舊 source」的 path 的 retry 訊號一併清掉——下次 rebind
        // 看集合沒變、invalidated 空 → 早退，該目錄永久失聰而 watchedPaths 仍報健康
        //（正是 F1 要關的失效模式從窄路回歸）。保留旗標＝下一個 event 再試。
        invalidated.subtract(reopened)
        invalidated.formIntersection(Set(sources.keys))   // 已不在集合的不必再追
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
        // onQueueSync 讓「最後一個 strong reference 在 watcher queue 上釋放」的
        // deinit 不會 dispatch_sync 自死（verify F5 的 probe 形狀，pre-existing）。
        stop()
    }
}
