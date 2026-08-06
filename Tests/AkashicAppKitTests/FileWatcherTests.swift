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

    /// 有界輪詢取代固定 sleep（verify M5：固定 0.6s 在慢 CI 上既可假紅也可假綠）。
    /// 條件成立即早退；超時回 false 讓呼叫端的斷言訊息說話。
    @discardableResult
    private func eventually(timeout: TimeInterval = 5.0,
                            _ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            Thread.sleep(forTimeInterval: 0.05)
        }
        return condition()
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

        // 模擬 migrate：root 下新建 entities/（root 的 vnode event → debounce → rebind）。
        // 結構變化事件自己也要產生一次 onChange（rebind 不吞事件，verify M5）。
        lock.lock(); let base = count; lock.unlock()
        try FileManager.default.createDirectory(at: entities, withIntermediateDirectories: true)
        XCTAssertTrue(eventually { watcher.watchedPaths.contains(entities.path) },
                      "root 的結構變化必須讓 watcher 追上新目錄——否則 migrate 後外部變更永不刷新")
        XCTAssertTrue(eventually { lock.lock(); defer { lock.unlock() }; return count > base },
                      "結構變化事件本身也要觸發 onChange（rebind 不吞掉它）")

        // rebind 之後，新目錄**內**的變更要能觸發刷新
        lock.lock(); let before = count; lock.unlock()
        try "e".write(to: entities.appendingPathComponent("x.yaml"),
                      atomically: true, encoding: .utf8)
        XCTAssertTrue(eventually { lock.lock(); defer { lock.unlock() }; return count > before },
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
        XCTAssertTrue(eventually { !watcher.watchedPaths.contains(entries.path) },
                      "消失的目錄要從監看集合移除——殭屍 fd 不是監看")
    }

    func testRebindReopensReplacedDirectoryAtSamePath() throws {
        // verify F1（PROBE2 重現的 stale-fd）：fd 綁 inode 不綁路徑。同路徑刪除重建
        //（git checkout / rm -rf + migrate / 雲端同步替換）後，路徑集合比對看不出
        // 變化——沒有 invalidation 機制的話，舊 source 掛在死 inode 上，此後該目錄
        // 的一切變更靜默丟失而 watchedPaths 仍報健康。
        let entries = dir.appendingPathComponent("entries")
        try FileManager.default.createDirectory(at: entries, withIntermediateDirectories: true)
        let lock = NSLock()
        var count = 0
        let watcher = FileWatcher(
            directoryProvider: { self.existing([self.dir!, entries]) },
            debounce: 0.1) {
            lock.lock(); count += 1; lock.unlock()
        }
        try watcher.start()
        defer { watcher.stop() }

        // 同路徑替換：刪掉 + 立刻重建（新 inode）
        try FileManager.default.removeItem(at: entries)
        try FileManager.default.createDirectory(at: entries, withIntermediateDirectories: true)
        XCTAssertTrue(eventually { watcher.watchedPaths.contains(entries.path) })
        // 等 rebind 沉澱後，向**重建後**的目錄寫入——必須觸發 onChange
        Thread.sleep(forTimeInterval: 0.3)
        lock.lock(); let before = count; lock.unlock()
        try "x".write(to: entries.appendingPathComponent("new.yaml"),
                      atomically: true, encoding: .utf8)
        XCTAssertTrue(eventually { lock.lock(); defer { lock.unlock() }; return count > before },
                      "重建後目錄內的寫入必須觸發 onChange——舊 fd 綁死 inode 就是靜默失聰")
    }

    func testReopenFailureKeepsRetrySignal() throws {
        // #126 verify 複驗缺陷 B（PROBE-INV）：同路徑替換成**不可開**的目錄時，
        // rebind 沿用舊（死）source——此時 invalidated 旗標若被無條件清掉，
        // 下次 rebind 看集合沒變、旗標空 → 早退，該目錄永久失聰。
        // 旗標保留 ＝ 權限恢復後的下一個 event 把它重開回來。
        let entries = dir.appendingPathComponent("entries")
        try FileManager.default.createDirectory(at: entries, withIntermediateDirectories: true)
        let lock = NSLock()
        var count = 0
        let watcher = FileWatcher(
            directoryProvider: { self.existing([self.dir!, entries]) },
            debounce: 0.1) {
            lock.lock(); count += 1; lock.unlock()
        }
        try watcher.start()
        defer { watcher.stop() }

        // 同路徑替換 + 立即封權限：rename event 標 invalidated、reopen 失敗
        try FileManager.default.removeItem(at: entries)
        try FileManager.default.createDirectory(at: entries, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: entries.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: entries.path) }
        _ = eventually(timeout: 1.0) { false }   // 讓 replace 事件的 rebind 跑完（reopen 失敗）

        // 權限恢復 + root 層 event → 下一輪 rebind 必須重開（retry 訊號還在）
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: entries.path)
        try "t".write(to: dir.appendingPathComponent("touch.yaml"),
                      atomically: true, encoding: .utf8)
        Thread.sleep(forTimeInterval: 0.4)
        lock.lock(); let before = count; lock.unlock()
        try "x".write(to: entries.appendingPathComponent("alive.yaml"),
                      atomically: true, encoding: .utf8)
        XCTAssertTrue(eventually { lock.lock(); defer { lock.unlock() }; return count > before },
                      "reopen 失敗的 retry 訊號被清掉＝該目錄永久失聰（watchedPaths 仍報健康）")
    }

    func testPartialOpenFailureKeepsRootAndRecovers() throws {
        // verify F3（PROBE8 的 silent-shrink）：want 中某目錄開不起來（EACCES）時，
        // 不得把整個監看集合縮到只剩 root 而無恢復路徑——root 恆在，權限恢復後
        // 的下一個 root event 要能把它撿回來。
        let entries = dir.appendingPathComponent("entries")
        try FileManager.default.createDirectory(at: entries, withIntermediateDirectories: true)
        let sealed = dir.appendingPathComponent("entities")
        try FileManager.default.createDirectory(at: sealed, withIntermediateDirectories: true)
        let watcher = FileWatcher(
            directoryProvider: { self.existing([self.dir!, entries, sealed]) },
            debounce: 0.1) {}
        try watcher.start()
        defer { watcher.stop() }
        XCTAssertTrue(watcher.watchedPaths.contains(sealed.path))

        // 讓 sealed 變得不可 open（權限 000），並以同路徑替換使舊 fd 失效
        try FileManager.default.removeItem(at: sealed)
        try FileManager.default.createDirectory(at: sealed, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: sealed.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: sealed.path) }
        _ = eventually(timeout: 1.0) { false }   // 讓 replace 事件的 rebind 跑完
        XCTAssertTrue(watcher.watchedPaths.contains(dir.path),
                      "root 必須恆在——它是恢復的唯一事件源")

        // 權限恢復 + root 層變化 → 下一輪 rebind 撿回
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: sealed.path)
        try "t".write(to: dir.appendingPathComponent("touch.yaml"),
                      atomically: true, encoding: .utf8)
        XCTAssertTrue(eventually { watcher.watchedPaths.contains(sealed.path) },
                      "開失敗的目錄在可開之後要被下一輪 rebind 撿回（恢復路徑存在）")
    }

    func testWatchedPathsReadableFromOnChange() throws {
        // verify F4（PROBE7 的 SIGTRAP）：onChange 在 watcher queue 上執行，
        // queue.sync 對已持有的 queue 是即刻 crash——重入必須直接執行。
        let read = expectation(description: "watchedPaths read inside onChange")
        read.assertForOverFulfill = false
        var seen: Set<String> = []
        var watcher: FileWatcher!
        watcher = FileWatcher(directoryProvider: { [self.dir!] }, debounce: 0.05) {
            seen = watcher.watchedPaths   // 重入讀取——修法前這行直接 SIGTRAP
            read.fulfill()
        }
        try watcher.start()
        defer { watcher.stop() }
        try "x".write(to: dir.appendingPathComponent("f.yaml"),
                      atomically: true, encoding: .utf8)
        wait(for: [read], timeout: 5.0)
        XCTAssertEqual(seen, Set([dir.path]), "回呼內讀到的集合要是真值")
    }

    func testStoreYamlAtomicRewriteTriggersOnChange() throws {
        // watchTargets 把 store.yaml 納入監看的理由：format 變更要能刷新。
        // akashic 的寫入是 atomic（temp+rename）——rename 讓舊 fd 失效，
        // invalidation 機制要在 rebind 時重開新 inode，後續變更不失聰。
        let marker = dir.appendingPathComponent("store.yaml")
        try "format: 1\n".write(to: marker, atomically: true, encoding: .utf8)
        let lock = NSLock()
        var count = 0
        let watcher = FileWatcher(
            directoryProvider: { self.existing([self.dir!, marker]) },
            debounce: 0.1) {
            lock.lock(); count += 1; lock.unlock()
        }
        try watcher.start()
        defer { watcher.stop() }

        try "format: 2\n".write(to: marker, atomically: true, encoding: .utf8)   // atomic = rename
        XCTAssertTrue(eventually { lock.lock(); defer { lock.unlock() }; return count >= 1 },
                      "atomic 改寫 store.yaml 必須觸發 onChange")
        // rename 之後（舊 inode 已死）再寫一次——invalidation + reopen 讓第二次也看得見
        Thread.sleep(forTimeInterval: 0.3)
        lock.lock(); let before = count; lock.unlock()
        try "format: 3\n".write(to: marker, atomically: true, encoding: .utf8)
        XCTAssertTrue(eventually { lock.lock(); defer { lock.unlock() }; return count > before },
                      "第二次 atomic 改寫也要觸發——fd 若仍綁第一代 inode 就是失聰")
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
                                     root.appendingPathComponent("store.yaml").path,
                                     root.appendingPathComponent("entries").path,
                                     root.appendingPathComponent("people").path]),
                       "legacy store：root + store.yaml + 存在的 legacy 目錄")
    }

    func testWatchTargetsEntitiesStore() throws {
        try StoreVersion.write(root: root, format: StoreVersion.supported)
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("entities"), withIntermediateDirectories: true)
        let store = LibraryStore(root: root, key: nil, environment: ["AKASHIC_HOME": root.path])
        let targets = Set(FileWatcher.watchTargets(for: store).map(\.path))
        XCTAssertEqual(targets, Set([root.path,
                                     root.appendingPathComponent("store.yaml").path,
                                     root.appendingPathComponent("entities").path]),
                       "entities store：不含 legacy 目錄——監看不存在的目錄是靜默缺角的來源")
    }

    func testWatchTargetsCrossoverLayoutsFollowDiskNotFormat(){
        // verify M5（crossover）：監看目標以「磁碟現況」為準、不看 format 猜——
        // format 1 但已有 entities/（就地遷移中）與 format 新但殘留 entries/（migrate
        // 不刪空目錄）都要把**存在的全部**納入；按 format 挑目錄的錯誤實作兩測皆綠。
        try? StoreVersion.write(root: root, format: 1)
        for d in ["entries", "people", "entities"] {
            try? FileManager.default.createDirectory(
                at: root.appendingPathComponent(d), withIntermediateDirectories: true)
        }
        let store = LibraryStore(root: root, key: nil, environment: ["AKASHIC_HOME": root.path])
        let targets = Set(FileWatcher.watchTargets(for: store).map(\.path))
        XCTAssertEqual(targets, Set([root.path,
                                     root.appendingPathComponent("store.yaml").path,
                                     root.appendingPathComponent("entries").path,
                                     root.appendingPathComponent("people").path,
                                     root.appendingPathComponent("entities").path]),
                       "format 1 + 既存 entities/：存在的全都要監看——按 format 猜就會缺角")
    }
}
