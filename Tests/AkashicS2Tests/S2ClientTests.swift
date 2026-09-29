import XCTest
@testable import AkashicS2

/// #664 任務 1.1：三個測試覆寫的解析（Requirement「Test overrides are confined」）。
/// 期望值一律寫成字面值，不呼叫被測程式推導。
final class S2SettingsTests: XCTestCase {
    private let home = ["HOME": "/Users/tester"]

    func testDefaultsTargetSemanticScholarWithRealKeychainNames() throws {
        let s = try S2Settings.resolve(environment: home)
        XCTAssertEqual(s.target, .semanticScholar)
        XCTAssertEqual(s.keychainService, "semantic-scholar")
        XCTAssertEqual(s.keychainAccount, "default")
        XCTAssertEqual(s.stateDirectory.path, "/Users/tester/Library/Caches/akashic")
    }

    func testEmptyOverridesMeanUnset() throws {
        let env = home.merging(["AKASHIC_S2_BASE_URL": "", "AKASHIC_S2_KEYCHAIN_SERVICE": "",
                                "AKASHIC_S2_STATE_DIR": ""]) { $1 }
        let s = try S2Settings.resolve(environment: env)
        XCTAssertEqual(s.target, .semanticScholar)
        XCTAssertEqual(s.keychainService, "semantic-scholar")
        XCTAssertEqual(s.stateDirectory.path, "/Users/tester/Library/Caches/akashic")
    }

    func testLoopbackBaseURLsAreAccepted() throws {
        for raw in ["http://127.0.0.1:8765", "http://localhost", "http://[::1]:9", "http://127.0.0.1/"] {
            let s = try S2Settings.resolve(environment: home.merging(["AKASHIC_S2_BASE_URL": raw]) { $1 })
            guard case .loopback(let url) = s.target else {
                return XCTFail("\(raw) should resolve to a loopback target, got \(s.target)")
            }
            XCTAssertEqual(url.scheme, "http", raw)
        }
    }

    func testNonLoopbackBaseURLsAreRefused() {
        let refused = [
            "https://example.org",
            "http://example.org",
            "https://127.0.0.1:8765",          // spec：只收 http
            "http://127.0.0.1.evil.com",       // 前綴像 loopback，host 不是
            "http://localhost@evil.com",       // userinfo 是 localhost，host 是 evil.com
            "http://user@127.0.0.1",
            "http://127.0.0.1/graph/v1",       // 帶路徑
            "http://127.0.0.1?x=1",
            "not a url",
        ]
        for raw in refused {
            XCTAssertThrowsError(
                try S2Settings.resolve(environment: home.merging(["AKASHIC_S2_BASE_URL": raw]) { $1 }), raw
            ) { error in
                XCTAssertEqual(error as? S2SettingsError, .baseURLNotLoopback(raw), raw)
            }
        }
    }

    func testKeychainServiceOverrideMustBeTestPrefixed() throws {
        let ok = try S2Settings.resolve(
            environment: home.merging(["AKASHIC_S2_KEYCHAIN_SERVICE": "akashic-test-7f3a"]) { $1 })
        XCTAssertEqual(ok.keychainService, "akashic-test-7f3a")
        XCTAssertEqual(ok.keychainAccount, "default")

        for raw in ["stat-sinica-compute", "semantic-scholar", "akashic-test-", "Akashic-Test-x"] {
            XCTAssertThrowsError(
                try S2Settings.resolve(environment: home.merging(["AKASHIC_S2_KEYCHAIN_SERVICE": raw]) { $1 }), raw
            ) { error in
                XCTAssertEqual(error as? S2SettingsError, .keychainServiceNotForTests(raw), raw)
            }
        }
    }

