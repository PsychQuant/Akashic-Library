import AkashicCore
import Foundation

/// path 在擲出端逃脫一次，描述原樣組句（#554）。
public enum S2ThrottleError: Error, Equatable, CustomStringConvertible, SanitizedErrorDescription {
    case stateFile(path: String, errno: Int32)
    /// 另一個呼叫者收到 429，共用封鎖還有這麼久，而且比一個呼叫者願意等的上限（60 秒）長：快速失敗，不睡過去。
    case blocked(seconds: Int)

    public var description: String {
        switch self {
        case .stateFile(let path, let e): return "無法使用 S2 節流狀態檔 \(path)（errno \(e)）"   // display-safe-exempt: path 擲出端已 displaySafeInvisible；e 是 errno（Int32）
        case .blocked(let seconds): return "另一個呼叫者收到 Semantic Scholar 的 429，共用封鎖還有 \(seconds) 秒"   // display-safe-exempt: seconds 是 Int
        }
    }
}

/// 跨程序節流：以 `flock` 鎖住狀態檔預約送出時段（design〈跨程序節流：預約時段，429 退避共用〉）。
public final class S2FileThrottle: S2Throttling, @unchecked Sendable {
    public static let interval: TimeInterval = 1.05
    public static let staleAfter: TimeInterval = 60
    /// 一個呼叫者願意等一個封鎖過去的上限；剩下比這長就快速失敗（結束碼 4），與 `Retry-After` 超過 60 秒時的處置一致。
    public static let maxWait: TimeInterval = 60
    /// 共用封鎖最多記多久：S2 回再長的 `Retry-After` 也只記這麼久，之後的呼叫者再試一次、必要時再記一次。
    public static let maxBackOff: TimeInterval = 3600
    /// 封鎖比「現在＋`maxBackOff`」還遠超過 `staleAfter` 才視為過期（時鐘回撥或檔案損毀）。
    /// 與時段／放行的 `staleAfter` 分開：合法的長退避不能被 60 秒的過期門檻丟掉（#664 verify R1）。
    static var blockStaleAfter: TimeInterval { maxBackOff + staleAfter }
    public static let fileName = "s2-throttle"
    /// 比這短的等待不睡（#701）：排程器兌現不了，而準時醒來的呼叫者會因浮點誤差差上幾個 ulp。
    /// 放行間隔因此保證的是 `interval − releaseSlack`＝1.049 秒。
    static let releaseSlack: TimeInterval = 0.001

    let stateDirectory: URL
    let now: @Sendable () -> Date
    let sleep: @Sendable (TimeInterval) async throws -> Void

    public init(stateDirectory: URL,
                now: @escaping @Sendable () -> Date = { Date() },
                sleep: @escaping @Sendable (TimeInterval) async throws -> Void = { seconds in
                    try await Task.sleep(nanoseconds: UInt64(max(0, seconds) * 1_000_000_000))
                }) {
        self.stateDirectory = stateDirectory
        self.now = now
        self.sleep = sleep
    }

    public var stateFile: URL { stateDirectory.appendingPathComponent(Self.fileName) }

    /// `akashic s2 status` 用：讀出下次可送時間，**不建立**目錄或檔案；沒有狀態檔時回 nil。
    public func peekNextAllowedAt() -> Date? {
        guard let data = FileManager.default.contents(atPath: stateFile.path),
              let state = try? JSONDecoder().decode(State.self, from: data), state.nextAllowedAt > 0
        else { return nil }
        return Date(timeIntervalSince1970: state.nextAllowedAt)
    }

    /// 狀態檔內容。`blockedUntil` 由 429 退避寫入（任務 3.2）；`lastReleasedAt` 是上一次放行的實際時刻（#701）。
    /// 沒有 `lastReleasedAt` 的舊檔照讀；舊 binary 寫回時會丟掉它，那一次的放行間隔回到只由預約保證。
    struct State: Codable, Equatable {
        var nextAllowedAt: Double = 0
        var blockedUntil: Double?
        var lastReleasedAt: Double?
    }

    /// 在排他鎖內預約一個送出時段並回傳它；**解鎖後**呼叫者才等待，
    /// 所以其他程序可以接著預約下一個時段。存的時間比現在晚超過 60 秒時視為過期。
    func reserveSlot() throws -> Date {
        try withLockedState { state in
            let t = now().timeIntervalSince1970
            if let remaining = Self.remainingBlock(&state, at: t), remaining > Self.maxWait {
                throw S2ThrottleError.blocked(seconds: Int(remaining.rounded(.up)))
            }
            var next = state.nextAllowedAt
            if next - t > Self.staleAfter { next = t }
            let slot = Swift.max(t, next)
            state.nextAllowedAt = slot + Self.interval
            return Date(timeIntervalSince1970: slot)
        }
    }

    /// 預約時段、睡到時段；醒來後在鎖內決定能不能送出（`release()`）：預約之後才被別的程序的 429 擋住時重新預約
    /// （spec「A 429 delays the other session too」），離上一次放行不到 `interval` 時睡到滿了再問一次（#701）。
    public func acquire() async throws {
        var slot = try reserveSlot()
        while true {
            let wait = slot.timeIntervalSince(now())
            if wait > 0 { try await sleep(wait) }
            switch try release() {
            case .go: return
            case .rebook: slot = try reserveSlot()
            case .wait(let more): slot = now().addingTimeInterval(more)
            }
        }
    }

