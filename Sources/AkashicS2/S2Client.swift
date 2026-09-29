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