    func testStateDirectoryOverrideMustBeAbsolute() throws {
        let ok = try S2Settings.resolve(environment: home.merging(["AKASHIC_S2_STATE_DIR": "/tmp/s2-state"]) { $1 })
        XCTAssertEqual(ok.stateDirectory.path, "/tmp/s2-state")

        for raw in ["relative/dir", "~/s2", "./s2"] {
            XCTAssertThrowsError(
                try S2Settings.resolve(environment: home.merging(["AKASHIC_S2_STATE_DIR": raw]) { $1 }), raw
            ) { error in
                XCTAssertEqual(error as? S2SettingsError, .stateDirectoryNotAbsolute(raw), raw)
            }
        }
    }

    func testBaseURLOverrideTurnsOffKeychainReading() throws {
        let s = try S2Settings.resolve(environment: home.merging(["AKASHIC_S2_BASE_URL": "http://127.0.0.1:8765"]) { $1 })
        XCTAssertFalse(s.readsKeychain)
        XCTAssertTrue(try S2Settings.resolve(environment: home).readsKeychain)
    }
}

/// #664 任務 2.1：金鑰讀取（Requirement「The key is read from the keychain without
/// interaction and never exposed」）。不建立任何 keychain 項目——ACL 分支以純函式測，
/// 狀態碼是 Apple 定義的字面值。
final class S2KeyProviderTests: XCTestCase {
    func testKeyNeverPrintsItsValue() {
        let key = S2APIKey(value: "sk-live-abc123")
        XCTAssertEqual("\(key)", "<redacted>")
        XCTAssertEqual(String(describing: key), "<redacted>")
        XCTAssertEqual(String(reflecting: key), "<redacted>")
        var dumped = ""
        dump(key, to: &dumped)
        XCTAssertFalse(dumped.contains("sk-live"), dumped)
    }

    func testMissingItemIsReportedAsMissing() {
        let service = "akashic-test-\(UUID().uuidString)"
        let provider = S2KeychainKeyProvider(service: service, account: "default")
        XCTAssertThrowsError(try provider.key()) { error in
            XCTAssertEqual(error as? S2KeyError, .missing(service: service, account: "default"))
        }
        XCTAssertEqual(provider.probe(), S2KeyProbe(present: false, readable: false))
    }

    func testStatusClassification() {
        let s = "akashic-test-x", a = "default"
        XCTAssertNil(S2KeychainKeyProvider.classify(status: 0, service: s, account: a))
        XCTAssertEqual(S2KeychainKeyProvider.classify(status: -25300, service: s, account: a),
                       .missing(service: s, account: a))       // errSecItemNotFound
        XCTAssertEqual(S2KeychainKeyProvider.classify(status: -25308, service: s, account: a),
                       .notReadable(service: s, account: a))   // errSecInteractionNotAllowed
        XCTAssertEqual(S2KeychainKeyProvider.classify(status: -25293, service: s, account: a),
                       .notReadable(service: s, account: a))   // errSecAuthFailed
        XCTAssertEqual(S2KeychainKeyProvider.classify(status: -34018, service: s, account: a),
                       .keychain(status: -34018))              // 其他狀態原樣回報
    }

    func testDecodeTrimsEdgesAndRejectsUnsafeValues() throws {
        let s = "akashic-test-x", a = "default"
        XCTAssertEqual(try S2KeychainKeyProvider.decode(Data("abc123\n".utf8), service: s, account: a).value, "abc123")
        XCTAssertEqual(try S2KeychainKeyProvider.decode(Data("  abc123 ".utf8), service: s, account: a).value, "abc123")
        for bad in [Data(), Data("   ".utf8), Data("ab\ncd".utf8), Data("ab\u{0}cd".utf8), Data([0xff, 0xfe])] {
            XCTAssertThrowsError(try S2KeychainKeyProvider.decode(bad, service: s, account: a)) { error in
                XCTAssertEqual(error as? S2KeyError, .invalidValue(service: s, account: a))
            }
        }
    }

