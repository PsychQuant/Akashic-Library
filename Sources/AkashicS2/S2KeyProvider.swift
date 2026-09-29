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

public enum S2KeyError: Error, Equatable, CustomStringConvertible {
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
            return "找不到 Semantic Scholar 的 API 金鑰：keychain 裡沒有 service「\(s)」、account「\(a)」的項目。設定方法見 \(doc)"
        case .notReadable(let s, let a):
            return "keychain 裡有 service「\(s)」、account「\(a)」的項目，但它的存取權限不允許在不跳出授權框的情況下讀取。請把該項目改成所有 app 可讀，做法見 \(doc)"
        case .invalidValue(let s, let a):
            return "keychain 項目 service「\(s)」、account「\(a)」的內容不是可用的金鑰（空的、不是 UTF-8，或含換行等控制字元）。請重新存入，做法見 \(doc)"
        case .keychain(let status):
            return "讀取 keychain 失敗（OSStatus \(status)）"
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
        guard let data = result as? Data else { throw S2KeyError.invalidValue(service: service, account: account) }
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
        case errSecItemNotFound: return .missing(service: service, account: account)
        case errSecInteractionNotAllowed, errSecAuthFailed: return .notReadable(service: service, account: account)
        default: return .keychain(status: status)
        }
    }

    /// 去掉前後的空白與換行；內部含控制字元（含換行）、空值、非 UTF-8 一律拒絕。
    static func decode(_ data: Data, service: String, account: String) throws -> S2APIKey {
        guard let text = String(data: data, encoding: .utf8) else {
            throw S2KeyError.invalidValue(service: service, account: account)
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              !trimmed.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
        else { throw S2KeyError.invalidValue(service: service, account: account) }
        return S2APIKey(value: trimmed)
    }
}
