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
    /// 睡眠前呼叫（測試用來注入另一個程序在此刻的動作）；只觸發一次。
    var beforeFirstSleep: (() throws -> Void)?
    /// 記錄睡眠長度，並把時鐘往前推同樣的時間——醒來後重新檢查的迴圈才會前進。
    func recordSleep(_ s: TimeInterval) throws {
        let hook: (() throws -> Void)?
        lock.lock(); hook = beforeFirstSleep; beforeFirstSleep = nil; lock.unlock()
        try hook?()
        lock.lock(); slept.append(s); t = t.addingTimeInterval(s); lock.unlock()
    }
    func throttle(_ dir: URL) -> S2FileThrottle {
        S2FileThrottle(stateDirectory: dir, now: { [self] in now }, sleep: { [self] s in try recordSleep(s) })
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

/// #664 任務 3.2：429 退避由所有呼叫者共用（Requirement「Rate-limit responses back off
/// for every caller」）。
final class S2ThrottleBackOffTests: XCTestCase {
    private var dir: URL!
    private let t0 = Date(timeIntervalSince1970: 1_000_000)

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("s2-backoff-\(UUID().uuidString)", isDirectory: true)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: dir) }

    /// spec Scenario「A 429 delays the other session too」：A 在 1.00 收到 429、Retry-After: 3，
    /// 此時 B 已預約時段在等 → B 的下一個請求不早於 4.00。
    func testA429DelaysTheOtherSessionToo() async throws {
        let clock = FakeClock(t0)
        let a = clock.throttle(dir), b = clock.throttle(dir)
        try await a.acquire()                                   // A 於 0.00 送出
        clock.set(t0.addingTimeInterval(0.30))
        clock.beforeFirstSleep = { [t0] in                      // B 預約後、醒來前：A 在 1.00 收到 429
            clock.set(t0.addingTimeInterval(1.00))
            try a.backOff(until: t0.addingTimeInterval(4.00))
            clock.set(t0.addingTimeInterval(0.30))              // 回到 B 開始睡的時刻
        }
        try await b.acquire()
        XCTAssertGreaterThanOrEqual(clock.now.timeIntervalSince(t0), 4.00 - 1e-9)
    }

    func testBackOffMovesTheNextAllowedTime() throws {
        let clock = FakeClock(t0.addingTimeInterval(1.00))
        let a = clock.throttle(dir)
        try a.backOff(until: t0.addingTimeInterval(4.00))
        XCTAssertGreaterThanOrEqual(try a.reserveSlot().timeIntervalSince(t0), 4.00)
    }

    // MARK: 長退避（#664 verify R1 第 4、19 列）

    /// 比 60 秒長的 `Retry-After` 以前被當成「過期的狀態」清掉，其他 session 看不到它。
    /// 現在記下來；剩下的封鎖超過 60 秒時，其他呼叫者**快速失敗**（結束碼 4），不睡上好幾分鐘。
    func testALongBackOffIsKeptAndOtherCallersFailFastInsteadOfSleepingThroughIt() async throws {
        let clock = FakeClock(t0)
        let a = clock.throttle(dir), b = clock.throttle(dir)
        try a.backOff(until: t0.addingTimeInterval(120))
        do {
            try await b.acquire()
            XCTFail("封鎖還有 120 秒，應該快速失敗")
        } catch {
            XCTAssertEqual(error as? S2ThrottleError, .blocked(seconds: 120))
        }
        XCTAssertTrue(clock.slept.isEmpty, "快速失敗不睡")
    }

    /// 剩下的封鎖降到 60 秒以內，呼叫者就等它過去再送——而且是睡過去，不是在鎖上空轉。
    func testWhenTheRemainingBlockIsShortACallerSleepsThroughItAndThenGoes() async throws {
        let clock = FakeClock(t0)
        let a = clock.throttle(dir)
        try a.backOff(until: t0.addingTimeInterval(120))
        clock.set(t0.addingTimeInterval(70))
        try await a.acquire()
        XCTAssertGreaterThanOrEqual(clock.now.timeIntervalSince(t0), 120 - 1e-9)
        XCTAssertLessThan(clock.slept.count, 5, "睡了 \(clock.slept.count) 次：這是空轉")
    }

    /// 荒謬的 `Retry-After`（一天）只記一小時：之後的呼叫者不會被一個過期很久的狀態卡到明天。
    func testAnAbsurdRetryAfterIsRecordedAsAtMostOneHour() async throws {
        let clock = FakeClock(t0)
        let a = clock.throttle(dir)
        try a.backOff(until: t0.addingTimeInterval(86_400))
        clock.set(t0.addingTimeInterval(3_601))
        try await a.acquire()                                   // 不丟、不睡
        XCTAssertTrue(clock.slept.isEmpty)
    }

    /// 時鐘被往回撥或檔案壞掉時，比一小時還遠的封鎖才視為過期。
    func testABlockFarBeyondTheCapIsTreatedAsStale() async throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let far = t0.addingTimeInterval(100_000).timeIntervalSince1970
        try Data("{\"nextAllowedAt\":0,\"blockedUntil\":\(far)}".utf8).write(to: dir.appendingPathComponent("s2-throttle"))
        let clock = FakeClock(t0)
        try await clock.throttle(dir).acquire()
        XCTAssertTrue(clock.slept.isEmpty)
    }

    /// 狀態檔裡留著比一小時還遠的舊封鎖（時鐘回撥、檔案損毀）：新的 429 退避不能被它蓋掉。
    func testAFreshBackOffSurvivesAStaleFarFutureBlockInTheFile() throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let far = t0.addingTimeInterval(100_000).timeIntervalSince1970
        try Data("{\"nextAllowedAt\":\(far),\"blockedUntil\":\(far)}".utf8).write(to: dir.appendingPathComponent("s2-throttle"))
        let clock = FakeClock(t0)
        let a = clock.throttle(dir)
        try a.backOff(until: t0.addingTimeInterval(30))
        XCTAssertGreaterThanOrEqual(try a.reserveSlot().timeIntervalSince(t0), 30, "新的退避不見了")
    }

    /// 寫進狀態檔的 `blockedUntil` 必須是新的退避值，不是留著的舊遠期值（R3：只驗 `nextAllowedAt` 那一半，
    /// 拿掉清除舊 `blockedUntil` 的那一行測試照綠）。
    func testThePersistedBlockIsTheFreshBackOffNotTheStaleOne() throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let far = t0.addingTimeInterval(100_000).timeIntervalSince1970
        let file = dir.appendingPathComponent("s2-throttle")
        try Data("{\"nextAllowedAt\":\(far),\"blockedUntil\":\(far)}".utf8).write(to: file)
        try FakeClock(t0).throttle(dir).backOff(until: t0.addingTimeInterval(30))
        let state = try JSONDecoder().decode(S2FileThrottle.State.self, from: Data(contentsOf: file))
        XCTAssertEqual(state.blockedUntil ?? 0, t0.addingTimeInterval(30).timeIntervalSince1970, accuracy: 1e-6)
        XCTAssertEqual(state.nextAllowedAt, t0.addingTimeInterval(30).timeIntervalSince1970, accuracy: 1e-6)
    }

    // MARK: 狀態檔（#664 verify R1 第 20、23 列）

    /// 狀態檔若是 symlink，不跟隨——否則寫入會落到別處。
    func testAStateFileThatIsASymlinkIsRefusedAndTheTargetIsNotWritten() throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let target = dir.appendingPathComponent("elsewhere")
        try Data("untouched".utf8).write(to: target)
        try FileManager.default.createSymbolicLink(at: dir.appendingPathComponent("s2-throttle"), withDestinationURL: target)
        XCTAssertThrowsError(try FakeClock(t0).throttle(dir).reserveSlot()) { error in
            guard case .stateFile(_, let e)? = error as? S2ThrottleError else { return XCTFail("\(error)") }
            XCTAssertEqual(e, ELOOP)
        }
        XCTAssertEqual(try String(contentsOf: target, encoding: .utf8), "untouched")
    }

    /// 已存在而權限較寬的狀態檔（例如別的程式建的）收緊到 0600。
    func testAnExistingWiderStateFileIsTightenedTo0600() throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("s2-throttle")
        try Data("{}".utf8).write(to: file)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: file.path)
        _ = try FakeClock(t0).throttle(dir).reserveSlot()
        XCTAssertEqual(try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? Int, 0o600)
    }
}