    func testErrorMessagesNameTheItemAndTheSetupDocument() {
        let missing = String(describing: S2KeyError.missing(service: "semantic-scholar", account: "default"))
        XCTAssertTrue(missing.contains("semantic-scholar"), missing)
        XCTAssertTrue(missing.contains("default"), missing)
        XCTAssertTrue(missing.contains("semantic-scholar.md"), missing)
        let unreadable = String(describing: S2KeyError.notReadable(service: "semantic-scholar", account: "default"))
        XCTAssertTrue(unreadable.contains("所有 app"), unreadable)
    }
}

// MARK: - 測試替身（同 target 的其他測試檔共用）

/// 攔截所有請求的 URLProtocol。**不連網**：回應由 `handler` 決定，收到的請求記在 `requests`。
final class StubURLProtocol: URLProtocol {
    struct Reply { let status: Int; let headers: [String: String]; let body: Data }
    private static let lock = NSLock()
    nonisolated(unsafe) private static var _handler: ((URLRequest) throws -> Reply)?
    nonisolated(unsafe) private static var _requests: [URLRequest] = []

    static func install(_ handler: @escaping (URLRequest) throws -> Reply) {
        lock.lock(); defer { lock.unlock() }
        _handler = handler
        _requests = []
    }
    static var requests: [URLRequest] { lock.lock(); defer { lock.unlock() }; return _requests }

    static func session() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: config)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lock.lock()
        Self._requests.append(request)
        let handler = Self._handler
        Self.lock.unlock()
        do {
            guard let handler else { throw URLError(.unsupportedURL) }
            let reply = try handler(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: reply.status,
                                           httpVersion: "HTTP/1.1", headerFields: reply.headers)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: reply.body)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }
    override func stopLoading() {}
}

/// 不節流（任務 3 之前的測試用）。
struct NoThrottle: S2Throttling {
    func acquire() async throws {}
    func backOff(until: Date) throws {}
}

/// 固定回同一把金鑰，並計算被呼叫幾次。
final class CountingKeyProvider: S2KeyProviding, @unchecked Sendable {
    private let lock = NSLock()
    private var _calls = 0
    private let result: Result<S2APIKey, S2KeyError>
    init(_ result: Result<S2APIKey, S2KeyError>) { self.result = result }
    var calls: Int { lock.lock(); defer { lock.unlock() }; return _calls }
    func key() throws -> S2APIKey {
        lock.lock(); _calls += 1; lock.unlock()
        return try result.get()
    }
}

/// #664 任務 2.2：host 規則與錯誤分類（Requirement「The key header is sent only to the
/// Semantic Scholar host」「Other failures are reported with their cause」）。
final class S2ClientRequestTests: XCTestCase {
    private let home = ["HOME": "/Users/tester"]
    private let paper = S2Request(endpoint: "paper", path: "/graph/v1/paper/DOI:10.1037/a0038889",
                                  subject: "DOI:10.1037/a0038889")

    private func client(_ env: [String: String], key: CountingKeyProvider) throws -> S2Client {
        S2Client(settings: try S2Settings.resolve(environment: home.merging(env) { $1 }),
                 keyProvider: key, throttle: NoThrottle(), session: StubURLProtocol.session())
    }

    func testKeyIsAttachedOnlyForTheSemanticScholarHost() async throws {
        StubURLProtocol.install { _ in .init(status: 200, headers: [:], body: Data("{}".utf8)) }
        let key = CountingKeyProvider(.success(S2APIKey(value: "k-123")))
        _ = try await client([:], key: key).send(paper)
        let sent = try XCTUnwrap(StubURLProtocol.requests.first)
        XCTAssertEqual(sent.url?.host, "api.semanticscholar.org")
        XCTAssertEqual(sent.value(forHTTPHeaderField: "x-api-key"), "k-123")
        XCTAssertFalse(sent.url!.absoluteString.contains("k-123"))
    }

