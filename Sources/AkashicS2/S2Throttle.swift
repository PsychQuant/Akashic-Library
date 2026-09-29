import AkashicCore
import Foundation

public enum S2ThrottleError: Error, Equatable, CustomStringConvertible {
    case stateFile(path: String, errno: Int32)

    public var description: String {
        switch self {
        case .stateFile(let path, let e): return "無法使用 S2 節流狀態檔 \(displaySafe(path, max: 800))（errno \(e)）"
        }
    }
}

/// 跨程序節流：以 `flock` 鎖住狀態檔預約送出時段（design〈跨程序節流：預約時段，429 退避共用〉）。
public final class S2FileThrottle: S2Throttling, @unchecked Sendable {
    public static let interval: TimeInterval = 1.05
    public static let staleAfter: TimeInterval = 60
    public static let fileName = "s2-throttle"

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

    /// 狀態檔內容。`blockedUntil` 由 429 退避寫入（任務 3.2）。
    struct State: Codable, Equatable {
        var nextAllowedAt: Double = 0
        var blockedUntil: Double?
    }

    /// 在排他鎖內預約一個送出時段並回傳它；**解鎖後**呼叫者才等待，
    /// 所以其他程序可以接著預約下一個時段。存的時間比現在晚超過 60 秒時視為過期。
    func reserveSlot() throws -> Date {
        try withLockedState { state in
            let t = now().timeIntervalSince1970
            var next = state.nextAllowedAt
            if next - t > Self.staleAfter { next = t }
            let slot = Swift.max(t, next)
            state.nextAllowedAt = slot + Self.interval
            return Date(timeIntervalSince1970: slot)
        }
    }

    /// 預約時段、睡到時段；醒來後在鎖內再看一次 429 的封鎖期——預約之後才被
    /// 別的程序的 429 擋住時，重新預約（spec「A 429 delays the other session too」）。
    public func acquire() async throws {
        while true {
            let slot = try reserveSlot()
            let wait = slot.timeIntervalSince(now())
            if wait > 0 { try await sleep(wait) }
            if try !isBlocked() { return }
        }
    }

    /// 記下 429 的退避：`until` 之前任何呼叫者都不送出。
    public func backOff(until: Date) throws {
        try withLockedState { state in
            let u = until.timeIntervalSince1970
            state.blockedUntil = Swift.max(state.blockedUntil ?? 0, u)
            state.nextAllowedAt = Swift.max(state.nextAllowedAt, u)
        }
    }

    /// 仍在封鎖期內？封鎖期比現在晚超過 60 秒視為過期（時鐘回撥或檔案損毀）。
    func isBlocked() throws -> Bool {
        try withLockedState { state in
            guard let blocked = state.blockedUntil else { return false }
            let t = now().timeIntervalSince1970
            if blocked - t > Self.staleAfter { state.blockedUntil = nil; return false }
            return blocked > t
        }
    }

    /// 開檔 → `flock(LOCK_EX)` → 讀 → 改 → 寫回 → 關檔（關檔即解鎖，程序中途死掉也不留鎖）。
    func withLockedState<T>(_ body: (inout State) throws -> T) throws -> T {
        try FileManager.default.createDirectory(
            at: stateDirectory, withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700])
        let path = stateFile.path
        let fd = open(path, O_RDWR | O_CREAT, 0o600)
        guard fd >= 0 else { throw S2ThrottleError.stateFile(path: path, errno: errno) }
        defer { close(fd) }
        guard flock(fd, LOCK_EX) == 0 else { throw S2ThrottleError.stateFile(path: path, errno: errno) }

        var bytes = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while true {
            let n = read(fd, &buffer, buffer.count)
            if n < 0 { throw S2ThrottleError.stateFile(path: path, errno: errno) }
            if n == 0 { break }
            bytes.append(buffer, count: n)
        }
        // 空檔或損毀的內容視同全新狀態——最壞的結果是多送一個請求，不會卡住任何人。
        var state = (try? JSONDecoder().decode(State.self, from: bytes)) ?? State()
        let result = try body(&state)

        let out = try JSONEncoder().encode(state)
        guard ftruncate(fd, 0) == 0, lseek(fd, 0, SEEK_SET) == 0 else {
            throw S2ThrottleError.stateFile(path: path, errno: errno)
        }
        let written = out.withUnsafeBytes { write(fd, $0.baseAddress, out.count) }
        guard written == out.count else { throw S2ThrottleError.stateFile(path: path, errno: errno) }
        return result
    }
}
