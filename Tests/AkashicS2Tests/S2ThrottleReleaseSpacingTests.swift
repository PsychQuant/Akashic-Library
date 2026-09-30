import XCTest
@testable import AkashicS2

/// #701：兩次放行的間隔由鎖內記下的實際放行時刻保證，不由預約的時段保證。
///
/// 預約只保證每一次放行不早於自己的時段。`Task.sleep` 睡得越久晚醒越多——2026-09-30 在 30 次跨程序測試裡量到
/// 睡約 1.05 秒的呼叫者晚 124–139 ms 才醒、睡約 0.5 秒的晚約 58 ms。前一個呼叫者晚醒、後一個準時醒時，兩次放行只差
/// 1.05 秒減去兩者晚醒的差（實測放行間隔 0.976 秒，全套測試時量到 0.92 秒）。醒來之後在鎖內比對上一次放行的時刻，
/// 不到 1.05 秒就再等，這個間隔才成為保證。
final class S2ThrottleReleaseSpacingTests: XCTestCase {
    private var dir: URL!
    private let t0 = Date(timeIntervalSince1970: 1_000_000)

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("s2-release-\(UUID().uuidString)", isDirectory: true)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: dir) }

    /// A 的時段是 t0、晚 130 ms 才醒來放行；B 的時段是 t0 + 1.05、準時醒 → B 要再等 130 ms，不早於 t0 + 1.18 放行。
    func testALateWakingPredecessorPushesTheNextReleaseBack() async throws {
        let clock = FakeClock(t0)
        let a = clock.throttle(dir), b = clock.throttle(dir)
        XCTAssertEqual(try a.reserveSlot(), t0)
        clock.beforeFirstSleep = { [t0] in                      // B 預約後、睡著時：A 晚醒、放行
            clock.set(t0.addingTimeInterval(0.13))
            XCTAssertEqual(try a.release(), .go)
            clock.set(t0)                                       // 回到 B 開始睡的時刻
        }
        try await b.acquire()
        // Date 以 2001 年起算的秒數存，t0 附近的解析度約 1e-7 秒，所以容許 1e-6
        XCTAssertGreaterThanOrEqual(clock.now.timeIntervalSince(t0), 1.18 - 1e-6)
        XCTAssertEqual(clock.slept.count, 2, "\(clock.slept)")   // 先睡到自己的時段，再補足與 A 的間隔
        XCTAssertEqual(clock.slept.last ?? -1, 0.13, accuracy: 1e-6)
    }

    /// 放行把 `nextAllowedAt` 推到放行時刻加 1.05：之後的預約從實際放行算起，`s2 status` 報的下次可送時間也不會早於它。
    func testReleasePushesTheNextAllowedTimeFromTheActualRelease() throws {
        let clock = FakeClock(t0)
        let a = clock.throttle(dir)
        XCTAssertEqual(try a.reserveSlot(), t0)
        clock.set(t0.addingTimeInterval(0.13))
        XCTAssertEqual(try a.release(), .go)
        XCTAssertEqual(a.peekNextAllowedAt()?.timeIntervalSince(t0) ?? -1, 1.18, accuracy: 1e-6)
        clock.set(t0.addingTimeInterval(0.20))
        XCTAssertEqual(try a.reserveSlot().timeIntervalSince(t0), 1.18, accuracy: 1e-6)
    }

    /// 上一次放行比現在晚超過 60 秒（時鐘回撥或檔案損毀）：視為過期，不擋人。
    func testAStaleLastReleaseDoesNotBlock() async throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let far = t0.addingTimeInterval(120).timeIntervalSince1970
        try Data("{\"nextAllowedAt\":0,\"lastReleasedAt\":\(far)}".utf8).write(to: dir.appendingPathComponent("s2-throttle"))
        let clock = FakeClock(t0)
        try await clock.throttle(dir).acquire()
        XCTAssertEqual(clock.slept, [])
        XCTAssertEqual(clock.now, t0)
    }
}
