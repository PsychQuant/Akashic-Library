import XCTest
@testable import AkashicAppKit
@testable import AkashicStoreIO

final class FileWatcherTests: XCTestCase {
    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("akashic-watch-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    /// 計數版 debounce 斷言：密集寫入合併為「恰好一次」回呼——
    /// assertForOverFulfill = false 只能證明「至少一次」，證明不了合併。
    func testDebounceCoalescesToExactlyOne() throws {
        let lock = NSLock()
        var count = 0
        let watcher = FileWatcher(directories: [dir], debounce: 0.2) {
            lock.lock(); count += 1; lock.unlock()
        }
        try watcher.start()
        defer { watcher.stop() }

        for i in 0..<3 {
            try "x\(i)".write(to: dir.appendingPathComponent("f\(i).yaml"),
                              atomically: true, encoding: .utf8)
        }
        // 等 debounce 沉澱 + 餘裕，確認沒有第二次
        Thread.sleep(forTimeInterval: 1.0)
        lock.lock(); let final = count; lock.unlock()
        XCTAssertEqual(final, 1, "debounce 視窗內的密集變更必須合併為恰好一次")
    }

    func testStartThrowsWhenNoDirectoryWatchable() {
        let ghost = FileManager.default.temporaryDirectory
            .appendingPathComponent("akashic-ghost-\(UUID().uuidString)")   // 不存在
        let watcher = FileWatcher(directories: [ghost]) {}
        XCTAssertThrowsError(try watcher.start(),
                             "全部目錄 open 失敗時 start() 靜默成功會讓 App 誤以為監看已啟動")
    }

    func testNoCallbackAfterStop() throws {
        let lock = NSLock()
        var count = 0
        let watcher = FileWatcher(directories: [dir], debounce: 0.1) {
            lock.lock(); count += 1; lock.unlock()
        }
        try watcher.start()
        watcher.stop()
        try "after".write(to: dir.appendingPathComponent("after.yaml"),
                          atomically: true, encoding: .utf8)
        Thread.sleep(forTimeInterval: 0.5)
        lock.lock(); let final = count; lock.unlock()
        XCTAssertEqual(final, 0, "stop() 之後不得再有回呼")
    }

    func testStopIsIdempotentAndRestartable() throws {
        let lock = NSLock()
        var count = 0
        let watcher = FileWatcher(directories: [dir], debounce: 0.1) {
            lock.lock(); count += 1; lock.unlock()
        }
        try watcher.start()
        watcher.stop()
        watcher.stop()   // 重複 stop 不得 crash（fd 雙重 close 的典型雷）
        try watcher.start()
        defer { watcher.stop() }
        try "again".write(to: dir.appendingPathComponent("again.yaml"),
                          atomically: true, encoding: .utf8)
        Thread.sleep(forTimeInterval: 0.5)
        lock.lock(); let final = count; lock.unlock()
        XCTAssertEqual(final, 1, "restart 後監看必須恢復")
    }
}

/// #116：佈局感知監看 + 結構變化 rebind。
///
/// 靶心場景：watcher 綁 `start()` 當下的 fd，而 `migrate` 之後 canonical 搬進
/// **start() 時不存在**的 `entities/`——沒有 rebind 的話，對它的外部變更永遠不會
/// 自動刷新（App 顯示過期畫面且無訊號）。
final class FileWatcherRebindTests: XCTestCase {
    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("akashic-rebind-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    private func existing(_ candidates: [URL]) -> [URL] {
        candidates.filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    func testProviderInitWatchesOnlyExistingDirectories() throws {
        let entries = dir.appendingPathComponent("entries")
        try FileManager.default.createDirectory(at: entries, withIntermediateDirectories: true)
        let ghost = dir.appendingPathComponent("entities")   // 不建
        let watcher = FileWatcher(
            directoryProvider: { [self.dir!, entries, ghost].filter {
                FileManager.default.fileExists(atPath: $0.path) } }) {}
        try watcher.start()
        defer { watcher.stop() }
        XCTAssertEqual(watcher.watchedPaths, Set([dir.path, entries.path]),
                       "start() 只監看 provider 當下存在的目錄")
    }

    func testRebindPicksUpDirectoryCreatedAfterStart() throws {
        let entries = dir.appendingPathComponent("entries")
        try FileManager.default.createDirectory(at: entries, withIntermediateDirectories: true)
        let entities = dir.appendingPathComponent("entities")
        let lock = NSLock()
        var count = 0
        let watcher = FileWatcher(
            directoryProvider: { self.existing([self.dir!, entries, entities]) },
            debounce: 0.1) {
            lock.lock(); count += 1; lock.unlock()
        }
        try watcher.start()
        defer { watcher.stop() }
        XCTAssertFalse(watcher.watchedPaths.contains(entities.path),
                       "前置：entities/ 尚不存在、不在監看集合")

        // 模擬 migrate：root 下新建 entities/（root 的 vnode event → debounce → rebind）
        try FileManager.default.createDirectory(at: entities, withIntermediateDirectories: true)
        Thread.sleep(forTimeInterval: 0.6)
        XCTAssertTrue(watcher.watchedPaths.contains(entities.path),
                      "root 的結構變化必須讓 watcher 追上新目錄——否則 migrate 後外部變更永不刷新")

        // rebind 之後，新目錄**內**的變更要能觸發刷新
        lock.lock(); let before = count; lock.unlock()
        try "e".write(to: entities.appendingPathComponent("x.yaml"),
                      atomically: true, encoding: .utf8)
        Thread.sleep(forTimeInterval: 0.6)
        lock.lock(); let after = count; lock.unlock()
        XCTAssertGreaterThan(after, before,
                             "rebind 後 entities/ 內的寫入必須觸發 onChange（#116 的靶心）")
    }

    func testRebindDropsDeletedDirectory() throws {
        let entries = dir.appendingPathComponent("entries")
        try FileManager.default.createDirectory(at: entries, withIntermediateDirectories: true)
        let watcher = FileWatcher(
            directoryProvider: { self.existing([self.dir!, entries]) },
            debounce: 0.1) {}
        try watcher.start()
        defer { watcher.stop() }
        XCTAssertTrue(watcher.watchedPaths.contains(entries.path))

        try FileManager.default.removeItem(at: entries)
        Thread.sleep(forTimeInterval: 0.6)
        XCTAssertFalse(watcher.watchedPaths.contains(entries.path),
                       "消失的目錄要從監看集合移除——殭屍 fd 不是監看")
    }
}

/// #116：App 端的監看目標由 store 佈局推導（下沉到 AppKit 使其可測——#113 同路）。
final class FileWatcherWatchTargetsTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("akashic-wt-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    func testWatchTargetsLegacyStore() throws {
        // format 1：entries/ + people/，無 entities/
        try StoreVersion.write(root: root, format: 1)
        for d in ["entries", "people"] {
            try FileManager.default.createDirectory(
                at: root.appendingPathComponent(d), withIntermediateDirectories: true)
        }
        let store = LibraryStore(root: root, key: nil, environment: ["AKASHIC_HOME": root.path])
        let targets = Set(FileWatcher.watchTargets(for: store).map(\.path))
        XCTAssertEqual(targets, Set([root.path,
                                     root.appendingPathComponent("entries").path,
                                     root.appendingPathComponent("people").path]),
                       "legacy store：root（含 store.yaml 與結構變化）+ 存在的 legacy 目錄")
    }

    func testWatchTargetsEntitiesStore() throws {
        try StoreVersion.write(root: root, format: StoreVersion.supported)
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("entities"), withIntermediateDirectories: true)
        let store = LibraryStore(root: root, key: nil, environment: ["AKASHIC_HOME": root.path])
        let targets = Set(FileWatcher.watchTargets(for: store).map(\.path))
        XCTAssertEqual(targets, Set([root.path,
                                     root.appendingPathComponent("entities").path]),
                       "entities store：不含 legacy 目錄——監看不存在的目錄是靜默缺角的來源")
    }
}