    func testLoopbackTargetNeverReadsTheKeychainNorSendsAKey() async throws {
        StubURLProtocol.install { _ in .init(status: 200, headers: [:], body: Data("{}".utf8)) }
        let key = CountingKeyProvider(.success(S2APIKey(value: "k-123")))
        _ = try await client(["AKASHIC_S2_BASE_URL": "http://127.0.0.1:8765"], key: key).send(paper)
        let sent = try XCTUnwrap(StubURLProtocol.requests.first)
        XCTAssertEqual(sent.url?.host, "127.0.0.1")
        XCTAssertEqual(sent.url?.port, 8765)
        XCTAssertNil(sent.value(forHTTPHeaderField: "x-api-key"))
        XCTAssertEqual(key.calls, 0)
    }

    func testAttachesKeyRequiresHttpsAndTheExactHost() {
        XCTAssertTrue(S2Client.attachesKey(to: URL(string: "https://api.semanticscholar.org/graph/v1/paper/x")!))
        XCTAssertFalse(S2Client.attachesKey(to: URL(string: "http://api.semanticscholar.org/graph/v1/paper/x")!))
        XCTAssertFalse(S2Client.attachesKey(to: URL(string: "https://api.semanticscholar.org.evil.com/x")!))
        XCTAssertFalse(S2Client.attachesKey(to: URL(string: "https://127.0.0.1:8765/x")!))
    }

    func testUnavailableKeySendsNoRequest() async throws {
        StubURLProtocol.install { _ in .init(status: 200, headers: [:], body: Data("{}".utf8)) }
        let missing = S2KeyError.missing(service: "semantic-scholar", account: "default")
        do {
            _ = try await client([:], key: CountingKeyProvider(.failure(missing))).send(paper)
            XCTFail("expected keyUnavailable")
        } catch {
            XCTAssertEqual(error as? S2Error, .keyUnavailable(missing))
        }
        XCTAssertEqual(StubURLProtocol.requests.count, 0)
    }

    func testNotFoundNamesTheIdentifier() async throws {
        StubURLProtocol.install { _ in .init(status: 404, headers: [:], body: Data("{\"error\":\"not found\"}".utf8)) }
        let req = S2Request(endpoint: "paper", path: "/graph/v1/paper/DOI:10.0000/none", subject: "DOI:10.0000/none")
        do {
            _ = try await client([:], key: CountingKeyProvider(.success(S2APIKey(value: "k-123")))).send(req)
            XCTFail("expected notFound")
        } catch {
            XCTAssertEqual(error as? S2Error, .notFound(endpoint: "paper", subject: "DOI:10.0000/none"))
            XCTAssertTrue(String(describing: error).contains("DOI:10.0000/none"))
        }
    }

    func testServerErrorReportsStatusWithoutHeadersOrKey() async throws {
        StubURLProtocol.install { _ in .init(status: 500, headers: [:], body: Data()) }
        do {
            _ = try await client([:], key: CountingKeyProvider(.success(S2APIKey(value: "k-123")))).send(paper)
            XCTFail("expected http error")
        } catch {
            XCTAssertEqual(error as? S2Error, .http(endpoint: "paper", status: 500))
            let text = String(describing: error)
            XCTAssertTrue(text.contains("500"), text)
            XCTAssertFalse(text.contains("k-123"), text)
            XCTAssertFalse(text.lowercased().contains("x-api-key"), text)
        }
    }

    func testConnectionFailureIsANetworkError() async throws {
        StubURLProtocol.install { _ in throw URLError(.notConnectedToInternet) }
        do {
            _ = try await client([:], key: CountingKeyProvider(.success(S2APIKey(value: "k-123")))).send(paper)
            XCTFail("expected network error")
        } catch {
            guard case .network(let endpoint, _)? = error as? S2Error else {
                return XCTFail("expected .network, got \(error)")
            }
            XCTAssertEqual(endpoint, "paper")
        }
    }
}
