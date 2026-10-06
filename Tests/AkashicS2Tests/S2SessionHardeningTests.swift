import XCTest
@testable import AkashicS2

/// #664 verify R1 第 1、2 列：金鑰不得落盤、不得隨轉址送到別的主機。
///
/// 兩個失敗都出在「預設用 `URLSession.shared`」：它帶著 `URLCache.shared`（序列化的請求連同
/// `x-api-key` 寫進 `~/Library/Caches/akashic/Cache.db`），而且自動跟隨轉址、把自訂 header 一起帶過去。
final class S2SessionHardeningTests: XCTestCase {
    private let paper = S2Request(endpoint: "paper", path: "/graph/v1/paper/DOI:10.1037/a0038889",
                                  subject: "DOI:10.1037/a0038889")

    private func client() throws -> S2Client {
        S2Client(settings: try S2Settings.resolve(environment: ["HOME": "/Users/tester"]),
                 keyProvider: CountingKeyProvider(.success(S2APIKey(value: "k-123"))),
                 throttle: NoThrottle(), session: StubURLProtocol.session())
    }

    // MARK: 不落盤

    func testTheSessionClientsUseByDefaultNeverCachesAndStoresNoCookies() {
        let c = S2Client.makeSession().configuration
        XCTAssertNil(c.urlCache, "有 URLCache 就會把含 x-api-key 的請求寫進磁碟")
        XCTAssertNil(c.httpCookieStorage)
        XCTAssertFalse(c.httpShouldSetCookies)
        XCTAssertEqual(c.requestCachePolicy, .reloadIgnoringLocalAndRemoteCacheData)
    }

    func testEveryRequestOptsOutOfCachesAndCookiesEvenOnAnInjectedSession() throws {
        let r = try client().makeURLRequest(paper, key: S2APIKey(value: "k-123"))
        XCTAssertEqual(r.cachePolicy, .reloadIgnoringLocalAndRemoteCacheData)
        XCTAssertFalse(r.httpShouldHandleCookies)
    }

    // MARK: 不跟隨轉址

    func testACrossHostRedirectIsNotFollowedSoTheKeyNeverLeavesTheS2Host() async throws {
        StubURLProtocol.install { req in
            if req.url?.host == "api.semanticscholar.org" {
                return .init(status: 302, headers: ["Location": "https://elsewhere.example/steal"], body: Data())
            }
            return .init(status: 200, headers: [:], body: Data("{}".utf8))
        }
        do {
            _ = try await client().send(paper)
            XCTFail("轉址應該被當成錯誤，不是成功")
        } catch {
            XCTAssertEqual(error as? S2Error, .http(endpoint: "paper", status: 302))
        }
        XCTAssertEqual(StubURLProtocol.requests.count, 1, "不得對轉址的目標再送一個請求")
        XCTAssertNil(StubURLProtocol.requests.first { $0.url?.host == "elsewhere.example" })
    }

    func testAnHttpsToHttpDowngradeRedirectIsNotFollowedEither() async throws {
        StubURLProtocol.install { req in
            if req.url?.scheme == "https" {
                return .init(status: 301, headers: ["Location": "http://api.semanticscholar.org/graph/v1/paper/x"], body: Data())
            }
            return .init(status: 200, headers: [:], body: Data("{}".utf8))
        }
        do {
            _ = try await client().send(paper)
            XCTFail("降級轉址不得被跟隨")
        } catch {
            XCTAssertEqual(error as? S2Error, .http(endpoint: "paper", status: 301))
        }
        XCTAssertEqual(StubURLProtocol.requests.count, 1)
        XCTAssertNil(StubURLProtocol.requests.first { $0.url?.scheme == "http" })
    }

    func testASameHostRedirectIsNotFollowedAndDoesNotBypassTheThrottle() async throws {
        StubURLProtocol.install { req in
            if req.url?.path.hasSuffix("/moved") == false {
                return .init(status: 307, headers: ["Location": "https://api.semanticscholar.org/graph/v1/paper/moved"], body: Data())
            }
            return .init(status: 200, headers: [:], body: Data("{}".utf8))
        }
        let throttle = RecordingThrottle()
        let c = S2Client(settings: try S2Settings.resolve(environment: ["HOME": "/Users/tester"]),
                         keyProvider: CountingKeyProvider(.success(S2APIKey(value: "k-123"))),
                         throttle: throttle, session: StubURLProtocol.session())
        do { _ = try await c.send(paper); XCTFail("轉址應該是錯誤") } catch {
            XCTAssertEqual(error as? S2Error, .http(endpoint: "paper", status: 307))
        }
        XCTAssertEqual(StubURLProtocol.requests.count, throttle.acquires, "每個真正送出的請求都要經過節流")
    }
}