/// 記錄 backOff 的節流替身（不真的等）。
final class RecordingThrottle: S2Throttling, @unchecked Sendable {
    private let lock = NSLock()
    private(set) var acquires = 0
    private(set) var backOffs: [Date] = []
    // NSLock 的 lock()／unlock() 在 async context 不可用（Swift 6 語言模式；pre-push 以 -warnings-as-errors 擋下），
    // 所以計數放在同步的 helper 裡。
    func acquire() async throws { recordAcquire() }
    func backOff(until: Date) throws { lock.lock(); backOffs.append(until); lock.unlock() }
    private func recordAcquire() { lock.lock(); acquires += 1; lock.unlock() }
}

/// #664 任務 3.2：重試上限（spec Example「Retry budget」四列）。
final class S2RetryTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_000_000)
    private let paper = S2Request(endpoint: "paper", path: "/graph/v1/paper/DOI:10.1037/a0038889",
                                  subject: "DOI:10.1037/a0038889")

    private func run(_ replies: [StubURLProtocol.Reply]) async -> (Result<Data, Error>, RecordingThrottle, Int) {
        let queue = ReplyQueue(replies)
        StubURLProtocol.install { _ in queue.next() }
        let throttle = RecordingThrottle()
        let settings = try! S2Settings.resolve(environment: ["HOME": "/Users/tester"])
        let client = S2Client(settings: settings,
                              keyProvider: CountingKeyProvider(.success(S2APIKey(value: "k-123"))),
                              throttle: throttle, session: StubURLProtocol.session(), now: { [t0] in t0 })
        let result: Result<Data, Error>
        do { result = .success(try await client.send(paper)) } catch { result = .failure(error) }
        return (result, throttle, StubURLProtocol.requests.count)
    }

    private let ok = StubURLProtocol.Reply(status: 200, headers: [:], body: Data("{}".utf8))
    private func limited(_ retryAfter: String? = nil) -> StubURLProtocol.Reply {
        .init(status: 429, headers: retryAfter.map { ["Retry-After": $0] } ?? [:], body: Data())
    }

    func testOneRetryThenSuccess() async {
        let (r, throttle, sent) = await run([limited(), ok])
        XCTAssertNoThrow(try r.get())
        XCTAssertEqual(sent, 2)
        XCTAssertEqual(throttle.backOffs, [t0.addingTimeInterval(2)])
    }

    func testThreeRetriesThenSuccess() async {
        let (r, throttle, sent) = await run([limited(), limited(), limited(), ok])
        XCTAssertNoThrow(try r.get())
        XCTAssertEqual(sent, 4)
        XCTAssertEqual(throttle.backOffs, [2, 4, 8].map { t0.addingTimeInterval($0) })
    }

    func testFourth429IsRateLimited() async {
        let (r, throttle, sent) = await run([limited(), limited(), limited(), limited()])
        XCTAssertEqual(sent, 4)
        // 最後一次 429 也要記進共用退避：這次呼叫不再重試，不代表其他呼叫者可以無視 S2 的退避（verify R1 第 4 列）。
        XCTAssertEqual(throttle.backOffs, [2, 4, 8, 8].map { t0.addingTimeInterval($0) })
        guard case .failure(let e) = r, case .rateLimited(let endpoint, _)? = e as? S2Error else {
            return XCTFail("expected rateLimited, got \(r)")
        }
        XCTAssertEqual(endpoint, "paper")
    }

    func testRetryAfterOver60SecondsFailsWithoutWaiting() async {
        let (r, throttle, sent) = await run([limited("120"), ok])
        XCTAssertEqual(sent, 1)
        XCTAssertEqual(throttle.backOffs, [t0.addingTimeInterval(120)], "這次呼叫不等，但要讓其他呼叫者知道")
        guard case .failure(let e) = r, case .rateLimited? = e as? S2Error else {
            return XCTFail("expected rateLimited, got \(r)")
        }
    }

    /// 另一個呼叫者記下了超過 60 秒的封鎖：這個呼叫者在送出任何請求之前就以 `rateLimited` 失敗（結束碼 4），
    /// 不是節流層的原始錯誤（結束碼 1）。
    func testABlockRecordedByAnotherCallerSurfacesAsRateLimitedWithoutSendingAnything() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("s2-blocked-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let clock = FakeClock(t0)
        try clock.throttle(dir).backOff(until: t0.addingTimeInterval(120))
        StubURLProtocol.install { _ in .init(status: 200, headers: [:], body: Data("{}".utf8)) }
        let client = S2Client(settings: try S2Settings.resolve(environment: ["HOME": "/Users/tester"]),
                              keyProvider: CountingKeyProvider(.success(S2APIKey(value: "k-123"))),
                              throttle: clock.throttle(dir), session: StubURLProtocol.session(), now: { [t0] in t0 })
        do { _ = try await client.send(paper); XCTFail("應該以 rateLimited 失敗") } catch {
            guard case .rateLimited(let endpoint, let reason)? = error as? S2Error else { return XCTFail("\(error)") }
            XCTAssertEqual(endpoint, "paper")
            XCTAssertTrue(reason.contains("120"), reason)
        }
        XCTAssertEqual(StubURLProtocol.requests.count, 0)
    }

    /// `Retry-After` 是對方給的任意整數：`Int.max` 轉成 `Int(delay)` 會讓整個程序當掉（MCP 時是整個 server）。
    func testAnAbsurdRetryAfterIsRateLimitedAndDoesNotCrash() async {
        let (r, throttle, sent) = await run([limited("9223372036854775807"), ok])
        XCTAssertEqual(sent, 1)
        guard case .failure(let e) = r, case .rateLimited? = e as? S2Error else { return XCTFail("expected rateLimited, got \(r)") }
        XCTAssertEqual(throttle.backOffs.count, 1)
        XCTAssertLessThanOrEqual(throttle.backOffs[0].timeIntervalSince(t0), 86_400)
    }

    /// 比 `Int.max` 還大的 `Retry-After`：`Int(raw)` 解不出來，以前被當成「沒給」而照預設 2／4／8 秒重試——
    /// 對方明明說了「很久」。現在視為封頂值。
    func testARetryAfterBeyondIntRangeIsTreatedAsVeryLongNotAsAbsent() async {
        let (r, throttle, sent) = await run([limited("99999999999999999999999999"), ok])
        XCTAssertEqual(sent, 1, "不得照預設 2 秒重試")
        guard case .failure(let e) = r, case .rateLimited? = e as? S2Error else { return XCTFail("expected rateLimited, got \(r)") }
        XCTAssertEqual(throttle.backOffs.count, 1)
        XCTAssertGreaterThan(throttle.backOffs[0].timeIntervalSince(t0), 3_600 - 1)
    }

    func testRetryAfterSecondsAndHTTPDateAreHonoured() async {
        let (_, t1, _) = await run([limited("3"), ok])
        XCTAssertEqual(t1.backOffs, [t0.addingTimeInterval(3)])
        // 1970-01-12 13:46:45 GMT ＝ t0 ＋ 5 秒
        let (_, t2, _) = await run([limited("Mon, 12 Jan 1970 13:46:45 GMT"), ok])
        XCTAssertEqual(t2.backOffs, [t0.addingTimeInterval(5)])
    }
}

/// 依序回覆的佇列。
final class ReplyQueue: @unchecked Sendable {
    private let lock = NSLock()
    private var replies: [StubURLProtocol.Reply]
    init(_ replies: [StubURLProtocol.Reply]) { self.replies = replies }
    func next() -> StubURLProtocol.Reply {
        lock.lock(); defer { lock.unlock() }
        return replies.isEmpty ? .init(status: 599, headers: [:], body: Data()) : replies.removeFirst()
    }
}
