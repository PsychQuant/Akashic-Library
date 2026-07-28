import XCTest
@testable import AkashicAppKit

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