    /// 醒來的呼叫者在鎖內得到的答案。
    enum Release: Equatable {
        case go
        /// 仍在 429 的封鎖期：重新預約。
        case rebook
        /// 離上一次放行不到 `interval`：再等這麼久。
        case wait(TimeInterval)
    }

    /// 在鎖內決定醒來的呼叫者能不能送出。
    ///
    /// 預約只保證每一次放行不早於自己的時段，**不保證兩次放行的間隔**：`Task.sleep` 睡得越久晚醒越多（#701 實測睡約 1.05 秒的
    /// 晚醒 124–139 ms、睡約 0.5 秒的晚醒約 58 ms），前一個呼叫者晚醒、後一個準時醒時，兩次放行會比 `interval` 近。所以放行時
    /// 記下這一刻（`lastReleasedAt`），下一個醒來的呼叫者離它不到 `interval` 就再等；這個比對在同一把鎖裡，程序之間不會同時通過。
    /// 放行時也把 `nextAllowedAt` 推到至少這一刻加 `interval`，之後的預約從實際放行算起。代價：單一呼叫者連續請求時，
    /// 每個間隔都多付前一次的晚醒量（#701 R1 verify 實測平均 1.10 秒對 1.056 秒，約 5%），理由見 changelog。
    /// 封鎖期與上一次放行比現在晚超過 60 秒時視為過期（時鐘回撥或檔案損毀）。
    func release() throws -> Release {
        try withLockedState { state in
            let t = now().timeIntervalSince1970
            if let remaining = Self.remainingBlock(&state, at: t) {
                // 封鎖還剩很久就快速失敗；剩得短才睡過去（`.rebook` 會睡到 `nextAllowedAt`，`backOff` 已把它推到封鎖結束）。
                if remaining > Self.maxWait { throw S2ThrottleError.blocked(seconds: Int(remaining.rounded(.up))) }
                return .rebook
            }
            if let last = state.lastReleasedAt, last - t <= Self.staleAfter {
                let more = last + Self.interval - t
                if more > Self.releaseSlack { return .wait(more) }
            }
            state.lastReleasedAt = t
            state.nextAllowedAt = Swift.max(state.nextAllowedAt, t + Self.interval)
            return .go
        }
    }

    /// 記下 429 的退避：`until` 之前任何呼叫者都不送出。
    public func backOff(until: Date) throws {
        try withLockedState { state in
            let t = now().timeIntervalSince1970
            let u = Swift.min(until.timeIntervalSince1970, t + Self.maxBackOff)
            state.blockedUntil = Swift.max(state.blockedUntil ?? 0, u)
            state.nextAllowedAt = Swift.max(state.nextAllowedAt, u)
        }
    }

    /// 仍然有效的封鎖還剩幾秒；沒有或已過回 nil。過期的（時鐘回撥或檔案損毀）順手清掉。
    static func remainingBlock(_ state: inout State, at t: Double) -> TimeInterval? {
        guard let blocked = state.blockedUntil else { return nil }
        if blocked - t > blockStaleAfter { state.blockedUntil = nil; return nil }
        return blocked > t ? blocked - t : nil
    }

    /// 開檔 → `flock(LOCK_EX)` → 讀 → 改 → 寫回 → 關檔（關檔即解鎖，程序中途死掉也不留鎖）。
    /// `errno` 在失敗的那個呼叫之後**立刻**取走，再去組錯誤（組錯誤會呼叫別的函式，可能改掉它）。
    /// 狀態檔不跟隨 symlink（`O_NOFOLLOW`），並收緊到 0600——目錄只在建立時是 0700，已存在的目錄不動它的權限。
    func withLockedState<T>(_ body: (inout State) throws -> T) throws -> T {
        try FileManager.default.createDirectory(
            at: stateDirectory, withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700])
        let path = stateFile.path
        func failure(_ e: Int32) -> S2ThrottleError { .stateFile(path: displaySafeInvisible(path, max: 800), errno: e) }
        let fd = open(path, O_RDWR | O_CREAT | O_NOFOLLOW, 0o600)
        guard fd >= 0 else { throw failure(errno) }
        defer { close(fd) }
        guard flock(fd, LOCK_EX) == 0 else { throw failure(errno) }
        _ = fchmod(fd, 0o600)   // 別人先建出來而權限較寬的檔；不是自己的檔就收不動，照樣用

        var bytes = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while true {
            let n = read(fd, &buffer, buffer.count)
            if n < 0 { throw failure(errno) }
            if n == 0 { break }
            bytes.append(buffer, count: n)
        }
        // 空檔或損毀的內容視同全新狀態——最壞的結果是多送一個請求，不會卡住任何人。
        var state = (try? JSONDecoder().decode(State.self, from: bytes)) ?? State()
        let result = try body(&state)

        let out = try JSONEncoder().encode(state)
        guard ftruncate(fd, 0) == 0 else { throw failure(errno) }
        guard lseek(fd, 0, SEEK_SET) == 0 else { throw failure(errno) }
        let written = out.withUnsafeBytes { write(fd, $0.baseAddress, out.count) }
        if written < 0 { throw failure(errno) }
        if written != out.count { throw failure(EIO) }   // 寫了一半：errno 沒有意義，不拿舊的充數
        return result
    }
}
