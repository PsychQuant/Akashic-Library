import AkashicCore
import Foundation

/// #664：Semantic Scholar 共用接口的設定。
///
/// 三個環境覆寫只為測試存在，各自有限制（design〈測試接縫：三個受限的覆寫〉）。
/// 解析一律經 `environment:` 注入（沿用 `LibraryLocator` 的慣例），不直接讀 process env。
public struct S2Settings: Sendable, Equatable {
    public static let productionHost = "api.semanticscholar.org"
    public static let productionBaseURL = URL(string: "https://api.semanticscholar.org")!
    public static let keychainService = "semantic-scholar"
    public static let keychainAccount = "default"
    /// 測試覆寫的 service 名稱必須以此開頭——讓測試走完「沒有金鑰」路徑，
    /// 但無法把讀取指向任何真實項目。
    public static let testServicePrefix = "akashic-test-"
    /// 給使用者的金鑰設定文件（錯誤訊息引用它）。
    public static let setupDocument = "plugin/skills/akashic-bootstrap/references/semantic-scholar.md"

    /// 請求送往哪裡。「讀不讀 keychain」由它推導，不另設旗標——
    /// 兩者分開存放時會出現「覆寫了網址卻還讀金鑰」這種不一致的組合。
    public enum Target: Sendable, Equatable {
        /// 正式的 S2 主機。會讀 keychain，並附上 `x-api-key`。
        case semanticScholar
        /// 測試用的本機位址。不讀 keychain，也不附金鑰。
        case loopback(URL)
    }

    public let target: Target
    public let keychainService: String
    public let keychainAccount: String
    public let stateDirectory: URL

    public var baseURL: URL {
        switch target {
        case .semanticScholar: return Self.productionBaseURL
        case .loopback(let url): return url
        }
    }

    /// 只有請求會送到 S2 主機時才讀 keychain（spec「Test overrides are confined」）。
    public var readsKeychain: Bool { target == .semanticScholar }

    public static func resolve(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) throws -> S2Settings {
        // 空字串視同未設定——與 `LibraryLocator` 對 `AKASHIC_LIBRARY` 的處理一致。
        func value(_ key: String) -> String? {
            guard let v = environment[key], !v.isEmpty else { return nil }
            return v
        }

        var target = Target.semanticScholar
        if let raw = value("AKASHIC_S2_BASE_URL") {
            guard let url = loopbackURL(raw) else { throw S2SettingsError.baseURLNotLoopback(raw) }
            target = .loopback(url)
        }

        var service = keychainService
        if let raw = value("AKASHIC_S2_KEYCHAIN_SERVICE") {
            guard raw.hasPrefix(testServicePrefix), raw.count > testServicePrefix.count else {
                throw S2SettingsError.keychainServiceNotForTests(raw)
            }
            service = raw
        }

        let stateDirectory: URL
        if let raw = value("AKASHIC_S2_STATE_DIR") {
            guard raw.hasPrefix("/") else { throw S2SettingsError.stateDirectoryNotAbsolute(raw) }
            stateDirectory = URL(fileURLWithPath: raw, isDirectory: true)
        } else if let home = value("HOME") {
            // 依注入的 HOME 展開（#309 的教訓：NSHomeDirectory() 無視 $HOME）。
            stateDirectory = URL(fileURLWithPath: home, isDirectory: true)
                .appendingPathComponent("Library/Caches/akashic", isDirectory: true)
        } else {
            let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            stateDirectory = caches.appendingPathComponent("akashic", isDirectory: true)
        }

        return S2Settings(target: target, keychainService: service,
                          keychainAccount: keychainAccount, stateDirectory: stateDirectory)
    }

    /// 只接受 `http` 上的 `127.0.0.1`、`localhost`、`[::1]`，可帶 port；
    /// 不接受 userinfo、路徑、query、fragment。host 以解析後的值精確比對——
    /// `http://localhost@evil.com` 的 host 是 `evil.com`。
    static func loopbackURL(_ raw: String) -> URL? {
        guard var comps = URLComponents(string: raw),
              comps.scheme?.lowercased() == "http",
              comps.user == nil, comps.password == nil,
              comps.query == nil, comps.fragment == nil,
              comps.path.isEmpty || comps.path == "/",
              let host = comps.host?.lowercased(),
              ["127.0.0.1", "localhost", "::1", "[::1]"].contains(host)
        else { return nil }
        comps.path = ""
        return comps.url
    }
}

