import XCTest
@testable import AkashicAppKit

final class FileWatcherTests: XCTestCase {
    func testDebouncedChangeNotification() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("akashic-watch-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let expectation = expectation(description: "change fired")
        expectation.assertForOverFulfill = false
        let watcher = FileWatcher(directories: [dir], debounce: 0.2) {
            expectation.fulfill()
        }
        try watcher.start()
        defer { watcher.stop() }

        // 連續三次寫入 → debounce 應合併
        for i in 0..<3 {
            try "x\(i)".write(to: dir.appendingPathComponent("f\(i).yaml"),
                              atomically: true, encoding: .utf8)
        }
        wait(for: [expectation], timeout: 3.0)
    }
}
