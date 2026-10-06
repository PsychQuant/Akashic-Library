import AkashicCore
import Foundation
import LocalAuthentication
import Security

/// Semantic Scholar 的 API 金鑰。**任何描述方式都只印 `<redacted>`**：字串插值、
/// `String(reflecting:)`、`dump` 都不會露出值（預設的 struct 描述會把它整個印出來）。
/// 值只在 `S2Client` 附上 header 時於模組內讀取。
public struct S2APIKey: Sendable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    let value: String
    init(value: String) { self.value = value }
    public var description: String { "<redacted>" }
    public var debugDescription: String { "<redacted>" }
    public var customMirror: Mirror { Mirror(self, children: [], displayStyle: .struct) }
}

/// service／account 在建構端逃脫一次（它們可來自測試覆寫的環境變數），描述原樣組句（#554）。
public enum S2KeyError: Error, Equatable, CustomStringConvertible, SanitizedErrorDescription {
    /// keychain 沒有這個項目。
    case missing(service: String, account: String)
    /// 項目存在，但它的存取權限不允許在不跳授權框的情況下讀取。
    case notReadable(service: String, account: String)
    /// 內容是空的、不是 UTF-8，或內部含換行等控制字元（放進 header 會造成注入）。
    case invalidValue(service: String, account: String)
    /// 其他 keychain 錯誤，原樣回報狀態碼。
    case keychain(status: Int32)

    public var description: String {
        let doc = S2Settings.setupDocument
        switch self {
        case .missing(let s, let a):
            // 錯誤訊息本身帶可以照著做的指令：只裝 plugin 的使用者讀不到 repo 內的設定文件。`-w` 後面不接金鑰，系統會提示輸入。
            return "找不到 Semantic Scholar 的 API 金鑰：keychain 裡沒有 service「\(s)」、account「\(a)」的項目。在 Terminal 執行 security add-generic-password -s \"\(s)\" -a \"\(a)\" -A -w（-w 後面不要接金鑰，系統會提示你輸入）。說明見 \(doc)（plugin 使用者：plugin 安裝處的 skills/akashic-bootstrap/references/semantic-scholar.md）"   // display-safe-exempt: s、a 建構端已 displaySafeInvisible；doc 是常量
        case .notReadable(let s, let a):
            // -25308 既是「存取權限需要提示」也是「keychain 鎖著」，兩者回同一個狀態碼，所以兩個原因都講、先講便宜的那個。
            return "keychain 裡有 service「\(s)」、account「\(a)」的項目，但現在無法在不跳出授權框的情況下讀取它。可能的原因，依序檢查：(1) keychain 鎖著（SSH 或背景工作階段最常見）——先解鎖；(2) 項目的存取權限不允許——把它改成所有 app 可讀，做法見 \(doc)"   // display-safe-exempt: s、a 建構端已 displaySafeInvisible；doc 是常量
        case .invalidValue(let s, let a):
            return "keychain 項目 service「\(s)」、account「\(a)」的內容不是可用的金鑰（空的、不是 UTF-8，或含換行等控制字元）。請重新存入，做法見 \(doc)"   // display-safe-exempt: s、a 建構端已 displaySafeInvisible；doc 是常量
        case .keychain(let status):
            return "讀取 keychain 失敗（OSStatus \(status)）"   // display-safe-exempt: status 是 OSStatus（Int32）
        }
    }
}

/// `akashic s2 status` 用：只回報存在與可讀，**不回傳值**。
public struct S2KeyProbe: Sendable, Equatable, Codable {
    public let present: Bool
    public let readable: Bool
    public init(present: Bool, readable: Bool) { self.present = present; self.readable = readable }
}

public protocol S2KeyProviding: Sendable {
    func key() throws -> S2APIKey
}

/// 以 Security framework 在程序內讀取 generic password，**非互動**：查詢帶
/// `kSecUseAuthenticationContext`，值為 `interactionNotAllowed = true` 的 `LAContext`
/// （Apple 文件：`kSecUseAuthenticationUIFail` 自 macOS 11 棄用，改用這個寫法）。
public struct S2KeychainKeyProvider: S2KeyProviding {
    public let service: String
    public let account: String

    public init(service: String, account: String) {
        self.service = service
        self.account = account
    }

    public init(settings: S2Settings) {
        self.init(service: settings.keychainService, account: settings.keychainAccount)
    }

    public func key() throws -> S2APIKey {
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query(returningData: true) as CFDictionary, &result)
        if let error = Self.classify(status: status, service: service, account: account) { throw error }
        guard let data = result as? Data else {
            throw S2KeyError.invalidValue(service: displaySafeInvisible(service), account: displaySafeInvisible(account))
        }
        return try Self.decode(data, service: service, account: account)
    }

    public func probe() -> S2KeyProbe {
        var attributes: CFTypeRef?
        let status = SecItemCopyMatching(query(returningData: false) as CFDictionary, &attributes)
        switch Self.classify(status: status, service: service, account: account) {
        case .none, .notReadable?:
            // 屬性查得到（或存在但受權限保護）＝存在；可讀與否要實際試讀。
            let readable = (try? key()) != nil
            return S2KeyProbe(present: true, readable: readable)
        default:
            return S2KeyProbe(present: false, readable: false)
        }
    }

    private func query(returningData: Bool) -> [CFString: Any] {
        let context = LAContext()
        context.interactionNotAllowed = true
        var q: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecMatchLimit: kSecMatchLimitOne,
            kSecUseAuthenticationContext: context,
        ]
        if returningData { q[kSecReturnData] = true } else { q[kSecReturnAttributes] = true }
        return q
    }

    /// 成功回 nil。狀態碼依 Apple 定義：-25300 errSecItemNotFound、
    /// -25308 errSecInteractionNotAllowed、-25293 errSecAuthFailed。
    static func classify(status: Int32, service: String, account: String) -> S2KeyError? {
        switch status {
        case errSecSuccess: return nil
        case errSecItemNotFound:
            return .missing(service: displaySafeInvisible(service), account: displaySafeInvisible(account))
        case errSecInteractionNotAllowed, errSecAuthFailed:
            return .notReadable(service: displaySafeInvisible(service), account: displaySafeInvisible(account))
        default: return .keychain(status: status)
        }
    }

    /// 去掉前後的空白與換行；內部含控制字元（含換行）、空值、非 UTF-8 一律拒絕。
    static func decode(_ data: Data, service: String, account: String) throws -> S2APIKey {
        guard let text = String(data: data, encoding: .utf8) else {
            throw S2KeyError.invalidValue(service: displaySafeInvisible(service), account: displaySafeInvisible(account))
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              !trimmed.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
        else { throw S2KeyError.invalidValue(service: displaySafeInvisible(service), account: displaySafeInvisible(account)) }
        return S2APIKey(value: trimmed)
    }
}