public enum S2SettingsError: Error, Equatable, CustomStringConvertible {
    case baseURLNotLoopback(String)
    case keychainServiceNotForTests(String)
    case stateDirectoryNotAbsolute(String)

    public var description: String {
        switch self {
        case .baseURLNotLoopback(let raw):
            return "AKASHIC_S2_BASE_URL 只接受本機位址（http://127.0.0.1、http://localhost、http://[::1]，可帶 port）；收到「\(displaySafe(raw))」"
        case .keychainServiceNotForTests(let raw):
            return "AKASHIC_S2_KEYCHAIN_SERVICE 只接受以「akashic-test-」開頭的測試用名稱；收到「\(displaySafe(raw))」"
        case .stateDirectoryNotAbsolute(let raw):
            return "AKASHIC_S2_STATE_DIR 必須是絕對路徑；收到「\(displaySafe(raw))」"
        }
    }
}

// MARK: - 請求與錯誤（任務 2.2）

public enum S2HTTPMethod: String, Sendable {
    case get = "GET"
    case post = "POST"
}

/// 一個已組好的 S2 請求。`path` 已編碼；`subject` 是 404 時要點名的識別碼。
public struct S2Request: Sendable, Equatable {
    public let endpoint: String
    public let method: S2HTTPMethod
    public let path: String
    public let query: [URLQueryItem]
    public let body: Data?
    public let subject: String?

    public init(endpoint: String, method: S2HTTPMethod = .get, path: String,
                query: [URLQueryItem] = [], body: Data? = nil, subject: String? = nil) {
        self.endpoint = endpoint
        self.method = method
        self.path = path
        self.query = query
        self.body = body
        self.subject = subject
    }
}

/// 錯誤文字只含端點、狀態碼、識別碼與錯誤類別——**不含任何請求 header**。
public enum S2Error: Error, Equatable, CustomStringConvertible {
    case keyUnavailable(S2KeyError)
    case notFound(endpoint: String, subject: String)
    case rateLimited(endpoint: String, reason: String)
    case http(endpoint: String, status: Int)
    case network(endpoint: String, reason: String)
    case invalidResponse(endpoint: String)
    case invalidRequest(endpoint: String)

    public var description: String {
        switch self {
        case .keyUnavailable(let e):
            return e.description
        case .notFound(let endpoint, let subject):
            return "Semantic Scholar 找不到「\(displaySafe(subject))」（\(endpoint)）"
        case .rateLimited(let endpoint, let reason):
            return "Semantic Scholar 限流用盡（\(endpoint)）：\(reason)"
        case .http(let endpoint, let status):
            return "Semantic Scholar 回應錯誤：\(endpoint) 回 HTTP \(status)"
        case .network(let endpoint, let reason):
            return "連線 Semantic Scholar 失敗（\(endpoint)）：\(reason)"
        case .invalidResponse(let endpoint):
            return "Semantic Scholar 的回應無法解讀（\(endpoint)）"
        case .invalidRequest(let endpoint):
            return "無法組出 \(endpoint) 的請求網址"
        }
    }
}

public protocol S2Throttling: Sendable {
    /// 等到呼叫者可以送出才回來。
    func acquire() async throws
    /// 記下 429 的退避：`until` 之前任何呼叫者都不送出。
    func backOff(until: Date) throws
}

public final class S2Client: Sendable {
    public let settings: S2Settings
    let keyProvider: S2KeyProviding
    let throttle: S2Throttling
    let session: URLSession
    let now: @Sendable () -> Date

    public init(settings: S2Settings, keyProvider: S2KeyProviding, throttle: S2Throttling,
                session: URLSession = .shared, now: @escaping @Sendable () -> Date = { Date() }) {
        self.settings = settings
        self.keyProvider = keyProvider
        self.throttle = throttle
        self.session = session
        self.now = now
    }

