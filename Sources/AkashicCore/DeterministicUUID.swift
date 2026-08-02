import Foundation
import CryptoKit

/// 從既有字串身分推出**確定性** UUID（#35）。
///
/// ## 為什麼必須確定性
///
/// `entities/<uuid>.yaml` 需要每筆記錄都有 UUID，但 legacy 的 `people/<key>.yaml`
/// 沒有 `id` 欄位。若讀取時隨機生一個，**同一個檔每次載入都會得到不同的 id**——
/// index 的 primary key、entry 的作者引用、graph 的節點全部會漂。
///
/// 所以用 **UUIDv5**（RFC 4122 §4.3：namespace UUID + name 的 SHA-1）。同一個
/// person key 永遠推出同一個 UUID，且不同 key 幾乎不可能碰撞。
///
/// ## 為什麼不用 hash 的前 16 bytes 就好
///
/// 會產生一個**不是合法 UUID** 的 128-bit 值（version / variant 位元沒設）。那種值
/// 在別的工具眼裡是壞掉的 UUID，而 store 的檔名要能被任何人用一般工具檢查。
public enum DeterministicUUID {

    /// Akashic person 的 namespace。任意選定但**永久固定**——換掉它等於讓所有既有
    /// person 的身分改變，那會把 entry 的作者引用全部打斷。
    public static let personNamespace = UUID(uuidString: "6b2f1d3e-9c47-4a58-8b21-0f5e7c9a4d16")!

    /// UUIDv5（SHA-1 based，RFC 4122 §4.3）。
    public static func v5(namespace: UUID, name: String) -> UUID {
        var bytes = [UInt8]()
        withUnsafeBytes(of: namespace.uuid) { bytes.append(contentsOf: $0) }
        bytes.append(contentsOf: Array(name.utf8))

        var digest = Array(Insecure.SHA1.hash(data: Data(bytes)))
        // version 5：高 nibble of byte 6 設為 0101
        digest[6] = (digest[6] & 0x0F) | 0x50
        // variant RFC 4122：高兩 bit of byte 8 設為 10
        digest[8] = (digest[8] & 0x3F) | 0x80

        let u = (digest[0], digest[1], digest[2], digest[3], digest[4], digest[5],
                 digest[6], digest[7], digest[8], digest[9], digest[10], digest[11],
                 digest[12], digest[13], digest[14], digest[15])
        return UUID(uuid: u)
    }

    /// legacy person（`people/<key>.yaml`，無 `id` 欄位）的身分。
    public static func forPerson(key: String) -> UUID {
        v5(namespace: personNamespace, name: key)
    }
}
