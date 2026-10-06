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
    /// 只裝 plugin 的使用者讀不到 repo 內的路徑，所以兩種位置都寫。
    public static let setupDocument = "plugin/skills/akashic-bootstrap/references/semantic-scholar.md"
    /// 只裝 plugin 的使用者讀不到上面那個 repo 內的路徑；錯誤訊息把兩個位置分行寫，行長上限不會截掉第二個。
    public static let setupDocumentInPlugin = "plugin 安裝處的 skills/akashic-bootstrap/references/semantic-scholar.md"

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
            guard let url = loopbackURL(raw) else { throw S2SettingsError.baseURLNotLoopback(displaySafeInvisible(raw)) }
            target = .loopback(url)
        }

        var service = keychainService
        if let raw = value("AKASHIC_S2_KEYCHAIN_SERVICE") {
            guard raw.hasPrefix(testServicePrefix), raw.count > testServicePrefix.count else {
                throw S2SettingsError.keychainServiceNotForTests(displaySafeInvisible(raw))
            }
            service = raw
        }

        let stateDirectory: URL
        if let raw = value("AKASHIC_S2_STATE_DIR") {
            guard raw.hasPrefix("/") else { throw S2SettingsError.stateDirectoryNotAbsolute(displaySafeInvisible(raw)) }
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

/// payload 在擲出端逃脫一次（`displaySafeInvisible`），描述原樣組句——repo 的消毒紀律（#554）。
public enum S2SettingsError: Error, Equatable, CustomStringConvertible, SanitizedErrorDescription {
    case baseURLNotLoopback(String)
    case keychainServiceNotForTests(String)
    case stateDirectoryNotAbsolute(String)

    public var description: String {
        switch self {
        case .baseURLNotLoopback(let raw):
            return "AKASHIC_S2_BASE_URL 只接受本機位址（http://127.0.0.1、http://localhost、http://[::1]，可帶 port）；收到「\(raw)」"   // display-safe-exempt: raw 擲出端已 displaySafeInvisible
        case .keychainServiceNotForTests(let raw):
            return "AKASHIC_S2_KEYCHAIN_SERVICE 只接受以「akashic-test-」開頭的測試用名稱；收到「\(raw)」"   // display-safe-exempt: raw 擲出端已 displaySafeInvisible
        case .stateDirectoryNotAbsolute(let raw):
            return "AKASHIC_S2_STATE_DIR 必須是絕對路徑；收到「\(raw)」"   // display-safe-exempt: raw 擲出端已 displaySafeInvisible
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
/// payload 在擲出端逃脫一次，描述原樣組句（#554）。
public enum S2Error: Error, Equatable, CustomStringConvertible, SanitizedErrorDescription {
    case keyUnavailable(S2KeyError)
    case notFound(endpoint: String, subject: String)
    case rateLimited(endpoint: String, reason: String)
    case http(endpoint: String, status: Int)
    case network(endpoint: String, reason: String)
    case invalidResponse(endpoint: String)
    case invalidRequest(endpoint: String)
    /// 注入的連線帶磁碟快取：含 `x-api-key` 的請求會被寫進磁碟。程式錯誤，不是使用者能修的——在讀金鑰之前就拒絕，
    /// 以錯誤回報（MCP 時是 `isError`），不是讓整個程序 trap。
    case unsafeSession(endpoint: String)

    public var description: String {
        switch self {
        case .keyUnavailable(let e):
            return displaySafeErrorText(e)
        case .notFound(let endpoint, let subject):
            return "Semantic Scholar 找不到「\(subject)」（\(endpoint)）"   // display-safe-exempt: subject、endpoint 擲出端已 displaySafeInvisible
        case .rateLimited(let endpoint, let reason):
            return "Semantic Scholar 限流用盡（\(endpoint)）：\(reason)"   // display-safe-exempt: endpoint、reason 擲出端已 displaySafeInvisible
        case .http(let endpoint, let status):
            return "Semantic Scholar 回應錯誤：\(endpoint) 回 HTTP \(status)"   // display-safe-exempt: endpoint 擲出端已 displaySafeInvisible；status 是 HTTP 狀態碼（Int）
        case .network(let endpoint, let reason):
            return "連線 Semantic Scholar 失敗（\(endpoint)）：\(reason)"   // display-safe-exempt: endpoint、reason 擲出端已 displaySafeInvisible
        case .invalidResponse(let endpoint):
            return "Semantic Scholar 的回應無法解讀（\(endpoint)）"   // display-safe-exempt: endpoint 擲出端已 displaySafeInvisible
        case .unsafeSession(let endpoint):
            return "拒絕送出 \(endpoint)：這個 URLSession 帶磁碟快取，含金鑰的請求會被寫進磁碟（程式錯誤，請回報；預設連線不帶快取）"   // display-safe-exempt: endpoint 擲出端已 displaySafeInvisible
        case .invalidRequest(let endpoint):
            return "無法組出 \(endpoint) 的請求網址"   // display-safe-exempt: endpoint 擲出端已 displaySafeInvisible
        }
    }
}

public protocol S2Throttling: Sendable {
    /// 等到呼叫者可以送出才回來。
    func acquire() async throws
    /// 記下 429 的退避：`until` 之前任何呼叫者都不送出。
    func backOff(until: Date) throws
}

/// 不跟隨轉址：S2 的 API 不該轉址，而 URLSession 轉址時會把自訂 header（`x-api-key`）原樣帶到新位址——
/// 目標若是別的主機或 `http`，金鑰就送出去了（#664 verify R1）。回傳 nil＝把 3xx 當成最終回應交還給呼叫者。
final class S2NoRedirectDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

public final class S2Client: Sendable {
    /// 預設連線：不快取、不存 cookie。`URLSession.shared` 帶著 `URLCache.shared`，S2 的回應沒有 `Cache-Control`，
    /// GET 會被啟發式快取，序列化的請求（含 `x-api-key`）就寫進 `~/Library/Caches/<程序名>/Cache.db`（#664 verify R1）。
    public static func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil
        config.httpCookieStorage = nil
        config.httpShouldSetCookies = false
        config.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        return URLSession(configuration: config)
    }

    /// 全程序共用的預設連線。每次呼叫都新建一個，長駐的 `akashic-mcp` 會隨呼叫次數增長（R2 實測 2,000 次約 +61 MiB；
    /// 每次補 `invalidate` 只省約 5%）。連線本身無快取、無 cookie，共用沒有跨呼叫的狀態。
    public static let defaultSession: URLSession = makeSession()

    /// 這個連線會不會把請求寫進磁碟快取。**逐請求的 `cachePolicy` 擋不住寫入**（它只管讀；R2 實測：帶磁碟快取的連線照樣把含
    /// `x-api-key` 的請求存進 `Cache.db`，task delegate 的 `willCacheResponse` 也不會被呼叫），所以保證在連線這一層。
    public static func isCacheFree(_ session: URLSession) -> Bool {
        guard let cache = session.configuration.urlCache else { return true }
        return cache.diskCapacity == 0
    }

    public let settings: S2Settings
    let keyProvider: S2KeyProviding
    let throttle: S2Throttling
    let session: URLSession
    let now: @Sendable () -> Date

    public init(settings: S2Settings, keyProvider: S2KeyProviding, throttle: S2Throttling,
                session: URLSession = S2Client.defaultSession, now: @escaping @Sendable () -> Date = { Date() }) {
        self.settings = settings
        self.keyProvider = keyProvider
        self.throttle = throttle
        self.session = session
        self.now = now
    }

    /// 送出一個請求並回傳回應本文。讀不到金鑰時在送出任何請求之前就停下。
    public func send(_ request: S2Request) async throws -> Data {
        // 注入的連線若帶磁碟快取，含金鑰的請求會被寫進磁碟（見 `isCacheFree`）：在讀金鑰與送出任何請求之前就拒絕。
        // 用錯誤，不用 `precondition`——後者在 MCP server 裡會讓每個工具一起掛掉。兩條出貨路徑都用預設連線，所以這一行擋的是呼叫端換進來的連線。
        guard Self.isCacheFree(session) else { throw S2Error.unsafeSession(endpoint: displaySafeInvisible(request.endpoint)) }
        let key: S2APIKey?
        if settings.readsKeychain {
            do { key = try keyProvider.key() } catch let e as S2KeyError { throw S2Error.keyUnavailable(e) }   // display-safe-exempt: e 是 S2KeyError（SanitizedErrorDescription，建構端已逃）
        } else {
            key = nil
        }
        let urlRequest = try makeURLRequest(request, key: key)

        for attempt in 0...Self.maxRetries {
            do { try await throttle.acquire() } catch S2ThrottleError.blocked(let seconds) {
                // 另一個呼叫者記下了比我願意等的更長的封鎖：照 429 用盡處理（結束碼 4），一個請求都不送。
                throw S2Error.rateLimited(endpoint: displaySafeInvisible(request.endpoint),
                                          reason: displaySafeInvisible("另一個呼叫者收到 429，共用封鎖還有 \(seconds) 秒"))
            }
            let data: Data
            let response: URLResponse
            do {
                (data, response) = try await session.data(for: urlRequest, delegate: S2NoRedirectDelegate())
            } catch let e as URLError {
                throw S2Error.network(endpoint: displaySafeInvisible(request.endpoint), reason: displaySafeInvisible("URLError \(e.code.rawValue)"))
            } catch {
                throw S2Error.network(endpoint: displaySafeInvisible(request.endpoint), reason: displaySafeInvisible("\(type(of: error))"))
            }
            guard let http = response as? HTTPURLResponse else {
                throw S2Error.invalidResponse(endpoint: displaySafeInvisible(request.endpoint))
            }
            switch http.statusCode {
            case 200..<300:
                return data
            case 404:
                throw S2Error.notFound(endpoint: displaySafeInvisible(request.endpoint), subject: displaySafeInvisible(request.subject ?? request.path))
            case 429:
                let delay = Self.retryAfter(http.value(forHTTPHeaderField: "Retry-After"), now: now())
                    ?? Self.defaultBackOff[Swift.min(attempt, Self.defaultBackOff.count - 1)]
                // 先把退避記進共用狀態，再決定這次呼叫要不要等或放棄：一個呼叫者「不再重試」不代表其他呼叫者
                // 可以無視 S2 的退避（最後一次 429、`Retry-After` 超過 60 秒都一樣；#664 verify R1）。
                try throttle.backOff(until: now().addingTimeInterval(delay))
                if attempt == Self.maxRetries {
                    throw S2Error.rateLimited(endpoint: displaySafeInvisible(request.endpoint),
                                              reason: displaySafeInvisible("重試 \(Self.maxRetries) 次後仍是 429"))
                }
                if delay > Self.maxRetryAfter {
                    throw S2Error.rateLimited(endpoint: displaySafeInvisible(request.endpoint),
                                              reason: displaySafeInvisible("Retry-After 為 \(Int(delay)) 秒，超過 \(Int(Self.maxRetryAfter)) 秒"))
                }
            default:
                throw S2Error.http(endpoint: displaySafeInvisible(request.endpoint), status: http.statusCode)   // display-safe-exempt: http.statusCode 是 Int
            }
        }
        throw S2Error.rateLimited(endpoint: displaySafeInvisible(request.endpoint), reason: displaySafeInvisible("重試 \(Self.maxRetries) 次後仍是 429"))
    }

    static let maxRetries = 3
    static let maxRetryAfter: TimeInterval = 60
    /// 解析 `Retry-After` 時的封頂（一天）。
    static let maxParsedRetryAfter: TimeInterval = 86_400
    /// 沒有 `Retry-After` 時第 1、2、3 次重試前的等待。
    static let defaultBackOff: [TimeInterval] = [2, 4, 8]

    /// `Retry-After` 可以是秒數或 HTTP-date（RFC 9110）；無法解讀時回 nil。
    static func retryAfter(_ header: String?, now: Date) -> TimeInterval? {
        guard let raw = header?.trimmingCharacters(in: .whitespaces), !raw.isEmpty else { return nil }
        // 對方給的任意整數：`Int.max` 之類轉成 `Int(delay)` 會讓整個程序當掉。超過一天的等待與超過一分鐘沒有差別（都是限流用盡），封頂。
        if let seconds = Int(raw), seconds >= 0 { return Swift.min(TimeInterval(seconds), maxParsedRetryAfter) }
        // 全是數字、卻大到放不進 `Int`：對方說的是「很久」，不是「沒給」——不能落到預設的 2／4／8 秒重試。
        if raw.unicodeScalars.allSatisfy({ ("0"..."9").contains($0) }) { return maxParsedRetryAfter }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "GMT")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss 'GMT'"
        guard let date = formatter.date(from: raw) else { return nil }
        return Swift.min(Swift.max(0, date.timeIntervalSince(now)), maxParsedRetryAfter)
    }

    /// 組出 `URLRequest`。`x-api-key` 只在 `attachesKey(to:)` 成立時附上。
    func makeURLRequest(_ request: S2Request, key: S2APIKey?) throws -> URLRequest {
        // `percentEncodedPath` 收到未編碼的字元會 precondition 當掉——先檢查。
        let allowed = CharacterSet.urlPathAllowed.union(CharacterSet(charactersIn: "%"))
        guard request.path.hasPrefix("/"),
              request.path.unicodeScalars.allSatisfy({ allowed.contains($0) }),
              var comps = URLComponents(url: settings.baseURL, resolvingAgainstBaseURL: false)
        else { throw S2Error.invalidRequest(endpoint: displaySafeInvisible(request.endpoint)) }
        comps.percentEncodedPath = request.path
        // 自行編碼 query：URLComponents 預設不編碼 `+`，伺服器可能把它當成空白。
        var queryAllowed = CharacterSet.urlQueryAllowed
        queryAllowed.remove(charactersIn: "+&=?")
        func enc(_ v: String) -> String? { v.addingPercentEncoding(withAllowedCharacters: queryAllowed) }
        comps.percentEncodedQueryItems = request.query.isEmpty ? nil : request.query.map {
            URLQueryItem(name: enc($0.name) ?? $0.name, value: $0.value.flatMap(enc))
        }
        guard let url = comps.url else { throw S2Error.invalidRequest(endpoint: displaySafeInvisible(request.endpoint)) }

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = request.method.rawValue
        urlRequest.timeoutInterval = 60
        // 只管「讀不讀快取」與 cookie，**不管「存不存」**——存不存由連線決定（`makeSession`、`isCacheFree`）。
        urlRequest.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        urlRequest.httpShouldHandleCookies = false
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