    /// 送出一個請求並回傳回應本文。讀不到金鑰時在送出任何請求之前就停下。
    public func send(_ request: S2Request) async throws -> Data {
        let key: S2APIKey?
        if settings.readsKeychain {
            do { key = try keyProvider.key() } catch let e as S2KeyError { throw S2Error.keyUnavailable(e) }
        } else {
            key = nil
        }
        let urlRequest = try makeURLRequest(request, key: key)

        for attempt in 0...Self.maxRetries {
            try await throttle.acquire()
            let data: Data
            let response: URLResponse
            do {
                (data, response) = try await session.data(for: urlRequest)
            } catch let e as URLError {
                throw S2Error.network(endpoint: request.endpoint,
                                      reason: "URLError \(e.code.rawValue)：\(e.localizedDescription)")
            } catch {
                throw S2Error.network(endpoint: request.endpoint, reason: String(describing: type(of: error)))
            }
            guard let http = response as? HTTPURLResponse else {
                throw S2Error.invalidResponse(endpoint: request.endpoint)
            }
            switch http.statusCode {
            case 200..<300:
                return data
            case 404:
                throw S2Error.notFound(endpoint: request.endpoint, subject: request.subject ?? request.path)
            case 429:
                if attempt == Self.maxRetries {
                    throw S2Error.rateLimited(endpoint: request.endpoint,
                                              reason: "重試 \(Self.maxRetries) 次後仍是 429")
                }
                let delay = Self.retryAfter(http.value(forHTTPHeaderField: "Retry-After"), now: now())
                    ?? Self.defaultBackOff[attempt]
                if delay > Self.maxRetryAfter {
                    throw S2Error.rateLimited(endpoint: request.endpoint,
                                              reason: "Retry-After 為 \(Int(delay)) 秒，超過 \(Int(Self.maxRetryAfter)) 秒")
                }
                try throttle.backOff(until: now().addingTimeInterval(delay))
            default:
                throw S2Error.http(endpoint: request.endpoint, status: http.statusCode)
            }
        }
        throw S2Error.rateLimited(endpoint: request.endpoint, reason: "重試 \(Self.maxRetries) 次後仍是 429")
    }

    static let maxRetries = 3
    static let maxRetryAfter: TimeInterval = 60
    /// 沒有 `Retry-After` 時第 1、2、3 次重試前的等待。
    static let defaultBackOff: [TimeInterval] = [2, 4, 8]

    /// `Retry-After` 可以是秒數或 HTTP-date（RFC 9110）；無法解讀時回 nil。
    static func retryAfter(_ header: String?, now: Date) -> TimeInterval? {
        guard let raw = header?.trimmingCharacters(in: .whitespaces), !raw.isEmpty else { return nil }
        if let seconds = Int(raw), seconds >= 0 { return TimeInterval(seconds) }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "GMT")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss 'GMT'"
        guard let date = formatter.date(from: raw) else { return nil }
        return Swift.max(0, date.timeIntervalSince(now))
    }

    /// 組出 `URLRequest`。`x-api-key` 只在 `attachesKey(to:)` 成立時附上。
    func makeURLRequest(_ request: S2Request, key: S2APIKey?) throws -> URLRequest {
        // `percentEncodedPath` 收到未編碼的字元會 precondition 當掉——先檢查。
        let allowed = CharacterSet.urlPathAllowed.union(CharacterSet(charactersIn: "%"))
        guard request.path.hasPrefix("/"),
              request.path.unicodeScalars.allSatisfy({ allowed.contains($0) }),
              var comps = URLComponents(url: settings.baseURL, resolvingAgainstBaseURL: false)
        else { throw S2Error.invalidRequest(endpoint: request.endpoint) }
        comps.percentEncodedPath = request.path
        comps.queryItems = request.query.isEmpty ? nil : request.query
        guard let url = comps.url else { throw S2Error.invalidRequest(endpoint: request.endpoint) }

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = request.method.rawValue
        urlRequest.timeoutInterval = 60
        if let body = request.body {
            urlRequest.httpBody = body
            urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        if let key, Self.attachesKey(to: url) {
            urlRequest.setValue(key.value, forHTTPHeaderField: "x-api-key")
        }
        return urlRequest
    }

    /// 只有 `https` 且 host 恰為 `api.semanticscholar.org` 才附金鑰。
    static func attachesKey(to url: URL) -> Bool {
        url.scheme?.lowercased() == "https" && url.host?.lowercased() == S2Settings.productionHost
    }
}
