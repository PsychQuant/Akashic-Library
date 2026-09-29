import XCTest
@testable import AkashicS2

/// 可手動推進的時鐘，與記錄睡眠長度的 sleeper。
final class FakeClock: @unchecked Sendable {
    private let lock = NSLock()
    private var t: Date
    private(set) var slept: [TimeInterval] = []
    init(_ start: Date) { t = start }
    var now: Date { lock.lock(); defer { lock.unlock() }; return t }
    func set(_ d: Date) { lock.lock(); t = d; lock.unlock() }
    func recordSleep(_ s: TimeInterval) { lock.lock(); slept.append(s); lock.unlock() }
    func throttle(_ dir: URL) -> S2FileThrottle {
        S2FileThrottle(stateDirectory: dir, now: { [self] in now }, sleep: { [self] s in recordSleep(s) })
    }
}

/// #664 任務 3.1：時段預約（Requirement「Requests are throttled machine-wide」）。
final class S2ThrottleTests: XCTestCase {
    private var dir: URL!
    private let t0 = Date(timeIntervalSince1970: 1_000_000)

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("s2-throttle-\(UUID().uuidString)", isDirectory: true)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: dir) }

    /// spec Example「Slot reservation」：A 在 0.00、B 在 0.30 → A 於 0.00 送出，B 於 1.00 以後。
    func testSlotReservationExample() throws {
        let clock = FakeClock(t0)
        let a = clock.throttle(dir), b = clock.throttle(dir)   // 兩個獨立的 open()，flock 互斥
        let slotA = try a.reserveSlot()
        clock.set(t0.addingTimeInterval(0.30))
        let slotB = try b.reserveSlot()
        XCTAssertEqual(slotA, t0)
        XCTAssertGreaterThanOrEqual(slotB.timeIntervalSince(t0), 1.00)
    }

    func testAcquireWaitsUntilTheReservedSlot() async throws {
        let clock = FakeClock(t0)
        let a = clock.throttle(dir), b = clock.throttle(dir)
        try await a.acquire()
        clock.set(t0.addingTimeInterval(0.30))
        try await b.acquire()
        XCTAssertEqual(clock.slept.count, 1)                              // A 不必等
        XCTAssertEqual(clock.slept.first ?? -1, 0.75, accuracy: 1e-6)     // 1.05 − 0.30
    }

    func testStaleStateIsResetToNow() throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let far = t0.addingTimeInterval(120).timeIntervalSince1970
        try Data("{\"nextAllowedAt\":\(far)}".utf8).write(to: dir.appendingPathComponent("s2-throttle"))
        let slot = try FakeClock(t0).throttle(dir).reserveSlot()
        XCTAssertEqual(slot, t0)
    }

    func testStateFileAndDirectoryArePrivate() throws {
        _ = try FakeClock(t0).throttle(dir).reserveSlot()
        let dirMode = try FileManager.default.attributesOfItem(atPath: dir.path)[.posixPermissions] as? Int
        let fileMode = try FileManager.default.attributesOfItem(
            atPath: dir.appendingPathComponent("s2-throttle").path)[.posixPermissions] as? Int
        XCTAssertEqual(dirMode, 0o700)
        XCTAssertEqual(fileMode, 0o600)
    }
}
