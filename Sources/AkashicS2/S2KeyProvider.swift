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
        let doc = S2Settings.setupDocument, pluginDoc = S2Settings.setupDocumentInPlugin
        switch self {
        case .missing(let s, let a):
            // 多行：行長上限是每行 400 個 scalar，單行會把最後一個文件位置截掉。錯誤訊息本身帶可以照著做的指令（只裝 plugin 的使用者
            // 讀不到 repo 內的設定文件）；`-w` 後面不接金鑰。存金鑰是使用者自己的動作，金鑰不進對話。
            return """
            找不到 Semantic Scholar 的 API 金鑰：keychain 裡沒有 service「\(s)」、account「\(a)」的項目。
            請你自己在 Terminal 執行下面這行（-w 後面不要接金鑰，系統會提示你輸入；AI agent 不要代跑，金鑰也不要貼進對話）：
            security add-generic-password -s "\(s)" -a "\(a)" -A -w
            （-A＝所有 app 可讀：同一使用者的任何程序都讀得到這把金鑰，取捨見說明）
            說明見 \(doc)
            只裝 plugin 的話見 \(pluginDoc)
            """   // display-safe-exempt: s、a 建構端已 displaySafeInvisible；doc、pluginDoc 是常量
        case .notReadable(let s, let a):
            // -25308 既是「存取權限需要提示」也是「keychain 鎖著」，兩者回同一個狀態碼，所以兩個原因都講、先講便宜的那個。
            // 解鎖與重存都是使用者自己的動作：登入密碼比 S2 金鑰值錢得多，不進對話、不經 agent。
            return """
            keychain 裡有 service「\(s)」、account「\(a)」的項目，但現在無法在不跳出授權框的情況下讀取它。可能的原因，依序檢查：
            (1) keychain 鎖著（SSH 或背景工作階段最常見）：請你在自己的 Terminal 執行 security unlock-keychain（不要加 -p，密碼由系統提示輸入；登入密碼不要貼進對話，AI agent 不要代跑）。解鎖後仍讀不到的話，請在執行 akashic／akashic-mcp 的同一個工作階段再解鎖一次（解鎖是否跨工作階段尚未實機驗證，#725）
            (2) 項目的存取權限不允許：請你刪除該項目、照說明帶 -A 重存（改成所有 app 可讀；金鑰由你自己輸入，不要貼進對話；AI agent 不要代刪、代存）
            說明見 \(doc)
            只裝 plugin 的話見 \(pluginDoc)
            """   // display-safe-exempt: s、a 建構端已 displaySafeInvisible；doc、pluginDoc 是常量
        case .invalidValue(let s, let a):
            return """
            keychain 項目 service「\(s)」、account「\(a)」的內容不是可用的金鑰（空的、不是 UTF-8，或含換行等控制字元）。
            請你自己在 Terminal 重新存入（-w 後面不要接金鑰，系統會提示你輸入；金鑰不要貼進對話，AI agent 不要代跑、代存）：
            security add-generic-password -U -s "\(s)" -a "\(a)" -A -w
            做法見 \(doc)
            只裝 plugin 的話見 \(pluginDoc)
            """   // display-safe-exempt: s、a 建構端已 displaySafeInvisible；doc、pluginDoc 是常量
        case .keychain(let status):
            return """
            讀取 keychain 失敗（OSStatus \(status)）。這不是「沒有金鑰」：項目可能在，請你自己處理（解鎖、權限、重存都是你在自己 Terminal 的動作，AI agent 不要代跑）。
            說明見 \(doc)
            只裝 plugin 的話見 \(pluginDoc)
            """   // display-safe-exempt: status 是 OSStatus（Int32）；doc、pluginDoc 是常量
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

    /// `present` 只有一個意思：keychain **明確回答「找不到」**（`errSecItemNotFound`）才是 false。其他任何狀態——鎖著、
    /// 權限、其他 keychain 錯誤——都不是「沒有金鑰」：取得順序靠這個欄位分辨「先請使用者設定」與「停下回報」，
    /// 把不明的錯誤算成「沒有」，就會在金鑰存在時退到不受全機節流的頁面路徑（#664 verify R3）。
    static func itemMayExist(forAttributeStatus status: Int32) -> Bool { status != errSecItemNotFound }

    public func probe() -> S2KeyProbe {
        var attributes: CFTypeRef?
        let status = SecItemCopyMatching(query(returningData: false) as CFDictionary, &attributes)
        guard Self.itemMayExist(forAttributeStatus: status) else { return S2KeyProbe(present: false, readable: false) }
        // 屬性查得到（或存在但受權限保護、或 keychain 出了別的錯）：可讀與否要實際試讀。
        return S2KeyProbe(present: true, readable: (try? key()) != nil)
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
