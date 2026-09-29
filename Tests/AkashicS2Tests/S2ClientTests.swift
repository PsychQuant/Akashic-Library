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
